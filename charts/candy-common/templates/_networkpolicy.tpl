{{- define "candy-common.networkpolicy" -}}
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "candy-common.fullname" . }}-netpol
  namespace: {{ .Values.cloud.namespace }}
spec:
  podSelector:
    matchLabels:
      {{- include "candy-common.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kong
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.cloud.namespace }}
      ports:
        - port: 8080
  egress:
    - {}
{{- end }}
{{- end }}
