# Rapport de corrections — TaskFlow DevSecOps

## Architecture retenue

La cible est **AWS EKS + Kubernetes + Helm + Argo CD + GitHub Actions + Terraform**. ECS n'est pas utilisé.

## Changements réalisés

- Passage du cluster EKS par défaut à Kubernetes 1.36.
- Suppression du rôle GitHub `deploy` et de l'Access Entry de déploiement direct dans EKS. GitHub Actions ne fait pas de `kubectl apply` ni de `helm upgrade` en production.
- Les rôles GitHub sont limités au plan et à l’apply Terraform; la publication applicative utilise Docker Hub et ne nécessite aucun rôle AWS. Le plan Terraform est lié à l'Environment `terraform-plan`, pas aux pull requests non fiables.
- Retrait des dépôts ECR et de leur rôle IAM de publication Terraform; Docker Hub est le registre applicatif temporaire pour maîtriser les coûts.
- Ajout d'un refus de lecture des secrets non gérés par Terraform pour le rôle plan; seuls les trois secrets applicatifs gérés par Terraform peuvent être rafraîchis, et le secret maître RDS est exclu.
- Ajout d'un compte SQL runtime (CRUD) et d'un compte migrator (DDL) séparés. Le compte maître RDS ne va pas dans les pods. Le Job de migration utilise son propre Secret et son propre ServiceAccount sans IRSA.
- Ajout de l'endpoint VPC STS pour l'échange des tokens IRSA et conservation de l'endpoint S3 privé; permissions KMS explicites du rôle de contrôle EKS pour le chiffrement des Secrets Kubernetes. Les volumes EBS des nœuds restent chiffrés avec la clé AWS gérée `aws/ebs`.
- Ajout du flux Ops host → endpoint privé EKS sur TCP/443 lorsque l'hôte Ops est activé.
- Correction du chart Helm : valeurs et ServiceAccounts harmonisés, digest d'image supporté, secrets externes séparés, bootstrap administrateur optionnel, migrations isolées, frontend rootless avec `fsGroup`, worker à deux réplicas et PDB/topology spread.
- Alignement Argo CD/Helm : le nom de release par défaut correspond au nom de l'Application Argo CD, afin d'éviter le conflit de tracking label `app.kubernetes.io/instance`.
- Déplacement des anciens manifests de workloads Kubernetes dans `kubernetes/legacy/`; Helm est la source de vérité des workloads.
- Bootstrap de plateforme : External Secrets, AWS Load Balancer Controller (region/VPC explicités car IMDS hop limit 1), Kyverno, Reloader, metrics-server et Argo CD.
- Fusion de CI, scans de sécurité et publication d'images dans `ci.yml`. La publication ne s'exécute qu'après réussite des jobs de tests, sécurité, Terraform statique et Helm.
- Build et push Docker Hub intégrés à la CI : build local, scan Trivy CRITICAL/HIGH, génération SBOM CycloneDX, push sur `main`, résolution des digests et PR GitOps dans un job séparé à permissions d'écriture limitées.
- Images Docker Hub construites dans la CI, scannées avec Trivy, SBOM CycloneDX publié en artefact et digests immuables mis à jour par PR GitOps avec `GH_APP_TOKEN`.
- Ajout de Conftest pour tester les politiques OPA et contrôler les manifests Helm rendus, ainsi que l'évaluation du plan Terraform avant apply.
- Ajout d'un workflow DAST ZAP baseline passif hebdomadaire/manuellement déclenché.
- Ajout d'un `.gitignore` racine et d'un `.env.example` racine pour le développement Docker Compose.
- Mise à jour des runbooks, de la documentation architecture/sécurité et du case study pour refléter ce qui est réellement configuré.

## Contrôles exécutés dans l'environnement de correction

- Fichiers YAML statiques : analyse syntaxique avec détection de clés dupliquées.
- PHP : `php -l` sur les fichiers PHP du backend.
- Shell : `bash -n` sur les scripts shell; `sh -n` sur l'entrypoint local.
- JSON : `composer.lock` et `package-lock.json` vérifiés comme JSON.
- Contrôle statique des déclarations Terraform dupliquées et de références de l'ancien modèle ECS/déploiement direct.

## Ce qui reste à faire avant production

1. Exécuter les workflows GitHub et obtenir des checks verts. Les commandes `terraform validate/plan`, `helm lint/template`, Conftest, PHPUnit, Vitest, builds Docker, Trivy, Checkov, Semgrep et ZAP n'ont pas été exécutées dans cet environnement de correction.
2. Générer et committer `infrastructure/terraform/.terraform.lock.hcl` après `terraform init`.
3. Précréer le bucket et la table DynamoDB du backend Terraform; fournir la clé KMS du state.
4. Remplacer les placeholders `REPLACE_*`, le domaine, le certificat ACM et les CIDR d'accès EKS. L'adresse `203.0.113.10/32` de l'exemple est réservée à la documentation et ne doit pas être utilisée.
5. Créer les comptes SQL `taskflow_app` et `taskflow_migrator` selon le runbook après le premier apply.
6. Configurer les Environments GitHub `terraform-plan` et `production-infra`, leurs restrictions de branche et l'approbation obligatoire pour l'apply.
7. Faire remplacer le rôle `tf-apply` basé sur `AdministratorAccess` + permissions boundary partielle par une policy réellement least-privilege. Ne pas activer l'apply automatique.
8. Choisir un fournisseur OIDC utilisateur si un SSO est attendu. L'OIDC AWS pour GitHub/IRSA est configuré; l'application utilise actuellement Sanctum.
9. Ajouter `league/flysystem-aws-s3-v3` et tester les téléversements avant d'activer `FILESYSTEM_DISK=s3`. Le code actuel ne gère pas encore de pièces jointes.
10. Ajouter la signature Cosign et Kyverno `verifyImages` si l’on souhaite imposer une vérification de provenance à l’admission. La livraison Docker Hub actuelle publie les digests et SBOM mais ne signe pas encore les images.
11. Ajouter Cluster Autoscaler ou Karpenter si le scaling des nœuds devient nécessaire. Les HPA scalent uniquement les pods.
