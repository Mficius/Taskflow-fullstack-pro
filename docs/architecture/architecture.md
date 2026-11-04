# Architecture (v2 — ECS Fargate + RDS)

> La v1 « instance unique » est conservée dans [`legacy/ec2/`](../../legacy/ec2/README.md). Le raisonnement de la migration est dans [l'étude de cas](../case-study/case-study.md).

## Vue d'ensemble

```mermaid
flowchart LR
    U([Utilisateur]) -->|HTTP/HTTPS| ALB[Application Load Balancer<br/>SG : 80/443 publics]
    subgraph VPC["VPC 10.0.0.0/16 — 2 AZ"]
      subgraph PUB["Sous-réseaux publics"]
        ALB
        subgraph TASK["Tâche ECS Fargate (awsvpc) — SG : 8000 depuis l'ALB uniquement"]
          NGX["nginx :8000<br/>en-têtes sécu · rate-limit"] --> FE["frontend :8080<br/>React/Vite statique"]
          NGX -->|FastCGI :9000| BE["backend<br/>Laravel 12 · PHP-FPM"]
        end
      end
      subgraph DB["Sous-réseaux ISOLÉS (sans route Internet)"]
        RDS[(RDS MySQL 8.4<br/>chiffré · sauvegardes 7 j)]
      end
      ALB -->|HTTP 8000| NGX
      BE -->|3306 — SG→SG| RDS
    end
    ECR[(ECR ×3<br/>tags immuables · scan)] -.pull.-> TASK
    SSM[SSM Parameter Store<br/>APP_KEY · DB_PASSWORD…] -.secrets injectés.-> TASK
    CW[CloudWatch<br/>Container Insights · dashboard · alarmes] -.métriques/logs.-> TASK
```

| Couche | Choix | Pourquoi |
|---|---|---|
| Entrée | ALB, health check `GET /up` (Laravel) | Terminaison TLS (ACM), redirection HTTP→HTTPS, retire les tâches malsaines |
| Calcul | **ECS Fargate**, 1 tâche = nginx + frontend + backend | Aucun serveur à patcher, déploiement progressif, rollback automatique |
| Base | **RDS MySQL** dans des sous-réseaux sans route Internet | Sauvegardes/PITR gérés, chiffrement, accessible seulement depuis les tâches |
| Réseau | Tâches en sous-réseau public + IP publique, SG `ALB → app` | Évite la NAT Gateway (~35 $/mois). Évolution : sous-réseaux privés + VPC endpoints |
| Admin | ECS Exec (SSM) | Aucun port SSH, session journalisée |
| Secrets | SSM Parameter Store → champ `secrets` des tâches | Générés par Terraform, jamais dans le code ni dans les variables GitHub |
| Images | ECR, tag = SHA du commit, immuable | Traçabilité + rollback exact |
| Observabilité | CloudWatch Container Insights + dashboard + alarmes SNS | Natif, sans serveur. Prometheus/Grafana : profil local |

## Déploiement (CD)

```mermaid
sequenceDiagram
    autonumber
    participant GH as GitHub Actions
    participant AWS as AWS STS (OIDC)
    participant ECR
    participant ECS
    participant RDS

    GH->>GH: CI verte sur main
    GH->>AWS: jeton OIDC (sub = …:ref:refs/heads/main)
    AWS-->>GH: credentials temporaires (rôle ECR-push)
    GH->>ECR: build ×3 → scan Trivy → push (tag = SHA)
    Note over GH: environnement « production » (approbation)
    GH->>AWS: jeton OIDC (sub = …:environment:production)
    AWS-->>GH: credentials temporaires (rôle deploy)
    GH->>ECS: enregistre les nouvelles définitions de tâche
    GH->>ECS: run-task « migrate »
    ECS->>RDS: php artisan migrate
    alt migration en échec
        GH-->>GH: déploiement ARRÊTÉ, service intact
    else migration OK
        GH->>ECS: update-service (nouvelle révision)
        ECS->>ECS: démarre la nouvelle tâche · health check ALB
        alt déploiement en échec
            ECS->>ECS: circuit breaker → retour AUTOMATIQUE à la révision précédente
        end
    end
    GH->>GH: smoke test public /up
```

Rollback manuel : *Actions → CD → Run workflow* avec `image_tag` = tag précédent (même procédure, sans build).

## Limites connues (documentées)

- **Une seule tâche par défaut** (`DESIRED_COUNT=1`) : pas de haute disponibilité tant qu'on n'en lance pas deux ; RDS Multi-AZ via `db_multi_az = true`.
- **La base utilise l'utilisateur principal RDS** (pas d'utilisateur applicatif à droits réduits) : évolution recommandée.
- **Trafic ALB → tâche en HTTP** (TLS terminé à l'ALB, réseau privé du VPC).
- Les migrations ne sont pas annulées par un rollback : écrire des migrations rétro-compatibles (*expand / contract*).
- Les secrets Terraform sont dans le state : backend S3 chiffré (voir runbook).
