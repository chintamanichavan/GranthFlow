from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

HighlightColor = Literal["yellow", "green", "pink", "blue"]


class HighlightCreate(BaseModel):
    cfi: str = Field(min_length=1)
    text: str = Field(min_length=1)
    color: HighlightColor = "yellow"
    note: str | None = None
    tags: list[str] = Field(default_factory=list)


class HighlightUpdate(BaseModel):
    color: HighlightColor | None = None
    note: str | None = None
    tags: list[str] | None = None


class LocationUpdate(BaseModel):
    cfi: str = Field(min_length=1)


class HighlightOut(BaseModel):
    id: int
    book_id: int
    cfi: str
    text: str
    note: str | None
    color: str
    created_at: str
    tags: list[str]
