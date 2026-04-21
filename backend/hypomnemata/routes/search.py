from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from ..crud import to_out
from ..db import get_session
from ..models import Item, ItemTag, Tag
from ..schemas import ItemList

router = APIRouter(prefix="/search", tags=["search"])


def _sanitize_fts_query(q: str) -> str:
    """Wrap tokens so FTS5 treats user input as prefix-matching tokens, not syntax."""
    tokens = [t for t in q.replace('"', " ").split() if t]
    if not tokens:
        return '""'
    return " ".join(f'"{t}"*' for t in tokens)


@router.get("", response_model=ItemList)
async def search(
    q: str = Query(min_length=1),
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_session),
) -> ItemList:
    fts_q = _sanitize_fts_query(q)
    sql = text(
        """
        SELECT items.id AS id
        FROM items_fts
        JOIN items ON items.rowid = items_fts.rowid
        WHERE items_fts MATCH :q
        ORDER BY bm25(items_fts)
        LIMIT :lim OFFSET :off
        """
    )
    ids = [r[0] for r in (await db.execute(sql, {"q": fts_q, "lim": limit, "off": offset})).all()]
    if not ids:
        return ItemList(items=[], total=0)

    orm_items = list((await db.execute(select(Item).where(Item.id.in_(ids)))).scalars().all())
    order = {id_: idx for idx, id_ in enumerate(ids)}
    orm_items = sorted(orm_items, key=lambda i: order.get(i.id, 10**9))

    tag_stmt = (
        select(ItemTag.item_id, Tag.name)
        .join(Tag, Tag.id == ItemTag.tag_id)
        .where(ItemTag.item_id.in_(ids))
    )
    tag_map: dict[str, list[str]] = {iid: [] for iid in ids}
    for iid, name in (await db.execute(tag_stmt)).all():
        tag_map[iid].append(name)
    for iid in tag_map:
        tag_map[iid].sort()

    return ItemList(
        items=[to_out(i, tag_names=tag_map.get(i.id, [])) for i in orm_items],
        total=len(orm_items),
    )
