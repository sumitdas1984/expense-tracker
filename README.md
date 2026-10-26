# expense-tracker

Microservices for an expense tracker. Each service is a standalone FastAPI app with its own
SQLite database, plus a report service that aggregates across the others.

| Service | Port | Description |
|---------|------|-------------|
| [expense-service](expense-service/) | 8001 | CRUD for expenses |
| [category-service](category-service/) | 8002 | CRUD for categories |
| [report-service](report-service/) | 8003 | Monthly and category-wise expense reports |

## Run everything

```bash
docker compose up --build
```

To run a single service on its own, see its README — each one also runs locally with `uv`.

## Service layout

```
<service>/
├── src/<package>/       main.py, database.py, models.py, schemas.py
├── tests/               pytest suite
├── pyproject.toml       hatchling build, package lives in src/<package>
├── Dockerfile
└── README.md
```

`report-service` is the exception — it has no database of its own, so it is just
`src/report_service/{main.py,config.py}`, and it reads from the other two over HTTP.

## Notes

- `report-service` reaches the others by hostname (`expense-service:8001`), set through
  `EXPENSE_SERVICE_URL` and `CATEGORY_SERVICE_URL`.
- The SQLite files live inside their containers, so removing the containers loses the data.
- Open issues for each service are tracked in that service's README.
