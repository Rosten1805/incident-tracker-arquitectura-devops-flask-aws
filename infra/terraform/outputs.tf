############################################
# Outputs
############################################

output "alb_dns_name" {
  description = "DNS name del ALB (punto de entrada publico de la app). Un ALB no tiene IP fija, por eso no hay un output de IP aqui."
  value       = aws_lb.app.dns_name
}

output "ecr_repository_name" {
  description = "Nombre del repositorio ECR de la imagen de la app."
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  description = "URL completa del repositorio ECR (para docker push/pull)."
  value       = aws_ecr_repository.app.repository_url
}

output "jenkins_server_public_ip" {
  description = "IP publica de jenkins-server, para acceder a la UI en :8080 desde allowed_ip."
  value       = aws_instance.jenkins_server.public_ip
}

output "app_server_instance_id" {
  description = "Instance ID de app-server (usado por Jenkins para el despliegue via SSM Run Command)."
  value       = aws_instance.app_server.id
}

output "s3_backups_bucket" {
  description = "Nombre del bucket S3 de backups usado por el script de housekeeping en Python."
  value       = aws_s3_bucket.backups.bucket
}

output "cloudwatch_log_group" {
  description = "Nombre del log group de CloudWatch de app-server."
  value       = aws_cloudwatch_log_group.app.name
}
