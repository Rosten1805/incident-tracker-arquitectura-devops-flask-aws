############################################
# Outputs: valores a copiar en infra/terraform/backend.hcl
############################################

output "tfstate_bucket_name" {
  description = "Nombre del bucket S3 que debe usarse como 'bucket' en backend.hcl del Terraform principal."
  value       = aws_s3_bucket.tfstate.bucket
}
