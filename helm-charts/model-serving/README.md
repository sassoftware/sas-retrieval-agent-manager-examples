# Model Serving Helm Chart

This chart installs KServe and values-driven model workloads as one Helm release. It uses the seven official KServe `v0.20.0` OCI charts as locked dependencies instead of copying upstream manifests into this repository.

## Prerequisites

- Kubernetes 1.30 or later
- Helm 3.19 or later
- cert-manager installed in the cluster
- Gateway API and any optional autoscaling or leader-worker CRDs required by the KServe features you enable

## Install

Build the locked dependencies before installing from a source checkout:

```sh
helm dependency build helm-charts/model-serving
helm upgrade --install model-serving helm-charts/model-serving \
  --namespace kserve \
  --create-namespace
```

### The first install on a cluster that has no KServe CRDs

The command above works on a cluster that already has the KServe CRDs, and on
every upgrade. It does **not** work on a cluster that has none, and the failure
is a wall of lines like:

```text
ensure CRDs are installed first, resource mapping not found for name:
"kserve-vllm-cpu" ... no matches for kind "ClusterServingRuntime" in version
"serving.kserve.io/v1alpha1"
```

This is a Helm limitation rather than a chart bug, and it is worth
understanding before working around it. Helm installs the contents of a
`crds/` directory first and waits for each definition to be established.
Upstream KServe does not ship its definitions that way -- `kserve-crd` renders
them from `templates/` -- so they are ordinary templated resources. Helm sorts
them ahead of the custom resources that need them, but it does not wait for the
API server to establish them, and `ClusterServingRuntime` is rejected while its
definition is still being accepted.

Create the workload namespace first. The chart renders the Hugging Face secret
and service account into `namespace` (`models` by default) but does not create
it, and `--create-namespace` applies to the release namespace only, so without
this the install stops on `namespaces "models" not found`:

```sh
kubectl create namespace models
```

Then install in two phases. The component switches already exist for this, so
no values file is needed:

```sh
# 1. Definitions only, waiting for them to be established.
helm install model-serving helm-charts/model-serving \
  --namespace kserve --create-namespace --wait \
  --set components.kserve.enabled=false \
  --set components.llmisvc.enabled=false \
  --set components.localModel.enabled=false \
  --set components.runtimeConfigs.enabled=false \
  --set clusterServingRuntimes.openVINO.enabled=false \
  --set clusterServingRuntimes.vllmCPU.enabled=false \
  --set serviceAccount.enabled=false

# 2. Everything, against definitions that now exist.
#    --reset-values is NOT optional here: see below.
helm upgrade model-serving helm-charts/model-serving \
  --namespace kserve --reset-values --wait
```

Every later upgrade is the single command at the top of this section.

Four things that cost time if they are not known in advance:

- **Phase 2 needs `--reset-values`.** Helm carries the previous release's
  user-supplied values into an upgrade, so without it every `enabled=false`
  from phase 1 is still in effect: the upgrade reports `STATUS: deployed`,
  and installs nothing. A release that claims success while the namespace
  stays empty is this flag, not a broken chart. `helm get values model-serving
  -n kserve` shows what the release is actually holding.
- **A failed first install leaves the definitions behind.** Helm records the
  release as failed, but resources already applied from `templates/` are not
  rolled back, so a retry can stop on
  `customresourcedefinitions.apiextensions.k8s.io "..." already exists`, and
  reinstalling under the same name stops on `cannot re-use a name that is still
  in use`. Either run phase 2 against the failed release, or uninstall and
  remove the definitions before starting again.
- **Removing the definitions spans four API groups, not one.** Filtering on
  `kserve` alone leaves the LLMISVC and Gateway API Inference Extension
  definitions behind, and the next install then fails on ownership metadata for
  something like `inferencemodelrewrites.llm-d.ai`:

  ```sh
  kubectl get crd -o name \
    | grep -E 'serving\.kserve\.io|llm-d\.ai|inference\.networking' \
    | xargs -r kubectl delete
  ```

- **Argo CD does not hit the ordering problem**, because `Retry=true`
  re-applies the rejected resources once the definitions are established. An
  installation that works under Argo CD therefore says nothing about whether
  `helm install` works, and this is exactly how the problem stayed hidden.

The release namespace holds the KServe control plane; generated model workloads
go to the separate namespace configured by `namespace`, which defaults to
`models`. The split is deliberate, and the release namespace has to be `kserve`
specifically.

Most of the chart is namespace-portable: rendered into `models`, 46 of its 48
namespaced resources follow the release namespace, and the webhook serving
certificates follow it correctly too (`llmisvc-webhook-server-service.models
.svc`). Two do not. The `llminferenceservices` and `llminferenceserviceconfigs`
definitions declare a conversion webhook whose `clientConfig` is pinned to a
literal namespace:

```yaml
conversion:
  strategy: Webhook
  webhook:
    clientConfig:
      service:
        name: llmisvc-webhook-server-service
        namespace: kserve          # literal, not .Release.Namespace
```

A definition is cluster-scoped, so that pin does not move with the release.
Installing the control plane anywhere else leaves the API server calling a
service that is not there, and because conversion runs on read as well as
write, every `LLMInferenceService` becomes unreadable rather than merely
uncreatable. Nothing surfaces at install time -- the chart reports success and
the controllers come up healthy.

So: install the control plane into `kserve`. Choose the workload namespace
freely with `namespace`; that is the one the models land in, and it is the one
to point per-team RBAC and quotas at. Running the controllers in that same
namespace would also mean cluster-level permissions sitting next to tenant
workloads, which is the arrangement the split exists to avoid.

If the LLMISVC feature is not wanted at all (`components.llmisvc.enabled` and
`components.llmisvcCrd.enabled` both false), the pinned references are never
rendered and the control plane can live anywhere -- but that trades away
`LLMInferenceService` entirely, so it is a narrower choice than it looks.

From GHCR:

```sh
helm upgrade --install model-serving \
  oci://ghcr.io/sassoftware/sas-retrieval-agent-manager-examples/charts/model-serving \
  --namespace kserve \
  --create-namespace
```

Omit `--version` to install the newest published chart. Add `--version <x.y.z>` to
pin an exact version.

## Model workloads

```yaml
namespace: models

hfSecret:
  enabled: true
  managed: true
  name: hf-secret
  token: ""

models:
  - name: example-model
    storageUri: hf://organization/model

llmInferenceServices:
  - name: example-llm
    model:
      uri: hf://organization/llm
    resources:
      limits:
        nvidia.com/gpu: "1"
```

Supply tokens through a protected values file or `--set-string`; never commit credentials.

## Replicas and node placement

Every entry in `models` and `llmInferenceServices` accepts `nodeSelector`,
`tolerations` and `affinity`, plus a `placementProfile` that names an entry in
the top-level `placementProfiles` map. `models` additionally accepts `replicas`.
The same keys can be set on `modelDefaults` and `llmDefaults` to apply to every
entry.

```yaml
placementProfiles:
  cpu-inference:
    nodeSelector:
      node.kubernetes.io/instance-type: m6i.8xlarge
    tolerations:
      - key: workload
        operator: Equal
        value: inference
        effect: NoSchedule

models:
  - name: example-model
    storageUri: hf://organization/model
    replicas: 2
    placementProfile: cpu-inference
    # Explicit fields win over the profile, field by field.
    tolerations:
      - key: dedicated
        operator: Equal
        value: example
        effect: NoSchedule
```

Precedence is resolved per field, highest first:

1. the field on the model or LLM service entry
2. the same field on the profile that entry names
3. the same field on `modelDefaults` or `llmDefaults`

Resolving field by field is what lets a model adopt a profile wholesale and
still change one toleration. A profile name that is not defined in
`placementProfiles` fails the render, naming both the workload and the profile.
Falling back to "no placement" would be worse than failing: the workload
schedules somewhere arbitrary, the scheduler reports success, and the mistake
only surfaces later as an eviction or an OOM on a node that was never meant to
run the model.

`replicas` renders as both `predictor.minReplicas` and `predictor.maxReplicas`,
because that is how KServe is told to hold a fixed pod count; there is no single
`replicas` field on a predictor. Leaving it unset renders neither field, which
is not the same as `replicas: 1`: it leaves the KServe defaults and any
autoscaler configuration in charge.

`LLMInferenceService` has its own `spec.replicas`, so `replicas` keeps its
existing meaning there. Placement is applied to `spec.template`, and to
`spec.worker` when a worker is requested, because the CRD models both as a full
PodSpec.

An empty map or list means "not set" and falls through to the next level. To
stop a profile's `nodeSelector` from applying to one model, name a different
profile or set the field to a value, rather than to `{}`.

## Local model cache

KServe's LocalModel feature downloads model weights onto a set of nodes once and
mounts them from node-local disk, instead of every pod pulling its own copy. An
`InferenceService` whose `storageUri` matches a `LocalModelCache` is mounted
from the node cache and is pinned by the scheduler to the nodes in that cache's
node groups.

The feature is off by default and renders nothing.

### Prerequisites

The chart cannot create any of these for you:

- **Node-local storage.** A StorageClass that provisions node-local volumes
  (local-path provisioner, LVM, or similar), or hand-made `local` PersistentVolumes.
  Network storage defeats the purpose and will usually fail the node affinity check.
- **Labelled nodes.** The node group's `nodeAffinity` has to select real nodes,
  and those nodes need the label the local model agent's DaemonSet selects on
  (`kserve/localmodel: worker` by default, see
  `kserve-localmodel-resources.kserve.localmodelnode.controller.nodeSelector`).
- **Disk headroom.** `modelSize` is how KServe decides whether a node group has
  room. Too small and the download is scheduled onto a node that then runs out
  of space.
- **The local model controller.** It runs a controller plus a per-node agent
  DaemonSet that writes to a host path.

### Enabling it

```yaml
localModelCache:
  enabled: true
  nodeGroups:
    - name: inference-cache
      size: 200Gi
      storageClassName: local-storage
      hostPath: /mnt/models
      nodeAffinity:
        required:
          nodeSelectorTerms:
            - matchExpressions:
                - key: kserve/localmodel
                  operator: In
                  values: ["worker"]

models:
  - name: example-model
    storageUri: hf://organization/model
    localCache:
      enabled: true
      size: 20Gi
      nodeGroups: [inference-cache]

# Helm cannot set a subchart value from a parent value, so the controller has
# its own switch. The chart fails the render if the two disagree.
components:
  localModel:
    enabled: true
kserve-localmodel-resources:
  kserve:
    localmodel:
      enabled: true
```

Each `localModelCache.nodeGroups` entry renders one cluster-scoped
`LocalModelNodeGroup`. The chart generates `persistentVolumeSpec` and
`persistentVolumeClaimSpec` from the convenience keys (`size`,
`storageClassName`, `hostPath`, `nodeAffinity`, `persistentVolumeReclaimPolicy`)
because the full specs are verbose and nearly always the same shape. Setting
either spec explicitly replaces the generated one entirely; the chart does not
merge them, because a half-merged volume spec is harder to debug than a copied
one.

`nodeAffinity` is the PersistentVolume's own node affinity. It is what actually
pins the cache, and therefore every pod using it, to the node group. Without it
the volume can bind anywhere and the cache is useless.

Each model with `localCache.enabled` renders one cluster-scoped
`LocalModelCache` whose `sourceModelUri` is the model's `storageUri`. That URI
is immutable in the CRD and is what KServe matches an `InferenceService`
against, so changing a cached model's `storageUri` means deleting and recreating
the cache. `size` defaults to `localModelCache.defaultSize`, and `nodeGroups`
defaults to every node group the release defines.

Turning `localModelCache.enabled` on while the controller is off fails the
render. Creating objects that nothing reconciles would be worse than failing:
the `InferenceService` would wait indefinitely for a cache that never fills.
Set `localModelCache.requireController: false` when the controller is
deliberately owned by another release.

## Components

Every upstream chart can be disabled under `components`. All seven are enabled by default. `kserve-resources` is the sole owner of shared resources; keep `kserve-llmisvc-resources.kserve.createSharedResources` disabled.

The dependency versions are pinned in `Chart.yaml` and `Chart.lock`. To upgrade KServe, update all seven dependency versions and `appVersion` together, then run:

```sh
helm dependency update helm-charts/model-serving
helm dependency build helm-charts/model-serving
helm lint helm-charts/model-serving --strict
helm unittest helm-charts/model-serving
bash helm-charts/model-serving/ci/validate.sh
```

Commit `Chart.lock`, but do not commit generated archives under `charts/`.

`tests/` holds per-template assertions; `ci/validate.sh` holds whole-release
render checks. `.github/workflows/helm-charts.yml` runs both for every chart
under `helm-charts/`, discovering them by listing the directory.

## Values migration

### 0.4.0: vLLM CPU hardening, placement, local model cache

Three additions. Only the first changes an existing release's render.

**vLLM CPU runtime hardening.** The only change that affects an existing
release's render, and the one to read before upgrading: it moves the vLLM
container to a non-root uid, which that image does not tolerate without help.

Until 0.4.0 the `vllmCPU` runtime had neither probes nor a `securityContext`,
while the OpenVINO runtime next to it had both.
That asymmetry was an oversight rather than a decision, and it had two
consequences: KServe marked the `InferenceService` `Ready` as soon as the
container process existed, long before vLLM could answer a request, and the
container ran as whatever user the image chose, which on the published CPU image
is root.

```yaml
clusterServingRuntimes:
  vllmCPU:
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: [ALL]
      privileged: false
      runAsNonRoot: true
      runAsUser: 1000
      seccompProfile:
        type: RuntimeDefault
    probes:
      startup:
        periodSeconds: 10
        failureThreshold: 9999
        httpGet: {path: /health, port: 8080}
      readiness:
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3
        httpGet: {path: /health, port: 8080}
      liveness:
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3
        httpGet: {path: /health, port: 8080}
    cacheVolume:
      enabled: true
      mountPath: /home/vllm
      sizeLimit: 2Gi
      env:
        - {name: USER, value: vllm}
        - {name: LOGNAME, value: vllm}
        - {name: HOME, value: /home/vllm}
        - {name: HF_HOME, value: /home/vllm/.cache/huggingface}
        - {name: XDG_CACHE_HOME, value: /home/vllm/.cache}
        - {name: VLLM_CACHE_ROOT, value: /home/vllm/.cache/vllm}
```

All three probes use vLLM's `GET /health`, which the OpenAI-compatible server
answers on its serving port; the template pins that to 8080 through the fixed
`--port=8080` argument. The startup probe uses `failureThreshold: 9999` for the
same reason as the OpenVINO runtime: a first start downloads and compiles a
model and has no useful upper bound, and a startup probe that gives up just
restarts the pod into the same slow path forever.

`cacheVolume` is load-bearing for the non-root change, and it carries two
different fixes.

**`USER` and `LOGNAME` keep vLLM importable.** This is the part that is easy to
get wrong, because the failure is not a permissions failure. The published image
(`public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.26.0`) declares no `USER` and
has no `/etc/passwd` entry for uid 1000, so `importing vllm` runs
`vllm/env_override.py` â†’ `torch._dynamo.package.cache_dir()` â†’
`torch._inductor.runtime.cache_dir_utils.default_cache_dir()` â†’
`getpass.getuser()` â†’ `pwd.getpwuid(os.getuid())`, which raises:

```text
KeyError: 'getpwuid(): uid not found: 1000'
```

This was verified by running the image directly: as root `import vllm` prints
`0.26.0`; with `--user 1000:1000` it raises the `KeyError` above. It happens at
*import* time, before vLLM reads any cache path, so no `HOME`, `HF_HOME`,
`XDG_CACHE_HOME` or `VLLM_CACHE_ROOT` value avoids it, and neither does
`TORCHINDUCTOR_CACHE_DIR` (tested on its own: still fails). `getpass.getuser()`
checks `LOGNAME`, `USER`, `LNAME` and `USERNAME` before falling back to `pwd`,
so one variable is enough; adding `-e USER=vllm` makes the same `--user
1000:1000` run import cleanly. The chart sets two of them because they cost
nothing, and the value never has to match a real account.

Because of that, the chart **refuses to render** a `vllmCPU` `securityContext`
that forces a non-root uid when none of those four variables is present in the
runtime's environment. Shipping it would produce a crash loop whose traceback
names `torch` and never mentions this chart.

**The cache paths keep vLLM running once it has started.** vLLM writes its torch
compile/inductor cache, the Hugging Face hub cache that `--trust-remote-code`
model code pulls from, and its own cache root under `$HOME`, which in this image
belongs to root. The chart mounts an `emptyDir` and points `HOME`, `HF_HOME`,
`XDG_CACHE_HOME` and `VLLM_CACHE_ROOT` at it. The kubelet creates `emptyDir`
world-writable (0777), so this needs no `fsGroup` â€” which is just as well,
because `ClusterServingRuntime` has no pod-level `securityContext` field to put
one in. That ownership behaviour belongs to the kubelet, not to this chart, and
is the one part of the arrangement the chart cannot assert.

All of these are rendered *before* `clusterServingRuntimes.vllmCPU.env`, so an
entry in `env` with the same name wins. Setting `cacheVolume.enabled: false`
drops the identity variables along with the cache ones, so it is only valid for
an image that has a real passwd entry for the uid.

To go back to the pre-0.4.0 behaviour entirely:

```yaml
clusterServingRuntimes:
  vllmCPU:
    securityContext: null   # not {}: Helm merges maps, it does not replace them
```

Also note that `readinessProbe` only applies in raw deployment mode. In
Knative-backed serverless mode the queue-proxy owns readiness, and KServe may
rewrite the probe it finds here.

The OpenVINO runtime gained `seccompProfile: RuntimeDefault` for parity, and its
existing startup probe and `securityContext` moved into values unchanged, so
they can be overridden the same way. Its `probes.readiness` and `probes.liveness`
default to empty: nothing about the OVMS behaviour changed, and adding a liveness
probe to a runtime that already survives in production is a good way to
introduce restart loops under load.

**Placement and replicas** (`placementProfiles`, plus `replicas`,
`placementProfile`, `nodeSelector`, `tolerations` and `affinity` on models, LLM
services and their defaults) are all unset by default and render nothing new.
See "Replicas and node placement" above.

**The local model cache** (`localModelCache`, plus `localCache` on a model) is
off by default and renders nothing. See "Local model cache" above.

### 0.3.0: runtime environment

Each entry of `clusterServingRuntimes` now also takes an `env` list, in the
Kubernetes `EnvVar` form. KServe merges it into the predictor pod, so it
applies to every model served by that runtime. Nothing has to be migrated: the
value is additive, and `env: []` renders no `env` block at all.

`clusterServingRuntimes.vllmCPU.env` ships one default, and it is load-bearing:

```yaml
clusterServingRuntimes:
  vllmCPU:
    env:
      - name: VLLM_USE_V2_MODEL_RUNNER
        value: "0"
```

Without it, a request that asks for structured output, meaning
`response_format: {"type": "json_schema"}` or any other guided decoding, kills
the vLLM engine on the CPU backend. vLLM 0.26.0 picks its "v2" model runner for
several model architectures, Gemma among them, even when the device is CPU, and
that runner's structured output worker is GPU-only: it hardcodes
`pin_memory=True` and drives a Triton kernel over CUDA streams. The first
schema-constrained request fails with

```text
RuntimeError: pin_memory=True requires a CUDA or other accelerator backend;
no pinned memory allocator is available on this system
```

which returns HTTP 500 and restarts the pod. Plain completions never reach that
code path, so the model otherwise looks healthy and the InferenceService still
reports `Ready`; a rising restart count is the only outward symptom.

Selecting the v1 runner routes to a path that honours the platform
pinned-memory flag, which is `False` on CPU, and that has an explicit CPU branch
for applying the grammar bitmask. Drop the variable once the runtime image
carries the upstream fix, which replaces the hardcoded `pin_memory=True` with
the platform flag.

The same list-replacement rule as `args` applies: setting `env` discards the
chart default, so copy the variable forward if it is still needed.

### 0.2.0: runtime arguments

Each entry of `clusterServingRuntimes` now takes one `args` list instead of a
fixed key for each flag. The chart tracked a moving target: every new runtime
flag needed a new value, a new template branch, and a new schema property. A
list passes any flag the runtime image accepts, so the chart no longer has to
follow upstream releases.

| Removed value | Replacement entry in `clusterServingRuntimes.vllmCPU.args` |
| --- | --- |
| `maxModelLen: 4096` | `- --max-model-len` then `- "4096"` |
| `gpuMemoryUtilization: "0.7"` | `- --gpu-memory-utilization` then `- "0.5"` |

`--gpu-memory-utilization` does not mean what its name suggests on the CPU
backend: it is the fraction of memory vLLM reserves for itself, measured
against the **node's** total rather than the container's limit. vLLM's own
default is 0.92, which fails to start on any node more than 8% busy, with the
engine core exiting and the pod restarting while the InferenceService sits at
`Ready=False`:

```text
ValueError: Available memory on node 0 (55.6/62.79 GiB) on startup is less
than desired CPU memory utilization (0.92, 57.77 GiB)
```

The chart therefore ships 0.5. Raise it for a node dedicated to one large
model, lower it when packing several models together, and when the container
carries a memory limit keep `NODE_TOTAL * fraction` below that limit â€” the
kernel will otherwise kill a container that vLLM believes is within budget.

The removed keys are rejected by the values schema, so a values file that still
sets them fails `helm lint` and `helm install` instead of being ignored.

```yaml
clusterServingRuntimes:
  vllmCPU:
    args:
      - --max-model-len
      - "4096"
```

Three rules apply to both runtimes:

- Every entry must be a string. Kubernetes container `args` take strings only,
  so quote a numeric value such as `"4096"`.
- Helm replaces lists, it does not merge them. Setting `args` discards the
  chart default, so copy forward any default that is still wanted.
- The flag style follows the runtime. vLLM takes the flag and its value as two
  entries. OpenVINO Model Server takes `--flag=value` as one entry.

The arguments that KServe depends on stay in the template and cannot be
overridden: `--model_name`, `--model_path`, `--port`, and `--rest_port` for
OpenVINO, and `/mnt/models`, `--host`, `--port`, and `--trust-remote-code` for
vLLM. `--rest_port` is fixed because the startup probe and the Prometheus
annotations refer to the same port, and since 0.4.0 vLLM's `--port` is fixed for
the same reason: its probes hit `/health` on it.

### Native KServe dependencies

The previous chart passed one shared `kserve` map into copied templates. Native dependencies use a value root for each chart:

| Previous value | New value |
| --- | --- |
| `kserve.controller.*` | `kserve-resources.kserve.controller.*` |
| `kserve.storage.*` | `kserve-resources.kserve.storage.*` |
| `kserve.agent.*` | `kserve-resources.kserve.agent.*` |
| `kserve.router.*` | `kserve-resources.kserve.router.*` |
| `kserve.certManager.*` | `kserve-resources.kserve.certManager.*` |
| `kserve.createSharedResources` | `kserve-resources.kserve.createSharedResources` |
| `kserve.llmisvc.*` | `kserve-llmisvc-resources.kserve.llmisvc.*` |
| `kserve.localmodel.*` | `kserve-localmodel-resources.kserve.localmodel.*` |
| `kserve.localmodelnode.*` | `kserve-localmodel-resources.kserve.localmodelnode.*` |
| `kserve.servingruntime.*` | `kserve-runtime-configs.kserve.servingruntime.*` |
| `kserve.llmisvcConfigs.*` | `kserve-runtime-configs.kserve.llmisvcConfigs.*` |

The chart-owned `models`, `modelDefaults`, `llmInferenceServices`, `llmDefaults`, `hfSecret`, `serviceAccount`, and `clusterServingRuntimes` interfaces remain available.

Helm does not forward arbitrary parent values into subcharts. A legacy value such as:

```yaml
kserve:
  controller:
    gateway:
      ingressGateway:
        className: contour
```

must therefore become:

```yaml
kserve-resources:
  kserve:
    controller:
      gateway:
        ingressGateway:
          className: contour
```

Leaving the value at the legacy root has no effect with native upstream dependencies.

## CRD lifecycle

Helm installs dependency CRDs before templates but does not delete CRDs during uninstall. Before installing this chart into a cluster with an existing KServe installation, remove or migrate the previous releases deliberately to avoid cluster-scoped resource ownership conflicts.

## Publishing

Merges to `main` publish the exact version from `Chart.yaml`. Increment that version before merging a chart change; published OCI versions are immutable.
