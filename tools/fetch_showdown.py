#!/usr/bin/env python3
"""Mirror the Pokemon Showdown data tables that carry the CAP project.

CAP (Create-A-Pokemon) species exist in no game and so in no PokeAPI response.
Smogon's simulator is their reference implementation: pokedex.ts holds the 99
species, moves.ts the handful of moves invented for them, learnsets.ts what each
one knows, and text/moves.ts the English descriptions.

Like fetch_pokeapi.py this only mirrors; build_data.py does the converting.

    python3 tools/fetch_showdown.py [--cache DIR] [--force]
"""

from __future__ import annotations

import argparse
import os
import sys
import urllib.error
import urllib.request

RAW = "https://raw.githubusercontent.com/smogon/pokemon-showdown/master"
UA = "claude-code-sts-pokemon-import/1.0 (github.com/local; contact: repo owner)"

## Repo path -> filename under {cache}/showdown/.
FILES = {
    "data/pokedex.ts": "pokedex.ts",
    "data/moves.ts": "moves.ts",
    "data/learnsets.ts": "learnsets.ts",
    "data/text/moves.ts": "moves-text.ts",
}


def download(path: str, dest: str, attempts: int = 4) -> int:
    url = f"{RAW}/{path}"
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = resp.read()
            tmp = dest + ".part"
            with open(tmp, "wb") as fh:
                fh.write(body)
            os.replace(tmp, dest)
            return len(body)
        except (urllib.error.URLError, TimeoutError, OSError):
            if attempt == attempts - 1:
                raise
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.environ.get("POKE_CACHE", ".pokecache"))
    ap.add_argument("--force", action="store_true",
                    help="re-download files that are already cached")
    args = ap.parse_args()

    out_dir = os.path.join(os.path.abspath(args.cache), "showdown")
    os.makedirs(out_dir, exist_ok=True)
    print(f"showdown -> {out_dir}")

    for path, name in FILES.items():
        dest = os.path.join(out_dir, name)
        if os.path.exists(dest) and not args.force:
            print(f"  {name}  cached")
            continue
        size = download(path, dest)
        print(f"  {name}  {size / 1024:.0f} KiB")
    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
