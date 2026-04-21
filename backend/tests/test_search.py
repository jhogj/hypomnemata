from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_search_fts_basic(client):
    await client.post("/captures", data={"kind": "note", "title": "filosofia grega", "body_text": "Sócrates"})
    await client.post("/captures", data={"kind": "note", "title": "design de sistemas", "body_text": "API"})

    r = await client.get("/search", params={"q": "filosofia"})
    assert r.status_code == 200
    data = r.json()
    assert data["total"] == 1
    assert data["items"][0]["title"] == "filosofia grega"


@pytest.mark.asyncio
async def test_search_diacritics_insensitive(client):
    await client.post("/captures", data={"kind": "note", "title": "filosófia", "body_text": "—"})

    r = await client.get("/search", params={"q": "filosofia"})
    assert r.status_code == 200
    assert r.json()["total"] == 1


@pytest.mark.asyncio
async def test_search_prefix_match(client):
    await client.post("/captures", data={"kind": "note", "title": "arquitetura de software"})
    r = await client.get("/search", params={"q": "arqui"})
    assert r.json()["total"] == 1


@pytest.mark.asyncio
async def test_search_updates_after_patch(client):
    r = await client.post("/captures", data={"kind": "note", "title": "antigo"})
    iid = r.json()["id"]

    r1 = await client.get("/search", params={"q": "novo"})
    assert r1.json()["total"] == 0

    await client.patch(f"/items/{iid}", json={"title": "novo titulo"})
    r2 = await client.get("/search", params={"q": "novo"})
    assert r2.json()["total"] == 1
