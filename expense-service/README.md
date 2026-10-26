# expense-service

FastAPI + SQLAlchemy service for tracking expenses. SQLite file (`expenses.db`) is created
on first run.

```
src/expense_service/   main.py, database.py, models.py, schemas.py
tests/                 test_expenses.py
```

## Run

Local:

```bash
uv sync
uv run uvicorn expense_service.main:app --reload --port 8001
```

Docker:

```bash
docker build -t expense-service .
docker run -p 8001:8001 -v expense_data:/app/data -e DATABASE_URL=sqlite:////app/data/expenses.db expense-service
```

The volume is what keeps the database across container removal. `docker compose up --build`
from the repo root mounts it for you.

Docs at http://localhost:8001/docs

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| GET | `/health` | liveness check |
| POST | `/expenses` | create, returns 201 |
| GET | `/expenses` | filters: `category_id`, `start_date`, `end_date`; paginates: `skip`, `limit` (default 10, max 100) |
| GET | `/expenses/{id}` | 404 if missing |
| PUT | `/expenses/{id}` | full replace, all fields required |
| DELETE | `/expenses/{id}` | returns 204 |

Expense body: `amount` (>0), `category_id` (>0), `description`, `expense_date` (`YYYY-MM-DD`).

## Tests

```bash
uv run pytest
```
