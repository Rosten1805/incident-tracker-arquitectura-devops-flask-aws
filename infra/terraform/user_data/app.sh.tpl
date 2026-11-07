#!/bin/bash
# user_data de app-server: instala Docker y el CloudWatch Agent.
# El contenedor de la app NO se arranca aqui: lo despliega Jenkins despues,
# vía SSM Run Command, tras hacer login/pull de ECR (ver ARCHITECTURE.md,
# flujo de CI/CD, paso 8).
#
# Los LOGS de la app no pasan por este agente: Jenkins arranca el
# contenedor con --log-driver awslogs, asi que Docker manda stdout/stderr
# directo a CloudWatch Logs (log_group), sin necesidad de montar ningun
# volumen ni de que el agente tenga que tailear ficheros. Este agente solo
# se encarga de METRICAS (cpu/mem/disk) de la instancia, que si le hacen
# falta a el.
#
# ${aws_region} es variable de plantilla de Terraform (templatefile),
# sustituida en el momento del apply; no es variable de shell.
set -euxo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user || true

# CloudWatch Agent (paquete oficial, no esta en los repos dnf de AL2023)
rpm -Uvh "https://s3.${aws_region}.amazonaws.com/amazoncloudwatch-agent-${aws_region}/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"

cat > /opt/cloudwatch-agent-config.json <<EOF
{
  "metrics": {
    "namespace": "${project_name}/app-server",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "totalcpu": true
      },
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/cloudwatch-agent-config.json
