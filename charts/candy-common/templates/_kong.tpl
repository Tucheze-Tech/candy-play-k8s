{{/*
candy-common.kong — single source of truth for a service's Kong objects.

Renders, all into .Values.cloud.namespace (so prod and staging never share a
namespace-scoped object):
  - one KongPlugin per entry in .Values.kong.plugins  (name/type/config)
  - an optional KongConsumer (.Values.kong.consumer)  — omit the block to skip
    (tpay / 01-tech have no consumer)
  - an optional key-auth credential Secret, rendered ONLY when
    .Values.kong.consumer.apiKey is supplied at deploy time (empty default keeps
    the legacy out-of-band secret flow). The key is GLOBAL across the Kong
    cluster, so prod and staging MUST pass different values.

Plugin NAMES live here once and are referenced by the Ingress annotation
(.Values.ingress.kongPlugins / .Values.callbackIngress.kongPlugins) in the same
values file — one producer, Helm-owned, rollback-safe, no orphan objects.
*/}}
{{- define "candy-common.kong" -}}
{{- if .Values.kong }}
{{- $ns := .Values.cloud.namespace }}
{{- range .Values.kong.plugins }}
---
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: {{ .name }}
  namespace: {{ $ns }}
plugin: {{ .type }}
{{- with .config }}
config:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- with .Values.kong.consumer }}
---
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: {{ .name }}
  namespace: {{ $ns }}
  annotations:
    kubernetes.io/ingress.class: kong
username: {{ .name }}
credentials:
  - {{ .credentialSecret }}
{{- if .apiKey }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ .credentialSecret }}
  namespace: {{ $ns }}
  labels:
    konghq.com/credential: key-auth
type: Opaque
stringData:
  key: {{ .apiKey | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
