# Runbook de déploiement AWS

## 0. Prérequis (une fois)
1. Bucket S3 + table DynamoDB pour le state Terraform (chiffrés, versionnés).
2. Certificat ACM validé dans la région de l'ALB.
3. Installer les outils `terraform`, AWS CLI, `kubectl`, Helm, `jq` et Conftest. Premier `terraform apply` **depuis un poste admin** : il crée le fournisseur OIDC et les rôles GitHub (problème de l'œuf et de la poule). Ensuite, tout passe par GitHub Actions.
   ```bash
   cd infrastructure/terraform
   cp terraform.tfvars.example terraform.tfvars   # éditer
   cp backend.hcl.example backend.hcl             # éditer
   terraform init -backend-config=backend.hcl && terraform plan -out tfplan
   terraform show -json tfplan > tfplan.json && conftest test --policy ../../policy/terraform tfplan.json
   terraform apply tfplan
   ```
4. Après le premier apply, reporter les outputs Terraform dans `helm/taskflow/values-eks.yaml` : `rds_endpoint` → `api.config.DB_HOST`; `app_secret_name` → `secrets.external.appSecretName`; `rds_app_secret_arn` et `rds_migrator_secret_arn` → les deux ARN de secrets; `app_files_bucket` → `api.config.AWS_BUCKET`; `irsa_role_arns["taskflow-app"]` → `serviceAccount.apiRoleArn`; `alb_target_group_arns["frontend"]` et `["api"]` → les TargetGroupBindings. Définir manuellement `APP_URL`, `CORS_ALLOWED_ORIGINS` et le certificat ACM. Si le VPC CIDR change, adapter les trois CIDR de `networkPolicy`.
5. Configurer les variables GitHub. Configurer les secrets Docker Hub et `GH_APP_TOKEN`, puis merger le code sur `main`. La CI construit, scanne et publie les deux images Docker Hub, puis ouvre une PR GitOps qui met à jour les digests.
6. Exécuter ensuite `scripts/bootstrap-cluster.sh` (admin) : namespace PSA, External Secrets, AWS Load Balancer Controller, Kyverno, Reloader, metrics-server et Argo CD.

> **Migration depuis ECR :** le fichier Terraform `ecr.tf` a été retiré car les images sont désormais publiées sur Docker Hub. Si ECR a déjà été créé avec cette configuration, examine le `terraform plan` avant tout `apply` : Terraform proposera de supprimer les dépôts ECR. Sauvegarde les images utiles et vérifie leur contenu avant d'accepter cette suppression. Si l'infrastructure n'a jamais été appliquée, aucune action de migration n'est nécessaire.

## 1. Configuration GitHub
**Environments** : `terraform-plan` (branche `main` uniquement) et `production-infra` (reviewers obligatoires, branche `main` uniquement).

**Variables** (Settings → Variables) : `AWS_REGION`, `AWS_ROLE_TF_PLAN`,
`AWS_ROLE_TF_APPLY`, `TF_STATE_BUCKET`, `TF_STATE_LOCK_TABLE`, `TF_STATE_KMS_KEY_ID`, `TF_STATE_BUCKET_ARN`,
`TF_STATE_LOCK_TABLE_ARN`, `TF_STATE_KMS_KEY_ARN`, `ACM_CERTIFICATE_ARN`, `EKS_PUBLIC_ACCESS_CIDRS` (JSON),
`APP_URL`, `SINGLE_NAT_GATEWAY` (`false` pour le profil HA de l'exemple) et `DB_MULTI_AZ` (`true`). Les ARN des rôles sont dans `terraform output -json github_role_arns` (clés `tf-plan`, `tf-apply`). La publication Docker Hub ne nécessite aucun rôle AWS. Le job CI n'obtient aucun accès Kubernetes : il ouvre une PR modifiant `values-eks.yaml`; Argo CD applique ensuite le changement après merge.

**Secrets** : `DOCKER_USERNAME`, `DOCKER_PASSWORD` (token d’accès Docker Hub, de préférence plutôt que le mot de passe du compte), `GH_APP_TOKEN` (GitHub App/PAT limité à Contents + Pull requests, nécessaire pour que la PR GitOps déclenche les checks), `SONAR_TOKEN`, `SONAR_HOST_URL`, `SNYK_TOKEN` (les trois derniers sont optionnels), et `GITLEAKS_LICENSE` seulement si le dépôt privé requiert une licence Gitleaks. 

**Docker Hub** : créer au préalable deux dépôts nommés exactement `laravel-api` et `react-frontend` dans le namespace du compte `DOCKER_USERNAME`. La CI publie uniquement sur `main`, après tests et scans, avec le SHA Git comme tag. Les images sont ensuite référencées par digest dans Helm. Attention : un dépôt public rend le contenu des images téléchargeable par tous; le code Laravel présent dans l'image API sera donc inspectable. Si le code doit rester privé, utiliser des dépôts privés et vérifier que le plan Docker Hub permet les deux dépôts. Dans ce cas, créer le Secret Kubernetes `dockerhub-registry` dans le namespace `taskflow`, puis renseigner `imagePullSecrets: [{name: dockerhub-registry}]` dans `values-eks.yaml`. Même pour des dépôts publics, un pull secret peut aider à éviter les limites de téléchargement anonymes de Docker Hub.

**Branch protection sur `main`** : exiger les checks des jobs `CI / Backend - Laravel tests`, `CI / Frontend - Tests & production build`, `CI / Quality & Security analysis`, `CI / Terraform - Format & validate` et `CI / Helm - Lint, render & policy checks`.

> Les runners GitHub ont des IP changeantes : si vous voulez une API EKS 100 % privée
> (`eks_endpoint_public_access=false`), déployez depuis un runner auto-hébergé dans le VPC (ex. l'hôte EC2 `enable_ops_host`).

## 2. Déployer
Merge sur `main` → tests/scans, build des images, scan Trivy, push Docker Hub, PR de mise à jour GitOps; après merge de cette PR, Argo CD synchronise EKS. Le plan Terraform se lance manuellement dans l'environment `terraform-plan`; l'apply se lance manuellement dans `production-infra` avec approbation.

## 3. Premier administrateur
1. Ajouter temporairement `ADMIN_EMAIL` et `ADMIN_PASSWORD` au JSON du secret dont le nom est donné par `terraform output -raw app_secret_name` (par défaut `taskflow/prod/laravel`) dans Secrets Manager.
2. Passer `adminBootstrap.enabled: true` dans `helm/taskflow/values-eks.yaml`, puis merger la PR GitOps pour synchroniser le Secret Kubernetes.
3. Attendre `ExternalSecret/taskflow-api-secrets` en état `Ready=True`, puis exécuter une seule fois :
   `kubectl -n taskflow exec deploy/taskflow-production-api -c php-fpm -- php artisan db:seed --force`.
4. Retirer les deux clés temporaires de Secrets Manager, remettre `adminBootstrap.enabled: false`, merger la PR et vérifier que les clés ont disparu du Secret Kubernetes. Changer ensuite le mot de passe depuis l'application.

Avant le premier push, générer et committer `.terraform.lock.hcl` avec `terraform init` depuis `infrastructure/terraform` (le fichier lock n'est pas un secret).

## 4. Retour arrière
Pour une révision applicative, **revert** le commit ou la PR GitOps qui a modifié `helm/taskflow/values-eks.yaml`, puis merger le revert. Argo CD resynchronise automatiquement l'ancien digest. Les migrations SQL doivent rester rétro-compatibles; une migration destructive nécessite une procédure de restauration dédiée.
