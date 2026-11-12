output "vpc_id" {
  value = aws_vpc.main.id
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "alb_dns_name" {
  description = "DNS de l'ALB (créer un CNAME/ALIAS vers cette valeur)."
  value       = aws_lb.main.dns_name
}

output "alb_target_group_arns" {
  description = "ARN à renseigner dans values-eks.yaml (targetGroupBinding)."
  value = {
    frontend = aws_lb_target_group.frontend.arn
    api      = aws_lb_target_group.api.arn
  }
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "rds_master_secret_arn" {
  description = "Secret Manager contenant le mot de passe RDS (géré par AWS)."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "app_secret_name" {
  value = aws_secretsmanager_secret.app.name
}

output "github_role_arns" {
  description = "À copier dans les variables du dépôt GitHub (Settings > Variables)."
  value       = { for k, r in aws_iam_role.github : k => r.arn }
}

output "irsa_role_arns" {
  value = { for k, r in aws_iam_role.irsa : k => r.arn }
}

output "ops_instance_id" {
  value = var.enable_ops_host ? aws_instance.ops[0].id : null
}

output "rds_app_secret_arn" {
  description = "Secret JSON username/password du compte SQL applicatif TaskFlow."
  value       = aws_secretsmanager_secret.db_app.arn
}

output "app_files_bucket" {
  description = "Bucket S3 privé pour les fichiers téléversés par TaskFlow."
  value       = aws_s3_bucket.app_files.bucket
}


output "rds_migrator_secret_arn" {
  description = "Secret JSON du compte MySQL réservé aux migrations."
  value       = aws_secretsmanager_secret.db_migrator.arn
}
