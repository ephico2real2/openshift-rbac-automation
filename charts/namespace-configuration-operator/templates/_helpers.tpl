{{/*
Chart name (overridable via nameOverride). Used for the app.kubernetes.io/name label.
Resource names themselves come from explicit .Values (namespace / package name) rather
than a fullname helper — that avoids the release-name + chart-name concatenation that
produces doubled, over-long names.
*/}}
{{- define "nco.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name shared by every resource of the CSV image-override machinery (SA, Role, RoleBinding,
ConfigMap, Job, CronJob), so they are trivially greppable and deletable as one unit.
*/}}
{{- define "nco.imageOverride.name" -}}
{{- printf "%s-image-override" .Values.subscription.packageName | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name shared by the InstallPlan approver's SA, Role, RoleBinding, ConfigMap and Job.
*/}}
{{- define "nco.approver.name" -}}
{{- printf "%s-installplan-approver" .Values.subscription.packageName | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully-qualified operator image the CSV should be patched to.
*/}}
{{- define "nco.imageOverride.image" -}}
{{- printf "%s:%s" .Values.operatorImage.repository .Values.operatorImage.tag }}
{{- end }}

{{/*
Pod spec shared by the image-override Job and the reconcile CronJob, so both run the same
container, the same env and the same script. Rendered at the "spec:" level of a PodTemplate.
*/}}
{{- define "nco.imageOverride.podSpec" -}}
serviceAccountName: {{ include "nco.imageOverride.name" . }}
restartPolicy: Never
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
containers:
  - name: patch-csv-image
    image: {{ .Values.operatorImage.job.image | quote }}
    imagePullPolicy: IfNotPresent
    command: ["/bin/bash", "/scripts/patch-csv-image.sh"]
    env:
      - name: NAMESPACE
        value: {{ .Values.namespace | quote }}
      - name: SUBSCRIPTION
        value: {{ .Values.subscription.packageName | quote }}
      - name: CSV_DEPLOYMENT
        value: {{ .Values.operatorImage.csvDeploymentName | quote }}
      - name: CONTAINER
        value: {{ .Values.operatorImage.containerName | quote }}
      - name: TARGET_IMAGE
        value: {{ include "nco.imageOverride.image" . | quote }}
      - name: PULL_POLICY
        value: {{ .Values.operatorImage.pullPolicy | quote }}
      - name: EXPECTED_IMAGE_PATTERN
        value: {{ .Values.operatorImage.expectedImagePattern | quote }}
      - name: PULL_SECRET
        value: {{ .Values.operatorImage.imagePullSecret | quote }}
      - name: WAIT_SECONDS
        value: {{ .Values.operatorImage.job.waitSeconds | quote }}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    resources:
      {{- toYaml .Values.operatorImage.job.resources | nindent 6 }}
    volumeMounts:
      - name: scripts
        mountPath: /scripts
        readOnly: true
      # oc writes a cache under $HOME; the root filesystem is read-only.
      - name: home
        mountPath: /.kube
volumes:
  - name: scripts
    configMap:
      name: {{ include "nco.imageOverride.name" . }}
      defaultMode: 0555
  - name: home
    emptyDir: {}
{{- end }}

{{/*
Common labels applied to every resource this chart creates.
*/}}
{{- define "nco.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "nco.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}
