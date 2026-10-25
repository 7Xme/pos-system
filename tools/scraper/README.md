# almouggar.com → YPOS catalog importer

Scrapes the **entire** almouggar.com catalogue (≈99 430 products) and turns it into
a ready-to-import SQLite database plus local product images.

Everything ends up in `data/` (git-ignored):

```
data/
├─ product_urls.txt          99 430 canonical product URLs (from the sitemaps)
├─ products.jsonl            one JSON record per product (the raw scrape)
├─ categories.json           category list
├─ bookstore_pos.sqlite      Drift-compatible DB (products + categories + barcodes)
├─ bookstore_pos.sql.gz      same data as a plain SQL dump
├─ product_images/           <template_id>.jpg  (512 px, ~4 GB total)
└─ logs/                     crawler stdout/stderr
```

## Requirements

Python 3.10+ with `aiohttp` (everything else is stdlib):

```powershell
python -m pip install aiohttp
```

## Quick start

```powershell
# 1) crawl everything (resumable, safe to Ctrl+C and re-run)
powershell -File tools\scraper\run_full.ps1

# 2) build the database once the crawl is done
python tools\scraper\build_db.py --sql
```

Then in the app: **استيراد** (Import) → pick the `data` folder.

### Hands-off completion

`finalize.ps1` waits for the page crawl, retries failed pages/images, rebuilds the
DB, validates it and only then writes `data/.finalized`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\scraper\finalize.ps1
```

### Fast parallel completion (multiple workers)

Split the remaining work across several workers. The split is by
`template_id % shards`, so workers never fetch the same product/image:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\scraper\finalize_parallel.ps1 -Shards 3
```

It launches `Shards` copies of `shard_worker.ps1` (each doing rounds of
pages → images for its own slice), waits for all of them, then rebuilds and
validates the DB and writes `data/.finalized`. Worker logs go to
`data/logs/shard<N>.log`, orchestration log to `data/logs/finalize_parallel.log`.

Check progress at any time (safe while the crawlers run):

```powershell
python tools\scraper\status.py          # human-readable
python tools\scraper\status.py --json   # for scripts
```


## Phases

| Command | What it does |
|---|---|
| `python scrape.py urls` | read the 3 sitemaps → `product_urls.txt` (no network beyond sitemaps) |
| `python scrape.py pages` | fetch + parse every product page → `products.jsonl` |
| `python scrape.py images` | download every product image → `product_images/` |
| `python build_db.py` | build `bookstore_pos.sqlite` (+ `--sql` for a text dump) |

Both network phases are **resumable**: they skip whatever is already on disk, so
an interrupted run loses nothing.

Useful flags:

```powershell
python scrape.py pages  --concurrency 64 --limit 500   # pilot
python scrape.py images --concurrency 24 --follow      # keeps re-scanning until pages finish
python build_db.py --stock 999999 --cost-ratio 0.0 --sql

# sharding: run M workers for this phase, worker N takes template_id % M == N
python scrape.py pages  --shard 0 --shards 3
python scrape.py images --shard 0 --shards 3
```

## What is extracted

Per product page (`parse_product.py`):

| Field | Source |
|---|---|
| **title** | `data-product-tracking-info.item_name` → `<h1 itemprop="name">` |
| **price** | `data-product-tracking-info.price` → `itemprop="price"` |
| **barcode** | `data-product-tracking-info.item_id` (ISBN for books, EAN otherwise) |
| **image** | `/web/image/product.template/<id>/image_512` |
| category | `data-product-tracking-info.item_category` |
| brand / author | `itemprop="brand"` / `itemprop="author"` |
| extra | ISBN, Langue, Format, Pages, Dimensions, Poids (in `products.jsonl`) |

## Notes & caveats

* **robots.txt** — `/shop/<product>` pages are allowed and that is all we fetch.
  We deliberately avoid the paths robots.txt disallows (`/autocomplete`,
  `/shop/*?page=`, `/my/`, …) and we request canonical URLs with no query string.
* **Barcodes are the ISBN** for books. Roughly 3 % of products have none on the
  site; those get a deterministic synthetic barcode `ALM<template_id>` so the
  UNIQUE constraint holds.
* **`cost`** (purchase price) is not published by the site, so it defaults to `0`.
  Pass `--cost-ratio 0.7` to seed it as a fraction of the selling price instead.
* **`stockQty`** defaults to `999999` because the POS refuses to sell an item at
  stock 0. Set real quantities in the app.
* The crawl rate is limited by the server (~5–14 req/s observed). For the initial
  full run the server is the bottleneck, so adding workers gives little. For
  **retries / leftover work**, sharding across several `--shards` workers is much
  faster in practice (observed ~5× on the image phase). Push concurrency too far
  and the server answers `HTTP 503` — those pages are simply retried later.

## Files

| File | Role |
|---|---|
| `collect_urls.py` | sitemap → product URL list |
| `parse_product.py` | product-page HTML → dict (regex based, ~2.6 ms/page) |
| `scrape.py` | async crawler (pages + images), resumable |
| `build_db.py` | JSONL + images → SQLite (Drift schema, `user_version = 5`) |
| `run_full.ps1` | starts both crawlers detached, logging to `data/logs/` |
| `status.py` | progress summary (URLs/products/images/errors) |
| `finalize.ps1` | waits, retries failures, rebuilds + validates, writes `.finalized` |
| `shard_worker.ps1` | one parallel worker: rounds of pages → images for its own slice |
| `finalize_parallel.ps1` | launches N shard workers, waits, rebuilds + validates the DB |
| `analyze_sitemaps.py`, `bench*.py`, `test_parse.py` | diagnostics |

## Windows build notes

Two manual engine artifacts are easy to miss when the Flutter cache was populated
by hand (both live under
`C:\flutter\bin\cache\artifacts\engine\windows-x64\`):

* `const_finder.dart.snapshot` and `font-subset.exe` come from
  `<engine-rev>/windows-x64/font-subset.zip` — without them a release build fails
  inside `flutter_assemble` with `IconTreeShakerException`.
* `vm_isolate_snapshot.bin` is legitimately 0 bytes in the upstream
  `windows-x64/artifacts.zip`; do not replace it.

The app pins `sqlite3_flutter_libs: >=0.5.0 <0.6.0`: `0.6.0+eol` is an empty shim
for `package:sqlite3` 3.x, while `drift` 2.x still needs the 0.5.x build that
bundles `sqlite3.dll` next to `YPOS.exe`.

