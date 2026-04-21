"""Headless browser rendering for JavaScript-heavy pages (SPA fallback)."""
from __future__ import annotations

import logging

log = logging.getLogger("hypomnemata.playwright")

_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)


def fetch_with_playwright(url: str, timeout_ms: int = 30_000) -> str | None:
    """Render url with headless Chromium; return full HTML or None on failure.

    Requires `playwright install chromium` to have been run once.
    Returns None gracefully if playwright is not installed or rendering fails.
    """
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        log.debug("playwright not installed, skipping JS render for %s", url)
        return None

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            try:
                page = browser.new_page(
                    user_agent=_UA,
                    extra_http_headers={"Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8"},
                )
                page.goto(url, wait_until="networkidle", timeout=timeout_ms)
                return page.content()
            finally:
                browser.close()
    except Exception as exc:
        log.warning("playwright render failed for %s: %s", url, exc)
        return None
