{{- define "euro-virtuals.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "euro-virtuals.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "euro-virtuals.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "euro-virtuals.selectorLabels" -}}
app.kubernetes.io/name: euro-virtuals
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
