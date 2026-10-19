"""Pass 93, lane LEGS: the Desert Spider's legs walk properly (Garry: "most legs aren't moving, and the ones that are
moving are moving in the wrong direction") and two looks from SP-B, light purple and light blue.

Groups: the made walk's step=track maths (tools/blender_gait.py: track_offset slides a planted foot back and brings it
forward through the air; two_bone reaches a target in reach, keeps the knee up, stops short along the line to one out of
reach); tools/gait_check.py's verdicts (the old swing's front and back legs SIDEWAYS in the front view, a foot sliding
forward on the ground BACKWARDS in the side view); jobs.py's driver_depth step/stride/raise/crouch/knee (only changed keys,
tips=1 and the gait check on a made walk); methods.json's fields; the creature's SP-E and SP-F. Nothing here runs Blender.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import math
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


def _rot(p, a):
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


def checks(check, run_node, server):
    import blender_gait as G
    import gait_check as GC
    import jobs

    # ---- step=track: the foot's path over a stride
    d = G.GAIT_DEFAULTS
    check(d["step"] == "swing", "the old drivers keep step=swing by default")
    check(all(k in d for k in ("stride", "raise", "crouch", "knee")), "the track settings have defaults: %s" % sorted(d))
    a0, h0 = G.track_offset(0.0, 0.55, 0.2, 0.1)
    a1, h1 = G.track_offset(0.5, 0.55, 0.2, 0.1)
    check(abs(a0 - 0.1) < 1e-9 and h0 == 0.0 and a1 < a0 and h1 == 0.0, "on the ground the foot slides back, planted: %s -> %s" % (a0, a1))
    am, hm = G.track_offset(0.775, 0.55, 0.2, 0.1)
    check(abs(hm - 0.1) < 1e-9 and abs(am) < 1e-9, "mid-step the foot is at its highest, half way forward: %s %s" % (am, hm))
    xs = [G.track_offset(k / 24.0, 0.55, 0.2, 0.1)[0] for k in range(25)]
    check(abs(xs[0] - xs[24]) < 1e-9 and max(xs) <= 0.1 + 1e-9 and min(xs) >= -0.1 - 1e-9, "the stride loops within +-stride/2")

    # ---- two_bone: the foot reaches the target, the knee stays up
    j1, e = (0.5, 0.5), (1.2, -0.2)
    for t in [(1.0, -0.2), (1.3, -0.2), (1.2, 0.1), (0.8, 0.0)]:
        hip, knee = G.two_bone(j1, e, t)
        k = _rot(j1, hip)
        e2 = _rot(e, hip)
        v = _rot((e2[0] - k[0], e2[1] - k[1]), knee)
        foot = (k[0] + v[0], k[1] + v[1])
        check(math.hypot(foot[0] - t[0], foot[1] - t[1]) < 1e-6, "two_bone reaches %s: %s" % (t, foot))
        # the knee above the hip-to-foot line
        check(k[0] * t[1] - k[1] * t[0] < 0, "the knee stays above the line to %s" % (t,))
    hip, knee = G.two_bone(j1, e, (5.0, 0.0))
    k = _rot(j1, hip)
    e2 = _rot(e, hip)
    v = _rot((e2[0] - k[0], e2[1] - k[1]), knee)
    check(abs((k[1] + v[1])) < 1e-6 and k[0] + v[0] < 5.0, "out of reach the foot stops short on the line to the target")

    # ---- gait_check: verdicts from tips.json
    tmp = tempfile.mkdtemp(prefix="le_selftest_legs_")
    try:
        def tips(fn):
            return {"legs": ["L1 a (4 bones)", "R1 b (4 bones)"], "size": 640,
                    "views": {v: [[fn(v, li, k) + fn(v, li, k) for li in range(2)] for k in range(13)] for v in ("front", "side", "back")}}

        def good(v, li, k):
            a_, h_ = G.track_offset(k / 12.0 + 0.5 * li, 0.55, 60.0, 30.0)
            return [300.0 + (a_ if v == "side" else 0.0), 400.0 - h_ - (0.4 * a_ if v != "side" else 0.0)]

        def bad(v, li, k):
            a_, h_ = G.track_offset(k / 12.0 + 0.5 * li, 0.55, 60.0, 30.0)
            return [300.0 + (-a_ if v == "side" else 2.5 * a_), 400.0 - h_]
        for name, fn, want in (("good", good, 0), ("bad", bad, 1)):
            dd = os.path.join(tmp, name)
            os.makedirs(dd)
            json.dump(tips(fn), open(os.path.join(dd, "tips.json"), "w"))
            rc = GC.main([dd, "--strict"])
            rep = json.load(open(os.path.join(dd, "gait_check.json")))
            check(rc == want, "gait_check --strict on the %s walk returns %d: %s" % (name, want, rep))
            if name == "bad":
                check(rep["side"]["L1"]["verdict"] == "BACKWARDS" and rep["front"]["L1"]["verdict"] == "SIDEWAYS",
                      "a foot sliding forward on the ground is BACKWARDS, one sweeping across the body SIDEWAYS: %s" % rep)
                check(GC.main([dd]) == 0, "without --strict a check never fails (the editor's job)")
            else:
                check(all(r["verdict"] == "ok" for v in rep.values() for r in v.values()), "the track walk is ok everywhere: %s" % rep)
            check(os.path.isfile(os.path.join(dd, "gait_check.png")), "gait_check draws the foot paths")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- jobs.py: the track settings reach the command line only when changed; a made walk is checked
    f = jobs.SPECS["driver_depth"]["fields"]
    check(all(k in f for k in ("step", "stride", "raise", "crouch", "knee")), "driver_depth offers step and the track settings")
    check(f["step"]["default"] == "swing" and tuple(f["step"].get("options") or f["step"].get("choices") or ()) in ((), ("swing", "track")),
          "step defaults to swing (the old drivers)")
    args = jobs.made_motion_args({"mode": "gait", "step": "track", "stride": 0.22, "raise": "0.15", "crouch": 0.15, "knee": "up", "legs": "leg_"})
    check(args == ["legs=leg_", "step=track", "raise=0.15", "crouch=0.15"], "only the changed track keys: %s" % args)
    p = jobs._plan({"id": "jl1", "kind": "driver_depth", "target": {}, "spec": {"src": "tools/dl/uploads/3d/spider_8legs/spider_8legs.glb",
                    "name": "spider_walk_t", "mode": "gait", "step": "track", "raise": 0.15, "crouch": 0.15, "sway": 0, "bob": 0.03,
                    "legs": "leg_", "forward": "+Y"}})
    check("step=track" in p["equiv"] and "tips=1" in p["equiv"] and "gait_check.py" in p["equiv"], "a track walk's job writes tips and checks the walk: %s" % p["equiv"])
    check(len(p["steps"]) == 2 and p["steps"][1][1].endswith("gait_check.py"), "the check is the job's second step")
    p = jobs._plan({"id": "jl2", "kind": "driver_depth", "target": {}, "spec": {"src": "x.glb", "name": "d", "mode": "cycle", "action": "walk"}})
    check("tips=1" not in p["equiv"] and len(p["steps"]) == 1, "a clip's walk is unchanged: %s" % p["equiv"])

    # ---- methods.json
    m = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    dd = next(x for x in m["methods"] if x["id"] == "driver_depth")
    keys = {x["key"]: x for x in dd["job_fields"]}
    check(all(k in keys for k in ("step", "stride", "raise", "crouch", "knee")), "the form shows the track settings")
    check(keys["step"]["options"] == ["swing", "track"] and keys["step"]["default"] == "swing", "the form's step: swing | track")
    check(any("step track" in w for w in dd["weaknesses"]), "driver_depth names the sideways-legs lesson")

    cc = next(x for x in m["methods"] if x["id"] == "creature_ctl")
    rk = {x["key"]: x for x in cc["recipe_fields"]}
    check("fit_ref" in rk and rk["fit_ref"]["type"] == "json", "creature_ctl offers fit_ref")
    check(rk.get("no_green", {}).get("type") == "json" and "rb" in rk["no_green"]["help"], "no_green takes true / \"rb\" / false")
    af = open(os.path.join(HERE, "assets_fields.js"), encoding="utf-8").read()
    check("R('no_green', 'No green', 'json'" in af and "R('fit_ref'" in af, "the typed recipe keeps no_green \"rb\" (a bool row would save it as true)")
    gsrc = open(os.path.join(TOOLS, "gen_ctl.py"), encoding="utf-8").read()
    check("def fit_to_ctl(" in gsrc and 'mode == "rb"' in gsrc, "gen_ctl has fit_to_ctl and no_green rb")

    # ---- the creature: SP-E (light purple) and SP-F (light blue) from SP-B, on the fixed walk
    cj = os.path.join(ROOT, "game", "content", "enemies", "desert_spider", "desert_spider.json")
    d = json.load(open(cj, encoding="utf-8"))
    vs = d.get("variants") or {}
    for code, colour in (("SP-E", "lavender"), ("SP-F", "sky-blue")):
        check(code in vs, "%s exists" % code)
        if code not in vs:
            continue
        r = vs[code]["recipe"]
        b = vs["SP-B"]["recipe"]
        check(r["drivers"] == "spider_walk_v2" and r["death_drivers"] == "spider_death", "%s walks on spider_walk_v2, dies on spider_death" % code)
        check(colour in r["prompt"] and "rust-orange" not in r["prompt"] and "grumpy frown" in r["prompt"], "%s is SP-B's design in its colour" % code)
        check(r["anatomy"] == b["anatomy"] and r["words"] == b["words"], "%s keeps SP-B's anatomy and view words" % code)
        check(bool(vs[code].get("fresh")), "%s is fresh for Garry to approve" % code)
        meta = os.path.join(TOOLS, "dl", "drivers", "spider_walk_v2", "meta.json")
        if os.path.isfile(meta):
            g = json.load(open(meta, encoding="utf-8")).get("gait") or {}
            check(g.get("step") == "track", "spider_walk_v2 is a track walk: %s" % g)
