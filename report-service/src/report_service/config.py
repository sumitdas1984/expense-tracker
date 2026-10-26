import os

EXPENSE_SERVICE_URL = os.getenv(
    "EXPENSE_SERVICE_URL", "http://localhost:8001"
)

CATEGORY_SERVICE_URL = os.getenv(
    "CATEGORY_SERVICE_URL", "http://localhost:8002"
)
