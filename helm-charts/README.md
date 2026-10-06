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

## Using a certificate for MCP Server

To let RAM trust a certificate authority used by an MCP server, create a
ConfigMap with the certificate bundle in PEM format. Use the same namespace as
the RAM Helm release. The key must be `trusted-certs.pem`:

If a certificate chain has separate root and intermediate CA certificate files,
combine the files before you create the ConfigMap:

```sh
cat root-ca.pem intermediate-ca.pem > ca-bundle.pem
```

Replace the example file names with your certificate file names. Keep the PEM
certificate boundaries. Each input file must end with a newline. Do not include
private keys. Keep certificates required by existing connections when you
update a bundle.

Before you update an existing installation, check the current
`integrations.trustedCerts` Helm values. Use the existing ConfigMap name in
place of `trusted-certs-bundle` in both commands below. If the installation
uses a Secret instead of a ConfigMap, do not change the resource type.

The ConfigMap update replaces the `trusted-certs.pem` field. It does not
append certificates. Save the existing ConfigMap before you change it.
Use new backup file names to avoid overwriting an earlier backup:

```sh
kubectl get configmap <existing-configmap> \
	--namespace retagentmgr -o yaml > trusted-certs-backup.yaml
kubectl get configmap <existing-configmap> \
	--namespace retagentmgr \
	-o jsonpath='{.data.trusted-certs\.pem}' > existing-ca-bundle.pem
```

Stop if either command fails. Check that `existing-ca-bundle.pem` contains
the existing certificates. Keep the backup until you verify the updated
connections.

Combine the existing certificates with the new CA bundle. Use a separate
output file so that the command does not overwrite either input file:

```sh
{
	cat existing-ca-bundle.pem
	printf '\n'
	cat ca-bundle.pem
} > combined-ca-bundle.pem
```

For an existing installation, use `/path/to/combined-ca-bundle.pem` in the
command below. For a new installation, use `/path/to/ca-bundle.pem`.
Do not apply the new CA certificates alone if existing connections still
require the certificates in the current bundle:

```sh
kubectl create configmap trusted-certs-bundle \
	--namespace retagentmgr \
	--from-file=trusted-certs.pem=/path/to/ca-bundle.pem \
	--dry-run=client -o yaml | kubectl apply -f -
```

Upgrade the existing RAM release. Replace `<release-name>`, `<chart-reference>`,
and `retagentmgr` with the values for your installation:

```sh
helm upgrade <release-name> <chart-reference> \
	--namespace retagentmgr \
	--reuse-values \
	--set integrations.trustedCerts.enabled=true \
	--set integrations.trustedCerts.type=configMap \
	--set integrations.trustedCerts.name=trusted-certs-bundle
```

The chart mounts the bundle at `/mnt/config/certs/trusted-certs.pem` and sets
`TRUSTED_CERTS_PATH` for the API. On the first upgrade, enabling these values
adds the mount and rolls the API pods. RAM can then use the bundle to trust the
MCP server certificate. To update the bundle later, apply the ConfigMap command
again. Restart the API pods if the application does not reload the mounted
file.

If you'd like to use these certificates with an MCP server, they must also be passed in as an environment variable. See [this section for more details](../examples/container_mcp_servers/sas_mcp_server/README.md#configuration-file).
