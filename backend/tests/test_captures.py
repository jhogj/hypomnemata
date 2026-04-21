from __future__ import annotations

from pathlib import Path

import pytest


@pytest.mark.asyncio
async def test_create_note_no_file(client):
    r = await client.post(
        "/captures",
        data={
            "kind": "note",
            "title": "Primeira nota",
            "body_text": "texto do corpo",
            "tags": "filosofia, grego",
        },
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["kind"] == "note"
    assert body["title"] == "Primeira nota"
    assert set(body["tags"]) == {"filosofia", "grego"}
    assert body["asset_path"] is None


@pytest.mark.asyncio
async def test_create_with_file_saves_asset(client):
    from hypomnemata.config import settings

    files = {"file": ("foto.png", b"\x89PNG\r\n\x1a\nfake", "image/png")}
    r = await client.post(
        "/captures",
        data={"kind": "image", "title": "shot"},
        files=files,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["asset_path"] is not None
    disk = settings.assets_dir / body["asset_path"]
    assert disk.is_file()
    assert disk.read_bytes().startswith(b"\x89PNG")


@pytest.mark.asyncio
async def test_invalid_kind_rejected(client):
    r = await client.post("/captures", data={"kind": "invalid"})
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_asset_too_large(client):
    big = b"x" * (11 * 1024 * 1024)  # 11MB > 10MB test limit
    r = await client.post(
        "/captures",
        data={"kind": "image"},
        files={"file": ("big.bin", big, "application/octet-stream")},
    )
    assert r.status_code == 413
