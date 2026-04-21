from __future__ import annotations

import sys
from unittest.mock import MagicMock, patch

import pytest


def _make_pw_sync_api(page_html: str | None = None, launch_error: Exception | None = None):
    """Build a fake playwright.sync_api module that returns page_html."""
    mock_page = MagicMock()
    if page_html is not None:
        mock_page.content.return_value = page_html

    mock_browser = MagicMock()
    mock_browser.new_page.return_value = mock_page
    if launch_error:
        mock_browser.launch = MagicMock(side_effect=launch_error)

    mock_ctx = MagicMock()
    mock_ctx.__enter__ = lambda s: mock_ctx
    mock_ctx.__exit__ = MagicMock(return_value=False)
    if launch_error:
        mock_ctx.chromium.launch.side_effect = launch_error
    else:
        mock_ctx.chromium.launch.return_value = mock_browser

    mock_sync_playwright = MagicMock(return_value=mock_ctx)

    mock_sync_api = MagicMock()
    mock_sync_api.sync_playwright = mock_sync_playwright

    return mock_sync_api, mock_page, mock_browser


# ---------- unit: fetch_with_playwright ----------

def test_playwright_not_installed_returns_none():
    """ImportError → None, no exception raised."""
    from hypomnemata.playwright_scraper import fetch_with_playwright

    with patch.dict(sys.modules, {"playwright.sync_api": None}):
        result = fetch_with_playwright("http://example.com")

    assert result is None


def test_playwright_launch_failure_returns_none():
    """Browser launch exception → None, no exception raised."""
    mock_sync_api, _, _ = _make_pw_sync_api(launch_error=RuntimeError("no chromium binary"))

    with patch.dict(sys.modules, {"playwright": MagicMock(), "playwright.sync_api": mock_sync_api}):
        from hypomnemata.playwright_scraper import fetch_with_playwright
        result = fetch_with_playwright("http://example.com")

    assert result is None


def test_playwright_returns_rendered_html():
    """Successful render returns the page content string."""
    fake_html = "<html><body><h1>SPA Content</h1></body></html>"
    mock_sync_api, mock_page, mock_browser = _make_pw_sync_api(page_html=fake_html)

    with patch.dict(sys.modules, {"playwright": MagicMock(), "playwright.sync_api": mock_sync_api}):
        from hypomnemata.playwright_scraper import fetch_with_playwright
        result = fetch_with_playwright("http://spa-example.com")

    assert result == fake_html
    mock_page.goto.assert_called_once_with(
        "http://spa-example.com", wait_until="networkidle", timeout=30_000
    )
    mock_browser.close.assert_called_once()


def test_playwright_uses_realistic_user_agent():
    """UA string should look like a real browser, not a bot."""
    from hypomnemata.playwright_scraper import _UA

    assert "Mozilla" in _UA
    assert "Chrome" in _UA


# ---------- integration ----------

@pytest.mark.asyncio
async def test_article_capture_sets_download_pending(client):
    """Article URL without file should set download_status=pending."""
    r = await client.post(
        "/captures",
        data={"kind": "article", "source_url": "http://example.com/article"},
    )
    assert r.status_code == 201
    assert r.json()["download_status"] == "pending"
