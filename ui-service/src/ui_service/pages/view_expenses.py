import requests
import streamlit as st

from ui_service.config import EXPENSE_SERVICE_URL
from ui_service.pages import fetch_categories


def show_view_expenses():
    st.subheader("View Expenses")

    categories = fetch_categories()

    if categories is None:
        st.error("Unable to fetch categories. Please check the Category Service.")
        st.stop()

    # Category filter
    category_options = {
        "All Categories": None
    }

    for category in categories:
        category_options[category["name"]] = category["id"]

    with st.form("expense_filter_form"):
        col1, col2, col3 = st.columns(3)

        with col1:
            selected_category = st.selectbox(
                "Category",
                options=list(category_options.keys()),
            )

        with col2:
            start_date = st.date_input(
                "Start Date",
                value=None,
            )

        with col3:
            end_date = st.date_input(
                "End Date",
                value=None,
            )

        apply_filters = st.form_submit_button("Apply Filters")

    # Fetch expenses when filters are applied
    if apply_filters:
        params = {
            "skip": 0,
            "limit": 100,
        }

        category_id = category_options[selected_category]

        if category_id is not None:
            params["category_id"] = category_id

        if start_date:
            params["start_date"] = start_date.isoformat()

        if end_date:
            params["end_date"] = end_date.isoformat()

        if start_date and end_date and start_date > end_date:
            st.error("Start Date cannot be after End Date.")

        else:
            try:
                response = requests.get(
                    f"{EXPENSE_SERVICE_URL}/expenses",
                    params=params,
                    timeout=5,
                )
                response.raise_for_status()
                expenses = response.json()

                if expenses:
                    category_names = {
                        category["id"]: category["name"]
                        for category in categories
                    }

                    expense_rows = []

                    for expense in expenses:
                        expense_rows.append({
                            "Date": expense["expense_date"],
                            "Category": category_names.get(
                                expense["category_id"], "Unknown"
                            ),
                            "Description": expense["description"],
                            "Amount": expense["amount"],
                        })

                    st.dataframe(
                        expense_rows,
                        use_container_width=True,
                        hide_index=True,
                    )

                else:
                    st.info("No expenses found for the selected filters.")

            except requests.RequestException:
                st.error("Unable to fetch expenses. Please try again.")
