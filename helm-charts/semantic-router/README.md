# Semantic Router Helm Chart

Puts the [vLLM Semantic Router](https://github.com/vllm-project/semantic-router) in front of LiteLLM, so that a client can ask for one virtual model â€” `vllm-sr/auto` â€” and have the router pick the real one.

```text
client â”€â”€â–¶ Envoy â”€â”€â–¶ LiteLLM â”€â”€â–¶ KServe / external providers
            â”‚  â–²
            â–¼  â”‚ gRPC :50051 (ext_proc)
     Semantic Router  â—€â”€â”€ :8080 management API â”€â”€ model controller
```

Envoy terminates the OpenAI API and hands every chat request to the router over Envoy's external-processing (`ext_proc`) protocol. The router classifies the prompt, rewrites the `model` field, and Envoy forwards the result to LiteLLM. Guards (jailbreak, PII) run inside the router, before LiteLLM is reached.

The caller's `Authorization` header is **not** touched, so LiteLLM still applies the budgets, model permissions, response cache and Langfuse logging that belong to that key â€” on the model the router selected. That property is the point of this deployment, and it is also the easiest one to break; see [The Authorization pass-through](#the-authorization-pass-through).

## Contents

- [Prerequisites](#prerequisites)
- [Install](#install)
- [Versions](#versions)
- [What this chart adds](#what-this-chart-adds)
- [The Authorization pass-through](#the-authorization-pass-through)
- [The LiteLLM backend URL](#the-litellm-backend-url)
- [How the router config is assembled](#how-the-router-config-is-assembled)
- [Who owns routing policy](#who-owns-routing-policy)
- [Guards](#guards)
- [Semantic cache](#semantic-cache)
- [The Envoy data plane](#the-envoy-data-plane)
- [Publishing the entrypoint](#publishing-the-entrypoint)
- [Management API and NetworkPolicy](#management-api-and-networkpolicy)
- [Storage and first start](#storage-and-first-start)
- [Scaling](#scaling)
- [Observability](#observability)
- [Values reference](#values-reference)
- [Validation](#validation)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Not included](#not-included)

## Prerequisites

| Requirement | Why |
| --- | --- |
| Kubernetes 1.25+ | `policy/v1` PodDisruptionBudget, `networking.k8s.io/v1` NetworkPolicy. |
| A LiteLLM release | The router rewrites a model name; LiteLLM is what serves it. The [`litellm`](../litellm) chart in this repository is the one this chart is written against. |
| A default StorageClass | The router downloads ~1.2 GB per classifier checkpoint on first start. |
| A CNI that enforces NetworkPolicy | Otherwise the policy this chart renders is accepted and ignored, and `:8080` is open to the namespace. |
| Gateway API / Contour / OpenShift CRDs | Only for the matching publishing mode. |

The router wants about 1 CPU and 3 GiB to idle, and up to 2 CPU / 7 GiB while it loads classifiers (upstream's defaults, left alone). Envoy wants a fraction of that.

## Install

```sh
helm dependency build helm-charts/semantic-router
helm upgrade --install semantic-router helm-charts/semantic-router \
  --namespace llm --create-namespace \
  --set global.semanticRouter.litellm.releaseName=litellm
```

Then point a client at the Envoy Service and ask for the virtual model:

```sh
kubectl -n llm port-forward svc/semantic-router-envoy 8080:8080

curl http://localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer sk-your-litellm-virtual-key" \
  -H 'Content-Type: application/json' \
  -d '{"model":"vllm-sr/auto","messages":[{"role":"user","content":"Prove that sqrt(2) is irrational"}]}'
```

The first start takes a while: the router downloads its embedding and classifier models before it reports ready. `kubectl -n llm logs -f deploy/semantic-router` shows the progress.

## Versions

| | |
| --- | --- |
| Chart version | 0.1.0 |
| App version | `v0.4.0` (the upstream Semantic Router release everything here was verified against) |
| Subchart | `oci://ghcr.io/vllm-project/charts/semantic-router` **0.4.0**, digest `sha256:86e495f7â€¦` |
| Envoy | `docker.io/envoyproxy/envoy:distroless-v1.35.3` |

Upstream's documentation disagrees with itself about the chart version â€” the `Chart.yaml` committed at the `v0.4.0` application tag says `0.2.0`, and the install snippets use both `0.4.0` and `0.0.0-latest`. The registry is the authority:

```sh
$ helm show chart oci://ghcr.io/vllm-project/charts/semantic-router
Pulled: ghcr.io/vllm-project/charts/semantic-router:0.4.0
Digest: sha256:86e495f70a418c50a1255145e14d67ae99b2b58ecf2a07caa4e81995e0b2e889
version: 0.4.0
appVersion: v0.4.0
```

The dependency is pinned to that exact version rather than a range. A release should render the same bytes in six months as it does today, and `helm dependency update` is a deliberate act that moves the pin and rewrites `Chart.lock` in the same commit. That matters more here than in most wrappers, because this chart [redefines one of the subchart's templates](#how-the-router-config-is-assembled).

## What this chart adds

The router workload, its Services, PVC and RBAC all come from the upstream subchart. This chart adds:

| Object | Why it is here and not upstream |
| --- | --- |
| Envoy Deployment + ConfigMap | Upstream ships an `ext_proc` server and example Envoy configs, but no Envoy. This one runs non-root with a read-only root filesystem, buffers the request body, streams the response, and fails closed. |
| Envoy Service (+ a stats Service) | The release entrypoint. The stats port is kept off it. |
| Ingress / HTTPRoute / HTTPProxy / Route | The same four publishing modes, in the same shape, as the `litellm` chart. |
| NetworkPolicy | `:50051` for Envoy, `:8080` for the model controller, `:9190` for Prometheus. |
| Management API token Secret | Upstream defaults the management API to `auth.mode: disabled`. |
| ServiceMonitors | For Envoy's stats and for the router's own metrics port, which upstream ships no ServiceMonitor for. |
| The seed router config | Including the LiteLLM backend URL, the guards, and the management API auth block â€” none of which upstream can know. |

## The Authorization pass-through

This is the security linchpin of the whole design, and it works **by omission**.

The router resolves a credential for the backend it is about to call. With no `access_key`, no `api_key`, no `api_key_env` and no custom `global.services.authz.providers`, it finds none, leaves the `Authorization` header alone, and LiteLLM sees the end user's virtual key.

Setting a key on the backend ref does not "add" authentication. It **replaces** every caller's `Authorization` with one shared static credential, so every request arrives at LiteLLM as the same principal and every per-key budget, rate limit, model permission and spend attribution collapses into one. There is no named "pass-through" flag to turn on instead.

The chart therefore refuses to render a config that carries one:

```console
$ helm template â€¦ --set 'semantic-router.configOverride.providers.models[0].backend_refs[0].access_key=shared'
Error: backend ref "litellm" in semantic-router.configOverride sets "access_key". The router
passes the CALLER's Authorization header to LiteLLM only while it has no credential of its
own; setting one overwrites every caller's key with a single shared credential and collapses
LiteLLM's per-key budgets, model permissions and spend attribution into one principal.
```

`global.services.authz` is refused for the same reason: adding a provider flips the credential resolver's `fail_open` default and starts rewriting the header. If you ever need one, set `fail_open` explicitly and update the assertions in `ci/validate.sh` and `tests/router-config_test.yaml`, which exist precisely so this cannot drift unnoticed.

## The LiteLLM backend URL

A backend ref's `base_url` **replaces** the OpenAI protocol's canonical base path rather than prefixing it, and the protocol then appends `/chat/completions`. The litellm chart mounts the proxy under `serverRootPath: /litellm` so it does not claim a whole hostname, which makes the correct value:

```text
http://litellm.<namespace>.svc.cluster.local:4000/litellm/v1
```

`â€¦/litellm` without the `/v1` produces `/litellm/chat/completions` and a 404 that looks like a misconfigured model. `chat_path` is not the fix â€” it replaces the whole path instead of being appended â€” and the chart refuses to render with it set.

The URL is derived in `_helpers.tpl` from four values, the same way the ram-extension chart derives its own LiteLLM URL:

```yaml
global:
  semanticRouter:
    litellm:
      releaseName: litellm     # Service name follows: <release>-litellm, collapsed
      serviceName: ""          #   to <release> when it already contains "litellm"
      namespace: ""            # defaults to this release's namespace
      port: 4000
      serverRootPath: /litellm # must match the litellm chart's own value
      baseUrl: ""              # overrides all of the above
```

`baseUrl` is schema-constrained to end in `/v1`.

## How the router config is assembled

Read this before changing anything under `semantic-router.configOverride`.

Helm does not template values. A parent chart cannot compute a subchart's value from the release name, and the upstream chart does not run its values through `tpl`. So the router's config is assembled in two halves:

1. **The static skeleton** lives in `values.yaml` under `semantic-router.configOverride` â€” listeners, the provider entry, the fallback decision, the shape of `global`. `configOverride` is upstream's own extension point: it *replaces* the chart's `config` block atomically rather than merging into it, which is what keeps upstream's `replace-with-your-model` placeholders out of the rendered file.

2. **Everything release- or switch-dependent** is filled in at render time by this chart's definition of `semantic-router.effectiveConfig`. Template names are global across a chart tree and the parent's definitions are parsed last, so this chart's definition replaces the subchart's, and the subchart's own ConfigMap template calls it without knowing. It fills in the LiteLLM base URL, the management API auth block, the guards, the semantic cache and the virtual model names â€” then upstream's post-processing (Redis/Milvus wiring, the version stamp, the live-config check) runs unchanged on the result.

That is why the knobs those parts come from live under **`global.semanticRouter`**: `global` is the one map both charts can read.

The failure mode of (2) is a future upstream version renaming the helper: this chart's definition would stop being called and the seed would silently lose the backend URL and the guards. It is caught by `tests/router-config_test.yaml` ("replaces upstream's placeholder config entirely") and by `ci/validate.sh`, both of which assert on values only this definition produces, and the dependency is pinned exactly so the rename can only arrive with a deliberate bump.

### Editing the seed by hand

Anything the switches do not cover â€” extra signals, domain-specific decisions, a second provider â€” goes straight into `semantic-router.configOverride`. The chart validates what it renders, not just what you set, so a hand-written backend ref with an `api_key` is refused the same way.

## Who owns routing policy

After install, two things can write the router's config:

- **This chart**, at `helm upgrade`, from `semantic-router.configOverride`.
- **The model controller**, at runtime, through `PATCH /api/v1/config` (ETag-guarded with `If-Match`).

Nothing else writes it. The RAM extension's API container also talks to the management API, but only to read, validate and preview â€” see [Two clients on `:8080`](#two-clients-on-8080-and-why-they-are-not-the-same).

Upstream resolves the conflict with `semantic-router.configMap.applyValuesRevision`:

| `applyValuesRevision` | What an upgrade does |
| --- | --- |
| Unchanged (default `""`) | **Keeps the live ConfigMap.** Controller-applied policy survives. |
| Changed to any new string | Re-seeds from values and **discards** what the controller wrote. |

So the normal case â€” `helm upgrade` to change an Envoy timeout â€” leaves routing policy alone. Treat a revision bump as "throw away the live policy and start from the seed".

## Guards

Both guards are classifier modules that run inside the router, on CPU, before LiteLLM is reached.

```yaml
global:
  semanticRouter:
    guards:
      jailbreak:
        enabled: true
        threshold: 0.7
        onError: block
      pii:
        enabled: true
        threshold: 0.9
        onError: block
        allowedTypes: [EMAIL_ADDRESS]
```

Three things must line up for a guard to do anything, and **upstream ships none of them**:

1. `global.model_catalog.system.<ref>` â€” the checkpoint on disk (`models/Vela-1.0-Encoder-307M-Guard`, `models/Vela-1.0-Encoder-307M-PII`). There is no upstream default, and a module with no catalog entry loads no classifier: it does not fail, it scores nothing and allows everything.
2. `global.model_catalog.modules.â€¦` â€” the module that scores prompts.
3. A signal rule **and a decision** â€” scoring is not rejecting. The chart renders a `block_jailbreak` / `block_pii` decision at priority 1000/990 with a `fast_response` plugin, which answers with a refusal without ever calling a model.

All three are rendered from the one switch, so a half-configured guard cannot exist.

`onError: block` is this chart's default and differs from upstream's `allow`: an inference failure means the prompt could not be *verified* safe, and this router sits in front of a key boundary. Set `allow` if a broken classifier taking the service down is the worse failure for you.

The checkpoints are downloaded on first start, so a guard requires `semantic-router.persistence.enabled` â€” the chart refuses the combination that would re-download gigabytes on every restart.

## Semantic cache

Off by default, and **not** the same thing as LiteLLM's response cache: this one answers a *similar* prompt from a previous answer, so it changes behaviour, not just latency.

```yaml
global:
  semanticRouter:
    semanticCache:
      enabled: true
      backend: redis                     # memory | redis
      similarityThreshold: 0.9
      redis:
        address: litellm-valkey:6379     # reuse the Valkey the litellm chart deploys
```

The default threshold is 0.9 rather than upstream's 0.8, which is loose enough on short prompts to merge "write a haiku about spring" with "write a haiku about autumn".

The in-process `memory` backend is per replica, so the chart refuses it alongside more than one router replica. The bundled bitnami Redis stays disabled (its versioned image tags were withdrawn); point the cache at a Redis or Valkey you already run.

## The Envoy data plane

| Value | Default | Why |
| --- | --- | --- |
| `envoy.extProc.failureModeAllow` | `false` | **Fail closed.** Upstream's Istio reference fails open, which is right for a router that only *improves* a request. Here the router decides which LiteLLM key boundary a prompt crosses, and the guards run inside it, so failing open would forward the prompt the guard was meant to stop. |
| `envoy.extProc.requestBodyMode` | `BUFFERED` | The prompt is in the request body; the router cannot classify what it has not seen. |
| `envoy.extProc.responseBodyMode` | `STREAMED` | Tokens reach the client as they are produced. Use `BUFFERED` only for a response-side guard. |
| `envoy.routes.allowedPaths` | `/v1/chat/completions` | An allow-list with an explicit `403` catch-all. This is a chat entrypoint, not a general-purpose proxy in front of LiteLLM's management API and Admin UI. |
| `envoy.extProc.useHeadlessService` | `true` | gRPC streams are long-lived, so a ClusterIP would pin every stream from one Envoy to one router pod. |
| `envoy.adminPort` | `19000` | Bound to 127.0.0.1. A second, tiny listener on `envoy.statsPort` re-publishes only `/ready` and `/stats/prometheus` from it â€” that is what the probes and the ServiceMonitor use. |

Envoy is stateless: no routing decision, no learning state, no cache. Scale it freely; two replicas is the right production setting.

Requests arrive as `/v1/chat/completions` and are rewritten onto LiteLLM's mount prefix (`prefix_rewrite: /litellm/v1/chat/completions`). With `serverRootPath: ""` no rewrite is rendered at all.

Each allowed path is therefore published **twice**: once as the client sends it, and once as the router leaves it. The router does its own rewrite, onto the `base_url` of its LiteLLM backend â€” which already carries the mount prefix â€” so a classified request re-enters routing as `/litellm/v1/chat/completions`. Matched against the client-facing route alone it matches nothing and falls through to the catch-all, and the router's own answer is refused with `path_not_routed` after a model has already been chosen. The second route exists to catch it, and rewrites nothing, because by then the path is already the upstream's.

### Vendor fields in the response

The router decodes upstream responses strictly: any field outside the canonical OpenAI shape is rejected with `invalid_upstream_json: upstream response JSON contains a non-canonical field`, turning an answer the model has already produced â€” and been billed for â€” into a `502`.

LiteLLM adds several such fields (`routing`, `prompt_filter_results`, `provider_specific_fields` on both the choice and the message, and `latency_checkpoint` in `usage`). The router offers no leniency setting and LiteLLM no suppression, so the chart reconciles the two with a small Lua filter that removes exactly those fields on the way back â€” see `envoy.sanitizeResponse`. It sits after `ext_proc` in the filter chain and therefore *before* it on the response path, which runs filters in reverse.

Add to `envoy.sanitizeResponse.fields` if a different proxy or provider introduces its own extensions; the list names fields explicitly rather than matching by shape, because a rule broad enough to catch "anything unexpected" would eventually delete part of an answer.

### Embeddings and pinned models

Only the paths in `envoy.routes.allowedPaths` go through the router. Embeddings, `/v1/completions` and anything else keep calling LiteLLM directly â€” which is also how a client pins a concrete model: a request naming a real LiteLLM model, rather than `vllm-sr/auto`, is passed through unclassified.

`envoy.routes.modelsFromRouter` publishes `/v1/models` from the router instead of LiteLLM, so that clients see `vllm-sr/auto` in the list. It needs `networkPolicy.allowEnvoyToManagementApi` as well, and the chart refuses one without the other.

## Publishing the entrypoint

Identical in shape to the `litellm` chart: shared settings first, then one block per implementation, and more than one may be enabled at a time so a migration from Ingress to Gateway API has no gap.

```yaml
routing:
  hosts: [router.example.com]
  path: /v1
  tls:
    enabled: true
    secretName: router-tls
  ingress:
    enabled: true
    className: nginx
```

`routing.path` defaults to `/v1`, not `/`: Envoy serves exactly the OpenAI surface listed in `envoy.routes.allowedPaths`, and claiming the hostname root would take it from every neighbouring application. Unlike the litellm chart there is no server-side root path to keep in step â€” Envoy matches the path the client sent â€” so publishing under a different prefix needs a rewrite on the routing object as well.

| Implementation | Object | Notes |
| --- | --- | --- |
| `routing.ingress` | `networking.k8s.io/v1` Ingress | A dotted path is downgraded to `ImplementationSpecific` on ingress-nginx, whose admission webhook rejects dots in `Prefix`. |
| `routing.httpRoute` | `gateway.networking.k8s.io/v1` HTTPRoute | `routing.tls` is ignored: in Gateway API the certificate belongs to the Gateway's listener. Set `timeouts.backendRequest: 0s` for long completions. |
| `routing.httpProxy` | `projectcontour.io/v1` HTTPProxy | `delegated: true` renders a child proxy with no virtualhost, for a hostname another release owns as root. |
| `routing.route` | `route.openshift.io/v1` Route | A passthrough Route carries no path. |

## Management API and NetworkPolicy

The router's `:8080` can rewrite routing policy â€” which model a prompt is sent to, and therefore which LiteLLM key boundary it crosses. Upstream's default is `auth.mode: disabled`.

This chart turns bearer auth on, generates a token, and locks the port down:

```yaml
global:
  semanticRouter:
    managementApi:
      auth:
        mode: bearer
        tokenEnv: VSR_MGMT_TOKEN
      token:
        create: true
        existingSecret:
          name: semantic-router-management-token
          key: VSR_MGMT_TOKEN
```

The token is generated once and read back out of the live Secret on every later upgrade, so `helm upgrade` never rotates it out from under the model controller.

Two details that look odd and are not:

- **The Secret name is a plain literal**, not `<release>-â€¦`. The subchart mounts it through its own `envFromSecrets` value, and Helm cannot template values; the chart checks that the two names agree and fails the render if they do not.
- **The Secret key is the environment variable name.** `envFromSecrets` projects every key of a Secret as a variable of the same name, so a key called `token` would set `$token`, which the router never reads.

The NetworkPolicy covers the router pods:

| Port | Allowed from |
| --- | --- |
| 50051 | the Envoy pods of this release, and nothing else |
| 8080 | `networkPolicy.modelController` (default: `app.kubernetes.io/component: model-controller`) **and** `networkPolicy.extensionApi` (default: `app.kubernetes.io/name: ram-extension`), both in this namespace |
| 9190 | `networkPolicy.metricsScrape` (default: any pod in this namespace) |

### Two clients on `:8080`, and why they are not the same

`:8080` has two callers in the `ram-extension` layout, and the difference between them is the security story:

| Client | Calls | Role |
| --- | --- | --- |
| `networkPolicy.modelController` | `PATCH /api/v1/config` (ETag-guarded with `If-Match`) | **The only writer.** It reconciles routable LiteLLM models and the stored policy into the live router config. |
| `networkPolicy.extensionApi` | `GET /api/v1/config`, `POST /api/v1/config/validate`, `GET /api/v1/status`, `POST /api/v1/routing/preview` | **Read-only.** The RAM extension's API container serves the routing-policy editor: it shows the live config, rejects a policy before it is stored, reports convergence per replica, and previews which model a prompt would go to. Its client interface deliberately has no `PatchConfig` method. |

One writer on an ETag-guarded resource is what keeps two reconcilers from fighting over the config and losing an edit to last-write-wins. The read path is *not* a smaller version of the write path â€” it is a different capability, and it is the one the UI needs.

They are **two selectors, rendered as two rules**, not one widened selector, for three reasons:

1. They are different workloads with different labels. In the `ram-extension` release the controller carries `app.kubernetes.io/component: model-controller`, while the API Deployment carries `app.kubernetes.io/name: ram-extension` and **no component label at all** â€” its own Service selects on name and instance alone. One selector cannot match both without matching far more.
2. Either can be revoked without the other: `networkPolicy.extensionApi.enabled: false` removes the policy editor's access and leaves reconciliation working; `networkPolicy.modelController.enabled: false` freezes the config while leaving the editor able to read it.
3. The asymmetry stays visible in the rendered policy, with the writer and reader named in the comment above each rule. A later "tidy-up" that collapses them into one rule loses the distinction, which is exactly what should not happen silently.

Neither default is an empty selector. An empty `podSelector` with an empty `namespaceSelector` would admit *every* pod in the namespace to an API that can redirect prompts to a different LiteLLM key boundary, so the chart refuses to render one:

```text
Error: networkPolicy.extensionApi is enabled with no podSelector and no namespaceSelector,
which admits EVERY pod in this namespace to the management API â€” a port that can redirect
prompts to a different LiteLLM key boundary. Name the workload, or put a deliberate blanket
rule in networkPolicy.extraIngress where it is visible as one.
```

Adjust the selectors for a release that renames the chart, pin a rule to one release by adding `app.kubernetes.io/instance`, or add further clients through `networkPolicy.extraIngress`. `:50051` stays Envoy-only and `:9190` scrape-only regardless â€” the management API's clients get one port each, and never the ext_proc data path.

`policyTypes` lists **Ingress only**. The router downloads its classifier checkpoints from Hugging Face on first start, and an egress policy that forgot that turns a slow first boot into an unexplained `CrashLoopBackOff`. Add egress rules deliberately, once the models are on the volume.

## Storage and first start

```yaml
semantic-router:
  persistence:
    enabled: true
    size: 40Gi
    storageClassName: ""
  startupProbe:
    failureThreshold: 360   # 360 Ã— 10s = one hour
```

Upstream defaults to `10Gi` and `storageClassName: "standard"`. Both are changed here:

- The guard, PII, domain and embedding checkpoints are ~307M-parameter encoders at fp32 (roughly 1.2 GB each), and the Hugging Face cache keeps both the download and the extracted snapshot â€” a release with two guards and the default embedding model is already past half of 10 GiB before any knowledge base or learning state. A ReadWriteOnce PVC cannot be grown without recreating the pod on most storage classes, so 40Gi buys room to add classifiers later.
- `"standard"` does not exist on most clusters, and a PVC that references a missing StorageClass sits `Pending` with no obvious cause. Empty uses the cluster default.

The one-hour startup probe is upstream's and is kept: it is not excessive on a cold cache or a slow registry, and a shorter one produces a restart loop that re-downloads from zero each time.

## Scaling

**Envoy**: stateless, scale at will.

**The router**: one replica, deliberately. Upstream's `safetyGuards.rejectMultiReplicaLocalLearningState` (left on) refuses to render more while Router Learning keeps request-time state in the pod. Before `semantic-router.replicaCount: 2`, move three things to shared storage:

| Setting | Default | Needs to become |
| --- | --- | --- |
| `global.router.learning.state_store` | replica-local | `backend: redis` |
| `global.services.response_api` | in-process `memory` | `store_backend: redis` |
| `global.stores.response_cache` | `memory` (and off) | `backend_type: redis` |

Each router pod also downloads its own copy of the classifier models into its own ReadWriteOnce volume, so N replicas means N first starts unless the storage class supports ReadWriteMany.

## Observability

```yaml
serviceMonitor:
  enabled: true
  router:
    enabled: true
```

Two ServiceMonitors: Envoy's `/stats/prometheus` (request rates, upstream failures, and the `ext_proc` filter's own counters â€” where a router that is timing out or being skipped shows up first), and the router's `:9190` (classification, decision and guard counters).

Envoy's access log is one JSON line per request on stdout and includes `selected_model`, which is the field that explains a routing decision after the fact.

Tracing is OTLP to a collector you already run:

```yaml
global:
  semanticRouter:
    tracing:
      enabled: true
      endpoint: jaeger-collector:4317
```

The bundled Jaeger dependency stays disabled: upstream pins `jaeger.allInOne.image.tag: "latest"`, so a release that enables it has no reproducible image.

## Values reference

### Workload

| Value | Description | Default |
| --- | --- | --- |
| `replicaCount` | Envoy replicas. Stateless; 2 in production. | `1` |
| `image.repository` / `image.tag` | Envoy image, pinned exactly. | `docker.io/envoyproxy/envoy` / `distroless-v1.35.3` |
| `image.pullPolicy` | | `IfNotPresent` |
| `imagePullSecrets` | | `[]` |
| `nameOverride` / `fullnameOverride` | | `""` |
| `commonLabels` / `commonAnnotations` | Merged into every object this chart renders. | `{}` |
| `serviceAccount.create` / `.name` / `.annotations` | | `true` / `""` / `{}` |
| `serviceAccount.automount` | Envoy talks to no Kubernetes API. | `false` |
| `deploymentAnnotations` / `deploymentLabels` / `podAnnotations` / `podLabels` | | `{}` |
| `strategy` | Deployment update strategy. | `{}` |
| `terminationGracePeriodSeconds` | Envoy drains; a streaming completion can be long. | `90` |
| `podSecurityContext` / `securityContext` | Non-root (uid 101), read-only root, all capabilities dropped. | see values.yaml |
| `resources` | | 100m/128Mi â†’ 1/512Mi |
| `nodeSelector` / `tolerations` / `affinity` / `topologySpreadConstraints` | | empty |
| `extraVolumes` / `extraVolumeMounts` / `extraEnv` | | `[]` |
| `startupProbe` / `readinessProbe` / `livenessProbe` | All hit `/ready` on the stats listener. | see values.yaml |
| `extraResources` | Rendered verbatim, through `tpl`. | `[]` |

### Envoy

| Value | Description | Default |
| --- | --- | --- |
| `envoy.listenerPort` | The OpenAI listener. | `8080` |
| `envoy.adminPort` | Bound to 127.0.0.1 only. | `19000` |
| `envoy.statsPort` | Publishes `/ready` and `/stats/prometheus`. | `19001` |
| `envoy.accessLog.enabled` | One JSON line per request, including `selected_model`. | `true` |
| `envoy.timeouts.route` / `.request` / `.streamIdle` / `.idle` | Envoy's stock values cut off streaming answers. | `300s` |
| `envoy.perConnectionBufferLimitBytes` | The request body is buffered for classification. | `52428800` |
| `envoy.extProc.failureModeAllow` | Fail closed. | `false` |
| `envoy.extProc.messageTimeout` / `.maxMessageTimeout` | Classification and guard inference happen inside this. | `300s` / `600s` |
| `envoy.extProc.requestBodyMode` / `.responseBodyMode` | | `BUFFERED` / `STREAMED` |
| `envoy.extProc.allowModeOverride` | Lets the router skip processing per request. | `true` |
| `envoy.extProc.useHeadlessService` | Balance gRPC streams per router pod. | `true` |
| `envoy.extProc.connectTimeout` | | `5s` |
| `envoy.routes.allowedPaths` | Allow-list of `{path}` / `{prefix}` matchers. | `/v1/chat/completions` |
| `envoy.routes.modelsFromRouter` / `.modelsPath` | Serve `/v1/models` from the router. | `false` / `/v1/models` |
| `envoy.routes.extraRoutes` | Appended before the catch-all deny. | `[]` |
| `envoy.routes.deny.status` / `.contentType` / `.body` | The catch-all. | `403` / JSON |
| `envoy.sanitizeResponse.enabled` | Strip the proxy's vendor fields before the router decodes the response. Off only against a proxy that already returns canonical JSON. | `true` |
| `envoy.sanitizeResponse.fields` | The fields removed. | `provider_specific_fields`, `latency_checkpoint`, `prompt_filter_results`, `routing` |
| `envoy.extraClusters` | For a route added through `extraRoutes`. | `[]` |
| `service.type` / `.port` / `.annotations` | The release entrypoint. | `ClusterIP` / `8080` |
| `service.loadBalancerClass` / `.loadBalancerSourceRanges` | LoadBalancer only. | `""` / `[]` |

### Routing

| Value | Description | Default |
| --- | --- | --- |
| `routing.hosts` | Required for `ingress` and a root `httpProxy`. | `[]` |
| `routing.path` | Published prefix; Envoy matches the path as sent. | `/v1` |
| `routing.tls.enabled` / `.secretName` | | `false` / `""` |
| `routing.annotations` / `routing.labels` | Merged into every routing object. | `{}` |
| `routing.ingress.enabled` / `.className` / `.pathType` / `.annotations` / `.extraPaths` | | `false` / `""` / `Prefix` / `{}` / `[]` |
| `routing.httpRoute.enabled` / `.parentRefs` / `.matches` / `.filters` / `.timeouts` / `.extraRules` / `.annotations` | | `false` / `[]` â€¦ |
| `routing.httpProxy.enabled` / `.delegated` / `.ingressClassName` / `.tls` / `.conditions` / `.loadBalancerPolicy` / `.timeoutPolicy` / `.retryPolicy` / `.extraRoutes` / `.includes` / `.annotations` | | `false` â€¦ |
| `routing.route.enabled` / `.wildcardPolicy` / `.tls` / `.annotations` | | `false` / `None` â€¦ |

### Availability, metrics, policy

| Value | Description | Default |
| --- | --- | --- |
| `pdb.enabled` / `.minAvailable` / `.maxUnavailable` / `.annotations` / `.labels` | Covers the Envoy pods. | `false` â€¦ |
| `serviceMonitor.enabled` / `.interval` / `.scrapeTimeout` / `.labels` / `.annotations` / `.namespaceSelector` / `.relabelings` | | `false` / `30s` / `10s` â€¦ |
| `serviceMonitor.router.enabled` / `.path` | The router's own metrics port. | `true` / `/metrics` |
| `networkPolicy.enabled` | | `true` |
| `networkPolicy.modelController.enabled` / `.podSelector` / `.namespaceSelector` | The management API's **writer**. | `true` / component `model-controller` / `{}` |
| `networkPolicy.extensionApi.enabled` / `.podSelector` / `.namespaceSelector` | The management API's **read-only** client (config, validate, status, routing preview). | `true` / name `ram-extension` / `{}` |
| `networkPolicy.allowEnvoyToManagementApi` | Needed with `envoy.routes.modelsFromRouter`. | `false` |
| `networkPolicy.metricsScrape.enabled` / `.podSelector` / `.namespaceSelector` | Who may scrape `:9190`. | `true` / `{}` / `{}` |
| `networkPolicy.extraIngress` | Appended verbatim. | `[]` |

### Shared with the subchart (`global.semanticRouter`)

| Value | Description | Default |
| --- | --- | --- |
| `litellm.releaseName` / `.serviceName` / `.namespace` / `.port` | Locates the LiteLLM Service. | `litellm` / `""` / `""` / `4000` |
| `litellm.serverRootPath` | Must match the litellm chart's own value. | `/litellm` |
| `litellm.baseUrl` | Overrides the derived URL; must end in `/v1`. | `""` |
| `routerService.name` / `.namespace` / `.grpcPort` / `.apiPort` / `.metricsPort` | For a router this release does not deploy. | `""` / `""` / `50051` / `8080` / `9190` |
| `autoModelNames` | Model names that mean "let the router decide". | `[vllm-sr/auto, auto]` |
| `managementApi.auth.mode` / `.tokenEnv` | `bearer` or `disabled`. | `bearer` / `VSR_MGMT_TOKEN` |
| `managementApi.token.create` / `.value` / `.existingSecret.name` / `.existingSecret.key` | | `true` / `""` / `semantic-router-management-token` / `VSR_MGMT_TOKEN` |
| `guards.jailbreak.enabled` / `.threshold` / `.onError` / `.modelPath` | | `false` / `0.7` / `block` / Vela Guard |
| `guards.pii.enabled` / `.threshold` / `.onError` / `.modelPath` / `.allowedTypes` / `.maxSequenceLength` | | `false` / `0.9` / `block` / Vela PII / `[]` / `32768` |
| `semanticCache.enabled` / `.backend` / `.similarityThreshold` / `.maxEntries` / `.ttlSeconds` / `.evictionPolicy` / `.embeddingModel` | | `false` / `memory` / `0.9` / `1000` / `3600` / `fifo` / `mmbert` |
| `semanticCache.redis.address` / `.database` / `.password` / `.tls.enabled` | Required for `backend: redis`. | `""` / `0` / `""` / `false` |
| `tracing.enabled` / `.endpoint` / `.samplingRate` | OTLP. | `false` / `""` / `0.1` |

### Subchart (`semantic-router`)

Upstream's values, documented at <https://github.com/vllm-project/semantic-router>. The ones this chart sets or reads back:

| Value | Description | Default here |
| --- | --- | --- |
| `semantic-router.enabled` | `false` runs Envoy against a router deployed elsewhere. | `true` |
| `semantic-router.replicaCount` | See [Scaling](#scaling). | `1` |
| `semantic-router.safetyGuards.rejectMultiReplicaLocalLearningState` | Leave on. | `true` |
| `semantic-router.persistence.enabled` / `.size` / `.storageClassName` / `.accessMode` | | `true` / `40Gi` / `""` / `ReadWriteOnce` |
| `semantic-router.startupProbe.failureThreshold` / `.periodSeconds` | One hour for the first model download. | `360` / `10` |
| `semantic-router.envFromSecrets` | Must contain the management token Secret. | `[semantic-router-management-token]` |
| `semantic-router.configMap.applyValuesRevision` | Bump to discard controller-applied policy. | `""` |
| `semantic-router.configOverride` | The static seed skeleton. | see values.yaml |
| `semantic-router.dependencies.*` | Redis, Milvus, Jaeger, Prometheus, Grafana. | all `false` |
| `semantic-router.dashboard.enabled` | A second writer on an ETag-guarded config. | `false` |

## Validation

```sh
helm dependency build helm-charts/semantic-router
helm lint helm-charts/semantic-router
helm unittest helm-charts/semantic-router
bash helm-charts/semantic-router/ci/validate.sh
```

`values.schema.json` is strict (`additionalProperties: false`), including for `global` â€” a schema that omits `global` rejects the chart the moment anything sets one, which is what made an earlier litellm chart unusable as a subchart.

The render also fails, by design, on value combinations that would produce a release that works and is wrong:

| Mistake | Message names |
| --- | --- |
| `access_key` / `api_key` / `api_key_env` / `auth_header` on a backend ref | the caller's key being overwritten |
| `global.services.authz` | the credential resolver's `fail_open` default |
| `chat_path` on a backend ref | the path being replaced rather than appended |
| A base URL not ending in `/v1` | the OpenAI base path |
| `default_model` | it not being a v0.3 field |
| A guard with no `modelPath`, or with `persistence` off | a guard that silently allows everything |
| A token Secret the subchart was never told to mount | `semantic-router.envFromSecrets` |
| A Redis cache with no address, or an in-process cache across replicas | the per-replica cache |
| A management API client with no selectors at all, or every client disabled | the pods that would be admitted, or the reconcile loop that would time out |
| `modelsFromRouter` without `allowEnvoyToManagementApi` | the policy that would drop it |
| An Ingress with no host, an HTTPRoute with no `parentRefs`, a root HTTPProxy with no FQDN, TLS with no Secret | the missing value |

## Upgrading

1. `helm dependency update helm-charts/semantic-router` when moving the subchart pin; commit the rewritten `Chart.lock` with the `Chart.yaml` change.
2. Re-read [How the router config is assembled](#how-the-router-config-is-assembled) â€” a subchart upgrade is the one event that can silently disable this chart's config assembly. `helm unittest` catches it.
3. Routing policy applied by the model controller survives unless `semantic-router.configMap.applyValuesRevision` changes.
4. The management API token is read back from the live Secret, so it does not rotate.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Every request returns `403` with `path_not_routed` | The path is not in `envoy.routes.allowedPaths`. Only chat completions are published through the router. |
| An *unrouted* request succeeds but a routed one returns `403` with `path_not_routed` | The post-rewrite route is missing. Envoy's access log is decisive: log `%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%` and the selected model, and you will see the path arrive as `/v1/chat/completions` on the way in and as the rewritten path on the way back. The chart publishes both; a hand-written `allowedPaths` entry in an older release may not. |
| Every routed answer returns `502` with `invalid_upstream_json` in the router log | The proxy added a field outside the canonical OpenAI shape. The log line names it. Add it to `envoy.sanitizeResponse.fields`. |
| Every request fails with `ext_proc` errors in the Envoy log | The router is not ready yet (first start downloads models), or the NetworkPolicy does not match the Envoy pods. With fail-closed ext_proc the request is rejected rather than forwarded. |
| `404` from LiteLLM, with the right model name | The base URL lost its `/v1`, or `serverRootPath` here does not match the litellm release's. |
| `401` from LiteLLM | The caller's key, not the router's: there is no router credential. Check the virtual key's model permissions. |
| The model controller gets `401` on `/api/v1/config` | The Secret was recreated with a new token, or `envFromSecrets` names a Secret that does not exist. |
| The policy editor shows "cannot reach the router", or validate/preview time out | The extension API's pods do not match `networkPolicy.extensionApi.podSelector` â€” likely a renamed chart or a different namespace. Connections are dropped, not refused, so this looks like a hang rather than a `403`. |
| The model controller gets `412` | A missing or stale `If-Match` ETag. `GET` the config first. |
| The router pod is `Pending` | No default StorageClass for the 40Gi PVC. |
| The router restarts after ~1 hour | The model download did not finish inside the startup probe's budget. Check egress to Hugging Face. |
| A guard is on and nothing is ever blocked | Rendered config has no `model_catalog.system` entry â€” which this chart cannot produce; check that the `semantic-router.effectiveConfig` override is still in effect (see upgrading). |
| `helm upgrade` does not change routing | Expected: the live ConfigMap wins until `applyValuesRevision` changes. |

## Not included

- **The model controller.** It lives in the ram-extension repository and is what turns routable LiteLLM models into `providers.models` entries and DB-held policy into decisions.
- **LiteLLM.** Separate release, separate chart.
- **The upstream dashboard.** It is a second writer on the same ETag-guarded config as the controller.
- **An egress NetworkPolicy.** See [Management API and NetworkPolicy](#management-api-and-networkpolicy).
- **Autoscaling for the router.** Replica-local learning state has to move to Redis first.
