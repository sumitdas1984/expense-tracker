import requests
import streamlit as st

from ui_service.config import (
    EXPENSE_SERVICE_URL,
    CATEGORY_SERVICE_URL,
    REPORT_SERVICE_URL,
)

st.set_page_config(
    page_title="Personal Expense Tracker",
    page_icon="💰",
    layout="wide",
)

#################################### ADD EXPENSE SECTION ####################################
st.title("Personal Expense Tracker")
st.subheader("Add Expense")

# Fetch categories from Category Service
try:
    response = requests.get(
        f"{CATEGORY_SERVICE_URL}/categories",
        timeout=5,
    )
    response.raise_for_status()
    categories = response.json()

except requests.RequestException:
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
        min_value=0.01,
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

##################################### VIEW EXPENSES SECTION ####################################
st.divider()
st.subheader("View Expenses")

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

########################### VIEW CATEGORIES MANAGEMENT SECTION ###############################
st.divider()
st.header("Category Management")

# Display existing categories
try:
    response = requests.get(
        f"{CATEGORY_SERVICE_URL}/categories",
        timeout=5,
    )
    response.raise_for_status()
    all_categories = response.json()

except requests.RequestException:
    st.error("Unable to fetch categories.")
    all_categories = []

# View categories
st.subheader("Existing Categories")

if all_categories:
    category_rows = []

    for category in all_categories:
        category_rows.append({
            "ID": category["id"],
            "Name": category["name"],
            "Description": category.get("description") or "",
        })

    st.dataframe(
        category_rows,
        use_container_width=True,
        hide_index=True,
    )
else:
    st.info("No categories found.")

# Add category
st.subheader("Add Category")

with st.form("add_category_form"):
    new_category_name = st.text_input("Category Name")
    new_category_description = st.text_input("Description")

    add_category = st.form_submit_button("Add Category")

    if add_category:
        if not new_category_name.strip():
            st.error("Category name is required.")
        else:
            payload = {
                "name": new_category_name.strip(),
                "description": new_category_description.strip() or None,
            }

            try:
                response = requests.post(
                    f"{CATEGORY_SERVICE_URL}/categories",
                    json=payload,
                    timeout=5,
                )
                response.raise_for_status()
                st.success("Category added successfully.")
                st.rerun()

            except requests.HTTPError as error:
                if error.response.status_code == 409:
                    st.error("A category with this name already exists.")
                else:
                    st.error("Failed to add category.")

            except requests.RequestException:
                st.error("Unable to connect to the Category Service.")

# Update category
st.subheader("Update Category")

if all_categories:
    category_ids = {
        f"{category['name']} (ID: {category['id']})": category
        for category in all_categories
    }

    selected_update = st.selectbox(
        "Select category to update",
        options=list(category_ids.keys()),
        key="update_category",
    )

    selected_category = category_ids[selected_update]

    with st.form("update_category_form"):
        updated_name = st.text_input(
            "Category Name",
            value=selected_category["name"],
        )

        updated_description = st.text_input(
            "Description",
            value=selected_category.get("description") or "",
        )

        update_category = st.form_submit_button("Update Category")

        if update_category:
            if not updated_name.strip():
                st.error("Category name is required.")
            else:
                payload = {
                    "name": updated_name.strip(),
                    "description": updated_description.strip() or None,
                }

                try:
                    response = requests.put(
                        f"{CATEGORY_SERVICE_URL}/categories/"
                        f"{selected_category['id']}",
                        json=payload,
                        timeout=5,
                    )
                    response.raise_for_status()
                    st.success("Category updated successfully.")
                    st.rerun()

                except requests.HTTPError as error:
                    if error.response.status_code == 409:
                        st.error("A category with this name already exists.")
                    elif error.response.status_code == 404:
                        st.error("Category not found.")
                    else:
                        st.error("Failed to update category.")

                except requests.RequestException:
                    st.error("Unable to connect to the Category Service.")

# Delete category
st.subheader("Delete Category")

if all_categories:
    selected_delete = st.selectbox(
        "Select category to delete",
        options=list(category_ids.keys()),
        key="delete_category",
    )

    category_to_delete = category_ids[selected_delete]

    confirm_delete = st.checkbox(
        f"Confirm deletion of '{category_to_delete['name']}'",
        key="confirm_delete",
    )

    if st.button("Delete Category", disabled=not confirm_delete):
        try:
            response = requests.delete(
                f"{CATEGORY_SERVICE_URL}/categories/"
                f"{category_to_delete['id']}",
                timeout=5,
            )
            response.raise_for_status()
            st.success("Category deleted successfully.")
            st.rerun()

        except requests.HTTPError as error:
            if error.response.status_code == 404:
                st.error("Category not found.")
            else:
                st.error("Failed to delete category.")

        except requests.RequestException:
            st.error("Unable to connect to the Category Service.")

################################### REPORT GENERATION SECTION ####################################
st.divider()
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