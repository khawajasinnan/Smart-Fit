"""Polite HTTP for catalog scraping (spec §10).

* Identifies itself with SCRAPER_USER_AGENT (no browser impersonation).
* Checks robots.txt before every request (Protego supports the `*` / `$`
  wildcards Shopify robots files use; Python's urllib.robotparser doesn't).
* Waits SCRAPER_RATE_LIMIT_SECONDS between requests to the same host.
* No retries around blocks, no proxies, no header tricks: if a site says no,
  the caller reports it and falls back to manual collection.
"""

from __future__ import annotations

import asyncio
import time
from urllib.parse import urlparse

import httpx
from protego import Protego

from shared.config import settings


class RobotsDisallowed(Exception):
    """robots.txt forbids this URL for our user agent."""


class PoliteClient:
    def __init__(self, client: httpx.AsyncClient, user_agent: str | None = None, delay: float | None = None) -> None:
        self._client = client
        self.user_agent = user_agent or settings.scraper_user_agent
        self.delay = settings.scraper_rate_limit_seconds if delay is None else delay
        self._robots: dict[str, Protego | None] = {}
        self._last: dict[str, float] = {}
        self._locks: dict[str, asyncio.Lock] = {}

    async def _robots_for(self, origin: str) -> Protego | None:
        """Parsed robots.txt, or None = everything allowed (4xx / no file)."""
        if origin not in self._robots:
            await self._wait_turn(origin)
            res = await self._client.get(f"{origin}/robots.txt", headers={"User-Agent": self.user_agent}, timeout=20)
            if res.status_code >= 500:
                # Server error: be conservative and treat the whole site as off-limits.
                raise RobotsDisallowed(f"{origin}/robots.txt returned {res.status_code}")
            self._robots[origin] = Protego.parse(res.text) if res.status_code == 200 else None
        return self._robots[origin]

    async def _wait_turn(self, origin: str) -> None:
        lock = self._locks.setdefault(origin, asyncio.Lock())
        async with lock:
            wait = self._last.get(origin, 0.0) + self.delay - time.monotonic()
            if wait > 0:
                await asyncio.sleep(wait)
            self._last[origin] = time.monotonic()

    async def allowed(self, url: str) -> bool:
        parsed = urlparse(url)
        robots = await self._robots_for(f"{parsed.scheme}://{parsed.netloc}")
        return robots is None or robots.can_fetch(url, self.user_agent)

    async def get(self, url: str, **kwargs) -> httpx.Response:
        if not await self.allowed(url):
            raise RobotsDisallowed(f"robots.txt disallows {url}")
        parsed = urlparse(url)
        await self._wait_turn(f"{parsed.scheme}://{parsed.netloc}")
        headers = {"User-Agent": self.user_agent, **kwargs.pop("headers", {})}
        return await self._client.get(url, headers=headers, timeout=kwargs.pop("timeout", 30), **kwargs)
