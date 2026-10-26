import os

EXPENSE_SERVICE_URL = os.getenv(
    "EXPENSE_SERVICE_URL", "http://localhost:8001"
)

CATEGORY_SERVICE_URL = os.getenv(
    "CATEGORY_SERVICE_URL", "http://localhost:8002"
)

REPORT_SERVICE_URL = os.getenv(
    "REPORT_SERVICE_URL", "http://localhost:8003"
)