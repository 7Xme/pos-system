"""Where does the per-page time actually go? fetch vs decode vs parse."""

from __future__ import annotations

import asyncio
import time
from pathlib import Path

import aiohttp

from collect_urls import DATA_DIR
from parse_product import parse_product

HEADERS = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120"}


async def main(n: int = 40) -> None:
    urls = [
        u for u in (DATA_DIR / "product_urls.txt").read_text(encoding="utf-8").splitlines()
        if u.strip()
    ][40000 : 40000 + n]

    t0 = time.perf_counter()
    conn = aiohttp.TCPConnector(limit=32)
    async with aiohttp.ClientSession(headers=HEADERS, connector=conn) as s:
        async def grab(u: str) -> bytes:
            async with s.get(u, timeout=aiohttp.ClientTimeout(total=60)) as r:
                return await r.read()

        blobs = await asyncio.gather(*(grab(u) for u in urls))
    fetch_t = time.perf_counter() - t0

    t1 = time.perf_counter()
    texts = [b.decode("utf-8", errors="replace") for b in blobs]
    decode_t = time.perf_counter() - t1

    t2 = time.perf_counter()
    for u, txt in zip(urls, texts):
        parse_product(u, txt)
    parse_t = time.perf_counter() - t2

    total_bytes = sum(len(b) for b in blobs)
    print(f"pages={n}  avg size={total_bytes / n / 1024:.0f} KB")
    print(f"fetch   (concurrency 32, wall) : {fetch_t:7.2f}s  -> {n / fetch_t:6.1f} req/s")
    print(f"decode  (serial)               : {decode_t:7.3f}s  -> {decode_t / n * 1000:6.2f} ms/page")
    print(f"parse   (serial)               : {parse_t:7.3f}s  -> {parse_t / n * 1000:6.2f} ms/page")
    print(f"cpu/page (decode+parse)        : {(decode_t + parse_t) / n * 1000:6.2f} ms")
    print(f"cpu ceiling (1 core)           : {(decode_t + parse_t) and n / (decode_t + parse_t):6.1f} req/s")


if __name__ == "__main__":
    asyncio.run(main())
