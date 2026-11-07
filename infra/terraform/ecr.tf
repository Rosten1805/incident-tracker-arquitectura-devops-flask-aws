############################################
# Amazon ECR: repositorio de la imagen de la app
############################################

############################################
# Amazon ECR: repositorio de la imagen propia de Jenkins
#
# Imagen que extiende jenkins/jenkins:lts con docker (cliente),
# aws-cli y terraform ya instalados (ver jenkins/Dockerfile en la raiz
# del repo). Se construye y sube UNA VEZ, a mano, como un bootstrap mas
# -no en cada boot de la instancia- para que el arranque sea rapido y
# la imagen sea inmutable/reproducible. El user_data de jenkins-server
# (ver user_data/jenkins.sh.tpl) solo hace "docker pull" de esta imagen.
############################################

resource "aws_ecr_repository" "jenkins_image" {
  name                 = "${var.project_name}-jenkins"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "jenkins_image" {
  repository = aws_ecr_repository.jenkins_image.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expirar imagenes sin tag tras 14 dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_repository" "app" {
  name = "${var.project_name}-app"

  # MUTABLE porque el pipeline etiqueta cada build con <commit-sha> Y
  # con "latest" (ARCHITECTURE.md, stage 5) y "latest" se reescribe en
  # cada push. El tag del commit-sha nunca se reutiliza, asi que el
  # rollback (volver a desplegar un sha anterior) sigue siendo seguro.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

# Limpieza automatica de imagenes sin tag (capas huerfanas de builds
# fallidos o intermedios) para no acumular coste de almacenamiento.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expirar imagenes sin tag tras 14 dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
