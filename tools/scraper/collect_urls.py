"""Collect every product URL from the almouggar.com sitemaps.

The shop sitemap splits into:
  * flat slugs          -> real products   (/shop/<slug>-<id>)   ~99 430
  * nested paths        -> taxonomy pages  (/shop/category/.., /shop/auteur/.., ...)

This module keeps only the first group and de-duplicates by template id.
"""

from __future__ import annotations

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parent.parent
DATA_DIR = PROJECT_ROOT / "data"

# /shop/<segment>/... is a taxonomy listing, never a product
NON_PRODUCT_SEGMENTS = {
    "category",
    "auteur",
    "auteurs",
    "serie",
    "collection",
    "editions",
    "marques",
    "cart",
    "checkout",
    "confirm_order",
    "payment",
    "extra_info",
    "change_pricelist",
    "product",
}

_RE_LOC = re.compile(r"<loc>(.*?)</loc>", re.S)
_RE_TRAILING_ID = re.compile(r"/shop/(?:.*-)?(\d+)/?$")


def _product_urls_from_sitemaps(sitemap_dir: Path) -> list[str]:
    urls: list[str] = []
    for f in sorted(sitemap_dir.glob("sitemap-*.xml")):
        text = f.read_text(encoding="utf-8", errors="replace")
        urls.extend(u.strip() for u in _RE_LOC.findall(text))
    return urls


def collect(sitemap_dir: Path = HERE) -> list[str]:
    raw = _product_urls_from_sitemaps(sitemap_dir)
    seen: dict[int, str] = {}
    for url in raw:
        if "/shop/" not in url:
            continue
        after = url.split("/shop/", 1)[1]
        segment = after.split("/", 1)[0]
        if "/" in after:  # nested taxonomy page
            continue
        if segment.lower() in NON_PRODUCT_SEGMENTS:
            continue
        m = _RE_TRAILING_ID.search(url.split("?")[0])
        if not m:
            continue
        tid = int(m.group(1))
        # normalise to https and a stable canonical form
        canonical = f"https://almouggar.com/shop/{m.group(1)}"
        if tid not in seen:
            seen[tid] = canonical
    return [seen[k] for k in sorted(seen)]


def write_urls(path: Path | None = None, sitemap_dir: Path = HERE) -> Path:
    urls = collect(sitemap_dir)
    out = path or (DATA_DIR / "product_urls.txt")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(urls) + "\n", encoding="utf-8")
    return out


if __name__ == "__main__":
    p = write_urls()
    n = sum(1 for _ in p.open(encoding="utf-8"))
    print(f"Wrote {n} product URLs -> {p}")
