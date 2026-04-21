from __future__ import annotations

import pytest


async def _make(client, **kw):
    data = {"kind": "note", "title": "x", "tags": ""}
    data.update(kw)
    r = await client.post("/captures", data=data)
    assert r.status_code == 201, r.text
    return r.json()


@pytest.mark.asyncio
async def test_list_and_filter(client):
    await _make(client, kind="note", title="um")
    await _make(client, kind="article", title="dois")
    await _make(client, kind="article", title="três", tags="pesquisa")

    all_r = await client.get("/items")
    assert all_r.status_code == 200
    assert all_r.json()["total"] == 3

    art = await client.get("/items", params={"kind": "article"})
    assert art.json()["total"] == 2

    tag = await client.get("/items", params={"tag": "pesquisa"})
    assert tag.json()["total"] == 1
    assert tag.json()["items"][0]["title"] == "três"


@pytest.mark.asyncio
async def test_get_one_and_patch(client):
    item = await _make(client, title="antes", tags="a")
    iid = item["id"]

    got = await client.get(f"/items/{iid}")
    assert got.status_code == 200
    assert got.json()["title"] == "antes"

    patched = await client.patch(
        f"/items/{iid}", json={"title": "depois", "tags": ["b", "c"]}
    )
    assert patched.status_code == 200
    body = patched.json()
    assert body["title"] == "depois"
    assert set(body["tags"]) == {"b", "c"}


@pytest.mark.asyncio
async def test_delete_removes_asset(client):
    from hypomnemata.config import settings

    r = await client.post(
        "/captures",
        data={"kind": "image"},
        files={"file": ("a.png", b"\x89PNGfake", "image/png")},
    )
    item = r.json()
    rel = item["asset_path"]
    disk = settings.assets_dir / rel
    assert disk.is_file()

    d = await client.delete(f"/items/{item['id']}")
    assert d.status_code == 204
    assert not disk.exists()

    gone = await client.get(f"/items/{item['id']}")
    assert gone.status_code == 404


@pytest.mark.asyncio
async def test_tags_endpoint(client):
    await _make(client, title="a", tags="x, y")
    await _make(client, title="b", tags="y")
    r = await client.get("/tags")
    assert r.status_code == 200
    by_name = {t["name"]: t["count"] for t in r.json()}
    assert by_name == {"x": 1, "y": 2}
