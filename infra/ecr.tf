resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "IMMUTABLE" # every deploy is a unique git-SHA tag
  force_delete         = true

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 25 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 25 }
      action       = { type = "expire" }
    }]
  })
}
