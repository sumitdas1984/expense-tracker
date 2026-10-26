import requests
import streamlit as st

from ui_service.config import REPORT_SERVICE_URL


def show_expense_report():
    st.header("Expense Reports")

    report_year = st.number_input(
        "Year",
        min_value=2000,
        max_value=2100,
        value=2026,
        step=1,
    )

    report_month = st.selectbox(
        "Month",
        options=list(range(1, 13)),
        format_func=lambda month: [
            "January", "February", "March", "April",
            "May", "June", "July", "August",
            "September", "October", "November", "December",
        ][month - 1],
    )

    if st.button("Generate Reports"):
        params = {
            "year": int(report_year),
            "month": report_month,
        }

        # Monthly summary
        st.subheader("Monthly Summary")

        try:
            response = requests.get(
                f"{REPORT_SERVICE_URL}/reports/monthly",
                params=params,
                timeout=10,
            )
            response.raise_for_status()
            monthly_report = response.json()

            col1, col2 = st.columns(2)

            col1.metric(
                "Total Expenses",
                f"₹{monthly_report['total_expenses']:,.2f}",
            )

            col2.metric(
                "Number of Expenses",
                monthly_report["expense_count"],
            )

        except requests.RequestException:
            st.error("Unable to generate the monthly report.")

        # Category-wise report
        st.subheader("Category-wise Breakdown")

        try:
            response = requests.get(
                f"{REPORT_SERVICE_URL}/reports/category-wise",
                params=params,
                timeout=10,
            )
            response.raise_for_status()
            category_report = response.json()

            categories_data = category_report.get("categories", [])

            if categories_data:
                st.dataframe(
                    categories_data,
                    use_container_width=True,
                    hide_index=True,
                )

                chart_data = {
                    item["category"]: item["total_amount"]
                    for item in categories_data
                }

                st.bar_chart(chart_data)

            else:
                st.info("No expenses found for the selected month.")

        except requests.RequestException:
            st.error("Unable to generate the category-wise report.")
