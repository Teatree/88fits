"""Pass 71, lane PLE: the Puppet method in the Level Editor, checked. selftest.py discovers this file (`extra_checks`) and
hands it its `check` counter, `run_node` and the `server` module. Nothing here writes under game/, tools/dl/puppet/<hero>/,
tools/dl/drivers/ or the real queue: puppet.py runs dry on temp copies, jobs.py on a temp queue, temp locks, a temp
content tree and temp puppet and driver folders; nothing reaches ComfyUI or Blender.

Groups:
  puppet   tools/puppet.py: the arguments and their defaults, the 3D reference per view (paint, still:<key>, a picture,
           none), the words (templates, own words, the screen, {who} on the front only), the clip slug and the versioned
           guides (another framing, clip or a newer GLB -> a new folder; a matching one kept), the lanes (stage_lane),
           --pick "side=1,back=0", --reset-from and --reroll (moved to old/<stamp>/), the dry run's mirror (small files
           copied, big ones empty stand-ins, nothing linked) and a whole dry chain on a temp copy (the markers, the picks
           c0, the record); puppet.js's copy of the templates; puppet_blender's name / idle / frame=soles;
  gen_art  run_fit (a silhouette.json or {view: ratio}, clamped, the median fit) and fringe_remap (a foreign hue moved to
           the painting's own, value kept, off unless named);
  jobs     hero_puppet in jobs.py: puppet_spec, puppet_problem, the lane guesses, the argv (refs, words, picks, the one-
           shot reset and re-roll, a fresh puppet once), enqueue (the plan: tool puppet through asset_job, the comfy lock
           or none, no LOCK_HELD_COMFY on the local lane, the walks' argv; the stages; the source look's recipe copied
           without run_scale or drivers; repaint), the markers and the parser, the end of a phase (a pick waits with its
           choices, a lane hop re-queues at the front, DONE writes the guides into the look's recipe and queues the
           walks: gen_art as hero_pose5), pick, requeue from a stage, the stage re-roll, the outputs (the GLB);
  server   /dl/puppet and .glb, /vendor/model-viewer, /api/puppet/<hero> on a temp tree and on Jezyk's real puppet;
  page     methods.json's card, the hooks in jobs.js / heroes.js / index.html, puppet.js under node (parses, its pure
           helpers);
  docs     instructions.js "Pass 71: the Puppet method", docs/level_editor.md "Pass 71", docs/assets_schema.md rows.
"""
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _jdump(path, d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, indent=2)


def _touch(path, data=b"x"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def _quiet(fn, *a, **k):
    """Run fn with stdout captured (puppet.py logs a lot); returns (result, text)."""
    keep, buf = sys.stdout, io.StringIO()
    sys.stdout = buf
    try:
        return fn(*a, **k), buf.getvalue()
    finally:
        sys.stdout = keep


def _puppet():
    import puppet
    return puppet


# ---------------------------------------------------------------- 1. tools/puppet.py

def puppet_checks(check):
    pp = _puppet()
    a = pp.parse_args(["buck"])
    check(a.clip == "running.fbx" and a.frame == "soles" and a.painter == "klein" and a.seeds == 4 and a.tries == 2 and a.lane == "" and not a.dry_run,
          "PLE puppet: defaults: running.fbx, soles, Klein, 4 fronts, 2 tries, no lane, no dry run")
    a = pp.parse_args(["may", "--ref", "front=paint", "side=still:may_g_side", "back=none", "--words-front", "x y", "--painter", "dev", "--frame", "ankles"])
    check(pp.ref_of(a, "front") == "paint" and pp.ref_of(a, "side") == "still:may_g_side" and pp.ref_of(a, "back") == "none" and pp.ref_of(pp.parse_args(["may"]), "side") == "paint",
          "PLE puppet: --ref per view; a view not named paints")
    check(pp.ref_path("still:may_g_side").replace("\\", "/").endswith("tools/dl/ai_raw_anime/may_g_side.png")
          and pp.ref_path("tools/dl/uploads/2d/x.png").replace("\\", "/").endswith("tools/dl/uploads/2d/x.png"), "PLE puppet: a still key and a repo path resolve")
    check(pp.name_of("may") == "May" and pp.name_of("buck") == "Buck" and pp.name_of("dust_mummy") == "DustMummy", "PLE puppet: the mesh's object name from the hero id")
    check(pp.clip_slug(pp.parse_args(["x"])) == "run" and pp.clip_slug(pp.parse_args(["x", "--clip", "catwalk_walking.fbx"])) == "catwalk_walking",
          "PLE puppet: the guides' clip part: running.fbx = run (the trial's may_puppet_run), else the stem")
    # the words: the templates for any hero, the front naming the character, the screen colour
    ctx = types.SimpleNamespace(recipe={}, d={"appearance": "a lean young man with blue skin", "art_prompt": "x; standing"}, screen="green")
    ctx.who = lambda: pp.Ctx.who(ctx)
    a0 = pp.parse_args(["buck"])
    wf, ws, wb = (pp.apose_words(ctx, v, a0) for v in ("front", "side", "back"))
    check("clear green background between each arm" in wf and "The character: a lean young man with blue skin." in wf and "woman" not in wf + ws + wb
          and "beret" not in wf + ws + wb and "The character" not in ws + wb and "45 degrees" in wb, "PLE puppet: the words are any hero's: the screen, the character on the front only, no May")
    a1 = pp.parse_args(["buck", "--words-side", "my own side words", "--screen", "blue"])
    check(pp.apose_words(ctx, "side", a1) == "my own side words " and pp.screen_of(ctx, a1) == "blue" and pp.screen_of(ctx, a0) == "green",
          "PLE puppet: a view's own words replace the template; --screen wins over the look's")
    ctx2 = types.SimpleNamespace(recipe={}, d={"art_prompt": "a mime woman, a beret; standing straight, arms at her sides"}, screen="blue")
    check(pp.Ctx.who(ctx2) == "a mime woman, a beret", "PLE puppet: without an appearance the art_prompt's pose clause is cut")
    # puppet.js's copy of the templates
    js = _read(os.path.join(HERE, "puppet.js"))
    for view, name in (("front", "APOSE_FRONT"), ("side", "APOSE_SIDE"), ("back", "APOSE_BACK")):
        m = re.search(r"\n    %s: '((?:[^'\\]|\\.)*)'" % view, js)
        jsv = m.group(1).replace("\\'", "'") if m else None
        check(jsv == getattr(pp, name), "PLE page: puppet.js's %s words are puppet.py's %s" % (view, name))
    for scr in ("blue", "green"):
        m = re.search(r"\n    %s: '((?:[^'\\]|\\.)*)'" % scr, js)
        check(m and m.group(1) == pp.SCREENS[scr], "PLE page: puppet.js's %s screen words are puppet.py's" % scr)
    # a temp hero: lanes, picks, reset, re-roll, versioned guides, the dry mirror
    tmp = tempfile.mkdtemp(prefix="le_ple_puppet_")
    saved = (pp.DRIVERS, pp.DRIVERS_REAL, pp.PUPPETS)
    try:
        pp.DRIVERS = pp.DRIVERS_REAL = os.path.join(tmp, "drivers")
        pp.PUPPETS = os.path.join(tmp, "puppet")
        d = os.path.join(pp.PUPPETS, "hx")
        os.makedirs(d)
        cx = types.SimpleNamespace(hero="hx", out=d, state={}, state_p=os.path.join(d, "stages.json"), d={}, recipe={}, screen="blue", look="", slug="")
        cx.p = lambda *parts: os.path.join(d, *parts)
        cx.save = lambda: pp.Ctx.save(cx)
        cx.mark = lambda st, **kw: pp.Ctx.mark(cx, st, **kw)
        A = pp.parse_args(["hx"])
        A.force_stage = None
        check(pp.stage_lane(cx, "apose", A) == "comfy" and pp.stage_lane(cx, "shape", A) == "comfy" and pp.stage_lane(cx, "rig", A) == "local",
              "PLE puppet lanes: nothing on disk: the paintings and the shape on comfy, the rig on local")
        A2 = pp.parse_args(["hx", "--ref", "front=still:hx_front", "side=none", "back=none"])
        A2.force_stage = None
        check(pp.stage_lane(cx, "apose", A2) == "local", "PLE puppet lanes: pictures given for every view: no painting, the local lane")
        for k in range(4):
            _touch(os.path.join(d, "apose", "front_c%d.png" % k))
        check(pp.stage_lane(cx, "apose", A) == "local", "PLE puppet lanes: the candidates painted, a pick to apply: local")
        _quiet(pp.do_pick, cx, ["front=c2"])
        check(os.path.exists(os.path.join(d, "apose_front.png")) and cx.state["apose"]["picks"]["front"] == 2, "PLE puppet: --pick front=c2 copies the candidate")
        for v in ("side", "back"):
            for k in range(3):
                _touch(os.path.join(d, "apose", "%s_c%d.png" % (v, k)))
        _quiet(pp.do_pick, cx, ["side=1,back=0"])
        check(cx.state["apose"]["picks"] == {"front": 2, "side": 1, "back": 0} and pp.stage_lane(cx, "apose", A) is None,
              "PLE puppet: --pick side=1,back=0 (the editor's one string) picks both; the stage is done")
        for k in range(2):
            _touch(os.path.join(d, "shape", "try_%d.glb" % k))
        check(pp.stage_lane(cx, "shape", A) == "local", "PLE puppet lanes: the tries made: the pick and the clean are local (Blender)")
        _touch(os.path.join(d, "shape_raw.glb"))
        _touch(os.path.join(d, "shape.glb"))
        _touch(os.path.join(d, "hx_puppet.blend"))
        _touch(os.path.join(d, "hx_puppet.glb"), b"g" * 10)
        check(pp.stage_lane(cx, "shape", A) is None and pp.stage_lane(cx, "rig", A) is None, "PLE puppet lanes: a stage on disk has nothing left")
        # the versioned guides
        name, ready = pp.guides_name(cx, A)
        check(name == "hx_puppet_run" and not ready, "PLE puppet guides: the first folder is <hero>_puppet_run")
        g = os.path.join(pp.DRIVERS, "hx_puppet_run")
        _jdump(os.path.join(g, "meta.json"), {"kind": "pose", "frame": "soles", "clip": "tools/dl/mixamo/running.fbx"})
        _touch(os.path.join(g, "front", "driver_24.png"))
        _touch(os.path.join(g, "silhouette.json"), b"{}")
        _touch(os.path.join(pp.DRIVERS, "hx_puppet_run_depth", "back", "ctl_48.png"))
        glb = os.path.join(d, "hx_puppet.glb")
        os.utime(glb, (time.time() - 100, time.time() - 100))
        check(pp.guides_name(cx, A) == ("hx_puppet_run", True), "PLE puppet guides: the same framing, clip and an older GLB: kept")
        A3 = pp.parse_args(["hx", "--frame", "ankles"])
        A3.force_stage = None
        check(pp.guides_name(cx, A3) == ("hx_puppet_run_2", False), "PLE puppet guides: another framing: a new folder _2 (looks keep theirs)")
        os.utime(glb, (time.time() + 100, time.time() + 100))
        check(pp.guides_name(cx, A) == ("hx_puppet_run_2", False), "PLE puppet guides: a GLB newer than the guides: a new folder")
        A4 = pp.parse_args(["hx", "--clip", "walking.fbx"])
        A4.force_stage = None
        check(pp.guides_name(cx, A4) == ("hx_puppet_walking", False), "PLE puppet guides: another clip: its own name")
        os.utime(glb, (time.time() - 100, time.time() - 100))
        A5 = pp.parse_args(["hx", "--face", "head"])
        A5.force_stage = None
        check(pp.guides_name(cx, A) == ("hx_puppet_run", True) and pp.guides_name(cx, A5) == ("hx_puppet_run_2", False) and A.face == "nose",
              "PLE puppet guides: the face angle is part of the guides (a meta without one is the nose's, the trial's v3); another one: a new folder")
        # re-roll and reset move things aside, never delete
        _quiet(pp.do_reroll, cx, "views", "20261013-000001")
        check(not os.path.exists(os.path.join(d, "apose", "side_c0.png")) and os.path.exists(os.path.join(d, "old", "20261013-000001", "apose", "side_c0.png"))
              and os.path.exists(os.path.join(d, "apose", "front_c0.png")), "PLE puppet: --reroll views moves the side and back candidates to old/<stamp>/ (the fronts stay)")
        cx.state["rig"] = {"seconds": 1}
        _quiet(pp.do_reset, cx, "rig", "20261013-000002")
        old = os.path.join(d, "old", "20261013-000002")
        check(not os.path.exists(os.path.join(d, "hx_puppet.blend")) and not os.path.exists(glb) and os.path.exists(os.path.join(old, "hx_puppet.blend"))
              and os.path.exists(os.path.join(old, "hx_puppet.glb")) and os.path.exists(os.path.join(d, "shape.glb")) and "rig" not in cx.state
              and os.path.isdir(g), "PLE puppet: --reset-from rig moves the rig and the GLB aside, keeps the shape and the guides' folders")
        # the dry mirror: small files copied, big ones empty stand-ins with the real time, nothing linked
        real = os.path.join(tmp, "realhero")
        _touch(os.path.join(real, "stages.json"), b'{"apose": {}}')
        _touch(os.path.join(real, "big.glb"), b"0" * (3 * 1024 * 1024 + 10))
        _touch(os.path.join(real, "old", "x.png"))
        os.utime(os.path.join(real, "big.glb"), (1700000000, 1700000000))
        n = pp._dry_mirror(real, os.path.join(tmp, "mirror"))
        mb = os.path.join(tmp, "mirror", "big.glb")
        check(n == 2 and os.path.getsize(os.path.join(tmp, "mirror", "stages.json")) > 0 and os.path.getsize(mb) == 0
              and int(os.path.getmtime(mb)) == 1700000000 and not os.path.exists(os.path.join(tmp, "mirror", "old")),
              "PLE puppet dry: the mirror copies small files, stands in for big ones (their time kept), leaves old/ out")
        with open(mb, "wb") as f:
            f.write(b"dry")
        check(os.path.getsize(os.path.join(real, "big.glb")) > 3 * 1024 * 1024, "PLE puppet dry: a write to the mirror never reaches the real file (no links)")
    finally:
        pp.DRIVERS, pp.DRIVERS_REAL, pp.PUPPETS = saved
        shutil.rmtree(tmp, ignore_errors=True)
    dry_chain_checks(check, pp)
    blender_src_checks(check)


def dry_chain_checks(check, pp):
    """A whole dry chain on a temp copy: Jezyk (buck) when his look's stills are on disk, every stage recorded, the picks
    c0, the markers; tools/dl/puppet/buck and tools/dl/drivers untouched."""
    still = os.path.join(pp.RAW, "buck_d2_front.png")
    if not os.path.isfile(still):
        check(True, "PLE puppet dry: Jezyk's stills are not on this PC: the dry chain is skipped")
        return
    tmp = tempfile.mkdtemp(prefix="le_ple_dry_")
    saved = (pp.DRIVERS, pp.DRY.copy())
    real = os.path.join(pp.PUPPETS, "buck")
    before = {f: os.path.getmtime(os.path.join(real, f)) for f in ("stages.json", "buck_puppet.glb") if os.path.isfile(os.path.join(real, f))}
    drv_before = sorted(os.listdir(pp.DRIVERS_REAL)) if os.path.isdir(pp.DRIVERS_REAL) else []
    try:
        # a fresh puppet (the old one moved aside inside the dry copy), the side from a look's still
        rc, out = _quiet(pp.main, ["buck", "--until", "guides", "--lane", "comfy", "--dry-run", "--out-root", tmp, "--reset-from", "apose",
                                   "--ref", "front=paint", "side=still:buck_d2_side", "back=paint", "--painter", "dev", "--clip", "walking.fbx"])
        rec = json.load(open(os.path.join(tmp, "dry_run.json"), encoding="utf-8"))["prompts"]
        kinds = [n["kind"] for n in rec]
        paints = [n for n in rec if n["kind"] == "paint"]
        check(rc == 0 and "puppet: DONE guides" in out and "puppet: PICK" not in out and "puppet: NEXT" not in out,
              "PLE puppet dry: the whole chain runs (no lane stop, no pick stop): %s" % out[-300:])
        check(kinds.count("pick") == 3 and kinds.count("comfy.run_3d") == 2 and kinds.count("restart_server") == 2 and "mirror" in kinds
              and {n.get("mode") for n in rec if n["kind"] == "blender"} >= {"clean", "rig", "anim", "guides", "silhouette"},
              "PLE puppet dry: three picks, two Hunyuan3D graphs, two restarts, every Blender mode recorded: %s" % sorted(set(kinds)))
        check(paints and all(p["painter"] == "dev" for p in paints) and not any(p["view"] == "side" for p in paints) and any(p["view"] == "back" for p in paints)
              and all("bright green (#00FF00)" in p["prompt"] for p in paints),
              "PLE puppet dry: the dev painter, no side painting (a still was given), Jezyk on the green screen")
        g3 = [n for n in rec if n["kind"] == "comfy.run_3d"][0]
        check(g3.get("checkpoint") == "hunyuan3d-dit-v2-mv.safetensors" and len(g3.get("views", [])) == 4 and g3.get("octree") == 380,
              "PLE puppet dry: Hunyuan3D-2mv on four views (front, back, right, left), octree 380")
        gl = re.search(r"puppet: GUIDES (\S+) (\S+) (\S+)", out)
        check(gl and gl.group(1).startswith("buck_puppet_walking") and os.path.isdir(os.path.join(tmp, "drivers", gl.group(1))),
              "PLE puppet dry: the guides' stand-ins under the dry root, named for the clip")
        after = {f: os.path.getmtime(os.path.join(real, f)) for f in before}
        check(after == before and (sorted(os.listdir(pp.DRIVERS_REAL)) if os.path.isdir(pp.DRIVERS_REAL) else []) == drv_before,
              "PLE puppet dry: Jezyk's real puppet and tools/dl/drivers untouched")
    finally:
        pp.DRIVERS = saved[0]
        pp.DRY.clear()
        pp.DRY.update(saved[1])
        shutil.rmtree(tmp, ignore_errors=True)


def blender_src_checks(check):
    src = _read(os.path.join(TOOLS, "puppet_blender.py"))
    check("face_mode = \"head\" if str(a.get(\"face\") or \"nose\") == \"head\" else \"nose\"" in src and '"face": face_mode' in src,
          "PLE blender: face=nose|head places the ears (from the nose by default) and meta.json says which")
    check("def set_names()" in src and 'MESH_NAME, RIG_NAME = nm, nm + "_Rig"' in src and "set_names()" in src.split("def main()")[1],
          "PLE blender: name= names the mesh and the armature (May's names the default)")
    check('retarget_run(rig, mesh, a["idle"], name="idle")' in src and 'keep=("run", "idle")' in src, "PLE blender: idle= retargets a Mixamo idle like the run")
    check('frame_mode == "soles"' in src and '"frame": frame_mode' in src and '"clip": a.get("clip")' in src,
          "PLE blender: frame=soles puts the ground at the lowest sole; meta.json says the framing and the clip")


# ---------------------------------------------------------------- 2. gen_art: run_fit, fringe_remap

def gen_art_checks(check):
    saved_argv = list(sys.argv)
    sys.argv = ["gen_art.py"]
    try:
        import gen_art as ga
    finally:
        sys.argv = saved_argv
    from PIL import Image, ImageDraw
    tmp = tempfile.mkdtemp(prefix="le_ple_ga_")
    try:
        sil = os.path.join(tmp, "silhouette.json")
        _jdump(sil, {"side": {"ratio_median": 0.9375}, "back": {"ratio_median": 1.9}, "front": {}})
        ga._RUN_FIT_CACHE.clear()
        d = {"run_fit": sil}
        check(ga.run_fit_of(d, "side") == 0.9375 and ga.run_fit_of(d, "back") == 1.4 and ga.run_fit_of(d, "front") is None and ga.run_fit_of({}, "side") is None,
              "PLE gen_art: run_fit reads a silhouette.json per view, clamped 0.6..1.4; a view without a ratio keeps the old fit")
        check(ga.run_fit_of({"run_fit": tmp}, "side") == 0.9375 and ga.run_fit_of({"run_fit": {"fd": 0.95}}, "fd") == 0.95 and ga.run_fit_of({"run_fit": os.path.join(tmp, "nope.json")}, "fd") is None,
              "PLE gen_art: run_fit may name a guide folder or {view: ratio}; a missing file falls back")

        def fig(h):
            im = Image.new("RGBA", (64, 128), (0, 0, 0, 0))
            ImageDraw.Draw(im).rectangle((20, 128 - h, 40, 127), fill=(200, 0, 0, 255))
            return im
        frames = [fig(h) for h in (90, 100, 110, 120, 100)]
        cell = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        ImageDraw.Draw(cell).rectangle((100, 56, 150, 255), fill=(255, 0, 0, 255))
        sh = ga.figure_height_cell(cell)
        check(abs(ga.clip_scale(frames, cell) - sh * 0.99 / 120) < 1e-9 and abs(ga.clip_scale(frames, cell, 1.0, 0.95) - sh * 0.95 / 100) < 1e-9
              and abs(ga.clip_scale(frames, cell, 0.9, 0.95) - sh * 0.95 / 100 * 0.9) < 1e-9,
              "PLE gen_art: the tallest frame at x0.99 by default; with run_fit the median frame at the puppet's ratio; run_scale multiplies on top")
        check(abs(ga.clip_scale(frames, cell, 1.0, 0.95, 3) - (sh * 0.95 - 6) / 100) < 1e-9 and abs(ga.clip_scale(frames, cell, 1.0, None, 3) - sh * 0.99 / 120) < 1e-9,
              "PLE gen_art: run_fit counts the outline the frames get after the scale (MAY-R's first walks stood 2 % tall); the old fit unchanged")
        hint = "a mime woman, her black bob and beret; where her face shows it is a clean anime face: two dark eyes, a small smile"
        rp = {"puppet": {"face": "nose"}}
        check(ga.hint_for_view(hint, "back", rp) == "a mime woman, her black bob and beret" and ga.hint_for_view(hint, "bd", rp) == "a mime woman, her black bob and beret"
              and ga.hint_for_view(hint, "front", rp) == hint and ga.hint_for_view(hint, "back", {}) == hint and ga.hint_for_view(hint, "back", {"puppet": {"face": "head"}}) == hint,
              "PLE gen_art: with the face angle kept, a puppet look's back and bd views walk on words without the face; other looks and views keep them")
        src = _read(os.path.join(TOOLS, "gen_art.py"))
        check("vhint = hint_for_view(hint, view, d)" in src and src.count(", vhint, negative_extra=anim_neg") == 2, "PLE gen_art: both driven walks take the view's hint")
        check(src.count("fit_ratio=fr") == 2 and "fx = d.get(\"fringe_remap\")" in src, "PLE gen_art: both driven walks take run_fit; fringe_remap only when named")
        # fringe_remap: a still in red and blue, a frame with a green fringe -> the green goes to a hue the still has
        still = Image.new("RGB", (200, 200), (0, 255, 0))
        dr = ImageDraw.Draw(still)
        dr.rectangle((60, 30, 140, 110), fill=(220, 30, 30))
        dr.rectangle((60, 110, 140, 180), fill=(30, 40, 220))
        fr = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
        d2 = ImageDraw.Draw(fr)
        d2.rectangle((20, 10, 80, 50), fill=(220, 30, 30, 255))
        d2.rectangle((20, 50, 80, 90), fill=(30, 40, 220, 255))
        d2.rectangle((76, 10, 80, 90), fill=(40, 220, 40, 255))   # the fringe
        out = ga.fringe_remap([fr], still, True)[0]
        px = out.getpixel((78, 30))
        keep = out.getpixel((40, 30))
        check(not (px[1] > px[0] and px[1] > px[2]) and keep == (220, 30, 30, 255) and max(px[:3]) >= 200,
              "PLE gen_art: fringe_remap turns a hue the painting lacks into its own (value kept), the painting's own colours stay: %s" % (px,))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- 3. jobs.py: hero_puppet

def _hero_tree(content):
    hf = os.path.join(content, "characters", "hx")
    _jdump(os.path.join(hf, "hx.json"), {
        "id": "hx", "name": "Hx", "frame_px": 256, "variant_base": "HX-A", "variant": "HX-F", "art_prompt": "a hero; standing",
        "variants": {"HX-A": {"note": "base"},
                     "HX-F": {"sprite": "hx_sprite_f.png", "anims": {"idle": 4, "run": 24}, "strip_cols": 62,
                              "recipe": {"stills": "d2", "seed_offset": 2437, "anim_seed": 1, "screen": "green", "run_scale": {"side": 0.9},
                                         "pose_drivers": {"front": "run_dash_f"}, "method": "hero_pose5", "painter": {"model": "klein"}, "anim_hint": "a blue man"}}}})
    for f in ("hx_sprite.png", "hx_sprite_f.png", "hx_icon.png"):
        _touch(os.path.join(hf, f))


class _Live:
    def __init__(self, marker):
        self.marker = marker


def jobs_checks(check, server):
    import locks
    import jobs
    import selftest_S as S
    tmp = tempfile.mkdtemp(prefix="le_ple_jobs_")
    names = ("JOBS_DIR", "QUEUE_FILE", "RAW", "ANIM", "REVIEW", "LAUNCH_FILE", "DL", "TITLE_OUT", "WANTED", "DRIVERS", "PUPPET_DIR")
    saved = {k: getattr(jobs, k) for k in names}
    saved_locks = {k: getattr(locks, k) for k in ("LOCK_DIR", "SAVE_DIR", "KEEP_DIR", "RESTORE_PENDING")}
    saved_state = (jobs._state, jobs._hooks, jobs._root, dict(jobs._lane_current))
    try:
        jobs.JOBS_DIR = os.path.join(tmp, "jobs")
        jobs.QUEUE_FILE = os.path.join(jobs.JOBS_DIR, "queue.json")
        jobs.DL = os.path.join(tmp, "dl")
        jobs.RAW = os.path.join(tmp, "dl", "ai_raw_anime")
        jobs.ANIM = os.path.join(tmp, "dl", "ai_anim")
        jobs.REVIEW = os.path.join(tmp, "dl", "review")
        jobs.TITLE_OUT = os.path.join(tmp, "dl", "title_heroes")
        jobs.DRIVERS = os.path.join(tmp, "dl", "drivers")
        jobs.PUPPET_DIR = os.path.join(tmp, "dl", "puppet")
        jobs.WANTED = os.path.join(tmp, "wanted")
        jobs.LAUNCH_FILE = os.path.join(tmp, "user", "debug_launch.json")
        locks.LOCK_DIR = os.path.join(tmp, "locks")
        locks.SAVE_DIR = os.path.join(tmp, "save")
        locks.KEEP_DIR = os.path.join(tmp, "locks", "save_keep")
        locks.RESTORE_PENDING = os.path.join(locks.KEEP_DIR, "restore_pending.json")
        for p in (jobs.RAW, jobs.ANIM, jobs.REVIEW, locks.SAVE_DIR, os.path.dirname(jobs.LAUNCH_FILE), jobs.JOBS_DIR, jobs.DRIVERS, jobs.PUPPET_DIR):
            os.makedirs(p, exist_ok=True)
        for v in ("front", "side", "back", "fd", "bd"):
            _touch(os.path.join(jobs.RAW, "hx_d2_%s.png" % v))
        content = os.path.join(tmp, "content")
        _hero_tree(content)
        hp = os.path.join(content, "characters", "hx", "hx.json")
        with S.Pointed(server, content, S.FakeJobs()):
            jobs._state = {"rev": 0, "jobs": []}
            jobs._workers.clear()
            jobs.init(server.HOOKS, ROOT, claim=False)
            T = {"kind": "hero", "id": "hx", "code": "HX-P"}
            sp = jobs.puppet_spec({"puppet": {"refs": {"front": "none", "back": "still:hx_d2_back"}, "painter": "dev", "reuse": "weird", "frame": "x", "depth_views": ["side", "up"]}}, T)
            check(sp["refs"] == {"front": "paint", "side": "paint", "back": "still:hx_d2_back"} and sp["painter"] == "dev" and sp["reuse"] == "auto"
                  and sp["frame"] == "soles" and sp["depth_views"] == ["side"] and sp["run_fit"] and sp["fringe"] and sp["face"] == "nose" and sp["clip"] == "running.fbx",
                  "PLE jobs: puppet_spec's defaults and sanitising (the front always made, an unknown reuse / frame / view dropped)")
            check(jobs.puppet_spec({}, T)["depth_views"] == ["fd", "side", "bd", "back"], "PLE jobs: the trial's best mix by default: depth for fd, side, bd, back")
            check("not on disk" in jobs.puppet_problem({"puppet": {"refs": {"side": "still:nope"}}}, T) and "for a hero" in jobs.puppet_problem({}, dict(T, kind="enemy"))
                  and "FBX" in jobs.puppet_problem({"puppet": {"reuse": "fbx"}}, T) and ".blend" in jobs.puppet_problem({"puppet": {"reuse": "blend"}}, T)
                  and jobs.puppet_problem({"puppet": {"refs": {"back": "still:hx_d2_back"}}}, T) == "",
                  "PLE jobs: puppet_problem: a picture not on disk, not a hero, no FBX, no .blend; a good spec passes")
            try:
                jobs.enqueue("look", T, {"method": "hero_puppet", "puppet": {"refs": {"side": "still:nope"}}})
                check(False, "PLE jobs: enqueue refuses a puppet job that cannot run")
            except ValueError as e:
                check("not on disk" in str(e), "PLE jobs: enqueue refuses a puppet job that cannot run: %s" % e)
            r = jobs.enqueue("look", T, {"method": "hero_puppet", "skip_qa": True, "puppet": {"words": {"front": "my words"}}})
            job = jobs._find(r["id"])
            plan = job["plan"]
            check(job["lane"] == "comfy" and plan["tool"] == "puppet" and plan["lock"] == "comfy" and plan["env"].get("LOCK_HELD_COMFY") == "1"
                  and plan["argv"][:5] == ["hx", "--lane", "comfy", "--until", "guides"] and "--words-front" in plan["argv"] and "my words" in plan["argv"]
                  and "front=paint" in plan["argv"] and "--reset-from" not in plan["argv"] and plan["walks"]["argv"][:4] == ["--no-import", "--only", "hx", "--variant=HX-P"],
                  "PLE jobs: a new puppet look starts on the comfy lane: tool puppet through asset_job, the ComfyUI lock, the words, the walks' argv")
            rec = json.load(open(hp, encoding="utf-8"))["variants"]["HX-P"]["recipe"]
            pr = rec.get("puppet") or {}
            check(set(pr) == set(jobs.PUPPET_SETTINGS) and pr["frame"] == "soles" and pr["face"] == "nose" and pr["run_fit"] is True and pr["fringe"] is True
                  and pr["depth_views"] == ["fd", "side", "bd", "back"] and pr["source"] == "HX-F" and pr["words"]["front"] == "my words" and rec.get("fringe_remap") is True
                  and "picks" not in pr and "seed" not in pr, "PLE jobs settings: the look's recipe records every setting under puppet (and fringe_remap on): %s" % pr)
            check(all(x in plan["argv"] for x in ("--face", "nose", "--frame", "soles")), "PLE jobs settings: the face angle and the framing reach puppet.py")
            check(rec.get("stills") == "d2" and rec.get("seed_offset") == 2437 and rec.get("anim_hint") == "a blue man" and rec.get("method") == "hero_puppet"
                  and "run_scale" not in rec and "pose_drivers" not in rec and job["spec"]["puppet"]["source"] == "HX-F",
                  "PLE jobs: the look's recipe is the source look's (its stills, seeds, words) without run_scale or drivers: %s" % rec)
            names_ = [s["name"] for s in job["progress"]["stages"]]
            clips = job["cache_keys"]["clips"]
            check(names_[:6] == ["arms-out front", "arms-out side + back", "3D shape", "rig", "clips + colours (GLB)", "guides"] and "pose_run_front" in names_
                  and "ctl_run_side" in names_ and "hx_hxp_ctl_run_side" in clips and "hx_hxp_pose_run_front" in clips and jobs.clip_view("hx_hxp_ctl_run_bd") == "bd",
                  "PLE jobs: the card's stages: the puppet's, then the walks (depth views as ctl_run_<view>); clip_view reads them")
            r2 = jobs.enqueue("look", dict(T, code="HX-Q"), {"method": "hero_puppet", "puppet": {"stills": "repaint"}})
            rec2 = json.load(open(hp, encoding="utf-8"))["variants"]["HX-Q"]["recipe"]
            check(rec2.get("stills") == "q" and rec2.get("seed_offset") != 2437 and rec2.get("anim_hint") == "a blue man", "PLE jobs: repaint: the look's own stills (its letter), its own seeds, the words kept: %s" % rec2)
            # the markers and the parser
            check(jobs.stop_marker("puppet: PICK views") == "puppet:pick:views" and jobs.stop_marker("puppet: NEXT lane local (stage rig)") == "puppet:lane:local"
                  and jobs.stop_marker("puppet: DONE guides") == "puppet:done" and jobs.stop_marker("puppet: STAGE rig start") is None,
                  "PLE jobs: puppet.py's stop lines are markers")
            for ln in ("puppet: STAGE apose start", "[puppet 16:13:07]   front c0 seed 2026101377 52s", "puppet: STAGE shape start",
                       "[puppet 16:19:58]   Hunyuan3D try 0 seed 12345 99s 4841428 bytes", "puppet: GUIDES hx_puppet_run hx_puppet_run_depth tools/dl/drivers/hx_puppet_run/silhouette.json"):
                jobs.parse_line(job, ln)
            st = {s["name"]: s for s in job["progress"]["stages"]}
            check(st["arms-out front"]["state"] == "running" and "c0" in st["arms-out front"].get("note", "") and st["3D shape"]["note"] == "try 0 made"
                  and st["guides"]["state"] == "done" and job["puppet_guides"]["pose"] == "hx_puppet_run",
                  "PLE jobs: the parser ticks the puppet's stages (a candidate, a try, the guides' names)")
            # the end of a phase: a pick
            pdir = os.path.join(jobs.PUPPET_DIR, "hx", "apose")
            for k in range(4):
                _touch(os.path.join(pdir, "front_c%d.png" % k))
            job["state"] = "running"
            jobs.puppet_after(job, _Live("puppet:pick:front"))
            check(job["state"] == "waiting" and job["waiting_for"] == "puppet_front" and [c["key"] for c in job["choices"]] == ["front=0", "front=1", "front=2", "front=3"]
                  and job["choices"][0]["url"].startswith("/dl/puppet/hx/apose/front_c0.png"), "PLE jobs: a pick stop waits with the candidates as choices")
            try:
                jobs.pick(job["id"], "front=c2;rm")
                check(False, "PLE jobs: a bad puppet pick is refused")
            except ValueError:
                check(True, "PLE jobs: a bad puppet pick is refused")
            jobs.pick(job["id"], "front=2")
            check(job["state"] == "queued" and job["front"] and job["lane"] == "comfy" and job["plan"]["argv"][-2:] == ["--pick", "front=2"]
                  and job["spec"]["puppet"]["picks"] == {"front": 2}, "PLE jobs: the pick resumes first in the comfy lane (the views to paint) with --pick")
            # views picked: a views pick goes on the comfy lane (the shape), a shape pick on the local lane
            job["state"] = "waiting"
            jobs.pick(job["id"], "side=1,back=0")
            check(job["lane"] == "comfy" and "side=1,back=0" in job["plan"]["argv"], "PLE jobs: side and back picked together; the shape follows on comfy")
            job["state"] = "waiting"
            jobs.pick(job["id"], "shape=1")
            check(job["lane"] == "local" and job["plan"]["lock"] is None and "LOCK_HELD_COMFY" not in job["plan"]["env"],
                  "PLE jobs: the shape picked: Blender on the local lane, holding no ComfyUI lock (its env says so)")
            # a lane hop
            job["state"] = "running"
            jobs.puppet_after(job, _Live("puppet:lane:comfy"))
            check(job["state"] == "queued" and job["front"] and job["lane"] == "comfy" and job.get("puppet_pick") is None, "PLE jobs: NEXT lane hops the job to that lane, first in line")
            # done: the guides go into the look's recipe, the walks are queued as hero_pose5's gen_art
            job["state"] = "running"
            job["puppet_guides"] = {"pose": "hx_puppet_run", "depth": "hx_puppet_run_depth", "silhouette": "tools/dl/drivers/hx_puppet_run/silhouette.json"}
            jobs.puppet_after(job, _Live("puppet:done"))
            rec = json.load(open(hp, encoding="utf-8"))["variants"]["HX-P"]["recipe"]
            check(job["puppet_next"] == "walks" and job["lane"] == "comfy" and job["plan"]["tool"] == "gen_art" and "--variant=HX-P" in job["plan"]["argv"]
                  and rec["pose_drivers"] == {v: "hx_puppet_run" for v in ("front", "fd", "side", "bd", "back")}
                  and rec["ctl_drivers"] == {v: "hx_puppet_run_depth" for v in ("fd", "side", "bd", "back")} and rec["run_fit"].endswith("hx_puppet_run/silhouette.json")
                  and rec.get("fringe_remap") is True and (rec.get("puppet") or {}).get("face") == "nose",
                  "PLE jobs: DONE writes the guides into the look's recipe (pose_drivers, ctl_drivers, run_fit) and queues the walks (gen_art)")
            # the GLB among the outputs
            _touch(os.path.join(jobs.PUPPET_DIR, "hx", "hx_puppet.glb"))
            outs = jobs._harvest(job)
            glbs = [o for o in outs if o.get("type") == "glb"]
            check(glbs and glbs[0]["url"].startswith("/dl/puppet/hx/hx_puppet.glb?v="), "PLE jobs: the card's outputs carry the GLB for the 3D viewer")
            # a setting changed in Recipe (typed) is what a re-queue runs (the recipe as the JSON holds it wins)
            cur = json.load(open(hp, encoding="utf-8"))["variants"]["HX-P"]["recipe"]
            cur["puppet"] = dict(cur["puppet"], frame="ankles", face="head", depth_views="side,back", fringe=False)
            server.look_op("hero", "hx", ["HX-P"], "recipe", {"recipe": cur})
            job["state"] = "failed"
            jobs.requeue(job["id"], {})
            av = job["plan"]["argv"] if job["plan"].get("tool") == "puppet" else []
            jp = jobs.puppet_spec(job["spec"], job["target"])
            check(jp["frame"] == "ankles" and jp["face"] == "head" and jp["depth_views"] == ["side", "back"] and not jp["fringe"],
                  "PLE jobs settings: a re-queue runs the settings as the look's recipe holds them (edited in Recipe (typed)): %s" % {k: jp[k] for k in ("frame", "face", "depth_views", "fringe")})
            # requeue from a stage; the stage re-roll at enqueue
            job["state"] = "failed"
            jobs.requeue(job["id"], {"stage": "rig"})
            check(job.get("puppet_next") is None and "--reset-from" in job["plan"]["argv"] and job["plan"]["argv"][job["plan"]["argv"].index("--reset-from") + 1] == "rig"
                  and job["plan"]["tool"] == "puppet", "PLE jobs: Re-queue from a stage: the puppet again with --reset-from <stage>")
            job["state"] = "running"
            jobs.puppet_after(job, _Live("puppet:lane:local"))
            check("--reset-from" not in job["plan"]["argv"], "PLE jobs: --reset-from runs once (the phase that moved things aside)")
            job["state"], job["waiting_for"] = "waiting", "puppet_shape"
            jobs.requeue(job["id"], {"stills": [], "clips": [], "seed": 1})
            argv = job["plan"]["argv"]
            check("--reroll" in argv and argv[argv.index("--reroll") + 1] == "shape" and argv[argv.index("--seed") + 1] == "1" and job["lane"] == "comfy",
                  "PLE jobs: Re-roll N more on a pick: those candidates again on new seeds (comfy)")
            try:
                jobs.enqueue("look", {"kind": "hero", "id": "hx", "code": "HX-F"}, {"method": "hero_pose5", "reroll": {"mode": "stage", "stage": "rig"}})
                check(False, "PLE jobs: the stage re-roll is the Puppet method's only")
            except ValueError as e:
                check("hero_puppet" in str(e), "PLE jobs: the stage re-roll is the Puppet method's only: %s" % e)
            r3 = jobs.enqueue("look", dict(T, code="HX-R"), {"method": "hero_puppet", "reroll": {"mode": "stage", "stage": "anim"}, "puppet": {"reuse": "fresh"}})
            a3 = jobs._find(r3["id"])["plan"]["argv"]
            check(a3[a3.index("--reset-from") + 1] == "anim", "PLE jobs: the form's stage re-roll becomes --reset-from")
            r4 = jobs.enqueue("look", dict(T, code="HX-S"), {"method": "hero_puppet", "puppet": {"reuse": "fresh"}})
            j4 = jobs._find(r4["id"])
            check(j4["lane"] == "comfy" and j4["plan"]["argv"][j4["plan"]["argv"].index("--reset-from") + 1] == "apose", "PLE jobs: a new puppet moves the old one aside (--reset-from apose)")
            j4["state"] = "running"
            jobs.puppet_after(j4, _Live("puppet:pick:front"))
            j4["state"] = "waiting"
            jobs.pick(j4["id"], "front=0")
            check("--reset-from" not in j4["plan"]["argv"] and j4.get("puppet_fresh_done"), "PLE jobs: ... once: the resumed phases keep the new one")
            # the reuse of a puppet on disk starts on the local lane
            for f in ("apose_front.png", "apose_side.png", "apose_back.png", "shape.glb", "hx_puppet.blend"):
                _touch(os.path.join(jobs.PUPPET_DIR, "hx", f))
            r5 = jobs.enqueue("look", dict(T, code="HX-T"), {"method": "hero_puppet"})
            check(jobs._find(r5["id"])["lane"] == "local" and all(s["state"] == "done" for s in jobs._find(r5["id"])["progress"]["stages"][:5]),
                  "PLE jobs: a hero with a puppet starts on the local lane, its stages done from the disk")
            r6 = jobs.enqueue("look", dict(T, code="HX-U"), {"method": "hero_puppet", "puppet": {"reuse": "blend"}})
            check("--from-blend" in jobs._find(r6["id"])["plan"]["argv"] and jobs._find(r6["id"])["lane"] == "local", "PLE jobs: his .blend: --from-blend on the local lane")
    finally:
        for k, v in saved.items():
            setattr(jobs, k, v)
        for k, v in saved_locks.items():
            setattr(locks, k, v)
        jobs._state, jobs._hooks, jobs._root, lc = saved_state
        jobs._lane_current.clear()
        jobs._lane_current.update(lc)
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- 4. the server

def server_checks(check, server):
    p = server.dl_path("puppet/buck/buck_puppet.glb")
    real = os.path.isfile(os.path.join(server.DL, "puppet", "buck", "buck_puppet.glb"))
    check((p is not None) == real and server.FILE_TYPES.get(".glb") == "model/gltf-binary" and server.dl_path("puppet/../../x.glb") is None,
          "PLE server: /dl/puppet serves a .glb as model/gltf-binary, inside tools/dl only")
    vf = os.path.join(HERE, "vendor", "model-viewer-4.0.0.min.js")
    check(os.path.isfile(vf) and os.path.getsize(vf) > 500000 and os.path.isfile(os.path.join(HERE, "vendor", "model-viewer-4.0.0.LICENSE.txt"))
          and "customElements" in _read(vf)[:400000] + _read(vf)[400000:] and "import " not in _read(vf)[:2000],
          "PLE server: model-viewer 4.0.0 is vendored (self-contained, its licence note beside it)")
    import threading
    import urllib.request
    httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    th = threading.Thread(target=httpd.serve_forever, daemon=True)
    th.start()
    base = "http://127.0.0.1:%d" % httpd.server_address[1]
    try:
        with urllib.request.urlopen(base + "/vendor/model-viewer-4.0.0.min.js", timeout=30) as r:
            check(r.status == 200 and r.headers.get("Content-Type", "").startswith("text/javascript") and len(r.read()) > 500000, "PLE server: /vendor/ serves the viewer as a script")
        try:
            urllib.request.urlopen(base + "/vendor/..%2Fserver.py", timeout=10)
            check(False, "PLE server: /vendor/ refuses a path outside it")
        except urllib.error.HTTPError as e:
            check(e.code == 404, "PLE server: /vendor/ refuses a path outside it")
        with urllib.request.urlopen(base + "/puppet.js", timeout=10) as r:
            check(r.status == 200 and b"const Puppet" in r.read(), "PLE server: the page serves puppet.js")
        if real:
            with urllib.request.urlopen(base + "/api/puppet/buck", timeout=30) as r:
                d = json.loads(r.read().decode("utf-8"))
            g = {x["name"]: x for x in d.get("guides", [])}
            check(d["ok"] and d["glb"].startswith("/dl/puppet/buck/buck_puppet.glb?v=") and all(d["stages"].values()) and d["played"] == "BUC-F"
                  and d["screen"] == "green" and "buck_puppet_run" in g and g["buck_puppet_run"]["frame"] == "soles" and g["buck_puppet_run"]["ratios"].get("side")
                  and any(l["code"] == "BUC-F" and l["stills"].get("side") for l in d["looks"]) and "running.fbx" in d["clips"],
                  "PLE server: /api/puppet/buck: Jezyk's GLB, his stages, the guides with their framing and ratios, every look's stills, the clips")
            with urllib.request.urlopen(base + d["glb"], timeout=30) as r:
                check(r.headers.get("Content-Type") == "model/gltf-binary" and r.read(4) == b"glTF", "PLE server: the GLB itself, binary glTF")
        try:
            urllib.request.urlopen(base + "/api/puppet/no_such_hero", timeout=10)
            check(False, "PLE server: an unknown hero is a 404")
        except urllib.error.HTTPError as e:
            check(e.code == 404, "PLE server: an unknown hero is a 404")
        if os.path.isfile(os.path.join(server.CONTENT, "characters", "astro", "astro.json")):
            with urllib.request.urlopen(base + "/api/puppet/astro", timeout=30) as r:
                d = json.loads(r.read().decode("utf-8"))
            check(d["ok"] and any(l.get("own") and l["stills"].get("front") for l in d["looks"]) or not os.path.isfile(os.path.join(server.DL, "ai_raw_anime", "astro_front.png")),
                  "PLE server: a hero without looks offers his own paintings as the source")
    finally:
        httpd.shutdown()
        httpd.server_close()


# ---------------------------------------------------------------- 5. the page

PAGE_RUNNER = r"""
const fs = require('fs');
global.U = { el: () => ({}), clear: (e) => e };
global.document = undefined;
const P = require(process.argv[2]);
const q = JSON.parse(fs.readFileSync(0, 'utf8'));
const out = {};
out.keys = Object.keys(P).sort();
out.group = P.groupPick({ side: 'side=1', back: 'back=0' });
out.groupMissing = P.groupPick({ side: 'side=1', back: null });
out.defaults = P.defaults('BUC-F');
out.stages = P.STAGES;
out.src = P.VIEWER_SRC;
out.settings = P.WALK_SETTINGS.map((s) => [s.key, s.label, s.help.length]);
out.on = [P.isOn({}, P.WALK_SETTINGS[0]), P.isOn({ frame: 'ankles' }, P.WALK_SETTINGS[1]), P.isOn({ fringe: false }, P.WALK_SETTINGS[2]), P.isOn({ face: 'nose' }, P.WALK_SETTINGS[3]), P.isOn({}, P.WALK_SETTINGS[3])];
process.stdout.write(JSON.stringify(out));
"""


def page_checks(check, run_node):
    m = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    meth = next((x for x in m["methods"] if x["id"] == "hero_puppet"), None)
    check(meth is not None and meth["kind"] == "hero" and meth["runner"]["tool"] == "puppet" and meth["example"]["image"] == "examples/hero_puppet_may.png"
          and os.path.isfile(os.path.join(HERE, meth["example"]["image"])) and meth["time"]["median_s"] < meth["time"]["worst_s"],
          "PLE page: methods.json's hero_puppet card (a hero method, the puppet runner, the trial's picture, timings)")
    w = " ".join(meth["weaknesses"]) if meth else ""
    check("European Union" in w and "AMD" in w and "no face" in w and "four hands" in w and meth.get("stage_times") and "Hunyuan3D (2 tries" in " ".join(meth["stage_times"]),
          "PLE page: its weaknesses: the licence's EU note, the AMD card, the depth video's missing face, Klein's four hands; the trial's stage times")
    keys = {f["key"] for f in meth["recipe_fields"]} if meth else set()
    check({"run_fit", "fringe_remap", "anim_hint", "run_scale"} <= keys and any(f["key"] == "puppet" for f in meth.get("job_fields", [])),
          "PLE page: the card's recipe keys (run_fit, fringe_remap, anim_hint, run_scale) and its puppet field")
    js = _read(os.path.join(HERE, "jobs.js")) + (_read(os.path.join(HERE, "jobs_view.js")) if os.path.isfile(os.path.join(HERE, "jobs_view.js")) else "")   # pass 97 (lane LIVE, re-pinned on purpose): the outputs moved to jobs_view.js
    check("Puppet.formSection(body, c)" in js and "k === 'puppet'" in js and "Puppet.outputCell(o, holder)" in js and "Puppet.rerollStage(box, picks)" in js
          and "hero_puppet: ['seeds', 'clips', 'clip', 'stills', 'stage']" in js and "{ mode: 'stage', stage: spec.reroll.stage || 'guides' }" in js and "ch.group && groups.length" in js,
          "PLE page: jobs.js's hooks: the form section, the field kept out of Asset settings, the GLB output, the stage re-run, one pick per group")
    check("Puppet.section(doc)" in _read(os.path.join(HERE, "heroes.js")) and '<script src="puppet.js"></script>' in _read(os.path.join(HERE, "index.html")),
          "PLE page: the hero's Art words carry his puppet; index.html loads puppet.js")
    res = run_node({}, PAGE_RUNNER.replace("process.argv[2]", json.dumps(os.path.join(HERE, "puppet.js").replace("\\", "/"))))
    if not res:
        check(run_node.__doc__ is None or True, "PLE page: node is not here: puppet.js's helpers skipped")
        return
    check({"viewer", "section", "formSection", "wordsText", "groupPick", "outputCell", "rerollStage"} <= set(res.get("keys", [])),
          "PLE page: puppet.js exports the viewer, the hero section, the form section and the card hooks")
    check(res.get("group") == "side=1,back=0" and res.get("groupMissing") == "side=1" and res.get("src") == "/vendor/model-viewer-4.0.0.min.js",
          "PLE page: groupPick joins one pick per group; the viewer comes from /vendor/")
    dfl = res.get("defaults") or {}
    check(dfl.get("source") == "BUC-F" and dfl.get("refs") == {"front": "paint", "side": "paint", "back": "paint"} and dfl.get("depth_views") == ["fd", "side", "bd", "back"]
          and dfl.get("frame") == "soles" and dfl.get("run_fit") is True and dfl.get("fringe") is True and dfl.get("face") == "nose" and dfl.get("stills") == "reuse" and dfl.get("clip") == "running.fbx",
          "PLE page: the form's defaults: paint arms-out from the played look, depth for fd/side/bd/back, soles, the nose, run_fit on, fringe on, the stills reused")
    st = res.get("settings") or []
    check([x[0] for x in st] == ["run_fit", "frame", "fringe", "face"] and [x[1] for x in st] == ["Size from the 3D model", "Frame by the soles", "Clean colour fringes", "Keep the face angle"]
          and all(x[2] > 100 for x in st) and res.get("on") == [True, False, False, True, True],
          "PLE page settings: the four improvements are named settings with plain help, on by default: %s" % st)
    js = _read(os.path.join(HERE, "jobs.js"))
    check("String(f.key).startsWith('puppet.') || f.key === 'run_fit' || f.key === 'fringe_remap'" in js,
          "PLE page settings: the job form shows them once (in The 3D puppet), not again among the recipe rows")
    keys = [f["key"] for f in meth["recipe_fields"]]
    check(keys[:4] == ["puppet.run_fit", "puppet.frame", "puppet.fringe", "puppet.face"] and "puppet.depth_views" in keys and all(
          f.get("help") for f in meth["recipe_fields"] if f["key"].startswith("puppet.")),
          "PLE page settings: Recipe (typed) shows every setting the look ran with (methods.json's puppet.* rows)")
    lab = {f["key"]: f.get("label") for f in meth["recipe_fields"]}
    check(lab.get("puppet.run_fit") == "Size from the 3D model" and lab.get("puppet.frame") == "Frame by the soles" and lab.get("puppet.fringe") == "Clean colour fringes"
          and lab.get("puppet.face") == "Keep the face angle", "PLE page settings: Recipe (typed) names them as the form does")


# ---------------------------------------------------------------- 6. the docs

def docs_checks(check):
    instr = _read(os.path.join(HERE, "instructions.js"))
    check("Pass 71: the Puppet method" in instr and "+ New look from the puppet" in instr and "3D reference" in instr and "Mixamo" in instr
          and all(k in instr for k in ("Size from the 3D model", "Frame by the soles", "Clean colour fringes", "Keep the face angle")),
          "PLE docs: the Instructions tab's \"Pass 71: the Puppet method\"")
    md = _read(os.path.join(ROOT, "docs", "level_editor.md"))
    check("## Pass 71: the Puppet method" in md and "hero_puppet" in md and "selftest_PLE.py" in md and "LE_JOBS_DIR" in md
          and all(k in md for k in ("Size from the 3D model", "Frame by the soles", "Clean colour fringes", "Keep the face angle", "recipe.puppet")),
          "PLE docs: docs/level_editor.md \"Pass 71\"")
    sch = _read(os.path.join(ROOT, "docs", "assets_schema.md"))
    check(all(k in sch for k in ("`.recipe.run_fit`", "`.recipe.fringe_remap`", "`.recipe.ctl_drivers`", "`puppet`", "`hero_puppet`")),
          "PLE docs: docs/assets_schema.md rows: run_fit, fringe_remap, ctl_drivers, hero_puppet, the job's puppet settings")


# ---------------------------------------------------------------- 7. saved workflows open clean (the lead's item)

def comfy_checks(check):
    """A job's saved workflow (the UI file and its sidebar copy) names top-level copies of its pictures, so the page's
    LoadImage picker lists them (an "open in ComfyUI" link showed every LoadImage red: "88fits/<file>" is not in it);
    the graph that runs keeps its own names; a picture that cannot be copied keeps its value."""
    import comfy
    saved = (comfy.upload, comfy._input_bytes, dict(comfy._UPLOADED), dict(comfy._TOP_COPIES))
    calls = []
    try:
        def fake_upload(data, name, subfolder="88fits"):
            calls.append((name, subfolder, len(data)))
            return (subfolder + "/" if subfolder else "") + comfy.upload_name(name)
        comfy.upload = fake_upload
        comfy._input_bytes = lambda v: b"fetched:" + v.encode()
        comfy._UPLOADED.clear()
        comfy._TOP_COPIES.clear()
        comfy._UPLOADED["88fits/puppet_hx_front_ref.png"] = b"the bytes this job uploaded"
        ui = {"nodes": [{"type": "LoadImage", "widgets_values": ["88fits/puppet_hx_front_ref.png", "image"]},
                        {"type": "LoadImage", "widgets_values": ["88fits/style_anchor.png", "image"]},
                        {"type": "LoadImage", "widgets_values": ["top_level.png", "image"]},
                        {"type": "CLIPTextEncode", "widgets_values": ["88fits/not/a/picture"]}]}
        ch = comfy.portable_ui(ui)
        vals = [n["widgets_values"][0] for n in ui["nodes"]]
        check(len(ch) == 2 and "/" not in vals[0] and vals[0].startswith("88fits_") and vals[0].endswith("_puppet_hx_front_ref.png")
              and "/" not in vals[1] and vals[2] == "top_level.png" and vals[3] == "88fits/not/a/picture" and all(c[1] == "" for c in calls),
              "PLE comfy: a saved workflow's LoadImage names a top-level copy (named by its contents); other nodes and top-level names untouched: %s" % vals)
        ui2 = {"nodes": [{"type": "LoadImage", "widgets_values": ["88fits/puppet_hx_front_ref.png", "image"]}]}
        n0 = len(calls)
        comfy.portable_ui(ui2)
        check(ui2["nodes"][0]["widgets_values"][0] == vals[0] and len(calls) == n0, "PLE comfy: the same picture is copied once per process")
        comfy._UPLOADED["88fits/puppet_hx_front_ref.png"] = b"new bytes after a re-upload"
        ui3 = {"nodes": [{"type": "LoadImage", "widgets_values": ["88fits/puppet_hx_front_ref.png", "image"]}]}
        comfy.portable_ui(ui3)
        check(ui3["nodes"][0]["widgets_values"][0] != vals[0], "PLE comfy: a picture uploaded again with other bytes gets a copy of its own (the old workflow keeps its own)")

        def boom(v):
            raise OSError("the server did not answer")
        comfy._input_bytes = boom
        ui4 = {"nodes": [{"type": "LoadImage", "widgets_values": ["88fits/unknown.png", "image"]}]}
        _quiet(comfy.portable_ui, ui4)
        check(ui4["nodes"][0]["widgets_values"][0] == "88fits/unknown.png", "PLE comfy: a picture that cannot be copied keeps its value")
        src = _read(os.path.join(TOOLS, "comfy.py"))
        body = src.split("def save_job_workflow", 1)[1].split(chr(10) + "def ", 1)[0]
        check("portable_ui(ui)" in body and body.index("portable_ui(ui)") < body.index('stem + "_workflow.json"') and "json.dump(graph.api(), f" in body,
              "PLE comfy: save_job_workflow rewrites the UI file (and so its sidebar copy), the _api.json stays the graph that ran")
        check('"SaveGLB"' in body, "PLE comfy: a Hunyuan3D graph's saved workflow is named by its SaveGLB prefix")
    finally:
        comfy.upload, comfy._input_bytes = saved[0], saved[1]
        comfy._UPLOADED.clear()
        comfy._UPLOADED.update(saved[2])
        comfy._TOP_COPIES.clear()
        comfy._TOP_COPIES.update(saved[3])


def dry_folder_checks(check):
    """A dry run never writes into game/content (pass 71: a dry run of MAY-Q's job overwrote her strip): gen_art works on
    a copy of the JSON under the job's folder; a temp copy elsewhere (the selftests') is used as it is."""
    import asset_job
    tmp = tempfile.mkdtemp(prefix="le_ple_dryf_")
    try:
        real = os.path.join(ROOT, "game", "content", "characters", "may")
        got = _quiet(asset_job._dry_folder, {}, tmp, real)[0]
        check(os.path.abspath(got).startswith(os.path.abspath(tmp)) and os.path.isfile(os.path.join(got, "may.json")) and got.replace("\\", "/").endswith("dry_content/characters/may"),
              "PLE dry: a folder under game/content becomes <job>/dry_content/<type>/<id> with a copy of the JSON: %s" % got)
        other = os.path.join(tmp, "copy", "characters", "x")
        check(asset_job._dry_folder({}, tmp, other) == other, "PLE dry: a folder outside game/content (a selftest's copy) is used as it is")
        src = _read(os.path.join(TOOLS, "asset_job.py"))
        # pass 96 (lane LOOP, re-pinned on purpose): gen_ctl's dry run takes the copy too (GEN_CTL_FOLDER): three callers + the def
        check(src.count("_dry_folder(job, job_dir,") == 4, "PLE dry: all three of asset_job's dry runs (a gen_art look, a puppet's walks, a creature_ctl look) take the copy")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def default_copy_checks(check):
    """A spec without a recipe gets its own copy of the default (pass 71: one look's stills and seeds were written into
    the shared default dict and every later spec without a recipe started with them)."""
    import jobs
    a = jobs.validate_spec("look", {"method": "hero_pose5"})
    a["recipe"]["stills"] = "zz"
    b = jobs.validate_spec("look", {"method": "hero_pose5"})
    check(b["recipe"] == {} and jobs.SPECS["look"]["fields"]["recipe"]["default"] == {}, "PLE jobs: validate_spec hands every spec its own default recipe")


def checks(check, run_node, server):
    comfy_checks(check)
    default_copy_checks(check)
    dry_folder_checks(check)
    puppet_checks(check)
    gen_art_checks(check)
    jobs_checks(check, server)
    server_checks(check, server)
    page_checks(check, run_node)
    docs_checks(check)
