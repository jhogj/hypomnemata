from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

from .models import KINDS

Kind = Literal["image", "article", "video", "tweet", "bookmark", "note", "pdf"]


class ItemSummary(BaseModel):
    id: str
    title: str | None = None
    kind: str
    captured_at: str

class ItemOut(BaseModel):
    id: str
    kind: str
    source_url: str | None = None
    title: str | None = None
    note: str | None = None
    body_text: str | None = None
    asset_path: str | None = None
    meta_json: str | None = None
    ocr_status: str | None = None
    download_status: str | None = None
    captured_at: str
    created_at: str
    tags: list[str] = Field(default_factory=list)
    links: list[ItemSummary] = Field(default_factory=list)
    backlinks: list[ItemSummary] = Field(default_factory=list)


class ItemList(BaseModel):
    items: list[ItemOut]
    total: int


class ItemPatch(BaseModel):
    title: str | None = None
    note: str | None = None
    body_text: str | None = None
    tags: list[str] | None = None

    @field_validator("tags")
    @classmethod
    def _strip_tags(cls, v: list[str] | None) -> list[str] | None:
        if v is None:
            return None
        return [t.strip().lower() for t in v if t.strip()]


class TagCount(BaseModel):
    name: str
    count: int


class CaptureResult(BaseModel):
    id: str


def validate_kind(value: str) -> str:
    if value not in KINDS:
        raise ValueError(f"invalid kind: {value!r}. valid: {sorted(KINDS)}")
    return value
