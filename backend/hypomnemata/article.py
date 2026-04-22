from __future__ import annotations

import asyncio
import json
import logging
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import create_engine, select, update
from sqlalchemy.orm import Session

from .config import settings

log = logging.getLogger("hypomnemata.article")

_UA = "Mozilla/5.0 (compatible; Hypomnemata/1.0)"
_IMAGE_EXTS = frozenset({".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"})
_MIN_TEXT_LEN = 200  # minimum chars to consider the scrape successful


def _download_image(url: str, dest: Path, max_bytes: int) -> bool:
    """Download an image URL to dest. Returns True on success."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": _UA})
        with urllib.request.urlopen(req, timeout=20) as r:
            data = r.read(max_bytes + 1)
            if len(data) > max_bytes:
                log.debug("image too large: %s (%d bytes)", url, len(data))
                return False
            dest.write_bytes(data)
            return dest.stat().st_size > 0
    except Exception as e:
        log.debug("image download failed: %s — %s", url, e)
        return False


def _guess_ext_from_url(url: str) -> str:
    """Guess image extension from URL path."""
    path = urllib.parse.urlparse(url).path.lower()
    for ext in _IMAGE_EXTS:
        if path.endswith(ext):
            return ext
    return ".jpg"


def _run_scrape_sync(item_id: str) -> None:
    from .models import Item

    engine = create_engine(
        settings.sync_db_url,
        connect_args={"check_same_thread": False},
    )
    try:
        with Session(engine) as db:
            item = db.execute(select(Item).where(Item.id == item_id)).scalar_one_or_none()
            if item is None or not item.source_url:
                return

            try:
                import trafilatura
            except ImportError:
                log.warning("trafilatura not installed, skipping item=%s", item_id)
                db.execute(
                    update(Item)
                    .where(Item.id == item_id)
                    .values(download_status="error:missing_dep")
                )
                db.commit()
                return

            try:
                # Fetch page
                downloaded = trafilatura.fetch_url(item.source_url)
                if not downloaded:
                    log.info("trafilatura fetch returned None for %s, trying playwright", item.source_url)
                    from .playwright_scraper import fetch_with_playwright
                    downloaded = fetch_with_playwright(item.source_url)
                    if not downloaded:
                        raise RuntimeError("trafilatura.fetch_url returned None")

                # Extract text + metadata
                text = trafilatura.extract(
                    downloaded,
                    include_comments=False,
                    include_tables=True,
                    favor_precision=False,
                    favor_recall=True,
                )
                metadata = trafilatura.extract_metadata(downloaded)

                # Playwright fallback when static fetch gives insufficient text (SPA)
                if not text or len(text) < _MIN_TEXT_LEN:
                    from .playwright_scraper import fetch_with_playwright
                    pw_html = fetch_with_playwright(item.source_url)
                    if pw_html:
                        pw_text = trafilatura.extract(
                            pw_html,
                            include_comments=False,
                            include_tables=True,
                            favor_precision=False,
                            favor_recall=True,
                        )
                        if pw_text and (not text or len(pw_text) > len(text)):
                            pw_meta = trafilatura.extract_metadata(pw_html)
                            text = pw_text
                            if pw_meta:
                                metadata = pw_meta
                            log.info(
                                "playwright fallback extracted %d chars for item=%s",
                                len(text),
                                item_id,
                            )

                if not text or len(text) < _MIN_TEXT_LEN:
                    # Not enough content — mark as done but don't promote.
                    # Keep what we got, if anything.
                    vals: dict = {"download_status": "done"}
                    if text:
                        vals["body_text"] = text
                    if metadata and metadata.title and not item.title:
                        vals["title"] = metadata.title
                    db.execute(update(Item).where(Item.id == item_id).values(**vals))
                    db.commit()
                    log.info("article scrape: insufficient text item=%s (%d chars)", item_id, len(text or ""))
                    return

                # Prepare output directory
                now = datetime.now(timezone.utc)
                output_dir = settings.assets_dir / f"{now:%Y}" / f"{now:%m}"
                item_subdir = output_dir / item_id
                item_subdir.mkdir(parents=True, exist_ok=True)
                max_bytes = settings.max_asset_mb * 1024 * 1024

                vals = {
                    "body_text": text,
                    "download_status": "done",
                }

                if metadata:
                    if metadata.title and not item.title:
                        vals["title"] = metadata.title

                # Build meta_json
                existing_meta: dict = {}
                if item.meta_json:
                    try:
                        existing_meta = json.loads(item.meta_json)
                    except Exception:
                        pass

                if metadata:
                    if metadata.author:
                        existing_meta["author"] = metadata.author
                    if metadata.date:
                        existing_meta["pub_date"] = str(metadata.date)
                    if metadata.sitename:
                        existing_meta["sitename"] = metadata.sitename
                    if metadata.description:
                        existing_meta["description"] = metadata.description

                # Download hero image (og:image or first image)
                hero_url: str | None = None
                if metadata and metadata.image:
                    hero_url = metadata.image

                if hero_url:
                    ext = _guess_ext_from_url(hero_url)
                    hero_path = item_subdir / f"hero{ext}"
                    if _download_image(hero_url, hero_path, max_bytes):
                        rel = str(hero_path.relative_to(settings.assets_dir))
                        vals["asset_path"] = rel
                        existing_meta["thumbnail_path"] = rel
                        log.info("article hero image saved: %s", rel)

                if existing_meta:
                    vals["meta_json"] = json.dumps(existing_meta)

                # Remove old screenshot if extension captured one
                if item.asset_path and "asset_path" in vals:
                    from .storage import resolve_asset
                    try:
                        old = resolve_asset(item.asset_path)
                        new = resolve_asset(vals["asset_path"])
                        if old.exists() and old.resolve() != new.resolve():
                            old.unlink(missing_ok=True)
                    except Exception:
                        pass

                db.execute(update(Item).where(Item.id == item_id).values(**vals))
                db.commit()
                log.info(
                    "article scrape done item=%s title=%r text_len=%d has_hero=%s",
                    item_id,
                    vals.get("title", item.title),
                    len(text),
                    "asset_path" in vals,
                )

                # Auto-resumo
                from .llm import summarize_sync, get_autotags_sync
                existing_meta["ai_status"] = "pending"
                db.execute(
                    update(Item)
                    .where(Item.id == item_id)
                    .values(meta_json=json.dumps(existing_meta, ensure_ascii=False))
                )
                db.commit()
                summary: str | None = None
                try:
                    summary = summarize_sync(vals.get("title", item.title), text)
                finally:
                    existing_meta.pop("ai_status", None)
                    if summary:
                        existing_meta["summary"] = summary
                    db.execute(
                        update(Item)
                        .where(Item.id == item_id)
                        .values(meta_json=json.dumps(existing_meta, ensure_ascii=False))
                    )
                    db.commit()
                    if summary:
                        log.info("auto-resumo salvo item=%s (%d chars)", item_id, len(summary))

                # Auto-tags (silencioso se LLM indisponível)
                auto_tags = get_autotags_sync(vals.get("title", item.title), text)
                if auto_tags:
                    from .crud import set_item_tags_sync
                    set_item_tags_sync(db, item_id, auto_tags)
                    db.commit()
                    log.info("auto-tags salvas item=%s: %s", item_id, auto_tags)

            except Exception as exc:
                log.exception("article scrape failed item=%s: %s", item_id, exc)
                db.execute(
                    update(Item)
                    .where(Item.id == item_id)
                    .values(download_status=f"error:{type(exc).__name__}: {exc}"[:120])
                )
                db.commit()
    finally:
        engine.dispose()


async def scrape_article(item_id: str) -> None:
    await asyncio.to_thread(_run_scrape_sync, item_id)
