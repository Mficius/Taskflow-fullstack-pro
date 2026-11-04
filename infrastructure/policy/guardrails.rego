# Contrôles PRÉVENTIFS (policy-as-code) évalués sur le plan Terraform (JSON) AVANT tout apply.
# Une seule violation => le pipeline s'arrête, rien n'est créé.
#   terraform show -json tfplan > plan.json
#   conftest test --all-namespaces -p infrastructure/policy plan.json
package terraform.guardrails

import rego.v1

world := "0.0.0.0/0"

web_ports := {80, 443}

admin_ports := {22, 3389}

allowed_instance_types := {
	"t3.small", "t3.medium", "t3.large",
	"t3a.small", "t3a.medium", "t3a.large",
}

# Ressources créées ou modifiées (état final connu)
active(type) := [rc |
	some rc in input.resource_changes
	rc.type == type
	rc.change.after != null
]

# ── Réseau ───────────────────────────────────────────────────
deny contains msg if {
	some rc in active("aws_vpc_security_group_ingress_rule")
	rc.change.after.cidr_ipv4 == world
	not rc.change.after.from_port in web_ports
	msg := sprintf("%s : ouvre le port %v à 0.0.0.0/0 (seuls 80 et 443 sont autorisés publiquement)", [rc.address, rc.change.after.from_port])
}

deny contains msg if {
	some rc in active("aws_vpc_security_group_ingress_rule")
	rc.change.after.ip_protocol == "-1"
	msg := sprintf("%s : règle d'entrée « tous protocoles » interdite", [rc.address])
}

deny contains msg if {
	some rc in active("aws_vpc_security_group_ingress_rule")
	some p in admin_ports
	rc.change.after.from_port <= p
	p <= rc.change.after.to_port
	msg := sprintf("%s : le port d'administration %v ne doit jamais être exposé (utiliser SSM Session Manager)", [rc.address, p])
}

# ── Calcul / stockage ────────────────────────────────────────
imdsv2(after) if after.metadata_options[0].http_tokens == "required"

deny contains msg if {
	some rc in active("aws_instance")
	not imdsv2(rc.change.after)
	msg := sprintf("%s : IMDSv2 obligatoire (metadata_options.http_tokens = \"required\")", [rc.address])
}

deny contains msg if {
	some rc in active("aws_instance")
	some dev in rc.change.after.root_block_device
	dev.encrypted != true
	msg := sprintf("%s : le volume racine doit être chiffré", [rc.address])
}

deny contains msg if {
	some rc in active("aws_ebs_volume")
	rc.change.after.encrypted != true
	msg := sprintf("%s : le volume EBS doit être chiffré", [rc.address])
}

deny contains msg if {
	some rc in active("aws_instance")
	not rc.change.after.instance_type in allowed_instance_types
	msg := sprintf("%s : type d'instance %v non autorisé (garde-fou de coût)", [rc.address, rc.change.after.instance_type])
}

# ── S3 ───────────────────────────────────────────────────────
pab_flags := ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]

deny contains msg if {
	some rc in active("aws_s3_bucket_public_access_block")
	some f in pab_flags
	rc.change.after[f] != true
	msg := sprintf("%s : %s doit être true", [rc.address, f])
}

deny contains msg if {
	count(active("aws_s3_bucket")) > count(active("aws_s3_bucket_public_access_block"))
	msg := "Chaque bucket S3 doit avoir un aws_s3_bucket_public_access_block"
}

# ── ECR ──────────────────────────────────────────────────────
scan_on_push(after) if after.image_scanning_configuration[0].scan_on_push == true

deny contains msg if {
	some rc in active("aws_ecr_repository")
	rc.change.after.image_tag_mutability != "IMMUTABLE"
	msg := sprintf("%s : les tags d'image doivent être IMMUTABLE", [rc.address])
}

deny contains msg if {
	some rc in active("aws_ecr_repository")
	not scan_on_push(rc.change.after)
	msg := sprintf("%s : scan_on_push doit être activé", [rc.address])
}

# ── IAM ──────────────────────────────────────────────────────
wildcard(x) if x == "*"

wildcard(x) if {
	is_array(x)
	"*" in x
}

deny contains msg if {
	some rc in active("aws_iam_role_policy_attachment")
	endswith(rc.change.after.policy_arn, "/AdministratorAccess")
	not endswith(object.get(rc.change.after, "role", ""), "-gha-tf-apply")
	msg := sprintf("%s : AdministratorAccess n'est autorisé que pour le rôle d'apply Terraform", [rc.address])
}

deny contains msg if {
	some rc in active("aws_iam_role_policy")
	pol := json.unmarshal(rc.change.after.policy)
	some st in pol.Statement
	st.Effect == "Allow"
	wildcard(st.Action)
	wildcard(st.Resource)
	msg := sprintf("%s : politique « Action:* sur Resource:* » interdite", [rc.address])
}

as_array(x) := x if is_array(x)

as_array(x) := [x] if not is_array(x)

github_oidc_statement(st) if contains(sprintf("%v", [st.Principal]), "oidc-provider/token.actions.githubusercontent.com")

sub_values(st) := as_array(st.Condition.StringEquals["token.actions.githubusercontent.com:sub"])

deny contains msg if {
	some rc in active("aws_iam_role")
	trust := json.unmarshal(rc.change.after.assume_role_policy)
	some st in trust.Statement
	github_oidc_statement(st)
	not sub_values(st)
	msg := sprintf("%s : la confiance OIDC GitHub doit restreindre le claim « sub » (StringEquals)", [rc.address])
}

deny contains msg if {
	some rc in active("aws_iam_role")
	trust := json.unmarshal(rc.change.after.assume_role_policy)
	some st in trust.Statement
	github_oidc_statement(st)
	some v in sub_values(st)
	contains(v, "*")
	msg := sprintf("%s : le claim « sub » OIDC ne doit pas contenir de joker (%s)", [rc.address, v])
}

# ── RDS ──────────────────────────────────────────────────────
deny contains msg if {
	some rc in active("aws_db_instance")
	rc.change.after.storage_encrypted != true
	msg := sprintf("%s : la base de données doit être chiffrée", [rc.address])
}

deny contains msg if {
	some rc in active("aws_db_instance")
	rc.change.after.publicly_accessible == true
	msg := sprintf("%s : la base de données ne doit jamais être publique", [rc.address])
}

# ── ECS ──────────────────────────────────────────────────────
circuit_breaker(after) if {
	after.deployment_circuit_breaker[0].enable == true
	after.deployment_circuit_breaker[0].rollback == true
}

deny contains msg if {
	some rc in active("aws_ecs_service")
	not circuit_breaker(rc.change.after)
	msg := sprintf("%s : le circuit breaker avec rollback automatique doit être activé", [rc.address])
}

deny contains msg if {
	some rc in active("aws_ecs_task_definition")
	defs := json.unmarshal(rc.change.after.container_definitions)
	some c in defs
	c.privileged == true
	msg := sprintf("%s : le conteneur %s ne doit pas être privilégié", [rc.address, c.name])
}

deny contains msg if {
	some rc in active("aws_ecs_task_definition")
	defs := json.unmarshal(rc.change.after.container_definitions)
	some c in defs
	endswith(c.image, ":latest")
	msg := sprintf("%s : le conteneur %s utilise le tag « latest » (tags immuables obligatoires)", [rc.address, c.name])
}

# ── Protection des données : jamais de suppression automatique ─
protected_types := {"aws_ebs_volume", "aws_s3_bucket", "aws_db_instance"}

deny contains msg if {
	some rc in input.resource_changes
	rc.type in protected_types
	"delete" in rc.change.actions
	msg := sprintf("%s : suppression/remplacement d'une ressource contenant des données — à faire manuellement après sauvegarde", [rc.address])
}
