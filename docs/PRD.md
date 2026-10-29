# PRD — Expense Tracker

## 1. Project Overview

A personal expense tracking system. Users record expenses against categories and review
spending through monthly and category-wise reports, from a single web interface.

The system is built as a set of small independent services — three APIs and a UI — so each
concern can evolve, deploy, and be tested on its own.

V1.0 is a working system: record expenses, manage categories, see reports, and do all of
it through the web UI. Everything listed under future scope is a direction, not a
commitment.

## 2. Target Users

- **Individual users** who want a clear picture of where their money goes each month.
- **Developers** (future) who want to query expense data from an AI assistant through MCP.

V1.0 serves the first group only.

## 3. Product Goals

1. **Fast capture** — record an expense in seconds, not minutes.
2. **Consistent categories** — every expense rolls up to a category, so reports are meaningful.
3. **Simple reports** — monthly totals and per-category breakdowns, on demand.
4. **One way in** — every function is reachable from a single web interface.
5. **Service independence** — no single component holds every concern.

## 4. Product Scope

### V1.0 — current

- Create, read, update, and delete expenses.
- Create, read, update, and delete categories.
- Monthly report: total spend and expense count for a given month.
- Category-wise report: spend per category for a given month.
- A web UI over all three APIs, with a page for each area.
- A health endpoint on every API service.

### Future roadmap

The roadmap below is the intended order of work. The phases build on each other: the
foundation has to be safe and repeatable before the platform is worth hardening, and the
platform has to be solid before AI features are built on top of it.

```
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 1: Core DevOps & Infrastructure                                  │
│   1. CI/CD via GitHub Actions (Automated tests, Docker builds, deploys)│ ◄── Current Step
│   2. Security & Secrets Baseline (AWS Secrets Manager/SSM, IAM roles)  │
│   3. IaC Migration (Terraform)                                         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ Phase 2: Production Readiness & Platform Hardening                     │
│   (3. Terraform refinements / complete state lock)                     │
│   4. Foundational Auth & Multi-Tenancy (User context, JWT / Cognito)   │
│   5. Observability (Structured JSON logs, distributed trace IDs, APM)  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ Phase 3: Advanced AI & Product Features                                │
│   6. The MCP Server & Chatbot Layer (Expose tools & conversational UI) │
│   7. Advanced Features & Analytics (Receipt OCR, budgets, alerts)      │
└────────────────────────────────────────────────────────────────────────┘
```

| Phase | Items | What it delivers |
|-------|-------|------------------|
| **1. Core DevOps & Infrastructure** | 1. CI/CD via GitHub Actions · 2. Security and secrets baseline (Secrets Manager/SSM, IAM roles) · 3. IaC migration to Terraform | The stack deploys itself, stops leaking secrets, and stops being a folder of shell scripts |
| **2. Production Readiness & Platform Hardening** | 3. Terraform refinements and a complete state lock · 4. Foundational auth and multi-tenancy (user context, JWT or Cognito) · 5. Observability (structured JSON logs, distributed trace ids, APM) | The stack is safe to run for real users, and debuggable when it goes wrong |
| **3. Advanced AI & Product Features** | 6. The MCP server and chatbot layer (expose the APIs as tools, conversational UI) · 7. Advanced features and analytics (receipt OCR, budgets, alerts) | The tracker becomes queryable by an assistant, and starts to act on the data |

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

## 7. Non-Functional Requirements

| Area | Requirement |
|------|-------------|
| Performance | List and report endpoints respond in well under a second for a personal dataset of thousands of rows. |
| Failure handling | A downstream failure is reported to the caller, not swallowed. `report-service` returns 502, and the UI shows an error. |
| Data durability | Expense and category data survives container removal. |
| Testability | Every API service has an automated test suite. `report-service` tests need no live backends. `ui-service` has no test suite yet. |
| Portability | The full stack runs on a developer machine with one command. |

## 8. Acceptance Criteria

V1.0 is done when:

- [ ] Every API endpoint behaves as specified, including the error cases: 400, 404, 409, 502.
- [ ] `docker compose up --build` starts the stack, the three API health endpoints respond, and the UI loads on port 8501.
- [ ] Each of the four UI pages renders and reaches the APIs it needs.
- [ ] Data written through the API survives `docker compose down` followed by `up`.
- [ ] `report-service` returns a real monthly and category-wise report while the other two services are running.
- [ ] Each API service's test suite passes.
- [ ] The totals in a category-wise report match the expenses that were created.
