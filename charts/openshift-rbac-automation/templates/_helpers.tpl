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
Name shared by the orphan sweeper's SA, ClusterRole, ClusterRoleBinding, ConfigMap and Job. Same
pattern as the two above so the whole unit is greppable and deletable together.
*/}}
{{- define "nco.orphanSweeper.name" -}}
{{- printf "%s-orphan-sweeper" .Values.subscription.packageName | trunc 63 | trimSuffix "-" }}
{{- end }}

# The operator-wait Job and its RBAC. Same shape as the other component helpers so the objects are
# recognisably one component in `oc get all -l app.kubernetes.io/component=operator-wait`.
{{- define "nco.operatorWait.name" -}}
{{- printf "%s-wait" (include "nco.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Fully-qualified operator image the CSV should be patched to: digest beats tag beats appVersion.

THIS STRING IS THE ROLLOUT TRIGGER, which is why it is validated here rather than trusted. The CSV
patch in 04-image-override-script skips when the live image already equals it (a string comparison),
so a reference that never changes is an operator that never restarts — the ":latest" defect that
values.yaml's operatorImage block records. Two render-time refusals keep a broken reference out of
the CSV, where the failure is a wedged install rather than a failed template:

  - a digest that is not sha256:<64 hex> — "@sha256:latest" is a plausible typo that would render a
    syntactically valid reference pointing at nothing.
  - an empty resolution. With tag, digest and appVersion all empty this would emit a bare
    "repository:", which is non-empty and so passes the script's ${TARGET_IMAGE:?} guard.

toString is deliberate: `--set operatorImage.tag=1.3` reaches Helm as float64, and "%s" on a float
renders %!s(float64=1.3). Use --set-string for a tag; this keeps the plain form from silently
producing a garbage reference.
*/}}
{{- define "nco.imageOverride.image" -}}
{{- $repo := default "" .Values.operatorImage.repository | toString -}}
{{- if not $repo -}}
{{- fail "operatorImage.repository is empty, which would render a reference like \":tag\" — non-empty, so the script's ${TARGET_IMAGE:?} guard does not catch it, and the CSV is wedged with an unpullable image." -}}
{{- end -}}
{{- $digest := default "" .Values.operatorImage.digest | toString -}}
{{- if $digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $digest) -}}
{{- fail (printf "operatorImage.digest %q is not a digest. It must be sha256: followed by 64 lowercase hex characters; read one off the registry with `skopeo inspect docker://%s:<tag>` and copy its Digest field. Leave it empty to deploy operatorImage.tag." $digest .Values.operatorImage.repository) -}}
{{- end -}}
{{- printf "%s@%s" $repo $digest -}}
{{- else -}}
{{- $tag := default .Chart.AppVersion .Values.operatorImage.tag | toString -}}
{{- if not (regexMatch "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$" $tag) -}}
{{- fail (printf "operatorImage resolves to tag %q, which is not a Docker tag (empty, or containing a character such as \"/\" that is not [A-Za-z0-9_.-]). An unusable tag wedges the CSV with an image that cannot be pulled. Set operatorImage.tag to an immutable build tag, or operatorImage.digest." $tag) -}}
{{- end -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end }}

{{/*
Pod spec shared by the image-override Job and the reconcile CronJob, so both run the same
container, the same env and the same script. Rendered at the "spec:" level of a PodTemplate.
*/}}
{{- define "nco.imageOverride.podSpec" -}}
{{- /*
  Shared by the image-override hook Job, the reconcile CronJob and the csv-reclaim hook Job, so all
  three run byte-identical logic from one ConfigMap.

  Accepts EITHER the root context (the historical callers) OR a dict {root, mode}. The dict form only
  adds MODE to the env, which the script uses to run just the orphan reclaim and exit. Kept
  backward-compatible on purpose: a second copy of this pod spec is how the two callers would drift.
*/ -}}
{{- $root := . }}
{{- $mode := "" }}
{{- if kindIs "map" . }}{{- if hasKey . "root" }}{{- $root = .root }}{{- $mode = .mode | default "" }}{{- end }}{{- end }}
{{- with $root }}
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
      - name: RECLAIM_ORPHANED_CSV
        value: {{ .Values.operatorImage.reclaimOrphanedCSV | quote }}
      - name: RECLAIM_WAIT_SECONDS
        value: {{ .Values.operatorImage.reclaimWaitSeconds | quote }}
{{- if $mode }}
      - name: MODE
        value: {{ $mode | quote }}
{{- end }}
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
