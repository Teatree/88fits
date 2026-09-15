"""Meadow textures for Mossy Hollow, the same way tools/gen_textures.py paints the desert: seamless noise, no
photos. Writes grass.png, dirt.png, mossrock.png and sky_meadow.png into game/art/env/.

    python tools/gen_textures_meadow.py
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_textures import ROOT, tileable_noise, to_rgb, lerp_color  # noqa: E402


def grass(size=1024):
    n = tileable_noise(size, octaves=6, base_freq=3, seed=21)
    blades = tileable_noise(size, octaves=3, base_freq=160, seed=22)
    clumps = tileable_noise(size, octaves=4, base_freq=9, seed=23)
    base = lerp_color((72, 122, 54), (128, 176, 78), n * 0.55 + clumps * 0.45)
    base = base * (0.84 + 0.3 * blades[..., None]) * (0.92 + 0.16 * clumps[..., None])
    return to_rgb(base)


def dirt(size=1024):
    n = tileable_noise(size, octaves=5, base_freq=4, seed=31)
    grain = tileable_noise(size, octaves=2, base_freq=110, seed=32)
    pebbles = tileable_noise(size, octaves=3, base_freq=40, seed=33)
    peb = np.clip((pebbles - 0.6) * 5.0, 0, 1)
    # calm: no bright pebbles, a value close to the grass so worn patches read as ground, not as camouflage
    base = lerp_color((84, 70, 44), (112, 94, 60), n)
    base = base * (0.94 + 0.12 * grain[..., None])
    base = base * (1 - peb[..., None] * 0.12)
    return to_rgb(base)


def mossrock(size=1024):
    n = tileable_noise(size, octaves=6, base_freq=3, seed=41)
    moss = tileable_noise(size, octaves=4, base_freq=6, seed=42)
    m = np.clip((moss - 0.5) * 3.0, 0, 1)
    rock = lerp_color((98, 102, 96), (150, 152, 142), n)
    green = lerp_color((60, 110, 48), (110, 160, 70), moss)
    base = rock * (1 - m[..., None]) + green * m[..., None]
    return to_rgb(base)


def sky_meadow(w=2048, h=1024):
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    x = np.linspace(0, 1, w, dtype=np.float32)[None, :]
    top = np.array((58, 118, 212), np.float32) / 255
    mid = np.array((132, 180, 236), np.float32) / 255
    hor = np.array((208, 226, 236), np.float32) / 255
    ground = np.array((70, 110, 60), np.float32) / 255
    t = np.repeat(y, w, axis=1)
    above = t < 0.5
    tt = np.clip(t / 0.5, 0, 1)
    sky = top[None, None, :] * (1 - tt[..., None]) ** 1.4 + mid[None, None, :] * (1 - (1 - tt[..., None]) ** 1.4)
    horz = np.clip((tt - 0.78) / 0.22, 0, 1)
    sky = sky * (1 - horz[..., None]) + hor[None, None, :] * horz[..., None]
    gt = np.clip((t - 0.5) / 0.5, 0, 1)
    gnd = hor[None, None, :] * (1 - gt[..., None]) ** 2 + ground[None, None, :] * (1 - (1 - gt[..., None]) ** 2)
    img = np.where(above[..., None], sky, gnd)
    # sun, high and white
    sx, sy = 0.3 * w, 0.2 * h
    xx = np.repeat(x, h, axis=0) * w
    yy = np.repeat(y, w, axis=1) * h
    d = np.sqrt((xx - sx) ** 2 + (yy - sy) ** 2)
    disc = np.clip(1.0 - (d - 30) / 10.0, 0, 1)
    glow = np.exp(-d / 220.0) * 0.35
    img = img * (1 - disc[..., None]) + np.array((1.0, 0.98, 0.9), np.float32)[None, None, :] * disc[..., None]
    img = np.clip(img + glow[..., None] * np.array((1.0, 0.95, 0.8), np.float32)[None, None, :], 0, 1)
    # big fluffy cumulus in two bands
    cn = tileable_noise(1024, octaves=6, base_freq=2, seed=51)
    cn = np.asarray(Image.fromarray((cn * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255
    band = np.clip(1 - np.abs(t - 0.3) / 0.2, 0, 1) ** 1.2
    clouds = np.clip((cn - 0.5) * 3.2, 0, 1) * band
    shade = np.clip((cn - 0.62) * 4.0, 0, 1) * band
    cloud_col = np.array((1.0, 1.0, 1.0), np.float32)
    img = img * (1 - clouds[..., None] * 0.92) + cloud_col[None, None, :] * clouds[..., None] * 0.92
    img = img * (1 - shade[..., None] * 0.18)
    # forested hills under the horizon
    hill_col = np.array((46, 84, 52), np.float32) / 255
    r = random.Random(5)
    silhouette = np.zeros((h, w), np.float32)
    for k in range(22):
        cx = r.random() * w
        width = 160 + r.random() * 320
        height = 22 + r.random() * 52
        x0, x1 = int(cx - width / 2), int(cx + width / 2)
        for xi in range(x0, x1):
            xm = xi % w
            u = (xi - x0) / max(1.0, (x1 - x0))
            hh = int(height * math.sin(u * math.pi))
            silhouette[int(0.5 * h) - hh:int(0.5 * h) + 8, xm] = 1.0
    img = img * (1 - silhouette[..., None]) + hill_col[None, None, :] * silhouette[..., None]
    return to_rgb(img)


def main():
    os.makedirs(ROOT, exist_ok=True)
    for name, fn in [("grass", grass), ("dirt", dirt), ("mossrock", mossrock), ("sky_meadow", sky_meadow)]:
        img = fn()
        img.save(os.path.join(ROOT, name + ".png"))
        print("wrote", name, img.size)


if __name__ == "__main__":
    main()
