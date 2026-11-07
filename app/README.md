# Task / Incident Tracker — app

API REST mínima en Python 3.14 + Flask, con persistencia en SQLite. Es el
"pretexto" de este proyecto: la parte que importa de verdad es la
infraestructura y el pipeline CI/CD que la rodea (ver `../docs/ARCHITECTURE.md`).

## Endpoints

| Método | Ruta           | Descripción                                   |
|--------|----------------|------------------------------------------------|
| GET    | `/health`      | Health check (usado por el ALB)                |
| GET    | `/version`     | Commit SHA de la imagen en ejecución (`GIT_SHA`) |
| POST   | `/tasks`       | Crea una tarea/incidencia                      |
| GET    | `/tasks`       | Lista todas las tareas                         |
| GET    | `/tasks/<id>`  | Devuelve una tarea por id (404 si no existe)   |
| DELETE | `/tasks/<id>`  | Elimina una tarea por id (404 si no existe)     |

## Correr en local

Requiere Python 3.14. En Windows, si el `python` por defecto apunta a otra
versión, usa el lanzador `py -3.14`.

```powershell
py -3.14 -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

La app arranca en `http://localhost:5000` y crea un fichero `tasks.db`
(SQLite) en el directorio actual. Puedes cambiar la ruta de la base de datos
con la variable de entorno `DB_PATH`.

Ejemplo de uso:

```powershell
curl http://localhost:5000/health
curl -X POST http://localhost:5000/tasks -H "Content-Type: application/json" -d "{\"title\": \"Disk almost full\"}"
curl http://localhost:5000/tasks
```

## Tests

```powershell
pip install -r requirements-dev.txt
pytest
```

Con cobertura:

```powershell
pytest --cov=app --cov-report=term-missing
```

## Decisiones de diseño (resumen)

- **SQLite vía `sqlite3` (stdlib)** en vez de un ORM: para 4 endpoints CRUD
  un ORM añade dependencias y una capa de abstracción que no hace falta.
  SQL directo es más fácil de leer y de explicar.
- **Logging a stdout**: Docker ya redirige stdout/stderr del contenedor por
  defecto, así que basta con configurar el CloudWatch Agent en la instancia
  EC2 para recoger esos logs, sin tocar la app.
- **`GIT_SHA` como variable de entorno**: se inyecta en build time desde el
  Dockerfile (`--build-arg GIT_SHA=<sha>`). El endpoint `/version` la expone
  para que el pipeline pueda hacer un smoke test después del despliegue y
  confirmar que el commit desplegado es el esperado.
