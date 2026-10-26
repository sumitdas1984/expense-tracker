from datetime import date

import httpx
from fastapi import FastAPI, HTTPException, Query

app = FastAPI(title="Report Service")

EXPENSE_SERVICE_URL = "http://localhost:8001"
CATEGORY_SERVICE_URL = "http://localhost:8002"

@app.get("/reports/monthly")
async def monthly_report(
    year: int = Query(ge=2000, le=2100),
    month: int = Query(ge=1, le=12),
):
    start_date = date(year, month, 1)

    if month == 12:
        end_date = date(year + 1, 1, 1)
    else:
        end_date = date(year, month + 1, 1)

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{EXPENSE_SERVICE_URL}/expenses",
                params={
                    "start_date": start_date.isoformat(),
                    "end_date": (
                        end_date - __import__("datetime").timedelta(days=1)
                    ).isoformat(),
                    "skip": 0,
                    "limit": 100,
                },
                timeout=10.0,
            )
            response.raise_for_status()
            expenses = response.json()

    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail="Unable to retrieve expenses from Expense Service",
        ) from exc

    total = sum(expense["amount"] for expense in expenses)

    return {
        "year": year,
        "month": month,
        "total_expenses": round(total, 2),
        "expense_count": len(expenses),
    }


@app.get("/reports/category-wise")
async def category_wise_report(
    year: int = Query(ge=2000, le=2100),
    month: int = Query(ge=1, le=12),
):
    start_date = date(year, month, 1)

    if month == 12:
        end_date = date(year + 1, 1, 1)
    else:
        end_date = date(year, month + 1, 1)

    try:
        async with httpx.AsyncClient() as client:
            expense_response = await client.get(
                f"{EXPENSE_SERVICE_URL}/expenses",
                params={
                    "start_date": start_date.isoformat(),
                    "end_date": (end_date - __import__("datetime").timedelta(days=1)).isoformat(),
                    "skip": 0,
                    "limit": 100,
                },
                timeout=10.0,
            )
            expense_response.raise_for_status()

            category_response = await client.get(
                f"{CATEGORY_SERVICE_URL}/categories",
                timeout=10.0,
            )
            category_response.raise_for_status()

    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail="Unable to retrieve data from backend services",
        ) from exc

    expenses = expense_response.json()
    categories = category_response.json()

    category_names = {
        category["id"]: category["name"]
        for category in categories
    }

    report = {}

    for expense in expenses:
        category_id = expense["category_id"]
        category_name = category_names.get(category_id, "Unknown")

        if category_name not in report:
            report[category_name] = {
                "expense_count": 0,
                "total_amount": 0,
            }

        report[category_name]["expense_count"] += 1
        report[category_name]["total_amount"] += expense["amount"]

    return {
        "year": year,
        "month": month,
        "categories": [
            {
                "category": name,
                "expense_count": values["expense_count"],
                "total_amount": round(values["total_amount"], 2),
            }
            for name, values in report.items()
        ],
    }
