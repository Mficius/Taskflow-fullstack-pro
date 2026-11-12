# Étude de cas — Industrialiser et sécuriser TaskFlow

## Contexte

TaskFlow est une application de gestion de tâches construite avec React, Laravel 12, Sanctum et MySQL. L'objectif de cette évolution est de disposer d'une architecture AWS EKS reproductible, d'une chaîne CI sécurisée et d'un déploiement GitOps où GitHub Actions ne possède aucun accès de déploiement Kubernetes.

## Évolutions apportées

| Domaine | Correction |
|---|---|
| Infrastructure | Harmonisation Terraform autour d'EKS, ALB/WAF, RDS privé, KMS, Secrets Manager, S3 et endpoints privés S3/STS |
| IAM | Suppression du rôle GitHub de déploiement direct et des Access Entries correspondantes; séparation OIDC GitHub→AWS et IRSA des pods |
| Base de données | Séparation des comptes runtime CRUD et migrator DDL; le compte maître RDS n'est plus synchronisé dans les pods |
| Helm | Sécurisation des workloads, probes, ressources, HPA/PDB, ExternalSecrets, NetworkPolicies et TargetGroupBindings |
| GitOps | AppProject et Application Argo CD; Helm devient la source de vérité des workloads |
| CI | Tests Laravel/React, Gitleaks, Trivy, Semgrep, Checkov, Terraform validate, Helm lint/render et tests Conftest |
| Supply chain | Scan Trivy avant publication, SBOM CycloneDX en artefact CI, références Docker Hub par digest |
| Déploiement | PR GitOps après build; Argo CD synchronise après merge; aucun `kubectl apply`/`helm upgrade` de production depuis GitHub Actions |
| Plateforme | Bootstrap External Secrets, AWS Load Balancer Controller, Kyverno, Reloader, metrics-server et Argo CD |

## Décisions importantes

1. **GitOps réel** : le pipeline CI publie les images et modifie les valeurs Helm par PR. Argo CD est le seul acteur qui synchronise l'application vers EKS.
2. **Identités séparées** : OIDC GitHub→AWS pour les workflows, IRSA pour les pods; aucun rôle GitHub n'est autorisé à modifier directement les ressources Kubernetes.
3. **Secrets minimisés** : APP_KEY, compte runtime et compte migrator sont stockés dans Secrets Manager. Le secret maître RDS reste réservé à l'administration.
4. **Contrôles avant déploiement** : tests, scanners, validation Terraform, rendu Helm et Conftest; le plan Terraform est évalué avant apply.
5. **Images immuables** : tags SHA et digests Docker Hub, scans Trivy et SBOM CycloneDX.

## État de validation de cette livraison

Les vérifications exécutées pendant la correction de l'archive :

- 43 fichiers YAML statiques analysés avec détection des clés dupliquées;
- 65 fichiers PHP passés avec `php -l`;
- scripts shell passés avec `bash -n`;
- `composer.lock` vérifié comme JSON valide;
- contrôle statique des déclarations Terraform dupliquées et des références retirées des anciens mécanismes de déploiement direct et de l’ancienne cible ECS.

**Les validations suivantes n'ont pas pu être exécutées dans l'environnement de correction** : `terraform validate/plan`, `helm lint/template`, `conftest verify/test`, tests PHPUnit, tests Vitest, builds Docker, scans Trivy/Checkov/Semgrep et déploiement AWS. Les workflows CI sont configurés pour les exécuter dans GitHub Actions. Ne pas considérer le projet comme prêt pour la production avant que ces jobs soient verts et que les placeholders aient été remplacés.

## Limites et points à traiter avant production

- Le rôle `tf-apply` conserve `AdministratorAccess` sous une permissions boundary partielle. Cette boundary n'est pas du least privilege complet; garder l'approbation humaine et faire auditer/réduire ce rôle.
- Le node group EKS reste à capacité fixe; HPA scale les pods, pas les nœuds. Cluster Autoscaler/Karpenter n'est pas encore installé.
- Le bucket S3 et IRSA sont prêts pour les futures pièces jointes, mais le code actuel n'a pas de fonctionnalité de téléversement. Ajouter `league/flysystem-aws-s3-v3`, mettre à jour `composer.lock` et tester avant de passer `FILESYSTEM_DISK` à `s3`.
- Les images ne sont pas encore signées par Cosign; la vérification de signature à l'admission n'est donc pas activée.
- L'OIDC utilisateur (SSO) n'est pas configuré : l'application utilise actuellement Sanctum.
- Remplacer les valeurs `REPLACE_*`, l'URL, le certificat ACM, les CIDR d'accès EKS et les paramètres du backend Terraform.

## Suites possibles

Least privilege complet pour `tf-apply`, Kyverno `verifyImages`, scaling de nœuds, stockage S3 effectif des pièces jointes, authentification utilisateur OIDC/SSO, CSP avec nonce et stratégie de sauvegarde/restauration testée.
