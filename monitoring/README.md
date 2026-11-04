# Monitoring

| Environnement | Outil | Où |
|---|---|---|
| **Production (ECS Fargate)** | CloudWatch Container Insights + dashboard + alarmes (SNS) | Terraform `infrastructure/terraform/monitoring.tf` — URL : `terraform output dashboard_url` |
| **Local / développement** | Prometheus + Grafana + cAdvisor + exporters MySQL/nginx | `docker compose --profile monitoring up -d` → Grafana http://localhost:3001 (admin/admin) |

Les règles d'alerte Prometheus (`prometheus/alerts.yml`) et le dashboard Grafana (`grafana/dashboards/taskflow-overview.json`) sont provisionnés automatiquement.
Sur Fargate, Prometheus/Grafana auto-hébergés demanderaient du stockage persistant et un accès réseau dédié : CloudWatch est natif, sans serveur à maintenir. Évolution possible : Amazon Managed Service for Prometheus + Grafana.
