# ═══════════════════════════════════════════════════════════
#  ECS Fargate : cluster, définitions de tâche, service
# ═══════════════════════════════════════════════════════════
# Une tâche = 3 conteneurs partageant localhost :
#   nginx (passerelle, seul exposé à l'ALB, port 8000)  →  frontend (statique, 8080)  +  backend (PHP-FPM, 9000)
# Les révisions réelles des définitions de tâche sont enregistrées par la CD (scripts/ecs-deploy.sh) avec
# les tags d'image du commit ; Terraform ne gère que la structure (d'où ignore_changes sur le service).

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "${local.ssm_prefix}/ecs"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "main" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

locals {
  image = { for k, r in aws_ecr_repository.app : k => "${r.repository_url}:${var.bootstrap_image_tag}" }

  log_options = {
    awslogs-group  = aws_cloudwatch_log_group.ecs.name
    awslogs-region = var.aws_region
  }

  backend_env = [
    { name = "APP_NAME", value = "TaskFlow" },
    { name = "APP_ENV", value = "production" },
    { name = "APP_DEBUG", value = "false" },
    { name = "APP_URL", value = local.app_url },
    { name = "LOG_CHANNEL", value = "stderr" },
    { name = "LOG_LEVEL", value = "warning" },
    { name = "DB_CONNECTION", value = "mysql" },
    { name = "DB_HOST", value = aws_db_instance.main.address },
    { name = "DB_PORT", value = "3306" },
    { name = "DB_DATABASE", value = "taskflow" },
    { name = "DB_USERNAME", value = "taskflow" },
    { name = "SESSION_DRIVER", value = "database" },
    { name = "CACHE_STORE", value = "database" },
    { name = "QUEUE_CONNECTION", value = "database" },
    { name = "CORS_ALLOWED_ORIGINS", value = local.app_url },
    { name = "RUN_MIGRATIONS", value = "false" }, # les migrations sont jouées par la tâche « migrate » avant chaque déploiement
  ]

  backend_secrets = [
    { name = "APP_KEY", valueFrom = aws_ssm_parameter.secret["app_key"].arn },
    { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.secret["db_password"].arn },
  ]

  migrate_secrets = concat(local.backend_secrets, [
    { name = "SEED_ADMIN_EMAIL", valueFrom = aws_ssm_parameter.secret["seed_admin_email"].arn },
    { name = "SEED_ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.secret["seed_admin_password"].arn },
  ])
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name              = "backend"
      image             = local.image["backend"]
      essential         = true
      memoryReservation = 512
      portMappings      = [{ containerPort = 9000, protocol = "tcp" }]
      environment       = local.backend_env
      secrets           = local.backend_secrets
      linuxParameters   = { initProcessEnabled = true }
      healthCheck = {
        command     = ["CMD-SHELL", "SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 | grep -q pong"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 60
      }
      logConfiguration = { logDriver = "awslogs", options = merge(local.log_options, { awslogs-stream-prefix = "backend" }) }
    },
    {
      name              = "frontend"
      image             = local.image["frontend"]
      essential         = true
      memoryReservation = 64
      portMappings      = [{ containerPort = 8080, protocol = "tcp" }]
      linuxParameters   = { initProcessEnabled = true }
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
      logConfiguration = { logDriver = "awslogs", options = merge(local.log_options, { awslogs-stream-prefix = "frontend" }) }
    },
    {
      name              = "nginx"
      image             = local.image["nginx"]
      essential         = true
      memoryReservation = 64
      portMappings      = [{ containerPort = local.container_port, protocol = "tcp" }]
      environment = [
        { name = "BACKEND_HOST", value = "127.0.0.1" },
        { name = "FRONTEND_HOST", value = "127.0.0.1" },
        { name = "LISTEN_PORT", value = tostring(local.container_port) },
      ]
      dependsOn = [
        { containerName = "backend", condition = "HEALTHY" },
        { containerName = "frontend", condition = "HEALTHY" },
      ]
      linuxParameters = { initProcessEnabled = true }
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:${local.container_port}/up || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }
      logConfiguration = { logDriver = "awslogs", options = merge(local.log_options, { awslogs-stream-prefix = "nginx" }) }
    },
  ])
}

# Tâche ponctuelle : migrations Laravel (+ création de l'admin au premier passage), jouée par la CD
# AVANT la mise à jour du service. Si elle échoue, rien n'est déployé.
resource "aws_ecs_task_definition" "migrate" {
  family                   = "${local.name}-migrate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name        = "backend"
      image       = local.image["backend"]
      essential   = true
      command     = ["sh", "-c", "php artisan migrate --force --no-interaction && php artisan db:seed --force --no-interaction"]
      environment = local.backend_env
      secrets     = local.migrate_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options, { awslogs-stream-prefix = "migrate" })
      }
    },
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 0 # la CD le fixe (DESIRED_COUNT) après avoir poussé les premières images
  launch_type     = "FARGATE"
  force_delete    = var.demo_mode

  enable_execute_command             = true
  health_check_grace_period_seconds  = 90
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Retour arrière AUTOMATIQUE si le nouveau déploiement n'atteint pas l'état sain.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true # sortie vers ECR/SSM/Logs sans NAT ; entrée impossible hors ALB (security group)
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "nginx"
    container_port   = local.container_port
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
