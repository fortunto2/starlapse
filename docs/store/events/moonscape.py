"""Full-Moon event media: the real Moon over a ridge at dusk. No text.

    uv run --with numpy --with pillow python3 moonscape.py <moon.jpg>
"""
import sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
PHOTO = sys.argv[1]  # NASA Goddard full Moon, public domain: commons.wikimedia.org/wiki/File:Full_Moon_(15984763045).jpg

MARIA = [  # (x, y, rx, ry) in disc radii, y up — the near side as seen from the north
    (-0.36, 0.40, 0.26, 0.22), (-0.62, 0.02, 0.22, 0.42), (0.16, 0.40, 0.15, 0.14),
    (0.31, 0.12, 0.19, 0.16), (0.70, 0.27, 0.11, 0.09), (0.55, -0.16, 0.12, 0.15),
    (-0.20, -0.33, 0.16, 0.13), (-0.49, -0.40, 0.09, 0.09), (0.38, -0.30, 0.08, 0.08),
    (0.00, 0.72, 0.40, 0.06), (-0.02, -0.05, 0.10, 0.08),
]

def blur(a, r):
    return np.asarray(Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r)), np.float32) / 255

def moon_disc(D, rng):
    """The real Moon: NASA Goddard / LRO full Moon, public domain. Cropped to its disc."""
    im = np.asarray(Image.open(PHOTO).convert("RGB"), np.float32) / 255
    lum = im.mean(2); ys, xs = np.nonzero(lum > 0.08)
    cy, cx = (ys.min() + ys.max()) / 2, (xs.min() + xs.max()) / 2
    R = ((ys.max() - ys.min()) + (xs.max() - xs.min())) / 4
    box = (int(cx - R), int(cy - R), int(cx + R), int(cy + R))
    disc = np.asarray(Image.fromarray((im * 255).astype(np.uint8)).crop(box).resize((D, D), Image.LANCZOS), np.float32) / 255
    y, x = np.mgrid[-1:1:D * 1j, -1:1:D * 1j]
    alpha = np.clip((1 - np.hypot(x, y)) * D / 2 - 1.0, 0, 1)
    return disc, alpha

def render(W, H, centre, D, seed, out, ground=(10, 10, 22), trees=True, mars=None, lanterns=0, warm=(255, 232, 200), snow=False):
    rng = np.random.default_rng(seed)
    t = np.linspace(0, 1, H)[:, None, None]
    stops = [(0.0, (8, 14, 40)), (0.45, (28, 40, 88)), (0.70, (70, 72, 120)), (0.80, (150, 112, 140)), (0.86, (190, 130, 128))]
    sky = np.zeros((H, 1, 3), np.float32)
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        m = (t >= a) & (t <= b); f = (t - a) / (b - a)
        sky = np.where(m, np.array(ca) + (np.array(cb) - np.array(ca)) * f, sky)
    sky = np.where(t > 0.86, np.array(stops[-1][1]), sky)
    img = np.broadcast_to(sky, (H, W, 3)).astype(np.float32).copy()
    # faint stars only high up, where the sky is already dark
    n = int(W * H / 2500); sx = rng.integers(0, W, n); sy = (rng.random(n) ** 2 * H * 0.45).astype(int)
    st = np.zeros((H, W), np.float32); np.add.at(st, (sy, sx), 60 + 140 * rng.random(n) ** 4 * (1 - sy / (H * 0.45)))
    img += blur(st / 255, 0.6)[..., None] * 255 * 1.4
    # the Moon, warm because it is low, with a soft glow around it
    disc, alpha = moon_disc(D, rng)
    cx, cy = centre; x0, y0 = cx - D // 2, cy - D // 2
    tint = np.array(warm, np.float32)
    glow = np.zeros((H, W), np.float32); glow[y0:y0 + D, x0:x0 + D] = alpha
    halo = blur(glow, D * 0.25) * 0.55 + blur(glow, D * 0.06) * 0.35
    img += halo[..., None] * np.array([255, 220, 180]) * 0.55
    patch = img[y0:y0 + D, x0:x0 + D]
    img[y0:y0 + D, x0:x0 + D] = patch * (1 - alpha[..., None]) + (np.clip(disc * 1.12, 0, 1) * tint) * alpha[..., None]
    # ridge with conifers
    xs = np.arange(W); noise = np.convolve(rng.standard_normal(W), np.ones(15) / 15, mode="same")
    ridge = H * (0.86 + 0.03 * np.sin(xs / W * 3.7 + seed) + 0.012 * np.sin(xs / W * 9.3 + 2.1)) + noise * H * 0.003
    land = Image.new("L", (W, H), 0); dr = ImageDraw.Draw(land)
    dr.polygon([(0, H)] + [(int(i), float(ridge[i])) for i in xs[::2]] + [(W - 1, H)], fill=255)
    for _ in range(int(W / 22) if trees else 0):
        tx = int(rng.integers(0, W)); base = float(ridge[tx]) + 4; h = H * rng.uniform(0.025, 0.07); w = h * rng.uniform(0.28, 0.4)
        for k in range(4):
            yk = base - h * k / 4.4; wk = w * (1 - k / 5)
            dr.polygon([(tx - wk, yk), (tx + wk, yk), (tx, yk - h * 0.42)], fill=255)
    m = np.asarray(land.filter(ImageFilter.GaussianBlur(0.7)), np.float32)[..., None] / 255
    if mars:
        mx, my = mars; dot = np.zeros((H, W), np.float32); dot[my - 2:my + 3, mx - 2:mx + 3] = 1
        img += blur(dot, 2.5)[..., None] * np.array([255, 140, 70]) * 9 + blur(dot, 10)[..., None] * np.array([255, 120, 60]) * 6
    if lanterns:
        L = np.zeros((H, W), np.float32)
        for _ in range(lanterns):
            lx = int(rng.integers(int(W * 0.05), int(W * 0.95))); ly = int(H * rng.uniform(0.45, 0.82)); s = max(2, int(H * rng.uniform(0.004, 0.009) * (ly / H)))
            L[ly - s:ly + s, lx - int(s * 0.8):lx + int(s * 0.8)] = 1
        img += blur(L, 1.2)[..., None] * np.array([255, 170, 80]) * 1.1 + blur(L, 9)[..., None] * np.array([255, 120, 40]) * 2.2
    img = img * (1 - m) + np.array(ground) * m
    if snow:
        xs2 = np.arange(W); edge = H * (0.915 + 0.025 * np.sin(xs2 / W * 2.2 + 0.4))
        yy2 = np.arange(H)[:, None]; field = yy2 > edge[None, :]
        depth = np.clip((yy2 - edge[None, :]) / (H * 0.09), 0, 1)
        col = np.array([196, 206, 228]) * (1 - 0.35 * depth[..., None]) + rng.normal(0, 3, (H, W, 1))
        img = np.where(field[..., None], col, img)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(out, quality=95)



render(1920, 1080, (1260, 560), 380, 3, "christmas-card-1920x1080.jpg")
render(1080, 1920, (560, 1180), 470, 5, "christmas-details-1080x1920.jpg")
render(1920, 1080, (700, 470), 360, 21, "beaver-card-1920x1080.jpg")
render(1080, 1920, (420, 1050), 440, 23, "beaver-details-1080x1920.jpg")
render(1920, 1080, (1180, 540), 380, 31, "wolf-card-1920x1080.jpg", snow=True, warm=(240, 238, 235))
render(1080, 1920, (600, 1120), 460, 33, "wolf-details-1080x1920.jpg", snow=True, warm=(240, 238, 235))
render(1920, 1080, (1080, 500), 360, 41, "lantern-card-1920x1080.jpg", trees=False, mars=(1330, 400), lanterns=26)
render(1080, 1920, (520, 1000), 430, 43, "lantern-details-1080x1920.jpg", trees=False, mars=(800, 830), lanterns=22)
