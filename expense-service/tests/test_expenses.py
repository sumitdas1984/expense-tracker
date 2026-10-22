import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from main import app, get_db
from database import Base

# Create an isolated test database in memory
TEST_DATABASE_URL = "sqlite://"

test_engine = create_engine(
    TEST_DATABASE_URL,
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


def test_create_expense(client):
    response = client.post(
        "/expenses",
        json={
            "amount": 500,
            "category_id": 1,
            "description": "Dinner",
            "expense_date": "2026-10-22",
        },
    )

    assert response.status_code == 201
    assert response.json()["amount"] == 500
    assert response.json()["description"] == "Dinner"


def test_get_expenses(client):
    client.post(
        "/expenses",
        json={
            "amount": 500,
            "category_id": 1,
            "description": "Dinner",
            "expense_date": "2026-10-22",
        },
    )

    response = client.get("/expenses")

    assert response.status_code == 200
    assert len(response.json()) == 1
    assert response.json()[0]["amount"] == 500
    assert response.json()[0]["description"] == "Dinner"
    assert response.json()[0]["category_id"] == 1
    assert response.json()[0]["expense_date"] == "2026-10-22"


def test_delete_expense(client):
    response = client.post(
        "/expenses",
        json={
            "amount": 500,
            "category_id": 1,
            "description": "Dinner",
            "expense_date": "2026-10-22",
        },
    )
    expense_id = response.json()["id"]

    delete_response = client.delete(f"/expenses/{expense_id}")
    assert delete_response.status_code == 204

    get_response = client.get(f"/expenses/{expense_id}")
    assert get_response.status_code == 404
    assert get_response.json()["detail"] == "Expense not found"

def test_update_expense(client):
    response = client.post(
        "/expenses",
        json={
            "amount": 500,
            "category_id": 1,
            "description": "Dinner",
            "expense_date": "2026-10-22",
        },
    )
    expense_id = response.json()["id"]

    update_response = client.put(
        f"/expenses/{expense_id}",
        json={
            "amount": 600,
            "category_id": 1,
            "description": "Lunch",
            "expense_date": "2026-10-23",
        },
    )
    assert update_response.status_code == 200
    assert update_response.json()["amount"] == 600
    assert update_response.json()["description"] == "Lunch"
    assert update_response.json()["expense_date"] == "2026-10-23"
    assert update_response.json()["category_id"] == 1


def test_get_expense_by_id(client):
    response = client.post(
        "/expenses",
        json={
            "amount": 500,
            "category_id": 1,
            "description": "Dinner",
            "expense_date": "2026-10-22",
        },
    )
    expense_id = response.json()["id"]

    get_response = client.get(f"/expenses/{expense_id}")
    assert get_response.status_code == 200
    assert get_response.json()["amount"] == 500
    assert get_response.json()["description"] == "Dinner"
    assert get_response.json()["category_id"] == 1
    assert get_response.json()["expense_date"] == "2026-10-22"
    assert get_response.json()["id"] == expense_id