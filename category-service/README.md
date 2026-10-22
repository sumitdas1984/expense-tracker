# category-service

FastAPI + SQLAlchemy service for managing expense categories. SQLite file (`categories.db`)
is created on first run.

## Run

Local:

```bash
uv sync
uv run uvicorn main:app --reload --port 8002
```

Docker:

```bash
docker build -t category-service .
docker run -p 8002:8002 category-service
```

Docs at http://localhost:8002/docs

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
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