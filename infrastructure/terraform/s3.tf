###############################################################################
# Stockage des pièces jointes TaskFlow. Le bucket est privé et les pods utilisent
# IRSA. Les endpoints S3 et STS restent accessibles depuis le VPC.
###############################################################################
resource "aws_s3_bucket" "app_files" {
  bucket_prefix = "${local.name}-files-"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "app_files" {
  bucket                  = aws_s3_bucket.app_files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "app_files_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.app_files.arn, "${aws_s3_bucket.app_files.arn}/*"]

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

resource "aws_s3_bucket_policy" "app_files" {
  bucket = aws_s3_bucket.app_files.id
  policy = data.aws_iam_policy_document.app_files_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.app_files]
}

resource "aws_security_group" "aws_endpoints" {
  name_prefix = "${local.name}-aws-endpoints-"
  description = "HTTPS depuis EKS vers les endpoints AWS prives"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS depuis le SG du cluster EKS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }
}

resource "aws_vpc_endpoint" "s3_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.aws_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${local.name}-s3-interface" }
}

resource "aws_vpc_endpoint" "sts_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.aws_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${local.name}-sts-interface" }
}
