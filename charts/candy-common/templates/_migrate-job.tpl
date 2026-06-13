{{/*
candy-common.migrate-job — Helm post-install/post-upgrade migration Job.
Renders only when .Values.migrate.enabled (icore, tpay). Command is
configurable via .Values.migrate.command. Env is unified on envFrom secretRef.
*/}}
{{- define "candy-common.migrate-job" -}}
{{- if .Values.migrate.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "candy-common.fullname" . }}-migrate
  namespace: {{ .Values.cloud.namespace }}
  annotations:
    helm.sh/hook: post-upgrade,post-install
    helm.sh/hook-weight: "-5"
    helm.sh/hook-delete-policy: hook-succeeded
spec:
  backoffLimit: 3
  template:
    spec:
      serviceAccountName: {{ .Values.serviceAccount.name }}
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: {{ .Values.migrate.command | toJson }}
          {{- with .Values.env }}
          env:
            {{- range $k, $v := . }}
            {{- if $v }}
            - name: {{ $k }}
              value: {{ $v | quote }}
            {{- end }}
            {{- end }}
          {{- end }}
          {{- if ne (toString .Values.externalSecret.enabled) "false" }}
          envFrom:
            - secretRef:
                name: {{ .Values.externalSecret.targetName }}
          {{- end }}
        {{- if .Values.cloudSqlProxy.enabled }}
        - name: cloud-sql-proxy
          image: {{ .Values.cloudSqlProxy.image }}
          args:
            - "--structured-logs"
            - "--port=5432"
            - "--private-ip"
            - "{{ .Values.cloudSqlProxy.connectionName }}"
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
        {{- end }}
{{- end }}
{{- end }}
