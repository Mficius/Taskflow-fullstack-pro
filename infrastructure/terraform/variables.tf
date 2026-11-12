variable "project_name" {
  description = "Nom du projet (préfixe de toutes les ressources)."
  type        = string
  default     = "taskflow"
}

variable "environment" {
  description = "Environnement cible."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment doit valoir dev, staging ou prod."
  }
}

variable "aws_region" {
  description = "Région AWS."
  type        = string
  default     = "eu-west-3"
}

variable "extra_tags" {
  description = "Tags additionnels."
  type        = map(string)
  default     = {}
}

# ------------------------------- Réseau --------------------------------------
variable "vpc_cidr" {
  description = "CIDR du VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Nombre de zones de disponibilité (2 minimum pour ALB/RDS)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count doit être 2 ou 3."
  }
}

variable "single_nat_gateway" {
  description = "true = 1 NAT (économique, non HA) ; false = 1 NAT par AZ (HA)."
  type        = bool
  default     = true
}

# --------------------------------- EKS ---------------------------------------
variable "eks_version" {
  description = "Version Kubernetes du control plane."
  type        = string
  default     = "1.36"
}

variable "eks_public_access_cidrs" {
  description = "CIDR autorisés sur l'endpoint public de l'API EKS. 0.0.0.0/0 est interdit."
  type        = list(string)

  validation {
    condition     = !contains(var.eks_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 est interdit pour l'endpoint API EKS (preventive control)."
  }
}

variable "eks_endpoint_public_access" {
  description = "false = API privée uniquement (déploiement depuis l'hôte ops / un runner dans le VPC)."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "Types d'instances du node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 5
}

# --------------------------------- RDS ---------------------------------------
variable "db_name" {
  description = "Nom de la base applicative."
  type        = string
  default     = "taskflow"
}

variable "db_username" {
  description = "Utilisateur maître RDS (réservé à l'administration et au bootstrap)."
  type        = string
  default     = "taskflow_admin"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.small"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_max_allocated_storage" {
  type    = number
  default = 100
}

variable "db_multi_az" {
  description = "Multi-AZ (true par défaut ; false seulement pour dev)."
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

# --------------------------------- ALB ---------------------------------------
variable "acm_certificate_arn" {
  description = "ARN du certificat ACM pour le listener HTTPS (obligatoire : pas de HTTP en clair)."
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "CIDR autorisés à joindre l'ALB (HTTPS)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "waf_rate_limit" {
  description = "Requêtes / 5 min / IP avant blocage par le WAF."
  type        = number
  default     = 2000
}

# ------------------------------ EC2 (ops host) --------------------------------
variable "enable_ops_host" {
  description = "Crée un hôte d'administration SSM-only (pas de SSH, pas d'IP publique)."
  type        = bool
  default     = false
}

variable "ops_instance_type" {
  type    = string
  default = "t3.micro"
}

# ------------------------------- GitHub OIDC ----------------------------------
variable "github_repository" {
  description = "Dépôt GitHub autorisé via OIDC, format org/repo."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository doit être au format org/repo."
  }
}

variable "create_github_oidc_provider" {
  description = "false si le fournisseur OIDC GitHub existe déjà dans le compte (1 seul autorisé)."
  type        = bool
  default     = true
}

variable "github_infra_environment" {
  description = "Environment GitHub (avec reviewers obligatoires) autorisé à lancer terraform apply."
  type        = string
  default     = "production-infra"
}

variable "eks_admin_principal_arns" {
  description = "ARN IAM (rôles SSO / admins) qui reçoivent AmazonEKSClusterAdminPolicy."
  type        = list(string)
  default     = []
}

variable "tfstate_bucket_arn" {
  description = "ARN du bucket S3 du state (pour le rôle terraform plan en lecture)."
  type        = string
  default     = ""
}

variable "tfstate_lock_table_arn" {
  description = "ARN de la table DynamoDB de lock."
  type        = string
  default     = ""
}

variable "tfstate_kms_key_arn" {
  description = "ARN de la clé KMS dédiée au chiffrement du state Terraform distant."
  type        = string
  default     = ""
}
