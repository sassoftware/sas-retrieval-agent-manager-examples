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

# The vLLM runtime shipped with neither probes nor a securityContext until
# 0.4.0, so a default render that lost them again would be a silent regression.
#
# USER and LOGNAME are checked with the rest of the hardening because they are
# part of it: the image has no passwd entry for the uid the securityContext
# forces, so without one of them "import vllm" dies with
# "KeyError: 'getpwuid(): uid not found: 1000'" before the server starts.
for hardening in 'path: /health' 'runAsNonRoot: true' 'VLLM_CACHE_ROOT' \
  'name: USER' 'name: LOGNAME'; do
  if ! grep -q "${hardening}" "$out/render.yaml"; then
    echo "The default render is missing the vLLM CPU hardening (${hardening})." >&2
    exit 1
  fi
done

# A non-root uid with no getpass variable has to fail the render rather than
# ship a pod that crash-loops on an import error.
if helm template model-serving "$CHART_PATH" --namespace kserve \
  --kube-version "$KUBE_VERSION" \
  --set clusterServingRuntimes.vllmCPU.cacheVolume.enabled=false >/dev/null 2>&1; then
  echo "A non-root vLLM runtime rendered without a USER/LOGNAME variable." >&2
  exit 1
fi

# The local model cache is opt-in, so the default render must not contain the
# chart's own cache template at all. Matching on the Source comment rather than
# on the kind is deliberate: LocalModelNodeGroup and LocalModelCache also
# appear in the CRD definitions that the dependency charts always install.
if grep -q '# Source: model-serving/templates/localmodelcache.yaml' "$out/render.yaml"; then
  echo "The default render unexpectedly contains local model cache resources." >&2
  exit 1
fi

# Every 0.4.0 feature switched on at once, which is also the combination the
# strict values schema is most likely to reject.
helm template model-serving "$CHART_PATH" --namespace kserve \
  --kube-version "$KUBE_VERSION" \
  --values "$CHART_PATH/tests/fixtures/placement-cache-values.yaml" >"$out/features.yaml"

for expected in \
  '# Source: model-serving/templates/localmodelcache.yaml' \
  'sourceModelUri: hf://OpenVINO/gemma-4-E2B-it-fp16-ov' \
  'storageLimit: 200Gi' \
  'minReplicas: 2' \
  'node.kubernetes.io/instance-type: m6i.8xlarge'; do
  if ! grep -q "${expected}" "$out/features.yaml"; then
    echo "The feature render is missing ${expected}." >&2
    exit 1
  fi
done

# Naming a profile that does not exist must fail the render rather than
# quietly scheduling a large model wherever there happens to be room.
if helm template model-serving "$CHART_PATH" --namespace kserve \
  --kube-version "$KUBE_VERSION" \
  --set 'models[0].name=typo' \
  --set 'models[0].storageUri=hf://org/model' \
  --set 'models[0].placementProfile=does-not-exist' >/dev/null 2>&1; then
  echo "An unknown placementProfile rendered instead of failing." >&2
  exit 1
fi

# Overriding the hardening has to stay possible, including removing it.
helm template model-serving "$CHART_PATH" --namespace kserve \
  --kube-version "$KUBE_VERSION" \
  --set clusterServingRuntimes.openVINO.enabled=false \
  --set clusterServingRuntimes.vllmCPU.securityContext=null \
  --set clusterServingRuntimes.vllmCPU.cacheVolume.enabled=false \
  --set clusterServingRuntimes.vllmCPU.probes.liveness=null \
  --show-only templates/clusterservingruntimes.yaml >"$out/relaxed.yaml"

for unexpected in runAsNonRoot livenessProbe VLLM_CACHE_ROOT 'name: LOGNAME'; do
  if grep -q "${unexpected}" "$out/relaxed.yaml"; then
    echo "The relaxed render still contains ${unexpected}." >&2
    exit 1
  fi
done

rm -rf "$out"
echo "model-serving render checks passed."
