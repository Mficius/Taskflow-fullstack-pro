###############################################################################
# EC2 : hôte d'administration "bastion SSM" (optionnel)
# - aucune IP publique, aucun port entrant, pas de clé SSH
# - accès uniquement par AWS Systems Manager Session Manager
# - sert à joindre RDS (port-forward) et l'API EKS privée
###############################################################################
data "aws_ssm_parameter" "al2023" {
  count = var.enable_ops_host ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "ops" {
  count = var.enable_ops_host ? 1 : 0

  ami                         = data.aws_ssm_parameter.al2023[0].value
  instance_type               = var.ops_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.ops[0].id]
  iam_instance_profile        = aws_iam_instance_profile.ops[0].name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    kms_key_id  = aws_kms_key.main.arn
  }

  tags = { Name = "${local.name}-ops" }

  lifecycle {
    ignore_changes = [ami] # pas de recréation à chaque nouvelle AMI
  }
}
