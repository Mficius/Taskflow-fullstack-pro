data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name       = "${var.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
  ssm_prefix = "/${var.project}/${var.environment}"

  https_enabled = var.certificate_arn != ""
  app_url       = var.app_url != "" ? var.app_url : "http://${aws_lb.main.dns_name}"

  ecr_registry     = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  ecr_repositories = ["backend", "frontend", "nginx"]
  github_repo_ref  = "${var.github_owner}/${var.github_repo}"

  container_port = 8000 # nginx (passerelle) : seul conteneur exposé à l'ALB
}
