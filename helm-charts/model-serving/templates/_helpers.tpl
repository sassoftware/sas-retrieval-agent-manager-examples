{{/* Parent chart naming and labels. */}}
{{- define "model-serving.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "model-serving.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "model-serving.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Container probes for a ClusterServingRuntime entry.

Takes one runtime map (for example .Values.clusterServingRuntimes.vllmCPU) and
renders startupProbe, readinessProbe and livenessProbe from its .probes map. An
absent or empty probe renders nothing at all, which is how an operator turns a
single probe off without having to template around it.
*/}}
{{- define "model-serving.runtimeProbes" -}}
{{- $probes := .probes | default dict -}}
{{- with $probes.startup }}
startupProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $probes.readiness }}
readinessProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $probes.liveness }}
livenessProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
One vLLM ClusterServingRuntime, CPU or GPU.

Takes a dict of root (the chart context), runtime (one of the
clusterServingRuntimes entries) and key (that entry's name in values, used only
in error messages).

Shared rather than written twice because the two runtimes differ ONLY in their
values: same server, same CLI, same fixed arguments, same /health endpoint on
the same port. Two copies of this would drift, and the half that drifted would
be the one nobody was testing, which on this chart is whichever of CPU and
GPU the cluster in front of you does not have.
*/}}
{{- define "model-serving.vllmRuntime" -}}
{{- $root := .root -}}
{{- $vllm := .runtime -}}
{{- $key := .key -}}
{{- $cache := $vllm.cacheVolume | default dict -}}
{{- $cacheEnv := list -}}
{{- if $cache.enabled }}{{- $cacheEnv = $cache.env | default list }}{{- end -}}
{{- $vllmEnv := concat $cacheEnv ($vllm.env | default list) -}}
{{/*
A non-root uid is useless on a vLLM image without one of the getpass
variables. The published CPU image has no /etc/passwd entry for uid 1000, so
importing vllm reaches getpass.getuser(), falls through to pwd and raises
"KeyError: 'getpwuid(): uid not found: 1000'" before the server ever starts.
getpass.getuser() reads LOGNAME, USER, LNAME and USERNAME first, so any one of
them avoids it. Refusing to render beats shipping a crash loop whose traceback
blames torch and never mentions this chart.
*/}}
{{- $sc := $vllm.securityContext | default dict -}}
{{- if or (eq ($sc.runAsNonRoot | toString) "true") (ne (int ($sc.runAsUser | default 0)) 0) -}}
{{- $identity := list "LOGNAME" "USER" "LNAME" "USERNAME" -}}
{{- $hasIdentity := false -}}
{{- range $vllmEnv }}{{- if has .name $identity }}{{- $hasIdentity = true }}{{- end }}{{- end -}}
{{- if not $hasIdentity -}}
{{- fail (printf "model-serving: clusterServingRuntimes.%s forces a non-root user (runAsUser %v) but no %s environment variable is set, so \"import vllm\" will fail with KeyError: 'getpwuid(): uid not found: ...' before the server starts. Keep clusterServingRuntimes.%s.cacheVolume.enabled=true, or add one of those variables to clusterServingRuntimes.%s.env, or set clusterServingRuntimes.%s.securityContext to null." $key ($sc.runAsUser | default "unset") (join "/" $identity) $key $key $key) -}}
{{- end -}}
{{- end -}}
apiVersion: serving.kserve.io/v1alpha1
kind: ClusterServingRuntime
metadata:
  name: {{ $vllm.name }}
  labels:
    {{- include "model-serving.labels" $root | nindent 4 }}
  {{- with $root.Values.commonAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  supportedModelFormats:
    - name: huggingface
      autoSelect: {{ $vllm.autoSelect }}
  containers:
    - name: kserve-container
      image: {{ $vllm.image }}
      imagePullPolicy: {{ $vllm.imagePullPolicy }}
      args:
        - /mnt/models
        - --host=0.0.0.0
        - --port=8080
        - --trust-remote-code
        {{- with $vllm.args }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with $vllmEnv }}
      env:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (include "model-serving.runtimeProbes" $vllm | trim) }}
      {{- . | nindent 6 }}
      {{- end }}
      {{- with $vllm.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $vllm.securityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      volumeMounts:
        - name: shm
          mountPath: /dev/shm
        {{- if $cache.enabled }}
        - name: runtime-cache
          mountPath: {{ $cache.mountPath }}
        {{- end }}
  volumes:
    - name: shm
      emptyDir:
        medium: Memory
        sizeLimit: {{ $vllm.shmSize }}
    {{- if $cache.enabled }}
    - name: runtime-cache
      emptyDir:
        sizeLimit: {{ $cache.sizeLimit }}
    {{- end }}
{{- end }}

{{/*
Resolve the placement profile named by a workload entry.

Takes a dict of root (the chart context), entry (the model or LLM service),
defaults (modelDefaults or llmDefaults) and kind (used only in the error
message). Returns the profile map, or an empty map when no profile is named.

A profile name that is not defined in .Values.placementProfiles fails the
render. Falling back to "no placement" would be worse than failing: the
workload schedules somewhere arbitrary, the scheduler reports success, and the
mistake only surfaces as an eviction or an OOM on a node that was never meant
to run the model.
*/}}
{{- define "model-serving.placementProfile" -}}
{{- $profiles := .root.Values.placementProfiles | default dict -}}
{{- $name := .entry.placementProfile | default .defaults.placementProfile | default "" -}}
{{- if $name -}}
{{- if not (hasKey $profiles $name) -}}
{{- $known := keys $profiles | sortAlpha -}}
{{- fail (printf "model-serving: %s %q references placementProfile %q, which is not defined in placementProfiles (defined: %s)" .kind (.entry.name | toString) $name (ternary "none" (join ", " $known) (eq (len $known) 0))) -}}
{{- end -}}
{{- toYaml (index $profiles $name | default dict) -}}
{{- else -}}
{{- toYaml dict -}}
{{- end -}}
{{- end }}

{{/*
nodeSelector, tolerations and affinity for one workload entry.

Takes the same dict as model-serving.placementProfile. Each field is resolved
independently, highest precedence first: the entry itself, then the profile it
names, then the chart defaults. Resolving field by field rather than picking one
whole map is what lets a single model adopt a profile and still override one
toleration.

Renders at indent 0; callers apply nindent.
*/}}
{{- define "model-serving.placement" -}}
{{- $profile := fromYaml (include "model-serving.placementProfile" .) -}}
{{- $entry := .entry -}}
{{- $defaults := .defaults -}}
{{- with coalesce $entry.nodeSelector $profile.nodeSelector $defaults.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with coalesce $entry.tolerations $profile.tolerations $defaults.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with coalesce $entry.affinity $profile.affinity $defaults.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Node group names for a per-model localCache entry.

Falls back to every node group defined in localModelCache.nodeGroups, because a
LocalModelCache with no node groups is rejected by the CRD (nodeGroups has
minItems 1) with an error that does not mention this chart.
*/}}
{{- define "model-serving.localCacheNodeGroups" -}}
{{- $cache := .entry.localCache | default dict -}}
{{- $groups := $cache.nodeGroups | default list -}}
{{- if not $groups -}}
{{- range .root.Values.localModelCache.nodeGroups -}}
{{- $groups = append $groups .name -}}
{{- end -}}
{{- end -}}
{{- if not $groups -}}
{{- fail (printf "model-serving: model %q enables localCache but no node groups are available; set localModelCache.nodeGroups or the model's localCache.nodeGroups" (.entry.name | toString)) -}}
{{- end -}}
{{- toYaml $groups -}}
{{- end }}
