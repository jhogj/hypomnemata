"""Backup incremental via rsync para pasta configurada (ex: iCloud Drive).

Fluxo:
  1. Verifica sentinel file (.hypomnemata-backup) no destino
  2. Checkpoint WAL do SQLite
  3. rsync -a --delete <data_dir>/ <backup_dir>/

Só roda se HYPO_BACKUP_DIR estiver configurado.
"""
from __future__ import annotations

import logging
import shutil
import subprocess
import threading
from pathlib import Path

from .config import settings

log = logging.getLogger("hypomnemata.backup")

_SENTINEL = ".hypomnemata-backup"
_backup_lock = threading.Lock()


def _wal_checkpoint() -> None:
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

    if not _backup_lock.acquire(blocking=False):
        raise RuntimeError("backup já em andamento")

    try:
        # Sentinel check: recusa rodar --delete em diretório não vazio que
        # não seja um backup Hypomnemata conhecido.
        sentinel = backup_dir / _SENTINEL
        if backup_dir.exists() and any(backup_dir.iterdir()) and not sentinel.exists():
            raise RuntimeError(
                f"Recusando backup: '{backup_dir}' não está vazio e não contém "
                f"'{_SENTINEL}'. Crie o arquivo manualmente para confirmar que "
                "este diretório é um backup do Hypomnemata."
            )

        try:
            backup_dir.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise RuntimeError(f"Não foi possível criar o diretório de backup: {exc}") from None

        sentinel.touch(exist_ok=True)
        _wal_checkpoint()

        src = str(settings.data_dir).rstrip("/") + "/"
        dst = str(backup_dir).rstrip("/") + "/"

        try:
            result = subprocess.run(
                ["rsync", "-a", "--delete", src, dst],
                capture_output=True,
                text=True,
                timeout=300,
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError("rsync excedeu o tempo limite de 300s (caminho inacessível?)") from None
        except OSError as exc:
            raise RuntimeError(f"Falha ao executar rsync: {exc}") from None

        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or f"rsync saiu com código {result.returncode}")

        log.info("backup incremental concluído: %s → %s", src, dst)
        return f"Sincronizado com {dst}"

    finally:
        _backup_lock.release()
