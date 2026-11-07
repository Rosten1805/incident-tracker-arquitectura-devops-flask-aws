############################################
# IAM: dos roles separados, mínimo privilegio real
#
# Restricción verificada de la cuenta (ARCHITECTURE.md, sección 4):
# iam:CreateRole solo funciona si el rol tiene permissions_boundary =
# StudentBoundary Y su nombre empieza por "student-". Ese mismo prefijo
# es el único permitido para iam:PassRole. Por eso TODOS los roles de
# este fichero cumplen ambas condiciones.
############################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

############################################
# Rol 1: student-jenkins-ec2-role
#   - SSM (administración sin SSH)
#   - ECR: permiso de ESCRITURA (push de imágenes desde el pipeline)
############################################

resource "aws_iam_role" "jenkins_ec2" {
  name                 = "student-jenkins-ec2-role"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume_role.json
  permissions_boundary = var.permissions_boundary_arn
  description          = "Rol de la instancia jenkins-server: SSM + push a ECR"

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# PowerUser de ECR = pull + push. Es lo mínimo gestionado por AWS que
# cubre "push de imágenes"; no existe un managed policy "solo push".
resource "aws_iam_role_policy_attachment" "jenkins_ecr_write" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# Permisos que el Jenkinsfile necesita y que NINGUN managed policy cubre
# sin pasarse de amplio: localizar app-server y el ALB en tiempo de
# ejecucion (sin hardcodear IDs en el pipeline), y enviar/leer comandos
# SSM Run Command contra esa instancia concreta (no contra cualquier
# instancia de la cuenta).
resource "aws_iam_role_policy" "jenkins_deploy" {
  name = "jenkins-pipeline-deploy"
  role = aws_iam_role.jenkins_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeParaResolverDestino"
        Effect = "Allow"
        # ec2:DescribeInstances y elasticloadbalancing:DescribeLoadBalancers
        # son acciones de solo lectura que AWS no permite restringir a nivel
        # de recurso (siempre Resource = "*"); es su comportamiento normal.
        Action = [
          "ec2:DescribeInstances",
          "elasticloadbalancing:DescribeLoadBalancers",
        ]
        Resource = "*"
      },
      {
        Sid    = "EnviarComandoSoloAAppServer"
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
          "arn:aws:ec2:${var.aws_region}:*:instance/*",
        ]
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Name" = "${var.project_name}-app-server"
          }
        }
      },
      {
        Sid      = "LeerResultadoDelComando"
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_ec2" {
  name = "student-jenkins-ec2-profile"
  role = aws_iam_role.jenkins_ec2.name
}

############################################
# Rol 2: student-app-ec2-role
#   - SSM (despliegue remoto vía Run Command, sin SSH)
#   - ECR: permiso de SOLO LECTURA (pull de la imagen a ejecutar)
#   - CloudWatch: logs + métricas (CloudWatch Agent)
############################################

resource "aws_iam_role" "app_ec2" {
  name                 = "student-app-ec2-role"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume_role.json
  permissions_boundary = var.permissions_boundary_arn
  description          = "Rol de la instancia app-server: SSM + ECR read-only + CloudWatch"

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "app_ecr_read" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "app_cloudwatch" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app_ec2" {
  name = "student-app-ec2-profile"
  role = aws_iam_role.app_ec2.name
}
