# AGILE.md — SDLC y metodología aplicada a este proyecto

> Este documento no es teoría de Scrum copiada de un manual: usa el propio desarrollo de este proyecto (jueves → lunes) como ejemplo real de sprint, con sus impedimentos reales incluidos. Es la mejor forma de defender en la entrevista que entiendo Agile aplicado a trabajo de DevOps, no solo de memoria.

## 1. Estrategia de ramas

**Trunk-based development**: `main` siempre debe quedar en estado desplegable. Cambios en ramas `feature/<nombre>` cortas, con Pull Request antes de integrar a `main`.

- El pipeline de Jenkins (`Jenkinsfile`) actúa como **gate de calidad automático**: si los tests (`pytest`) fallan, el pipeline se detiene antes de construir ninguna imagen — no hay despliegue posible con tests en rojo.
- **Nota honesta para la entrevista**: en este proyecto, al trabajar en solitario y con el tiempo limitado, el pipeline se dispara sobre `main` directamente en vez de sobre cada Pull Request. En un equipo real, lo correcto sería disparar el pipeline (al menos los stages de tests) también en cada PR, antes de mergear — lo documento aquí como la mejora obvia si este fuera un repo de equipo.

## 2. Definition of Done

Un cambio no se considera terminado hasta que:

- [ ] El código tiene tests y pasan en verde (`pytest`, tanto en `app/` como en `scripts/`)
- [ ] El pipeline de Jenkins corre en verde de principio a fin (build → push → deploy → smoke test)
- [ ] `docs/ARCHITECTURE.md` refleja la decisión tomada, si el cambio afecta a arquitectura (no se documenta al final, se documenta *mientras* se decide)
- [ ] No hay secretos, credenciales ni IDs de cuenta hardcodeados en el código versionado
- [ ] Si el cambio toca Terraform: `terraform plan` se ha revisado antes de `apply`, nunca a ciegas

## 3. Sprint de ejemplo: este mismo proyecto

**Sprint goal**: construir un proyecto completo de AWS DevOps (app + Docker + Terraform + Jenkins/CI-CD + script Python) para defenderlo en una entrevista técnica, de jueves a lunes.

| Día | Qué se entregó | Impedimentos reales que surgieron (y cómo se resolvieron) |
|---|---|---|
| Jueves | App Flask + tests + Dockerfile, contenerizada | Permisos de usuario no-root en Docker rompían la escritura de SQLite (`WORKDIR` creado como root antes del `USER`) → fijado con `chown` explícito |
| Viernes | Terraform completo aplicado: IAM, red, ALB, 2 EC2, ECR, S3, CloudWatch | Restricción real de la cuenta de estudiante (`iam:CreateRole` exige `permissions_boundary` + prefijo `student-`); problema de huevo-y-gallina del backend S3 de Terraform (resuelto con un módulo de bootstrap aparte, con estado local) |
| Sábado | Jenkins operativo + imagen propia con `docker`/`aws-cli`/`terraform` + `Jenkinsfile` con pipeline completo en verde | La imagen de Jenkins se construyó dos veces: primero se nos olvidó el paquete `docker-cli` (Debian lo separa de `docker.io`); después, la política IAM de `ssm:SendCommand` fallaba por combinar dos recursos distintos (documento + instancia) en un único statement con una sola condición — exactamente el tipo de bug que solo se ve corriendo el pipeline de verdad, no leyendo el código |
| Domingo (hoy) | Script Python/boto3 (`scripts/aws_housekeeping.py`) con tests (`moto`) + `docs/AGILE.md` | — |
| Lunes | Repaso final antes de la entrevista | — |

**Por qué esto es una buena respuesta de entrevista**: cada "impedimento" de la tabla es justo lo que en una daily de Scrum real se reportaría como bloqueo — y la solución a cada uno no fue "lo intento otra vez", sino diagnosticar la causa raíz (un permiso real de AWS, un paquete de Debian, una regla de evaluación de IAM) antes de aplicar el fix. Eso es lo que se busca en un perfil DevOps, no solo saber la sintaxis de Terraform de memoria.

## 4. Cómo este proyecto cubre el ciclo de vida completo (SDLC)

- **Control de versiones**: Git + GitHub, historial de commits real (no un único commit "proyecto completo")
- **Integración/entrega continua**: Jenkins, pipeline como código (`Jenkinsfile`), sin pasos manuales de despliegue
- **Infraestructura como código**: Terraform versionado, `plan` revisado antes de `apply` siempre
- **Testing**: `pytest` (app, 98% cobertura) y `moto` (script, simula AWS sin tocar la cuenta real)
- **Documentación viva**: `docs/ARCHITECTURE.md` se actualizó en cada decisión de diseño tomada durante el propio desarrollo, no se escribió de golpe al final
- **Observabilidad**: CloudWatch (logs, dashboard, alarma de CPU)
