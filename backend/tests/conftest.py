from __future__ import annotations

import os
import tempfile
from collections.abc import AsyncIterator
from pathlib import Path

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient


@pytest.fixture(scope="session", autouse=True)
def _isolated_data_dir():
    tmp = Path(tempfile.mkdtemp(prefix="hypo-test-"))
    os.environ["HYPO_DATA_DIR"] = str(tmp)
    os.environ["HYPO_MAX_ASSET_MB"] = "10"
    yield tmp


@pytest_asyncio.fixture
async def app():
    # Import after env vars are set so settings picks them up.
    from hypomnemata.config import settings
    from hypomnemata.db import engine, init_db
    from hypomnemata.main import create_app
    from hypomnemata.models import Base
    from hypomnemata.storage import nuke_assets

    # Clean slate per test: drop + recreate everything.
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        from sqlalchemy import text
        for name in ("items_fts", "items_fts_data", "items_fts_idx",
                     "items_fts_content", "items_fts_docsize", "items_fts_config"):
            await conn.execute(text(f"DROP TABLE IF EXISTS {name}"))
    await init_db()
    nuke_assets()

    # Exercise lifespan (ensure_dirs etc).
    _ = settings  # silence linter
    app = create_app()
    return app


@pytest_asyncio.fixture
async def client(app) -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
