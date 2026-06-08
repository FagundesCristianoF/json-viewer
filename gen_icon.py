#!/usr/bin/env python3
"""Generate DevKit macOS app icon — { globe } concept."""

import math
import os
import json
from PIL import Image, ImageDraw, ImageFont

AMBER = (124, 107, 248)   # Electric Indigo
BG = (13, 11, 26)
ICON_DIR = "JsonViewApp/JsonViewApp/Assets.xcassets/AppIcon.appiconset"


def draw_globe(draw, cx, cy, r, color, line_width):
    """Draw a simple globe: outer circle + 2 latitude lines + 2 longitude ellipses."""
    box = [cx - r, cy - r, cx + r, cy + r]
    draw.ellipse(box, outline=color, width=line_width)

    # Equator
    draw.line([(cx - r, cy), (cx + r, cy)], fill=color, width=line_width)

    # Upper/lower latitude lines
    for lat_frac in [0.45]:
        lat_y_off = r * lat_frac
        lat_r = math.sqrt(max(0, r * r - lat_y_off * lat_y_off))
        for sign in [-1, 1]:
            ly = cy + sign * lat_y_off
            draw.ellipse([cx - lat_r, ly - line_width // 2,
                          cx + lat_r, ly + line_width // 2],
                         outline=color, width=1)

    # Vertical meridian (center)
    draw.ellipse(box, outline=color, width=line_width)

    # Two longitude arcs as narrow ellipses
    for x_stretch in [0.55]:
        draw.ellipse([cx - r * x_stretch, cy - r, cx + r * x_stretch, cy + r],
                     outline=color, width=line_width)


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Background rounded rect
    bg_draw = ImageDraw.Draw(img, "RGBA")
    radius = int(size * 0.225)
    bg_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=BG + (255,))

    draw = ImageDraw.Draw(img, "RGBA")
    cx, cy = size / 2, size / 2

    # Thin circular arc — 3/4 circle, gap at bottom-right
    arc_width = max(1, int(size * 0.022))
    arc_r = size * 0.40
    arc_box = [cx - arc_r, cy - arc_r, cx + arc_r, cy + arc_r]
    draw.arc(arc_box, start=45, end=315, fill=AMBER + (70,), width=arc_width)

    # {/} centered
    font_size = int(size * 0.38)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", font_size)
    except Exception:
        font = ImageFont.load_default()

    text = "{/}"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = cx - tw / 2 - bbox[0]
    ty = cy - th / 2 - bbox[1]

    if size >= 64:
        glow_color = AMBER + (30,)
        for dx, dy in [(-2, 0), (2, 0), (0, -2), (0, 2)]:
            draw.text((tx + dx, ty + dy), text, font=font, fill=glow_color)

    draw.text((tx, ty), text, font=font, fill=AMBER + (255,))

    return img


def main():
    os.makedirs(ICON_DIR, exist_ok=True)

    size_map = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    for filename, px in size_map.items():
        icon = draw_icon(px)
        path = os.path.join(ICON_DIR, filename)
        icon.save(path, "PNG")
        print(f"  {path}")

    entries = [
        ("16x16", "1x", "icon_16x16.png"),
        ("16x16", "2x", "icon_16x16@2x.png"),
        ("32x32", "1x", "icon_32x32.png"),
        ("32x32", "2x", "icon_32x32@2x.png"),
        ("128x128", "1x", "icon_128x128.png"),
        ("128x128", "2x", "icon_128x128@2x.png"),
        ("256x256", "1x", "icon_256x256.png"),
        ("256x256", "2x", "icon_256x256@2x.png"),
        ("512x512", "1x", "icon_512x512.png"),
        ("512x512", "2x", "icon_512x512@2x.png"),
    ]
    images = [{"filename": f, "idiom": "mac", "scale": s, "size": sz} for sz, s, f in entries]
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(ICON_DIR, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("Done.")


if __name__ == "__main__":
    main()
