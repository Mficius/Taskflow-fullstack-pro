output "app_url" {
  description = "URL publique de l'application."
  value       = local.app_url
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "instance_id" {
  description = "Utiliser avec : aws ssm start-session --target <id>"
  value       = aws_instance.app.id
}

output "deploy_bucket" {
  value = aws_s3_bucket.deploy.id
}

output "github_oidc_role_arns" {
  value = {
    ecr_push = aws_iam_role.gha_ecr.arn
    deploy   = aws_iam_role.gha_deploy.arn
  }
}

# À copier dans GitHub → Settings → Secrets and variables → Actions → Variables
output "github_actions_variables" {
  description = "Variables (non secrètes) à créer dans GitHub Actions."
  value = {
    AWS_REGION          = var.aws_region
    AWS_ECR_ROLE_ARN    = aws_iam_role.gha_ecr.arn
    AWS_DEPLOY_ROLE_ARN = aws_iam_role.gha_deploy.arn
    DEPLOY_BUCKET       = aws_s3_bucket.deploy.id
    APP_URL             = local.app_url
  }
}

output "secrets_ssm_prefix" {
  description = "Les mots de passe générés (admin TaskFlow, Grafana…) sont lisibles ici avec aws ssm get-parameter --with-decryption."
  value       = local.ssm_prefix
}

output "github_infra_pipeline_variables" {
  description = "Variables GitHub pour .github/workflows/infra.yml (vide tant que tf_state_bucket n'est pas défini)."
  value = local.infra_pipeline == 1 ? {
    TF_STATE_BUCKET     = var.tf_state_bucket
    AWS_TF_PLAN_ROLE_ARN  = aws_iam_role.gha_tf_plan[0].arn
    AWS_TF_APPLY_ROLE_ARN = aws_iam_role.gha_tf_apply[0].arn
  } : {}
}
