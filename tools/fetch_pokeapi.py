#!/usr/bin/env python3
"""Download the raw PokeAPI payloads this project needs into a local cache.

PokeAPI asks callers to cache aggressively, so every response is written to
CACHE_DIR and re-used on later runs; deleting a file is how you force a refetch.
This step only mirrors the API. Turning the cache into game data is build_data.py.

    python3 tools/fetch_pokeapi.py [--cache DIR] [--workers N] [--limit N]
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

API = "https://pokeapi.co/api/v2"
# The National Dex through Gen 9. Ids above this are alternate forms (megas,
# regional variants, totems), which would duplicate species we already have.
MAX_DEX = 1025
UA = "claude-code-sts-pokemon-import/1.0 (github.com/local; contact: repo owner)"

_print_lock = threading.Lock()
_done = 0
_total = 0


def log(msg: str) -> None:
    with _print_lock:
        print(msg, flush=True)


def tick(what: str) -> None:
    global _done
    with _print_lock:
        _done += 1
        if _done % 100 == 0 or _done == _total:
            print(f"  {_done}/{_total} {what}", flush=True)


def cache_path(cache_dir: str, kind: str, key) -> str:
    return os.path.join(cache_dir, kind, f"{key}.json")


def fetch(cache_dir: str, kind: str, key, attempts: int = 4):
    """GET /{kind}/{key}, via the on-disk cache. Returns the parsed body."""
    path = cache_path(cache_dir, kind, key)
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                return json.load(fh)
        except (json.JSONDecodeError, OSError):
            os.remove(path)  # truncated by an interrupted run; refetch it

    url = f"{API}/{kind}/{key}/" if kind else f"{API}/{key}"
    delay = 1.0
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp = path + ".part"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(body, fh)
            os.replace(tmp, path)  # so a killed run never leaves half a file
            return body
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            if attempt == attempts - 1:
                raise
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            if attempt == attempts - 1:
                raise
        time.sleep(delay)
        delay *= 2
    return None


def fetch_many(cache_dir: str, kind: str, keys, workers: int) -> dict:
    global _done, _total
    _done, _total = 0, len(keys)
    out = {}
    log(f"{kind}: {len(keys)} to fetch")
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(fetch, cache_dir, kind, k): k for k in keys}
        for fut in futures:
            pass
        for fut, key in futures.items():
            body = fut.result()
            if body is not None:
                out[key] = body
            tick(kind)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.environ.get("POKE_CACHE", ".pokecache"))
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=MAX_DEX,
                    help="highest dex number to fetch (for quick test runs)")
    args = ap.parse_args()

    cache = os.path.abspath(args.cache)
    os.makedirs(cache, exist_ok=True)
    log(f"cache: {cache}")

    # 1. Type chart. Small, and every damage calculation depends on it.
    types_index = fetch(cache, "", "type?limit=100")
    type_names = [t["name"] for t in types_index["results"]]
    fetch_many(cache, "type", type_names, args.workers)

    # 2. Every species' default form: stats, types and its learnset.
    dex = list(range(1, args.limit + 1))
    mons = fetch_many(cache, "pokemon", dex, args.workers)

    # 3. Species records carry the legendary/mythical flags and flavour text
    #    that the encounter tiering and card text use.
    fetch_many(cache, "pokemon-species", dex, args.workers)

    # 4. Only the moves that something can actually learn.
    # Struggle appears in no learnset but is every Pokemon's last resort.
    move_names = {"struggle"}
    for body in mons.values():
        for entry in body.get("moves", []):
            move_names.add(entry["move"]["name"])
    fetch_many(cache, "move", sorted(move_names), args.workers)

    # 5. Evolution chains, for the levelling and evolution system. Several
    #    species share one chain, so collect the distinct ids first.
    chain_ids = set()
    for dex in dex:
        body = fetch(cache, "pokemon-species", dex)
        if not body:
            continue
        url = (body.get("evolution_chain") or {}).get("url")
        if url:
            chain_ids.add(int(url.rstrip("/").rsplit("/", 1)[-1]))
    fetch_many(cache, "evolution-chain", sorted(chain_ids), args.workers)

    # 6. Growth rates give the XP curve for each level.
    rates = fetch(cache, "", "growth-rate?limit=100")
    fetch_many(cache, "growth-rate", [r["name"] for r in rates["results"]], args.workers)

    # 7. Ailments and move-categories, so the effect mapper can enumerate them.
    fetch(cache, "", "move-ailment?limit=100")
    fetch(cache, "", "move-category?limit=100")

    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
