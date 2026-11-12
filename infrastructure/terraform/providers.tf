###############################################################################
# Providers & backend
# - Le state distant est chiffré (S3 + KMS) et verrouillé (DynamoDB).
# - La configuration du backend est PARTIELLE : voir backend.hcl.example
#   terraform init -backend-config=backend.hcl
###############################################################################
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  # Tags appliqués à TOUTES les ressources (gouvernance + coûts + preuve d'IaC)
  default_tags {
    tags = local.common_tags
  }
}
