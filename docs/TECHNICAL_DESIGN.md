# Technical Design — Expense Tracker

## 1. Technology Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Language | Python 3.13 | Matches the local toolchain |
| API framework | FastAPI | Typed request/response models, automatic OpenAPI docs |
| ORM | SQLAlchemy 2.x | Explicit models, a clear path off SQLite later |
| Database | SQLite | Zero-setup for V1.0; each service owns its own file |
| ASGI server | uvicorn | Standard FastAPI runner |
| Dependency and build tool | uv | Resolves fast, manages the venv, installs the project |
| Packaging | hatchling, `src/` layout | Keeps the importable package separate from the repo root |
| Tests | pytest, httpx `TestClient`, respx | respx mocks outbound HTTP so `report-service` needs no live backends |
| Containers | Docker, `python:3.13-slim` + uv | Small image, same toolchain as local |

## 2. System Architecture

Three independent FastAPI services. Each owns its own database and runs in its own
container. Services reach each other over HTTP only — no shared database, no shared schema.

```
                         client
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│    expense    │  │    category   │  │     report    │
│    :8001      │  │     :8002     │  │     :8003     │
│               │  │               │  │               │
│  expenses.db  │  │ categories.db │  │  no database  │
└───────────────┘  └───────────────┘  └───────┬───────┘
                                             │
                    reads expenses ────────────┤
                    reads categories ──────────┘
```

Consequences of this shape:

- A service can be replaced or rewritten without touching the others.
- `report-service` has no data of its own, so it cannot drift out of sync with its sources.
- There is no distributed transaction. Cross-service consistency is not guaranteed, and V1.0
  does not need it.

## 3. Microservices and Responsibilities

| Service | Port | Owns | Responsibilities | Depends on |
|---------|------|------|------------------|------------|
| `expense-service` | 8001 | `expenses` table | Create, list, filter, update, delete expenses | — |
| `category-service` | 8002 | `categories` table | Create, list, update, delete categories | — |
| `report-service` | 8003 | nothing | Monthly and category-wise reports | the other two, over HTTP |

Each service is a self-contained Python package under `src/`:

```
<service>/
├── src/<package>/       main.py, database.py, models.py, schemas.py
├── tests/               pytest suite
├── pyproject.toml       hatchling build, package lives in src/<package>
├── Dockerfile
└── README.md
```

`report-service` is the exception — it has no database, so it is just
`src/report_service/{main.py,config.py}`.

## 4. Data Model

### Expense — `expense-service`, table `expenses`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | Integer | PK, indexed | |
| `amount` | Float | not null | Must be greater than zero; validated at the API layer |
| `category_id` | Integer | not null | A `category-service` id. Not enforced by a foreign key |
| `description` | String | not null | |
| `expense_date` | Date | not null | |

### Category — `category-service`, table `categories`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | Integer | PK, indexed | |
| `name` | String | not null, unique | Duplicate names are rejected with 409 |
| `description` | String | nullable | |

### Known data model gaps

- `amount` is a `Float`. Binary floating point rounds, so money should move to
  `Numeric(12,2)` and `Decimal`.
- `category_id` carries no foreign key. An unknown category id is accepted silently.
- Neither `category_id` nor `expense_date` is indexed, although both are filter columns.

## 5. API Requirements

All endpoints return JSON. Each service also serves OpenAPI docs at `/docs`.

### `expense-service` — :8001

| Method | Path | Success | Errors |
|--------|------|---------|--------|
| GET | `/health` | 200 | — |
| POST | `/expenses` | 201 | 422 invalid body |
| GET | `/expenses` | 200 | 400 bad date range or non-positive `category_id` |
| GET | `/expenses/{id}` | 200 | 404 not found |
| PUT | `/expenses/{id}` | 200 | 404 not found |
| DELETE | `/expenses/{id}` | 204 | 404 not found |

`GET /expenses` accepts `category_id`, `start_date`, `end_date`, `skip` (default 0), and
`limit` (default 10, max 100). `PUT` is a full replace — every field is required.

### `category-service` — :8002

| Method | Path | Success | Errors |
|--------|------|---------|--------|
| GET | `/health` | 200 | — |
| POST | `/categories` | 201 | 409 name already taken |
| GET | `/categories` | 200 | — |
| GET | `/categories/{id}` | 200 | 404 not found |
| PUT | `/categories/{id}` | 200 | 404 not found, 409 name taken |
| DELETE | `/categories/{id}` | 204 | 404 not found |

### `report-service` — :8003

| Method | Path | Success | Errors |
|--------|------|---------|--------|
| GET | `/health` | 200 | — |
| GET | `/reports/monthly` | 200 | 502 backend unreachable |
| GET | `/reports/category-wise` | 200 | 502 backend unreachable |

Both reports take `year` (2000–2100) and `month` (1–12). Monthly returns `total_expenses`
and `expense_count`; category-wise returns a list of `{category, expense_count, total_amount}`.

### Known API gaps

- No authentication on any service. Every endpoint is open, and the dataset is shared.
- `PUT` cannot update a single field on `expense-service`.
- `GET /expenses` returns no total count, so a client cannot build accurate pagination.
- `report-service` fetches with `limit=100` and no pagination, so a month with more than
  100 expenses is under-reported.

## 6. Configuration and Environment Setup

| Variable | Service | Default | Purpose |
|----------|---------|---------|---------|
| `DATABASE_URL` | expense-service | `sqlite:///./expenses.db` | Database location |
| `DATABASE_URL` | category-service | `sqlite:///./categories.db` | Database location |
| `EXPENSE_SERVICE_URL` | report-service | `http://localhost:8001` | Where to find expense-service |
| `CATEGORY_SERVICE_URL` | report-service | `http://localhost:8002` | Where to find category-service |

All four are optional locally — the defaults work. Under Docker, `docker-compose.yml` sets
them, and the two database URLs point at the mounted volume.

Local setup per service:

```bash
cd <service>
uv sync
uv run uvicorn <package>.main:app --reload --port <port>
```

## 7. Docker and Local Deployment

Each service has a `Dockerfile` based on `python:3.13-slim` with `uv` installed. The build
copies `src/` and installs the project, so the container runs the same importable package
as a local checkout.

`docker-compose.yml` runs all three together:

- `expense-service` — 8001, database in the `expense_data` volume at `/app/data`
- `category-service` — 8002, database in the `category_data` volume at `/app/data`
- `report-service` — 8003, no database, reaches the other two by service hostname

```bash
docker compose up --build     # start everything
docker compose down           # stop; the named volumes keep the data
docker compose down -v        # stop and delete the data
```

The named volumes are what make the data survive container removal. Without them, each
`sqlite` file dies with its container.

## 8. Testing Strategy

| Service | Tests | Covers |
|---------|-------|--------|
| `expense-service` | 6 | CRUD, health, filters, pagination, 404s |
| `category-service` | 10 | CRUD, health, duplicate-name 409, 404s |
| `report-service` | 4 | Monthly report, category-wise report, 502 on each backend failure |

Run them per service:

```bash
cd <service>
uv run pytest
```

`expense-service` and `category-service` point the app at an in-memory SQLite database
through a `get_db` override, so tests are fast and leave no files behind.

`report-service` has no database. It uses `respx` to mock the HTTP calls to the other two
services, so its tests run without anything else being up. This is the pattern to follow
for any future service that calls another service.

## 9. Future AWS Deployment Considerations

Nothing below is implemented. These are the decisions to make when the system outgrows a
single machine.

- **Compute** — ECS/Fargate for the three services, or App Runner for the simpler
  one-service-per-container case. The Dockerfiles need no change.
- **Databases** — SQLite does not work across replicas. Move each service to its own RDS
  Postgres instance, or one instance with a database per service. `DATABASE_URL` already
  makes this a configuration change, but the `sqlite`-specific engine options in
  `database.py` need to become conditional.
- **Registry** — ECR, with images built and pushed from CI.
- **Ingress** — an Application Load Balancer in front of the three services, with routing
  by path so `/expenses` and `/categories` land on the right service.
- **Configuration and secrets** — `DATABASE_URL` and the service URLs move to SSM
  Parameter Store or Secrets Manager, injected as environment variables.
- **CI/CD** — GitHub Actions running the three test suites and building images on merge.
- **MCP server and chatbot** — expose the APIs as MCP tools in their own service, with
  authentication and per-user scoping. The current services are unauthenticated and
  single-tenant, so this work comes first.
- **Observability** — structured logs, request tracing across services, and metrics on
  latency and error rates.
