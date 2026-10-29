# expense-tracker

A personal expense tracker. Record expenses against categories, see where the money went
each month, and browse it all from a web UI.

Four independent services: three FastAPI APIs over a shared PostgreSQL server, and a
Streamlit UI that talks to them over HTTP.

Python 3.13 · FastAPI · SQLAlchemy · PostgreSQL 17 · Streamlit · uv · Docker

## Architecture

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

| Service | Port | Owns |
|---------|------|------|
| [expense-service](expense-service/) | 8001 | the `expenses` table in `expense_db` |
| [category-service](category-service/) | 8002 | the `categories` table in `category_db` |
| [report-service](report-service/) | 8003 | nothing — it aggregates the other two |
| [ui-service](ui-service/) | 8501 | the web interface |

No service shares a database with another. They talk over HTTP only, so any one of them
can be changed or replaced on its own.

## Features

- Add expenses with an amount, category, description, and date
- Browse expenses, filtered by category and date range
- Manage categories — create, rename, delete
- Monthly report: total spend and number of expenses
- Category-wise report: spend per category, with a bar chart
- A health endpoint on every API service
- Data persists in a named volume, so it survives `docker compose down`

## Prerequisites

- **Docker and Docker Compose** — for the one-command path
- **Python 3.13 and [uv](https://docs.astral.sh/uv/)** — only if you want to run a service
  locally instead of in a container

## Run the application

```bash
docker compose up --build
```

Then open **http://localhost:8501** for the UI.

| | |
|---|---|
| UI | http://localhost:8501 |
| Expense API | http://localhost:8001/docs |
| Category API | http://localhost:8002/docs |
| Report API | http://localhost:8003/docs |
| PostgreSQL | localhost:5432 |

Stop the stack with `docker compose down` — the data stays in the `postgres_data` volume. Add
`-v` to delete that data too.

The compose file starts PostgreSQL 17 and creates `expense_db`. `category_db` is not
created for you, so create it once:

```bash
docker compose exec postgres createdb -U expense_user category_db
```

### Running a service locally

Each service has its own README. The general shape for an API:

```bash
cd expense-service
uv sync
uv run uvicorn expense_service.main:app --reload --port 8001
```

With no `DATABASE_URL` set, a service falls back to a local SQLite file, so it runs
without PostgreSQL. Point it at the container instead with:

```bash
export DATABASE_URL=postgresql+psycopg://expense_user:local_dev_password@localhost:5432/expense_db
```

For the UI:

```bash
cd ui-service
uv sync
uv run streamlit run src/ui_service/main.py --server.port 8501
```

The UI needs all three APIs running first.

## Project layout

```
expense-tracker/
├── docs/                 PRD.md, TECHNICAL_DESIGN.md
├── scripts/              deploy-infrastructure.sh, deploy-services.sh,
│                         verify-deployment.sh, cleanup-aws.sh
├── expense-service/
├── category-service/
├── report-service/
├── ui-service/
├── docker-compose.yml
└── README.md
```

Every service has the same shape — an installable package under `src/`, a pytest suite,
a `pyproject.toml`, a Dockerfile, and a README:

```
<service>/
├── src/<package>/
├── tests/
├── pyproject.toml
├── Dockerfile
└── README.md
```

`report-service` has no database, so it is just `src/report_service/{main.py,config.py}`.
`ui-service` has a `pages/` package instead of the API trio.

## Deploy to AWS

The same four services run on ECS Fargate behind an Application Load Balancer, with
CloudFront in front for HTTPS. The scripts in `scripts/` do it in order, and each one is
idempotent — re-run them whenever you change something.

```bash
scripts/deploy-infrastructure.sh   # ECR, ECS cluster, security groups, ALB,
                                   # CloudFront, RDS PostgreSQL
scripts/deploy-services.sh         # build and push the images, register task
                                   # definitions, run the four ECS services
scripts/verify-deployment.sh       # report what is up and where it is
scripts/cleanup-aws.sh             # tear everything down (asks first)
```

The first script writes `scripts/.infrastructure-output.env` with the ids and endpoints
it created — the other two read it, so run them in that order.

Everything lands in **ap-south-1**. The app is served over HTTPS from a CloudFront
distribution, with the Application Load Balancer behind it on plain HTTP. The live URLs
are printed by `scripts/verify-deployment.sh`, and also written to
`scripts/.infrastructure-output.env` as `CF_DOMAIN` and `ALB_DNS`.

**Cost:** the four Fargate tasks, the load balancer, CloudFront and the RDS instance bill
continuously while they run — roughly $150 a month. `scripts/cleanup-aws.sh` removes all
of it.

## Docs

- [PRD](docs/PRD.md) — what the product does, who it is for, and the **roadmap** for
  what comes next
- [Technical design](docs/TECHNICAL_DESIGN.md) — architecture, data model, API, and deployment

## Notes

- `report-service` and `ui-service` reach the APIs by hostname (`expense-service:8001`),
  set through `EXPENSE_SERVICE_URL`, `CATEGORY_SERVICE_URL`, and `REPORT_SERVICE_URL`.
- On AWS those hostnames are Cloud Map DNS names under `expense-tracker.local`; locally
  they are plain host names.
- Locally the two data services use separate databases (`expense_db` and `category_db`).
  On AWS they share one database, `expense_tracker` — their tables are `expenses` and
  `categories`, so they do not collide.
- Known gaps in the current implementation are listed in the
  [technical design](docs/TECHNICAL_DESIGN.md).
