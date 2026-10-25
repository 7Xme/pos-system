"""Analyze the almouggar sitemaps: how many real product URLs vs. category pages."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent

NON_PRODUCT_SEGMENTS = {
    "category",
    "auteur",
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


def main() -> None:
    urls: list[str] = []
    for f in sorted(HERE.glob("sitemap-*.xml")):
        text = f.read_text(encoding="utf-8", errors="replace")
        found = re.findall(r"<loc>(.*?)</loc>", text, re.S)
        print(f"{f.name}: {len(found)} loc entries")
        urls.extend(u.strip() for u in found)

    print(f"TOTAL loc: {len(urls)}")

    shop = [u for u in urls if "/shop/" in u]
    print(f"/shop/ URLs: {len(shop)}")

    buckets: Counter[str] = Counter()
    product_like: list[str] = []
    for u in shop:
        after = u.split("/shop/", 1)[1]
        seg = after.split("/", 1)[0]
        if "/" in after:
            buckets[f"nested:{seg}"] += 1
        else:
            buckets["flat"] += 1
            product_like.append(u)

    for k, v in buckets.most_common(40):
        print(f"  {k:32s} {v}")

    print(f"\nflat product-like: {len(product_like)}")
    for u in product_like[:10]:
        print("  ", u)

    # shape of the flat slugs
    shapes: Counter[str] = Counter()
    for u in product_like:
        slug = u.split("/shop/", 1)[1]
        if re.fullmatch(r"\d+", slug):
            shapes["id"] += 1
        elif re.fullmatch(r"[\w-]+-\d+", slug):
            shapes["slug-id"] += 1
        elif re.fullmatch(r"\d+-\d+", slug):
            shapes["id-id"] += 1
        else:
            shapes["other"] += 1
            print("   OTHER:", u)
    for k, v in shapes.most_common():
        print(f"  shape {k:10s} {v}")

    # non-shop urls
    other = [u for u in urls if "/shop/" not in u]
    print(f"\nnon-shop urls: {len(other)}")
    for u in other[:20]:
        print("  ", u)

    # duplicates
    print(f"\nunique shop urls: {len(set(shop))}")


if __name__ == "__main__":
    main()
