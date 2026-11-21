{{- define "kawa.name" -}}
{{- default "kawa" .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kawa.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
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
app.kubernetes.io/version: {{ .Values.gateway.image.tag | quote }}
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

{{/* The Kafka port: the first listener in gateway.config (the gateway's default 9092). */}}
{{- define "kawa.gateway.kafkaPort" -}}
{{- $listeners := (.Values.gateway.config | default dict).listeners | default list -}}
{{- if $listeners -}}
{{- (first $listeners).port | default 9092 -}}
{{- else -}}
9092
{{- end -}}
{{- end }}

{{/* The admin port: admin.port in gateway.config (the gateway's default 8080). */}}
{{- define "kawa.gateway.adminPort" -}}
{{- ((.Values.gateway.config | default dict).admin | default dict).port | default 8080 -}}
{{- end }}

{{/* "true" when gateway.config turns the admin API on (admin.enabled; the gateway's default is off), else "". */}}
{{- define "kawa.gateway.adminEnabled" -}}
{{- if ((.Values.gateway.config | default dict).admin | default dict).enabled -}}
true
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
