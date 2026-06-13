{{- define "candy-common.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "candy-common.fullname" . }}
  namespace: {{ .Values.cloud.namespace }}
  labels:
    {{- include "candy-common.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  selector:
    {{- include "candy-common.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: 8080
      protocol: TCP
{{- end }}
