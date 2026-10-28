# category-service

FastAPI + SQLAlchemy service for managing expense categories. It stores its data in the
`categories` table, in the `category_db` database on PostgreSQL.

```
src/category_service/   main.py, database.py, models.py, schemas.py
tests/                  test_categories.py
```

## Configuration

| Env var | Default |
|---------|---------|
| `DATABASE_URL` | `sqlite:///./categories.db` |

Any URL starting with `sqlite` is opened as a SQLite file; anything else is opened as
PostgreSQL. The compose file points it at
`postgresql+psycopg://expense_user:local_dev_password@postgres:5432/category_db`.

## Run

Local:

```bash
uv sync
uv run uvicorn category_service.main:app --reload --port 8002
```

With no `DATABASE_URL` this uses a local SQLite file. To use the container's PostgreSQL:

```bash
export DATABASE_URL=postgresql+psycopg://expense_user:local_dev_password@localhost:5432/category_db
uv run uvicorn category_service.main:app --reload --port 8002
```

Docker:

```bash
docker compose up --build category-service
```

The `categories` table is created on startup, so the `category_db` database has to exist
first — see the root README.

Docs at http://localhost:8002/docs

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| GET | `/health` | liveness check |
| POST | `/categories` | create, returns 201, 409 if name taken |
| GET | `/categories` | all categories |
| GET | `/categories/{id}` | 404 if missing |
| PUT | `/categories/{id}` | full replace, all fields required |
| DELETE | `/categories/{id}` | returns 204 |

Category body: `name` (required, unique), `description` (optional).

## Tests

```bash
uv run pytest
```
