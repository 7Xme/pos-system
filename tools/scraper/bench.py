"""Throughput benchmark: can multiple processes exceed the single-process ~5 req/s?"""

from __future__ import annotations

import argparse
import asyncio
import time
from pathlib import Path

import aiohttp

from collect_urls import DATA_DIR

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
}


async def run(concurrency: int, n: int, offset: int) -> None:
    urls = [
        u
        for u in (DATA_DIR / "product_urls.txt").read_text(encoding="utf-8").splitlines()
        if u.strip()
    ][offset : offset + n]

    sem = asyncio.Semaphore(concurrency)
    done = 0
    started = time.time()
    connector = aiohttp.TCPConnector(limit=concurrency)
    async with aiohttp.ClientSession(headers=HEADERS, connector=connector) as s:

        async def one(u: str) -> None:
            nonlocal done
            async with sem:
                try:
                    async with s.get(u, timeout=aiohttp.ClientTimeout(total=60)) as r:
                        await r.read()
                except Exception:
                    pass
            done += 1

        await asyncio.gather(*(one(u) for u in urls))
    el = time.time() - started
    print(f"concurrency={concurrency} n={n} offset={offset} elapsed={el:.1f}s -> {done / el:.2f} req/s")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--concurrency", type=int, default=32)
    p.add_argument("--n", type=int, default=150)
    p.add_argument("--offset", type=int, default=0)
    a = p.parse_args()
    asyncio.run(run(a.concurrency, a.n, a.offset))
