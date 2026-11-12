{{- define "taskflow.fullname" -}}
{{- .Release.Name | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{- define "taskflow.labels" -}}
app.kubernetes.io/part-of: taskflow
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/* Image Docker Hub par tag SHA ou digest immuable. */}}
{{- define "taskflow.image" -}}
{{- $tag := default .root.Chart.AppVersion .root.Values.image.tag -}}
{{- $digest := default "" .digest -}}
{{- if .root.Values.image.registry -}}
  {{- if $digest -}}
    {{- printf "%s/%s@%s" .root.Values.image.registry .repo $digest -}}
  {{- else -}}
    {{- printf "%s/%s:%s" .root.Values.image.registry .repo $tag -}}
  {{- end -}}
{{- else -}}
  {{- if $digest -}}
    {{- printf "%s@%s" .repo $digest -}}
  {{- else -}}
    {{- printf "%s:%s" .repo $tag -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "taskflow.apiEnvFrom" -}}
- configMapRef:
    name: {{ include "taskflow.fullname" . }}-api-config
- secretRef:
    name: {{ .Values.secrets.name }}
{{- end -}}

{{/* volumes inscriptibles pour un conteneur Laravel en rootfs read-only */}}
{{- define "taskflow.laravelMounts" -}}
- {name: tmp, mountPath: /tmp}
- {name: storage, mountPath: /var/www/html/storage}
- {name: bootstrap-cache, mountPath: /var/www/html/bootstrap/cache}
{{- end -}}

{{- define "taskflow.laravelVolumes" -}}
- {name: tmp, emptyDir: {sizeLimit: 64Mi}}
- {name: storage, emptyDir: {sizeLimit: 256Mi}}
- {name: bootstrap-cache, emptyDir: {sizeLimit: 32Mi}}
{{- end -}}

{{- define "taskflow.migrateEnvFrom" -}}
- configMapRef:
    name: {{ include "taskflow.fullname" . }}-api-config
{{- if .Values.mysql.enabled }}
- secretRef:
    name: {{ .Values.secrets.name }}
{{- else }}
- secretRef:
    name: {{ .Values.secrets.migrateName }}
{{- end }}
{{- end -}}
