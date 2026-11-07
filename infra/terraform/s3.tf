############################################
# S3: bucket unico para backups del script de housekeeping (Python+boto3)
#
# NO es backend de Terraform. El estado de Terraform es local a proposito
# (ver ARCHITECTURE.md, seccion 5: problema de bootstrap de usar un bucket
# que el propio apply crearia).
############################################

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "backups" {
  # Se añade el account id para garantizar un nombre globalmente unico
  # (los nombres de bucket S3 son unicos a nivel global, no solo de cuenta).
  bucket = "${var.project_name}-backups-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, { Name = "${var.project_name}-backups" })
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Buena practica de seguridad basica, no pedida explicitamente pero
# facil de justificar en entrevista: bucket de backups sin acceso publico.
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
