############################################
# Bootstrap del backend remoto del Terraform principal
#
# Este Terraform es independiente y usa ESTADO LOCAL a proposito: es la
# unica excepcion a la regla de "backend remoto" del resto del proyecto.
# Motivo (problema de huevo-y-gallina): el Terraform principal
# (infra/terraform) quiere usar backend "s3" con locking en DynamoDB,
# pero ese bucket/tabla tienen que existir ANTES de poder hacer
# `terraform init` con ese backend. Este modulo bootstrap se aplica una
# sola vez (y casi no vuelve a cambiar) con estado local, crea el bucket
# y la tabla, y solo entonces el Terraform principal puede inicializarse
# contra ellos via `terraform init -backend-config=backend.hcl`.
############################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Sin backend{} -> estado local, intencionado (ver comentario arriba).
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

data "aws_caller_identity" "current" {}

############################################
# Bucket S3 para el tfstate del Terraform principal
############################################

resource "aws_s3_bucket" "tfstate" {
  # Nombre deterministico y unico a nivel global (se añade el account id).
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project     = var.project_name
    Owner       = var.owner
    Environment = "bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
# Tabla DynamoDB para locking del state
############################################

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.project_name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project     = var.project_name
    Owner       = var.owner
    Environment = "bootstrap"
  }
}
