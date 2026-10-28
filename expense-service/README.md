# expense-service

FastAPI + SQLAlchemy service for tracking expenses. It stores its data in the `expenses`
table, in the `expense_db` database on PostgreSQL.

```
src/expense_service/   main.py, database.py, models.py, schemas.py
tests/                 test_expenses.py
```

## Configuration

| Env var | Default |
|---------|---------|
| `DATABASE_URL` | `sqlite:///./expenses.db` |

Any URL starting with `sqlite` is opened as a SQLite file; anything else is opened as
PostgreSQL. The compose file points it at
`postgresql+psycopg://expense_user:local_dev_password@postgres:5432/expense_db`.

## Run

Local:

```bash
uv sync
uv run uvicorn expense_service.main:app --reload --port 8001
```

With no `DATABASE_URL` this uses a local SQLite file. To use the container's PostgreSQL:

```bash
export DATABASE_URL=postgresql+psycopg://expense_user:local_dev_password@localhost:5432/expense_db
uv run uvicorn expense_service.main:app --reload --port 8001
```

Docker:

```bash
docker compose up --build expense-service
```

The `expenses` table is created on startup, so the `expense_db` database has to exist
first — see the root README.

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
