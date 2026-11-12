###############################################################################
# RDS MySQL : privé, chiffré KMS, TLS obligatoire, mot de passe géré par AWS
# Secrets Manager, sauvegardes, logs, Performance Insights.
###############################################################################
resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db"
  subnet_ids = aws_subnet.database[*].id
}

resource "aws_db_parameter_group" "mysql" {
  name_prefix = "${local.name}-mysql8-"
  family      = "mysql8.0"
  description = "TaskFlow MySQL 8.0 - TLS obligatoire"

  parameter {
    name  = "require_secure_transport"
    value = "1"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier = local.name

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  port     = 3306

  # Pas de mot de passe dans le state ni dans le code : AWS le génère et le fait tourner
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.arn

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.mysql.name
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  copy_tags_to_snapshot               = true

  backup_retention_period   = var.db_backup_retention_days
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:03:30-sun:04:30"
  deletion_protection       = var.environment == "prod"
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-final"

  enabled_cloudwatch_logs_exports       = ["error", "general", "slowquery"]
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.main.arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}

# ---- Secret applicatif : APP_KEY Laravel ----------------------------------------
resource "random_id" "app_key" {
  byte_length = 32
}

resource "aws_secretsmanager_secret" "app" {
  #checkov:skip=CKV2_AWS_57:APP_KEY Laravel ne doit pas être roté automatiquement (invalide les données chiffrées / tokens)
  name                    = "${var.project_name}/${var.environment}/laravel"
  description             = "Secrets applicatifs TaskFlow (lus par External Secrets Operator)"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    APP_KEY = "base64:${random_id.app_key.b64_std}"
  })
}


# Identifiants dédiés à Laravel. Le mot de passe est généré par Terraform et
# stocké dans Secrets Manager ; le compte SQL doit être créé une fois via le runbook.
resource "random_password" "db_app" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_app" {
  name                    = "${var.project_name}/${var.environment}/database-app"
  description             = "Compte MySQL applicatif TaskFlow (jamais le compte maître RDS)"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db_app" {
  secret_id = aws_secretsmanager_secret.db_app.id
  secret_string = jsonencode({
    username = "${var.project_name}_app"
    password = random_password.db_app.result
  })
}


resource "random_password" "db_migrator" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_migrator" {
  name                    = "${var.project_name}/${var.environment}/database-migrator"
  description             = "Compte MySQL réservé aux migrations Laravel"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db_migrator" {
  secret_id = aws_secretsmanager_secret.db_migrator.id
  secret_string = jsonencode({
    username = "${var.project_name}_migrator"
    password = random_password.db_migrator.result
  })
}
