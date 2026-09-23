#!/usr/bin/env bash
# Render assertions for the model-serving chart, run by
# .github/workflows/helm-charts.yml.
#
# CHART_PATH is exported by the workflow. The default lets the script also be
# run by hand from the repository root.
set -euo pipefail

CHART_PATH="${CHART_PATH:-helm-charts/model-serving}"
# Pinned so the render does not depend on the helm build's default capabilities.
# Helm 3 and Helm 4 assume different Kubernetes versions when no cluster is
# reachable, which changes both kubeVersion constraints and any
# .Capabilities.APIVersions check a subchart makes.
KUBE_VERSION="${KUBE_VERSION:-1.31.0}"
out="$(mktemp -d)"

# The KServe controllers belong in the kserve namespace because KServe v0.20.0
# contains namespace-sensitive webhook and cert-manager references.
helm template model-serving "$CHART_PATH" --namespace kserve \
  --kube-version "$KUBE_VERSION" >"$out/render.yaml"

for runtime in kserve-openvino kserve-vllm-cpu; do
  if ! grep -q "name: ${runtime}" "$out/render.yaml"; then
    echo "The render is missing the ${runtime} ClusterServingRuntime." >&2
    exit 1
  fi
done

rm -rf "$out"
echo "model-serving render checks passed."
