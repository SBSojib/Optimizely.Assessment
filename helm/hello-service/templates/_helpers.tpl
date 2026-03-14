{{/*
Chart name, truncated to 63 characters.
*/}}
{{- define "hello-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name, truncated to 63 characters.
*/}}
{{- define "hello-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "hello-service.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "hello-service.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "hello-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hello-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "hello-service.serviceAccountName" -}}
{{- $sa := .Values.serviceAccount | default dict }}
{{- if $sa.create }}
{{- default (include "hello-service.fullname" .) $sa.name }}
{{- else }}
{{- default "default" $sa.name }}
{{- end }}
{{- end }}

{{/*
Google service account email used for Workload Identity.
*/}}
{{- define "hello-service.gcpServiceAccountEmail" -}}
{{- $sa := .Values.serviceAccount | default dict }}
{{- $global := .Values.global | default dict }}
{{- if $sa.gcpServiceAccount -}}
{{- $sa.gcpServiceAccount -}}
{{- else -}}
{{- printf "%s@%s.iam.gserviceaccount.com" ($sa.gcpServiceAccountName | default "default") ($global.projectId | default "default") -}}
{{- end -}}
{{- end }}
