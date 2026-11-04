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

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service" {
  value = aws_ecs_service.app.name
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "github_oidc_role_arns" {
  value = {
    ecr_push = aws_iam_role.gha_ecr.arn
    deploy   = aws_iam_role.gha_deploy.arn
  }
}

# À copier dans GitHub → Settings → Secrets and variables → Actions → Variables
# (ou chargé automatiquement par `make demo-up`).
output "github_actions_variables" {
  description = "Variables (non secrètes) à créer dans GitHub Actions."
  value = {
    AWS_REGION          = var.aws_region
    AWS_ECR_ROLE_ARN    = aws_iam_role.gha_ecr.arn
    AWS_DEPLOY_ROLE_ARN = aws_iam_role.gha_deploy.arn
    APP_URL             = local.app_url
    ECS_CLUSTER         = aws_ecs_cluster.main.name
    ECS_SERVICE         = aws_ecs_service.app.name
    ECS_APP_FAMILY      = aws_ecs_task_definition.app.family
    ECS_MIGRATE_FAMILY  = aws_ecs_task_definition.migrate.family
    ECS_SUBNETS         = join(",", aws_subnet.public[*].id)
    ECS_SECURITY_GROUP  = aws_security_group.app.id
  }
}

output "secrets_ssm_prefix" {
  description = "Identifiants admin TaskFlow : aws ssm get-parameter --with-decryption --name <prefix>/seed_admin_password"
  value       = local.ssm_prefix
}

output "github_infra_pipeline_variables" {
  description = "Variables GitHub pour .github/workflows/infra.yml (vide tant que tf_state_bucket n'est pas défini)."
  value = local.infra_pipeline == 1 ? {
    TF_STATE_BUCKET       = var.tf_state_bucket
    AWS_TF_PLAN_ROLE_ARN  = aws_iam_role.gha_tf_plan[0].arn
    AWS_TF_APPLY_ROLE_ARN = aws_iam_role.gha_tf_apply[0].arn
  } : {}
}
