# Étude de cas — Industrialiser TaskFlow : de `docker compose` à ECS Fargate avec une chaîne DevSecOps

> **Statut honnête** : l'architecture, le Terraform et les pipelines ont été conçus et validés statiquement (syntaxe, tests unitaires applicatifs). Les chiffres de la section « Résultats » sont à remplacer par les mesures du premier déploiement réel (voir `docs/deployment-checklist.md`).

## Contexte

TaskFlow est une application de gestion de tâches (React 18 + MUI, Laravel 12 + Sanctum, MySQL) qui ne tournait qu'en local.
Objectif : la rendre **déployable, observable et sécurisée**, avec une chaîne de livraison reproductible et un budget maîtrisé.

## Problèmes constatés au départ

| Constat | Risque |
|---|---|
| `.env` (avec `APP_KEY` et mot de passe root MySQL = `root`) présent dans l'archive du projet | Fuite de secrets |
| `config:cache` exécuté **au build** de l'image | Les variables d'environnement du serveur sont ignorées en production |
| Image de production contenant compilateur, git, pcov | Surface d'attaque, image lourde |
| Seeder avec comptes `admin123` / `manager123` | Compte administrateur trivial en production |
| phpMyAdmin et MySQL exposés sur l'hôte ; `mysql/data` monté dans le dépôt | Accès direct à la base, données versionnables par erreur |
| Test frontend écrit pour Jest alors que le projet utilise Vitest | CI impossible |
| Aucune infra, aucun pipeline, aucune supervision | Déploiement manuel, pas de rollback |

## Parcours : deux architectures, un choix argumenté

### v1 — une instance EC2 + Docker Compose (conservée dans `legacy/ec2/`)

1 EC2, MySQL sur volume EBS chiffré, déploiement par SSM + script avec rollback, Prometheus/Grafana embarqués. **≈ 75 $/mois**, simple à valider.
Limites : un seul point de défaillance (instance **et** base), système d'exploitation à patcher, base non managée, pas de montée en charge.

### v2 — ECS Fargate + RDS (version principale)

| Sujet | v1 (EC2) | v2 (Fargate) | Raison du choix |
|---|---|---|---|
| Serveur | À patcher, Docker à gérer | **Aucun** | Moins de surface d'attaque et d'exploitation |
| Base | MySQL en conteneur | **RDS** chiffrée, sous-réseaux isolés, PITR | Sauvegardes et restauration gérées |
| Déploiement | Script SSM + compose | **ECS** + circuit breaker | Rollback automatique natif |
| Migrations | Au démarrage du conteneur | **Tâche ponctuelle avant déploiement** | Une migration en échec n'interrompt pas la prod |
| Supervision | Prometheus/Grafana (stockage à gérer) | **CloudWatch** + Container Insights | Natif, sans serveur ; Prometheus reste en local |
| Montée en charge | Impossible sans refonte | `DESIRED_COUNT`, Multi-AZ RDS | Prêt pour plusieurs tâches |
| Coût | ≈ 75 $ | ≈ 75 $ (1 tâche, sans NAT) | Équivalent à taille égale, mais avec base managée |

Les **mêmes images ECR** et le même pipeline de sécurité servent aux deux : le passage de l'une à l'autre n'a pas demandé de réécrire l'application.

## Solution (v2)

1. **Conteneurs de production** : image PHP-FPM Alpine multi-étapes sans outils de build, non-root, healthcheck, caches Laravel générés au démarrage ; frontend nginx *unprivileged* ; **passerelle nginx** (en-têtes de sécurité, rate-limit sur `/api/auth/login`) configurée par template.
2. **Infrastructure as Code (Terraform)** : VPC 2 AZ, ALB, ECS Fargate (1 tâche = 3 conteneurs), RDS en sous-réseaux isolés, ECR (tags immuables, scan), secrets générés dans SSM et injectés par ECS, alarmes et dashboard CloudWatch.
3. **CI** : tests (PHPUnit, Vitest) avec couverture, Gitleaks, SonarQube, CodeQL, Snyk, audits Composer/npm, Hadolint, Trivy (dépendances, images).
4. **Sécurité de l'IaC avant création** : Trivy + Checkov + Snyk IaC, puis **contrôles préventifs OPA/Conftest** sur le plan Terraform (aucun apply si une règle est violée), garde-fous de compte.
5. **Tester l'infra sans cloud** : `terraform test` avec providers simulés ; apply réel sur **LocalStack** quand le jeton est disponible.
6. **CD avec OIDC** : aucune clé AWS stockée ; rôles distincts (push ECR depuis `main`, déploiement depuis l'environnement protégé) ; migrations → mise à jour du service → circuit breaker.
7. **DAST** : scan actif authentifié de l'API par OWASP ZAP sur une pile éphémère (jamais sur la production) ; baseline passif après déploiement.
8. **Cycle « démonstration »** : `make demo-up` / `make demo-down` créent et détruisent tout (quelques dollars par session) pour un portfolio qui ne coûte rien au repos.

## Décisions et compromis

| Décision | Alternative | Raison |
|---|---|---|
| Tâches en sous-réseau public + IP publique | Sous-réseaux privés + NAT/endpoints | ≈ −35 $/mois ; entrée impossible hors ALB (security group) ; évolution documentée |
| 1 tâche, RDS mono-AZ par défaut | 2 tâches + Multi-AZ | Coût de démonstration ; activables (`DESIRED_COUNT`, `db_multi_az`) |
| CloudWatch en production | Prometheus/Grafana sur Fargate | Pas de stockage persistant ni d'accès réseau dédié à gérer |
| Utilisateur principal RDS pour l'application | Utilisateur à droits réduits | Simplicité ; amélioration listée |
| Rôle `apply` Terraform très large | Politique fine par service | Terraform gère IAM/VPC/…; protégé par environnement approuvé + OPA ; à resserrer |
| LocalStack conditionnel | LocalStack obligatoire | ECS/RDS/ELB sont (à notre connaissance) des services payants ; les tests `mock_provider` couvrent le cas sans compte |

## Résultats (à compléter après le déploiement réel)

| Mesure | Valeur |
|---|---|
| Durée CI / CD | _à mesurer_ |
| Durée d'un déploiement complet (`make demo-up`) | _à mesurer_ |
| Coût réel d'une session de démonstration | _à mesurer_ |
| Alertes ZAP (High / Medium) traitées | _à mesurer_ |
| Vulnérabilités corrigées grâce aux scans | _à mesurer_ |
| Test de rollback automatique | _capture_ |

## Leçons

- Générer les caches Laravel **au démarrage** et non au build.
- Des tags d'image immuables rendent le rollback déterministe.
- Jouer les migrations **avant** de toucher au service évite de casser la production avec un schéma à moitié appliqué.
- La sécurité de la chaîne de livraison (OIDC, moindres privilèges, politiques préventives, environnement protégé) compte autant que celle de l'application.
- Un émulateur (LocalStack) détecte des erreurs de configuration, il ne remplace pas un vrai déploiement.

## Prochaines étapes

Sous-réseaux privés + VPC endpoints, HTTPS (ACM) + WAF, 2 tâches + RDS Multi-AZ, Auto Scaling, utilisateur MySQL dédié, signature d'images (cosign), tests de charge.
