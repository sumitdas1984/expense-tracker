import requests
import streamlit as st

from ui_service.config import CATEGORY_SERVICE_URL
from ui_service.pages import fetch_categories


def show_category_management():
    st.header("Category Management")

    # Display existing categories
    all_categories = fetch_categories()

    if all_categories is None:
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
