#!/usr/bin/env python3
"""Download the PokeAPI sprite set into assets/sprites/pokemon/.

Source: https://github.com/PokeAPI/sprites — the front-default sprites, which are
small (~1.3 MB for the whole dex) and consistent across all nine generations.
The player's own Pokemon is drawn from the same sprite mirrored horizontally, so
it faces the enemy; see SpriteCache.gd.

    python3 tools/fetch_sprites.py [--out DIR] [--workers N] [--limit N]
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

BASE = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
MAX_DEX = 1025
UA = "claude-code-sts-pokemon-import/1.0 (github.com/local; contact: repo owner)"

_lock = threading.Lock()
_done = 0
_failed: list[int] = []


def fetch_one(out_dir: str, dex: int, attempts: int = 4) -> bool:
    global _done
    path = os.path.join(out_dir, f"{dex}.png")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        with _lock:
            _done += 1
        return True

    delay = 1.0
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(f"{BASE}/{dex}.png", headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=45) as resp:
                body = resp.read()
            if not body:
                raise ValueError("empty body")
            tmp = path + ".part"
            with open(tmp, "wb") as fh:
                fh.write(body)
            os.replace(tmp, path)
            with _lock:
                _done += 1
                if _done % 100 == 0:
                    print(f"  {_done} sprites", flush=True)
            return True
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                break
            if attempt == attempts - 1:
                break
        except Exception:
            if attempt == attempts - 1:
                break
        time.sleep(delay)
        delay *= 2
    with _lock:
        _failed.append(dex)
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/sprites/pokemon")
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--limit", type=int, default=MAX_DEX)
    args = ap.parse_args()

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    print(f"downloading {args.limit} sprites -> {out_dir}")

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(lambda d: fetch_one(out_dir, d), range(1, args.limit + 1)))

    total = sum(os.path.getsize(os.path.join(out_dir, f))
                for f in os.listdir(out_dir) if f.endswith(".png"))
    print(f"done: {_done} sprites, {total / 1024:.0f} KiB")
    if _failed:
        print(f"missing {len(_failed)}: {sorted(_failed)[:20]}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
