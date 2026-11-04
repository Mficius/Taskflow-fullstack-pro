# ═══════════════════════════════════════════════════════════
#  SÉCURITÉ : security groups · IAM instance · secrets · OIDC GitHub
# ═══════════════════════════════════════════════════════════

# ── Security groups ─────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB public"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "Instance applicative : trafic entrant uniquement depuis l'ALB"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each          = toset(var.allowed_ingress_cidrs)
  security_group_id = aws_security_group.alb.id
  description       = "HTTP"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each          = local.https_enabled ? toset(var.allowed_ingress_cidrs) : toset([])
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB vers instance"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP depuis l'ALB uniquement"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

# Aucun SSH : l'administration passe par AWS Systems Manager (Session Manager).
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS sortant (ECR, S3, SSM, dnf, images Docker)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP sortant (dépôts Amazon Linux)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_dns" {
  security_group_id = aws_security_group.app.id
  description       = "DNS (résolveur du VPC)"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = var.vpc_cidr
}

# ── Secrets applicatifs (SSM Parameter Store, SecureString) ─
# Générés par Terraform, jamais écrits dans le dépôt ni dans les variables GitHub.
# NB : ils figurent dans le state Terraform → utiliser un backend S3 chiffré.
resource "random_password" "db_root" {
  length  = 32
  special = false
}

resource "random_password" "db_app" {
  length  = 32
  special = false
}

resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "random_password" "seed_admin" {
  length  = 20
  special = false
}

resource "random_id" "app_key" {
  byte_length = 32
}

locals {
  secrets = {
    db_root_password       = random_password.db_root.result
    db_password            = random_password.db_app.result
    grafana_admin_password = random_password.grafana.result
    seed_admin_password    = random_password.seed_admin.result
    seed_admin_email       = var.admin_email
    app_key                = "base64:${random_id.app_key.b64_std}"
  }
}

resource "aws_ssm_parameter" "secret" {
  for_each = nonsensitive(toset(keys(local.secrets)))
  name     = "${local.ssm_prefix}/${each.key}"
  type     = "SecureString"
  value    = local.secrets[each.key]
}

# ── Rôle IAM de l'instance (moindre privilège) ──────────────
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${local.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "instance" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid       = "EcrPull"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = [for r in aws_ecr_repository.app : r.arn]
  }
  statement {
    sid       = "ReadDeployBundles"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.deploy.arn}/bundles/*"]
  }
  statement {
    sid       = "ReadOwnSecrets"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter${local.ssm_prefix}",
      "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter${local.ssm_prefix}/*",
    ]
  }
  statement {
    sid       = "DecryptSecretsViaSsmOnly"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "taskflow-instance"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name
}

# ═══════════════════════════════════════════════════════════
#  OIDC GitHub Actions → AWS (aucune clé d'accès longue durée)
# ═══════════════════════════════════════════════════════════
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# Rôle 1 — CI/CD « build » : peut UNIQUEMENT pousser des images ECR, et seulement depuis la branche main.
data "aws_iam_policy_document" "gha_ecr_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo_ref}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "gha_ecr" {
  name                 = "${local.name}-gha-ecr-push"
  description          = "GitHub Actions (${local.github_repo_ref}@${var.github_branch}) : push ECR"
  assume_role_policy   = data.aws_iam_policy_document.gha_ecr_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "gha_ecr" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages",
    ]
    resources = [for r in aws_ecr_repository.app : r.arn]
  }
}

resource "aws_iam_role_policy" "gha_ecr" {
  name   = "ecr-push"
  role   = aws_iam_role.gha_ecr.id
  policy = data.aws_iam_policy_document.gha_ecr.json
}

# Rôle 2 — CD « deploy » : uniquement depuis l'environnement GitHub protégé (approbation manuelle possible).
data "aws_iam_policy_document" "gha_deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo_ref}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "gha_deploy" {
  name                 = "${local.name}-gha-deploy"
  description          = "GitHub Actions (${local.github_repo_ref}, env ${var.github_environment}) : déploiement via SSM"
  assume_role_policy   = data.aws_iam_policy_document.gha_deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "gha_deploy" {
  statement {
    sid       = "UploadBundle"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.deploy.arn}/bundles/*"]
  }
  statement {
    sid       = "VerifyImageExists"
    actions   = ["ecr:DescribeImages"]
    resources = [for r in aws_ecr_repository.app : r.arn]
  }
  statement {
    sid       = "RunDeployDocument"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript"]
  }
  statement {
    sid       = "RunOnTaggedInstanceOnly"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${var.aws_region}:${local.account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Project"
      values   = [var.project]
    }
  }
  statement {
    sid       = "ReadCommandResult"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:ListCommands", "ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  name   = "ssm-deploy"
  role   = aws_iam_role.gha_deploy.id
  policy = data.aws_iam_policy_document.gha_deploy.json
}

# ═══════════════════════════════════════════════════════════
#  Pipeline INFRA (terraform plan / apply) — rôles OIDC dédiés
#  Créés seulement si tf_state_bucket est renseigné (après le bootstrap).
# ═══════════════════════════════════════════════════════════
locals {
  infra_pipeline = var.tf_state_bucket != "" ? 1 : 0
}

# Plan : lecture seule de l'infra, déclenchable depuis une pull request.
data "aws_iam_policy_document" "gha_tf_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo_ref}:pull_request", "repo:${local.github_repo_ref}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "gha_tf_plan" {
  count              = local.infra_pipeline
  name               = "${local.name}-gha-tf-plan"
  description        = "GitHub Actions : terraform plan (lecture seule)"
  assume_role_policy = data.aws_iam_policy_document.gha_tf_plan_trust.json
}

resource "aws_iam_role_policy_attachment" "gha_tf_plan_readonly" {
  count      = local.infra_pipeline
  role       = aws_iam_role.gha_tf_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "gha_tf_state" {
  count = local.infra_pipeline
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.tf_state_bucket}"]
  }
  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.tf_state_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "gha_tf_plan_state" {
  count  = local.infra_pipeline
  name   = "tfstate"
  role   = aws_iam_role.gha_tf_plan[0].id
  policy = data.aws_iam_policy_document.gha_tf_state[0].json
}

# Apply : uniquement depuis l'environnement GitHub protégé (approbation humaine).
data "aws_iam_policy_document" "gha_tf_apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo_ref}:environment:${var.github_infra_environment}"]
    }
  }
}

resource "aws_iam_role" "gha_tf_apply" {
  count              = local.infra_pipeline
  name               = "${local.name}-gha-tf-apply"
  description        = "GitHub Actions : terraform apply (environnement ${var.github_infra_environment})"
  assume_role_policy = data.aws_iam_policy_document.gha_tf_apply_trust.json
}

# Terraform gère IAM, VPC, EC2, ALB… : ce rôle est très puissant. Il n'est assumable
# que depuis l'environnement protégé ; à restreindre davantage une fois l'infra stabilisée.
resource "aws_iam_role_policy_attachment" "gha_tf_apply_admin" {
  count      = local.infra_pipeline
  role       = aws_iam_role.gha_tf_apply[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ═══════════════════════════════════════════════════════════
#  Garde-fous PRÉVENTIFS au niveau du compte
# ═══════════════════════════════════════════════════════════
# Impossible de rendre public un bucket S3 du compte, même par erreur de configuration.
resource "aws_s3_account_public_access_block" "account" {
  count                   = var.enable_account_guardrails ? 1 : 0
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tout nouveau volume EBS de la région est chiffré, même si le code l'oublie.
resource "aws_ebs_encryption_by_default" "this" {
  count   = var.enable_account_guardrails ? 1 : 0
  enabled = true
}
