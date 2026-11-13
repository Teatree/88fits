"""Pass 146 (Garry: "The Stranger ... looks too static ... a bit of an idle animation. He should look passive ... Let's make
it so he actually dies when Player agrees / doesn't. Just collapses into that thing that stays."): the Stranger's
(content/structures/hooded_figure) idle loop and his collapse, painted by Wan 2.2 first-last-frame on the AI server from
his two paintings, so nothing new is drawn by hand and both ends are the paintings themselves:

- idle: his standing painting to itself (a seamless loop: he breathes, the hem stirs), 32 frames at 16 fps, which the
  game steps as every looping strip (pass 144's held poses);
- die: his standing painting to his spent one (the empty robe in a heap, st_hooded_figure_off.png), cut to DIE_N frames
  at 12 fps, the last the spent painting exactly.

Both paintings go in at one scale and one place (the 256 px cell x2 on a 640 green screen), so every frame maps back
onto the cell without a jump.

    python tools/gen_stranger_anim.py --kind idle,die [--seeds 3] [--force]   # candidates + sheets + GIFs in tools/dl/p146/STRANGER
    python tools/gen_stranger_anim.py --pick idle=K die=K [--dry-run]       # the strip art/sprites/props/st_hooded_figure_anim.png
                                                                             # and params.anim in hooded_figure.json
"""
import argparse, io, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import artkit, animate, comfy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(REPO, "game", "art", "sprites", "props")
STILL = os.path.join(PROPS, "st_hooded_figure.png")
OFF = os.path.join(PROPS, "st_hooded_figure_off.png")
STRIP = os.path.join(PROPS, "st_hooded_figure_anim.png")
JSON_P = os.path.join(REPO, "game", "content", "structures", "hooded_figure", "hooded_figure.json")
OUT = os.path.join(REPO, "tools", "dl", "p146", "STRANGER")

CELL = 256
SIZE = 640
SCALE = 2
OFF_XY = (SIZE - CELL * SCALE) // 2
SCREEN = (0, 255, 0)
LENGTH = 33
IDLE_FPS = 16
DIE_N = 12
DIE_FPS = 12
COLS = 8
OUTLINE = (64, 46, 34, 255)
SEED0 = 14500

LOOK = ("A 2D anime game sprite of a tall, thin hooded stranger in a long, tattered dark purple robe, his face hidden in "
        "the black shadow of his hood, no face, no hands showing")
TAIL = (" The same figure, robe and colours in every frame, crisp clean line art, cel shading. The camera is completely "
        "locked off and static. The background stays a flat solid green color with nothing in it, no ground plane, no shadow.")
PROMPTS = {
    "idle": LOOK + ": he stands still in one place and waits patiently and silently. He breathes slowly, his shoulders rise "
            "and fall a little, the ragged hem of his robe stirs gently in a light breeze, his hood tilts very slightly, then "
            "he settles back exactly as he started." + TAIL,
    "die": LOOK + ": he dies. The body inside the robe is gone and the empty robe slowly crumples and collapses straight "
           "down onto the ground, folding into a flat heap of purple cloth, then it lies still." + TAIL,
}
NEG = (animate.NEGATIVE + ", a face, eyes, skin, hands, arms reaching, a person visible inside the hood, walking, turning "
       "around, extra limbs, a second figure, morphing, melting, sparkles, smoke")


def _cell(path):
    return Image.open(path).convert("RGBA")


def _canvas(cell_rgba):
    c = Image.new("RGB", (SIZE, SIZE), SCREEN)
    big = cell_rgba.resize((CELL * SCALE, CELL * SCALE), Image.LANCZOS)
    c.paste(big, (OFF_XY, OFF_XY), big)
    return c


def _back(frame_rgba):
    """A keyed 640 frame back onto the 256 cell (the inverse of _canvas)."""
    box = (OFF_XY, OFF_XY, OFF_XY + CELL * SCALE, OFF_XY + CELL * SCALE)
    return frame_rgba.crop(box).resize((CELL, CELL), Image.LANCZOS)


def _key(img):
    return artkit.key_background(img, 0.16, 0.7, cut_shadow=False)


def clip(kind, seed, force=False):
    d = os.path.join(OUT, "%s_s%d" % (kind, seed))
    os.makedirs(d, exist_ok=True)
    done = os.path.join(d, "clip.json")
    if os.path.exists(done) and not force:
        print("  cached", d)
        return d
    first = _canvas(_cell(STILL))
    last = _canvas(_cell(STILL if kind == "idle" else OFF))
    n_a = comfy.upload_pil(first, "p146_stranger_%s_first.png" % kind)
    n_b = comfy.upload_pil(last, "p146_stranger_%s_last.png" % kind)
    pngs, secs = comfy.run(animate.wan_flf(PROMPTS[kind], n_a, n_b, seed, SIZE, SIZE, LENGTH, negative=NEG,
                                           prefix="88fits/p146_stranger_" + kind), timeout=3600)
    raw = [Image.open(io.BytesIO(b)).convert("RGB") for b in pngs][:LENGTH]
    for k, im in enumerate(raw):
        im.save(os.path.join(d, "raw_%02d.png" % k))
        _back(_key(im)).save(os.path.join(d, "cell_%02d.png" % k))
    json.dump({"kind": kind, "seed": seed, "frames": len(raw), "seconds": round(secs, 1), "prompt": PROMPTS[kind]},
              open(done, "w", encoding="utf-8", newline="\n"), indent=1)
    print("  %-4s seed %-6d %5.0fs %d frames -> %s" % (kind, seed, secs, len(raw), d), flush=True)
    return d


def _cells(d):
    names = sorted(f for f in os.listdir(d) if f.startswith("cell_"))
    return [Image.open(os.path.join(d, f)).convert("RGBA") for f in names]


def _match(frames, ref_a, ref_b=None):
    """Every video frame brought to the paintings' saturation and brightness (blended from a to b along the clip)."""
    import gen_art
    s0 = gen_art.colour_stats(ref_a)
    s1 = gen_art.colour_stats(ref_b) if ref_b is not None else s0
    out = []
    n = max(1, len(frames) - 1)
    for k, f in enumerate(frames):
        q = k / n
        out.append(gen_art.match_colours(f, s0[0] * (1 - q) + s1[0] * q, s0[1] * (1 - q) + s1[1] * q))
    return out


def idle_frames(d):
    cells = _cells(d)[:LENGTH - 1]
    return [artkit.add_outline(f, 2, OUTLINE) for f in _match(cells, _cell(STILL))]


def die_frames(d):
    cells = _cells(d)
    still, off = _cell(STILL), _cell(OFF)
    feats = animate._silhouettes(cells)
    span = max(1e-6, float(np.mean(np.abs(feats[0] - feats[-1]))))
    d0 = [float(np.mean(np.abs(f - feats[0]))) for f in feats]
    d1 = [float(np.mean(np.abs(f - feats[-1]))) for f in feats]
    start = next((k for k in range(1, len(cells)) if d0[k] >= 0.12 * span), 1) - 1
    end = next((k for k in range(start + 1, len(cells)) if d1[k] < 0.06 * span), len(cells) - 1)
    idx = [start + int(round(j * (end - start) / (DIE_N - 1))) for j in range(DIE_N)]
    chosen = _match([cells[i] for i in idx], still, off)
    chosen = [artkit.add_outline(f, 2, OUTLINE) for f in chosen]
    chosen[0] = still
    chosen[-1] = off
    print("  die frames", idx, "of", len(cells))
    return chosen


def review(kind, d):
    frames = idle_frames(d) if kind == "idle" else die_frames(d)
    bg = Image.new("RGBA", (CELL, CELL), (150, 120, 90, 255))
    gif = []
    for f in frames:
        g = bg.copy()
        g.alpha_composite(f)
        gif.append(g.convert("RGB"))
    if kind == "idle":
        # as the game plays it: every 2nd frame held (pass 144 at 10 poses a second), two loops
        gif = [gif[k - k % 2] for k in range(len(gif))] * 2
    gif[0].save(os.path.join(d, "preview.gif"), save_all=True, append_images=gif[1:], duration=int(1000 / (IDLE_FPS if kind == "idle" else DIE_FPS)), loop=0)
    artkit.contact_sheet(frames, 8, 160, bg=(150, 120, 90, 255)).save(os.path.join(d, "sheet.png"))
    return frames


def install(idle_d, die_d, dry):
    idle, die = idle_frames(idle_d), die_frames(die_d)
    frames = idle + die
    rows = (len(frames) + COLS - 1) // COLS
    strip = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))
    for k, f in enumerate(frames):
        strip.alpha_composite(f, ((k % COLS) * CELL, (k // COLS) * CELL))
    js = json.load(open(JSON_P, encoding="utf-8"))
    js.setdefault("params", {})["anim"] = {
        "strip": "res://art/sprites/props/st_hooded_figure_anim.png",
        "cols": COLS, "idle": len(idle), "die": len(die),
        "fps": {"idle": IDLE_FPS, "die": DIE_FPS},
        "die_on": "closed",
        "made_by": "tools/gen_stranger_anim.py (Wan 2.2 first-last-frame) from %s and %s" % (os.path.basename(idle_d), os.path.basename(die_d)),
    }
    print("strip %dx%d, idle %d, die %d" % (strip.width, strip.height, len(idle), len(die)))
    if dry:
        return
    strip.save(STRIP)
    open(JSON_P, "w", encoding="utf-8", newline="\n").write(json.dumps(js, indent=2, ensure_ascii=False) + "\n")
    print("wrote", STRIP, "and", JSON_P)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", default="idle,die")
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--pick", nargs="*")
    ap.add_argument("--review", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if a.pick:
        p = dict(x.split("=") for x in a.pick)
        install(os.path.join(OUT, "idle_s%d" % (SEED0 + int(p["idle"]))), os.path.join(OUT, "die_s%d" % (SEED0 + int(p["die"]))), a.dry_run)
        return
    for kind in a.kind.split(","):
        for k in range(a.seeds):
            d = os.path.join(OUT, "%s_s%d" % (kind, SEED0 + k)) if a.review else clip(kind, SEED0 + k, a.force)
            if os.path.exists(os.path.join(d, "clip.json")):
                review(kind, d)


if __name__ == "__main__":
    main()
