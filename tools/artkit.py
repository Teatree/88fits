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


def hop_cycle(stand, cell, n=12, height=0.13, ground=0.3):
    """A hop drawn from one standing cell (pass 45: the Blue Slime and the Tumbleweed Minion). The painting itself squashes
    as it lands, gathers, stretches as it leaves the ground and rides a parabola `height` of the cell high, so the face
    never changes, the colours are the painting's and nothing can leave the cell (the video clips moved the slimes'
    mouths, greyed them mid-hop and grew the minion legs). `ground` is the share of the cycle spent touching the sand.
    Frame 0 is the landing; the cycle loops."""
    out = []
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
        out.append(transform(stand, bob=bob, sx=sx, sy=sy))
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
