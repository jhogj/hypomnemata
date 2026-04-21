from __future__ import annotations

from fastapi import APIRouter

from ..config import settings

router = APIRouter(tags=["storage"])


def _dir_size(path) -> int:
    """Walk a directory tree and return total bytes."""
    total = 0
    if not path.is_dir():
        return 0
    for f in path.rglob("*"):
        if f.is_file():
            try:
                total += f.stat().st_size
            except OSError:
                pass
    return total


@router.get("/storage")
async def storage_info():
    total_bytes = _dir_size(settings.assets_dir)
    return {"total_bytes": total_bytes}
