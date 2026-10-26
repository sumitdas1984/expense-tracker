import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from category_service.main import app, get_db
from category_service.database import Base


# Create an in-memory test database
test_engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)

TestingSessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=test_engine,
)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture
def client():
    Base.metadata.create_all(bind=test_engine)
    app.dependency_overrides[get_db] = override_get_db

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=test_engine)


def test_create_category(client):
    response = client.post(
        "/categories",
        json={"name": "Food", "description": "Meals and groceries"},
    )

    assert response.status_code == 201
    assert response.json()["name"] == "Food"


def test_get_categories(client):
    client.post(
        "/categories",
        json={"name": "Food", "description": "Meals"},
    )

    response = client.get("/categories")

    assert response.status_code == 200
    assert len(response.json()) == 1


def test_get_category(client):
    create_response = client.post(
        "/categories",
        json={"name": "Travel", "description": "Transportation"},
    )
    category_id = create_response.json()["id"]

    response = client.get(f"/categories/{category_id}")

    assert response.status_code == 200
    assert response.json()["name"] == "Travel"


def test_get_nonexistent_category(client):
    response = client.get("/categories/999")

    assert response.status_code == 404


def test_update_category(client):
    create_response = client.post(
        "/categories",
        json={"name": "Food", "description": "Meals"},
    )
    category_id = create_response.json()["id"]

    response = client.put(
        f"/categories/{category_id}",
        json={"name": "Dining", "description": "Restaurant meals"},
    )

    assert response.status_code == 200
    assert response.json()["name"] == "Dining"


def test_update_nonexistent_category(client):
    response = client.put(
        "/categories/999",
        json={"name": "Dining", "description": "Restaurant meals"},
    )

    assert response.status_code == 404


def test_delete_category(client):
    create_response = client.post(
        "/categories",
        json={"name": "Shopping", "description": "Purchases"},
    )
    category_id = create_response.json()["id"]

    response = client.delete(f"/categories/{category_id}")

    assert response.status_code == 204

    get_response = client.get(f"/categories/{category_id}")
    assert get_response.status_code == 404


def test_delete_nonexistent_category(client):
    response = client.delete("/categories/999")

    assert response.status_code == 404


def test_create_duplicate_category(client):
    client.post(
        "/categories",
        json={"name": "Food", "description": "Meals"},
    )

    response = client.post(
        "/categories",
        json={"name": "Food", "description": "Food and groceries"},
    )

    assert response.status_code == 409
