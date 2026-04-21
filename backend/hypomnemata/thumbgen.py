from __future__ import annotations

import asyncio
import json
import logging
import subprocess
from pathlib import Path

from sqlalchemy import create_engine, select, update
from sqlalchemy.orm import Session

from .config import settings

log = logging.getLogger("hypomnemata.thumbgen")


def _pdf_thumbnail(pdf_path: Path, dest: Path) -> bool:
    """Render the first page of a PDF as a JPEG thumbnail."""
    try:
        import fitz  # PyMuPDF

        doc = fitz.open(str(pdf_path))
        if doc.page_count == 0:
            doc.close()
            return False
        page = doc[0]
        # Render at 2x default resolution for crisp thumbnails
        mat = fitz.Matrix(2.0, 2.0)
        pix = page.get_pixmap(matrix=mat)
        pix.save(str(dest))
        doc.close()
        return dest.exists() and dest.stat().st_size > 0
    except Exception as e:
        log.debug("PDF thumbnail failed: %s — %s", pdf_path, e)
        return False


def _video_thumbnail(video_path: Path, dest: Path) -> bool:
    """Extract a frame from a video file at t=1s using ffmpeg."""
    try:
        subprocess.run(
            [
                "ffmpeg", "-y",
                "-ss", "1",
                "-i", str(video_path),
                "-frames:v", "1",
                "-q:v", "2",
                str(dest),
            ],
            capture_output=True,
            timeout=30,
        )
        return dest.exists() and dest.stat().st_size > 0
    except Exception as e:
        log.debug("video thumbnail failed: %s — %s", video_path, e)
        return False


def _run_thumbgen_sync(item_id: str) -> None:
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

            asset = settings.assets_dir / item.asset_path
            if not asset.exists():
                return

            # Determine output path — thumb.jpg next to the asset
            thumb_path = asset.parent / "thumb.jpg"

            ext = asset.suffix.lower()
            ok = False
            if ext == ".pdf":
                ok = _pdf_thumbnail(asset, thumb_path)
            elif ext in (".mp4", ".webm", ".mkv", ".mov", ".m4v", ".avi"):
                ok = _video_thumbnail(asset, thumb_path)

            if not ok:
                # Still mark as done so polling stops.
                db.execute(
                    update(Item).where(Item.id == item_id).values(download_status="done")
                )
                db.commit()
                return

            rel = str(thumb_path.relative_to(settings.assets_dir))

            # Update meta_json with thumbnail_path
            existing_meta: dict = {}
            if item.meta_json:
                try:
                    existing_meta = json.loads(item.meta_json)
                except Exception:
                    pass

            existing_meta["thumbnail_path"] = rel

            db.execute(
                update(Item)
                .where(Item.id == item_id)
                .values(
                    meta_json=json.dumps(existing_meta),
                    download_status="done",
                )
            )
            db.commit()
            log.info("thumbnail generated for item=%s → %s", item_id, rel)
    finally:
        engine.dispose()


async def generate_upload_thumbnail(item_id: str) -> None:
    """Generate a thumbnail for an uploaded file (PDF or video)."""
    await asyncio.to_thread(_run_thumbgen_sync, item_id)
