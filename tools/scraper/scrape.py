"""almouggar.com crawler — product pages + product images.

Phases
------
urls    collect all product URLs from the sitemaps          (fast, offline)
pages   fetch every product page, parse it -> products.jsonl (resumable)
images  download every product image -> product_images/      (resumable)

Both network phases are resumable: re-running skips whatever is already on disk.
Records are streamed straight to disk so an interrupted run loses nothing.

Usage
-----
    python scrape.py urls
    python scrape.py pages                 # all ~99k pages
    python scrape.py pages --limit 500     # pilot
    python scrape.py images
    python scrape.py images --concurrency 32
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import signal
import sys
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

import aiohttp

from collect_urls import DATA_DIR, write_urls
from parse_product import parse_product

HERE = Path(__file__).resolve().parent

URLS_FILE = DATA_DIR / "product_urls.txt"
PRODUCTS_FILE = DATA_DIR / "products.jsonl"
ERRORS_FILE = DATA_DIR / "errors.jsonl"
IMAGES_DIR = DATA_DIR / "product_images"

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "fr-FR,fr;q=0.9,ar;q=0.8,en;q=0.7",
}

EXT_BY_TYPE = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
    "image/bmp": ".bmp",
}


# ─────────────────────────────────────────────────────────────── helpers


def template_ids_in(path: Path) -> set[int]:
    """All template ids already present in a jsonl file (resume support)."""
    done: set[int] = set()
    if not path.exists():
        return done
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            tid = rec.get("template_id")
            if isinstance(tid, int):
                done.add(tid)
    return done


def read_urls() -> list[str]:
    if not URLS_FILE.exists():
        print(f"[!] {URLS_FILE} missing - running 'urls' phase first")
        write_urls()
    return [u for u in URLS_FILE.read_text(encoding="utf-8").splitlines() if u.strip()]


class Progress:
    """Minimal, dependency-free progress line (works in any console)."""

    def __init__(self, total: int, label: str) -> None:
        self.total = total
        self.label = label
        self.done = 0
        self.failed = 0
        self.started = time.time()
        self._last = 0.0

    def tick(self, ok: bool = True, force: bool = False) -> None:
        self.done += 1
        if not ok:
            self.failed += 1
        now = time.time()
        if not force and now - self._last < 1.0:
            return
        self._last = now
        elapsed = now - self.started
        rate = self.done / elapsed if elapsed else 0.0
        remaining = (self.total - self.done) / rate if rate else 0.0
        eta = f"{remaining / 60:6.1f}m" if remaining < 3600 else f"{remaining / 3600:5.2f}h"
        pct = 100.0 * self.done / self.total if self.total else 100.0
        sys.stdout.write(
            f"\r  {self.label}: {self.done}/{self.total} ({pct:5.1f}%) "
            f"fail={self.failed} {rate:5.1f}/s eta={eta}   "
        )
        sys.stdout.flush()

    def finish(self) -> None:
        self._last = 0.0
        self.tick(force=True)
        self.done -= 1  # tick() above incremented for the final render
        sys.stdout.write("\n")
        sys.stdout.flush()


# ─────────────────────────────────────────────────────────────── pages


async def fetch_page(
    session: aiohttp.ClientSession,
    url: str,
    sem: asyncio.Semaphore,
    retries: int,
    timeout: float,
) -> tuple[bytes | None, str | None]:
    last_err: str | None = None
    for attempt in range(retries + 1):
        try:
            async with sem:
                async with session.get(
                    url, timeout=aiohttp.ClientTimeout(total=timeout)
                ) as resp:
                    if resp.status == 200:
                        return await resp.read(), None
                    if resp.status in (404, 410):
                        return None, f"HTTP {resp.status}"
                    last_err = f"HTTP {resp.status}"
                    if resp.status in (429, 503):
                        ra = resp.headers.get("Retry-After")
                        delay = float(ra) if (ra or "").isdigit() else 20.0
                        await asyncio.sleep(min(delay, 120.0))
        except Exception as exc:  # noqa: BLE001
            last_err = f"{type(exc).__name__}: {exc}"
        if attempt < retries:
            await asyncio.sleep(min(30.0, 1.5 * (2**attempt)) + random.random())
    return None, last_err or "unknown error"


def parse_bytes(url: str, raw: bytes) -> dict:
    """Decode + parse entirely inside the worker thread (keeps the loop free)."""
    return parse_product(url, raw.decode("utf-8", errors="replace"))


async def crawl_pages(
    urls: list[str],
    concurrency: int,
    retries: int,
    timeout: float,
    limit: int | None,
    shard: int = 0,
    shards: int = 1,
) -> None:
    done = template_ids_in(PRODUCTS_FILE)
    todo: list[str] = []
    for u in urls:
        tid = int(u.rstrip("/").rsplit("/", 1)[-1])
        if tid in done:
            continue
        # deterministic sharding by template id so parallel workers never overlap
        if shards > 1 and tid % shards != shard:
            continue
        todo.append(u)
    if limit:
        todo = todo[:limit]

    print(f"[pages] already done: {len(done)}   to fetch: {len(todo)}")
    if not todo:
        return

    sem = asyncio.Semaphore(concurrency)
    progress = Progress(len(todo), "pages")
    queue: asyncio.Queue[dict] = asyncio.Queue()
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    # Parsing is CPU bound (regex over ~290 KB of HTML) and holds the GIL, so a
    # generous thread pool keeps the network pipeline busy.
    pool = ThreadPoolExecutor(max_workers=max(8, min(32, concurrency // 2)))

    def _sigint(*_: object) -> None:
        print("\n[pages] interrupted - finishing in-flight work and flushing...")
        stop.set()

    try:
        signal.signal(signal.SIGINT, _sigint)
    except (ValueError, OSError):
        pass

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    products_fh = PRODUCTS_FILE.open("a", encoding="utf-8")
    errors_fh = ERRORS_FILE.open("a", encoding="utf-8")

    async def writer() -> None:
        while True:
            rec = await queue.get()
            try:
                if rec is None:
                    return
                if rec.get("_error"):
                    errors_fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
                else:
                    products_fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
                if progress.done % 200 == 0:
                    products_fh.flush()
                    errors_fh.flush()
            finally:
                queue.task_done()

    writer_task = asyncio.create_task(writer())

    connector = aiohttp.TCPConnector(limit=concurrency, ttl_dns_cache=600)
    async with aiohttp.ClientSession(headers=HEADERS, connector=connector) as session:

        async def worker(url: str) -> None:
            if stop.is_set():
                return
            html, err = await fetch_page(session, url, sem, retries, timeout)
            if html is None:
                await queue.put({"url": url, "_error": err})
                progress.tick(ok=False)
                return
            try:
                rec = await loop.run_in_executor(pool, parse_bytes, url, html)
            except Exception as exc:  # noqa: BLE001
                await queue.put({"url": url, "_error": f"parse: {exc}"})
                progress.tick(ok=False)
                return
            if rec.get("template_id") is None or not rec.get("name"):
                await queue.put({"url": url, "_error": "incomplete record", **rec})
                progress.tick(ok=False)
                return
            await queue.put(rec)
            progress.tick()

        tasks = [asyncio.create_task(worker(u)) for u in todo]
        try:
            await asyncio.gather(*tasks)
        finally:
            for t in tasks:
                if not t.done():
                    t.cancel()
            await queue.put(None)
            await writer_task
            pool.shutdown(wait=False)

    products_fh.close()
    errors_fh.close()
    progress.finish()
    print(f"[pages] records -> {PRODUCTS_FILE}")
    if limit is None:
        (DATA_DIR / ".pages_complete").write_text(
            time.strftime("%Y-%m-%d %H:%M:%S"), encoding="utf-8"
        )
        print("[pages] full crawl complete")


# ─────────────────────────────────────────────────────────────── images


def load_image_targets() -> list[tuple[int, str]]:
    """(template_id, image_url) for records that still need a download."""
    targets: list[tuple[int, str]] = []
    if not PRODUCTS_FILE.exists():
        return targets
    with PRODUCTS_FILE.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            tid, url = rec.get("template_id"), rec.get("image_url")
            if isinstance(tid, int) and url:
                targets.append((tid, url))
    return targets


def existing_image(tid: int) -> str | None:
    for ext in (".jpg", ".png", ".webp", ".gif", ".bmp"):
        if (IMAGES_DIR / f"{tid}{ext}").exists():
            return f"{tid}{ext}"
    return None


async def crawl_images(
    concurrency: int,
    retries: int,
    timeout: float,
    limit: int | None,
    follow: bool = False,
    interval: float = 90.0,
    shard: int = 0,
    shards: int = 1,
) -> None:
    marker = DATA_DIR / ".pages_complete"
    while True:
        missing = await _images_pass(concurrency, retries, timeout, limit, shard, shards)
        if not follow:
            break
        if marker.exists() and missing == 0:
            print("[images] pages complete and no image missing - done")
            break
        print(f"[images] {missing} still missing, re-checking in {interval:.0f}s...")
        await asyncio.sleep(interval)


async def _images_pass(
    concurrency: int,
    retries: int,
    timeout: float,
    limit: int | None,
    shard: int = 0,
    shards: int = 1,
) -> int:
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    all_targets = load_image_targets()
    todo = [
        (t, u)
        for t, u in all_targets
        if existing_image(t) is None
        # deterministic sharding by template id so parallel workers never overlap
        and (shards <= 1 or t % shards == shard)
    ]
    if limit:
        todo = todo[:limit]
    print(f"[images] products: {len(all_targets)}   missing: {len(todo)}")
    if not todo:
        return 0

    sem = asyncio.Semaphore(concurrency)
    progress = Progress(len(todo), "images")
    stop = asyncio.Event()

    def _sigint(*_: object) -> None:
        print("\n[images] interrupted - stopping...")
        stop.set()

    try:
        signal.signal(signal.SIGINT, _sigint)
    except (ValueError, OSError):
        pass

    sizing = "image_512"
    connector = aiohttp.TCPConnector(limit=concurrency, ttl_dns_cache=600)
    async with aiohttp.ClientSession(headers=HEADERS, connector=connector) as session:

        async def one(tid: int, url: str) -> None:
            if stop.is_set():
                return
            # normalise to the requested size
            if "/image_" in url:
                url = url.rsplit("/image_", 1)[0] + "/" + sizing
            last_err = ""
            for attempt in range(retries + 1):
                try:
                    async with sem:
                        async with session.get(
                            url, timeout=aiohttp.ClientTimeout(total=timeout)
                        ) as resp:
                            if resp.status == 200:
                                data = await resp.read()
                                if not data:
                                    last_err = "empty body"
                                else:
                                    ctype = (resp.headers.get("Content-Type") or "").split(";")[0].strip()
                                    ext = EXT_BY_TYPE.get(ctype, ".jpg")
                                    (IMAGES_DIR / f"{tid}{ext}").write_bytes(data)
                                    progress.tick()
                                    return
                            else:
                                last_err = f"HTTP {resp.status}"
                except Exception as exc:  # noqa: BLE001
                    last_err = f"{type(exc).__name__}: {exc}"
                if attempt < retries:
                    await asyncio.sleep(min(20.0, 1.0 * (2**attempt)) + random.random())
            progress.tick(ok=False)

        tasks = [asyncio.create_task(one(t, u)) for t, u in todo]
        try:
            await asyncio.gather(*tasks)
        finally:
            for t in tasks:
                if not t.done():
                    t.cancel()

    progress.finish()
    print(f"[images] -> {IMAGES_DIR}")
    return progress.failed


# ─────────────────────────────────────────────────────────────── cli


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="phase", required=True)

    sub.add_parser("urls", help="collect product urls from the sitemaps")

    sp = sub.add_parser("pages", help="fetch + parse product pages")
    sp.add_argument("--concurrency", type=int, default=12)
    sp.add_argument("--retries", type=int, default=3)
    sp.add_argument("--timeout", type=float, default=45.0)
    sp.add_argument("--limit", type=int, default=None)
    sp.add_argument("--shard", type=int, default=0,
                    help="this worker's shard index (0-based)")
    sp.add_argument("--shards", type=int, default=1,
                    help="total number of parallel workers (for splitting work)")

    si = sub.add_parser("images", help="download product images")
    si.add_argument("--concurrency", type=int, default=24)
    si.add_argument("--retries", type=int, default=3)
    si.add_argument("--timeout", type=float, default=45.0)
    si.add_argument("--limit", type=int, default=None)
    si.add_argument("--shard", type=int, default=0,
                    help="this worker's shard index (0-based)")
    si.add_argument("--shards", type=int, default=1,
                    help="total number of parallel workers (for splitting work)")
    si.add_argument("--follow", action="store_true",
                    help="keep re-scanning until the page crawl is done and no image is missing")
    si.add_argument("--interval", type=float, default=90.0)

    return p


def main() -> None:
    args = build_parser().parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    if args.phase == "urls":
        path = write_urls()
        n = sum(1 for _ in path.open(encoding="utf-8"))
        print(f"Wrote {n} product URLs -> {path}")
    elif args.phase == "pages":
        asyncio.run(crawl_pages(
            read_urls(), args.concurrency, args.retries, args.timeout, args.limit,
            args.shard, args.shards,
        ))
    elif args.phase == "images":
        asyncio.run(
            crawl_images(
                args.concurrency, args.retries, args.timeout, args.limit,
                args.follow, args.interval, args.shard, args.shards,
            )
        )


if __name__ == "__main__":
    main()
