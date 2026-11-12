# Pré-requis avant une mise en production réelle

- Remplacer toutes les valeurs `REPLACE_*`, l'URL de domaine et le certificat ACM.
- Le CIDR `203.0.113.10/32` de l'exemple est une plage réservée à la documentation : il ne fonctionne pas sur Internet.
- Créer le bucket S3 et la table DynamoDB du backend Terraform avant le premier `terraform init`.
- Vérifier les limites de permissions du rôle `tf-apply`. Le rôle est encore basé sur `AdministratorAccess` avec une permissions boundary partielle. Elle bloque plusieurs actions de persistance d'identités, mais ne constitue pas une vraie policy least-privilege et ne neutralise pas tous les scénarios d'escalade via IAM roles/trust policies. Ne pas autoriser l'apply automatique; garder l'Environment GitHub avec approbation et remplacer ce rôle par une policy dédiée avant production réelle.
- Le node group reste à capacité fixe (min/desired/max configurés par Terraform). Les HPA scalent les pods, pas les nœuds; ajouter Cluster Autoscaler ou Karpenter seulement si le besoin de scaling des nœuds est établi.
- Le chart n'a pas été rendu avec Helm dans cet environnement. Exécuter `helm lint helm/taskflow` et `helm template taskflow helm/taskflow -n taskflow -f helm/taskflow/values-eks.yaml` après remplacement des placeholders.
- Le code actuel ne téléverse pas de fichiers. Le bucket S3 et IRSA sont prêts pour une évolution, mais l'activation du disque S3 Laravel nécessite `league/flysystem-aws-s3-v3`, la mise à jour de `composer.lock`, `AWS_BUCKET`, puis des tests d'intégration.
- L'OIDC GitHub→AWS est distinct de l'authentification OIDC des utilisateurs TaskFlow. L'application actuelle utilise Laravel Sanctum; aucun fournisseur OIDC utilisateur (Keycloak, Entra ID, Auth0, etc.) n'est configuré par ces fichiers.
- Le workflow Terraform de plan nécessite `AWS_ROLE_TF_PLAN` et les variables de backend. Le rôle plan doit avoir lecture du state et droits de verrouillage DynamoDB.

- Le secret GitHub `GH_APP_TOKEN` doit permettre à l'action de créer la PR GitOps et de déclencher les checks CI sur cette PR. Limiter ses permissions au dépôt TaskFlow.
- Les images Docker Hub sont référencées par digest dans Helm. Trivy bloque les vulnérabilités CRITICAL/HIGH avant le push et les SBOM CycloneDX sont archivés comme artefacts CI. La signature Cosign et sa vérification à l’admission ne sont pas activées.

- Le rôle `tf-plan` est lié à l'Environment GitHub `terraform-plan` (pas au contexte `pull_request`) et refuse les valeurs de tous les secrets non gérés par Terraform (dont le secret maître RDS) et les valeurs SSM; il lit uniquement les trois secrets applicatifs gérés par Terraform pour le refresh de leurs versions. Restreindre cet Environment à `main`. Le state Terraform contient des valeurs sensibles (notamment les mots de passe générés) : conserver un accès S3/KMS très limité.

- Épingler les versions Helm des opérateurs de plateforme (External Secrets, AWS Load Balancer Controller, Kyverno, Reloader, metrics-server et Argo CD) après validation; le script bootstrap utilise actuellement les dernières versions des dépôts Helm.
