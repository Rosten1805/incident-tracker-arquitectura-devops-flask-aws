# ARCHITECTURE.md — Especificación del proyecto "Task / Incident Tracker"

> Documento de referencia para la entrevista de **AWS DevOps Engineer** (Social You, lunes). Consolida las decisiones de arquitectura tomadas durante la preparación, incluidas las correcciones tras revisión.

## 1. La aplicación

API REST mínima de gestión de incidencias ("Task / Incident Tracker"), elegida como pretexto temático DevOps. Deliberadamente simple para poder dedicar el tiempo de estudio a lo que rodea la app, no a la app en sí.

- **Stack**: Python 3.14 + Flask
- **Persistencia**: SQLite local (sin dependencias externas)
- **Endpoints**:
  - `GET /health` — health check (usado por el ALB)
  - `GET /version` — devuelve el commit SHA con el que se construyó la imagen en ejecución
  - `POST /tasks`, `GET /tasks`, `GET /tasks/<id>`, `DELETE /tasks/<id>` — CRUD mínimo
- **Tests**: pytest + coverage
- **Empaquetado**: Dockerfile de **una sola etapa** (se evaluó multi-stage y se descartó conscientemente: las dependencias — Flask, Gunicorn — son Python puro sin compilación nativa, así que un segundo stage no reduce tamaño real; se reserva para dependencias con compilación nativa). Usuario no-root, Gunicorn como servidor WSGI, `GIT_SHA` como build-arg

## 2. Stack completo por capas

| Capa | Herramienta | Requisito de la oferta |
|---|---|---|
| Código | Python 3.14 + Flask | Imprescindible (Python) |
| Tests | pytest + coverage | Gate de calidad del pipeline |
| Empaquetado | Docker (una sola etapa, justificado) | — |
| Control de versiones | Git + GitHub (feature branches + PR) | SDLC/Agile |
| CI/CD | Jenkins, corriendo en su propia EC2 | Imprescindible |
| IaC | Terraform (estado local) | Valorable |
| Cloud | AWS: EC2, VPC/Subnets, Security Groups, ALB, ECR, S3, CloudWatch, SSM | Imprescindible |
| Observabilidad | CloudWatch Agent + Dashboard + Alarmas | Valorable |
| Gestión de secretos | Jenkins Credentials (pipeline); Secrets Manager documentado pero no implementado en v1 | — |
| Automatización | Python + boto3 (script independiente de la app) | Imprescindible (scripting) |

## 3. Arquitectura (ver diagrama `Arquitectura DevOps Flask en AWS.png`)

**Flujo de CI/CD (Jenkinsfile, 10 stages):**
1. Checkout del código desde GitHub
2. Instalar dependencias / preparar entorno de build
3. Tests unitarios con pytest + coverage (gate de calidad)
4. Build de imagen Docker
5. Etiquetar la imagen con `<commit-sha>` y `latest`
6. Login y push a Amazon ECR (desde el rol de `jenkins-server`, que tiene permiso de escritura)
7. `terraform plan` / `apply` (crear o actualizar infraestructura)
8. Desplegar la nueva versión en el `app-server` vía **AWS Systems Manager Run Command**
9. Smoke test: `GET /health` y `GET /version` a través del ALB, verificando que el SHA desplegado es el esperado
10. Si falla: rollback automático a la última imagen estable etiquetada en ECR

**Runtime en AWS:**
- **ALB** (Application Load Balancer) — en ≥2 subredes de AZs distintas (requisito de AWS para crear un ALB), balanceo + health check `/health`, único listener HTTP:80 (sin TLS — necesitaría dominio propio + ACM, fuera de alcance para esta demo)
- **EC2 `app-server`** (subred pública) — Docker + Flask + SQLite + CloudWatch Agent, Security Group solo acepta el puerto de la app desde el SG del ALB; **sin puerto 22** (acceso a shell vía SSM Session Manager, no SSH)
- **EC2 `jenkins-server`** — Jenkins corriendo en Docker, puerto 8080 abierto solo a mi IP; **sin puerto 22** (SSM Session Manager también aquí)
- **Amazon ECR** — registro de imágenes, tags por commit SHA (permite rollback a versión anterior)
- **Amazon S3** — un único bucket, usado solo por el script Python de housekeeping (backups), **no** como backend de Terraform (ver sección 5)
- **AWS Systems Manager (SSM)** — despliegue remoto y administración de ambas instancias sin SSH
- **CloudWatch** — logs, métricas, dashboard, alarmas (p. ej. CPU alta, fallo de health check)

## 4. Restricciones reales de la cuenta AWS (verificadas, no teóricas)

Cuenta: AWS IAM Identity Center / SSO, rol `AWSReservedSSO_StudentLabAccess`, región `eu-west-1`.

**Hallazgo clave**: `iam:CreateRole` está denegado salvo que el rol creado:
1. Tenga como **permissions boundary** la política gestionada `StudentBoundary` (ARN: `arn:aws:iam::921049725767:policy/StudentBoundary`)
2. Tenga un **nombre que empiece por `student`** (ej. `student-app-ec2-role`) — es además el único prefijo para el que `iam:PassRole` está permitido

Contenido de `StudentBoundary` (el techo máximo de permisos de cualquier rol creado por la alumna):
- `AllowAllButIdentityAndAccountAdmin`: permite **todas** las acciones excepto `iam:*`, `organizations:*`, `account:*`
- `AllowReadIam`: permite `iam:Get*` / `iam:List*` (solo lectura de IAM)
- `AllowPassStudentRoles`: `iam:PassRole` solo sobre `role/student*`
- `AllowServiceLinkedRoles`: `iam:CreateServiceLinkedRole` sin restricción (el rol vinculado a servicio que necesita el ALB se crea sin problema)

**Consecuencia para Terraform**: cualquier `aws_iam_role` que creemos debe incluir `permissions_boundary` apuntando a esa política y `name` con prefijo `student-`. Esto permite crear **varios roles distintos** (uno por instancia, ver sección 5) sin perder mínimo privilegio.

**Pendiente de verificar** (no confirmado todavía, es un permiso de usuario distinto al de los roles):
- Permisos de ECR a nivel de usuario `estudiante` (`aws ecr describe-repositories --profile estudiante --region eu-west-1`) — si falla con `AccessDenied`, plan B: Docker Hub en vez de ECR.
- Creación real del Service-Linked Role del ALB al desplegar Terraform (debería funcionar según `AllowServiceLinkedRoles`, pero no se ha probado aún).

## 5. Decisiones de Terraform (tras revisión antes de generar el código)

- **Backend S3 real, bootstrapeado por separado.** Terraform no puede usar como backend un bucket que el propio `apply` principal va a crear (problema de huevo y gallina: `terraform init` necesita que el backend ya exista). Solución: un Terraform **independiente y mínimo** en `infra/terraform-bootstrap/` crea el bucket S3 (versionado + cifrado + acceso público bloqueado) y una tabla DynamoDB para *state locking*. Ese bootstrap usa **estado local a propósito** (es una pieza de infraestructura que se aplica una vez y casi nunca cambia — es la única excepción deliberada). El Terraform principal (`infra/terraform/`) usa ese bucket como backend remoto, configurado vía `-backend-config` (no se hardcodea el nombre del bucket en ficheros versionados). *Respuesta de entrevista: "separo el bootstrap del backend del resto de la infraestructura porque no se puede depender circularmente de un recurso que aún no existe — es un patrón estándar en Terraform, no una ocurrencia mía."*
- **Dos roles IAM, no uno compartido**: `student-jenkins-ec2-role` (SSM + permiso de *escritura* en ECR) y `student-app-ec2-role` (SSM + permiso de *lectura* en ECR + envío de logs/métricas a CloudWatch). Mínimo privilegio real, no solo de palabra.
- **Sin puerto 22 en ningún Security Group.** Con SSM Session Manager ya disponible (por el rol), abrir SSH no aporta nada y sí añade superficie de ataque.
- **ALB en ≥2 subredes de AZs distintas** — requisito técnico de AWS para crear el ALB, se seleccionan explícitamente de la VPC por defecto.
- **Secuencia de aplicación**: el código se genera primero; se revisa `terraform plan` + coste aproximado + permisos efectivos; solo entonces se ejecuta `apply`. Nunca `apply` a ciegas.
- **Outputs**: el ALB expone un **DNS name**, no una IP fija — así se documenta en `outputs.tf`.
- **Disciplina de coste**: 2 EC2 + ALB + CloudWatch generan coste aunque no haya tráfico. `terraform destroy` al final de cada sesión de estudio.

## 6. Gestión de secretos

**Principio**: ningún secreto vive en el código ni en el repo.

| Secreto | Dónde vive | Cómo se accede |
|---|---|---|
| Credenciales AWS de Jenkins | Jenkins Credentials Plugin (cifrado en disco) | `withCredentials([...])` en el `Jenkinsfile`, nunca en texto plano |
| Variables de desarrollo local | `.env` (no versionado) | `.env.example` sí versionado como plantilla |
| Secretos de runtime de la app (futuro) | AWS Secrets Manager — **no implementado en v1**, la app no tiene secretos reales que guardar todavía | Se documenta aquí como la solución correcta si la app llegase a necesitar, p. ej., una contraseña de base de datos |

En producción real (sin las restricciones de la cuenta de estudiante) esto se simplificaría usando un **IAM Role de instancia con least privilege** en vez de credenciales estáticas — distinción que se documenta aquí para poder explicarla en la entrevista.

## 7. Prácticas de "producción" aplicadas

- Trunk-based development: ramas `feature/*` cortas, PR obligatoria antes de `main`, el pipeline de Jenkins como gate (no se despliega si fallan los tests)
- Imágenes inmutables: cada build se etiqueta con el commit SHA; nunca se despliega `latest` a ciegas
- `terraform plan` siempre se revisa antes de `apply`
- Variables de Terraform (`terraform.tfvars`) para poder escalar a varios entornos sin reescribir código
- Logs centralizados en CloudWatch en vez de en la terminal de la instancia
- Tagging de todo recurso (`Project`, `Owner`, `Environment`) — control de coste y input para el script de housekeeping en Python
- Rollback simple: se conserva la imagen anterior en ECR para poder volver atrás sin reconstruir

## 8. Disponibilidad: qué es esto y qué no es

Esta arquitectura (una EC2 por rol, sin Auto Scaling) es un **punto único de fallo real**: si `app-server` se cae, el ALB no tiene a dónde más enviar tráfico. Es una decisión de alcance consciente, no un descuido — construir Auto Scaling + multi-AZ + despliegue rolling es trabajo real que no cabe en el tiempo disponible, y no es necesario para demostrar el patrón completo (Terraform, CI/CD, IAM, Docker, ECR, monitorización).

**Respuesta de entrevista si preguntan "¿esto serviría en producción tal cual?"**: *"Para una app interna pequeña que tolere alguna interrupción, sí. Para algo con requisitos reales de alta disponibilidad, esto es la v1 que demuestra el patrón; la v2 añadiría un Auto Scaling Group con mínimo 2 instancias en 2 AZs distintas detrás del mismo ALB, y un despliegue rolling (desregistrar del target group → actualizar contenedor → volver a registrar, una instancia cada vez) para no tener cortes de servicio."*

## 9. Plan B (si algún permiso de usuario, no de rol, resulta bloqueado)

| Componente ideal | Alternativa si falla |
|---|---|
| Amazon ECR | Docker Hub (repo público) |
| Despliegue vía SSM Run Command | SSH desde Jenkins con clave `.pem` guardada en Jenkins Credentials (reabriría el puerto 22 solo como fallback) |
| ALB | Exponer el `app-server` directamente (Security Group abierto solo al puerto de la app) |
