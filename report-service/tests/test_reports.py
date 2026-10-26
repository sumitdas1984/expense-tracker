import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import respx
from fastapi.testclient import TestClient
from httpx import Response

from report_service.main import app


client = TestClient(app)


@respx.mock
def test_monthly_report():
    respx.get("http://localhost:8001/expenses").mock(
        return_value=Response(
            200,
            json=[
                {"id": 1, "amount": 500, "category_id": 1,
                 "description": "Dinner", "expense_date": "2026-10-22"},
                {"id": 2, "amount": 300, "category_id": 1,
                 "description": "Breakfast", "expense_date": "2026-10-23"},
            ],
        )
    )

    response = client.get("/reports/monthly?year=2026&month=10")

    assert response.status_code == 200
    assert response.json()["total_expenses"] == 800
    assert response.json()["expense_count"] == 2


@respx.mock
def test_category_wise_report():
    respx.get("http://localhost:8001/expenses").mock(
        return_value=Response(
            200,
            json=[
                {"id": 1, "amount": 500, "category_id": 1,
                 "description": "Dinner", "expense_date": "2026-10-22"},
                {"id": 2, "amount": 300, "category_id": 1,
                 "description": "Breakfast", "expense_date": "2026-10-23"},
                {"id": 3, "amount": 1200, "category_id": 2,
                 "description": "Taxi", "expense_date": "2026-10-22"},
            ],
        )
    )

    respx.get("http://localhost:8002/categories").mock(
        return_value=Response(
            200,
            json=[
                {"id": 1, "name": "Food", "description": None},
                {"id": 2, "name": "Travel", "description": None},
            ],
        )
    )

    response = client.get("/reports/category-wise?year=2026&month=10")

    assert response.status_code == 200

    categories = {
        item["category"]: item
        for item in response.json()["categories"]
    }

    assert categories["Food"]["total_amount"] == 800
    assert categories["Food"]["expense_count"] == 2
    assert categories["Travel"]["total_amount"] == 1200
    assert categories["Travel"]["expense_count"] == 1


@respx.mock
def test_monthly_report_returns_502_when_expense_service_fails():
    respx.get("http://localhost:8001/expenses").mock(
        return_value=Response(503)
    )

    response = client.get("/reports/monthly?year=2026&month=10")

    assert response.status_code == 502


@respx.mock
def test_category_report_returns_502_when_category_service_fails():
    respx.get("http://localhost:8001/expenses").mock(
        return_value=Response(
            200,
            json=[
                {"id": 1, "amount": 500, "category_id": 1,
                 "description": "Dinner", "expense_date": "2026-10-22"},
            ],
        )
    )

    respx.get("http://localhost:8002/categories").mock(
        return_value=Response(503)
    )

    response = client.get("/reports/category-wise?year=2026&month=10")

    assert response.status_code == 502