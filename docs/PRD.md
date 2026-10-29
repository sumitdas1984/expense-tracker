# PRD — Expense Tracker

## 1. Project Overview

A personal expense tracking system. Users record expenses against categories and review spending through monthly and category-wise reports via a structured web interface and an AI assistant.

The system is built as a set of small independent services — three APIs and a UI — so each
concern can evolve, deploy, and be tested on its own.

V1.0 is a working system: record expenses, manage categories, see reports, and do all of
it through the web UI, deployed on AWS. The roadmap below says what comes next.

## 2. Target Users & Interaction Modalities

### Primary Persona
- **Individual Users**: Anyone seeking visibility and control over personal monthly spending without complex spreadsheets or manual overhead.

### Interaction Modalities
Users interact with their financial data through two channels:
1. **Structured Interface (Web UI)**: Visual dashboards, tabular views, date/category filters, and management forms for explicit, deterministic data management. *Shipped in V1.0.*
2. **Conversational Assistant (Natural Language)**: Frictionless capture and ad-hoc queries powered by an AI assistant (embedded chatbot and MCP server tools) to log expenses and summarize spending using natural language. *Phase 3 of the roadmap.*

## 3. Product Goals

1. **Fast capture** — record an expense in seconds, not minutes.
2. **Consistent categories** — every expense rolls up to a category, so reports are meaningful.
3. **Simple reports** — monthly totals and per-category breakdowns, on demand.
4. **Dual-mode interaction** — capture and query data seamlessly via structured forms or natural language conversation.
5. **Service independence** — no single component holds every concern.

## 4. Product Scope

### V1.0 — Completed Baseline

#### Core Functionality

- **Full CRUD for expenses** — amount, date, description, and a category reference.
- **Full CRUD for categories** — unique names, optional descriptions.
- **Monthly aggregation report** — total spend and transaction count for a month.
- **Category breakdown report** — proportional spend per category, with a chart.
- **Unified Streamlit web UI** across all of the above.

#### Microservices Architecture

- **Four independent containerised services** — `ui-service`, `expense-service`,
  `category-service`, `report-service`. Each is a separate image on its own port, and the
  two data services own their own tables.
- **Health probes on every service** — `/health` on the three APIs, `/_stcore/health` on
  the UI.

#### Cloud Infrastructure — AWS ap-south-1

- **ECS Fargate** for serverless orchestration, with **Cloud Map service discovery** on the
  `expense-tracker.local` namespace, so the services reach each other by name.
- **Amazon RDS for PostgreSQL** (`db.t3.micro`), single-AZ and private, in place of a
  database file.
- **Application Load Balancer** with path-based routing — `/expenses`, `/categories` and
  `/reports` to their services, everything else to the UI — and sticky sessions on the UI
  target group.
- **Amazon CloudFront** edge layer terminating TLS with `redirect-to-https`, and an
  `X-Origin-Verify` header sent to the origin.

---

### Future Roadmap

The roadmap proceeds sequentially: each phase provides the stability, reproducibility, or
security prerequisites required by the next.

```text
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 1: Core DevOps & Infrastructure (Automation & IaC)               │
│   1. CI/CD via GitHub Actions (Automated tests, Docker builds, deploys)│ ◄── Current Step
│   2. Security & Secrets Baseline (AWS Secrets Manager/SSM, IAM roles)  │
│   3. IaC Migration (Terraform)                                         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ Phase 2: Production Readiness & Platform Hardening                     │
│   4. Terraform Refinements & Remote State Locking (S3 + DynamoDB)      │
│   5. Foundational Auth & Multi-Tenancy (User context, JWT / Cognito)   │
│   6. Observability (Structured JSON logs, distributed trace IDs, APM)  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ Phase 3: Advanced AI & Product Features                                │
│   7. The MCP Server & Chatbot Layer (Expose tools & conversational UI) │
│   8. Advanced Features & Analytics (Receipt OCR, budgets, alerts)      │
└────────────────────────────────────────────────────────────────────────┘
```

| Phase | Items | What it delivers |
|-------|-------|------------------|
| **1. Core DevOps & Infrastructure** | 1. CI/CD via GitHub Actions · 2. Security and secrets baseline (Secrets Manager/SSM, IAM roles) · 3. IaC migration to Terraform | The stack deploys itself, stops leaking secrets, and stops being a folder of shell scripts |
| **2. Production Readiness & Platform Hardening** | 4. Terraform refinements and remote state locking (S3 + DynamoDB) · 5. Foundational auth and multi-tenancy (user context, JWT or Cognito) · 6. Observability (structured JSON logs, distributed trace ids, APM) | The stack is safe to run for real users, and debuggable when it goes wrong |
| **3. Advanced AI & Product Features** | 7. The MCP server and chatbot layer (expose the APIs as tools, conversational UI) · 8. Advanced features and analytics (receipt OCR, budgets, alerts) | The tracker becomes queryable by an assistant, and starts to act on the data |

**Where the project is now:** step 1 of Phase 1. The deployment scripts exist and are
idempotent, but they are still run by hand — there is no pipeline yet, the database
password sits in the scripts, and nothing authenticates the API.

## 5. Functional Requirements

### Expenses

| ID | Requirement |
|----|-------------|
| E-1 | A user records an expense with amount, category, description, and date. |
| E-2 | Amount must be greater than zero. |
| E-3 | Expenses can be listed, filtered by category and date range, and paginated. |
| E-4 | An expense can be fetched, updated, or deleted by id. |

### Categories

| ID | Requirement |
|----|-------------|
| C-1 | A user creates a category with a name and optional description. |
| C-2 | Category names are unique; a duplicate name is rejected. |
| C-3 | Categories can be listed, fetched, updated, and deleted by id. |

### Reports

| ID | Requirement |
|----|-------------|
| R-1 | A monthly report gives total spend and expense count for a year and month. |
| R-2 | A category-wise report groups spend by category name for a year and month. |
| R-3 | A report surfaces a clear error when a backing service is unavailable. |

### Web interface

| ID | Requirement |
|----|-------------|
| U-1 | Every function of the system is reachable from one web interface. |
| U-2 | The interface is organised into four pages: Add Expense, View Expenses, Category Management, Expense Report. |
| U-3 | A page states clearly when a backing service is unreachable, rather than failing silently. |
| U-4 | The report page lets the user choose the year and month before generating. |

### Conversational assistant

*Phase 3 — not built yet.*

| ID | Requirement |
|----|-------------|
| N-1 | A user records an expense by describing it in natural language, without opening a form. |
| N-2 | A user asks for spending over a period and gets back the same figures the reports give. |
| N-3 | The assistant reads and writes through the same APIs the web interface uses, so the two never drift apart. |
| N-4 | When the assistant cannot reach a service, it says so rather than inventing a figure. |

### Availability

| ID | Requirement |
|----|-------------|
| A-1 | Every API service exposes a health endpoint reporting healthy status. |

## 6. User Workflows

**Record an expense**

1. Open the Add Expense page.
2. Pick a category, then enter amount, description, and date.
3. Submit. The page confirms the expense was added.

**Browse expenses**

1. Open the View Expenses page.
2. Filter by category, start date, and end date.
3. See the matching expenses in a table, with category names resolved.

**Review the month**

1. Open the Expense Report page.
2. Choose a year and month, then generate the report.
3. See the total spend and expense count, then the per-category breakdown and its chart.

**Fix a category mistake**

1. Open the Category Management page.
2. Select the category, then update its name or description, or delete it.

**Log an expense by conversation** — *Phase 3*

1. Ask the assistant to record an expense, for example "450 on groceries yesterday, Food".
2. The assistant resolves the category and posts it through the expense API.
3. It confirms the amount, category and date it recorded.

## 7. Non-Functional Requirements

| Area | Requirement |
|------|-------------|
| Performance | List and report endpoints respond in well under a second for a personal dataset of thousands of rows. |
| Failure handling | A downstream failure is reported to the caller, not swallowed. `report-service` returns 502, and the UI shows an error. |
| Data durability | Expense and category data survives container removal, and the deployed database is managed by RDS. |
| Testability | Every API service has an automated test suite. `report-service` tests need no live backends. `ui-service` has no test suite yet. |
| Portability | The full stack runs on a developer machine with one command, and on AWS through the scripts in `scripts/`. |

## 8. Acceptance Criteria

V1.0 is done when:

- [ ] Every API endpoint behaves as specified, including the error cases: 400, 404, 409, 502.
- [ ] `docker compose up --build` starts the stack, the three API health endpoints respond, and the UI loads on port 8501.
- [ ] Each of the four UI pages renders and reaches the APIs it needs.
- [ ] Data written through the API survives `docker compose down` followed by `up`.
- [ ] `report-service` returns a real monthly and category-wise report while the other two services are running.
- [ ] Each API service's test suite passes.
- [ ] The totals in a category-wise report match the expenses that were created.
- [ ] The four services run on ECS Fargate in ap-south-1, reachable through CloudFront, with the data in RDS.
