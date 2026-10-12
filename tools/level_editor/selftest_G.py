"""Lane G's checks (pass 68): the art tools' inputs, words, keys and seeds, without ComfyUI.

- gen_art: a hero look's still keys (D1: `<id>_<slug>_<view>`, still_keys first, no slug = the hero's own), a look's
  seeds (D2: seed_offset x 104729), the painter the marker names (D4), the reference helpers (a path under the repo,
  under tools/dl/, absolute or /dl/...; a transparent picture laid on the screen colour), the look-entry writer.
- gen_badge_cands / gen_title_heroes / gen_icon_cands (D7): the words as pure functions (every pass 66 prompt kept when
  no new input is given, every hand-written icon job's words unchanged), the per-job candidate keys and tags, the seeds,
  the command lines, the picks on temporary copies (a look's own icon or cut-out and its entry, the base as before, the
  old cut-out backed up, a hero refused by the icon pick).
- tools/asset_job.py: how a job's argv, job.json keys, spec and target reach each tool (badge_argv, title_call,
  icon_spec), and --dry-run end to end on temporary copies of Astro (the badge, the title, the icon candidates, a hero
  look through gen_art, the picks skipped): the words, references, seeds and keys recorded in dry_run.json.

selftest.py discovers this file and calls `checks(check, run_node, server)`. Nothing here writes under game/ or into
tools/dl/ (every tool's folders are pointed at temporary ones), and nothing reaches ComfyUI.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
RAW = os.path.join(ROOT, "tools", "dl", "ai_raw_anime")


def _legacy_badge(pp, bg):
    """gen_badge_cands.portrait_prompt as pass 66 wrote it (and gen_art's base badge)."""
    return ("A close-up portrait of this exact character for a mobile game avatar icon: only the head and shoulders, the head filling "
            "half of the frame, " + pp + ", facing the viewer, the shoulders and chest running off the bottom edge of the frame, "
            "expressive and lively, no legs, no full body. Keep the same face, outfit, colors and art style as the reference. " + bg + ".")


def _legacy_title(pose, view, holds, words, style, bg):
    """gen_title_heroes.paint's words as pass 66 wrote them."""
    extra = words + (" " if words and not words.endswith(" ") else "")
    return ("A full-body character illustration of this exact character for a mobile game's hero select screen: " + pose +
            ", " + view + ", the whole figure visible from the top of the head down to the "
            "feet with empty space around it, " + holds + ". " + extra + "Keep the same face, outfit, colors and proportions as the reference. " +
            style + ". " + bg + ".")


def _import_tools():
    """The four tools and asset_job, imported in this process with sys.argv kept (gen_badge_cands rewrites it)."""
    saved_argv, saved_path = list(sys.argv), list(sys.path)
    sys.path.insert(0, TOOLS)
    try:
        import gen_badge_cands as gbc
        sys.argv = list(saved_argv)
        import gen_title_heroes as gth
        import gen_icon_cands as gic
        import asset_job as aj
        import gen_art as ga
        import comfy
    finally:
        sys.argv = saved_argv
        sys.path[:] = saved_path
    return ga, gbc, gth, gic, aj, comfy


def _figure(path, screen=(0, 0, 255), size=(256, 256)):
    """A small keyable painting: a figure on the screen colour."""
    from PIL import Image, ImageDraw
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = Image.new("RGB", size, screen)
    dr = ImageDraw.Draw(im)
    w, h = size
    dr.ellipse((w * 0.36, h * 0.12, w * 0.64, h * 0.4), fill=(235, 190, 150))
    dr.rectangle((w * 0.3, h * 0.38, w * 0.7, h * 0.9), fill=(200, 80, 30))
    im.save(path)
    return path


def _transparent(path, colour=(200, 30, 30, 255)):
    """A picture with a transparent film round a disc (a Blender render, a cut-out)."""
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((16, 16, 48, 48), fill=colour)
    im.save(path)
    return path


def _write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(obj, indent=2) + "\n")


def checks(check, run_node, server):
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        check(True, "lane G skipped: numpy/Pillow not in this interpreter")
        return
    ga, gbc, gth, gic, aj, comfy = _import_tools()
    n0 = _count(check)
    _gen_art_checks(check, ga)
    _badge_checks(check, ga, gbc)
    _title_checks(check, ga, gth)
    _icon_checks(check, ga, gic)
    _asset_job_checks(check, aj, gth)
    _pick_checks(check, ga, gbc, gth, gic)
    _gen_ctl_checks(check)
    _dry_run_checks(check, ga, gbc, gth, gic, comfy)
    print("lane G: art tools' words, keys, seeds, picks and dry runs (%s checks)" % (_count(check) - n0 if n0 is not None else "?"))


def _count(check):
    """The shared pass counter, when selftest.py's `check` is the one handed in (for the summary line only)."""
    try:
        mod = sys.modules.get("__main__")
        return mod.PASSES[0] if hasattr(mod, "PASSES") else None
    except Exception:
        return None


# ---------------------------------------------------------------- gen_art (D1, D2, D4, the shared helpers)

def _gen_art_checks(check, ga):
    k = ga.hero_still_key
    check(k("mamy", "front", {}) == "mamy_front" and k("mamy", "dead", {"stills": ""}) == "mamy_dead",
          "D1: a hero look with no slug reads the hero's own paintings (<id>_<view>)")
    views = ("front", "back", "side", "fd", "bd", "cheer", "hurt_front", "hurt_back", "hurt_side", "hurt_bd", "hurt_fd", "dead")
    check([k("mamy", v, {"stills": "c"}) for v in views] == ["mamy_c_" + v for v in views], "D1: a slug keys every hero still <id>_<slug>_<view>")
    sk = {"stills": "c", "still_keys": {"side": "solenne_s55_side", "hurt_side": "solenne_s55_hurt_side", "back": ""}}
    check(k("solenne", "side", sk) == "solenne_s55_side" and k("solenne", "hurt_side", sk) == "solenne_s55_hurt_side",
          "D1: still_keys[view] wins over the slug")
    check(k("solenne", "front", sk) == "solenne_c_front" and k("solenne", "back", sk) == "solenne_c_back",
          "D1: views still_keys leaves out (or names empty) follow the slug")
    check(k("solenne", "side", {"still_keys": {"side": "solenne_s55_side"}}) == "solenne_s55_side" and
          k("solenne", "front", {"still_keys": {"side": "x"}}) == "solenne_front", "D1: SOL-B's still_keys without a slug as before")
    check(k("mamy", "front", {"still_keys": "not a dict", "stills": None}) == "mamy_front", "D1: a broken still_keys or a null slug is ignored")
    check(ga.still_slug({"stills": "b"}) == "b" and ga.still_slug({}) == "" and ga.still_slug({"stills": ""}) == "" and ga.still_slug(None) == "",
          "still_slug: the look's own paintings or none")
    # D2: seeds
    base = ga.seed_for("mamy")
    check(ga.LOOK_SEED_STEP == 104729, "D2: the look seed step is the prime 104729")
    check(ga.look_seed("mamy", {}) == base and ga.look_seed("mamy", {"seed_offset": 0}) == base and ga.look_seed("mamy", {"seed_offset": None}) == base,
          "D2: no seed_offset = the seeds every look before pass 68 was painted with")
    check(ga.look_seed("mamy", {"seed_offset": 7}) == base + 7 * 104729 and ga.look_seed("mamy", {"seed_offset": "3"}) == base + 3 * 104729,
          "D2: seed_offset moves the first seed by 104729 a step")
    check(ga.look_seed("mamy", {"seed_offset": "junk"}) == base and ga.seed_offset_of({"seed_offset": 2.0}) == 2,
          "D2: a seed_offset that is not a number counts as 0")
    offs = [1 + (i * 37) % 9973 for i in range(40)]
    check(len({ga.look_seed("dust_mummy", {"seed_offset": o}) for o in offs}) == len(set(offs)), "D2: different offsets, different seeds")
    retries = {ga.look_seed("dust_mummy", {"seed_offset": 5}) + a * 7919 for a in range(3)}
    check(not any((ga.look_seed("dust_mummy", {"seed_offset": o}) in retries) for o in range(0, 200) if o != 5),
          "D2: one look's retry seeds (7919 steps) never land on another look's first seed")
    # D4: the painter
    saved = dict(ga.MODEL)
    try:
        ga.MODEL.update(model="klein", steps=0, guidance=0.0, turbo=None)
        check(ga.painter_info() == {"model": "klein", "unet": ga.comfy.KLEIN_UNET, "steps": 4}, "D4: Klein, 4 steps by default: %s" % ga.painter_info())
        ga.MODEL.update(model="dev", steps=0, guidance=0.0, turbo=None)
        p = ga.painter_info()
        check(p["model"] == "dev" and p["unet"] == ga.comfy.FLUX2_UNET and p["steps"] == 8 and p["turbo"] is True and p["guidance"] == 4.0,
              "D4: dev quick form: 8 Turbo steps: %s" % p)
        p = ga.painter_info(full=True)
        check(p["steps"] == 28 and p["turbo"] is False, "D4: dev full (the candidates' default): 28 steps without Turbo: %s" % p)
        ga.MODEL.update(model="dev", steps=32, guidance=3.5, turbo=True)
        p = ga.painter_info()
        check(p["steps"] == 32 and p["guidance"] == 3.5 and p["turbo"] is True, "D4: the job's own steps and guidance: %s" % p)
    finally:
        ga.MODEL.clear()
        ga.MODEL.update(saved)
    src = open(os.path.join(TOOLS, "gen_art.py"), encoding="utf-8").read()
    check('"model": comfy.KLEIN_UNET' not in src and '"model": painter["unet"]' in src, "D4: the run's marker no longer hard-codes Klein")
    check("seed = look_seed(id_, d)" in src and "return hero_still_key(id_, view, d)" in src, "D1/D2: process() reads the look's seed and still keys")
    # look codes and the merged recipe
    d = {"id": "mamy", "art_prompt": "a mime", "variant_base": "MAM-A",
         "variants": {"MAM-A": {"note": "base"}, "MAM-C": {"recipe": {"stills": "c", "art_prompt": "a mime in red"}}}}
    check(ga.look_letter("MAM-C") == "c" and ga.look_letter("GOB-AB") == "ab" and ga.look_letter("") == "", "look_letter: the code's letter")
    check(ga.is_base_code(d, "") and ga.is_base_code(d, None) and ga.is_base_code(d, "MAM-A") and not ga.is_base_code(d, "MAM-C"),
          "is_base_code: no code or the JSON's variant_base")
    m = ga.look_merged(d, "MAM-C")
    check(m["stills"] == "c" and m["art_prompt"] == "a mime in red" and m["id"] == "mamy" and d["art_prompt"] == "a mime",
          "look_merged: the look's recipe over the JSON, the JSON untouched")
    check(ga.look_merged(d, "MAM-A") == d and ga.look_merged({"id": "x"}, "") == {"id": "x"}, "look_merged: the base as it is")
    check(ga.has_look(d, "MAM-C") and ga.has_look(d, "MAM-A") and ga.has_look(d, "") and ga.has_look({"variant_base": "X-A"}, "X-A")
          and not ga.has_look(d, "MAM-Z") and not ga.has_look({}, "X-B"), "has_look: an entry or the variant_base; a mistyped code is not a look")
    try:
        ga.look_merged(d, "MAM-Z")
        check(False, "look_merged: an unknown look is refused")
    except SystemExit as e:
        check("MAM-Z" in str(e), "look_merged: an unknown look is refused: %s" % e)
    # the reference helpers on a temporary repo
    from PIL import Image
    tmp = tempfile.mkdtemp(prefix="le_selftest_G_ref_")
    saved_repo = ga.REPO
    try:
        ga.REPO = os.path.join(tmp, "repo")
        a = _figure(os.path.join(ga.REPO, "tools", "dl", "spear_ref.png"))
        b = _figure(os.path.join(ga.REPO, "tools", "dl", "uploads", "2d", "Mime Sheet.png"))
        c = _figure(os.path.join(tmp, "elsewhere.png"))
        np_ = os.path.normpath
        check(ga.ref_path("spear_ref.png") == np_(a), "ref_path: a render under tools/dl/ by its name")
        check(ga.ref_path("tools/dl/uploads/2d/Mime Sheet.png") == np_(b) and ga.ref_path("tools\\dl\\uploads\\2d\\Mime Sheet.png") == np_(b),
              "ref_path: an upload by its repo path (the space kept)")
        check(ga.ref_path("uploads/2d/Mime Sheet.png") == np_(b), "ref_path: an upload by its tools/dl path")
        check(ga.ref_path(c) == np_(c), "ref_path: an absolute path")
        check(ga.ref_path("/dl/uploads/2d/Mime Sheet.png") == np_(b), "ref_path: the page's /dl/ URL")
        check(ga.ref_path("uploads/2d/MimeSheet.png") is None and ga.ref_path("") is None and ga.ref_path(None) is None,
              "ref_path: a missing picture (Garry's typed name without its space) is None, not a crash")
    finally:
        ga.REPO = saved_repo
    try:
        t = Image.open(_transparent(os.path.join(tmp, "t.png")))
        blue, green = ga.on_screen(t, True), ga.on_screen(t, False)
        check(blue.mode == "RGB" and blue.getpixel((0, 0)) == (0, 0, 255) and green.getpixel((0, 0)) == (0, 255, 0),
              "on_screen: the transparent film laid on the blue or the green screen")
        check(blue.getpixel((32, 32)) == (200, 30, 30) and green.getpixel((32, 32)) == (200, 30, 30), "on_screen: the picture itself kept")
        o = Image.open(_figure(os.path.join(tmp, "o.png"), screen=(250, 250, 250)))
        check(list(ga.on_screen(o, True).getdata()) == list(o.convert("RGB").getdata()), "on_screen: an opaque picture comes back as it is")
        # backups and the look-entry writer
        dst = os.path.join(tmp, "icon.png")
        open(dst, "wb").write(b"old")
        check(ga.backup_icon(dst, b"old", os.path.join(tmp, "bk")) == "" and not os.path.isdir(os.path.join(tmp, "bk")), "backup_icon: the same bytes keep no copy")
        kept = ga.backup_icon(dst, b"new", os.path.join(tmp, "bk"))
        check(kept and os.path.dirname(kept) == os.path.join(tmp, "bk") and open(kept, "rb").read() == b"old", "backup_icon: a folder of its own (the title's)")
        jp = os.path.join(tmp, "x.json")
        text = '{\n  "id": "x",\n  "name": "X",\n  "variants": {\n    "X-B": {"note": "b", "sprite": "x_sprite_b.png"}\n  },\n  "hp": 10.0\n}\n'
        open(jp, "w", encoding="utf-8", newline="\n").write(text)
        ga.write_look_entry(jp, "X-B", {"title": "hero_x_b.png"})
        back = json.load(open(jp, encoding="utf-8"))
        new = open(jp, encoding="utf-8", newline="").read()
        check(back["variants"]["X-B"] == {"note": "b", "sprite": "x_sprite_b.png", "title": "hero_x_b.png"} and back["hp"] == 10.0 and '"hp": 10.0' in new,
              "write_look_entry: the key joins the look's entry, the rest of the file kept: %s" % back["variants"])
        check(new.startswith('{\n  "id": "x",\n  "name": "X",\n') and "\r" not in new, "write_look_entry: the file's layout and line endings kept")
        ga.write_look_entry(jp, "X-C", {"icon": "x_icon_c.png"})
        check(json.load(open(jp, encoding="utf-8"))["variants"].get("X-C") == {"icon": "x_icon_c.png"}, "write_look_entry: a look with no entry yet gets one")
        ga.write_top_block(jp, "badge", {"still": "x_portrait_x_c1", "head_width": 0.0, "top_pad": 0.03}, (("end", None),))
        check(json.load(open(jp, encoding="utf-8")).get("badge", {}).get("still") == "x_portrait_x_c1", "write_top_block: the badge block written")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- gen_badge_cands (D7)

def _badge_checks(check, ga, gbc):
    bg = ga.BG_BLUE
    for pp in ("smiling at the viewer", "head and shoulders, winking", ""):
        check(gbc.badge_prompt("", pp, bg) == _legacy_badge(pp, bg) and gbc.portrait_prompt({"portrait_prompt": pp or "x"}, pp, bg) == _legacy_badge(pp or "x", bg),
              "badge: no character = the pass 66 words exactly (%r)" % pp)
    p = gbc.badge_prompt("a slender mime woman with a black beret; ", "her hands pressed on glass", bg)
    check(p.startswith("A close-up portrait of this exact character for a mobile game avatar icon: a slender mime woman with a black beret, only the head"),
          "badge: the character right after the colon, its trailing semicolon dropped: %s" % p[:140])
    check(", her hands pressed on glass, facing the viewer," in p and p.endswith(bg + "."), "badge: the action and the screen in place")
    check(gbc.action_of({"portrait_prompt": "winking"}) == "winking" and gbc.action_of({"portrait_prompt": "winking"}, "waving") == "waving"
          and gbc.action_of({}) == "smiling at the viewer", "badge: the action is --prompt, else portrait_prompt, else a smile")
    check(gbc.clean_words("  a mime ;, . ") == "a mime" and gbc.clean_words(None) == "", "clean_words: trailing punctuation off")
    check(gbc.cand_tag("j20261012-112518-8854") == "8854" and gbc.cand_tag("8854") == "8854" and gbc.cand_tag("") == "x" and gbc.cand_tag(None) == "x"
          and gbc.cand_tag("ab") == "ab" and gbc.cand_tag("--__") == "x", "badge: the tag is the job id's last four letters and digits, x by hand")
    check(gbc.cand_key("mamy", "8854", 2) == "mamy_portrait_8854_c2", "badge: candidates keyed <id>_portrait_<tag>_c<k>")
    base = ga.seed_for("mamy") + 40
    check(gbc.badge_seeds("mamy", 3) == [base, base + 1000, base + 2000], "badge: the base's first attempt paints the pass 66 seeds")
    check(gbc.badge_seeds("mamy", 2, 5, 2, 3) == [base + 5 + 4 * 104729, base + 5 + 4 * 104729 + 1000], "badge: first seed, look offset and attempt move the seeds")
    d = {"id": "mamy", "variant_base": "MAM-A", "still_keys": {}, "variants": {"MAM-A": {}, "MAM-C": {"recipe": {"stills": "c"}},
                                                                            "MAM-D": {"recipe": {"still_keys": {"front": "mamy_d55_front"}}}, "MAM-E": {"recipe": {"stills": ""}}}}
    check(gbc.front_still_key(d, "mamy") == "mamy_front" and gbc.front_still_key(d, "mamy", "MAM-C") == "mamy_c_front"
          and gbc.front_still_key(d, "mamy", "MAM-D") == "mamy_d55_front" and gbc.front_still_key(d, "mamy", "MAM-E") == "mamy_front",
          "badge: the reference is the look's own front still (its slug or still_keys), else the hero's")
    check(gbc.front_still_key({"still_keys": {"front": "x_s_front"}}, "x") == "x_s_front", "badge: the hero's still_keys.front as in pass 66")
    check(gbc.look_code(d, "") == "" and gbc.look_code(d, None) == "" and gbc.look_code(d, "MAM-C") == "MAM-C" and gbc.look_code(d, "MAM-A") == ""
          and gbc.look_code(d, " MAM-A ") == "" and gbc.look_code({}, "MAM-A") == "MAM-A",
          "badge: no code = the hero's own badge; the base strip's code (variant_base) is the hero's own too (the review: the game never "
          "reads a hero base entry's icon); any other code is a look")
    check(gbc.pick_key("mamy", "2", "j20261012-112518-8854") == "mamy_portrait_8854_c2" and gbc.pick_key("mamy", "c2", "8854") == "mamy_portrait_8854_c2",
          "badge pick: a number under the painting job's tag")
    check(gbc.pick_key("mamy", "mamy_portrait_8854_c2") == "mamy_portrait_8854_c2", "badge pick: a whole key as it is")
    # main(): the pick's tag is --tag, else the job the queue runs it under (ASSET_JOB_ID: lane J gives an install job the
    # painting job's id), else none (by hand); the paint's is --tag, else ASSET_JOB_ID
    calls = []
    saved = (gbc.pick, gbc.paint, gbc.ARGS, os.environ.get("ASSET_JOB_ID"))
    try:
        gbc.pick = lambda *a, **kw: calls.append(("pick", a, kw))
        gbc.paint = lambda *a, **kw: calls.append(("paint", a, kw))
        os.environ["ASSET_JOB_ID"] = "j20261012-112518-8854"
        gbc.ARGS = ["--id", "mamy", "--pick", "2", "--variant", "MAM-C"]
        gbc.main()
        gbc.ARGS = ["--id", "mamy", "--pick", "2", "--tag", "abcd"]
        gbc.main()
        del os.environ["ASSET_JOB_ID"]
        gbc.ARGS = ["--id", "mamy", "--pick=c1"]
        gbc.main()
        gbc.ARGS = ["--id", "mamy", "--seeds", "3", "--character=a mime", "--ref", "x.png", "--variant", "MAM-C", "--attempt", "2", "--first-seed", "7", "--prompt", "waving"]
        gbc.main()
        check([c[1][4:] for c in calls[:3]] == [("MAM-C", "j20261012-112518-8854"), ("", "abcd"), ("", None)] and [c[1][1] for c in calls[:3]] == ["2", "2", "c1"],
              "badge main(): the pick's tag from --tag, else ASSET_JOB_ID, else none: %s" % [c[1] for c in calls[:3]])
        check(calls[3][0] == "paint" and calls[3][1] == ("mamy", 3, "waving", 7, 0.0, 0.03)
              and calls[3][2] == {"character": "a mime", "ref": "x.png", "variant": "MAM-C", "tag": None, "attempt": 2},
              "badge main(): every paint flag reaches paint(): %s" % (calls[3][1:],))
    finally:
        gbc.pick, gbc.paint, gbc.ARGS = saved[:3]
        os.environ.pop("ASSET_JOB_ID", None)
        if saved[3] is not None:
            os.environ["ASSET_JOB_ID"] = saved[3]


# ---------------------------------------------------------------- gen_title_heroes (D7)

def _title_checks(check, ga, gth):
    S, B = ga.STYLE, ga.BG_BLUE
    for pose, view, holds, words in (("standing", "facing the viewer", "no weapon", ""),
                                     (gth.POSES["calavera"], gth.FACING["calavera"], gth.HOLDS["calavera"], gth.EXTRA_REFS["calavera"][1])):
        check(gth.title_prompt("", pose, view, holds, words, S, B) == _legacy_title(pose, view, holds, words, S, B),
              "title: no character = the pass 66 words exactly (%s)" % pose[:30])
    p = gth.title_prompt("a slender mime woman; ", "standing tall", "facing the viewer", "no weapon", "The second picture is a ball", S, B)
    check(p.startswith("A full-body character illustration of this exact character, a slender mime woman, for a mobile game's hero select screen: standing tall, facing the viewer,"),
          "title: the character right after 'this exact character': %s" % p[:150])
    check("no weapon. The second picture is a ball Keep the same face" in p, "title: the extra words before the keep sentence")
    pose, holds, view, extra = gth.title_words("calavera", {})
    check(pose == gth.POSES["calavera"] and holds == gth.HOLDS["calavera"] and view == gth.FACING["calavera"] and extra == gth.EXTRA_REFS["calavera"],
          "title: calavera's table words as before")
    check(gth.title_words("ironwood", {})[2] == gth.CAMERA["ironwood"], "title: the camera table")
    w = gth.title_words("mamy", {"portrait_prompt": "head and shoulders, her mime face"})
    check(w[0] == gth.DEFAULT_POSE == "standing confidently in a heroic pose, full body" and w[1] == "no weapon" and w[2] == gth.DEFAULT_VIEW and w[3] is None,
          "title: no title_pose and no table row = the full-body default, not the badge's head-and-shoulders words")
    dj = {"title_pose": "arms crossed", "title_holds": "a cane", "title_camera": "from below", "title_extra_ref": {"file": "cane_ref.png", "words": "The cane."}}
    check(gth.title_words("calavera", dj) == ("arms crossed", "a cane", "from below", ("cane_ref.png", "The cane.")), "title: the JSON's title_* first")
    ti = gth.title_inputs
    check(ti("calavera", {}) == (gth.POSES["calavera"], gth.HOLDS["calavera"], gth.FACING["calavera"]) + gth.EXTRA_REFS["calavera"],
          "title_inputs: nothing given = the defaults")
    check(ti("calavera", {}, pose="", holds="", camera="", extra_ref="", extra_words="") == ti("calavera", {}),
          "title_inputs: an empty field = the default (a server that leaves calavera's pose empty keeps his guitar)")
    check(ti("calavera", {}, pose="jumping", holds="a hat", camera="from above")[:3] == ("jumping", "a hat", "from above"), "title_inputs: given words win")
    check(ti("calavera", {}, extra_ref="uploads/2d/hat.png")[3:] == ("uploads/2d/hat.png", ""), "title_inputs: a new extra picture drops the table's guitar words")
    check(ti("calavera", {}, extra_ref="uploads/2d/hat.png", extra_words="The hat.")[3:] == ("uploads/2d/hat.png", "The hat."), "title_inputs: with its own words")
    check(ti("calavera", {}, extra_words="Another guitar.")[3:] == ("guitarra_ref.png", "Another guitar."), "title_inputs: new words for the default picture")
    check(ti("mamy", {})[3:] == ("", ""), "title_inputs: no extra picture")
    check(gth.title_seeds(11, 4) == [11, 112, 213, 314], "title: the pass 66 seeds")
    check(gth.title_seeds(11, 2, 5, 2) == [11 + 6 * 104729, 112 + 6 * 104729], "title: a look's offset and the attempt move them")
    d = {"variant_base": "AST-A", "variants": {"AST-A": {}, "AST-X": {}}}
    check(gth.out_stem("astro") == "astro" and gth.out_stem("astro", "AST-X") == "astro_x", "title: a look's stem <id>[_<letter>] (its cut-out hero_<stem>.png)")
    check(gth.look_code(d, "AST-A") == "" and gth.look_code(d, "AST-X") == "AST-X" and gth.look_code(d, None) == "" and gth.look_code(None, "") == ""
          and gth.look_code(None, "AST-X") == "AST-X", "title: no code or the base strip's code = the hero's own cut-out (the review); any other code is a look")
    # the review: the cut-outs are keyed per job (a second job for the same look painted over the first's)
    check(gth.cand_tag("j20261012-112518-8854") == "8854" and gth.cand_tag("abcd") == "abcd" and gth.cand_tag(None) == "" and gth.cand_tag("--") == "",
          "title: the tag is the job id's last four letters and digits (the badges' rule), none by hand")
    check(gth.cand_stem("astro", "AST-X", "j20261012-112518-8854") == "astro_x_8854" and gth.cand_stem("astro", "", "abcd") == "astro_abcd"
          and gth.cand_stem("astro", "AST-X") == "astro_x" and gth.cand_stem("astro") == "astro",
          "title: candidates <id>[_<letter>]_<tag>_<n>.png under a job; a hand run's <id>[_<letter>]_<n>.png as before")
    o = gth.parse_args(["--only", "astro", "--seeds", "3", "--first-seed=5", "--character", "a b", "--variant=AST-B", "--extra-words", "x y",
                        "--extra-ref=r.png", "--pose", "p", "--holds", "h", "--camera", "c", "--ref", "f.png", "--attempt", "2", "--tag", "j1-abcd"])
    check(o == {"pick": None, "only": "astro", "seeds": "3", "first_seed": "5", "character": "a b", "variant": "AST-B", "extra_words": "x y",
                "extra_ref": "r.png", "pose": "p", "holds": "h", "camera": "c", "ref": "f.png", "attempt": "2", "tag": "j1-abcd"}, "title: every flag, --x v and --x=v: %s" % o)
    check(gth.parse_args(["--only=astro,drifter", "--seeds=4"]) == {"pick": None, "only": "astro,drifter", "seeds": "4"}, "title: the pass 66 command line")
    check(gth.parse_args(["--pick", "astro=2", "drifter=1", "--variant", "AST-B", "--tag=j1-abcd"]) == {"pick": ["astro=2", "drifter=1"], "variant": "AST-B", "tag": "j1-abcd"},
          "title: --pick pairs, then --variant and --tag")
    # main(): the pick's tag is --tag, else the job the queue runs it under (ASSET_JOB_ID: the install job carries the
    # painting job's id), else none (by hand); the paint's is --tag, else (inside paint) ASSET_JOB_ID
    calls = []
    saved = (gth.pick, gth.paint, list(sys.argv), os.environ.get("ASSET_JOB_ID"))
    try:
        gth.pick = lambda *a, **kw: calls.append(("pick", a, kw))
        gth.paint = lambda *a, **kw: calls.append(("paint", a, kw))
        os.environ["ASSET_JOB_ID"] = "j20261012-112518-8854"
        sys.argv = ["gen_title_heroes.py", "--pick", "mamy=2", "--variant", "MAM-C"]
        gth.main()
        sys.argv = ["gen_title_heroes.py", "--pick", "mamy=2", "--tag", "abcd"]
        gth.main()
        del os.environ["ASSET_JOB_ID"]
        sys.argv = ["gen_title_heroes.py", "--pick", "mamy=1"]
        gth.main()
        sys.argv = ["gen_title_heroes.py", "--only", "mamy", "--seeds", "2", "--tag", "j9-ffff"]
        gth.main()
        check([c[1] for c in calls[:3]] == [(["mamy=2"], "MAM-C", "j20261012-112518-8854"), (["mamy=2"], None, "abcd"), (["mamy=1"], None, None)],
              "title main(): the pick's tag from --tag, else ASSET_JOB_ID, else none: %s" % [c[1] for c in calls[:3]])
        check(calls[3][0] == "paint" and calls[3][1] == ("mamy", 2, 11) and calls[3][2].get("tag") == "j9-ffff", "title main(): --tag reaches paint(): %s" % (calls[3][1:],))
    finally:
        gth.pick, gth.paint = saved[:2]
        sys.argv = saved[2]
        os.environ.pop("ASSET_JOB_ID", None)
        if saved[3] is not None:
            os.environ["ASSET_JOB_ID"] = saved[3]
    from PIL import Image
    check(gth.screen_sniff(Image.new("RGB", (32, 32), (6, 250, 12))) == ga.BG_GREEN and gth.screen_sniff(Image.new("RGB", (32, 32), (3, 8, 251))) == ga.BG_BLUE,
          "title: a painting on a screen says its colour")
    check(gth.screen_sniff(Image.new("RGB", (32, 32), (255, 255, 255))) is None and gth.screen_sniff(Image.new("RGBA", (32, 32), (0, 255, 0, 0))) is None,
          "title: white or transparent says nothing (the hero's own screen then)")


# ---------------------------------------------------------------- gen_icon_cands (D7)

def _icon_checks(check, ga, gic):
    changed = []
    n = 0
    for key, j in gic.JOBS.items():
        if not j:
            continue
        n += 1
        bg = ga.BG_BLUE if j.get("screen") == "blue" else ga.BG_GREEN
        if gic.icon_words(j["subject"], j.get("kind", ""), bool(j.get("ref")), j.get("style"), bg) != j["subject"] + ". " + j.get("style", ga.ICON_STYLE) + ". " + bg + ".":
            changed.append(key)
    check(n > 100 and not changed, "icon: every hand-written job's words unchanged (%d jobs): %s" % (n, changed[:5]))
    w = gic.icon_words("a goofy beast with a club.", "enemies", True)
    check(w.startswith("The reference image shows this exact creature: keep its shape, colors and proportions. a goofy beast with a club. Mobile game item icon"),
          "icon: a creature with a picture leads with the creature sentence, one full stop: %s" % w[:130])
    check(gic.icon_words("a beast", "bosses", True).startswith(gic.REF_CREATURE) and gic.icon_words("a mime", "characters", True).startswith(gic.REF_CHARACTER),
          "icon: bosses as creatures, a hero's character sentence")
    check(gic.icon_words("a sword", "weapons", True).startswith(gic.COPY + "a sword. "), "icon: an object with a picture is copied from it (COPY)")
    check(gic.icon_words("a goofy beast", "enemies", False) == "a goofy beast. " + ga.ICON_STYLE + ". " + ga.BG_GREEN + ".", "icon: no picture, no lead")
    check(gic.icon_words(gic.COPY + "a spear", "weapons", True).count("Copy this exact object") == 1 and
          gic.icon_words("two turrets like the one in the reference image", "mutations", True).startswith("two turrets"),
          "icon: a subject that already speaks of the reference image gets nothing more")
    check(gic.icon_words("x", "enemies", False, "My style", ga.BG_BLUE) == "x. My style. " + ga.BG_BLUE + ".", "icon: the job's own style and screen")
    check(gic.icon_words("  ", "enemies", True) == gic.REF_CREATURE + ga.ICON_STYLE + ". " + ga.BG_GREEN + ".", "icon: a picture with no words: the sentence and the style, no stray full stop")
    saved_jobs, saved_dl = dict(gic.JOBS), gic.DL
    tmp_dl = tempfile.mkdtemp(prefix="le_selftest_G_none_")
    try:
        gic.DL = tmp_dl
        gic.JOBS.clear()
        gic.JOBS["nothing"] = {"kind": "weapons", "id": "x", "subject": " ", "set": "_le_none"}
        gic.paint(["nothing"], 1, False)
        check(False, "icon: a job with no words and no picture is refused")
    except SystemExit as e:
        check("nothing to paint from" in str(e) and os.listdir(tmp_dl) == [], "icon: a job with no words and no picture is refused before anything is made: %s" % e)
    finally:
        gic.JOBS.clear()
        gic.JOBS.update(saved_jobs)
        gic.DL = saved_dl
        shutil.rmtree(tmp_dl, ignore_errors=True)
    b = ga.seed_for("icon46_tb")
    check(gic.candidate_seeds("tb", 3) == [b, b + 7919, b + 15838] and gic.candidate_seeds("tb", 2, 3) == [b + 2 * 104729, b + 2 * 104729 + 7919],
          "icon: the pass 46 seeds, moved for a re-run")
    tmp = tempfile.mkdtemp(prefix="le_selftest_G_icon_")
    try:
        for name in ("tb_c0.png", "tb_c0.json", "tb_c1.png", "review_tb.png", "tb_c_c0.png", "other_c0.png"):
            open(os.path.join(tmp, name), "w").write("x")
        check(gic.retire(tmp, "tb", 1) == [] and gic.retire(tmp, "tb", None) == [], "icon: a first attempt moves nothing")
        moved = gic.retire(tmp, "tb", 2)
        check(sorted(os.path.basename(p) for p in moved) == ["review_tb.png", "tb_c0.json", "tb_c0.png", "tb_c1.png"] and
              sorted(os.listdir(tmp)) == ["attempt1", "other_c0.png", "tb_c_c0.png"], "icon: a re-run moves this key's candidates into attempt1/: %s" % sorted(os.listdir(tmp)))
        open(os.path.join(tmp, "tb_c0.png"), "w").write("y")
        moved = gic.retire(tmp, "tb", 2)
        check(len(moved) == 1 and os.path.basename(os.path.dirname(moved[0])).startswith("attempt1_"), "icon: a second move never overwrites the first")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- asset_job: the inputs a job hands each tool

def _asset_job_checks(check, aj, gth):
    paint = {"argv": ["--id", "mamy", "--seeds", "3", "--prompt", "winking"], "attempt": 2, "target": {"kind": "hero", "id": "mamy", "code": "MAM-C"},
             "spec": {"character": "a mime", "ref": "tools/dl/ai_raw_anime/mamy_c_front.png", "prompt": "other words", "seeds": 3}}
    a = aj.badge_argv(paint)
    check(a == ["--id", "mamy", "--seeds", "3", "--prompt", "winking", "--character", "a mime", "--ref", "tools/dl/ai_raw_anime/mamy_c_front.png",
                "--attempt", "2", "--variant", "MAM-C"], "asset_job badge: the spec's character and ref, the attempt and the target's look added, the argv's prompt kept: %s" % a)
    a = aj.badge_argv({"argv": ["--id", "mamy", "--seeds", "3", "--variant", "MAM-B", "--character=x"], "target": {"code": "MAM-C"}, "spec": {"character": "y"}})
    check(a == ["--id", "mamy", "--seeds", "3", "--variant", "MAM-B", "--character=x"], "asset_job badge: nothing passed twice: %s" % a)
    a = aj.badge_argv({"argv": ["--id", "mamy", "--seeds", "4"], "target": {"kind": "hero", "id": "mamy", "code": ""}, "spec": {"character": "", "ref": None}})
    check(a == ["--id", "mamy", "--seeds", "4"], "asset_job badge: empty inputs and the base add nothing: %s" % a)
    inst = {"argv": ["--id", "mamy", "--pick", "2"], "target": {"kind": "hero", "id": "mamy", "code": "MAM-C"}, "attempt": 3,
            "spec": {"source_job": "j20261012-112518-8854", "choice": "2", "character": "ignored"}}
    a = aj.badge_argv(inst)
    check(a == ["--id", "mamy", "--pick", "2", "--tag", "j20261012-112518-8854", "--variant", "MAM-C"],
          "asset_job badge pick: the painting job's tag and the look, no words, no attempt: %s" % a)
    title = {"call": "paint", "argv": ["--only", "astro", "--seeds=3", "--first-seed=11"], "hid": "astro", "seeds": 3, "first": 11, "attempt": 2,
             "target": {"kind": "hero", "id": "astro", "code": "AST-X"},
             "spec": {"character": "an astronaut", "pose": "", "holds": None, "ref": "uploads/2d/a.png", "extra_words": "A ball."}}
    how = aj.title_call(title, gth.parse_args)
    check(how == ("paint", "astro", 3, 11, {"character": "an astronaut", "ref": "uploads/2d/a.png", "extra_words": "A ball.", "variant": "AST-X", "attempt": 2}),
          "asset_job title: the spec's words, the target's look, the attempt; empty words left to the tool: %s" % (how,))
    title2 = dict(title, argv=["--only", "astro", "--seeds", "2", "--first-seed", "0", "--character", "argv words", "--variant", "AST-Y"], attempt=1)
    how = aj.title_call(title2, gth.parse_args)
    check(how[1:4] == ("astro", 2, 0) and how[4]["character"] == "argv words" and how[4]["variant"] == "AST-Y" and how[4]["attempt"] == 1,
          "asset_job title: the argv wins (a first seed of 0 kept): %s" % (how,))
    how = aj.title_call({"call": "pick", "argv": ["--pick", "astro=2"], "hid": "astro", "choice": "2", "target": {"code": "AST-X"}}, gth.parse_args)
    check(how == ("pick", ["astro=2"], "AST-X", None), "asset_job title pick: the pair and the look (no tag: a hand run's cut-outs): %s" % (how,))
    how = aj.title_call({"call": "pick", "argv": [], "hid": "astro", "choice": "1", "target": {"code": ""}}, gth.parse_args)
    check(how == ("pick", ["astro=1"], "", None), "asset_job title pick: from the job.json keys: %s" % (how,))
    how = aj.title_call({"call": "pick", "argv": ["--pick", "astro=2", "--variant", "AST-X", "--tag", "j20261012-000000-abcd"], "target": {"code": "AST-X"},
                         "spec": {"source_job": "jother"}}, gth.parse_args)
    check(how == ("pick", ["astro=2"], "AST-X", "j20261012-000000-abcd"), "asset_job title pick: the argv's --tag (the painting job) wins: %s" % (how,))
    how = aj.title_call({"call": "pick", "argv": ["--pick", "astro=2"], "target": {"code": ""}, "spec": {"source_job": "j20261012-000000-beef"}}, gth.parse_args)
    check(how == ("pick", ["astro=2"], "", "j20261012-000000-beef"), "asset_job title pick: else the install's source job: %s" % (how,))
    how = aj.title_call(dict(title, argv=title["argv"] + ["--tag", "j20261012-000000-abcd"]), gth.parse_args)
    check(how[0] == "paint" and how[4].get("tag") == "j20261012-000000-abcd", "asset_job title paint: the argv's --tag reaches paint(): %s" % (how[4],))
    icon = {"icon_job": {"kind": "enemies", "id": "goblin", "subject": "a goblin", "set": "_le_j1"}, "target": {"kind": "enemy", "id": "goblin", "code": "GOB-E"},
            "spec": {"subject": "other", "ref": "tools/dl/ai_raw_anime/goblin_e_front.png", "screen": "blue", "file": "goblin_icon_e.png"}}
    s = aj.icon_spec(icon, "x/j1")
    check(s == {"kind": "enemies", "id": "goblin", "subject": "a goblin", "set": "_le_j1", "ref": "tools/dl/ai_raw_anime/goblin_e_front.png", "screen": "blue",
                "file": "goblin_icon_e.png", "variant": "GOB-E"}, "asset_job icon: the plan's entry, the spec's ref/screen/file, the look: %s" % s)
    s = aj.icon_spec({"icon_job": {"kind": "weapons", "id": "pike", "subject": "a spear"}, "id": "pike", "spec": {"screen": "green"}, "target": {"code": ""}}, "jobs/j9")
    check(s == {"kind": "weapons", "id": "pike", "subject": "a spear", "set": "_le_j9"}, "asset_job icon: the green screen and no look add nothing: %s" % s)
    check(os.path.normpath(aj._content_dir({"folder": "game/content/characters/mamy"}, 1)) == os.path.normpath(os.path.join(ROOT, "game", "content", "characters"))
          and aj._content_dir({"folder": ""}, 1) is None and aj._content_dir({}, 2) is None, "asset_job: the tools' content folder follows job.json folder")


# ---------------------------------------------------------------- the picks on temporary copies

def _pick_checks(check, ga, gbc, gth, gic):
    from PIL import Image
    tmp = tempfile.mkdtemp(prefix="le_selftest_G_pick_")
    saved = {"ga": (ga.RAW, ga.ICON_BACKUPS, ga.SIDECAR), "gbc": gbc.CHARS, "gth": (gth.OUT, gth.SLOT_DIR, gth.BACKUP, gth.CHARS), "gic": (gic.CONTENT, gic.DL),
             "env": os.environ.pop("ASSET_JOB_SIDECAR", None)}

    def job_sidecar(path):
        """What a job's process has: the env var the tools read, and gen_art's copy of it (read at its import)."""
        if path:
            os.environ["ASSET_JOB_SIDECAR"] = path
        else:
            os.environ.pop("ASSET_JOB_SIDECAR", None)
        ga.SIDECAR = path or ""

    try:
        ga.RAW = os.path.join(tmp, "raw")
        ga.ICON_BACKUPS = os.path.join(tmp, "backup_icons")
        os.makedirs(ga.RAW)
        chars = os.path.join(tmp, "characters")
        gbc.CHARS = gth.CHARS = chars
        hero = {"id": "tst", "name": "Test", "icon": "tst_icon.png", "portrait_prompt": "winking", "variant_base": "TST-A",
                "variants": {"TST-A": {"note": "base"}, "TST-B": {"note": "b", "recipe": {"stills": "b"}, "sprite": "tst_sprite_b.png"}}}
        jp = os.path.join(chars, "tst", "tst.json")
        _write(jp, hero)
        Image.new("RGBA", (256, 256), (9, 9, 9, 255)).save(os.path.join(chars, "tst", "tst_icon.png"))
        _figure(os.path.join(ga.RAW, "tst_portrait_8854_c2.png"))
        _figure(os.path.join(ga.RAW, "tst_portrait_c1.png"))
        # badge: a look's own icon, by hand
        dst = gbc.pick("tst", "2", 0.0, 0.03, "TST-B", "j20261012-112518-8854")
        d = json.load(open(jp, encoding="utf-8"))
        check(os.path.basename(dst) == "tst_icon_b.png" and Image.open(dst).size == (256, 256) and Image.open(dst).mode == "RGBA",
              "badge pick for a look: <id>_icon_<letter>.png, a 256 px round badge")
        check(d["variants"]["TST-B"].get("icon") == "tst_icon_b.png" and "badge" not in d and d["variants"]["TST-B"].get("sprite") == "tst_sprite_b.png",
              "badge pick for a look (by hand): the look's entry names it, no badge block, the strip untouched: %s" % d["variants"]["TST-B"])
        check(Image.open(os.path.join(chars, "tst", "tst_icon.png")).getpixel((5, 5)) == (9, 9, 9, 255), "badge pick for a look: the hero's own badge untouched")
        # under a job: the sidecar
        side = os.path.join(tmp, "result.json")
        job_sidecar(side)
        gbc.pick("tst", "c2", 0.0, 0.03, "TST-B", "8854")
        r = json.load(open(side, encoding="utf-8"))
        check(r.get("variant") == "TST-B" and r.get("entry") == {"icon": "tst_icon_b.png"} and r.get("top") == {} and r["info"].get("pick") == "tst_portrait_8854_c2",
              "badge pick for a look (a job): the sidecar's entry {icon}, no top: %s" % {k: r.get(k) for k in ("variant", "entry", "top")})
        gbc.pick("tst", "2", 0.5, 0.05, "", "8854")
        r = json.load(open(side, encoding="utf-8"))
        check(r.get("variant") == "" and r.get("top", {}).get("badge") == {"still": "tst_portrait_8854_c2", "head_width": 0.5, "top_pad": 0.05} and r.get("entry") == {},
              "badge pick for the hero (a job): top.badge as in pass 66: %s" % r.get("top"))
        gbc.pick("tst", "2", 0.0, 0.03, "TST-A", "8854")
        r = json.load(open(side, encoding="utf-8"))
        check(r.get("variant") == "" and r.get("entry") == {} and r.get("top", {}).get("badge") == {"still": "tst_portrait_8854_c2", "head_width": 0.0, "top_pad": 0.03}
              and not os.path.isfile(os.path.join(chars, "tst", "tst_icon_a.png")),
              "badge pick for the base look's code (the review): the hero's own (<id>_icon.png and top.badge), as the Level Editor sends it: %s"
              % {k: r.get(k) for k in ("variant", "entry", "top")})
        check(os.listdir(ga.ICON_BACKUPS) and all(f.startswith(("tst_icon_", "tst_icon_b_")) for f in os.listdir(ga.ICON_BACKUPS)), "badge pick: the replaced icons kept")
        job_sidecar("")
        gbc.pick("tst", "1", 0.0, 0.03, "")
        d = json.load(open(jp, encoding="utf-8"))
        check(d.get("badge") == {"still": "tst_portrait_c1", "head_width": 0.0, "top_pad": 0.03}, "badge pick by hand with no tag: the pass 66 untagged candidate, the badge block written")
        _figure(os.path.join(ga.RAW, "tst_portrait_x_c1.png"))
        check(gbc.pick_key("tst", "1") == "tst_portrait_x_c1", "badge pick by hand: the x-tagged candidate first")
        try:
            gbc.pick("tst", "3", 0.0, 0.03, "", "8854")
            check(False, "badge pick: a missing candidate is refused")
        except SystemExit as e:
            check("tst_portrait_8854_c3" in str(e), "badge pick: a missing candidate is refused: %s" % e)
        try:
            gbc.pick("tst", "2", 0.0, 0.03, "TST-Z", "8854")
            check(False, "badge pick: a code the hero has no look for is refused")
        except SystemExit as e:
            check("no look TST-Z" in str(e) and not os.path.isfile(os.path.join(chars, "tst", "tst_icon_z.png"))
                  and "TST-Z" not in json.load(open(jp, encoding="utf-8"))["variants"], "badge pick: a code the hero has no look for is refused, nothing written: %s" % e)
        # title: a look's cut-out with a backup
        gth.OUT = os.path.join(tmp, "title_heroes")
        gth.SLOT_DIR = os.path.join(tmp, "wanted")
        gth.BACKUP = os.path.join(tmp, "backup_title")
        os.makedirs(gth.OUT)
        Image.new("RGBA", (66, 88), (200, 0, 0, 255)).save(os.path.join(gth.OUT, "tst_b_1.png"))
        Image.new("RGBA", (66, 88), (0, 200, 0, 255)).save(os.path.join(gth.OUT, "tst_b_2.png"))
        Image.new("RGBA", (66, 88), (0, 0, 200, 255)).save(os.path.join(gth.OUT, "tst_0.png"))
        out = gth.pick(["tst=1"], "TST-B")
        d = json.load(open(jp, encoding="utf-8"))
        check([os.path.basename(x) for x in out] == ["hero_tst_b.png"] and d["variants"]["TST-B"].get("title") == "hero_tst_b.png"
              and not os.path.isdir(gth.BACKUP), "title pick for a look (by hand): hero_<id>_<letter>.png and the look's entry, nothing to back up yet")
        gth.pick(["tst=2"], "TST-B")
        bk = os.listdir(gth.BACKUP)
        check(len(bk) == 1 and bk[0].startswith("hero_tst_b_") and Image.open(os.path.join(gth.BACKUP, bk[0])).getpixel((3, 3)) == (200, 0, 0, 255)
              and Image.open(os.path.join(gth.SLOT_DIR, "hero_tst_b.png")).getpixel((3, 3)) == (0, 200, 0, 255),
              "title pick: the cut-out it replaces kept in backup/title/ first: %s" % bk)
        gth.pick(["tst=2"], "TST-B")
        check(len(os.listdir(gth.BACKUP)) == 1, "title pick: the same picture again keeps no second copy")
        job_sidecar(side)
        gth.pick(["tst=0"], None)
        r = json.load(open(side, encoding="utf-8"))
        check(os.path.isfile(os.path.join(gth.SLOT_DIR, "hero_tst.png")) and r.get("variant") == "" and r.get("entry") == {} and r.get("top") == {},
              "title pick for the hero (a job): hero_<id>.png, nothing for the server to merge")
        Image.new("RGBA", (66, 88), (90, 90, 0, 255)).save(os.path.join(gth.OUT, "tst_a_0.png"))
        Image.new("RGBA", (66, 88), (90, 0, 90, 255)).save(os.path.join(gth.OUT, "tst_9a1f_0.png"))
        gth.pick(["tst=0"], "TST-A", "j20261012-000000-9a1f")
        r = json.load(open(side, encoding="utf-8"))
        check(not os.path.isfile(os.path.join(gth.SLOT_DIR, "hero_tst_a.png")) and Image.open(os.path.join(gth.SLOT_DIR, "hero_tst.png")).getpixel((3, 3)) == (90, 0, 90, 255)
              and r.get("variant") == "" and r.get("entry") == {},
              "title pick for the base look's code (the review): the hero's own hero_<id>.png from the job's <id>_<tag>_<n>.png, nothing for the server to merge")
        # the review: a job's cut-outs are its own (<stem>_<tag>_<n>.png); its pick reads only those
        Image.new("RGBA", (66, 88), (0, 90, 90, 255)).save(os.path.join(gth.OUT, "tst_b_abcd_1.png"))
        gth.pick(["tst=1"], "TST-B", "j20261012-000000-abcd")
        r = json.load(open(side, encoding="utf-8"))
        check(Image.open(os.path.join(gth.SLOT_DIR, "hero_tst_b.png")).getpixel((3, 3)) == (0, 90, 90, 255) and r.get("entry") == {"title": "hero_tst_b.png"}
              and r["info"].get("pick") == "tst_b_abcd_1.png", "title pick under a job's tag: that job's own cut-out, not an untagged one of the same look")
        try:
            gth.pick(["tst=2"], "TST-B", "j20261012-000000-ffff")
            check(False, "title pick: another job's tag finds nothing")
        except SystemExit as e:
            check("tst_b_ffff_2" in str(e), "title pick: a tag whose job painted no such cut-out is refused (no untagged stand-in): %s" % e)
        gth.pick(["tst=1"], "TST-B")
        r = json.load(open(side, encoding="utf-8"))
        check(r.get("variant") == "TST-B" and r.get("entry") == {"title": "hero_tst_b.png"} and r["info"].get("title_backup"),
              "title pick for a look (a job): the sidecar's entry {title} and the backup: %s" % {k: r.get(k) for k in ("variant", "entry")})
        job_sidecar("")
        try:
            gth.pick(["tst=7"], "TST-B")
            check(False, "title pick: a missing candidate is refused")
        except SystemExit as e:
            check("tst_b_7" in str(e), "title pick: a missing candidate is refused: %s" % e)
        Image.new("RGBA", (66, 88), (9, 9, 9, 255)).save(os.path.join(gth.OUT, "tst_z_0.png"))
        try:
            gth.pick(["tst=0"], "TST-Z")
            check(False, "title pick: a code the hero has no look for is refused")
        except SystemExit as e:
            check("no look TST-Z" in str(e) and not os.path.isfile(os.path.join(gth.SLOT_DIR, "hero_tst_z.png")),
                  "title pick: a code the hero has no look for is refused, nothing installed: %s" % e)
        # icon: a creature look's own icon, the base, a hero refused
        gic.CONTENT = os.path.join(tmp, "content")
        gic.DL = os.path.join(tmp, "dl")
        cj = os.path.join(gic.CONTENT, "enemies", "tb", "tb.json")
        _write(cj, {"id": "tb", "variant_base": "TB-0", "variants": {"TB-0": {"note": "base"}, "TB-B": {"note": "b", "sprite": "tb_sprite_b.png", "icon": "tb_icon_b.png"}}})
        os.makedirs(os.path.join(gic.DL, "icons_le_j1"))
        _figure(os.path.join(gic.DL, "icons_le_j1", "tb_c1.png"), screen=(0, 255, 0))
        saved_jobs = dict(gic.JOBS)
        try:
            gic.JOBS["tb"] = {"kind": "enemies", "id": "tb", "subject": "a beast", "set": "_le_j1", "variant": "TB-B"}
            gic.pick(["tb=1"])
            d = json.load(open(cj, encoding="utf-8"))
            check(os.path.isfile(os.path.join(gic.CONTENT, "enemies", "tb", "tb_icon_b.png")) and not os.path.isfile(os.path.join(gic.CONTENT, "enemies", "tb", "tb_icon.png"))
                  and d["variants"]["TB-B"].get("icon") == "tb_icon_b.png", "icon pick for a look: <id>_icon_<letter>.png, the base creature's icon untouched")
            job_sidecar(side)
            gic.pick(["tb=1"])
            r = json.load(open(side, encoding="utf-8"))
            check(r.get("variant") == "TB-B" and r.get("entry") == {"icon": "tb_icon_b.png"} and os.listdir(os.path.join(gic.DL, "backup", "icons_le_j1")) == ["tb_icon_b.png"],
                  "icon pick for a look (a job): the sidecar's entry, the replaced icon kept")
            gic.JOBS["tb"] = {"kind": "enemies", "id": "tb", "subject": "a beast", "set": "_le_j1"}
            gic.pick(["tb=1"])
            r = json.load(open(side, encoding="utf-8"))
            check(os.path.isfile(os.path.join(gic.CONTENT, "enemies", "tb", "tb_icon.png")) and r.get("variant") == "" and r.get("entry") == {},
                  "icon pick with no look: <id>_icon.png as before")
            gic.JOBS["tb"] = {"kind": "enemies", "id": "tb", "subject": "a beast", "set": "_le_j1", "variant": "TB-B", "file": "tb_named.png"}
            gic.pick(["tb=1"])
            r = json.load(open(side, encoding="utf-8"))
            check(os.path.isfile(os.path.join(gic.CONTENT, "enemies", "tb", "tb_named.png")) and r.get("entry") == {"icon": "tb_named.png"}, "icon pick: a named file wins")
            gic.JOBS["tb"] = {"kind": "enemies", "id": "tb", "subject": "a beast", "set": "_le_j1", "variant": "TB-Z"}
            try:
                gic.pick(["tb=1"])
                check(False, "icon pick: a code the creature has no look for is refused")
            except SystemExit as e:
                check("no look TB-Z" in str(e) and not os.path.isfile(os.path.join(gic.CONTENT, "enemies", "tb", "tb_icon_z.png")),
                      "icon pick: a code the creature has no look for is refused, nothing written: %s" % e)
            job_sidecar("")
            _write(os.path.join(gic.CONTENT, "characters", "tst", "tst.json"), hero)
            gic.JOBS["hero"] = {"kind": "characters", "id": "tst", "subject": "a mime", "set": "_le_j1"}
            os.rename(os.path.join(gic.DL, "icons_le_j1", "tb_c1.png"), os.path.join(gic.DL, "icons_le_j1", "hero_c1.png"))
            try:
                gic.pick(["hero=1"])
                check(False, "icon pick for a hero is refused")
            except SystemExit as e:
                check("round badge" in str(e) and not os.path.isfile(os.path.join(gic.CONTENT, "characters", "tst", "tst_icon.png")),
                      "icon pick for a hero is refused (its icon is the round badge): %s" % e)
        finally:
            gic.JOBS.clear()
            gic.JOBS.update(saved_jobs)
    finally:
        ga.RAW, ga.ICON_BACKUPS, ga.SIDECAR = saved["ga"]
        gbc.CHARS = saved["gbc"]
        gth.OUT, gth.SLOT_DIR, gth.BACKUP, gth.CHARS = saved["gth"]
        gic.CONTENT, gic.DL = saved["gic"]
        os.environ.pop("ASSET_JOB_SIDECAR", None)
        if saved["env"] is not None:
            os.environ["ASSET_JOB_SIDECAR"] = saved["env"]
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- gen_ctl: a picked icon is kept (the pass 68 review)

def _gen_ctl_checks(check):
    """A creature_ctl look's icon picked from candidates (the entry's icon_picked) is not painted over by its next run."""
    saved_argv, saved_path = list(sys.argv), list(sys.path)
    sys.path.insert(0, TOOLS)
    try:
        import gen_ctl   # rewrites sys.argv at import (put back below)
    except Exception as e:
        check(True, "gen_ctl checks skipped: %s: %s" % (type(e).__name__, e))
        return
    finally:
        sys.argv = saved_argv
        sys.path[:] = saved_path
    tmp = tempfile.mkdtemp(prefix="le_selftest_G_ctl_")
    try:
        k = gen_ctl.keeps_picked_icon
        icon = os.path.join(tmp, "tb_icon_c.png")
        check(not k({"icon_picked": True}, icon) and not k({}, icon) and not k(None, icon),
              "gen_ctl: nothing to keep when the icon file is not on disk or was not picked")
        with open(icon, "wb") as f:
            f.write(b"png")
        check(k({"icon_picked": True, "icon": "tb_icon_c.png"}, icon) and not k({"icon": "tb_icon_c.png"}, icon) and not k({"icon_picked": False}, icon),
              "gen_ctl: a look whose icon was picked from candidates keeps it (icon_picked and the file on disk)")
        with open(os.path.join(TOOLS, "gen_ctl.py"), encoding="utf-8") as f:
            src = f.read()
        check("if keeps_picked_icon(entry, os.path.join(folder, iname)):" in src and '"icon": iname' in src,
              "gen_ctl.main: the pack skips the front-still crop for a picked icon, and its entry still names the file")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- asset_job --dry-run end to end (temporary copies of Astro)

def _dry_run_checks(check, ga, gbc, gth, gic, comfy):
    src = os.path.join(ROOT, "game", "content", "characters", "astro", "astro.json")
    if not os.path.isfile(src) or not all(os.path.isfile(os.path.join(RAW, "astro_%s.png" % v)) for v in ("front", "back", "side", "fd", "bd", "dead")):
        check(True, "lane G dry runs skipped: Astro or his cached stills are not on this PC")
        return
    tmp = tempfile.mkdtemp(prefix="le_selftest_G_dry_")
    watch = [os.path.join(ROOT, "game", "art", "ui", "wanted", "hero_astro.png"), os.path.join(ROOT, "tools", "dl", "review", "astro_badge_cands.png"),
             os.path.join(ROOT, "tools", "dl", "title_heroes", "astro_0.png"), src]
    before = {p: os.path.getmtime(p) for p in watch if os.path.isfile(p)}
    try:
        folder = os.path.join(tmp, "characters", "astro")
        d = json.load(open(src, encoding="utf-8"))
        d.setdefault("variants", {})
        d["variants"]["AST-X"] = {"note": "lane G: a new look with its own paintings", "recipe": {"stills": "x", "seed_offset": 5, "still_keys": {"side": "astro_side"}}}
        d["variants"]["AST-Y"] = {"note": "lane G: a new look on the hero's paintings", "recipe": {"stills": "", "seed_offset": 3}}
        _write(os.path.join(folder, "astro.json"), d)
        ref = _transparent(os.path.join(tmp, "ref pic.png"))
        extra = _transparent(os.path.join(tmp, "ball.png"), (30, 30, 200, 255))

        def run(name, job, env=None):
            jd = os.path.join(tmp, "jobs", name)
            os.makedirs(jd, exist_ok=True)
            job.setdefault("env", {}).update({"ASSET_JOB_SIDECAR": os.path.join(jd, "result.json"), "ASSET_JOB_ID": name})
            job.setdefault("id", "astro")
            job.setdefault("type", "characters")
            job.setdefault("folder", folder)
            json.dump(job, open(os.path.join(jd, "job.json"), "w", encoding="utf-8"), indent=1)
            e = {k: v for k, v in os.environ.items() if not k.startswith(("ART_", "ASSET_JOB"))}
            e.update(env or {})
            e["PYTHONIOENCODING"] = "utf-8"
            p = subprocess.run([sys.executable, "-u", os.path.join(TOOLS, "asset_job.py"), jd, "--dry-run"], capture_output=True, text=True,
                               encoding="utf-8", errors="replace", cwd=ROOT, timeout=300, env=e)
            dr_p, res_p = os.path.join(jd, "dry_run.json"), os.path.join(jd, "result.json")
            dr = json.load(open(dr_p, encoding="utf-8")).get("prompts", []) if os.path.isfile(dr_p) else []
            res = json.load(open(res_p, encoding="utf-8")) if os.path.isfile(res_p) else {}
            return p, jd, dr, res

        def tail(p):
            return (p.stdout + p.stderr).strip().splitlines()[-4:]

        # 1. badge candidates for a look: the description, the action, the picture laid on blue, per-job keys, the look's seeds
        p, jd, dr, res = run("j20261012-000000-abcd", {"tool": "gen_badge_cands", "call": "main", "kind": "hero_badge", "argv": ["--id", "astro", "--seeds", "2", "--skip-qa"],
                                                         "target": {"kind": "hero", "id": "astro", "code": "AST-Y"}, "attempt": 1,
                                                         "spec": {"character": "a test astronaut", "ref": ref, "prompt": "waving"}})
        renders = [x for x in dr if x.get("kind") == "render"]
        ups = [x for x in dr if x.get("kind") == "comfy.upload"]
        want = gbc.badge_prompt("a test astronaut", "waving", ga.BG_BLUE)
        check(p.returncode == 0, "dry run badge: exits 0: %s" % tail(p))
        check([x.get("key") for x in renders] == ["astro_portrait_abcd_c0", "astro_portrait_abcd_c1"], "dry run badge: keyed per job: %s" % [x.get("key") for x in renders])
        check(all(x.get("prompt") == want for x in renders) and want.startswith("A close-up portrait of this exact character for a mobile game avatar icon: a test astronaut, only"),
              "dry run badge: the description and the action in the words")
        check([x.get("seed") for x in renders] == gbc.badge_seeds("astro", 2, 0, 3, 1), "dry run badge: the look's seeds: %s" % [x.get("seed") for x in renders])
        name = comfy.safe_name("astro_badge_ref_ref pic.png")
        check(all(x.get("refs") == ["88fits/" + name] for x in renders) and any(u.get("name") == name and u.get("corner") == [0, 0, 255] for u in ups),
              "dry run badge: the given picture is the reference, laid on the blue screen: %s" % ups)
        check(res.get("tag") == "abcd" and res.get("variant") == "AST-Y" and res.get("ref") == os.path.normpath(ref) and res.get("character") == "a test astronaut"
              and res.get("keys") == ["astro_portrait_abcd_c0", "astro_portrait_abcd_c1"], "dry run badge: the sidecar names the tag, the look and the picture")
        check(os.path.isfile(os.path.join(jd, "astro_badge_cands.png")) and not any(f.startswith("astro_portrait_abcd") for f in os.listdir(RAW)),
              "dry run badge: the review sheet in the job folder, nothing in the paintings' cache")
        # 2. badge by default: the base, the hero's front still, the pass 66 words and seeds
        p, jd, dr, res = run("jbadge0", {"tool": "gen_badge_cands", "call": "main", "kind": "hero_badge", "argv": ["--id", "astro", "--seeds", "1", "--skip-qa"],
                                          "target": {"kind": "hero", "id": "astro", "code": ""}, "spec": {}})
        renders = [x for x in dr if x.get("kind") == "render"]
        check(p.returncode == 0 and renders and renders[0].get("prompt") == _legacy_badge(d.get("portrait_prompt", "smiling at the viewer"), ga.BG_BLUE)
              and renders[0].get("refs") == ["88fits/astro_front.png"] and renders[0].get("seed") == ga.seed_for("astro") + 40,
              "dry run badge by default: the hero's front still, the pass 66 words and seed: %s" % tail(p))
        # 3. a look whose front still is not painted yet, and no picture named: a clear refusal
        p, jd, dr, res = run("jbadgex", {"tool": "gen_badge_cands", "call": "main", "kind": "hero_badge", "argv": ["--id", "astro", "--seeds", "1", "--skip-qa"],
                                          "target": {"kind": "hero", "id": "astro", "code": "AST-X"}, "spec": {}})
        check(p.returncode != 0 and "astro_x_front" in (p.stdout + p.stderr), "dry run badge: a look with no front still yet is refused by name: %s" % tail(p))
        # 4. title cut-outs for a look: the description, the words, both pictures on blue, the look's stem and seeds
        p, jd, dr, res = run("jtitle", {"tool": "gen_title_heroes", "call": "paint", "kind": "hero_title", "argv": ["--only", "astro", "--seeds=2", "--first-seed=11"],
                                         "hid": "astro", "seeds": 2, "first": 11, "target": {"kind": "hero", "id": "astro", "code": "AST-X"},
                                         "spec": {"character": "a test astronaut", "ref": ref, "pose": "", "extra_ref": extra, "extra_words": "The second picture is a ball."}})
        runs = [x for x in dr if x.get("kind") == "comfy.run"]
        ups = {x.get("name"): x for x in dr if x.get("kind") == "comfy.upload"}
        want = gth.title_prompt("a test astronaut", gth.POSES["astro"], gth.DEFAULT_VIEW, gth.DEFAULT_HOLDS, "The second picture is a ball.", ga.STYLE, ga.BG_BLUE)
        check(p.returncode == 0 and len(runs) == 2, "dry run title: exits 0, two paintings: %s" % tail(p))
        check(all(x.get("prompts") == [want] for x in runs), "dry run title: the description after 'this exact character', the table pose, the extra words")
        check(all(x.get("refs") == ["88fits/title_ref_astro_x.png", "88fits/title_extra_ball.png"] for x in runs), "dry run title: both pictures sent: %s" % [x.get("refs") for x in runs])
        check(ups.get("title_ref_astro_x.png", {}).get("corner") == [0, 0, 255] and ups.get("title_extra_ball.png", {}).get("corner") == [0, 0, 255],
              "dry run title: the transparent pictures laid on the hero's blue screen")
        check([x.get("seed") for x in runs] == gth.title_seeds(11, 2, 5, 1), "dry run title: the look's seeds: %s" % [x.get("seed") for x in runs])
        outs = sorted(os.listdir(os.path.join(jd, "title_heroes"))) if os.path.isdir(os.path.join(jd, "title_heroes")) else []
        check(outs == ["astro_x_itle.json", "astro_x_itle_0.png", "astro_x_itle_0_raw.png", "astro_x_itle_1.png", "astro_x_itle_1_raw.png", "review_astro_x_itle.png"]
              and res.get("variant") == "AST-X" and res.get("tag") == "itle" and [os.path.basename(c) for c in res.get("choices", [])] == ["astro_x_itle_0.png", "astro_x_itle_1.png"],
              "dry run title: <id>_<letter>_<tag>_<n>.png (the job's own: ASSET_JOB_ID jtitle -> itle) in the job folder, the sidecar's choices: %s" % outs)
        # 5. title by default: the pass 66 words from the hero's front still
        p, jd, dr, res = run("jtitle0", {"tool": "gen_title_heroes", "call": "paint", "kind": "hero_title", "argv": ["--only", "astro", "--seeds=1", "--first-seed=11"],
                                          "hid": "astro", "seeds": 1, "first": 11, "target": {"kind": "hero", "id": "astro", "code": ""}, "spec": {}})
        runs = [x for x in dr if x.get("kind") == "comfy.run"]
        from PIL import Image
        bg = gth.screen_of(Image.open(os.path.join(RAW, "astro_front.png")))
        check(p.returncode == 0 and runs and runs[0].get("prompts") == [_legacy_title(gth.POSES["astro"], gth.DEFAULT_VIEW, "no weapon", "", ga.STYLE, bg)]
              and runs[0].get("refs") == ["88fits/title_ref_astro.png"] and runs[0].get("seed") == 11, "dry run title by default: the pass 66 words and seed: %s" % tail(p))
        # 6. icon candidates for a creature look, a re-run: the creature sentence, the picture, new seeds, the old ones aside
        ic = os.path.join(tmp, "jobs", "jicon", "icons_le_jicon")
        os.makedirs(ic)
        for nm in ("tb_c0.png", "tb_c0.json", "review_tb.png"):
            open(os.path.join(ic, nm), "w").write("old")
        p, jd, dr, res = run("jicon", {"tool": "gen_icon_cands", "call": "paint", "kind": "icon_cands", "argv": ["--only", "tb", "--seeds", "2"], "key": "tb", "seeds": 2,
                                        "attempt": 2, "id": "tb", "type": "enemies", "folder": "",
                                        "icon_job": {"kind": "enemies", "id": "tb", "subject": "a goofy beast", "set": "_le_jicon"},
                                        "target": {"kind": "enemy", "id": "tb", "code": "TB-B"}, "spec": {"ref": ref}})
        runs = [x for x in dr if x.get("kind") == "comfy.run"]
        check(p.returncode == 0 and len(runs) == 2 and all(x.get("prompts") == [gic.icon_words("a goofy beast", "enemies", True)] for x in runs),
              "dry run icon: the creature sentence and the subject: %s" % tail(p))
        check(all(x.get("refs") == ["88fits/ref_pic.png"] for x in runs) and [x.get("seed") for x in runs] == gic.candidate_seeds("tb", 2, 2),
              "dry run icon: the picture sent, a re-run's new seeds: %s" % [(x.get("refs"), x.get("seed")) for x in runs])
        check(sorted(os.listdir(os.path.join(ic, "attempt1"))) == ["review_tb.png", "tb_c0.json", "tb_c0.png"] and open(os.path.join(ic, "tb_c0.png"), "rb").read(3) != b"old",
              "dry run icon: the earlier attempt's candidates moved aside and painted again")
        # 7. picks are never run by a dry run
        p, jd, dr, res = run("jpick", {"tool": "gen_title_heroes", "call": "pick", "kind": "install", "argv": ["--pick", "astro=0"], "hid": "astro", "choice": "0",
                                        "target": {"kind": "hero", "id": "astro", "code": ""}, "spec": {"source_job": "jtitle0", "choice": "0"}})
        check(p.returncode == 0 and [x.get("kind") for x in dr if x.get("kind") != "comfy.upload"] == ["pick"], "dry run: a title pick is recorded, not run: %s" % tail(p))
        pk = [x for x in dr if x.get("kind") == "pick"]
        check(pk and pk[0].get("tag") == "jtitle0" and pk[0].get("would_install") == ["astro=0"],
              "dry run: a title pick names the painting job's tag (the install's source job): %s" % (pk[:1] or tail(p)))
        p, jd, dr, res = run("jpick2", {"tool": "gen_badge_cands", "call": "main", "kind": "install", "argv": ["--id", "astro", "--pick", "1"],
                                         "target": {"kind": "hero", "id": "astro", "code": "AST-Y"}, "spec": {"source_job": "j20261012-000000-abcd", "choice": "1"}})
        pk = [x for x in dr if x.get("kind") == "pick"]
        check(p.returncode == 0 and pk and pk[0].get("would_install") == ["--id", "astro", "--pick", "1", "--tag", "j20261012-000000-abcd", "--variant", "AST-Y"],
              "dry run: a badge pick is recorded with the painting job's tag and the look: %s" % (pk[:1] or tail(p)))
        # 8. a hero look through gen_art: its own still keys (still_keys first), its seeds, the real painter in the marker
        p, jd, dr, res = run("jlook", {"tool": "gen_art", "call": "process", "kind": "look", "argv": ["--no-import", "--only", "astro", "--variant=AST-X", "--skip-qa"]},
                             env={"ART_MODEL": "dev", "ART_STEPS": "32"})
        keys = [(x.get("key"), x.get("seed")) for x in dr if x.get("kind") == "render"]
        s0 = ga.seed_for("astro") + 5 * 104729
        a = int(d.get("anim_seed", 0))   # the hero branch adds anim_seed before the hurt and dead stills, as it always did
        want = [("astro_x_front", s0), ("astro_x_back", s0 + 1), ("astro_side", s0 + 6), ("astro_x_fd", s0 + 7), ("astro_x_bd", s0 + 8), ("astro_x_cheer", s0 + 10),
                ("astro_x_hurt_back", s0 + a + 30), ("astro_x_hurt_front", s0 + a + 31), ("astro_x_hurt_side", s0 + a + 32), ("astro_x_hurt_bd", s0 + a + 33),
                ("astro_x_hurt_fd", s0 + a + 34), ("astro_x_dead", s0 + a + 12)]
        check(p.returncode == 0 and keys == want, "dry run hero look: <id>_<slug>_<view> (still_keys first) at the look's seeds: %s %s" % (keys[:3], tail(p)))
        info = res.get("info", {})
        check(res.get("variant") == "AST-X" and info.get("model") == comfy.FLUX2_UNET and info.get("painter", {}).get("model") == "dev"
              and info.get("painter", {}).get("steps") == 32, "dry run hero look: the marker names Flux.2 dev at 32 steps: %s" % info.get("painter"))
        check(info.get("renders", {}).get("side", {}).get("cached") is True, "dry run hero look: a still from the cache says so (astro_side)")
        check(sorted(os.listdir(folder)) == ["astro.json", "astro_sprite_x.png", "astro_x_ai.json"], "dry run hero look: the strip and marker in the copy only")
        after = {p_: os.path.getmtime(p_) for p_ in watch if os.path.isfile(p_)}
        check(after == before, "the dry runs left the game's cut-out, the review sheet, the title candidates and astro.json alone")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
