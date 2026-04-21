from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..crud import tag_counts
from ..db import get_session
from ..schemas import TagCount

router = APIRouter(prefix="/tags", tags=["tags"])


@router.get("", response_model=list[TagCount])
async def list_tags(db: AsyncSession = Depends(get_session)) -> list[TagCount]:
    return [TagCount(name=n, count=c) for n, c in await tag_counts(db)]
