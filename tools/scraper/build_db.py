"""Build a Drift-compatible SQLite database from the scraped JSONL.

Output: data/bookstore_pos.sqlite

Schema mirrors lib/core/database/tables.dart exactly (snake_case columns,
Drift type mapping, PRAGMA user_version = 5) so the file can either be read by
the import screen or dropped straight into %APPDATA%/YPOS/YPOS/.

Mapping
-------
category (leaf name from the site)  -> categories.name
name / barcode / price              -> products.name / barcode / price
image file on disk                  -> products.imagePath  (absolute path)
stockQty                            -> configurable, default 999999
"""

from __future__ import annotations

import argparse
import gzip
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

from collect_urls import DATA_DIR

PRODUCTS_FILE = DATA_DIR / "products.jsonl"
IMAGES_DIR = DATA_DIR / "product_images"
DB_FILE = DATA_DIR / "bookstore_pos.sqlite"
CATEGORIES_FILE = DATA_DIR / "categories.json"

SCHEMA_VERSION = 5

DDL = """
CREATE TABLE IF NOT EXISTS categories (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    description TEXT NULL,
    image_path TEXT NULL,
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE TABLE IF NOT EXISTS products (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER NULL REFERENCES categories (id),
    name TEXT NOT NULL,
    barcode TEXT NOT NULL UNIQUE,
    price REAL NOT NULL,
    cost REAL NOT NULL DEFAULT 0,
    stock_qty INTEGER NOT NULL DEFAULT 0,
    min_stock INTEGER NOT NULL DEFAULT 5,
    image_path TEXT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE TABLE IF NOT EXISTS product_barcodes (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES products (id) ON DELETE CASCADE,
    barcode TEXT NOT NULL UNIQUE,
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS settings (
    "key" TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
);

-- الجداول التالية فارغة في ملف الكتالوج، لكنها موجودة حتى يكون الملف
-- صالحاً للاستعمال المباشر كقاعدة التطبيق (Drift لا ينشئ الجداول الناقصة
-- إذا كان PRAGMA user_version مطابقاً).
CREATE TABLE IF NOT EXISTS invoices (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    invoice_number TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    cashier TEXT NOT NULL DEFAULT 'كاشير',
    total REAL NOT NULL,
    discount REAL NOT NULL DEFAULT 0,
    discount_type TEXT NOT NULL DEFAULT 'amount',
    amount_paid REAL NOT NULL,
    "change" REAL NOT NULL DEFAULT 0,
    notes TEXT NULL
);

CREATE TABLE IF NOT EXISTS invoice_items (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    invoice_id INTEGER NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products (id),
    qty INTEGER NOT NULL,
    unit_price REAL NOT NULL,
    line_total REAL NOT NULL,
    product_name TEXT NOT NULL DEFAULT '',
    unit_cost REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS purchase_orders (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    po_number TEXT NOT NULL UNIQUE,
    supplier_name TEXT NOT NULL DEFAULT '',
    supplier_phone TEXT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    total_cost REAL NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    notes TEXT NULL
);

CREATE TABLE IF NOT EXISTS purchase_order_items (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    po_id INTEGER NOT NULL REFERENCES purchase_orders (id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products (id),
    qty_ordered INTEGER NOT NULL,
    qty_received INTEGER NOT NULL DEFAULT 0,
    unit_cost REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS returns (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    return_number TEXT NOT NULL UNIQUE,
    invoice_id INTEGER NOT NULL REFERENCES invoices (id),
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    reason TEXT NOT NULL DEFAULT '',
    total REAL NOT NULL,
    cashier TEXT NOT NULL DEFAULT 'كاشير'
);

CREATE TABLE IF NOT EXISTS return_items (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    return_id INTEGER NOT NULL REFERENCES returns (id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products (id),
    qty INTEGER NOT NULL,
    unit_price REAL NOT NULL,
    unit_cost REAL NOT NULL DEFAULT 0,
    line_total REAL NOT NULL,
    product_name TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_products_name ON products (name);
CREATE INDEX IF NOT EXISTS idx_products_category ON products (category_id);
CREATE INDEX IF NOT EXISTS idx_product_barcodes_product ON product_barcodes (product_id);
"""

EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp")


def image_for(tid: int, images_dir: Path) -> str | None:
    for ext in EXTENSIONS:
        p = images_dir / f"{tid}{ext}"
        if p.exists():
            return str(p.resolve())
    return None


def load_records() -> list[dict]:
    recs: list[dict] = []
    if not PRODUCTS_FILE.exists():
        return recs
    with PRODUCTS_FILE.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(rec.get("template_id"), int) and rec.get("name"):
                recs.append(rec)
    # de-duplicate by template id (keep the last occurrence)
    by_id = {r["template_id"]: r for r in recs}
    return [by_id[k] for k in sorted(by_id)]


def build(db_path: Path, cost_ratio: float, stock_qty: int, images_dir: Path) -> dict:
    records = load_records()
    if db_path.exists():
        db_path.unlink()

    con = sqlite3.connect(db_path)
    con.execute("PRAGMA journal_mode = OFF")
    con.execute("PRAGMA synchronous = OFF")
    con.executescript(DDL)
    con.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")

    category_ids: dict[str, int] = {}
    barcode_seen: set[str] = set()
    stats: Counter[str] = Counter()
    now = 1_700_000_000  # fixed timestamp -> reproducible builds

    products: list[tuple] = []
    barcodes: list[tuple] = []

    for rec in records:
        tid = rec["template_id"]
        stats["records"] += 1

        cat = (rec.get("category") or "").strip()
        if cat:
            cid = category_ids.get(cat)
            if cid is None:
                cur = con.execute(
                    "INSERT OR IGNORE INTO categories (name, created_at) VALUES (?, ?)",
                    (cat, now),
                )
                if cur.lastrowid:
                    cid = cur.lastrowid
                else:
                    cid = con.execute(
                        "SELECT id FROM categories WHERE name = ?", (cat,)
                    ).fetchone()[0]
                category_ids[cat] = cid
        else:
            cid = None
            stats["no_category"] += 1

        price = rec.get("price")
        if price is None:
            price = 0.0
            stats["no_price"] += 1

        barcode = str(rec.get("barcode") or "").strip()
        if not barcode:
            barcode = f"ALM{tid}"
            stats["synthetic_barcode"] += 1
        if barcode in barcode_seen:
            barcode = f"ALM{tid}"
            stats["duplicate_barcode"] += 1
            while barcode in barcode_seen:
                barcode += "X"
        barcode_seen.add(barcode)

        img = image_for(tid, images_dir)
        if img:
            stats["with_image"] += 1

        products.append(
            (
                cid,
                rec["name"],
                barcode,
                float(price),
                round(float(price) * cost_ratio, 2),
                stock_qty,
                5,
                img,
                1,
                0,
                now,
            )
        )
        barcodes.append((barcode,))

    con.executemany(
        "INSERT INTO products (category_id, name, barcode, price, cost, stock_qty,"
        " min_stock, image_path, is_active, is_favorite, updated_at)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        products,
    )
    # product_barcodes.product_id must reference the freshly inserted rows
    con.execute(
        "INSERT INTO product_barcodes (product_id, barcode, sort_order) "
        "SELECT id, barcode, 0 FROM products"
    )

    con.commit()
    n_products = con.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    n_cats = con.execute("SELECT COUNT(*) FROM categories").fetchone()[0]
    n_bc = con.execute("SELECT COUNT(*) FROM product_barcodes").fetchone()[0]
    con.close()

    CATEGORIES_FILE.write_text(
        json.dumps(
            [{"id": v, "name": k} for k, v in sorted(category_ids.items(), key=lambda kv: kv[1])],
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    return {
        "products": n_products,
        "categories": n_cats,
        "product_barcodes": n_bc,
        **stats,
    }


def _sql_literal(value: object) -> str:
    """SQLite literal. Backslashes are literal in SQL, so Windows paths survive."""
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def build_sql_dump(db_path: Path, out: Path) -> None:
    """A .sql.gz dump (schema + inserts) for anyone who wants plain SQL."""
    with gzip.open(out, "wt", encoding="utf-8", newline="\n") as fh:
        fh.write("PRAGMA foreign_keys=OFF;\nBEGIN TRANSACTION;\n")
        con = sqlite3.connect(db_path)
        for (name, sql) in con.execute(
            "SELECT name, sql FROM sqlite_master "
            "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'"
        ):
            fh.write(f"{sql};\n")
        for table in ("categories", "products", "product_barcodes"):
            cols = [r[1] for r in con.execute(f"PRAGMA table_info({table})")]
            cur = con.execute(f"SELECT * FROM {table}")
            for row in cur.fetchall():
                vals = ",".join(_sql_literal(v) for v in row)
                fh.write(f"INSERT INTO {table} ({','.join(cols)}) VALUES ({vals});\n")
        con.close()
        fh.write("COMMIT;\n")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--db", type=Path, default=DB_FILE)
    p.add_argument("--images", type=Path, default=IMAGES_DIR)
    p.add_argument("--cost-ratio", type=float, default=0.0,
                   help="cost = price * ratio (default 0 = unknown)")
    p.add_argument("--stock", type=int, default=999999)
    p.add_argument("--sql", action="store_true", help="also write bookstore_pos.sql.gz")
    a = p.parse_args()

    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    stats = build(a.db, a.cost_ratio, a.stock, a.images)
    print(f"database : {a.db}")
    for k, v in stats.items():
        print(f"  {k:20s} {v}")
    if a.sql:
        out = a.db.with_suffix(".sql.gz")
        build_sql_dump(a.db, out)
        print(f"sql dump : {out} ({out.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
