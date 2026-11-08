"""Geminids event media: a stacked night sky with meteors radiating from Gemini. No text."""
import sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

def render(W, H, radiant, seed, out, n_met=13):
    rng = np.random.default_rng(seed)
    y = np.linspace(0, 1, H)[:, None]; x = np.linspace(0, 1, W)[None, :]
    top = np.array([3, 5, 14]); mid = np.array([10, 16, 36]); bot = np.array([34, 40, 70])
    t = y[..., None]
    sky = np.where(t < 0.6, top + (mid - top) * (t / 0.6), mid + (bot - mid) * ((t - 0.6) / 0.4) ** 1.5)
    img = np.broadcast_to(sky, (H, W, 3)).astype(np.float32).copy()
    d = (x * 0.6 + y * 0.8 - 0.8) / 0.10
    img += np.exp(-d ** 2)[..., None] * np.array([12, 13, 20]) * (0.7 + 0.3 * rng.random((H, W, 1)))
    # stars
    n = int(W * H / 420)
    sx = rng.integers(0, W, n); sy = rng.integers(0, int(H * 0.9), n)
    lum = rng.random(n) ** 4.5
    star = np.zeros((H, W, 3), np.float32)
    tint = np.stack([0.85 + 0.15 * rng.random(n), np.full(n, 0.95), 0.92 + 0.08 * rng.random(n)], 1)
    np.add.at(star, (sy, sx), tint * (70 + 185 * lum)[:, None])
    big = star.copy(); big[big < 160] = 0
    halo = np.asarray(Image.fromarray(np.clip(big, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2)), np.float32)
    soft = np.asarray(Image.fromarray(np.clip(star, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)), np.float32)
    img += soft * 1.6 + halo * 2.2
    # meteors at 2x, tapered: thin faint tail, wide bright head
    S = 2
    layer = Image.new("L", (W * S, H * S), 0); dr = ImageDraw.Draw(layer)
    rx, ry = radiant
    angles = np.linspace(0, 2 * math.pi, n_met, endpoint=False) + rng.uniform(-0.18, 0.18, n_met)
    for a in angles:
        start = rng.uniform(0.07, 0.30) * max(W, H); length = rng.uniform(0.09, 0.22) * max(W, H)
        segs = 40
        for k in range(segs):
            t0, t1 = k / segs, (k + 1) / segs
            p0 = (rx + math.cos(a) * (start + length * t0), ry + math.sin(a) * (start + length * t0))
            p1 = (rx + math.cos(a) * (start + length * t1), ry + math.sin(a) * (start + length * t1))
            fade = 1.0 if t1 < 0.93 else max(0.0, (1 - t1) / 0.07)
            v = int(255 * (0.15 + 0.85 * t1 ** 1.4) * fade)
            w = max(1, int(S * (0.6 + 2.4 * t1 ** 2)))
            dr.line([(p0[0] * S, p0[1] * S), (p1[0] * S, p1[1] * S)], fill=v, width=w)
    met = np.asarray(layer.resize((W, H), Image.LANCZOS), np.float32) / 255
    glow = np.asarray(Image.fromarray((met * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4)), np.float32) / 255
    img += met[..., None] * np.array([250, 250, 255]) * 1.3 + glow[..., None] * np.array([90, 160, 200]) * 1.6
    # horizon
    xs = np.arange(W)
    noise = np.convolve(rng.standard_normal(W), np.ones(9) / 9, mode="same")
    ridge = H * (0.885 + 0.03 * np.sin(xs / W * 4.3 + seed) + 0.014 * np.sin(xs / W * 11.9 + 1.3)) + noise * H * 0.003
    yy = np.arange(H)[:, None]
    img += np.exp(-((yy - ridge[None, :]) / (H * 0.045)) ** 2)[..., None] * np.array([26, 26, 34])
    img[yy > ridge[None, :]] = np.array([2, 3, 6])
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(out, quality=95)

base = sys.argv[1] if len(sys.argv) > 1 else "."
render(1920, 1080, (1180, 300), 7, f"{base}/geminids-card-1920x1080.jpg", 14)
render(1080, 1920, (620, 560), 11, f"{base}/geminids-details-1080x1920.jpg", 13)
render(1920, 1080, (300, 120), 57, f"{base}/quad-card-1920x1080.jpg", 13)
render(1080, 1920, (880, 380), 59, f"{base}/quad-details-1080x1920.jpg", 12)
