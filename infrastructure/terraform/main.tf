###############################################################################
# TaskFlow - Infrastructure AWS (EKS + RDS MySQL + ALB + Docker Hub)
# Les ressources sont réparties par fichier : vpc, security, eks, ec2,
# alb, iam, rds. Ce fichier ne contient que les données partagées.
###############################################################################
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Le nombre d'AZ utilisées est borné par var.az_count (slice)
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = "${var.project_name}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = var.github_repository
    },
    var.extra_tags,
  )

  k8s_namespace = "taskflow"
}
