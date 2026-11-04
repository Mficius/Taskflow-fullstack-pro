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
  description = "Deux sous-réseaux publics (ALB requiert 2 AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "Au moins deux sous-réseaux sont nécessaires pour l'ALB."
  }
}

variable "allowed_ingress_cidrs" {
  description = "CIDR autorisés à joindre l'ALB (restreindre pour une préproduction)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_flow_logs" {
  description = "Active les VPC Flow Logs vers CloudWatch."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  type    = number
  default = 14
}

# ── Calcul ──────────────────────────────────────────────────
variable "instance_type" {
  description = "Type d'instance (app + MySQL + monitoring : 4 Go de RAM minimum conseillé)."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_gb" {
  type    = number
  default = 30
}

variable "data_volume_gb" {
  description = "Volume EBS persistant (MySQL, Prometheus, Grafana)."
  type        = number
  default     = 20
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

variable "enable_deletion_protection" {
  type    = bool
  default = false
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

variable "create_github_oidc_provider" {
  description = "false si le provider OIDC GitHub existe déjà dans le compte (un seul par URL)."
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

variable "tf_state_bucket" {
  description = "Bucket S3 de l'état Terraform (créé par scripts/bootstrap-tfstate.sh). Active les rôles OIDC du pipeline infra."
  type        = string
  default     = ""
}

variable "github_infra_environment" {
  description = "Environnement GitHub (avec approbation) autorisé à exécuter terraform apply."
  type        = string
  default     = "infra-production"
}

variable "enable_account_guardrails" {
  description = "Active des garde-fous au niveau du compte/région : Block Public Access S3 et chiffrement EBS par défaut. Mettre false si le compte est partagé avec d'autres charges de travail."
  type        = bool
  default     = true
}
