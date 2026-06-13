{{/*
candy-common.ingress — Kong ingress with optional second "callback" ingress
(used by 01-tech for IP-restricted provider callbacks). Both routes are
namespace-aware via .Values.cloud.namespace.
*/}}
{{- define "candy-common.ingress" -}}
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "candy-common.fullname" . }}-ingress
  namespace: {{ .Values.cloud.namespace }}
  annotations:
    konghq.com/strip-path: "true"
    konghq.com/plugins: {{ .Values.ingress.kongPlugins | quote }}
spec:
  ingressClassName: kong
  tls:
    - hosts:
        - {{ .Values.ingress.host }}
      secretName: {{ .Values.ingress.tlsSecret }}
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: {{ .Values.ingress.pathPrefix }}
            pathType: Prefix
            backend:
              service:
                name: {{ include "candy-common.fullname" . }}
                port:
                  number: {{ .Values.service.port }}
{{- end }}
{{- if and .Values.callbackIngress .Values.callbackIngress.enabled }}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "candy-common.fullname" . }}-callbacks-ingress
  namespace: {{ .Values.cloud.namespace }}
  annotations:
    konghq.com/strip-path: "false"
    konghq.com/plugins: {{ .Values.callbackIngress.kongPlugins | quote }}
spec:
  ingressClassName: kong
  tls:
    - hosts:
        - {{ .Values.ingress.host }}
      secretName: {{ .Values.ingress.tlsSecret }}
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: {{ .Values.callbackIngress.pathPrefix }}
            pathType: Prefix
            backend:
              service:
                name: {{ include "candy-common.fullname" . }}
                port:
                  number: {{ .Values.service.port }}
{{- end }}
{{- end }}
