# PRD — Expense Tracker

## 1. Project Overview

A personal expense tracking system. Users record expenses against categories and review
spending through monthly and category-wise reports.

The system is built as a set of small independent services, so each concern — expenses,
categories, reporting — can evolve, deploy, and be tested on its own.

V1.0 is a working system: record expenses, manage categories, and see reports. Everything
listed under future scope is a direction, not a commitment.

## 2. Target Users

- **Individual users** who want a clear picture of where their money goes each month.
- **Developers** (future) who want to query expense data from an AI assistant through MCP.

V1.0 serves the first group only.

## 3. Product Goals

1. **Fast capture** — record an expense in seconds, not minutes.
2. **Consistent categories** — every expense rolls up to a category, so reports are meaningful.
3. **Simple reports** — monthly totals and per-category breakdowns, on demand.
4. **Service independence** — no single component holds every concern.

## 4. Product Scope

### V1.0 — current

- Create, read, update, and delete expenses.
- Create, read, update, and delete categories.
- Monthly report: total spend and expense count for a given month.
- Category-wise report: spend per category for a given month.
- A health endpoint on every service.

### Future — not in V1.0

- **UI service** — a web interface over the three APIs.
- **MCP server** — expose the expense APIs as tools so an AI assistant can read and write expenses.
- **Agentic chatbot** — conversational entry and querying built on MCP.
- **Authentication and multi-user support** — V1.0 is a single shared dataset.
- **AWS deployment** — hosting, managed databases, CI/CD.
- **Recurring expenses, budgets, and notifications.**

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

### Availability

| ID | Requirement |
|----|-------------|
| A-1 | Every service exposes a health endpoint reporting healthy status. |

## 6. User Workflows

**Record an expense**

1. Look up a category, for example Food.
2. Submit the amount, description, and date.
3. The expense appears in the expense list.

**Review the month**

1. Request the monthly report for the month.
2. See total spend and how many expenses it covers.
3. Request the category-wise report to see which categories drove the total.

**Fix a mistake**

1. Fetch the expense by id.
2. Update it with corrected values, or delete it.

## 7. Non-Functional Requirements

| Area | Requirement |
|------|-------------|
| Performance | List and report endpoints respond in well under a second for a personal dataset of thousands of rows. |
| Failure handling | A downstream failure is reported to the caller, not swallowed. `report-service` returns 502. |
| Data durability | Expense and category data survives container removal. |
| Testability | Every service has an automated test suite. `report-service` tests need no live backends. |
| Portability | The full stack runs on a developer machine with one command. |

## 8. Acceptance Criteria

V1.0 is done when:

- [ ] Every endpoint behaves as specified, including the error cases: 400, 404, 409, 502.
- [ ] `docker compose up --build` starts the stack and all three health endpoints respond.
- [ ] Data written through the API survives `docker compose down` followed by `up`.
- [ ] `report-service` returns a real monthly and category-wise report while the other two services are running.
- [ ] Each service's test suite passes.
- [ ] The totals in a category-wise report match the expenses that were created.
