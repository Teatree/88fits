"""Pass 92, lane SPIDER: a spider by the scorpion's method (Garry's spider._low_poly.glb, made eight-legged), its made walk
and its death on its back, and the Level Editor fixes met on the way.

Groups: the made motions' maths (tools/blender_gait.py: the alternating sets of eight legs, a tripod of six, the stride's
sweep and lift, the death's timeline and its held end); the probe's leg chains and its head-bone forward
(tools/blender_ref.limb_chains); jobs.py's driver_depth modes gait / flip_curl (their fields with the tool's own defaults,
only the changed keys on the command line, only to the mode that reads them) and the new kind ref_limbs (the limb clone,
then the probe of the new model); a model dropped loose into uploads/3d (listed, its probe in uploads/3d/<slug>/);
methods.json (the modes, the fields, the ref_limbs method, the truth about negative words at cfg 1); the creature's four
looks and their recipes. Nothing here runs Blender or writes under game/.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

SPIDER6 = ["_rootJoint", "body_01", "neck_02", "head_03", "head_end_04", "right_chap_05", "left_chap_06"] + [
    "%s_leg_%s_%d_0%d" % (s, p, k, i) for i, (s, p) in enumerate([(s, p) for s in ("left", "right") for p in ("front", "center", "back")])
    for k in (1, 2, 3, 4)]


def _parents(names):
    out = {}
    for n in names:
        if "_leg_" in n:
            k = int(n.split("_")[3])
            out[n] = "body_01" if k == 1 else n.rsplit("_", 2)[0] + "_%d_" % (k - 1) + n.rsplit("_", 1)[1]
        elif n == "_rootJoint":
            out[n] = None
        else:
            out[n] = "_rootJoint" if n == "body_01" else "body_01"
    return out


def checks(check, run_node, server):
    import blender_gait as G
    import blender_ref as BR
    import jobs

    # ---- the made walk: two sets, alternating along each side and across
    sides = [-1, -1, -1, -1, 1, 1, 1, 1]
    order = [0, 1, 2, 3, 0, 1, 2, 3]
    offs = G.phase_offsets(sides, order, "alternate")
    check(offs == [0.0, 0.5, 0.0, 0.5, 0.5, 0.0, 0.5, 0.0], "eight legs alternate: L1 R2 L3 R4 against R1 L2 R3 L4: %s" % offs)
    six = G.phase_offsets([-1, -1, -1, 1, 1, 1], [0, 1, 2, 0, 1, 2], "alternate")
    check(six == [0.0, 0.5, 0.0, 0.5, 0.0, 0.5], "six legs walk the insect's tripod (L1 R2 L3 / R1 L2 R3): %s" % six)
    wave = G.phase_offsets(sides, order, "wave")
    check(len(set(wave[:4])) == 4 and all(abs(((a - b) % 1.0) - 0.5) < 1e-9 for a, b in zip(wave[:4], wave[4:])),
          "wave: each side's legs one after another, the sides half a stride apart: %s" % wave)
    y0, l0, f0 = G.leg_angles(0.0, 0.55, 18, 24, 16)
    y1, l1, f1 = G.leg_angles(0.5, 0.55, 18, 24, 16)
    ym, lm, fm = G.leg_angles(0.55 + 0.45 / 2, 0.55, 18, 24, 16)
    check(abs(y0 - 18) < 1e-9 and l0 == 0 and f0 == 0, "a leg's stride starts forward on the ground: %s" % [y0, l0, f0])
    check(y1 < 0 and l1 == 0, "on the ground it sweeps back: %s" % [y1, l1])
    check(abs(lm - 24) < 1e-6 and abs(fm - 16) < 1e-6 and abs(ym) < 1e-6, "mid-step it is raised and bent and passing its hip: %s" % [ym, lm, fm])
    check(all(abs(a - b) < 1e-9 for a, b in zip(G.leg_angles(0.0, 0.55, 18, 24, 16), G.leg_angles(1.0, 0.55, 18, 24, 16))), "the stride loops")

    # ---- the look's proportions in the clay: a bigger body keeps its legs' size, the head is the first head bone
    sc = G.bone_scales({"body_scale": 1.5, "head_scale": 1.6, "leg_scale": 0.65}, SPIDER6, "body_01", ["left_leg_front_1_00", "right_leg_back_1_05"])
    check(sc.get("body_01") == 1.5 and abs(sc["left_leg_front_1_00"] * 1.5 - 0.65) < 1e-9 and sc.get("head_03") == 1.6 and "head_end_04" not in sc,
          "body 1.5 with legs 0.65 of their length: the leg roots get 0.65 / 1.5, the head bone 1.6, not its end: %s" % sc)
    check(G.bone_scales({}, SPIDER6, "body_01", ["x"]) == {}, "no proportions: nothing scaled")
    jf = jobs.SPECS["driver_depth"]["fields"]
    check(all(k in jf and jf[k]["default"] == v for k, v in G.SCALE_DEFAULTS.items()), "driver_depth carries the proportion fields with the tool's defaults")

    # ---- the made death: the timeline and its held end
    o = G.options({"curl": "55", "curl_root": "70"}, G.DEATH_DEFAULTS)
    check(o["curl"] == 55.0 and o["roll_axis"] == "side", "options parse numbers and keep text: %s" % {k: o[k] for k in ("curl", "roll_axis")})
    st0 = G.death_curve(0.0, o)
    check(st0["roll"] == 0 and st0["curl"] == 0, "at the hit it stands: %s" % st0)
    mid = G.death_curve(o["roll_start"] + o["roll_time"] / 2, o)
    check(60 < mid["roll"] < 120, "half way through the roll it is on its side: %.1f" % mid["roll"])
    land = G.death_curve(o["roll_start"] + o["roll_time"] + 0.001, o)
    check(abs(land["roll"] - 180) < 1e-6, "it lands on its back: %.1f" % land["roll"])
    end = G.death_curve(o["seconds"], o)
    held = G.death_curve(o["seconds"] * o["hold"], o)
    check(end == held and end["curl"] == 1.0 and end["hop"] == 0.0 and abs(end["twitch"]) < 1e-9,
          "past hold the dead pose is held, fully curled and still: %s" % end)
    curls = [G.death_curve(t / 20.0 * o["seconds"], o)["curl"] for t in range(21)]
    check(all(b >= a for a, b in zip(curls, curls[1:])), "the legs only ever curl further in")
    hops = [G.death_curve(o["roll_start"] + o["roll_time"] + t * 0.03, o)["hop"] for t in range(1, 12)]
    check(max(hops) > 0 and max(hops) <= o["bounce"] + 1e-9, "it bounces once it lands, never higher than bounce: %.3f" % max(hops))

    # ---- the probe: leg chains and the head's forward
    par = _parents(SPIDER6)
    lc = BR.limb_chains(SPIDER6, par)
    check(lc["count"] == 6 and lc["left"] == 3 and lc["right"] == 3, "the spider's file has six leg chains, three a side: %s" % lc)
    eight = SPIDER6 + ["left_leg_mid_%d_011" % k for k in (1, 2, 3, 4)] + ["right_leg_mid_%d_022" % k for k in (1, 2, 3, 4)]
    par8 = dict(par)
    for side, tail in (("left", "011"), ("right", "022")):
        for k in (1, 2, 3, 4):
            par8["%s_leg_mid_%d_%s" % (side, k, tail)] = "body_01" if k == 1 else "%s_leg_mid_%d_%s" % (side, k - 1, tail)
    lc8 = BR.limb_chains(eight, par8)
    check(lc8["count"] == 8 and lc8["left"] == 4 and lc8["right"] == 4, "made eight-legged: four a side: %s" % lc8)
    src = open(os.path.join(TOOLS, "blender_ref.py"), encoding="utf-8").read()
    check('basis = "head"' in src and '"limbs": limbs' in src and '"gait_drivers"' in src,
          "the probe guesses a creature's forward from its head bone and writes limbs and can.gait_drivers")

    # ---- jobs.py: driver_depth's made modes and the new ref_limbs
    f = jobs.SPECS["driver_depth"]["fields"]
    check(set(f["mode"]["options"]) == {"cycle", "oneshot", "gait", "flip_curl"}, "driver_depth offers the made modes: %s" % f["mode"]["options"])
    for k, v in G.GAIT_DEFAULTS.items():
        check(k in f and f[k]["default"] == v, "driver_depth field %s defaults to the tool's %r (%r)" % (k, v, f.get(k, {}).get("default")))
    for k, v in G.DEATH_DEFAULTS.items():
        if k == "spasm":
            continue
        check(k in f and f[k]["default"] == v, "driver_depth field %s defaults to the tool's %r (%r)" % (k, v, f.get(k, {}).get("default")))
    check(jobs.made_motion_args({"mode": "gait", "swing": 14.0, "lift": "24", "legs": "leg_", "curl": 55}) == ["legs=leg_", "lift=24"],
          "only the changed gait keys reach the command line, and no death key: %s" % jobs.made_motion_args({"mode": "gait", "swing": 14.0, "lift": "24", "legs": "leg_", "curl": 55}))
    check(jobs.made_motion_args({"mode": "flip_curl", "curl": 55, "curl_root": 70.0, "swing": 30}) == ["curl=55", "curl_root=70.0"],
          "only the changed death keys reach a flip_curl: %s" % jobs.made_motion_args({"mode": "flip_curl", "curl": 55, "curl_root": 70.0, "swing": 30}))
    check(jobs.made_motion_args({"mode": "cycle", "swing": 30}) == [], "a clip's cycle takes none of them")
    p = jobs._plan({"id": "jt1", "kind": "driver_depth", "target": {}, "spec": {"src": "tools/dl/uploads/3d/spider_8legs/spider_8legs.glb", "name": "spider_walk_t",
                                                                               "mode": "gait", "swing": 18, "lift": 24, "legs": "leg_", "forward": "+Y"}})
    check("mode=gait" in p["equiv"] and "swing=18" in p["equiv"] and "legs=leg_" in p["equiv"] and "action=" not in p["equiv"],
          "a gait job's command needs no clip: %s" % p["equiv"])
    check("ref_limbs" in jobs.SPECS and jobs.SPECS["ref_limbs"]["fields"]["rest"]["default"] == "frame:0", "the ref_limbs kind exists (rest frame:0 by default)")
    p = jobs._plan({"id": "jt2", "kind": "ref_limbs", "target": {}, "spec": {"src": "tools/dl/uploads/3d/spider._low_poly.glb", "name": "Spider 8 legs X",
                                                                            "rest": "frame:0", "clone": "a_:b_:24:-0.06;c_:d_:-24", "forward": "+Y"}})
    check(len(p.get("steps") or []) == 2 and "blender_limb_clone.py" in p["equiv"] and "out=tools/dl/uploads/3d/spider_8_legs_x/spider_8_legs_x.glb" in p["equiv"]
          and '"clone=a_:b_:24:-0.06;c_:d_:-24"' in p["equiv"] and "blender_ref.py -- src=tools/dl/uploads/3d/spider_8_legs_x/spider_8_legs_x.glb" in p["equiv"],
          "ref_limbs writes a new upload of its own and probes it (the ; quoted for a shell): %s" % p["equiv"])
    p = jobs._plan({"id": "jt3", "kind": "ref_limbs", "target": {}, "spec": {"src": "x.glb", "name": ""}})
    check(bool(p.get("error")), "ref_limbs without a name is refused: %s" % p.get("error"))
    check(jobs._blender_ready("ref_limbs", {}) in ("",) or "Blender not found" in jobs._blender_ready("ref_limbs", {}), "ref_limbs has its script")

    # ---- a model dropped loose into uploads/3d
    d3 = os.path.join(jobs.UPLOADS, "3d")
    check(os.path.normpath(jobs.loose_slug_dir(d3, "tools/dl/uploads/3d/spider._low_poly.glb")) == os.path.normpath(os.path.join(d3, "spider_low_poly")),
          "a loose model's probe goes to uploads/3d/<slug>/")
    other = os.path.join(d3, "beetle")
    check(jobs.loose_slug_dir(other, "tools/dl/uploads/3d/beetle/beetle.fbx") == other, "an uploaded model's folder is its own")
    p = jobs._plan({"id": "jt4", "kind": "ref_probe", "target": {}, "spec": {"src": "tools/dl/uploads/3d/spider._low_poly.glb"}})
    check("out=tools/dl/uploads/3d/spider_low_poly mode=probe" in p["equiv"], "the probe of a loose model: %s" % p["equiv"])
    import server as srv
    tmp = tempfile.mkdtemp(prefix="le_spider92_")
    try:
        open(os.path.join(tmp, "spider._low_poly.glb"), "wb").write(b"glTF")
        open(os.path.join(tmp, "notes.txt"), "w").write("x")
        open(os.path.join(tmp, "pack.zip"), "wb").write(b"PK")
        os.makedirs(os.path.join(tmp, "beetle"))
        open(os.path.join(tmp, "beetle", "beetle.fbx"), "wb").write(b"x")
        open(os.path.join(tmp, "beetle.glb"), "wb").write(b"glTF")
        lm = srv.loose_models(tmp)
        check(lm == {"spider_low_poly": "spider._low_poly.glb", "beetle_loose": "beetle.glb"},
              "loose models are listed by slug, a zip and a text file are not, a slug an upload holds gets _loose: %s" % lm)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- the walk cache follows the painting, the seed and the control video (a view painted again walks anew)
    import animate
    check(animate.cache_fits({"seed": 7, "ctl_dir": "/x/front"}, "h1", 7, "/x/front"), "a cache from before pass 92 (no hash) still serves its own seed")
    check(not animate.cache_fits({"seed": 7, "ref_hash": "h0"}, "h1", 7, "/x"), "a view painted again does not get the old walk")
    check(not animate.cache_fits({"seed": 1007}, "h1", 7, "/x"), "another walk seed (walk_seeds) does not get the old walk")
    check(animate.cache_fits({"seed": 7 + 7919, "ref_hash": "h1"}, "h1", 7, "/x"), "the retry seed of the same call is the same walk")
    check(not animate.cache_fits({"seed": 7, "ctl_dir": "/x/front"}, "h1", 7, "/x/back"), "another control video does not get the old walk")
    # ---- ctl_soft: the body's depth softened, the thin legs kept sharp
    tmpd = tempfile.mkdtemp(prefix="le_spider92_soft_")
    try:
        import numpy as np
        from PIL import Image as _I
        vdir = os.path.join(tmpd, "drv", "front")
        os.makedirs(vdir)
        a = np.zeros((120, 120), np.uint8)
        a[40:80, 40:80] = 200          # the body: a block an opening keeps
        a[60:62, 0:40] = 255           # a leg two pixels thick: the opening drops it
        _I.fromarray(a).convert("RGB").save(os.path.join(vdir, "ctl_00.png"))
        out = animate.soften_ctl(vdir, 6, True, open_iter=3)
        b = np.asarray(_I.open(os.path.join(out, "ctl_00.png")).convert("L")).astype(int)
        check(out.endswith(os.path.join("drv_soft6b", "front")), "the softened copy sits beside the driver: %s" % out)
        check(abs(b[61, 10] - 255) <= 2 and b[40, 60] < 200, "ctl_soft blurs the body and keeps a thin leg sharp (leg %d, body edge %d)" % (b[61, 10], b[40, 60]))
    except ImportError:
        pass
    finally:
        shutil.rmtree(tmpd, ignore_errors=True)
    tmpc = tempfile.mkdtemp(prefix="le_spider92_ctl_")
    try:
        open(os.path.join(tmpc, "ctl_00.png"), "wb").write(b"a")
        s0 = animate.ctl_sig(tmpc)
        check(animate.cache_fits({"seed": 7, "ctl_dir": tmpc, "ctl_sig": s0}, "h", 7, tmpc), "the same control video on disk: the walk is reused")
        open(os.path.join(tmpc, "ctl_00.png"), "wb").write(b"abc")
        check(not animate.cache_fits({"seed": 7, "ctl_dir": tmpc, "ctl_sig": s0}, "h", 7, tmpc), "a driver rendered again under the same name walks anew")
    finally:
        shutil.rmtree(tmpc, ignore_errors=True)
    try:
        from PIL import Image
        a = Image.new("RGB", (64, 64), (10, 200, 10))
        b = a.copy()
        b.putpixel((3, 3), (200, 10, 10))
        check(animate.ref_hash(a, 64) != animate.ref_hash(b, 64) and animate.ref_hash(a, 64) == animate.ref_hash(a.copy(), 64), "ref_hash tells two paintings apart")
    except ImportError:
        pass

    # ---- methods.json
    m = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    by = {x["id"]: x for x in m["methods"]}
    dd = by["driver_depth"]
    modef = next(x for x in dd["job_fields"] if x["key"] == "mode")
    check(modef["options"] == ["cycle", "oneshot", "gait", "flip_curl"], "the form offers the made modes")
    keys = {x["key"] for x in dd["job_fields"]}
    check(all(k in keys for k in ("legs", "base", "gait", "swing", "lift", "flex", "curl", "curl_root", "roll", "roll_time", "bounce", "twitch", "hold")),
          "the form shows the made motions' settings: %s" % sorted(keys))
    check("ref_limbs" in by and by["ref_limbs"]["runner"]["tool"] == "blender_limb_clone", "the ref_limbs method")
    neg = next(x for x in by["creature_ctl"]["recipe_fields"] if x["key"] == "anim_negative")
    check("cfg 1" in neg["help"], "creature_ctl says negative words change nothing at cfg 1")
    check(any("Many legs" in w for w in by["creature_ctl"]["weaknesses"]), "creature_ctl names the many-legs lesson")
    js = open(os.path.join(HERE, "jobs.js"), encoding="utf-8").read()
    check("function limbsText" in js and "u.loose" in js, "the probe box says the leg count and a loose model's next step")

    # ---- the creature: four looks on the same drivers
    cj = os.path.join(ROOT, "game", "content", "enemies", "desert_spider", "desert_spider.json")
    check(os.path.isfile(cj), "content/enemies/desert_spider exists")
    if os.path.isfile(cj):
        d = json.load(open(cj, encoding="utf-8"))
        vs = d.get("variants") or {}
        check({"SP-A", "SP-B", "SP-C", "SP-D"} <= set(vs), "four looks SP-A..SP-D (pass 93 added SP-E, SP-F): %s" % sorted(vs))
        for code, e in sorted(vs.items()):
            r = e.get("recipe") or {}
            check(str(r.get("drivers", "")).startswith("spider_walk") and str(r.get("death_drivers", "")).startswith("spider_death"),
                  "%s walks and dies on the spider's drivers (a cartoon look on its own proportions)" % code)
            check("exactly eight legs, four on each side" in str(r.get("anatomy", "")), "%s states the leg count per side" % code)
            check(isinstance(r.get("death_keep"), list) and len(r["death_keep"]) == 8, "%s keeps 8 death frames" % code)
        check(d.get("variant") in vs, "the creature plays one of its looks: %s" % d.get("variant"))
