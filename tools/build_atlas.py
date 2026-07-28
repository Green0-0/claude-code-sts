#!/usr/bin/env python3
"""Pack the downloaded Pokemon sprites into one atlas texture.

    python3 tools/build_atlas.py [--src DIR] [--out FILE]

1025 loose PNGs would mean 1025 Godot .import files and 1025 disk reads; one
atlas means one of each. The layout is implicit rather than stored in a
manifest: cell = dex - 1, column = cell % COLS, row = cell / COLS, which is
what PokeSprites.gd assumes.

Sprites are centred in a fixed CELL box so every frame lands on the same grid
even where the source art is a different size.
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image

CELL = 96
COLS = 33
MAX_DEX = 1025


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="assets/sprites/pokemon")
    ap.add_argument("--out", default="assets/pokemon_atlas.png")
    ap.add_argument("--limit", type=int, default=MAX_DEX)
    args = ap.parse_args()

    src = os.path.abspath(args.src)
    if not os.path.isdir(src):
        print(f"no sprites at {src} — run tools/fetch_sprites.py first", file=sys.stderr)
        return 1

    rows = (args.limit + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))

    packed = 0
    missing = []
    for dex in range(1, args.limit + 1):
        path = os.path.join(src, f"{dex}.png")
        if not os.path.exists(path):
            missing.append(dex)
            continue
        sprite = Image.open(path).convert("RGBA")
        if sprite.size != (CELL, CELL):
            # Fit rather than stretch, so nothing gets distorted.
            sprite.thumbnail((CELL, CELL), Image.NEAREST)
        cell = dex - 1
        x = (cell % COLS) * CELL + (CELL - sprite.width) // 2
        y = (cell // COLS) * CELL + (CELL - sprite.height) // 2
        atlas.paste(sprite, (x, y), sprite)
        packed += 1

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    atlas.save(args.out, optimize=True)
    size = os.path.getsize(args.out)
    print(f"{packed} sprites -> {args.out}  ({atlas.width}x{atlas.height}, "
          f"{size / 1024 / 1024:.1f} MiB)")
    if missing:
        print(f"missing: {missing}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
