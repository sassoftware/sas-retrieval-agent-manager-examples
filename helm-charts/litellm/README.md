# LiteLLM Helm Chart

Deploys the [LiteLLM](https://docs.litellm.ai/) proxy: an OpenAI-compatible gateway in front of every model provider, plus the management API and the Admin UI. One Deployment serves all three.

This chart is a clean-room replacement for the two upstream charts (`helm/litellm-helm` and `helm/litellm`). It carries neither as a dependency.

The reason it exists is routing. Both upstream charts publish through a `networking.k8s.io/v1` Ingress and nothing else, so a cluster running Envoy Gateway, Contour, or OpenShift has to bolt its own object on afterwards, usually as a hand-written manifest outside the release. Here each implementation is a first-class, schema-validated template.

| Implementation | API | Typical controller |
| --- | --- | --- |
| Ingress | `networking.k8s.io/v1` | ingress-nginx, HAProxy, Traefik |
| HTTPRoute | `gateway.networking.k8s.io/v1` | Envoy Gateway, Contour, Istio, NGINX Gateway Fabric |
| HTTPProxy | `projectcontour.io/v1` | Contour |
| Route | `route.openshift.io/v1` | OpenShift |

More than one may be enabled at a time, which is how you move from Ingress to Gateway API without a gap in service.

## Contents

- [Prerequisites](#prerequisites)
- [Install](#install)
- [Versions](#versions)
- [Model management](#model-management)
- [Provider credentials](#provider-credentials)
- [Routing](#routing)
- [Sharing a hostname](#sharing-a-hostname)
- [Single sign-on](#single-sign-on)
- [Database](#database)
- [Creating the database](#creating-the-database)
- [Redis](#redis)
- [Migration Job](#migration-job)
- [Secrets](#secrets)
- [Scaling and availability](#scaling-and-availability)
- [Observability](#observability)
- [Running read-only](#running-read-only)
- [Values reference](#values-reference)
- [Validation](#validation)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Not included](#not-included)

## Prerequisites

- Kubernetes 1.25 or later
- Helm 3.19 or later
- The CRDs for whichever routing implementation you enable
- PostgreSQL 14 or later, for the database flow only
- Redis 7.0 or later, for more than one replica

This chart deploys no database and no Redis. Both upstream charts bundle the Bitnami subcharts, whose versioned tags were withdrawn from `docker.io/bitnami` and now need a `bitnamilegacy` repoint to install at all. A proxy that stores virtual keys and spend data belongs in front of a database you back up and patch, so this chart points at one you already run instead.

## Install

From a source checkout:

```sh
helm upgrade --install litellm helm-charts/litellm \
  --namespace litellm \
  --create-namespace \
  --values my-values.yaml
```

From GHCR:

```sh
helm upgrade --install litellm \
  oci://ghcr.io/sassoftware/sas-retrieval-agent-manager-examples/charts/litellm \
  --namespace litellm \
  --create-namespace \
  --values my-values.yaml
```

Omit `--version` to install the newest published chart. Add `--version <x.y.z>` to pin an exact version.

The default values install a working proxy with one mock model, so a bare `helm install` starts and passes its health probes with nothing else configured. Replace `models` before you send real traffic.

Reach it without routing:

```sh
kubectl -n litellm port-forward svc/litellm 4000
```

The OpenAI-compatible API is then at `http://localhost:4000`, and the Admin UI at `http://localhost:4000/ui`.

## Versions

`appVersion` in `Chart.yaml` is the upstream LiteLLM release this chart targets, and it is the default container tag. `image.tag` is empty by default and falls back to it, so one edit moves the proxy and the migration Job together. Nothing can pin them apart: both resolve the image through the same template helper.

Set `image.tag` only to run a release other than the one the chart targets.

> [!WARNING]
> The chart rejects `latest` and `main-latest`. The proxy and the migration Job resolve the tag independently at pull time, so a tag that moves between the Job finishing and a pod restarting runs a different proxy against the schema that Job just migrated. `main-stable`, LiteLLM's documented floating production tag, is allowed.

`version` in `Chart.yaml` is the chart's own version and is managed by CI, which resolves the next free patch from the registry on every publish.

## Model management

`modelManagement.mode` decides where the model catalog lives. It is the single most consequential value in this chart, and it is worth choosing deliberately. Everything else works the same either way.

| | `config` | `database` |
| --- | --- | --- |
| Catalog lives in | `config.yaml`, from `models` in your values | PostgreSQL |
| Adding a model | edit values, `helm upgrade`, pods roll | Admin UI or `POST /model/new`, no redeploy |
| Reproducible from Git | yes | no — the database is the source of truth |
| Needs PostgreSQL | no | yes |
| Migration Job | not rendered | runs `prisma migrate deploy` before the proxy |
| Virtual keys, teams, budgets | unavailable | available |
| Spend tracking | unavailable | available |
| Audit of who changed what | Git history | the database |

Those last three rows usually decide it. Virtual keys and spend tracking have no `config.yaml` representation, so any deployment that hands out per-team keys or bills usage back needs `database`.

### Config flow

```yaml
modelManagement:
  mode: config

models:
  - model_name: gpt-4o
    litellm_params:
      model: azure/gpt-4o
      api_base: https://example.openai.azure.com/
      api_key: os.environ/AZURE_OPENAI_API_KEY
  - model_name: claude-sonnet
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

environmentSecrets:
  - litellm-provider-keys
```

`models` is appended to `proxyConfig.model_list` and rendered into a ConfigMap. The pod template carries a checksum of that ConfigMap, so `helm upgrade` restarts the proxy whenever the catalog changes. Without the checksum the new file would sit in the ConfigMap unread until an unrelated change happened to roll the pods.

Everything that is not a model goes in `proxyConfig`, which is rendered verbatim:

```yaml
proxyConfig:
  litellm_settings:
    drop_params: true
    request_timeout: 600
    callbacks: ["prometheus"]
  router_settings:
    routing_strategy: simple-shuffle
  general_settings:
    proxy_batch_write_at: 60
```

To manage `config.yaml` entirely outside this chart, set `config.existingConfigMap.name`. `models` and `proxyConfig` are then ignored, and no ConfigMap is rendered.

### Database flow

```yaml
modelManagement:
  mode: database

database:
  host: litellm-pg.postgres.database.azure.com
  name: litellm
  sslMode: verify-full
  existingSecret:
    name: litellm-db        # keys: username, password

redis:
  host: litellm-redis.example.com
  existingSecret:
    name: litellm-redis     # key: password
```

The chart sets `general_settings.store_model_in_db`, renders the migration Job, and starts the proxy with `DISABLE_SCHEMA_UPDATE=true` so that N replicas do not race one database on every rollout.

`config.yaml` is still mounted and still owns everything that is not a model: callbacks, router settings, guardrails, and the rest of `general_settings`. Only the catalog moves.

Set `modelManagement.seedFromConfig: true` to also render `models` into `config.yaml` as an always-present floor, for example a house model that must exist even if someone empties the database. Config entries are read-only in the UI.

### Turning the database on without moving the catalog

`database.enabled` is independent of `modelManagement.mode`. Setting it while staying in `config` mode gives you virtual keys, teams, budgets, and spend tracking, while the catalog stays in Git:

```yaml
modelManagement:
  mode: config
database:
  enabled: true
  host: litellm-pg.example.com
  existingSecret:
    name: litellm-db
```

This is a good middle ground for a platform team that wants reviewable model changes and per-team keys at the same time.

### Switching flows later

`config` to `database` is additive: point `database.*` at a server, flip the mode, upgrade. The migration Job creates the schema, and the catalog you already had keeps loading if you set `seedFromConfig`.

`database` to `config` drops every runtime-created model, key, team, and spend record from the serving path. Export anything you need first; the chart cannot migrate it for you.

## Provider credentials

Never put a literal API key in `models` or `proxyConfig`. Both are rendered into a ConfigMap, which is world-readable to anything with `get configmap` in the namespace, and both end up in the Helm release secret in plain text.

Put keys in a Secret, list it under `environmentSecrets`, and reference them as `os.environ/<KEY>`:

```sh
kubectl -n litellm create secret generic litellm-provider-keys \
  --from-literal=AZURE_OPENAI_API_KEY=... \
  --from-literal=ANTHROPIC_API_KEY=...
```

```yaml
environmentSecrets:
  - litellm-provider-keys
models:
  - model_name: gpt-4o
    litellm_params:
      model: azure/gpt-4o
      api_key: os.environ/AZURE_OPENAI_API_KEY
```

Every key in a listed Secret becomes an environment variable in the pod, so the names in the Secret are exactly what `os.environ/` resolves against. `environmentConfigMaps` works the same way for values that are not secret.

In the database flow, credentials added through the Admin UI are encrypted in the database with `LITELLM_SALT_KEY`. Set it once through `environmentSecrets` and never change it: it encrypts stored provider keys, and changing it makes them unreadable.

## Routing

Shared settings live under `routing`; each implementation adds its own block. `routing.hosts`, `routing.path`, `routing.tls`, `routing.annotations`, and `routing.labels` apply to all of them.

The proxy serves the OpenAI API, the management API, and the UI from one port, so a single path prefix covers everything and no path-based dispatch is needed.

`routing.path` defaults to `/litellm` and must match `serverRootPath`, which is the prefix the proxy actually serves under — see [Sharing a hostname](#sharing-a-hostname).

### Forwarded headers

TLS terminates at the ingress, so the request arriving at the pod is plaintext. Left to itself the proxy takes that at face value and emits `http://` URLs — the trailing-slash redirect on `/ui` sends the browser to a plaintext address, downgrading a release this chart published over HTTPS.

uvicorn already parses the `X-Forwarded-*` headers that say otherwise, but ignores them unless the sender is trusted, and its default is `127.0.0.1` — which in Kubernetes is never the ingress. `trustedProxies` supplies that list, and defaults to `*`:

```yaml
trustedProxies: ["*"]
```

`*` trusts any client that can reach the pod. The Service is ClusterIP, so that means in-cluster callers rather than the internet, and the only header they could forge is consulted for the client IP in logs and for LiteLLM's optional `allowed_ips`. On a cluster without NetworkPolicy, narrow it to whatever fronts the release:

```yaml
trustedProxies: ["10.244.0.0/16"]   # pod CIDR
```

CIDR notation needs uvicorn 0.30 or newer, which the chart's pinned image carries. Setting `trustedProxies: []` leaves the variable unset and restores uvicorn's own default.

### Ingress

```yaml
routing:
  hosts: [litellm.example.com]
  tls:
    enabled: true
    secretName: litellm-tls
  ingress:
    enabled: true
    className: nginx
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
      nginx.ingress.kubernetes.io/proxy-body-size: "32m"
```

> [!NOTE]
> ingress-nginx rejects a dot in an `Exact` or `Prefix` path through its admission webhook, and serves `ImplementationSpecific` as a plain prefix anyway. The chart therefore downgrades a dotted path to `ImplementationSpecific` when `className` is `nginx`, so a path such as `/v1.0` is accepted instead of being rejected at apply time.

Raise the read timeout. A streaming completion holds the connection open far longer than the 60-second default, and the symptom of leaving it alone is truncated responses under load rather than an obvious error.

`routing.ingress.extraPaths` adds further paths to each host, for example to send one prefix to a different Service.

### HTTPRoute (Gateway API)

```yaml
routing:
  hosts: [litellm.example.com]
  httpRoute:
    enabled: true
    parentRefs:
      - name: eg
        namespace: envoy-gateway-system
        sectionName: https
    timeouts:
      backendRequest: 0s
```

> [!IMPORTANT]
> `routing.tls` is ignored here on purpose. In Gateway API the certificate belongs to the Gateway's listener, not to the route attached to it. Put the Secret in the listener's `tls.certificateRefs`; a chart that also rendered it here would silently do nothing.

`timeouts.backendRequest: 0s` disables the request timeout. Without it a long streaming completion is cut off at the implementation's default, which for Envoy Gateway is 15 seconds.

`filters` and `extraRules` are passed through untouched, so a `URLRewrite`, a `RequestHeaderModifier`, or an extra rule for a second hostname all work without the chart knowing about them.

### HTTPProxy (Contour)

```yaml
routing:
  hosts: [litellm.example.com]
  tls:
    enabled: true
    secretName: litellm-tls
  httpProxy:
    enabled: true
    ingressClassName: contour
    timeoutPolicy:
      response: infinity
      idle: 600s
    retryPolicy:
      count: 2
      retryOn: ["5xx"]
```

Prefer this over a plain Ingress on Contour. The retry policy, response timeout, and load balancer policy become schema-validated fields the API server checks, instead of controller-specific annotations that nothing validates and that fail silently when misspelled.

`timeoutPolicy.response: infinity` is the Contour equivalent of the timeout note above.

One HTTPProxy carries one virtual host. The chart fails the render rather than silently publishing only the first entry when `routing.hosts` has more than one.

#### Sharing a hostname another release already owns

Contour allows one **root** HTTPProxy per FQDN, and a root is any proxy that declares a `virtualhost`. When another application already owns the hostname this release has to answer on, a second root is rejected — and it is undefined which of the two loses, so the attempt risks taking the incumbent down.

The way through is delegation: that application includes this one under a path prefix, and this release renders a **child** proxy with no `virtualhost` of its own.

In the owning release's root HTTPProxy:

```yaml
includes:
  - name: litellm
    namespace: litellm
    conditions:
      - prefix: /litellm
```

And here:

```yaml
serverRootPath: /litellm      # must match the delegated prefix
routing:
  path: /litellm
  httpProxy:
    enabled: true
    delegated: true
```

`routing.hosts` and `routing.tls` are not needed and are ignored: the child inherits both from the parent, so it needs no certificate of its own. TLS passthrough is rejected, since it is a property of a virtualhost the child does not have.

The generated route matches `/`, not `routing.path`. Contour concatenates the parent's condition with the child's, so repeating the prefix would publish `/litellm/litellm`. `serverRootPath` must still match the delegated prefix, because that is what the proxy itself serves under.

> [!IMPORTANT]
> A child is reachable only while the parent includes it. Delete or reconfigure the parent and Contour reports the child as **orphaned** and ignores it — the release keeps running and serves nothing. `kubectl get httpproxy <name> -o jsonpath='{.status.description}'` is what tells you.

Delegation also makes the mount root useful. The proxy answers its own root with a plain `"LiteLLM: RUNNING"` string, so a browser opening `/litellm` lands on nothing helpful; `requestRedirectPolicy` on an exact match sends it to the Admin UI instead:

```yaml
routing:
  httpProxy:
    extraRoutes:
      - conditions:
          - exact: /
        requestRedirectPolicy:
          path: /litellm/ui/
          statusCode: 302
```

An exact match is what keeps this to the bare prefix — a `prefix` condition would redirect `/litellm/v1/...` as well. This works for a root HTTPProxy too; it is only unavailable on a plain Ingress, where Contour ignores the redirect annotations.

### Route (OpenShift)

```yaml
routing:
  hosts: [litellm.example.com]   # omit to let OpenShift generate one
  tls:
    enabled: true
  route:
    enabled: true
    tls:
      termination: edge
      insecureEdgeTerminationPolicy: Redirect
```

Leave `routing.hosts` empty and the router generates a hostname from the route name, the namespace, and the cluster's apps domain.

A passthrough Route cannot carry a path, so the chart omits `spec.path` when `termination` is `passthrough` and sends the whole host to the proxy.

### Migrating between implementations

Enable both, cut traffic over at DNS, then disable the old one:

```yaml
routing:
  hosts: [litellm.example.com]
  ingress:
    enabled: true          # still serving
    className: nginx
  httpRoute:
    enabled: true          # new path, warming up
    parentRefs:
      - name: eg
```

Both objects point at the same Service, so neither takes the proxy down.

## Sharing a hostname

At the domain root LiteLLM claims `/ui`, `/v1`, `/docs`, `/health`, `/metrics` and more. That is an awkward neighbour for an application that owns the site, and it is the usual reason to deploy this chart as an add-on rather than as the main tenant.

**The chart therefore ships mounted under `/litellm`**, via `serverRootPath`:

```yaml
serverRootPath: /litellm
routing:
  path: /litellm
```

The Admin UI is at `/litellm/ui` and the OpenAI-compatible base URL is `https://<host>/litellm/v1`. Nothing outside the prefix is served, so every root path stays available to the other application.

To claim the domain root instead, clear both:

```yaml
serverRootPath: ""
routing:
  path: /
```

> [!IMPORTANT]
> Point clients at the prefix. With the default, `OPENAI_BASE_URL` is `https://<host>/litellm/v1`; a client configured for `https://<host>/v1` gets a 404 from the proxy rather than a connection error, which tends to read as a missing model.

### API docs

LiteLLM serves the Swagger UI at its **mount root** — upstream's `DOCS_URL` defaults to `/` — so opening the release in a browser lands on the API reference rather than the Admin UI. This chart moves it to `/docs`:

```yaml
docs:
  enabled: true
  path: /docs
```

| | URL with the chart defaults |
| --- | --- |
| Swagger UI | `https://<host>/litellm/docs` |
| Admin UI | `https://<host>/litellm/ui` |

Set `path: /` to restore upstream's behaviour, or `enabled: false` to drop the docs page and the OpenAPI schema together — both, because Swagger reads the schema, and removing one without the other leaves a page that renders an error. A path under `/ui` fails the render, since it would be shadowed by the Admin UI.

> [!NOTE]
> With the docs moved, the mount root itself returns LiteLLM's plain `"LiteLLM: RUNNING"` health string. The proxy has no route that redirects its root to the Admin UI, so link people to `/litellm/ui` directly.

> [!NOTE]
> The health endpoints keep answering at the **root** as well, which is why the probes in this chart are not prefixed. Verified against the image: with `SERVER_ROOT_PATH` set, `/health/readiness` and `/litellm/health/readiness` both return 200 while `/ui` returns 404 and `/litellm/ui` returns 200. The UI's own asset URLs are rewritten by the image at runtime.

The chart fails the render if `routing.path` does not match the prefix, because publishing `/` anyway would defeat the point, and publishing a *different* prefix would serve 404s.

This changes the client-facing API base URL, so existing callers need updating.

## Single sign-on

Signs in to the Admin UI with an OpenID Connect provider instead of the shared master key, through LiteLLM's generic OIDC support.

> [!IMPORTANT]
> SSO is a LiteLLM **enterprise** feature. Since v1.76.0 it is free for up to five users; past that it needs a licence in `license.existingSecret`.

```yaml
sso:
  enabled: true
  clientId: litellm
  authorizationEndpoint: https://idp.example.com/realms/r/protocol/openid-connect/auth
  tokenEndpoint: https://idp.example.com/realms/r/protocol/openid-connect/token
  userinfoEndpoint: https://idp.example.com/realms/r/protocol/openid-connect/userinfo
```

The client secret is generated on first install and reused on every later upgrade, so upgrading never invalidates the provider-side registration. Supply your own with `sso.clientSecret.existingSecret`.

`sso.proxyBaseUrl` is derived from `routing.hosts[0]`, `routing.tls.enabled` and `routing.path` when left empty, including any `serverRootPath` prefix. Deriving it keeps the redirect URI from drifting out of step with the Ingress. The provider must accept `<proxyBaseUrl>/sso/callback`.

### Why the three endpoints are separate

They are not called by the same party, and they are frequently not interchangeable.

| Setting | Called by | Must be reachable from |
| --- | --- | --- |
| `authorizationEndpoint` | the browser | the user's machine |
| `tokenEndpoint` | the proxy pod | inside the cluster |
| `userinfoEndpoint` | the proxy pod | inside the cluster |

A provider published through a cloud load balancer is often unreachable from inside the same cluster, because the load balancer does not hairpin — yet it still advertises its public URL in its discovery document. Copying all three from that document produces a sign-in that redirects correctly and then fails at the token exchange. Point the browser-facing one at the public address and the other two at the in-cluster Service.

### Keycloak bootstrap

`sso.keycloakBootstrap` adds a one-shot Job that configures the Keycloak side to match:

```yaml
sso:
  keycloakBootstrap:
    enabled: true
    url: http://keycloak.identity.svc.cluster.local:8080
    realm: myrealm
    admin:
      existingSecret:
        name: keycloak-admin     # keys: username, password
```

It creates, in an existing realm:

1. A confidential OIDC client with the right redirect URIs, including LiteLLM's `/sso/debug/callback` claim-dumping route.
2. Two **client** roles carrying LiteLLM's own role names — `proxy_admin` and `internal_user` by default.
3. Two groups, `litellm-admins` and `litellm-users`, granted those roles.
4. A protocol mapper putting the client roles into a flat `roles` claim.
5. Optionally an `llmadmin` account in the admin group.

Step 4 is the one that is easy to miss. Keycloak nests client roles under `resource_access.<client>.roles`, which LiteLLM does not read, so without the mapper every user signs in carrying no role at all.

Client roles rather than realm roles, and dedicated groups rather than existing ones, so nothing this chart creates appears at realm scope or changes another application's authorization. Point `groups` at existing group names if you would rather reuse them.

Every step reads before it writes, so the Job is safe to re-run and repairs a half-applied earlier run rather than duplicating it. It never creates realms.

> [!WARNING]
> Realms usually carry a password policy. The generated `llmadmin` password ends in a fixed `Aa1!` so it satisfies the common `upperCase(1) lowerCase(1) digits(1) specialChars(1)` rules by construction — relying on chance would fail roughly one deploy in four hundred. If your policy is stricter, set `sso.keycloakBootstrap.adminUser.password.value`; the Job names the policy in its error output when Keycloak rejects one.

Read the account password with:

```sh
kubectl -n litellm get secret litellm-sso \
  -o jsonpath='{.data.admin-user-password}' | base64 -d
```

## Database

The chart reads database credentials from a Secret only and accepts no inline password.

It emits the discrete `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, and `DATABASE_NAME` variables and lets the proxy assemble and percent-encode the URL. This matters: a password containing `@`, `/`, or `?` corrupts a hand-assembled connection string, and the resulting failure is an opaque Prisma connect error rather than anything that names the password as the cause.

```sh
kubectl -n litellm create secret generic litellm-db \
  --from-literal=username=litellm \
  --from-literal=password='<password>'
```

```yaml
database:
  enabled: true
  host: litellm-pg.example.com
  port: 5432
  name: litellm
  sslMode: verify-full
  existingSecret:
    name: litellm-db
    usernameKey: username
    passwordKey: password
```

Set `database.existingSecret.urlKey` instead to supply a whole connection URL from one Secret key, for parameters the discrete fields cannot express. The discrete host, port, and name are then not emitted.

### Workload identity

For a managed database with IAM authentication, no password is read at all. The proxy mints a token at startup.

```yaml
database:
  auth:
    mode: azureEntra     # or awsIam
serviceAccount:
  create: true
  annotations:
    azure.workload.identity/client-id: <client-id>
```

The Secret is still required for the username. `migrationJob.serviceAccountName` gives the Job its own identity when it needs one distinct from the proxy's.

### TLS to the database

`sslMode: verify-full` with a CA bundle is what a managed PostgreSQL service expects. Mount the bundle and point at it:

```yaml
database:
  sslMode: verify-full
  sslRootCert: /certs/ca.pem
volumes:
  - name: db-ca
    configMap:
      name: rds-ca
volumeMounts:
  - name: db-ca
    mountPath: /certs
    readOnly: true
```

`volumes` and `volumeMounts` are applied to the migration Job as well as the proxy, so migrations verify the certificate on the same terms.

### Connection budget

Each worker opens its own pool, so a pod holds `numWorkers × connection_limit` upstream connections and the total scales with `maxReplicas`, not with the replicas running today. An autoscaler at the default `maxReplicas: 100` can ask for far more connections than a stock PostgreSQL accepts.

Either size `autoscaling.maxReplicas` from what the database can serve, or turn on the in-pod pooler:

```yaml
database:
  connectionPool:
    enabled: true
    maxDbConnections: 20
    maxClientConn: 1000
```

With the pooler a pod holds at most `maxDbConnections` upstream connections however many workers run. Set `database.disablePreparedStatements: true` in front of an external transaction-mode pooler such as PgBouncer or RDS Proxy.

### Read replica

```yaml
database:
  readReplica:
    enabled: true
    host: litellm-pg-reader.example.com
```

Read-only queries go to the replica and writes continue to the writer. Fields left empty fall back to the writer's values, including the credentials Secret.

## Creating the database

Everything above assumes the database, the login role, and the schema already exist — the usual case, because a DBA provisioned them. When they do not, `database.init` adds a one-shot Job that creates them.

It is off by default. Turning it on does not change how the proxy connects; it only adds a step in front.

```yaml
database:
  host: litellm-pg.example.com
  name: litellm
  schema: litellm
  existingSecret:
    name: litellm-db        # keys: username, password

  init:
    enabled: true
    admin:
      existingSecret:
        name: litellm-pg-admin   # keys: username, password
```

### Which credential is which

There are two, and conflating them is the easy mistake:

| | Used by | Lifetime |
| --- | --- | --- |
| `database.existingSecret` | the proxy, every day | permanent |
| `database.init.admin` | this Job, once | erased when the Job succeeds |

`database.existingSecret` is the **input** to the Job, not something it reads back. The Job creates a login role with that username and password, makes it the owner of `database.name` and `database.schema`, and exits. The proxy then authenticates as that role. One Secret, written once by you, used by both.

The admin credential is separate because creating a database and a role needs privileges the proxy must never hold.

### What it runs

Against the maintenance database named by `admin.database` (`postgres` by default, because `CREATE DATABASE` cannot run inside the database being created):

1. `CREATE ROLE` for the service user, or `ALTER ROLE` to reset its password to match the Secret.
2. `CREATE DATABASE` owned by that role.

Then, connected to the new database:

3. `GRANT ALL PRIVILEGES ON DATABASE` to the role.
4. `CREATE SCHEMA ... AUTHORIZATION` the role, and `GRANT ALL ON SCHEMA`.
5. `ALTER ROLE ... SET search_path`, so an interactive `psql` session as that role lands in the right schema.

Each step is skipped when the object already exists, so the Job is safe to re-run. Step 4's `GRANT` runs even on an existing schema: PostgreSQL 15 stopped granting `CREATE` on `public` to everyone, and without it `prisma migrate deploy` fails with `permission denied for schema`.

Turn individual steps off with `createDatabase`, `createUser`, and `createSchema` when a DBA has already done part of the work.

### Password rotation

The `ALTER ROLE` in step 1 is unconditional, so changing the password in `database.existingSecret` and upgrading resets the role to match. Without that, rotating the Secret would leave the proxy unable to log in until someone fixed the role by hand.

### Erasing the admin credentials

With inline `admin.username` / `admin.password`, the chart renders a Secret, the Job uses it, and a second container erases both keys from it the moment the Job succeeds.

The ordering is structural rather than best-effort. The `psql` step is an **init container** and the cleanup is the **only ordinary container**, so Kubernetes will not start the cleanup until the init container has exited 0. A failed initialization therefore never reaches the erase step, and the credentials survive for the retry.

The erase is a JSON merge patch setting both keys to `null`. That removes them whether or not they are still there, which makes it idempotent with no conditional logic — and that in turn is what lets it invoke `kubectl` directly, with no shell. The upstream `registry.k8s.io/kubectl` image is distroless and has no `/bin/sh`, so a shell script here would not run at all.

The Secret object itself is kept, with its data keys gone. The Role carries `get` and `patch` on that one Secret name and deliberately no `delete`, so this chart never creates a Role that could delete Secrets in your namespace.

> [!IMPORTANT]
> Erasing the Kubernetes Secret does not remove an inline password from the **Helm release secret**, which `helm get values` can read. It is also restored for the length of the hook window on every upgrade, because re-running the Job needs it.
>
> To keep the admin password out of the release entirely, create the Secret yourself and name it under `admin.existingSecret`. The chart then modifies nothing — it only destroys what it created — and rotating that Secret afterwards is yours to do.

The cleanest sequence for a one-time bootstrap is therefore: install with `init.enabled: true`, confirm the Job succeeded, then set `init.enabled: false` for every later upgrade.

### Ordering

The Job is a Helm hook at weight `-5`, ahead of the migration Job at `1`. The chart rejects a weight that is not below the migration's, because the failure it prevents surfaces as a confusing Prisma error about a database that does not exist rather than as a misconfigured value.

Under a GitOps controller, turn `hooks.helm.enabled` off and `hooks.argocd.enabled` on; the sync waves keep the same order.

The wave is the hook weight. They express the same thing in two dialects, so the
chart does not ask for both — there is no `syncWave` value to keep in step with
the weight beside it.

A wave is only meaningful relative to everything else in the same ArgoCD
Application, which the chart cannot see: how the surrounding Applications are
numbered, or whether the database is provisioned by this chart at all. Where the
defaults do not fit, set the annotation directly — it is applied after the
chart's own and so takes precedence:

```yaml
migrationJob:
  annotations:
    argocd.argoproj.io/sync-wave: "12"
```

### Ordinary failures

- **`password authentication failed`** for the admin user: `admin.username` is not a login that may `CREATE DATABASE` and `CREATE ROLE`. On a managed service this is the server administrator, not `postgres`.
- **The Job waits and then times out**: the server is not reachable from the cluster. `waitTimeout` bounds this at 300 seconds.
- **`permission denied to create database`**: the admin user exists but lacks `CREATEDB`.

Read what it actually did:

```sh
kubectl -n litellm logs job/litellm-db-init -c db-init
```

## Redis

Redis is the proxy's coordination store: cross-pod rate limits, spend tracking, and the pod lock manager that elects a single owner for shared background jobs.

```yaml
redis:
  host: litellm-redis.example.com
  port: 6379
  existingSecret:
    name: litellm-redis
    passwordKey: password
```

The chart wires `REDIS_HOST`, `REDIS_PORT`, and `REDIS_PASSWORD`, and renders a `general_settings.coordination_redis` block. A `coordination_redis` block you write in `proxyConfig` always wins. Set `redis.coordination: false` to wire only the environment variables, for example when Redis is there for response caching alone.

> [!WARNING]
> Without Redis, rate limits and spend counters are per-pod. A `tpm` budget is then enforced at roughly `replicaCount` times what you configured, and budget resets run once per pod instead of once. The chart prints this warning on install whenever `replicaCount` is above one or autoscaling is on and `redis.host` is unset.

For Sentinel, set `redis.sentinel.enabled` and `redis.sentinel.masterSet`; the coordination block is then rendered with `sentinel_nodes` and `service_name` instead of host and port.

## Migration Job

In the database flow the chart runs `prisma migrate deploy` in a Job ahead of the proxy, and starts the proxy with `DISABLE_SCHEMA_UPDATE=true` for as long as that Job owns the schema. Without this, every replica races to push the schema on every rollout.

`DISABLE_SCHEMA_UPDATE` is emitted last in both workloads, after `envVars` and `extraEnvVars`, so a user-supplied value cannot silently shadow it under last-wins duplicate-environment semantics.

> [!IMPORTANT]
> A Job's pod template is immutable, so a stable-named Job cannot be updated in place: the first `helm upgrade` that changes the image tag or any environment variable would be rejected by the API server. `migrationJob.hooks.helm.enabled` is on by default and deletes and recreates the Job ahead of each install and upgrade, which is what makes repeated upgrades work.

Under a GitOps controller that runs the Job itself, turn the Helm hook off and `migrationJob.hooks.argocd.enabled` on. Running both migrates twice.

`migrationJob.activeDeadlineSeconds` defaults to 1800 and is a wall-clock budget for the whole Job, shared across every retry. Without it a migration blocked on a lock never fails, and a release waiting on the hook never returns.

## Secrets

### Master key

The master key authenticates admin API calls and is the Admin UI password.

It is generated once as `sk-...` on first install and stored in `<release>-masterkey`. Every later upgrade reads the value back out of the live Secret, so upgrading never rotates the key and never invalidates the virtual keys derived from it.

```sh
kubectl -n litellm get secret litellm-masterkey \
  -o jsonpath='{.data.masterkey}' | base64 -d
```

Point `masterKey.existingSecret.name` at a Secret you manage to take it over. The chart then renders no Secret of its own, which is the right choice when an external secrets operator owns the namespace.

`masterKey.value` sets it inline. It ends up in the Helm release secret in plain text, so prefer `existingSecret` outside development.

### License and UI login

```yaml
license:
  existingSecret:
    name: litellm-license   # key: license
ui:
  credentialsSecret:
    name: litellm-ui        # keys: username, password
```

Without `ui.credentialsSecret` the Admin UI is reached with the master key, which means sharing the credential that also authorises every admin API call.

## Scaling and availability

```yaml
replicaCount: 3
numWorkers: "1"
resources:
  requests:
    cpu: "1"
    memory: 4Gi
  limits:
    cpu: "1"
    memory: 4Gi
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 60
pdb:
  enabled: true
  maxUnavailable: 1
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: litellm
```

`resources` is unset by default so the chart installs on a small cluster, and so an upgrade never leaves a pod Pending. Production should set it. One worker at database-connected steady state needs roughly 1 CPU and 4Gi, and both scale with `numWorkers`.

4Gi is a floor rather than a target. The Prisma query engine's resident memory is a high-water mark that grows to the largest statement it has ever run and is not returned to the OS, so a pod's floor ratchets up to its worst-ever write. Provision below that and one large write is enough to get the pod OOM-killed, which surfaces as a crash loop under traffic that looks unremarkable on every other metric.

One worker per pod is the right default on Kubernetes: it keeps the HPA reading CPU against a single process and makes rolling restarts drain cleanly.

> [!NOTE]
> `autoscaling.targetMemoryUtilizationPercentage` is deliberately unset. For the same high-water-mark reason, a memory target reads the largest write a pod ever did rather than its current load, so replicas ratchet up after one large write and never scale back in. Scale on CPU, or on the per-pod request and token metrics.

60 percent rather than something higher because a new replica is not useful the moment it is created: the startup probe allows up to 300 seconds. A target that only trips near saturation adds capacity minutes after it was needed.

`targetRequestsPerSecond` and `targetTokensPerSecond` render `autoscaling/v2` Pods metrics on the proxy's own counters. Both need a Prometheus Adapter serving those names on `custom.metrics.k8s.io`.

### Graceful shutdown

```yaml
terminationGracePeriodSeconds: 90
lifecycle:
  preStop:
    httpGet:
      path: /health/drain
      port: 4000
      httpHeaders:
        - name: X-Drain-Token
          value: <same value as drain_endpoint_token>
proxyConfig:
  general_settings:
    enable_drain_endpoint: true
    drain_endpoint_token: <token>
```

`/health/drain` marks the pod NotReady and blocks only until in-flight requests actually finish, instead of the fixed `sleep` that a preStop hook usually contains. Keep `terminationGracePeriodSeconds` a few seconds above `GRACEFUL_SHUTDOWN_TIMEOUT` (30 by default) to leave room for teardown before SIGKILL.

## Observability

```yaml
metricsServer:
  enabled: true
  port: 4001
serviceMonitor:
  enabled: true
  interval: 15s
proxyConfig:
  litellm_settings:
    callbacks: ["prometheus"]
```

`metricsServer` moves Prometheus `/metrics` onto a separate process and port with its own ClusterIP Service, so a scrape never lands on an inference worker. The ServiceMonitor then scrapes that Service instead of the proxy port.

> [!CAUTION]
> The proxy port serves `/metrics` behind virtual-key auth and answers an unauthenticated scrape with 401, so enable `metricsServer` whenever `serviceMonitor` is on. The metrics port itself carries no auth: keep it off public routing. The chart rejects a metrics port equal to the service port.

For production logging, turn the proxy's own verbosity down and emit structured logs:

```yaml
logLevel: ERROR
proxyConfig:
  litellm_settings:
    set_verbose: false
    json_logs: true
```

## Running read-only

`readOnlyRootFilesystem` is supported. The image writes to the filesystem on startup, so the chart adds emptyDir volumes for `/tmp`, `/.cache`, and `/.npm` automatically when you enable it:

```yaml
securityContext:
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
envVars:
  LITELLM_MIGRATION_DIR: /tmp/migrations
  PRISMA_BINARY_CACHE_DIR: /tmp/prisma
  XDG_CACHE_HOME: /tmp/cache
```

The same volumes are added to the migration Job. The environment variables above point the components that still need a writable path at the emptyDir.

## Values reference

Defaults are the shipped `values.yaml`. Every value is validated by `values.schema.json`, which rejects unknown keys, so a typo is caught at install time rather than ignored.

### Model management

| Key | Description | Default |
| --- | --- | --- |
| `modelManagement.mode` | `config` or `database` | `config` |
| `modelManagement.seedFromConfig` | Also render `models` into config.yaml in database mode | `false` |
| `models` | Model catalog, appended to `proxyConfig.model_list` | one mock model |
| `proxyConfig` | The rest of config.yaml, rendered verbatim | `{general_settings: {}}` |
| `config.existingConfigMap.name` | Mount this ConfigMap instead of rendering one | `""` |
| `config.existingConfigMap.key` | Key holding the config file | `config.yaml` |
| `config.mountPath` | In-container path of the config file | `/etc/litellm/config.yaml` |

### Workload

| Key | Description | Default |
| --- | --- | --- |
| `replicaCount` | Proxy replicas, ignored when autoscaling is on | `1` |
| `numWorkers` | Passed as `--num_workers`; empty lets the image decide | `""` |
| `listen` | Bind address inside the pod | `0.0.0.0` |
| `serverRootPath` | Prefix the proxy is mounted under; `""` claims the root | `/litellm` |
| `trustedProxies` | Senders whose `X-Forwarded-*` headers are believed | `["*"]` |
| `docs.enabled` | Serve the Swagger UI and the OpenAPI schema | `true` |
| `docs.path` | Path for the Swagger UI; `/` is upstream's mount root | `/docs` |
| `image.repository` | Proxy image | `ghcr.io/berriai/litellm` |
| `image.tag` | Empty follows `appVersion` | `""` |
| `image.pullPolicy` | | `IfNotPresent` |
| `imagePullSecrets` | | `[]` |
| `serviceAccount.create` | Needed only for a cloud IAM binding | `false` |
| `serviceAccount.annotations` | Where the IAM binding goes | `{}` |
| `resources` | Requests and limits; set these in production | `{}` |
| `strategy` | Deployment update strategy | `{}` |
| `terminationGracePeriodSeconds` | | `90` |
| `topologySpreadConstraints` | | `[]` |
| `nodeSelector`, `tolerations`, `affinity` | | `{}`, `[]`, `{}` |
| `podSecurityContext`, `securityContext` | | `{}` |
| `lifecycle` | Prefer the `/health/drain` preStop hook | `{}` |
| `volumes`, `volumeMounts` | Also applied to the migration Job | `[]` |
| `extraContainers`, `extraInitContainers` | Run through `tpl` | `[]` |
| `command`, `args` | Override the image entrypoint | `[]` |
| `deploymentAnnotations`, `deploymentLabels` | | `{}` |
| `podAnnotations`, `podLabels` | `podLabels` cannot set a selector key | `{}` |
| `commonLabels`, `commonAnnotations` | Applied to every rendered object | `{}` |

### Environment and secrets

| Key | Description | Default |
| --- | --- | --- |
| `environmentSecrets` | Secret names mounted wholesale as env vars | `[]` |
| `environmentConfigMaps` | ConfigMap names mounted wholesale as env vars | `[]` |
| `logLevel` | Sets `LITELLM_LOG`; `""` to source it elsewhere | `INFO` |
| `envVars` | Plain key/value env entries | `{}` |
| `extraEnvVars` | Full Kubernetes EnvVar list, for `valueFrom` | `[]` |
| `masterKey.value` | Inline key; prefer `existingSecret` | `""` |
| `masterKey.existingSecret.name` | Take over the master key Secret | `""` |
| `license.existingSecret.name` | Enterprise license, into `LITELLM_LICENSE` | `""` |
| `ui.credentialsSecret.name` | Admin UI login | `""` |

### Service and probes

| Key | Description | Default |
| --- | --- | --- |
| `service.type` | | `ClusterIP` |
| `service.port` | Also the in-pod listen port | `4000` |
| `service.annotations` | | `{}` |
| `service.loadBalancerClass` | LoadBalancer only | `""` |
| `service.loadBalancerSourceRanges` | LoadBalancer only | `[]` |
| `metricsServer.enabled` | Separate metrics process and Service | `false` |
| `metricsServer.port` | Must differ from `service.port` | `4001` |
| `serviceMonitor.enabled` | Needs the Prometheus operator CRDs | `false` |
| `serviceMonitor.interval`, `.scrapeTimeout` | | `15s`, `10s` |
| `livenessProbe.*` | `/health/liveliness` | see values.yaml |
| `readinessProbe.*` | `/health/readiness` | see values.yaml |
| `startupProbe.*` | Allows up to 300s to first ready | see values.yaml |

### Routing

| Key | Description | Default |
| --- | --- | --- |
| `routing.hosts` | Hostnames; required for `ingress` and `httpProxy` | `[]` |
| `routing.path` | Published prefix; must match `serverRootPath` | `/litellm` |
| `routing.tls.enabled` | | `false` |
| `routing.tls.secretName` | `kubernetes.io/tls` Secret | `""` |
| `routing.annotations`, `routing.labels` | Merged into every routing object | `{}` |
| `routing.ingress.enabled` | | `false` |
| `routing.ingress.className` | | `""` |
| `routing.ingress.pathType` | Auto-downgraded for a dotted path on nginx | `Prefix` |
| `routing.ingress.extraPaths` | Further paths per host | `[]` |
| `routing.httpRoute.enabled` | | `false` |
| `routing.httpRoute.parentRefs` | Required; the Gateways to attach to | `[]` |
| `routing.httpRoute.matches`, `.filters`, `.timeouts` | Passed through | `[]`, `[]`, `{}` |
| `routing.httpRoute.extraRules` | Appended after the generated rule | `[]` |
| `routing.httpProxy.enabled` | | `false` |
| `routing.httpProxy.delegated` | Render a child proxy for a parent that includes it | `false` |
| `routing.httpProxy.ingressClassName` | | `""` |
| `routing.httpProxy.tls.*` | Falls back to `routing.tls.secretName` | see values.yaml |
| `routing.httpProxy.timeoutPolicy`, `.retryPolicy`, `.loadBalancerPolicy` | Contour policies | `{}` |
| `routing.httpProxy.conditions`, `.extraRoutes`, `.includes` | | `[]` |
| `routing.route.enabled` | | `false` |
| `routing.route.tls.termination` | `edge`, `reencrypt`, or `passthrough` | `edge` |
| `routing.route.tls.insecureEdgeTerminationPolicy` | | `Redirect` |
| `routing.route.wildcardPolicy` | | `None` |

### Single sign-on

| Key | Description | Default |
| --- | --- | --- |
| `sso.enabled` | Sign in to the Admin UI with OIDC. Enterprise; free to five users | `false` |
| `sso.proxyBaseUrl` | Browser-facing URL; derived from `routing` when empty | `""` |
| `sso.clientId` | | `litellm` |
| `sso.scope` | | `openid profile email` |
| `sso.clientState`, `.usePkce` | Required by some providers | `""`, `false` |
| `sso.authorizationEndpoint` | Browser-facing; must be publicly reachable | `""` |
| `sso.tokenEndpoint`, `.userinfoEndpoint` | Called by the pod; may be in-cluster | `""` |
| `sso.logoutUrl` | | `""` |
| `sso.clientSecret.value` | Generated on first install when empty | `""` |
| `sso.clientSecret.existingSecret.name` | Use a Secret you manage | `""` |
| `sso.keycloakBootstrap.enabled` | Configure the Keycloak side automatically | `false` |
| `sso.keycloakBootstrap.url` | Admin API base URL, reachable in-cluster | `""` |
| `sso.keycloakBootstrap.realm` | Must already exist; the Job creates no realms | `""` |
| `sso.keycloakBootstrap.admin.existingSecret.name` | Required. Keycloak administrator | `""` |
| `sso.keycloakBootstrap.admin.realm` | Realm holding the admin account | `master` |
| `sso.keycloakBootstrap.roles.admin`, `.user` | Must be names LiteLLM recognises | `proxy_admin`, `internal_user` |
| `sso.keycloakBootstrap.groups.admin`, `.user` | Groups granted those roles | `litellm-admins`, `litellm-users` |
| `sso.keycloakBootstrap.adminUser.enabled` | Create a named administrator account | `true` |
| `sso.keycloakBootstrap.adminUser.username` | | `llmadmin` |
| `sso.keycloakBootstrap.adminUser.password.value` | Generated when empty | `""` |
| `sso.keycloakBootstrap.adminUser.permanentPassword` | False forces a change at first sign-in | `true` |
| `sso.keycloakBootstrap.extraRedirectUris` | Beyond the two the chart registers | `[]` |
| `sso.keycloakBootstrap.image.*` | Needs `kcadm.sh`; match the server's minor version | `quay.io/keycloak/keycloak:26.3.2` |
| `sso.keycloakBootstrap.waitTimeout` | Seconds to wait for Keycloak | `300` |
| `sso.keycloakBootstrap.hooks.helm.weight` | Runs after the database Jobs | `"2"` |

### Database

| Key | Description | Default |
| --- | --- | --- |
| `database.enabled` | Forced on by `modelManagement.mode: database` | `false` |
| `database.host`, `.port`, `.name`, `.schema` | | `""`, `5432`, `litellm`, `""` |
| `database.sslMode` | `verify-full` for a managed service | `""` |
| `database.sslRootCert` | In-container path to a CA bundle | `""` |
| `database.auth.mode` | `password`, `awsIam`, or `azureEntra` | `password` |
| `database.existingSecret.name` | Required; no inline password is accepted | `""` |
| `database.existingSecret.usernameKey`, `.passwordKey` | | `username`, `password` |
| `database.existingSecret.urlKey` | Whole URL from one key | `""` |
| `database.existingSecret.hostKey` | Host from a Secret key | `""` |
| `database.readReplica.enabled` | Route read-only queries to a replica | `false` |
| `database.readReplica.host`, `.port` | Empty falls back to the writer | `""` |
| `database.connectionPool.enabled` | In-pod PgBouncer, transaction mode | `false` |
| `database.connectionPool.maxDbConnections` | Upstream cap per pod | `20` |
| `database.connectionPool.maxClientConn` | | `1000` |
| `database.disablePreparedStatements` | Required in front of an external pooler | `false` |
| `database.maxIdleConnectionLifetime` | Seconds; the proxy defaults to 60 | `""` |

### Creating the database

| Key | Description | Default |
| --- | --- | --- |
| `database.init.enabled` | Create the database, role, and schema before anything else runs | `false` |
| `database.init.admin.username` | Administrator login. Recorded in the Helm release secret | `""` |
| `database.init.admin.password` | Administrator password. Recorded in the Helm release secret | `""` |
| `database.init.admin.existingSecret.name` | Read the admin credentials from a Secret you own. The chart then erases nothing | `""` |
| `database.init.admin.existingSecret.usernameKey`, `.passwordKey` | | `username`, `password` |
| `database.init.admin.database` | Maintenance database to connect to for `CREATE DATABASE` | `postgres` |
| `database.init.admin.sslMode` | Falls back to `database.sslMode` | `""` |
| `database.init.createDatabase` | | `true` |
| `database.init.createUser` | Create the login role, and reset its password to match the Secret | `true` |
| `database.init.createSchema` | Needs a non-empty `database.schema` | `true` |
| `database.init.cleanup` | Erase the admin credentials from the Secret the chart created | `true` |
| `database.init.waitTimeout` | Seconds to wait for the server to accept connections | `300` |
| `database.init.image.*` | Needs `psql` and `pg_isready` | `postgres:17-alpine` |
| `database.init.kubectlImage.*` | Cleanup container only | `registry.k8s.io/kubectl:v1.34.0` |
| `database.init.serviceAccount.create` | ServiceAccount, Role, and RoleBinding for the cleanup container | `true` |
| `database.init.hooks.helm.weight` | Must be below `migrationJob.hooks.helm.weight`. Also used as the ArgoCD sync wave | `"-5"` |
| `database.init.hooks.argocd.enabled` | | `false` |
| `database.init.backoffLimit`, `.ttlSecondsAfterFinished`, `.activeDeadlineSeconds` | | `4`, `120`, `900` |
| `database.init.resources`, `.nodeSelector`, `.tolerations`, `.affinity` | | `{}` |
| `database.init.podSecurityContext`, `.securityContext` | | `{}` |

### Redis

| Key | Description | Default |
| --- | --- | --- |
| `redis.host`, `.port` | | `""`, `6379` |
| `redis.existingSecret.name`, `.passwordKey` | | `""`, `password` |
| `redis.sentinel.enabled`, `.masterSet` | | `false`, `mymaster` |
| `redis.coordination` | Render `general_settings.coordination_redis` | `true` |

### Migration Job

| Key | Description | Default |
| --- | --- | --- |
| `migrationJob.enabled` | | `true` |
| `migrationJob.hooks.helm.enabled` | Required for repeated upgrades | `true` |
| `migrationJob.hooks.helm.weight` | | `"1"` |
| `migrationJob.hooks.argocd.enabled` | Turn on only with the Helm hook off | `false` |
| `migrationJob.backoffLimit` | | `4` |
| `migrationJob.activeDeadlineSeconds` | Whole-Job budget; `null` to disable | `1800` |
| `migrationJob.ttlSecondsAfterFinished` | | `120` |
| `migrationJob.serviceAccountName` | For a Job-specific cloud identity | `""` |
| `migrationJob.resources` | | `{}` |
| `migrationJob.extraContainers`, `.extraInitContainers` | | `[]` |

### Scaling

| Key | Description | Default |
| --- | --- | --- |
| `autoscaling.enabled` | | `false` |
| `autoscaling.minReplicas`, `.maxReplicas` | `maxReplicas` sets the DB connection budget | `1`, `100` |
| `autoscaling.targetCPUUtilizationPercentage` | | `60` |
| `autoscaling.targetMemoryUtilizationPercentage` | Deliberately unset; see above | `""` |
| `autoscaling.targetRequestsPerSecond`, `.targetTokensPerSecond` | Need a Prometheus Adapter | `""` |
| `autoscaling.behavior` | | `{}` |
| `pdb.enabled` | | `false` |
| `pdb.minAvailable`, `.maxUnavailable` | Set exactly one | `null` |
| `extraResources` | Extra manifests, run through `tpl` | `[]` |

## Validation

The chart fails the render, naming the value, rather than producing a workload that cannot start. A template-time error is readable; the same mistake found at runtime is an opaque CrashLoopBackOff or a route that silently publishes nothing.

| Condition | Why it fails |
| --- | --- |
| `config` mode with no models | The proxy needs at least one model to start |
| `seedFromConfig` in `config` mode | Every model is already in config.yaml; the value would do nothing |
| Database flow with no credentials Secret | Credentials come from a Secret only |
| Unknown `database.auth.mode` | Caught by the schema before templates render |
| `httpRoute` with no `parentRefs` | A route with no parent attaches to no Gateway |
| `ingress` or `httpProxy` with no hosts | Would publish nothing |
| TLS enabled with no certificate Secret | Would serve the controller's default certificate |
| More than one host on `httpProxy` or `route` | Both carry exactly one |
| `metricsServer.port` equal to `service.port` | The container cannot bind both |
| `image.tag` of `latest` or `main-latest` | Splits the proxy and the migration Job across versions |
| `podLabels` setting a selector key | The Deployment selector is immutable; the apply would be rejected |
| `pdb` with neither or both bounds | Ambiguous |
| `autoscaling.minReplicas` above `maxReplicas` | Cannot be satisfied |
| `database.init` with no admin credentials, or with two sources for them | Nothing to authenticate as, or ambiguity about which gets erased |
| `database.init` under `awsIam` or `azureEntra` | The cloud issues the login, so there is no password to set on a role |
| `database.init` with `existingSecret.urlKey` | A connection URL carries no separate user to create |
| `database.init.createSchema` with an empty `database.schema` | Nothing to create |
| `database.init` hook weight at or above the migration's | The migration would run before the database exists |
| `serverRootPath` with `routing.path: /` | The release would still claim the whole host |
| `serverRootPath` and `routing.path` disagreeing | The published prefix would return 404 |
| `sso.enabled` with no host and no `proxyBaseUrl` | There is no redirect URI to register |
| `sso.proxyBaseUrl` without a scheme | Providers reject such a `redirect_uri` |
| `keycloakBootstrap` with no admin Secret | Nothing to authenticate to Keycloak as |
| `keycloakBootstrap` roles outside LiteLLM's own set | The role is ignored and users get no privileges |
| `keycloakBootstrap` admin and user groups the same | One group cannot carry two roles |
| `keycloakBootstrap` without `sso.enabled` | It would register a client nothing uses |

## Upgrading

```sh
helm diff upgrade litellm helm-charts/litellm -n litellm -f my-values.yaml
helm upgrade litellm helm-charts/litellm -n litellm -f my-values.yaml
```

The master key is never rotated by an upgrade, so virtual keys survive. In the database flow the migration Job runs first, as a pre-upgrade hook, and the release waits on it.

To move to a new LiteLLM release, bump `appVersion` in `Chart.yaml` rather than setting `image.tag`. That keeps the proxy and the migration Job on one version by construction.

Read the upstream release notes before crossing a minor version. Migrations are one-way, and rolling the chart back does not roll the schema back.

## Troubleshooting

**Pods crash-loop straight after install.** Check `kubectl -n litellm logs deploy/litellm`. A bad `proxyConfig` shows as a startup parse error naming the key. In the database flow, check the migration Job first: `kubectl -n litellm logs job/litellm-migrations`.

**`helm upgrade` hangs.** Usually the migration Job waiting on a database lock. `migrationJob.activeDeadlineSeconds` bounds this at 1800 seconds by default; if it was set to `null`, the release waits forever.

**Rate limits allow more than configured.** `redis.host` is unset and each pod is counting on its own. See [Redis](#redis).

**Streaming responses are truncated.** A timeout at the routing layer. See the timeout guidance for [your implementation](#routing).

**The Admin UI shows no models in database mode.** The catalog is in the database, not in `config.yaml`. An empty list is expected on a fresh install; add models through the UI or `POST /model/new`.

**Model changes do not take effect in config mode.** Confirm the ConfigMap changed and the pods rolled. The pod template carries `checksum/config`, so a real change always restarts the pods; no restart means the rendered config was identical.

**A routing object exists but nothing serves.** Check the controller accepted it:

```sh
kubectl -n litellm get httproute litellm -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")]}'
kubectl -n litellm get httpproxy litellm -o jsonpath='{.status.currentStatus}'
kubectl -n litellm describe ingress litellm
```

## Development

```sh
helm lint helm-charts/litellm --strict
helm unittest helm-charts/litellm
bash helm-charts/litellm/ci/validate.sh
helm package helm-charts/litellm --destination /tmp
```

`tests/` holds per-template assertions. `ci/validate.sh` holds whole-release render checks, where the question is which objects exist together: both flows, every routing implementation, and that the proxy and the migration Job agree on one image. `.github/workflows/helm-charts.yml` runs all of it for every chart under `helm-charts/`, discovering them by listing the directory.

> [!NOTE]
> Pass `--kube-version` to any `helm template` you run by hand. Helm 3 and Helm 4 assume different Kubernetes versions when no cluster is reachable, which changes whether this chart's `kubeVersion` constraint is met.

For schema validation:

```sh
helm template litellm helm-charts/litellm -n litellm --kube-version 1.31.0 | \
  helm kubeconform --summary --ignore-missing-schemas -f - helm-charts/litellm
```

The three CRD-based routing objects are skipped unless you pass `--schema-location` for their schemas.

## Not included

- **A bundled PostgreSQL or Redis subchart.** See [Prerequisites](#prerequisites). `database.init` creates a database *on* a server you run; it does not run the server.
- **The split gateway / backend / UI deployment** from the upstream `helm/litellm` chart. One Deployment keeps the baseline at one pod and avoids path-prefix dispatch that has to track the image's route allowlist. The templates carry `app.kubernetes.io/component` labels and per-component helpers, so the split can be added later without breaking any existing value path.
- **KEDA autoscaling.** The HPA covers CPU and the two per-pod workload metrics.
- **Enterprise billable-request metering.**
