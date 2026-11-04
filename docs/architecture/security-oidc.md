# Sécurité — OIDC GitHub → AWS et défense en profondeur

## Pourquoi OIDC ?

Sans OIDC, il faudrait stocker `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` dans GitHub : clés longue durée, à renouveler, qui fuient (logs, forks, compromission d'un compte).
Avec OIDC, GitHub émet à chaque job un **jeton signé de courte durée** ; AWS le vérifie et délivre des **credentials temporaires (1 h max)**. Rien à stocker, rien à renouveler.

## Rôles et niveaux de confiance

| Rôle IAM | Qui peut l'assumer (claim `sub`) | Droits |
|---|---|---|
| `taskflow-prod-gha-ecr-push` | `repo:<owner>/<repo>:ref:refs/heads/main` | Push/pull sur **les 3 dépôts ECR** uniquement |
| `taskflow-prod-gha-deploy` | `repo:<owner>/<repo>:environment:production` | Enregistrer des définitions de tâche, `UpdateService` **sur notre seul service**, `RunTask` **sur la seule tâche de migration**, `PassRole` **limité aux 2 rôles ECS** |
| `taskflow-prod-gha-tf-plan` | `…:pull_request` et `…:ref:refs/heads/main` | `ReadOnlyAccess` + état S3 |
| `taskflow-prod-gha-tf-apply` | `…:environment:infra-production` | `AdministratorAccess` (approbation humaine obligatoire, politiques OPA avant apply) |

Rôles **ECS** (identités des conteneurs, distinctes de GitHub) :

| Rôle | Utilisé par | Droits |
|---|---|---|
| `…-task-execution` | ECS (pas le code) | Tirer les images, écrire les logs, **lire uniquement** `/taskflow/prod/*` dans SSM |
| `…-task` | Le code applicatif | **Aucun** accès AWS (seulement le canal ECS Exec pour le débogage) |

Conséquences : une PR ne peut rien faire sur AWS ; seul l'environnement `production` déploie ; une tâche compromise ne peut ni lire d'autres secrets ni toucher à l'infra ; `id-token: write` n'est accordé qu'aux jobs qui en ont besoin.

## Mise en place

1. `terraform apply` (ou `make demo-up`).
2. `terraform output github_actions_variables` → créer ces **variables** (pas des secrets) dans *Settings → Secrets and variables → Actions → Variables*.
3. *Settings → Environments* : `production` et `infra-production` (+ relecteurs).
4. Optionnel : secrets `SONAR_TOKEN`, `SNYK_TOKEN`, `LOCALSTACK_AUTH_TOKEN`.

> Si le provider OIDC GitHub existe déjà dans votre compte AWS (un seul par URL) : `create_github_oidc_provider = false`.

## Contrôles de sécurité du projet

| Domaine | Contrôle |
|---|---|
| Secrets | Gitleaks en CI · aucun `.env` dans le dépôt/les images · secrets générés par Terraform → SSM SecureString → injectés par ECS |
| Code | SonarQube/SonarCloud · CodeQL · Snyk · `composer audit` · `npm audit` |
| Conteneurs | Hadolint · Trivy sur les 3 images (bloque CRITICAL/HIGH corrigeables) · utilisateur non-root · tags ECR immuables + scan on push |
| Infra | Trivy config · Checkov · Snyk IaC · politiques OPA sur le plan · tests `terraform test` · SG `ALB → app → RDS` · RDS en sous-réseaux isolés et chiffrée · pas de SSH · Flow Logs (REJECT) |
| Application | Sanctum · RBAC · rate-limit login (nginx + Laravel) · en-têtes de sécurité (CSP, X-Frame-Options, nosniff…) · `APP_DEBUG=false` · seeder sans mot de passe en dur en production |
| Chaîne CD | OIDC, rôles séparés, environnement protégé, migrations avant déploiement, circuit breaker, rollback en une étape |

## Pour aller plus loin

- Épingler les actions GitHub par **SHA de commit** (Dependabot les maintient).
- AWS WAF devant l'ALB, HTTPS obligatoire (`certificate_arn`).
- Sous-réseaux privés + VPC endpoints (ECR, S3, SSM, Logs) pour supprimer l'IP publique des tâches.
- Utilisateur MySQL applicatif à droits réduits ; TLS vers RDS.
- Signature des images (cosign) et SBOM.
