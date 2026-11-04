terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.81, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # État distant S3 (verrouillage natif). Les valeurs sont fournies à l'init :
  #   terraform init -backend-config="bucket=<bucket>" -backend-config="key=prod/terraform.tfstate" \
  #                  -backend-config="region=<region>" -backend-config="use_lockfile=true" -backend-config="encrypt=true"
  # Le bucket est créé une fois par scripts/bootstrap-tfstate.sh. En CI : terraform init -backend=false pour valider.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
