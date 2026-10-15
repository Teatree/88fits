"""Pass 82 (lane SAND; Garry: "Sand Texture is still not very good. I added a reference called sand-texture.webp let's
try generating something like that, and maybe a couple (4) variants to try out, see which feels most natural. I like
the little rocks in the texture though, can you keep them in 2 out of the 4 variants. Add the previous sand texture as
the 5th variant as well. I want to be able to switch between them easily."): the four new sands.

The reference (a watermarked stock photo) is only described in words here, never fed to a model or traced: soft, broad,
wavy dune shading (wide gentle light and dark bands, no hard ripples), a fine even grain, warm golden tan.

Every sand is laid over today's mean colour (gen_textures.sand_procedural's, the palette Garry approved in passes 54 and
61), so the river bed, the oases and the walls still match and the colour pins hold; only its light and dark (and a
little of a pebble's own colour) come from the source.

  python tools/gen_sand.py --paint [--prompts dunes,pebbles] [--seeds 8201,8202]   # Klein paintings (AI server, comfy lock)
  python tools/gen_sand.py --seam [--only <stem>,...]                              # make them tileable (seam inpaint)
  python tools/gen_sand.py --cands                                                 # candidate textures -> tools/dl/p82/SAND/cands
  python tools/gen_sand.py --keep [--only <id>,...]                                # the picked tiles -> tools/art_src/sand_<id>_src.png
  python tools/gen_sand.py [--only <id>,...]                                       # write game/art/env/sand_<id>.png (SANDS)
  python tools/gen_sand.py --previews <shots dir>                                  # the Level Editor's sand_previews.png

Tileable without the half-offset cross-fade (it doubles every pebble and flattens the bands where the copies cross):
the painting is rolled half a tile, so its old edges meet in a cross through the middle and its new edges wrap
cleanly; the cross is painted again by the model under a latent noise mask (everything else kept), and composited back
feathered (seam_inpaint). The procedural parts are made on a torus, tileable by construction.
"""
import io, math, os, sys
import numpy as np
from PIL import Image, ImageFilter

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)

ENV = os.path.join(REPO, "game", "art", "env")
ART_SRC = os.path.join(TOOLS, "art_src")
WORK = os.path.join(TOOLS, "dl", "p82", "SAND")
AI_DIR = os.path.join(WORK, "ai")
CAND_DIR = os.path.join(WORK, "cands")
SIZE = 1024
LUMA = np.array([0.299, 0.587, 0.114], np.float32)

# The prompts (the reference in words; nothing of the photo goes to the server)
PROMPTS = {
    "dunes": ("Seamless tileable top-down texture of smooth desert sand for a stylized video game ground. Soft broad "
              "wind-shaped dune shading: wide gentle wavy bands of slightly lighter and slightly darker sand flowing "
              "across the whole image, very soft blurred edges between them, no sharp ripples. A fine even sand grain "
              "all over, like fine speckled noise. Warm golden tan colour, low contrast, flat even lighting, "
              "orthographic view straight down, no shadows, no footprints, no plants, no objects, no text."),
    "pebbles": ("Seamless tileable top-down texture of smooth desert sand for a stylized video game ground. Soft broad "
                "wind-shaped dune shading: wide gentle wavy bands of slightly lighter and slightly darker sand flowing "
                "across the whole image, very soft blurred edges between them, no sharp ripples. A fine even sand grain "
                "all over. A few small scattered pebbles and tiny grey-brown stones lying far apart on the sand, sparse. "
                "Warm golden tan colour, low contrast, flat even lighting, orthographic view straight down, no "
                "footprints, no plants, no text."),
    # the same, softer and less regular: hazy patches more than stripes (the reference's bands are blurred)
    "drift": ("Seamless tileable top-down texture of fine desert sand for a stylized video game ground. Very soft, hazy, "
              "irregular wind-blown shading: broad blurry waves and patches of slightly lighter and slightly darker sand, "
              "uneven and organic, nothing regular, no stripes, no sharp edges. A fine even sand grain all over, like "
              "fine speckled noise. Warm golden tan colour, low contrast, flat even lighting, orthographic view straight "
              "down, no shadows, no footprints, no plants, no objects, no text."),
    "drift_pebbles": ("Seamless tileable top-down texture of fine desert sand for a stylized video game ground. Very "
                      "soft, hazy, irregular wind-blown shading: broad blurry waves and patches of slightly lighter and "
                      "slightly darker sand, uneven and organic, no stripes, no sharp edges. A fine even sand grain all "
                      "over. A few small scattered pebbles and tiny grey-brown stones lying far apart on the sand, "
                      "sparse. Warm golden tan colour, low contrast, flat even lighting, orthographic view straight "
                      "down, no footprints, no plants, no text."),
}


# ---------------------------------------------------------------- shared

def load_rgb(path, size=SIZE):
    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return np.asarray(img).astype(np.float32) / 255.0


def save_rgb(a, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(path)


def blur_wrap(a, sigma):
    """A Gaussian blur that wraps round the tile's edges (separable, by FFT)."""
    if sigma <= 0:
        return a
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (math.pi ** 2) * (sigma ** 2) * (fx * fx + fy * fy)).astype(np.float32)
    if a.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)
    return np.stack([np.real(np.fft.ifft2(np.fft.fft2(a[..., c]) * g)) for c in range(a.shape[2])], -1).astype(np.float32)


def norm(a):
    a = a - a.mean()
    return a / max(float(a.std()), 1e-6)


def torus_noise(size, freq, octaves, seed, persistence=0.5):
    """gen_textures' value noise (integer frequencies on a torus: it wraps), normalised to mean 0, SD 1."""
    import gen_textures
    return norm(gen_textures.tileable_noise(size, octaves=octaves, base_freq=freq, persistence=persistence, seed=seed))


# ---------------------------------------------------------------- procedural parts (tileable by construction)

def proc_bands(size=SIZE, k=3, j=1, warp=0.35, warp_freq=2, asym=0.35, mod=0.4, seed=1):
    """Soft wavy dune bands: `k` bands down the tile (and `j` across, a slant), their crests moved `warp` of a band by a
    smooth torus noise, an asymmetric profile (a long lit slope, a shorter shade: `asym`), their strength varied by
    `mod` along them. Integer k, j and a torus noise: it wraps."""
    u = (np.arange(size, dtype=np.float32) / size)
    U, V = np.meshgrid(u, u)
    r = np.random.default_rng(seed)
    # one long sway along the bands, one slower across them, and a little smooth noise: wavy, never marbled
    w = (np.sin(2 * math.pi * (U + r.random())) + 0.5 * np.sin(2 * math.pi * (2 * U + V + r.random()))
         + 0.35 * torus_noise(size, warp_freq, 1, seed))
    ph = 2 * math.pi * (k * V + j * U + warp * w)
    b = np.sin(ph) + asym * np.sin(2 * ph - 0.6)
    b = norm(b)
    am = 1.0 + mod * torus_noise(size, 2, 2, seed + 7)
    return norm(b * np.clip(am, 0.15, None))


def proc_grain(size=SIZE, sigma=0.7, seed=3):
    """A fine even grain: white noise softened a hair (wrapped)."""
    r = np.random.default_rng(seed)
    return norm(blur_wrap(r.standard_normal((size, size)).astype(np.float32), sigma))


def proc_mottle(size=SIZE, freq=16, seed=5):
    """Faint mid-scale patches (a few tens of centimetres) so the grain is not machine-even."""
    return torus_noise(size, freq, 3, seed)


def pebble_layer(size=SIZE, count=34, big=7, seed=11, mean=None):
    """Sparse little pebbles: (colour RGB, alpha, shade) layers, wrapped. Each pebble a soft ellipse, a grey-brown a
    little darker than the sand, lit from the top left, with a soft contact shadow to the bottom right. Mostly tiny
    (1.5-3 px), `big` of them 4-7 px; scattered, a few in loose pairs."""
    r = np.random.default_rng(seed)
    col = np.zeros((size, size, 3), np.float32)
    alpha = np.zeros((size, size), np.float32)
    shade = np.zeros((size, size), np.float32)
    mean = np.array(mean if mean is not None else (0.84, 0.74, 0.57), np.float32)
    pts = []
    n = count + big
    while len(pts) < n:
        p = r.random(2) * size
        if all(min(abs(p[0] - q[0]), size - abs(p[0] - q[0])) ** 2 + min(abs(p[1] - q[1]), size - abs(p[1] - q[1])) ** 2 > 40 ** 2 for q in pts):
            pts.append(p)
            if r.random() < 0.3 and len(pts) < n:   # a loose pair
                pts.append((p + r.normal(0, 9, 2)) % size)
    yy, xx = np.mgrid[-12:13, -12:13].astype(np.float32)
    for i, p in enumerate(pts):
        rad = r.uniform(4.0, 7.0) if i % max(1, n // max(big, 1)) == 0 and big > 0 else r.uniform(1.4, 3.0)
        ax = rad * r.uniform(0.75, 1.0)
        ang = r.uniform(0, math.pi)
        ca, sa = math.cos(ang), math.sin(ang)
        x1 = (xx * ca + yy * sa) / rad
        y1 = (-xx * sa + yy * ca) / ax
        d = np.sqrt(x1 * x1 + y1 * y1)
        a = np.clip((1.0 - d) * rad * 0.9 + 0.5, 0, 1)                  # anti-aliased edge
        light = np.clip(1.0 - 0.45 * ((xx + rad * 0.35) ** 2 + (yy + rad * 0.35) ** 2) ** 0.5 / rad, 0.55, 1.0)
        tone = r.uniform(0.55, 0.78)
        hue = np.array([1.0, r.uniform(0.94, 0.99), r.uniform(0.86, 0.97)], np.float32)
        base = mean * tone * hue / hue.mean() * np.array([0.98, 0.98, 1.04], np.float32)
        sd = np.sqrt((xx - rad * 0.35) ** 2 + (yy - rad * 0.45) ** 2) / (rad * 1.15)
        sh = np.clip(1.0 - sd, 0, 1) ** 1.5 * 0.35
        cx, cy = int(p[0]), int(p[1])
        ys = (np.arange(cy - 12, cy + 13) % size)
        xs = (np.arange(cx - 12, cx + 13) % size)
        sub_a = alpha[np.ix_(ys, xs)]
        new_a = np.maximum(sub_a, a)
        sub_c = col[np.ix_(ys, xs)]
        col[np.ix_(ys, xs)] = sub_c * (1 - a[..., None]) + (base[None, None, :] * light[..., None]) * a[..., None]
        alpha[np.ix_(ys, xs)] = new_a
        shade[np.ix_(ys, xs)] = np.maximum(shade[np.ix_(ys, xs)], sh * (1 - a))
    return col, alpha, blur_wrap(shade, 1.2)


def compose(mean, lum_dev, warm=0.0, pebbles=None):
    """The sand at `mean` x (1 + lum_dev) (a little warmer where lighter: `warm`), pebbles over it."""
    out = mean[None, None, :] * (1.0 + lum_dev[..., None])
    if warm:
        out = out + warm * lum_dev[..., None] * np.array([0.6, 0.15, -0.75], np.float32)[None, None, :] * mean.mean()
    if pebbles is not None:
        col, alpha, shade = pebbles
        out = out * (1.0 - shade[..., None])
        out = out * (1 - alpha[..., None]) + col * alpha[..., None]
    return np.clip(out, 0, 1)


def palette_from(a, mean, band=0.055, fine=1.0, band_sigma=6.0, chroma=0.0):
    """A painting brought to the sand's colour: its luminance split into the broad shading (blurred `band_sigma` px),
    normalised to `band` of the colour per SD, and the fine rest as a ratio to it (grain and pebbles keep their own
    contrast, times `fine`), laid over `mean`; `chroma` keeps that much of the painting's local colour (its colour
    against its own blurred colour: a grey pebble stays a little grey, a broad cast never shows)."""
    lum = a @ LUMA
    lo = blur_wrap(lum, band_sigma)
    dev = band * norm(lo) + fine * (lum / np.maximum(lo, 1e-3) - 1.0)
    out = mean[None, None, :] * (1.0 + dev[..., None])
    if chroma:
        cd = a - lum[..., None]
        out = out + chroma * (cd - blur_wrap(cd, band_sigma))
    return np.clip(out, 0, 1)


# ---------------------------------------------------------------- the AI paintings

def paint(prompts, seeds):
    import comfy
    os.makedirs(AI_DIR, exist_ok=True)
    for pid in prompts:
        for seed in seeds:
            raw = os.path.join(AI_DIR, "raw_%s_s%d.png" % (pid, seed))
            if os.path.exists(raw):
                continue
            g = comfy.klein(PROMPTS[pid], seed, width=SIZE, height=SIZE, prefix="88fits/p82_sand")
            imgs, secs = comfy.run(g)
            Image.open(io.BytesIO(imgs[0])).convert("RGB").save(raw)
            print("gen_sand: %s seed %d painted in %.0f s" % (pid, seed, secs))


def cross_mask(size, half, feather):
    """1 on a cross through the middle (half-width `half` px), falling to 0 over `feather` px."""
    d = np.abs(np.arange(size, dtype=np.float32) - (size - 1) / 2.0)
    t = np.clip((half + feather - d) / max(feather, 1e-6), 0, 1)
    t = t * t * (3 - 2 * t)
    return np.maximum(t[:, None], t[None, :])


def seam_graph(image_name, mask_name, prompt, seed, steps=12):
    import comfy
    g = comfy.Graph()
    m = g.add("UNETLoader", "Flux.2 Klein 9B", unet_name=comfy.KLEIN_UNET, weight_dtype="default")
    # differential diffusion: the grey mask says how early each pixel may change (the seam from the first step, the
    # cross's edges only in the last), so the repainted cross grows out of the painting round it
    m = g.add("DifferentialDiffusion", model=(m, 0), strength=1.0)
    c = g.add("CLIPLoader", "Qwen3 8B text encoder", clip_name=comfy.KLEIN_CLIP, type="flux2", device="default")
    v = g.add("VAELoader", vae_name=comfy.VAE)
    pos = g.add("CLIPTextEncode", "prompt", clip=(c, 0), text=prompt)
    neg = g.add("ConditioningZeroOut", conditioning=(pos, 0))
    li = g.add("LoadImage", "the painting rolled half a tile", image=image_name)
    lm = g.add("LoadImage", "the seam cross", image=mask_name)
    mk = g.add("ImageToMask", image=(lm, 0), channel="red")
    enc = g.add("VAEEncode", pixels=(li, 0), vae=(v, 0))
    lat = g.add("SetLatentNoiseMask", samples=(enc, 0), mask=(mk, 0))
    guider = g.add("CFGGuider", model=(m, 0), positive=(pos, 0), negative=(neg, 0), cfg=1.0)
    sampler = g.add("KSamplerSelect", sampler_name="euler")
    sig = g.add("Flux2Scheduler", steps=steps, width=SIZE, height=SIZE)
    noise = g.add("RandomNoise", noise_seed=seed)
    out = g.add("SamplerCustomAdvanced", noise=(noise, 0), guider=(guider, 0), sampler=(sampler, 0), sigmas=(sig, 0), latent_image=(lat, 0))
    dec = g.add("VAEDecode", samples=(out, 0), vae=(v, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix="88fits/p82_sand_seam")
    return g


def edge_taper(size, keep=40, ramp=160):
    """0 within `keep` px of either edge, rising to 1 over `ramp` px."""
    k = np.arange(size, dtype=np.float32)
    t = np.clip((np.minimum(k, size - 1 - k) - keep) / ramp, 0, 1)
    return t * t * (3 - 2 * t)


def mid_window(size, half=260, ramp=120):
    """1 within `half` px of the middle, falling to 0 over `ramp` px."""
    d = np.abs(np.arange(size, dtype=np.float32) - (size - 1) / 2.0)
    t = np.clip((half + ramp - d) / ramp, 0, 1)
    return t * t * (3 - 2 * t)


def inpaint(img, mask, prompt, seed, fix_path, tag):
    """`img` painted again where `mask` says (differential diffusion), composited back (seam_composite). The model's raw
    output is kept at `fix_path` (reused unless --force)."""
    import comfy
    if os.path.exists(fix_path) and "--force" not in sys.argv:
        secs = 0.0
    else:
        img_name = comfy.upload_pil(Image.fromarray((img * 255 + 0.5).astype(np.uint8)), "p82_sand_%s.png" % tag)
        mask_name = comfy.upload_pil(Image.fromarray((mask * 255 + 0.5).astype(np.uint8)).convert("RGB"), "p82_sand_%s_mask.png" % tag)
        imgs, secs = comfy.run(seam_graph(img_name, mask_name, prompt, seed))
        Image.open(io.BytesIO(imgs[0])).convert("RGB").save(fix_path)
    print("gen_sand: %s in %.0f s" % (tag, secs))
    return seam_composite(img, load_rgb(fix_path), mask)


def seam_inpaint(raw_path, out_path, prompt, seed, half=24, feather=232):
    """Tileable in three repaints, every one off the tile's edges (a repaint that reached an edge would break the wrap):
      A: the painting rolled half a tile (its new edges wrap: they were neighbours); the cross where its old edges meet
         painted again, fully at the seam and less and less out to `half` + `feather` px (differential diffusion), its
         arms stopping short of the edges;
      B: rolled half a tile down, the vertical seam's two ends (now in the middle) painted the same way;
      C: rolled half a tile across, the horizontal seam's two ends.
    Every repaint is brought to the painting's colour and light before it is blended in (seam_composite)."""
    a = load_rgb(raw_path)
    name = os.path.splitext(os.path.basename(raw_path))[0][4:]
    d = os.path.dirname(out_path)
    across = np.clip((half + feather - np.abs(np.arange(SIZE, dtype=np.float32) - (SIZE - 1) / 2.0)) / feather, 0, 1)
    across = across * across * (3 - 2 * across)
    taper = edge_taper(SIZE)
    window = mid_window(SIZE)
    h = SIZE // 2
    img = np.roll(np.roll(a, h, axis=0), h, axis=1)
    mask_a = np.maximum(across[None, :] * taper[:, None], across[:, None] * taper[None, :])
    img = inpaint(img, mask_a, prompt, seed, os.path.join(d, "fixA_%s.png" % name), name + "_A")
    img = np.roll(img, h, axis=0)
    img = inpaint(img, across[None, :] * window[:, None], prompt, seed + 1, os.path.join(d, "fixB_%s.png" % name), name + "_B")
    img = np.roll(np.roll(img, -h, axis=0), h, axis=1)
    img = inpaint(img, across[:, None] * window[None, :], prompt, seed + 2, os.path.join(d, "fixC_%s.png" % name), name + "_C")
    img = np.roll(img, -h, axis=1)
    save_rgb(img, out_path)
    print("gen_sand: %s tileable -> %s" % (name, out_path))
    return img


def seam_composite(rolled, fixed, m_lat):
    """The repainted cross over the rolled painting: the model's output first brought to the painting's colour and light
    (it repaints with a slightly different cast: the mean difference over the ring the mask barely touched, then a
    smooth map of what is left of it), then blended by the mask itself (the cross's edges, which the model only
    retouched, fade out over its whole feather)."""
    ring = (m_lat > 0.02) & (m_lat < 0.35)
    fixed = fixed + (rolled[ring].mean(0) - fixed[ring].mean(0))[None, None, :]
    # what is left of the cast where the model kept the painting's shapes (low mask), smoothed, eased towards the seam
    diff = blur_wrap((rolled - fixed) * (m_lat < 0.5)[..., None], 48) / np.maximum(blur_wrap((m_lat < 0.5).astype(np.float32), 48), 1e-3)[..., None]
    fixed = fixed + diff * (1.0 - m_lat)[..., None]
    m = m_lat[..., None]
    return rolled * (1 - m) + fixed * m


# ---------------------------------------------------------------- candidates (tools/dl/p82/SAND/cands + a list for the shots)

def today_mean():
    """The mean colour of today's sand (art/env/sand.png): every new sand is laid over exactly this."""
    return load_rgb(os.path.join(ENV, "sand.png")).reshape(-1, 3).mean(0).astype(np.float32)


def at_mean(out, mean):
    """`out` moved so its mean is exactly `mean` (after clipping and pebbles)."""
    return np.clip(out + (mean - out.reshape(-1, 3).mean(0))[None, None, :], 0, 1)


def make_ai(tile_path, mean, band=0.055, fine=1.0, band_sigma=6.0, chroma=0.0):
    return at_mean(palette_from(load_rgb(tile_path), mean, band=band, fine=fine, band_sigma=band_sigma, chroma=chroma), mean)


def make_proc(mean, k=3, j=1, warp=0.12, asym=0.35, mod=0.35, band=0.05, grain=0.012, mottle=0.008, soft=4.0,
              pebbles=False, seed=21):
    b = norm(blur_wrap(proc_bands(k=k, j=j, warp=warp, asym=asym, mod=mod, seed=seed), soft))
    dev = band * b + grain * proc_grain() + mottle * proc_mottle()
    return at_mean(compose(mean, dev, pebbles=pebble_layer(mean=mean) if pebbles else None), mean)


def build_cands(only=None, band=0.055, fine=1.0, chroma=0.5, scale=1.0, tag="", proc=True):
    """Every AI tile and two procedural tries as candidates, plus today's, and the list the shots tool reads."""
    os.makedirs(CAND_DIR, exist_ok=True)
    mean = today_mean()
    lines = ["today today 1.0"]
    tiles = sorted(f for f in os.listdir(AI_DIR) if f.startswith("tile_")) if os.path.isdir(AI_DIR) else []
    for f in tiles:
        stem = f[5:-4]
        if only and stem not in only:
            continue
        name = "ai_" + stem + tag
        out = make_ai(os.path.join(AI_DIR, f), mean, band=band, fine=fine, chroma=chroma if "pebbles" in stem else 0.0)
        path = os.path.join(CAND_DIR, name + ".png")
        save_rgb(out, path)
        lines.append("%s %s %.4f" % (name, path.replace("\\", "/"), scale))
    if proc and not only:
        for name, kw in (("proc_bands3", {}), ("proc_bands3_peb", {"pebbles": True}), ("proc_bands2", {"k": 2, "warp": 0.15, "asym": 0.4, "mod": 0.45})):
            path = os.path.join(CAND_DIR, name + ".png")
            save_rgb(make_proc(mean, **kw), path)
            lines.append("%s %s 1.0" % (name, path.replace("\\", "/")))
    lst = os.path.join(WORK, "cands%s.txt" % tag)
    with open(lst, "w", encoding="utf-8", newline=chr(10)) as fh:
        fh.write(chr(10).join(lines) + chr(10))
    print("gen_sand: %d candidates, list %s" % (len(lines), lst))


# ---------------------------------------------------------------- the four sands the game ships (RedCanyon.SANDS)
# Each from one Klein painting (PROMPTS[prompt], seed), made tileable by seam_inpaint (its repaints' seeds are seed + 500,
# +501, +502) and kept as tools/art_src/sand_<id>_src.png; written at today's mean colour by palette_from with the
# recipe's band (the broad shading, of the colour per SD), fine (the grain's and the pebbles' own contrast) and chroma
# (a pebble's own colour).
# Picked by eye in the game at phone size from 16 paintings (4 seeds of each prompt; tools/dl/p82/SAND/g1-g4 sheets);
# RedCanyon.SANDS sets each one's size on the ground (dunes 0.8: its bands a little broader, like the reference's).
SANDS = {
    "dunes": {"prompt": "dunes", "seed": 8201, "band": 0.055, "fine": 0.7, "chroma": 0.0},
    "dunes_pebbles": {"prompt": "pebbles", "seed": 8201, "band": 0.055, "fine": 0.7, "chroma": 0.5},
    "ripples": {"prompt": "drift", "seed": 8203, "band": 0.055, "fine": 0.7, "chroma": 0.0},
    "ripples_pebbles": {"prompt": "drift_pebbles", "seed": 8202, "band": 0.055, "fine": 0.7, "chroma": 0.5},
}


def src_path(sid):
    return os.path.join(ART_SRC, "sand_%s_src.png" % sid)


def keep_sources(ids):
    """The chosen tileable paintings copied from the work folder into tools/art_src (the files the game's sands are made
    from, kept in the repo)."""
    import shutil
    for sid in ids:
        r = SANDS[sid]
        tile = os.path.join(AI_DIR, "tile_%s_s%d.png" % (r["prompt"], r["seed"]))
        shutil.copyfile(tile, src_path(sid))
        print("gen_sand: kept %s -> %s" % (tile, src_path(sid)))


def write(ids):
    mean = today_mean()
    for sid in ids:
        r = SANDS[sid]
        out = make_ai(src_path(sid), mean, band=r["band"], fine=r["fine"], chroma=r["chroma"])
        path = os.path.join(ENV, "sand_%s.png" % sid)
        save_rgb(out, path)
        print("gen_sand: wrote %s (mean %s)" % (path, np.round(out.reshape(-1, 3).mean(0) * 255, 1)))


def previews(shots_dir):
    """The Level Editor's previews (tools/level_editor/sand_previews.png): the hero on open sand, 300 px a sand, side by
    side in the order of its Sand row (pass81 first, then SANDS), from the shots of game/tools/_p82_SAND_shots.gd
    (spots=sand, one candidate a sand named by its id, the 864x1920 phone canvas)."""
    ids = ["pass81"] + list(SANDS)
    strip = Image.new("RGB", (300 * len(ids), 300))
    for k, sid in enumerate(ids):
        im = Image.open(os.path.join(shots_dir, "sand_%s.png" % sid)).convert("RGB")
        strip.paste(im.crop((32, 640, 832, 1440)).resize((300, 300), Image.LANCZOS), (300 * k, 0))
    out = os.path.join(TOOLS, "level_editor", "sand_previews.png")
    strip.save(out, optimize=True)
    print("gen_sand: previews -> %s" % out)


# ---------------------------------------------------------------- main

def main():
    args = sys.argv[1:]

    def opt(name, default=None):
        for k, v in enumerate(args):
            if v == name and k + 1 < len(args):
                return args[k + 1]
            if v.startswith(name + "="):
                return v.split("=", 1)[1]
        return default

    if "--paint" in args:
        prompts = (opt("--prompts", "dunes,pebbles")).split(",")
        seeds = [int(s) for s in opt("--seeds", "8201,8202,8203,8204").split(",")]
        paint(prompts, seeds)
        return
    if "--cands" in args:
        only = opt("--only")
        build_cands(only=only.split(",") if only else None, band=float(opt("--band", "0.055")), fine=float(opt("--fine", "1.0")),
                    chroma=float(opt("--chroma", "0.5")), scale=float(opt("--scale", "1.0")), tag=opt("--tag", ""), proc="--no-proc" not in args)
        return
    if "--previews" in args:
        previews(opt("--previews"))
        return
    if "--keep" in args:
        only = opt("--only")
        keep_sources(only.split(",") if only else list(SANDS))
        return
    if "--seam" in args:
        only = opt("--only")
        names = sorted(f for f in os.listdir(AI_DIR) if f.startswith("raw_") and f.endswith(".png"))
        for f in names:
            stem = f[4:-4]
            if only and stem not in only.split(","):
                continue
            out = os.path.join(AI_DIR, "tile_%s.png" % stem)
            if os.path.exists(out) and "--force" not in args:
                continue
            pid = stem.rsplit("_s", 1)[0]
            seed = int(stem.rsplit("_s", 1)[1])
            seam_inpaint(os.path.join(AI_DIR, f), out, PROMPTS.get(pid, PROMPTS["dunes"]), seed + 500)
        return
    only = opt("--only")
    write(only.split(",") if only else list(SANDS))


if __name__ == "__main__":
    main()
