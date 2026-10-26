# expense-tracker

A personal expense tracker. Record expenses against categories, see where the money went
each month, and browse it all from a web UI.

Four independent services: three FastAPI APIs, each with its own SQLite database, and a
Streamlit UI that talks to them over HTTP.

Python 3.13 · FastAPI · SQLAlchemy · SQLite · Streamlit · uv · Docker

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
│  expenses.db  │  │ categories.db │  │  no database  │
└───────────────┘  └───────────────┘  └───────┬───────┘
                                             │
                    reads expenses ────────────┤
                    reads categories ──────────┘
```

| Service | Port | Owns |
|---------|------|------|
| [expense-service](expense-service/) | 8001 | the `expenses` table |
| [category-service](category-service/) | 8002 | the `categories` table |
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
- A health endpoint on every service
- Data persists in named volumes, so it survives `docker compose down`

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

Stop the stack with `docker compose down` — the data stays in the named volumes. Add `-v`
to delete that data too.

### Running a service locally

Each service has its own README. The general shape for an API:

```bash
cd expense-service
uv sync
uv run uvicorn expense_service.main:app --reload --port 8001
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

## Docs

- [PRD](docs/PRD.md) — what the product does and who it is for
- [Technical design](docs/TECHNICAL_DESIGN.md) — architecture, data model, API, and deployment

## Notes

- `report-service` and `ui-service` reach the APIs by hostname (`expense-service:8001`),
  set through `EXPENSE_SERVICE_URL`, `CATEGORY_SERVICE_URL`, and `REPORT_SERVICE_URL`.
- Known gaps in the current implementation are listed in the
  [technical design](docs/TECHNICAL_DESIGN.md).
