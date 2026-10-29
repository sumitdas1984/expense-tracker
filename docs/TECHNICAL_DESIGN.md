# Technical Design — Expense Tracker

## 1. Technology Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Language | Python 3.13 | Matches the local toolchain |
| API framework | FastAPI | Typed request/response models, automatic OpenAPI docs |
| UI framework | Streamlit 1.66 | Python-native; the fastest path to a working interface |
| HTTP client | requests | Used by the UI to call the APIs |
| ORM | SQLAlchemy 2.x | Explicit models, same code across SQLite and PostgreSQL |
| Database | PostgreSQL 17 | One server, one database per data service |
| Database driver | psycopg 3 (`psycopg[binary]`) | The `postgresql+psycopg` URL scheme |
| ASGI server | uvicorn | Standard FastAPI runner |
| Dependency and build tool | uv | Resolves fast, manages the venv, installs the project |
| Packaging | hatchling (`src/` layout) for the API services, `uv_build` for `ui-service` | Keeps the importable package separate from the repo root |
| Tests | pytest, httpx `TestClient`, respx | respx mocks outbound HTTP so `report-service` needs no live backends |
| Containers | Docker, `python:3.13-slim` + uv | Small image, same toolchain as local |

## 2. System Architecture

Four independent services. Each runs in its own container. The two data services each own a
database on a shared PostgreSQL server; `report-service` and `ui-service` own none.
Services reach each other over HTTP only — no shared database, no shared schema.

```
                    ┌──────────────┐
                    │  ui-service  │  Streamlit, :8501
                    └──────┬───────┘
                           │ HTTP
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│    expense    │  │    category   │  │     report    │
│    :8001      │  │     :8002     │  │     :8003     │
│               │  │               │  │               │
│  expense_db   │  │  category_db  │  │  no database  │
└───────┬───────┘  └───────┬───────┘  └───────┬───────┘
        │                  │                  │
        └──────────┬───────┴──────────────────┘
                   │
          ┌────────┴─────────┐
          │  postgres :5432  │  postgres:17
          └──────────────────┘
```

Consequences of this shape:

- A service can be replaced or rewritten without touching the others.
- `report-service` and `ui-service` hold no data of their own, so they cannot drift out of
  sync with their sources.
- The two data services share a PostgreSQL server but not a database, so a schema change in
  one cannot affect the other.
- There is no distributed transaction. Cross-service consistency is not guaranteed, and V1.0
  does not need it.

The same four services run locally under Docker Compose and on AWS under ECS Fargate.
Section 9 covers the deployed version.

## 3. Microservices and Responsibilities

| Service | Port | Owns | Responsibilities | Depends on |
|---------|------|------|------------------|------------|
| `expense-service` | 8001 | `expense_db`, the `expenses` table | Create, list, filter, update, delete expenses | PostgreSQL |
| `category-service` | 8002 | `category_db`, the `categories` table | Create, list, update, delete categories | PostgreSQL |
| `report-service` | 8003 | nothing | Monthly and category-wise reports | the other two, over HTTP |
| `ui-service` | 8501 | nothing | The web interface over all three APIs | the other three, over HTTP |

Two more components are planned for the conversational modality in the PRD — an MCP server
exposing the APIs as tools, and a chatbot built on it. Neither exists yet; both are Phase 3
of the roadmap. The MCP server is a client of the same three APIs, so it adds no new data
path and no new schema.

Each service is a self-contained Python package under `src/`:

```
<service>/
├── src/<package>/
├── tests/               pytest suite
├── pyproject.toml
├── Dockerfile
└── README.md
```

The API services are shaped like `src/<package>/{main.py,database.py,models.py,schemas.py}`.
Two services break the pattern:

- `report-service` has no database, so it is just `src/report_service/{main.py,config.py}`.
- `ui-service` is a Streamlit app, so it is `src/ui_service/main.py`, `config.py`, and a
  `pages/` package — one module per page, each exposing a single `show_*()` function.

## 4. Data Model

### Expense — `expense-service`, `expense_db.expenses`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | Integer | PK, indexed | |
| `amount` | Float | not null | Must be greater than zero; validated at the API layer |
| `category_id` | Integer | not null | A `category-service` id. Not enforced by a foreign key |
| `description` | String | not null | |
| `expense_date` | Date | not null | |

### Category — `category-service`, `category_db.categories`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | Integer | PK, indexed | |
| `name` | String | not null, unique | Duplicate names are rejected with 409 |
| `description` | String | nullable | |

Both tables are created by SQLAlchemy's `create_all` at startup rather than by a migration
tool. There is no migration history, so changing a column means recreating the table.

### Known data model gaps

- `amount` is a `Float`. Binary floating point rounds, so money should move to
  `Numeric(12,2)` and `Decimal`.
- `category_id` carries no foreign key. An unknown category id is accepted silently.
- Neither `category_id` nor `expense_date` is indexed, although both are filter columns.

## 5. API Requirements

All endpoints return JSON. Each API service also serves OpenAPI docs at `/docs`.

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
- The UI's amount field allows `0`, but the API requires an amount greater than zero and
  answers with a 422.
- The UI calls `st.rerun()` right after showing a success message on category create, so
  the message is cleared before it is seen.
- The report page defaults to January rather than the current month, so a report always
  needs a deliberate month choice.
- `st.dataframe(use_container_width=True)` is deprecated in Streamlit 1.66 and warns on
  every render; it wants `width="stretch"` instead.

## 6. Configuration and Environment Setup

| Variable | Service | Default | Purpose |
|----------|---------|---------|---------|
| `DATABASE_URL` | expense-service | `sqlite:///./expenses.db` | Database location |
| `DATABASE_URL` | category-service | `sqlite:///./categories.db` | Database location |
| `EXPENSE_SERVICE_URL` | report-service | `http://localhost:8001` | Where to find expense-service |
| `CATEGORY_SERVICE_URL` | report-service | `http://localhost:8002` | Where to find category-service |
| `EXPENSE_SERVICE_URL` | ui-service | `http://localhost:8001` | Where to find expense-service |
| `CATEGORY_SERVICE_URL` | ui-service | `http://localhost:8002` | Where to find category-service |
| `REPORT_SERVICE_URL` | ui-service | `http://localhost:8003` | Where to find report-service |

All of them are optional locally — the defaults work. Under Docker, `docker-compose.yml`
sets them: the two database URLs become `postgresql+psycopg://` URLs pointing at the
`postgres` service, and the service URLs become compose hostnames.

On AWS the same variables are set by the deployment scripts, with the service URLs
pointing at Cloud Map names under `expense-tracker.local`. The values they take are
written to `scripts/.infrastructure-output.env` by `deploy-infrastructure.sh`, which
`deploy-services.sh` then reads. That file is gitignored.

`database.py` branches on the URL scheme. A URL starting with `sqlite` is opened with
`connect_args={"check_same_thread": False}`; anything else is opened as a plain
PostgreSQL engine. So the same code runs against either, and the choice is entirely
configuration:

```python
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./expenses.db")

if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(
        DATABASE_URL,
        connect_args={"check_same_thread": False},
    )
else:
    engine = create_engine(DATABASE_URL)
```

Local setup per API service:

```bash
cd <service>
uv sync
uv run uvicorn <package>.main:app --reload --port <port>
```

Without `DATABASE_URL` this uses a local SQLite file. To use the container's PostgreSQL
instead:

```bash
export DATABASE_URL=postgresql+psycopg://expense_user:local_dev_password@localhost:5432/expense_db
```

For the UI:

```bash
cd ui-service
uv sync
uv run streamlit run src/ui_service/main.py --server.port 8501
```

For the deployed version, see [section 9](#9-aws-deployment).

## 7. Docker and Local Deployment

This is the local path. The deployed version is in [section 9](#9-aws-deployment).

Each service has a `Dockerfile` based on `python:3.13-slim` with `uv` installed. The build
copies `src/` and installs the project, so the container runs the same importable package
as a local checkout.

`docker-compose.yml` runs all five together:

- `postgres` — 5432, the `postgres:17` image, data in the `postgres_data` volume
- `expense-service` — 8001, uses `expense_db`
- `category-service` — 8002, uses `category_db`
- `report-service` — 8003, no database, reaches the other two by service hostname
- `ui-service` — 8501, no database, reaches all three by service hostname

```bash
docker compose up --build     # start everything
docker compose down           # stop; the named volumes keep the data
docker compose down -v        # stop and delete the data
```

The `postgres_data` volume is what makes the data survive container removal.

**`category_db` has to be created once.** The Postgres image only creates the database
named by `POSTGRES_DB`, which is `expense_db`. There is no init script in the repo, so
after the first `up` run:

```bash
docker compose exec postgres createdb -U expense_user category_db
```

**The `expense_data` and `category_data` volumes are leftovers** from the SQLite setup.
The database files no longer live at `/app/data`, so those volumes now hold nothing the
services read. They can be dropped from the compose file.

**Schema creation is not a migration.** Each service calls `Base.metadata.create_all` at
startup, so tables appear on first boot and are never altered afterwards. A column change
needs a manual `ALTER TABLE`, or a migration tool such as Alembic.

## 8. Testing Strategy

| Service | Tests | Covers |
|---------|-------|--------|
| `expense-service` | 6 | CRUD, health, filters, pagination, 404s |
| `category-service` | 10 | CRUD, health, duplicate-name 409, 404s |
| `report-service` | 4 | Monthly report, category-wise report, 502 on each backend failure |
| `ui-service` | 0 | none yet |

Run the API service suites:

```bash
cd <service>
uv run pytest
```

`expense-service` and `category-service` point the app at an in-memory SQLite database
through a `get_db` override, so tests are fast, need no PostgreSQL, and leave no files
behind. Production runs against PostgreSQL, but the tests do not exercise that path.

`report-service` has no database. It uses `respx` to mock the HTTP calls to the other two
services, so its tests run without anything else being up. This is the pattern to follow
for any future service that calls another service.

`ui-service` has no test suite. It is currently verified by running the app and driving
it through Streamlit's `AppTest` harness, which executes the script and reports any
exception. That harness is the natural basis for a suite: patch `requests` for the
outbound calls, then assert on the elements each page renders. Writing that suite is the
first thing to do before adding more UI.

## 9. AWS Deployment

The same four services run on ECS Fargate in **ap-south-1**, behind an Application Load
Balancer with CloudFront in front of it.

```
                       https://
                          │
                  ┌───────▼────────┐
                  │   CloudFront    │  HTTPS, cached at the edge
                  └───────┬────────┘
                          │ HTTP
                  ┌───────▼────────┐
                  │       ALB       │  :80, one rule per API path
                  └───┬────────┬────┘
        ┌─────────────┘        └─────────────┐
        │                                      │
┌───────▼────────┐                     ┌───────▼────────┐
│  ui-service    │                     │ expense-service│
│     :8501      │                     │     :8001      │
└────────────────┘                     └───────┬────────┘
                                                   │
        ┌────────────────┐   ┌────────────────┐   │
        ▼                ▼   ▼                ▼   │
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│ category-svc  │  │ report-service│  │  RDS Postgres │
│     :8002     │  │     :8003     │  │  expense_     │
└───────────────┘  └───────────────┘  │  tracker      │
                                       └───────────────┘
```

### The scripts

| Script | What it does |
|--------|--------------|
| `deploy-infrastructure.sh` | ECR repositories, ECS cluster, three security groups, the ALB and its target groups, CloudFront, and the RDS instance |
| `deploy-services.sh` | The task execution role, the log group, the Cloud Map namespace, the images, the task definitions, and the ECS services |
| `verify-deployment.sh` | Reports the RDS status, the running task counts, the target group health, and the public URLs |
| `cleanup-aws.sh` | Tears all of it down, after asking for confirmation |

They run in that order. The first script writes `scripts/.infrastructure-output.env` —
the ids, the endpoints and the target group ARNs — and the next two read it.

Every script is idempotent: each resource is looked up before it is created, so a script
can be re-run after a change without leaving duplicates behind.

### Networking

Three security groups, in the default VPC:

| Group | Allows |
|-------|--------|
| `expense-tracker-alb-sg` | port 80 from `0.0.0.0/0` — the only group open to the internet |
| `expense-tracker-ecs-sg` | all traffic from itself, and ports 8000–8501 from the ALB group |
| `expense-tracker-rds-sg` | port 5432 from the ECS group only |

The tasks run in public subnets with `assignPublicIp=ENABLED`, so they can pull images from
ECR. There is no NAT gateway and no VPC endpoint — the tasks reach ECR over the internet
gateway directly.

### Service discovery

`report-service` and `ui-service` reach the APIs by DNS name, through a Cloud Map private
namespace called `expense-tracker.local`. The names resolve to
`expense-service.expense-tracker.local:8001` and so on, and the task definitions inject
them as `EXPENSE_SERVICE_URL`, `CATEGORY_SERVICE_URL` and `REPORT_SERVICE_URL`.

### One database, not two

On AWS both data services point at the same database, `expense_tracker`. Their tables are
`expenses` and `categories`, so they do not collide. Locally the compose setup gives each
service its own database, which is why the local and deployed connection strings differ.

### What is not done yet

The gaps in the current deployment, in the order the roadmap in the PRD says to close them:

- **No CI/CD.** The scripts are run by hand. The test suites should run on merge, and the
  images should be built in CI rather than pushed from a laptop.
- **Secrets are in plaintext.** The master password is in the scripts and in
  `scripts/.infrastructure-output.env`, which is gitignored. It should move to Secrets
  Manager and be injected with `valueFrom`.
- **No authentication.** Every service, the load balancer and the CloudFront distribution
  are open to the internet. This is the first thing to fix before the deployment is
  anything but a demo.
- **No observability.** Logs go to CloudWatch as plain text, with no trace ids to follow
  a request across the four services.
- **No migration tool.** `create_all` creates the tables; changing a column needs a manual
  `ALTER TABLE`.
- **The SQLite fallback is still in `database.py`.**
- **Backups are off** — the RDS instance runs with `--backup-retention-period 0`.
- **Single AZ, single instance.** An AZ failure takes the database down.
- **No conversational interface.** The PRD describes natural-language capture and querying
  as a second modality; the MCP server and chatbot that would provide it are Phase 3 and
  are not built yet.
