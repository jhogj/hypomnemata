from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, field_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..models import Folder, FolderItem, _uuid7_str, _utcnow_iso

router = APIRouter(prefix="/folders", tags=["folders"])


class FolderCreate(BaseModel):
    name: str

    @field_validator("name")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("name must not be empty or whitespace")
        return v


class FolderRename(FolderCreate):
    pass


class FolderItemsAdd(BaseModel):
    item_ids: list[str]


@router.get("")
async def list_folders(db: AsyncSession = Depends(get_session)):
    folders = list((await db.execute(select(Folder).order_by(Folder.created_at))).scalars().all())
    counts_rows = (await db.execute(
        select(FolderItem.folder_id, func.count(FolderItem.item_id)).group_by(FolderItem.folder_id)
    )).all()
    counts = {row[0]: row[1] for row in counts_rows}
    return [{"id": f.id, "name": f.name, "item_count": counts.get(f.id, 0)} for f in folders]


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_folder(payload: FolderCreate, db: AsyncSession = Depends(get_session)):
    folder = Folder(id=_uuid7_str(), name=payload.name.strip(), created_at=_utcnow_iso())
    db.add(folder)
    await db.commit()
    return {"id": folder.id, "name": folder.name, "item_count": 0}


@router.patch("/{folder_id}")
async def rename_folder(folder_id: str, payload: FolderRename, db: AsyncSession = Depends(get_session)):
    folder = await db.get(Folder, folder_id)
    if folder is None:
        raise HTTPException(404, "folder not found")
    folder.name = payload.name.strip()
    await db.commit()
    count = (await db.execute(
        select(func.count(FolderItem.item_id)).where(FolderItem.folder_id == folder_id)
    )).scalar_one()
    return {"id": folder.id, "name": folder.name, "item_count": count}


@router.delete("/{folder_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_folder(folder_id: str, db: AsyncSession = Depends(get_session)):
    folder = await db.get(Folder, folder_id)
    if folder is None:
        raise HTTPException(404, "folder not found")
    await db.delete(folder)
    await db.commit()


@router.post("/{folder_id}/items", status_code=status.HTTP_204_NO_CONTENT)
async def add_items_to_folder(folder_id: str, payload: FolderItemsAdd, db: AsyncSession = Depends(get_session)):
    folder = await db.get(Folder, folder_id)
    if folder is None:
        raise HTTPException(404, "folder not found")
    for item_id in payload.item_ids:
        existing = await db.get(FolderItem, (folder_id, item_id))
        if existing is None:
            db.add(FolderItem(folder_id=folder_id, item_id=item_id, added_at=_utcnow_iso()))
    await db.commit()


@router.delete("/{folder_id}/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_item_from_folder(folder_id: str, item_id: str, db: AsyncSession = Depends(get_session)):
    fi = await db.get(FolderItem, (folder_id, item_id))
    if fi is not None:
        await db.delete(fi)
        await db.commit()
