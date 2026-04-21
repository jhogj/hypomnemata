from __future__ import annotations

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from ..storage import UnsafePathError, resolve_asset

router = APIRouter(prefix="/assets", tags=["assets"])


@router.get("/{path:path}")
async def get_asset(path: str) -> FileResponse:
    try:
        abs_path = resolve_asset(path)
    except UnsafePathError as e:
        raise HTTPException(status_code=400, detail="invalid path") from e
    if not abs_path.is_file():
        raise HTTPException(status_code=404, detail="asset not found")
    return FileResponse(abs_path)
