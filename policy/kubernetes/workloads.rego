# Preventive controls Kubernetes (Conftest / OPA) - exécutés en CI AVANT tout déploiement
#   helm template ... | conftest test --policy policy/kubernetes -
package main

import rego.v1

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Job"}

pod_spec := input.spec.template.spec if input.kind in workload_kinds

containers contains c if {
	some c in pod_spec.containers
}

name := input.metadata.name

deny contains msg if {
	some c in containers
	c.securityContext.privileged == true
	msg := sprintf("%s/%s: conteneur '%s' privilégié interdit", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	not c.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("%s/%s: '%s' doit définir allowPrivilegeEscalation: false", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	not c.securityContext.readOnlyRootFilesystem == true
	msg := sprintf("%s/%s: '%s' doit définir readOnlyRootFilesystem: true", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	not "ALL" in c.securityContext.capabilities.drop
	msg := sprintf("%s/%s: '%s' doit retirer toutes les capabilities (drop: [ALL])", [input.kind, name, c.name])
}

deny contains msg if {
	pod_spec
	not pod_spec.securityContext.runAsNonRoot == true
	msg := sprintf("%s/%s: runAsNonRoot: true obligatoire", [input.kind, name])
}

deny contains msg if {
	pod_spec
	not pod_spec.securityContext.seccompProfile.type == "RuntimeDefault"
	msg := sprintf("%s/%s: seccompProfile RuntimeDefault obligatoire", [input.kind, name])
}

deny contains msg if {
	some c in containers
	not c.resources.limits.memory
	msg := sprintf("%s/%s: '%s' doit définir resources.limits.memory", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	not c.resources.requests.cpu
	msg := sprintf("%s/%s: '%s' doit définir resources.requests.cpu", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	endswith(c.image, ":latest")
	msg := sprintf("%s/%s: image '%s' avec tag :latest interdite", [input.kind, name, c.image])
}

deny contains msg if {
	some c in containers
	not contains(c.image, ":")
	msg := sprintf("%s/%s: image '%s' sans tag interdite", [input.kind, name, c.image])
}

deny contains msg if {
	pod_spec.hostNetwork == true
	msg := sprintf("%s/%s: hostNetwork interdit", [input.kind, name])
}

deny contains msg if {
	some v in pod_spec.volumes
	v.hostPath
	msg := sprintf("%s/%s: volume hostPath interdit", [input.kind, name])
}

deny contains msg if {
	pod_spec
	not pod_spec.automountServiceAccountToken == false
	msg := sprintf("%s/%s: automountServiceAccountToken doit valoir false", [input.kind, name])
}

# Secrets en clair dans un ConfigMap
deny contains msg if {
	input.kind == "ConfigMap"
	some key, _ in input.data
	regex.match(`(?i)(password|passwd|secret|api_?key|private_?key|_token$)`, key)
	msg := sprintf("ConfigMap/%s: la clé '%s' ressemble à un secret (utiliser ExternalSecret)", [name, key])
}

warn contains msg if {
	input.kind == "Service"
	input.spec.type in {"LoadBalancer", "NodePort"}
	msg := sprintf("Service/%s: type %s expose directement le workload (préférer ALB + TargetGroupBinding)", [name, input.spec.type])
}
