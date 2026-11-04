# Checklist — premier déploiement RÉEL et captures pour le portfolio

Aucun des fichiers Terraform/workflows n'a été exécuté contre un vrai compte AWS au moment de leur rédaction. Cette checklist sert à **le prouver** avant de publier sur Upwork.

## 0. Avant de commencer

- [ ] Compte AWS dédié (ou sandbox) ; **budget alerte à 10 $** (AWS Budgets) ; MFA sur le compte racine.
- [ ] Utilisateur/rôle d'administration pour le premier `apply` (pas le compte racine).
- [ ] Outils : AWS CLI, Terraform ≥ 1.10, Docker, `jq`, `make`.
- [ ] Dépôt GitHub créé (`github_owner`/`github_repo` dans `terraform.tfvars`), code poussé sur `main`.

## 1. Tests sans AWS (≈ 10 min)

- [ ] `make test-infra` → `terraform fmt/validate/test` + politiques OPA. **Corriger tout échec.**
- [ ] (optionnel) `LOCALSTACK_AUTH_TOKEN=… make localstack-test`.
- [ ] `make test-backend test-frontend`.

## 2. Déploiement de démonstration (≈ 15 min)

- [ ] `make demo-up` ; en cas d'erreur Terraform : la corriger, puis relancer (idempotent).
- [ ] L'URL affichée répond ; connexion avec l'admin (identifiants SSM, voir runbook).
- [ ] Créer un projet et une tâche (données pour les captures).
- [ ] Dashboard CloudWatch visible (`terraform output dashboard_url`).
- [ ] Tester le **rollback** : déployer un tag cassé (ex. variable d'environnement invalide) → constater que le circuit breaker revient en arrière.

## 3. Pipelines GitHub

- [ ] Créer les variables GitHub (`terraform output github_actions_variables`) et les environnements `production`, `infra-production` (relecteurs).
- [ ] Pousser un commit sur `main` : **CI verte**, **CD verte** (OIDC, scans, migrations, déploiement).
- [ ] Ouvrir une PR modifiant `infrastructure/` : `infra.yml` affiche le plan et les contrôles OPA.
- [ ] Lancer `dast.yml` : rapport ZAP disponible. **Traiter ou justifier chaque alerte High/Medium.**
- [ ] Corriger les premières erreurs des scanners (Trivy, Checkov, Snyk) : corriger le code **ou** ajouter une exception commentée.

## 4. Captures (dossier `docs/screenshots/`)

Voir la liste dans `docs/screenshots/README.md`. Masquer : numéro de compte, ARN, URLs de l'ALB si besoin, mots de passe.

## 5. Nettoyage

- [ ] `make demo-down` ; vérifier dans la console : plus d'ALB, RDS, NAT, volumes ou IP élastiques.
- [ ] Budget alerte conservé.

## 6. Mise à jour du dépôt avant publication

- [ ] Remplacer, dans `docs/case-study/case-study.md`, la section « Résultats » par les **vrais** chiffres (durées de pipeline, coût réel, alertes ZAP traitées).
- [ ] Ajouter les captures au README.
- [ ] `git tag v2-fargate` ; créer la branche `v1-ec2` depuis le commit de la v1, puis supprimer `legacy/`.
- [ ] Relire le dépôt : aucun secret, aucun ARN de compte réel dans le code ou les captures.
