#!/usr/bin/env bash
# Render assertions for the litellm chart, run by .github/workflows/helm-charts.yml.
# helm-unittest covers individual templates; this covers whole-release renders,
# where the question is which objects exist together.
#
# CHART_PATH and CHART_NAME are exported by the workflow. The defaults let the
# script also be run by hand from the repository root.
set -euo pipefail

CHART_PATH="${CHART_PATH:-helm-charts/litellm}"
# Pinned so the render does not depend on the helm build's default capabilities.
# Helm 3 and Helm 4 assume different Kubernetes versions when no cluster is
# reachable, which changes whether the chart's kubeVersion constraint is met.
KUBE_VERSION="${KUBE_VERSION:-1.31.0}"

# `mktemp -d` returns an empty string rather than failing on some Windows bash
# builds, which would silently redirect every render to "/<name>" and leave the
# assertions grepping files that were never written. Checked explicitly,
# because `set -u` does not catch an empty result from a command substitution.
out="$(mktemp -d 2>/dev/null || true)"
if [ -z "$out" ] || [ ! -d "$out" ]; then
  out="./.ci-render-$$"
  mkdir -p "$out"
fi
if ! : >"$out/.writable" 2>/dev/null; then
  echo "Cannot write to the scratch directory '$out'." >&2
  exit 1
fi
rm -f "$out/.writable"
trap 'rm -rf "$out"' EXIT

# Written as explicit if-blocks rather than `grep ... && exit 1`, whose
# behaviour under `set -e` depends on where the failing command sits in the
# AND-list. An assertion that silently never fails is worse than no assertion.
assert_present() { # <pattern> <file> <message>
  if ! grep -q "$1" "$2"; then
    echo "$3" >&2
    exit 1
  fi
}
assert_absent() { # <pattern> <file> <message>
  if grep -q "$1" "$2"; then
    echo "$3" >&2
    exit 1
  fi
}

# Renders into "$out/<name>.yaml" with carriage returns stripped.
#
# On a checkout with core.autocrlf=true the chart templates are CRLF, and Helm
# preserves that in its output. Every `$`-anchored assertion below would then
# fail to match on Windows while passing in CI, which is worse than either
# outcome on its own. Normalising here makes a local run and a CI run identical.
render() { # <output name> <helm args...>
  local name="$1"
  shift
  helm template litellm "$CHART_PATH" --namespace litellm \
    --kube-version "$KUBE_VERSION" "$@" | tr -d '\r' >"$out/${name}.yaml"
}

echo "── Config flow ───────────────────────────────────────────────────────────"
render config

assert_present "model_list" "$out/config.yaml" \
  "The config flow must render the model catalog into config.yaml."
# The checksum is what makes a `helm upgrade` roll the pods onto a new catalog.
assert_present "checksum/config" "$out/config.yaml" \
  "The pod template must carry a checksum of the config ConfigMap."
# The chart ships mounted under a prefix rather than claiming the whole host.
# A stock install that silently took the root back would break every
# neighbouring application on the hostname.
assert_present 'value: "/litellm"' "$out/config.yaml" \
  "A default install must set SERVER_ROOT_PATH to /litellm."
# Without this the pod treats the ingress's plaintext hop as the client's own
# scheme and redirects browsers to http://, downgrading a release the chart
# published over HTTPS.
assert_present "FORWARDED_ALLOW_IPS" "$out/config.yaml" \
  "A default install must trust the ingress's X-Forwarded-* headers."
assert_absent "store_model_in_db" "$out/config.yaml" \
  "The config flow must not set store_model_in_db."
# No database means no migration Job.
assert_absent "^kind: Job$" "$out/config.yaml" \
  "The config flow must not render a migration Job."

echo "── Database flow, every routing implementation ───────────────────────────"
render database \
  --set modelManagement.mode=database \
  --set database.host=pg.example.com \
  --set database.existingSecret.name=litellm-db \
  --set 'routing.hosts={litellm.example.com}' \
  --set routing.tls.enabled=true \
  --set routing.tls.secretName=litellm-tls \
  --set routing.ingress.enabled=true \
  --set routing.ingress.className=nginx \
  --set routing.httpRoute.enabled=true \
  --set 'routing.httpRoute.parentRefs[0].name=eg' \
  --set routing.httpProxy.enabled=true \
  --set routing.httpProxy.ingressClassName=contour \
  --set routing.route.enabled=true

assert_present "store_model_in_db: true" "$out/database.yaml" \
  "The database flow must set store_model_in_db."
assert_present "^kind: Job$" "$out/database.yaml" \
  "The database flow must render a migration Job."
for kind in Ingress HTTPRoute HTTPProxy Route; do
  assert_present "^kind: ${kind}$" "$out/database.yaml" \
    "The database flow render is missing a ${kind}."
done

echo "── Database initialization ───────────────────────────────────────────────"
render db-init \
  --set modelManagement.mode=database \
  --set database.host=pg.example.com \
  --set database.existingSecret.name=litellm-db \
  --set database.init.enabled=true \
  --set database.init.admin.username=postgres \
  --set database.init.admin.password=adminpw

assert_present "^kind: Job$" "$out/db-init.yaml" \
  "The initialization flow must render a Job."
# The psql step has to be an init container: Kubernetes only starts ordinary
# containers once init containers have exited 0, which is what stops the
# cleanup step erasing the credentials after a failed initialization.
assert_present "initContainers:" "$out/db-init.yaml" \
  "The psql step must run as an init container, ahead of the cleanup container."
assert_present '"data":{"username":null,"password":null}' "$out/db-init.yaml" \
  "The cleanup step must erase the admin credentials with a merge patch."
# The cleanup container runs the upstream distroless kubectl image, which has
# no shell. A command starting /bin/sh would never run.
assert_absent '/bin/sh", "/scripts/cleanup.sh' "$out/db-init.yaml" \
  "The cleanup container must invoke kubectl directly; its image has no shell."
# Scoped to the one Secret the chart created, and with no `delete` verb, so
# this chart never creates a Role that could delete Secrets in the namespace.
assert_present 'verbs: \["get", "patch"\]' "$out/db-init.yaml" \
  "The initialization Role must grant only get and patch."
assert_absent 'verbs:.*delete' "$out/db-init.yaml" \
  "The initialization Role must not grant delete on Secrets."

echo "── Initialization is off by default ──────────────────────────────────────"
assert_absent "db-init" "$out/database.yaml" \
  "The database flow must not render initialization objects unless asked."

echo "── SSO with the Keycloak bootstrap ───────────────────────────────────────"
render sso \
  --set serverRootPath=/litellm \
  --set routing.path=/litellm \
  --set 'routing.hosts={llm.example.com}' \
  --set routing.tls.enabled=true \
  --set routing.tls.secretName=tls \
  --set routing.ingress.enabled=true \
  --set routing.ingress.className=nginx \
  --set sso.enabled=true \
  --set sso.authorizationEndpoint=https://kc.example.com/a \
  --set sso.tokenEndpoint=http://kc.internal:8080/t \
  --set sso.userinfoEndpoint=http://kc.internal:8080/u \
  --set sso.keycloakBootstrap.enabled=true \
  --set sso.keycloakBootstrap.url=http://kc.internal:8080 \
  --set sso.keycloakBootstrap.realm=myrealm \
  --set sso.keycloakBootstrap.admin.existingSecret.name=kc-admin

assert_present "SERVER_ROOT_PATH" "$out/sso.yaml" \
  "The prefix must reach the proxy as SERVER_ROOT_PATH."
# The redirect URI has to carry the same prefix the Ingress publishes, or the
# provider rejects the sign-in.
assert_present "https://llm.example.com/litellm/sso/callback" "$out/sso.yaml" \
  "The registered redirect URI must include the server root path."
# Keycloak nests client roles under resource_access by default, which LiteLLM
# does not read; without this mapper every user signs in with no role.
assert_present '"claim.name": "roles"' "$out/sso.yaml" \
  "The role mapper must emit the flat claim LiteLLM reads."
# The Keycloak image is minimal: no python3, jq, awk or curl.
assert_absent "^ *python3 " "$out/sso.yaml" \
  "The bootstrap script must not call python3; the Keycloak image has none."
assert_absent "| *awk" "$out/sso.yaml" \
  "The bootstrap script must not call awk; the Keycloak image has none."

echo "── Probes stay on the root even under a prefix ───────────────────────────"
# Verified against the image: health endpoints answer at both the prefix and
# the root, so prefixing the probes would be wrong.
assert_present 'path: "/health/readiness"' "$out/sso.yaml" \
  "Readiness must stay on the root path."

echo "── SSO is off by default ─────────────────────────────────────────────────"
assert_absent "GENERIC_CLIENT_ID" "$out/database.yaml" \
  "The database flow must not enable SSO unless asked."

echo "── The proxy and the migration Job share one image tag ───────────────────"
app_version="$(helm show chart "$CHART_PATH" | awk '/^appVersion:/ { gsub(/"/, "", $2); print $2 }')"
tags="$(grep -E '^\s+image: ' "$out/database.yaml" | awk '{ print $2 }' | tr -d '"' | sort -u)"
if [[ "$(printf '%s\n' "$tags" | wc -l)" -ne 1 ]]; then
  echo "The proxy and the migration Job resolved different images:" >&2
  printf '%s\n' "$tags" >&2
  exit 1
fi
if [[ "$tags" != *":${app_version}" ]]; then
  echo "The default image tag is '$tags' but appVersion is '$app_version'. image.tag must fall back to appVersion." >&2
  exit 1
fi
echo "Both containers run $tags."

echo "── Every value the schema declares is mentioned in the README ────────────"
# This chart documents its values in a curated table grouped by topic, rather
# than with the flat alphabetical table helm-docs generates from '# --'
# comments. That is a deliberate choice and the better document: it explains
# which values matter and how they interact, which a generated table cannot.
#
# The cost of choosing it is that nothing regenerates the table, so a value
# added or renamed in values.yaml leaves the README quietly wrong. This closes
# that gap without giving up the curation -- it asserts coverage rather than
# byte-equality, so the prose stays hand-written and only genuinely
# undocumented values fail the build.
#
# Measured at 225/243 leaves when this was added; the 18 exceptions below are
# listed individually so that adding to them is a visible decision.
python3 - "$CHART_PATH" <<'PY'
import json
import re
import sys

chart = sys.argv[1]

# Values that are deliberately undocumented: Helm boilerplate every chart has,
# and probe/annotation passthroughs whose meaning is upstream Kubernetes rather
# than anything this chart decides.
ALLOWED = {
    "nameOverride", "fullnameOverride",
    "serviceAccount.automount", "serviceAccount.name",
    "deploymentMinReadySeconds",
    "masterKey.existingSecret",
    "sso.usePkce", "sso.userinfoEndpoint",
    "livenessProbe", "readinessProbe", "startupProbe",
    "redis.port", "redis.existingSecret.passwordKey",
    "migrationJob.annotations", "migrationJob.podAnnotations",
    "migrationJob.extraInitContainers",
}

with open(f"{chart}/README.md", encoding="utf-8") as handle:
    readme = handle.read()
with open(f"{chart}/values.schema.json", encoding="utf-8") as handle:
    schema = json.load(handle)

# Any dotted path the README mentions inside a code span counts as documented.
#
# The README also abbreviates sibling keys with a leading dot, sharing the
# previous path's prefix:
#
#     `autoscaling.targetRequestsPerSecond`, `.targetTokensPerSecond`
#
# Those have to be resolved, or the check reports values that are documented
# perfectly well. A check that cries wolf gets switched off, which would leave
# the chart worse documented than having no check at all.
SPAN = re.compile(r"`(\.?[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_\[\]*]+)*|\.[a-zA-Z][a-zA-Z0-9_]*)`")

mentioned = set()
for line in readme.splitlines():
    last_prefix = None
    for span in SPAN.findall(line):
        if span.startswith("."):
            if last_prefix:
                mentioned.add(f"{last_prefix}.{span.lstrip('.')}")
            continue
        mentioned.add(span)
        # Only a dotted path can act as a prefix for the shorthand; a bare word
        # like `true` in the same cell must not become one.
        if "." in span:
            last_prefix = span.rsplit(".", 1)[0]

leaves = []

def walk(node, prefix):
    if not isinstance(node, dict):
        return
    props = node.get("properties")
    if isinstance(props, dict) and props:
        for name, child in props.items():
            walk(child, f"{prefix}.{name}" if prefix else name)
    elif prefix:
        leaves.append(prefix)

walk(schema, "")

def covered(path):
    # An ancestor is enough: documenting `models` covers `models[0].model_name`.
    parts = path.split(".")
    return any(".".join(parts[:i]) in mentioned for i in range(len(parts), 0, -1))

missing = sorted(p for p in leaves if not covered(p) and p not in ALLOWED)

if missing:
    print("These values are declared in values.schema.json but appear nowhere", file=sys.stderr)
    print("in README.md, so nobody installing this chart can find out what they", file=sys.stderr)
    print("do. Document them, or add them to ALLOWED in this script with a", file=sys.stderr)
    print("reason:", file=sys.stderr)
    for path in missing:
        print(f"  {path}", file=sys.stderr)
    raise SystemExit(1)

print(f"All {len(leaves) - len(ALLOWED)} documented values are covered "
      f"({len(ALLOWED)} deliberate exceptions).")
PY

echo "litellm render checks passed."
