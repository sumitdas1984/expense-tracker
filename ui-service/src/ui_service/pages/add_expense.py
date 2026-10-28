import requests
import streamlit as st

from ui_service.config import EXPENSE_SERVICE_URL
from ui_service.pages import fetch_categories


def show_add_expense():
    st.subheader("Add Expense")

    # Fetch categories from Category Service
    categories = fetch_categories()

    if categories is None:
        st.error("Unable to fetch categories. Please check the Category Service.")
        st.stop()

    if not categories:
        st.warning("Please create a category before adding an expense.")
        st.stop()

    category_options = {
        category["name"]: category["id"]
        for category in categories
    }

    with st.form("expense_form"):
        amount = st.number_input(
            "Amount",
            min_value=0.00,
            step=100.0,
        )

        category_name = st.selectbox(
            "Category",
            options=list(category_options.keys()),
        )

        description = st.text_input("Description")

        expense_date = st.date_input("Expense Date")

        submitted = st.form_submit_button("Add Expense")

        if submitted:
            payload = {
                "amount": amount,
                "category_id": category_options[category_name],
                "description": description,
                "expense_date": expense_date.isoformat(),
            }

            try:
                response = requests.post(
                    f"{EXPENSE_SERVICE_URL}/expenses",
                    json=payload,
                    timeout=5,
                )
                response.raise_for_status()
                st.success("Expense added successfully!")

            except requests.RequestException as error:
                st.error(f"Failed to add expense: {error}")
