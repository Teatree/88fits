"""The bosses' chests in 2D (pass 118, lane BOSSCHEST; Garry: "There is also a 2d drawing of the chest with an opening
animation"): each boss chest painted closed, cracked and open with Flux.2 Klein over the Blender renders of its own 3D
model (tools/blender_boss_chests.py -> tools/dl/bosschest/<boss>_<pose>.png), so the drawing and the chest in the world
are one thing. The closed chest is painted first as an img2img of its render; the cracked and the open ones are painted
from their own renders with the picked closed painting as the second reference (its look, colours and line), so the
three frames are one chest. Several seeds each, picked by eye at full size.

  python tools/gen_boss_chests.py paint closed [--only tumbleweed_king,brander] [--seeds 4] [--denoise 0.8]
      -> tools/dl/bosschest/cands/<boss>_closed_c<k>.png + review_<boss>_closed.png
  python tools/gen_boss_chests.py pick closed tumbleweed_king=2 gila_grande=0 brander=1
  python tools/gen_boss_chests.py paint poses [--only ...] [--seeds 4]
      -> <boss>_cracked_c<k>.png, <boss>_open_c<k>.png + their review sheets
  python tools/gen_boss_chests.py pick cracked tumbleweed_king=1 ...   (and: pick open ...)
  python tools/gen_boss_chests.py install [--only ...]
      -> game/art/ui/wanted/bosschest/<boss>_<closed|cracked|open>.png: keyed, punched, outlined, the three frames cut
         on one canvas (the union of their silhouettes) at one scale, so the frames swap in place and the chest
         stands on the canvas's bottom edge (ui/BossChestScreen.gd draws them on their foot)

The picks are kept in tools/dl/bosschest/picks.json. The screen colour is blue for a chest with green in it (the King's
gem, the Gila's cacti), green for the Brander's. The art of the purple chest (art/ui/wanted/boss_chest_*.png, the
Elites' since pass 118) is never touched.
"""
import io
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artkit  # noqa: E402
import comfy  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REN = os.path.join(REPO, "tools", "dl", "bosschest")
CANDS = os.path.join(REN, "cands")
PICKS = os.path.join(REN, "picks.json")
OUT = os.path.join(REPO, "game", "art", "ui", "wanted", "bosschest")
FRAMES = ("closed", "cracked", "open")
# the installed frames' width in px (the screen draws the chest about 600 px wide on a 1080 screen)
WIDTH = 640
OUTLINE_PX = 4

STYLE = ("Mobile game item icon in the style of Shop Titans and Clash Royale: one single bold treasure chest, thick clean black "
         "outline, simple chunky shapes, flat cel shading with one soft highlight, saturated high-contrast colors, seen in a "
         "three-quarter view from the front left and a little above, the whole chest in the frame with a small margin, no "
         "text, no background, no scene, no ground, no shadow")

CHESTS = {
    "tumbleweed_king": {
        "screen": "blue",
        "subject": "the royal treasure chest of the Tumbleweed King: its body woven from golden straw in a chunky basket weave, "
                   "wrapped round by two thick twisted hemp ropes, shiny gold corner caps, a gold lock plate with one round "
                   "green gem, a dry brown tumbleweed tuft tied to its side, its rounded lid made of straw strips with two gold "
                   "bands over it and a small golden king's crown set with green and red jewels sitting on top of the lid",
    },
    "gila_grande": {
        "screen": "blue",
        "subject": "the treasure chest of the Gila Grande, a giant gila monster: its body and its rounded lid covered all over in "
                   "small beaded hexagonal scales in the gila monster's pattern of black with bright orange and salmon-pink "
                   "bands and blotches, bone-white bands down its corners and over the lid, a copper lock plate shaped like a "
                   "lizard's head with two black bead eyes, a curved green cactus-arm handle on its side, a small green "
                   "saguaro cactus with two arms growing out of the top of the lid and little round green cacti with pink "
                   "flowers on the lid's front corners",
    },
    "brander": {
        "screen": "green",
        "subject": "the Brander's treasure chest, forged for an outlaw demon: black iron plates studded with round grey rivets, "
                   "two red-hot glowing orange branding marks (a ring with a cross through it) burned into its front, a heavy "
                   "dark iron chain wrapped round its middle, an iron padlock with a glowing orange keyhole hanging on its front, "
                   "its rounded black iron lid with three riveted iron straps, two glowing red-hot rings on top and a row of "
                   "short sharp iron spikes along its top and on its corners",
    },
}

POSE_WORDS = {
    "cracked": "Its lid is now lifted open just a crack, exactly as in the pose of the other reference image, a bright warm "
               "golden light shining out through the thin gap under the lid, a few small sparkles round the gap",
    "open": "Its lid is now thrown wide open and stands up at the back, exactly as in the pose of the other reference image, the "
            "chest overflowing with a heap of shiny gold coins and glowing purple, blue and pink crystal gems, bright golden "
            "light bursting up out of it",
}


def _arg(a, name, default=None):
    for i, x in enumerate(a):
        if x == "--" + name and i + 1 < len(a):
            return a[i + 1]
        if x.startswith("--" + name + "="):
            return x.split("=", 1)[1]
    return default


def _picks():
    try:
        return json.load(open(PICKS, encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_picks(p):
    json.dump(p, open(PICKS, "w", encoding="utf-8", newline="\n"), indent=1)


def _cand(boss, frame, k):
    return os.path.join(CANDS, "%s_%s_c%d.png" % (boss, frame, k))


def _upload_render(boss, pose, blue):
    p = os.path.join(REN, "%s_%s.png" % (boss, pose))
    if not os.path.exists(p):
        raise SystemExit("gen_boss_chests: no render %s (run tools/blender_boss_chests.py first)" % p)
    return comfy.upload_pil(ga.on_screen(Image.open(p), blue), comfy.safe_name("bosschest_%s_%s.png" % (boss, pose)))


def _review(boss, frame, n):
    tiles = [Image.open(_cand(boss, frame, k)).convert("RGB") for k in range(n) if os.path.exists(_cand(boss, frame, k))]
    if not tiles:
        return
    sheet = Image.new("RGB", (512 * len(tiles), 540), (30, 30, 36))
    dr = ImageDraw.Draw(sheet)
    for k, t in enumerate(tiles):
        sheet.paste(t.resize((512, 512)), (512 * k, 28))
        dr.text((512 * k + 8, 6), "%s %s c%d" % (boss, frame, k), fill=(255, 255, 255))
    sheet.save(os.path.join(REN, "review_%s_%s.png" % (boss, frame)))
    print("review", os.path.join(REN, "review_%s_%s.png" % (boss, frame)), flush=True)


def paint(stage, only, seeds, denoise, first):
    os.makedirs(CANDS, exist_ok=True)
    picks = _picks()
    for boss, job in CHESTS.items():
        if only and boss not in only:
            continue
        blue = job["screen"] == "blue"
        bg = ga.BG_BLUE if blue else ga.BG_GREEN
        frames = ["closed"] if stage == "closed" else (["cracked", "open"] if stage == "poses" else [stage])
        for frame in frames:
            pose_ref = _upload_render(boss, frame, blue)
            if frame == "closed":
                refs = [pose_ref]
                prompt = ("Repaint this exact treasure chest from the reference image as a game icon: keep its silhouette, "
                          "proportions, parts and colours, seen from the same angle. " + job["subject"] + ". " + STYLE + ". " + bg + ".")
            else:
                k = picks.get(boss, {}).get("closed")
                if k is None:
                    raise SystemExit("gen_boss_chests: pick %s's closed chest first (pick closed %s=N)" % (boss, boss))
                painted = Image.open(_cand(boss, "closed", int(k))).convert("RGB")
                style_ref = comfy.upload_pil(painted, comfy.safe_name("bosschest_%s_closed_pick.png" % boss))
                refs = [style_ref, pose_ref]
                prompt = ("The first reference image shows this exact treasure chest, painted: keep its design, parts, colours, "
                          "materials, outline and art style exactly. The second reference image shows the pose. "
                          + POSE_WORDS[frame] + ". " + job["subject"] + ". " + STYLE + ". " + bg + ".")
            for k in range(seeds):
                p = _cand(boss, frame, k)
                if os.path.exists(p):
                    continue
                seed = ga.seed_for("bosschest_%s_%s" % (boss, frame)) + first + k * 1000003
                imgs, secs = ga.paint(prompt, seed, 1024, 1024, refs, "88fits/bosschest_%s_%s" % (boss, frame),
                                      init=pose_ref, denoise=denoise)
                Image.open(io.BytesIO(imgs[0])).convert("RGB").save(p)
                json.dump({"seed": seed, "prompt": prompt, "refs": refs, "denoise": denoise, "painter": ga.painter_info()},
                          open(p[:-4] + ".json", "w", encoding="utf-8"), indent=1)
                print("  %s %s c%d seed %d %.0fs" % (boss, frame, k, seed, secs), flush=True)
            _review(boss, frame, seeds)


def pick(frame, pairs):
    picks = _picks()
    for pair in pairs:
        boss, n = pair.split("=")
        if not os.path.exists(_cand(boss, frame, int(n))):
            raise SystemExit("gen_boss_chests: no candidate %s" % _cand(boss, frame, int(n)))
        picks.setdefault(boss, {})[frame] = int(n)
        print("picked", boss, frame, "c" + n)
    _save_picks(picks)


def _despill_green(im):
    import numpy as np
    a = np.asarray(im).astype(np.int32).copy()
    g = a[..., 1]
    r = a[..., 0]
    a[..., 1] = np.minimum(g, r)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def _foot(im):
    """The middle and the bottom of a frame's body: the opaque columns of its lowest quarter (the lid never reaches it)."""
    import numpy as np
    a = np.asarray(im)[..., 3] > 128
    rows = np.nonzero(a.any(1))[0]
    if len(rows) == 0:
        return im.width * 0.5, im.height
    bottom = rows.max()
    top = rows.min()
    band = a[max(int(bottom - (bottom - top) * 0.25), 0):bottom + 1]
    cols = np.nonzero(band.any(0))[0]
    return 0.5 * (cols.min() + cols.max()), float(bottom)


def _align_bodies(frames):
    cx0, b0 = _foot(frames[0])
    out = [frames[0]]
    for im in frames[1:]:
        cx, b = _foot(im)
        dx, dy = int(round(cx0 - cx)), int(round(b0 - b))
        moved = Image.new("RGBA", im.size, (0, 0, 0, 0))
        moved.alpha_composite(im, (max(dx, 0), max(dy, 0)), (max(-dx, 0), max(-dy, 0)))
        out.append(moved)
        print("  aligned a frame by (%d, %d)" % (dx, dy))
    return out


def install(only):
    os.makedirs(OUT, exist_ok=True)
    picks = _picks()
    for boss in CHESTS:
        if only and boss not in only:
            continue
        got = picks.get(boss, {})
        if any(got.get(f) is None for f in FRAMES):
            print("  %s: not every frame is picked yet (%s)" % (boss, got))
            continue
        keyed = [artkit.punch(artkit.key_background(Image.open(_cand(boss, f, int(got[f]))).convert("RGB"), cut_shadow=False))
                 for f in FRAMES]
        if CHESTS[boss]["screen"] == "green":
            # a painted light ray the green screen tinted (the Brander's open chest): green held down to red, so it reads
            # as the gold light it is (nothing on a green-screen chest is green)
            keyed = [_despill_green(im) for im in keyed]
        # each frame's body put where the closed chest's stands (its foot's middle and its bottom), so the lid is all
        # that moves when the frames swap
        keyed = _align_bodies(keyed)
        # one canvas for the three: the union of their silhouettes, so the frames swap in place
        box = None
        for im in keyed:
            bb = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
            if bb is None:
                continue
            box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
        pad = 10
        box = (max(box[0] - pad, 0), max(box[1] - pad, 0), min(box[2] + pad, keyed[0].width), min(box[3] + pad, keyed[0].height))
        sc = WIDTH / float(box[2] - box[0])
        size = (WIDTH, int(round((box[3] - box[1]) * sc)))
        for f, im in zip(FRAMES, keyed):
            cut = im.crop(box).resize(size, Image.LANCZOS)
            cut = artkit.add_outline(cut, OUTLINE_PX)
            dst = os.path.join(OUT, "%s_%s.png" % (boss, f))
            cut.save(dst)
            print("installed", dst, cut.size)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return
    only = [x for x in (_arg(a, "only", "") or "").split(",") if x]
    if a[0] == "paint":
        paint(a[1], only, int(_arg(a, "seeds", 4)), float(_arg(a, "denoise", 0.8)), int(_arg(a, "first-seed", 0)))
    elif a[0] == "pick":
        pick(a[1], [x for x in a[2:] if "=" in x and not x.startswith("--")])
    elif a[0] == "install":
        install(only)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
