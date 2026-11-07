#!/bin/bash
# user_data de app-server: instala Docker y el CloudWatch Agent.
# El contenedor de la app NO se arranca aqui: lo despliega Jenkins despues,
# vía SSM Run Command, tras hacer login/pull de ECR (ver ARCHITECTURE.md,
# flujo de CI/CD, paso 8).
#
# ${aws_region} y ${log_group} son variables de plantilla de Terraform
# (templatefile), sustituidas en el momento del apply; no son variables
# de shell.
set -euxo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user || true

mkdir -p /var/log/app

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
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "${log_group}",
            "log_stream_name": "{instance_id}",
            "region": "${aws_region}"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/cloudwatch-agent-config.json
