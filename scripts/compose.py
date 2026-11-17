#!/usr/bin/env python3
"""Trims transparent padding from docs/*.png and builds docs/hero.png (needs Pillow: pip3 install pillow).
The pixels are real captures of the running app; the wallpaper behind the hero is a generated gradient."""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFilter

DOCS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")

def trim(path, pad):
    im = Image.open(path).convert("RGBA")
    bbox = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if not bbox: return im
    l, t, r, b = bbox
    box = (max(0, l - pad), max(0, t - 0), min(im.width, r + pad), min(im.height, b + pad))
    im = im.crop(box); im.save(path); return im

for f in glob.glob(os.path.join(DOCS, "*.png")):
    name = os.path.basename(f)
    if name.startswith(("tab-", "closed", "alert")): trim(f, 28)
    elif name.startswith(("settings-", "onboarding-")): trim(f, 0)

home = Image.open(os.path.join(DOCS, "tab-home.png")).convert("RGBA")
W, H = 2400, 620
corners = [(24, 28, 72), (96, 40, 140), (20, 70, 120), (224, 72, 120)]  # tl, tr, bl, br
g = Image.new("RGB", (2, 2)); g.putdata([corners[0], corners[1], corners[2], corners[3]])
bg = g.resize((W, H), Image.BICUBIC).convert("RGBA")
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(glow)
d.ellipse((W * 0.15, H * 0.35, W * 0.85, H * 1.3), fill=(255, 255, 255, 40))
bg = Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(120)))
bar = Image.new("RGBA", (W, 52), (0, 0, 0, 215)); bg.alpha_composite(bar, (0, 0))   # menu bar
scale = 1.25
h2 = home.resize((int(home.width * scale), int(home.height * scale)), Image.LANCZOS)
bg.alpha_composite(h2, ((W - h2.width) // 2, 0))
bg.convert("RGB").save(os.path.join(DOCS, "hero.png"), optimize=True)
print("docs/hero.png", bg.size)
