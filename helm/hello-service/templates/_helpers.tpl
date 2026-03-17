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
{{- $wi := $sa.workloadIdentity | default dict }}
{{- if not $wi.enabled }}
{{- fail "serviceAccount.workloadIdentity.enabled must be true for hello-service." }}
{{- end }}
{{- $name := $sa.name | default "" }}
{{- if not $name }}
{{- fail "serviceAccount.name must be set to a dedicated Kubernetes service account for hello-service." }}
{{- end }}
{{- if eq $name "default" }}
{{- fail "serviceAccount.name must not be \"default\". Use a dedicated Kubernetes service account for hello-service." }}
{{- end }}
{{- $name }}
{{- end }}

{{/*
Google service account email used for Workload Identity.
*/}}
{{- define "hello-service.gcpServiceAccountEmail" -}}
{{- $sa := .Values.serviceAccount | default dict }}
{{- $global := .Values.global | default dict }}
{{- if $sa.gcpServiceAccount -}}
{{- $sa.gcpServiceAccount -}}
{{- else if and $sa.gcpServiceAccountName $global.projectId -}}
{{- if eq $sa.gcpServiceAccountName "default" -}}
{{- fail "serviceAccount.gcpServiceAccountName must not be \"default\" when Workload Identity is enabled." -}}
{{- end -}}
{{- printf "%s@%s.iam.gserviceaccount.com" $sa.gcpServiceAccountName $global.projectId -}}
{{- else -}}
{{- fail "serviceAccount.gcpServiceAccount or both serviceAccount.gcpServiceAccountName and global.projectId must be set for Workload Identity." -}}
{{- end -}}
{{- end }}
