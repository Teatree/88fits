"""Hero badge candidates (pass 66): the round avatar icon a hero wears on his plates and sheet, painted several times from
his front still with the badge's portrait words, each shown inside the round badge so they can be picked by eye (the
vision check cannot tell a good face from a bad one). The pick writes the badge and remembers which painting it came
from, so a later gen_art run makes the same badge (the JSON's "badge" {still, head_width, top_pad}, pass 56).

    python tools/gen_badge_cands.py --id solenne --seeds 4 [--prompt "winking at the viewer"] [--first-seed 0] [--skip-qa]
                                    [--character "<who>"] [--ref <picture>] [--variant SOL-C] [--tag 8854] [--attempt 2]
        -> tools/dl/ai_raw_anime/<id>_portrait_<tag>_c<k>.png (+ .json) and tools/dl/review/<id>_badge_cands.png
    python tools/gen_badge_cands.py --id solenne --pick 2 [--tag 8854] [--variant SOL-C] [--head-width 0.8 --top-pad 0.05]
        -> game/content/characters/<id>/<id>_icon.png (the old one kept in tools/dl/backup/icons_le/) and
           "badge": {"still": "<id>_portrait_<tag>_c2", "head_width": .., "top_pad": ..} in the hero JSON; under a Level
           Editor job (ASSET_JOB_SIDECAR) the badge goes into the sidecar's `top.badge` and the JSON is left to the server.
           For a look (--variant, a code other than the base strip's: the base's code is the hero's own, as above):
           <id>_icon_<letter>.png and the look's own entry {"icon": ...} (variants[CODE].icon; the sidecar's `entry`
           under a job), no badge block.
           Pass 76: --icon-file NAME (the Level Editor's install, its icon guard) writes the badge to NAME instead, a file
           of its own (NAME_2.png when another picture has that name: nothing is overwritten); the sidecar says the file
           (`entry.icon` for a look, `info.icon_file` for the base) and the server names it in the JSON.

The words (pass 68, badge_prompt): "this exact character: <character>, only the head and shoulders, ..., <action>, ...".
The character only when --character gives one (the Level Editor fills it from the hero's description); the action is
--prompt, else the look's (or hero's) `portrait_prompt`, else "smiling at the viewer"; without --character the words are
the pass 66 ones. The reference: --ref (a path under the repo, under tools/dl/ or absolute, laid on the screen colour
when it has a transparent film), else the look's own front still (the base: <id>_front, as before).
Candidates are keyed per job (the tag: the last four letters and digits of --tag or of the Level Editor job's id, "x" by
hand), so a second job paints its own instead of getting the first one's back; a pick names the tag (--tag) or a whole
key. Seeds: gen_art.seed_for(id) + 40 + first, moved by the look's seed_offset and by --attempt (a re-run paints new
ones), then by the job (pass 70, tools/cand_seeds.py: the job id's own move, candidate k a prime past a million from
k-1; two jobs of one look painted the same seeds before); one try each. Both --x value and --x=value work; the painter flags (--dev, --model=, --steps=,
--guidance=, --turbo, --no-turbo) reach gen_art.
"""
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ARGS = sys.argv[1:]
_PAINTER_FLAGS = ("--skip-qa", "--dev", "--turbo", "--no-turbo")
sys.argv = ["gen_art.py", "--no-import"] + [a for a in ARGS if a in _PAINTER_FLAGS or a.startswith(("--model=", "--steps=", "--guidance="))]
sys.path.insert(0, HERE)
import gen_art as g  # noqa: E402
import comfy  # noqa: E402
import cand_seeds  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

REVIEW = os.path.join(REPO, "tools", "dl", "review")
# the heroes' folders (tools/asset_job.py points this at a job's own folder, so a check can run on a copy)
CHARS = os.path.join(REPO, "game", "content", "characters")
PAPER = (243, 230, 200)


def opt(name, default=None):
    for i, a in enumerate(ARGS):
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
        if a == "--" + name and i + 1 < len(ARGS):
            return ARGS[i + 1]
    return default


def hero_folder(hid):
    return os.path.join(CHARS, hid)


def hero_json(hid):
    return json.load(open(os.path.join(hero_folder(hid), hid + ".json"), encoding="utf-8"))


# ---------------------------------------------------------------- the words, the keys and the seeds (pure)

def clean_words(s):
    """Words as typed, without the trailing comma, semicolon or full stop that would break the sentence they go into."""
    return re.sub(r"[\s,;.]+$", "", str(s or "").strip())


def action_of(d, words=""):
    """What the portrait shows the hero doing: the job's words, else the (look's) portrait_prompt, else a smile."""
    return str(words or d.get("portrait_prompt", "smiling at the viewer"))


def badge_prompt(character, action, bg):
    """gen_art's badge wording (process(), the characters branch) round the hero's portrait words, the hero's description
    first when one is given (pass 68: the painter had the picture but no words for who it shows)."""
    who = clean_words(character)
    return ("A close-up portrait of this exact character for a mobile game avatar icon: " + (who + ", " if who else "") +
            "only the head and shoulders, the head filling half of the frame, " + str(action) + ", facing the viewer, the shoulders "
            "and chest running off the bottom edge of the frame, expressive and lively, no legs, no full body. Keep the same face, "
            "outfit, colors and art style as the reference. " + bg + ".")


def portrait_prompt(d, words, bg):
    """The pass 66 words (no description), kept for its callers."""
    return badge_prompt("", action_of(d, words), bg)


def cand_tag(job_id=""):
    """The candidates' per-job tag: the last four letters and digits of a Level Editor job id (or of --tag); "x" by hand."""
    s = re.sub(r"[^A-Za-z0-9]", "", str(job_id or ""))
    return s[-4:] if s else "x"


def cand_key(hid, tag, k):
    return "%s_portrait_%s_c%d" % (hid, tag, int(k))


def badge_seeds(hid, seeds, first=0, offset=0, attempt=1, tag=""):
    """The first seed (pass 72: the job's "First seed" when it names one, else seed_for(id) + 40: cand_seeds.start; it was
    added to that before), moved by the look's seed_offset and by the job's attempt (each step gen_art.LOOK_SEED_STEP),
    then cand_seeds.seeds: the job's own move (`tag`, the Level Editor job id; none by hand) and candidate k CAND_STEP
    from k-1 (pass 70: a second job of one look had painted the first one's seeds again)."""
    base = cand_seeds.start(g.seed_for(hid) + 40, first) + g.LOOK_SEED_STEP * (int(offset) + max(0, int(attempt) - 1))
    return cand_seeds.seeds(base, seeds, tag)


def front_still_key(d, hid, code=""):
    """The painting a badge starts from: the look's front still (pass 68: a look with its own paintings has its own),
    else the hero's (the JSON's still_keys.front, else <id>_front)."""
    return g.hero_still_key(hid, "front", g.look_merged(d, code) if code else d)


def pick_key(hid, k, tag=None):
    """The candidate a pick names: a number (c2 or 2) under the job's tag (by hand "x", then the pass 66 untagged name),
    or a whole key."""
    s = str(k).strip()
    if s[:1] in ("c", "C") and s[1:].isdigit():
        s = s[1:]
    if not s.isdigit():
        return s
    key = cand_key(hid, cand_tag(tag) if tag else "x", int(s))
    if not tag and not os.path.isfile(os.path.join(g.RAW, key + ".png")):
        old = "%s_portrait_c%d" % (hid, int(s))
        if os.path.isfile(os.path.join(g.RAW, old + ".png")):
            return old
    return key


def look_code(d, variant):
    """The look a run is for ("" = the hero's own badge). The base strip's code (variant_base) is the hero's own too (pass
    68 review: the game never reads a hero base entry's icon, and the Level Editor sends no code for the base look): its
    badge is <id>_icon.png and the top-level badge block. Any other code names a look: <id>_icon_<letter>.png and its
    entry's icon."""
    code = str(variant or "").strip()
    return "" if g.is_base_code(d, code) else code


# ---------------------------------------------------------------- painting and picking

def sheet(hid, cands, head_width, top_pad):
    """Every candidate (key, image) inside the round badge on the title's paper, numbered."""
    size, pad = 256, 20
    out = Image.new("RGB", (len(cands) * (size + pad) + pad, size * 2 + 3 * pad + 30), PAPER)
    dr = ImageDraw.Draw(out)
    for i, (k, img) in enumerate(cands):
        img = img.convert("RGB")
        x = pad + i * (size + pad)
        out.paste(img.resize((size, size), Image.LANCZOS), (x, pad))
        badge = g.portrait_badge(img, size, head_width, top_pad)
        out.paste(badge, (x, size + 2 * pad), badge)
        dr.text((x + 4, size * 2 + 2 * pad + 6), "#%d  %s" % (i, k), fill=(36, 27, 20))
    os.makedirs(REVIEW, exist_ok=True)
    p = os.path.join(REVIEW, "%s_badge_cands.png" % hid)
    out.save(p)
    return p


def reference(hid, d0, code, ref, blue):
    """(uploaded name, the file it came from): --ref laid on the screen colour, else the look's front still."""
    if ref:
        src = g.ref_path(ref)
        if src is None:
            raise SystemExit("gen_badge_cands: no reference picture %r (looked under the repo, under tools/dl/ and as given)" % str(ref))
        return comfy.upload_pil(g.on_screen(Image.open(src), blue), comfy.safe_name("%s_badge_ref_%s" % (hid, os.path.basename(src)))), src
    key = front_still_key(d0, hid, code)
    src = os.path.join(g.RAW, key + ".png")
    if not os.path.isfile(src):
        raise SystemExit("gen_badge_cands: no front still %s (paint the look first, or name a picture with --ref)" % src)
    return comfy.upload_pil(Image.open(src).convert("RGB"), key + ".png"), src


def paint(hid, seeds, words="", first=0, head_width=0.0, top_pad=0.03, character="", ref="", variant="", tag=None, attempt=1):
    d0 = hero_json(hid)
    code = look_code(d0, variant)
    d = g.look_merged(d0, code) if code else d0
    bg = g.bg_for(d, "characters")
    front_ref, ref_file = reference(hid, d0, code, ref, bg == g.BG_BLUE)
    action = action_of(d, words)
    prompt = badge_prompt(character, action, bg)
    raw_tag = cand_seeds.job_tag(tag)
    tag = cand_tag(raw_tag)
    seed_list = badge_seeds(hid, seeds, first, g.seed_offset_of(d), attempt, raw_tag)
    keys, cands = [], []
    for k, s in enumerate(seed_list):
        key = cand_key(hid, tag, k)
        img, inf = g.render(key, prompt, [front_ref], {"subject": g.subject_for(d, "characters"), "view": "front", "subjects_max": 1, "bust": True},
                            s, tries=1)
        g.log("  badge %s c%d seed %d  %s" % (hid, k, inf.get("seed", s), ",".join(inf.get("qa", {}).get("problems", [])) or "ok"))
        keys.append(key)
        cands.append((key, img))
    path = sheet(hid, cands, head_width, top_pad)
    g.log("  badge candidates painted: look at %s, then --pick k" % path)
    sidecar = os.environ.get("ASSET_JOB_SIDECAR", "")
    if sidecar:
        json.dump({"id": hid, "kind": "hero_badge", "prompt": prompt, "review": path,
                   "choices": [os.path.join(g.RAW, k + ".png") for k in keys], "keys": keys, "tag": tag, "variant": code,
                   "ref": ref_file, "character": clean_words(character), "action": action, "seeds": seed_list},
                  open(sidecar, "w", encoding="utf-8", newline="\n"), indent=1)
    return keys, path


def pick(hid, k, head_width=0.0, top_pad=0.03, variant="", tag=None, icon_file=""):
    key = pick_key(hid, k, tag)
    src = os.path.join(g.RAW, key + ".png")
    if not os.path.isfile(src):
        raise SystemExit("gen_badge_cands: no candidate %s" % src)
    d = hero_json(hid)
    code = look_code(d, variant)
    if code and not g.has_look(d, code):
        raise SystemExit("gen_badge_cands: %s has no look %s" % (hid, code))
    img = Image.open(src).convert("RGB")
    badge = g.portrait_badge(img, 256, head_width, top_pad)
    buf = io.BytesIO()
    badge.save(buf, "PNG")
    sidecar = os.environ.get("ASSET_JOB_SIDECAR", "")
    icon_file = os.path.basename(str(icon_file or ""))
    if icon_file:
        # pass 76 (the Level Editor's icon guard): the badge goes into a file of its own (--icon-file, the server's new
        # name), never over another picture; the look's entry (or, for the base, the top-level icon) is named by the
        # server through set_look_files, which keeps the look's icon_history
        name, dst = g.free_icon_name(hero_folder(hid), icon_file, buf.getvalue())
        badge.save(dst)
        g.log("installed %s -> %s for %s (a file of its own: nothing overwritten)" % (key, dst, code or "the base"))
        info = {"pipeline": "gen_badge_cands", "pick": key, "icon_backup": "", "icon_file": name, "head_width": float(head_width),
                "top_pad": float(top_pad)}
        top = {} if code else {"badge": {"still": key, "head_width": float(head_width), "top_pad": float(top_pad)}}
        if sidecar:
            g.emit_sidecar(hero_folder(hid), hid, code, {"icon": name} if code else {}, info, top=top)
            return dst
        jpath = os.path.join(hero_folder(hid), hid + ".json")
        if code:
            g.write_look_entry(jpath, code, {"icon": name, "icon_picked": True})
        else:
            g.write_top_block(jpath, "icon", name, (("after", "flavour"), ("end", None)))
            g.write_top_block(jpath, "badge", top["badge"], (("after", "portrait_prompt"), ("end", None)))
        g.log("%s names its icon %s" % (code or hid, name))
        return dst
    if code:
        # pass 68 (D8): a look's own badge beside the hero's; the look's entry names it, the hero's badge block is untouched
        name = "%s_icon_%s.png" % (hid, g.look_letter(code))
        dst = os.path.join(hero_folder(hid), name)
        kept = g.backup_icon(dst, buf.getvalue())
        badge.save(dst)
        g.log("installed %s -> %s for %s%s" % (key, dst, code, (" (old kept: %s)" % kept) if kept else ""))
        info = {"pipeline": "gen_badge_cands", "pick": key, "icon_backup": kept, "head_width": float(head_width), "top_pad": float(top_pad)}
        if sidecar:
            g.emit_sidecar(hero_folder(hid), hid, code, {"icon": name}, info)
            return dst
        g.write_look_entry(os.path.join(hero_folder(hid), hid + ".json"), code, {"icon": name})
        g.log("%s's entry names its icon %s" % (code, name))
        return dst
    dst = os.path.join(hero_folder(hid), d.get("icon", hid + "_icon.png"))
    kept = g.backup_icon(dst, buf.getvalue())
    badge.save(dst)
    top = {"badge": {"still": key, "head_width": float(head_width), "top_pad": float(top_pad)}}
    g.log("installed %s -> %s%s" % (key, dst, (" (old kept: %s)" % kept) if kept else ""))
    if sidecar:
        # the server writes "badge" into the hero JSON in place
        g.emit_sidecar(hero_folder(hid), hid, "", {}, {"pipeline": "gen_badge_cands", "pick": key, "icon_backup": kept}, top=top)
        return dst
    jpath = os.path.join(hero_folder(hid), hid + ".json")
    # the Level Editor's structured writer keeps the file's layout when it is at hand
    g.write_top_block(jpath, "badge", top["badge"], (("after", "portrait_prompt"), ("end", None)))
    g.log("badge written into %s: %s" % (jpath, json.dumps(top["badge"])))
    return dst


def main():
    hid = opt("id")
    if not hid:
        raise SystemExit(__doc__)
    head_width = float(opt("head-width", "0") or 0)
    top_pad = float(opt("top-pad", "0.03") or 0.03)
    variant = opt("variant", "") or ""
    if opt("pick") is not None:
        # the candidates' tag: --tag, else the job the queue runs the pick under (an install job carries the painting
        # job's id as ASSET_JOB_ID); by hand neither: the x candidates, then the pass 66 untagged ones
        pick(hid, opt("pick"), head_width, top_pad, variant, opt("tag") or os.environ.get("ASSET_JOB_ID") or None,
             icon_file=opt("icon-file", "") or "")
        return
    paint(hid, int(opt("seeds", "4")), opt("prompt", "") or "", int(opt("first-seed", "0") or 0), head_width, top_pad,
          character=opt("character", "") or "", ref=opt("ref", "") or "", variant=variant, tag=opt("tag"),
          attempt=int(opt("attempt", "1") or 1))


if __name__ == "__main__":
    main()
