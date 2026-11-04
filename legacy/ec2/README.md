# TaskFlow — version v1 « instance unique » (base fonctionnelle, conservée)

Snapshot de la première architecture : **1 EC2 + Docker Compose + MySQL sur EBS**, déploiement par SSM + `deploy.sh`, monitoring Prometheus/Grafana embarqué.
Elle est conservée parce qu'elle est **simple, peu chère (≈ 75 $/mois) et rapide à valider**. La version principale du dépôt (`infrastructure/terraform`) est la migration vers **ECS Fargate + RDS** — voir `docs/case-study/case-study.md`.

| Fichier | Rôle |
|---|---|
| `terraform/` | VPC, ALB, EC2, EBS, ECR, OIDC (mêmes fichiers que la v1) |
| `docker-compose.prod.yml` | Pile de production (nginx, backend, frontend, MySQL, monitoring) |
| `scripts/deploy.sh` | Déploiement + rollback automatique, exécuté sur l'instance via SSM |
| `nginx/prod.conf` | Reverse-proxy de production v1 |
| `workflows/cd.yml`, `workflows/infra.yml` | Pipelines v1 (volontairement **inactifs** ici) |

## Réactiver la v1

1. Étiquetez d'abord l'état actuel : `git tag v1-ec2` (sur le commit qui contient cette version).
2. Pour la réutiliser : copiez `terraform/` vers `infrastructure/terraform/`, `docker-compose.prod.yml` à la racine, `scripts/deploy.sh` dans `scripts/`, `nginx/prod.conf` dans `nginx/`, et les deux workflows dans `.github/workflows/`.
3. Les variables GitHub et le runbook de la v1 sont décrits dans l'historique git (`git show v1-ec2:docs/runbook.md`).

> Recommandation : faire vivre la v1 sur une branche `v1-ec2` plutôt que dans ce dossier, et supprimer `legacy/` quand la branche existe.
