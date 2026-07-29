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

Alternate forms come from the same place. Smogon's CAP units cannot: they exist
in no game, so their art comes from the Showdown client, which draws them as
Gen-5-era pixel sprites. Those are far smaller than a HOME render, so they are
scaled up with nearest-neighbour, which keeps their edges hard rather than
blurring them into something that does not match the set it sits beside.

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

import cap

MAX_DEX = 1025
UA = "claude-code-sts-pokemon-import/1.0 (github.com/local; contact: repo owner)"

## Where the Showdown client keeps CAP art. "dex" is its largest still set at
## 120px; the 96px "gen5" sprites are the fallback for the few formes it files
## under a hyphenated name instead.
CAP_SPRITES = "https://play.pokemonshowdown.com/sprites"

_lock = threading.Lock()
_done = 0
_failed: list = []


## The sprite sets worth choosing between, in the order each falls back.
##   home     soft rounded 512px renders — the kawaii set, all 1025 covered
##   front    the classic ~96px game sprite, pixel-art, all 1025 covered
##   artwork  full official artwork, painterly rather than cute
##   showdown animated GIFs; only 1004 species, and Godot needs an importer
## Forms are patchier than species, so every chain ends at official artwork
## rather than giving up — a Mega with no HOME render still has a painting.
STYLES = {
    "home": [("other", "home", "front_default"), ("front_default",),
             ("other", "official-artwork", "front_default")],
    "front": [("front_default",), ("other", "home", "front_default"),
              ("other", "official-artwork", "front_default")],
    "artwork": [("other", "official-artwork", "front_default"), ("front_default",)],
    "showdown": [("other", "showdown", "front_default"), ("front_default",),
                 ("other", "official-artwork", "front_default")],
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


## Above this, a trimmed source is a render and scales smoothly; at or below it
## the source is one of the pixel sets — the 96px classic sprites, CAP's 120px
## art — and has to be scaled with hard edges instead.
PIXEL_ART_MAX = 140


def process(raw: bytes, size: int, colors: int) -> bytes:
    """Trim the transparent margin, fit to a square, and re-encode.

    A source smaller than the square is scaled up to fill it rather than left
    adrift in the middle: every unit has to read at the same size in a panel,
    and a Gen-5 CAP sprite is a quarter the size of a HOME render.
    """
    img = Image.open(io.BytesIO(raw)).convert("RGBA")
    bbox = img.getbbox()          # drops the large empty border HOME art carries
    if bbox:
        img = img.crop(bbox)
    longest = max(img.width, img.height)
    if longest and longest < size:
        scale = size / longest
        # Nearest keeps pixel art crisp. The scale is rarely a whole number, so
        # a pixel here and there ends up a row wider than its neighbour — far
        # less noticeable at this size than a unit rendering at half scale.
        resample = Image.NEAREST if longest <= PIXEL_ART_MAX else Image.LANCZOS
        img = img.resize((round(img.width * scale), round(img.height * scale)),
                         resample)
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


def download(urls: list, dest: str, size: int, colors: int,
             attempts: int = 3) -> str:
    """Try each url in turn; write the first that works. Returns "" on success."""
    problem = "no sprite url"
    for url in urls:
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
                return ""
            except urllib.error.HTTPError as exc:
                problem = str(exc)
                break                      # a 404 will not become a 200
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                problem = str(exc)
                if attempt == attempts - 1:
                    break
    return problem


def tally(total: int) -> None:
    global _done
    with _lock:
        _done += 1
        if _done % 100 == 0:
            print(f"  {_done}/{total}", flush=True)


def fetch_one(dex: int, cache: str, out_dir: str, size: int, colors: int,
              style: str, force: bool, total: int) -> None:
    dest = os.path.join(out_dir, f"{dex}.png")
    if os.path.exists(dest) and not force:
        tally(total)
        return
    cached = os.path.join(cache, "pokemon", f"{dex}.json")
    if not os.path.exists(cached):
        with _lock:
            _failed.append((dex, "no cached pokemon record"))
        return
    with open(cached, "r", encoding="utf-8") as fh:
        body = json.load(fh)
    urls = [u for u in [sprite_url(body, style)] if u]
    if not urls and dex > MAX_DEX:
        # The Koraidon and Miraidon ride forms have no art of their own; they
        # are the same creature in a different pose, so the species' stands in.
        species = os.path.join(cache, "pokemon",
                               f"{species_id_of(body)}.json")
        if os.path.exists(species):
            with open(species, "r", encoding="utf-8") as fh:
                urls = [u for u in [sprite_url(json.load(fh), style)] if u]

    problem = download(urls, dest, size, colors) if urls else "no sprite url"
    if problem:
        with _lock:
            _failed.append((dex, problem))
        return
    tally(total)


def species_id_of(body: dict) -> int:
    url = (body.get("species") or {}).get("url", "")
    return int(url.rstrip("/").rsplit("/", 1)[-1]) if url else 0


def fetch_cap(entry: dict, species: dict, out_dir: str, size: int, colors: int,
              force: bool, total: int) -> None:
    """CAP art from the Showdown client, keyed by the id build_data.py gives it."""
    unit = cap.unit_id(entry, species)
    dest = os.path.join(out_dir, f"{unit}.png")
    if os.path.exists(dest) and not force:
        tally(total)
        return
    # Showdown files base species under their bare id and formes under the
    # hyphenated name, so ask for both.
    slugs = [entry["name"].lower(), cap.slug(entry["name"])]
    urls = [f"{CAP_SPRITES}/{folder}/{s}.png"
            for s in dict.fromkeys(slugs) for folder in ("dex", "gen5")]
    problem = download(urls, dest, size, colors)
    if problem:
        with _lock:
            _failed.append((entry["name"], problem))
        return
    tally(total)


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
    ap.add_argument("--no-forms", action="store_true",
                    help="species only; skip megas, regionals and other forms")
    ap.add_argument("--no-cap", action="store_true",
                    help="skip Smogon's CAP dex")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    cache = os.path.abspath(args.cache)

    folder = os.path.join(cache, "pokemon")
    ids = sorted(int(f[:-5]) for f in os.listdir(folder) if f.endswith(".json"))
    if args.limit < MAX_DEX:
        ids = [i for i in ids if i <= args.limit]   # quick test run
    elif args.no_forms:
        ids = [i for i in ids if i <= MAX_DEX]
    cap_species = {} if args.no_cap else cap.load(cache)["species"]
    total = len(ids) + len(cap_species)

    print(f"sprites -> {args.out}  style={args.style} size={args.size}px")
    print(f"  {len(ids)} from PokeAPI, {len(cap_species)} from Showdown")
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for dex in ids:
            pool.submit(fetch_one, dex, cache, args.out, args.size, args.colors,
                        args.style, args.force, total)
        for entry in cap_species.values():
            pool.submit(fetch_cap, entry, cap_species, args.out, args.size,
                        args.colors, args.force, total)

    written = sum(os.path.getsize(os.path.join(args.out, f))
                  for f in os.listdir(args.out) if f.endswith(".png"))
    count = len([f for f in os.listdir(args.out) if f.endswith(".png")])
    print(f"{count} sprites, {written / 1024 / 1024:.1f} MiB")
    if _failed:
        print(f"{len(_failed)} failed:", file=sys.stderr)
        for dex, why in _failed[:10]:
            print(f"  {dex}: {why}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
