{{/* ── Naming ──────────────────────────────────────────────────────────── */}}

{{- define "litellm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "litellm.fullname" -}}
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

{{- define "litellm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels. `component` is pinned to `proxy` so a future split into
gateway / backend / ui can add its own components without colliding with an
existing release's immutable Deployment selector.
*/}}
{{- define "litellm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "litellm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: proxy
{{- end -}}

{{- define "litellm.labels" -}}
helm.sh/chart: {{ include "litellm.chart" . }}
{{ include "litellm.selectorLabels" . }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Labels for objects that are not the proxy workload (the migration Job), so
they are not swept up by the proxy's Service selector.
*/}}
{{- define "litellm.migrationLabels" -}}
helm.sh/chart: {{ include "litellm.chart" . }}
app.kubernetes.io/name: {{ include "litellm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: migrations
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "litellm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "litellm.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
The container tag, and the image reference built from it.

`image.tag` is empty by default and falls back to the chart's appVersion, which
is the upstream LiteLLM release this chart targets. Both the proxy and the
migration Job go through this helper, so they can never be pinned apart.
*/}}
{{- define "litellm.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion -}}
{{- end -}}

{{- define "litellm.image" -}}
{{- printf "%s:%s" .Values.image.repository (include "litellm.imageTag" .) -}}
{{- end -}}

{{/*
ServiceAccount for the migration Job.

With Helm hooks enabled the Job is created before the chart's ordinary
resources, so a ServiceAccount this chart creates does not exist yet and the
hook pod is rejected. Fall back to `default` in that case. An explicit
migrationJob.serviceAccountName always wins, which is how a Job that needs its
own cloud IAM identity gets one.
*/}}
{{- define "litellm.migrationServiceAccountName" -}}
{{- if .Values.migrationJob.serviceAccountName -}}
{{- .Values.migrationJob.serviceAccountName -}}
{{- else if and .Values.migrationJob.hooks.helm.enabled .Values.serviceAccount.create -}}
default
{{- else -}}
{{- include "litellm.serviceAccountName" . -}}
{{- end -}}
{{- end -}}

{{/* ── Feature switches ────────────────────────────────────────────────── */}}

{{/* Non-empty when this release talks to PostgreSQL. */}}
{{- define "litellm.databaseEnabled" -}}
{{- if or (eq .Values.modelManagement.mode "database") .Values.database.enabled -}}true{{- end -}}
{{- end -}}

{{/* Non-empty when the migration Job is rendered. */}}
{{- define "litellm.migrationEnabled" -}}
{{- if and (include "litellm.databaseEnabled" .) .Values.migrationJob.enabled -}}true{{- end -}}
{{- end -}}

{{/* ── Config file ─────────────────────────────────────────────────────── */}}

{{- define "litellm.configMapName" -}}
{{- if .Values.config.existingConfigMap.name -}}
{{- .Values.config.existingConfigMap.name -}}
{{- else -}}
{{- printf "%s-config" (include "litellm.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "litellm.configMapKey" -}}
{{- if .Values.config.existingConfigMap.name -}}
{{- default "config.yaml" .Values.config.existingConfigMap.key -}}
{{- else -}}
config.yaml
{{- end -}}
{{- end -}}

{{/*
The proxy's config.yaml.

Model entries are added only in the config flow, or in the database flow when
modelManagement.seedFromConfig asks for a bootstrap floor. Keys you set in
proxyConfig always win over the chart's defaults, so an explicit master_key,
store_model_in_db, or coordination_redis is never overwritten.
*/}}
{{- define "litellm.proxyConfig" -}}
{{- $config := deepCopy (default dict .Values.proxyConfig) -}}
{{- $general := deepCopy (default dict (get $config "general_settings")) -}}
{{- if not (hasKey $general "master_key") -}}
{{- $_ := set $general "master_key" "os.environ/PROXY_MASTER_KEY" -}}
{{- end -}}
{{- if eq .Values.modelManagement.mode "database" -}}
{{- if not (hasKey $general "store_model_in_db") -}}
{{- $_ := set $general "store_model_in_db" true -}}
{{- end -}}
{{- end -}}
{{- if and .Values.redis.host .Values.redis.coordination (not (hasKey $general "coordination_redis")) -}}
{{- $coordination := dict -}}
{{- if .Values.redis.sentinel.enabled -}}
{{- $_ := set $coordination "sentinel_nodes" (list (list .Values.redis.host (int .Values.redis.port))) -}}
{{- $_ := set $coordination "service_name" (default "mymaster" .Values.redis.sentinel.masterSet) -}}
{{- else -}}
{{- $_ := set $coordination "host" "os.environ/REDIS_HOST" -}}
{{- $_ := set $coordination "port" "os.environ/REDIS_PORT" -}}
{{- end -}}
{{- if .Values.redis.existingSecret.name -}}
{{- $_ := set $coordination "password" "os.environ/REDIS_PASSWORD" -}}
{{- end -}}
{{- $_ := set $general "coordination_redis" $coordination -}}
{{- end -}}
{{- $_ := set $config "general_settings" $general -}}
{{- $models := default list (get $config "model_list") -}}
{{- if or (eq .Values.modelManagement.mode "config") .Values.modelManagement.seedFromConfig -}}
{{- $models = concat $models (default list .Values.models) -}}
{{- end -}}
{{- if $models -}}
{{- $_ := set $config "model_list" $models -}}
{{- else -}}
{{- $_ := unset $config "model_list" -}}
{{- end -}}
{{- toYaml $config -}}
{{- end -}}

{{/* ── Secrets ─────────────────────────────────────────────────────────── */}}

{{- define "litellm.masterKeySecretName" -}}
{{- if .Values.masterKey.existingSecret.name -}}
{{- .Values.masterKey.existingSecret.name -}}
{{- else -}}
{{- printf "%s-masterkey" (include "litellm.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "litellm.masterKeySecretKey" -}}
{{- if .Values.masterKey.existingSecret.name -}}
{{- default "masterkey" .Values.masterKey.existingSecret.key -}}
{{- else -}}
masterkey
{{- end -}}
{{- end -}}

{{/* ── Environment ─────────────────────────────────────────────────────── */}}

{{/*
Discrete DATABASE_* variables. The chart never assembles the connection URL
itself: the proxy's own DatabaseURLSettings builds and percent-encodes it, so a
password holding URL-reserved characters survives. Pass a pre-built URL through
database.existingSecret.urlKey when the discrete fields cannot express it.
*/}}
{{- define "litellm.databaseEnv" -}}
{{- if include "litellm.databaseEnabled" . }}
{{- $db := .Values.database }}
{{- $secret := $db.existingSecret }}
{{- if $secret.urlKey }}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ required "database.existingSecret.name is required when database.existingSecret.urlKey is set" $secret.name }}
      key: {{ $secret.urlKey }}
{{- else }}
- name: DATABASE_HOST
{{- if $secret.hostKey }}
  valueFrom:
    secretKeyRef:
      name: {{ required "database.existingSecret.name is required when database.existingSecret.hostKey is set" $secret.name }}
      key: {{ $secret.hostKey }}
{{- else }}
  value: {{ required "database.host is required when the database flow is enabled" $db.host | quote }}
{{- end }}
- name: DATABASE_PORT
  value: {{ $db.port | quote }}
- name: DATABASE_NAME
  value: {{ required "database.name is required when the database flow is enabled" $db.name | quote }}
{{- with $db.schema }}
- name: DATABASE_SCHEMA
  value: {{ . | quote }}
{{- end }}
- name: DATABASE_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ required "database.existingSecret.name is required when the database flow is enabled" $secret.name }}
      key: {{ $secret.usernameKey }}
{{- if eq $db.auth.mode "password" }}
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $secret.name }}
      key: {{ $secret.passwordKey }}
{{- end }}
{{- end }}
{{- if eq $db.auth.mode "awsIam" }}
- name: IAM_TOKEN_DB_AUTH
  value: "true"
{{- else if eq $db.auth.mode "azureEntra" }}
- name: AZURE_POSTGRESQL_AUTH
  value: "true"
{{- end }}
{{- with $db.sslMode }}
- name: DATABASE_SSLMODE
  value: {{ . | quote }}
{{- end }}
{{- with $db.sslRootCert }}
- name: DATABASE_SSLROOTCERT
  value: {{ . | quote }}
{{- end }}
{{- if $db.disablePreparedStatements }}
- name: DATABASE_DISABLE_PREPARED_STATEMENTS
  value: "true"
{{- end }}
{{- with $db.maxIdleConnectionLifetime }}
- name: DATABASE_MAX_IDLE_CONNECTION_LIFETIME
  value: {{ . | quote }}
{{- end }}
{{- if $db.readReplica.enabled }}
{{- $rr := $db.readReplica }}
{{- $rrSecret := $rr.existingSecret }}
{{- $rrSecretName := default $secret.name $rrSecret.name }}
{{- if $rrSecret.urlKey }}
- name: DATABASE_URL_READ_REPLICA
  valueFrom:
    secretKeyRef:
      name: {{ required "database.readReplica.existingSecret.name or database.existingSecret.name is required" $rrSecretName }}
      key: {{ $rrSecret.urlKey }}
{{- else }}
- name: DATABASE_HOST_READ_REPLICA
{{- if $rrSecret.hostKey }}
  valueFrom:
    secretKeyRef:
      name: {{ required "database.readReplica.existingSecret.name or database.existingSecret.name is required" $rrSecretName }}
      key: {{ $rrSecret.hostKey }}
{{- else }}
  value: {{ required "database.readReplica.host is required when the read replica is enabled" $rr.host | quote }}
{{- end }}
{{- with $rr.port }}
- name: DATABASE_PORT_READ_REPLICA
  value: {{ . | quote }}
{{- end }}
{{- with $rrSecret.usernameKey }}
- name: DATABASE_USERNAME_READ_REPLICA
  valueFrom:
    secretKeyRef:
      name: {{ $rrSecretName }}
      key: {{ . }}
{{- end }}
{{- if eq $db.auth.mode "password" }}
{{- with $rrSecret.passwordKey }}
- name: DATABASE_PASSWORD_READ_REPLICA
  valueFrom:
    secretKeyRef:
      name: {{ $rrSecretName }}
      key: {{ . }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $db.connectionPool.enabled }}
- name: LITELLM_PGBOUNCER_ENABLED
  value: "true"
- name: LITELLM_PGBOUNCER_MAX_DB_CONNECTIONS
  value: {{ $db.connectionPool.maxDbConnections | quote }}
- name: LITELLM_PGBOUNCER_MAX_CLIENT_CONN
  value: {{ $db.connectionPool.maxClientConn | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "litellm.redisEnv" -}}
{{- if .Values.redis.host }}
- name: REDIS_HOST
  value: {{ .Values.redis.host | quote }}
- name: REDIS_PORT
  value: {{ .Values.redis.port | quote }}
{{- with .Values.redis.existingSecret.name }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: {{ $.Values.redis.existingSecret.passwordKey }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Environment for the proxy container.

DISABLE_SCHEMA_UPDATE is emitted last, after envVars and extraEnvVars, so a
user-supplied value cannot silently shadow it under last-wins duplicate-env
semantics. While the migration Job owns the schema, the proxy must not run its
own startup push, or N replicas race one database on every rollout.
*/}}
{{- define "litellm.env" -}}
- name: HOST
  value: {{ .Values.listen | default "0.0.0.0" | quote }}
- name: PORT
  value: {{ .Values.service.port | quote }}
- name: PROXY_MASTER_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "litellm.masterKeySecretName" . }}
      key: {{ include "litellm.masterKeySecretKey" . }}
{{- with .Values.license.existingSecret.name }}
- name: LITELLM_LICENSE
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: {{ $.Values.license.existingSecret.key }}
{{- end }}
{{- with .Values.ui.credentialsSecret.name }}
- name: UI_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: {{ $.Values.ui.credentialsSecret.usernameKey }}
- name: UI_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: {{ $.Values.ui.credentialsSecret.passwordKey }}
{{- end }}
{{- include "litellm.databaseEnv" . }}
{{- include "litellm.redisEnv" . }}
{{- if .Values.metricsServer.enabled }}
- name: PROMETHEUS_METRICS_PORT
  value: {{ .Values.metricsServer.port | quote }}
{{- end }}
{{- if and .Values.logLevel (not (hasKey (default dict .Values.envVars) "LITELLM_LOG")) }}
- name: LITELLM_LOG
  value: {{ .Values.logLevel | quote }}
{{- end }}
{{- range $key, $value := .Values.envVars }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- with .Values.extraEnvVars }}
{{ toYaml . | trimSuffix "\n" }}
{{- end }}
{{- if include "litellm.migrationEnabled" . }}
- name: DISABLE_SCHEMA_UPDATE
  value: "true"
{{- end }}
{{- end -}}

{{- define "litellm.envFrom" -}}
{{- range .Values.environmentSecrets }}
- secretRef:
    name: {{ . }}
{{- end }}
{{- range .Values.environmentConfigMaps }}
- configMapRef:
    name: {{ . }}
{{- end }}
{{- end -}}

{{/* ── Routing ─────────────────────────────────────────────────────────── */}}

{{/*
ingress-nginx's admission webhook rejects a dot in an Exact or Prefix path
(strict-validate-path-type), and it serves ImplementationSpecific as a plain
prefix location anyway, so a dotted path takes that type there.

Invoke with a dict: (dict "className" ... "pathType" ... "path" ...)
*/}}
{{- define "litellm.ingressPathType" -}}
{{- if and (eq .className "nginx") (contains "." .path) -}}
ImplementationSpecific
{{- else -}}
{{- .pathType -}}
{{- end -}}
{{- end -}}

{{/* Annotations shared by every routing object. */}}
{{- define "litellm.routingAnnotations" -}}
{{- $merged := merge (dict) (default dict .extra) (default dict .shared) (default dict .common) -}}
{{- with $merged }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* ── Validation ──────────────────────────────────────────────────────── */}}

{{/*
Fail the render on value combinations that produce a workload which cannot
start, or routing that silently publishes nothing. A template-time error names
the value; the same mistake found at runtime is an opaque CrashLoopBackOff.
*/}}
{{- define "litellm.validate" -}}
{{- if not (has .Values.modelManagement.mode (list "config" "database")) -}}
{{- fail (printf "modelManagement.mode must be \"config\" or \"database\", got %q" .Values.modelManagement.mode) -}}
{{- end -}}

{{- if and (eq .Values.modelManagement.mode "config") (not .Values.config.existingConfigMap.name) -}}
{{- if not (or .Values.models (get (default dict .Values.proxyConfig) "model_list")) -}}
{{- fail "modelManagement.mode is \"config\" but no models are defined. Add entries to `models`, or switch to modelManagement.mode: database to manage models at runtime." -}}
{{- end -}}
{{- end -}}

{{- if and (eq .Values.modelManagement.mode "config") .Values.modelManagement.seedFromConfig -}}
{{- fail "modelManagement.seedFromConfig applies to the database flow only. In config mode every model in `models` is already rendered into config.yaml." -}}
{{- end -}}

{{- if include "litellm.databaseEnabled" . -}}
{{- if not (has .Values.database.auth.mode (list "password" "awsIam" "azureEntra")) -}}
{{- fail (printf "database.auth.mode must be one of password, awsIam, azureEntra, got %q" .Values.database.auth.mode) -}}
{{- end -}}
{{- if not .Values.database.existingSecret.name -}}
{{- fail "database.existingSecret.name is required when the database flow is enabled. This chart reads database credentials from a Secret only and accepts no inline password." -}}
{{- end -}}
{{- end -}}

{{- if and .Values.metricsServer.enabled (eq (int .Values.metricsServer.port) (int .Values.service.port)) -}}
{{- fail "metricsServer.port must differ from service.port" -}}
{{- end -}}

{{- if has (include "litellm.imageTag" .) (list "latest" "main-latest") -}}
{{- fail (printf "image.tag must not be %q. The proxy and the migration Job resolve the tag independently at pull time, so a tag that moves between the Job completing and a pod restarting runs a different proxy version against the schema that Job just migrated. Leave image.tag empty to follow the chart's appVersion, or pin a release." (include "litellm.imageTag" .)) -}}
{{- end -}}

{{- if and .Values.pdb.enabled (not (or .Values.pdb.minAvailable .Values.pdb.maxUnavailable)) -}}
{{- fail "pdb.enabled requires exactly one of pdb.minAvailable or pdb.maxUnavailable" -}}
{{- end -}}
{{- if and .Values.pdb.minAvailable .Values.pdb.maxUnavailable -}}
{{- fail "set exactly one of pdb.minAvailable or pdb.maxUnavailable, not both" -}}
{{- end -}}

{{- if and .Values.autoscaling.enabled (gt (int .Values.autoscaling.minReplicas) (int .Values.autoscaling.maxReplicas)) -}}
{{- fail "autoscaling.minReplicas must not exceed autoscaling.maxReplicas" -}}
{{- end -}}

{{- range $key, $value := .Values.podLabels -}}
{{- if has $key (list "app.kubernetes.io/name" "app.kubernetes.io/instance" "app.kubernetes.io/component") -}}
{{- fail (printf "podLabels cannot set %s: it is part of the Deployment's immutable selector" $key) -}}
{{- end -}}
{{- end -}}

{{- if .Values.routing.ingress.enabled -}}
{{- if not .Values.routing.hosts -}}
{{- fail "routing.hosts is required when routing.ingress.enabled is true" -}}
{{- end -}}
{{- if and .Values.routing.tls.enabled (not .Values.routing.tls.secretName) -}}
{{- fail "routing.tls.secretName is required when routing.tls.enabled is true and an Ingress is rendered" -}}
{{- end -}}
{{- end -}}

{{- if .Values.routing.httpRoute.enabled -}}
{{- if not .Values.routing.httpRoute.parentRefs -}}
{{- fail "routing.httpRoute.parentRefs is required when routing.httpRoute.enabled is true. An HTTPRoute with no parent attaches to no Gateway and publishes nothing." -}}
{{- end -}}
{{- end -}}

{{- if .Values.routing.httpProxy.enabled -}}
{{- if not .Values.routing.hosts -}}
{{- fail "routing.hosts is required when routing.httpProxy.enabled is true" -}}
{{- end -}}
{{- if gt (len .Values.routing.hosts) 1 -}}
{{- fail "routing.httpProxy supports one virtual host. Set a single entry in routing.hosts, or render one release per host." -}}
{{- end -}}
{{- $secretName := default .Values.routing.tls.secretName .Values.routing.httpProxy.tls.secretName -}}
{{- if and .Values.routing.tls.enabled (not $secretName) (not .Values.routing.httpProxy.tls.passthrough) -}}
{{- fail "routing.tls.secretName or routing.httpProxy.tls.secretName is required when TLS is enabled without passthrough" -}}
{{- end -}}
{{- end -}}

{{- if .Values.routing.route.enabled -}}
{{- if not (has .Values.routing.route.tls.termination (list "edge" "reencrypt" "passthrough" "")) -}}
{{- fail (printf "routing.route.tls.termination must be edge, reencrypt, or passthrough, got %q" .Values.routing.route.tls.termination) -}}
{{- end -}}
{{- if gt (len .Values.routing.hosts) 1 -}}
{{- fail "routing.route supports one host. Set a single entry in routing.hosts, or leave it empty to let OpenShift generate one." -}}
{{- end -}}
{{- end -}}
{{- end -}}
