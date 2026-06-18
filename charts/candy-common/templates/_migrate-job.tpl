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
      {{- if .Values.cloudSqlProxy.enabled }}
      # Native sidecar (initContainer + restartPolicy: Always): the proxy starts
      # before migrate, stays up during it, and is auto-terminated when migrate
      # exits so the Job actually COMPLETES. A plain sidecar container would run
      # forever and the Job would never finish.
      initContainers:
        - name: cloud-sql-proxy
          image: {{ .Values.cloudSqlProxy.image }}
          restartPolicy: Always
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
{{- end }}
{{- end }}
