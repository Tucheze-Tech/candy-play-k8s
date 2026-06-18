{{- define "01-tech.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "01-tech.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "01-tech.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "01-tech.selectorLabels" -}}
app.kubernetes.io/name: 01-tech
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
