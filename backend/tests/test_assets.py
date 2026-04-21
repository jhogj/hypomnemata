from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_asset_download(client):
    r = await client.post(
        "/captures",
        data={"kind": "image"},
        files={"file": ("x.png", b"\x89PNGdata", "image/png")},
    )
    item = r.json()
    rel = item["asset_path"]

    got = await client.get(f"/assets/{rel}")
    assert got.status_code == 200
    assert got.content == b"\x89PNGdata"


@pytest.mark.asyncio
async def test_asset_traversal_blocked(client):
    r = await client.get("/assets/../../../../etc/passwd")
    # FastAPI collapses `..` in the URL path before we see it, but our
    # resolve_asset also guards; in either case we must not serve /etc/passwd.
    assert r.status_code in (400, 404)


@pytest.mark.asyncio
async def test_asset_missing_returns_404(client):
    r = await client.get("/assets/2026/01/does-not-exist.png")
    assert r.status_code == 404
