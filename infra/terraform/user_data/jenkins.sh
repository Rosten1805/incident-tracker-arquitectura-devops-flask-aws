#!/bin/bash
# user_data de jenkins-server: instala Docker y arranca Jenkins en un
# contenedor. Jenkins en si (plugins, jobs, credenciales) se configura a
# mano tras el primer arranque -> esto solo deja el binario corriendo.
set -euxo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user || true

docker volume create jenkins_home

docker run -d \
  --name jenkins \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts
