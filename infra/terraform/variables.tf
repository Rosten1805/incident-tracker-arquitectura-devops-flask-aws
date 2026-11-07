############################################
# Variables
############################################

variable "aws_region" {
  description = "Region de AWS donde se despliega toda la infraestructura."
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI (SSO) a usar por el provider de Terraform."
  type        = string
  default     = "estudiante"
}

variable "project_name" {
  description = "Nombre corto del proyecto, usado como prefijo de nombres de recursos y en la tag Project."
  type        = string
  default     = "task-tracker"
}

variable "owner" {
  description = "Propietaria/responsable del recurso, usada en la tag Owner (control de coste e input del script de housekeeping)."
  type        = string
  default     = "cristina"
}

variable "environment" {
  description = "Entorno (dev/staging/prod), usado en la tag Environment."
  type        = string
  default     = "dev"
}

variable "permissions_boundary_arn" {
  description = "ARN de la policy StudentBoundary. Obligatorio en todos los aws_iam_role de este cuenta de estudiante; sin el, iam:CreateRole es denegado (ver ARCHITECTURE.md seccion 4)."
  type        = string
  default     = "arn:aws:iam::921049725767:policy/StudentBoundary"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 usado tanto para jenkins-server como para app-server."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Puerto en el que escucha el contenedor Flask/Gunicorn de la app (usado por el SG de app-server y el target group del ALB)."
  type        = number
  default     = 5000
}

variable "allowed_ip" {
  description = "CIDR (p. ej. \"198.51.100.7/32\") desde el que se permite acceder al puerto 8080 (UI de Jenkins) de jenkins-server. Sin valor por defecto: cada persona/sesion tiene una IP publica distinta. NUNCA usar 0.0.0.0/0 aqui."
  type        = string
}

variable "log_retention_days" {
  description = "Dias de retencion del log group de CloudWatch de app-server."
  type        = number
  default     = 14
}

variable "cpu_alarm_threshold" {
  description = "Umbral de CPUUtilization (%) a partir del cual se dispara la alarma de app-server."
  type        = number
  default     = 75
}
