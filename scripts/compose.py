#!/usr/bin/env python3
"""Turns the raw captures in build/shots/ into the presentation images in docs/ (needs Pillow: pip3 install pillow).
Every app pixel is a real capture of the running app (scripts/screenshots.sh); the wallpaper and menu bar behind it are generated."""
import glob, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SHOTS, DOCS = os.path.join(ROOT, "build", "shots"), os.path.join(ROOT, "docs")
os.makedirs(DOCS, exist_ok=True)
import re
KEEP = set(re.findall(r"docs/([a-z0-9-]+\.png)", open(os.path.join(ROOT, "README.md")).read())) | {"hero.png", "social-preview.png"}

def trim(im, pad=0):
    bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if not bb: return im
    l, t, r, b = bb
    return im.crop((max(0, l - pad), 0, min(im.width, r + pad), min(im.height, b + pad)))

def wallpaper(w, h, seed=0):
    palette = [((20, 24, 66), (92, 36, 138), (16, 66, 118), (216, 66, 116)),
               ((12, 40, 70), (38, 90, 150), (70, 30, 110), (230, 110, 90))][seed % 2]
    g = Image.new("RGB", (2, 2)); g.putdata(list(palette))
    bg = g.resize((w, h), Image.BICUBIC).convert("RGBA")
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(glow)
    d.ellipse((w * 0.05, h * 0.5, w * 0.55, h * 1.5), fill=(120, 200, 255, 70))
    d.ellipse((w * 0.5, h * 0.3, w * 1.0, h * 1.4), fill=(255, 130, 190, 70))
    return Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(max(w, h) // 8)))

def menubar(bg, h=44):
    bg.alpha_composite(Image.new("RGBA", (bg.width, h), (0, 0, 0, 205)), (0, 0))

def island_card(src, name, pad_bottom=70, min_w=1500, seed=0):
    """An island capture hanging from a faux menu bar over a wallpaper."""
    im = trim(Image.open(src).convert("RGBA"), 36)
    w = max(min_w, im.width + 160)
    bg = wallpaper(w, im.height + pad_bottom, seed)
    menubar(bg)
    bg.alpha_composite(im, ((w - im.width) // 2, 0))
    if name in KEEP: bg.convert("RGB").save(os.path.join(DOCS, name), optimize=True)
    return bg

def window_card(src, name, pad=64, seed=1):
    im = Image.open(src).convert("RGBA")
    bg = wallpaper(im.width + 2 * pad, im.height + 2 * pad, seed)
    sh = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad + 14, pad + im.width, pad + im.height + 14), 40, fill=(0, 0, 0, 150))
    bg = Image.alpha_composite(bg, sh.filter(ImageFilter.GaussianBlur(26)))
    bg.alpha_composite(im, (pad, pad))
    if name in KEEP: bg.convert("RGB").save(os.path.join(DOCS, name), optimize=True)

def font(size, bold=True):
    for p in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial.ttf"):
        try: return ImageFont.truetype(p, size)
        except Exception: pass
    return ImageFont.load_default()

made = []
for f in sorted(glob.glob(os.path.join(SHOTS, "tab-*.png"))):
    n = os.path.basename(f)
    island_card(f, n, seed=len(made)); made.append(n)
pk = os.path.join(SHOTS, "picker.png")
if os.path.exists(pk): island_card(pk, "picker.png", seed=1); made.append("picker.png")
for n in ("closed", "alert"):
    f = os.path.join(SHOTS, n + ".png")
    if os.path.exists(f):
        im = trim(Image.open(f).convert("RGBA"), 40)
        bg = wallpaper(900, 220, 0); menubar(bg); bg.alpha_composite(im, ((900 - im.width) // 2, 0))
        bg.convert("RGB").save(os.path.join(DOCS, n + ".png"), optimize=True); made.append(n + ".png")
for f in sorted(glob.glob(os.path.join(SHOTS, "settings-*.png")) + glob.glob(os.path.join(SHOTS, "onboarding-*.png"))):
    n = os.path.basename(f); window_card(f, n); made.append(n)

# Hero: Home capture, large
home = os.path.join(SHOTS, "tab-home.png")
im = trim(Image.open(home).convert("RGBA"), 30)
sc = 1.3; im = im.resize((int(im.width * sc), int(im.height * sc)), Image.LANCZOS)
W, H = 2400, im.height + 90
bg = wallpaper(W, H, 0); menubar(bg, 52); bg.alpha_composite(im, ((W - im.width) // 2, 0))
bg.convert("RGB").save(os.path.join(DOCS, "hero.png"), optimize=True)

# GitHub social preview (Settings → Social preview): 1280x640
S = wallpaper(1280, 640, 0).convert("RGBA")
icon = Image.open(os.path.join(ROOT, "Resources", "AppIcon.png")).convert("RGBA")
icon = trim(icon, 0).resize((210, 210), Image.LANCZOS)
S.alpha_composite(icon, (90, 90))
d = ImageDraw.Draw(S)
d.text((330, 105), "Notchly", font=font(104), fill=(255, 255, 255, 255))
d.text((334, 235), "A control centre in your MacBook's notch", font=font(38), fill=(255, 255, 255, 225))
d.text((334, 288), "Music · Calendar · Files · Timers · Quick actions", font=font(28), fill=(255, 255, 255, 170))
hi = trim(Image.open(home).convert("RGBA"), 20); hi = hi.resize((820, int(hi.height * 820 / hi.width)), Image.LANCZOS)
S.alpha_composite(hi, ((1280 - hi.width) // 2, 640 - hi.height + 4))
S.convert("RGB").save(os.path.join(DOCS, "social-preview.png"), optimize=True)
print("docs:", len(made) + 4, "images")
