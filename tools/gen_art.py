"""88fits art pipeline v2: anime-style sprites and icons, generated with Flux.2 Klein 9B on the ComfyUI server
and locked to ONE style anchor image so every asset shares the same look.

Stages (each cached in tools/dl/ai_raw2/, so a re-run only paints what is missing):
  anchor      `--anchor` paints 4 style-sheet candidates (tools/dl/review/anchor_candidates.png); `--pick=N` installs one as
              game/art/style/style_anchor.png. Every later render passes the anchor as a reference image.
  items       weapons, evolutions, passives, mutations, lines, perks, shop, elites, maps, quests -> one icon render each -> <id>_icon.png
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
import base64, glob, hashlib, io, json, os, re, shutil, subprocess, sys, time, urllib.request

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
DEV = "--dev" in sys.argv               # Flux.2 dev for the stills (one render at a time, models released after each)
USE_ANCHOR = "--no-anchor-ref" not in sys.argv


def _model_settings():
    """The painter and its quality (pass 66 follow-up, Garry: "choose which Model ... the number of passes"): from the
    environment (the Level Editor's jobs: ART_MODEL klein|dev, ART_STEPS, ART_GUIDANCE, ART_TURBO 0|1) or the flags
    --model=klein|dev (--dev is --model=dev), --steps=N, --guidance=F, --turbo / --no-turbo. 0 means the model's own
    default: Klein 4 steps; dev 8 steps with the Turbo LoRA (the quick form) or 28 without (the full quality the
    candidates use)."""
    m = os.environ.get("ART_MODEL", "")
    steps = int(os.environ.get("ART_STEPS", "0") or 0)
    guidance = float(os.environ.get("ART_GUIDANCE", "0") or 0)
    turbo = os.environ.get("ART_TURBO", "")
    for a in sys.argv:
        if a.startswith("--model="):
            m = a.split("=", 1)[1]
        elif a.startswith("--steps="):
            steps = int(a.split("=", 1)[1] or 0)
        elif a.startswith("--guidance="):
            guidance = float(a.split("=", 1)[1] or 0)
        elif a == "--turbo":
            turbo = "1"
        elif a == "--no-turbo":
            turbo = "0"
    if "--dev" in sys.argv and not m:
        m = "dev"
    return {"model": m or "klein", "steps": steps, "guidance": guidance, "turbo": None if turbo == "" else turbo == "1",
            "explicit": bool(m or steps or guidance or turbo != "")}


MODEL = _model_settings()
if MODEL["model"] == "dev":
    DEV = True


def apply_painter(p):
    """A look's recorded painter (variants[CODE].recipe.painter: {model, steps, guidance, turbo}, written by the Level
    Editor's job) drives a hand run that named no painter itself (no ART_* env, no --model/--steps/--guidance/--turbo
    flags); a job's own settings win. So `gen_art.py --only goblin --variant=GOB-E` paints GOB-E as its look says."""
    global DEV
    if MODEL.get("explicit") or not isinstance(p, dict):
        return
    MODEL["model"] = "dev" if p.get("model") == "dev" else "klein"
    MODEL["steps"] = int(p.get("steps") or 0)
    MODEL["guidance"] = float(p.get("guidance") or 0)
    MODEL["turbo"] = p.get("turbo") if isinstance(p.get("turbo"), bool) else None
    DEV = MODEL["model"] == "dev"
    print("gen_art: the look's recorded painter: %s%s" % (MODEL["model"], (" %d steps" % MODEL["steps"]) if MODEL["steps"] else ""))


def painter_info(full=False):
    """The painter a still goes to, as paint() runs it (pass 68, D4: the run's marker names the real one, not always
    Klein): {"model": "klein", "unet", "steps"} or {"model": "dev", "unet", "steps", "guidance", "turbo"}. `full`: the
    candidates' default (dev without Turbo, 28 steps)."""
    if MODEL["model"] == "dev":
        turbo = MODEL["turbo"] if MODEL["turbo"] is not None else (not full)
        return {"model": "dev", "unet": comfy.FLUX2_UNET, "steps": int(MODEL["steps"] or (8 if turbo else 28)),
                "guidance": float(MODEL["guidance"] or 4.0), "turbo": bool(turbo)}
    return {"model": "klein", "unet": comfy.KLEIN_UNET, "steps": int(MODEL["steps"] or 4)}


def paint(prompt, seed, width, height, refs, prefix, full=False):
    """One still on the chosen painter with the chosen quality: Klein (MODEL steps or 4), or Flux.2 dev (steps,
    guidance, turbo from MODEL; `full` = the 28-step no-Turbo quality on a freshly restarted server, what the
    candidates use by default). Returns (png bytes, seconds). Every caller that painted a still itself goes through
    here, so the Level Editor's model settings reach them all."""
    p = painter_info(full)
    if p["model"] == "dev":
        g = comfy.flux2_dev(prompt, seed, width, height, refs=refs, steps=p["steps"], guidance=p["guidance"], turbo=p["turbo"], prefix=prefix)
        # every dev still on a freshly restarted server, Turbo too (2026-10-12: a dev job cancelled mid-render left
        # ComfyUI holding both models in a full RAM, and the next Turbo still went straight in and thrashed the swap
        # for twenty minutes; the models are released after each still anyway, so the restart costs seconds)
        imgs, secs = comfy.run_dev(g)
        log("  " + comfy.release_models())
        return imgs, secs
    return comfy.run(comfy.klein(prompt, seed, width, height, refs=refs, steps=p["steps"], prefix=prefix))
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
# --variant=GOB-B (pass 34): paint one art variant of a creature (with --only <id>): the recipe in its JSON's
# variants[code].recipe overrides the creature's art settings, the clips are cached under their own keys, and the strip
# goes to <id>_sprite_<letter>.png with its counts written into variants[code]; the art the game uses is not touched
# pass 55: heroes too (--only solenne --variant=SOL-B): the recipe may name other paintings per view ("still_keys"),
# other drivers ("pose_drivers"), the clip's motion words ("pose_motion") and its rate ("run_fps"); the badge is left alone
VARIANT = ""
for a in sys.argv:
    if a.startswith("--variant="):
        VARIANT = a.split("=", 1)[1]
for a in sys.argv:
    if a.startswith("--keys="):
        FORCE_KEYS = a.split("=", 1)[1].split(",")

# pass 66: a Level Editor job (tools/asset_job.py) sets ASSET_JOB_SIDECAR=<job>/result.json. Then this module never
# opens a content JSON for writing: what the run would have written (the variant entry, or the top-level keys of a base
# run) goes into that sidecar for the editor's server to merge in place, line by line, so Garry's layout and his hand
# edits made while the job ran survive. The <id>[_<letter>]_ai.json markers are still written. Without the variable
# (every command line Claude types) the write-back is the same as before.
SIDECAR = os.environ.get("ASSET_JOB_SIDECAR", "")
WRITE_JSON = SIDECAR == ""
QA_ONLINE = None   # whether LM Studio answered this run's vision checks (None: never asked, --skip-qa or no render)
ICON_BACKUPS = os.path.join(REPO, "tools", "dl", "backup", "icons_le")

ANCHOR_REF = "88fits/style_anchor.png"
_anchor_uploaded = False


def log(*a):
    print(*a, flush=True)


def emit_sidecar(folder, id_, vcode, patch, info, top=None):
    """What this run would have written into the content JSON, for the Level Editor's server to merge in place:
    {"id", "folder", "variant", "entry": {sprite, icon, anims, strip_cols, fps, head}, "top": {...}, "info": {...}}."""
    out = {"id": id_, "folder": folder, "variant": vcode or "", "entry": patch or {}, "top": top or {}, "info": info}
    path = SIDECAR or os.path.join(folder, id_ + "_result.json")
    if os.path.dirname(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    log("  sidecar written: %s" % path)
    return out


def backup_icon(dst, new_png_bytes=None, folder=None):
    """The icon about to be overwritten kept under tools/dl/backup/icons_le/<name>_<stamp>.png (pass 66, critique 22);
    nothing is kept when the new bytes equal the old (a cached re-run writes the same picture). Returns the copy's path.
    `folder` puts the copy elsewhere (pass 68: a title cut-out's go to tools/dl/backup/title/)."""
    if not os.path.isfile(dst):
        return ""
    try:
        old = open(dst, "rb").read()
    except OSError:
        return ""
    if new_png_bytes is not None and old == new_png_bytes:
        return ""
    folder = folder or ICON_BACKUPS
    os.makedirs(folder, exist_ok=True)
    stem = os.path.splitext(os.path.basename(dst))[0]
    out = os.path.join(folder, "%s_%s.png" % (stem, time.strftime("%Y%m%d-%H%M%S")))
    shutil.copy2(dst, out)
    return out


# ---------------------------------------------------------------- prompts

def anchor_prompt():
    return ("A game art style sheet on a flat solid bright green (#00FF00) background: five different subjects standing in a row with empty "
            "space between them, all the same height, all facing the viewer: a lean young man with messy dark hair in a long tan trench coat "
            "with the collar up and a dark red scarf, a tan coyote with big ears and a mischievous grin, a walking green cactus with a "
            "worried face, a wooden double-barreled shotgun, and a golden stopwatch. All five rendered in exactly the same " + STYLE +
            ". No ground, no shadows, no text.")


def bg_for(d, type_=""):
    # an item may name its own screen ("screen": "green"|"blue"): a blue-skinned creature on the blue screen loses its
    # skin to the keyer, and the video model then animates a headless body (the Rocketeer, pass 30)
    named = str(d.get("screen", "")).lower()
    if named == "green":
        return BG_GREEN
    if named == "blue":
        return BG_BLUE
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


# pass 68 (D2): a look's own seeds. A prime apart from the 7919 steps of --seed and of render()'s retries, so a look's
# seeds never land on another look's retry.
LOOK_SEED_STEP = 104729


def seed_offset_of(d):
    """A look's `seed_offset` (the Level Editor writes one into every NEW look's recipe); 0 when it has none."""
    try:
        return int(float((d or {}).get("seed_offset") or 0))
    except (TypeError, ValueError):
        return 0


def look_seed(id_, d):
    """The first seed of an item's paintings and clips (pass 68, D2): seed_for(id) moved by the look's seed_offset, so
    two new looks with the same words are no longer painted as clones (DM-E and DM-F, MAM-B and MAM-C). A look without
    one (every look made before pass 68, every base) keeps the seeds it was painted with."""
    return seed_for(id_) + LOOK_SEED_STEP * seed_offset_of(d)


def still_slug(d):
    """The look's own paintings ("stills": "c4" -> goblin_c4_front); "" = the item's own paintings."""
    return str(d["stills"]) if (d or {}).get("stills") else ""


def hero_still_key(id_, view, d):
    """A hero still's cache key (pass 68, D1): the look's `still_keys[view]` wins (Solenne's s55 side), else
    `<id>_<slug>_<view>` when the look has its own paintings (`stills`, as a creature look), else the hero's own
    `<id>_<view>`. Views: front, back, side, fd, bd, cheer, hurt_<view>, dead."""
    skeys = d.get("still_keys") if isinstance(d.get("still_keys"), dict) else {}
    if skeys.get(view):
        return str(skeys[view])
    slug = still_slug(d)
    return id_ + ("_" + slug if slug else "") + "_" + view


def look_letter(code):
    """A look code's file letter: MAM-C -> c (<id>_sprite_c.png, <id>_icon_c.png)."""
    return str(code or "").split("-")[-1].lower()


def is_base_code(d, code):
    """No look named, or the look that is the item's top-level art (the JSON's variant_base): its files are the item's own."""
    return not code or str(code) == str((d or {}).get("variant_base") or "")


def has_look(d, code):
    """Whether the item JSON has the look (an entry under variants, or its variant_base): a pick for a code it lacks is
    refused rather than writing a stray entry."""
    return is_base_code(d, code) or isinstance((d.get("variants") or {}).get(code), dict)


def look_merged(d, code):
    """The item JSON with a look's recipe laid over it, as process() paints the look (the JSON itself for no code)."""
    out = dict(d)
    if not code:
        return out
    entry = (d.get("variants") or {}).get(code)
    if not isinstance(entry, dict):
        if is_base_code(d, code):
            return out
        raise SystemExit("gen_art: %s has no look %s" % (d.get("id", "?"), code))
    out.update(entry.get("recipe") or {})
    return out


def ref_path(name):
    """The file a reference picture names, or None (pass 68, shared by the candidate tools): an absolute path, a path
    under the repo (the Level Editor's uploads, tools/dl/uploads/2d/x.png), a path under tools/dl/ (a render:
    spear_ref.png) or the page's /dl/... URL."""
    name = str(name or "").strip()
    if not name:
        return None
    dl = os.path.join(REPO, "tools", "dl")
    cands = []
    if name.replace("\\", "/").startswith("/dl/"):
        cands.append(os.path.join(dl, name.replace("\\", "/")[4:]))
    if os.path.isabs(name):
        cands.append(name)
    cands += [os.path.join(REPO, name), os.path.join(dl, name)]
    for p in cands:
        if os.path.isfile(p):
            return os.path.normpath(p)
    return None


def on_screen(img, blue=False):
    """A reference picture laid on the screen colour, as RGB: a Blender render or a cut-out has a transparent film; an
    opaque picture comes back as it is."""
    im = img.convert("RGBA")
    out = Image.new("RGBA", im.size, (0, 0, 255, 255) if blue else (0, 255, 0, 255))
    out.alpha_composite(im)
    return out.convert("RGB")


def _content_io():
    """The Level Editor's line-by-line JSON writer (tools/level_editor/content_io.py), or None."""
    p = os.path.join(REPO, "tools", "level_editor")
    if p not in sys.path:
        sys.path.insert(0, p)
    try:
        import content_io
        return content_io
    except Exception:
        return None


def write_look_entry(jpath, code, update):
    """A hand run's change to one look's entry (variants[CODE]) of a content JSON (pass 68: a badge or title cut-out
    picked for a look): line by line through the Level Editor's writer when it is at hand, so the file's layout and line
    endings stay, else the whole file dumped again. Under a job the sidecar carries it and the server writes it."""
    cio = _content_io()
    if cio is not None:
        try:
            new = cio.set_variant_entry(cio.read_text(jpath), code, update)
            if new:
                cio.write_atomic(jpath, new)
                return jpath
        except Exception:
            pass
    cur = json.load(open(jpath, encoding="utf-8"))
    cur.setdefault("variants", {}).setdefault(code, {}).update(update)
    json.dump(cur, open(jpath, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    return jpath


def write_top_block(jpath, key, value, places=()):
    """A hand run's top-level key (the badge block) written into a content JSON the same way."""
    cio = _content_io()
    if cio is not None:
        try:
            new = cio.set_top_block(cio.read_text(jpath), key, value, places)
            if new:
                cio.write_atomic(jpath, new)
                return jpath
        except Exception:
            pass
    cur = json.load(open(jpath, encoding="utf-8"))
    cur[key] = value
    json.dump(cur, open(jpath, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    return jpath


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
    global QA_ONLINE
    try:
        r = vision_json(img, q)
        QA_ONLINE = True
    except Exception as e:
        QA_ONLINE = False
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
    if r.get("matches") is False and not expect.get("no_match_ok"):
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


def passing_frame(frames):
    """The walk frame with the feet closest together (the passing pose), by the width of the bottom fifth of the figure:
    the one that reads as standing."""
    best, best_w = frames[0], 1e9
    for f in frames:
        a = np.asarray(f)[..., 3] > 127
        ys = np.nonzero(a.max(axis=1))[0]
        if not len(ys):
            continue
        y0 = int(ys.max() - (ys.max() - ys.min()) * 0.2)
        xs = np.nonzero(a[y0:ys.max() + 1].max(axis=0))[0]
        w = float(xs.max() - xs.min()) if len(xs) else 1e9
        if w < best_w:
            best, best_w = f, w
    return best


def figure_top(cell_img):
    """The top of the figure as a fraction of the cell's height, measured from the cell's bottom edge."""
    a = np.asarray(cell_img)[..., 3] > 127
    ys = np.nonzero(a.max(axis=1))[0]
    return (cell_img.height - float(ys.min())) / cell_img.height if len(ys) else 0.0


def figure_height_cell(cell_img):
    a = np.asarray(cell_img)[..., 3] > 127
    ys = np.nonzero(a.max(axis=1))[0]
    return float(ys.max() - ys.min()) if len(ys) else 0.0


# ---------------------------------------------------------------- pass 73 (lane ART): a picture of the back, painted attack poses

def lower_center_x(cell_img, frac=0.45):
    """Where a figure stands across its cell: the alpha-weighted mean column of its lower `frac` of rows (the legs, a
    poncho's hem), whatever it holds out at shoulder height (pass 73: the Saiga Sniper's rifle)."""
    a = np.asarray(cell_img.convert("RGBA"))[..., 3].astype(np.float32)
    ys = np.nonzero(a.max(axis=1) > 40)[0]
    if len(ys) == 0:
        return cell_img.width / 2.0
    y1 = int(ys.max())
    cut = int(round(y1 - (y1 - int(ys.min())) * frac))
    sub = a[cut:y1 + 1]
    w = float(sub.sum())
    if w <= 0:
        return cell_img.width / 2.0
    return float((sub.sum(axis=0) * np.arange(a.shape[1], dtype=np.float32)).sum() / w)


def back_ref_render(d, sk, bg, front_ref, back_prompt):
    """Pass 73 (lane ART, the Saiga Sniper): a creature's `back_ref` (a picture of it seen from behind: the back figure
    of Garry's turnaround) goes in as the back still's second reference, so the back copies the drawing's back (a hood,
    a poncho's stripes, a rifle across the back) instead of guessing it from the front. Returns (refs, prompt); without
    a back_ref (every creature before), ([front_ref], back_prompt) unchanged. Tried once on the sniper: the front's
    pose and the drawing's back mixed into a rifle with two muzzles (the QA passed it); the back he walks with was
    painted as candidates from the drawing alone and picked by eye, so check the back still after a back_ref run."""
    pic = ref_path(d.get("back_ref")) if d.get("back_ref") else None
    if not pic:
        if d.get("back_ref"):
            log("  (back_ref %r is not on disk: the back is edited from the front alone)" % str(d.get("back_ref")))
        return [front_ref], back_prompt
    up = comfy.upload_pil(on_screen(Image.open(pic), bg == BG_BLUE), sk + "_back_ref.png")
    copy = ("The second reference image shows this same creature seen from behind: copy its back view from it (its pose, the back "
            "of its head and clothes, how it carries what it holds), drawn in exactly the art style, colors and proportions of the "
            "first reference image. ")
    if d.get("back_prompt"):
        prompt = str(d["back_prompt"]) + " " + copy + bg + "."
    else:
        prompt = ("Turn the creature of the first reference image around and show a full-body back view seen directly from behind, no "
                  "face visible. " + copy + "Standing. " + str(d.get("back_hint", "")) + " " + bg + ".")
    return [front_ref, up], prompt


def attack_stills(d, sk, subject, bg, front_ref, img, back_img, seed, info):
    """Pass 73 (lane ART, the Saiga Sniper's aim): painted attack poses for a creature whose recipe or JSON names one:
    the pose in words (`aim_hint`, lane SNIPER's key), optionally with a picture of it (`aim_ref`). The front pose is
    an edit of the front still alone with the pose in words (<sk>_attack_front: identity and colours stay the walk's;
    a picture of the pose goes in as a second reference only when `aim_ref` names one: riskier, a two-reference edit
    of the sniper's back with another pose painted two guns); the pose from behind is an edit of the BACK still alone,
    now in the pose (<sk>_attack_back, words `aim_back_hint`), so its poncho and stripes are the back walk's, painted
    when the creature has `attack_views: "front_back"`. Both cached like every still (a re-roll moves them aside). None
    when nothing names a pose. The words are the ones the sniper's picked candidates were painted with
    (tools/dl/p73/art/scripts/q_aim.py route A, q_aimback.py route D; route C, the aim front turned around, painted a
    lighter poncho)."""
    hint, pic_name = str(d.get("aim_hint") or "").strip(), str(d.get("aim_ref") or "").strip()
    if not hint and not pic_name:
        return None
    pic = ref_path(pic_name) if pic_name else None
    if pic_name and not pic:
        log("  (aim_ref %r is not on disk: the attack pose is painted from its words)" % pic_name)
    tail = (" " + STYLE + ". Full body, the whole creature and everything it holds inside the picture, one of each thing it holds, no "
            "ground, no shadow. " + bg + ".")
    refs = [front_ref]
    if pic:
        refs.append(comfy.upload_pil(on_screen(Image.open(pic), bg == BG_BLUE), sk + "_attack_ref.png"))
        prompt = ("Show the creature of the first reference image in the pose of the second reference image" + (": " + hint if hint else "") +
                  ". Copy the pose, the angle and how it holds what it carries from the second reference image, but draw it in exactly the "
                  "art style, colors, proportions, face and outfit of the first reference image." + tail)
    else:
        prompt = ("The reference image shows this exact creature: keep its face, horns, fur, clothes, colors and proportions exactly, and "
                  "redraw it full body " + hint + "." + tail)
    h = figure_height(img)
    aim, inf = render(sk + "_attack_front", prompt, refs, {"subject": subject, "view": None, "subjects_max": 1, "ref_h": h}, seed + 11)
    info["renders"]["attack_front"] = inf
    if str(d.get("attack_views", "")) != "front_back":
        return aim, None
    back_up = comfy.upload_pil(back_img, sk + "_back.png")
    bhint = str(d.get("aim_back_hint") or hint).strip()
    bprompt = ("The reference image shows this exact creature seen from behind: keep it seen directly from behind, no face visible, "
               "keep its colors and proportions, and redraw it full body " + bhint + "." + tail)
    aim_b, inf = render(sk + "_attack_back", bprompt, [back_up], {"subject": "the same creature seen from behind", "view": None,
                        "subjects_max": 1, "ref_h": h}, seed + 12)
    info["renders"]["attack_back"] = inf
    return aim, aim_b


def _warm_stats(rgba, lo, hi, min_s):
    """Mean hue (degrees) and saturation of a figure's pixels in a hue band (saturated past min_s)."""
    arr = np.asarray(rgba.convert("RGBA"))
    hsv = np.asarray(Image.fromarray(arr[..., :3]).convert("HSV")).astype(np.float32) / 255.0
    m = (arr[..., 3] > 127) & (hsv[..., 0] * 360.0 >= lo) & (hsv[..., 0] * 360.0 <= hi) & (hsv[..., 1] > min_s)
    if not m.any():
        return None
    return float(hsv[..., 0][m].mean() * 360.0), float(hsv[..., 1][m].mean())


def match_band(pose_rgba, ref_rgba, lo=0.0, hi=60.0, min_s=0.25):
    """Pass 73 (lane ART): a painted pose's hues in a band (the browns: 0-60 degrees) moved by the difference of the two
    figures' mean hue there, and their saturation scaled to the reference's; the change fades out over 15 degrees past
    the band and toward grey, so blacks, greys and other colours stay. A pose painted as its own edit came out ~7
    degrees yellower and a little more saturated than the walk it plays between (the Saiga Sniper's poncho)."""
    ps, rs = _warm_stats(pose_rgba, lo, hi, min_s), _warm_stats(ref_rgba, lo, hi, min_s)
    if not ps or not rs:
        return pose_rgba
    arr = np.asarray(pose_rgba.convert("RGBA"))
    hsv = np.asarray(Image.fromarray(arr[..., :3]).convert("HSV")).astype(np.float32) / 255.0
    h = hsv[..., 0] * 360.0
    w = np.clip(1.0 - np.maximum(lo - h, h - hi) / 15.0, 0.0, 1.0) * np.clip((hsv[..., 1] - min_s * 0.5) / (min_s * 0.5), 0.0, 1.0)
    hsv[..., 0] = ((h + (rs[0] - ps[0]) * w) % 360.0) / 360.0
    hsv[..., 1] = np.clip(hsv[..., 1] * (1.0 + (rs[1] / max(ps[1], 1e-4) - 1.0) * w), 0.0, 1.0)
    out = Image.fromarray((hsv * 255.0 + 0.5).astype(np.uint8), "HSV").convert("RGBA")
    out.putalpha(Image.fromarray(arr[..., 3]))
    return out


def pose_cell(still_rgb, stand_cell, cell, outline_frac, outline_color, fit=1.0, pad_bottom=0.06, match=None):
    """A painted pose (an attack still) placed like the standing figure: its height the standing figure's x `fit` (1 when
    the pose stands as tall as the standing painting: the Saiga Sniper's aim), its lower body centred where the standing
    figure's is (lower_center_x) and its soles on the cell's floor line, slid back inside the cell when what it holds
    out (a rifle) would leave it; `match` {lo, hi} moves its colours in that hue band to the standing figure's
    (match_band). Returns (cell image, how far it was slid in px)."""
    keyed = artkit.crop_alpha(artkit.punch(artkit.key_background(still_rgb)))
    if isinstance(match, dict):
        keyed = match_band(keyed, stand_cell, float(match.get("lo", 0.0)), float(match.get("hi", 60.0)), float(match.get("min_s", 0.25)))
    al = np.asarray(keyed)[..., 3] > 127
    ys = np.nonzero(al.max(axis=1))[0]
    alpha_h = float(ys.max() - ys.min() + 1) if len(ys) else float(keyed.height)
    px = max(1, int(round(cell * outline_frac)))
    # the standing figure's height counts its outline; the pose's alpha (not its padded crop) is fitted to the rest
    target = max(1.0, figure_height_cell(stand_cell) * float(fit) - 2 * px)
    sc = target / max(1.0, alpha_h)
    w, h = max(1, int(round(keyed.width * sc))), max(1, int(round(keyed.height * sc)))
    if w > cell - 2 * px or h > cell - 2 * px:
        s2 = min((cell - 2 * px) / keyed.width, (cell - 2 * px) / keyed.height)
        w, h = max(1, int(keyed.width * s2)), max(1, int(keyed.height * s2))
    small = keyed.resize((w, h), Image.LANCZOS)
    want = int(round(lower_center_x(stand_cell) - lower_center_x(small)))
    x = max(px, min(cell - px - w, want))
    sa = np.asarray(small)[..., 3] > 127
    sy = np.nonzero(sa.max(axis=1))[0]
    bottom_pad = (h - 1 - int(sy.max())) if len(sy) else 0
    st = np.asarray(stand_cell)[..., 3] > 127
    ty = np.nonzero(st.max(axis=1))[0]
    # the soles on the standing figure's floor line (its outline counted), else the cell's
    floor = (int(ty.max()) - px) if len(ty) else cell - int(cell * pad_bottom)
    canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    canvas.alpha_composite(small, (x, max(0, floor - (h - bottom_pad) + 1)))
    return artkit.add_outline(canvas, px, outline_color), x - want


def attack_frames(aim, aim_b, stand_cell, back_cell, cell, outline_frac, outline_color, d, info):
    """The `attack` frames from the painted poses (attack_stills): the front pose held, a still and a breath (the aim
    "cannot move a muscle"); with the creature's "attack_views": "front_back" (lane SNIPER, pass 73: the game shows the
    first half while the aim points towards the camera, the second while it points away) the pose from behind follows
    as the second half. `aim_fit`: the pose's height against the standing figure's (1 = the same); `aim_match` (default
    {"lo": 0, "hi": 60}: the browns; false = off): the hue band whose colours are matched to the standing paintings."""
    fit = float(d.get("aim_fit", 1.0) or 1.0)
    match = d.get("aim_match", {"lo": 0, "hi": 60})
    match = match if isinstance(match, dict) else None
    a, slid = pose_cell(aim, stand_cell, cell, outline_frac, outline_color, fit, match=match)
    breath = cell / 160.0
    frames = [a, artkit.transform(a, bob=breath, sy=0.996, sx=1.002)]
    info["attack_slid_px"] = {"front": slid}
    if str(d.get("attack_views", "")) == "front_back" and aim_b is not None:
        b, slid_b = pose_cell(aim_b, back_cell, cell, outline_frac, outline_color, fit, match=match)
        frames += [b, artkit.transform(b, bob=breath, sy=0.996, sx=1.002)]
        info["attack_slid_px"]["back"] = slid_b
    return {"attack": frames}


def run_scale_of(d, view):
    """Pass 70 (lane ART): a look's per-view size of its run/walk clip, "run_scale": {"side": 0.88, "back": 1.06} in
    the recipe (or the JSON), multiplied into the clip's fitted scale (1 = as fitted). A driven clip is fitted by its
    tallest frame, so a view whose every frame crouches (a side run) comes out bigger than the others and one whose
    foot reaches down toward the camera (a back or front run) smaller: May's side run stood half a head taller than her
    other views, Jezyk's dash ran smaller from behind. Cached clips are only re-placed, nothing is painted again."""
    rs = d.get("run_scale") if isinstance(d, dict) else None
    if not isinstance(rs, dict):
        return 1.0
    try:
        return min(1.5, max(0.5, float(rs.get(view, 1.0))))
    except (TypeError, ValueError):
        return 1.0


_RUN_FIT_CACHE = {}


def run_fit_of(d, view):
    """Pass 71 (lane PLE, the Puppet method): the height a view's walk stands at against its standing still, from the
    hero's own 3D puppet: "run_fit" in the recipe is a silhouette.json (tools/puppet.py guides: per view the median screen
    height of the run's 24 poses over the idle's, through the guides' 25-degree cameras; a guide folder holding one may be
    named instead) or {view: ratio}. The walk is then scaled so its MEDIAN frame stands at that ratio of the still,
    instead of its tallest frame at the still's height (the fit run_scale tunes by hand; run_scale still multiplies on
    top). None = the tallest-frame fit. Clamped 0.6..1.4."""
    rf = d.get("run_fit") if isinstance(d, dict) else None
    if not rf:
        return None
    try:
        if isinstance(rf, dict):
            v = rf.get(view)
            return None if v in (None, "") else min(1.4, max(0.6, float(v)))
        path = str(rf)
        if not os.path.isabs(path):
            path = os.path.join(REPO, path)
        if os.path.isdir(path):
            path = os.path.join(path, "silhouette.json")
        if path not in _RUN_FIT_CACHE:
            with open(path, encoding="utf-8") as f:
                _RUN_FIT_CACHE[path] = json.load(f)
        r = (_RUN_FIT_CACHE[path].get(view) or {}).get("ratio_median")
        return None if r is None else min(1.4, max(0.6, float(r)))
    except (OSError, ValueError, TypeError, AttributeError) as e:
        log("  (run_fit for %s: %s; the tallest frame is fitted)" % (view, e))
        return None


def clip_scale(frames, stand_cell, scale_mul=1.0, fit_ratio=None, outline_px=0):
    """The scale a driven clip's frames take: by default the tallest frame fitted to the standing figure (x0.99); with
    `fit_ratio` (run_fit_of) the median frame at that ratio of the standing figure, the outline the frames get after
    the scale (`outline_px` a side) counted in (MAY-R's first walks stood 2 % over the puppet's ratio in every view).
    Times the look's run_scale."""
    if fit_ratio:
        med = float(np.median([_alpha_height(f) for f in frames])) if frames else 1.0
        want = figure_height_cell(stand_cell) * float(fit_ratio) - 2.0 * float(outline_px)
        return max(1.0, want) / max(1.0, med) * float(scale_mul)
    tallest = max(1.0, max(_alpha_height(f) for f in frames))
    return figure_height_cell(stand_cell) * 0.99 / tallest * float(scale_mul)


FACE_WORDS = re.compile(r"\b(face|faces|eyes?|smil\w*|cheeks?|mouth|nose|lips|eyebrows?)\b", re.I)


def hint_for_view(hint, view, d):
    """Pass 71 follow-up (lane PLE, "keep the correct face angle"): a puppet look with the face setting on (recipe
    puppet.face "nose", the default) walks its back and back-diagonal views on words without the face: the clauses of
    its hint (split at ";") that name the face are left out there. A depth video cannot tell a front from a back, and
    MAY-R's first back walk, whose hint described her face for the front views, ran with a face toward the camera.
    Any other look, and the other views, keep the hint whole."""
    face = ((d.get("puppet") or {}).get("face") if isinstance(d, dict) and isinstance(d.get("puppet"), dict) else None)
    if view not in ("back", "bd") or face != "nose" or not hint:
        return hint
    keep = [c.strip() for c in str(hint).split(";") if c.strip() and not FACE_WORDS.search(c)]
    return "; ".join(keep) if keep else hint


def fringe_remap(frames, still_rgb, opts=None):
    """Pass 71 (lane PLE, the trial's rainbow fringes on the sleeves): a clip's hues the view's own painting does not have
    (gen_art's hue bins: a bin is the painting's when it holds 0.3 % of the figure, or a neighbour does) moved to the
    painting's nearest own hue (the mean hue of its pixels in that bin), saturation x `sat`; value and alpha kept; only a
    pixel saturated past `min_sat`. Recipe "fringe_remap": true or {"min_sat": 0.2, "sat": 0.85}. Off unless named."""
    o = opts if isinstance(opts, dict) else {}
    min_sat, sat_mult, bins = float(o.get("min_sat", 0.2)), float(o.get("sat", 0.85)), 24
    ref = artkit.crop_alpha(artkit.key_background(still_rgb, 0.05, 0.45))
    hist = _hue_hist(ref, bins)
    own = hist > 0.003
    own = own | np.roll(own, 1) | np.roll(own, -1)
    if own.all() or not own.any():
        return frames
    ra = np.asarray(ref.convert("RGBA")).astype(np.float32) / 255.0
    rh, rs, rv = artkit._rgb_to_hsv(ra[..., :3])
    rm = (ra[..., 3] > 0.5) & (rs > 0.3) & (rv > 0.25)
    rb = (rh * bins).astype(np.int32) % bins
    own_idx = np.nonzero(own)[0]
    target = np.zeros(bins, dtype=np.float32)
    for b in range(bins):
        dist = np.minimum(np.abs(own_idx - b), bins - np.abs(own_idx - b))
        nb = int(own_idx[int(np.argmin(dist))])
        sel = rm & (rb == nb)
        if sel.any():
            ang = rh[sel] * 2 * np.pi
            target[b] = (np.arctan2(np.sin(ang).mean(), np.cos(ang).mean()) / (2 * np.pi)) % 1.0
        else:
            target[b] = (nb + 0.5) / bins
    out = []
    for f in frames:
        a = np.asarray(f.convert("RGBA")).astype(np.float32) / 255.0
        h, sa, v = artkit._rgb_to_hsv(a[..., :3])
        b = (h * bins).astype(np.int32) % bins
        sel = (a[..., 3] > 0.02) & (sa > min_sat) & ~own[b]
        if not sel.any():
            out.append(f)
            continue
        rgb = artkit._hsv_to_rgb(np.where(sel, target[b], h), np.where(sel, sa * sat_mult, sa), v)
        a[..., :3] = np.where(sel[..., None], rgb, a[..., :3])
        out.append(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA"))
    return out


def video_cycle(still_rgb, key, motion, seed, cell, stand_cell, n_out=12, outline_frac=0.012, outline_color=(38, 24, 30, 255), length=81, fill=0.72, scale_mul=1.0):
    """A run/walk cycle from a Wan clip of the still, scaled so the figure matches its standing cell; None on failure.
    `fill` (JSON "clip_fill") is the still's share of the clip canvas: less for a creature that bounces high (pass 45).
    `scale_mul`: the look's run_scale for this view (run_scale_of)."""
    if NO_VIDEO:
        return None
    try:
        frames, meta = animate.cycle(still_rgb, key, motion, seed, n_out, length=length, fill=fill)
    except Exception as e:
        log("  (video cycle failed for %s: %s)" % (key, e))
        return None
    # the still was scaled to `fill` of the 640 px clip; match the standing figure's cell height
    scale = figure_height_cell(stand_cell) / max(1.0, animate_still_height(still_rgb, fill)) * float(scale_mul)
    px = max(1, int(round(cell * outline_frac)))
    return artkit.place_clip_frames(frames, cell, scale, px, outline_color)


DRIVERS = os.path.join(REPO, "tools", "dl", "drivers")


def pose_cycle(still_rgb, key, clip, view, seed, cell, stand_cell, hint, outline_frac=0.012, outline_color=(38, 24, 30, 255), negative_extra="", loop=True, motion="running in place on the spot like on a treadmill", view_hint="", scale_mul=1.0, fit_ratio=None):
    """A run/walk cycle from Wan Animate driven by the Mixamo stride in tools/dl/drivers/<clip>/<view> (see
    tools/pose_driver.py): every driver frame is a sprite frame, so the count and cadence are exact in every view.
    Falls back to the free video cycle when the drivers are missing; None on failure."""
    if NO_VIDEO:
        return None
    driver_dir = os.path.join(DRIVERS, clip, view)
    if not os.path.isdir(driver_dir):
        log("  (no drivers in %s, falling back to a free clip)" % driver_dir)
        return None
    # the view goes into the prompt too: the drivers alone left a hero's back cycle with a face painted on it
    view_words = {"back": "seen directly from behind, the back of the head and the heels towards the viewer",
                  "front": "facing the viewer", "side": "in strict side profile facing right",
                  "bd": "in three-quarter back view, turned away from the viewer", "fd": "in three-quarter front view"}
    hint = (hint + ", " if hint else "") + view_words.get(view, "") + (", " + view_hint if view_hint else "")
    if view in ("back", "bd"):
        negative_extra = (negative_extra + ", " if negative_extra else "") + "face, eyes, mouth, nose, looking at the viewer"
    # a cycle already on disk was checked (and picked by eye) when it was made: the colour and facing checks below are
    # for fresh rolls only, or every later run of the creature re-rolls a cycle that sits a hair over a threshold
    # (Calavera's embroidery kept failing the foreign-hue check, so every run changed his front and side, pass 45)
    cached = os.path.exists(os.path.join(animate.ANIM, key, "cycle.json"))
    frames = None
    for attempt in range(3):
        try:
            frames, meta = animate.cycle_pose(still_rgb, key, driver_dir, seed + attempt * 101, prompt_hint=hint, negative_extra=negative_extra, loop=loop, motion=motion)
        except Exception as e:
            # two seeds failed inside (the figure left the frame): fresh seeds before giving up on the driven walk
            # (pass 34: a goblin's wide club went off the edge twice and the back walk fell back to a free clip)
            log("  (pose cycle failed for %s: %s)" % (key, e))
            if attempt < 2:
                shutil.rmtree(os.path.join(animate.ANIM, key), ignore_errors=True)
                continue
            return None
        if cached and attempt == 0:
            break
        # a part that flashes a colour for a frame (the goblin's club end went white, then orange, pass 33.9) rolls the
        # cycle again; 0.08 passes every hero run in the game (the worst, Dad's front, is 0.07)
        hx = hue_excess(frames, cyclic=loop)
        if max(hx) > 0.08 and attempt < 2:
            log("  pose %-24s frame %d flashes a colour its neighbours lack (%.3f), rolling again" % (key, hx.index(max(hx)) + 1, max(hx)))
            shutil.rmtree(os.path.join(animate.ANIM, key), ignore_errors=True)
            continue
        hf = hue_foreign(frames, still_rgb)
        if max(hf) > FOREIGN_MAX and attempt < 2:
            log("  pose %-24s frame %d has a colour the painting lacks (%.3f), rolling again" % (key, hf.index(max(hf)) + 1, max(hf)))
            shutil.rmtree(os.path.join(animate.ANIM, key), ignore_errors=True)
            continue
        # the drivers alone do not decide which way the figure faces: a back cycle came back with a face on it twice,
        # so a middle frame goes through the vision check and a cycle facing the wrong way is rolled again
        if view not in ("back", "bd") or SKIP_QA:
            break
        mid = frames[len(frames) // 2]
        probe = Image.new("RGB", mid.size, (128, 128, 128))
        probe.paste(mid, (0, 0), mid)
        _, rep = qa(probe, {"subject": hint, "view": None, "subjects_max": 1})
        if rep.get("view") != "front":
            break
        log("  pose %-24s faces the viewer in a %s cycle, rolling again" % (key, view))
        if attempt < 2:
            shutil.rmtree(os.path.join(animate.ANIM, key), ignore_errors=True)
    # Wan Animate draws the figure on the driver skeleton, which is nose-to-ankle: the painted body comes out about a
    # head taller than the still placed at the same fill. Measure the tallest frame and fit it to the standing figure.
    # pass 70: times the look's run_scale for this view (run_scale_of): the tallest frame is not the same body size in
    # every view; pass 71: a puppet look's run_fit fits the median frame to its 3D puppet's own run/idle ratio instead
    px = max(1, int(round(cell * outline_frac)))
    scale = clip_scale(frames, stand_cell, scale_mul, fit_ratio, px)
    return artkit.place_clip_frames(frames, cell, scale, px, outline_color)


def ctl_driver_of(d, view):
    """A hero look's depth guide for a view (lane PUPPET, 2026-10-13: "ctl_drivers" in the recipe, one folder under
    tools/dl/drivers/ for every view or {view: folder}); "" = the view runs on its pose driver as before."""
    c = d.get("ctl_drivers") if isinstance(d, dict) else None
    if isinstance(c, dict):
        return str(c.get(view) or "")
    return str(c or "")


def ctl_cycle(still_rgb, key, clip, view, seed, cell, stand_cell, hint, outline_frac=0.012, outline_color=(38, 24, 30, 255), negative_extra="",
              view_hint="", motion="running in place on the spot like on a treadmill", scale_mul=1.0, loop_frames=None, fit_ratio=None):
    """A hero's run from Wan 2.2 Fun Control on a depth guide (lane PUPPET: the depth videos of the hero's own rigged
    3D puppet, tools/puppet.py guides -> tools/dl/drivers/<hero>_puppet_run_depth/<view>/ctl_NN.png, two strides of 24
    poses + 1): the still is the reference, the second stride is kept (animate.cycle_control), fitted to the standing
    height by the tallest frame like pose_cycle, times the look's run_scale. None on failure."""
    if NO_VIDEO:
        return None
    ctl_dir = os.path.join(DRIVERS, clip, view)
    if not os.path.isdir(ctl_dir):
        log("  (no depth guide in %s)" % ctl_dir)
        return None
    n_ctl = len([f for f in os.listdir(ctl_dir) if f.startswith("ctl_") and f.endswith(".png")])
    loop = int(loop_frames or (n_ctl - 1) // 2)
    view_words = {"back": "seen directly from behind, the back of the head and the heels towards the viewer, no face",
                  "front": "facing the viewer", "side": "in strict side profile facing right",
                  "bd": "in three-quarter back view, turned away from the viewer", "fd": "in three-quarter front view"}
    if view in ("back", "bd"):
        negative_extra = (negative_extra + ", " if negative_extra else "") + "face, eyes, mouth, nose, looking at the viewer"
    prompt = ("A 2D anime game character sprite, " + (hint + ", " if hint else "") + view_words.get(view, "") + (", " + view_hint if view_hint else "") +
              ", " + motion + " exactly as the control video shows, the same character, outfit and colours as the reference in every frame, "
              "crisp clean line art, cel shading. The camera is completely locked off and static. The background stays a flat solid bright "
              "blue color with nothing in it, no ground, no shadow.")
    try:
        frames, meta = animate.cycle_control(still_rgb, key, ctl_dir, seed, prompt=prompt, negative_extra=negative_extra, loop_frames=loop)
    except Exception as e:
        log("  (control cycle failed for %s: %s)" % (key, e))
        return None
    px = max(1, int(round(cell * outline_frac)))
    scale = clip_scale(frames, stand_cell, scale_mul, fit_ratio, px)
    return artkit.place_clip_frames(frames, cell, scale, px, outline_color)


def colour_stats(img):
    """Mean and spread of saturation and value over the figure (alpha over half), as two 2-vectors."""
    rgba = img.convert("RGBA")
    hsv = np.asarray(rgba.convert("RGB").convert("HSV")).astype(np.float32)[..., 1:] / 255.0
    sv = hsv[np.asarray(rgba)[..., 3] > 127]
    return sv.mean(axis=0), sv.std(axis=0) + 1e-4


def match_colours(img, mu, sd):
    """The figure's saturation and value moved to another mean and spread, its hues kept: a video frame brought to
    its paintings (a per-channel match turned the goblin's brown loincloth maroon)."""
    rgba = img.convert("RGBA")
    hsv = np.asarray(rgba.convert("RGB").convert("HSV")).astype(np.float32) / 255.0
    fm, fs = colour_stats(rgba)
    hsv[..., 1:] = np.clip((hsv[..., 1:] - fm) / fs * sd + mu, 0.0, 1.0)
    out = Image.fromarray((hsv * 255.0 + 0.5).astype(np.uint8), "HSV").convert("RGBA")
    out.putalpha(rgba.getchannel("A"))
    return out


def _hue_hist(img, bins=24):
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    m = a[..., 3] > 0.5
    rgb = a[..., :3][m]
    mx, mn = rgb.max(axis=1), rgb.min(axis=1)
    keep = ((mx - mn) / (mx + 1e-6) > 0.3) & (mx > 0.25)
    r, g, b, c = rgb[keep, 0], rgb[keep, 1], rgb[keep, 2], mx[keep] - mn[keep] + 1e-6
    h = np.where(mx[keep] == r, ((g - b) / c) % 6, np.where(mx[keep] == g, (b - r) / c + 2, (r - g) / c + 4)) / 6.0
    hh = np.bincount((h * bins).astype(np.int32) % bins, minlength=bins).astype(np.float64)
    return hh / max(1.0, float(m.sum()))


def hue_foreign(frames, still_rgb):
    """Per frame, the share of the figure in hues the painting itself does not have (pass 34): a colour that crept in
    and stayed for a few frames, which hue_excess misses (the goblin's club went magenta for three frames of a walk and
    a fall smeared into a rainbow; both scored over 0.05, every good clip in the game stays under 0.016). A hue bin is
    the painting's own when it holds 0.3% of the figure, or a neighbouring bin does (a hue drifts a bin)."""
    ref = artkit.crop_alpha(artkit.key_background(still_rgb, 0.05, 0.45))
    own = _hue_hist(ref) > 0.003
    own = own | np.roll(own, 1) | np.roll(own, -1)
    return [float(_hue_hist(f)[~own].sum()) for f in frames]


FOREIGN_MAX = 0.025


def hue_excess(frames, cyclic=False, bins=24):
    """Per frame, the share of the figure in hues that neither neighbouring frame has (saturated pixels, 24 hue bins):
    high on a frame where one part flashed a wrong colour (the goblin's club went pink for one frame of its fall,
    orange at the end for two of a walk), low through ordinary motion."""
    hists = []
    for f in frames:
        a = np.asarray(f.convert("RGBA")).astype(np.float32) / 255.0
        m = a[..., 3] > 0.5
        rgb = a[..., :3][m]
        mx, mn = rgb.max(axis=1), rgb.min(axis=1)
        keep = ((mx - mn) / (mx + 1e-6) > 0.3) & (mx > 0.25)
        r, g, b, c = rgb[keep, 0], rgb[keep, 1], rgb[keep, 2], mx[keep] - mn[keep] + 1e-6
        h = np.where(mx[keep] == r, ((g - b) / c) % 6, np.where(mx[keep] == g, (b - r) / c + 2, (r - g) / c + 4)) / 6.0
        hh = np.bincount((h * bins).astype(np.int32) % bins, minlength=bins).astype(np.float64)
        hists.append(hh / max(1.0, float(m.sum())))
    n = len(hists)
    out = []
    for k in range(n):
        nb = [hists[(k - 1) % n], hists[(k + 1) % n]] if cyclic else [hists[j] for j in (k - 1, k + 1) if 0 <= j < n]
        out.append(float(np.maximum(hists[k] - np.maximum.reduce(nb), 0.0).sum()))
    return out


def fall_pick(frames, n_out):
    """Which frames of a fall to keep: n_out spread from the last one still near the start (a third of the way to the
    end pose, by silhouette) to the first one near the end pose (a tenth of the way back). Returns (idx, start, end, d0, d1)."""
    feats = animate._silhouettes(frames)
    span = max(1e-6, float(np.mean(np.abs(feats[0] - feats[-1]))))
    d0 = [float(np.mean(np.abs(f - feats[0]))) for f in feats]
    d1 = [float(np.mean(np.abs(f - feats[-1]))) for f in feats]
    start = next((k for k in range(1, len(frames)) if d0[k] >= 0.35 * span), 1) - 1
    end = next((k for k in range(start + 1, len(frames)) if d1[k] < 0.1 * span), len(frames) - 1)
    while end - start < n_out - 1 and end < len(frames) - 1:
        end += 1
    while end - start < n_out - 1 and start > 0:
        start -= 1
    idx = [start + int(round(j * (end - start) / (n_out - 1))) for j in range(n_out)]
    return idx, start, end, d0, d1


def pose_death(still_rgb, key, clip, seed, cell, stand_cell, n_out=8, outline_frac=0.024, outline_color=(14, 8, 12, 255), hint="", negative_extra=""):
    """A death driven by a Mixamo clip (pass 34, a creature's "death": "pose:<driver>", the goblins on Falling Back
    Death): Wan Animate paints the front painting onto the driver's one-shot fall (tools/pose_driver.py loop=0), every
    driver frame a frame, scaled like the walk; n_out of them are kept from where it starts to go to where it lies
    still, and the last one holds. None on failure."""
    frames = pose_cycle(still_rgb, key, clip, "front", seed, cell, stand_cell, hint, outline_frac, outline_color, negative_extra=negative_extra,
                        loop=False, motion="knocked down: it staggers, falls over backwards and lands on the ground, then lies still, dead")
    if not frames:
        return None
    idx, start, end, _, _ = fall_pick(frames, n_out)
    hf = hue_foreign(frames, still_rgb)
    for j in range(1, n_out - 1):
        k = idx[j]
        if hf[k] > FOREIGN_MAX:
            for alt in (k - 1, k + 1, k - 2, k + 2):
                if idx[j - 1] < alt < idx[j + 1] and hf[alt] <= FOREIGN_MAX:
                    log("  fall %-24s frame %d has a colour the painting lacks (%.3f), took %d" % (key, k, hf[k], alt))
                    idx[j] = alt
                    break
    log("  fall %-24s driven frames %s of %d (moving from %d, at rest from %d)" % (key, idx, len(frames), start, end))
    return [frames[i] for i in idx]


def death_cycle(still_rgb, dead_rgb, key, seed, cell, stand_cell, n_out=8, outline_frac=0.024, outline_color=(14, 8, 12, 255), hint="", negative_extra=""):
    """A creature's death as an animated fall (pass 33.9, JSON "death": "clip"): animate.fall_clip's first-last-frame
    clip from the standing painting to the dead one, cut to n_out frames from the first to the moment the body comes to
    rest, the dead painting last. Every frame keeps the clip's geometry: one scale (the standing figure exactly as tall
    as in its idle cell), the canvas's middle column on the cell's, the clip's floor on the cell's floor, so the fall
    starts where the idle frame stands and nothing jumps. None on failure (the tipped painting stays)."""
    if NO_VIDEO:
        return None
    try:
        frames, meta = animate.fall_clip(still_rgb, dead_rgb, key, seed, prompt_hint=hint, negative_extra=negative_extra)
    except Exception as e:
        log("  (fall clip failed for %s: %s)" % (key, e))
        return None
    size = int(meta.get("size", 640))
    floor = float(meta.get("floor", 0.86)) * size
    # the clip crouches a while before it falls and lies still a while after (the goblin's: 9 frames of a slow crouch,
    # the fall in the next 7, still from 19 of 33): the frames are spread from the last one still near the standing
    # painting (a third of the way to lying, by silhouette) to the first one near the dead painting (a tenth of the way
    # back), and that last pick is the dead painting itself (the first attempt spent four of eight frames standing)
    feats = animate._silhouettes(frames)
    span = max(1e-6, float(np.mean(np.abs(feats[0] - feats[-1]))))
    d0 = [float(np.mean(np.abs(f - feats[0]))) for f in feats]
    d1 = [float(np.mean(np.abs(f - feats[-1]))) for f in feats]
    start = next((k for k in range(1, len(frames)) if d0[k] >= 0.35 * span), 1) - 1
    end = next((k for k in range(start + 1, len(frames)) if d1[k] < 0.1 * span), len(frames) - 1)
    while end - start < n_out - 1 and end < len(frames) - 1:
        end += 1
    while end - start < n_out - 1 and start > 0:
        start -= 1
    idx = [start + int(round(j * (end - start) / (n_out - 1))) for j in range(n_out)]
    idx[-1] = len(frames) - 1
    # a frame with a colour neither neighbour has (the goblin's club flashed pink for one frame) gives way to a neighbour
    hx = hue_excess(frames)
    hf = hue_foreign(frames, still_rgb)
    hx = [max(a, 0.0 if b <= FOREIGN_MAX else 1.0) for a, b in zip(hx, hf)]
    for j in range(1, n_out - 1):
        k = idx[j]
        if hx[k] > 0.06:
            for alt in (k - 1, k + 1):
                if idx[j - 1] < alt < idx[j + 1] and hx[alt] <= 0.06:
                    log("  fall %-24s frame %d has a colour its neighbours lack (%.3f), took %d" % (key, k, hx[k], alt))
                    idx[j] = alt
                    break
    chosen = [frames[i] for i in idx]
    # the video model paints brighter than the paintings it starts and ends on (the goblin's green rose from 0.52 to
    # 0.62 mid-fall and the dead painting is 0.47, so the last step flashed darker): every kept video frame takes the
    # paintings' saturation and brightness, blended by how far through the fall it is
    s0, s1 = colour_stats(frames[0]), colour_stats(frames[-1])
    for j, k in enumerate(idx):
        if 0 < k < len(frames) - 1:
            q = d0[k] / max(1e-6, d0[k] + d1[k])
            chosen[j] = match_colours(frames[k], s0[0] * (1 - q) + s1[0] * q, s0[1] * (1 - q) + s1[1] * q)
    px = max(1, int(round(cell * outline_frac)))
    scale = (figure_height_cell(stand_cell) - 2 * px) / max(1.0, _alpha_height(frames[0]))
    # nothing may leave the cell: if the widest moment of the fall would, the whole fall is drawn a little smaller
    widest = 0.0
    for f in chosen:
        xs = np.nonzero((np.asarray(f)[..., 3] > 127).max(axis=0))[0]
        if len(xs):
            widest = max(widest, 2.0 * max(size / 2.0 - xs.min(), xs.max() - size / 2.0))
    if widest * scale > cell - 2 * px - 2:
        scale = (cell - 2 * px - 2) / widest
    pad = int(cell * 0.06)
    out = []
    for f in chosen:
        big = f.resize((max(1, int(round(size * scale))), max(1, int(round(size * scale)))), Image.LANCZOS)
        x0 = int(round(size * scale / 2.0 - cell / 2.0))
        y0 = int(round(floor * scale - (cell - pad)))
        out.append(artkit.add_outline(artkit.punch(big.crop((x0, y0, x0 + cell, y0 + cell))), px, outline_color))
    log("  fall %-24s frames %s of %d (moving from %d, at rest from %d)" % (key, idx, len(frames), start, end))
    return out


def _alpha_height(frame_rgba):
    a = np.asarray(frame_rgba)[..., 3]
    rows = np.nonzero(a.max(axis=1) > 127)[0]
    return float(rows.max() - rows.min() + 1) if len(rows) else 0.0


def animate_still_height(still_rgb, fill=0.72):
    """Height in clip pixels of the figure as tools/animate.py placed it (`fill` of a 640 px canvas, 0.72 unless the JSON says)."""
    keyed = artkit.crop_alpha(artkit.key_background(still_rgb))
    s = min(640 * fill / keyed.width, 640 * fill / keyed.height)
    return keyed.height * s


def render(key, prompt, refs, expect, seed, width=1024, height=1024, tries=3):
    """Returns (PIL RGB image, info). Cached in RAW/<key>.png + .json."""
    os.makedirs(RAW, exist_ok=True)
    raw, meta = os.path.join(RAW, key + ".png"), os.path.join(RAW, key + ".json")
    forced = (FORCE and (ONLY is None or any(key.startswith(o) for o in ONLY))) or key in FORCE_KEYS
    if not forced and os.path.exists(raw) and os.path.exists(meta):
        cached = json.load(open(meta, encoding="utf-8"))
        # pass 68 (D4): the run's marker says which stills came from the cache (painted by whoever painted them first)
        cached["cached"] = True
        return Image.open(raw).convert("RGB"), cached
    best, best_score, best_info = None, -1, None
    for attempt in range(tries):
        s = seed + attempt * 7919
        t0 = time.time()
        imgs, secs = paint(prompt, s, width, height, refs, "88fits/" + key)
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
            best, best_score, best_info = img, score, {"seed": s, "prompt": prompt, "refs": list(refs), "qa": report, "attempt": attempt,
                                                       "painter": painter_info()}
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


def portrait_badge(img_rgb, size=256, head_width=0.0, top_pad=0.03):
    """A round avatar badge: the keyed close-up scaled to the badge width, bottom-aligned so the bust fills the lower
    half, masked to a circle with a dark rim. icon_view draws it inside the character plate.
    head_width > 0 (pass 56, Solenne's sun head): the head's widest span (the upper half's, her rays) is scaled to that
    share of the badge and hung top_pad from the top, so the whole head shows and the shoulders run off the bottom; the
    default zoom had cut her to the head alone."""
    keyed = artkit.crop_alpha(artkit.key_background(img_rgb))
    if head_width > 0.0:
        upper = np.asarray(keyed)[: keyed.height // 2, :, 3] > 127
        cols = np.nonzero(upper.any(0))[0]
        span = float(cols.max() - cols.min() + 1) if len(cols) else float(keyed.width)
        mid = 0.5 * (cols.min() + cols.max()) if len(cols) else keyed.width * 0.5
        scale = size * head_width / span
        w, h = max(1, int(keyed.width * scale)), max(1, int(keyed.height * scale))
        big = keyed.resize((w, h), Image.LANCZOS)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        canvas.alpha_composite(big, (int(round(size * 0.5 - mid * scale)), int(round(size * top_pad))))
        return _badge_ring(canvas, size)
    # a render that runs down to the waist is cut to its top 60% so the head stays big; a head-and-shoulders render is kept whole
    if keyed.height > keyed.width * 1.15:
        keyed = artkit.crop_alpha(keyed.crop((0, 0, keyed.width, int(keyed.height * 0.6))))
    # cover the circle: fill its height (the mask trims the sides) unless that would push the head past the rim
    scale = min(max(size * 1.0 / keyed.width, size * 0.96 / keyed.height), size * 1.0 / keyed.height)
    w, h = max(1, int(keyed.width * scale)), max(1, int(keyed.height * scale))
    big = keyed.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(big, ((size - w) // 2, size - h + int(size * 0.03)))
    return _badge_ring(canvas, size)


def _badge_ring(canvas, size):
    """The badge's circle mask and its thin dark rim."""
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
    # a creature that wears another's painting through a res:// "sprite" (pass 49: the arena's attacking, Elite and Boss
    # dummies wear the training dummy's) has nothing of its own to paint
    if type_ in ("enemies", "bosses") and str(d.get("sprite", "")).startswith("res://"):
        log("  %s wears %s: nothing to paint" % (id_, d["sprite"]))
        return
    base_d = d
    vcode = VARIANT if (VARIANT and type_ in ("enemies", "bosses", "characters")) else ""
    ventry = None
    if vcode:
        ventry = (d.get("variants") or {}).get(vcode)
        if not isinstance(ventry, dict):
            raise SystemExit("gen_art: %s has no variant %s" % (id_, vcode))
        # the recipe overrides the creature's own art settings for this run only
        d = dict(base_d)
        d.update(ventry.get("recipe", {}))
        apply_painter(d.get("painter"))
    # an optional "grade" block colours the keyed figure of every still and frame (artkit.grade): Mira's blue-grey denim
    # shares the blue screen's hue, so it can only be keyed while grey and is turned blue afterwards
    artkit.GRADE = d.get("grade") if isinstance(d.get("grade"), dict) else None
    artkit.KEY_SAT = float(d.get("key_sat", 0.35))
    # pass 54: a glossy black figure keeps the screen colour it reflects (Solenne's catsuit and boots)
    artkit.KEY_MIN_V = float(d.get("key_min_value", 0.2))
    artkit.KEY_CUT_SHADOW = bool(d.get("key_cut_shadow", True))
    artkit.KEY_CLAMP_SCREEN = bool(d.get("key_clamp_screen", False))
    subject = subject_for(d, type_)
    bg = bg_for(d, type_)
    refs = ensure_anchor_uploaded()
    # pass 68 (D2): a new look's recipe carries its own seed_offset, so its paintings and clips are its own
    seed = look_seed(id_, d)
    # a creature may ask for other clip seeds ("anim_seed", pass 44: a free clip that drifted from its painting); the
    # cached paintings keep their keys, so only the clips roll again
    if type_ in ("enemies", "bosses"):
        seed += int(d.get("anim_seed", 0))
    # pass 66: "recipe_ran" is the recipe this run read (the entry may be edited while a job runs), "clip_kind" says per
    # view how its cycle was made (pose | free | procedural; gen_ctl writes control), so a silent fallback is seen
    # pass 68 (D4): "model" is the painter the stills went to (it was always Klein's file), "painter" its settings; a
    # still taken from the cache says "cached" in "renders"
    painter = painter_info()
    info = {"pipeline": "gen_art v2", "model": painter["unet"], "painter": painter, "anchor": anchor_hash() if USE_ANCHOR else "", "subject": subject, "renders": {},
            "recipe_ran": (ventry.get("recipe") if isinstance(ventry, dict) else None), "clip_kind": {}}
    kinds = info["clip_kind"]
    many = any(w in subject.lower() for w in ("three ", "pile", "family", "six ", "splitting", "pair of"))
    if type_ in ("enemies", "bosses"):
        cell = int(d.get("frame_px", 128))
        # the paintings' cache key (a variant may use other paintings: "stills": "c4" -> goblin_c4_front) and the clips'
        # (a variant's own: goblin_gobb_pose_f)
        sk = id_ + ("_" + still_slug(d) if still_slug(d) else "")
        ak = id_ + ("_" + vcode.lower().replace("-", "") if vcode else "")
        img, inf = render(sk + "_front", styled(subject, "Full body, front view, standing and facing the viewer.", bg), refs,
                          {"subject": subject, "view": "front", "subjects_max": 1}, seed)
        info["renders"]["front"] = inf
        front_ref = comfy.upload_pil(img, sk + "_front.png")
        # a creature JSON may carry "back_hint" too: what the back view must keep (the centipede's coil at its base)
        back_prompt = ("Turn this exact creature around and show a full-body back view seen directly from behind, no face visible. Keep the same "
                       "colors, proportions and art style, standing. " + str(d.get("back_hint", "")) + " " + bg + ".")
        # or the JSON says the whole back prompt itself ("back_prompt"): a creature whose pose the generic wording undoes
        if d.get("back_prompt"):
            back_prompt = str(d["back_prompt"]) + " " + bg + "."
        # pass 73 (lane ART): a picture of the back ("back_ref") as the back still's second reference
        back_refs, back_prompt = back_ref_render(d, sk, bg, front_ref, back_prompt)
        back_img, inf = render(sk + "_back", back_prompt, back_refs, {"subject": "the same creature seen from behind", "view": "back", "subjects_max": 1,
                               "ref_h": figure_height(img)}, seed + 1)
        info["renders"]["back"] = inf
        # creatures get a heavier, darker outline than the hero so they separate from the sand and from each other
        CO, CF = (14, 8, 12, 255), 0.024
        # a creature may ask for a lighter outline in its JSON (the Elite is three times a goblin, so the heavy rim read as black)
        CF = float(d.get("outline_frac", CF))
        if d.get("outline_color"):
            oc = str(d["outline_color"]).lstrip("#")
            CO = (int(oc[0:2], 16), int(oc[2:4], 16), int(oc[4:6], 16), 255)
        # "cell_fill": how much of the cell the standing figure takes (0.86); a creature that hops needs the headroom
        base, sc = finish(img, cell, float(d.get("cell_fill", 0.86)), True, None, CF, None, CO)
        back_cell = finish(back_img, cell, 0.86, True, None, CF, figure_height_cell(base), CO)[0]
        motion = str(d.get("motion", "walking in place with a steady stomping gait"))
        clip = str(d.get("pose", ""))
        run_f = run_b = None
        if str(d.get("walk", "")) == "hop":
            # a blob that hops instead of walking (pass 45, JSON "walk": "hop": the Blue Slime, the Tumbleweed Minion): the
            # painting itself squashes, stretches and leaves the ground (artkit.hop_cycle), so the face never moves, the
            # colours are the painting's and no frame can clip; the video clips moved the slimes' mouths, greyed them
            # mid-hop and grew the minion legs
            hh = float(d.get("hop_height", 0.13))
            run_f = artkit.hop_cycle(base, cell, CREATURE_RUN_FRAMES, hh)
            run_b = artkit.hop_cycle(back_cell, cell, CREATURE_RUN_FRAMES, hh)
            clip = ""
            kinds["front"] = kinds["back"] = "procedural"
        elif clip:
            # a humanoid creature walks on a Mixamo stride (pass 33.4, the skeletons: "pose": "walk_zombie", rendered by
            # tools/pose_driver.py): Wan Animate paints the still onto the driver's skeleton, one sprite frame per driver
            # frame, front and back only
            # a front view may take its own driver ("pose_front"): arms held out towards a camera above drop on screen, so
            # the skeletons' front walk raises them a little where the back walk slopes them down
            anim_neg = str(d.get("anim_negative", ""))
            gait = str(d.get("gait", "walking in place on the spot like on a treadmill"))
            run_f = pose_cycle(img, ak + "_pose_f", str(d.get("pose_front", clip)), "front", seed, cell, base, motion, CF, CO, negative_extra=anim_neg, motion=gait, scale_mul=run_scale_of(d, "front"))
            run_b = pose_cycle(back_img, ak + "_pose_b", clip, "back", seed + 1, cell, base, motion, CF, CO, negative_extra=anim_neg, motion=gait, scale_mul=run_scale_of(d, "back"))
            kinds["front"] = "pose" if run_f is not None else "free"
            kinds["back"] = "pose" if run_b is not None else "free"
        # "clip_fill": the still's share of the free clip's canvas (0.72); a creature that bounces high takes less so its
        # frames never touch the edge (the Blue Slime's 0.56, pass 45)
        cfill = float(d.get("clip_fill", 0.72))
        if run_f is None:
            run_f = video_cycle(img, ak + "_walk_f", motion + ", facing the viewer, seen from the front", seed, cell, base, CREATURE_RUN_FRAMES, CF, CO, 49, cfill, scale_mul=run_scale_of(d, "front"))
            kinds["front"] = "free" if run_f is not None else "procedural"
        if run_b is None:
            run_b = video_cycle(back_img, ak + "_walk_b", motion + ", seen directly from behind, walking away from the viewer", seed + 1, cell, base, CREATURE_RUN_FRAMES, CF, CO, 49, cfill, scale_mul=run_scale_of(d, "back"))
            kinds["back"] = "free" if run_b is not None else "procedural"
        info["clips"] = {"walk_f": run_f is not None, "walk_b": run_b is not None, "pose": clip}
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
            # pass 66: the side views' paintings and clips are keyed like the front's (sk) and the walks' (ak): before,
            # they were keyed by the id alone, so a variant with eight directions overwrote the base creature's
            for suffix, (vname, turn_prompt, walk_prompt, k) in turns.items():
                hint = (", " + str(hints[vname])) if vname in hints else ""
                v_img, inf = render(sk + "_" + vname, turn_prompt + hint + ". Keep the same colors, proportions and art style. " + bg + ".", [front_ref],
                                    {"subject": "the same creature, " + vname + " view", "view": None, "subjects_max": 1, "ref_h": figure_height(img)}, seed + k)
                info["renders"][vname] = inf
                v_cell = finish(v_img, cell, 0.86, True, None, CF, stand_h, CO)[0]
                v_run = video_cycle(v_img, ak + "_walk_" + vname, motion + ", " + walk_prompt, seed + k, cell, base, CREATURE_RUN_FRAMES, CF, CO, 49, scale_mul=run_scale_of(d, vname))
                info["clips"]["walk_" + vname] = v_run is not None
                kinds[vname] = "free" if v_run is not None else "procedural"
                views[suffix] = (v_cell, v_run)
        if clip and run_f and run_b and str(d.get("stand", "walk")) != "still":
            # a pose-driven walk stands, winds up, flinches and falls apart in the walk's own pose (the still may not
            # hold the driver's pose: the skeletons' arms came out spread wide instead of reaching forward); "stand":
            # "still" keeps the painting for them, when the painting already stands the way the walk does (the goblin)
            base = passing_frame(run_f)
            back_cell = passing_frame(run_b)
        frames = artkit.enemy_frames(base, cell, run_f, back_cell, run_b, views)
        # pass 73 (lane ART, the Saiga Sniper's aim): painted attack poses (aim_hint / aim_ref) instead of the leans
        atk = attack_stills(d, sk, subject, bg, front_ref, img, back_img, seed, info)
        if atk:
            frames.update(attack_frames(atk[0], atk[1], base, back_cell, cell, CF, CO, d, info))
        # the death: a painted "dead" still edited from the front, and three frames of the standing painting tipping over into it
        # a creature JSON may carry "dead_hint": the death pose in its own words (the generic "limbs sprawled, tongue out" turned
        # the centipede into a goblin with arms)
        dead_pose = str(d.get("dead_hint", "lying flat on its back on the ground, dead: eyes shut tight, tongue hanging out, limbs sprawled "
                                           "limp in the air"))
        dead_prompt = ("This exact creature " + dead_pose + ", seen from the front and a little above so the whole body is visible. "
                       "Keep the same colors, proportions and art style. " + bg + ".")
        # a creature that falls apart dies as a heap: the vision check asks for a heap, and a heap is many pieces
        falls_apart = str(d.get("death", "")) == "collapse"
        dead_expect = {"subject": "a heap of loose bones with a skull on top" if falls_apart else "the same creature lying on its back", "view": None,
                       "subjects_max": 8 if falls_apart else 1, "no_match_ok": falls_apart}
        dead_img, inf = render(sk + "_dead", dead_prompt, [front_ref], dead_expect, seed + 9)
        info["renders"]["dead"] = inf
        dead_cell = finish(dead_img, cell, 0.7, True, None, CF, None, CO)[0]
        fall = None
        death = str(d.get("death", ""))
        if death == "clip":
            fall = death_cycle(img, dead_img, ak + "_fall", seed + 9, cell, base, int(d.get("death_frames", 8)), CF, CO, subject.split(",")[0][:120], str(d.get("anim_negative", "")))
        elif death.startswith("pose:"):
            fall = pose_death(img, ak + "_death", death[5:], seed + 9, cell, base, int(d.get("death_frames", 8)), CF, CO, subject.split(",")[0][:120], str(d.get("anim_negative", "")))
        kinds["die"] = ("flf" if death == "clip" else "pose") if fall else "procedural"
        if fall:
            frames["die"] = fall
        elif death == "squash":
            # a creature that splats instead of falling over (the Blue Slime, pass 44): the standing painting squashes flatter
            # and wider over four frames into the painted puddle (the first-last-frame clip between the two grew it legs)
            frames["die"] = [artkit.transform(base, sy=0.86, sx=1.08), artkit.transform(base, sy=0.68, sx=1.2), artkit.transform(base, sy=0.48, sx=1.36),
                             artkit.transform(base, sy=0.3, sx=1.5), dead_cell, dead_cell]
        elif falls_apart:
            # a creature that falls apart instead of falling over (the skeletons, pass 33.3, JSON "death": "collapse"):
            # the standing painting itself drops apart in slices (artkit.crumble), then the painted heap it ends as. A
            # painted mid-collapse was tried and came out as a two-headed skeleton dripping rust.
            frames["die"] = [artkit.transform(base, lean_deg=-6, sy=0.95), artkit.crumble(base, 0.45, seed), artkit.crumble(base, 0.85, seed),
                             dead_cell, dead_cell]
        else:
            # the deeper leans are refitted (artkit.fall) so the head never leaves the cell
            frames["die"] = [artkit.transform(base, lean_deg=-14, sy=0.97), artkit.fall(base, 38), artkit.fall(base, 66), dead_cell, dead_cell]
        strip, counts, cols = artkit.pack_strip(frames, artkit.ENEMY_ORDER, cell)
        if vcode:
            # a variant's strip and icon sit beside the ones the game uses (its icon is its own painting)
            d["sprite"] = id_ + "_sprite_" + vcode.split("-")[-1].lower() + ".png"
            strip.save(os.path.join(folder, d["sprite"]))
            d["icon"] = id_ + "_icon_" + vcode.split("-")[-1].lower() + ".png"
            if isinstance(ventry, dict) and ventry.get("icon_picked") and os.path.isfile(os.path.join(folder, d["icon"])):
                # pass 68: the look's icon was picked from candidates (the Level Editor marks the entry): kept
                log("  the look's icon was picked from candidates: kept (%s)" % d["icon"])
            else:
                vicon, _ = finish(img, 256, 0.9, False, None, 0.009)
                vicon.save(os.path.join(folder, d["icon"]))
        else:
            strip.save(os.path.join(folder, d.get("sprite", id_ + "_sprite.png")))
            icon, _ = finish(img, 256, 0.9, False, None, 0.009)
            icon.save(os.path.join(folder, d.get("icon", id_ + "_icon.png")))
        d["anims"] = counts
        d["strip_cols"] = cols
        # how tall the figure stands in its cell (the game hangs its badge just above; tools/measure_heads.py does the same
        # for strips painted before pass 33.3)
        d["head"] = round(max(figure_top(f) for f in frames.get("idle", []) + frames.get("run", [])) if frames.get("idle") or frames.get("run") else 0.86, 3)
        d["fps"] = {"run": int(d.get("run_fps", CREATURE_RUN_FPS)) if run_f else 10, "die": 12 if fall else 8}
    elif type_ == "characters":
        cell = int(d.get("frame_px", 256))
        pose_hint = str(d.get("pose_hint", ""))
        # a hero's art variant (pass 55, Solenne's walks): "still_keys" in its recipe names other paintings for some views
        # ({"side": "solenne_s55_side"}; the rest stay the hero's own, so the variants differ only where they should), and
        # its clips are cached under their own keys (solenne_solb_pose_run_front)
        # pass 68 (D1): a look with its own paintings ("stills": "c") keys them <id>_c_<view>, as a creature look does;
        # before, every hero look read the hero's <id>_<view> (MAM-C came out byte-identical to MAM-B)
        def sk_(view):
            return hero_still_key(id_, view, d)

        ck = id_ + ("_" + vcode.lower().replace("-", "") if vcode else "")
        front, inf = render(sk_("front"), styled(subject, "Full body, front view, standing straight and facing the viewer, arms relaxed, feet fully visible. " + pose_hint, bg), refs,
                            {"subject": subject, "view": "front", "subjects_max": 1, "legs": True}, seed)
        info["renders"]["front"] = inf
        front_ref = comfy.upload_pil(front, id_ + "_front.png")
        back_prompt = ("Turn this exact character around and show a full-body back view seen directly from behind: the back of the head or helmet, "
                       "the back of the outfit and the heels, no face visible. Keep the same outfit, colors, proportions and art style, standing "
                       "straight with arms relaxed. " + pose_hint + " " + str(d.get("back_hint", "")) + " " + bg + ".")
        back, inf = render(sk_("back"), back_prompt, [front_ref], {"subject": "the same character seen from behind", "view": "back", "subjects_max": 1, "legs": True, "ref_h": figure_height(front)}, seed + 1)
        info["renders"]["back"] = inf
        back_ref = comfy.upload_pil(back, id_ + "_back.png")
        side_prompt = ("Turn this exact character to show a full-body side view in strict profile, facing to the right of the frame, standing "
                       "straight with arms relaxed. Keep the same outfit, colors, proportions and art style. " + pose_hint + " " + str(d.get("side_hint", "")) + " " + bg + ".")
        side, inf = render(sk_("side"), side_prompt, [front_ref], {"subject": "the same character seen from the side in profile", "view": "side", "subjects_max": 1, "legs": True, "ref_h": figure_height(front)}, seed + 6)
        info["renders"]["side"] = inf
        side_ref = comfy.upload_pil(side, id_ + "_side.png")
        front_h, back_h, side_h = figure_height(front), figure_height(back), figure_height(side)
        fd_prompt = ("Turn this exact character to a three-quarter front view: turned 45 degrees so the character faces towards the lower right of "
                     "the frame, face visible, standing straight with arms relaxed. Keep the same outfit, colors, proportions and art style. " + pose_hint + " " + bg + ".")
        fd, inf = render(sk_("fd"), fd_prompt, [front_ref], {"subject": "the same character, three-quarter front view", "view": None, "subjects_max": 1, "legs": True, "ref_h": front_h}, seed + 7)
        info["renders"]["fd"] = inf
        bd_prompt = ("Turn this exact character to a three-quarter back view: turned 45 degrees away from the viewer so the character faces the upper "
                     "right of the frame, the back and right shoulder visible, standing straight with arms relaxed. Keep the same outfit, colors, "
                     "proportions and art style. " + pose_hint + " " + bg + ".")
        bd, inf = render(sk_("bd"), bd_prompt, [front_ref], {"subject": "the same character, three-quarter back view", "view": None, "subjects_max": 1, "legs": True, "ref_h": front_h}, seed + 8)
        info["renders"]["bd"] = inf
        poses = [("cheer", "seen directly from behind (no face visible), jumping for joy with both arms raised high above the head, feet together", back_ref, "back")]
        pose_imgs = {}
        for k, (name, pose, ref, view) in enumerate(poses):
            p = ("The exact same character " + pose + ". Keep the same outfit, colors, proportions and art style as the reference. " + bg + ".")
            ref_h = {"back": back_h, "front": front_h, "side": side_h}.get(view, 0)
            im, inf = render(sk_(name), p, [ref], {"subject": "the same character", "view": view, "subjects_max": 1, "legs": True, "ref_h": ref_h}, seed + 10 + k)
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
            vh = str(d.get("back_hint", "")) if view in ("back", "bd") else ""
            vhint = hint_for_view(hint, view, d)   # pass 71: a puppet look's back views on words without the face
            # a view may run on its own driver ("pose_drivers": {"back": "run_occ"}, pass 44: the back view's driver hides the
            # hand that swings in front of the chest, which Wan Animate had painted on the back of Calavera's jacket)
            drv = str((d.get("pose_drivers") or {}).get(view, "run"))
            # lane PUPPET (2026-10-13): "ctl_drivers" walks the view on a depth guide (Wan Fun Control) instead
            ctl = ctl_driver_of(d, view) if pose_ok else ""
            # pass 71 (lane PLE): a puppet look sizes each view's walk from its 3D puppet's run/idle ratio (run_fit)
            fr = run_fit_of(d, view)
            if fr:
                log("  (run_fit %s: the median frame at %.3f of the standing figure, from the puppet)" % (view, fr))
            if ctl:
                c = ctl_cycle(still_img, ck + "_ctl_run_" + view, ctl, view, seed + k, cell, cell_img, vhint, negative_extra=anim_neg, view_hint=vh,
                              motion=str(d.get("pose_motion", "running in place on the spot like on a treadmill")), scale_mul=run_scale_of(d, view), fit_ratio=fr)
            else:
                c = pose_cycle(still_img, ck + "_pose_run_" + view, drv, view, seed + k, cell, cell_img, vhint, negative_extra=anim_neg, view_hint=vh,
                               motion=str(d.get("pose_motion", "running in place on the spot like on a treadmill")), scale_mul=run_scale_of(d, view), fit_ratio=fr) if pose_ok else None
            kinds[view] = ("control" if ctl else "pose") if c is not None else "free"
            if c is None:
                c = video_cycle(still_img, ck + "_run" + (suffix or "_b"), prompt, seed + k, cell, cell_img, N, scale_mul=run_scale_of(d, view))
                kinds[view] = "free" if c is not None else "procedural"
            clips[suffix] = c
        # "remap_hues" (pass 46): hues the video model smeared into the clips that the hero's palette lacks go back to his
        # own (Ironwood's fringed legs streaked green and magenta: keying residue of the motion blur)
        rh = d.get("remap_hues")
        if isinstance(rh, dict):
            for sfx in list(clips.keys()):
                if clips[sfx]:
                    clips[sfx] = [artkit.remap_hues(f, rh.get("ranges", []), rh.get("to", 30), rh.get("sat", 0.55)) for f in clips[sfx]]
        # pass 71 (lane PLE): "fringe_remap" moves the hues a view's painting lacks to its nearest own hue (the Puppet trial's
        # rainbow fringes on the sleeves); off unless the recipe names it
        fx = d.get("fringe_remap")
        if fx:
            for sfx, still_v in (("", back), ("_f", front), ("_s", side), ("_bd", bd), ("_fd", fd)):
                if clips.get(sfx):
                    clips[sfx] = fringe_remap(clips[sfx], still_v, fx)
            info["fringe_remap"] = fx if isinstance(fx, dict) else True
        info["clips"] = {k or "_b": v is not None for k, v in clips.items()}
        # hit reactions: a painted "hurt" still per view, edited from that view's still by the image model so it reads like
        # the rest of the sheet, then a short procedural wince around it (the pose-driven pain clip looked wrong on every hero)
        hits = {}
        hurt_hint = str(d.get("hurt_hint", "eyes squeezed shut, teeth gritted"))
        for suffix, still_img, cell_img, view, ref_h, seedk in (("", back, back_cell, "back", back_h, 30), ("_f", front, front_cell, "front", front_h, 31),
                                                              ("_s", side, side_cell, "side", side_h, 32), ("_bd", bd, bd_cell, "bd", front_h, 33), ("_fd", fd, fd_cell, "fd", front_h, 34)):
            view_words = {"back": "seen directly from behind", "front": "facing the viewer", "side": "in strict side profile facing right",
                          "bd": "in three-quarter back view", "fd": "in three-quarter front view"}[view]
            h_prompt = ("One single figure alone in the frame: the exact same character " + view_words + ", flinching in pain from a hit: leaning back a little, shoulders hunched, "
                        "one hand raised towards the chest, " + hurt_hint + ", still standing on both feet, feet fully visible. Keep the same "
                        "outfit, colors, proportions, pose scale and art style as the reference. " + bg + ".")
            ref = comfy.upload_pil(still_img, sk_(view) + "_ref.png")
            h_img, inf = render(sk_("hurt_" + view), h_prompt, [ref], {"subject": "the same character flinching", "view": view if view in ("front", "back", "side") else None,
                                                                          "subjects_max": 1, "legs": True, "ref_h": ref_h}, seed + seedk)
            info["renders"]["hurt_" + view] = inf
            hurt_cell = finish(h_img, cell, 0.84, True, None, 0.012, stand_h)[0]
            # four frames at HERO_HIT_FPS: the flinch, a deeper lean, the flinch, and a half step back to standing
            hits[suffix] = [hurt_cell, artkit.transform(hurt_cell, lean_deg=-6, bob=2, sy=0.97, sx=1.03), hurt_cell, artkit.transform(cell_img, lean_deg=-3, sy=0.99)]
        info["hits"] = {k or "_b": v is not None for k, v in hits.items()}
        frames = artkit.character_frames(back_cell, clips[""], cheer_cell, cell, front_cell, clips["_f"], side_cell, clips["_s"], bd_cell, clips["_bd"], fd_cell, clips["_fd"], hits)
        # the death: a painted "down" still edited from the front, and the flinch tipping over into it (one set, the body lies the same from every side)
        dead_prompt = ("This exact character lying flat on the ground on their back, knocked out: limbs sprawled, head to one side, seen from the front and a "
                       "little above so the whole body is visible. Keep the same outfit, colors, proportions and art style. " + hurt_hint + ". " + bg + ".")
        dead_img, inf = render(sk_("dead"), dead_prompt, [front_ref], {"subject": "the same character lying on the ground", "view": None, "subjects_max": 1}, seed + 12)
        info["renders"]["dead"] = inf
        dead_cell = finish(dead_img, cell, 0.66, True, None, 0.012)[0]
        hurt_f = hits["_f"][0] if hits.get("_f") else front_cell
        frames["die"] = [artkit.transform(hurt_f, lean_deg=-14, sy=0.97), artkit.fall(hurt_f, 38), artkit.fall(hurt_f, 66), dead_cell, dead_cell]
        strip, counts, cols = artkit.pack_strip(frames, artkit.CHAR_ORDER, cell)
        run_fps = int(d.get("run_fps", HERO_RUN_FPS)) if all(v is not None for v in clips.values()) else 14
        if vcode:
            # a hero's variant strip sits beside the one the game plays; the badge stays the hero's own (pass 55)
            d["sprite"] = id_ + "_sprite_" + vcode.split("-")[-1].lower() + ".png"
            strip.save(os.path.join(folder, d["sprite"]))
        else:
            strip.save(os.path.join(folder, d.get("sprite", id_ + "_sprite.png")))
            # the icon: a painted close-up doing something, keyed and set into a round badge that fills the plate's lower half
            pp = str(d.get("portrait_prompt", "smiling at the viewer"))
            # edited from the front still so the face and outfit are this character's; the head fills half the frame
            p_prompt = ("A close-up portrait of this exact character for a mobile game avatar icon: only the head and shoulders, the head filling "
                        "half of the frame, " + pp + ", facing the viewer, the shoulders and chest running off the bottom edge of the frame, "
                        "expressive and lively, no legs, no full body. Keep the same face, outfit, colors and art style as the reference. " + bg + ".")
            # a hero JSON "badge" {still, head_width, top_pad} (pass 56, Solenne) names a painting picked by eye for the badge
            # (a key in the paintings' cache) and how it sits in the circle, so a later run makes the same badge
            bdg = d.get("badge") if isinstance(d.get("badge"), dict) else {}
            if bdg.get("still") and os.path.exists(os.path.join(RAW, str(bdg["still"]) + ".png")):
                p_img = Image.open(os.path.join(RAW, str(bdg["still"]) + ".png")).convert("RGB")
                info["renders"]["portrait"] = {"still": str(bdg["still"])}
            else:
                p_img, inf = render(id_ + "_portrait", p_prompt, [front_ref], {"subject": subject, "view": "front", "subjects_max": 1, "bust": True}, seed + 40)
                info["renders"]["portrait"] = inf
            portrait_badge(p_img, head_width=float(bdg.get("head_width", 0.0)), top_pad=float(bdg.get("top_pad", 0.03))).save(os.path.join(folder, d.get("icon", id_ + "_icon.png")))
        d["anims"] = counts
        d["strip_cols"] = cols
        d["fps"] = {"run": run_fps, "hit": HERO_HIT_FPS, "die": 8}
    else:
        img, inf = render(id_ + "_icon2", subject + ". " + ICON_STYLE + ". " + bg + ".", [],
                          {"subject": subject, "view": None, "subjects_max": 6 if many else 1}, seed)
        info["renders"]["icon"] = inf
        icon, _ = finish(img, 256, 0.92, False, None, 0.006)
        dst = os.path.join(folder, d.get("icon", id_ + "_icon.png"))
        # pass 66: the icon the game shows today is kept aside before it is overwritten (unless the bytes are the same)
        buf = io.BytesIO()
        icon.save(buf, "PNG")
        kept = backup_icon(dst, buf.getvalue())
        if kept:
            info["icon_backup"] = kept
            log("  old icon kept: %s" % kept)
        icon.save(dst)
    d.setdefault("art_prompt", subject)
    info["qa_online"] = QA_ONLINE
    # merge into the file as it is now: a field edited by hand while this item rendered (a hint for the next roll) must
    # survive the write-back, and only the keys this run sets are written. Under a Level Editor job (ASSET_JOB_SIDECAR)
    # nothing is written here: the patch goes into the sidecar and the server merges it in place (pass 66).
    jpath = os.path.join(folder, id_ + ".json")
    if vcode:
        patch = {k: d[k] for k in ("sprite", "icon", "anims", "strip_cols", "fps", "head") if k in d}
        json.dump(info, open(os.path.join(folder, id_ + "_" + vcode.split("-")[-1].lower() + "_ai.json"), "w", encoding="utf-8", newline="\n"), indent=1)
        if not WRITE_JSON:
            emit_sidecar(folder, id_, vcode, patch, info)
            return
        try:
            cur = json.load(open(jpath, encoding="utf-8"))
        except Exception:
            cur = dict(d)
        entry = cur.setdefault("variants", {}).setdefault(vcode, {})
        entry.update(patch)
        json.dump(cur, open(jpath, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
        return
    patch = {k: d[k] for k in ("anims", "strip_cols", "fps", "head") if k in d}
    write_marker(folder, id_, info)
    if not WRITE_JSON:
        emit_sidecar(folder, id_, "", patch, info, top={"art_prompt": d.get("art_prompt", subject)})
    else:
        try:
            cur = json.load(open(jpath, encoding="utf-8"))
        except Exception:
            cur = dict(d)
        cur.update(patch)
        cur.setdefault("art_prompt", d.get("art_prompt", subject))
        json.dump(cur, open(jpath, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
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
    # a painted illustration from tools/gen_app_icon.py when one has been picked (tools/dl/app_icon/icon_src.png);
    # the default hero's portrait badge on the sun gradient otherwise
    painted = os.path.join(REPO, "tools", "dl", "app_icon", "icon_src.png")
    game = os.path.join(REPO, "game")
    if os.path.exists(painted):
        art = Image.open(painted).convert("RGBA")
        art.resize((1024, 1024), Image.LANCZOS).save(os.path.join(game, "icon.png"))
        art.resize((192, 192), Image.LANCZOS).save(os.path.join(game, "icon_192.png"))
        # adaptive: the whole painting is the foreground (the subject sits inside the middle 66%, the launcher's safe
        # zone); the background is the painting's own sky colour, for launchers that peek past the foreground
        sky = art.resize((1, 1), Image.BOX).getpixel((0, 0))
        # the foreground sits at 88% on a sky-coloured plate, so a circle or squircle launcher mask keeps the glove
        fg = Image.new("RGBA", (432, 432), (sky[0], sky[1], sky[2], 255))
        inner = art.resize((380, 380), Image.LANCZOS)
        fg.alpha_composite(inner, (26, 26))
        fg.save(os.path.join(game, "icon_fg_432.png"))
        Image.new("RGBA", (432, 432), (sky[0], sky[1], sky[2], 255)).save(os.path.join(game, "icon_bg_432.png"))
        log("app icons written from the painted icon")
        return
    src = os.path.join(CONTENT, "characters", "astro", "astro_icon.png")
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
            # a low sun behind the badge
            r, cx, cy = int(sz * 0.46), sz // 2, int(sz * 0.62)
            dr.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 214, 90, 255))
        return im

    def compose(sz, fg_scale, bg=True):
        im = base(sz, bg)
        g = hero.copy()
        s = int(sz * fg_scale)
        g = g.resize((s, s), Image.LANCZOS)
        sh = Image.new("RGBA", g.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 140), (0, 0), g)
        sh = sh.filter(ImageFilter.GaussianBlur(sz * 0.01))
        x, y = (sz - g.width) // 2, int(sz * 0.5 - g.height * 0.5)
        im.alpha_composite(sh, (x + int(sz * 0.015), y + int(sz * 0.02)))
        im.alpha_composite(g, (x, y))
        return im

    compose(1024, 0.8).save(os.path.join(game, "icon.png"))
    compose(192, 0.8).save(os.path.join(game, "icon_192.png"))
    compose(432, 0.58, bg=False).save(os.path.join(game, "icon_fg_432.png"))
    base(432).save(os.path.join(game, "icon_bg_432.png"))
    log("app icons written from Astro's portrait")


# ---------------------------------------------------------------- main

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    st = comfy.get("/system_stats")
    log("ComfyUI", st["system"].get("comfyui_version"), "on", st["devices"][0].get("name"), "at", comfy.SERVER, "| model", painter_info()["unet"])
    if "--anchor" in sys.argv:
        anchor_candidates()
        return
    if PICK is not None:
        pick_anchor(PICK)
        if "--only" not in sys.argv and not any(a.startswith("--only=") for a in sys.argv):
            return
    types = ["characters", "enemies", "bosses", "weapons", "evolutions", "passives", "mutations", "perks", "resources", "shop", "elites", "maps", "quests", "pickups"]
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
