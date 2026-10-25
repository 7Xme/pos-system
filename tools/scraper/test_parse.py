"""Quick parser smoke test against a handful of live product pages."""
from __future__ import annotations

import json
import sys

import requests

from parse_product import parse_product

URLS = [
    "https://almouggar.com/shop/416256",
    "https://almouggar.com/shop/o225-marqueur-double-pointe-henne-537638",
    "https://almouggar.com/shop/636847",
    "https://almouggar.com/shop/12-crayons-de-couleur-521831",
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
    "Accept-Language": "fr-FR,fr;q=0.9,ar;q=0.8",
}


def main() -> None:
    session = requests.Session()
    session.headers.update(HEADERS)
    for url in URLS:
        r = session.get(url, timeout=45)
        d = parse_product(url, r.text)
        print("=" * 90)
        print("URL      :", url, "->", r.status_code)
        for k, v in d.items():
            if k == "characteristics":
                continue
            print(f"  {k:14s}: {v!r}")
        print("  chars    :", json.dumps(d["characteristics"], ensure_ascii=False))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
