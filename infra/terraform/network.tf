############################################
# Security Groups
#
# Ninguno de los tres abre el puerto 22: el acceso a shell es vía
# AWS Systems Manager Session Manager (cubierto por el permiso SSM de
# los roles IAM en iam.tf), no SSH. Ver ARCHITECTURE.md secciones 3 y 5.
############################################

# SG del ALB: HTTP 80 abierto al mundo (es la puerta de entrada pública).
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: HTTP 80 publico"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP desde Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida sin restriccion"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-alb-sg" })
}

# SG de app-server: el puerto de la app SOLO se acepta desde el SG del ALB,
# nunca directamente desde Internet.
resource "aws_security_group" "app_server" {
  name        = "${var.project_name}-app-server-sg"
  description = "app-server: puerto de la app solo desde el ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "App port solo desde el SG del ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Salida sin restriccion (pull de ECR, SSM, CloudWatch...)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-app-server-sg" })
}

# SG de jenkins-server: el puerto 8080 (UI de Jenkins) solo accesible desde
# la IP indicada en var.allowed_ip (formato CIDR, p. ej. "1.2.3.4/32").
resource "aws_security_group" "jenkins_server" {
  name        = "${var.project_name}-jenkins-server-sg"
  description = "jenkins-server: puerto 8080 solo desde allowed_ip"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Jenkins UI solo desde la IP autorizada"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  egress {
    description = "Salida sin restriccion (pull de imagenes, push a ECR, SSM...)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-jenkins-server-sg" })
}
