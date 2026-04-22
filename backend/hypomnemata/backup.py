"""Backup incremental via rsync para pasta configurada (ex: iCloud Drive).

Fluxo:
  1. Checkpoint WAL do SQLite para garantir consistência do .db
  2. rsync -a --delete <data_dir>/ <backup_dir>/

Só roda se HYPO_BACKUP_DIR estiver configurado.
"""
from __future__ import annotations

import logging
import shutil
import subprocess
from pathlib import Path

from .config import settings

log = logging.getLogger("hypomnemata.backup")


def _wal_checkpoint() -> None:
    """Força o SQLite a mergear o WAL no arquivo principal antes do rsync."""
    try:
        import sqlite3
        with sqlite3.connect(str(settings.db_path)) as conn:
            conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    except Exception as exc:
        log.warning("wal_checkpoint falhou (ignorado): %s", exc)


def run_backup() -> str:
    """Executa o backup incremental. Retorna mensagem de sucesso.

    Levanta RuntimeError com mensagem legível em caso de falha.
    """
    backup_dir = settings.backup_dir
    if not backup_dir:
        raise RuntimeError("HYPO_BACKUP_DIR não configurado")

    if not shutil.which("rsync"):
        raise RuntimeError("rsync não encontrado no PATH")

    backup_dir.mkdir(parents=True, exist_ok=True)

    _wal_checkpoint()

    src = str(settings.data_dir).rstrip("/") + "/"
    dst = str(backup_dir).rstrip("/") + "/"

    result = subprocess.run(
        ["rsync", "-a", "--delete", src, dst],
        capture_output=True,
        text=True,
        timeout=300,
    )

    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"rsync saiu com código {result.returncode}")

    log.info("backup incremental concluído: %s → %s", src, dst)
    return f"Sincronizado com {dst}"
