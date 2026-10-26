from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session

from .database import Base, engine, SessionLocal
from .models import Category
from .schemas import CategoryCreate, CategoryUpdate, CategoryResponse

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Category Service")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Create a category
@app.post("/categories", response_model=CategoryResponse, status_code=201)
def create_category(category: CategoryCreate, db: Session = Depends(get_db)):
    existing = db.query(Category).filter(Category.name == category.name).first()

    if existing:
        raise HTTPException(status_code=409, detail="Category already exists")

    new_category = Category(**category.model_dump())
    db.add(new_category)
    db.commit()
    db.refresh(new_category)

    return new_category


# Retrieve all categories
@app.get("/categories", response_model=list[CategoryResponse])
def get_categories(db: Session = Depends(get_db)):
    return db.query(Category).all()


# Retrieve a category by ID
@app.get("/categories/{category_id}", response_model=CategoryResponse)
def get_category(category_id: int, db: Session = Depends(get_db)):
    category = db.query(Category).filter(Category.id == category_id).first()

    if not category:
        raise HTTPException(status_code=404, detail="Category not found")

    return category


# Update a category
@app.put("/categories/{category_id}", response_model=CategoryResponse)
def update_category(
    category_id: int,
    category: CategoryUpdate,
    db: Session = Depends(get_db)
):
    existing = db.query(Category).filter(Category.id == category_id).first()

    if not existing:
        raise HTTPException(status_code=404, detail="Category not found")

    duplicate = db.query(Category).filter(
        Category.name == category.name,
        Category.id != category_id
    ).first()

    if duplicate:
        raise HTTPException(status_code=409, detail="Category name already exists")

    for key, value in category.model_dump().items():
        setattr(existing, key, value)

    db.commit()
    db.refresh(existing)

    return existing


# Delete a category
@app.delete("/categories/{category_id}", status_code=204)
def delete_category(category_id: int, db: Session = Depends(get_db)):
    category = db.query(Category).filter(Category.id == category_id).first()

    if not category:
        raise HTTPException(status_code=404, detail="Category not found")

    db.delete(category)
    db.commit()
    return None