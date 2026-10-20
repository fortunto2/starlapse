"""The 1200×630 share image: a starfield, the name, one line, the stacking screenshot.

    python3 site/scripts/og.py
"""
import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parents[1]
FONTS = pathlib.Path.home() / "Library" / "Fonts"
W, H = 1200, 630
image = Image.new("RGB", (W, H), (0, 0, 0))
draw = ImageDraw.Draw(image)
random.seed(7)
for _ in range(900):
    x, y = random.random() * W, random.random() * H
    m = random.random() ** 3
    r = 0.5 + m * 1.8
    shade = int(110 + m * 145)
    draw.ellipse((x - r, y - r, x + r, y + r), fill=(shade, shade, min(255, shade + 10)))
# Concentric trails around a pole off the top left, faint.
for i in range(40):
    radius = 120 + i * 22
    start = random.random() * 360
    draw.arc((150 - radius, -60 - radius, 150 + radius, -60 + radius), start, start + 18, fill=(60, 60, 70), width=1)

bold = ImageFont.truetype(str(FONTS / "JetBrainsMono-Bold.ttf"), 76)
small = ImageFont.truetype(str(FONTS / "JetBrainsMono-Bold.ttf"), 26)
draw.text((72, 150), "STARLAPSE", font=bold, fill=(236, 235, 231))
draw.text((76, 250), "The night sky, properly.", font=small, fill=(255, 199, 64))
for i, line in enumerate(["Hundreds of 1 s frames, stacked", "Where to aim for tonight's meteors", "Sky darkness from every photo"]):
    draw.text((76, 330 + i * 44), "· " + line, font=small, fill=(154, 156, 163))
shot = Image.open(HERE / "public" / "img" / "02-stacking.jpg").convert("RGB")
shot = shot.resize((250, int(250 * shot.height / shot.width)))
mask = Image.new("L", shot.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width, shot.height), 30, fill=255)
image.paste(shot, (W - 250 - 110, 70), mask)
image.save(HERE / "public" / "og.jpg", quality=86)
print("og.jpg", image.size)
