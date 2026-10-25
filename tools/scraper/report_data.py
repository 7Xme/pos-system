"""Data-quality report over the scraped products.jsonl."""

from __future__ import annotations

import json
import sys
from collections import Counter

from collect_urls import DATA_DIR


def main() -> None:
    path = DATA_DIR / "products.jsonl"
    recs = []
    bad = 0
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                recs.append(json.loads(line))
            except json.JSONDecodeError:
                bad += 1

    uniq = {r["template_id"]: r for r in recs if isinstance(r.get("template_id"), int)}
    rows = list(uniq.values())
    n = len(rows)
    print(f"lines={len(recs)} bad_json={bad} unique_products={n}")

    c = Counter()
    barcodes: Counter[str] = Counter()
    for r in rows:
        if not r.get("barcode"):
            c["no_barcode"] += 1
        else:
            barcodes[r["barcode"]] += 1
        if r.get("price") is None:
            c["no_price"] += 1
        elif r.get("price") == 0:
            c["zero_price"] += 1
        if not r.get("name"):
            c["no_name"] += 1
        if not r.get("category"):
            c["no_category"] += 1
        if not r.get("image_url"):
            c["no_image_url"] += 1
        if r.get("isbn"):
            c["has_isbn"] += 1
        if r.get("brand"):
            c["has_brand"] += 1
        if r.get("author"):
            c["has_author"] += 1
        if r.get("in_stock") is False:
            c["out_of_stock"] += 1

    print("\nfield coverage:")
    for k, v in sorted(c.items()):
        print(f"  {k:16s} {v:7d}  ({100 * v / n:5.1f}%)")

    dupes = {b: k for b, k in barcodes.items() if k > 1}
    print(f"\ndistinct barcodes: {len(barcodes)}   duplicated: {len(dupes)}")
    if dupes:
        for b, k in list(dupes.items())[:10]:
            print(f"   {b} x{k}")

    lens = [len(b) for b in barcodes]
    print("\nbarcode length histogram:")
    for ln, k in sorted(Counter(lens).items()):
        print(f"  {ln:3d} chars: {k}")

    print("\nsample records:")
    for r in rows[:3]:
        print("  ", json.dumps({k: r[k] for k in (
            "template_id", "name", "barcode", "price", "category", "brand", "isbn")},
            ensure_ascii=False))

    print("\ntop categories:")
    for cat, k in Counter(r.get("category") or "(none)" for r in rows).most_common(12):
        print(f"  {k:6d}  {cat}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
