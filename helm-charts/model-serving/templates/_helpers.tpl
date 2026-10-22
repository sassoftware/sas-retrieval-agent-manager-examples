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
