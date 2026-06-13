{{/*
candy-common.serviceaccount — workload-identity / IRSA aware.
The annotation KEY is cloud-specific (.Values.cloud.serviceAccount.annotationKey):
  gke -> iam.gke.io/gcp-service-account
  eks -> eks.amazonaws.com/role-arn
The VALUE stays in .Values.serviceAccount.gcpServiceAccount (GSA email on GKE,
role ARN on EKS). Annotation is omitted entirely when the value is empty (local).
*/}}
{{- define "candy-common.serviceaccount" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.serviceAccount.name }}
  namespace: {{ .Values.cloud.namespace }}
  labels:
    {{- include "candy-common.labels" . | nindent 4 }}
  {{- if .Values.serviceAccount.gcpServiceAccount }}
  annotations:
    {{ .Values.cloud.serviceAccount.annotationKey }}: {{ .Values.serviceAccount.gcpServiceAccount | quote }}
  {{- end }}
{{- end }}
