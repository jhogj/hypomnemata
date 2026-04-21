from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..crud import load_tag_names, set_item_tags, to_out
from ..db import get_session
from ..models import Item, ItemTag, Tag
from ..schemas import ItemList, ItemOut, ItemPatch
from ..storage import delete_asset

router = APIRouter(prefix="/items", tags=["items"])

Order = Literal["captured_at_desc", "captured_at_asc", "created_at_desc"]


async def _collect_tag_names(db: AsyncSession, item_ids: list[str]) -> dict[str, list[str]]:
    if not item_ids:
        return {}
    stmt = (
        select(ItemTag.item_id, Tag.name)
        .join(Tag, Tag.id == ItemTag.tag_id)
        .where(ItemTag.item_id.in_(item_ids))
    )
    acc: dict[str, list[str]] = {iid: [] for iid in item_ids}
    for iid, name in (await db.execute(stmt)).all():
        acc[iid].append(name)
    for iid in acc:
        acc[iid].sort()
    return acc


@router.get("", response_model=ItemList)
async def list_items(
    kind: str | None = Query(default=None),
    tag: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    order: Order = Query(default="captured_at_desc"),
    db: AsyncSession = Depends(get_session),
) -> ItemList:
    stmt = select(Item)
    count_stmt = select(func.count(Item.id))

    if kind:
        stmt = stmt.where(Item.kind == kind)
        count_stmt = count_stmt.where(Item.kind == kind)
    if tag:
        sub = (
            select(ItemTag.item_id)
            .join(Tag, Tag.id == ItemTag.tag_id)
            .where(Tag.name == tag.strip().lower())
        )
        stmt = stmt.where(Item.id.in_(sub))
        count_stmt = count_stmt.where(Item.id.in_(sub))

    match order:
        case "captured_at_asc":
            stmt = stmt.order_by(Item.captured_at.asc())
        case "created_at_desc":
            stmt = stmt.order_by(Item.created_at.desc())
        case _:
            stmt = stmt.order_by(Item.captured_at.desc())

    stmt = stmt.limit(limit).offset(offset)
    items = list((await db.execute(stmt)).scalars().all())
    tag_map = await _collect_tag_names(db, [i.id for i in items])
    total = (await db.execute(count_stmt)).scalar_one()
    return ItemList(
        items=[to_out(i, tag_names=tag_map.get(i.id, [])) for i in items],
        total=total,
    )


@router.get("/{item_id}", response_model=ItemOut)
async def get_item(item_id: str, db: AsyncSession = Depends(get_session)) -> ItemOut:
    item = await db.get(Item, item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="item not found")
    names = await load_tag_names(db, item.id)
    return to_out(item, tag_names=names)


@router.patch("/{item_id}", response_model=ItemOut)
async def patch_item(
    item_id: str, patch: ItemPatch, db: AsyncSession = Depends(get_session)
) -> ItemOut:
    item = await db.get(Item, item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="item not found")

    data = patch.model_dump(exclude_unset=True)
    if "title" in data:
        item.title = data["title"]
    if "note" in data:
        item.note = data["note"]
    if "body_text" in data:
        item.body_text = data["body_text"]
    if "tags" in data:
        await set_item_tags(db, item, data["tags"] or [])

    await db.commit()
    names = await load_tag_names(db, item.id)
    return to_out(item, tag_names=names)


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(item_id: str, db: AsyncSession = Depends(get_session)) -> None:
    item = await db.get(Item, item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="item not found")
    asset = item.asset_path
    await db.delete(item)
    await db.commit()
    delete_asset(asset)
