############################################
# Terraform / provider configuration
############################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }


  backend "s3" {}
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

############################################
# Data sources: VPC por defecto y subredes
############################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Detalle de cada subred (incluye su AZ), una entrada por subnet-id.
data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

############################################
# Data source: AMI más reciente de Amazon Linux 2023
#
# Se usa el parametro publico de SSM que mantiene AWS, en vez de un
# filtro por nombre sobre aws_ami: es el metodo que AWS recomienda
# oficialmente para obtener siempre la AMI mas reciente sin arriesgarse
# a que un patron de nombre deje de coincidir en el futuro.
############################################

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

############################################
# Locals
############################################

locals {
  common_tags = {
    Project     = var.project_name
    Owner       = var.owner
    Environment = var.environment
  }

  # Agrupa las subredes de la VPC por defecto por AZ y se queda con UNA
  # subred por AZ (la primera encontrada). Esto garantiza que, si hay
  # subredes repetidas en la misma AZ, no las contamos dos veces.
  subnets_by_az = {
    for s in values(data.aws_subnet.default) : s.availability_zone => s.id...
  }

  # Lista de subnet-ids, una por AZ distinta, ordenada por nombre de AZ
  # (orden determinista entre applies). El ALB requiere >= 2 AZs distintas;
  # la VPC por defecto de eu-west-1 normalmente tiene 3.
  distinct_az_subnet_ids = [
    for az in sort(keys(local.subnets_by_az)) : local.subnets_by_az[az][0]
  ]

  # Subredes usadas por el ALB: todas las AZs distintas disponibles.
  alb_subnet_ids = local.distinct_az_subnet_ids

  # Subred para cada instancia EC2: se reparten entre AZs distintas cuando
  # es posible (no es un requisito funcional -ver sección 8 de
  # ARCHITECTURE.md sobre el SPOF consciente- pero no cuesta nada repartirlas).
  jenkins_subnet_id = local.distinct_az_subnet_ids[0]
  app_subnet_id     = length(local.distinct_az_subnet_ids) > 1 ? local.distinct_az_subnet_ids[1] : local.distinct_az_subnet_ids[0]
}
