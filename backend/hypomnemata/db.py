from __future__ import annotations

from collections.abc import AsyncIterator

from sqlalchemy import event, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from .config import settings

engine = create_async_engine(settings.db_url, future=True, echo=False)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


# Register on sync_engine so dbapi_conn here is the raw sqlite3.Connection —
# calling .cursor() on it doesn't need greenlet context. Listening on the
# abstract Engine class with aiosqlite gives us the async-adapter connection
# instead and would require greenlet_spawn for every PRAGMA.
@event.listens_for(engine.sync_engine, "connect")
def _sqlite_pragma(dbapi_conn, _):
    cur = dbapi_conn.cursor()
    cur.execute("PRAGMA foreign_keys=ON")
    cur.execute("PRAGMA journal_mode=WAL")
    cur.execute("PRAGMA synchronous=NORMAL")
    cur.close()


FTS_DDL = [
    """
    CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
        title, note, body_text,
        content='items', content_rowid='rowid',
        tokenize = 'unicode61 remove_diacritics 2'
    )
    """,
    """
    CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
        INSERT INTO items_fts(rowid, title, note, body_text)
        VALUES (new.rowid, coalesce(new.title,''), coalesce(new.note,''), coalesce(new.body_text,''));
    END
    """,
    """
    CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
        INSERT INTO items_fts(items_fts, rowid, title, note, body_text)
        VALUES ('delete', old.rowid, coalesce(old.title,''), coalesce(old.note,''), coalesce(old.body_text,''));
    END
    """,
    """
    CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
        INSERT INTO items_fts(items_fts, rowid, title, note, body_text)
        VALUES ('delete', old.rowid, coalesce(old.title,''), coalesce(old.note,''), coalesce(old.body_text,''));
        INSERT INTO items_fts(rowid, title, note, body_text)
        VALUES (new.rowid, coalesce(new.title,''), coalesce(new.note,''), coalesce(new.body_text,''));
    END
    """,
]


async def init_db() -> None:
    from . import models  # noqa: F401  (register mappers)

    settings.ensure_dirs()
    async with engine.begin() as conn:
        await conn.run_sync(models.Base.metadata.create_all)
        for ddl in FTS_DDL:
            await conn.execute(text(ddl))
        # Migrate existing DBs that predate the ocr_status column.
        # SQLite has no ALTER TABLE ... ADD COLUMN IF NOT EXISTS, so we catch the error.
        try:
            await conn.execute(text("ALTER TABLE items ADD COLUMN ocr_status TEXT"))
        except Exception:
            pass
        try:
            await conn.execute(text("ALTER TABLE items ADD COLUMN download_status TEXT"))
        except Exception:
            pass


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
