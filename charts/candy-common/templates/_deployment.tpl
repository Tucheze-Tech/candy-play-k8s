{{/*
candy-common.deployment — single Deployment template for all services.

Cloud seam:
  - namespace            <- .Values.cloud.namespace
  - nodeSelector/tolerations (spot) <- .Values.cloud.spot.*  (empty by default = no change)
  - cloud-sql-proxy sidecar renders only when .Values.cloudSqlProxy.enabled
    (gke overlay sets true; eks/local set false -> direct DB / RDS)

Secrets are unified: every service consumes its env from a single Secret via
`envFrom: secretRef` (no more /secrets/.env volume mounts). Non-secret config
stays in .Values.env.
*/}}
{{- define "candy-common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "candy-common.fullname" . }}
  namespace: {{ .Values.cloud.namespace }}
  labels:
    {{- include "candy-common.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "candy-common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "candy-common.selectorLabels" . | nindent 8 }}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: {{ .Values.serviceAccount.name }}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      {{- with .Values.cloud.spot.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.cloud.spot.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
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
          {{- with .Values.probes.liveness }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.probes.readiness }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
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
            {{- toYaml .Values.cloudSqlProxy.resources | nindent 12 }}
        {{- end }}
{{- end }}
