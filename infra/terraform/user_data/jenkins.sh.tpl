#!/bin/bash
# user_data de jenkins-server: instala Docker en el host y arranca
# Jenkins en un contenedor de nuestra PROPIA imagen (ver jenkins/Dockerfile
# en la raiz del repo), ya subida a ECR con docker/aws-cli/terraform
# instalados -ver ARCHITECTURE.md, seccion "Runtime en AWS"-. Jenkins en
# si (plugins, jobs, credenciales) se configura a mano tras el primer
# arranque -> esto solo deja el contenedor corriendo.
#
# ${aws_region} y ${jenkins_ecr_repo_url} son variables de plantilla de
# Terraform (templatefile), sustituidas en el momento del apply; no son
# variables de shell.
set -euxo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user || true

aws ecr get-login-password --region ${aws_region} \
  | docker login --username AWS --password-stdin "${jenkins_ecr_repo_url}"

docker pull "${jenkins_ecr_repo_url}:latest"

docker volume create jenkins_home

# --group-add con el GID real del socket del host: el proceso de Jenkins
# dentro del contenedor corre como usuario no-root (jenkins); sin esto no
# tendria permiso para hablar con el Docker del host a traves del socket
# montado, y los `docker build`/`docker push` del pipeline fallarian.
docker run -d \
  --name jenkins \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 50000:50000 \
  --group-add "$(stat -c '%g' /var/run/docker.sock)" \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${jenkins_ecr_repo_url}:latest"
