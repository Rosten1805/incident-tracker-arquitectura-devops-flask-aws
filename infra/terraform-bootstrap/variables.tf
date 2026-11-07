############################################
# Variables
############################################

variable "aws_region" {
  description = "Region de AWS donde se crea el bucket de tfstate y la tabla de locking. Debe coincidir con la region que usara el Terraform principal."
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI (SSO) a usar por el provider de Terraform."
  type        = string
  default     = "estudiante"
}

variable "project_name" {
  description = "Nombre corto del proyecto, usado para nombrar el bucket de tfstate y la tabla de locking. Debe coincidir con el project_name del Terraform principal."
  type        = string
  default     = "task-tracker"
}

variable "owner" {
  description = "Propietaria/responsable del recurso, usada en la tag Owner."
  type        = string
  default     = "cristina"
}
