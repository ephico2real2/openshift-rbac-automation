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
