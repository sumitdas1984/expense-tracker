import streamlit as st

from ui_service.pages.add_expense import show_add_expense
from ui_service.pages.view_expenses import show_view_expenses
from ui_service.pages.category_management import show_category_management
from ui_service.pages.expense_report import show_expense_report

st.set_page_config(
    page_title="Personal Expense Tracker",
    page_icon="💰",
    layout="wide",
)

st.title("Personal Expense Tracker")

page = st.sidebar.radio(
    "Navigation",
    [
        "Add Expense",
        "View Expenses",
        "Category Management",
        "Expense Report",
    ],
)

if page == "Add Expense":
    show_add_expense()
elif page == "View Expenses":
    show_view_expenses()
elif page == "Category Management":
    show_category_management()
else:
    show_expense_report()
