"""Starlapse event media template: a sky, the app's own overlay on it, no words.

The overlay is the app's language: the yellow it draws targets in, the dashed aim circle, the
radiant marker, the Moon-mode metering ring, the planet ring. It says "this is what the app
shows you that night" without a line of text, which App Store event media should not carry.
"""
import math, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from layout import CARD, DETAIL, EVENTS

GOLD = "#F4C542"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def corners(W, H):
    m, l = round(min(W, H) * 0.045), round(min(W, H) * 0.06)
    pts = [(m, m, 1, 1), (W - m, m, -1, 1), (m, H - m, 1, -1), (W - m, H - m, -1, -1)]
    return "".join(f'<path d="M{x + dx * l},{y} L{x},{y} L{x},{y + dy * l}" />' for x, y, dx, dy in pts)

def ticks(cx, cy, r, n, length, rot=0):
    out = []
    for k in range(n):
        a = math.radians(rot + 360 * k / n)
        out.append(f'<line x1="{cx + r * math.cos(a):.1f}" y1="{cy + r * math.sin(a):.1f}" x2="{cx + (r + length) * math.cos(a):.1f}" y2="{cy + (r + length) * math.sin(a):.1f}" />')
    return "".join(out)

def overlay(e, L):
    s = min(L["W"], L["H"]) / 1080  # one scale for both formats
    parts = [f'<g stroke="rgba(255,255,255,.55)" stroke-width="{3 * s:.1f}" fill="none" stroke-linecap="round">{corners(L["W"], L["H"])}</g>']
    g = f'stroke="{GOLD}" fill="none" stroke-linecap="round"'
    if e["kind"] == "meteor":
        rx, ry = L["radiant"]; ax, ay = L["aim"]; ar = 92 * s
        d = math.hypot(ax - rx, ay - ry); ux, uy = (ax - rx) / d, (ay - ry) / d
        parts += [
            f'<g {g} stroke-width="{2.6 * s:.1f}"><circle cx="{rx}" cy="{ry}" r="{13 * s:.1f}" />{ticks(rx, ry, 20 * s, 4, 12 * s, 45)}</g>',
            f'<circle cx="{rx}" cy="{ry}" r="{44 * s:.1f}" {g} stroke-width="{1.4 * s:.1f}" opacity=".35" />',
            f'<line x1="{rx + ux * 58 * s:.1f}" y1="{ry + uy * 58 * s:.1f}" x2="{ax - ux * (ar + 14 * s):.1f}" y2="{ay - uy * (ar + 14 * s):.1f}" {g} stroke-width="{2 * s:.1f}" stroke-dasharray="{2 * s:.1f} {11 * s:.1f}" opacity=".7" />',
            f'<circle cx="{ax}" cy="{ay}" r="{ar:.1f}" {g} stroke-width="{3.4 * s:.1f}" stroke-dasharray="{16 * s:.1f} {11 * s:.1f}" filter="url(#glow)" />',
        ]
    else:
        cx, cy = L["moon"]; r = L["D"] / 2 + 22 * s
        parts += [
            f'<g {g} stroke-width="{2.4 * s:.1f}" filter="url(#glow)"><circle cx="{cx}" cy="{cy}" r="{r:.1f}" />{ticks(cx, cy, r + 8 * s, 4, 18 * s, -90)}</g>',
            f'<circle cx="{cx}" cy="{cy}" r="{r + 48 * s:.1f}" {g} stroke-width="{1.4 * s:.1f}" stroke-dasharray="{3 * s:.1f} {9 * s:.1f}" opacity=".4" />',
        ]
        if e.get("mars"):
            mx, my = L["mars"]
            parts += [f'<circle cx="{mx}" cy="{my}" r="{17 * s:.1f}" {g} stroke-width="{2.6 * s:.1f}" />',
                      f'<circle cx="{mx}" cy="{my}" r="{28 * s:.1f}" {g} stroke-width="{1.2 * s:.1f}" opacity=".35" />']
    return "".join(parts)

def page(bg, e, L):
    W, H = L["W"], L["H"]
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;width:{W}px;height:{H}px;overflow:hidden;background:#05070f}}
.l{{position:absolute;inset:0;width:{W}px;height:{H}px}}
.bg{{object-fit:cover;filter:saturate(1.08) contrast(1.04)}}
.vig{{background:radial-gradient(ellipse 75% 70% at 55% 42%,transparent 55%,rgba(0,0,0,.42) 100%)}}
</style></head><body>
<img class="l bg" src="{bg}">
<div class="l vig"></div>
<svg class="l" viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">
<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="{4 * min(W, H) / 1080:.1f}" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="grain"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/></filter></defs>
<rect width="100%" height="100%" filter="url(#grain)" opacity=".05"/>
{overlay(e, L)}
</svg></body></html>"""

def shoot(html, W, H, png):
    with tempfile.TemporaryDirectory() as prof:
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={prof}",
                        f"--window-size={W},{H}", "--force-device-scale-factor=1", f"--screenshot={png}", f"file://{html}"],
                       check=True, capture_output=True, timeout=120)

if __name__ == "__main__":
    bgdir, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2]); os.makedirs(out, exist_ok=True)
    from PIL import Image
    for key, e in EVENTS.items():
        for L, tag, name in ((CARD, "card", "card-1920x1080"), (DETAIL, "details", "details-1080x1920")):
            html = f"{out}/{key}-{tag}.html"
            open(html, "w").write(page(f"file://{bgdir}/{key}-{tag}.jpg", e, L))
            png = f"{out}/{key}-{tag}.png"; shoot(html, L["W"], L["H"], png)
            im = Image.open(png).convert("RGB"); assert im.size == (L["W"], L["H"]), im.size
            im.save(f"{out}/{key}-{name}.jpg", quality=93); os.remove(png)
            print(key, tag, im.size)
