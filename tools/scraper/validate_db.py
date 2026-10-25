"""Validate the generated SQLite: schema integrity + a Drift-compatibility check."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

DB = Path(__file__).resolve().parent.parent.parent / "data" / "bookstore_pos.sqlite"

EXPECTED_TABLES = {
    "categories", "products", "invoices", "invoice_items",
    "purchase_orders", "purchase_order_items", "settings",
    "returns", "return_items", "product_barcodes",
}

# column name -> expected SQLite type affinity, straight from tables.dart
EXPECTED_COLUMNS = {
    "categories": {
        "id": "INTEGER", "name": "TEXT", "description": "TEXT",
        "image_path": "TEXT", "created_at": "INTEGER",
    },
    "products": {
        "id": "INTEGER", "category_id": "INTEGER", "name": "TEXT",
        "barcode": "TEXT", "price": "REAL", "cost": "REAL",
        "stock_qty": "INTEGER", "min_stock": "INTEGER", "image_path": "TEXT",
        "is_active": "INTEGER", "is_favorite": "INTEGER", "updated_at": "INTEGER",
    },
    "product_barcodes": {
        "id": "INTEGER", "product_id": "INTEGER", "barcode": "TEXT",
        "sort_order": "INTEGER",
    },
}


def main() -> int:
    if not DB.exists():
        print(f"missing {DB}")
        return 1
    con = sqlite3.connect(DB)
    ok = True

    version = con.execute("PRAGMA user_version").fetchone()[0]
    print(f"user_version      : {version} (Drift schemaVersion is 5)")
    ok &= version == 5

    integrity = con.execute("PRAGMA integrity_check").fetchone()[0]
    print(f"integrity_check   : {integrity}")
    ok &= integrity == "ok"

    fk = con.execute("PRAGMA foreign_key_check").fetchall()
    print(f"foreign_key_check : {fk or 'clean'}")
    ok &= not fk

    tables = {
        r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    missing = EXPECTED_TABLES - tables
    print(f"tables            : {len(tables)} present, missing={missing or 'none'}")
    ok &= not missing

    for table, cols in EXPECTED_COLUMNS.items():
        actual = {r[1]: r[2] for r in con.execute(f"PRAGMA table_info({table})")}
        for col, typ in cols.items():
            got = actual.get(col)
            if got is None:
                print(f"  !! {table}.{col} MISSING")
                ok = False
            elif got.upper() != typ:
                print(f"  !! {table}.{col} is {got}, expected {typ}")
                ok = False
    print("column types      :", "OK" if ok else "MISMATCH")

    n_prod = con.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    n_cat = con.execute("SELECT COUNT(*) FROM categories").fetchone()[0]
    n_bc = con.execute("SELECT COUNT(*) FROM product_barcodes").fetchone()[0]
    n_img = con.execute(
        "SELECT COUNT(*) FROM products WHERE image_path IS NOT NULL"
    ).fetchone()[0]
    print(f"rows              : products={n_prod} categories={n_cat} "
          f"barcodes={n_bc} with_image={n_img}")

    dupes = con.execute(
        "SELECT barcode, COUNT(*) c FROM products GROUP BY barcode HAVING c > 1"
    ).fetchall()
    print(f"duplicate barcodes: {dupes or 'none'}")
    ok &= not dupes

    orphans = con.execute(
        "SELECT COUNT(*) FROM product_barcodes pb "
        "LEFT JOIN products p ON p.id = pb.product_id WHERE p.id IS NULL"
    ).fetchone()[0]
    print(f"orphan barcodes   : {orphans}")
    ok &= orphans == 0

    print("\nsample rows:")
    for row in con.execute(
        "SELECT id, name, barcode, price, stock_qty, category_id FROM products LIMIT 4"
    ):
        print("  ", row)

    con.close()
    print("\nRESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
