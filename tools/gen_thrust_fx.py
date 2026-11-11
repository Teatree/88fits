"""The Spear's thrust flipbook, drawn by us (pass 142).

Garry (pass 142): "Spear, ok cool, but let's not just copy the reference. Instead can you go ahead and generate something
similar looking with the tools that we have? The goal wasn't to just use what they had". Pass 141 had cut the frames out
of his 2D pack (Everything.zip, row 4). This script draws our own, procedurally, in the same layout and channels, so
core/shaders/melee_burst.gdshader and MeleeFx play it exactly as pass 141 timed it:

  game/art/fx/melee/thrust_burst.png: six frames of 360 x 192 stacked top to bottom (360 x 1152), each with the stroke
  running +x, its tail at u = TAIL_U and its point at u = HEAD_U in the frames of the dart and the hit (MeleeFx's
  BURST_TAIL_U, BURST_HEAD_U), the frame's height the stroke's full width (2 x half_w). R = coverage, G = heat (0 the deep
  glow .. 1 the white core), B = a soft sheath (the dark backing that keeps it readable on pale sand). The shader tints it
  by the stroke's colours.

  frame 0  the needle at the start of the dart: a thin spindle of light, the first barbs
  frame 1  the dart: the spindle thickens, the arrowhead forms, short flame tongues
  frame 2  the hit (arrives with it): the arrowhead's flame at full spread, tongues streaming back, a white-hot core, sparks
  frame 3  the hold: the flame stretched back and narrowed, the point a touch past the reach, cooling
  frame 4  breaking up: wisps eaten by noise, a faint line, embers
  frame 5  the last embers

Drawn in "stroke units" (x 0 at the tail .. 1 at the point, y across, both in lengths of the stroke, so an angle here is
the angle on the sand): capsules along paths (a Gaussian falloff from each segment, the max for the light, a weighted mean
for the heat), a filled flame body, flame tongues, streak sparks; then a gentle warp across the stroke and streaky fBm
noise that eats the soft edges into flame, rendered at 2x and averaged down. Seeded: the same command gives the same file.

  python tools/gen_thrust_fx.py [--seed 1420] [--out game/art/fx/melee/thrust_burst.png] [--preview <dir>]

--preview writes <dir>/thrust_frames.png: each frame as data (R, G, B), then tinted as the shader tints it (the plain
Spear's blue and a fire orange) on black and on sand.
"""
import argparse
import math
import os

import numpy as np
from PIL import Image
from scipy import ndimage

# the frame (1x) and the render scale
FW, FH, FRAMES = 360, 192, 6
SS = 2
W, H = FW * SS, FH * SS
# MeleeFx's BURST_TAIL_U / BURST_HEAD_U: where the tail and the point at the hit lie along the texture
TAIL_U = 0.035
HEAD_U = 0.895
# the frame's half height in stroke lengths (a level-1 Spear: half width ~1 m on a ~4.4 m stroke)
YH = 0.23
KX = (HEAD_U - TAIL_U) * W
KY = H / (2.0 * YH)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "art", "fx", "melee", "thrust_burst.png")

# every pixel's place in stroke units
_YY, _XX = np.mgrid[0:H, 0:W].astype(np.float32)
SX = (_XX + 0.5 - TAIL_U * W) / KX
SY = (_YY + 0.5 - H * 0.5) / KY


class Canvas:
    def __init__(self):
        self.light = np.zeros((H, W), np.float32)
        self.hnum = np.zeros((H, W), np.float32)
        self.hden = np.zeros((H, W), np.float32)

    def _box(self, xs, ys, pad):
        x0 = int(max((min(xs) - pad) * KX + TAIL_U * W, 0))
        x1 = int(min((max(xs) + pad) * KX + TAIL_U * W + 2, W))
        y0 = int(max((min(ys) - pad) * KY + H * 0.5, 0))
        y1 = int(min((max(ys) + pad) * KY + H * 0.5 + 2, H))
        return x0, x1, y0, y1

    def _put(self, sl, g, heat):
        sub = self.light[sl]
        np.maximum(sub, g, out=sub)
        w = g * g
        self.hnum[sl] += w * heat
        self.hden[sl] += w

    def seg(self, a, b, wa, wb, ia, ib, ha, hb):
        """One straight stroke from a to b (stroke units): its sigma across, light and heat run from a to b."""
        self.path([a, b], [wa, wb], [ia, ib], [ha, hb])

    def path(self, pts, ws, its, hs):
        """A stroke along a polyline: every pixel takes the path's sigma, light and heat at its NEAREST point (not the
        brightest of the segments' capsules, whose round ends would bump the outline at every joint), and a Gaussian
        falloff from it."""
        pts = np.asarray(pts, np.float64)
        ws, its, hs = (np.asarray(v, np.float64) for v in (ws, its, hs))
        pad = 3.2 * float(ws.max())
        x0, x1, y0, y1 = self._box(pts[:, 0], pts[:, 1], pad)
        if x0 >= x1 or y0 >= y1:
            return
        sl = (slice(y0, y1), slice(x0, x1))
        px, py = SX[sl].astype(np.float64), SY[sl].astype(np.float64)
        best = np.full(px.shape, np.inf)
        bk = np.zeros(px.shape, np.int32)
        bt = np.zeros(px.shape)
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            dx, dy = b[0] - a[0], b[1] - a[1]
            ll = dx * dx + dy * dy
            t = np.clip(((px - a[0]) * dx + (py - a[1]) * dy) / max(ll, 1e-12), 0.0, 1.0)
            qx, qy = a[0] + dx * t - px, a[1] + dy * t - py
            d2 = qx * qx + qy * qy
            m = d2 < best
            best = np.where(m, d2, best)
            bk = np.where(m, k, bk)
            bt = np.where(m, t, bt)

        def at(v):
            return v[bk] + (v[bk + 1] - v[bk]) * bt
        sig = np.maximum(at(ws), 1e-4)
        g = at(its) * np.exp(-0.5 * best / (sig * sig))
        self._put(sl, g.astype(np.float32), at(hs).astype(np.float32))

    def blob(self, x, y, sx, sy, inten, heat):
        """An elliptical Gaussian (sigmas sx along, sy across, stroke units)."""
        x0, x1, y0, y1 = self._box((x,), (y,), 3.2 * max(sx, sy))
        if x0 >= x1 or y0 >= y1:
            return
        sl = (slice(y0, y1), slice(x0, x1))
        g = inten * np.exp(-0.5 * (((SX[sl] - x) / sx) ** 2 + ((SY[sl] - y) / sy) ** 2))
        self._put(sl, g.astype(np.float32), heat)


def fbm(rng, fx, fy, octaves=4):
    """Smooth value noise in [0, 1] over the canvas: `fx` x `fy` cells at the first octave (fewer along x: streaks)."""
    out = np.zeros((H, W), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cx, cy = max(int(fx * 2 ** o), 2), max(int(fy * 2 ** o), 2)
        g = rng.random((cy + 1, cx + 1)).astype(np.float32)
        z = ndimage.zoom(g, (H / (cy + 1), W / (cx + 1)), order=3, mode="reflect")[:H, :W]
        if z.shape != (H, W):
            z = np.pad(z, ((0, H - z.shape[0]), (0, W - z.shape[1])), mode="edge")
        out += amp * z
        tot += amp
        amp *= 0.5
    out /= tot
    lo, hi = np.percentile(out, 1), np.percentile(out, 99)
    return np.clip((out - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- the stroke's parts

def spindle(cv, x0, x1, hw, inten, heat, n=48):
    """The core: a spindle of light from x0 to x1 on the line, widest about two thirds along, a needle point at x1."""
    s = np.linspace(0.0, 1.0, n)
    prof = (s ** 0.6) * ((1.0 - s) ** 0.3)
    prof /= prof.max()
    pts = [(x0 + (x1 - x0) * t, 0.0) for t in s]
    cv.path(pts, list(np.maximum(hw * prof, 0.0008)), list(inten * (0.5 + 0.5 * s ** 0.7)),
            list(np.clip(heat * (0.78 + 0.22 * s), 0.0, 1.0)))


def blade_env(x, x0, xw, xh):
    """The blade's half-width share at x: 0 at its tail x0, rising to 1 at its widest xw, falling to a sharp point at xh."""
    if x <= x0 or x >= xh:
        return 0.0
    if x < xw:
        return ((x - x0) / (xw - x0)) ** 1.9
    return ((xh - x) / (xh - xw)) ** 1.35


def blade(cv, x0, xw, xh, half, inten, heat, n=56):
    """The flame blade: a leaf of light on the line, from a wisp at x0 to its widest `half` (sigma across) at xw and on
    to a sharp point at xh; cool (the stroke's deep colour) so the core and the tongues read hotter over it."""
    xs = np.linspace(x0, xh, n)
    env = np.array([blade_env(x, x0, xw, xh) for x in xs])
    cv.path([(x, 0.0) for x in xs], list(np.maximum(half * env, 0.0012)), list(inten * (0.25 + 0.75 * env ** 0.7)),
            list(heat * (0.6 + 0.4 * env)))


def tongue(cv, root, ang, length, w0, inten, heat, curve, wob, ph, n=22):
    """A flame tongue from `root` going back along -x at `ang` (radians, + towards +y), bending back towards the stroke's
    line as it goes (`curve`), thinning to its end, flickering (`wob`)."""
    x, y = root
    pts, ws, its, hs = [], [], [], []
    ds = length / (n - 1)
    for k in range(n):
        s = k / (n - 1)
        pts.append((x, y))
        # it grows out of the blade (no hard edge where it starts), thins to its end, flickers
        grow_in = 0.55 + 0.45 * min(s / 0.18, 1.0)
        ws.append(max(w0 * grow_in * (1.0 - s) ** 0.55 * (1.0 + wob * math.sin(ph + s * 8.0) * s), 0.0008))
        its.append(inten * (0.75 + 0.25 * min(s / 0.18, 1.0)) * (1.0 - s) ** 0.9 * (0.86 + 0.14 * math.sin(ph * 1.7 + s * 6.5)))
        hs.append(min(heat * (1.0 - s) ** 0.8 + 0.05, 1.0))
        a = ang * (1.0 - curve * s)
        x -= math.cos(a) * ds
        y += math.sin(a) * ds
    cv.path(pts, ws, its, hs)


def streak(cv, x, y, ang, length, w, inten, heat):
    """A spark flying at `ang` (radians from +x): a short hot streak, brightest at its head."""
    hx, hy = x + math.cos(ang) * length, y + math.sin(ang) * length
    cv.seg((x, y), (hx, hy), w * 0.4, w, inten * 0.25, inten, heat * 0.7, heat)


class Tongues:
    """One set of tongues shared by the frames (the same flames growing, stretching and breaking up), rooted on the
    blade's edge: short hot barbs flung back from just behind the point (the arrowhead), and long streamers swept back
    along the blade, turning parallel to it as they go (no broom at the hand)."""

    def __init__(self, rng, barbs=6, streamers=20):
        self.t = []
        for k in range(barbs + streamers):
            side = 1.0 if k % 2 == 0 else -1.0
            barb = k < barbs
            self.t.append({
                # 0 the blade's widest .. 1 just behind its point
                "at": 0.72 + 0.26 * rng.random() if barb else rng.random() ** 0.9,
                "side": side,
                "edge": 0.6 + 0.4 * rng.random() if barb else 0.35 + 0.6 * rng.random(),
                "ang": side * math.radians(28.0 + 20.0 * rng.random() if barb else 5.0 + 19.0 * rng.random()),
                "len": (0.1 + 0.1 * rng.random()) if barb else (0.26 + 0.36 * rng.random()),
                "w": (0.011 + 0.008 * rng.random()) if barb else (0.012 + 0.018 * rng.random()),
                "i": 0.85 + 0.15 * rng.random() if barb else 0.72 + 0.28 * rng.random(),
                "heat": 0.7 + 0.25 * rng.random() if barb else 0.4 + 0.4 * rng.random(),
                "curve": 0.25 + 0.3 * rng.random() if barb else 0.45 + 0.4 * rng.random(),
                "wob": 0.1 + 0.2 * rng.random() if barb else 0.15 + 0.35 * rng.random(),
                "ph": rng.random() * 6.28,
                "barb": barb,
            })

    def draw(self, cv, x0, xw, xh, half, grow, spread, thin, inten, heat, stretch=1.0, keep=1.0, rng=None, barbs=1.0):
        for t in self.t:
            if keep < 1.0 and rng is not None and rng.random() > keep:
                continue
            x = xw + (xh - 0.03 - xw) * t["at"]
            y = t["side"] * half * blade_env(x, x0, xw, xh) * t["edge"]
            g = grow
            if t["barb"]:
                # the barbs are out from the first frame (the point is an arrowhead from the start), only shorter
                g = max(grow, 0.55) * barbs
                if g <= 0.0:
                    continue
            tongue(cv, (x, y), t["ang"] * spread, t["len"] * g * stretch, t["w"] * thin, t["i"] * inten,
                   t["heat"] * heat, t["curve"], t["wob"], t["ph"])


# ---------------------------------------------------------------- the frames

def frame(k, seed):
    rng = np.random.default_rng(seed * 31 + k * 7919)
    tg = Tongues(np.random.default_rng(seed))
    cv = Canvas()
    if k == 0:
        # the needle: the dart has just left the hand
        blade(cv, 0.42, 0.82, 1.0, 0.018, 0.6, 0.3)
        spindle(cv, 0.36, 1.0, 0.0065, 1.0, 0.95)
        tg.draw(cv, 0.42, 0.82, 1.0, 0.018, 0.25, 0.6, 0.5, 0.5, 0.8)
        for _ in range(3):
            streak(cv, 0.45 + 0.45 * rng.random(), (rng.random() - 0.5) * 0.02, math.pi + (rng.random() - 0.5) * 0.3,
                   0.03, 0.0028, 0.7, 0.8)
        ero, warp = 0.2, 0.5
    elif k == 1:
        blade(cv, 0.16, 0.7, 1.0, 0.052, 0.66, 0.22)
        spindle(cv, 0.14, 1.0, 0.014, 1.0, 0.95)
        tg.draw(cv, 0.16, 0.7, 1.0, 0.052, 0.55, 0.85, 0.75, 0.85, 0.9)
        for _ in range(5):
            streak(cv, 0.4 + 0.55 * rng.random(), (rng.random() - 0.5) * 0.05, math.pi + (rng.random() - 0.5) * 0.5,
                   0.03 + 0.03 * rng.random(), 0.003, 0.75, 0.85)
        ero, warp = 0.3, 0.8
    elif k == 2:
        # the hit: everything at once
        blade(cv, 0.05, 0.66, 1.0, 0.088, 0.7, 0.2)
        spindle(cv, 0.06, 1.0, 0.02, 1.0, 0.95)
        tg.draw(cv, 0.05, 0.66, 1.0, 0.088, 1.0, 1.0, 1.0, 1.0, 1.0)
        # the impact's sparks flung out and ahead of the point
        for _ in range(9):
            a = (rng.random() - 0.5) * 1.9
            r = 0.01 + 0.035 * rng.random()
            streak(cv, 1.0 + math.cos(a) * r * 0.5, math.sin(a) * r, a, 0.02 + 0.03 * rng.random(), 0.003, 0.9, 0.9)
        for _ in range(6):
            streak(cv, 0.35 + 0.5 * rng.random(), (rng.random() - 0.5) * 0.12, math.pi + (rng.random() - 0.5) * 0.6,
                   0.03, 0.003, 0.7, 0.75)
        ero, warp = 0.42, 1.0
    elif k == 3:
        # the hold: the flame stretched back past the reach, narrowing, cooling
        blade(cv, 0.1, 0.72, 1.06, 0.072, 0.66, 0.18)
        spindle(cv, 0.12, 1.06, 0.016, 0.92, 0.85)
        tg.draw(cv, 0.1, 0.72, 1.06, 0.072, 1.0, 0.6, 0.85, 0.92, 0.8, stretch=1.3)
        for _ in range(9):
            a = (rng.random() - 0.5) * 2.2
            r = 0.05 + 0.08 * rng.random()
            streak(cv, 1.0 + math.cos(a) * r * 0.5 - 0.08 * rng.random(), math.sin(a) * r, a, 0.025, 0.003, 0.75, 0.8)
        ero, warp = 0.55, 1.2
    elif k == 4:
        # breaking up into wisps and embers
        blade(cv, 0.4, 0.78, 1.06, 0.04, 0.45, 0.24)
        spindle(cv, 0.56, 1.06, 0.005, 0.38, 0.7)
        tg.draw(cv, 0.4, 0.78, 1.06, 0.04, 1.0, 0.45, 0.6, 0.55, 0.6, stretch=1.4, keep=0.7, rng=rng, barbs=0.0)
        for _ in range(16):
            x = 0.3 + 0.78 * rng.random() ** 0.7
            y = (rng.random() - 0.5) * 0.2 * (0.4 + x * 0.6)
            cv.blob(x, y, 0.004, 0.004, 0.65 + 0.3 * rng.random(), 0.7 + 0.2 * rng.random())
        ero, warp = 0.8, 1.4
    else:
        # the last embers drifting out
        tg.draw(cv, 0.5, 0.8, 1.06, 0.03, 1.0, 0.38, 0.42, 0.24, 0.45, stretch=1.48, keep=0.4, rng=rng, barbs=0.0)
        for _ in range(9):
            x = 0.45 + 0.65 * rng.random() ** 0.6
            y = (rng.random() - 0.5) * 0.28 * (0.4 + x * 0.6)
            r = 0.0028 + 0.002 * rng.random()
            cv.blob(x, y, r, r, 0.5 + 0.3 * rng.random(), 0.6 + 0.2 * rng.random())
        ero, warp = 0.6, 1.6
    return finish(cv, rng, ero, warp)


def finish(cv, rng, ero, warp):
    light = cv.light
    heat = np.where(cv.hden > 1e-6, cv.hnum / np.maximum(cv.hden, 1e-6), 0.0).astype(np.float32)
    # a gentle wavy warp across the stroke (flames, not tubes)
    wn = fbm(rng, 3, 2, 3) - 0.5
    dy = (wn * 10.0 * warp * SS).astype(np.float32)
    light = ndimage.map_coordinates(light, [_YY + dy, _XX], order=1, mode="constant")
    heat = ndimage.map_coordinates(heat, [_YY + dy, _XX], order=1, mode="constant")
    # eaten by streaky noise (long along the stroke, fine across it): the soft edges break into flame, the core holds
    n = fbm(rng, 5, 30, 4)
    n2 = fbm(rng, 6, 40, 3)
    eaten = light * ((1.0 - ero) + ero * 2.0 * n)
    cov = smooth(0.13, 0.5, eaten) * np.clip(light * 1.8, 0.0, 1.0)
    cov = np.clip(np.maximum(cov, smooth(0.8, 1.0, light)), 0.0, 1.0)
    hot = np.clip(heat * (0.42 + 1.15 * n2 ** 1.3) + 0.32 * smooth(0.82, 1.0, light), 0.0, 1.0) * (cov > 0.004)
    sheath = np.clip(np.maximum(ndimage.gaussian_filter(cov, 8.0 * SS) * 2.6, cov), 0.0, 1.0)

    def down(a):
        return a.reshape(FH, SS, FW, SS).mean(axis=(1, 3))
    return np.stack([down(cov), down(hot), down(sheath)], axis=-1)


# ---------------------------------------------------------------- the preview

def tint(fr, glow, body, core, bg, shade=(0.04, 0.05, 0.12), shade_a=0.75):
    """The shader's colouring (melee_burst.gdshader): deep = glow squared at heat 0, glow 0.4, body 0.78, core 1."""
    cov, h, sh = fr[..., 0:1], fr[..., 1:2], fr[..., 2:3]
    glow, body, core = (np.array(c, np.float32) for c in (glow, body, core))
    deep = glow * glow
    col = np.where(h < 0.4, deep + (glow - deep) * (h / 0.4),
                   np.where(h < 0.78, glow + (body - glow) * ((h - 0.4) / 0.38), body + (core - body) * ((h - 0.78) / 0.22)))
    out = np.ones_like(col) * np.array(bg, np.float32)
    a = np.clip(shade_a * sh, 0, 1)
    out = np.array(shade, np.float32) * a + out * (1 - a)
    return col * cov + out * (1 - cov)


def preview(frames, path):
    rows = []
    blue = ((0.36, 0.6, 1.0), (0.82, 0.92, 1.0), (1.0, 1.0, 1.0))
    fire = ((1.0, 0.45, 0.12), (1.0, 0.82, 0.45), (1.0, 1.0, 0.92))
    sand = (0.93, 0.8, 0.56)
    for fr in frames:
        data = np.concatenate([np.repeat(fr[..., c:c + 1], 3, axis=-1) for c in range(3)], axis=1)
        tinted = np.concatenate([tint(fr, *blue, (0, 0, 0)), tint(fr, *blue, sand), tint(fr, *fire, (0, 0, 0)),
                                 tint(fr, *fire, sand)], axis=1)
        rows.append(np.concatenate([data, tinted], axis=1))
    Image.fromarray((np.clip(np.concatenate(rows, axis=0), 0, 1) * 255).astype(np.uint8)).save(path)
    return path


def main():
    ap = argparse.ArgumentParser(description="The Spear's thrust flipbook (pass 142).")
    ap.add_argument("--seed", type=int, default=1420)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    frames = [frame(k, a.seed) for k in range(FRAMES)]
    img = np.concatenate(frames, axis=0)
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(a.out)
    print("wrote", a.out, img.shape[1], "x", img.shape[0])
    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        print("preview", preview(frames, os.path.join(a.preview, "thrust_frames.png")))


if __name__ == "__main__":
    main()
