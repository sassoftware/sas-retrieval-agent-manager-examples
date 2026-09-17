# Helm charts

| Chart | Description |
| --- | --- |
| [litellm](litellm/) | Deploys the LiteLLM proxy with pluggable routing (Ingress, Gateway API, Contour, OpenShift) and a choice of config-file or database-backed model management. |
| [model-serving](model-serving/) | Installs KServe from locked upstream dependencies and declares model-serving workloads through Helm values. |

Each chart is published to GHCR under
`oci://ghcr.io/sassoftware/sas-retrieval-agent-manager-examples/charts/<chart>`
and documented in its own README. Installation, upgrade, and configuration
guidance lives there rather than here.

## Validating a chart

Run these before opening a pull request, substituting the chart you changed:

```sh
helm dependency build helm-charts/<chart>
helm lint helm-charts/<chart> --strict
helm unittest helm-charts/<chart>
bash helm-charts/<chart>/ci/validate.sh
```

`helm dependency build` is a no-op for a chart with no dependencies, so the same
four commands apply to every chart.

## Layout

Each chart directory follows the same structure:

| Path | Purpose |
| --- | --- |
| `Chart.yaml` | Chart metadata. `appVersion` tracks the upstream release; `version` is managed by CI. |
| `values.yaml` | Documented defaults. |
| `values.schema.json` | Rejects unknown keys and bad types at install time. |
| `templates/` | The rendered Kubernetes objects. |
| `tests/` | `helm unittest` suites, asserting on individual templates. |
| `ci/validate.sh` | Optional whole-release render checks, for assertions that span templates. |

`tests/` and `ci/` are excluded from the packaged chart.

## Continuous integration

`.github/workflows/helm-charts.yml` handles every chart. It builds its matrix by
listing this directory, so a new chart is picked up by existing: nothing in the
workflow names a chart.

For each chart it lints, runs the unit tests, runs `ci/validate.sh` when present,
and packages the result. A chart whose own files changed is published to GHCR
from the same job when the run is on `main`, with the next free patch version
resolved from the registry.
