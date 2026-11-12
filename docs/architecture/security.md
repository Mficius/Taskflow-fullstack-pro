# Modèle de sécurité TaskFlow

## 1. Identités et OIDC

Aucune clé AWS longue durée n'est stockée dans GitHub. Les workflows utilisent GitHub OIDC et des rôles temporaires STS pour Terraform. La publication des images utilise les secrets Docker Hub dédiés et ne nécessite aucun rôle AWS.

| Rôle | Claim `sub` | Droits principaux |
|---|---|---|
| `tf-plan` | `repo:ORG/REPO:environment:terraform-plan` | Lecture du state, verrouillage Terraform, ReadOnlyAccess + lecture des seuls secrets gérés par Terraform; refus du secret maître RDS et des valeurs SSM |
| `tf-apply` | `repo:ORG/REPO:environment:production-infra` | `AdministratorAccess` sous une permissions boundary partielle; approbation humaine obligatoire et audit IAM encore requis |

Les Environments `terraform-plan` et `production-infra` doivent être restreints à `main`; `production-infra` doit imposer des reviewers. Le rôle GitHub de déploiement EKS a été supprimé : Argo CD gère le déploiement.

IRSA est distinct de GitHub OIDC : rôles dédiés à VPC CNI, External Secrets Operator, AWS Load Balancer Controller et au ServiceAccount API TaskFlow. Le rôle TaskFlow ne peut accéder qu'au bucket S3 applicatif. Le rôle External Secrets ne lit que les trois secrets applicatifs nécessaires, pas le secret maître RDS.

**Attention :** `tf-apply` conserve un accès large `AdministratorAccess` encadré par une boundary qui bloque certaines actions sensibles. Ce n'est pas du least privilege complet et la boundary ne neutralise pas tous les scénarios d'escalade via IAM roles/trust policies. Ne pas autoriser l'apply automatique; remplacer ce rôle par une policy dédiée après audit avant une mise en production réelle.

## 2. Contrôles préventifs et détectifs

| Couche | Contrôle | Automatisation |
|---|---|---|
| Code | Gitleaks, Trivy filesystem (vulnérabilités, misconfiguration, secrets), Semgrep, Checkov | Job `Quality & Security analysis` de `ci.yml` |
| IaC | `terraform fmt`, `terraform validate`, tests OPA/Conftest; plan évalué par Conftest avant apply | CI + workflow manuel `terraform.yml` |
| Kubernetes | `helm lint`, `helm template`, Conftest sur les manifests rendus | Job `Helm - Lint, render & policy checks` |
| Admission | Pod Security Admission `restricted` + Kyverno `Enforce` | À la création des workloads |
| Réseau | NetworkPolicy default-deny, autorisations DNS, ALB, RDS et endpoints AWS nécessaires | Chart Helm |
| Runtime | `readOnlyRootFilesystem`, non-root, seccomp, capabilities `drop: ALL`, probes, HPA/PDB | Chart Helm |
| Vérification réelle | `verify-preventive-controls.sh` vérifie AWS et Kubernetes et tente des pods interdits en dry-run serveur | Après bootstrap/synchronisation |

Les politiques Rego sont dans `policy/terraform/` et `policy/kubernetes/`; leurs tests sont exécutés par Conftest. Le plan Terraform est évalué avant `terraform apply`.

## 3. Chaîne d'approvisionnement

- Docker Hub : dépôts `laravel-api` et `react-frontend`, tags SHA et références par digest; scans Trivy exécutés avant le push.
- CI : Trivy bloque les images locales avant publication sur Docker Hub.
- SBOM : génération CycloneDX pour API et frontend.
- GitOps : Helm référence les digests, pas seulement des tags mutables.

La signature Cosign et la vérification obligatoire à l'admission (Kyverno `verifyImages`) ne sont pas encore activées.

## 4. Secrets et données

- Secrets Manager contient l'APP_KEY, le compte SQL runtime et le compte SQL de migration.
- Le compte runtime a des droits CRUD; le compte migrator est réservé au Job de migration et détient les droits DDL nécessaires.
- Le compte maître RDS n'est jamais injecté dans les pods.
- RDS est privé, chiffré, TLS forcé, sauvegardé et Multi-AZ par défaut.
- Les fichiers applicatifs ne sont pas encore téléversés dans S3 par le code courant; le bucket et IRSA sont prêts, mais l'adaptateur Flysystem doit être ajouté et testé avant activation.

## 5. Authentification de l'application

L'OIDC GitHub→AWS n'est pas un système de connexion pour les utilisateurs TaskFlow. L'application utilise actuellement Laravel Sanctum avec des tokens bearer expirants et un contrôle RBAC côté serveur. Aucun fournisseur OIDC utilisateur (Keycloak, Entra ID, Auth0, etc.) n'est configuré par cette infrastructure.
