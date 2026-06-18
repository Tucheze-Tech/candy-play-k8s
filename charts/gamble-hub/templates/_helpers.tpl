{{- define "gamble-hub.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "gamble-hub.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "gamble-hub.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "gamble-hub.selectorLabels" -}}
app.kubernetes.io/name: gamble-hub
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
