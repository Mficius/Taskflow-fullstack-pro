package main

import rego.v1

good := {
	"kind": "Deployment",
	"metadata": {"name": "ok"},
	"spec": {"template": {"spec": {
		"automountServiceAccountToken": false,
		"securityContext": {"runAsNonRoot": true, "seccompProfile": {"type": "RuntimeDefault"}},
		"containers": [{
			"name": "app",
			"image": "registry/app:1.2.3",
			"securityContext": {"allowPrivilegeEscalation": false, "readOnlyRootFilesystem": true, "capabilities": {"drop": ["ALL"]}},
			"resources": {"requests": {"cpu": "10m"}, "limits": {"memory": "64Mi"}},
		}],
	}}},
}

test_good_workload_passes if {
	count(deny) == 0 with input as good
}

test_privileged_denied if {
	bad := json.patch(good, [{"op": "add", "path": "/spec/template/spec/containers/0/securityContext/privileged", "value": true}])
	count(deny) > 0 with input as bad
}

test_latest_tag_denied if {
	bad := json.patch(good, [{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "registry/app:latest"}])
	count(deny) > 0 with input as bad
}

test_root_denied if {
	bad := json.patch(good, [{"op": "replace", "path": "/spec/template/spec/securityContext/runAsNonRoot", "value": false}])
	count(deny) > 0 with input as bad
}

test_secret_in_configmap_denied if {
	count(deny) > 0 with input as {"kind": "ConfigMap", "metadata": {"name": "c"}, "data": {"DB_PASSWORD": "x"}}
}
