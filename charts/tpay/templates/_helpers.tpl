{{- define "tpay.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tpay.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "tpay.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "tpay.selectorLabels" -}}
app.kubernetes.io/name: tpay
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
