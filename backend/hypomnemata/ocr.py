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
    import logging

    log = logging.getLogger("hypomnemata.ocr")

    reader = PdfReader(str(abs_path))
    parts = [page.extract_text() or "" for page in reader.pages]
    text = "\n\n".join(p.strip() for p in parts if p.strip())

    # Se extraiu uma quantidade razoável de texto, é um PDF nativo
    if len(text) > 150:
        return text

    # Se não, pode ser um PDF escaneado (imagens). Vamos usar OCR.
    log.info("Pouco texto nativo encontrado em %s (%d chars). Tentando OCR via Tesseract...", abs_path, len(text))
    try:
        import fitz  # PyMuPDF
        import pytesseract
        from PIL import Image
        import tempfile
        import os

        doc = fitz.open(str(abs_path))
        ocr_parts = []
        
        with tempfile.TemporaryDirectory() as temp_dir:
            for i in range(doc.page_count):
                page = doc[i]
                # Renderiza em 2x para ter qualidade suficiente para o OCR
                mat = fitz.Matrix(2.0, 2.0)
                pix = page.get_pixmap(matrix=mat)
                
                temp_path = Path(temp_dir) / f"page_{i}.png"
                pix.save(str(temp_path))
                
                img = Image.open(temp_path)
                try:
                    page_text = pytesseract.image_to_string(img, lang="por+eng").strip()
                except pytesseract.pytesseract.TesseractError:
                    page_text = pytesseract.image_to_string(img, lang="eng").strip()
                
                if page_text:
                    ocr_parts.append(page_text)
                    
        doc.close()
        
        if ocr_parts:
            ocr_text = "\n\n".join(ocr_parts)
            return ocr_text

    except Exception as e:
        log.warning("Falha no OCR de fallback para PDF %s: %s", abs_path, e)

    return text


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
