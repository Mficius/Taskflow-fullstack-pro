variable "aws_region" {
  description = "Région AWS de déploiement."
  type        = string
  default     = "eu-west-3" # Paris
}

variable "project" {
  description = "Nom du projet (préfixe des ressources)."
  type        = string
  default     = "taskflow"
}

variable "environment" {
  description = "Nom de l'environnement."
  type        = string
  default     = "prod"
}

# ── Réseau ──────────────────────────────────────────────────
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Sous-réseaux publics (ALB + tâches Fargate). Deux AZ minimum."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactement deux sous-réseaux publics sont attendus."
  }
}

variable "db_subnet_cidrs" {
  description = "Sous-réseaux ISOLÉS pour RDS (aucune route vers Internet)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.db_subnet_cidrs) == 2
    error_message = "Exactement deux sous-réseaux de base de données sont attendus."
  }
}

variable "allowed_ingress_cidrs" {
  description = "CIDR autorisés à joindre l'ALB (restreindre pour une préproduction)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_flow_logs" {
  description = "Active les VPC Flow Logs (trafic refusé) vers CloudWatch."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  type    = number
  default = 14
}

# ── ECS Fargate ─────────────────────────────────────────────
variable "task_cpu" {
  description = "CPU de la tâche (256, 512, 1024…)."
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Mémoire de la tâche en Mo (1024 minimum avec 512 CPU)."
  type        = number
  default     = 1024
}

variable "min_tasks" {
  type    = number
  default = 1
}

variable "max_tasks" {
  type    = number
  default = 3
}

variable "bootstrap_image_tag" {
  description = "Tag initial des définitions de tâche (jamais exécuté : le service démarre à 0 ; la CD enregistre les vraies révisions)."
  type        = string
  default     = "bootstrap"
}

# ── Base de données (RDS MySQL) ─────────────────────────────
variable "db_engine_version" {
  type    = string
  default = "8.4"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_multi_az" {
  description = "Multi-AZ (haute disponibilité de la base, ×2 le coût)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

# ── Cycle de vie « démonstration » (portfolio) ──────────────
variable "demo_mode" {
  description = "true = tout peut être détruit proprement (pas de snapshot final, ECR vidé, pas de protection). false = production : protections activées."
  type        = bool
  default     = true
}

# ── HTTPS / URL ─────────────────────────────────────────────
variable "certificate_arn" {
  description = "ARN d'un certificat ACM (même région). Vide = HTTP uniquement."
  type        = string
  default     = ""
}

variable "app_url" {
  description = "URL publique (ex. https://taskflow.example.com). Vide = DNS de l'ALB en HTTP."
  type        = string
  default     = ""
}

# ── GitHub OIDC ─────────────────────────────────────────────
variable "github_owner" {
  description = "Propriétaire GitHub (utilisateur ou organisation)."
  type        = string
  default     = "Mficius"
}

variable "github_repo" {
  description = "Nom du dépôt GitHub."
  type        = string
  default     = "taskflow"
}

variable "github_branch" {
  description = "Seule branche autorisée à pousser des images."
  type        = string
  default     = "main"
}

variable "github_environment" {
  description = "Environnement GitHub (avec approbation) autorisé à déployer."
  type        = string
  default     = "production"
}

variable "github_infra_environment" {
  description = "Environnement GitHub (avec approbation) autorisé à exécuter terraform apply."
  type        = string
  default     = "infra-production"
}

variable "create_github_oidc_provider" {
  description = "false si le provider OIDC GitHub existe déjà dans le compte (un seul par URL)."
  type        = bool
  default     = true
}

variable "tf_state_bucket" {
  description = "Bucket S3 de l'état Terraform (créé par scripts/bootstrap-tfstate.sh). Active les rôles OIDC du pipeline infra."
  type        = string
  default     = ""
}

variable "enable_account_guardrails" {
  description = "Garde-fous au niveau du compte/région : Block Public Access S3 et chiffrement EBS par défaut. false si le compte est partagé."
  type        = bool
  default     = true
}

# ── Application / alertes ───────────────────────────────────
variable "admin_email" {
  description = "E-mail du compte administrateur TaskFlow créé au premier déploiement."
  type        = string
  default     = "admin@taskflow.local"
}

variable "alert_email" {
  description = "Adresse recevant les alarmes CloudWatch (vide = aucune notification)."
  type        = string
  default     = ""
}

variable "ecr_keep_images" {
  description = "Nombre d'images conservées par dépôt ECR."
  type        = number
  default     = 20
}
