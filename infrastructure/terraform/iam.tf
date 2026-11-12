###############################################################################
# IAM : tout passe par des identités fédérées, AUCUNE clé d'accès longue durée.
#   - GitHub Actions -> AWS      : OIDC (rôles à courte durée, scopés repo/env)
#   - Pods EKS       -> AWS      : IRSA (OIDC du cluster)
###############################################################################

# =============================== GitHub OIDC ===================================
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # Une identité = un "sub" précis. Jamais de repo:org/*.
  github_roles = {
    # terraform plan via l'Environment terraform-plan restreint à main : lecture du state
    tf-plan = { sub = "repo:${var.github_repository}:environment:terraform-plan" }
    # terraform apply (Environment "production-infra" : approbation manuelle)
    tf-apply = { sub = "repo:${var.github_repository}:environment:${var.github_infra_environment}" }
  }
}

data "aws_iam_policy_document" "github_assume" {
  for_each = local.github_roles

  statement {
    effect  = "Allow"
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
      values   = [each.value.sub]
    }
  }
}

# Boundary partielle : bloque plusieurs credentials durables et actions d'organisation; ne remplace pas une policy least-privilege
data "aws_iam_policy_document" "ci_boundary" {
  #checkov:skip=CKV_AWS_1:Permissions boundary = plafond (Allow * puis Deny explicites), pas une policy d'octroi
  #checkov:skip=CKV_AWS_49:Idem - plafond de permissions
  #checkov:skip=CKV_AWS_107:Idem - les Deny ci-dessous interdisent la création de credentials
  #checkov:skip=CKV_AWS_108:Idem - plafond de permissions
  #checkov:skip=CKV_AWS_109:Idem - plafond de permissions
  #checkov:skip=CKV_AWS_110:Idem - plafond de permissions
  #checkov:skip=CKV_AWS_111:Idem - plafond de permissions
  #checkov:skip=CKV_AWS_356:Idem - plafond de permissions
  #checkov:skip=CKV2_AWS_40:Idem - plafond de permissions
  statement {
    sid       = "AllowAllWithinGuardrails"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyLongLivedCredentialsAndOrgChanges"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "iam:DetachUserPolicy",
      "iam:DeleteUserPolicy",
      "iam:PutUserPermissionsBoundary",
      "iam:DeleteUserPermissionsBoundary",
      "iam:UpdateAccessKey",
      "iam:CreateServiceSpecificCredential",
      "iam:UpdateServiceSpecificCredential",
      "iam:DeleteServiceSpecificCredential",
      "iam:DeleteRolePermissionsBoundary",
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyTamperingWithAuditAndKeys"
    effect = "Deny"
    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "kms:ScheduleKeyDeletion",
      "guardduty:DeleteDetector",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_boundary" {
  name   = "${local.name}-ci-boundary"
  policy = data.aws_iam_policy_document.ci_boundary.json
}

resource "aws_iam_role" "github" {
  for_each = local.github_roles

  name                 = "${local.name}-gh-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.github_assume[each.key].json
  max_session_duration = 3600
  permissions_boundary = each.key == "tf-apply" ? aws_iam_policy.ci_boundary.arn : null
}

# Les images sont publiées sur Docker Hub par GitHub Actions avec les secrets
# DOCKER_USERNAME / DOCKER_PASSWORD. Aucun rôle AWS n'est requis pour ce push.

data "aws_iam_policy_document" "tf_plan_deny_secret_values" {
  # Le provider Terraform doit rafraîchir les 3 versions de secrets qu'il gère.
  # Tous les autres secrets, notamment le secret maître RDS, restent interdits.
  statement {
    sid           = "DenyUnmanagedSecretValues"
    effect        = "Deny"
    actions       = ["secretsmanager:GetSecretValue"]
    not_resources = [
      aws_secretsmanager_secret.app.arn,
      aws_secretsmanager_secret.db_app.arn,
      aws_secretsmanager_secret.db_migrator.arn,
    ]
  }

  statement {
    sid    = "DenySSMParameterValues"
    effect = "Deny"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:GetParameterHistory",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "tf_plan_deny_secret_values" {
  name   = "deny-secret-value-reads"
  role   = aws_iam_role.github["tf-plan"].id
  policy = data.aws_iam_policy_document.tf_plan_deny_secret_values.json
}

# ---- tf-plan : lecture seule + lecture du state ----------------------------------------
resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.github["tf-plan"].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "tf_plan_state" {
  count = var.tfstate_bucket_arn != "" ? 1 : 0

  statement {
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
    ]
    resources = [var.tfstate_bucket_arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.tfstate_bucket_arn}/*"]
  }
  statement {
    sid     = "RefreshOnlyTerraformManagedSecrets"
    actions = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.app.arn,
      aws_secretsmanager_secret.db_app.arn,
      aws_secretsmanager_secret.db_migrator.arn,
    ]
  }
  dynamic "statement" {
    for_each = var.tfstate_lock_table_arn != "" ? [1] : []
    content {
      actions   = ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      resources = [var.tfstate_lock_table_arn]
    }
  }
  dynamic "statement" {
    for_each = var.tfstate_kms_key_arn != "" ? [1] : []
    content {
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = [var.tfstate_kms_key_arn]
    }
  }
  statement {
    sid       = "DecryptOnlyTerraformManagedSecrets"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:SecretARN"
      values = [
        aws_secretsmanager_secret.app.arn,
        aws_secretsmanager_secret.db_app.arn,
        aws_secretsmanager_secret.db_migrator.arn,
      ]
    }
  }
}

resource "aws_iam_role_policy" "tf_plan_state" {
  count  = var.tfstate_bucket_arn != "" ? 1 : 0
  name   = "tfstate-read"
  role   = aws_iam_role.github["tf-plan"].id
  policy = data.aws_iam_policy_document.tf_plan_state[0].json
}

# ---- tf-apply : admin, mais encadré par la permissions boundary ---------------------------
resource "aws_iam_role_policy_attachment" "tf_apply_admin" {
  role       = aws_iam_role.github["tf-apply"].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

# =============================== IRSA (pods) ====================================
data "aws_iam_policy_document" "irsa_assume" {
  for_each = local.irsa_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

locals {
  irsa_roles = {
    "vpc-cni" = {
      namespace       = "kube-system"
      service_account = "aws-node"
    }
    "external-secrets" = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
    "lb-controller" = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    "taskflow-app" = {
      namespace       = "taskflow"
      service_account = "taskflow-production-api"
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_roles

  name               = "${local.name}-irsa-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[each.key].json
}

resource "aws_iam_role_policy_attachment" "irsa_vpc_cni" {
  role       = aws_iam_role.irsa["vpc-cni"].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# External Secrets Operator : lecture des trois secrets applicatifs, jamais du secret maître RDS
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid     = "ReadTaskflowSecrets"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.app.arn,
      aws_secretsmanager_secret.db_app.arn,
      aws_secretsmanager_secret.db_migrator.arn,
    ]
  }
  statement {
    sid       = "DecryptWithProjectKey"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "read-taskflow-secrets"
  role   = aws_iam_role.irsa["external-secrets"].id
  policy = data.aws_iam_policy_document.external_secrets.json
}

# TaskFlow API / worker : accès limité au bucket de fichiers applicatifs.
data "aws_iam_policy_document" "taskflow_app_s3" {
  statement {
    sid       = "ListTaskflowBucket"
    actions = ["s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.app_files.arn]
  }
  statement {
    sid = "ManageTaskflowObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.app_files.arn}/*"]
  }
}

resource "aws_iam_role_policy" "taskflow_app_s3" {
  name   = "taskflow-app-files"
  role   = aws_iam_role.irsa["taskflow-app"].id
  policy = data.aws_iam_policy_document.taskflow_app_s3.json
}

# AWS Load Balancer Controller en mode "TargetGroupBinding" uniquement
# (l'ALB et ses listeners sont gérés par Terraform, voir alb.tf) -> droits minimaux
data "aws_iam_policy_document" "lb_controller" {
  statement {
    sid = "TargetGroupBindingOnly"
    actions = [
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeListeners",
      "ec2:DescribeInstances",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "RegisterOnTaskflowTargetGroupsOnly"
    actions = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
    resources = [
      aws_lb_target_group.frontend.arn,
      aws_lb_target_group.api.arn,
    ]
  }
}

resource "aws_iam_role_policy" "lb_controller" {
  name   = "targetgroupbinding"
  role   = aws_iam_role.irsa["lb-controller"].id
  policy = data.aws_iam_policy_document.lb_controller.json
}

# =============================== Rôles de service =================================
data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "eks_cluster_kms" {
  statement {
    sid = "UseEksSecretsEncryptionKey"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.main.arn]
  }

  statement {
    sid       = "CreateEksResourceGrant"
    actions   = ["kms:CreateGrant"]
    resources = [aws_kms_key.main.arn]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "eks_cluster_kms" {
  name   = "eks-secrets-kms"
  role   = aws_iam_role.eks_cluster.id
  policy = data.aws_iam_policy_document.eks_cluster_kms.json
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_nodes" {
  name               = "${local.name}-eks-nodes"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_nodes" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.key}"
}

# ---- VPC flow logs ------------------------------------------------------------------
data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${local.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

# ---- RDS enhanced monitoring ------------------------------------------------------------
data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${local.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---- Hôte ops (SSM uniquement) -------------------------------------------------------------
resource "aws_iam_role" "ops" {
  count = var.enable_ops_host ? 1 : 0

  name               = "${local.name}-ops"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ops_ssm" {
  count = var.enable_ops_host ? 1 : 0

  role       = aws_iam_role.ops[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ops" {
  count = var.enable_ops_host ? 1 : 0

  name = "${local.name}-ops"
  role = aws_iam_role.ops[0].name
}
