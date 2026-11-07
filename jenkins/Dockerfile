# Imagen de Jenkins con las herramientas que el pipeline necesita ya
# instaladas (docker cliente, aws-cli, terraform). La imagen oficial
# jenkins/jenkins:lts solo trae el servidor Jenkins (Java); sin esto,
# habria que instalar estas herramientas a mano en cada contenedor
# nuevo, lo que no es reproducible. Se construye y se sube a ECR una
# sola vez (bootstrap manual, igual que infra/terraform-bootstrap), no
# en cada arranque de la instancia.
FROM jenkins/jenkins:lts

USER root

ARG TERRAFORM_VERSION=1.16.5

RUN apt-get update \
    && apt-get install -y --no-install-recommends docker.io docker-cli curl unzip python3 python3-venv \
    && curl -fsSL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && unzip -o /tmp/terraform.zip -d /usr/local/bin/ \
    && rm -f /tmp/terraform.zip \
    && curl -fsSL -o /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    && cd /tmp && unzip -q awscliv2.zip && ./aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
