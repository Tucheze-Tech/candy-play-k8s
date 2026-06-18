{{- define "01-tech.fullname" -}}
{{- "tech01" }}
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
