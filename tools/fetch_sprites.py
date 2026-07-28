#!/usr/bin/env python3
"""Download the PokeAPI sprite set the game draws with.

Takes the front-default sprites from github.com/PokeAPI/sprites — the classic
96x96 pixel art, which is both the iconic look and small enough to commit: the
whole dex is about 2 MB, against ~130 MB for the 512x512 HOME renders.

The URLs come out of the API cache written by fetch_pokeapi.py where possible,
so the two stay in step; otherwise they are constructed from the dex number.

    python3 tools/fetch_sprites.py [--out assets/pokemon] [--workers N]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BASE = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
MAX_DEX = 1025
UA = "claude-code-sts-pokemon-import/1.0 (github.com/local; contact: repo owner)"

_lock = threading.Lock()
_done = 0
_missing: list = []


def sprite_url(cache: str, dex: int) -> str:
    """Prefer the URL the API itself gave us; fall back to the canonical path."""
    path = os.path.join(cache, "pokemon", f"{dex}.json")
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                url = (json.load(fh).get("sprites") or {}).get("front_default")
            if url:
                return url
        except (json.JSONDecodeError, OSError):
            pass
    return f"{BASE}/{dex}.png"


def grab(cache: str, out_dir: str, dex: int, attempts: int = 4) -> None:
    global _done
    dest = os.path.join(out_dir, f"{dex}.png")
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        with _lock:
            _done += 1
        return

    url = sprite_url(cache, dex)
    delay = 1.0
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as resp:
                body = resp.read()
            if not body.startswith(b"\x89PNG"):
                raise ValueError("not a PNG")
            tmp = dest + ".part"
            with open(tmp, "wb") as fh:
                fh.write(body)
            os.replace(tmp, dest)
            break
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                with _lock:
                    _missing.append(dex)
                break
            if attempt == attempts - 1:
                with _lock:
                    _missing.append(dex)
        except (urllib.error.URLError, TimeoutError, ValueError, OSError):
            if attempt == attempts - 1:
                with _lock:
                    _missing.append(dex)
        time.sleep(delay)
        delay *= 2

    with _lock:
        _done += 1
        if _done % 100 == 0 or _done == MAX_DEX:
            print(f"  {_done}/{MAX_DEX}", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=".pokecache")
    ap.add_argument("--out", default="assets/pokemon")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=MAX_DEX)
    args = ap.parse_args()

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    print(f"sprites -> {out_dir}")

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for dex in range(1, args.limit + 1):
            pool.submit(grab, os.path.abspath(args.cache), out_dir, dex)

    have = len([f for f in os.listdir(out_dir) if f.endswith(".png")])
    total = sum(os.path.getsize(os.path.join(out_dir, f))
                for f in os.listdir(out_dir) if f.endswith(".png"))
    print(f"done: {have} sprites, {total / 1024 / 1024:.1f} MiB")
    if _missing:
        print(f"missing {len(_missing)}: {sorted(_missing)[:20]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
