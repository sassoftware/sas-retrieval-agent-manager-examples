# Expose a running RAM agent

Retrieval Agent Manager (RAM) stores agent definitions and agent cards.
Agent-to-Agent (A2A) is the agent communication protocol.
An agent card is a JSON document that describes an agent.
Kubernetes is the cluster management system.
A Kubernetes context identifies a cluster and its access settings.

Use [run-expose-a2a.sh](./run-expose-a2a.sh) from Bash.
Use [run-expose-a2a.ps1](./run-expose-a2a.ps1) from PowerShell.
Both scripts build a Docker image.
Both scripts run [expose-a2a.sh](./expose-a2a.sh) inside the container.
Use NGINX Ingress or Contour HTTPProxy to expose the agent.
Ingress and HTTPProxy are Kubernetes routing resources.
The script uses the routing rules from the extension application A2A feature.

## Requirements

- Docker with a running engine for Linux containers.
- Bash 4 or later and `jq` for [run-expose-a2a.sh](./run-expose-a2a.sh).
- PowerShell 7 or later for [run-expose-a2a.ps1](./run-expose-a2a.ps1).
- `kubectl` with access to the target cluster.
- RAM API access.
- Permission to list Services and Pods in the agent namespace.
- Permission to read and create Ingress resources for NGINX.
- Permission to read, create, and patch HTTPProxy resources for Contour.
- Permission to list Ingress resources for automatic route detection.
- Kubernetes API discovery access for automatic Contour detection.
- Permission to read the matching TLS Secrets when automatic HTTPS trust is needed.
- Permission to list HTTPProxy resources for automatic Contour certificate lookup.
- A public DNS name that points to the selected ingress controller.

For HTTPS with NGINX, the script reads the TLS Secret name from the detected route.
If the name is not available, supply `-TlsSecretName` or enter the name at the prompt.
The TLS Secret must exist in the agent namespace.
Transport Layer Security (TLS) protects HTTP traffic.
For Contour, configure the public host and TLS on the parent HTTPProxy.
The script does not create DNS records, certificates, or ingress controllers.
The container includes Bash, `curl`, `jq`, `kubectl`, `kubelogin`, and OpenSSL.
The host does not need these container tools, except for the host requirements above.

## Container execution

The host scripts follow the container convention from the docs repository.
Each run builds the local image `ram-a2a-expose:local`.
Docker reuses unchanged build layers.
Set `RAM_A2A_IMAGE` to use a different image name.
Use [Dockerfile](./Dockerfile) to change the container tool versions.
The build supports `amd64` and `arm64`.

The host script selects a Kubernetes context.
It creates a temporary configuration for that context.
It includes certificate data in the temporary configuration.
It mounts that file read-only in the container.
It removes the temporary file after the container exits.
The script does not change the host configuration.
The image does not contain cluster credentials.
[.dockerignore](./.dockerignore) excludes local files from the build.

The default configuration file is `$HOME/.kube/config`.
`KUBECONFIG_PATH` takes precedence over `KUBECONFIG`.
Supply one configuration file, not a list of files.
Use `--kubeconfig FILE` in Bash or `-Kubeconfig FILE` in PowerShell to select another file.

Static tokens and client certificates are supported.
The scripts also support the `kubelogin` login command.
For `kubelogin --login azurecli`, install Azure CLI and `kubelogin` on the host.
Sign in on the host before execution.
The host script obtains a token for the temporary configuration.
Other `kubelogin` login modes run inside the container.
Other Kubernetes login commands are not supported.
Host credential caches are not mounted in the container.

The container uses Docker host networking, as in the docs repository.
For Docker Desktop, enable host networking if the cluster uses a host-local address.
The scripts pass proxy environment variables to the container when set.
The container must have network access to the cluster and the RAM API.

## Select an agent

The default execution is interactive.
Start without options:

```bash
bash ./run-expose-a2a.sh
```

```powershell
./run-expose-a2a.ps1
```

The script uses the only Kubernetes context automatically.
If the configuration has more than one context, select a context.
The script then detects missing RAM settings from existing cluster routes.
It lists agents with valid cards, a champion configuration, and a ready production Service.
Select an agent number from that list.
The script applies the route after selection.
Use `--dry-run` or `-DryRun` to preview the operations instead.

To expose one known agent, supply its ID:

```bash
bash ./run-expose-a2a.sh --agent-id "my-agent-id"
```

```powershell
./run-expose-a2a.ps1 -AgentId "my-agent-id"
```

An agent ID skips the agent selection prompt.
The script still checks the configured card, champion configuration, and production Service.
The script still prompts for missing or ambiguous settings.
An unavailable agent ID causes an error.
The script does not select a different agent.

### Automatic settings

Explicit options take precedence over detected values.
Detection uses the selected namespace, which defaults to `retagentmgr`.
Use `--namespace` or `-Namespace` for another namespace.

For NGINX, the script looks for an Ingress route to `<base-path>/postgrest`.
It reads the host, protocol, ingress class, and matching TLS Secret.
For Contour, it checks the selected parent HTTPProxy for its virtual host and TLS settings.
The default parent name is `retrieval-agent-manager-ingress`.
The default parent namespace is the agent namespace.
Use `--http-proxy-name` and `--extension-namespace`, or their PowerShell parameters, for another parent.

The detected RAM URL and public URL use the configured base path.
The default base path is `/SASRetrievalAgentManager`.
Supply `--base-path` or `-BasePath` if the cluster uses another path.
The script prompts when more than one route matches.
It also prompts when a required setting cannot be detected.
Detection does not search all namespaces or infer other application paths.
Fully specified commands do not require route discovery.
For an existing managed Ingress, the script keeps the agent's current A2A path when no public URL or base path override is supplied.
For example, an endpoint under `/SASRetrievalAgentManager/extension/a2a/` stays at that path.
The script prints the existing endpoint URL.
It does not move that endpoint to the RAM root path.
TLS settings detected from the RAM Ingress are defaults for new Ingress resources.
They do not replace or invalidate the TLS settings of an existing agent Ingress.
An explicit TLS Secret option must match the existing Ingress.

### RAM credentials

The script signs in with a device code before it reads RAM data.
Keycloak is the RAM identity service.
The device-code flow lets you sign in with a browser without giving the script your password.
The script displays a browser URL and a user code.
Open the URL on the host.
Complete sign-in before the code expires.
The container does not open a host browser automatically.

The default Keycloak URL is `<RAM URL>/auth`.
The default realm is `sas-iot`.
The default public client is `sas-ram-api`.
These are the RAM Helm chart settings.
Use `--keycloak-url`, `--keycloak-realm`, and `--keycloak-client-id` for other settings.
PowerShell accepts `-KeycloakUrl`, `-KeycloakRealm`, and `-KeycloakClientId`.
The client must permit device authorization and the `S256` PKCE method.
Proof Key for Code Exchange (PKCE) protects the authorization exchange.
The script handles pending authorization, slower polling, denied authorization, and expired codes.

After sign-in, the script sends the access token with every RAM data request.
If a RAM data request fails, the script prints the HTTP status.
It also prints the PostgREST error code and message when the response contains these fields.
`PGRST302: Anonymous access is disabled` can mean that a valid token has no database role.
An administrator account does not ensure that the API client includes RAM roles in its tokens.
Check token forwarding, the user's RAM roles, the API client's role scopes and claim mappings, and PostgREST `jwt-role-claim-key`.
The default RAM role claim is `resource_access.sas-ram-app.roles[0]`.
It does not send the token to Kubernetes.
Kubernetes access still uses the selected kubeconfig.
Tokens and PKCE data use temporary protected files.
The script removes these files when it exits.
It does not save refresh tokens or reuse a device session on the next run.

To use an existing token instead, set `RAM_AUTHORIZATION` to the complete HTTP Authorization value.
Use the Bearer authentication scheme with the access token.
The script skips device sign-in when this value is set.
PowerShell also accepts `-Authorization`.
The scripts pass `RAM_AUTHORIZATION` by environment variable name.
Credential values are not added to Docker arguments.
Do not store tokens in the script.

### HTTPS certificate trust

A token does not correct a certificate verification error.
Certificate verification happens before Keycloak or RAM can accept the token.
You do not need to provide a certificate file for the selected cluster.
The script first uses the container's system certificate store.
If verification fails, the script finds a matching Ingress or Contour HTTPProxy.
It checks the agent namespace and the extension namespace.
It reads `ca.crt` and `tls.crt` from the route's TLS Secret through the selected Kubernetes context.
It does not write or print `tls.key`.
It adds the public certificates to a temporary bundle with the system certificates.
It then repeats the request with certificate and hostname verification enabled.

```bash
bash ./run-expose-a2a.sh --context ragrant
```

```powershell
./run-expose-a2a.ps1 -Context ragrant
```

The certificate lookup supports exact hosts and one-level wildcard hosts.
For Contour, it also supports a TLS Secret reference with its own namespace.
Kubernetes access must already verify the API server through the kubeconfig.
The script uses that authenticated access to obtain the route certificates.
The script stops if it cannot read a matching Secret or certificate verification still fails.
If a controller uses a default certificate with no route Secret reference, configure the route's TLS Secret.
Use the correct certificate for the host.
Replace expired certificates.
The script removes the temporary bundle when it exits.

`--ca-cert` and `-CaCert` remain optional overrides for certificates outside the selected cluster.
You can also set `RAM_CA_CERT` to an optional host certificate file path.
An explicit override disables automatic cluster certificate lookup.
The script does not disable certificate verification.
This bundle does not change Kubernetes certificate settings or browser trust.

From Bash:

```bash
bash ./run-expose-a2a.sh --ram-url "https://ram.example.com/SASRetrievalAgentManager" --dry-run
```

From PowerShell:

```powershell
./run-expose-a2a.ps1 -RamUrl "https://ram.example.com/SASRetrievalAgentManager" -DryRun
```

Select a context if more than one context is available.
Select a RAM route if more than one route matches.
Complete device-code sign-in.
Select an agent.
Supply any unresolved settings.

`-RamUrl` is the RAM application base URL, not the PostgREST URL.
PostgREST is the RAM database API.
The script reads `/postgrest/agent` and `/postgrest/agent_experiment`.
The script reads all pages of each response.
Supply the RAM URL for the selected cluster.
The script cannot confirm that a RAM URL belongs to a Kubernetes context.

Only agents with all these conditions are available:

- The configured agent card has the format accepted by the extension application.
- The agent has a champion configuration.
- Exactly one production Service selects a running, ready production Pod.
- The Service has a TCP port of `8001`.

The script checks the `sas-retagentmgr/agent-id` and `dev-server=false` labels.
The Pod must also have `sas-retagentmgr/workload-type=agent`.
The script checks all Service selector labels.
The script shows a reason for each agent that is not available.
The script does not read cards from running Services during selection.
Card validation checks the configured format, not runtime availability or full A2A protocol compliance.

Use `-ListOnly` to show the available agents without route changes:

```bash
bash ./run-expose-a2a.sh --context "my-cluster" --namespace "retagentmgr" \
  --ram-url "https://ram.example.com/SASRetrievalAgentManager" --list-only
```

```powershell
./run-expose-a2a.ps1 -Context "my-cluster" -Namespace "retagentmgr" `
  -RamUrl "https://ram.example.com/SASRetrievalAgentManager" -ListOnly
```

## NGINX Ingress

```bash
bash ./run-expose-a2a.sh --context "my-cluster" --namespace "retagentmgr" \
  --ram-url "https://ram.example.com/SASRetrievalAgentManager" \
  --agent-id "my-agent-id" --mode ingress \
  --public-base-url "https://agents.example.com/SASRetrievalAgentManager" \
  --ingress-class-name nginx --tls-secret-name "agents-tls" --dry-run
```

```powershell
./run-expose-a2a.ps1 -Context "my-cluster" -Namespace "retagentmgr" `
  -RamUrl "https://ram.example.com/SASRetrievalAgentManager" `
  -AgentId "my-agent-id" -Mode ingress `
  -PublicBaseUrl "https://agents.example.com/SASRetrievalAgentManager" `
  -IngressClassName nginx -TlsSecretName "agents-tls" -DryRun
```

The script creates a separate Ingress in the agent namespace.
The default Ingress class is `nginx`.
The resource name is `retrieval-agent-manager-a2a-<agent-id>`.
The route path is `<base-path>/a2a/<agent-id>`.
The NGINX rewrite removes the route prefix.
The Service receives the remaining path.

## Contour HTTPProxy

```bash
bash ./run-expose-a2a.sh --context "my-cluster" --namespace "retagentmgr" \
  --ram-url "https://ram.example.com/SASRetrievalAgentManager" \
  --agent-id "my-agent-id" --mode httpproxy \
  --public-base-url "https://agents.example.com/SASRetrievalAgentManager" \
  --http-proxy-name "retrieval-agent-manager-ingress" --dry-run
```

```powershell
./run-expose-a2a.ps1 -Context "my-cluster" -Namespace "retagentmgr" `
  -RamUrl "https://ram.example.com/SASRetrievalAgentManager" `
  -AgentId "my-agent-id" -Mode httpproxy `
  -PublicBaseUrl "https://agents.example.com/SASRetrievalAgentManager" `
  -HttpProxyName "retrieval-agent-manager-ingress" -DryRun
```

The parent HTTPProxy must exist.
Its virtual host must match the public URL host.
If the parent is in the agent namespace, the script adds a route to the parent.
The script keeps all other routes.
If the parent has includes but no routes, the script adds the routes field.

For a parent in another namespace, set `-ExtensionNamespace`:

```powershell
./run-expose-a2a.ps1 -Context "my-cluster" -Namespace "agents" `
  -ExtensionNamespace "ram-extension" `
  -RamUrl "https://ram.example.com/SASRetrievalAgentManager" `
  -AgentId "my-agent-id" -Mode httpproxy `
  -PublicBaseUrl "https://agents.example.com/SASRetrievalAgentManager" `
  -HttpProxyName "retrieval-agent-manager-ingress" -DryRun
```

The script creates a child HTTPProxy in the agent namespace.
The script adds an include to the parent HTTPProxy.
The child uses `-IngressClassName`, if supplied.
Otherwise, the child uses the parent class.
The route rewrite removes the route prefix.

## Parameters and safety

| PowerShell | Bash | Function |
| --- | --- | --- |
| `-Context` | `--context` | Select the Kubernetes context. Use the only context automatically when omitted. |
| `-Kubeconfig` | `--kubeconfig` | Select one host configuration file. |
| `-Namespace` | `--namespace` | Set the agent namespace. Default: `retagentmgr`. |
| `-RamUrl` | `--ram-url` | Set the RAM application base URL. Detect or prompt when omitted. |
| `-KeycloakUrl` | `--keycloak-url` | Set the Keycloak base URL. Default: RAM URL plus `/auth`. |
| `-KeycloakRealm` | `--keycloak-realm` | Set the realm. Default: `sas-iot`. |
| `-KeycloakClientId` | `--keycloak-client-id` | Set the public device client. Default: `sas-ram-api`. |
| `-CaCert` | `--ca-cert` | Optionally override automatic cluster trust with a host PEM bundle. |
| `-AgentId` | `--agent-id` | Select one available agent without a prompt. |
| `-Mode` | `--mode` | Select `ingress` or `httpproxy`. Detect or prompt when omitted. |
| `-PublicBaseUrl` | `--public-base-url` | Set the public origin and application path. Detect or prompt when omitted. |
| `-BasePath` | `--base-path` | Set the fallback path. Default: `/SASRetrievalAgentManager`. |
| `-ExtensionNamespace` | `--extension-namespace` | Set the parent namespace. Default: the agent namespace. |
| `-HttpProxyName` | `--http-proxy-name` | Set the parent name. Default: `retrieval-agent-manager-ingress`. |
| `-IngressClassName` | `--ingress-class-name` | Set the ingress class. |
| `-TlsSecretName` | `--tls-secret-name` | Set the NGINX TLS Secret name. |
| `-TimeoutSeconds` | `--timeout-seconds` | Set request and status timeouts. Default: `60` seconds. |
| `-ListOnly` | `--list-only` | Print available agents as JSON. |
| `-DryRun` | `--dry-run` | Print planned operations as JSON without route changes. |

Use `bash ./run-expose-a2a.sh --help` to show the Bash options.
PowerShell also accepts `-ImageName` to set the local image name.

Remove `-DryRun` to make the changes.
For Bash, remove `--dry-run`.
Both dry-run modes build and run the container.
Neither dry-run mode changes cluster resources.
Supply all selection parameters and `RAM_AUTHORIZATION` to run without user input.
An agent ID alone does not skip device sign-in.
Dry-run and list-only execution also require RAM sign-in when no token is supplied.
The script accepts default HTTP and HTTPS ports only.
Base paths can contain letters, numbers, `_`, `-`, and `/`.

The script uses the extension resource names and labels.
The script also checks legacy `ram-a2a-<hash>` resource names.
If an existing resource has different routing, the script stops.
For an Ingress conflict, the script prints the expected route and the existing routes.
It also identifies conflicting ownership, class, rewrite annotations, or explicit TLS settings.
The script does not replace the backend of an existing route.
HTTPProxy changes include a resource version check to prevent concurrent changes from being lost.
If a parent update fails after child creation, the child can remain.
Correct the reported problem before another run.

After a Contour change, the script waits for a `valid` HTTPProxy status.
NGINX has no equivalent status check in this script.
The script prints the endpoint URL and the public agent card URL.
Check the public agent card URL before use.
The script does not change URLs inside the configured agent card.