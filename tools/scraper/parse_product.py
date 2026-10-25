"""HTML parsing for almouggar.com product pages (Odoo 18 / website_sale).

Extraction is regex based: the templates are stable and it keeps the crawl fast
(no full DOM tree construction for ~100k pages).

Every field we need is available on the product page:
  * data-product-tracking-info (JSON) -> barcode (item_id), name, category, price
  * itemprop="isbn" / "name" / "price" / "image"
  * hidden inputs: product_id, product_template_id, product_category_id
  * itemprop="author" / "brand"
  * the "alm-product-characteristics" block (ISBN, Langue, Format, Pages, ...)
"""

from __future__ import annotations

import html as html_lib
import json
import re
from typing import Any

BASE = "https://almouggar.com"

_RE_TRACKING = re.compile(r'data-product-tracking-info="([^"]*)"')
_RE_H1_NAME = re.compile(r'<h1[^>]*itemprop="name"[^>]*>(.*?)</h1>', re.S)
_RE_OG_TITLE = re.compile(r'<meta\s+property="og:title"\s+content="([^"]*)"')
_RE_OG_IMAGE = re.compile(r'<meta\s+property="og:image"\s+content="([^"]*)"')
_RE_META = re.compile(r'<meta\s+itemprop="([^"]+)"\s+content="([^"]*)"')
_RE_PRICE = re.compile(r'itemprop="price"[^>]*>\s*([0-9]+(?:[.,][0-9]+)?)')
_RE_CURRENCY = re.compile(r'itemprop="priceCurrency"[^>]*>\s*([A-Z]{3})')
_RE_TEMPLATE_ID = re.compile(r'name="product_template_id"\s+value="(\d+)"')
_RE_VARIANT_ID = re.compile(r'name="product_id"\s+value="(\d+)"')
_RE_CATEGORY_ID = re.compile(r'name="product_category_id"\s+value="(\d+)"')
_RE_IMAGE_SPAN = re.compile(r'itemprop="image"\s+style="[^"]*"\s*>\s*([^<]+?)\s*<')
_RE_BRAND = re.compile(r'itemprop="brand"[^>]*>(.*?)</a>', re.S)
_RE_AUTHOR = re.compile(r'itemprop="author"[^>]*>(.*?)</a>', re.S)
_RE_STOCK = re.compile(r'alm-stock-status-([a-zA-Z_]+)')
_RE_IMAGE_URL = re.compile(r'/web/image/product\.template/(\d+)/image_(\d+)')
_RE_CHARACTERISTICS = re.compile(
    r'alm-product-characteristics.*?</section>', re.S
)
_RE_CHAR_PAIR = re.compile(
    r'<div class="small text-muted">(.*?)</div>\s*<div class="fw-semibold">(.*?)</div>',
    re.S,
)
_RE_TAG = re.compile(r"<[^>]+>")
_RE_WS = re.compile(r"\s+")
_RE_TRAILING_ID = re.compile(r"/shop/(?:.*-)?(\d+)/?$")


def _clean(text: str | None) -> str:
    if not text:
        return ""
    text = _RE_TAG.sub("", text)
    text = html_lib.unescape(text)
    return _RE_WS.sub(" ", text).strip()


def _to_float(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).strip().replace("\xa0", "")
    if not s:
        return None
    s = s.replace(" ", "").replace(",", ".")
    # 1.234.56 -> keep only the last dot as decimal separator
    if s.count(".") > 1:
        head, _, tail = s.rpartition(".")
        s = head.replace(".", "") + "." + tail
    try:
        return float(s)
    except ValueError:
        return None


def _unescape_json(raw: str) -> dict[str, Any]:
    """The tracking blob is HTML-escaped JSON (&#34; etc.)."""
    try:
        return json.loads(html_lib.unescape(raw))
    except Exception:
        return {}


def extract_template_id(url: str, page: str) -> int | None:
    m = _RE_TEMPLATE_ID.search(page)
    if m:
        return int(m.group(1))
    m = _RE_IMAGE_URL.search(page)
    if m:
        return int(m.group(1))
    m = _RE_TRAILING_ID.search(url.split("?")[0])
    if m:
        return int(m.group(1))
    return None


def parse_product(url: str, page: str) -> dict[str, Any]:
    """Turn one product page into a flat dict. Missing fields are None."""
    tracking = _RE_TRACKING.search(page)
    track = _unescape_json(tracking.group(1)) if tracking else {}

    metas = {k: v for k, v in _RE_META.findall(page)}

    template_id = extract_template_id(url, page)

    name = _clean(track.get("item_name"))
    if not name:
        m = _RE_H1_NAME.search(page)
        if m:
            name = _clean(m.group(1))
    if not name:
        m = _RE_OG_TITLE.search(page)
        if m:
            name = _clean(m.group(1))

    barcode = str(track.get("item_id") or "").strip()
    if not barcode:
        barcode = _clean(metas.get("isbn"))

    price = _to_float(track.get("price"))
    if price is None:
        m = _RE_PRICE.search(page)
        if m:
            price = _to_float(m.group(1))

    currency = track.get("currency")
    if not currency:
        m = _RE_CURRENCY.search(page)
        currency = m.group(1) if m else "MAD"

    # image: prefer the template render so the size can be chosen freely
    image_url: str | None = None
    if template_id:
        image_url = f"{BASE}/web/image/product.template/{template_id}/image_512"
    else:
        m = _RE_IMAGE_SPAN.search(page) or _RE_OG_IMAGE.search(page)
        if m:
            image_url = m.group(1).strip()

    m = _RE_AUTHOR.search(page)
    author = _clean(m.group(1)) if m else ""
    m = _RE_BRAND.search(page)
    brand = _clean(m.group(1)) if m else ""

    stock_status = "out_of_stock" if "out_of_stock" in page else "in_stock"

    m = _RE_VARIANT_ID.search(page)
    variant_id = int(m.group(1)) if m else None
    m = _RE_CATEGORY_ID.search(page)
    category_id = int(m.group(1)) if m else None

    characteristics: dict[str, str] = {}
    at = page.find("alm-product-characteristics")
    if at != -1:
        section = page[at : at + 6000]
        end = section.find("</section>")
        if end != -1:
            section = section[:end]
        for label, value in _RE_CHAR_PAIR.findall(section):
            label, value = _clean(label), _clean(value)
            if label:
                characteristics[label] = value

    return {
        "url": url,
        "template_id": template_id,
        "variant_id": variant_id,
        "category_id": category_id,
        "name": name,
        "barcode": barcode,
        "price": price,
        "currency": currency,
        "category": _clean(track.get("item_category")) or None,
        "author": author or None,
        "brand": brand or None,
        "image_url": image_url,
        "in_stock": stock_status == "in_stock",
        "stock_raw": stock_status or None,
        "isbn": characteristics.get("ISBN") or _clean(metas.get("isbn")) or None,
        "language": characteristics.get("Langue") or None,
        "format": characteristics.get("Format") or None,
        "pages": characteristics.get("Pages") or None,
        "dimensions": characteristics.get("Dimensions") or None,
        "weight": characteristics.get("Poids") or None,
        "characteristics": characteristics,
    }
