# Tests UNITAIRES : aucun compte AWS, aucun LocalStack — les providers sont simulés (mock_provider).
# Lancer : terraform -chdir=infrastructure/terraform test
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "random" {}

variables {
  aws_region   = "eu-west-3"
  github_owner = "example"
  github_repo  = "taskflow"
}

run "network_is_locked_down" {
  command = plan

  assert {
    condition     = length(aws_subnet.db) == 2 && alltrue([for s in aws_subnet.db : s.map_public_ip_on_launch == false])
    error_message = "Les sous-réseaux de base de données doivent être isolés (pas d'IP publique)."
  }

  assert {
    condition     = aws_security_group.db.name == "taskflow-prod-db"
    error_message = "Le security group de la base doit exister."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.db_from_app.from_port == 3306
    error_message = "MySQL ne doit être joignable que depuis les tâches ECS."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.app_from_alb.from_port == 8000
    error_message = "Les tâches ne doivent recevoir du trafic que de l'ALB sur le port de la passerelle."
  }
}

run "database_is_private_and_encrypted" {
  command = plan

  assert {
    condition     = aws_db_instance.main.storage_encrypted == true
    error_message = "RDS doit être chiffrée."
  }

  assert {
    condition     = aws_db_instance.main.publicly_accessible == false
    error_message = "RDS ne doit pas être publique."
  }

  assert {
    condition     = aws_db_instance.main.backup_retention_period >= 7
    error_message = "Au moins 7 jours de sauvegardes."
  }
}

run "registry_is_immutable_and_scanned" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_ecr_repository.app : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "Tous les dépôts ECR doivent avoir des tags immuables."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.app : r.image_scanning_configuration[0].scan_on_push])
    error_message = "Le scan à l'envoi doit être activé."
  }

  assert {
    condition     = length(aws_ecr_repository.app) == 3
    error_message = "Trois dépôts attendus : backend, frontend, nginx."
  }
}

run "service_rolls_back_automatically" {
  command = plan

  assert {
    condition     = aws_ecs_service.app.deployment_circuit_breaker[0].enable && aws_ecs_service.app.deployment_circuit_breaker[0].rollback
    error_message = "Le circuit breaker avec rollback automatique doit être actif."
  }

  assert {
    condition     = aws_ecs_service.app.desired_count == 0
    error_message = "Le service démarre à 0 : la CD le fixe après le push des premières images."
  }

  assert {
    condition     = one(aws_ecs_cluster.main.setting).value == "enabled"
    error_message = "Container Insights doit être activé."
  }
}

run "alb_is_hardened" {
  command = plan

  assert {
    condition     = aws_lb.main.drop_invalid_header_fields == true
    error_message = "L'ALB doit rejeter les en-têtes invalides."
  }

  assert {
    condition     = aws_lb_target_group.app.health_check[0].path == "/up"
    error_message = "Le health check doit viser /up."
  }
}

run "oidc_roles_are_scoped" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role.gha_ecr.description, "example/taskflow@main")
    error_message = "Le rôle ECR doit être lié au dépôt et à la branche main."
  }

  assert {
    condition     = aws_iam_role.gha_ecr.name != aws_iam_role.gha_deploy.name
    error_message = "Deux rôles distincts (push / déploiement)."
  }
}

run "demo_mode_allows_clean_destroy" {
  command = plan

  variables {
    demo_mode = true
  }

  assert {
    condition     = aws_db_instance.main.skip_final_snapshot == true && aws_db_instance.main.deletion_protection == false
    error_message = "En démonstration, la base doit pouvoir être détruite sans snapshot."
  }
}

run "production_mode_protects_data" {
  command = plan

  variables {
    demo_mode = false
  }

  assert {
    condition     = aws_db_instance.main.deletion_protection == true && aws_db_instance.main.skip_final_snapshot == false
    error_message = "En production, la base doit être protégée et avoir un snapshot final."
  }

  assert {
    condition     = aws_lb.main.enable_deletion_protection == true
    error_message = "En production, l'ALB doit être protégé contre la suppression."
  }
}
