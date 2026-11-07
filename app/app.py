"""Task / Incident Tracker API.

API REST mínima, pensada como "pretexto" para un ejercicio de DevOps en AWS:
lo importante aquí es que la app sea sencilla, fiable y fácil de explicar en
una entrevista, no que tenga funcionalidades avanzadas.

Decisiones de diseño (comentadas aquí para poder justificarlas en la
entrevista sin tener que rebuscar en el código):

- Persistencia: se usa `sqlite3` de la librería estándar en vez de
  flask-sqlalchemy. Para un CRUD de 4 endpoints no aporta nada un ORM
  (más dependencias, más superficie, más cosas que explicar) y usar SQL
  directo deja ver claramente qué hace la app, que es justo lo que interesa
  en este proyecto (el foco es la infra, no la app).
- Logging: se usa el módulo `logging` estándar configurado para escribir en
  stdout con un formato simple. Así el CloudWatch Agent, en EC2, puede
  recoger los logs del contenedor Docker sin configuración adicional: basta
  con que Docker los mande a stdout/stderr (comportamiento por defecto) y
  que el CloudWatch Agent tenga configurado el log group correspondiente.
- /version lee la variable de entorno GIT_SHA, que se inyecta en build time
  vía `--build-arg` en el Dockerfile. Esto permite que el pipeline de CI/CD
  verifique, después del despliegue, que el commit SHA desplegado es el que
  se esperaba (smoke test del Jenkinsfile).
"""

from __future__ import annotations

import logging
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any

from flask import Flask, Response, g, jsonify, request

# --- Configuración básica ---------------------------------------------------

DB_PATH = Path(os.environ.get("DB_PATH", "tasks.db"))
VALID_STATUSES = {"open", "in_progress", "closed"}
DEFAULT_STATUS = "open"

# Logging estructurado a stdout: formato simple, una línea por evento, para
# que sea fácil de parsear más adelante desde CloudWatch Logs Insights.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s level=%(levelname)s logger=%(name)s msg=%(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("task_tracker")

app = Flask(__name__)


# --- Acceso a la base de datos ----------------------------------------------


def get_db() -> sqlite3.Connection:
    """Devuelve una conexión SQLite por petición, reutilizando `flask.g`.

    Flask crea y destruye el contexto de aplicación en cada request, así que
    guardar la conexión en `g` evita abrir una conexión nueva en cada
    consulta dentro de la misma petición sin necesidad de un pool (SQLite,
    al ser un fichero local de un solo proceso, no lo necesita).
    """
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(exception: BaseException | None = None) -> None:
    """Cierra la conexión SQLite al terminar la petición."""
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db() -> None:
    """Crea la tabla `tasks` si no existe. Se ejecuta al arrancar la app."""
    connection = sqlite3.connect(DB_PATH)
    try:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'open'
            )
            """
        )
        connection.commit()
    finally:
        connection.close()


def row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    """Convierte una fila SQLite en un diccionario serializable a JSON."""
    return {
        "id": row["id"],
        "title": row["title"],
        "description": row["description"],
        "status": row["status"],
    }


# --- Endpoints ---------------------------------------------------------------


@app.get("/")
def index() -> Response:
    """Sirve el frontend estático (solo demo visual, no forma parte de la API)."""
    return app.send_static_file("index.html")


@app.get("/health")
def health() -> tuple[Response, int]:
    """Health check usado por el health check del ALB."""
    return jsonify({"status": "ok"}), 200


@app.get("/version")
def version() -> tuple[Response, int]:
    """Devuelve el commit SHA de la imagen en ejecución.

    El valor se lee de la variable de entorno GIT_SHA, inyectada en build
    time desde el Dockerfile. Si no está definida (p. ej. ejecución local
    fuera de Docker) se devuelve "dev" como fallback.
    """
    git_sha = os.environ.get("GIT_SHA", "dev")
    return jsonify({"git_sha": git_sha}), 200


@app.post("/tasks")
def create_task() -> tuple[Response, int]:
    """Crea una tarea/incidencia.

    Espera un JSON con:
      - title (str, obligatorio)
      - description (str, opcional, por defecto "")
      - status (str, opcional, uno de "open" / "in_progress" / "closed",
        por defecto "open")
    """
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        logger.warning("create_task rejected: invalid JSON body")
        return jsonify({"error": "request body must be a JSON object"}), 400

    title = payload.get("title")
    if not isinstance(title, str) or not title.strip():
        logger.warning("create_task rejected: missing or invalid title")
        return jsonify({"error": "'title' is required and must be a non-empty string"}), 400

    description = payload.get("description", "")
    if not isinstance(description, str):
        return jsonify({"error": "'description' must be a string"}), 400

    status = payload.get("status", DEFAULT_STATUS)
    if status not in VALID_STATUSES:
        return jsonify(
            {"error": f"'status' must be one of {sorted(VALID_STATUSES)}"}
        ), 400

    db = get_db()
    cursor = db.execute(
        "INSERT INTO tasks (title, description, status) VALUES (?, ?, ?)",
        (title.strip(), description, status),
    )
    db.commit()
    task_id = cursor.lastrowid

    logger.info("task created id=%s title=%r status=%s", task_id, title, status)

    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    return jsonify(row_to_dict(row)), 201


@app.get("/tasks")
def list_tasks() -> tuple[Response, int]:
    """Lista todas las tareas/incidencias."""
    db = get_db()
    rows = db.execute("SELECT * FROM tasks ORDER BY id").fetchall()
    return jsonify([row_to_dict(row) for row in rows]), 200


@app.get("/tasks/<int:task_id>")
def get_task(task_id: int) -> tuple[Response, int]:
    """Devuelve una tarea/incidencia por id, o 404 si no existe."""
    db = get_db()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        logger.info("task not found id=%s", task_id)
        return jsonify({"error": f"task {task_id} not found"}), 404
    return jsonify(row_to_dict(row)), 200


@app.delete("/tasks/<int:task_id>")
def delete_task(task_id: int) -> tuple[Response, int]:
    """Elimina una tarea/incidencia por id, o 404 si no existe."""
    db = get_db()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        logger.info("delete rejected, task not found id=%s", task_id)
        return jsonify({"error": f"task {task_id} not found"}), 404

    db.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
    db.commit()
    logger.info("task deleted id=%s", task_id)
    return jsonify({"deleted": task_id}), 200


# Crear el esquema en import time, para que funcione tanto con `python app.py`
# como al servir la app con un WSGI server (p. ej. gunicorn) en Docker.
init_db()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)  # noqa: S104 - contenedor Docker, no host dev
