"""Image helpers for the 88fits art pipeline: chroma keying, cleanup, outline, framing, procedural frames, strips.

Pure PIL + numpy (scipy optional, for connected-component cleanup). No ComfyUI here; see tools/comfy.py.
"""
import colorsys
import math
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance


# ---------------------------------------------------------------- keying

def key_background(img, despill=0.09, despill_mix=0.45, cut_shadow=None):
    """RGB render on a flat green/cyan/blue screen -> RGBA with the screen removed.

    The screen colour is sampled from the top edge (Flux likes to paint a ground plane along the bottom),
    keyed by hue distance, then: stray blobs are dropped, ground-shadow lines in the bottom 20% of the figure are
    cut, edges are despilled and sharpened. `cut_shadow` False keeps the bottom whole (pass 49: a structure's stone
    plinth, shaded with the screen's tint, lost its corner to the shadow cut). Left as None it follows KEY_CUT_SHADOW.
    KEY_MIN_V, KEY_CUT_SHADOW and KEY_CLAMP_SCREEN (pass 54, Solenne's glossy black catsuit) let a figure keep the screen's
    colour where it only reflects it: a screen-hued pixel darker than KEY_MIN_V is figure, not screen (a high KEY_SAT
    keeps the paler highlights too), and with KEY_CLAMP_SCREEN the edges are not unmixed (a black figure's edge came out
    magenta) and the screen's channel is held down to the other two in every figure pixel, so a reflection turns to grey shine."""
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
    if cut_shadow is None:
        cut_shadow = KEY_CUT_SHADOW
    is_bg = (dh < 0.05) & (sat > KEY_SAT) & (mx > KEY_MIN_V)
    is_bg |= np.linalg.norm(arr - bg[None, None, :], axis=2) < 0.12
    alpha = (~is_bg).astype(np.float32)
    alpha = keep_main_components(alpha)
    ys = np.nonzero(alpha.max(axis=1) > 0.5)[0]
    if len(ys) > 0 and cut_shadow and figure_wears_screen(alpha, dh, sat, mx, ys):
        # pass 91 (the Cactus Walker's black line): a figure whose own body is the screen's hue (a green cactus on the
        # green screen) would lose the bottom of its body to the shadow cut below, the ink lines staying behind as a
        # dark band the outline then fills in; no cut for such a figure (a cast shadow on it is the lesser evil)
        cut_shadow = False
    if len(ys) > 0 and cut_shadow:
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
    if not KEY_CLAMP_SCREEN:
        rgb[edge_px] = np.clip((rgb[edge_px] - bg[None, :] * (1 - alpha[edge_px])[:, None]) / np.maximum(alpha[edge_px][:, None], 0.2), 0, 1)
    # despill: pull the screen hue out of pixels that lean towards it (rim light bleed)
    spill = (dh < despill) & (sat > 0.2) & (alpha > 0.5)
    if spill.any():
        grey = rgb[spill].mean(axis=1, keepdims=True)
        rgb[spill] = rgb[spill] * (1.0 - despill_mix) + grey * despill_mix
    if KEY_CLAMP_SCREEN:
        # pass 54: glossy black latex reflects the screen; in a figure with none of the screen's colour every pixel has the
        # screen's channel (green or blue) held down to the larger of the other two, so a reflection becomes grey shine
        # and the screen's bleed on the edges goes dark
        c = int(np.argmax(bg))
        others = [k for k in range(3) if k != c]
        ch = rgb[..., c]
        cap = np.maximum(rgb[..., others[0]], rgb[..., others[1]])
        fig = alpha > 0.02
        rgb[..., c] = np.where(fig & (ch > cap), cap, ch)
    if GRADE:
        # the item's grade, on the figure only, after the screen is gone: a blue-grey garment on a blue screen can only be
        # keyed while it is grey; it becomes a real colour here and stays one in every still and frame
        rgb = grade_array(rgb, tuple(GRADE.get("hue", (0.5, 0.72))), float(GRADE.get("sat_mul", 1.8)), tuple(GRADE.get("sat_range", (0.04, 0.45))),
                          float(GRADE.get("hue_shift", 0.0)), float(GRADE.get("sat_max", 0.6)), alpha > 0.05, GRADE.get("grey"))
    out = np.concatenate([rgb, alpha[..., None]], axis=2)
    res = Image.fromarray((out * 255).astype(np.uint8), "RGBA")
    return res.filter(ImageFilter.UnsharpMask(radius=1.4, percent=60, threshold=2))


WEARS_SCREEN_SHARE = 0.04   # pass 91: the share of a figure's upper body in the shadow cut's colours that turns the cut off


def figure_wears_screen(alpha, dh, sat, mx, ys=None):
    """Pass 91: True when the figure itself is painted in the shadow cut's colours (near the screen's hue, saturated, not
    dark): more than WEARS_SCREEN_SHARE of its opaque pixels above the bottom band. The cut is then turned off: it was
    made for a cast shadow under feet, and on a green creature on the green screen it ate the creature's lower body
    (the ink lines stayed and became a black line at the bottom of every frame)."""
    if ys is None:
        ys = np.nonzero(alpha.max(axis=1) > 0.5)[0]
    if not len(ys):
        return False
    y_lo = int(ys.max() - (ys.max() - ys.min()) * 0.12)
    fig = alpha[:y_lo] > 0.5
    n = int(fig.sum())
    if n == 0:
        return False
    tinted = fig & (dh[:y_lo] < 0.11) & (sat[:y_lo] > 0.18) & (mx[:y_lo] > 0.3)
    return float(tinted.sum()) / n > WEARS_SCREEN_SHARE


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


def _rgb_to_hsv(arr):
    mx = arr.max(axis=2)
    mn = arr.min(axis=2)
    delta = mx - mn + 1e-6
    sat = np.where(mx > 0, delta / (mx + 1e-6), 0)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    h = np.zeros_like(mx)
    m = mx == r
    h[m] = ((g - b) / delta)[m] % 6
    m = mx == g
    h[m] = ((b - r) / delta)[m] + 2
    m = mx == b
    h[m] = ((r - g) / delta)[m] + 4
    return (h / 6.0) % 1.0, sat, mx


def _hsv_to_rgb(h, s, v):
    i = np.floor(h * 6.0).astype(int) % 6
    f = h * 6.0 - np.floor(h * 6.0)
    p = v * (1.0 - s)
    q = v * (1.0 - s * f)
    t = v * (1.0 - s * (1.0 - f))
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], axis=2)


GRADE = None    # the current item's "grade" block (see grade()): applied inside key_background, after the screen is gone
KEY_MIN_V = 0.2       # pass 54: a screen-hued pixel must be at least this bright to count as screen (JSON "key_min_value"):
                      # Solenne's glossy black boots reflect the screen at 0.3-0.7 while the screen itself is 0.98+
KEY_CUT_SHADOW = True  # pass 54: the cut of a cast shadow round the feet (JSON "key_cut_shadow"); a Wan clip has no shadow
KEY_CLAMP_SCREEN = False  # pass 54: the figure has none of the screen's colour (JSON "key_clamp_screen"): every trace of it is
                          # a reflection, held down to the pixel's other two channels (gen_ctl's no-green clamp, for any screen)
KEY_SAT = 0.35  # how saturated a screen-hued pixel must be to count as screen; an item whose garment shares the screen's
                # hue raises it (JSON "key_sat"): Mira's front still had denim at 0.4-0.48 and lost its overalls at 0.35


def grade_array(arr, hue=(0.5, 0.72), sat_mul=1.8, sat_range=(0.04, 0.45), hue_shift=0.0, sat_max=0.6, mask=None, grey=None):
    """grade() on a float RGB array, limited to `mask` when given. `grey` = {sat_below, value: [lo, hi], hue, sat} also
    paints the neutral mid-greys (a garment the image model painted grey to keep it apart from the screen) in that hue
    at that saturation. Returns a new array."""
    h, s, v = _rgb_to_hsv(arr)
    sel = (h >= hue[0]) & (h <= hue[1]) & (s >= sat_range[0]) & (s <= sat_range[1]) & (v > 0.08)
    if mask is not None:
        sel &= mask
    s2 = np.where(sel, np.minimum(s * sat_mul, sat_max), s)
    h2 = np.where(sel, (h + hue_shift) % 1.0, h)
    if grey:
        vr = grey.get("value", (0.2, 0.72))
        g = (s < float(grey.get("sat_below", 0.06))) & (v >= vr[0]) & (v <= vr[1])
        if mask is not None:
            g &= mask
        s2 = np.where(g, float(grey.get("sat", 0.45)), s2)
        h2 = np.where(g, float(grey.get("hue", 0.6)), h2)
        sel |= g
    if not sel.any():
        return arr
    out = _hsv_to_rgb(h2, s2, v)
    return np.clip(np.where(sel[..., None], out, arr), 0, 1)


def remap_hues(img, ranges, to_hue, sat_mult=0.55, min_sat=0.16, max_sat=1.01):
    """Colour the video model smeared in that the painting does not have, put back into the figure's own hue (pass 46:
    Ironwood's fringed buckskin left green and magenta streaks on the moving legs, keying residue of the motion blur).
    `ranges` are hue intervals in degrees ([[70, 170], [280, 335]]); a visible pixel saturated past `min_sat` inside one
    takes hue `to_hue` (degrees) at `sat_mult` of its saturation; value and alpha are kept. `max_sat` leaves the strongly
    saturated alone (SC-D's peach side pulled to its cream while its amber stinger, the same hue, stays)."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    h, s, v = _rgb_to_hsv(a[..., :3])
    deg = h * 360.0
    sel = (a[..., 3] > 0.02) & (s > min_sat) & (s <= max_sat)
    hit = np.zeros_like(sel)
    for lo, hi in ranges:
        hit |= (deg >= float(lo)) & (deg <= float(hi))
    sel &= hit
    if not sel.any():
        return img
    rgb = _hsv_to_rgb(np.where(sel, (float(to_hue) / 360.0) % 1.0, h), np.where(sel, s * sat_mult, s), v)
    a[..., :3] = np.where(sel[..., None], rgb, a[..., :3])
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA")


def tint_range(img, ranges, to_hue, sat_set=0.55, value_mult=0.6, min_sat=0.06, max_sat=0.55, min_val=0.3):
    """Recolour a pale material to a dark saturated one (pass 54, the dark-blue skeletons): a visible pixel whose hue is
    inside one of `ranges`, whose saturation is between `min_sat` and `max_sat` and whose value is at least `min_val` takes
    hue `to_hue`, saturation `sat_set` (absolute, not scaled: ivory bone has almost none) and `value_mult` of its value, so
    the highlights go dark blue and the shading darker still. Dark lines, sockets and the outline (value under `min_val`)
    and anything grey or cool (the knight's steel) stay as they are. remap_hues keeps value and scales saturation, which
    cannot turn ivory into dark blue."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    h, s, v = _rgb_to_hsv(a[..., :3])
    deg = h * 360.0
    sel = (a[..., 3] > 0.02) & (s >= min_sat) & (s <= max_sat) & (v >= min_val)
    hit = np.zeros_like(sel)
    for lo, hi in ranges:
        hit |= (deg >= float(lo)) & (deg <= float(hi))
    sel &= hit
    if not sel.any():
        return img
    rgb = _hsv_to_rgb(np.where(sel, (float(to_hue) / 360.0) % 1.0, h), np.where(sel, float(sat_set), s), np.where(sel, v * float(value_mult), v))
    a[..., :3] = np.where(sel[..., None], rgb, a[..., :3])
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA")


def _smooth(e0, e1, x):
    t = np.clip((x - e0) / max(e1 - e0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lift_range(img, ranges, to_hue, sat_set=None, sat_mult=1.0, v_lo=0.5, v_hi=1.0, gamma=1.0, min_sat=0.0, max_sat=1.01,
               min_val=0.0, src_hi=1.0, soft=0.04, hue_soft=0.0, to_hue_dark=None, mass=0, grow=None, mass_sat=None, keep_edge=0):
    """Recolour a material lighter (pass 107: the white beetle shells, the bright fire ants, the bone scorpion): a visible
    pixel whose hue is inside one of `ranges` (degrees; 340-360,0-40 for a red that wraps), whose saturation is between
    `min_sat` and `max_sat` and whose value is at least `min_val` takes hue `to_hue`, saturation `sat_set` (absolute) or
    `sat_mult` times its own when `sat_set` is None, and a value remapped from [min_val, src_hi] onto [v_lo, v_hi] with
    `gamma` (the shading order kept, the whole range lifted). Dark lines and the outline (under `min_val`) stay as they
    are; the saturation and value edges are blended over +-`soft` so no hard pixel seam shows where the selection ends.
    `hue_soft` (degrees) fades the selection out past each hue range's ends instead of cutting it; `to_hue_dark`, when
    given, is the hue of the darkest selected shades, blended to `to_hue` at the brightest (gold whose shadows go amber,
    not olive). `mass` (pixels) keeps only the material's areas (its hue, value and a saturation of at least `mass_sat`, default
    0.4 of `min_sat`, so its glints count) at least 2*mass+1 thick (a morphological opening: a beetle's shell, not its thin legs of the same red), grown back by `grow` pixels (default mass + 2) so the shell's rim comes
    with it. `keep_edge` (pixels) leaves the figure's outer band that wide as it is (an icon's grey outer stroke, as dark
    as the body it surrounds). tint_range only scales value down, remap_hues keeps it: neither turns a red or black shell white."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    h, s, v = _rgb_to_hsv(a[..., :3])
    deg = h * 360.0
    hit = np.zeros(h.shape, dtype=np.float32)
    hs = float(hue_soft)
    for lo, hi in ranges:
        if hs > 0.0:
            # distance in degrees outside [lo, hi] (on the circle), faded over hs
            dl = np.mod(float(lo) - deg, 360.0)
            dh = np.mod(deg - float(hi), 360.0)
            inside = (deg >= float(lo)) & (deg <= float(hi))
            dist = np.where(inside, 0.0, np.minimum(dl, dh))
            hit = np.maximum(hit, 1.0 - _smooth(0.0, hs, dist))
        else:
            hit = np.maximum(hit, ((deg >= float(lo)) & (deg <= float(hi))).astype(np.float32))
    w = hit * (a[..., 3] > 0.02)
    body = (w > 0.5) & (v >= float(min_val)) & (s >= (0.4 * float(min_sat) if mass_sat is None else float(mass_sat)))  # the material, its glints too
    sf = float(soft)
    if min_sat > 0.0:
        w = w * _smooth(min_sat - sf, min_sat + sf, s)
    if max_sat < 1.0:
        w = w * (1.0 - _smooth(max_sat - sf, max_sat + sf, s))
    if min_val > 0.0:
        w = w * _smooth(min_val - sf, min_val + sf, v)
    if int(mass) > 0:
        k = 2 * int(mass) + 1
        g = 2 * int(int(mass) + 2 if grow is None else grow) + 1
        core = Image.fromarray((body * 255).astype(np.uint8), "L")
        core = core.filter(ImageFilter.MinFilter(k)).filter(ImageFilter.MaxFilter(k)).filter(ImageFilter.MaxFilter(g))
        core = core.filter(ImageFilter.GaussianBlur(1.0))
        w = w * (np.asarray(core).astype(np.float32) / 255.0)
    if int(keep_edge) > 0:
        inner = Image.fromarray(((a[..., 3] > 0.5) * 255).astype(np.uint8), "L")
        inner = inner.filter(ImageFilter.MinFilter(2 * int(keep_edge) + 1)).filter(ImageFilter.GaussianBlur(0.7))
        w = w * (np.asarray(inner).astype(np.float32) / 255.0)
    if not (w > 0.0).any():
        return img
    t = np.clip((v - float(min_val)) / max(float(src_hi) - float(min_val), 1e-6), 0.0, 1.0) ** float(gamma)
    nv = float(v_lo) + (float(v_hi) - float(v_lo)) * t
    ns = np.full_like(s, float(sat_set)) if sat_set is not None else np.clip(s * float(sat_mult), 0.0, 1.0)
    if to_hue_dark is None:
        nh = np.full_like(h, (float(to_hue) / 360.0) % 1.0)
    else:
        nh = ((float(to_hue_dark) + (float(to_hue) - float(to_hue_dark)) * t) / 360.0) % 1.0
    rgb = _hsv_to_rgb(nh, ns, nv)
    a[..., :3] = a[..., :3] * (1.0 - w[..., None]) + rgb * w[..., None]
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA")


def grade(img, hue=(0.5, 0.72), sat_mul=1.8, sat_range=(0.04, 0.45), hue_shift=0.0, sat_max=0.6):
    """A hue-selective grade for a still: pixels whose hue sits in `hue` and whose saturation is inside `sat_range`
    get their saturation multiplied (capped at `sat_max`) and their hue shifted by `hue_shift`. A blue-grey garment
    that the video model would repaint in the screen colour becomes plainly, safely blue: saturated enough to be read
    as a colour, its hue nudged off the screen's so the keyer never mistakes it for the screen. The screen itself
    (saturation 1) is untouched."""
    arr = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    out = grade_array(arr, hue, sat_mul, sat_range, hue_shift, sat_max)
    return Image.fromarray((out * 255).astype(np.uint8), "RGB")


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
    return keep_top(img)


def keep_top(img, margin=2):
    """A frame whose figure was pushed past the cell's top edge (a lunge scaled up from the feet: the Skeleton Knight's
    second attack frame lost the crown of its helmet, pass 45) slides down until its top row sits inside the cell."""
    a = np.asarray(img)[..., 3]
    rows = np.nonzero(a.max(axis=1) > 0)[0]
    if not len(rows) or rows.min() >= margin:
        return img
    shift = int(margin - rows.min())
    # never push the feet out of the bottom: slide only as far as the cell allows
    shift = min(shift, img.height - 1 - int(rows.max()))
    if shift <= 0:
        return img
    canvas = Image.new("RGBA", img.size, (0, 0, 0, 0))
    canvas.alpha_composite(img, (0, shift))
    return canvas


# pass 111 (lane ENEMY): six optional LEFT-heading sets after idle_fd (tools/add_left_sets.py adds them; a strip that
# has them is never mirrored by the game: idle_l/run_l/attack_l/hit_l are the front set heading screen-left, run_bl/idle_bl
# the back set heading left; die has none). The painting pipelines (gen_art, gen_ctl, gen_ant) never produce them.
ENEMY_ORDER = ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd",
               "idle_l", "run_l", "attack_l", "hit_l", "run_bl", "idle_bl"]
LEFT_SETS = {"idle_l": "idle", "run_l": "run", "attack_l": "attack", "hit_l": "hit", "run_bl": "run_b", "idle_bl": "idle_b"}
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


def crumble(cell_img, t, seed=0, bands=8, pile=0.4):
    """Death frame for a creature that falls apart (the skeletons, pass 33.3): the standing figure cut into `bands`
    horizontal slices that drop, drift and tip towards a pile `pile` of the figure's height at its feet as `t` goes
    0 -> 1, under gravity (t squared). The slices keep their order, so the skull lands on top like the painted heap."""
    import random
    rng = random.Random(seed)
    cell = cell_img.width
    a = np.asarray(cell_img)[..., 3] > 127
    ys = np.nonzero(a.max(axis=1))[0]
    if not len(ys):
        return cell_img
    top, bot = int(ys.min()), int(ys.max()) + 1
    h = bot - top
    pile_h = max(h * pile, 1.0)
    fall_t = t * t
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    slices = []
    for k in range(bands):
        y0 = top + h * k // bands
        y1 = top + h * (k + 1) // bands
        if y1 <= y0:
            continue
        band_h = y1 - y0
        # where it comes to rest: the top slice at the top of the pile, the bottom one on the ground
        y_end = bot - pile_h + (k / max(bands - 1, 1)) * (pile_h - band_h)
        y = y0 + (y_end - y0) * fall_t
        dx = rng.uniform(-0.13, 0.13) * cell * t
        rot = rng.uniform(-32.0, 32.0) * t
        piece = cell_img.crop((0, y0, cell, y1))
        if abs(rot) > 0.5:
            piece = piece.rotate(rot, resample=Image.BICUBIC, expand=True)
        slices.append((k, piece, int(round((cell - piece.width) / 2 + dx)), int(round(y - (piece.height - band_h) / 2))))
    # the feet first, the skull last, so the upper slices land on the lower ones
    for k, piece, x, y in sorted(slices, key=lambda s: -s[0]):
        out.alpha_composite(piece, (max(x, 0), max(min(y, cell - piece.height), 0)), (max(-x, 0), 0))
    return out


def shatter(cell_img, n_frames=6, seed=0, pieces=14, outline_px=2, outline_color=(14, 8, 12, 255), spread=1.9, shrink=0.62):
    """Pass 91 (the Cactus Walker, Garry: "a pile of pieces"): a death in which the standing painting itself breaks into
    `pieces` irregular chunks (a Voronoi cut of its silhouette from `seed`) that pop out a little, fall, turn and come
    to rest heaped on the ground: a real pile, stacked by a height map of the cell's columns so no piece floats or sinks
    into another, the big ones first at the bottom. Every piece is the painting's own pixels with a fresh outline on
    its cut edges; no model paints anything, so the pile is always this creature's pieces. Returns n_frames cells, the
    last one the pile at rest (the dead frame the game holds). `spread` is the pile's width against the figure's;
    `shrink` the pieces' size at rest (a whole body heaped up in its own width stood as tall as the body)."""
    import random
    rng = random.Random(int(seed) * 7 + 91)
    cell = cell_img.width
    arr = np.asarray(cell_img.convert("RGBA"))
    a = arr[..., 3] > 40
    ys, xs = np.nonzero(a)
    if len(xs) < 20:
        return [cell_img] * n_frames
    top, bot = int(ys.min()), int(ys.max()) + 1
    left, right = int(xs.min()), int(xs.max()) + 1
    # the seeds: jittered inside the silhouette, so every piece is a chunk of the body
    idx = rng.sample(range(len(xs)), min(len(xs), pieces * 40))
    seeds = []
    for i in idx:
        p = (float(xs[i]), float(ys[i]))
        if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 > (0.32 * (right - left)) ** 2 / pieces * 2.2 for q in seeds):
            seeds.append(p)
        if len(seeds) >= pieces:
            break
    S = np.array(seeds, dtype=np.float32)
    gy, gx = np.mgrid[0:cell, 0:cell].astype(np.float32)
    d2 = (gx[..., None] - S[None, None, :, 0]) ** 2 + (gy[..., None] - S[None, None, :, 1]) ** 2
    lab = np.argmin(d2, axis=2)
    parts = []
    for k in range(len(seeds)):
        m = a & (lab == k)
        if m.sum() < 12:
            continue
        pys, pxs = np.nonzero(m)
        y0, y1, x0, x1 = int(pys.min()), int(pys.max()) + 1, int(pxs.min()), int(pxs.max()) + 1
        crop = arr[y0:y1, x0:x1].copy()
        crop[..., 3] = np.where(m[y0:y1, x0:x1], crop[..., 3], 0)
        pad = outline_px + 2
        im = Image.new("RGBA", (x1 - x0 + 2 * pad, y1 - y0 + 2 * pad), (0, 0, 0, 0))
        im.alpha_composite(Image.fromarray(crop, "RGBA"), (pad, pad))
        im = add_outline(im, outline_px, outline_color)
        # where its centre starts (cell px)
        parts.append({"img": im, "cx": x0 - pad + im.width / 2.0, "cy": y0 - pad + im.height / 2.0, "area": int(m.sum())})
    # the rest: big pieces first, each dropped onto the heap at a spot near the middle; its final turn is random
    mid = (left + right) / 2.0
    half = min((right - left) * spread / 2.0, cell * 0.40)
    ground = np.full(cell, float(bot), dtype=np.float32)   # the top of the heap per column
    for p in sorted(parts, key=lambda q: -q["area"]):
        rot = rng.uniform(-80.0, 80.0)
        small = p["img"].resize((max(1, int(p["img"].width * shrink)), max(1, int(p["img"].height * shrink))), Image.LANCZOS)
        r_img = small.rotate(rot, resample=Image.BICUBIC, expand=True)
        ra = np.asarray(r_img)[..., 3] > 60
        cols = np.nonzero(ra.any(axis=0))[0]
        if not len(cols):
            continue
        # each column's lowest opaque row in the rotated piece
        low = np.array([np.nonzero(ra[:, c])[0].max() if ra[:, c].any() else 0 for c in range(r_img.width)], dtype=np.float32)
        best = None
        for _ in range(14):   # a few spots tried, the lowest landing kept: the heap fills in rather than towering
            cx = mid + rng.triangular(-half, half, 0.0)
            x_left = int(round(cx - r_img.width / 2.0))
            cs = [c for c in cols if 0 <= x_left + c < cell]
            if not cs:
                continue
            y_top = min(ground[x_left + c] - 1 - low[c] for c in cs)
            if best is None or y_top > best[1]:
                best = (x_left, y_top, cs)
        if best is None:
            continue
        x_left, y_top, cs = best
        y_top = max(y_top, 0.0)
        # what the next pieces rest on: the piece's body, its thorns eroded away (pieces stood on a spike's tip)
        solid = np.asarray(r_img.getchannel("A").filter(ImageFilter.MinFilter(5)))> 60
        for c in cs:
            col = np.nonzero(solid[:, c])[0]
            if len(col):
                ground[x_left + c] = min(ground[x_left + c], y_top + float(col.min()))
        p.update(rot=rot, ex=x_left + r_img.width / 2.0, ey=y_top + r_img.height / 2.0)
    frames = []
    for f in range(n_frames):
        t = (f + 1) / float(n_frames)          # the last frame is the pile at rest
        out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        placed = []
        for p in parts:
            if "ex" not in p:
                continue
            # a small pop outward and up, then gravity: x eases, y follows a drop with an early lift
            ox = p["cx"] + (p["cx"] - mid) * 0.25 * math.sin(math.pi * min(t * 1.6, 1.0))
            x = ox + (p["ex"] - ox) * (1 - (1 - t) ** 2)
            lift = -0.10 * (bot - top) * math.sin(math.pi * min(t * 2.2, 1.0)) * (1.0 - t)
            y = p["cy"] + (p["ey"] - p["cy"]) * (t * t) + lift
            sc = 1.0 - (1.0 - shrink) * t
            im = p["img"].resize((max(1, int(p["img"].width * sc)), max(1, int(p["img"].height * sc))), Image.LANCZOS)
            im = im.rotate(p["rot"] * t, resample=Image.BICUBIC, expand=True)
            placed.append((y, im, int(round(x - im.width / 2.0)), int(round(y - im.height / 2.0))))
        for _, im, x, y in sorted(placed, key=lambda q: -q[0]):
            x = min(max(x, -im.width + 1), cell - 1)
            y = min(max(y, -im.height + 1), cell - 1)
            out.alpha_composite(im, (max(x, 0), max(y, 0)), (max(-x, 0), max(-y, 0)))
        frames.append(out)
    return frames


def _lag_top(frame, top, base, stretch):
    """Pass 126: the rows above `base` (cell px) drawn `stretch` times as tall, standing on `base`, the rows below as they are:
    the ears of a hopping thing lagging behind its body."""
    cell = frame.width
    h = base - top
    if h <= 1 or abs(stretch - 1.0) < 0.01:
        return frame
    new_h = max(1, int(round(h * stretch)))
    band = frame.crop((0, top, cell, base)).resize((cell, new_h), Image.LANCZOS)
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    out.alpha_composite(frame.crop((0, base, cell, cell)), (0, base))
    y = base - new_h
    out.alpha_composite(band, (0, max(y, 0)), (0, max(-y, 0)))
    return out


def hop_cycle(stand, cell, n=12, height=0.13, ground=0.3, top_lag=0.0, top_frac=0.3):
    """A hop drawn from one standing cell (pass 45: the Blue Slime and the Tumbleweed Minion). The painting itself squashes
    as it lands, gathers, stretches as it leaves the ground and rides a parabola `height` of the cell high, so the face
    never changes, the colours are the painting's and nothing can leave the cell (the video clips moved the slimes'
    mouths, greyed them mid-hop and grew the minion legs). `ground` is the share of the cycle spent touching the sand.
    Frame 0 is the landing; the cycle loops. Pass 126 (lane BESTIARY, the Dust Bunny's ears): `top_lag` > 0 lets the top
    `top_frac` of the figure lag: pressed down while it rises, thrown up while it falls and as it lands (0 = as before)."""
    out = []
    ys_ = np.nonzero(np.asarray(stand)[..., 3].max(axis=1) > 40)[0]
    top0, bot0 = (int(ys_.min()), int(ys_.max())) if len(ys_) else (0, cell - 1)
    for k in range(n):
        t = k / float(n)
        if t < ground:
            # on the sand: flattest as it lands, rounder as it gathers, flat again as it crouches to jump
            u = t / ground
            sy = 0.78 + 0.16 * math.sin(math.pi * u)
            bob = 0.0
        else:
            # in the air: stretched as it leaves and as it comes down, round at the top
            v = (t - ground) / (1.0 - ground)
            sy = 1.0 + 0.1 * abs(1.0 - 2.0 * v)
            bob = 4.0 * v * (1.0 - v) * height * cell
        sx = 1.0 + (1.0 - sy) * 0.9
        f = transform(stand, bob=bob, sx=sx, sy=sy)
        if top_lag > 0.0:
            # the body's vertical speed in the air, +1 leaving the ground, -1 coming down; thrown up as it lands
            vel = 1.0 - 2.0 * (t - ground) / (1.0 - ground) if t >= ground else -1.0 + 2.0 * (t / ground)
            ys2 = np.nonzero(np.asarray(f)[..., 3].max(axis=1) > 40)[0]
            if len(ys2):
                top = int(ys2.min())
                f = keep_top(_lag_top(f, top, top + int(round((bot0 - top0) * sy * top_frac)), 1.0 - top_lag * vel))
        out.append(f)
    return out


def align_pose(ref, pose, box=(0.32, 0.0, 0.68, 0.40), scales=(0.72, 1.75, 0.01)):
    """Pass 126 (lane BESTIARY, the Carrion Crow's wing beat): where a painted pose lies on its reference. Both keyed RGBA at the
    same size; `box` is the window of the reference's figure (its share of the bbox: the head, which every wing pose keeps)
    looked for in the pose at each scale (OpenCV's squared difference on grey over mid-grey, at half size). Returns (s, dx, dy):
    the pose scaled by s and moved by (dx, dy) in reference pixels lies on the reference. Klein's edits redraw a pose at
    their own size and place, so a beat from the raw paintings would pump and jump."""
    import cv2

    def grey(im):
        a = np.asarray(im.convert("RGBA")).astype(np.float32)
        return (a[..., :3].mean(axis=2) * (a[..., 3] / 255.0) + 128.0 * (1.0 - a[..., 3] / 255.0)).astype(np.float32)

    half = 2
    gr = grey(ref.resize((ref.width // half, ref.height // half), Image.LANCZOS))
    ys, xs = np.nonzero(np.asarray(ref)[..., 3] > 40)
    x0, x1, y0, y1 = int(xs.min()) // half, int(xs.max()) // half, int(ys.min()) // half, int(ys.max()) // half
    w, h = x1 - x0, y1 - y0
    tx0, ty0, tx1, ty1 = x0 + int(w * box[0]), y0 + int(h * box[1]), x0 + int(w * box[2]), y0 + int(h * box[3])
    tpl = gr[ty0:ty1, tx0:tx1]
    best = (1e18, 1.0, 0, 0)
    for s in np.arange(scales[0], scales[1], scales[2]):
        pw, ph = int(pose.width / half * s), int(pose.height / half * s)
        if pw <= tpl.shape[1] or ph <= tpl.shape[0]:
            continue
        gp = grey(pose.resize((pw, ph), Image.BILINEAR))
        res = cv2.matchTemplate(gp, tpl, cv2.TM_SQDIFF)
        mn, _, loc, _ = cv2.minMaxLoc(res)
        if mn < best[0]:
            best = (mn, float(s), loc[0], loc[1])
    _, s, lx, ly = best
    # the pose's (lx, ly) at scale s is the reference's (tx0, ty0)
    return s, (tx0 - lx) * half, (ty0 - ly) * half


def laid_cell(pose, ref, cell, scale, outline_px, outline_color, pad_bottom=0.06, box=(0.32, 0.0, 0.68, 0.40)):
    """Pass 126: a keyed pose as a cell on its reference's body: `scale` is what fit_cell gave the keyed reference, so the
    head stays where the reference's head stands in its cell, whatever the wings reach."""
    s, dx, dy = align_pose(ref, pose, box)
    # the pose's neutrals brought to the reference's (one edit paints the same black warmer than another, and a wing beat would
    # flicker brown and blue-black): a gain per channel from the median of each picture's dark greys, its bright parts spared
    def neutrals(im):
        a = np.asarray(im).astype(np.float32)
        mx, mn = a[..., :3].max(axis=2), a[..., :3].min(axis=2)
        m = (a[..., 3] > 200) & (mx > 28) & (mx < 150) & ((mx - mn) < 0.35 * mx)
        return np.median(a[..., :3][m], axis=0) if m.any() else np.array([1.0, 1.0, 1.0])

    gain = np.clip(neutrals(ref) / np.maximum(neutrals(pose), 1.0), 0.7, 1.4)
    pa = np.asarray(pose).astype(np.float32)
    v = pa[..., :3].max(axis=2, keepdims=True)
    w = np.clip((200.0 - v) / 60.0, 0.0, 1.0)
    pa[..., :3] = np.clip(pa[..., :3] * (1.0 + (gain - 1.0) * w), 0, 255)
    pose = Image.fromarray(pa.astype(np.uint8), "RGBA")
    ys, xs = np.nonzero(np.asarray(ref)[..., 3] > 40)
    pad = 6
    cx0, cx1 = max(int(xs.min()) - pad, 0), min(int(xs.max()) + pad, ref.width - 1) + 1
    cy1 = min(int(ys.max()) + pad, ref.height - 1) + 1
    # no wider than the cell: Klein draws wings-up poses with a small head, so a pose laid by its head alone would spread its wings
    # past the cell's sides; held at the cell's width about the head (the head then a little smaller than the reference's)
    pxs = np.nonzero(np.asarray(pose)[..., 3].max(axis=0) > 40)[0]
    if len(pxs):
        s_max = (cell - 2 * outline_px - 10) / (float(pxs.max() - pxs.min() + 1) * scale)
        if s > s_max:
            w_f, h_f = int(xs.max()) - int(xs.min()), int(ys.max()) - int(ys.min())
            hx = int(xs.min()) + w_f * (box[0] + box[2]) / 2.0
            hy = int(ys.min()) + h_f * (box[1] + box[3]) / 2.0
            ppx, ppy = (hx - dx) / s, (hy - dy) / s
            s = s_max
            dx, dy = hx - ppx * s, hy - ppy * s
    S = s * scale
    small = pose.resize((max(1, int(pose.width * S)), max(1, int(pose.height * S))), Image.LANCZOS)
    w_ref = int(round((cx1 - cx0) * scale))
    # the reference's crop origin in the cell: fit_cell centres it and stands it on the foot line
    ox = (cell - w_ref) // 2 - cx0 * scale
    oy = cell - int(cell * pad_bottom) - cy1 * scale
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    x, y = int(round(ox + dx * scale)), int(round(oy + dy * scale))
    # a pose whose body came out longer than the reference's (wings up) rides up rather than lose its feet at the cell's floor
    py = np.nonzero(np.asarray(pose)[..., 3].max(axis=1) > 40)[0]
    if len(py):
        over = y + int(py.max() * S) - (cell - outline_px - 1)
        if over > 0:
            y -= over
    # and slid sideways rather than cut, when one wing reaches further than the other
    if len(pxs):
        lo, hi = x + int(pxs.min() * S), x + int(pxs.max() * S)
        if lo < outline_px + 5:
            x += outline_px + 5 - lo
        elif hi > cell - outline_px - 6:
            x -= hi - (cell - outline_px - 6)
    out.alpha_composite(small, (max(x, 0), max(y, 0)), (max(-x, 0), max(-y, 0)))
    return add_outline(out, outline_px, outline_color)


FLAP_BEATS = (("stand", 0.0, 0.88), ("stand", 0.0, 0.95), ("down", 0.3, 1.0), ("mid", 0.58, 1.0), ("up", 0.8, 1.0), ("up", 0.94, 1.0),
              ("mid", 1.0, 1.0), ("down", 0.94, 1.0), ("down", 0.8, 1.0), ("mid", 0.58, 1.0), ("up", 0.3, 1.0), ("mid", 0.06, 1.0))


def flap_cycle(cells, cell, height=0.12, beats=FLAP_BEATS):
    """Pass 126 (lane BESTIARY, the Carrion Crow): a hop with two wing beats from painted poses, one picture per pose: `cells`
    {stand, up, mid, down}, each laid on the stand's body (laid_cell). A frame is a pose, how high it rides (a share of `height`
    of the cell) and how squashed it lands. Nothing can multiply a wing or blur it, since no video model draws a frame; the
    head and body hold still, only the wings change, and the hop itself moves every frame."""
    out = []
    for name, up, sy in beats:
        sx = 1.0 + (1.0 - sy) * 0.7
        out.append(transform(cells[name], bob=up * height * cell, sx=sx, sy=sy))
    return out


def _eye_sprites(cell_img, max_eyes=2):
    """Pass 126: the painted eyes of a figure as loose sprites [(RGBA, x, y)]: its largest pale blobs, the pupils inside them kept."""
    from scipy import ndimage
    arr = np.asarray(cell_img).astype(np.float32) / 255.0
    mx, mn = arr[..., :3].max(axis=2), arr[..., :3].min(axis=2)
    pale = (arr[..., 3] > 0.5) & (mx > 0.72) & ((mx - mn) < 0.18 * mx + 0.02)
    lab, n = ndimage.label(pale)
    if n == 0:
        return []
    sizes = ndimage.sum(pale, lab, range(1, n + 1))
    keep = [i + 1 for i in np.argsort(sizes)[::-1][:max_eyes] if sizes[i] >= 6]
    src = np.asarray(cell_img)
    out = []
    for k in keep:
        m = ndimage.binary_fill_holes(lab == k)
        m = ndimage.binary_dilation(m, iterations=1)
        ys, xs = np.nonzero(m)
        y0, y1, x0, x1 = int(ys.min()), int(ys.max()) + 1, int(xs.min()), int(xs.max()) + 1
        im = src[y0:y1, x0:x1].copy()
        im[..., 3] = np.where(m[y0:y1, x0:x1], 255, 0)
        out.append((Image.fromarray(im, "RGBA"), x0, y0))
    return out


def _cloud(cell, lumps, fill, light, outline_px, outline_color):
    """Pass 126: a cartoon dust cloud on a clear cell: discs [(x, y, r)] in cell px, one outline round them all, a paler disc up and to
    the left on each."""
    from PIL import ImageDraw
    ss = 3
    im = Image.new("RGBA", (cell * ss, cell * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    for x, y, r in lumps:
        if r > 0.3:
            dr.ellipse(((x - r) * ss, (y - r) * ss, (x + r) * ss, (y + r) * ss), fill=fill)
    for x, y, r in lumps:
        if r > 1.0:
            q = r * 0.68
            dr.ellipse(((x - r * 0.2 - q) * ss, (y - r * 0.25 - q) * ss, (x - r * 0.2 + q) * ss, (y - r * 0.25 + q) * ss), fill=light)
    return add_outline(im.resize((cell, cell), Image.LANCZOS), outline_px, outline_color)


def puff(cell_img, n_frames=5, seed=0, outline_px=2, outline_color=(14, 8, 12, 255), top_frac=0.32, lumps=9):
    """Pass 126 (lane BESTIARY, the Dust Bunny; Garry's brief: "a puff"): a death in which the figure goes up in a cartoon cloud of its
    own colour, its painted eyes hanging in the cloud, then falling onto a low heap of dust with its ears (the top `top_frac` of
    the figure) laid flat on it: the last frame is the one the game holds. No model paints anything."""
    import random
    rng = random.Random(int(seed) * 11 + 126)
    cell = cell_img.width
    arr = np.asarray(cell_img)
    ys, xs = np.nonzero(arr[..., 3] > 40)
    top, bot, left, right = int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())
    h = bot - top
    ball_top = top + int(h * top_frac)
    cx = (left + right) / 2.0
    cy = (ball_top + bot) / 2.0
    R = (bot - ball_top) / 2.0
    # the figure's own colours: the body's median and a paler one, outlines and pale eyes left out
    body = arr[ball_top:bot][arr[ball_top:bot][..., 3] > 200][..., :3].astype(np.float32)
    v = body.max(axis=1)
    mid = np.median(body[(v > 40) & (v < 190)], axis=0) if ((v > 40) & (v < 190)).any() else np.array([70.0, 70.0, 74.0])
    fill = tuple(int(c) for c in mid) + (255,)
    light = tuple(int(min(255, c * 1.28 + 10)) for c in mid) + (255,)
    eyes = _eye_sprites(cell_img)
    ang = [i * math.tau / lumps + rng.uniform(-0.25, 0.25) for i in range(lumps)]
    size = [rng.uniform(0.75, 1.15) for _ in range(lumps)]
    ground = bot - 1.0
    # the heap: low discs on the ground, the ears cut off the top of the figure and laid flat on it
    heap_w = (right - left) * 0.42
    heap = [(cx + (i - 2) / 2.0 * heap_w * 0.8, ground - R * 0.2 - (2 - abs(i - 2)) * R * 0.09, R * (0.34 - abs(i - 2) * 0.03)) for i in range(5)]
    ear_band = cell_img.crop((0, top, cell, ball_top + int(R * 0.1)))
    ear_h = max(2, int(ear_band.height * 0.5))
    ears = ear_band.resize((int(cell * 1.08), ear_h), Image.LANCZOS)
    frames = []
    k = max(n_frames - 1, 1)
    for fi in range(n_frames):
        t = fi / float(k)
        out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        if t >= 1.0:
            # the ears behind the heap, which hides where they were cut
            ex0 = int(cx - ears.width / 2.0)
            out.alpha_composite(ears, (max(ex0, 0), max(int(ground - R * 0.72 - ear_h * 0.25), 0)), (max(-ex0, 0), 0))
        if t >= 0.7:
            # the heap under what is left of the cloud
            gh = min(1.0, (t - 0.5) / 0.4)
            out.alpha_composite(_cloud(cell, [(x, ground - (ground - y) * gh, r * gh) for x, y, r in heap], fill, light, outline_px, outline_color))
        if fi == 0:
            out.alpha_composite(transform(cell_img, sx=1.12, sy=1.1))
        if t < 1.0:
            # the cloud: starts as a few small puffs round the body, grows to hide it, then flies apart and shrinks to nothing
            grow = min(1.0, t / 0.34)
            fly = max(0.0, (t - 0.25) / 0.75)
            sh = (1.0 - fly) ** 1.3
            lmp = []
            for a, s in zip(ang, size):
                d = R * (1.02 if fi == 0 else 0.45 + 0.35 * grow + 0.85 * fly)
                r = R * s * (0.2 if fi == 0 else (0.42 + 0.42 * grow) * sh)
                # never below the ground: a disc cut off by the cell's floor read as a flat-bottomed cloud
                lmp.append((cx + math.cos(a) * d, min(cy + math.sin(a) * d * 0.85 - fly * R * 0.25, ground - r), r))
            if t < 0.6 and fi > 0:
                r = R * (0.55 + 0.45 * grow) * sh
                lmp.append((cx, min(cy, ground - r), r))
            out.alpha_composite(_cloud(cell, lmp, fill, light, outline_px, outline_color))
        # the eyes hang in the cloud, then drop onto the heap
        drop = max(0.0, (t - 0.45) / 0.55)
        if t >= 0.2:
            for im, x, y in eyes:
                ex = int(cx + (x + im.width / 2.0 - cx) * 0.78 - im.width / 2.0)
                ey = int(y + (ground - R * 0.62 - y) * drop * drop)
                out.alpha_composite(im, (max(ex, 0), max(ey, 0)))
        frames.append(keep_top(out))
    return frames


def _bit_stamp(kind, length, col, rot, outline):
    """One loose bit, drawn four times too big and brought down: a straw stalk, or a feather's leaf shape."""
    from PIL import ImageDraw
    ss = 4
    size = int(length * 2.4) + 6
    im = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    c = size * ss / 2.0
    ln = length * ss / 2.0
    ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    if kind == "feather":
        pts = []
        for u, w in ((-1.0, 0.0), (-0.6, 0.30), (0.0, 0.42), (0.6, 0.26), (1.0, 0.0), (0.6, -0.26), (0.0, -0.42), (-0.6, -0.30)):
            x, y = u * ln, w * ln
            pts.append((c + x * ca - y * sa, c + x * sa + y * ca))
        dr.polygon(pts, fill=col)
        # the quill, a paler line down its length
        quill = tuple(min(255, c + 70) for c in col[:3]) + (255,)
        dr.line((c - ln * 1.25 * ca, c - ln * 1.25 * sa, c + ln * 0.8 * ca, c + ln * 0.8 * sa), fill=quill, width=max(1, int(ss * 0.7)))
    else:
        dr.line((c - ln * ca, c - ln * sa, c + ln * ca, c + ln * sa), fill=col, width=max(2, int(ss * 1.5)))
    return add_outline(im.resize((size, size), Image.LANCZOS), 1, outline)


def death_bits(frames, seed=0, kind="straw", n=20, colours=("#F2C744", "#E3A92B", "#FFE27A"), start=1, spread=0.32, rise=0.34, gravity=1.0, length=0.075,
               outline=(14, 8, 12, 255)):
    """Pass 126 (lane BESTIARY; the Straw Man's "straw flies", the crow's feathers): loose bits thrown out of the body over a death
    strip, drawn on the frames: each flies from the figure's middle from frame `start` on a little arc, turns as it goes, and lies
    on the ground for the rest of the strip (the last frame is the one the game holds). `kind` straw (a thin stalk) or feather (a
    leaf shape). No model paints anything. Sizes are shares of the cell; a higher `gravity` lands them sooner."""
    import random
    rng = random.Random(int(seed) * 13 + 126)
    if not frames:
        return frames
    cell = frames[0].width
    a = np.asarray(frames[0])[..., 3]
    ys, xs = np.nonzero(a > 40)
    cx = float(xs.mean()) if len(xs) else cell / 2.0
    cy = float(ys.mean()) if len(ys) else cell / 2.0
    floor = float(ys.max()) if len(ys) else cell * 0.94
    cols = [tuple(int(str(c).lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) + (255,) for c in colours]
    if isinstance(outline, str):
        outline = tuple(int(outline.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
    bits = []
    last = max(len(frames) - 1 - start, 1)
    for k in range(int(n)):
        ang = rng.uniform(-math.pi, 0.0)   # up and out
        v = rng.uniform(0.55, 1.0)
        bits.append({"x0": cx + rng.uniform(-0.1, 0.1) * cell, "y0": cy + rng.uniform(-0.15, 0.1) * cell,
                     "vx": math.cos(ang) * v * spread * cell, "vy": math.sin(ang) * v * rise * cell,
                     "col": rng.choice(cols), "rot0": rng.uniform(0, 360), "spin": rng.uniform(-520, 520),
                     "len": length * cell * rng.uniform(0.75, 1.3), "t0": start + rng.uniform(0.0, 1.2),
                     "rest": floor - rng.uniform(0.0, 0.24) * cell})
    out = []
    for fi, f in enumerate(frames):
        # what has landed lies under the body, what still flies over it
        under = Image.new("RGBA", f.size, (0, 0, 0, 0))
        over = Image.new("RGBA", f.size, (0, 0, 0, 0))
        for b in bits:
            t = (fi - b["t0"]) / float(last)
            if t < 0.0:
                continue
            # a throw up and out, falling onto its own spot on the ground, where it stays
            x = b["x0"] + b["vx"] * t * 1.6
            y = b["y0"] + b["vy"] * t * 1.6 + 0.5 * gravity * 2.4 * cell * t * t
            # all down by the last frame: it is the one the game holds, and a bit left in the air would hang there
            lying = (y >= b["rest"] and t > 0.05) or fi == len(frames) - 1
            if lying:
                y = b["rest"]
                # flat on the ground, whatever way it was turning
                rot = (b["rot0"] % 70.0) - 35.0
            else:
                rot = b["rot0"] + b["spin"] * t
            st = _bit_stamp(kind, b["len"], b["col"], rot, outline)
            # never past the cell's sides: a piece at the edge bleeds into the next frame of the strip through the mipmaps
            px, py = min(max(int(x - st.width / 2), 3), cell - st.width - 3), int(y - st.height / 2)
            if py + st.height <= 0 or py >= cell:
                continue
            (under if lying else over).alpha_composite(st, (max(px, 0), max(py, 0)), (max(-px, 0), max(-py, 0)))
        under.alpha_composite(f)
        under.alpha_composite(over)
        out.append(under)
    return out


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


# ---------------------------------------------------------------- pass 119 (the lead): a card's lean
# Pass 73's B cards were all turned to one 10-degree lean at install (tools/dl/p73/CARDS/cardkit.py: Klein leans a
# "tilted about 12 degrees" card anywhere from 8 degrees left to 12 right); the Level Editor's installs skipped that step,
# so a re-rolled card kept Klein's lean (Garry's Hydra stood upright among 41 cards at 10). Moved here so every finish
# can take it: gen_art.finish(..., lean=deg), the icon jobs' `lean` field.

def _bbox_area(mask, ang):
    m = mask.rotate(ang, resample=Image.NEAREST, expand=True)
    b = m.getbbox()
    return (b[2] - b[0]) * (b[3] - b[1]) if b else 0


def card_tilt(rgba):
    """The clockwise lean of the card in a keyed RGBA picture, in degrees (-30..30): rotating it this many degrees
    counter-clockwise (PIL's sense) stands it upright. The turn that makes its bounding box smallest, coarse to fine."""
    a = rgba.split()[3].point(lambda v: 255 if v > 127 else 0)
    small = a.resize((max(1, a.width // 4), max(1, a.height // 4)), Image.NEAREST)
    best = min(range(-30, 31, 2), key=lambda d: _bbox_area(small, d))
    fine = [best + x / 4.0 for x in range(-8, 9)]
    return float(min(fine, key=lambda d: _bbox_area(small, d)))


def lean_to(keyed, lean):
    """The keyed RGBA picture turned so its card leans `lean` degrees clockwise (its top to the right), on the full
    picture before it is fitted, so no line goes soft; the edge's smeared alpha made crisp again."""
    turn = card_tilt(keyed) - float(lean)
    if abs(turn) <= 0.4:
        return keyed
    out = keyed.rotate(turn, resample=Image.BICUBIC, expand=True)
    r, g, b, al = out.split()
    al = al.point(lambda v: 0 if v < 24 else (255 if v > 232 else v))
    return Image.merge("RGBA", (r, g, b, al))
