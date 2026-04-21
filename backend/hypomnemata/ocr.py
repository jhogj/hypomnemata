from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from sqlalchemy import create_engine, select, update
from sqlalchemy.orm import Session

from .config import settings
from .storage import resolve_asset

log = logging.getLogger("hypomnemata.ocr")

_IMAGE_EXTS = frozenset({".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tiff", ".tif"})
_PDF_EXT = ".pdf"


def is_ocr_candidate(asset_path: str) -> bool:
    return Path(asset_path).suffix.lower() in _IMAGE_EXTS | {_PDF_EXT}


def _ocr_image(abs_path: Path) -> str:
    import pytesseract
    from PIL import Image

    img = Image.open(abs_path)
    try:
        return pytesseract.image_to_string(img, lang="por+eng").strip()
    except pytesseract.pytesseract.TesseractError:
        return pytesseract.image_to_string(img, lang="eng").strip()


def _ocr_pdf(abs_path: Path) -> str:
    from pypdf import PdfReader

    reader = PdfReader(str(abs_path))
    parts = [page.extract_text() or "" for page in reader.pages]
    return "\n\n".join(p.strip() for p in parts if p.strip())


def _run_ocr_sync(item_id: str) -> None:
    from .models import Item

    engine = create_engine(
        settings.sync_db_url,
        connect_args={"check_same_thread": False},
    )
    try:
        with Session(engine) as db:
            item = db.execute(select(Item).where(Item.id == item_id)).scalar_one_or_none()
            if item is None or not item.asset_path:
                return

            abs_path = resolve_asset(item.asset_path)
            if not abs_path.exists():
                db.execute(
                    update(Item).where(Item.id == item_id).values(ocr_status="error:file_missing")
                )
                db.commit()
                return

            ext = abs_path.suffix.lower()
            try:
                text = _ocr_pdf(abs_path) if ext == _PDF_EXT else _ocr_image(abs_path)

                vals: dict = {"ocr_status": "done"}
                if text and not item.body_text:
                    vals["body_text"] = text

                db.execute(update(Item).where(Item.id == item_id).values(**vals))
                db.commit()
                log.info("ocr done item=%s chars=%d", item_id, len(text))
            except ImportError as exc:
                log.warning("ocr skipped item=%s: missing dep — %s", item_id, exc)
                db.execute(
                    update(Item).where(Item.id == item_id).values(ocr_status="error:missing_dep")
                )
                db.commit()
            except Exception as exc:
                log.exception("ocr failed item=%s", item_id)
                db.execute(
                    update(Item)
                    .where(Item.id == item_id)
                    .values(ocr_status=f"error:{type(exc).__name__}")
                )
                db.commit()
    finally:
        engine.dispose()


async def ocr_item(item_id: str) -> None:
    await asyncio.to_thread(_run_ocr_sync, item_id)
