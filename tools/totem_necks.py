"""Pass 138 (lane TOTEM): the Spirit Pole's carved faces without their wooden necks, laid on the cedar block again with
one shared drop shadow (Garry, 2026-11-10: "most of them have a wooden neck which looks weird considering that the face
is sitting on the wooden bg. Remove that neck, but only the neck, otherwise leaving the rest of the face as is. Consider
how the shadows have to change (drop shadow over the wooden square, etc)").

Works on the keyed heads tools/gen_totem_icons.py made (tools/dl/p83/TOTEM/cands/<id>_c<k>_cut.png; PICKS names the
candidate each installed spirit came from). A neck is found as the wood-coloured part of the figure that a flood from
the figure's foot reaches without crossing the head's black outline (NECKS: how far up it may climb, extra barriers drawn
as lines where the head is wood-coloured too, extra cuts), its own outline goes with it, and the cut edge is inked again
so the head stays closed. The head keeps its size on the block (the scale the uncut head had), centred, over a soft shadow
offset down-right (SHADOW), the same for every face; a face without a neck only gains the shadow.

  python tools/totem_necks.py [--only wolf,bear]       # -> tools/dl/p138/TOTEM/necks/<id>_*.png + necks_debug.png
  python tools/totem_necks.py --sheet                  # + tools/dl/p138/TOTEM/necks_before_after.png
  python tools/totem_necks.py --install                # -> game/art/ui/totem/spirit_<id>.png (then Godot --import)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import gen_totem_icons as gti  # noqa: E402

CANDS = os.path.join(REPO, "tools", "dl", "p83", "TOTEM", "cands")
OUT = os.path.join(REPO, "tools", "dl", "p138", "TOTEM", "necks")
ART = os.path.join(REPO, "game", "art", "ui", "totem")
SIDE = gti.SIDE

# the installed spirits' candidates (an exact match of game/art/ui/totem/spirit_<id>.png with cands/<id>_c<k>_seg.png)
PICKS = {"wolf": 3, "whale": 2, "bear": 3, "thunderbird": 1, "seal": 0, "salmon": 1, "frog": 0, "killer_whale": 3,
         "bullhead": 0, "raven": 0, "serpent": 2}

# per face, in the cut's own pixels: `top` the highest row the neck may reach; `walls` lines the flood may not cross
# (where the face is wood-coloured too), [x0, y0, x1, y1, ...] polylines; `seeds` [x, y] points on a piece of neck the
# flood from the foot cannot reach; `from_top` the flood starts at the crown too (a block behind the whole head);
# `cut` polygons removed whole; `keep` polygons never removed. A face not here has no neck.
NECKS = {
    "wolf": {"top": 540},
    "thunderbird": {"top": 620},
    "seal": {"top": 520, "keep": [[212, 430, 485, 430, 485, 705, 212, 705]], "seeds": [[75, 650], [625, 650]]},
    "salmon": {"top": 620, "seeds": [[255, 820]]},
    "frog": {"top": 480, "seeds": [[510, 600]]},
    "killer_whale": {"top": 600},
    "bullhead": {"top": 500},
    "raven": {"top": 440, "seeds": [[420, 640]]},
    "serpent": {"top": 0, "from_top": True, "seeds": [[140, 90], [580, 80], [615, 80], [632, 360]]},
}

# the shared drop shadow on the cedar block (canvas px at SIDE): offset, blur, strength, colour
SHADOW = {"dx": 5, "dy": 7, "blur": 5.0, "alpha": 0.5, "rgb": (28, 10, 4)}
# the ink along a cut edge, as thick as the head's own outline (px in the cut's pixels)
INK = (18, 12, 12)


def hsv(a):
    rgb = a[..., :3].astype(np.float32) / 255.0
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx)
    m = d > 1e-6
    rr = m & (mx == r)
    gg = m & (mx == g) & ~rr
    bb = m & ~rr & ~gg
    h[rr] = ((g - b)[rr] / d[rr]) % 6.0
    h[gg] = (b - r)[gg] / d[gg] + 2.0
    h[bb] = (r - g)[bb] / d[bb] + 4.0
    return h * 60.0, s, mx


def wood(a):
    """Cedar: orange to red-brown, saturated, not black (its dark grain counts)."""
    h, s, v = hsv(a)
    return ((h < 38.0) | (h > 340.0)) & (s > 0.32) & (v > 0.17) & (a[..., 3] > 0)


def dark(a):
    h, s, v = hsv(a)
    return (v < 0.17) & (a[..., 3] > 0)


def neck_mask(cut, spec):
    from scipy import ndimage
    a = np.asarray(cut).copy()
    H, W = a.shape[:2]
    op = a[..., 3] > 0
    passable = wood(a)
    walls = Image.new("L", (W, H), 0)
    dw = ImageDraw.Draw(walls)
    for line in spec.get("walls", []):
        dw.line(list(zip(line[0::2], line[1::2])), fill=255, width=int(spec.get("wall_w", 9)))
    passable &= np.asarray(walls) == 0
    top = int(spec.get("top", 0))
    passable[:top] = False
    lab, n = ndimage.label(passable)
    # the parts the figure's foot touches (its bottom 2 %; the top 2 % too for a block that runs up behind the head)
    foot = lab[int(H * 0.98):, :]
    ids = set(np.unique(foot[foot > 0]).tolist())
    # and the parts holding a seed point (a piece of neck the flood cannot reach: behind a black seam, off the foot)
    for sx, sy in spec.get("seeds", []):
        if lab[sy, sx] > 0:
            ids.add(int(lab[sy, sx]))
        else:
            print("totem_necks: seed (%d, %d) is not on wood" % (sx, sy))
    if spec.get("from_top"):
        crown = lab[:int(H * 0.02) + 1, :]
        ids |= set(np.unique(crown[crown > 0]).tolist())
    neck = np.isin(lab, list(ids)) if ids else np.zeros_like(passable)
    for poly in spec.get("cut", []):
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon(list(zip(poly[0::2], poly[1::2])), fill=255)
        neck |= (np.asarray(m) > 0) & op
    # holes inside the neck (grain flecks, small dark lines) are neck too
    neck = ndimage.binary_closing(neck, iterations=3) & op
    neck = ndimage.binary_fill_holes(neck) & op
    for poly in spec.get("keep", []):
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon(list(zip(poly[0::2], poly[1::2])), fill=255)
        neck &= ~(np.asarray(m) > 0)
    # its own outline: dark pixels nearer the neck than any other part of the head (outline thickness T)
    T = float(spec.get("outline", 16))
    # the rest of the head: its solid, non-black parts of some size (not the keyed rim's faint pixels)
    rest = (a[..., 3] > 200) & ~neck & ~dark(a)
    lab_r, n_r = ndimage.label(rest)
    if n_r > 0:
        sizes_r = ndimage.sum(rest, lab_r, range(1, n_r + 1))
        rest = np.isin(lab_r, [1 + i for i, sz in enumerate(sizes_r) if sz >= 150])
    d_neck = ndimage.distance_transform_edt(~neck)
    d_rest = ndimage.distance_transform_edt(~rest)
    drop = neck | (dark(a) & (d_neck <= T) & (d_neck < d_rest) & (np.arange(H)[:, None] >= top - T))
    # whatever is left of the figure: no thin lines near the cut (the neck's own outline where it met the head's rim),
    # then its biggest piece (a sliver cut off by the drop goes too)
    keep = op & ~drop
    opened = ndimage.binary_opening(keep, structure=np.ones((3, 3), bool), iterations=4)
    near = ndimage.distance_transform_edt(~drop) <= 30
    keep &= ~(near & ~opened)
    lab2, n2 = ndimage.label(keep)
    if n2 > 1:
        sizes = ndimage.sum(keep, lab2, range(1, n2 + 1))
        big = 1 + int(np.argmax(sizes))
        keep = lab2 == big
    return keep, op & ~keep


def ink_edge(cut, keep, cut_away, px):
    """The kept head with its cut edge inked `px` deep (only along the cut, not the head's own silhouette), the alpha
    smoothed by a hair."""
    from scipy import ndimage
    a = np.asarray(cut).astype(np.float32).copy()
    near_cut = ndimage.distance_transform_edt(~cut_away) <= px
    band = keep & near_cut
    for c in range(3):
        a[..., c] = np.where(band, INK[c], a[..., c])
    al = keep.astype(np.float32)
    soft = np.asarray(Image.fromarray((al * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255.0
    soft[soft < 0.12] = 0.0
    soft[soft > 0.88] = 1.0
    # the original alpha's own soft rim stays where nothing was cut
    orig = a[..., 3] / 255.0
    al_out = np.where(ndimage.distance_transform_edt(~cut_away) <= 3, soft * (orig > 0), orig * keep)
    a[..., 3] = al_out * 255.0
    a[..., :3][al_out == 0] = 0
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def outline_px(cut):
    """The head's own outline thickness: the median dark run inward from the silhouette's left and right edges."""
    a = np.asarray(cut)
    d = dark(a)
    runs = []
    for y in range(int(a.shape[0] * 0.2), int(a.shape[0] * 0.6), 7):
        row = a[y, :, 3] > 0
        xs = np.nonzero(row)[0]
        if xs.size == 0:
            continue
        x = xs[0]
        n = 0
        while x + n < a.shape[1] and d[y, x + n]:
            n += 1
        if 2 < n < 40:
            runs.append(n)
    return int(np.median(runs)) if runs else 10


def place(head, scale_from):
    """The head on the cedar block at the uncut head's scale (gen_totem_icons.segment's fit of `scale_from`), centred,
    over the shared shadow; opaque."""
    fill = 0.9
    blk = gti.block_image()
    room = SIDE * fill
    k = min(room / float(scale_from.width), room / float(scale_from.height))
    bb = head.getchannel("A").getbbox()
    head = head.crop(bb)
    h = head.resize((max(1, int(round(head.width * k))), max(1, int(round(head.height * k)))), Image.LANCZOS)
    x = (SIDE - h.width) // 2
    y = (SIDE - h.height) // 2
    sh = Image.new("L", (SIDE, SIDE), 0)
    sh.paste(h.getchannel("A"), (x + SHADOW["dx"], y + SHADOW["dy"]))
    sh = sh.filter(ImageFilter.GaussianBlur(SHADOW["blur"]))
    sh = sh.point(lambda v: int(v * SHADOW["alpha"]))
    shade = Image.new("RGBA", (SIDE, SIDE), SHADOW["rgb"] + (255,))
    shade.putalpha(sh)
    blk.alpha_composite(shade)
    blk.alpha_composite(h, (x, y))
    blk.putalpha(255)
    return blk


def debug_view(cut, cut_away):
    a = np.asarray(cut.convert("RGBA")).astype(np.float32).copy()
    bg = np.zeros_like(a)
    bg[..., 0], bg[..., 1], bg[..., 2], bg[..., 3] = 40, 160, 200, 255
    al = a[..., 3:4] / 255.0
    out = bg * (1 - al) + a * al
    out[cut_away] = out[cut_away] * 0.35 + np.array([255, 0, 255, 255]) * 0.65
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGBA").convert("RGB")


def run(ids, install=False):
    os.makedirs(OUT, exist_ok=True)
    dbg = []
    for sid in ids:
        cut = Image.open(os.path.join(CANDS, "%s_c%d_cut.png" % (sid, PICKS[sid]))).convert("RGBA")
        spec = NECKS.get(sid)
        if spec is None:
            head = cut
            away = np.zeros((cut.height, cut.width), bool)
        else:
            keep, away = neck_mask(cut, spec)
            head = ink_edge(cut, keep, away, int(spec.get("ink", outline_px(cut))))
        head.save(os.path.join(OUT, "%s_head.png" % sid))
        seg = place(head, cut)
        seg.save(os.path.join(OUT, "%s_seg.png" % sid))
        dbg.append((sid, debug_view(cut, away)))
        if install:
            seg.convert("RGB").save(os.path.join(ART, "spirit_%s.png" % sid))
            print("totem_necks: spirit_%s installed" % sid)
    # the debug sheet: each cut with what goes in magenta, 300 px tall
    th = 300
    tiles = [(s, im.resize((int(im.width * th / im.height), th))) for s, im in dbg]
    W = sum(t.width + 8 for _, t in tiles)
    sheet = Image.new("RGB", (W, th + 18), "white")
    d = ImageDraw.Draw(sheet)
    x = 0
    for s, t in tiles:
        sheet.paste(t, (x, 0))
        d.text((x + 3, th + 3), s, fill="black")
        x += t.width + 8
    sheet.save(os.path.join(OUT, "necks_debug.png"))
    print("totem_necks: debug", os.path.join(OUT, "necks_debug.png"))


def before_after(ids, dst):
    side = 256
    sheet = Image.new("RGB", (len(ids) * (side + 8), 2 * side + 40), "white")
    d = ImageDraw.Draw(sheet)
    for k, sid in enumerate(ids):
        b = os.path.join(OUT, "before", "spirit_%s.png" % sid)
        before = Image.open(b if os.path.isfile(b) else os.path.join(ART, "spirit_%s.png" % sid)).convert("RGB")
        after = Image.open(os.path.join(OUT, "%s_seg.png" % sid)).convert("RGB")
        x = k * (side + 8)
        sheet.paste(before.resize((side, side)), (x, 0))
        sheet.paste(after.resize((side, side)), (x, side + 20))
        d.text((x + 3, side + 4), sid + " before / after", fill="black")
    sheet.save(dst)
    print("totem_necks: sheet", dst)


def main():
    a = sys.argv[1:]
    only = []
    if "--only" in a:
        only = a[a.index("--only") + 1].split(",")
    ids = only or list(PICKS)
    # the installed pictures as they were, once (the sheet's "before")
    bdir = os.path.join(OUT, "before")
    if not os.path.isdir(bdir):
        os.makedirs(bdir)
        for sid in PICKS:
            Image.open(os.path.join(ART, "spirit_%s.png" % sid)).save(os.path.join(bdir, "spirit_%s.png" % sid))
    run(ids, "--install" in a)
    if "--sheet" in a:
        before_after(ids, os.path.join(REPO, "tools", "dl", "p138", "TOTEM", "necks_before_after.png"))


if __name__ == "__main__":
    main()
