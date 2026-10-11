from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from app.schemas.location import Coordinates


class SavedAddress(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    recipient_name: str = Field(..., min_length=2, max_length=200)
    phone: str = Field(..., pattern=r"^[6-9][0-9]{9}$")
    building: str = Field(..., min_length=1, max_length=100)
    street: str = Field(..., min_length=2, max_length=200)
    locality: str = Field(..., min_length=2, max_length=200)
    city: str = Field(..., min_length=2, max_length=100)
    state: str = Field(..., min_length=2, max_length=100)
    postal_code: str = Field(..., pattern=r"^[1-9][0-9]{5}$")
    instructions: str = Field("", max_length=500)
    coordinates: Optional[Coordinates] = None
    is_default: bool = False

    def checkout(self):
        values = self.model_dump(exclude={"is_default"})
        values["address"] = ", ".join(getattr(self, k) for k in ("building", "street", "locality", "city", "state"))
        return values
