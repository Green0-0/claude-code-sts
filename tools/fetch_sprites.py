#!/usr/bin/env python3
"""Download Pokemon sprites from the PokeAPI sprite repository.

Every sprite URL is already in the .pokecache payloads fetched by
fetch_pokeapi.py, so this reads them from there rather than guessing paths.

We take the **HOME** renders (`sprites/pokemon/other/home/{id}.png`) because they
are the soft, rounded, consistently-lit set — the closest thing the repository
has to a single kawaii art style, and the only one besides the classic front
sprites with all 1025 species covered. They ship at 512px, which is far more
than a 190px enemy panel needs, so each is trimmed to its content and downscaled
on the way in; that turns ~70 MB of source art into ~10 MB in the repo.

    python3 tools/fetch_sprites.py [--cache DIR] [--out DIR] [--size N]
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import threading
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

MAX_DEX = 1025
UA = "claude-code-sts-pokemon-import/1.0 (github.com/local; contact: repo owner)"

_lock = threading.Lock()
_done = 0
_failed: list = []


## The sprite sets worth choosing between, in the order each falls back.
##   home     soft rounded 512px renders — the kawaii set, all 1025 covered
##   front    the classic ~96px game sprite, pixel-art, all 1025 covered
##   artwork  full official artwork, painterly rather than cute
##   showdown animated GIFs; only 1004 species, and Godot needs an importer
STYLES = {
    "home": [("other", "home", "front_default"), ("front_default",)],
    "front": [("front_default",), ("other", "home", "front_default")],
    "artwork": [("other", "official-artwork", "front_default"), ("front_default",)],
    "showdown": [("other", "showdown", "front_default"), ("front_default",)],
}


def sprite_url(body: dict, style: str) -> str | None:
    sprites = body.get("sprites") or {}
    for path in STYLES.get(style, STYLES["home"]):
        node = sprites
        for key in path:
            if not isinstance(node, dict):
                node = None
                break
            node = node.get(key)
        if isinstance(node, str) and node:
            return node
    return None


def process(raw: bytes, size: int, colors: int) -> bytes:
    """Trim the transparent margin, fit to a square, and re-encode."""
    img = Image.open(io.BytesIO(raw)).convert("RGBA")
    bbox = img.getbbox()          # drops the large empty border HOME art carries
    if bbox:
        img = img.crop(bbox)
    img.thumbnail((size, size), Image.LANCZOS)
    # Centre it on a transparent square so every sprite shares one anchor and
    # the game can scale them all identically.
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(img, ((size - img.width) // 2, (size - img.height) // 2))
    if colors > 0:
        # These renders are smooth gradients over few hues, so a 128-colour
        # palette is indistinguishable at this size and halves the repo cost.
        canvas = canvas.quantize(colors=colors, method=Image.FASTOCTREE).convert("RGBA")
    out = io.BytesIO()
    canvas.save(out, "PNG", optimize=True)
    return out.getvalue()


def fetch_one(dex: int, cache: str, out_dir: str, size: int, colors: int,
              style: str, force: bool, attempts: int = 3) -> None:
    global _done
    dest = os.path.join(out_dir, f"{dex}.png")
    if os.path.exists(dest) and not force:
        with _lock:
            _done += 1
        return
    cached = os.path.join(cache, "pokemon", f"{dex}.json")
    if not os.path.exists(cached):
        with _lock:
            _failed.append((dex, "no cached pokemon record"))
        return
    with open(cached, "r", encoding="utf-8") as fh:
        url = sprite_url(json.load(fh), style)
    if not url:
        with _lock:
            _failed.append((dex, "no sprite url"))
        return

    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
            data = process(raw, size, colors)
            tmp = dest + ".part"
            with open(tmp, "wb") as fh:
                fh.write(data)
            os.replace(tmp, dest)
            with _lock:
                _done += 1
                if _done % 100 == 0:
                    print(f"  {_done}/{MAX_DEX}", flush=True)
            return
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            if attempt == attempts - 1:
                with _lock:
                    _failed.append((dex, str(exc)))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=".pokecache")
    ap.add_argument("--out", default="assets/sprites/pokemon")
    ap.add_argument("--size", type=int, default=192)
    ap.add_argument("--colors", type=int, default=128,
                    help="palette size; 0 keeps full colour")
    ap.add_argument("--style", default="home", choices=sorted(STYLES),
                    help="which sprite set from the repository to use")
    ap.add_argument("--force", action="store_true",
                    help="re-download and replace sprites that already exist")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=MAX_DEX)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    print(f"sprites -> {args.out}  style={args.style} size={args.size}px")
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for dex in range(1, args.limit + 1):
            pool.submit(fetch_one, dex, args.cache, args.out, args.size, args.colors,
                        args.style, args.force)

    total = sum(os.path.getsize(os.path.join(args.out, f))
                for f in os.listdir(args.out) if f.endswith(".png"))
    count = len([f for f in os.listdir(args.out) if f.endswith(".png")])
    print(f"{count} sprites, {total / 1024 / 1024:.1f} MiB")
    if _failed:
        print(f"{len(_failed)} failed:", file=sys.stderr)
        for dex, why in _failed[:10]:
            print(f"  {dex}: {why}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
