"""Captioned App Store screenshots for the product-page test. Same pixels as the raw shots,
scaled into a framed phone under a headline, so the page says what the screen shows."""
import sys, pathlib
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'ppo'
FONTS = pathlib.Path.home() / 'Library/Fonts'
W, H = 1284, 2778  # the 6.5-inch size the live set uses
BG = (5, 5, 7); WHITE = (240, 240, 240); GOLD = (245, 185, 66); DIM = (150, 150, 155); EDGE = (60, 60, 66)

SHOTS = {
    '01-aiming':   ("WHERE TO AIM\nTONIGHT", "Meteor showers, planets, the Moon.\nA target computed for your sky."),
    '02-stacking': ("MINUTES OF LIGHT,\nSTACKED", "300 frames aligned on the stars.\nNoise drops, the Milky Way comes out."),
    '03-controls': ("A CAMERA\nTHAT HOLDS", "ISO, shutter, focus, white balance:\nlocked for the whole night."),
    '04-detector': ("CATCHES METEORS\nFOR YOU", "Watches the sky and saves\na clip around each one."),
    '05-events':   ("TONIGHT'S\nEVENTS", "Active showers, their rates,\nand where to point. Bought once."),
}
TREATMENTS = {
    'captions':     ['01-aiming', '02-stacking', '03-controls', '04-detector'],
    'result-first': ['02-stacking', '01-aiming', '05-events', '03-controls', '04-detector'],
}

head_font = ImageFont.truetype(str(FONTS / 'JetBrainsMonoNerdFont-ExtraBold.ttf'), 94)
sub_font = ImageFont.truetype(str(FONTS / 'JetBrainsMonoNerdFont-Regular.ttf'), 43)

def frame(name: str) -> Image.Image:
    head, sub = SHOTS[name]
    canvas = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(canvas)
    draw.multiline_text((86, 160), head, font=head_font, fill=WHITE, spacing=10)
    draw.multiline_text((86, 425), sub, font=sub_font, fill=GOLD, spacing=14)
    shot = Image.open(ROOT / f'{name}.png').convert('RGB')
    scale = 0.80
    sw, sh = int(W * scale), int(H * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, 595
    mask = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=90, fill=255)
    canvas.paste(shot, (x, y), mask)
    draw.rounded_rectangle((x - 2, y - 2, x + sw + 1, y + sh + 1), radius=92, outline=EDGE, width=4)
    return canvas

for treatment, names in TREATMENTS.items():
    d = OUT / treatment; d.mkdir(parents=True, exist_ok=True)
    for f in d.glob('*.png'): f.unlink()
    for i, name in enumerate(names, 1):
        frame(name).save(d / f'{i:02d}-{name}.png', optimize=True)
    print(treatment, [p.name for p in sorted(d.glob('*.png'))])
