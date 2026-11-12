###############################################################################
# ALB public : HTTPS uniquement (TLS 1.3), WAF, logs d'accès chiffrés.
# Les target groups (type "ip") sont alimentés par des TargetGroupBinding
# Kubernetes via helm/taskflow/templates/targetgroupbinding.yaml.
###############################################################################

# ---- Bucket des access logs (privé, chiffré, versionné) -------------------------------
resource "aws_s3_bucket" "alb_logs" {
  #checkov:skip=CKV_AWS_18:Bucket de logs lui-même (pas de log de log)
  #checkov:skip=CKV_AWS_144:Réplication inter-région non requise pour des logs d'accès
  #checkov:skip=CKV_AWS_145:Les access logs ALB ne supportent que SSE-S3 (limitation AWS)
  #checkov:skip=CKV2_AWS_62:Pas de notifications d'événements nécessaires
  bucket_prefix = "${local.name}-alb-logs-"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Les logs ALB ne supportent que SSE-S3 (pas SSE-KMS)
#trivy:ignore:AWS-0132 -- les access logs ALB ne supportent que SSE-S3 (limitation AWS)
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 365
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "AlbWriteLogs"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.alb_logs.arn,
      "${aws_s3_bucket.alb_logs.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

# ---- Load balancer ----------------------------------------------------------------------
resource "aws_lb" "main" {
  #checkov:skip=CKV2_AWS_76:KnownBadInputsRuleSet (Log4j) est actif dans le WAF associé (CKV_AWS_192 validé) ; la règle de graphe ne résout pas le bloc dynamique
  name               = substr("${local.name}-alb", 0, 32)
  load_balancer_type = "application"
  internal           = false #tfsec:ignore:aws-elb-alb-not-public -- point d'entrée public voulu, protégé par WAF + HTTPS
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = var.environment == "prod"
  enable_http2               = true
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}

# ---- Target groups (alimentés par TargetGroupBinding) ------------------------------------
resource "aws_lb_target_group" "frontend" {
  name        = substr("${local.name}-web", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "api" {
  #checkov:skip=CKV_AWS_378:Trafic ALB->pod en HTTP dans des sous-réseaux privés ; TLS bout-en-bout nécessite un service mesh (hors périmètre)
  name        = substr("${local.name}-api", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    path                = "/up"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ---- Listeners --------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    path_pattern {
      values = ["/api", "/api/*", "/up"]
    }
  }
}
