from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from uuid_utils.compat import uuid7


class Base(DeclarativeBase):
    pass


def _uuid7_str() -> str:
    return str(uuid7())


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Item(Base):
    __tablename__ = "items"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid7_str)
    kind: Mapped[str] = mapped_column(String, nullable=False, index=True)
    source_url: Mapped[str | None] = mapped_column(Text)
    title: Mapped[str | None] = mapped_column(Text)
    note: Mapped[str | None] = mapped_column(Text)
    body_text: Mapped[str | None] = mapped_column(Text)
    asset_path: Mapped[str | None] = mapped_column(Text)
    meta_json: Mapped[str | None] = mapped_column(Text)
    ocr_status: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    download_status: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    captured_at: Mapped[str] = mapped_column(String, nullable=False, default=_utcnow_iso, index=True)
    created_at: Mapped[str] = mapped_column(String, nullable=False, default=_utcnow_iso)

    tags: Mapped[list["Tag"]] = relationship(
        secondary="item_tags", back_populates="items", lazy="selectin"
    )


class Tag(Base):
    __tablename__ = "tags"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String, unique=True, nullable=False, index=True)

    items: Mapped[list[Item]] = relationship(secondary="item_tags", back_populates="tags")


class ItemTag(Base):
    __tablename__ = "item_tags"
    __table_args__ = (UniqueConstraint("item_id", "tag_id", name="uq_item_tag"),)

    item_id: Mapped[str] = mapped_column(
        String, ForeignKey("items.id", ondelete="CASCADE"), primary_key=True
    )
    tag_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tags.id", ondelete="CASCADE"), primary_key=True
    )


KINDS = {"image", "article", "video", "tweet", "bookmark", "note", "pdf"}
