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
out="$(mktemp -d)"

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

echo "── Config flow ───────────────────────────────────────────────────────────"
helm template litellm "$CHART_PATH" --namespace litellm \
  --kube-version "$KUBE_VERSION" >"$out/config.yaml"

assert_present "model_list" "$out/config.yaml" \
  "The config flow must render the model catalog into config.yaml."
# The checksum is what makes a `helm upgrade` roll the pods onto a new catalog.
assert_present "checksum/config" "$out/config.yaml" \
  "The pod template must carry a checksum of the config ConfigMap."
assert_absent "store_model_in_db" "$out/config.yaml" \
  "The config flow must not set store_model_in_db."
# No database means no migration Job.
assert_absent "^kind: Job$" "$out/config.yaml" \
  "The config flow must not render a migration Job."

echo "── Database flow, every routing implementation ───────────────────────────"
helm template litellm "$CHART_PATH" --namespace litellm \
  --kube-version "$KUBE_VERSION" \
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
  --set routing.route.enabled=true \
  >"$out/database.yaml"

assert_present "store_model_in_db: true" "$out/database.yaml" \
  "The database flow must set store_model_in_db."
assert_present "^kind: Job$" "$out/database.yaml" \
  "The database flow must render a migration Job."
for kind in Ingress HTTPRoute HTTPProxy Route; do
  assert_present "^kind: ${kind}$" "$out/database.yaml" \
    "The database flow render is missing a ${kind}."
done

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

rm -rf "$out"
echo "litellm render checks passed."
