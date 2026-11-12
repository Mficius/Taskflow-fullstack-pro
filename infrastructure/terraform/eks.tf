###############################################################################
# EKS : control plane chiffré/journalisé, nodes privés IMDSv2, accès via Access
# Entries (plus d'aws-auth ConfigMap), OIDC provider pour IRSA.
###############################################################################
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

#trivy:ignore:AWS-0040 -- endpoint public restreint par CIDR (0.0.0.0/0 interdit par validation) ; eks_endpoint_public_access=false pour du 100 % privé
resource "aws_eks_cluster" "main" {
  #checkov:skip=CKV_AWS_38:CIDR restreints par variable (0.0.0.0/0 interdit par validation) ; mettre eks_endpoint_public_access=false pour une API 100% privée
  #checkov:skip=CKV_AWS_39:Endpoint public conditionnel (variable) - voir ci-dessus
  name     = local.name
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = var.eks_endpoint_public_access
    public_access_cidrs     = var.eks_endpoint_public_access ? var.eks_public_access_cidrs : null
  }

  # Chiffrement des Secrets Kubernetes dans etcd avec notre CMK
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.main.arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy.eks_cluster_kms,
    aws_cloudwatch_log_group.eks,
  ]
}

# ---- OIDC provider du cluster (IRSA : rôle IAM par ServiceAccount) -----------
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

# ---- Nodes : launch template durci --------------------------------------------
resource "aws_launch_template" "nodes" {
  name_prefix            = "${local.name}-nodes-"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 uniquement
    http_put_response_hop_limit = 1          # les pods n'atteignent pas l'IMDS du node
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 40
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name}-default"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"
  ami_type        = "AL2023_x86_64_STANDARD"

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  labels = { workload = "taskflow" }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes,
    aws_eks_addon.vpc_cni,
  ]

}

# ---- Add-ons gérés -------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  service_account_role_arn    = aws_iam_role.irsa["vpc-cni"].arn
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# ---- Accès administrateur humain (Access Entries) ------------------------------
resource "aws_eks_access_entry" "admins" {
  for_each = toset(var.eks_admin_principal_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admins" {
  for_each = toset(var.eks_admin_principal_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}
