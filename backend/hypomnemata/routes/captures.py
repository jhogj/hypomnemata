from __future__ import annotations

import json
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from ..crud import load_tag_names, set_item_tags, to_out
from ..db import get_session
from ..models import Item
from ..ocr import is_ocr_candidate, ocr_item
from ..article import scrape_article
from ..thumbgen import generate_upload_thumbnail
from ..ytdlp import download_video
from ..schemas import ItemOut, validate_kind
from ..storage import AssetTooLargeError, save_upload

_THUMB_EXTS = {".pdf", ".mp4", ".webm", ".mkv", ".mov", ".m4v", ".avi"}

router = APIRouter(prefix="/captures", tags=["captures"])


@router.post("", status_code=status.HTTP_201_CREATED, response_model=ItemOut)
async def create_capture(
    background_tasks: BackgroundTasks,
    kind: Annotated[str, Form()],
    source_url: Annotated[str | None, Form()] = None,
    title: Annotated[str | None, Form()] = None,
    note: Annotated[str | None, Form()] = None,
    body_text: Annotated[str | None, Form()] = None,
    tags: Annotated[str | None, Form(description="comma-separated tags")] = None,
    meta_json: Annotated[str | None, Form()] = None,
    file: Annotated[UploadFile | None, File()] = None,
    db: AsyncSession = Depends(get_session),
) -> ItemOut:
    try:
        kind = validate_kind(kind)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e)) from e

    if meta_json is not None:
        try:
            json.loads(meta_json)
        except json.JSONDecodeError as e:
            raise HTTPException(status_code=422, detail=f"meta_json not valid JSON: {e}") from e

    item = Item(
        kind=kind,
        source_url=source_url,
        title=title,
        note=note,
        body_text=body_text,
        meta_json=meta_json,
    )
    db.add(item)
    await db.flush()  # populate item.id

    if file is not None and file.filename:
        try:
            rel = await save_upload(item.id, file.filename, file, file.content_type)
        except AssetTooLargeError as e:
            await db.rollback()
            raise HTTPException(status_code=413, detail=str(e)) from e
        item.asset_path = str(rel)

    if item.asset_path and is_ocr_candidate(item.asset_path):
        item.ocr_status = "pending"

    # Tweets/videos sem arquivo (URL colada no webapp) passam pelo yt-dlp;
    # Articles passam pelo scraper de artigos.
    # Tweets com screenshot da extensão já têm asset_path — não substituímos.
    needs_thumbgen = False
    if item.source_url and kind in ("video", "tweet") and not item.asset_path:
        item.download_status = "pending"
    elif item.source_url and kind == "article" and not item.asset_path:
        item.download_status = "pending"
    elif item.asset_path and not item.download_status:
        from pathlib import PurePosixPath
        ext = PurePosixPath(item.asset_path).suffix.lower()
        if ext in _THUMB_EXTS:
            item.download_status = "pending"
            needs_thumbgen = True

    tag_list = [t.strip() for t in (tags or "").split(",") if t.strip()]
    if tag_list:
        await set_item_tags(db, item, tag_list)

    await db.commit()

    if item.ocr_status == "pending":
        background_tasks.add_task(ocr_item, item.id)
    if item.download_status == "pending":
        if needs_thumbgen:
            background_tasks.add_task(generate_upload_thumbnail, item.id)
        elif kind == "article":
            background_tasks.add_task(scrape_article, item.id)
        else:
            background_tasks.add_task(download_video, item.id)

    tag_names = await load_tag_names(db, item.id)
    return to_out(item, tag_names=tag_names)
