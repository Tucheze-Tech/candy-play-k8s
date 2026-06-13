{{/*
candy-common shared naming + label helpers.

These intentionally key off `.Chart.Name`, which resolves to the *consuming*
service chart (icore, euro-virtuals, tpay, 01-tech) when a service template
calls `{{ include "candy-common.X" . }}`. That keeps fullname/selectorLabels
byte-identical to the pre-refactor per-chart helpers, so existing running
Deployments are matched (no orphaned selectors).
*/}}

{{- define "candy-common.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "candy-common.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "candy-common.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "candy-common.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Namespace comes from the cloud abstraction block (was hardcoded candy-services). */}}
{{- define "candy-common.namespace" -}}
{{- .Values.cloud.namespace }}
{{- end }}
