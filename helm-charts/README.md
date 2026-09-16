# Helm charts

| Chart | Description |
| --- | --- |
| [model-serving](model-serving/) | Installs KServe from locked upstream dependencies and declares model-serving workloads through Helm values. |

Build dependencies and validate all chart changes before opening a pull request:

```sh
helm dependency build helm-charts/model-serving
helm lint helm-charts/model-serving --strict
helm unittest helm-charts/model-serving
```

See the chart README for installation, upgrade, migration, and CRD lifecycle guidance.
