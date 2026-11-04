# Tests d'INTÉGRATION : apply réel sur LocalStack (provider redirigé par localstack/provider_override.tf),
# puis destroy automatique. Lancer : infrastructure/localstack/run-tests.sh
variables {
  aws_region   = "eu-west-3"
  github_owner = "example"
  github_repo  = "taskflow"
  demo_mode    = true
}

run "apply_full_stack" {
  command = apply

  assert {
    condition     = output.ecs_cluster == "taskflow-prod"
    error_message = "Le cluster ECS doit être créé."
  }

  assert {
    condition     = length(output.ecr_repository_urls) == 3
    error_message = "Trois dépôts ECR doivent exister."
  }

  assert {
    condition     = output.github_actions_variables.ECS_SERVICE == "taskflow-prod-app"
    error_message = "Les variables de la CD doivent être exposées."
  }

  assert {
    condition     = output.rds_endpoint != ""
    error_message = "La base RDS doit avoir un point d'accès."
  }
}
