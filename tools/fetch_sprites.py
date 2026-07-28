#!/usr/bin/env python3
"""Download Pokemon sprites from the PokeAPI sprite repository.

    python3 tools/fetch_sprites.py [--out DIR] [--limit N] [--workers N]

Pulls sprites/pokemon/<id>.png from github.com/PokeAPI/sprites — the 96x96
pixel-art front sprites. They are chosen over the 512x512 HOME renders and the
official artwork on size alone: the whole dex costs about 1.5 MB this way
against 80 MB, and pixel art scales up cleanly with nearest-neighbour
filtering, which is what the game does.

Already-downloaded files are skipped, so re-running is free.
"""

from __future__ import annotations

import argparse
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

RAW = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
MAX_DEX = 1025
UA = "claude-code-sts-pokemon-import/1.0"

_lock = threading.Lock()
_done = 0
_missing: list[int] = []


def fetch_one(dex: int, out_dir: str, attempts: int = 4) -> bool:
    global _done
    path = os.path.join(out_dir, f"{dex}.png")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        with _lock:
            _done += 1
        return True

    delay = 1.0
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(f"{RAW}/{dex}.png", headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as resp:
                blob = resp.read()
            tmp = path + ".part"
            with open(tmp, "wb") as fh:
                fh.write(blob)
            os.replace(tmp, path)
            with _lock:
                _done += 1
                if _done % 100 == 0:
                    print(f"  {_done} sprites", flush=True)
            return True
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                with _lock:
                    _missing.append(dex)
                return False
            if attempt == attempts - 1:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == attempts - 1:
                raise
        time.sleep(delay)
        delay *= 2
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/sprites/pokemon")
    ap.add_argument("--limit", type=int, default=MAX_DEX)
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    print(f"sprites -> {out_dir}")

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(lambda d: fetch_one(d, out_dir), range(1, args.limit + 1)))

    total = sum(os.path.getsize(os.path.join(out_dir, f))
                for f in os.listdir(out_dir) if f.endswith(".png"))
    have = len([f for f in os.listdir(out_dir) if f.endswith(".png")])
    print(f"done: {have} sprites, {total / 1024 / 1024:.1f} MiB")
    if _missing:
        print(f"missing from the repo: {sorted(_missing)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
