from __future__ import annotations

import mimetypes
import shutil
from datetime import datetime, timezone
from pathlib import Path

from .config import settings


class AssetTooLargeError(Exception):
    pass


class UnsafePathError(Exception):
    pass


def asset_subpath(item_id: str, filename: str, when: datetime | None = None) -> Path:
    when = when or datetime.now(timezone.utc)
    suffix = Path(filename).suffix.lower() or guess_suffix(filename)
    return Path(f"{when:%Y}") / f"{when:%m}" / f"{item_id}{suffix}"


def guess_suffix(content_type_or_name: str) -> str:
    ext = mimetypes.guess_extension(content_type_or_name) or ""
    return ext


def resolve_asset(rel: str | Path) -> Path:
    """Resolve a relative asset path into an absolute one, guarding against traversal."""
    assets_root = settings.assets_dir.resolve()
    candidate = (assets_root / rel).resolve()
    try:
        candidate.relative_to(assets_root)
    except ValueError as e:
        raise UnsafePathError(f"Path escapes assets_dir: {rel}") from e
    return candidate


async def save_upload(item_id: str, filename: str, stream, content_type: str | None = None) -> Path:
    """Persist an upload to assets/. Returns the relative path stored in the DB."""
    rel = asset_subpath(item_id, filename or (content_type or "bin"))
    abs_path = settings.assets_dir / rel
    abs_path.parent.mkdir(parents=True, exist_ok=True)

    max_bytes = settings.max_asset_mb * 1024 * 1024
    written = 0
    with abs_path.open("wb") as out:
        while chunk := await stream.read(1024 * 1024):
            written += len(chunk)
            if written > max_bytes:
                out.close()
                abs_path.unlink(missing_ok=True)
                raise AssetTooLargeError(
                    f"Asset exceeds {settings.max_asset_mb}MB limit ({written} bytes)"
                )
            out.write(chunk)
    return rel


def save_bytes(item_id: str, filename: str, data: bytes) -> Path:
    rel = asset_subpath(item_id, filename)
    abs_path = settings.assets_dir / rel
    abs_path.parent.mkdir(parents=True, exist_ok=True)
    max_bytes = settings.max_asset_mb * 1024 * 1024
    if len(data) > max_bytes:
        raise AssetTooLargeError(f"Asset exceeds {settings.max_asset_mb}MB limit")
    abs_path.write_bytes(data)
    return rel


def delete_asset(rel: str | Path | None) -> None:
    if not rel:
        return
    try:
        abs_path = resolve_asset(rel)
    except UnsafePathError:
        return
    if abs_path.is_file():
        abs_path.unlink()
        _prune_empty_parents(abs_path.parent)


def _prune_empty_parents(path: Path) -> None:
    root = settings.assets_dir.resolve()
    cur = path.resolve()
    while cur != root and cur.is_dir() and not any(cur.iterdir()):
        parent = cur.parent
        cur.rmdir()
        cur = parent


def nuke_assets() -> None:
    """Only for tests."""
    if settings.assets_dir.exists():
        shutil.rmtree(settings.assets_dir)
    settings.assets_dir.mkdir(parents=True, exist_ok=True)
