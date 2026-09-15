"""Image helpers for the 88fits art pipeline: chroma keying, cleanup, outline, framing, procedural frames, strips.

Pure PIL + numpy (scipy optional, for connected-component cleanup). No ComfyUI here; see tools/comfy.py.
"""
import colorsys
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance


# ---------------------------------------------------------------- keying

def key_background(img, despill=0.09, despill_mix=0.45):
    """RGB render on a flat green/cyan/blue screen -> RGBA with the screen removed.

    The screen colour is sampled from the top edge (Flux likes to paint a ground plane along the bottom),
    keyed by hue distance, then: stray blobs are dropped, ground-shadow lines in the bottom 20% of the figure are
    cut, edges are despilled and sharpened."""
    arr = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    h, w, _ = arr.shape
    edge = np.concatenate([arr[:24, :, :].reshape(-1, 3), arr[:h // 2, :24].reshape(-1, 3), arr[:h // 2, -24:].reshape(-1, 3)])
    bg = np.median(edge, axis=0)
    bh, bs, bv = colorsys.rgb_to_hsv(*bg)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    mx = arr.max(axis=2)
    mn = arr.min(axis=2)
    delta = mx - mn + 1e-6
    sat = np.where(mx > 0, delta / (mx + 1e-6), 0)
    hue = np.zeros_like(mx)
    m = mx == r
    hue[m] = ((g - b) / delta)[m] % 6
    m = mx == g
    hue[m] = ((b - r) / delta)[m] + 2
    m = mx == b
    hue[m] = ((r - g) / delta)[m] + 4
    hue = hue / 6.0
    dh = np.abs(hue - bh)
    dh = np.minimum(dh, 1.0 - dh)
    is_bg = (dh < 0.05) & (sat > 0.35) & (mx > 0.2)
    is_bg |= np.linalg.norm(arr - bg[None, None, :], axis=2) < 0.12
    alpha = (~is_bg).astype(np.float32)
    alpha = keep_main_components(alpha)
    ys = np.nonzero(alpha.max(axis=1) > 0.5)[0]
    if len(ys) > 0:
        # only the thin sliver where a cast shadow overlaps the feet, and only pixels close to the screen hue:
        # olive trousers and brown boots must survive (they did not, once, and the hero lost his legs)
        y_lo = int(ys.max() - (ys.max() - ys.min()) * 0.12)
        streak = np.zeros_like(alpha, dtype=bool)
        streak[y_lo:, :] = (dh[y_lo:, :] < 0.11) & (sat[y_lo:, :] > 0.18) & (mx[y_lo:, :] > 0.3)
        streak[y_lo:, :] |= (dh[y_lo:, :] < 0.11) & (sat[y_lo:, :] > 0.3) & (mx[y_lo:, :] > 0.08) & (mx[y_lo:, :] < 0.5)
        alpha[streak] = 0.0
        alpha = keep_main_components(alpha)
    a_img = Image.fromarray((alpha * 255).astype(np.uint8))
    a_img = a_img.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.6))
    alpha = np.asarray(a_img).astype(np.float32) / 255.0
    edge_px = (alpha > 0.05) & (alpha < 0.95)
    rgb = arr.copy()
    rgb[edge_px] = np.clip((rgb[edge_px] - bg[None, :] * (1 - alpha[edge_px])[:, None]) / np.maximum(alpha[edge_px][:, None], 0.2), 0, 1)
    # despill: pull the screen hue out of pixels that lean towards it (rim light bleed)
    spill = (dh < despill) & (sat > 0.2) & (alpha > 0.5)
    if spill.any():
        grey = rgb[spill].mean(axis=1, keepdims=True)
        rgb[spill] = rgb[spill] * (1.0 - despill_mix) + grey * despill_mix
    out = np.concatenate([rgb, alpha[..., None]], axis=2)
    res = Image.fromarray((out * 255).astype(np.uint8), "RGBA")
    return res.filter(ImageFilter.UnsharpMask(radius=1.4, percent=60, threshold=2))


def keep_main_components(alpha, keep_ratio=0.02):
    """Drop connected alpha blobs smaller than keep_ratio of the largest one."""
    mask = alpha > 0.5
    try:
        from scipy import ndimage
    except ImportError:
        return alpha
    labels, n = ndimage.label(mask)
    if n <= 1:
        return alpha
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    biggest = sizes.max()
    keep = np.zeros(n + 1, dtype=bool)
    for i, sz in enumerate(sizes, start=1):
        keep[i] = sz >= biggest * keep_ratio
    out = alpha.copy()
    out[~keep[labels]] = 0.0
    return out


def crop_alpha(img, pad=6):
    a = np.asarray(img)[..., 3]
    ys, xs = np.nonzero(a > 40)
    if len(xs) == 0:
        return img
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad, img.width - 1)
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad, img.height - 1)
    return img.crop((x0, y0, x1 + 1, y1 + 1))


# ---------------------------------------------------------------- readability

def punch(img, contrast=1.06, saturation=1.08):
    """Small contrast and saturation lift so sprites hold up on sandy ground."""
    rgb = img.convert("RGB")
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    out = rgb.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out


def add_outline(img, px, color=(38, 24, 30, 255)):
    """Dark outline around the silhouette (px wide). Makes small sprites read against busy ground."""
    if px <= 0:
        return img
    a = img.getchannel("A").filter(ImageFilter.MaxFilter(2 * px + 1))
    line = Image.new("RGBA", img.size, color)
    line.putalpha(a)
    line.alpha_composite(img)
    return line


# ---------------------------------------------------------------- framing

def fit_cell(img, cell, fill=0.86, bottom=True, scale=None, pad_bottom=0.06):
    """Scale the cropped sprite into a square cell. Returns (canvas, scale) so sibling frames can share a scale."""
    img = crop_alpha(img)
    if scale is None:
        scale = min(cell * fill / img.width, cell * fill / img.height)
    w, h = max(1, int(round(img.width * scale))), max(1, int(round(img.height * scale)))
    if w > cell or h > cell:
        s2 = min(cell / img.width, cell / img.height)
        w, h = max(1, int(img.width * s2)), max(1, int(img.height * s2))
    small = img.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    x = (cell - w) // 2
    y = cell - int(cell * pad_bottom) - h if bottom else (cell - h) // 2
    canvas.alpha_composite(small, (x, max(y, 0)))
    return canvas, scale


def transform(cell_img, lean_deg=0.0, bob=0.0, sx=1.0, sy=1.0, tint=None, rotate=0.0, flip=False):
    """Procedural frame from a cell: lean/rotate around the feet, bob up, squash, tint, mirror."""
    cell = cell_img.width
    img = cell_img
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    if sx != 1.0 or sy != 1.0:
        w, h = int(cell * sx), int(cell * sy)
        scaled = img.resize((w, h), Image.LANCZOS)
        canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        canvas.alpha_composite(scaled, ((cell - w) // 2, cell - h))
        img = canvas
    if lean_deg or rotate:
        img = img.rotate(lean_deg + rotate, resample=Image.BICUBIC, center=(cell / 2, cell * 0.94), expand=False)
    if bob:
        canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        canvas.alpha_composite(img, (0, -int(bob)))
        img = canvas
    if tint:
        arr = np.asarray(img).astype(np.float32)
        col = np.array(tint, np.float32)
        arr[..., :3] = arr[..., :3] * 0.4 + col[None, None, :] * 0.6
        img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    return img


ENEMY_ORDER = ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
CHAR_ORDER = ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]


def place_clip_frames(frames, cell, scale, outline_px=0, outline_color=(38, 24, 30, 255), pad_bottom=0.06):
    """Video-cycle frames share one crop box, so pasting them with one scale at the cell floor keeps the bounce."""
    out = []
    for f in frames:
        w, h = max(1, int(round(f.width * scale))), max(1, int(round(f.height * scale)))
        if w > cell or h > cell:
            s2 = min(cell / f.width, cell / f.height)
            w, h = max(1, int(f.width * s2)), max(1, int(f.height * s2))
        small = f.resize((w, h), Image.LANCZOS)
        canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        canvas.alpha_composite(small, ((cell - w) // 2, max(0, cell - int(cell * pad_bottom) - h)))
        out.append(add_outline(punch(canvas), outline_px, outline_color) if outline_px else canvas)
    return out


def idle_frames(stand, cell):
    b = cell / 128.0
    return [stand, transform(stand, bob=1 * b, sy=0.992, sx=1.004), transform(stand, bob=2 * b, sy=0.985, sx=1.008), transform(stand, bob=1 * b, sy=0.992, sx=1.004)]


def enemy_frames(base, cell, run=None, back=None, run_b=None, views=None):
    """idle 4, run (8 video frames, or a 6-frame walk from the painting), attack 2, hit 1, die 1, then the back set."""
    b = cell / 128.0
    frames = _enemy_front_frames(base, cell)
    if run:
        frames["run"] = run
    if back is not None:
        frames["run_b"] = run_b if run_b else [transform(back, lean_deg=6, bob=3 * b), transform(back, lean_deg=3, bob=6 * b), transform(back, bob=2 * b),
                                               transform(back, lean_deg=-6, bob=3 * b), transform(back, lean_deg=-3, bob=6 * b), transform(back, bob=2 * b)]
        frames["idle_b"] = idle_frames(back, cell)
    # eight-direction creatures: side, back-diagonal and front-diagonal sets ({"_s": (stand, run_frames), ...})
    for suffix, (stand, run_list) in (views or {}).items():
        if stand is None:
            continue
        frames["idle" + suffix] = idle_frames(stand, cell)
        frames["run" + suffix] = list(run_list) if run_list else [transform(stand, lean_deg=6, bob=3 * b), transform(stand, lean_deg=3, bob=6 * b), transform(stand, bob=2 * b),
                                                                    transform(stand, lean_deg=-6, bob=3 * b), transform(stand, lean_deg=-3, bob=6 * b), transform(stand, bob=2 * b)]
    return frames


def _enemy_front_frames(base, cell):
    b = cell / 128.0
    return {
        "idle": [base, transform(base, bob=2 * b, sy=0.985, sx=1.01), transform(base, bob=3 * b, sy=0.97, sx=1.02), transform(base, bob=1 * b, sy=0.99, sx=1.005)],
        # a walk cycle: lean right, up, centre, lean left, up, centre - six frames from one painting
        "run": [transform(base, lean_deg=6, bob=3 * b, sy=0.98, sx=1.02), transform(base, lean_deg=3, bob=6 * b), transform(base, lean_deg=0, bob=2 * b),
                transform(base, lean_deg=-6, bob=3 * b, sy=0.98, sx=1.02), transform(base, lean_deg=-3, bob=6 * b), transform(base, lean_deg=0, bob=2 * b)],
        "attack": [transform(base, lean_deg=12, sy=0.92, sx=1.06), transform(base, lean_deg=-14, sy=1.06, sx=0.97, bob=3 * b)],
        "hit": [transform(base, sy=0.9, sx=1.08, tint=(255, 255, 255))],
        "die": [fall(base, 75)],
    }


def _view_frames(stand, runs, cell):
    """idle 4 + run 6 for one view from a standing cell and six rendered stride cells (any may be None):
    contact left, flight left, pass left, contact right, flight right, pass right."""
    b = cell / 128.0
    runs = list(runs) if runs else [None] * 6
    while len(runs) < 6:
        runs.append(None)
    fallback = [transform(stand, lean_deg=4), transform(stand, bob=5 * b, sy=0.99), transform(stand, sy=0.985),
                transform(stand, lean_deg=-4), transform(stand, bob=5 * b, sy=0.99), transform(stand, sy=0.985)]
    cells = [runs[k] if runs[k] is not None else fallback[k] for k in range(6)]
    bobs = [1 * b, 7 * b, 3 * b, 1 * b, 7 * b, 3 * b]
    idle = [stand, transform(stand, bob=1 * b, sy=0.992, sx=1.004), transform(stand, bob=2 * b, sy=0.985, sx=1.008), transform(stand, bob=1 * b, sy=0.992, sx=1.004)]
    run = [transform(cells[k], bob=bobs[k]) for k in range(6)]
    return idle, run


def character_frames(back, runs, cheer, cell, front=None, front_runs=None, side=None, side_runs=None, bd=None, bd_runs=None, fd=None, fd_runs=None, hits=None):
    """Hero strip: back view idle 4 / run, hit 1, die 1, cheer 1, then front, side, back-diagonal and front-diagonal
    views (idle 4 / run each) when their cells are given. A `runs` list that is a full cycle (video frames) is used as is;
    a list of up to six stride cells is packed the old way. Views are picked in game from the direction of travel."""
    b = cell / 128.0

    def view(stand, run_list):
        if run_list and len(run_list) >= 7 and all(r is not None for r in run_list):
            return idle_frames(stand, cell), list(run_list)
        return _view_frames(stand, run_list, cell)

    idle_b, run_b = view(back, runs)
    cheer_f = cheer if cheer is not None else transform(back, bob=9 * b, sy=1.06, sx=0.98)
    frames = {
        "idle": idle_b,
        "run": run_b,
        "turn": [],
        "hit": [transform(back, sy=0.92, sx=1.06, tint=(255, 255, 255))],
        "die": [fall(back, 80)],
        "cheer": [cheer_f],
    }
    for suffix, stand, run_list in (("_f", front, front_runs), ("_s", side, side_runs), ("_bd", bd, bd_runs), ("_fd", fd, fd_runs)):
        if stand is not None:
            frames["idle" + suffix], frames["run" + suffix] = view(stand, run_list)
    # hit reactions per view (pose-driven one-shots); a missing view keeps the single squashed frame / falls back in game
    for suffix, clip in (hits or {}).items():
        if clip:
            frames["hit" + suffix] = list(clip)
    return frames


def fall(cell_img, deg=80):
    """Death frame: the sprite tips over and is refitted so nothing leaves the cell."""
    cell = cell_img.width
    rot = cell_img.rotate(deg, resample=Image.BICUBIC, expand=True)
    out, _ = fit_cell(rot, cell, 0.8, True)
    return out


def pack_strip(frames, order, cell, max_width=16000):
    """Packs the frames in `order` into a grid: one row while it fits in max_width, more rows beyond (GPUs and WebP
    stop at 16k px). Returns (image, counts, cols); the game reads frame k at column k % cols, row k // cols."""
    seq = []
    for anim in order:
        seq.extend(frames.get(anim, []))
    n = max(1, len(seq))
    cols = max(1, min(n, max_width // cell))
    rows = (n + cols - 1) // cols
    strip = Image.new("RGBA", (cell * cols, cell * rows), (0, 0, 0, 0))
    for k, f in enumerate(seq):
        strip.alpha_composite(f, ((k % cols) * cell, (k // cols) * cell))
    return strip, {anim: len(frames.get(anim, [])) for anim in order if len(frames.get(anim, [])) > 0}, cols


# ---------------------------------------------------------------- review sheets

def contact_sheet(images, cols, cell, bg=(40, 40, 48, 255), labels=None):
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), bg)
    for i, im in enumerate(images):
        t = im.convert("RGBA").copy()
        t.thumbnail((cell - 8, cell - 8))
        sheet.alpha_composite(t, ((i % cols) * cell + (cell - t.width) // 2, (i // cols) * cell + (cell - t.height) // 2))
    return sheet
