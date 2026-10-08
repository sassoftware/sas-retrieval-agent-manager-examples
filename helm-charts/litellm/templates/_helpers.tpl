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

{{/* Non-empty when the database initialization Job is rendered. */}}
{{- define "litellm.dbInitEnabled" -}}
{{- if and (include "litellm.databaseEnabled" .) .Values.database.init.enabled -}}true{{- end -}}
{{- end -}}

{{/* Non-empty when the Keycloak bootstrap Job is rendered. */}}
{{- define "litellm.keycloakBootstrapEnabled" -}}
{{- if and .Values.sso.enabled .Values.sso.keycloakBootstrap.enabled -}}true{{- end -}}
{{- end -}}

{{/* ── Single sign-on ──────────────────────────────────────────────────── */}}

{{/*
The browser-facing base URL of this proxy.

Derived from the routing block when not given, because every part of it is
already stated there: whether TLS is on, the host, and the path the release is
published under. Deriving it keeps the redirect URI from drifting out of step
with the Ingress after someone edits one and forgets the other.
*/}}
{{- define "litellm.proxyBaseUrl" -}}
{{- if .Values.sso.proxyBaseUrl -}}
{{- .Values.sso.proxyBaseUrl | trimSuffix "/" -}}
{{- else -}}
{{- $scheme := ternary "https" "http" .Values.routing.tls.enabled -}}
{{- $host := first .Values.routing.hosts -}}
{{- $path := .Values.routing.path | default "/" | trimSuffix "/" -}}
{{- printf "%s://%s%s" $scheme $host $path -}}
{{- end -}}
{{- end -}}

{{- define "litellm.sso.secretName" -}}
{{- if .Values.sso.clientSecret.existingSecret.name -}}
{{- .Values.sso.clientSecret.existingSecret.name -}}
{{- else -}}
{{- printf "%s-sso" (include "litellm.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "litellm.sso.secretKey" -}}
{{- if .Values.sso.clientSecret.existingSecret.name -}}
{{- default "client-secret" .Values.sso.clientSecret.existingSecret.key -}}
{{- else -}}
client-secret
{{- end -}}
{{- end -}}

{{/* Non-empty when the chart owns the SSO Secret rather than referencing one. */}}
{{- define "litellm.sso.ownsSecret" -}}
{{- if not .Values.sso.clientSecret.existingSecret.name -}}true{{- end -}}
{{- end -}}

{{/*
The bootstrap administrator's password Secret.

Falls back to the chart's own SSO Secret, so the common case needs no second
Secret and no extra values.
*/}}
{{- define "litellm.sso.adminUserSecretName" -}}
{{- $u := .Values.sso.keycloakBootstrap.adminUser -}}
{{- if $u.password.existingSecret.name -}}
{{- $u.password.existingSecret.name -}}
{{- else -}}
{{- include "litellm.sso.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "litellm.sso.adminUserSecretKey" -}}
{{- $u := .Values.sso.keycloakBootstrap.adminUser -}}
{{- if $u.password.existingSecret.name -}}
{{- default "password" $u.password.existingSecret.key -}}
{{- else -}}
admin-user-password
{{- end -}}
{{- end -}}

{{- define "litellm.keycloakBootstrap.fullname" -}}
{{- printf "%s-keycloak-bootstrap" (include "litellm.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "litellm.keycloakBootstrap.labels" -}}
helm.sh/chart: {{ include "litellm.chart" . }}
app.kubernetes.io/name: {{ include "litellm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: keycloak-bootstrap
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Environment that turns on SSO.

LiteLLM reads its generic OIDC provider entirely from the environment, so this
is the whole integration.
*/}}
{{- define "litellm.ssoEnv" -}}
{{- if .Values.sso.enabled }}
- name: PROXY_BASE_URL
  value: {{ include "litellm.proxyBaseUrl" . | quote }}
- name: GENERIC_CLIENT_ID
  value: {{ .Values.sso.clientId | quote }}
- name: GENERIC_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "litellm.sso.secretName" . }}
      key: {{ include "litellm.sso.secretKey" . }}
- name: GENERIC_AUTHORIZATION_ENDPOINT
  value: {{ required "sso.authorizationEndpoint is required when sso.enabled is true" .Values.sso.authorizationEndpoint | quote }}
- name: GENERIC_TOKEN_ENDPOINT
  value: {{ required "sso.tokenEndpoint is required when sso.enabled is true" .Values.sso.tokenEndpoint | quote }}
- name: GENERIC_USERINFO_ENDPOINT
  value: {{ required "sso.userinfoEndpoint is required when sso.enabled is true" .Values.sso.userinfoEndpoint | quote }}
{{- with .Values.sso.scope }}
- name: GENERIC_SCOPE
  value: {{ . | quote }}
{{- end }}
{{- with .Values.sso.clientState }}
- name: GENERIC_CLIENT_STATE
  value: {{ . | quote }}
{{- end }}
{{- if .Values.sso.usePkce }}
- name: GENERIC_CLIENT_USE_PKCE
  value: "true"
{{- end }}
{{- with .Values.sso.logoutUrl }}
- name: PROXY_LOGOUT_URL
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── Database initialization ─────────────────────────────────────────── */}}

{{- define "litellm.dbInit.fullname" -}}
{{- printf "%s-db-init" (include "litellm.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels for the initialization Job and its owned objects. `component: db-init`
keeps them out of the proxy Service's selector.
*/}}
{{- define "litellm.dbInit.labels" -}}
helm.sh/chart: {{ include "litellm.chart" . }}
app.kubernetes.io/name: {{ include "litellm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: db-init
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Non-empty when the chart owns the admin Secret, rather than referencing one. */}}
{{- define "litellm.dbInit.ownsAdminSecret" -}}
{{- if not .Values.database.init.admin.existingSecret.name -}}true{{- end -}}
{{- end -}}

{{- define "litellm.dbInit.adminSecretName" -}}
{{- if .Values.database.init.admin.existingSecret.name -}}
{{- .Values.database.init.admin.existingSecret.name -}}
{{- else -}}
{{- printf "%s-admin" (include "litellm.dbInit.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "litellm.dbInit.adminUsernameKey" -}}
{{- if .Values.database.init.admin.existingSecret.name -}}
{{- default "username" .Values.database.init.admin.existingSecret.usernameKey -}}
{{- else -}}
username
{{- end -}}
{{- end -}}

{{- define "litellm.dbInit.adminPasswordKey" -}}
{{- if .Values.database.init.admin.existingSecret.name -}}
{{- default "password" .Values.database.init.admin.existingSecret.passwordKey -}}
{{- else -}}
password
{{- end -}}
{{- end -}}

{{/*
Non-empty when the cleanup container is rendered.

Cleanup erases the admin credentials from the Secret the chart created. With
`admin.existingSecret` the chart created nothing, so there is nothing of ours
to erase and no RBAC to grant — the operator owns that Secret's lifecycle.
*/}}
{{- define "litellm.dbInit.cleanupEnabled" -}}
{{- if and (include "litellm.dbInitEnabled" .) .Values.database.init.cleanup (include "litellm.dbInit.ownsAdminSecret" .) -}}true{{- end -}}
{{- end -}}

{{- define "litellm.dbInit.serviceAccountName" -}}
{{- if .Values.database.init.serviceAccount.create -}}
{{- default (include "litellm.dbInit.fullname" .) .Values.database.init.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.database.init.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
The container that talks to PostgreSQL.

Rendered as an init container when cleanup is on and as the only ordinary
container when it is off, so it is defined once here rather than twice in the
Job. Kubernetes runs init containers to completion before any ordinary
container starts, which is exactly the ordering the cleanup step needs: a
failed initialization never reaches the step that erases the credentials.
*/}}
{{- define "litellm.dbInit.psqlContainer" -}}
- name: db-init
  image: "{{ .Values.database.init.image.repository }}:{{ .Values.database.init.image.tag }}"
  imagePullPolicy: {{ .Values.database.init.image.pullPolicy }}
  command: ["/bin/sh", "/scripts/init.sh"]
  {{- with .Values.database.init.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  env:
    - name: PGHOST
      {{- if .Values.database.existingSecret.hostKey }}
      valueFrom:
        secretKeyRef:
          name: {{ .Values.database.existingSecret.name }}
          key: {{ .Values.database.existingSecret.hostKey }}
      {{- else }}
      value: {{ .Values.database.host | quote }}
      {{- end }}
    - name: PGPORT
      value: {{ .Values.database.port | quote }}
    {{- /* The maintenance database. CREATE DATABASE cannot run inside the
           database being created, so the session starts here. */}}
    - name: PGDATABASE
      value: {{ .Values.database.init.admin.database | quote }}
    {{- $sslMode := .Values.database.init.admin.sslMode | default .Values.database.sslMode }}
    {{- with $sslMode }}
    - name: PGSSLMODE
      value: {{ . | quote }}
    {{- end }}
    {{- with .Values.database.sslRootCert }}
    - name: PGSSLROOTCERT
      value: {{ . | quote }}
    {{- end }}
    - name: DB_NAME
      value: {{ .Values.database.name | quote }}
    - name: DB_SCHEMA
      value: {{ .Values.database.schema | quote }}
    - name: WAIT_TIMEOUT
      value: {{ .Values.database.init.waitTimeout | quote }}
  {{- with .Values.database.init.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: scripts
      mountPath: /scripts
      readOnly: true
    - name: admin-credentials
      mountPath: /secret/admin
      readOnly: true
    - name: service-credentials
      mountPath: /secret/service
      readOnly: true
    {{- with .Values.volumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end -}}

{{/*
Hook annotations shared by the initialization Job and the objects it needs.

The Job runs as a Helm hook so that it completes before the migration Job,
which is itself a hook. Everything the Job consumes — the Secret, the scripts,
the RBAC — therefore has to be a hook too, at a lower weight; an ordinary
resource does not exist yet when a pre-install hook runs.

Invoke with a dict: (dict "root" $ "weight" "-10").
*/}}
{{- define "litellm.dbInit.hookAnnotations" -}}
{{- include "litellm.hookAnnotations" (dict "hooks" .root.Values.database.init.hooks "weight" .weight) -}}
{{- end -}}

{{/*
Annotations for a hook object, driven by a `hooks` block of the shape every Job
in this chart uses, merged with whatever the caller wants to add.

Invoke with a dict:
  (dict "hooks" .Values.<thing>.hooks "weight" "-10" "extra" (list .Values.commonAnnotations .Values.<thing>.annotations))

`weight` is passed separately so the objects a Job depends on can be ordered
ahead of the Job itself while sharing one hooks configuration.

`extra` is a list of annotation maps, applied in order with later entries
winning, and all of them beating the hook annotations below. Merged into one
map rather than concatenated as text: rendering the chart's annotations and
then the caller's underneath emits the same key twice, and while Kubernetes
happens to accept that and keep the last one, a manifest that contains
`argocd.argoproj.io/sync-wave` twice is not something anyone should have to
reason about.

THE SYNC WAVE IS THE HOOK WEIGHT. They are the same idea in two dialects --
"run this before that" -- and every place this chart previously set both, it
set them to the same number. A separate `syncWave` value was only a second
thing to keep in step, and the one place the two disagreed was the migration
Job, whose wave was never rendered at all.

What a wave should be depends on the Application it is synced into: how the
surrounding waves are numbered, whether the database is managed by this chart
at all. A chart schema cannot know that, so it is not a value here -- override
the annotation directly and it wins, like any other.
*/}}
{{- define "litellm.hookAnnotations" -}}
{{- $hooks := .hooks -}}
{{- $weight := .weight | toString -}}
{{- $ann := dict -}}
{{- if $hooks.helm.enabled -}}
{{- $_ := set $ann "helm.sh/hook" "pre-install,pre-upgrade" -}}
{{- $_ := set $ann "helm.sh/hook-delete-policy" "before-hook-creation" -}}
{{- $_ := set $ann "helm.sh/hook-weight" $weight -}}
{{- end -}}
{{- if $hooks.argocd.enabled -}}
{{- $_ := set $ann "argocd.argoproj.io/hook" "PreSync" -}}
{{- $_ := set $ann "argocd.argoproj.io/hook-delete-policy" "BeforeHookCreation" -}}
{{- $_ := set $ann "argocd.argoproj.io/sync-wave" $weight -}}
{{- end -}}
{{/*
  Reversed so that the LAST map the caller listed is the first source `merge`
  sees, and therefore the one that wins: `merge` keeps the value it already
  holds for a key. deepCopy because merge mutates its destination, and these
  maps come straight from .Values.
*/}}
{{- $merged := dict -}}
{{- range reverse (.extra | default list) -}}
{{- $merged = merge $merged (deepCopy (. | default dict)) -}}
{{- end -}}
{{- $merged = merge $merged $ann -}}
{{- with $merged -}}
{{- toYaml . -}}
{{- end -}}
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
{{- with .Values.serverRootPath }}
{{- /* Moves the UI and the API under a prefix. Health endpoints keep
       answering at the root as well, so the probes are unaffected. */}}
- name: SERVER_ROOT_PATH
  value: {{ . | quote }}
{{- end }}
{{- if and .Values.trustedProxies (not (hasKey (default dict .Values.envVars) "FORWARDED_ALLOW_IPS")) }}
{{- /* Without this the pod sees plaintext from the ingress and emits http://
       redirects. Rendered ahead of envVars so an explicit entry there wins. */}}
- name: FORWARDED_ALLOW_IPS
  value: {{ join "," .Values.trustedProxies | quote }}
{{- end }}
{{- if not .Values.docs.enabled }}
{{- /* Drops the Swagger page and the schema it reads. */}}
- name: NO_DOCS
  value: "True"
- name: NO_OPENAPI
  value: "True"
{{- else if .Values.docs.path }}
{{- /* Upstream defaults this to "/", which puts Swagger on the mount root and
       hides the Admin UI behind a path nobody guesses. */}}
- name: DOCS_URL
  value: {{ .Values.docs.path | quote }}
{{- end }}
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
{{- include "litellm.ssoEnv" . }}
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

{{- if .Values.database.init.enabled -}}
{{- if not (include "litellm.databaseEnabled" .) -}}
{{- fail "database.init.enabled requires the database flow. Set modelManagement.mode: database, or database.enabled: true." -}}
{{- end -}}
{{- $admin := .Values.database.init.admin -}}
{{- if not (or $admin.existingSecret.name (and $admin.username $admin.password)) -}}
{{- fail "database.init needs administrator credentials: set database.init.admin.existingSecret.name, or both database.init.admin.username and database.init.admin.password." -}}
{{- end -}}
{{- if and $admin.existingSecret.name (or $admin.username $admin.password) -}}
{{- fail "set either database.init.admin.existingSecret.name or the inline database.init.admin.username/password, not both. Two sources for one credential is ambiguous about which the Job uses and which gets erased." -}}
{{- end -}}
{{- if ne .Values.database.auth.mode "password" -}}
{{- fail (printf "database.init.enabled requires database.auth.mode \"password\", got %q. Under %s the login is issued by the cloud IAM provider, so there is no password for this Job to set on a role." .Values.database.auth.mode .Values.database.auth.mode) -}}
{{- end -}}
{{- if .Values.database.existingSecret.urlKey -}}
{{- fail "database.init cannot be used with database.existingSecret.urlKey. The Job creates the login role from a discrete username and password; a connection URL gives it neither. Use the discrete usernameKey and passwordKey instead." -}}
{{- end -}}
{{- if and (not .Values.database.host) (not .Values.database.existingSecret.hostKey) -}}
{{- fail "database.host or database.existingSecret.hostKey is required when database.init.enabled is true." -}}
{{- end -}}
{{- if and .Values.database.init.createSchema (not .Values.database.schema) -}}
{{- fail "database.init.createSchema is true but database.schema is empty. Name the schema, or set createSchema: false to use the database's default." -}}
{{- end -}}
{{- if not .Values.database.init.admin.database -}}
{{- fail "database.init.admin.database is required. CREATE DATABASE cannot run inside the database being created, so the Job connects to this one first — usually \"postgres\"." -}}
{{- end -}}
{{- if and .Values.database.init.hooks.helm.enabled (ge (int .Values.database.init.hooks.helm.weight) (int .Values.migrationJob.hooks.helm.weight)) -}}
{{- fail (printf "database.init.hooks.helm.weight (%s) must be below migrationJob.hooks.helm.weight (%s), or the migration runs against a database that does not exist yet." (toString .Values.database.init.hooks.helm.weight) (toString .Values.migrationJob.hooks.helm.weight)) -}}
{{- end -}}
{{- end -}}

{{- if and .Values.metricsServer.enabled (eq (int .Values.metricsServer.port) (int .Values.service.port)) -}}
{{- fail "metricsServer.port must differ from service.port" -}}
{{- end -}}

{{- if and .Values.docs.enabled .Values.docs.path -}}
{{- if hasPrefix "/ui" .Values.docs.path -}}
{{- fail (printf "docs.path %q would be served under the Admin UI's own path. Pick a path outside /ui, such as /docs." .Values.docs.path) -}}
{{- end -}}
{{- end -}}

{{- with .Values.serverRootPath -}}
{{- if not (hasPrefix "/" .) -}}
{{- fail (printf "serverRootPath must start with \"/\", got %q" .) -}}
{{- end -}}
{{- if hasSuffix "/" . -}}
{{- fail (printf "serverRootPath must not end with \"/\", got %q. LiteLLM joins it to route paths directly, so a trailing slash produces doubled separators." .) -}}
{{- end -}}
{{- end -}}

{{- if and .Values.serverRootPath (eq .Values.routing.path "/") -}}
{{- if or .Values.routing.ingress.enabled .Values.routing.httpRoute.enabled .Values.routing.httpProxy.enabled .Values.routing.route.enabled -}}
{{- fail (printf "serverRootPath is %q but routing.path is \"/\", so this release still claims the whole host. Set routing.path to %q as well — the point of serverRootPath is to leave the root to another application." .Values.serverRootPath .Values.serverRootPath) -}}
{{- end -}}
{{- end -}}

{{- if and .Values.serverRootPath .Values.routing.path (ne .Values.routing.path "/") -}}
{{- if ne (.Values.routing.path | trimSuffix "/") .Values.serverRootPath -}}
{{- fail (printf "routing.path (%q) and serverRootPath (%q) must match. The proxy only serves its UI under serverRootPath, so a different routing path publishes a prefix that returns 404." .Values.routing.path .Values.serverRootPath) -}}
{{- end -}}
{{- end -}}

{{- if .Values.sso.enabled -}}
{{- if not (or .Values.sso.proxyBaseUrl .Values.routing.hosts) -}}
{{- fail "sso.enabled needs a browser-facing URL: set sso.proxyBaseUrl, or routing.hosts so the chart can derive it. The provider redirects back to <proxyBaseUrl>/sso/callback." -}}
{{- end -}}
{{- $base := include "litellm.proxyBaseUrl" . -}}
{{- if not (or (hasPrefix "http://" $base) (hasPrefix "https://" $base)) -}}
{{- fail (printf "sso.proxyBaseUrl must include the scheme, got %q. A provider rejects a redirect_uri without one." $base) -}}
{{- end -}}
{{- if .Values.sso.keycloakBootstrap.enabled -}}
{{- $kb := .Values.sso.keycloakBootstrap -}}
{{- if not $kb.admin.existingSecret.name -}}
{{- fail "sso.keycloakBootstrap.admin.existingSecret.name is required. The Job authenticates to Keycloak as an administrator, and this chart reads those credentials from a Secret only." -}}
{{- end -}}
{{- $valid := list "proxy_admin" "proxy_admin_viewer" "internal_user" "internal_user_viewer" -}}
{{- if not (has $kb.roles.admin $valid) -}}
{{- fail (printf "sso.keycloakBootstrap.roles.admin must be one of %s, got %q. LiteLLM matches this value against its own role names; anything else is ignored and the user signs in with no privileges." (join ", " $valid) $kb.roles.admin) -}}
{{- end -}}
{{- if not (has $kb.roles.user $valid) -}}
{{- fail (printf "sso.keycloakBootstrap.roles.user must be one of %s, got %q." (join ", " $valid) $kb.roles.user) -}}
{{- end -}}
{{- if eq $kb.groups.admin $kb.groups.user -}}
{{- fail (printf "sso.keycloakBootstrap.groups.admin and .user must differ, both are %q. One group cannot carry two different LiteLLM roles." $kb.groups.admin) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if and .Values.sso.keycloakBootstrap.enabled (not .Values.sso.enabled) -}}
{{- fail "sso.keycloakBootstrap.enabled requires sso.enabled. The Job registers a client this release would not then use." -}}
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

{{- if and .Values.routing.httpProxy.enabled .Values.routing.httpProxy.delegated -}}
{{- /*
  A child carries no virtualhost, so passthrough — which is a property of one —
  cannot be honoured. Silently dropping it would leave TLS terminating at the
  parent when the operator asked for it not to.
*/ -}}
{{- if .Values.routing.httpProxy.tls.passthrough -}}
{{- fail "routing.httpProxy.tls.passthrough cannot be combined with routing.httpProxy.delegated. TLS passthrough is a property of the virtualhost, and a delegated child has none: it inherits the parent's. Publish a root HTTPProxy instead, or drop passthrough." -}}
{{- end -}}
{{- end -}}

{{- if and .Values.routing.httpProxy.enabled (not .Values.routing.httpProxy.delegated) -}}
{{- if not .Values.routing.hosts -}}
{{- fail "routing.hosts is required when routing.httpProxy.enabled is true. Set routing.httpProxy.delegated when another release owns the hostname and includes this one." -}}
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
