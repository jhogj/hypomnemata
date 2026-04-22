import asyncio
import os
import shutil
import tempfile
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from ..config import settings

router = APIRouter(prefix="/system", tags=["System"])

def _create_backup_zip(data_dir: Path) -> Path:
    temp_dir = Path(tempfile.mkdtemp())
    zip_filename = f"hypomnemata_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    zip_path = temp_dir / f"{zip_filename}.zip"
    
    # shutil.make_archive automatically appends .zip to the base_name
    base_name = str(temp_dir / zip_filename)
    shutil.make_archive(base_name, 'zip', root_dir=data_dir)
    
    return zip_path

def _cleanup_backup(zip_path: Path):
    if zip_path.exists():
        try:
            os.remove(zip_path)
        except Exception:
            pass
    temp_dir = zip_path.parent
    if temp_dir.exists():
        shutil.rmtree(temp_dir, ignore_errors=True)

@router.post("/backup")
async def trigger_backup():
    """Executa backup incremental via rsync para HYPO_BACKUP_DIR."""
    from ..backup import run_backup
    try:
        msg = await asyncio.to_thread(run_backup)
        return {"ok": True, "message": msg}
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))


@router.get("/backup/status")
async def backup_status():
    """Retorna se o backup está configurado."""
    configured = settings.backup_dir is not None
    return {"configured": configured, "backup_dir": str(settings.backup_dir) if configured else None}


@router.get("/export")
async def export_backup():
    """Gera um arquivo ZIP com o banco de dados e a pasta de assets."""
    zip_path = await asyncio.to_thread(_create_backup_zip, settings.data_dir)
    
    return FileResponse(
        path=zip_path,
        filename=zip_path.name,
        media_type="application/zip",
        background=BackgroundTask(_cleanup_backup, zip_path)
    )
