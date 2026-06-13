{{/*
candy-common.externalsecret — unified ESO pattern for ALL services.
Uses dataFrom.extract so the upstream secret is a flat JSON object
({"KEY":"value", ...}); each key becomes a Secret key, consumed via
`envFrom: secretRef` in the Deployment. The backend (GCP Secret Manager vs
AWS Secrets Manager) is selected purely by .Values.cloud.secretStore.*.

NOTE: icore + tpay previously stored the whole .env as a single string secret.
Migrating to this template REQUIRES their upstream secrets be reformatted to
flat JSON. See k8s/README.md "Secret format" before cutover.
*/}}
{{- define "candy-common.externalsecret" -}}
{{- if ne (toString .Values.externalSecret.enabled) "false" }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ .Values.externalSecret.targetName }}
  namespace: {{ .Values.cloud.namespace }}
spec:
  refreshInterval: {{ .Values.externalSecret.refreshInterval }}
  secretStoreRef:
    kind: {{ .Values.cloud.secretStore.kind }}
    name: {{ .Values.cloud.secretStore.name }}
  target:
    name: {{ .Values.externalSecret.targetName }}
    creationPolicy: Owner
    template:
      type: Opaque
      engineVersion: v2
  dataFrom:
    - extract:
        key: {{ .Values.externalSecret.gcpSecretName }}
{{- end }}
{{- end }}
