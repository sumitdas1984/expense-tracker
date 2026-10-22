from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import date
from fastapi import Query

from database import Base, engine, SessionLocal
from schemas import ExpenseCreate
from models import Expense

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Expense Service")


# Database session dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Create an expense
@app.post("/expenses", status_code=201)
def create_expense(
    expense: ExpenseCreate,
    db: Session = Depends(get_db)
):
    print(expense)
    new_expense = Expense(**expense.model_dump())

    db.add(new_expense)
    db.commit()
    db.refresh(new_expense)

    return new_expense


# Retrieve all expenses
@app.get("/expenses")
def get_expenses(
    category_id: int | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=10, gt=0, le=100),
    db: Session = Depends(get_db),
):
    if start_date and end_date and start_date > end_date:
        raise HTTPException(
            status_code=400,
            detail="start_date must be before or equal to end_date"
        )

    if category_id is not None and category_id <= 0:
        raise HTTPException(
            status_code=400,
            detail="category_id must be positive"
        )

    query = db.query(Expense)

    if category_id is not None:
        query = query.filter(Expense.category_id == category_id)

    if start_date is not None:
        query = query.filter(Expense.expense_date >= start_date)

    if end_date is not None:
        query = query.filter(Expense.expense_date <= end_date)

    expenses = query.offset(skip).limit(limit).all()

    return expenses


# Retrieve a single expense by ID
@app.get("/expenses/{expense_id}")
def get_expense(expense_id: int, db: Session = Depends(get_db)):
    expense = db.query(Expense).filter(Expense.id == expense_id).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found")
    return expense


# Update an expense by ID
@app.put("/expenses/{expense_id}")
def update_expense(expense_id: int, expense: ExpenseCreate, db: Session = Depends(get_db)):
    existing_expense = db.query(Expense).filter(Expense.id == expense_id).first()
    if not existing_expense:
        raise HTTPException(status_code=404, detail="Expense not found")
    for key, value in expense.model_dump().items():
        setattr(existing_expense, key, value)
    db.commit()
    db.refresh(existing_expense)
    return existing_expense


# Delete an expense by ID
@app.delete("/expenses/{expense_id}", status_code=204)
def delete_expense(expense_id: int, db: Session = Depends(get_db)):
    existing_expense = db.query(Expense).filter(Expense.id == expense_id).first()
    if not existing_expense:
        raise HTTPException(status_code=404, detail="Expense not found")
    db.delete(existing_expense)
    db.commit()
    return None
