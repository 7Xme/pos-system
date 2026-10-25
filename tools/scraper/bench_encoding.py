"""Does gzip/Brotli transfer encoding change the achievable request rate?"""

from __future__ import annotations

import asyncio
import time

import aiohttp

from collect_urls import DATA_DIR

BASE_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


async def run(label: str, headers: dict, concurrency: int, n: int, offset: int) -> None:
    urls = [
        u for u in (DATA_DIR / "product_urls.txt").read_text(encoding="utf-8").splitlines()
        if u.strip()
    ][offset : offset + n]
    sem = asyncio.Semaphore(concurrency)
    total = 0
    encoding = "?"
    started = time.perf_counter()
    conn = aiohttp.TCPConnector(limit=concurrency)
    async with aiohttp.ClientSession(headers=headers, connector=conn) as s:

        async def one(u: str) -> None:
            nonlocal total, encoding
            async with sem:
                try:
                    async with s.get(u, timeout=aiohttp.ClientTimeout(total=60)) as r:
                        encoding = r.headers.get("Content-Encoding", "identity")
                        data = await r.read()
                        total += len(data)
                except Exception:
                    pass

        await asyncio.gather(*(one(u) for u in urls))
    el = time.perf_counter() - started
    print(
        f"{label:34s} c={concurrency:3d} {n / el:6.2f} req/s  "
        f"avg={total / max(n, 1) / 1024:6.1f} KB  enc={encoding}"
    )


async def main() -> None:
    ident = {"User-Agent": BASE_UA}
    gz = {"User-Agent": BASE_UA, "Accept-Encoding": "gzip, deflate, br"}
    await run("identity            c=32", ident, 32, 150, 60000)
    await run("gzip/br             c=32", gz, 32, 150, 60000)
    await run("gzip/br             c=64", gz, 64, 200, 70000)
    await run("gzip/br             c=96", gz, 96, 200, 80000)


if __name__ == "__main__":
    asyncio.run(main())
