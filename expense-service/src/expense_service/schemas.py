from pydantic import BaseModel, Field
from datetime import date

# Request schema
class ExpenseCreate(BaseModel):
    amount: float = Field(gt=0)
    category_id: int = Field(gt=0)
    description: str = Field(min_length=1)
    expense_date: date
