############################################
# CloudWatch: log group, dashboard y alarma de CPU
############################################

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/app-server"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "CPU Utilization - EC2"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          stat    = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.app_server.id, { label = "app-server" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.jenkins_server.id, { label = "jenkins-server" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB - Requests y tiempo de respuesta"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix, { stat = "Sum", label = "Requests" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix, { stat = "Average", label = "Response time (s)" }]
          ]
        }
      }
    ]
  })
}

# Alarma de CPU alta sobre app-server (es la instancia de produccion
# visible detras del ALB; jenkins-server es herramienta interna de CI).
resource "aws_cloudwatch_metric_alarm" "app_cpu_high" {
  alarm_name          = "${var.project_name}-app-server-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  treat_missing_data  = "notBreaching"
  alarm_description   = "CPU de app-server por encima del umbral durante 2 periodos de 5 min"

  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  tags = local.common_tags
}
