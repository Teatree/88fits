"""Pass 123 (lane BACKDROP; Garry: "Paint a sunset version of today's title scene (same desert, props and hero) and use it
behind the menus" ... "The BG should also be a bit animated, maybe a tumbleweed passes every minute or so, maybe a wind
moves some cactuses gently, maybe the sun shine. The BG should feel alive, picturesque."): the Royale theme's menu
backdrop (game/ui/wanted/RoyaleBackdrop.gd), made reproducibly.

The plate is the live title's own world (TitleStage: Red Canyon on its title roll) seen from a lower camera that shows
the horizon (game/tools/_p123_BACKDROP_ref.gd: the fort wall and the red-rock cliffs, the far scatter of the map), with
the title preset's paintings taken off; Flux.2 Klein repaints it at sunset with the capture as its reference (a guide
copy has the flat haze sky swapped for a sunset gradient and a sun where the sun should set, so every seed puts it
there). The preset's paintings come back in the game as the game's own prop pictures, cut-outs on the plate at the very
spots the capture projected them to (<ref>_props.json), graded for the sunset and swaying (the backdrop's shader). The
picture is the 20:9 canvas (1080 x 2400; a 16:9 phone shows its middle, the hero's spot kept), painted at 864 x 1920.

  GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \\
      --script res://tools/_p123_BACKDROP_ref.gd -- out=D:/_projects/88fits/tools/dl/p123/BACKDROP/ref/ref.png \\
      horizon=1040 feet=1370 hero_px=300 hero=0                       # the capture (ref.png, ref_plate.png, ref_props.json)
  python tools/gen_royale_backdrop.py --guide                         # ref/guide_plate.png (the sunset sky laid in)
  python tools/gen_royale_backdrop.py --paint [--seeds 6] [--prompt k] [--force]   # candidates + a review sheet (comfy lock)
  python tools/gen_royale_backdrop.py --pick <name>                   # the plate -> game/art/ui/royale/backdrop_plate.jpg
  python tools/gen_royale_backdrop.py --tumble [--seeds 4] [--force]  # tumbleweed candidates (keyed off blue)
  python tools/gen_royale_backdrop.py --pick-tumble <k>               # -> game/art/ui/royale/tumbleweed.png
  python tools/gen_royale_backdrop.py --manifest                      # game/art/ui/royale/backdrop.json (layers, sun, disc)
"""
import io
import json
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)

WORK = os.path.join(REPO, "tools", "dl", "p123", "BACKDROP")
REF_DIR = os.path.join(WORK, "ref")
CANDS = os.path.join(WORK, "cands")
OUT_DIR = os.path.join(REPO, "game", "art", "ui", "royale")
PLATE_OUT = os.path.join(OUT_DIR, "backdrop_plate.jpg")
TUMBLE_OUT = os.path.join(OUT_DIR, "tumbleweed.png")
MANIFEST = os.path.join(OUT_DIR, "backdrop.json")
PICKS = os.path.join(WORK, "picks.json")
# what the repo keeps (tools/dl is git-ignored): the capture's projections, the picks, the reference and the guide
ART_SRC = os.path.join(REPO, "tools", "art_src", "royale_backdrop")

# the canvas the plate is laid on (20:9) and the size it is painted at
CANVAS = (1080, 2400)
PAINT = (864, 1920)
K = PAINT[0] / CANVAS[0]          # 0.8: the capture and the painting are the canvas at this scale
# where the sun sets (canvas px of the 2400-tall canvas): left of the middle, on the low ridge, under the title's wordmark
SUN = (430.0, 770.0)
SUN_R = 118.0
# the README's sunset sky, top to the horizon
SKY = ["120c3a", "2d1a5a", "7a2a5a", "d8513f", "f7a33a", "ffd27a"]
SEED = 12301
# pass 123, Garry: "Make the environment art a bit Sparser": the paintings of the preset the backdrop keeps
# Pass 124 (Garry: "look at the bg critically ... see if when it comes to rules of composition there is room for improvement"). The
# capture's five props stood in one flat row at one depth, a rock and a bush level with the hero like dumb-bells, the two tall plants
# the same size either side. Laid out by hand now, in three depths: a dark near saguaro cut by the right edge against the sun on the
# left (one big shape balancing the bright one, a line that leads the eye down to the hero); a smaller Joshua tree and a far hazy
# ocotillo to the left that step back into the distance; a near bush in the bottom-left corner closing the frame. The middle stays
# clear for the hero. (look, base x, base y on the 1080 x 2400 plate, picture height px, wind, how dark, flip.)
PROPS_LAYOUT = [
    ("ocotillo_b", 322.0, 1136.0, 120.0, 0.03, 0.96, False),
    ("joshua_tree_b", 118.0, 1236.0, 300.0, 0.02, 0.9, False),
    ("rock_small", 262.0, 1352.0, 66.0, 0.0, 0.92, False),
    ("saguaro_big", 988.0, 1500.0, 660.0, 0.012, 0.62, False),
    ("dead_shrub_b", 40.0, 1668.0, 330.0, 0.03, 0.5, False),
]

PROMPTS = {
    "sunset": (
        "Repaint this exact desert scene at sunset, keeping the same composition, camera and layout: the same open sand "
        "dunes in front, the same low stone fort wall and wooden posts along the horizon, the same red-rock canyon cliffs "
        "and mesas behind it, the same small far trees and cacti. Change only the time of day to a warm golden sunset: a "
        "large glowing orange-gold sun low in the sky, setting just above the far cliffs left of centre, exactly where it "
        "is in the reference; the sky a smooth gradient from deep violet and indigo at the top through magenta and rose "
        "to hot orange and gold near the horizon, a few thin glowing streaks of cloud lit pink and gold from below. The "
        "cliffs in warm violet shadow with a bright orange rim of light along their ridges, a soft warm haze between the "
        "cliffs and the wall. The sand lit warm orange, peach and rose, with long soft violet shadows in the dune hollows "
        "and gentle golden highlights on the crests, the light raking towards the viewer. Picturesque, calm, inviting. "
        "Painted illustration in the clean stylized cel-shaded art style of a mobile video game background, soft painterly "
        "gradients, crisp simple shapes. No people, no characters, no animals, no text, no letters, no UI, no border."),
    "golden": (
        "Repaint this exact desert scene at the golden hour just before sunset, keeping the same composition, camera and "
        "layout: the same open sand dunes, the same stone fort wall and posts on the horizon, the same red-rock cliffs "
        "behind, the same small far trees and cacti. A big soft glowing sun sits low over the far cliffs left of centre, "
        "where it is in the reference, with a warm halo; the sky blends from violet-blue at the top through pink and "
        "coral to bright gold at the horizon, with a few long thin clouds glowing peach. Warm orange light rakes across "
        "the sand towards the viewer, every dune crest glows gold and the hollows hold long cool purple shadows; the "
        "cliffs are dusky rose and violet with glowing orange edges. Picturesque and peaceful. Painted mobile game "
        "background, clean stylized cel shading, smooth painterly gradients, simple readable shapes. No people, no "
        "characters, no animals, no text, no UI, no border."),
}

# pass 123, Garry on the first picks: "The BG is a bit too busy right now and is a bit brighter than I expected. I'd want it
# to be a bit darker"
PROMPTS["dusk"] = (
    "Repaint this exact desert scene in the last minutes of sunset, keeping the same composition, camera and layout: the "
    "same open sand in front, the same low stone fort wall on the horizon, the same red-rock cliffs behind it. The light is "
    "low and dim: the sun has almost set, a deep orange-red disc half hidden by haze just above the far cliffs left of "
    "centre, where it is in the reference, with a soft restrained glow. The sky is a calm smooth gradient from dark indigo "
    "at the top through deep violet and dusky plum to a muted burnt orange at the horizon, with at most one or two faint thin "
    "clouds. The cliffs are dark violet silhouettes with only a thin dim orange edge. The sand is in evening shade, dark "
    "dusky plum and muted rose with a calm, smooth, almost flat surface, very gentle dunes, no large shadow shapes, only a "
    "faint warm glow on the sand towards the sun. Sparse, quiet, uncluttered, plenty of empty calm space. Painted mobile "
    "game background, clean stylized cel shading, smooth painterly gradients, simple shapes. No people, no characters, no "
    "animals, no rocks in the foreground, no text, no UI, no border.")

PROMPTS["evening"] = (
    "Repaint this exact desert scene at sunset, a little darker than golden hour, keeping the same composition, camera and "
    "layout: the same open sand in front, the same low stone fort wall on the horizon, the same red-rock cliffs behind it. "
    "A large warm orange sun sits low just above the far cliffs left of centre, where it is in the reference, with a soft "
    "warm glow around it. The sky is a calm smooth gradient from deep indigo at the top through violet and rich magenta to a "
    "warm orange glow at the horizon, with only one or two soft thin clouds. The cliffs are dusky violet with a warm orange "
    "edge along their ridges. The sand is calm and smooth in warm dusky rose and muted amber, darker towards the viewer, "
    "gentle wide dunes, soft low contrast, no large dark shadow shapes, a warm glow on the sand under the sun. Sparse, "
    "quiet, picturesque, plenty of calm empty space. Painted mobile game background, clean stylized cel shading, smooth "
    "painterly gradients, simple shapes. No people, no characters, no animals, no rocks in the foreground, no text, no UI, "
    "no border.")

TUMBLE_PROMPT = (
    "Using exactly the same art style, rendering, line art, cel shading, palette and level of detail as the reference "
    "image, draw a new desert prop for the same game: a single dry tumbleweed, a round airy ball of thin tangled dry "
    "brown and tan twigs and stems, light and see-through between the twigs, a little lopsided, no face, no eyes, not a "
    "character, just the plant. Seen from the side, the whole ball visible, nothing else in the frame. ")


ARGS = sys.argv[1:]


def arg(name, default=None):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default


FORCE = "--force" in ARGS


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def log(msg):
    print(msg, flush=True)


# ---------------------------------------------------------------- the guide

def sky_mask(img):
    """The capture's sky: the flat haze colour, connected to the top edge."""
    import cv2
    a = np.asarray(img.convert("RGB")).astype(np.int32)
    sky = a[4, 4]
    close = (np.abs(a - sky).sum(2) <= 18).astype(np.uint8)
    n, lab = cv2.connectedComponents(close, connectivity=4)
    top = set(np.unique(lab[0][close[0] > 0]).tolist())
    m = np.isin(lab, list(top)) & (close > 0)
    return m


def sunset_sky(w, h, horizon):
    """The README's gradient from the top to the horizon (then the last stop), a sun's glow at SUN."""
    stops = [hexc(c) for c in SKY]
    y = np.arange(h, dtype=np.float32)[:, None] / max(1.0, horizon)
    y = np.clip(y, 0.0, 1.0) * (len(stops) - 1)
    i0 = np.clip(np.floor(y).astype(int), 0, len(stops) - 2)
    t = (y - i0)[..., None]
    s0 = np.stack(stops)[i0]
    s1 = np.stack(stops)[i0 + 1]
    col = s0 * (1.0 - t) + s1 * t
    col = np.repeat(col, w, axis=1)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    sx, sy, sr = SUN[0] * K, SUN[1] * K, SUN_R * K
    d = np.sqrt((xx - sx) ** 2 + (yy - sy) ** 2)
    glow = np.exp(-np.maximum(d - sr, 0.0) / (sr * 2.2))[..., None]
    col = col * (1.0 - 0.55 * glow) + hexc("ffd27a") * 0.55 * glow
    disc = np.clip((sr - d) / 3.0, 0.0, 1.0)[..., None]
    col = col * (1.0 - disc) + hexc("fff1c4") * disc
    return col


def guide():
    src = os.path.join(REF_DIR, "ref_plate.png")
    img = Image.open(src).convert("RGB")
    w, h = img.size
    m = sky_mask(img)
    rows = np.nonzero(m.any(1))[0]
    horizon = float(rows.max()) if len(rows) else h * 0.4
    sky = sunset_sky(w, h, horizon)
    a = np.asarray(img).astype(np.float32)
    # the land a warm, darker sunset grade (so the model reads the light), the sky the gradient
    land = a * np.array([1.0, 0.78, 0.66], np.float32) * 0.86
    land = land + np.array([28, 6, 22], np.float32) * (np.arange(h, dtype=np.float32)[:, None, None] / h)
    mm = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    mk = (np.asarray(mm).astype(np.float32) / 255.0)[..., None]
    out = sky * mk + land * (1.0 - mk)
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(os.path.join(REF_DIR, "guide_plate.png"))
    log("guide -> %s (sky to y %d of %d)" % (os.path.join(REF_DIR, "guide_plate.png"), horizon, h))


# ---------------------------------------------------------------- the paintings

def paint():
    import comfy
    os.makedirs(CANDS, exist_ok=True)
    seeds = int(arg("--seeds", "6"))
    keys = arg("--prompt", "sunset,golden").split(",")
    which = arg("--ref", "guide")
    refp = os.path.join(REF_DIR, "guide_plate.png" if which == "guide" else "ref_plate.png")
    ref = comfy.upload_pil(Image.open(refp).convert("RGB"), "p123_backdrop_%s.png" % which)
    made = []
    for key in keys:
        for k in range(seeds):
            s = SEED + k * 977 + (0 if key == "sunset" else 50000)
            name = "plate_%s_%s_s%d" % (key, which, s)
            out = os.path.join(CANDS, name + ".png")
            if os.path.exists(out) and not FORCE:
                made.append(name)
                continue
            t0 = time.time()
            imgs, _ = comfy.run(comfy.klein(PROMPTS[key], s, PAINT[0], PAINT[1], refs=[ref], prefix="88fits/p123_backdrop"))
            Image.open(io.BytesIO(imgs[0])).convert("RGB").save(out)
            log("  %s %.0fs" % (name, time.time() - t0))
            made.append(name)
    sheet(made, os.path.join(CANDS, "review_%s.png" % which))


def sheet(names, path):
    tw, th = 288, 640
    cols = min(6, max(1, len(names)))
    rows = (len(names) + cols - 1) // cols
    sh = Image.new("RGB", (cols * (tw + 12) + 12, rows * (th + 40) + 12), (24, 20, 32))
    dr = ImageDraw.Draw(sh)
    for i, n in enumerate(names):
        im = Image.open(os.path.join(CANDS, n + ".png")).convert("RGB").resize((tw, th), Image.LANCZOS)
        x = 12 + (i % cols) * (tw + 12)
        y = 12 + (i // cols) * (th + 40)
        sh.paste(im, (x, y))
        dr.text((x + 2, y + th + 6), n.replace("plate_", ""), fill=(240, 230, 210))
    sh.save(path)
    log("review -> %s" % path)


def pick(name):
    src = os.path.join(CANDS, name + ".png")
    im = Image.open(src).convert("RGB").resize(CANVAS, Image.LANCZOS)
    os.makedirs(OUT_DIR, exist_ok=True)
    im.save(PLATE_OUT, quality=90, optimize=True, progressive=False)
    picks = json.load(open(PICKS, encoding="utf-8")) if os.path.exists(PICKS) else {}
    picks["plate"] = name
    json.dump(picks, open(PICKS, "w", encoding="utf-8", newline="\n"), indent=1)
    log("plate: %s -> %s (%d KB)" % (name, PLATE_OUT, os.path.getsize(PLATE_OUT) // 1024))


# ---------------------------------------------------------------- the tumbleweed

def tumble():
    import comfy
    import gen_art as ga
    os.makedirs(CANDS, exist_ok=True)
    seeds = int(arg("--seeds", "4"))
    refs = list(ga.ensure_anchor_uploaded())
    p = os.path.join(REPO, "game", "art", "sprites", "props", "dead_shrub.png")
    shrub = Image.open(p).convert("RGBA")
    flat = Image.new("RGB", shrub.size, (0, 0, 255))
    flat.paste(shrub, (0, 0), shrub)
    refs.append(comfy.upload_pil(flat, "p123_tumble_ref.png"))
    out_cells = []
    for k in range(seeds):
        s = SEED + 700 + k * 131
        raw = os.path.join(CANDS, "tumble_raw_s%d.png" % s)
        if not os.path.exists(raw) or FORCE:
            t0 = time.time()
            prompt = TUMBLE_PROMPT + ga.STYLE + ". " + ga.BG_BLUE + "."
            imgs, _ = comfy.run(comfy.klein(prompt, s, 1024, 1024, refs=refs, prefix="88fits/p123_tumble"))
            Image.open(io.BytesIO(imgs[0])).convert("RGB").save(raw)
            log("  tumble s%d %.0fs" % (s, time.time() - t0))
        cell, _ = ga.finish(Image.open(raw).convert("RGB"), 256, 0.92, False, None, 0.007, None, (70, 46, 30, 230))
        cell.save(os.path.join(CANDS, "tumble_c%d.png" % k))
        out_cells.append(cell)
    sh = Image.new("RGBA", (len(out_cells) * 276 + 20, 300), (214, 140, 96, 255))
    dr = ImageDraw.Draw(sh)
    for i, c in enumerate(out_cells):
        sh.alpha_composite(c, (20 + i * 276, 10))
        dr.text((24 + i * 276, 276), "c%d" % i, fill=(30, 16, 10, 255))
    sh.save(os.path.join(CANDS, "tumble_review.png"))
    log("tumble review -> %s" % os.path.join(CANDS, "tumble_review.png"))


def pick_tumble(k):
    os.makedirs(OUT_DIR, exist_ok=True)
    Image.open(os.path.join(CANDS, "tumble_c%d.png" % k)).save(TUMBLE_OUT)
    picks = json.load(open(PICKS, encoding="utf-8")) if os.path.exists(PICKS) else {}
    picks["tumbleweed"] = "tumble_c%d" % k
    json.dump(picks, open(PICKS, "w", encoding="utf-8", newline="\n"), indent=1)
    log("tumbleweed: c%d -> %s" % (k, TUMBLE_OUT))


# ---------------------------------------------------------------- the manifest

def find_sun(img, guess, r_guess):
    """The painted sun: the largest bright warm blob near where it was asked for (centre and radius, canvas px)."""
    import cv2
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    lum = a @ np.array([0.299, 0.587, 0.114], np.float32)
    gx, gy = guess[0] * K, guess[1] * K
    win = int(r_guess * K * 2.6)
    y0, y1 = max(0, int(gy - win)), min(a.shape[0], int(gy + win))
    x0, x1 = max(0, int(gx - win)), min(a.shape[1], int(gx + win))
    sub = lum[y0:y1, x0:x1]
    thr = max(200.0, float(np.percentile(sub, 97)) - 6.0)
    m = (sub >= thr).astype(np.uint8)
    n, lab, stats, cent = cv2.connectedComponentsWithStats(m, 8)
    if n <= 1:
        return list(guess), r_guess
    best = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    cx, cy = cent[best]
    # the disc's radius from its width (its foot may sink behind the ridge)
    w = stats[best, cv2.CC_STAT_WIDTH]
    r = w * 0.5
    return [round((x0 + cx) / K, 1), round((y0 + cy) / K, 1)], round(r / K, 1)


def sky_mask_out(path_out):
    """The capture's sky (a ridge line the painting follows), a little tighter, soft, at a quarter size."""
    ref = os.path.join(REF_DIR, "ref_plate.png")
    if not os.path.exists(ref):
        if os.path.exists(path_out):
            return
        ref = os.path.join(ART_SRC, "ref_plate.jpg")
    m = sky_mask(Image.open(ref))
    im = Image.fromarray((m * 255).astype(np.uint8))
    im = im.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(10))
    # the rect the sun's shine covers: the plate's top to the horizon + 220 (canvas px), at a quarter of the canvas
    src = REF_DIR if os.path.exists(os.path.join(REF_DIR, "ref_props.json")) else ART_SRC
    h_canvas = int(json.load(open(os.path.join(src, "ref_props.json")))["horizon"]) + 220
    im = im.resize((CANVAS[0] // 4, int(CANVAS[1] // 4)), Image.LANCZOS)
    im = im.crop((0, 0, CANVAS[0] // 4, h_canvas // 4))
    im.save(path_out)


def keep_sources():
    import shutil
    os.makedirs(ART_SRC, exist_ok=True)
    for name in ("ref_props.json",):
        if os.path.exists(os.path.join(REF_DIR, name)):
            shutil.copy(os.path.join(REF_DIR, name), os.path.join(ART_SRC, name))
    if os.path.exists(PICKS):
        shutil.copy(PICKS, os.path.join(ART_SRC, "picks.json"))
    for name in ("ref_plate.png", "guide_plate.png"):
        p = os.path.join(REF_DIR, name)
        if os.path.exists(p):
            Image.open(p).convert("RGB").save(os.path.join(ART_SRC, name[:-4] + ".jpg"), quality=88)


def foot_of(look):
    """Where a picture's foot really is: its empty rows under the foot (a share of the height), the foot's middle from the picture's
    middle and its width (shares of the width), from the lowest eighth of what is painted."""
    im = Image.open(os.path.join(REPO, "game", "art", "sprites", "props", look + ".png")).convert("RGBA")
    a = np.array(im)[:, :, 3] > 128
    ys = np.where(a.any(axis=1))[0]
    y0, y1 = int(ys.min()), int(ys.max())
    band = a[max(y1 - (y1 - y0) // 8, 0): y1 + 1]
    xs = np.where(band.any(axis=0))[0]
    return dict(foot_up=round((im.height - 1 - y1) / im.height, 4), foot_x=round((float(xs.mean()) - im.width * 0.5) / im.width, 4),
                foot_w=round((int(xs.max()) - int(xs.min()) + 1) / im.width, 4))


def manifest():
    src = REF_DIR if os.path.exists(os.path.join(REF_DIR, "ref_props.json")) else ART_SRC
    info = json.load(open(os.path.join(src, "ref_props.json"), encoding="utf-8"))
    pk = PICKS if os.path.exists(PICKS) else os.path.join(ART_SRC, "picks.json")
    picks = json.load(open(pk, encoding="utf-8")) if os.path.exists(pk) else {}
    cand = os.path.join(CANDS, picks.get("plate", "") + ".png")
    plate_img = Image.open(cand) if picks.get("plate") and os.path.exists(cand) else None
    sun, sun_r = (list(SUN), SUN_R)
    if plate_img is not None:
        sun, sun_r = find_sun(plate_img, SUN, SUN_R)
    # find_sun misses a soft-edged sun (the evening plate): measured by hand, kept over a rewrite
    if os.path.exists(MANIFEST):
        old_m = json.load(open(MANIFEST, encoding="utf-8"))
        if sun_r < 30.0 and float(old_m.get("sun_radius", 0.0)) >= 30.0:
            sun, sun_r = old_m["sun_center"], old_m["sun_radius"]
    os.makedirs(OUT_DIR, exist_ok=True)
    sky_mask_out(os.path.join(OUT_DIR, "backdrop_sky.png"))
    props = []
    for look, bx, by, hpx, sway, dark, flip in PROPS_LAYOUT:
        props.append(dict(id=look, look=look, texture="res://art/sprites/props/%s.png" % look, base=[bx, by], height_px=hpx, flip=flip,
                          sway=sway, dark=dark, shadow_a=0.5, **foot_of(look)))
    feet = info["feet_px"]
    out = {
        "_doc": "Pass 123 (lane BACKDROP): the Royale menu backdrop's layers (game/ui/wanted/RoyaleBackdrop.gd), written by "
                "tools/gen_royale_backdrop.py --manifest. Canvas px of the 1080 x 2400 plate. props: the title preset's "
                "paintings where the capture projected them (base = the foot's middle, height_px = the picture's square). "
                "grade / sun / motes: shader parameters laid over the shaders' defaults.",
        "plate": "res://art/ui/royale/backdrop_plate.jpg",
        "sky_mask": "res://art/ui/royale/backdrop_sky.png",
        "tumbleweed": "res://art/ui/royale/tumbleweed.png",
        "canvas": list(CANVAS),
        "horizon_y": info["horizon"], "feet_y": info["feet_y"], "hero_px": info["hero_px"],
        "disc_center": [feet[0], feet[1] + 30.0],
        "sun_center": sun, "sun_radius": sun_r,
        "tumble_lane": [1290.0, 1335.0],
        "preset": info["preset"],
        "props": props,
        "grade": {}, "shadow": {"color": "#1a0c24", "alpha": 0.62, "length": 0.62, "width": 0.34, "flat": 0.42, "contact": 0.7,
                                "blur_near": 0.008, "blur_far": 0.055},
        "sun": {}, "motes": {"rect": [0, 760, 1080, 760]},
        "source": {"capture": "game/tools/_p123_BACKDROP_ref.gd horizon=%s feet=%s hero_px=%s" % (
            info["horizon"], info["feet_y"], info["hero_px"]), "picks": picks},
    }
    if os.path.exists(MANIFEST):
        old = json.load(open(MANIFEST, encoding="utf-8"))
        # hand-tuned numbers survive a rewrite
        for k in ("grade", "sun", "motes", "tumble_lane", "disc_center"):
            if k in old:
                out[k] = old[k]
    json.dump(out, open(MANIFEST, "w", encoding="utf-8", newline="\n"), indent=1)
    log("manifest -> %s (sun %s r %s, %d props)" % (MANIFEST, sun, sun_r, len(props)))


if __name__ == "__main__":
    if "--guide" in ARGS:
        guide()
    elif "--paint" in ARGS:
        paint()
    elif "--pick" in ARGS:
        pick(arg("--pick"))
    elif "--tumble" in ARGS:
        tumble()
    elif "--pick-tumble" in ARGS:
        pick_tumble(int(arg("--pick-tumble")))
    elif "--manifest" in ARGS:
        manifest()
    else:
        print(__doc__)
