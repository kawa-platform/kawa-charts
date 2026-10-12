{{- define "kawa.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kawa.fullname" -}}
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

{{- define "kawa.gateway.fullname" -}}
{{- printf "%s-gateway" (include "kawa.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kawa.studio.fullname" -}}
{{- printf "%s-studio" (include "kawa.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kawa.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "kawa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kawa
{{- end }}

{{- define "kawa.gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kawa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: gateway
{{- end }}

{{- define "kawa.studio.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kawa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: studio
{{- end }}

{{- define "kawa.gateway.secretName" -}}
{{- default (include "kawa.gateway.fullname" .) .Values.gateway.secrets.existingSecret }}
{{- end }}

{{/* The host clients reach the gateway Service on, used when advertised.host is not set. */}}
{{- define "kawa.gateway.advertisedHost" -}}
{{- printf "%s.%s.svc.cluster.local" (include "kawa.gateway.fullname" .) .Release.Namespace }}
{{- end }}

{{/* The Kafka port: the first listener in gateway.config (the gateway's default 9092), or the Service value with existingConfigMap. */}}
{{- define "kawa.gateway.kafkaPort" -}}
{{- if .Values.gateway.existingConfigMap -}}
{{- .Values.gateway.service.kafkaPort -}}
{{- else -}}
{{- $listeners := (.Values.gateway.config | default dict).listeners | default list -}}
{{- if $listeners -}}
{{- (first $listeners).port | default 9092 -}}
{{- else -}}
9092
{{- end -}}
{{- end -}}
{{- end }}

{{/* The admin port: admin.port in gateway.config (the gateway's default 8080), or the Service value with existingConfigMap. */}}
{{- define "kawa.gateway.adminPort" -}}
{{- if .Values.gateway.existingConfigMap -}}
{{- .Values.gateway.service.adminPort -}}
{{- else -}}
{{- ((.Values.gateway.config | default dict).admin | default dict).port | default 8080 -}}
{{- end -}}
{{- end }}

{{/* The gateway's config.yaml: gateway.config as written, with advertised.host set when it is not. */}}
{{- define "kawa.gateway.config" -}}
{{- $cfg := deepCopy (.Values.gateway.config | default dict) }}
{{- $advertised := $cfg.advertised | default dict }}
{{- if not $advertised.host }}
{{- $_ := set $advertised "host" (include "kawa.gateway.advertisedHost" .) }}
{{- end }}
{{- $_ := set $cfg "advertised" $advertised }}
{{- toYaml $cfg }}
{{- end }}
