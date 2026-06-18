{{- define "icore.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "icore.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "icore.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "icore.selectorLabels" -}}
app.kubernetes.io/name: icore
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
