#!/usr/bin/env python3
"""Generate Snag's app icon.

Upstream Cling ships its own artwork (a shattered sun in warm orange). GPL-3 covers the code,
not the logo, so a fork must draw its own mark rather than inherit that one.

Snag's mark is a hook, for the name and because a single bold curve survives being scaled to
16x16 where anything finer turns to mush. The palette is deliberately cool (cyan to indigo)
so the two apps are never confused in a Dock or a System Settings list.

Everything is drawn at 4x and downsampled with LANCZOS, which is cheaper than fighting PIL for
analytic antialiasing.

    python3 tools/make-icon.py
"""
from __future__ import annotations

import json
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "Cling/Assets.xcassets/AppIcon.appiconset"
SS = 4                      # supersampling factor
CANVAS = 1024
# macOS icons do not fill their canvas; the rounded body sits inside a margin so the system
# has room for the drop shadow it composites underneath.
INSET = 100
TOP = (56, 208, 245)        # cyan
BOTTOM = (79, 70, 229)      # indigo


def squircle(size: int, radius: float) -> Image.Image:
    """Apple-style continuous-curvature squircle, as an alpha mask.

    A plain rounded rectangle joins its arcs to the straight edges with a curvature
    discontinuity that reads as a subtle pinch at the corners next to real macOS icons.
    A superellipse |x/a|^n + |y/a|^n = 1 has no such join. n is derived from the requested
    corner radius so the silhouette still matches the platform metric.
    """
    n = 2.0 + 3.0 * (1.0 - min(radius / (size / 2), 1.0)) ** 0.5
    n = max(n, 4.0)
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    a = size / 2
    pts = []
    steps = 2048
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(c) ** (2 / n), c)
        y = a * math.copysign(abs(s) ** (2 / n), s)
        pts.append((a + x, a + y))
    d.polygon(pts, fill=255)
    return mask


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    grad = Image.new("RGB", (1, size))
    px = grad.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        # Ease the ramp so the midtone sits slightly high; a linear blend of these two hues
        # muddies through grey-blue right where the hook crosses it.
        t = t * t * (3 - 2 * t)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return grad.resize((size, size), Image.BILINEAR)


def hook(draw: ImageDraw.ImageDraw, size: int) -> None:
    """A fish hook: long shank, wide semicircular bend, barb rising to a spear point.

    Three details do the work of making this read as a hook rather than a "J":
    the bend is wide relative to the stroke (a tight bend closes into a "U"), the barb
    rises most of the way back up, and it ends in a triangular point rather than a
    round cap. Without the point it is just two parallel lines joined by a curve.
    """
    w = size * 0.072                     # stroke ~7% of the icon; still solid at 16px
    r = size * 0.190                     # bend radius, deliberately > 2x the stroke
    shank_x = size * 0.585
    top_y = size * 0.215
    bend_cy = size * 0.605

    draw.line([(shank_x, top_y), (shank_x, bend_cy)], fill=255, width=round(w))
    draw.ellipse(
        [shank_x - r, bend_cy - r, shank_x + r, bend_cy + r],
        outline=255, width=round(w),
    )
    # Erase the bend's upper half so the arc is a hook, not a closed ring. This also clips
    # the shank, so redraw it afterwards.
    draw.rectangle([shank_x - r * 1.7, bend_cy - r * 2.0, shank_x + r * 1.7, bend_cy], fill=0)
    draw.line([(shank_x, top_y), (shank_x, bend_cy)], fill=255, width=round(w))

    # Barb rises from the bend's left extremity. Anywhere further left and it floats free
    # of the curve, and the mark reads as a "U" beside a stray dot.
    barb_x = shank_x - r
    barb_top = bend_cy - r * 1.02
    draw.line([(barb_x, bend_cy), (barb_x, barb_top + w * 0.4)], fill=255, width=round(w))
    draw.polygon(
        [
            (barb_x - w * 0.78, barb_top + w * 0.75),
            (barb_x + w * 0.78, barb_top + w * 0.75),
            (barb_x, barb_top - w * 1.15),
        ],
        fill=255,
    )
    # Flush round cap on the shank, exactly half the stroke so it doesn't bulge.
    draw.ellipse(
        [shank_x - w / 2, top_y - w / 2, shank_x + w / 2, top_y + w / 2], fill=255,
    )


def build() -> Image.Image:
    big = CANVAS * SS
    inset = INSET * SS
    body = big - 2 * inset

    mask = squircle(body, body * 0.225)
    grad = vertical_gradient(body, TOP, BOTTOM)

    # A soft top-left sheen keeps the flat gradient from looking like a plain swatch.
    sheen = Image.new("L", (body, body), 0)
    ImageDraw.Draw(sheen).ellipse(
        [-body * 0.35, -body * 0.75, body * 0.95, body * 0.42], fill=64,
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(body * 0.09))
    grad = Image.composite(Image.new("RGB", (body, body), (255, 255, 255)), grad, sheen)

    glyph = Image.new("L", (body, body), 0)
    hook(ImageDraw.Draw(glyph), body)
    glyph = glyph.filter(ImageFilter.GaussianBlur(SS * 0.6))
    grad = Image.composite(Image.new("RGB", (body, body), (255, 255, 255)), grad, glyph)

    icon = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    icon.paste(grad, (inset, inset), mask)
    return icon.resize((CANVAS, CANVAS), Image.LANCZOS)


def main() -> None:
    master = build()
    manifest = json.loads((OUT / "Contents.json").read_text())
    written = set()
    for entry in manifest["images"]:
        px = int(entry["size"].split("x")[0]) * int(entry["scale"].rstrip("x"))
        master.resize((px, px), Image.LANCZOS).save(OUT / entry["filename"])
        written.add(entry["filename"])
    print(f"wrote {len(written)} icons to {OUT}")


if __name__ == "__main__":
    main()
