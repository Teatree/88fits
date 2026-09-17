"""88fits art pipeline v2: anime-style sprites and icons, generated with Flux.2 Klein 9B on the ComfyUI server
and locked to ONE style anchor image so every asset shares the same look.

Stages (each cached in tools/dl/ai_raw2/, so a re-run only paints what is missing):
  anchor      `--anchor` paints 4 style-sheet candidates (tools/dl/review/anchor_candidates.png); `--pick=N` installs one as
              game/art/style/style_anchor.png. Every later render passes the anchor as a reference image.
  items       weapons, evolutions, passives, shop, elites, maps, quests -> one icon render each -> <id>_icon.png
  creatures   enemies, bosses -> one front-view render -> strip (idle 2, run 2, attack 2, hit, die) + icon
  characters  front view (portrait icon + identity reference) -> back, side, back-diagonal and front-diagonal views
              (edits of the front) -> every view animated by Wan 2.2 image-to-video (tools/animate.py: the still runs
              in place, the loop is cut into 8 frames) -> cheer -> strip (idle 4 + run 8 per view, hit, die, cheer).
              The game picks the view from the direction of travel relative to the camera (diagonals mirrored).
  creatures   front view -> back view (edit) -> both animated by video (walk in place, 8 frames) -> strip
              (idle 4, run 8, attack 2, hit, die, run_b 8, idle_b 4) + icon
  qa          every render is checked by the local vision model (one subject, not cropped, no text, right view);
              failures are re-rolled with a new seed, up to 3 times. `--skip-qa` turns it off.
  review      tools/dl/review/{icons,strips,phone}.png, phone.png shows sprites at their on-screen pixel size.
  import      godot --import + tools/import_json.gd (skip with --no-import)

Run:  python tools/gen_art.py [--only id,id] [--force] [--keys=k1,k2] [--seed=N] [--anchor] [--pick=N] [--no-anchor-ref] [--skip-qa] [--no-import]
The JSON `art_prompt` of each content item is the source of truth for what gets painted.
"""
import base64, glob, hashlib, io, json, os, subprocess, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy, artkit, animate
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT = os.path.join(REPO, "game", "content")
STYLE_ID = "anime"          # raw renders are cached per style so a restyle never reuses old paintings
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_" + STYLE_ID)
REVIEW = os.path.join(REPO, "tools", "dl", "review")
ANCHOR = os.path.join(REPO, "game", "art", "style", "style_anchor.png")
LMSTUDIO = "http://127.0.0.1:1234/v1/chat/completions"
VISION_MODEL = "qwen2.5-vl-7b-instruct-abliterated"

STYLE = ("in a clean modern anime art style: crisp confident line art, cel shading with two-tone shadows and sharp highlights, flat "
         "saturated colors, appealing stylized proportions, simple readable shapes with no texture noise, like character art from a "
         "Japanese action RPG mobile game. Game asset")
BG_GREEN = ("isolated on a flat solid bright green (#00FF00) background that fills the entire frame, floating in empty space with no ground "
            "plane, no cast shadow, no grass, no text, no watermark")
BG_BLUE = BG_GREEN.replace("bright green (#00FF00)", "bright blue (#0000FF)")
ICON_STYLE = ("Mobile game item icon in the style of Shop Titans: one single bold object, thick clean black outline, simple chunky shapes, "
              "flat cel shading with one soft highlight, saturated high-contrast colors, centered and filling the frame with a small margin, "
              "readable at thumbnail size, no text, no background, no scene")

# run cycles: more frames from the same clip means smoother motion at the same cycle length
HERO_RUN_FRAMES, HERO_RUN_FPS = 24, 36
HERO_HIT_FPS = 12
CREATURE_RUN_FRAMES, CREATURE_RUN_FPS = 12, 15
FORCE = "--force" in sys.argv
SKIP_QA = "--skip-qa" in sys.argv
NO_IMPORT = "--no-import" in sys.argv
NO_VIDEO = "--no-video" in sys.argv      # skip the Wan clips (procedural cycles instead)
USE_ANCHOR = "--no-anchor-ref" not in sys.argv
ONLY, SEED_OFFSET, PICK = None, 0, None
for a in sys.argv:
    if a.startswith("--only="):
        ONLY = a.split("=", 1)[1].split(",")
    if a.startswith("--seed="):
        SEED_OFFSET = int(a.split("=", 1)[1])
    if a.startswith("--pick="):
        PICK = int(a.split("=", 1)[1])
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
FORCE_KEYS = []          # --keys=drifter_st1,drifter_sts1 re-renders just those cache keys (combine with --seed=N for fresh rolls)
for a in sys.argv:
    if a.startswith("--keys="):
        FORCE_KEYS = a.split("=", 1)[1].split(",")

ANCHOR_REF = "88fits/style_anchor.png"
_anchor_uploaded = False


def log(*a):
    print(*a, flush=True)


# ---------------------------------------------------------------- prompts

def anchor_prompt():
    return ("A game art style sheet on a flat solid bright green (#00FF00) background: five different subjects standing in a row with empty "
            "space between them, all the same height, all facing the viewer: a lean young man with messy dark hair in a long tan trench coat "
            "with the collar up and a dark red scarf, a tan coyote with big ears and a mischievous grin, a walking green cactus with a "
            "worried face, a wooden double-barreled shotgun, and a golden stopwatch. All five rendered in exactly the same " + STYLE +
            ". No ground, no shadows, no text.")


def bg_for(d, type_=""):
    # heroes wear olive, khaki and brown: those sit next to green, so characters always get the blue screen
    if type_ == "characters":
        return BG_BLUE
    ph = d.get("placeholder", {})
    for key in ("color", "hat", "outline"):
        col = str(ph.get(key, "")).lstrip("#")
        if len(col) != 6:
            continue
        r, g, b = int(col[0:2], 16) / 255, int(col[2:4], 16) / 255, int(col[4:6], 16) / 255
        import colorsys
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if s > 0.25 and 0.2 < h < 0.48:
            return BG_BLUE
    return BG_GREEN


def subject_for(d, type_):
    if d.get("art_prompt"):
        return d["art_prompt"]
    name = d.get("name", d.get("id", "thing"))
    fl = d.get("flavour", "").lower().rstrip(".")
    if type_ in ("enemies", "bosses"):
        return "a goofy %s creature, %s" % (name.lower(), fl)
    if type_ == "characters":
        return "a small goofy hero called %s, %s" % (name, fl)
    return "a game item icon of %s, a single object" % name.lower()


def seed_for(key):
    return sum(ord(c) * (i + 7) for i, c in enumerate(key)) % 999983 + 100 + SEED_OFFSET * 7919


def styled(subject, view_hint, bg, with_anchor=True):
    if with_anchor and USE_ANCHOR:
        return ("Using exactly the same art style, rendering, shading, palette and outline treatment as the reference image, draw a new subject: "
                + subject + ". " + view_hint + " " + STYLE + ". " + bg + ". Do not copy any subject from the reference.")
    return subject + ". " + view_hint + " " + STYLE + ". " + bg + "."


# ---------------------------------------------------------------- vision QA

def vision_json(img, question, max_tokens=220):
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "PNG")
    body = {"model": VISION_MODEL, "max_tokens": max_tokens, "temperature": 0, "messages": [{"role": "user", "content": [
        {"type": "text", "text": question},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()}}]}]}
    req = urllib.request.Request(LMSTUDIO, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    txt = json.load(urllib.request.urlopen(req, timeout=300))["choices"][0]["message"]["content"]
    txt = txt.strip().strip("`")
    if txt.startswith("json"):
        txt = txt[4:]
    i, j = txt.find("{"), txt.rfind("}")
    return json.loads(txt[i:j + 1]) if i >= 0 and j > i else {}


def qa(img, expect):
    """expect: {'subject': str, 'view': 'front'|'back'|None, 'subjects_max': int}. Returns (passed, report)."""
    if SKIP_QA:
        return True, {"skipped": True}
    q = ("You are checking a generated video game asset. Answer ONLY with one JSON object, no prose, with keys: "
         "subjects (integer, how many separate characters or objects are shown), "
         "background (\"flat\" if the background is a single flat color, otherwise \"scene\"), "
         "ground (true if a floor, ground plane, grass or a cast shadow is drawn under the subject), "
         "text (true if any letters, numbers or a watermark appear), "
         "cropped (true if part of the main subject is cut off by the image border), "
         "legs (true if the subject's legs and feet are both completely visible and drawn, false if any limb is missing or cut off), "
         "view (\"front\" if the main subject's face or front is towards the viewer, \"back\" if it is seen from behind with no face visible, "
         "\"side\" for a profile, else \"other\"), "
         "matches (true if the image clearly shows: %s)." % expect.get("subject", "the requested subject"))
    try:
        r = vision_json(img, q)
    except Exception as e:
        log("  (vision QA failed: %s)" % e)
        return True, {"error": str(e)}
    problems = []
    n = int(r.get("subjects", 1) or 1)
    if n > int(expect.get("subjects_max", 1)):
        problems.append("subjects=%d" % n)
    if r.get("background") == "scene":
        problems.append("scene")
    if r.get("text"):
        problems.append("text")
    if r.get("cropped"):
        problems.append("cropped")
    if r.get("matches") is False:
        problems.append("no-match")
    if expect.get("view") and r.get("view") and r.get("view") != expect["view"]:
        problems.append("view=%s" % r.get("view"))
    if expect.get("legs") and r.get("legs") is False:
        problems.append("legs")
    r["problems"] = problems
    return len(problems) == 0, r


# ---------------------------------------------------------------- rendering with cache + retries

def geometry(img):
    """Where the keyed figure sits in the frame: margins to every edge and its size, in pixels."""
    a = np.asarray(artkit.key_background(img))[..., 3] > 127
    ys, xs = np.nonzero(a)
    if len(xs) == 0:
        return {"empty": True}
    h, w = a.shape
    return {"left": int(xs.min()), "right": int(w - 1 - xs.max()), "top": int(ys.min()), "bottom": int(h - 1 - ys.max()),
            "height": int(ys.max() - ys.min()), "width": int(xs.max() - xs.min())}


def figure_height(img):
    return geometry(img).get("height", 0)


def figure_height_cell(cell_img):
    a = np.asarray(cell_img)[..., 3] > 127
    ys = np.nonzero(a.max(axis=1))[0]
    return float(ys.max() - ys.min()) if len(ys) else 0.0


def video_cycle(still_rgb, key, motion, seed, cell, stand_cell, n_out=12, outline_frac=0.012, outline_color=(38, 24, 30, 255), length=81):
    """A run/walk cycle from a Wan clip of the still, scaled so the figure matches its standing cell; None on failure."""
    if NO_VIDEO:
        return None
    try:
        frames, meta = animate.cycle(still_rgb, key, motion, seed, n_out, length=length)
    except Exception as e:
        log("  (video cycle failed for %s: %s)" % (key, e))
        return None
    # the still was scaled to 72% of the 640 px clip; match the standing figure's cell height
    scale = figure_height_cell(stand_cell) / max(1.0, animate_still_height(still_rgb))
    px = max(1, int(round(cell * outline_frac)))
    return artkit.place_clip_frames(frames, cell, scale, px, outline_color)


DRIVERS = os.path.join(REPO, "tools", "dl", "drivers")


def pose_cycle(still_rgb, key, clip, view, seed, cell, stand_cell, hint, outline_frac=0.012, outline_color=(38, 24, 30, 255), negative_extra="", loop=True, motion="running in place on the spot like on a treadmill"):
    """A run/walk cycle from Wan Animate driven by the Mixamo stride in tools/dl/drivers/<clip>/<view> (see
    tools/pose_driver.py): every driver frame is a sprite frame, so the count and cadence are exact in every view.
    Falls back to the free video cycle when the drivers are missing; None on failure."""
    if NO_VIDEO:
        return None
    driver_dir = os.path.join(DRIVERS, clip, view)
    if not os.path.isdir(driver_dir):
        log("  (no drivers in %s, falling back to a free clip)" % driver_dir)
        return None
    try:
        frames, meta = animate.cycle_pose(still_rgb, key, driver_dir, seed, prompt_hint=hint, negative_extra=negative_extra, loop=loop, motion=motion)
    except Exception as e:
        log("  (pose cycle failed for %s: %s)" % (key, e))
        return None
    # Wan Animate draws the figure on the driver skeleton, which is nose-to-ankle: the painted body comes out about a
    # head taller than the still placed at the same fill. Measure the tallest frame and fit it to the standing figure.
    tallest = max(1.0, max(_alpha_height(f) for f in frames))
    scale = figure_height_cell(stand_cell) * 0.99 / tallest
    px = max(1, int(round(cell * outline_frac)))
    return artkit.place_clip_frames(frames, cell, scale, px, outline_color)


def _alpha_height(frame_rgba):
    a = np.asarray(frame_rgba)[..., 3]
    rows = np.nonzero(a.max(axis=1) > 127)[0]
    return float(rows.max() - rows.min() + 1) if len(rows) else 0.0


def animate_still_height(still_rgb):
    """Height in clip pixels of the figure as tools/animate.py placed it (fill 0.72 of a 640 px canvas)."""
    keyed = artkit.crop_alpha(artkit.key_background(still_rgb))
    s = min(640 * 0.72 / keyed.width, 640 * 0.72 / keyed.height)
    return keyed.height * s


def render(key, prompt, refs, expect, seed, width=1024, height=1024, tries=3):
    """Returns (PIL RGB image, info). Cached in RAW/<key>.png + .json."""
    os.makedirs(RAW, exist_ok=True)
    raw, meta = os.path.join(RAW, key + ".png"), os.path.join(RAW, key + ".json")
    forced = (FORCE and (ONLY is None or any(key.startswith(o) for o in ONLY))) or key in FORCE_KEYS
    if not forced and os.path.exists(raw) and os.path.exists(meta):
        return Image.open(raw).convert("RGB"), json.load(open(meta, encoding="utf-8"))
    best, best_score, best_info = None, -1, None
    for attempt in range(tries):
        s = seed + attempt * 7919
        t0 = time.time()
        imgs, secs = comfy.run(comfy.klein(prompt, s, width, height, refs=refs, prefix="88fits/" + key))
        img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
        ok, report = qa(img, expect)
        geo = geometry(img)
        report.setdefault("problems", [])
        if geo.get("empty"):
            report["problems"].append("empty")
        else:
            # portraits are meant to run off the bottom edge; everything else must sit clear of every edge
            if expect.get("bust"):
                if min(geo["left"], geo["right"], geo["top"]) < 12:
                    report["problems"].append("touches-edge")
            elif min(geo["left"], geo["right"], geo["top"]) < 12 or geo["bottom"] < 20:
                report["problems"].append("touches-edge")
            if expect.get("ref_h") and geo["height"] < 0.68 * float(expect["ref_h"]):
                report["problems"].append("too-short")
            if expect.get("ref_h") and geo["height"] > 1.2 * float(expect["ref_h"]):
                report["problems"].append("too-tall")
        report["geometry"] = geo
        ok = len(report["problems"]) == 0
        score = 10 - len(report.get("problems", []))
        log("  render %-26s seed %-7d %5.1fs  %s" % (key, s, secs, "ok" if ok else "retry: " + ",".join(report.get("problems", []))))
        if not ok and attempt == tries - 1:
            log("  (kept the best of %d for %s: %s)" % (tries, key, ",".join(best_info.get("qa", {}).get("problems", [])) if best_info else "?"))
        if score > best_score:
            best, best_score, best_info = img, score, {"seed": s, "prompt": prompt, "refs": list(refs), "qa": report, "attempt": attempt}
        if ok:
            break
    best.save(raw)
    json.dump(best_info, open(meta, "w", encoding="utf-8", newline="\n"), indent=1)
    return best, best_info


def ensure_anchor_uploaded():
    global _anchor_uploaded
    if not USE_ANCHOR:
        return []
    if not os.path.exists(ANCHOR):
        raise SystemExit("No style anchor at %s. Run with --anchor, look at tools/dl/review/anchor_candidates.png, then --pick=N." % ANCHOR)
    if not _anchor_uploaded:
        comfy.upload(open(ANCHOR, "rb").read(), "style_anchor.png")
        _anchor_uploaded = True
    return [ANCHOR_REF]


def anchor_candidates(n=4):
    os.makedirs(REVIEW, exist_ok=True)
    cands = []
    for k in range(n):
        key = "anchor_cand%d" % k
        raw = os.path.join(RAW, key + ".png")
        if os.path.exists(raw) and not FORCE:
            cands.append(Image.open(raw).convert("RGB"))
            continue
        imgs, secs = comfy.run(comfy.klein(anchor_prompt(), 1000 + k * 7919 + SEED_OFFSET, 1536, 768, prefix="88fits/" + key))
        img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
        os.makedirs(RAW, exist_ok=True)
        img.save(raw)
        log("  anchor candidate %d  %.1fs" % (k, secs))
        cands.append(img)
    sheet = Image.new("RGB", (1536, 768 * n + 40 * n), (30, 30, 36))
    d = ImageDraw.Draw(sheet)
    for k, c in enumerate(cands):
        sheet.paste(c, (0, k * 808 + 40))
        d.text((10, k * 808 + 10), "candidate %d" % k, fill=(255, 255, 255))
    p = os.path.join(REVIEW, "anchor_candidates.png")
    sheet.save(p)
    log("wrote", p, "- choose with --pick=N")


def pick_anchor(k):
    src = os.path.join(RAW, "anchor_cand%d.png" % k)
    os.makedirs(os.path.dirname(ANCHOR), exist_ok=True)
    Image.open(src).convert("RGB").save(ANCHOR)
    log("installed style anchor", ANCHOR, "from candidate", k)


# ---------------------------------------------------------------- finishing

def finish(img_rgb, cell, fill, bottom, scale=None, outline_frac=0.009, target_h=None, outline_color=(38, 24, 30, 255)):
    """Key, lift, fit into the cell, outline. target_h (cell px) fits the figure to that height instead of the fill."""
    keyed = artkit.punch(artkit.key_background(img_rgb))
    if target_h is not None:
        crop = artkit.crop_alpha(keyed)
        scale = float(target_h) / max(1, crop.height)
    canvas, sc = artkit.fit_cell(keyed, cell, fill, bottom, scale)
    px = max(1, int(round(cell * outline_frac)))
    return artkit.add_outline(canvas, px, outline_color), sc


def portrait_badge(img_rgb, size=256):
    """A round avatar badge: the keyed close-up scaled to the badge width, bottom-aligned so the bust fills the lower
    half, masked to a circle with a dark rim. icon_view draws it inside the character plate."""
    keyed = artkit.crop_alpha(artkit.key_background(img_rgb))
    # a render that runs down to the waist is cut to its top 60% so the head stays big; a head-and-shoulders render is kept whole
    if keyed.height > keyed.width * 1.15:
        keyed = artkit.crop_alpha(keyed.crop((0, 0, keyed.width, int(keyed.height * 0.6))))
    # cover the circle: fill its height (the mask trims the sides) unless that would push the head past the rim
    scale = min(max(size * 1.0 / keyed.width, size * 0.96 / keyed.height), size * 1.0 / keyed.height)
    w, h = max(1, int(keyed.width * scale)), max(1, int(keyed.height * scale))
    big = keyed.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(big, ((size - w) // 2, size - h + int(size * 0.03)))
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(artkit.punch(canvas), (0, 0), mask)
    # a thin dark rim inside the circle
    rim = ImageDraw.Draw(out)
    rim.ellipse((1, 1, size - 2, size - 2), outline=(24, 16, 20, 255), width=3)
    return out


def portrait(front_rgb, size=256):
    """Head-and-shoulders crop of the front view, used as the character icon."""
    keyed = artkit.key_background(front_rgb)
    keyed = artkit.crop_alpha(keyed)
    h = keyed.height
    bust = keyed.crop((0, 0, keyed.width, int(h * 0.52)))
    bust = artkit.crop_alpha(bust)
    canvas, _ = artkit.fit_cell(artkit.punch(bust), size, 0.92, False)
    return artkit.add_outline(canvas, 2)


def write_marker(folder, id_, info):
    json.dump(info, open(os.path.join(folder, id_ + "_ai.json"), "w", encoding="utf-8", newline="\n"), indent=1)


def anchor_hash():
    return hashlib.sha1(open(ANCHOR, "rb").read()).hexdigest()[:12] if os.path.exists(ANCHOR) else ""


# ---------------------------------------------------------------- per type

def process(type_, folder, id_):
    d = json.load(open(os.path.join(folder, id_ + ".json"), encoding="utf-8"))
    subject = subject_for(d, type_)
    bg = bg_for(d, type_)
    refs = ensure_anchor_uploaded()
    seed = seed_for(id_)
    info = {"pipeline": "gen_art v2", "model": comfy.KLEIN_UNET, "anchor": anchor_hash() if USE_ANCHOR else "", "subject": subject, "renders": {}}
    many = any(w in subject.lower() for w in ("three ", "pile", "family", "six ", "splitting", "pair of"))
    if type_ in ("enemies", "bosses"):
        cell = int(d.get("frame_px", 128))
        img, inf = render(id_ + "_front", styled(subject, "Full body, front view, standing and facing the viewer.", bg), refs,
                          {"subject": subject, "view": "front", "subjects_max": 1}, seed)
        info["renders"]["front"] = inf
        front_ref = comfy.upload_pil(img, id_ + "_front.png")
        back_prompt = ("Turn this exact creature around and show a full-body back view seen directly from behind, no face visible. Keep the same "
                       "colors, proportions and art style, standing. " + bg + ".")
        back_img, inf = render(id_ + "_back", back_prompt, [front_ref], {"subject": "the same creature seen from behind", "view": "back", "subjects_max": 1,
                               "ref_h": figure_height(img)}, seed + 1)
        info["renders"]["back"] = inf
        # creatures get a heavier, darker outline than the hero so they separate from the sand and from each other
        CO, CF = (14, 8, 12, 255), 0.024
        base, sc = finish(img, cell, 0.86, True, None, CF, None, CO)
        back_cell = finish(back_img, cell, 0.86, True, None, CF, figure_height_cell(base), CO)[0]
        motion = str(d.get("motion", "walking in place with a steady stomping gait"))
        run_f = video_cycle(img, id_ + "_walk_f", motion + ", facing the viewer, seen from the front", seed, cell, base, CREATURE_RUN_FRAMES, CF, CO, 49)
        run_b = video_cycle(back_img, id_ + "_walk_b", motion + ", seen directly from behind, walking away from the viewer", seed + 1, cell, base, CREATURE_RUN_FRAMES, CF, CO, 49)
        info["clips"] = {"walk_f": run_f is not None, "walk_b": run_b is not None}
        views = {}
        if int(d.get("directions", 2)) == 8:
            # side and diagonal stills edited from the front painting, a walk clip each, fitted to the front's height
            stand_h = figure_height_cell(base)
            turns = {
                "_s": ("side", "Turn this exact creature to show a full-body side view in strict profile, facing to the right of the frame, standing", "in strict side profile facing right, walking to the right", 3),
                "_bd": ("bd", "Turn this exact creature to a three-quarter back view: turned 45 degrees away from the viewer so it faces the upper right of the frame, its back and right side visible, standing", "three-quarter back view, walking away towards the upper right", 4),
                "_fd": ("fd", "Turn this exact creature to a three-quarter front view: turned 45 degrees so it faces the lower right of the frame, face visible, standing", "three-quarter front view, walking towards the lower right", 5),
            }
            hints = d.get("view_hints", {})   # per-view wording for creatures whose side view is easy to get wrong
            for suffix, (vname, turn_prompt, walk_prompt, k) in turns.items():
                hint = (", " + str(hints[vname])) if vname in hints else ""
                v_img, inf = render(id_ + "_" + vname, turn_prompt + hint + ". Keep the same colors, proportions and art style. " + bg + ".", [front_ref],
                                    {"subject": "the same creature, " + vname + " view", "view": None, "subjects_max": 1, "ref_h": figure_height(img)}, seed + k)
                info["renders"][vname] = inf
                v_cell = finish(v_img, cell, 0.86, True, None, CF, stand_h, CO)[0]
                v_run = video_cycle(v_img, id_ + "_walk_" + vname, motion + ", " + walk_prompt, seed + k, cell, base, CREATURE_RUN_FRAMES, CF, CO, 49)
                info["clips"]["walk_" + vname] = v_run is not None
                views[suffix] = (v_cell, v_run)
        frames = artkit.enemy_frames(base, cell, run_f, back_cell, run_b, views)
        strip, counts, cols = artkit.pack_strip(frames, artkit.ENEMY_ORDER, cell)
        strip.save(os.path.join(folder, d.get("sprite", id_ + "_sprite.png")))
        icon, _ = finish(img, 256, 0.9, False, None, 0.009)
        icon.save(os.path.join(folder, d.get("icon", id_ + "_icon.png")))
        d["anims"] = counts
        d["strip_cols"] = cols
        d["fps"] = {"run": CREATURE_RUN_FPS if run_f else 10}
    elif type_ == "characters":
        cell = int(d.get("frame_px", 256))
        front, inf = render(id_ + "_front", styled(subject, "Full body, front view, standing straight and facing the viewer, arms relaxed, feet fully visible.", bg), refs,
                            {"subject": subject, "view": "front", "subjects_max": 1, "legs": True}, seed)
        info["renders"]["front"] = inf
        front_ref = comfy.upload_pil(front, id_ + "_front.png")
        back_prompt = ("Turn this exact character around and show a full-body back view seen directly from behind: the back of the head or helmet, "
                       "the back of the outfit and the heels, no face visible. Keep the same outfit, colors, proportions and art style, standing "
                       "straight with arms relaxed. " + bg + ".")
        back, inf = render(id_ + "_back", back_prompt, [front_ref], {"subject": "the same character seen from behind", "view": "back", "subjects_max": 1, "legs": True, "ref_h": figure_height(front)}, seed + 1)
        info["renders"]["back"] = inf
        back_ref = comfy.upload_pil(back, id_ + "_back.png")
        side_prompt = ("Turn this exact character to show a full-body side view in strict profile, facing to the right of the frame, standing "
                       "straight with arms relaxed. Keep the same outfit, colors, proportions and art style. " + bg + ".")
        side, inf = render(id_ + "_side", side_prompt, [front_ref], {"subject": "the same character seen from the side in profile", "view": "side", "subjects_max": 1, "legs": True, "ref_h": figure_height(front)}, seed + 6)
        info["renders"]["side"] = inf
        side_ref = comfy.upload_pil(side, id_ + "_side.png")
        front_h, back_h, side_h = figure_height(front), figure_height(back), figure_height(side)
        fd_prompt = ("Turn this exact character to a three-quarter front view: turned 45 degrees so the character faces towards the lower right of "
                     "the frame, face visible, standing straight with arms relaxed. Keep the same outfit, colors, proportions and art style. " + bg + ".")
        fd, inf = render(id_ + "_fd", fd_prompt, [front_ref], {"subject": "the same character, three-quarter front view", "view": None, "subjects_max": 1, "legs": True, "ref_h": front_h}, seed + 7)
        info["renders"]["fd"] = inf
        bd_prompt = ("Turn this exact character to a three-quarter back view: turned 45 degrees away from the viewer so the character faces the upper "
                     "right of the frame, the back and right shoulder visible, standing straight with arms relaxed. Keep the same outfit, colors, "
                     "proportions and art style. " + bg + ".")
        bd, inf = render(id_ + "_bd", bd_prompt, [front_ref], {"subject": "the same character, three-quarter back view", "view": None, "subjects_max": 1, "legs": True, "ref_h": front_h}, seed + 8)
        info["renders"]["bd"] = inf
        poses = [("cheer", "seen directly from behind (no face visible), jumping for joy with both arms raised high above the head, feet together", back_ref, "back")]
        pose_imgs = {}
        for k, (name, pose, ref, view) in enumerate(poses):
            p = ("The exact same character " + pose + ". Keep the same outfit, colors, proportions and art style as the reference. " + bg + ".")
            ref_h = {"back": back_h, "front": front_h, "side": side_h}.get(view, 0)
            im, inf = render(id_ + "_" + name, p, [ref], {"subject": "the same character", "view": view, "subjects_max": 1, "legs": True, "ref_h": ref_h}, seed + 10 + k)
            info["renders"][name] = inf
            pose_imgs[name] = im if not inf.get("qa", {}).get("problems") else None
        back_cell, sc = finish(back, cell, 0.84, True)
        # Klein draws running figures smaller than standing ones: fit every stride to 94% of the standing height
        ab = np.asarray(back_cell)[..., 3]
        rows = np.nonzero(ab.max(axis=1) > 127)[0]
        stand_h = float(rows.max() - rows.min()) if len(rows) else cell * 0.8

        front_cell = finish(front, cell, 0.84, True, None, 0.012, stand_h)[0]
        side_cell = finish(side, cell, 0.84, True, None, 0.012, stand_h)[0]
        fd_cell = finish(fd, cell, 0.84, True, None, 0.012, stand_h)[0]
        bd_cell = finish(bd, cell, 0.84, True, None, 0.012, stand_h)[0]
        cheer_cell = finish(pose_imgs["cheer"], cell, 0.9, True)[0] if pose_imgs.get("cheer") is not None else None
        gait = str(d.get("motion", "running in place at a steady jog, arms and legs swinging naturally"))
        N = HERO_RUN_FRAMES
        # pose-driven cycles: the Mixamo run stride rendered per view drives Wan Animate, so every view has the same
        # 24-frame cadence and loops by construction; the free i2v clip stays as the fallback
        # the JSON may carry "anim_hint" (what the animation must keep) and "anim_negative" (what it must not invent)
        hint = str(d.get("anim_hint", subject.split(",")[0][:120]))
        anim_neg = str(d.get("anim_negative", ""))
        seed += int(d.get("anim_seed", 0))
        # "pose_driven": false in the JSON keeps a non-humanoid hero (the Roomba) on the free clip
        pose_ok = bool(d.get("pose_driven", True))
        clips = {}
        for suffix, still_img, cell_img, view, prompt in (
            ("", back, back_cell, "back", gait + ", seen directly from behind, running away from the viewer"),
            ("_f", front, front_cell, "front", gait + ", facing the viewer, running straight towards the viewer"),
            ("_s", side, side_cell, "side", gait + ", in strict side profile facing right, running to the right"),
            ("_bd", bd, bd_cell, "bd", gait + ", three-quarter back view, running away towards the upper right"),
            ("_fd", fd, fd_cell, "fd", gait + ", three-quarter front view, running towards the lower right")):
            k = {"": 20, "_f": 21, "_s": 22, "_bd": 23, "_fd": 24}[suffix]
            c = pose_cycle(still_img, id_ + "_pose_run_" + view, "run", view, seed + k, cell, cell_img, hint, negative_extra=anim_neg) if pose_ok else None
            if c is None:
                c = video_cycle(still_img, id_ + "_run" + (suffix or "_b"), prompt, seed + k, cell, cell_img, N)
            clips[suffix] = c
        info["clips"] = {k or "_b": v is not None for k, v in clips.items()}
        # hit reactions: a painted "hurt" still per view, edited from that view's still by the image model so it reads like
        # the rest of the sheet, then a short procedural wince around it (the pose-driven pain clip looked wrong on every hero)
        hits = {}
        hurt_hint = str(d.get("hurt_hint", "eyes squeezed shut, teeth gritted"))
        for suffix, still_img, cell_img, view, ref_h, seedk in (("", back, back_cell, "back", back_h, 30), ("_f", front, front_cell, "front", front_h, 31),
                                                              ("_s", side, side_cell, "side", side_h, 32), ("_bd", bd, bd_cell, "bd", front_h, 33), ("_fd", fd, fd_cell, "fd", front_h, 34)):
            view_words = {"back": "seen directly from behind", "front": "facing the viewer", "side": "in strict side profile facing right",
                          "bd": "in three-quarter back view", "fd": "in three-quarter front view"}[view]
            h_prompt = ("The exact same character " + view_words + ", flinching in pain from a hit: leaning back a little, shoulders hunched, "
                        "one hand raised towards the chest, " + hurt_hint + ", still standing on both feet, feet fully visible. Keep the same "
                        "outfit, colors, proportions, pose scale and art style as the reference. " + bg + ".")
            ref = comfy.upload_pil(still_img, id_ + "_" + view + "_ref.png")
            h_img, inf = render(id_ + "_hurt_" + view, h_prompt, [ref], {"subject": "the same character flinching", "view": view if view in ("front", "back", "side") else None,
                                                                          "subjects_max": 1, "legs": True, "ref_h": ref_h}, seed + seedk)
            info["renders"]["hurt_" + view] = inf
            hurt_cell = finish(h_img, cell, 0.84, True, None, 0.012, stand_h)[0]
            # four frames at HERO_HIT_FPS: the flinch, a deeper lean, the flinch, and a half step back to standing
            hits[suffix] = [hurt_cell, artkit.transform(hurt_cell, lean_deg=-6, bob=2, sy=0.97, sx=1.03), hurt_cell, artkit.transform(cell_img, lean_deg=-3, sy=0.99)]
        info["hits"] = {k or "_b": v is not None for k, v in hits.items()}
        frames = artkit.character_frames(back_cell, clips[""], cheer_cell, cell, front_cell, clips["_f"], side_cell, clips["_s"], bd_cell, clips["_bd"], fd_cell, clips["_fd"], hits)
        strip, counts, cols = artkit.pack_strip(frames, artkit.CHAR_ORDER, cell)
        strip.save(os.path.join(folder, d.get("sprite", id_ + "_sprite.png")))
        # the icon: a painted close-up doing something, keyed and set into a round badge that fills the plate's lower half
        pp = str(d.get("portrait_prompt", "smiling at the viewer"))
        # edited from the front still so the face and outfit are this character's; the head fills half the frame
        p_prompt = ("A close-up portrait of this exact character for a mobile game avatar icon: only the head and shoulders, the head filling "
                    "half of the frame, " + pp + ", facing the viewer, the shoulders and chest running off the bottom edge of the frame, "
                    "expressive and lively, no legs, no full body. Keep the same face, outfit, colors and art style as the reference. " + bg + ".")
        p_img, inf = render(id_ + "_portrait", p_prompt, [front_ref], {"subject": subject, "view": "front", "subjects_max": 1, "bust": True}, seed + 40)
        info["renders"]["portrait"] = inf
        portrait_badge(p_img).save(os.path.join(folder, d.get("icon", id_ + "_icon.png")))
        d["anims"] = counts
        d["strip_cols"] = cols
        d["fps"] = {"run": HERO_RUN_FPS if all(v is not None for v in clips.values()) else 14, "hit": HERO_HIT_FPS}
    else:
        img, inf = render(id_ + "_icon2", subject + ". " + ICON_STYLE + ". " + bg + ".", [],
                          {"subject": subject, "view": None, "subjects_max": 6 if many else 1}, seed)
        info["renders"]["icon"] = inf
        icon, _ = finish(img, 256, 0.92, False, None, 0.006)
        icon.save(os.path.join(folder, d.get("icon", id_ + "_icon.png")))
    d.setdefault("art_prompt", subject)
    json.dump(d, open(os.path.join(folder, id_ + ".json"), "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    write_marker(folder, id_, info)
    for suffix in ("_sprite_flat.png", "_icon_flat.png"):
        p = os.path.join(folder, id_ + suffix)
        if os.path.exists(p):
            os.remove(p)


# ---------------------------------------------------------------- review + app icon

def review_sheets():
    os.makedirs(REVIEW, exist_ok=True)
    icons = sorted(glob.glob(os.path.join(CONTENT, "*", "*", "*_icon.png")))
    artkit.contact_sheet([Image.open(p) for p in icons], 8, 112).save(os.path.join(REVIEW, "icons.png"))
    strips = sorted(glob.glob(os.path.join(CONTENT, "*", "*", "*_sprite.png")))
    ims = [Image.open(p).convert("RGBA") for p in strips]
    if ims:
        w = max(i.width for i in ims)
        h = sum(i.height for i in ims)
        out = Image.new("RGBA", (w, h), (40, 40, 48, 255))
        y = 0
        for i in ims:
            out.alpha_composite(i, (0, y))
            y += i.height
        out.thumbnail((2000, 2000))
        out.save(os.path.join(REVIEW, "strips.png"))
    # phone preview: sprites at their on-screen size (camera 16 m, fov 65 keep-height -> ~94 px per metre on a 1920 px tall screen)
    ppm = 1920.0 / (2.0 * 16.0 * np.tan(np.radians(65.0 / 2.0)))
    sand = Image.open(os.path.join(REPO, "game", "art", "env", "sand_albedo.png")).convert("RGBA") if os.path.exists(os.path.join(REPO, "game", "art", "env", "sand_albedo.png")) else Image.new("RGBA", (512, 512), (214, 168, 110, 255))
    phone = Image.new("RGBA", (1080, 640), (0, 0, 0, 255))
    for x in range(0, 1080, sand.width):
        for y in range(0, 640, sand.height):
            phone.alpha_composite(sand, (x, y))
    x = 30
    for p in strips:
        id_ = os.path.basename(p).replace("_sprite.png", "")
        folder = os.path.dirname(p)
        d = json.load(open(os.path.join(folder, id_ + ".json"), encoding="utf-8"))
        cell = int(d.get("frame_px", 128))
        metres = float(d.get("size", 1.6))
        strip = Image.open(p).convert("RGBA")
        frame = strip.crop((0, 0, cell, cell))
        px = int(metres * ppm)
        frame = frame.resize((px, px), Image.LANCZOS)
        phone.alpha_composite(frame, (x, 640 - 40 - px))
        x += px + 20
        if x > 1080 - px:
            break
    # HUD/collection icon sizes
    y = 20
    for p in icons[:7]:
        ic = Image.open(p).convert("RGBA").resize((84, 84), Image.LANCZOS)   # HUD slot size
        phone.alpha_composite(ic, (1080 - 100, y))
        y += 88
    phone.save(os.path.join(REVIEW, "phone.png"))
    log("review sheets in", REVIEW)


def app_icon():
    src = os.path.join(CONTENT, "characters", "drifter", "knight_icon.png")
    if not os.path.exists(src):
        return
    hero = Image.open(src).convert("RGBA")

    def base(sz, bg=True):
        im = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
        if bg:
            arr = np.zeros((sz, sz, 4), dtype=np.uint8)
            yy = np.linspace(0, 1, sz)[:, None]
            top, bot = np.array([242, 140, 60]), np.array([120, 50, 30])
            col = (top * (1 - yy) + bot * yy).astype(np.uint8)
            arr[..., :3] = np.repeat(col[:, None, :], sz, axis=1)
            arr[..., 3] = 255
            im = Image.fromarray(arr, "RGBA")
            dr = ImageDraw.Draw(im)
            r, cx, cy = int(sz * 0.36), sz // 2, int(sz * 0.42)
            dr.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 214, 90, 255))
        return im

    def compose(sz, fg_scale, bg=True):
        im = base(sz, bg)
        g = hero.copy()
        s = int(sz * fg_scale)
        g.thumbnail((s, s))
        sh = Image.new("RGBA", g.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 140), (0, 0), g)
        sh = sh.filter(ImageFilter.GaussianBlur(sz * 0.01))
        x, y = (sz - g.width) // 2, int(sz * 0.5 - g.height * 0.42)
        im.alpha_composite(sh, (x + int(sz * 0.015), y + int(sz * 0.02)))
        im.alpha_composite(g, (x, y))
        return im

    game = os.path.join(REPO, "game")
    compose(1024, 0.86).save(os.path.join(game, "icon.png"))
    compose(192, 0.86).save(os.path.join(game, "icon_192.png"))
    compose(432, 0.62, bg=False).save(os.path.join(game, "icon_fg_432.png"))
    base(432).save(os.path.join(game, "icon_bg_432.png"))
    log("app icons written from the knight portrait")


# ---------------------------------------------------------------- main

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    st = comfy.get("/system_stats")
    log("ComfyUI", st["system"].get("comfyui_version"), "on", st["devices"][0].get("name"), "at", comfy.SERVER, "| model", comfy.KLEIN_UNET)
    if "--anchor" in sys.argv:
        anchor_candidates()
        return
    if PICK is not None:
        pick_anchor(PICK)
        if "--only" not in sys.argv and not any(a.startswith("--only=") for a in sys.argv):
            return
    types = ["characters", "enemies", "bosses", "weapons", "evolutions", "passives", "shop", "elites", "maps", "quests", "pickups"]
    jobs = []
    for t in types:
        base = os.path.join(CONTENT, t)
        if not os.path.isdir(base):
            continue
        for id_ in sorted(os.listdir(base)):
            folder = os.path.join(base, id_)
            if os.path.isfile(os.path.join(folder, id_ + ".json")) and (ONLY is None or id_ in ONLY):
                jobs.append((t, folder, id_))
    log("%d items, anchor reference %s, QA %s" % (len(jobs), "on" if USE_ANCHOR else "off", "off" if SKIP_QA else "on"))
    t0 = time.time()
    fails = 0
    for k, (t, folder, id_) in enumerate(jobs):
        try:
            process(t, folder, id_)
            log("[%2d/%2d] %-11s %-18s ok   (%4.0fs elapsed)" % (k + 1, len(jobs), t, id_, time.time() - t0))
        except Exception as e:
            fails += 1
            log("[%2d/%2d] %-11s %-18s FAIL %s" % (k + 1, len(jobs), t, id_, e))
    app_icon()
    review_sheets()
    log("gen_art: done, %d items, %d failures, %.0f min" % (len(jobs), fails, (time.time() - t0) / 60))
    godot = os.path.join(REPO, "Godot_v4.7.2-stable_win64", "Godot_v4.7.2-stable_win64.exe")
    if os.path.exists(godot) and not NO_IMPORT:
        game = os.path.join(REPO, "game")
        subprocess.run([godot, "--headless", "--path", game, "--import"], capture_output=True)
        subprocess.run([godot, "--headless", "--path", game, "--script", "res://tools/import_json.gd"], capture_output=True)
        log("imported into Godot")


if __name__ == "__main__":
    main()
