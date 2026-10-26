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
docker run -p 8001:8001 expense-service
```

Docs at http://localhost:8001/docs

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
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

## Open Issues

1. SQLite lives inside the container (`/app/expenses.db`) — removing the container wipes it. Fix with a Docker volume mount so the db persists across the container lifecycle