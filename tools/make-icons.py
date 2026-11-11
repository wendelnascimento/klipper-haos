#!/usr/bin/env python3
"""Draw the app icon (128x128) and logo (250x100). Original artwork.

Usage: python tools/make-icons.py klipper   (requires Pillow)
"""
import sys
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
S = 4  # supersampling

def nozzle(d, cx, top, w, h, color):
    # heater block + nozzle cone
    d.rounded_rectangle([cx - w//2, top, cx + w//2, top + h*0.45], radius=w//10, fill=color)
    d.polygon([(cx - w*0.28, top + h*0.45), (cx + w*0.28, top + h*0.45),
               (cx + w*0.07, top + h*0.80), (cx - w*0.07, top + h*0.80)], fill=color)

def icon():
    n = 128 * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=26 * S, fill=(3, 169, 244, 255))  # HA blue
    nozzle(d, n // 2, 18 * S, 56 * S, 70 * S, (255, 255, 255, 255))
    # extruded line
    y = 92 * S
    d.rounded_rectangle([24 * S, y, n // 2 + 3 * S, y + 9 * S], radius=4 * S, fill=(255, 152, 0, 255))
    d.rounded_rectangle([20 * S, y + 14 * S, n - 20 * S, y + 23 * S], radius=4 * S, fill=(255, 255, 255, 200))
    return img.resize((128, 128), Image.LANCZOS)

def logo():
    w, h = 250 * S, 100 * S
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ic = icon().resize((84 * S, 84 * S), Image.LANCZOS)
    img.paste(ic, (8 * S, 8 * S), ic)
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 23 * S)
        small = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 15 * S)
    except OSError:
        font = small = ImageFont.load_default()
    d.text((98 * S, 22 * S), "Klipper HAOS", font=font, fill=(33, 150, 243, 255))
    d.text((102 * S, 60 * S), "community app", font=small, fill=(120, 120, 120, 255))
    return img.resize((250, 100), Image.LANCZOS)

icon().save(f"{out}/icon.png", optimize=True)
logo().save(f"{out}/logo.png", optimize=True)
