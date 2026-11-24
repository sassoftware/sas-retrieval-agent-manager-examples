{{/* ── Naming ──────────────────────────────────────────────────────────────

This chart and its subchart have the same name, so every template defined here
is prefixed `srouter.` instead of `semantic-router.`. Template names are global
across a chart tree and the LAST definition wins, which would otherwise mean a
helper defined here silently replacing the upstream chart's helper of the same
name and renaming its workload. There is exactly one deliberate exception —
`semantic-router.effectiveConfig`, documented under "Seeding the router config"
below.

`srouter.fullname` names the release; `srouter.envoy.fullname` names the
objects this chart owns. They have to differ: the subchart already creates a
Deployment, a Service and a ServiceAccount called `<release>-semantic-router`.
*/}}

{{- define "srouter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "srouter.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "srouter.envoy.fullname" -}}
{{- printf "%s-envoy" (include "srouter.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "srouter.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels for the Envoy workload.

`component: envoy` is what keeps the subchart's Services from selecting these
pods: every Service upstream renders adds `app.kubernetes.io/component: router`
to its selector, and the two components never overlap.
*/}}
{{- define "srouter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "srouter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: envoy
{{- end -}}

{{- define "srouter.labels" -}}
helm.sh/chart: {{ include "srouter.chart" . }}
{{ include "srouter.selectorLabels" . }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "srouter.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "srouter.envoy.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "srouter.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}

{{/* ── Shared knobs ────────────────────────────────────────────────────────

`global.semanticRouter` is the one map both this chart and the subchart can
read, which is why the values the ROUTER CONFIG needs live there rather than at
the top level. Every helper below reaches them through this accessor, so the
same helper works whether it is called from a template of this chart (where
`.Values` is this chart's) or from the `semantic-router.effectiveConfig`
override (where `.Values` belongs to the subchart).
*/}}
{{- define "srouter.knobs" -}}
{{- $global := .Values.global | default dict -}}
{{- toYaml (get $global "semanticRouter" | default dict) -}}
{{- end -}}

{{/* ── The LiteLLM backend ─────────────────────────────────────────────── */}}

{{/*
Name of the LiteLLM Service.

The litellm chart's own fullname helper collapses `<release>-litellm` to
`<release>` when the release name already contains "litellm", so the common
case — `helm install litellm ./helm-charts/litellm` — produces a Service called
plainly `litellm`. That rule is reproduced here rather than reused, because
this chart does not depend on the litellm chart: LiteLLM is a separate release,
usually in a separate Helm run, and frequently in a separate namespace.
*/}}
{{- define "srouter.litellm.serviceName" -}}
{{- $l := (include "srouter.knobs" . | fromYaml).litellm | default dict -}}
{{- if $l.serviceName -}}
{{- $l.serviceName -}}
{{- else -}}
{{- $release := $l.releaseName | default "litellm" -}}
{{- if contains "litellm" $release -}}
{{- $release | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-litellm" $release | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "srouter.litellm.namespace" -}}
{{- $l := (include "srouter.knobs" . | fromYaml).litellm | default dict -}}
{{- $l.namespace | default .Release.Namespace -}}
{{- end -}}

{{/*
In-cluster OpenAI base URL of LiteLLM.

THE `/v1` SUFFIX IS LOAD-BEARING. In the router config a backend ref's
`base_url` REPLACES the protocol's canonical base path rather than prefixing
it, and the OpenAI protocol then appends `/chat/completions`. A base_url of
`http://litellm:4000/litellm` therefore produces `/litellm/chat/completions`,
which LiteLLM answers with 404 — the proxy serves its OpenAI surface under
`<serverRootPath>/v1`. `chat_path` is NOT the fix: setting it replaces the
whole path instead of being appended to the base.

`serverRootPath` is part of the URL for the same reason: the litellm chart
mounts the proxy under /litellm by default so the release does not claim a
whole hostname, and the prefix is what the proxy itself serves under.

An explicit `global.semanticRouter.litellm.baseUrl` wins, for a LiteLLM this
release does not deploy.
*/}}
{{- define "srouter.litellm.baseUrl" -}}
{{- $l := (include "srouter.knobs" . | fromYaml).litellm | default dict -}}
{{- if $l.baseUrl -}}
{{- $l.baseUrl -}}
{{- else -}}
{{- printf "http://%s.%s.svc.cluster.local:%v%s/v1"
      (include "srouter.litellm.serviceName" .)
      (include "srouter.litellm.namespace" .)
      ($l.port | default 4000)
      ($l.serverRootPath | default "") -}}
{{- end -}}
{{- end -}}

{{/*
Host, port and path prefix for Envoy's upstream cluster, parsed back out of the
base URL so that an explicit `baseUrl` and the derived one cannot disagree
about where LiteLLM is. Envoy sends the path the CLIENT used, so the route
rewrites `/v1` to the prefix below; the router only needs the base URL for the
calls it makes itself.
*/}}
{{- define "srouter.litellm.authority" -}}
{{- $url := include "srouter.litellm.baseUrl" . -}}
{{- $rest := $url | trimPrefix "http://" | trimPrefix "https://" -}}
{{- (splitList "/" $rest) | first -}}
{{- end -}}

{{- define "srouter.litellm.host" -}}
{{- $authority := include "srouter.litellm.authority" . -}}
{{- (splitList ":" $authority) | first -}}
{{- end -}}

{{- define "srouter.litellm.port" -}}
{{- $authority := include "srouter.litellm.authority" . -}}
{{- $parts := splitList ":" $authority -}}
{{- if gt (len $parts) 1 -}}
{{- index $parts 1 -}}
{{- else if hasPrefix "https://" (include "srouter.litellm.baseUrl" .) -}}
443
{{- else -}}
80
{{- end -}}
{{- end -}}

{{/* The path LiteLLM serves the OpenAI API under, e.g. /litellm/v1. */}}
{{- define "srouter.litellm.basePath" -}}
{{- $url := include "srouter.litellm.baseUrl" . -}}
{{- $rest := $url | trimPrefix "http://" | trimPrefix "https://" -}}
{{- $authority := (splitList "/" $rest) | first -}}
{{- printf "/%s" ($rest | trimPrefix $authority | trimPrefix "/") | trimSuffix "/" -}}
{{- end -}}

{{/* ── The router workload ─────────────────────────────────────────────── */}}

{{/*
Name of the router Service.

When the subchart is enabled its own naming helper is CALLED rather than
copied, with a context scoped to the subchart's values — the same trick the
ram-extension chart uses for LiteLLM. It is only safe inside the `enabled`
branch: Helm drops a dependency whose condition is false from the chart tree
entirely, templates included, so the helper would not exist.
*/}}
{{- define "srouter.router.fullname" -}}
{{- $sub := (index .Values "semantic-router") | default dict -}}
{{- $svc := (include "srouter.knobs" . | fromYaml).routerService | default dict -}}
{{- if $svc.name -}}
{{- $svc.name -}}
{{- else if $sub.enabled -}}
{{- include "semantic-router.fullname" (dict "Chart" (dict "Name" "semantic-router") "Release" .Release "Values" $sub) -}}
{{- else -}}
{{- fail "semantic-router.enabled is false, so this chart does not deploy a router. Set global.semanticRouter.routerService.name to the Service of the router Envoy should call." -}}
{{- end -}}
{{- end -}}

{{/*
Upstream renders a second, headless Service for the gRPC port so that an
ext_proc client can balance streams across router pods itself. A gRPC stream is
long-lived, so a ClusterIP pins every stream from one Envoy to one router pod
for the life of the connection.
*/}}
{{- define "srouter.router.extProcService" -}}
{{- $svc := (include "srouter.knobs" . | fromYaml).routerService | default dict -}}
{{- if and ($svc.name | not) .Values.envoy.extProc.useHeadlessService -}}
{{- printf "%s-headless" (include "srouter.router.fullname" .) -}}
{{- else -}}
{{- include "srouter.router.fullname" . -}}
{{- end -}}
{{- end -}}

{{- define "srouter.router.namespace" -}}
{{- $svc := (include "srouter.knobs" . | fromYaml).routerService | default dict -}}
{{- $svc.namespace | default .Release.Namespace -}}
{{- end -}}

{{- define "srouter.router.grpcPort" -}}
{{- $svc := (include "srouter.knobs" . | fromYaml).routerService | default dict -}}
{{- $svc.grpcPort | default 50051 -}}
{{- end -}}

{{- define "srouter.router.apiPort" -}}
{{- $svc := (include "srouter.knobs" . | fromYaml).routerService | default dict -}}
{{- $svc.apiPort | default 8080 -}}
{{- end -}}

{{- define "srouter.router.metricsPort" -}}
{{- $svc := (include "srouter.knobs" . | fromYaml).routerService | default dict -}}
{{- $svc.metricsPort | default 9190 -}}
{{- end -}}

{{/* ── Management API token ────────────────────────────────────────────── */}}

{{/*
The Secret name is a plain literal, not `<release>-…`, and that is forced: the
subchart reads it from its own `envFromSecrets` value, and Helm does not
template values. The validation below checks that the name configured here is
the name the subchart was told to mount, so the two cannot drift apart
silently.
*/}}
{{- define "srouter.managementToken.secretName" -}}
{{- $m := (include "srouter.knobs" . | fromYaml).managementApi | default dict -}}
{{- $token := $m.token | default dict -}}
{{- $existing := $token.existingSecret | default dict -}}
{{- $existing.name | default "semantic-router-management-token" -}}
{{- end -}}

{{/*
The key has to equal the env var the router reads the token from:
`envFromSecrets` projects every key of a Secret as an environment variable of
the same name, so a key called `token` would set `$token`, not `$VSR_MGMT_TOKEN`.
*/}}
{{- define "srouter.managementToken.secretKey" -}}
{{- $m := (include "srouter.knobs" . | fromYaml).managementApi | default dict -}}
{{- $auth := $m.auth | default dict -}}
{{- $token := $m.token | default dict -}}
{{- $existing := $token.existingSecret | default dict -}}
{{- $existing.key | default ($auth.tokenEnv | default "VSR_MGMT_TOKEN") -}}
{{- end -}}

{{/* ── Seeding the router config ───────────────────────────────────────────

WHAT THIS IS

`semantic-router.effectiveConfig` is defined by the UPSTREAM chart, and
redefining it here replaces it: template names are global across a chart tree
and the parent chart's definitions are parsed last, so this one wins. The
subchart's own configmap.yaml calls it, gets the config assembled below, and
then applies its own post-processing (Redis/Milvus/Jaeger wiring, the v0.3
version stamp) unchanged.

WHY IT IS NECESSARY

Helm does not template values. `semantic-router.configOverride` in values.yaml
is a static document, so it cannot contain the release's namespace, the LiteLLM
Service name, or anything derived from a switch like `guards.pii.enabled`. The
alternatives were to make operators hand-edit a 60-line nested config for every
knob, or to let a `guards.pii.enabled: true` that silently does nothing sit in
values.yaml. Both are worse than one documented override.

WHAT TO WATCH

If a future upstream version renames this helper, this definition stops being
called and the rendered config falls back to upstream's handling of
`configOverride` — which is the skeleton in values.yaml, without the LiteLLM
URL, the guards, or the management API auth. That failure is caught: the unit
tests and ci/validate.sh both assert on values this definition is the only
source of. The dependency is pinned exactly so the change can only arrive with
a deliberate bump.
*/}}
{{- define "semantic-router.effectiveConfig" -}}
{{- $live := include "semantic-router.liveConfig" . -}}
{{- if ne (trim $live) "" -}}
{{/* The management API has written to the live ConfigMap since install, and
     configMap.applyValuesRevision has not changed. Upstream's rule is to keep
     what is live; re-seeding here would overwrite controller-applied policy on
     every `helm upgrade`. */}}
{{- $live -}}
{{- else -}}
{{- include "srouter.routerConfig" . -}}
{{- end -}}
{{- end -}}

{{/*
Assembles the router config: the static skeleton from values.yaml, plus
everything that depends on the release or on a switch.

Callable from either context — it reads the skeleton from the subchart's
`configOverride`/`config` when called from the subchart, and from
`.Values["semantic-router"]` when called from this chart's own templates (the
unit tests and the ConfigMap checksum).
*/}}
{{- define "srouter.routerConfig" -}}
{{- $k := include "srouter.knobs" . | fromYaml -}}
{{- $sub := (index .Values "semantic-router") -}}
{{- $skeleton := dict -}}
{{- if $sub -}}
{{/* Parent context. */}}
{{- $skeleton = ($sub.configOverride | default $sub.config | default dict) -}}
{{- else -}}
{{/* Subchart context. */}}
{{- $skeleton = (.Values.configOverride | default .Values.config | default dict) -}}
{{- end -}}
{{- $cfg := deepCopy $skeleton -}}

{{/* The config format version. There is no `default_model` field in v0.3: the
     fallback is the lowest-priority decision with no conditions, which the
     skeleton carries. */}}
{{- $_ := set $cfg "version" ($cfg.version | default "v0.3") -}}

{{/* ── Backends ──────────────────────────────────────────────────────────
     Every backend ref that names no endpoint of its own is a LiteLLM ref, and
     gets the derived base URL. Credentials are deliberately NOT set: the
     caller's Authorization header reaches LiteLLM only while the router finds
     no key of its own to substitute. */}}
{{- $providers := (get $cfg "providers") | default dict -}}
{{- $models := (get $providers "models") | default list -}}
{{- range $model := $models -}}
{{- range $ref := (get $model "backend_refs") | default list -}}
{{- if not (get $ref "endpoint") -}}
{{- $_ := set $ref "base_url" (include "srouter.litellm.baseUrl" $) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $_ := set $providers "models" $models -}}
{{- $_ := set $cfg "providers" $providers -}}

{{- $global := (get $cfg "global") | default dict -}}

{{/* ── Virtual model names ───────────────────────────────────────────── */}}
{{- $router := (get $global "router") | default dict -}}
{{- with $k.autoModelNames -}}
{{- $_ := set $router "auto_model_names" . -}}
{{- $_ := set $router "auto_model_name" (first .) -}}
{{- end -}}
{{- $_ := set $global "router" $router -}}

{{/* ── Management API ────────────────────────────────────────────────────
     bind_address must be 0.0.0.0, not upstream's 127.0.0.1: the model
     controller reaches this port across the pod boundary. What keeps it
     private is bearer auth plus the NetworkPolicy, not the bind address. */}}
{{- $services := (get $global "services") | default dict -}}
{{- $mgmt := $k.managementApi | default dict -}}
{{- $mgmtAuth := $mgmt.auth | default dict -}}
{{- $api := dict "bind_address" "0.0.0.0" "port" (atoi (include "srouter.router.apiPort" .)) "remote_exposure" true -}}
{{- if eq ($mgmtAuth.mode | default "bearer") "bearer" -}}
{{- $_ := set $api "auth" (dict "mode" "bearer" "tokens" (list (dict "env" ($mgmtAuth.tokenEnv | default "VSR_MGMT_TOKEN") "role" "admin"))) -}}
{{- else -}}
{{- $_ := set $api "auth" (dict "mode" "disabled") -}}
{{- end -}}
{{- $_ := set $services "management_api" $api -}}

{{/* ── Tracing ──────────────────────────────────────────────────────────── */}}
{{- $tracing := $k.tracing | default dict -}}
{{- if $tracing.enabled -}}
{{- $_ := set $services "observability" (dict "tracing" (dict
      "enabled" true
      "provider" "opentelemetry"
      "exporter" (dict "type" "otlp" "endpoint" ($tracing.endpoint | default "") "insecure" true)
      "sampling" (dict "type" "probabilistic" "rate" ($tracing.samplingRate | default 0.1))
      "resource" (dict "service_name" "vllm-semantic-router" "deployment_environment" .Release.Namespace))) -}}
{{- end -}}
{{- $_ := set $global "services" $services -}}

{{/* ── Semantic cache ────────────────────────────────────────────────────
     Upstream calls it `response_cache`; it answers a SIMILAR prompt from a
     previous answer, so it changes behaviour and not just latency. */}}
{{- $stores := (get $global "stores") | default dict -}}
{{- $cache := $k.semanticCache | default dict -}}
{{- if $cache.enabled -}}
{{- $backend := $cache.backend | default "memory" -}}
{{- $rc := dict
      "enabled" true
      "backend_type" $backend
      "similarity_threshold" ($cache.similarityThreshold | default 0.9)
      "max_entries" (int ($cache.maxEntries | default 1000))
      "ttl_seconds" (int ($cache.ttlSeconds | default 3600))
      "eviction_policy" ($cache.evictionPolicy | default "fifo")
      "embedding_model" ($cache.embeddingModel | default "mmbert") -}}
{{- if eq $backend "redis" -}}
{{- $redis := $cache.redis | default dict -}}
{{- $address := splitList ":" ($redis.address | default "") -}}
{{- $redisPort := "6379" -}}
{{- if eq (len $address) 2 -}}
{{- $redisPort = index $address 1 -}}
{{- end -}}
{{- $_ := set $rc "redis" (dict
      "connection" (dict
        "host" (first $address)
        "port" (int $redisPort)
        "database" (int ($redis.database | default 0))
        "password" ($redis.password | default "")
        "timeout" 5
        "tls" (dict "enabled" ((($redis.tls) | default dict).enabled | default false)))
      "index" (dict
        "name" "semantic_cache_idx"
        "prefix" "vsr:cache:"
        "vector_field" (dict "name" "vector" "dimension" 384 "metric_type" "COSINE")
        "index_type" "HNSW"
        "params" (dict "M" 16 "efConstruction" 200))
      "search" (dict "topk" 5)
      "development" (dict "auto_create_index" true "drop_index_on_startup" false)) -}}
{{- end -}}
{{- $_ := set $stores "response_cache" $rc -}}
{{- else -}}
{{- $_ := set $stores "response_cache" (dict "enabled" false) -}}
{{- end -}}
{{- $_ := set $global "stores" $stores -}}

{{/* ── Guards ────────────────────────────────────────────────────────────
     Three things have to line up for a guard to do anything, and upstream
     ships none of them:

       1. `global.model_catalog.system.<ref>` — the checkpoint on disk.
       2. `global.model_catalog.modules.…`    — the module that scores prompts.
       3. a signal rule plus a decision       — scoring alone never rejects a
                                                request; a decision with a
                                                `fast_response` plugin does.

     All three are rendered together from one switch so a half-configured guard
     cannot exist. */}}
{{- $guards := $k.guards | default dict -}}
{{- $jailbreak := $guards.jailbreak | default dict -}}
{{- $pii := $guards.pii | default dict -}}
{{- if or $jailbreak.enabled $pii.enabled -}}
{{- $catalog := (get $global "model_catalog") | default dict -}}
{{- $system := (get $catalog "system") | default dict -}}
{{- $modules := (get $catalog "modules") | default dict -}}
{{- $classifier := (get $modules "classifier") | default dict -}}

{{- if $jailbreak.enabled -}}
{{- $path := $jailbreak.modelPath | default "models/Vela-1.0-Encoder-307M-Guard" -}}
{{- $_ := set $system "prompt_guard" $path -}}
{{- $_ := set $modules "prompt_guard" (dict
      "enabled" true
      "model_ref" "prompt_guard"
      "model_id" $path
      "threshold" ($jailbreak.threshold | default 0.7)
      "use_cpu" true
      "on_error" ($jailbreak.onError | default "block")
      "positive_labels" (list "jailbreak")
      "jailbreak_mapping_path" (printf "%s/jailbreak_type_mapping.json" $path)) -}}
{{- end -}}

{{- if $pii.enabled -}}
{{- $path := $pii.modelPath | default "models/Vela-1.0-Encoder-307M-PII" -}}
{{- $_ := set $system "pii_classifier" $path -}}
{{- $_ := set $classifier "pii" (dict
      "enabled" true
      "model_ref" "pii_classifier"
      "model_id" $path
      "threshold" ($pii.threshold | default 0.9)
      "use_cpu" true
      "on_error" ($pii.onError | default "block")
      "use_mmbert_32k" true
      "max_sequence_length" (int ($pii.maxSequenceLength | default 32768))
      "window" (dict "size" 512 "overlap" 255)
      "pii_mapping_path" (printf "%s/pii_mapping.json" $path)) -}}
{{- $_ := set $modules "classifier" $classifier -}}
{{- end -}}

{{- $_ := set $catalog "system" $system -}}
{{- $_ := set $catalog "modules" $modules -}}
{{- $_ := set $global "model_catalog" $catalog -}}

{{/* Signals and the decisions that enforce them. */}}
{{- $routing := (get $cfg "routing") | default dict -}}
{{- $signals := (get $routing "signals") | default dict -}}
{{- $decisions := (get $routing "decisions") | default list -}}
{{- $blocking := list -}}
{{- if $jailbreak.enabled -}}
{{- $_ := set $signals "jailbreak" (list (dict
      "name" "prompt_injection"
      "threshold" ($jailbreak.threshold | default 0.7)
      "include_history" true
      "description" "Prompt-injection and jailbreak attempts.")) -}}
{{- $blocking = append $blocking (dict
      "name" "block_jailbreak"
      "description" "Reject prompts the jailbreak guard flagged, before any backend is called."
      "priority" 1000
      "rules" (dict "operator" "OR" "conditions" (list (dict "type" "jailbreak" "name" "prompt_injection")))
      "plugins" (list (dict "type" "fast_response" "configuration" (dict
        "message" "Your request was declined by the prompt-safety policy.")))) -}}
{{- end -}}
{{- if $pii.enabled -}}
{{- $_ := set $signals "pii" (list (dict
      "name" "restricted_pii"
      "threshold" ($pii.threshold | default 0.9)
      "include_history" true
      "pii_types_allowed" ($pii.allowedTypes | default list)
      "description" "Prompts carrying personally identifiable information.")) -}}
{{- $blocking = append $blocking (dict
      "name" "block_pii"
      "description" "Reject prompts carrying restricted PII, before any backend is called."
      "priority" 990
      "rules" (dict "operator" "OR" "conditions" (list (dict "type" "pii" "name" "restricted_pii")))
      "plugins" (list (dict "type" "fast_response" "configuration" (dict
        "message" "Your request was declined by the data-protection policy.")))) -}}
{{- end -}}
{{- $_ := set $routing "signals" $signals -}}
{{- $_ := set $routing "decisions" (concat $blocking $decisions) -}}
{{- $_ := set $cfg "routing" $routing -}}
{{- end -}}

{{- $_ := set $cfg "global" $global -}}
{{- toYaml $cfg -}}
{{- end -}}

{{/* ── Envoy ───────────────────────────────────────────────────────────── */}}

{{/*
The whole envoy.yaml, as one bootstrap document.

Three listeners' worth of decisions are worth stating here rather than in the
rendered file:

  * The HTTP listener runs ext_proc BEFORE the router filter, so the router
    sees the request body and can rewrite `model` before a cluster is picked.
  * The admin interface stays on 127.0.0.1 — it serves /quitquitquit and a full
    config dump — and a second, tiny listener re-publishes only /ready and
    /stats/prometheus from it. That is what the probes and the ServiceMonitor
    use.
  * The route table is an allow-list with an explicit deny at the end. This
    listener publishes a chat entrypoint, not a general-purpose proxy in front
    of LiteLLM's management API and Admin UI.
*/}}
{{- define "srouter.envoyConfig" -}}
{{- $e := .Values.envoy -}}
{{- $basePath := include "srouter.litellm.basePath" . -}}
admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: {{ $e.adminPort }}
static_resources:
  listeners:
    - name: http
      address:
        socket_address:
          address: 0.0.0.0
          port_value: {{ $e.listenerPort }}
      per_connection_buffer_limit_bytes: {{ int $e.perConnectionBufferLimitBytes }}
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress_http
                use_remote_address: true
                stream_idle_timeout: {{ $e.timeouts.streamIdle }}
                request_timeout: {{ $e.timeouts.request }}
                common_http_protocol_options:
                  idle_timeout: {{ $e.timeouts.idle }}
                {{- if $e.accessLog.enabled }}
                access_log:
                  - name: envoy.access_loggers.stdout
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
                      log_format:
                        json_format:
                          time: "%START_TIME%"
                          method: "%REQ(:METHOD)%"
                          path: "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%"
                          protocol: "%PROTOCOL%"
                          response_code: "%RESPONSE_CODE%"
                          response_flags: "%RESPONSE_FLAGS%"
                          duration: "%DURATION%"
                          bytes_received: "%BYTES_RECEIVED%"
                          bytes_sent: "%BYTES_SENT%"
                          upstream_cluster: "%UPSTREAM_CLUSTER%"
                          request_id: "%REQ(X-REQUEST-ID)%"
                          requested_model: "%REQ(X-REQUESTED-MODEL)%"
                          selected_model: "%REQ(X-SELECTED-MODEL)%"
                          {{- /* Why the router chose what it chose.
                                 
                                 RESP, not REQ: the router reports its decision
                                 on the way back, and these are the only place
                                 it is reported at all, v0.4.0's management
                                 API has no per-query history, and the caller
                                 is RAM rather than anything this release can
                                 instrument. Logging them here is what makes a
                                 routed answer explainable after the fact.
                                 
                                 `response_path` is the one to read first: it
                                 says `upstream` when a model produced the
                                 answer, so a value that is ever anything else
                                 means something answered without calling a
                                 model. */}}
                          decision: "%RESP(X-VSR-SELECTED-DECISION)%"
                          decision_algorithm: "%RESP(X-VSR-SELECTED-ALGORITHM)%"
                          decision_confidence: "%RESP(X-VSR-SELECTED-CONFIDENCE)%"
                          answered_by: "%RESP(X-VSR-SELECTED-MODEL)%"
                          response_path: "%RESP(X-VSR-RESPONSE-PATH)%"
                          routing_latency_ms: "%RESP(X-VSR-ROUTING-LATENCY-MS)%"
                          {{- /* The money and the wait, from the proxy that
                                 actually knows both. Cost is per request and
                                 split input/output; duration excludes this
                                 router's own overhead, which is logged
                                 separately above. */}}
                          cost_input: "%RESP(X-LITELLM-RESPONSE-COST-INPUT)%"
                          cost_output: "%RESP(X-LITELLM-RESPONSE-COST-OUTPUT)%"
                          model_latency_ms: "%RESP(X-LITELLM-RESPONSE-DURATION-MS)%"
                {{- end }}
                route_config:
                  name: semantic_router
                  virtual_hosts:
                    - name: openai
                      domains: ["*"]
                      routes:
                        {{- if $e.routes.modelsFromRouter }}
                        # The router's own model list: it includes the virtual
                        # model names ({{ join ", " ((include "srouter.knobs" . | fromYaml).autoModelNames | default list) }}),
                        # which LiteLLM does not know about.
                        - match:
                            path: {{ $e.routes.modelsPath | quote }}
                          route:
                            cluster: semantic_router_api
                            timeout: {{ $e.timeouts.route }}
                        {{- end }}
                        {{- range $match := $e.routes.allowedPaths }}
                        {{- $rewritten := printf "%s%s" $basePath (((($match.path) | default $match.prefix) | trimPrefix "/v1")) }}
                        - match:
                            {{- if $match.path }}
                            path: {{ $match.path | quote }}
                            {{- else }}
                            prefix: {{ $match.prefix | quote }}
                            {{- end }}
                          route:
                            cluster: litellm
                            timeout: {{ $e.timeouts.route }}
                            {{- if ne $basePath "/v1" }}
                            # LiteLLM serves the OpenAI API under
                            # {{ $basePath }}; the client sent /v1/…
                            prefix_rewrite: {{ $rewritten | quote }}
                            {{- end }}
                        {{- if ne $basePath "/v1" }}
                        # The SAME request after the router has handled it.
                        #
                        # The router rewrites the path onto its backend's
                        # `base_url`, which already carries {{ $basePath }},
                        # so a classified request re-enters routing as
                        # {{ $rewritten }} and no longer matches the route
                        # above. Without this it falls through to the
                        # catch-all: the router picks a model and Envoy then
                        # refuses its own result with `path_not_routed`.
                        #
                        # No rewrite here, because the path is already the
                        # upstream's.
                        - match:
                            {{- if $match.path }}
                            path: {{ $rewritten | quote }}
                            {{- else }}
                            prefix: {{ $rewritten | quote }}
                            {{- end }}
                          route:
                            cluster: litellm
                            timeout: {{ $e.timeouts.route }}
                        {{- end }}
                        {{- end }}
                        {{- with $e.routes.extraRoutes }}
                        {{- toYaml . | nindent 24 }}
                        {{- end }}
                        # The catch-all. Fail-closed ext_proc and an open route
                        # table would contradict each other.
                        - match:
                            prefix: "/"
                          direct_response:
                            status: {{ $e.routes.deny.status }}
                            body:
                              inline_string: {{ $e.routes.deny.body | quote }}
                          response_headers_to_add:
                            - header:
                                key: content-type
                                value: {{ $e.routes.deny.contentType | quote }}
                              append_action: OVERWRITE_IF_EXISTS_OR_ADD
                http_filters:
                  - name: envoy.filters.http.ext_proc
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.ext_proc.v3.ExternalProcessor
                      grpc_service:
                        envoy_grpc:
                          cluster_name: semantic_router_ext_proc
                        timeout: {{ $e.extProc.messageTimeout }}
                      failure_mode_allow: {{ $e.extProc.failureModeAllow }}
                      message_timeout: {{ $e.extProc.messageTimeout }}
                      max_message_timeout: {{ $e.extProc.maxMessageTimeout }}
                      allow_mode_override: {{ $e.extProc.allowModeOverride }}
                      processing_mode:
                        request_header_mode: SEND
                        response_header_mode: SEND
                        request_body_mode: {{ $e.extProc.requestBodyMode }}
                        response_body_mode: {{ $e.extProc.responseBodyMode }}
                        request_trailer_mode: SKIP
                        response_trailer_mode: SKIP
                  {{- with $e.sanitizeResponse }}
                  {{- if and .enabled .fields }}
                  # Removes the proxy's vendor extensions before the router
                  # decodes the answer.
                  #
                  # The router decodes responses strictly and refuses any field
                  # outside the canonical OpenAI shape:
                  #
                  #   invalid_upstream_json: upstream response JSON contains a
                  #   non-canonical field
                  #
                  # LiteLLM adds several. Every routed answer therefore became
                  # a 502 AFTER the model had produced it and been billed for
                  # it. Neither side has a setting, since the router offers no
                                    # leniency and the proxy no suppression, so the mismatch is
                  # reconciled here.
                  #
                  # Placed AFTER ext_proc in the chain and therefore BEFORE it
                  # on the response path, which runs filters in reverse.
                  - name: envoy.filters.http.lua
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                      default_source_code:
                        inline_string: |
                          -- Named explicitly rather than stripped by shape: a
                          -- rule broad enough to catch "anything unexpected"
                          -- would eventually delete part of an answer.
                          local VENDOR_FIELDS = {
                            {{- range .fields }}
                            {{ . | quote }},
                            {{- end }}
                          }

                          local function removeField(text, name)
                            local key = '"' .. name .. '"%s*:%s*'
                            -- %b matches a balanced pair, so a nested object
                            -- or array is removed whole rather than cut in
                            -- half and left as broken JSON.
                            text = text:gsub(key .. '%b{},?', '')
                            text = text:gsub(key .. '%b[],?', '')
                            -- Numbers, true, false, null.
                            text = text:gsub(key .. '[%-%d%.eE%+]+,?', '')
                            text = text:gsub(key .. '%a+,?', '')
                            return text
                          end

                          local function strip(body)
                            local cleaned = body
                            for _, name in ipairs(VENDOR_FIELDS) do
                              cleaned = removeField(cleaned, name)
                            end
                            -- A removed field may have been last in its object
                            -- or array, leaving the comma before it.
                            cleaned = cleaned:gsub(',%s*}', '}')
                            cleaned = cleaned:gsub(',%s*%]', ']')
                            return cleaned
                          end

                          function envoy_on_response(handle)
                            local kind = handle:headers():get("content-type")
                            if kind == nil or not string.find(kind, "json", 1, true) then
                              return
                            end
                            local body = handle:body()
                            if body == nil or body:length() == 0 then
                              return
                            end
                            local text = tostring(body:getBytes(0, body:length()))
                            local touched = false
                            for _, name in ipairs(VENDOR_FIELDS) do
                              if string.find(text, name, 1, true) then touched = true end
                            end
                            if not touched then
                              return
                            end
                            body:setBytes(strip(text))
                          end
                  {{- end }}
                  {{- end }}
                  - name: envoy.filters.http.router
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
    - name: stats
      address:
        socket_address:
          address: 0.0.0.0
          port_value: {{ $e.statsPort }}
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: stats
                route_config:
                  name: stats
                  virtual_hosts:
                    - name: stats
                      domains: ["*"]
                      routes:
                        - match:
                            path: /ready
                          route:
                            cluster: envoy_admin
                        - match:
                            path: /stats/prometheus
                          route:
                            cluster: envoy_admin
                        - match:
                            prefix: "/"
                          direct_response:
                            status: 404
                            body:
                              inline_string: "not found"
                http_filters:
                  - name: envoy.filters.http.router
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  clusters:
    # The router's ext_proc service. STRICT_DNS against the headless Service
    # gives Envoy one endpoint per router pod; gRPC needs HTTP/2 explicitly.
    - name: semantic_router_ext_proc
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      connect_timeout: {{ $e.extProc.connectTimeout }}
      per_connection_buffer_limit_bytes: {{ int $e.perConnectionBufferLimitBytes }}
      typed_extension_protocol_options:
        envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
          "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
          explicit_http_config:
            http2_protocol_options:
              connection_keepalive:
                interval: 30s
                timeout: 10s
      load_assignment:
        cluster_name: semantic_router_ext_proc
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: {{ printf "%s.%s.svc.cluster.local" (include "srouter.router.extProcService" .) (include "srouter.router.namespace" .) }}
                      port_value: {{ include "srouter.router.grpcPort" . }}
    - name: litellm
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      connect_timeout: 5s
      per_connection_buffer_limit_bytes: {{ int $e.perConnectionBufferLimitBytes }}
      typed_extension_protocol_options:
        envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
          "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
          explicit_http_config:
            http_protocol_options: {}
      load_assignment:
        cluster_name: litellm
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: {{ include "srouter.litellm.host" . }}
                      port_value: {{ include "srouter.litellm.port" . }}
    {{- if .Values.envoy.routes.modelsFromRouter }}
    - name: semantic_router_api
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      connect_timeout: 5s
      load_assignment:
        cluster_name: semantic_router_api
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: {{ printf "%s.%s.svc.cluster.local" (include "srouter.router.fullname" .) (include "srouter.router.namespace" .) }}
                      port_value: {{ include "srouter.router.apiPort" . }}
    {{- end }}
    # Loopback to the admin interface, so the stats listener can expose two of
    # its endpoints without publishing the rest.
    - name: envoy_admin
      type: STATIC
      connect_timeout: 1s
      load_assignment:
        cluster_name: envoy_admin
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: {{ $e.adminPort }}
    {{- with $e.extraClusters }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end -}}

{{/* ── Management API clients ──────────────────────────────────────────────

The clients allowed to reach the router's management port, in a fixed order:
the WRITER first, the READER second.

They are two entries rather than one widened selector because they are two
workloads with two sets of labels — in the ram-extension release the API
carries no component label at all — and because the difference between them is
the security story:

  modelController  reconciles models and stored policy into the live config
                   with PATCH /api/v1/config, and is the only writer. One
                   writer on an ETag-guarded resource is what stops two
                   reconcilers losing an edit to last-write-wins.
  extensionApi     serves the routing-policy editor and calls the API
                   read-only: GET /api/v1/config, POST /api/v1/config/validate,
                   GET /api/v1/status, POST /api/v1/routing/preview. Its client
                   has no PatchConfig method.

Returns a YAML array so the template can render one rule per entry; an entry
with `enabled: false` is dropped, which is how one half is revoked without
losing the other.
*/}}
{{- define "srouter.apiClients" -}}
{{- $np := .Values.networkPolicy -}}
{{- $clients := list -}}
{{- $controller := $np.modelController | default dict -}}
{{- if $controller.enabled -}}
{{- $clients = append $clients (dict
      "name" "modelController"
      "description" "The model controller. The only WRITER of router config (PATCH /api/v1/config)."
      "podSelector" ($controller.podSelector | default dict)
      "namespaceSelector" ($controller.namespaceSelector | default dict)) -}}
{{- end -}}
{{- $api := $np.extensionApi | default dict -}}
{{- if $api.enabled -}}
{{- $clients = append $clients (dict
      "name" "extensionApi"
      "description" "The RAM extension API. READ-ONLY: config, validate, status and routing preview."
      "podSelector" ($api.podSelector | default dict)
      "namespaceSelector" ($api.namespaceSelector | default dict)) -}}
{{- end -}}
{{- toYaml $clients -}}
{{- end -}}

{{/* ── Routing helpers ─────────────────────────────────────────────────── */}}

{{/*
ingress-nginx's admission webhook rejects a dot in an Exact or Prefix path
(strict-validate-path-type), and serves ImplementationSpecific as a plain
prefix location anyway.

Invoke with a dict: (dict "className" ... "pathType" ... "path" ...)
*/}}
{{- define "srouter.ingressPathType" -}}
{{- if and (eq .className "nginx") (contains "." .path) -}}
ImplementationSpecific
{{- else -}}
{{- .pathType -}}
{{- end -}}
{{- end -}}

{{/* ── Validation ──────────────────────────────────────────────────────────

Fails the render on value combinations that produce a release which cannot
work, or — more importantly here — one that works but has silently removed a
security boundary. A template-time error names the value; the same mistake
found at runtime is a 404, a 401, or an unenforced guard.
*/}}
{{- define "srouter.validate" -}}
{{- $k := include "srouter.knobs" . | fromYaml -}}
{{- $sub := (index .Values "semantic-router") | default dict -}}

{{/* ── The Authorization pass-through ────────────────────────────────────
     This is the security linchpin of the whole design, and it works by
     OMISSION: the router leaves the caller's header alone only while it finds
     no credential of its own for the backend. Any of these keys on a backend
     ref would replace every caller's key with one shared static credential,
     and LiteLLM would see every request as the same principal. */}}
{{- $providers := (get ($sub.configOverride | default dict) "providers") | default dict -}}
{{- range $model := (get $providers "models") | default list -}}
{{- range $ref := (get $model "backend_refs") | default list -}}
{{- range $forbidden := list "access_key" "api_key" "api_key_env" "auth_header" "auth_prefix" -}}
{{- if hasKey $ref $forbidden -}}
{{- fail (printf "backend ref %q in semantic-router.configOverride sets %q. The router passes the CALLER's Authorization header to LiteLLM only while it has no credential of its own; setting one overwrites every caller's key with a single shared credential and collapses LiteLLM's per-key budgets, model permissions and spend attribution into one principal. Remove it." ((get $ref "name") | default "<unnamed>") $forbidden) -}}
{{- end -}}
{{- end -}}
{{- if hasKey $ref "chat_path" -}}
{{- fail (printf "backend ref %q in semantic-router.configOverride sets chat_path. It REPLACES the whole request path rather than being appended to base_url, so the request would miss LiteLLM's %s prefix. Leave it unset; the chart derives base_url with the /v1 suffix the OpenAI protocol needs." ((get $ref "name") | default "<unnamed>") (($k.litellm | default dict).serverRootPath | default "/litellm")) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- $cfgServices := (get ((get ($sub.configOverride | default dict) "global") | default dict) "services") | default dict -}}
{{- if hasKey $cfgServices "authz" -}}
{{- fail "semantic-router.configOverride sets global.services.authz. Adding an authz provider flips the credential resolver's fail_open default and makes the router rewrite the caller's Authorization header, which is exactly what this deployment relies on it NOT doing. If you need it, set fail_open explicitly and update the pass-through assertions in ci/validate.sh and tests/." -}}
{{- end -}}

{{- if hasKey ($sub.configOverride | default dict) "default_model" -}}
{{- fail "semantic-router.configOverride sets default_model, which is not a field in the v0.3 config. The fallback is an ordinary decision with the lowest priority and `conditions: []` — the skeleton in values.yaml has one called `fallback`." -}}
{{- end -}}

{{/* ── The LiteLLM base URL ─────────────────────────────────────────────── */}}
{{- $baseUrl := include "srouter.litellm.baseUrl" . -}}
{{- if not (hasSuffix "/v1" $baseUrl) -}}
{{- fail (printf "the LiteLLM base URL is %q, which does not end in /v1. A backend ref's base_url REPLACES the OpenAI protocol's canonical base path, so a URL without it produces <root>/chat/completions and a 404. Set global.semanticRouter.litellm.baseUrl to the full OpenAI base, e.g. http://litellm:4000/litellm/v1." $baseUrl) -}}
{{- end -}}

{{/* ── Management API ───────────────────────────────────────────────────── */}}
{{- $mgmt := $k.managementApi | default dict -}}
{{- $mgmtAuth := $mgmt.auth | default dict -}}
{{- $mode := $mgmtAuth.mode | default "bearer" -}}
{{- if not (has $mode (list "bearer" "disabled")) -}}
{{- fail (printf "global.semanticRouter.managementApi.auth.mode must be \"bearer\" or \"disabled\", got %q" $mode) -}}
{{- end -}}
{{- if eq $mode "bearer" -}}
{{- $secretName := include "srouter.managementToken.secretName" . -}}
{{- if not (has $secretName ($sub.envFromSecrets | default list)) -}}
{{- fail (printf "the management API token Secret is %q, but semantic-router.envFromSecrets is %v. Helm cannot template a subchart's values, so the two are written separately and checked here: add %q to semantic-router.envFromSecrets, or the router starts with no admin token and rejects every call from the model controller." $secretName ($sub.envFromSecrets | default list) $secretName) -}}
{{- end -}}
{{- if ne (include "srouter.managementToken.secretKey" .) ($mgmtAuth.tokenEnv | default "VSR_MGMT_TOKEN") -}}
{{- fail (printf "the management token Secret key (%q) must equal global.semanticRouter.managementApi.auth.tokenEnv (%q). envFromSecrets projects each key of the Secret as an environment variable of the same name, so a different key sets a variable the router never reads." (include "srouter.managementToken.secretKey" .) ($mgmtAuth.tokenEnv | default "VSR_MGMT_TOKEN")) -}}
{{- end -}}
{{- end -}}

{{/* ── Guards ──────────────────────────────────────────────────────────── */}}
{{- $guards := $k.guards | default dict -}}
{{- range $name, $guard := $guards -}}
{{- if $guard.enabled -}}
{{- if not $guard.modelPath -}}
{{- fail (printf "global.semanticRouter.guards.%s.enabled is true but modelPath is empty. A guard with no entry in global.model_catalog.system loads no classifier and scores nothing — it does not fail, it silently allows everything." $name) -}}
{{- end -}}
{{- if not (has ($guard.onError | default "block") (list "allow" "block")) -}}
{{- fail (printf "global.semanticRouter.guards.%s.onError must be \"allow\" or \"block\", got %q" $name ($guard.onError | default "")) -}}
{{- end -}}
{{- $threshold := $guard.threshold | default 0.0 -}}
{{- if or (le (float64 $threshold) 0.0) (gt (float64 $threshold) 1.0) -}}
{{- fail (printf "global.semanticRouter.guards.%s.threshold must be greater than 0 and at most 1, got %v" $name $threshold) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and (or ($guards.jailbreak | default dict).enabled (($guards.pii | default dict).enabled)) (not ($sub.persistence | default dict).enabled) -}}
{{- fail "a guard is enabled but semantic-router.persistence.enabled is false. The classifier checkpoints are downloaded on first start; without a volume every pod restart re-downloads several gigabytes before the router becomes ready." -}}
{{- end -}}

{{/* ── Semantic cache ──────────────────────────────────────────────────── */}}
{{- $cache := $k.semanticCache | default dict -}}
{{- if $cache.enabled -}}
{{- if not (has ($cache.backend | default "memory") (list "memory" "redis")) -}}
{{- fail (printf "global.semanticRouter.semanticCache.backend must be \"memory\" or \"redis\", got %q" ($cache.backend | default "")) -}}
{{- end -}}
{{- if and (eq ($cache.backend | default "memory") "redis") (not (($cache.redis | default dict).address)) -}}
{{- fail "global.semanticRouter.semanticCache.backend is \"redis\" but semanticCache.redis.address is empty. Point it at a server you already run — the Valkey the litellm chart deploys is the obvious one (e.g. litellm-valkey:6379); the upstream bundled Redis stays disabled because bitnami withdrew its versioned image tags." -}}
{{- end -}}
{{- end -}}

{{/* ── Replicas ────────────────────────────────────────────────────────── */}}
{{- $routerReplicas := int ($sub.replicaCount | default 1) -}}
{{- if gt $routerReplicas 1 -}}
{{- if and $cache.enabled (eq ($cache.backend | default "memory") "memory") -}}
{{- fail (printf "semantic-router.replicaCount is %d with an in-process semantic cache. Each replica would keep its own cache, so the same prompt gets a cached answer or a fresh one depending on which pod answered. Set global.semanticRouter.semanticCache.backend: redis with a shared address first." $routerReplicas) -}}
{{- end -}}
{{- end -}}

{{/* ── Envoy ───────────────────────────────────────────────────────────── */}}
{{- if eq (int .Values.envoy.listenerPort) (int .Values.envoy.statsPort) -}}
{{- fail "envoy.listenerPort and envoy.statsPort must differ: the stats listener publishes /ready and /stats/prometheus, which must not be reachable on the public listener." -}}
{{- end -}}
{{- if eq (int .Values.envoy.adminPort) (int .Values.envoy.statsPort) -}}
{{- fail "envoy.adminPort and envoy.statsPort must differ: the stats listener proxies a subset of the admin interface and cannot bind the same port." -}}
{{- end -}}
{{/* ── Management API clients ──────────────────────────────────────────── */}}
{{- if .Values.networkPolicy.enabled -}}
{{- $clients := include "srouter.apiClients" . | fromYamlArray -}}
{{- if not $clients -}}
{{- fail "every client of the router's management API is disabled, so nothing can write or read routing policy and the model controller's reconcile loop will time out on every pass. Enable networkPolicy.modelController, or set networkPolicy.enabled: false if the policy is managed elsewhere." -}}
{{- end -}}
{{- range $client := $clients -}}
{{- if and (not $client.podSelector) (not $client.namespaceSelector) -}}
{{- fail (printf "networkPolicy.%s is enabled with no podSelector and no namespaceSelector, which admits EVERY pod in this namespace to the management API — a port that can redirect prompts to a different LiteLLM key boundary. Name the workload, or put a deliberate blanket rule in networkPolicy.extraIngress where it is visible as one." $client.name) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if and .Values.envoy.routes.modelsFromRouter (not .Values.networkPolicy.allowEnvoyToManagementApi) (.Values.networkPolicy.enabled) -}}
{{- fail "envoy.routes.modelsFromRouter sends /v1/models to the router's management port, but networkPolicy.allowEnvoyToManagementApi is false, so the policy this chart renders would drop that traffic. Enable both, or neither." -}}
{{- end -}}
{{- if not .Values.envoy.routes.allowedPaths -}}
{{- fail "envoy.routes.allowedPaths is empty, so every request would hit the catch-all deny and the release would publish nothing." -}}
{{- end -}}

{{/* ── Routing ─────────────────────────────────────────────────────────── */}}
{{- $r := .Values.routing -}}
{{- if and $r.ingress.enabled (not $r.hosts) -}}
{{- fail "routing.ingress.enabled requires at least one entry in routing.hosts: an Ingress rule without a host matches every hostname on the controller." -}}
{{- end -}}
{{- if and $r.httpProxy.enabled (not $r.httpProxy.delegated) (not $r.hosts) -}}
{{- fail "routing.httpProxy.enabled requires routing.hosts, because a root HTTPProxy owns an FQDN. A child proxy (routing.httpProxy.delegated: true) inherits its parent's hostname and needs none." -}}
{{- end -}}
{{- if and $r.httpRoute.enabled (not $r.httpRoute.parentRefs) -}}
{{- fail "routing.httpRoute.enabled requires routing.httpRoute.parentRefs: an HTTPRoute attached to no Gateway is accepted by the API server and then ignored." -}}
{{- end -}}
{{- if and $r.tls.enabled (not $r.tls.secretName) (not $r.route.enabled) (not $r.httpProxy.tls.passthrough) -}}
{{- fail "routing.tls.enabled requires routing.tls.secretName (a kubernetes.io/tls Secret)." -}}
{{- end -}}
{{- end -}}
