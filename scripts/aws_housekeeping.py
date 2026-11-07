"""Script de automatizacion con boto3, independiente de la app Flask.

Dos tareas de "housekeeping" tipicas en una cuenta AWS real:

- backup:    saca un snapshot de los datos actuales de la app (via su propia
             API, a traves del ALB) y lo sube a S3 con un nombre con timestamp.
- report:    lista las instancias EC2 del proyecto (por tag Project) con su
             estado y cuanto tiempo llevan corriendo.
- stop-idle: de ese mismo listado, para las instancias que llevan corriendo
             mas de N horas. Por defecto es un dry-run (solo dice que pararia);
             hace falta --confirm para pararlas de verdad. Pensado para no
             agotar credito en la cuenta de estudiante sin querer.

Credenciales: usa la cadena de resolucion estandar de boto3 (variable de
entorno AWS_PROFILE, perfil por defecto, o el rol de la instancia si corre
dentro de AWS) - no hay nada de credenciales hardcodeado aqui.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import logging
import sys
import urllib.request

import boto3

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("aws_housekeeping")

PROJECT_TAG_VALUE = "task-tracker"


def list_project_instances(ec2_client, project: str = PROJECT_TAG_VALUE) -> list[dict]:
    """Devuelve las instancias EC2 etiquetadas con Project=<project>.

    No filtra por estado a proposito: una instancia parada tambien es
    informacion util en un reporte de housekeeping.
    """
    response = ec2_client.describe_instances(
        Filters=[{"Name": "tag:Project", "Values": [project]}]
    )

    instances = []
    now = dt.datetime.now(dt.timezone.utc)

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            tags = {t["Key"]: t["Value"] for t in instance.get("Tags", [])}
            launch_time = instance["LaunchTime"]
            running_hours = (now - launch_time).total_seconds() / 3600

            instances.append(
                {
                    "instance_id": instance["InstanceId"],
                    "name": tags.get("Name", "(sin tag Name)"),
                    "state": instance["State"]["Name"],
                    "instance_type": instance["InstanceType"],
                    "launch_time": launch_time.isoformat(),
                    "running_hours": round(running_hours, 1),
                }
            )

    return instances


def fetch_tasks_snapshot(alb_dns_name: str) -> dict:
    """Pide el listado actual de tareas a la propia API de la app (vía ALB).

    No lee la base de datos SQLite directamente (viviria en app-server, no
    aqui): usar la API es mas sencillo y no depende de como la app guarde
    sus datos por dentro.
    """
    url = f"http://{alb_dns_name}/tasks"
    with urllib.request.urlopen(url, timeout=10) as response:
        tasks = json.loads(response.read())

    return {
        "backed_up_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": url,
        "tasks": tasks,
    }


def upload_backup(s3_client, bucket: str, snapshot: dict) -> str:
    """Sube el snapshot a S3 con un nombre unico por timestamp y devuelve la key."""
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    key = f"backups/tasks-{timestamp}.json"

    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(snapshot, indent=2).encode("utf-8"),
        ContentType="application/json",
    )
    return key


def cmd_report(args: argparse.Namespace) -> int:
    ec2 = boto3.client("ec2", region_name=args.region)
    instances = list_project_instances(ec2, args.project)

    if not instances:
        logger.info("No hay instancias con tag Project=%s", args.project)
        return 0

    logger.info("Instancias del proyecto %s:", args.project)
    for i in instances:
        logger.info(
            "  %-20s %-12s %-9s %-10s %6.1fh corriendo",
            i["name"], i["instance_id"], i["state"], i["instance_type"], i["running_hours"],
        )
    return 0


def cmd_backup(args: argparse.Namespace) -> int:
    logger.info("Pidiendo snapshot de tareas a http://%s/tasks ...", args.alb_dns_name)
    snapshot = fetch_tasks_snapshot(args.alb_dns_name)
    logger.info("Snapshot con %d tareas", len(snapshot["tasks"]))

    s3 = boto3.client("s3", region_name=args.region)
    key = upload_backup(s3, args.bucket, snapshot)
    logger.info("Backup subido a s3://%s/%s", args.bucket, key)
    return 0


def cmd_stop_idle(args: argparse.Namespace) -> int:
    ec2 = boto3.client("ec2", region_name=args.region)
    instances = list_project_instances(ec2, args.project)

    candidates = [
        i for i in instances
        if i["state"] == "running" and i["running_hours"] >= args.max_hours
    ]

    if not candidates:
        logger.info(
            "Ninguna instancia running lleva >= %sh (umbral configurado).", args.max_hours
        )
        return 0

    for i in candidates:
        if args.confirm:
            logger.info("Parando %s (%s), %.1fh corriendo...", i["name"], i["instance_id"], i["running_hours"])
            ec2.stop_instances(InstanceIds=[i["instance_id"]])
        else:
            logger.info(
                "[DRY RUN] Pararia %s (%s), %.1fh corriendo. Repite con --confirm para pararla de verdad.",
                i["name"], i["instance_id"], i["running_hours"],
            )

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", default="eu-west-1")
    parser.add_argument("--project", default=PROJECT_TAG_VALUE, help="Valor del tag Project a filtrar")

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("report", help="Lista las instancias del proyecto y cuanto llevan corriendo")

    backup_parser = subparsers.add_parser("backup", help="Backup de los datos actuales de la app a S3")
    backup_parser.add_argument("--alb-dns-name", required=True, help="DNS name del ALB (output de Terraform)")
    backup_parser.add_argument("--bucket", required=True, help="Bucket S3 de backups (output de Terraform)")

    stop_parser = subparsers.add_parser("stop-idle", help="Para instancias que llevan corriendo demasiado tiempo")
    stop_parser.add_argument("--max-hours", type=float, default=4.0, help="Umbral en horas (por defecto 4)")
    stop_parser.add_argument("--confirm", action="store_true", help="Sin esto, solo simula (dry-run)")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    commands = {"report": cmd_report, "backup": cmd_backup, "stop-idle": cmd_stop_idle}
    return commands[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
