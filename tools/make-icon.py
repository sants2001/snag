#!/usr/bin/env python3
"""Build Snag's app icon set from the source artwork.

The artwork is Santino's: a pixel-art hook lifting a folder, over a blue card. One thing has
to happen on the way in: the white page background becomes transparent. macOS composites its
own shadow under an icon and expects alpha outside the shape, so an opaque white square renders
as a visible white tile in the Dock and in Settings lists.

Transparency is flooded in from the page corners rather than keyed on "white", so the interior
white of the card survives. A naive white-to-alpha pass would eat the card and leave the folder
floating.

    python3 tools/make-icon.py [path/to/source.png]
"""
from __future__ import annotations

import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Snag/Assets.xcassets/AppIcon.appiconset"
SOURCE = ROOT / "tools/icon-source.png"

CANVAS = 1024
# macOS icons do not fill their canvas. The body sits inside a margin so the system has room
# for the shadow it draws underneath; without it the icon reads as oversized next to others.
MARGIN = 0.094


def drop_page_background(im: Image.Image) -> Image.Image:
    """Make the white page around the icon transparent, without touching interior white."""
    w, h = im.size
    marker = Image.new("RGB", (w, h), (0, 0, 0))
    marker.paste(im.convert("RGB"), (0, 0))
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        ImageDraw.floodfill(marker, corner, (255, 0, 255), thresh=26)

    mpx = marker.load()
    alpha = Image.new("L", (w, h), 255)
    apx = alpha.load()
    for y in range(h):
        for x in range(w):
            if mpx[x, y] == (255, 0, 255):
                apx[x, y] = 0
    # Feather by a hair so the cut edge is not aliased after downscaling.
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))

    out = im.copy()
    out.putalpha(alpha)
    return out


def trim(im: Image.Image) -> Image.Image:
    bbox = im.split()[3].getbbox()
    return im.crop(bbox) if bbox else im


def build(source: pathlib.Path) -> Image.Image:
    im = trim(drop_page_background(Image.open(source).convert("RGBA")))

    # Fit the trimmed artwork into the canvas, preserving aspect, centred, inside the margin.
    box = round(CANVAS * (1 - 2 * MARGIN))
    scale = min(box / im.width, box / im.height)
    art = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.paste(art, ((CANVAS - art.width) // 2, (CANVAS - art.height) // 2), art)
    return icon


def main() -> None:
    source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else SOURCE
    if not source.exists():
        sys.exit(f"No source artwork at {source}")

    master = build(source)
    manifest = json.loads((OUT / "Contents.json").read_text())
    for entry in manifest["images"]:
        px = int(entry["size"].split("x")[0]) * int(entry["scale"].rstrip("x"))
        master.resize((px, px), Image.LANCZOS).save(OUT / entry["filename"])
    print(f"wrote {len(manifest['images'])} icons from {source.name}")


if __name__ == "__main__":
    main()
