#!/usr/bin/env bash
# Render assertions for the semantic-router chart, run by
# .github/workflows/helm-charts.yml. helm-unittest covers individual templates;
# this covers whole-release renders, where the question is which objects exist
# together — and the renders that must FAIL, which helm-unittest cannot express
# for a values.schema.json violation.
#
# CHART_PATH and CHART_NAME are exported by the workflow. The defaults let the
# script also be run by hand from the repository root.
set -euo pipefail

CHART_PATH="${CHART_PATH:-helm-charts/semantic-router}"
# Pinned so the render does not depend on the helm build's default
# capabilities. Helm 3 and Helm 4 assume different Kubernetes versions when no
# cluster is reachable, which changes whether the chart's kubeVersion
# constraint is met.
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
# outcome on its own. Normalising here makes a local run and a CI run
# identical.
render() { # <output name> <helm args...>
  local name="$1"
  shift
  helm template sr "$CHART_PATH" --namespace sr \
    --kube-version "$KUBE_VERSION" "$@" | tr -d '\r' >"$out/${name}.yaml"
}

# A render that MUST fail, with a message naming the value. These are the
# mistakes that would otherwise produce a working release with a security
# boundary quietly removed.
assert_render_fails() { # <description> <expected message fragment> <helm args...>
  local description="$1" expected="$2"
  shift 2
  local output
  if output="$(helm template sr "$CHART_PATH" --namespace sr \
      --kube-version "$KUBE_VERSION" "$@" 2>&1)"; then
    echo "Expected the render to fail: ${description}" >&2
    exit 1
  fi
  if ! printf '%s' "$output" | grep -q "$expected"; then
    echo "The render failed for the wrong reason: ${description}" >&2
    echo "Expected a message containing: ${expected}" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

echo "── Defaults ──────────────────────────────────────────────────────────────"
render defaults

# THE assertion. The router forwards the caller's Authorization header to
# LiteLLM only while it has no credential of its own to substitute; a key on
# the backend ref would replace every caller's key with one shared credential
# and collapse LiteLLM's per-key budgets, permissions and spend attribution
# into a single principal.
assert_absent "access_key" "$out/defaults.yaml" \
  "The rendered router config must never carry a backend access_key."
assert_absent "api_key" "$out/defaults.yaml" \
  "The rendered router config must never carry a backend api_key or api_key_env."
assert_absent "auth_header" "$out/defaults.yaml" \
  "The rendered router config must not override the Authorization header."
# Adding an authz provider flips the credential resolver's fail_open default.
assert_absent "authz" "$out/defaults.yaml" \
  "The rendered router config must not configure global.services.authz."

# LiteLLM serves its OpenAI surface under <serverRootPath>/v1, and a backend
# ref's base_url REPLACES the protocol's canonical base path rather than
# prefixing it. Without the /v1 the router would call
# /litellm/chat/completions and get a 404.
assert_present "base_url: http://litellm.sr.svc.cluster.local:4000/litellm/v1$" "$out/defaults.yaml" \
  "The backend base URL must be LiteLLM's OpenAI base path, ending in /litellm/v1."
assert_absent "chat_path" "$out/defaults.yaml" \
  "chat_path replaces the whole path and must stay unset."

# The v0.3 config has no default_model: the fallback is the lowest-priority
# decision with no conditions.
assert_present "version: v0.3" "$out/defaults.yaml" \
  "The router config must declare version v0.3."
assert_absent "default_model" "$out/defaults.yaml" \
  "The v0.3 config has no default_model field."
assert_present "name: fallback" "$out/defaults.yaml" \
  "The seed config must carry a lowest-priority fallback decision."

# One router replica, because Router Learning keeps request-time state in the
# pod and upstream's safety guard refuses to render more.
assert_present "^  replicas: 1$" "$out/defaults.yaml" \
  "Both workloads must default to a single replica."

# Fail-closed ext_proc plus an explicit catch-all deny: this router decides
# which LiteLLM key boundary a request crosses.
assert_present "failure_mode_allow: false" "$out/defaults.yaml" \
  "ext_proc must fail closed by default."
assert_present "request_body_mode: BUFFERED" "$out/defaults.yaml" \
  "The request body must be buffered; the prompt is what gets classified."
assert_present "response_body_mode: STREAMED" "$out/defaults.yaml" \
  "The response body must stream, or every answer arrives in one block."
assert_present "status: 403" "$out/defaults.yaml" \
  "The route table must end in an explicit deny."
assert_present "prefix_rewrite: \"/litellm/v1/chat/completions\"" "$out/defaults.yaml" \
  "Envoy must rewrite the client's /v1 path onto LiteLLM's mount prefix."

# Envoy holds no state and needs no filesystem, no token, and no root.
assert_present "readOnlyRootFilesystem: true" "$out/defaults.yaml" \
  "Envoy must run with a read-only root filesystem."
assert_present "runAsNonRoot: true" "$out/defaults.yaml" \
  "Envoy must run as a non-root user."
assert_present "automountServiceAccountToken: false" "$out/defaults.yaml" \
  "Envoy talks to no Kubernetes API and must not mount a token."
# The admin interface serves /quitquitquit and a full config dump.
assert_present "address: 127.0.0.1" "$out/defaults.yaml" \
  "Envoy's admin interface must stay bound to loopback."

# Two ports, two audiences: :50051 is the data path, :8080 can rewrite routing
# policy.
assert_present "^kind: NetworkPolicy$" "$out/defaults.yaml" \
  "A default install must render the NetworkPolicy around the router's ports."
# :8080 has TWO clients, and they are not equivalent: the model controller
# writes the config, and the RAM extension API only reads, validates and
# previews it. Both must be admitted, as separate rules.
assert_present "The only WRITER of router config" "$out/defaults.yaml" \
  "The policy must admit the model controller to the management API."
assert_present "app.kubernetes.io/component: model-controller" "$out/defaults.yaml" \
  "The policy must select the model controller's pods."
assert_present "READ-ONLY: config, validate, status and routing preview" "$out/defaults.yaml" \
  "The policy must admit the RAM extension API, which drives the policy editor."
assert_present "app.kubernetes.io/name: ram-extension" "$out/defaults.yaml" \
  "The policy must select the RAM extension API's pods, which carry no component label."
# Two rules for the management port, and neither of them an open selector.
# Anchored on the NetworkPolicy's own indentation: "port: 8080" also appears in
# the router config's listeners and in the Envoy bootstrap.
if [ "$(grep -c "^        - port: 8080$" "$out/defaults.yaml")" -ne 2 ]; then
  echo "The management API must be reachable by exactly two clients by default." >&2
  exit 1
fi
assert_present "mode: bearer" "$out/defaults.yaml" \
  "The management API must require a bearer token by default."
assert_present "^kind: Secret$" "$out/defaults.yaml" \
  "The chart must generate the management API token Secret."

# Nothing is published outside the cluster until asked.
for kind in Ingress HTTPRoute HTTPProxy Route ServiceMonitor PodDisruptionBudget; do
  assert_absent "^kind: ${kind}$" "$out/defaults.yaml" \
    "A default install must not render a ${kind}."
done

# Every optional upstream platform stays off: bitnami/redis (withdrawn
# versioned tags), milvus, and a Jaeger whose image tag upstream pins to
# "latest".
assert_absent "image: jaegertracing" "$out/defaults.yaml" \
  "The bundled Jaeger must stay disabled; upstream pins its tag to latest."
assert_absent "^kind: StatefulSet$" "$out/defaults.yaml" \
  "No bundled Redis or Milvus may be deployed by default."

echo "── Guards ────────────────────────────────────────────────────────────────"
# Upstream ships no model_catalog, so a guard module enabled on its own loads
# no classifier and scores nothing: it allows everything, silently.
render guards \
  --set global.semanticRouter.guards.jailbreak.enabled=true \
  --set global.semanticRouter.guards.pii.enabled=true

assert_present "prompt_guard: models/Vela-1.0-Encoder-307M-Guard" "$out/guards.yaml" \
  "The jailbreak guard must name its checkpoint in model_catalog.system."
assert_present "pii_classifier: models/Vela-1.0-Encoder-307M-PII" "$out/guards.yaml" \
  "The PII guard must name its checkpoint in model_catalog.system."
assert_present "jailbreak_mapping_path:" "$out/guards.yaml" \
  "The jailbreak module needs its label mapping path."
assert_present "pii_mapping_path:" "$out/guards.yaml" \
  "The PII module needs its label mapping path."
# Scoring is not rejecting: a decision with a fast_response plugin is what
# returns the refusal without calling a model.
assert_present "name: block_jailbreak" "$out/guards.yaml" \
  "A guard that scores but never blocks is not a guard."
assert_present "name: block_pii" "$out/guards.yaml" \
  "A guard that scores but never blocks is not a guard."
assert_present "type: fast_response" "$out/guards.yaml" \
  "The blocking decisions must answer without reaching a backend."
assert_present "on_error: block" "$out/guards.yaml" \
  "A classifier failure must not pass unverified content through by default."
# Still no credential, with guards on.
assert_absent "access_key" "$out/guards.yaml" \
  "Enabling guards must not introduce a backend credential."

echo "── Semantic cache ────────────────────────────────────────────────────────"
render cache \
  --set global.semanticRouter.semanticCache.enabled=true \
  --set global.semanticRouter.semanticCache.backend=redis \
  --set global.semanticRouter.semanticCache.redis.address=litellm-valkey:6379

assert_present "backend_type: redis" "$out/cache.yaml" \
  "The semantic cache must use the backend it was given."
assert_present "host: litellm-valkey" "$out/cache.yaml" \
  "The semantic cache must point at the Redis it was given."
# The bundled bitnami Redis stays off; the Valkey the litellm chart deploys is
# the one to reuse.
assert_absent "^kind: StatefulSet$" "$out/cache.yaml" \
  "Enabling the cache must not deploy a bundled Redis."

echo "── The cache is off by default ───────────────────────────────────────────"
assert_absent "similarity_threshold" "$out/defaults.yaml" \
  "A default install must not enable the semantic cache."

echo "── Every publishing implementation ───────────────────────────────────────"
render publish \
  --set 'routing.hosts={router.example.com}' \
  --set routing.tls.enabled=true \
  --set routing.tls.secretName=router-tls \
  --set routing.ingress.enabled=true \
  --set routing.ingress.className=nginx \
  --set routing.httpRoute.enabled=true \
  --set 'routing.httpRoute.parentRefs[0].name=eg' \
  --set routing.httpProxy.enabled=true \
  --set routing.httpProxy.ingressClassName=contour \
  --set routing.route.enabled=true \
  --set serviceMonitor.enabled=true \
  --set pdb.enabled=true \
  --set pdb.minAvailable=1

for kind in Ingress HTTPRoute HTTPProxy Route ServiceMonitor PodDisruptionBudget; do
  assert_present "^kind: ${kind}$" "$out/publish.yaml" \
    "The publishing render is missing a ${kind}."
done
# Every routing object points at the Envoy Service, never at the router's own
# ports: :50051 is a gRPC data path and :8080 can rewrite routing policy.
assert_present "name: sr-semantic-router-envoy$" "$out/publish.yaml" \
  "Routing objects must point at the Envoy Service."
# Two ServiceMonitors: Envoy's own stats, and the router's classification and
# guard counters, which upstream ships no ServiceMonitor for.
assert_present "path: /stats/prometheus" "$out/publish.yaml" \
  "Envoy's metrics must be scraped from the stats listener."
assert_present "service: metrics" "$out/publish.yaml" \
  "The router's own metrics Service must be scraped too."

echo "── Fail-open, for a deployment where routing is only an optimisation ─────"
render fail-open --set envoy.extProc.failureModeAllow=true
assert_present "failure_mode_allow: true" "$out/fail-open.yaml" \
  "envoy.extProc.failureModeAllow must be able to turn the fail-closed default off."

echo "── Against a router this release does not deploy ─────────────────────────"
render external \
  --set semantic-router.enabled=false \
  --set global.semanticRouter.routerService.name=shared-router \
  --set global.semanticRouter.routerService.namespace=platform

assert_present "address: shared-router.platform.svc.cluster.local" "$out/external.yaml" \
  "The ext_proc cluster must follow global.semanticRouter.routerService."
assert_absent "kind: PersistentVolumeClaim" "$out/external.yaml" \
  "Disabling the subchart must render none of its objects."

echo "── Renders that must fail ────────────────────────────────────────────────"
# Each of these produces a release that WORKS and is wrong, which is the only
# kind of mistake worth failing a render over.

assert_render_fails "a static key on the LiteLLM backend" \
  "overwrites every caller's key" \
  --set 'semantic-router.configOverride.providers.models[0].backend_refs[0].access_key=shared'

assert_render_fails "an authz provider, which flips the resolver's defaults" \
  "global.services.authz" \
  --set 'semantic-router.configOverride.global.services.authz.providers[0].type=header-injection'

assert_render_fails "a base URL that is not an OpenAI base path" \
  "does not match pattern" \
  --set global.semanticRouter.litellm.baseUrl=http://litellm:4000/litellm

assert_render_fails "chat_path, which would undo the base URL" \
  "REPLACES the whole request path" \
  --set 'semantic-router.configOverride.providers.models[0].backend_refs[0].chat_path=/chat/completions'

assert_render_fails "a guard with no checkpoint, which scores nothing" \
  "minLength" \
  --set global.semanticRouter.guards.pii.enabled=true \
  --set global.semanticRouter.guards.pii.modelPath=

assert_render_fails "an empty allow-list, which would publish only the deny" \
  "minItems" \
  --set-json 'envoy.routes.allowedPaths=[]'

assert_render_fails "a token Secret the subchart was never told to mount" \
  "semantic-router.envFromSecrets" \
  --set global.semanticRouter.managementApi.token.existingSecret.name=other

assert_render_fails "a management API client that admits the whole namespace" \
  "admits EVERY pod in this namespace" \
  --set networkPolicy.modelController.podSelector=null

assert_render_fails "a policy with no management API client left" \
  "nothing can write or read routing policy" \
  --set networkPolicy.modelController.enabled=false \
  --set networkPolicy.extensionApi.enabled=false

assert_render_fails "a guard whose classifier is re-downloaded on every restart" \
  "persistence.enabled is false" \
  --set global.semanticRouter.guards.jailbreak.enabled=true \
  --set semantic-router.persistence.enabled=false

echo "semantic-router render checks passed."
