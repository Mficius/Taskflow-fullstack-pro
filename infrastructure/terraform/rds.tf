# Base de données managée : sous-réseaux isolés, chiffrée, sauvegardes automatiques (PITR),
# accessible uniquement depuis les tâches ECS (security group).
resource "aws_db_instance" "main" {
  identifier     = "${local.name}-mysql"
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 3
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "taskflow"
  username = "taskflow"
  password = random_password.db_app.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period    = var.db_backup_retention_days
  backup_window              = "02:00-03:00"
  maintenance_window         = "Mon:03:30-Mon:04:30"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  # Production : protégée. Démonstration : détruisible sans snapshot final.
  deletion_protection       = !var.demo_mode
  skip_final_snapshot       = var.demo_mode
  final_snapshot_identifier = var.demo_mode ? null : "${local.name}-final"
  apply_immediately         = var.demo_mode
}
