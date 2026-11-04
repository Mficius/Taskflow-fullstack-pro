# Runbook d'exploitation (ECS Fargate)

## Deux modes d'usage

| | Démonstration (portfolio) | Production |
|---|---|---|
| `demo_mode` | `true` (défaut) | `false` |
| Création | `make demo-up` | `terraform apply` + pipelines |
| Destruction | `make demo-down` (coût → 0) | Protégée (RDS, ALB), snapshot final |
| Coût | ≈ 3 $/jour **pendant** la démo | ≈ 75–95 $/mois |

Checklist complète du premier déploiement réel et des captures : [`deployment-checklist.md`](deployment-checklist.md).

## Démonstration en une commande

```bash
aws sso login            # ou variables AWS_* d'un utilisateur dédié
make demo-up             # terraform apply → build/push des 3 images → migrations → service ECS (≈ 15 min)
make demo-down           # détruit TOUT (ECS, RDS, ALB, ECR…)
```

Prérequis : AWS CLI, Terraform ≥ 1.10, Docker, `jq`. Copier `infrastructure/terraform/terraform.tfvars.example` en `terraform.tfvars`.
L'état de la démonstration est local (`backend_override.tf`, ignoré par git).

## Production : pipelines

```bash
scripts/bootstrap-tfstate.sh eu-west-3                 # bucket d'état S3 (une fois)
cd infrastructure/terraform
terraform init -backend-config=bucket=<bucket> -backend-config=key=prod/terraform.tfstate \
               -backend-config=region=eu-west-3 -backend-config=use_lockfile=true -backend-config=encrypt=true
terraform apply -var demo_mode=false -var tf_state_bucket=<bucket>   # premier apply manuel (crée aussi les rôles OIDC)
terraform output github_actions_variables              # → variables GitHub (voir security-oidc.md)
terraform output github_infra_pipeline_variables
```

Ensuite : l'infra évolue via `infra.yml` (plan sur PR, apply approuvé sur `main`) et l'application via `cd.yml`.

## Premier démarrage du service

`terraform apply` crée le service ECS à **0 tâche** (les images n'existent pas encore). Le premier passage de la CD (ou `make demo-deploy`) pousse les images, joue les migrations, crée le compte admin et passe le service à `DESIRED_COUNT` (1 par défaut ; variable GitHub `DESIRED_COUNT`).

Identifiants administrateur :

```bash
aws ssm get-parameter --name /taskflow/prod/seed_admin_email    --with-decryption --query Parameter.Value --output text
aws ssm get-parameter --name /taskflow/prod/seed_admin_password --with-decryption --query Parameter.Value --output text
```

Changez ce mot de passe à la première connexion (un redéploiement ne le réinitialise jamais).

## Rollback

- **Automatique** : si une nouvelle révision ne devient pas saine, le circuit breaker ECS revient à la précédente et la CD échoue.
- **Manuel (une étape)** : *Actions → CD → Run workflow* → `image_tag` = tag précédent (12 caractères, visible dans le résumé du déploiement ou dans ECR).
- Si une **migration** échoue : rien n'est déployé, le service continue sur l'ancienne version.

> Les migrations ne sont pas annulées par un rollback : les écrire de façon rétro-compatible (*expand / contract*).

## Observer et diagnostiquer

```bash
terraform output dashboard_url                          # dashboard CloudWatch
aws logs tail /taskflow/prod/ecs --follow               # logs de tous les conteneurs
aws ecs describe-services --cluster taskflow-prod --services taskflow-prod-app \
  --query 'services[0].events[:10].message' --output text   # pourquoi un déploiement échoue
# Shell dans le conteneur backend (sans SSH) :
aws ecs execute-command --cluster taskflow-prod --task <task-id> --container backend --interactive --command "sh"
```

## Incidents courants

| Symptôme | Vérifier | Action |
|---|---|---|
| Cible *unhealthy*, 502/503 | Événements du service ; logs `nginx` et `backend` | Rollback ; vérifier secrets SSM et connexion RDS |
| Tâche qui redémarre en boucle | `stoppedReason` de la tâche ; `CannotPullContainerError` ? | Image/tag absent d'ECR, ou pas de sortie vers ECR (SG/IP publique) |
| `ResourceInitializationError` (secrets) | Rôle d'exécution, chemin SSM | Vérifier `/taskflow/prod/*` et la politique du rôle d'exécution |
| Migration en échec | Journal affiché par `ecs-deploy.sh` | Corriger la migration ; le service n'a pas été touché |
| RDS : connexions refusées | Security group `db` | Seul le SG `app` doit être autorisé sur 3306 |

## Sauvegardes et restauration

- RDS : sauvegardes automatiques 7 jours (restauration à un instant précis) ; snapshot final en mode production.
- Restauration : RDS → *Restore to point in time* → nouvelle instance, puis mettre à jour `DB_HOST` (Terraform).
- **Testez la restauration** au moins une fois par trimestre.

## Rotation des secrets

`terraform apply -replace=random_password.db_app` puis relancer la CD (nouvelle révision de tâche). Pour `APP_KEY` : régénérer invalide les sessions/tokens chiffrés.

## Coûts (ordre de grandeur, région Paris ; à vérifier avec le AWS Pricing Calculator)

| Poste | ≈ USD / mois |
|---|---|
| Fargate 0,5 vCPU / 1 Go, 1 tâche 24/7 | 20 |
| RDS `db.t4g.micro` + 20 Go | 18 |
| ALB | 20 |
| IPv4 publiques (tâche + ALB ×2) | 11 |
| CloudWatch (Container Insights, logs, alarmes), ECR, SSM | 6 |
| **Total (1 tâche, sans NAT)** | **≈ 75** |

Variantes : +35 $ avec une NAT Gateway ; +20 $ par tâche supplémentaire ; ×2 la part RDS en Multi-AZ. En démonstration, détruire après usage ramène le coût à quelques dollars par session.
