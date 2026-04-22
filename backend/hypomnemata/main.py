from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .db import init_db
from .routes import assets, captures, folders, items, search, storage_info, tags, system

log = logging.getLogger("hypomnemata")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings.ensure_dirs()
    await init_db()
    log.info("hypomnemata ready at %s:%s (data=%s)", settings.host, settings.port, settings.data_dir)
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Hypomnemata", version="0.1.0", lifespan=lifespan)

    origins = list(settings.cors_origins)
    origin_regex = r"chrome-extension://.*" if settings.allow_chrome_extension else None

    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_origin_regex=origin_regex,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(captures.router)
    app.include_router(folders.router)
    app.include_router(items.router)
    app.include_router(search.router)
    app.include_router(tags.router)
    app.include_router(assets.router)
    app.include_router(storage_info.router)
    app.include_router(system.router)

    @app.get("/health")
    async def health():
        return {"ok": True, "version": "0.1.0"}

    return app


app = create_app()
