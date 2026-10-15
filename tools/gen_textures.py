"""Painted-style environment textures for Dry Gulch, generated procedurally with Pillow + numpy.

Writes into game/art/env/:
  sand.png          1024x1024 tileable sand with wind ripples and grain
  cracked.png       1024x1024 tileable cracked dry riverbed
  sandstone.png     1024x1024 mesa rock bands
  sky_panorama.png  2048x1024 equirectangular golden-hour sky: gradient, sun, clouds, distant mesas
  props_atlas.png   256x256 flat colour swatches used by the Blender props (one cell per material)
Run: python tools/gen_textures.py [--only sandstone,redrock]
"""
import math, os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "art", "env")
os.makedirs(ROOT, exist_ok=True)
rng = np.random.default_rng(88)


def tileable_noise(size, octaves=5, base_freq=4.0, persistence=0.5, seed=0):
    """Value noise summed over octaves, sampled on a torus so every axis wraps exactly."""
    r = np.random.default_rng(seed)
    out = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    total = 0.0
    u = np.linspace(0.0, 1.0, size, endpoint=False, dtype=np.float32)
    for o in range(octaves):
        f = int(base_freq * (2 ** o))
        grid = r.random((f, f)).astype(np.float32)
        fx = u * f
        i0 = np.floor(fx).astype(np.int64) % f
        i1 = (i0 + 1) % f
        t = fx - np.floor(fx)
        t = t * t * (3.0 - 2.0 * t)
        # bilinear on the periodic grid
        g00 = grid[i0[:, None], i0[None, :]]
        g10 = grid[i1[:, None], i0[None, :]]
        g01 = grid[i0[:, None], i1[None, :]]
        g11 = grid[i1[:, None], i1[None, :]]
        top = g00 * (1 - t[None, :]) + g01 * t[None, :]
        bot = g10 * (1 - t[None, :]) + g11 * t[None, :]
        out += (top * (1 - t[:, None]) + bot * t[:, None]) * amp
        total += amp
        amp *= persistence
    return out / total


def to_rgb(arr3):
    return Image.fromarray(np.clip(arr3 * 255.0, 0, 255).astype(np.uint8), "RGB")


def lerp_color(a, b, t):
    a = np.array(a, dtype=np.float32) / 255.0
    b = np.array(b, dtype=np.float32) / 255.0
    return a[None, None, :] * (1 - t[..., None]) + b[None, None, :] * t[..., None]


def sand(size=1024):
    n = tileable_noise(size, octaves=6, base_freq=3, seed=1)
    grain = tileable_noise(size, octaves=2, base_freq=128, seed=2)
    y = np.linspace(0, 1, size, dtype=np.float32)[:, None]
    x = np.linspace(0, 1, size, dtype=np.float32)[None, :]
    ripples = 0.5 + 0.5 * np.sin((x * 9.0 + n * 2.5 + y * 2.0) * math.pi * 2.0)
    ripples = ripples ** 2
    blotch = tileable_noise(size, octaves=3, base_freq=2, seed=6)
    # pass 54 (Garry: the sand a little lighter and less orange): value +6 %, saturation -10 %, a touch toward beige
    # (206, 160, 104) -> (246, 214, 156), mean (210, 175, 121). Pass 61 (Garry: "Make the generic desert floor sand
    # material even lighter"): another step, mean (215, 189, 146), value 0.84, saturation 0.32 (was 0.42), hue unchanged
    base = lerp_color((214, 176, 130), (250, 228, 182), n * 0.5 + blotch * 0.5)
    base = base * (0.80 + 0.36 * ripples[..., None]) * (0.92 + 0.16 * grain[..., None])
    img = to_rgb(base)
    return img


def cracked(size=1024):
    n = tileable_noise(size, octaves=5, base_freq=4, seed=3)
    # pass 54: the river bed follows the sand, lighter and less orange ((142, 96, 58) -> (206, 152, 98), cracks (104, 68,
    # 40), mean (169, 120, 75)). Pass 61 (Garry: "from brown colouring of the desert to a slightly browner shade of the
    # generic desert colour"): the sand's own family a step darker and warmer, mean (200, 166, 126) against the sand's
    # (215, 189, 146), the cracks a sand-brown that still reads
    base = lerp_color((176, 142, 104), (230, 198, 154), n)
    img = to_rgb(base)
    draw = ImageDraw.Draw(img)
    # cracks: a jittered Voronoi-ish polygon web drawn as dark lines, wrapped
    pts = [(rng.random() * size, rng.random() * size) for _ in range(90)]
    for (px, py) in pts:
        for _ in range(3):
            ang = rng.random() * math.tau
            length = 40 + rng.random() * 120
            x2, y2 = px + math.cos(ang) * length, py + math.sin(ang) * length
            for ox in (-size, 0, size):
                for oy in (-size, 0, size):
                    draw.line((px + ox, py + oy, x2 + ox, y2 + oy), fill=(158, 122, 86), width=int(2 + rng.random() * 3))
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    arr = np.asarray(img).astype(np.float32) / 255.0
    plates = tileable_noise(size, octaves=2, base_freq=12, seed=4)
    arr = arr * (0.85 + 0.3 * plates[..., None])
    return to_rgb(arr)


def sandstone(size=1024):
    n = tileable_noise(size, octaves=4, base_freq=3, seed=5)
    y = np.linspace(0, 1, size, dtype=np.float32)[:, None]
    bands = 0.5 + 0.5 * np.sin((y * 14.0 + n * 1.5) * math.pi * 2.0)
    bands = np.repeat(bands, size, axis=1) if bands.shape[1] == 1 else bands
    # pass 79 (Garry: "Map the sides are too orange"): grey bands with the old ones' light and dark ((160, 88, 52) ->
    # (204, 130, 78) before, the orange the cliffs wore under any tint), so Red Canyon's wall_colors tint them to exactly
    # the colour named (RedCanyon.WALL_COLORS); mean about 0.84
    base = lerp_color((182, 182, 182), (250, 250, 250), bands)
    base = base * (0.9 + 0.2 * n[..., None])
    return to_rgb(base)


def redrock(size=1024):
    """Broken red rock for the canyon rim: dark cracks over warm bands."""
    n = tileable_noise(size, octaves=5, base_freq=5, seed=9)
    n2 = tileable_noise(size, octaves=3, base_freq=9, seed=11)
    bands = 0.5 + 0.5 * np.sin((np.linspace(0, 1, size, dtype=np.float32)[:, None] * 9.0 + n * 2.0) * math.pi * 2.0)
    bands = np.repeat(bands, size, axis=1) if bands.shape[1] == 1 else bands
    base = lerp_color((146, 70, 48), (196, 112, 70), bands * 0.7 + n * 0.3)
    cracks = np.clip((np.abs(n2 - 0.5) < 0.02).astype(np.float32), 0, 1)
    base = base * (1.0 - 0.45 * cracks[..., None]) * (0.88 + 0.24 * n[..., None])
    return to_rgb(base)


def sky_panorama(w=2048, h=1024):
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    x = np.linspace(0, 1, w, dtype=np.float32)[None, :]
    # vertical gradient: top dusk purple -> horizon orange -> ground warm brown
    top = np.array((53, 35, 79), np.float32) / 255
    mid = np.array((214, 116, 66), np.float32) / 255
    hor = np.array((240, 162, 96), np.float32) / 255
    ground = np.array((132, 84, 46), np.float32) / 255
    img = np.zeros((h, w, 3), np.float32)
    t = np.repeat(y, w, axis=1)
    above = t < 0.5
    tt = np.clip(t / 0.5, 0, 1)
    sky = top[None, None, :] * (1 - tt[..., None]) ** 1.6 + mid[None, None, :] * (1 - (1 - tt[..., None]) ** 1.6)
    horz = np.clip((tt - 0.8) / 0.2, 0, 1)
    sky = sky * (1 - horz[..., None]) + hor[None, None, :] * horz[..., None]
    gt = np.clip((t - 0.5) / 0.5, 0, 1)
    gnd = hor[None, None, :] * (1 - gt[..., None]) ** 2 + ground[None, None, :] * (1 - (1 - gt[..., None]) ** 2)
    img = np.where(above[..., None], sky, gnd)
    # sun: low on the horizon at azimuth 0.62
    sx, sy = 0.62 * w, 0.44 * h
    xx = np.repeat(x, h, axis=0) * w
    yy = np.repeat(y, w, axis=1) * h
    d = np.sqrt((xx - sx) ** 2 + ((yy - sy) * 1.0) ** 2)
    disc = np.clip(1.0 - (d - 40) / 12.0, 0, 1)
    glow = np.exp(-d / 260.0) * 0.55
    sun_col = np.array((255, 226, 150), np.float32) / 255
    img = img * (1 - disc[..., None]) + sun_col[None, None, :] * disc[..., None]
    img = np.clip(img + glow[..., None] * np.array((1.0, 0.75, 0.45), np.float32)[None, None, :], 0, 1)
    # clouds: soft blobs in the upper band
    cn = tileable_noise(1024, octaves=5, base_freq=2, seed=9)
    cn = np.asarray(Image.fromarray((cn * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255
    cloud_band = np.clip(1 - np.abs(t - 0.28) / 0.16, 0, 1) ** 1.5
    clouds = np.clip((cn - 0.55) * 4.0, 0, 1) * cloud_band
    cloud_col = np.array((255, 214, 190), np.float32) / 255
    img = img * (1 - clouds[..., None] * 0.85) + cloud_col[None, None, :] * clouds[..., None] * 0.85
    # distant mesas: dark silhouettes just under the horizon line
    mesa_col = np.array((92, 52, 54), np.float32) / 255
    r = random.Random(7)
    silhouette = np.zeros((h, w), np.float32)
    for k in range(18):
        cx = r.random() * w
        width = 120 + r.random() * 260
        height = 18 + r.random() * 46
        x0, x1 = int(cx - width / 2), int(cx + width / 2)
        y0 = int(0.5 * h - height)
        for xi in range(x0, x1):
            xm = xi % w
            edge = min(xi - x0, x1 - xi) / 30.0
            hh = int(height * min(1.0, edge))
            silhouette[int(0.5 * h) - hh:int(0.5 * h) + 6, xm] = 1.0
    img = img * (1 - silhouette[..., None]) + mesa_col[None, None, :] * silhouette[..., None]
    return to_rgb(img)


def props_atlas(size=256):
    cells = [
        (78, 143, 76), (60, 120, 62), (156, 138, 122), (122, 104, 92), (184, 107, 62), (143, 78, 44),
        (122, 74, 58), (86, 50, 36), (138, 106, 74), (216, 67, 59), (91, 66, 37), (241, 232, 214),
        (110, 74, 44), (58, 42, 30), (200, 170, 110), (255, 178, 59),
    ]
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    n = 4
    cs = size // n
    for i, c in enumerate(cells):
        x, y = (i % n) * cs, (i // n) * cs
        d.rectangle((x, y, x + cs - 1, y + cs - 1), fill=c)
        # a little painted variation inside each cell
        for _ in range(60):
            px, py = x + rng.random() * cs, y + rng.random() * cs
            rr = 3 + rng.random() * 9
            shade = tuple(int(np.clip(v * (0.85 + rng.random() * 0.3), 0, 255)) for v in c)
            d.ellipse((px - rr, py - rr, px + rr, py + rr), fill=shade)
    return img


def main():
    # pass 79: `--only sandstone,redrock` writes just those (the others stay byte for byte as they are); cracked() and
    # props_atlas() draw from the shared rng, so they are always made in this order and only the asked-for ones saved
    import sys
    only = None
    for k, a in enumerate(sys.argv[1:]):
        if a.startswith("--only="):
            only = set(a[7:].split(","))
        elif a == "--only" and k + 2 < len(sys.argv):
            only = set(sys.argv[k + 2].split(","))
    makers = [("sand", sand), ("cracked", cracked), ("sandstone", sandstone), ("redrock", redrock),
              ("sky_panorama", sky_panorama), ("props_atlas", props_atlas)]
    wrote = 0
    for name, make in makers:
        if only is not None and name not in only and name not in ("cracked", "props_atlas"):
            continue
        img = make()
        if only is None or name in only:
            img.save(os.path.join(ROOT, name + ".png"))
            wrote += 1
    print("gen_textures: wrote %d textures into" % wrote, ROOT)


if __name__ == "__main__":
    main()
