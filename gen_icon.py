#!/usr/bin/env python3
"""Generate Brace macOS app icon — render 2048px master, LANCZOS-downscale all sizes."""

import math
import os
import json
from PIL import Image, ImageDraw, ImageFont, ImageFilter

TEAL = (0, 212, 170)
BG = (9, 22, 20)
ICON_DIR = "JsonViewApp/JsonViewApp/Assets.xcassets/AppIcon.appiconset"
MASTER = 2048


def draw_master() -> Image.Image:
    S = MASTER
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Background rounded rect
    bg = ImageDraw.Draw(img, "RGBA")
    radius = int(S * 0.225)
    bg.rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=BG + (255,))

    cx, cy = S / 2, S / 2

    # Thin circular arc — 3/4 circle, gap at bottom-right
    draw = ImageDraw.Draw(img, "RGBA")
    arc_width = max(1, int(S * 0.022))
    arc_r = S * 0.40
    arc_box = [cx - arc_r, cy - arc_r, cx + arc_r, cy + arc_r]
    draw.arc(arc_box, start=45, end=315, fill=TEAL + (70,), width=arc_width)

    # {/} centered
    font_size = int(S * 0.38)
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

    # Glow layer 1 — wide soft glow
    glow1 = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd1 = ImageDraw.Draw(glow1, "RGBA")
    gd1.text((tx, ty), text, font=font, fill=TEAL + (120,))
    glow1 = glow1.filter(ImageFilter.GaussianBlur(S // 22))
    img = Image.alpha_composite(img, glow1)

    # Glow layer 2 — tight inner glow
    glow2 = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd2 = ImageDraw.Draw(glow2, "RGBA")
    gd2.text((tx, ty), text, font=font, fill=TEAL + (180,))
    glow2 = glow2.filter(ImageFilter.GaussianBlur(S // 55))
    img = Image.alpha_composite(img, glow2)

    # Crisp text on top
    draw = ImageDraw.Draw(img, "RGBA")
    draw.text((tx, ty), text, font=font, fill=TEAL + (255,))

    return img


def main():
    os.makedirs(ICON_DIR, exist_ok=True)

    master = draw_master()

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
        icon = master.resize((px, px), Image.LANCZOS)
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
