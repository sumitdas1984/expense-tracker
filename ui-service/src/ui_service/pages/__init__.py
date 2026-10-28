"""Page modules for the expense tracker UI."""

import requests

from ui_service.config import CATEGORY_SERVICE_URL


def fetch_categories():
    """Return the list of categories, or None if the service is unreachable."""
    try:
        response = requests.get(
            f"{CATEGORY_SERVICE_URL}/categories",
            timeout=5,
        )
        response.raise_for_status()
        return response.json()

    except requests.RequestException:
        return None
