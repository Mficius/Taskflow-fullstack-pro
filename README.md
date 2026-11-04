# TaskFlow

Application de gestion de tâches (Kanban, projets, notifications, analytics, audit) — **React 18 + MUI**, **Laravel 12 + Sanctum**, **MySQL 8** — livrée avec une chaîne **DevSecOps complète sur AWS ECS Fargate** (Terraform, GitHub Actions + **OIDC**, scans de sécurité, contrôles préventifs, DAST).

```
taskflow/
├── backend/                   API Laravel (Dockerfile prod + dev)
├── frontend/                  SPA React/Vite (Dockerfile prod + dev)
├── nginx/                     passerelle nginx (image prod, template) + conf dev
├── infrastructure/
│   ├── terraform/             VPC · sécurité/IAM/OIDC · ECR · ECS Fargate · RDS · ALB · CloudWatch + tests
│   ├── policy/                contrôles préventifs OPA/Rego + tests
│   └── localstack/            AWS simulé pour tester le Terraform
├── .github/workflows/         ci · cd · infra · infra-test · dast
├── monitoring/                Prometheus/Grafana (local) — prod : CloudWatch via Terraform
├── scripts/                   ecs-deploy.sh · push-images.sh · demo-deploy.sh · policy-check.sh
├── docs/                      architecture · runbook · case-study · screenshots · openapi
├── legacy/ec2/                v1 « instance unique » conservée (base fonctionnelle)
├── docker-compose.yml         développement (+ profil monitoring)
└── docker-compose.ci.yml      pile éphémère pour le DAST
```

## Démarrage local

```bash
make init      # crée .env avec des secrets aléatoires
make up        # http://localhost:8080
```

Comptes de démo (hors production uniquement) : `admin@taskflow.local / admin123`, `manager@taskflow.local / manager123`, `member@taskflow.local / member123`.
Monitoring local : `docker compose --profile monitoring up -d` → Grafana http://localhost:3001. phpMyAdmin : `--profile tools`.
Tests : `make test-backend` · `make test-frontend` · `make test-infra`.

## Déploiement sur AWS

```bash
make demo-up      # démonstration : infra + images + migrations + service (≈ 15 min, ~3 $/jour)
make demo-down    # détruit tout
```

Production : bootstrap de l'état, `terraform apply`, variables GitHub, puis pipelines — voir [`docs/runbook.md`](docs/runbook.md). **Avant de publier le projet : suivre [`docs/deployment-checklist.md`](docs/deployment-checklist.md).**

## Sécurité (résumé)

- **OIDC GitHub → AWS** : aucune clé d'accès stockée ; rôles aux droits minimaux, liés à la branche `main` et aux environnements protégés.
- Gitleaks, SonarQube, CodeQL, Snyk, Trivy (code, IaC, images), Hadolint, `composer audit`, `npm audit`.
- **IaC scannée avant création** (Trivy + Checkov + Snyk IaC), **contrôles préventifs OPA** sur le plan Terraform, `terraform test` et LocalStack.
- **DAST OWASP ZAP** : scan actif authentifié sur une pile éphémère, baseline passif sur la production.
- Conteneurs non-root, tags ECR immuables, base RDS chiffrée en sous-réseaux isolés, secrets dans SSM, pas de SSH.

Chaîne complète : [`docs/architecture/devsecops-pipeline.md`](docs/architecture/devsecops-pipeline.md) · OIDC : [`docs/architecture/security-oidc.md`](docs/architecture/security-oidc.md) · Architecture : [`docs/architecture/architecture.md`](docs/architecture/architecture.md) · Étude de cas : [`docs/case-study/case-study.md`](docs/case-study/case-study.md).

## Fonctionnalités applicatives

Authentification Sanctum · tâches + filtres · projets et membres · dashboard · analytics 7/30/90 jours · recherche globale · notifications persistantes · inbox · vues enregistrées · journal d'activité/audit · commentaires · RBAC côté backend (le frontend n'est pas une frontière de sécurité).

## Prérequis de CI

Variables GitHub : sorties de `terraform output github_actions_variables` (`AWS_REGION`, `AWS_ECR_ROLE_ARN`, `AWS_DEPLOY_ROLE_ARN`, `APP_URL`, `ECS_*`) et, pour le pipeline infra, `terraform output github_infra_pipeline_variables`. Secrets optionnels : `SONAR_TOKEN` (+ variable `SONAR_HOST_URL`), `SNYK_TOKEN`, `LOCALSTACK_AUTH_TOKEN`.
