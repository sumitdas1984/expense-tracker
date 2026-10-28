# ui-service

Streamlit web UI for the expense tracker. It talks to `expense-service` (8001),
`category-service` (8002), and `report-service` (8003) over HTTP — it has no database of
its own.

```
src/ui_service/
├── main.py                       entry point and sidebar navigation
├── config.py                     backend service URLs
└── pages/
    ├── add_expense.py            Add Expense form
    ├── view_expenses.py          expense listing and filters
    ├── category_management.py    category CRUD
    └── expense_report.py         monthly and category-wise reports
```

## Configuration

| Env var | Default |
|---------|---------|
| `EXPENSE_SERVICE_URL` | `http://localhost:8001` |
| `CATEGORY_SERVICE_URL` | `http://localhost:8002` |
| `REPORT_SERVICE_URL` | `http://localhost:8003` |

## Run

The three backend services must be running first.

Local:

```bash
uv sync
uv run streamlit run src/ui_service/main.py --server.port 8501
```

Docker:

```bash
docker build -t ui-service .
docker run -p 8501:8501 ui-service
```

Open http://localhost:8501.

## Pages

| Page | What it does |
|------|--------------|
| Add Expense | Pick a category, enter amount, description, and date |
| View Expenses | List expenses with category and date-range filters |
| Category Management | List, add, update, and delete categories |
| Expense Report | Monthly total and category-wise breakdown for a chosen month |
