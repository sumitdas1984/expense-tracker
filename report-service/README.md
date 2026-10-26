# report-service

FastAPI service that builds expense reports. It has no database of its own — it reads
from `expense-service` (8001) and `category-service` (8002) over HTTP.

```
src/report_service/   main.py, config.py
```

## Configuration

| Env var | Default |
|---------|---------|
| `EXPENSE_SERVICE_URL` | `http://localhost:8001` |
| `CATEGORY_SERVICE_URL` | `http://localhost:8002` |

## Run

Both other services must be running first.

Local:

```bash
uv sync
uv run uvicorn report_service.main:app --reload --port 8003
```

Docker:

```bash
docker build -t report-service .
docker run -p 8003:8003 report-service
```

Docs at http://localhost:8003/docs

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| GET | `/health` | liveness check |
| GET | `/reports/monthly` | `year` (2000–2100), `month` (1–12) |
| GET | `/reports/category-wise` | `year`, `month` |

Returns 502 if either backend service is unreachable.

## Tests

```bash
uv run pytest
```
