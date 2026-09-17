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

The KServe controllers belong in the `kserve` release namespace because KServe `v0.20.0` contains namespace-sensitive webhook and cert-manager references. Generated model workloads default to the separate `models` namespace configured by `namespace`.

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

## Components

Every upstream chart can be disabled under `components`. All seven are enabled by default. `kserve-resources` is the sole owner of shared resources; keep `kserve-llmisvc-resources.kserve.createSharedResources` disabled.

The dependency versions are pinned in `Chart.yaml` and `Chart.lock`. To upgrade KServe, update all seven dependency versions and `appVersion` together, then run:

```sh
helm dependency update helm-charts/model-serving
helm dependency build helm-charts/model-serving
helm lint helm-charts/model-serving --strict
helm unittest helm-charts/model-serving
```

Commit `Chart.lock`, but do not commit generated archives under `charts/`.

## Values migration

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
