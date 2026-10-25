#!/usr/bin/env python3
"""طباعة حالة الجمع: الروابط، المنتجات، الصور، والأخطاء.

الاستخدام:
    python tools/scraper/status.py
    python tools/scraper/status.py --json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[2] / "data"
URLS = DATA / "product_urls.txt"
PRODUCTS = DATA / "products.jsonl"
ERRORS = DATA / "errors.jsonl"
IMAGES = DATA / "product_images"
PAGES_DONE = DATA / ".pages_complete"

IMAGE_EXTS = (".jpg", ".png", ".webp", ".gif", ".bmp")


def url_id(url: str) -> str:
    return url.rstrip("/").rsplit("/", 1)[-1]


def read_url_ids() -> set[str]:
    if not URLS.exists():
        return set()
    return {
        url_id(line.strip())
        for line in URLS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def read_product_ids() -> tuple[set[int], set[int], int, int]:
    """(unique template ids, ids with an image url, records, malformed lines)"""
    ids: set[int] = set()
    with_image: set[int] = set()
    records = 0
    bad = 0
    if not PRODUCTS.exists():
        return ids, with_image, records, bad
    with PRODUCTS.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                bad += 1
                continue
            tid = rec.get("template_id")
            if isinstance(tid, int):
                ids.add(tid)
                if rec.get("image_url"):
                    with_image.add(tid)
            records += 1
    return ids, with_image, records, bad


def present_images() -> set[str]:
    if not IMAGES.is_dir():
        return set()
    return {
        entry.stem
        for entry in IMAGES.iterdir()
        if entry.is_file() and entry.suffix.lower() in IMAGE_EXTS
    }


def error_count() -> int:
    if not ERRORS.exists():
        return 0
    with ERRORS.open(encoding="utf-8", errors="replace") as fh:
        return sum(1 for line in fh if line.strip())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="output JSON only")
    args = parser.parse_args(argv)

    # وحدة التحكم في ويندوز قد تكون cp1252 — النص عربي.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    urls = read_url_ids()
    products, with_image_url, records, bad = read_product_ids()
    images = present_images()

    missing_products = len({u for u in urls if u.isdigit()} - {str(p) for p in products})
    missing_images = len({str(p) for p in with_image_url} - images)

    stats = {
        "urls_unique": len(urls),
        "products_unique": len(products),
        "product_records": records,
        "malformed_lines": bad,
        "missing_products": missing_products,
        "products_with_image_url": len(with_image_url),
        "images_present": len(images),
        "missing_images": missing_images,
        "errors_logged": error_count(),
        "pages_complete": PAGES_DONE.exists(),
    }

    if args.json:
        print(json.dumps(stats, ensure_ascii=False))
    else:
        print(f"الروابط الفريدة      : {stats['urls_unique']:,}")
        print(f"المنتجات المسجّلة    : {stats['products_unique']:,} (سجلات: {records:,})")
        print(f"منتجات ناقصة         : {stats['missing_products']:,}")
        print(f"لها رابط صورة        : {stats['products_with_image_url']:,}")
        print(f"الصور الموجودة       : {stats['images_present']:,}")
        print(f"صور ناقصة            : {stats['missing_images']:,}")
        print(f"أخطاء مسجّلة         : {stats['errors_logged']:,}")
        print(f"انتهاء صفحات         : {'نعم' if stats['pages_complete'] else 'لا'}")
        if bad:
            print(f"أسطر JSON تالفة      : {bad:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
