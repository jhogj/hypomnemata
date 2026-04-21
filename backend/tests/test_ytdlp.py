from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest


# ---------- unit ----------

def test_find_media_files_video(tmp_path: Path):
    from hypomnemata.ytdlp import _find_media_files

    (tmp_path / "001.mp4").touch()
    (tmp_path / "001.info.json").touch()

    result = _find_media_files(tmp_path)
    assert len(result) == 1
    assert result[0].name == "001.mp4"


def test_find_media_files_images(tmp_path: Path):
    from hypomnemata.ytdlp import _find_media_files

    (tmp_path / "001.jpg").touch()
    (tmp_path / "002.jpg").touch()
    (tmp_path / "003.jpg").touch()
    (tmp_path / "001.info.json").touch()

    result = _find_media_files(tmp_path)
    assert len(result) == 3
    assert all(f.suffix == ".jpg" for f in result)


def test_find_media_files_missing(tmp_path: Path):
    from hypomnemata.ytdlp import _find_media_files

    nonexistent = tmp_path / "nodir"
    assert _find_media_files(nonexistent) == []


def test_download_tweet_images_no_gallerydl_no_network(tmp_path: Path):
    """When gallery-dl is absent and oEmbed fails, returns ([], None) without raising."""
    from hypomnemata.ytdlp import _download_tweet_images

    subdir = tmp_path / "item123"
    subdir.mkdir()

    import urllib.request

    def bad_urlopen(*_a, **_kw):
        raise OSError("no network in tests")

    with patch("subprocess.run", side_effect=FileNotFoundError):
        with patch.object(urllib.request, "urlopen", side_effect=bad_urlopen):
            files, text = _download_tweet_images(
                "https://x.com/user/status/1", subdir, 10 * 1024 * 1024
            )

    assert files == []
    assert text is None


# ---------- integration ----------

@pytest.mark.asyncio
async def test_capture_video_url_sets_download_pending(client):
    """Captura com kind=video e source_url deve retornar download_status=pending."""
    r = await client.post(
        "/captures",
        data={"kind": "video", "source_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"},
    )
    assert r.status_code == 201
    assert r.json()["download_status"] == "pending"


@pytest.mark.asyncio
async def test_capture_video_file_only_no_download(client):
    """Vídeo enviado como arquivo (sem source_url) não deve disparar download."""
    files = {"file": ("clip.mp4", b"fake-mp4-data", "video/mp4")}
    r = await client.post("/captures", data={"kind": "video"}, files=files)
    assert r.status_code == 201
    assert r.json()["download_status"] is None


@pytest.mark.asyncio
async def test_capture_image_no_download_status(client):
    """Imagens nunca devem ter download_status."""
    files = {"file": ("shot.png", b"\x89PNG\r\n\x1a\nfake", "image/png")}
    r = await client.post("/captures", data={"kind": "image"}, files=files)
    assert r.status_code == 201
    assert r.json()["download_status"] is None


@pytest.mark.asyncio
async def test_download_status_in_get(client):
    """download_status deve aparecer no GET /items/{id}."""
    r = await client.post(
        "/captures",
        data={"kind": "video", "source_url": "https://www.youtube.com/watch?v=test"},
    )
    item_id = r.json()["id"]
    r2 = await client.get(f"/items/{item_id}")
    assert r2.status_code == 200
    assert r2.json()["download_status"] is not None


@pytest.mark.asyncio
async def test_run_ytdlp_sync_missing_dep(client):
    """Se yt-dlp não estiver disponível, download_status vira error:missing_dep."""
    r = await client.post(
        "/captures",
        data={"kind": "video", "source_url": "https://www.youtube.com/watch?v=test"},
    )
    item_id = r.json()["id"]

    from hypomnemata.ytdlp import _run_ytdlp_sync
    import builtins
    real_import = builtins.__import__

    def block_ytdlp(name, *args, **kwargs):
        if name == "yt_dlp":
            raise ImportError("yt_dlp not available in test")
        return real_import(name, *args, **kwargs)

    with patch("builtins.__import__", side_effect=block_ytdlp):
        _run_ytdlp_sync(item_id)

    r2 = await client.get(f"/items/{item_id}")
    assert r2.json()["download_status"] == "error:missing_dep"
