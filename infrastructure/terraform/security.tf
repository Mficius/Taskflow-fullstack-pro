###############################################################################
# Sécurité transverse : KMS, Security Groups, WAF, garde-fous niveau compte
###############################################################################

# ---- KMS : une clé CMK (rotation activée) pour EKS secrets, RDS et logs ---
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Politique de clé KMS standard : l'administration est déléguée à IAM via le compte racine
  #checkov:skip=CKV_AWS_111:Idem
  #checkov:skip=CKV_AWS_356:Dans une key policy, "*" désigne la clé elle-même
  statement {
    sid       = "AccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*",
      "kms:GenerateDataKey*", "kms:Describe*"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "main" {
  description             = "${local.name} - chiffrement EKS/RDS/logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}

# ---- Security Groups ---------------------------------------------------------
resource "aws_security_group" "alb" {
  name_prefix = "${local.name}-alb-"
  description = "ALB public TaskFlow"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS depuis ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

# Le port 80 n'est ouvert que pour répondre par une redirection 301 vers HTTPS
resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  #checkov:skip=CKV_AWS_260:Port 80 ouvert uniquement pour la redirection 301 vers HTTPS (listener sans forward)
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP (redirection 301 vers HTTPS) depuis ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_pods" {
  security_group_id = aws_security_group.alb.id
  description       = "ALB vers les pods (port applicatif 8080) dans le VPC"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = var.vpc_cidr
}

# Autorise l'ALB à joindre les pods (SG du cluster EKS = SG des nodes et pods)
resource "aws_vpc_security_group_ingress_rule" "cluster_from_alb" {
  security_group_id            = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description                  = "ALB vers pods TaskFlow 8080"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  description = "MySQL TaskFlow - accessible uniquement depuis EKS (et l'hote ops)"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL depuis les pods EKS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "eks_api_from_ops" {
  count = var.enable_ops_host ? 1 : 0

  security_group_id            = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description                  = "API Kubernetes privée depuis l'hôte ops SSM"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ops[0].id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ops" {
  count = var.enable_ops_host ? 1 : 0

  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL depuis l'hote ops (SSM port-forward)"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.ops[0].id
}

resource "aws_security_group" "ops" {
  count = var.enable_ops_host ? 1 : 0

  name_prefix = "${local.name}-ops-"
  description = "Hote d'administration SSM-only (aucune entree)"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "ops_https" {
  count = var.enable_ops_host ? 1 : 0

  security_group_id = aws_security_group.ops[0].id
  description       = "HTTPS sortant (SSM, API EKS, mises a jour)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ops_to_rds" {
  count = var.enable_ops_host ? 1 : 0

  security_group_id            = aws_security_group.ops[0].id
  description                  = "MySQL vers RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

# ---- WAF v2 (attaché à l'ALB dans alb.tf) -------------------------------------
resource "aws_wafv2_web_acl" "alb" {
  name        = "${local.name}-alb"
  description = "Protection L7 TaskFlow (OWASP Top 10, IP reputation, rate limiting)"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  # Log4Shell / entrées malveillantes connues
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = {
      "AWSManagedRulesAmazonIpReputationList" = 10
      "AWSManagedRulesCommonRuleSet"          = 20
      "AWSManagedRulesSQLiRuleSet"            = 40
      "AWSManagedRulesPHPRuleSet"             = 50
    }
    content {
      name     = rule.key
      priority = rule.value
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-alb"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_log_group" "waf" {
  # Le nom DOIT commencer par aws-waf-logs-
  name              = "aws-waf-logs-${local.name}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  resource_arn            = aws_wafv2_web_acl.alb.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}

# ---- Garde-fous niveau compte (Preventive Controls) --------------------------
# Impossible de rendre un bucket S3 public dans ce compte
resource "aws_s3_account_public_access_block" "account" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tout volume EBS créé dans la région est chiffré
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  key_arn = aws_kms_key.main.arn
}

# IMDSv2 obligatoire par défaut (anti-SSRF vers les credentials)
resource "aws_ec2_instance_metadata_defaults" "this" {
  http_tokens                 = "required"
  http_put_response_hop_limit = 2
}
