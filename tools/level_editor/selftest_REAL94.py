"""Pass 94, lane REAL: two realistic light purple Desert Spiders as close to the 3D model as it gets (SP-G on Klein, SP-H on
Flux.2 dev, many iterations each) and the settings behind them.

Groups: animate.py's Wan settings (wan_settings over the defaults; wan_fun_control without the speed-up LoRA, its steps split
half and half, its cfg; the cache serves only the settings it was walked with); comfy.py's img2img (`init` + `denoise`:
the start picture encoded and the schedule cut, no empty latent; the defaults unchanged); gen_ctl's repaint helpers (run in a
child Python: gen_ctl rewrites sys.argv when it is imported): clay_for crops round the figure and uncrop puts the painting
back where the crop came from, tinted_clay on the pure screen, repaint_prompt's wording; methods.json / assets_fields.js /
vocab.py carry the new keys; the creature's SP-G and SP-H recipes. Nothing here talks to the AI server.

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

NEW_KEYS = ("paint_mode", "anchor", "style", "clay_src", "clay_fill", "init", "refine", "wan")

CHILD = r'''
import json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
import numpy as np
from PIL import Image
import gen_ctl as G
out = {}
d = tempfile.mkdtemp(prefix="real94_")
os.makedirs(os.path.join(d, "side"))
im = Image.new("RGB", (640, 640), (108, 197, 80))
for x in range(200, 360):
    for y in range(300, 380):
        im.putpixel((x, y), (128, 128, 128))
im.save(os.path.join(d, "side", "clay.png"))
Image.new("RGB", (640, 640), (108, 197, 80)).save(os.path.join(d, "side", "look.png"))
r0 = {}
c0, b0 = G.clay_for(r0, d, "side")
out["plain"] = [c0.size, b0]
c1, b1 = G.clay_for({"clay_fill": 0.8}, d, "side")
out["crop"] = [c1.size, list(b1)]
a = np.asarray(c1)
out["crop_figure"] = int((np.abs(a.astype(int) - [128, 128, 128]).sum(axis=2) < 30).sum())
back = G.uncrop(c1, b1)
bb = np.asarray(back)
grey = np.abs(bb.astype(int) - [128, 128, 128]).sum(axis=2) < 40
ys, xs = np.nonzero(grey)
out["uncrop_box"] = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
cl, _ = G.clay_for({"clay_src": "look"}, d, "side")
out["look_src_empty"] = int((np.abs(np.asarray(cl).astype(int) - [128, 128, 128]).sum(axis=2) < 30).sum())
t = G.tinted_clay(c0, {"init": {"denoise": 0.85, "tint": "#C4A8E2"}}, G.g.BG_GREEN)
ta = np.asarray(t)
out["tint_corner"] = [int(v) for v in ta[5, 5]]
out["tint_figure"] = [int(v) for v in ta[340, 280]]
out["denoise"] = [G.init_denoise({}), G.init_denoise({"init": {"denoise": 0.9}}), G.init_denoise({"init": {}})]
ts = np.asarray(G.tinted_clay(c0, {"init": {"shade_blur": 12}}, G.g.BG_GREEN)).astype(int)
tp = np.asarray(G.tinted_clay(c0, {"init": {"posterize": 3}}, G.g.BG_GREEN)).astype(int)
out["shade"] = [[int(v) for v in ts[5, 5]], [int(v) for v in ts[340, 280]], len(set(tuple(v) for v in tp[312:368, 212:348].reshape(-1, 3).tolist()))]
out["modes"] = [G.repaint_mode({}), G.repaint_mode({"paint_mode": "repaint"})]
p = G.repaint_prompt({"prompt": "a lilac spider", "noun": "a spider", "anatomy": "exactly eight legs", "style": "A realistic painting",
                      "words": {"front": "seen from the front"}}, "front", "on green", True)
out["prompt"] = p
out["prompt_default_style"] = G.g.STYLE in G.repaint_prompt({"prompt": "x"}, "side", "on green", False)
pa = G.repaint_prompt({"prompt": "a lilac spider", "anchor": True}, "front", "on green", True)
out["anchor"] = [G.repaint_anchor({}), G.repaint_anchor({"anchor": True}), "third reference image shows the art style only" in pa,
                 "anime game creature illustration of a lilac spider" in pa, G.g.STYLE in pa,
                 "second reference image shows the art style only" in G.repaint_prompt({"prompt": "x", "anchor": True}, "side", "g", False)]
print("JSON" + json.dumps(out))
'''


def checks(check, run_node, server):
    import animate
    import comfy

    # ---- Wan settings
    d = animate.wan_settings(None)
    check(d == {"steps": 4, "cfg": 1.0, "lora": True, "shift": 5.0, "size": 640}, "the walks' defaults are pass 93's: %s" % d)
    w = animate.wan_settings({"lora": False, "steps": 20, "cfg": 3.5})
    check(w["lora"] is False and w["steps"] == 20 and w["cfg"] == 3.5 and w["size"] == 640, "a recipe's wan overrides: %s" % w)
    check(animate.wan_settings({"size": 830})["size"] == 816 and animate.wan_settings({"steps": 1})["steps"] == 2,
          "size to a multiple of 16, at least 2 steps")
    g0 = animate.wan_fun_control("p", "r.png", ["c0.png", "c1.png"], 1)
    n0 = g0.api()
    loras0 = [n for n in n0.values() if n["class_type"] == "LoraLoaderModelOnly"]
    ks0 = [n["inputs"] for n in n0.values() if n["class_type"] == "KSamplerAdvanced"]
    check(len(loras0) == 2 and all(k["steps"] == 4 and k["cfg"] == 1.0 for k in ks0) and ks0[0]["end_at_step"] == 2,
          "the default graph is the 4-step LoRA graph at cfg 1, split at 2")
    g1 = animate.wan_fun_control("p", "r.png", ["c0.png"], 1, steps=20, cfg=3.5, lora=False)
    n1 = g1.api()
    ks1 = [n["inputs"] for n in n1.values() if n["class_type"] == "KSamplerAdvanced"]
    check(not [n for n in n1.values() if n["class_type"] == "LoraLoaderModelOnly"], "lora false drops the speed-up LoRAs")
    check(all(k["steps"] == 20 and k["cfg"] == 3.5 for k in ks1) and ks1[0]["end_at_step"] == 10 and ks1[1]["start_at_step"] == 10,
          "20 steps split 10 + 10 at cfg 3.5: %s" % ks1)
    check(animate.wan_fits({}, animate.wan_settings(None)) and not animate.wan_fits({}, w)
          and animate.wan_fits({"wan": w}, w), "a cache serves only the Wan settings it was walked with (none = the defaults)")

    # ---- img2img in comfy.py
    k0 = comfy.klein("x", 1, refs=["a.png"]).api()
    check(any(n["class_type"] == "EmptyFlux2LatentImage" for n in k0.values())
          and not any(n["class_type"] == "SplitSigmasDenoise" for n in k0.values()), "Klein without init: from an empty latent, as before")
    k1 = comfy.klein("x", 1, refs=["a.png"], init="b.png", denoise=0.85).api()
    sp = [n for n in k1.values() if n["class_type"] == "SplitSigmasDenoise"]
    check(sp and sp[0]["inputs"]["denoise"] == 0.85 and not any(n["class_type"] == "EmptyFlux2LatentImage" for n in k1.values()),
          "Klein with init: the start picture encoded, the schedule cut at the denoise")
    samp = [n for n in k1.values() if n["class_type"] == "SamplerCustomAdvanced"][0]["inputs"]
    sid = [i for i, n in k1.items() if n["class_type"] == "SplitSigmasDenoise"][0]
    check(samp["sigmas"] == [sid, 1], "the sampler runs the low (remaining) sigmas: %s" % samp["sigmas"])
    dv = comfy.flux2_dev("x", 1, init="b.png", denoise=0.9, turbo=False, steps=40).api()
    check(any(n["class_type"] == "SplitSigmasDenoise" and n["inputs"]["denoise"] == 0.9 for n in dv.values()), "Flux.2 dev takes init too")
    check(any(n["class_type"] == "EmptyFlux2LatentImage" for n in comfy.flux2_dev("x", 1).api().values()), "dev without init unchanged")
    check(any(n["class_type"] == "EmptyFlux2LatentImage" for n in comfy.klein("x", 1, init="b.png", denoise=1.0).api().values()),
          "denoise 1 ignores the start picture")

    # ---- gen_ctl's repaint helpers (a child Python)
    r = subprocess.run([sys.executable, "-c", CHILD, TOOLS], capture_output=True, text=True, timeout=180, cwd=ROOT)
    line = [ln for ln in r.stdout.splitlines() if ln.startswith("JSON")]
    check(r.returncode == 0 and line, "gen_ctl's helpers run: %s" % (r.stderr[-600:] if not line else "ok"))
    if line:
        o = json.loads(line[-1][4:])
        check(o["plain"] == [[640, 640], None], "no clay_fill: the render as it is: %s" % o["plain"])
        x0, y0, x1, y1 = o["crop"][1]
        check(o["crop"][0] == [1024, 1024] and abs((x1 - x0) - 200) <= 2 and abs((x0 + x1) / 2 - 280) <= 2,
              "clay_fill 0.8: a square round the 160 px figure, 200 px, centred on it: %s" % o["crop"])
        check(o["crop_figure"] > 0.55 * 1024 * 1024 * 0.8 * 0.4, "the figure fills the crop: %s" % o["crop_figure"])
        ub = o["uncrop_box"]
        check(abs(ub[0] - 200) <= 3 and abs(ub[2] - 359) <= 3 and abs(ub[1] - 300) <= 3 and abs(ub[3] - 379) <= 3,
              "uncrop puts the painting back where the crop came from: %s" % ub)
        check(o["look_src_empty"] == 0, "clay_src look paints from look.png")
        check(o["tint_corner"] == [0, 255, 0], "the tinted clay lies on the pure green screen: %s" % o["tint_corner"])
        tf = o["tint_figure"]
        check(tf[2] > tf[1] and tf[0] > tf[1], "the clay's grey coloured lavender: %s" % tf)
        check(o["denoise"] == [1.0, 0.9, 0.8], "init's denoise (none = 1, default 0.8): %s" % o["denoise"])
        check(o["shade"][0] == [0, 255, 0] and o["shade"][1][2] > o["shade"][1][1], "shade_blur keeps the pure screen and the tint: %s" % o["shade"])
        check(1 <= o["shade"][2] <= 3, "posterize 3 leaves at most three colours inside a flat figure: %s" % o["shade"][2])
        check(o["modes"] == [False, True], "paint_mode repaint")
        p = o["prompt"]
        check(p.startswith("The first reference image is a rough 3D model of a spider") and "Repaint this exact model as a lilac spider" in p
              and "seen from the front" in p and "second reference image is the finished painting" in p and "A realistic painting" in p
              and "exactly eight legs" in p, "the repaint wording: %s" % p[:200])
        check(o["prompt_default_style"], "without a style line the anime one is used")
        check(o["anchor"] == [False, True, True, True, True, True],
              "anchor: the style anchor named last (third with the side painting, second on the side), the house style kept: %s" % o["anchor"])

    # ---- driver_depth's smooth (the rounded low-poly renders)
    import jobs
    check("smooth" in jobs.SPECS["driver_depth"]["fields"], "driver_depth offers smooth")
    pl = jobs._plan({"id": "jr1", "kind": "driver_depth", "target": {}, "spec": {"src": "x.glb", "name": "d3", "mode": "gait", "smooth": 2}})
    check("smooth=2" in pl["equiv"] and "tips=1" in pl["equiv"], "a smooth 2 job passes smooth=2 to Blender: %s" % pl["equiv"])
    pl0 = jobs._plan({"id": "jr2", "kind": "driver_depth", "target": {}, "spec": {"src": "x.glb", "name": "d3", "mode": "gait"}})
    check("smooth" not in pl0["equiv"], "without it nothing is passed (the old drivers unchanged)")
    dsrc = open(os.path.join(TOOLS, "blender_depth_drivers.py"), encoding="utf-8").read()
    check('A.get("smooth"' in dsrc and "SUBSURF" in dsrc and "show_viewport = False" in dsrc, "blender_depth_drivers renders the subdivision and keeps the viewport mesh raw")
    mj = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    dd = next(x for x in mj["methods"] if x["id"] == "driver_depth")
    check(any(f["key"] == "smooth" for f in dd.get("job_fields", []) + dd.get("recipe_fields", [])), "the depth driver form shows smooth")
    keys = {f["key"] for f in dd.get("job_fields", []) + dd.get("recipe_fields", [])}
    check("skin" in keys and "skin_radius" in keys, "the depth driver form shows skin and skin_radius")
    pl2 = jobs._plan({"id": "jr3", "kind": "driver_depth", "target": {}, "spec": {"src": "x.glb", "name": "d4", "mode": "gait", "smooth": 2, "skin": "capsule", "skin_radius": 0.08}})
    check("skin=capsule" in pl2["equiv"] and "skin_radius=0.08" in pl2["equiv"], "a capsule job passes skin and its radius: %s" % pl2["equiv"])
    pl3 = jobs._plan({"id": "jr4", "kind": "driver_depth", "target": {}, "spec": {"src": "x.glb", "name": "d4", "mode": "gait", "skin": "capsule"}})
    check("skin=capsule" in pl3["equiv"] and "skin_radius" not in pl3["equiv"], "the default radius is not passed")
    check("def capsule_legs(" in dsrc and "primitive_cone_add" in dsrc and "ob.parent = arm" in dsrc, "blender_depth_drivers builds the capsules along the bones, children of the armature")

    # ---- the editor's fields
    m = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    cc = next(x for x in m["methods"] if x["id"] == "creature_ctl")
    keys = {f["key"]: f for f in cc["recipe_fields"]}
    check(all(k in keys for k in NEW_KEYS), "creature_ctl's form has the pass 94 keys: %s" % [k for k in NEW_KEYS if k not in keys])
    check(keys["paint_mode"]["options"] == ["redraw", "repaint"] and keys["paint_mode"]["default"] == "redraw", "paint_mode redraw | repaint")
    check("lora" in keys["wan"]["help"] and "cfg" in keys["wan"]["help"], "the wan help names the LoRA and the cfg")
    check("act" in next(f for f in cc["recipe_fields"] if f["key"] == "anim_negative")["help"], "anim_negative says when it acts")
    js = open(os.path.join(HERE, "assets_fields.js"), encoding="utf-8").read()
    check(all("R('%s'" % k in js for k in NEW_KEYS), "the look recipe editor shows them")
    import vocab
    check(all(k in vocab.CTL_RECIPE_KEYS for k in NEW_KEYS), "vocab's ctl keys")

    # ---- the content
    sp = json.load(open(os.path.join(ROOT, "game", "content", "enemies", "desert_spider", "desert_spider.json"), encoding="utf-8"))
    v = sp["variants"]
    check(sp["variant"] == "SP-B", "the spider still plays SP-B")
    for code, model in (("SP-G", "klein"), ("SP-H", "dev")):
        e = v.get(code) or {}
        rc = e.get("recipe") or {}
        check(e.get("fresh") is True and rc.get("paint_mode") == "repaint" and (rc.get("painter") or {}).get("model") == model,
              "%s: a fresh repaint look on %s" % (code, model))
        check(isinstance(rc.get("init"), dict) and isinstance(rc.get("wan"), dict) and rc["wan"].get("lora") is False,
              "%s starts from the clay and walks on the full Wan" % code)
        check(rc.get("anchor") is True and not rc.get("style") and "cartoon face" in str(rc.get("detail")),
              "%s keeps the house style at SP-A's realism (Garry's correction)" % code)
