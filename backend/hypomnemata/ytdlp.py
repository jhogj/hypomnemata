from __future__ import annotations

import asyncio
import json
import logging
import re
import shutil
import subprocess
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path

from sqlalchemy import create_engine, select, update
from sqlalchemy.orm import Session

from .config import settings
from .storage import resolve_asset

log = logging.getLogger("hypomnemata.ytdlp")

_VIDEO_EXTS = frozenset({".mp4", ".mkv", ".webm", ".mov", ".m4v", ".avi"})
_IMAGE_EXTS = frozenset({".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"})
_MEDIA_EXTS = _VIDEO_EXTS | _IMAGE_EXTS
_DESC_MAX = 5000
_UA = "Mozilla/5.0 (compatible; Hypomnemata/1.0)"
_THUMB_NAME = "thumb.jpg"


def _find_media_files(item_subdir: Path) -> list[Path]:
    if not item_subdir.is_dir():
        return []
    return sorted(
        f for f in item_subdir.iterdir()
        if f.is_file() and f.suffix.lower() in _MEDIA_EXTS
    )


def _generate_thumbnail(
    item_subdir: Path,
    video_file: Path | None,
    info: dict | None,
    assets_dir: Path,
) -> str | None:
    """Generate a thumbnail for a video item.

    Strategy:
      1. Download thumbnail URL from yt-dlp info (YouTube/Vimeo always have one).
      2. Fallback: extract a frame from the video file using ffmpeg.
    Returns the relative asset path of the thumbnail, or None on failure.
    """
    thumb_path = item_subdir / _THUMB_NAME

    # 1) Try yt-dlp thumbnail URL (YouTube, Vimeo, etc.)
    if info:
        thumb_url = info.get("thumbnail")
        # For playlists / multi-entry results, dig into entries
        if not thumb_url and info.get("_type") == "playlist" and info.get("entries"):
            entry = next((e for e in info["entries"] if e), None)
            if entry:
                thumb_url = entry.get("thumbnail")
        if thumb_url:
            try:
                req = urllib.request.Request(thumb_url, headers={"User-Agent": _UA})
                with urllib.request.urlopen(req, timeout=15) as r:
                    thumb_path.write_bytes(r.read())
                if thumb_path.stat().st_size > 0:
                    log.info("thumbnail downloaded from info.thumbnail → %s", thumb_path.name)
                    return str(thumb_path.relative_to(assets_dir))
            except Exception as e:
                log.debug("thumbnail download failed: %s", e)
                thumb_path.unlink(missing_ok=True)

    # 2) Fallback: extract a frame from the video file using ffmpeg
    if video_file and video_file.exists() and shutil.which("ffmpeg"):
        try:
            subprocess.run(
                [
                    "ffmpeg", "-y",
                    "-ss", "1",
                    "-i", str(video_file),
                    "-frames:v", "1",
                    "-q:v", "2",
                    str(thumb_path),
                ],
                capture_output=True,
                timeout=30,
            )
            if thumb_path.exists() and thumb_path.stat().st_size > 0:
                log.info("thumbnail extracted via ffmpeg → %s", thumb_path.name)
                return str(thumb_path.relative_to(assets_dir))
        except Exception as e:
            log.debug("ffmpeg thumbnail extraction failed: %s", e)
            thumb_path.unlink(missing_ok=True)

    return None


def _parse_oembed_text(html: str) -> str | None:
    """Extract plain tweet text from oEmbed embed HTML."""

    class _PTag(HTMLParser):
        def __init__(self) -> None:
            super().__init__()
            self._in = False
            self._parts: list[str] = []

        def handle_starttag(self, tag: str, attrs: list) -> None:
            if tag == "p":
                self._in = True

        def handle_endtag(self, tag: str) -> None:
            if tag == "p":
                self._in = False

        def handle_data(self, data: str) -> None:
            if self._in:
                self._parts.append(data)

    parser = _PTag()
    parser.feed(html)
    text = "".join(parser._parts).strip()
    # pic.twitter.com/xxx links are already represented by the downloaded image
    text = re.sub(r"\s*pic\.twitter\.com/\S+", "", text).strip()
    return text or None


def _fetch_oembed(tweet_url: str) -> dict:
    url = "https://publish.twitter.com/oembed?" + urllib.parse.urlencode(
        {"url": tweet_url, "omit_script": "true"}
    )
    req = urllib.request.Request(url, headers={"User-Agent": _UA})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())  # type: ignore[no-any-return]


def _download_tweet_images(
    tweet_url: str, item_subdir: Path, max_bytes: int
) -> tuple[list[Path], str | None]:
    """
    Download images from a tweet that has no video.
    Returns (media_files, body_text).

    Strategy:
      1. gallery-dl (pip install gallery-dl) — handles multi-image galleries.
      2. oEmbed thumbnail — always available, gives one image.
    Tweet text is extracted from oEmbed regardless of which download path succeeds.
    """
    body_text: str | None = None
    oembed_data: dict | None = None

    # Fetch oEmbed once: used for text AND as image fallback.
    try:
        oembed_data = _fetch_oembed(tweet_url)
        if raw_html := oembed_data.get("html", ""):
            body_text = _parse_oembed_text(raw_html)
    except Exception as e:
        log.debug("oEmbed fetch failed: %s", e)

    # ── gallery-dl (optional) ────────────────────────────────────────────────
    try:
        tmp = item_subdir / "_tmp"
        tmp.mkdir(exist_ok=True)
        try:
            subprocess.run(
                ["gallery-dl", f"--dest={tmp}", tweet_url],
                capture_output=True,
                timeout=120,
                check=True,
            )
            raw = sorted(
                f for f in tmp.rglob("*")
                if f.is_file() and f.suffix.lower() in _IMAGE_EXTS
            )
            if raw:
                renamed: list[Path] = []
                for i, src in enumerate(raw, 1):
                    dst = item_subdir / f"{i:03d}{src.suffix.lower()}"
                    shutil.move(str(src), str(dst))
                    renamed.append(dst)
                return renamed, body_text
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    except FileNotFoundError:
        log.debug("gallery-dl não instalado; usando fallback oEmbed")
    except subprocess.CalledProcessError as e:
        log.debug("gallery-dl falhou (%s); usando fallback oEmbed", e)
    except Exception as e:
        log.debug("gallery-dl erro inesperado (%s); usando fallback oEmbed", e)

    # ── oEmbed thumbnail fallback ────────────────────────────────────────────
    if oembed_data is None:
        return [], body_text

    thumbnail_url: str | None = oembed_data.get("thumbnail_url")
    if not thumbnail_url:
        log.warning("oEmbed: sem thumbnail_url para %s", tweet_url)
        return [], body_text

    img_url = re.sub(r"name=\w+", "name=orig", thumbnail_url)
    low = thumbnail_url.lower()
    ext = ".png" if "format=png" in low else ".webp" if "format=webp" in low else ".jpg"

    out_path = item_subdir / f"001{ext}"
    written = 0
    try:
        req = urllib.request.Request(img_url, headers={"User-Agent": _UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            with out_path.open("wb") as f:
                while chunk := r.read(1024 * 1024):
                    written += len(chunk)
                    if written > max_bytes:
                        out_path.unlink(missing_ok=True)
                        log.warning("oEmbed: imagem acima do limite para %s", tweet_url)
                        return [], body_text
                    f.write(chunk)
        log.info("oEmbed: baixou %s → %s (%.1fKB)", tweet_url, out_path.name, written / 1024)
        return [out_path], body_text
    except Exception as e:
        log.warning("oEmbed download falhou para %s: %s", tweet_url, e)
        return [], body_text


def _run_ytdlp_sync(item_id: str) -> None:
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

            now = datetime.now(timezone.utc)
            output_dir = settings.assets_dir / f"{now:%Y}" / f"{now:%m}"
            item_subdir = output_dir / item_id
            item_subdir.mkdir(parents=True, exist_ok=True)
            outtmpl = str(item_subdir / "%(autonumber)03d.%(ext)s")
            max_bytes = settings.max_asset_mb * 1024 * 1024

            try:
                import yt_dlp

                if item.kind == "tweet":
                    ydl_opts: dict = {
                        "format": "best",
                        "outtmpl": outtmpl,
                        "quiet": True,
                        "no_warnings": True,
                        "noplaylist": False,
                        "max_filesize": max_bytes,
                    }
                else:
                    ydl_opts = {
                        "format": "best[ext=mp4]/bestvideo[ext=mp4]+bestaudio[ext=m4a]/best",
                        "merge_output_format": "mp4",
                        "outtmpl": outtmpl,
                        "quiet": True,
                        "no_warnings": True,
                        "noplaylist": True,
                        "max_filesize": max_bytes,
                    }

                info: dict | None = None
                media_files: list[Path] = []
                tweet_body: str | None = None

                try:
                    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                        info = ydl.extract_info(item.source_url, download=True)
                    media_files = _find_media_files(item_subdir)
                except yt_dlp.utils.DownloadError as dl_err:
                    if item.kind != "tweet":
                        raise
                    log.info(
                        "yt-dlp: tweet sem vídeo (%s), tentando download de imagem item=%s",
                        dl_err,
                        item_id,
                    )

                # Image-only tweet: yt-dlp found nothing → use image fallback.
                if not media_files and item.kind == "tweet":
                    media_files, tweet_body = _download_tweet_images(
                        item.source_url, item_subdir, max_bytes
                    )
                    info = None

                if not media_files:
                    raise RuntimeError("nenhum arquivo de mídia encontrado após download")

                # Prefer video over images as the primary asset (video tweet case).
                video_files = [f for f in media_files if f.suffix.lower() in _VIDEO_EXTS]
                primary = video_files[0] if video_files else media_files[0]

                if primary.stat().st_size > max_bytes:
                    for f in media_files:
                        f.unlink(missing_ok=True)
                    try:
                        item_subdir.rmdir()
                    except OSError:
                        pass
                    db.execute(
                        update(Item)
                        .where(Item.id == item_id)
                        .values(download_status="error:too_large")
                    )
                    db.commit()
                    return

                # Remove screenshot captured by the extension (if it exists and differs).
                if item.asset_path:
                    try:
                        old = resolve_asset(item.asset_path)
                        if old.exists() and old.resolve() != primary.resolve():
                            old.unlink(missing_ok=True)
                    except Exception:
                        pass

                rel_primary = str(primary.relative_to(settings.assets_dir))
                vals: dict = {"asset_path": rel_primary, "download_status": "done"}

                # Build meta dict from existing meta_json.
                existing_meta: dict = {}
                if item.meta_json:
                    try:
                        existing_meta = json.loads(item.meta_json)
                    except Exception:
                        pass

                # Multiple images → persist all paths so the UI shows a grid.
                if len(media_files) > 1:
                    existing_meta["media_paths"] = [
                        str(f.relative_to(settings.assets_dir)) for f in media_files
                    ]

                # Generate thumbnail for video items (and tweets with video).
                video_primary = primary if primary.suffix.lower() in _VIDEO_EXTS else None
                thumb_rel = _generate_thumbnail(
                    item_subdir, video_primary, info, settings.assets_dir
                )
                if thumb_rel:
                    existing_meta["thumbnail_path"] = thumb_rel

                if existing_meta:
                    vals["meta_json"] = json.dumps(existing_meta)

                # Metadata: prefer yt-dlp info (video tweets); fall back to oEmbed text.
                if info:
                    actual = info
                    if info.get("_type") == "playlist" and info.get("entries"):
                        actual = next((e for e in info["entries"] if e), info)
                    if not item.title and actual.get("title"):
                        vals["title"] = actual["title"]
                    desc = actual.get("description") or ""
                    if desc:
                        vals["body_text"] = desc[:_DESC_MAX]
                elif tweet_body:
                    vals["body_text"] = tweet_body[:_DESC_MAX]

                db.execute(update(Item).where(Item.id == item_id).values(**vals))
                db.commit()
                log.info(
                    "download done item=%s files=%d primary_size=%.1fMB",
                    item_id,
                    len(media_files),
                    primary.stat().st_size / 1_048_576,
                )

            except ImportError:
                log.warning("yt-dlp não instalado, skipping item=%s", item_id)
                db.execute(
                    update(Item)
                    .where(Item.id == item_id)
                    .values(download_status="error:missing_dep")
                )
                db.commit()
            except Exception as exc:
                log.exception("download falhou item=%s: %s", item_id, exc)
                db.execute(
                    update(Item)
                    .where(Item.id == item_id)
                    .values(download_status=f"error:{type(exc).__name__}: {exc}"[:120])
                )
                db.commit()
    finally:
        engine.dispose()


async def download_video(item_id: str) -> None:
    await asyncio.to_thread(_run_ytdlp_sync, item_id)
