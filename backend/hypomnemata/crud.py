from __future__ import annotations

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import Item, ItemTag, Tag, ItemLink
from .schemas import ItemOut, ItemSummary


async def ensure_tags(db: AsyncSession, names: list[str]) -> list[Tag]:
    clean = sorted({n.strip().lower() for n in names if n and n.strip()})
    if not clean:
        return []
    existing = (await db.execute(select(Tag).where(Tag.name.in_(clean)))).scalars().all()
    existing_names = {t.name for t in existing}
    for name in clean:
        if name not in existing_names:
            db.add(Tag(name=name))
    await db.flush()
    return list(
        (await db.execute(select(Tag).where(Tag.name.in_(clean)))).scalars().all()
    )


import re

async def set_item_tags(db: AsyncSession, item: Item, names: list[str]) -> None:
    """Replace the item's tags. Uses direct ItemTag rows to avoid triggering
    a lazy load on item.tags in async context."""
    await db.execute(delete(ItemTag).where(ItemTag.item_id == item.id))
    tags = await ensure_tags(db, names)
    for t in tags:
        db.add(ItemTag(item_id=item.id, tag_id=t.id))
    await db.flush()

async def sync_item_links(db: AsyncSession, item: Item) -> None:
    """Extrai [[ID]] dos campos de texto e sincroniza os links."""
    text = (item.note or "") + " " + (item.body_text or "")
    
    # Regex para extrair UUIDs dentro de colchetes [[...]] (ignorando possível pipe de título)
    pattern = r"\[\[([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:\|[^\]]*)?\]\]"
    matches = re.findall(pattern, text)
    unique_targets = set(matches)
    
    # Não permitir link para si mesmo
    if item.id in unique_targets:
        unique_targets.remove(item.id)
        
    await db.execute(delete(ItemLink).where(ItemLink.source_id == item.id))
    
    # Valida se os targets realmente existem no banco antes de inserir para não quebrar a FK
    if unique_targets:
        stmt = select(Item.id).where(Item.id.in_(unique_targets))
        valid_targets = set((await db.execute(stmt)).scalars().all())
        
        for t_id in valid_targets:
            db.add(ItemLink(source_id=item.id, target_id=t_id))
    
    await db.flush()


async def load_tag_names(db: AsyncSession, item_id: str) -> list[str]:
    stmt = (
        select(Tag.name)
        .join(ItemTag, ItemTag.tag_id == Tag.id)
        .where(ItemTag.item_id == item_id)
        .order_by(Tag.name)
    )
    return [r[0] for r in (await db.execute(stmt)).all()]


async def load_links(db: AsyncSession, item_id: str) -> list[dict]:
    stmt = (
        select(Item.id, Item.title, Item.kind, Item.captured_at)
        .join(ItemLink, ItemLink.target_id == Item.id)
        .where(ItemLink.source_id == item_id)
        .order_by(Item.captured_at.desc())
    )
    return [{"id": r.id, "title": r.title, "kind": r.kind, "captured_at": r.captured_at} for r in (await db.execute(stmt)).all()]


async def load_backlinks(db: AsyncSession, item_id: str) -> list[dict]:
    stmt = (
        select(Item.id, Item.title, Item.kind, Item.captured_at)
        .join(ItemLink, ItemLink.source_id == Item.id)
        .where(ItemLink.target_id == item_id)
        .order_by(Item.captured_at.desc())
    )
    return [{"id": r.id, "title": r.title, "kind": r.kind, "captured_at": r.captured_at} for r in (await db.execute(stmt)).all()]


def to_out(
    item: Item, 
    tag_names: list[str] | None = None,
    links: list[dict] | None = None,
    backlinks: list[dict] | None = None,
) -> ItemOut:
    tags = tag_names if tag_names is not None else sorted(t.name for t in item.tags)
    return ItemOut(
        id=item.id,
        kind=item.kind,
        source_url=item.source_url,
        title=item.title,
        note=item.note,
        body_text=item.body_text,
        asset_path=item.asset_path,
        meta_json=item.meta_json,
        ocr_status=item.ocr_status,
        download_status=item.download_status,
        captured_at=item.captured_at,
        created_at=item.created_at,
        tags=tags,
        links=[ItemSummary(**lnk) for lnk in (links or [])],
        backlinks=[ItemSummary(**lnk) for lnk in (backlinks or [])],
    )


def set_item_tags_sync(db, item_id: str, names: list[str]) -> None:
    """Versão síncrona de set_item_tags para uso em workers (Session síncrona)."""
    from sqlalchemy import delete as sa_delete, select as sa_select
    clean = sorted({n.strip().lower() for n in names if n and n.strip()})
    db.execute(sa_delete(ItemTag).where(ItemTag.item_id == item_id))
    for name in clean:
        tag = db.execute(sa_select(Tag).where(Tag.name == name)).scalar_one_or_none()
        if not tag:
            tag = Tag(name=name)
            db.add(tag)
            db.flush()
        db.add(ItemTag(item_id=item_id, tag_id=tag.id))
    db.flush()


async def tag_counts(db: AsyncSession) -> list[tuple[str, int]]:
    stmt = (
        select(Tag.name, func.count(ItemTag.item_id))
        .join(ItemTag, ItemTag.tag_id == Tag.id)
        .group_by(Tag.name)
        .order_by(func.count(ItemTag.item_id).desc(), Tag.name)
    )
    return [(row[0], row[1]) for row in (await db.execute(stmt)).all()]
