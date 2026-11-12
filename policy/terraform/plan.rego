# Preventive controls Terraform (Conftest / OPA) sur le JSON du plan :
#   terraform plan -out tfplan && terraform show -json tfplan > tfplan.json
#   conftest test --policy policy/terraform tfplan.json
# Ces règles BLOQUENT le pipeline avant tout `terraform apply`.
package main

import rego.v1

# Ressources créées ou modifiées par le plan
changed contains r if {
	some r in input.resource_changes
	some a in r.change.actions
	a in {"create", "update"}
}

after(r) := r.change.after

deny contains msg if {
	some r in changed
	r.type == "aws_db_instance"
	after(r).publicly_accessible == true
	msg := sprintf("%s: RDS ne doit JAMAIS être public", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_db_instance"
	not after(r).storage_encrypted == true
	msg := sprintf("%s: RDS doit être chiffré (KMS)", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_db_instance"
	after(r).backup_retention_period < 7
	msg := sprintf("%s: rétention des sauvegardes RDS >= 7 jours", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_eks_cluster"
	count(after(r).encryption_config) == 0
	msg := sprintf("%s: chiffrement des secrets EKS (KMS) obligatoire", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_eks_cluster"
	some cidr in after(r).vpc_config[0].public_access_cidrs
	cidr == "0.0.0.0/0"
	msg := sprintf("%s: API EKS publique ouverte à 0.0.0.0/0 interdite", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_eks_cluster"
	count(after(r).enabled_cluster_log_types) < 5
	msg := sprintf("%s: les 5 types de logs du control plane doivent être activés", [r.address])
}

# Aucun port d'administration ouvert à Internet
admin_ports := {22, 3389, 3306, 5432, 6379, 9200}

deny contains msg if {
	some r in changed
	r.type == "aws_vpc_security_group_ingress_rule"
	after(r).cidr_ipv4 == "0.0.0.0/0"
	after(r).from_port in admin_ports
	msg := sprintf("%s: port %d ouvert à 0.0.0.0/0", [r.address, after(r).from_port])
}

deny contains msg if {
	some r in changed
	r.type == "aws_security_group_rule"
	r.change.after.type == "ingress"
	"0.0.0.0/0" in after(r).cidr_blocks
	after(r).from_port in admin_ports
	msg := sprintf("%s: port %d ouvert à 0.0.0.0/0", [r.address, after(r).from_port])
}

# Le seul listener HTTP admis est une redirection vers HTTPS
deny contains msg if {
	some r in changed
	r.type == "aws_lb_listener"
	after(r).protocol == "HTTP"
	some act in after(r).default_action
	act.type != "redirect"
	msg := sprintf("%s: un listener HTTP doit uniquement rediriger vers HTTPS", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_lb_listener"
	after(r).protocol == "HTTPS"
	not startswith(after(r).ssl_policy, "ELBSecurityPolicy-TLS13")
	msg := sprintf("%s: politique TLS 1.3 obligatoire", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_lb"
	not after(r).drop_invalid_header_fields == true
	msg := sprintf("%s: drop_invalid_header_fields obligatoire", [r.address])
}

# IMDSv2 obligatoire (EC2 + launch templates des nodes)
deny contains msg if {
	some r in changed
	r.type == "aws_instance"
	after(r).metadata_options[0].http_tokens != "required"
	msg := sprintf("%s: IMDSv2 obligatoire (http_tokens=required)", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_launch_template"
	after(r).metadata_options[0].http_tokens != "required"
	msg := sprintf("%s: IMDSv2 obligatoire (http_tokens=required)", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_instance"
	after(r).associate_public_ip_address == true
	msg := sprintf("%s: pas d'IP publique sur les instances", [r.address])
}

# IAM : pas d'Allow "*" sur "*" et pas de confiance OIDC GitHub générique
deny contains msg if {
	some r in changed
	r.type in {"aws_iam_policy", "aws_iam_role_policy"}
	r.address != "aws_iam_policy.ci_boundary"
	doc := json.unmarshal(after(r).policy)
	some st in doc.Statement
	st.Effect == "Allow"
	is_star(st.Action)
	is_star(st.Resource)
	msg := sprintf("%s: Allow Action:* Resource:* interdit", [r.address])
}

warn contains msg if {
	some r in changed
	r.address == "aws_iam_policy.ci_boundary"
	doc := json.unmarshal(after(r).policy)
	some st in doc.Statement
	st.Effect == "Allow"
	is_star(st.Action)
	is_star(st.Resource)
	msg := "ci_boundary autorise *:* avant Deny explicites : garde-fou partiel, revue IAM humaine obligatoire"
}

deny contains msg if {
	some r in changed
	r.type == "aws_iam_role"
	doc := json.unmarshal(after(r).assume_role_policy)
	some st in doc.Statement
	some _, v in st.Condition.StringLike
	some pattern in as_array(v)
	regex.match(`^repo:[^:]*[*]`, pattern)
	msg := sprintf("%s: confiance OIDC GitHub trop large (%s)", [r.address, pattern])
}

deny contains msg if {
	some r in changed
	r.type == "aws_iam_role"
	doc := json.unmarshal(after(r).assume_role_policy)
	some st in doc.Statement
	st.Principal.Federated
	contains(sprintf("%v", [st.Principal.Federated]), "token.actions.githubusercontent.com")
	not st.Condition.StringEquals["token.actions.githubusercontent.com:sub"]
	msg := sprintf("%s: rôle OIDC GitHub sans condition sur 'sub'", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_iam_user_policy_attachment"
	msg := sprintf("%s: pas d'utilisateurs IAM (utiliser rôles + OIDC)", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_iam_access_key"
	msg := sprintf("%s: aucune clé d'accès longue durée (OIDC uniquement)", [r.address])
}

deny contains msg if {
	some r in changed
	r.type == "aws_s3_bucket_public_access_block"
	some k in ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]
	not after(r)[k] == true
	msg := sprintf("%s: %s doit être true", [r.address, k])
}

# Aucune ressource ne doit être détruite sans revue explicite pour les données
warn contains msg if {
	some r in input.resource_changes
	"delete" in r.change.actions
	r.type in {"aws_db_instance", "aws_kms_key", "aws_secretsmanager_secret", "aws_eks_cluster"}
	msg := sprintf("%s: SUPPRESSION d'une ressource critique - revue manuelle obligatoire", [r.address])
}

is_star(x) if x == "*"

is_star(x) if {
	is_array(x)
	"*" in x
}

as_array(x) := x if is_array(x)

as_array(x) := [x] if not is_array(x)
