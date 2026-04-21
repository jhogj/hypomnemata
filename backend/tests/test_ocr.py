from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest


# ---------- unit ----------

def test_is_ocr_candidate_images():
    from hypomnemata.ocr import is_ocr_candidate
    for ext in (".png", ".jpg", ".jpeg", ".webp", ".tiff"):
        assert is_ocr_candidate(f"2026/04/abc{ext}") is True


def test_is_ocr_candidate_pdf():
    from hypomnemata.ocr import is_ocr_candidate
    assert is_ocr_candidate("2026/04/doc.pdf") is True


def test_is_ocr_candidate_unsupported():
    from hypomnemata.ocr import is_ocr_candidate
    for ext in (".mp4", ".txt", ".html", ".bin"):
        assert is_ocr_candidate(f"2026/04/abc{ext}") is False


def test_ocr_image_uses_pytesseract(tmp_path: Path):
    from PIL import Image
    from hypomnemata.ocr import _ocr_image

    img_path = tmp_path / "blank.png"
    Image.new("RGB", (200, 50), "white").save(img_path)

    with patch("pytesseract.image_to_string", return_value="texto extraído  \n") as mock_ocr:
        result = _ocr_image(img_path)

    mock_ocr.assert_called_once()
    assert result == "texto extraído"


def test_ocr_pdf_extracts_text(tmp_path: Path):
    from pypdf import PdfWriter
    from hypomnemata.ocr import _ocr_pdf

    pdf_path = tmp_path / "test.pdf"
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    with open(pdf_path, "wb") as f:
        writer.write(f)

    # Blank page has no text — result should be empty string
    result = _ocr_pdf(pdf_path)
    assert result == ""


# ---------- integration ----------

@pytest.mark.asyncio
async def test_capture_image_ocr_status_pending(client):
    """Screenshot capture should set ocr_status=pending on the response."""
    files = {"file": ("screenshot.png", b"\x89PNG\r\n\x1a\nfake", "image/png")}
    r = await client.post("/captures", data={"kind": "image"}, files=files)
    assert r.status_code == 201
    # Response body is built before background task runs, so status is "pending"
    assert r.json()["ocr_status"] == "pending"


@pytest.mark.asyncio
async def test_capture_note_no_ocr_status(client):
    """Items without a file asset should have ocr_status=None."""
    r = await client.post("/captures", data={"kind": "note", "title": "sem ocr"})
    assert r.status_code == 201
    assert r.json()["ocr_status"] is None


@pytest.mark.asyncio
async def test_ocr_status_exposed_in_get(client):
    """ocr_status should be visible when fetching the item by id."""
    files = {"file": ("cap.png", b"\x89PNG\r\n\x1a\nfake", "image/png")}
    r = await client.post("/captures", data={"kind": "image"}, files=files)
    item_id = r.json()["id"]

    r2 = await client.get(f"/items/{item_id}")
    assert r2.status_code == 200
    assert r2.json()["ocr_status"] is not None  # pending, done, or error
