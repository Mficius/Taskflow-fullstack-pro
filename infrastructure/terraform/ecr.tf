# Registres d'images : tags IMMUABLES (un tag = un commit, jamais écrasé), scan à chaque push.
resource "aws_ecr_repository" "app" {
  for_each             = toset(local.ecr_repositories)
  name                 = "${var.project}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.demo_mode # permet un « destroy » propre en démonstration

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conserver les ${var.ecr_keep_images} dernières images (rollback possible)"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_keep_images
      }
      action = { type = "expire" }
    }]
  })
}
