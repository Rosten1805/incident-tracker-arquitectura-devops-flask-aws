"""Tests for the Task / Incident Tracker API.

Cada test usa una base de datos SQLite temporal distinta (fixture `client`),
para que los tests no compartan estado entre sí y se puedan ejecutar en
cualquier orden.
"""

from __future__ import annotations

import importlib
from collections.abc import Iterator
from pathlib import Path

import pytest
from flask.testing import FlaskClient


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[FlaskClient]:
    """Crea un cliente de test con una base de datos SQLite aislada.

    `app.py` crea la conexión a partir de la variable de entorno DB_PATH y
    construye el esquema en import time, así que la variable debe fijarse
    antes de (re)importar el módulo.
    """
    db_path = tmp_path / "test_tasks.db"
    monkeypatch.setenv("DB_PATH", str(db_path))

    import app as app_module

    importlib.reload(app_module)

    app_module.app.testing = True
    with app_module.app.test_client() as test_client:
        yield test_client


def test_health_returns_ok(client: FlaskClient) -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_version_defaults_to_dev_when_git_sha_not_set(
    client: FlaskClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("GIT_SHA", raising=False)

    response = client.get("/version")

    assert response.status_code == 200
    assert response.get_json() == {"git_sha": "dev"}


def test_version_returns_git_sha_env_var(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test_tasks.db"))
    monkeypatch.setenv("GIT_SHA", "abc1234")

    import app as app_module

    importlib.reload(app_module)

    with app_module.app.test_client() as test_client:
        response = test_client.get("/version")

    assert response.status_code == 200
    assert response.get_json() == {"git_sha": "abc1234"}


def test_create_task_returns_201_with_created_task(client: FlaskClient) -> None:
    response = client.post(
        "/tasks",
        json={"title": "Disk almost full", "description": "root volume at 90%"},
    )

    assert response.status_code == 201
    body = response.get_json()
    assert body["id"] == 1
    assert body["title"] == "Disk almost full"
    assert body["description"] == "root volume at 90%"
    assert body["status"] == "open"


def test_create_task_defaults_description_and_status(client: FlaskClient) -> None:
    response = client.post("/tasks", json={"title": "Review PR"})

    assert response.status_code == 201
    body = response.get_json()
    assert body["description"] == ""
    assert body["status"] == "open"


def test_create_task_without_title_returns_400(client: FlaskClient) -> None:
    response = client.post("/tasks", json={"description": "no title here"})

    assert response.status_code == 400
    assert "error" in response.get_json()


def test_create_task_with_blank_title_returns_400(client: FlaskClient) -> None:
    response = client.post("/tasks", json={"title": "   "})

    assert response.status_code == 400


def test_create_task_with_invalid_status_returns_400(client: FlaskClient) -> None:
    response = client.post(
        "/tasks", json={"title": "Bad status", "status": "not_a_real_status"}
    )

    assert response.status_code == 400


def test_create_task_without_json_body_returns_400(client: FlaskClient) -> None:
    response = client.post("/tasks", data="not json", content_type="text/plain")

    assert response.status_code == 400


def test_list_tasks_empty(client: FlaskClient) -> None:
    response = client.get("/tasks")

    assert response.status_code == 200
    assert response.get_json() == []


def test_list_tasks_returns_all_created_tasks(client: FlaskClient) -> None:
    client.post("/tasks", json={"title": "Task 1"})
    client.post("/tasks", json={"title": "Task 2"})

    response = client.get("/tasks")

    assert response.status_code == 200
    body = response.get_json()
    assert len(body) == 2
    assert [task["title"] for task in body] == ["Task 1", "Task 2"]


def test_get_task_returns_single_task(client: FlaskClient) -> None:
    create_response = client.post("/tasks", json={"title": "Find me"})
    task_id = create_response.get_json()["id"]

    response = client.get(f"/tasks/{task_id}")

    assert response.status_code == 200
    assert response.get_json()["title"] == "Find me"


def test_get_nonexistent_task_returns_404(client: FlaskClient) -> None:
    response = client.get("/tasks/999")

    assert response.status_code == 404
    assert "error" in response.get_json()


def test_delete_task_removes_it(client: FlaskClient) -> None:
    create_response = client.post("/tasks", json={"title": "Delete me"})
    task_id = create_response.get_json()["id"]

    delete_response = client.delete(f"/tasks/{task_id}")
    assert delete_response.status_code == 200
    assert delete_response.get_json() == {"deleted": task_id}

    get_response = client.get(f"/tasks/{task_id}")
    assert get_response.status_code == 404


def test_delete_nonexistent_task_returns_404(client: FlaskClient) -> None:
    response = client.delete("/tasks/999")

    assert response.status_code == 404
    assert "error" in response.get_json()
