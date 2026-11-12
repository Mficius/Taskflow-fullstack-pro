# TaskFlow Pro - Full Stack, DevSecOps & Cloud

Application de gestion de tâches (React 18 + MUI · Laravel 12 + Sanctum · MySQL) livrée avec une
chaîne **DevSecOps structurée** : infrastructure AWS en Terraform, déploiement Kubernetes (Helm),
workflows Terraform authentifiés par **OIDC** (zéro clé AWS longue durée stockée), scans **Gitleaks + Trivy + Semgrep + Checkov + Conftest**,
**Preventive Controls** (OPA, Kyverno, Pod Security) et **DAST** (OWASP ZAP + tests d'autorisation).

```text
TaskFlow/
├── backend/                  Laravel 12 API, Sanctum, tests, Dockerfile production
├── frontend/                 React 18 / MUI / Vite, tests, Nginx non-root
├── infrastructure/terraform/ VPC, EKS, RDS, ALB/WAF, IAM/IRSA, S3/STS endpoints
├── helm/taskflow/             Chart applicatif (API, frontend, worker, migrations)
├── gitops/                    AppProject + Application Argo CD
├── kubernetes/                Namespace et politiques Kyverno/quota; anciens manifests dans legacy/
├── .github/workflows/         CI, Terraform manuel, DAST baseline
├── policy/                    Règles OPA/Conftest et tests
├── security/                  Plans OWASP ZAP et contrôles d'autorisation API
├── scripts/                   Bootstrap EKS, vérification préventive, DAST local
├── monitoring/                Configurations Prometheus / Blackbox
├── docs/                      Architecture, runbooks, sécurité, étude de cas
└── docker-compose*.yml        Développement, DAST local et monitoring
```

## Démarrage rapide

**Développement (Docker)**
```bash
cp .env.example .env && cp backend/.env.example backend/.env   # changer les mots de passe locaux
docker compose up --build            # http://localhost:8080 (APP_KEY générée au démarrage local)
# comptes de démo (non production) : voir backend/database/seeders/DatabaseSeeder.php
```

**Cluster local (kind / minikube)**
```bash
docker build -t taskflow/laravel-api:local ./backend
docker build -t taskflow/react-frontend:local ./frontend
helm install taskflow helm/taskflow -n taskflow --create-namespace -f helm/taskflow/values-local.yaml \
  --set secrets.local.appKey="base64:$(openssl rand -base64 32)" --set secrets.local.dbPassword="$(openssl rand -hex 12)"
```

**AWS (EKS)** - voir [docs/architecture/deployment-runbook.md](docs/architecture/deployment-runbook.md).

**DAST complet en local** : `./scripts/dast-local.sh` (Docker requis).

## Workflows GitHub Actions

| Workflow | Déclenchement | Responsabilité |
|---|---|---|
| `ci.yml` | Pull Request, push sur `main` ou lancement manuel sur `main` | Tests Laravel/React, Gitleaks, Trivy, Semgrep, Checkov, validation Terraform, Helm lint/render et Conftest. Après succès de tous les jobs sur `main`, build des images, scan Trivy, SBOM CycloneDX et PR de mise à jour GitOps. Les images sont publiées sur Docker Hub uniquement après réussite des scans Trivy. |
| `terraform.yml` | Lancement manuel | Plan ou apply Terraform via OIDC; Conftest évalue le plan avant toute application. `terraform-plan` et `production-infra` sont des Environments distincts. |
| `dast.yml` | Hebdomadaire ou manuel | ZAP baseline passif sur `APP_URL`; les tests DAST actifs/authentifiés restent exécutés sur la stack locale éphémère. |

La PR GitOps doit être créée avec le secret `GH_APP_TOKEN` (GitHub App ou PAT limité au dépôt) afin que les checks CI se déclenchent sur cette PR. Ajouter aussi `DOCKER_USERNAME` et `DOCKER_PASSWORD` pour publier sur Docker Hub. Créer les dépôts `laravel-api` et `react-frontend` dans Docker Hub. Attention : un dépôt public expose le contenu des images (dont le code Laravel); si le code doit rester privé, utiliser des dépôts privés et configurer `imagePullSecrets` dans Helm.

## Sécurité : où lire quoi
- [Architecture et flux](docs/architecture/architecture.md)
- [Modèle de sécurité (OIDC, Preventive Controls, matrice de contrôles)](docs/architecture/security.md)
- [DAST (ZAP + tests d'autorisation)](docs/architecture/dast.md)
- [Étude de cas](docs/case-study/case-study.md)

## Ce qui a changé par rapport à la version d'origine
Voir la section « Correctifs et durcissements » de l'[étude de cas](docs/case-study/case-study.md#correctifs-et-durcissements-apportés-au-projet-existant).


## Production GitOps (AWS EKS)

- `infrastructure/terraform/` : VPC, EKS, ALB/WAF, RDS, Secrets Manager, S3 et rôles IAM/IRSA.
- `helm/taskflow/` : source de vérité pour les workloads applicatifs.
- `gitops/applications/` : Application Argo CD et projet dédié.
- `kubernetes/policies/` : politiques de plateforme (Kyverno, quotas, NetworkPolicy si non gérées par Helm).
- `.github/workflows/` : CI + sécurité + build/push Docker Hub + GitOps (après succès des tests) et workflow Terraform séparé.

**Production :** GitHub Actions ne déploie jamais avec `kubectl` ou `helm` dans EKS. Le workflow construit et scanne les images, produit les SBOM, publie les images Docker Hub et enregistre leurs digests puis ouvre une PR qui met à jour les références immuables dans `helm/taskflow/values-eks.yaml`. Argo CD synchronise uniquement après merge.

Avant le premier déploiement, remplacer les valeurs `REPLACE_*` de `values-eks.yaml` par les outputs Terraform, créer les comptes MySQL applicatif/migrator selon `docs/operations/database-user-bootstrap.md`, publier puis merger la PR GitOps des images, et enfin exécuter `scripts/bootstrap-cluster.sh`.
