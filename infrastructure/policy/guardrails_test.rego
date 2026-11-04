package terraform.guardrails_test

import data.terraform.guardrails
import rego.v1

plan(type, address, after) := {"resource_changes": [{"type": type, "address": address, "change": {"actions": ["create"], "after": after}}]}

test_ssh_from_world_is_denied if {
	p := plan("aws_vpc_security_group_ingress_rule", "x", {"cidr_ipv4": "0.0.0.0/0", "from_port": 22, "to_port": 22, "ip_protocol": "tcp"})
	count(guardrails.deny) > 0 with input as p
}

test_https_from_world_is_allowed if {
	p := plan("aws_vpc_security_group_ingress_rule", "x", {"cidr_ipv4": "0.0.0.0/0", "from_port": 443, "to_port": 443, "ip_protocol": "tcp"})
	count(guardrails.deny) == 0 with input as p
}

test_imdsv1_is_denied if {
	p := plan("aws_instance", "i", {"instance_type": "t3.medium", "metadata_options": [{"http_tokens": "optional"}], "root_block_device": [{"encrypted": true}]})
	count(guardrails.deny) > 0 with input as p
}

test_compliant_instance_is_allowed if {
	p := plan("aws_instance", "i", {"instance_type": "t3.medium", "metadata_options": [{"http_tokens": "required"}], "root_block_device": [{"encrypted": true}]})
	count(guardrails.deny) == 0 with input as p
}

test_unencrypted_volume_is_denied if {
	p := plan("aws_ebs_volume", "v", {"encrypted": false})
	count(guardrails.deny) > 0 with input as p
}

test_mutable_ecr_is_denied if {
	p := plan("aws_ecr_repository", "r", {"image_tag_mutability": "MUTABLE", "image_scanning_configuration": [{"scan_on_push": true}]})
	count(guardrails.deny) > 0 with input as p
}

test_admin_access_denied_for_other_roles if {
	p := plan("aws_iam_role_policy_attachment", "a", {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess", "role": "taskflow-prod-gha-deploy"})
	count(guardrails.deny) > 0 with input as p
}

test_admin_access_allowed_for_apply_role if {
	p := plan("aws_iam_role_policy_attachment", "a", {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess", "role": "taskflow-prod-gha-tf-apply"})
	count(guardrails.deny) == 0 with input as p
}

test_volume_deletion_is_denied if {
	p := {"resource_changes": [{"type": "aws_ebs_volume", "address": "v", "change": {"actions": ["delete"], "after": null}}]}
	count(guardrails.deny) > 0 with input as p
}

test_public_rds_is_denied if {
	p := plan("aws_db_instance", "d", {"storage_encrypted": true, "publicly_accessible": true})
	count(guardrails.deny) > 0 with input as p
}

test_private_encrypted_rds_is_allowed if {
	p := plan("aws_db_instance", "d", {"storage_encrypted": true, "publicly_accessible": false})
	count(guardrails.deny) == 0 with input as p
}

test_ecs_service_without_circuit_breaker_is_denied if {
	p := plan("aws_ecs_service", "s", {"deployment_circuit_breaker": [{"enable": false, "rollback": false}]})
	count(guardrails.deny) > 0 with input as p
}

test_ecs_service_with_circuit_breaker_is_allowed if {
	p := plan("aws_ecs_service", "s", {"deployment_circuit_breaker": [{"enable": true, "rollback": true}]})
	count(guardrails.deny) == 0 with input as p
}

test_latest_tag_is_denied if {
	defs := json.marshal([{"name": "backend", "image": "repo/backend:latest"}])
	p := plan("aws_ecs_task_definition", "t", {"container_definitions": defs})
	count(guardrails.deny) > 0 with input as p
}

test_database_deletion_is_denied if {
	p := {"resource_changes": [{"type": "aws_db_instance", "address": "d", "change": {"actions": ["delete"], "after": null}}]}
	count(guardrails.deny) > 0 with input as p
}
