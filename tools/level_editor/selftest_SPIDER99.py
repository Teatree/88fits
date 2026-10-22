"""Pass 99, lane SPIDER: the Desert Spider's SP-G / SP-H finished, round 2: a walk driver without the model's dorsal fins
(blender_depth_drivers drop_islands / drop_groups, spider_walk_v5) and gen_ctl's per-view keys (view_words, clay_drivers,
view_drivers). Checks the driver form and its Blender arguments, the creature_ctl recipe fields in methods.json /
assets_fields.js / vocab.py, gen_ctl's clay_for honouring clay_drivers and repaint_prompt honouring view_words (in a
child Python: gen_ctl rewrites sys.argv when it is imported), and both looks' recipes. Nothing here talks to the AI server.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

CHILD = r'''
import json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
from PIL import Image
import gen_ctl as G
out = {}
base = tempfile.mkdtemp(prefix="spider99_")
real = os.path.join(base, "tools", "dl", "drivers")
# two drivers whose side clay has the figure in different places: clay_drivers picks the one named
for name, x0 in (("drvA", 200), ("drvB", 300)):
    os.makedirs(os.path.join(real, name, "side"))
    im = Image.new("RGB", (640, 640), (108, 197, 80))
    for x in range(x0, x0 + 100):
        for y in range(300, 360):
            im.putpixel((x, y), (120, 120, 120))
    im.save(os.path.join(real, name, "side", "clay.png"))
G.REPO = base
r = {"clay_fill": 0.8}
out["plain"] = G.clay_for(r, os.path.join(real, "drvA"), "side")[1]
out["named"] = G.clay_for(dict(r, clay_drivers="drvB"), os.path.join(real, "drvA"), "side")[1]
out["perview"] = G.clay_for(dict(r, clay_drivers={"side": "drvB"}), os.path.join(real, "drvA"), "side")[1]
out["otherview"] = G.clay_for(dict(r, clay_drivers={"fd": "drvB"}), os.path.join(real, "drvA"), "side")[1]
rec = {"prompt": "a purple spider", "words": {"fd": "three-quarter"}, "view_words": {"fd": "strong violet contrast"}}
out["p_fd"] = G.repaint_prompt(rec, "fd", "green", True)
out["p_bd"] = G.repaint_prompt(rec, "bd", "green", True)
out["p_none"] = G.repaint_prompt({"prompt": "a purple spider", "words": {"fd": "three-quarter"}}, "fd", "green", True)
print("JSON" + json.dumps(out))
'''


def checks(check, run_node, server):
    import jobs
    # ---- driver_depth: drop_islands
    f = jobs.SPECS["driver_depth"]["fields"]
    check("drop_islands" in f and "drop_groups" in f, "driver_depth offers drop_islands and drop_groups")
    pl = jobs._plan({"id": "s99a", "kind": "driver_depth", "target": {}, "spec": {"src": "x.glb", "name": "w5", "mode": "gait", "smooth": 2, "skin": "capsule", "drop_islands": 4}})
    check("drop_islands=4" in pl["equiv"] and "drop_groups" not in pl["equiv"], "a drop job passes drop_islands=4 (the default groups not passed): %s" % pl["equiv"])
    pl2 = jobs._plan({"id": "s99b", "kind": "driver_depth", "target": {}, "spec": {"src": "x.glb", "name": "w5", "mode": "gait", "drop_islands": 3, "drop_groups": "body"}})
    check("drop_islands=3" in pl2["equiv"] and "drop_groups=body" in pl2["equiv"], "and its groups when set: %s" % pl2["equiv"])
    pl0 = jobs._plan({"id": "s99c", "kind": "driver_depth", "target": {}, "spec": {"src": "x.glb", "name": "w4", "mode": "gait", "smooth": 2}})
    check("drop_islands" not in pl0["equiv"], "without it nothing is passed (the old drivers unchanged)")
    dsrc = open(os.path.join(TOOLS, "blender_depth_drivers.py"), encoding="utf-8").read()
    check("def drop_islands(" in dsrc and 'A.get("drop_islands"' in dsrc and "bmesh.ops.delete" in dsrc, "blender_depth_drivers drops the small loose islands")
    check('"drop_islands": int(A.get("drop_islands"' in dsrc, "the driver's meta.json records drop_islands")
    m = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    dd = next(x for x in m["methods"] if x["id"] == "driver_depth")
    keys = {x["key"] for x in dd.get("job_fields", []) + dd.get("recipe_fields", [])}
    check("drop_islands" in keys and "drop_groups" in keys, "the depth driver form shows drop_islands and drop_groups")
    # ---- creature_ctl's per-view keys
    cc = next(x for x in m["methods"] if x["id"] == "creature_ctl")
    ck = {x["key"] for x in cc["recipe_fields"]}
    for k in ("view_words", "clay_drivers", "view_drivers"):
        check(k in ck, "creature_ctl's recipe fields carry %s" % k)
    js = open(os.path.join(HERE, "assets_fields.js"), encoding="utf-8").read()
    check(all("R('%s'" % k in js for k in ("view_words", "clay_drivers", "view_drivers")), "the typed recipe editor shows the three keys")
    import vocab
    check(all(k in vocab.CTL_RECIPE_KEYS for k in ("view_words", "clay_drivers", "view_drivers")), "vocab lists them as creature_ctl recipe keys")
    gsrc = open(os.path.join(TOOLS, "gen_ctl.py"), encoding="utf-8").read()
    check('recipe.get("view_drivers")' in gsrc and "os.path.join(vdrv, view)" in gsrc, "gen_ctl walks a view on its view_drivers entry")
    # ---- gen_ctl helpers in a child Python
    p = subprocess.run([sys.executable, "-c", CHILD, TOOLS], capture_output=True, text=True, timeout=120)
    line = [x for x in p.stdout.splitlines() if x.startswith("JSON")]
    check(bool(line), "the gen_ctl child ran: %s" % (p.stderr[-400:] if not line else "ok"))
    if line:
        o = json.loads(line[-1][4:])
        check(o["plain"] != o["named"] and o["named"] == o["perview"], "clay_drivers (a name or {view: name}) crops the named driver's clay: %s %s" % (o["plain"], o["named"]))
        check(o["otherview"] == o["plain"], "a view clay_drivers does not name keeps the drivers' clay")
        check("strong violet contrast" in o["p_fd"] and "strong violet contrast" not in o["p_bd"], "view_words reach that view's painting only")
        check(o["p_none"] == o["p_fd"].replace(", strong violet contrast", ""), "without view_words the wording is unchanged")
    # ---- the looks
    sp = json.load(open(os.path.join(ROOT, "game", "content", "enemies", "desert_spider", "desert_spider.json"), encoding="utf-8"))
    for code in ("SP-G", "SP-H"):
        r = sp["variants"][code]["recipe"]
        check(str(r["drivers"]).startswith("spider_walk_v"), "%s walks on a spider_walk driver: %s" % (code, r["drivers"]))
        check(bool(sp["variants"][code].get("sprite")), "%s has its strip" % code)
