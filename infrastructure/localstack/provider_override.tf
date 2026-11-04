# Fichier d'OVERRIDE Terraform : copié temporairement dans infrastructure/terraform/ par run-tests.sh
# pour rediriger le provider AWS vers LocalStack. Il n'est JAMAIS utilisé en production.
terraform {
  backend "local" {}
}

provider "aws" {
  region                      = "eu-west-3"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2                    = "http://localhost:4566"
    ecr                    = "http://localhost:4566"
    ecs                    = "http://localhost:4566"
    elbv2                  = "http://localhost:4566"
    rds                    = "http://localhost:4566"
    iam                    = "http://localhost:4566"
    sts                    = "http://localhost:4566"
    ssm                    = "http://localhost:4566"
    sns                    = "http://localhost:4566"
    logs                   = "http://localhost:4566"
    cloudwatch             = "http://localhost:4566"
    s3                     = "http://localhost:4566"
    applicationautoscaling = "http://localhost:4566"
  }
}
