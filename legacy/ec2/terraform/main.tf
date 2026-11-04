data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# AMI Amazon Linux 2023 la plus récente (résolue via SSM, pas de filtre fragile)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name       = "${var.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
  ssm_prefix = "/${var.project}/${var.environment}"

  https_enabled = var.certificate_arn != ""
  app_url       = var.app_url != "" ? var.app_url : "http://${aws_lb.main.dns_name}"

  ecr_repositories = ["backend", "frontend"]
  github_repo_ref  = "${var.github_owner}/${var.github_repo}"
}
