"""Title-screen hero cut-outs (the Wanted title's carousel, pass 40): a full-body splash painting per hero.

Each hero is painted with Flux.2 Klein from its front sprite still (tools/dl/ai_raw_anime/<id>_front.png, the identity
reference) standing in a confident pose facing the viewer, on the screen colour its still was painted on; then keyed,
trimmed and fitted to the title's 520 x 700 box at 1.27x (660 x 888, the phone's scale). Several seeds per hero; they are
picked by eye from the review sheet (vision QA passes extra fingers and ears), then installed:

    python tools/gen_title_heroes.py [--only astro,drifter] [--seeds 4] [--first-seed 11]
                                     [--character "<who>"] [--pose ..] [--holds ..] [--camera ..] [--ref <picture>]
                                     [--extra-ref <picture>] [--extra-words ..] [--variant AST-B] [--tag 8854] [--attempt 2]
        -> tools/dl/title_heroes/<id>[_<letter>][_<tag>]_<n>.png (keyed, fitted) + raw renders + review_<id>[_<letter>][_<tag>].png
    python tools/gen_title_heroes.py --pick astro=2 drifter=1 [--variant AST-B] [--tag 8854]
        -> game/art/ui/wanted/hero_<id>.png (the title's WPlaceholder slot `hero_<id>` draws it); for a look (--variant,
           a code other than the base strip's: the base's code is the hero's own), hero_<id>_<letter>.png and the look's
           entry {"title": ...} (variants[CODE].title; the sidecar's `entry` under a Level Editor job). The cut-out it
           replaces is kept in tools/dl/backup/title/ first.

The candidates are keyed per job (pass 68 review, as the badges): under a Level Editor job the tag is the last four letters
and digits of its id (ASSET_JOB_ID, or --tag), so a second job paints its own instead of overwriting the first's, and a
pick names the job that painted them (--tag). By hand (no tag) a run paints and a pick reads the untagged names, as
before (<id>[_<letter>]_<n>.png).

Pass 68: the words and the picture are inputs. Each of --character, --pose, --holds, --camera, --extra-ref and
--extra-words (or paint()'s keyword of the same name) wins when it is given and not empty; otherwise the hero JSON's
title_* keys, then the tables below, then plain defaults (title_words). The character's description goes right after
"this exact character" (title_prompt). The reference: --ref (a path under the repo, under tools/dl/ or absolute, laid on
the screen colour when it has a transparent film), else the look's own front still (the base: <id>_front). Seeds:
first, moved by the look's seed_offset and by --attempt (a re-run paints new ones), then by the job (pass 70,
tools/cand_seeds.py: the job id's own move, candidate n a prime past a million from n-1; every title job of a hero had
painted 11, 112, 213, 314). Both --x v and --x=v work.
"""
import io
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import artkit  # noqa: E402
import cand_seeds  # noqa: E402
import comfy  # noqa: E402
from gen_art import STYLE, BG_BLUE, BG_GREEN  # noqa: E402
import gen_art as ga  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_anime")
OUT = os.path.join(REPO, "tools", "dl", "title_heroes")
SLOT_DIR = os.path.join(REPO, "game", "art", "ui", "wanted")
BACKUP = os.path.join(REPO, "tools", "dl", "backup", "title")
# the heroes' folders (tools/asset_job.py points this at a job's own folder, so a check can run on a copy)
CHARS = os.path.join(REPO, "game", "content", "characters")
BOX = (660, 888)          # the title's 520 x 700 box at 1.27x
RENDER = (832, 1120)      # the same shape, multiples of 16

# the pose each hero strikes (built from its portrait_prompt: the same gesture, the whole body)
POSES = {
    "astro": "standing tall in a confident heroic stance with one hand on her hip and the other giving a cheerful thumbs-up in an "
             "orange glove; her round helmet visor is a completely dark opaque black mirror with no face visible behind it",
    "drifter": "standing with his feet apart, one hand tipping the brim of his wide hat with two fingers, a confident half-smile, "
               "his long brown duster coat and red scarf swaying in the wind",
    "dad": "standing with his hands on his hips and his chest puffed out, grinning proudly under his thick brown mustache",
    "buck": "standing relaxed with one thumb hooked in the collar of his teal t-shirt, a slow easy grin and one eyebrow raised",
    "mira": "standing with one gloved hand raised holding up a fat gold nugget, grinning with a wink, her long braid over her shoulder",
    # pass 46 (Garry): the cartoon guitar from his reference model, looking off to the side and down, smiling slightly
    "calavera": "standing relaxed with his feet apart, holding the cartoon Mexican acoustic guitar from the second reference image across "
                "his body in playing position, one hand on its neck and the other over its strings, his head turned to look off to the "
                "side and down with a slight quiet smile under his painted sugar-skull face, his wide black sombrero tipped a little "
                "forward, his red sash and bow tie bright against the black charro suit",
    # pass 46: Ironwood, a serious fellow: arms crossed, looking down at us, his spear planted beside him
    "ironwood": "standing tall and still with his arms crossed over his bare chest, his chin lowered a little, looking down at the viewer "
                "with a calm, stern, unsmiling face, his long black hair over his shoulders, the tall spear from the second reference "
                "image planted upright in the ground beside him",
}
# heroes painted with something in their hands (the prompt otherwise forbids a weapon, which the model reads as any held thing)
HOLDS = {"calavera": "the guitar is the only thing he holds",
         "ironwood": "his hands hold nothing; the spear stands on its own, planted in the ground beside him"}
# a second reference image per hero (pass 46): the object the pose shows, rendered from the game's own 3D model
# (tools/dl/<x>_ref.png, transparent film laid on the screen colour)
EXTRA_REFS = {"calavera": ("guitarra_ref.png", "The second reference image shows the guitar: copy its shape and colours exactly: a "
                           "yellow top with a thin red line round its edge, green sides, a round rosette of red, white and blue "
                           "triangles round a black soundhole, a black neck and headstock. "),
              "ironwood": ("spear_ref.png", "The second reference image shows the spear: a long dark wooden shaft wrapped in red cloth "
                           "at three places, two feathers hanging under a leaf-shaped steel point. ")}
# the camera and the way the hero faces, when not the default (eye level, facing the viewer)
CAMERA = {"ironwood": "his body facing the viewer, seen from the front and a little from below so that he looks down at the viewer"}
FACING = {"calavera": "his body facing the viewer, seen from the front at eye level"}
# pass 68 (D6): the pose of a hero with no title_pose and no row above (it was the badge's head-and-shoulders words)
DEFAULT_POSE = "standing confidently in a heroic pose, full body"
DEFAULT_HOLDS = "no weapon"
DEFAULT_VIEW = "facing the viewer, seen from the front at eye level"
FLAGS = ("only", "seeds", "first-seed", "character", "pose", "holds", "camera", "ref", "extra-ref", "extra-words", "variant", "attempt",
         "tag")


def log(*a):
    print(*a, flush=True)


def hero_folder(hid):
    return os.path.join(CHARS, hid)


def hero_json(hid):
    return json.load(open(os.path.join(hero_folder(hid), hid + ".json"), encoding="utf-8"))


def screen_of(still):
    """The screen colour the hero's still was painted on (it was chosen to key well): blue or green."""
    r, g, b = still.convert("RGB").getpixel((8, 8))
    return BG_GREEN if g > b else BG_BLUE


def screen_sniff(pic):
    """A picture's screen colour when its corner clearly is one (a painting on the green or blue screen); None for a
    transparent corner or any other colour (an upload on white, a turnaround sheet)."""
    rgba = pic.convert("RGBA")
    r, g, b, a = rgba.getpixel((8, 8))
    if a < 250:
        return None
    if g > 150 and r < 100 and b < 100:
        return BG_GREEN
    if b > 150 and r < 100 and g < 100:
        return BG_BLUE
    return None


def fit(rgba):
    """Trim to the figure and fit it to BOX: 95 % of the height, feet 2 % off the bottom, centred."""
    bbox = rgba.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    fig = rgba.crop(bbox)
    k = min(BOX[1] * 0.95 / fig.height, BOX[0] * 0.98 / fig.width)
    fig = fig.resize((max(1, round(fig.width * k)), max(1, round(fig.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", BOX, (0, 0, 0, 0))
    out.alpha_composite(fig, ((BOX[0] - fig.width) // 2, BOX[1] - fig.height - round(BOX[1] * 0.02)))
    return out


# ---------------------------------------------------------------- the words (pure)

def title_words(hid, d):
    """The pose, what the hero holds, the camera and the extra reference: the hero JSON's `title_pose`, `title_holds`,
    `title_camera`, `title_extra_ref {file, words}` first (pass 66: the Level Editor's hero form writes them), then the
    tables above, then plain defaults (pass 68: DEFAULT_POSE, no longer the badge's portrait_prompt). Returns (pose,
    holds, view, extra_ref (file, words) or None)."""
    pose = str(d.get("title_pose") or POSES.get(hid) or DEFAULT_POSE)
    holds = str(d.get("title_holds") or HOLDS.get(hid, DEFAULT_HOLDS))
    view = str(d.get("title_camera") or CAMERA.get(hid) or FACING.get(hid) or DEFAULT_VIEW)
    extra = None
    er = d.get("title_extra_ref")
    if isinstance(er, dict) and er.get("file"):
        extra = (str(er["file"]), str(er.get("words", "")))
    elif hid in EXTRA_REFS:
        extra = EXTRA_REFS[hid]
    return pose, holds, view, extra


def title_inputs(hid, d, pose=None, holds=None, camera=None, extra_ref=None, extra_words=None):
    """The words one paint uses (pass 68): a given, non-empty value wins; an empty or missing one is the hero's default
    (title_words). A given extra picture comes with the given extra words only (the default words describe the default
    picture). Returns (pose, holds, view, extra file or "", extra words)."""
    dp, dh, dv, de = title_words(hid, d)
    ef, ew = de if de else ("", "")
    if extra_ref:
        ef, ew = str(extra_ref), str(extra_words or "")
    elif extra_words:
        ew = str(extra_words)
    return str(pose or dp), str(holds or dh), str(camera or dv), ef, ew


def clean_words(s):
    """Words as typed, without the trailing comma, semicolon or full stop that would break the sentence they go into."""
    return re.sub(r"[\s,;.]+$", "", str(s or "").strip())


def title_prompt(character, pose, camera, holds, extra_words, style, bg):
    """The cut-out's words: the hero's description right after "this exact character" when one is given (pass 68), the
    pose, the camera, the whole figure, what the hands hold, the extra reference's words, the style and the screen."""
    who = clean_words(character)
    extra = str(extra_words or "")
    extra = extra + (" " if extra and not extra.endswith(" ") else "")
    return ("A full-body character illustration of this exact character" + (", " + who + "," if who else "") +
            " for a mobile game's hero select screen: " + str(pose) + ", " + str(camera) + ", the whole figure visible from the top of the "
            "head down to the feet with empty space around it, " + str(holds) + ". " + extra + "Keep the same face, outfit, colors and "
            "proportions as the reference. " + style + ". " + bg + ".")


def title_seeds(first, seeds, offset=0, attempt=1, tag=""):
    """first (pass 72: 0 = the tool's own start, 11: cand_seeds.start), moved by the look's seed_offset and the job's
    attempt (each a gen_art.LOOK_SEED_STEP), then cand_seeds.seeds: the job's own move (`tag`, the Level Editor job id;
    none by hand) and candidate n CAND_STEP from n-1 (pass 70)."""
    move = ga.LOOK_SEED_STEP * (int(offset) + max(0, int(attempt) - 1))
    return cand_seeds.seeds(cand_seeds.start(11, first) + move, seeds, tag)


def out_stem(hid, code=""):
    """The look's name: <id> for the hero, <id>_<letter> for a look (its cut-out hero_<stem>.png; its candidates
    title_heroes/<stem>[_<tag>]_<n>.png, cand_stem)."""
    return hid + ("_" + ga.look_letter(code) if code else "")


def cand_tag(tag=""):
    """The candidates' per-job tag (gen_badge_cands.cand_tag's rule): the last four letters and digits of a Level Editor
    job id (or of --tag); "" by hand. (Not the badges' "x": a hand run's <id>_x_<n> would be a look X's <id>_x_<n>.)"""
    s = re.sub(r"[^A-Za-z0-9]", "", str(tag or ""))
    return s[-4:]


def cand_stem(hid, code="", tag=None):
    """The candidates' name (pass 68 review): <id>[_<letter>]_<tag> under a job, so a second title job for the same hero
    or look paints files of its own (title_heroes/<cand_stem>_<n>.png, review_<cand_stem>.png, <cand_stem>.json); by
    hand (no tag) <id>[_<letter>] as before."""
    t = cand_tag(tag)
    return out_stem(hid, code) + ("_" + t if t else "")


def look_code(d, variant):
    """The look a run is for ("" = the hero's own cut-out). The base strip's code (variant_base) is the hero's own too
    (pass 68 review: one rule with the Level Editor, which sends no code for the base look: its cut-out is hero_<id>.png,
    what the game shows for a base entry that names none); any other code names a look: its cut-out is
    hero_<id>_<letter>.png and its entry's title."""
    code = str(variant or "").strip()
    return "" if ga.is_base_code(d, code) else code


def parse_args(argv):
    """The command line: {"pick": [pairs] or None, "only", "seeds", "first_seed", "character", "pose", "holds",
    "camera", "ref", "extra_ref", "extra_words", "variant", "attempt"} (the strings as given); --x v and --x=v."""
    out = {"pick": None}
    argv = [str(a) for a in argv]
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--pick":
            pairs = []
            i += 1
            while i < len(argv) and not argv[i].startswith("--"):
                pairs.append(argv[i])
                i += 1
            out["pick"] = pairs
            continue
        if a.startswith("--"):
            name, eq, val = a[2:].partition("=")
            if name in FLAGS:
                if not eq and i + 1 < len(argv):
                    i += 1
                    val = argv[i]
                out[name.replace("-", "_")] = val
        i += 1
    return out


# ---------------------------------------------------------------- painting and picking

def paint(hid, seeds, first, character=None, pose=None, holds=None, camera=None, ref=None, extra_ref=None, extra_words=None,
          variant=None, attempt=1, tag=None):
    d0 = hero_json(hid)
    code = look_code(d0, variant)
    d = ga.look_merged(d0, code) if code else d0
    stem = out_stem(hid, code)
    # the candidates are this job's own (--tag, else the Level Editor job's id; untagged by hand)
    raw_tag = cand_seeds.job_tag(tag)
    tag = cand_tag(raw_tag)
    cstem = cand_stem(hid, code, tag)
    if ref:
        src = ga.ref_path(ref)
        if src is None:
            raise SystemExit("gen_title_heroes: no reference picture %r (looked under the repo, under tools/dl/ and as given)" % str(ref))
        pic = Image.open(src)
        # a painting on a screen says its colour; anything else (an upload on white) goes on the hero's own screen
        bg = screen_sniff(pic) or ga.bg_for(d, "characters")
        still = ga.on_screen(pic, bg == BG_BLUE)
    else:
        src = os.path.join(RAW, ga.hero_still_key(hid, "front", d) + ".png")
        if not os.path.isfile(src):
            raise SystemExit("gen_title_heroes: no front still %s (paint the look first, or name a picture with --ref)" % src)
        still = Image.open(src)
        bg = screen_of(still)
        still = still.convert("RGB")
    artkit.KEY_SAT = float(d.get("key_sat", 0.35))
    artkit.GRADE = d.get("grade")
    refs = [comfy.upload_pil(still, "title_ref_" + stem + ".png")]
    pose_w, holds_w, view_w, extra_file, extra_w = title_inputs(hid, d, pose, holds, camera, extra_ref, extra_words)
    if extra_file:
        ep = ga.ref_path(extra_file)
        if ep is None:
            raise SystemExit("gen_title_heroes: no second reference picture %r (looked under the repo, under tools/dl/ and as given)" % extra_file)
        refs.append(comfy.upload_pil(ga.on_screen(Image.open(ep), bg == BG_BLUE), comfy.safe_name("title_extra_" + os.path.basename(ep))))
    prompt = title_prompt(character, pose_w, view_w, holds_w, extra_w, STYLE, bg)
    os.makedirs(OUT, exist_ok=True)
    seed_list = title_seeds(first, seeds, ga.seed_offset_of(d), attempt, raw_tag)
    made = []
    for n, seed in enumerate(seed_list):
        imgs, secs = ga.paint(prompt, seed, RENDER[0], RENDER[1], refs, "88fits/title_" + stem)   # the painter from gen_art.MODEL
        raw = Image.open(io.BytesIO(imgs[0])).convert("RGB")
        raw.save(os.path.join(OUT, "%s_%d_raw.png" % (cstem, n)))
        cut = fit(artkit.key_background(raw))
        cut.save(os.path.join(OUT, "%s_%d.png" % (cstem, n)))
        made.append(cut)
        log("  %s #%d seed %d  %.1fs" % (cstem, n, seed, secs))
    json.dump({"prompt": prompt, "seeds": seed_list, "ref": os.path.basename(src), "variant": code, "tag": tag},
              open(os.path.join(OUT, cstem + ".json"), "w", encoding="utf-8"), indent=1)
    sheet = review(cstem, made)
    # pass 66: a Level Editor job reads the candidates and the words that were sent from its sidecar
    sidecar = os.environ.get("ASSET_JOB_SIDECAR", "")
    if sidecar:
        json.dump({"id": hid, "kind": "hero_title", "prompt": prompt, "review": sheet,
                   "choices": [os.path.join(OUT, "%s_%d.png" % (cstem, n)) for n in range(len(seed_list))], "variant": code,
                   "tag": tag, "ref": src, "extra_ref": extra_file, "seeds": seed_list},
                  open(sidecar, "w", encoding="utf-8", newline="\n"), indent=1)
    return made


def review(stem, cuts):
    """The candidates side by side on the title's paper, numbered, to pick by eye."""
    pad = 20
    sheet = Image.new("RGB", (len(cuts) * (BOX[0] + pad) + pad, BOX[1] + 2 * pad + 40), (243, 230, 200))
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(os.path.join(REPO, "game", "ui", "fonts", "AlfaSlabOne-Regular.ttf"), 34)
    except Exception:
        font = ImageFont.load_default()
    for i, c in enumerate(cuts):
        x = pad + i * (BOX[0] + pad)
        dr.rectangle([x - 2, pad - 2, x + BOX[0] + 1, pad + BOX[1] + 1], outline=(36, 27, 20), width=2)
        sheet.paste(c, (x, pad), c)
        dr.text((x + 8, pad + BOX[1] + 4), "#%d" % i, fill=(36, 27, 20), font=font)
    path = os.path.join(OUT, "review_%s.png" % stem)
    sheet.save(path)
    log("  review: " + path)
    return path


def pick(pairs, variant=None, tag=None):
    """Install <id>=N: the hero's cut-out, or with `variant` (a look code; the base strip's is the hero's own) the
    look's own; N is a candidate of the job `tag` names (title_heroes/<cand_stem>_<N>.png; no tag: a hand run's
    untagged one); the file it replaces is kept in tools/dl/backup/title/ first (pass 68)."""
    os.makedirs(SLOT_DIR, exist_ok=True)
    sidecar = os.environ.get("ASSET_JOB_SIDECAR", "")
    done = []
    for p in pairs:
        hid, n = p.split("=")
        d = hero_json(hid)
        code = look_code(d, variant)
        if code and not ga.has_look(d, code):
            raise SystemExit("gen_title_heroes: %s has no look %s" % (hid, code))
        stem = out_stem(hid, code)
        if n.lower().endswith(".png"):
            # pass 70: a candidate named by its file (the Level Editor's look picker installs any job's cut-out into any look)
            src = os.path.join(OUT, os.path.basename(n))
        else:
            src = os.path.join(OUT, "%s_%s.png" % (cand_stem(hid, code, tag), n))
        if not os.path.isfile(src):
            raise SystemExit("gen_title_heroes: no candidate %s" % src)
        name = "hero_%s.png" % stem
        if not code:
            # pass 70: a base look made from a look (its old base removed) keeps the cut-out its entry names, which the
            # game shows for the base (JsonContent: the base entry's title)
            bent = (d.get("variants") or {}).get(str(d.get("variant_base") or "")) if isinstance(d.get("variants"), dict) else None
            if isinstance(bent, dict) and bent.get("title") and re.match(r"^[A-Za-z0-9._-]+\.png$", str(bent["title"])):
                name = os.path.basename(str(bent["title"]))
        dst = os.path.join(SLOT_DIR, name)
        buf = io.BytesIO()
        Image.open(src).save(buf, "PNG")
        kept = ga.backup_icon(dst, buf.getvalue(), BACKUP)
        with open(dst, "wb") as f:
            f.write(buf.getvalue())
        log("installed %s -> %s%s" % (src, dst, (" (old kept: %s)" % kept) if kept else ""))
        info = {"pipeline": "gen_title_heroes", "pick": os.path.basename(src), "title_backup": kept}
        if code:
            # pass 68 (D8): the look's entry names its cut-out (a file under res://art/ui/wanted/)
            if sidecar:
                ga.emit_sidecar(hero_folder(hid), hid, code, {"title": name}, info)
            else:
                ga.write_look_entry(os.path.join(hero_folder(hid), hid + ".json"), code, {"title": name})
                log("%s's entry names its cut-out %s" % (code, name))
        elif sidecar:
            ga.emit_sidecar(hero_folder(hid), hid, "", {}, info)
        done.append(dst)
    return done


def main():
    o = parse_args(sys.argv[1:])
    if o["pick"] is not None:
        # the candidates' tag: --tag, else the job the queue runs the pick under (an install job carries the painting
        # job's id as ASSET_JOB_ID); by hand neither: the untagged ones a hand run paints
        pick(o["pick"], o.get("variant") or None, o.get("tag") or os.environ.get("ASSET_JOB_ID") or None)
        return
    only = [x for x in str(o.get("only") or "").split(",") if x] or ["astro", "drifter", "dad", "buck", "mira"]
    seeds = int(o.get("seeds") or 4)
    first = int(o.get("first_seed") or 11)
    for hid in only:
        log("painting " + hid)
        paint(hid, seeds, first, character=o.get("character"), pose=o.get("pose"), holds=o.get("holds"), camera=o.get("camera"),
              ref=o.get("ref"), extra_ref=o.get("extra_ref"), extra_words=o.get("extra_words"), variant=o.get("variant"),
              attempt=int(o.get("attempt") or 1), tag=o.get("tag"))


if __name__ == "__main__":
    main()
