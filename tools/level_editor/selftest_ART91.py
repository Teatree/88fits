"""Pass 91, lane ARTJOB: the Cactus Walker's fixes (Garry: a black line at the bottom of his front, a "pile of pieces"
death that came out as a whole cactus, and a method that takes a front and a back picture).

Groups: the method "creature_pictures" in methods.json (its recipe fields: the two pictures, picture_use, every field
of creature_proc but its pose and screen, the screen with auto; the shatter death offered and described) and in
jobs.py (a look method, its argv is gen_art's on the look, no clips, no dead stage for a shatter); the keyer's guard
(artkit.figure_wears_screen: a green figure on the green screen keeps its lower body, a brown one still loses the
cast shadow under it); artkit.shatter (the frames, a pile resting on the ground, lower than the figure stood);
gen_art's picture still and auto screen (a green picture goes on blue, the still cached as a painting).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
if HERE not in sys.path:
    sys.path.insert(0, HERE)


def _figure(colour, size=400, screen=(0, 255, 0), ink=(20, 20, 20)):
    """A round figure on a screen: a disc in `colour` with an ink rim and ink ribs (the cactus's drawing)."""
    from PIL import Image, ImageDraw
    im = Image.new("RGB", (size, size), screen)
    dr = ImageDraw.Draw(im)
    dr.ellipse((90, 90, 310, 330), fill=colour, outline=ink, width=6)
    for x in (150, 200, 250):
        dr.line((x, 100, x, 320), fill=ink, width=4)
    return im


def checks(check, run_node, server):
    import numpy as np
    m = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    meths = {x["id"]: x for x in m["methods"]}
    cp = meths.get("creature_pictures")
    check(cp is not None, "ART91: methods.json has creature_pictures")
    if cp:
        keys = [f["key"] for f in cp["recipe_fields"]]
        check(keys[:3] == ["front_ref", "back_ref", "picture_use"], "ART91: the two pictures first, then picture_use: %s" % keys[:3])
        check([f["type"] for f in cp["recipe_fields"][:2]] == ["file", "file"], "ART91: the pictures are file pickers (Upload...)")
        proc_keys = [f["key"] for f in meths["creature_proc"]["recipe_fields"] if f["key"] not in ("pose",)]
        check(all(k in keys for k in proc_keys), "ART91: every creature_proc input is on creature_pictures: %s" % [k for k in proc_keys if k not in keys])
        scr = next(f for f in cp["recipe_fields"] if f["key"] == "screen")
        check(scr["default"] == "auto" and "auto" in scr["options"], "ART91: the screen defaults to auto")
        dth = next(f for f in cp["recipe_fields"] if f["key"] == "death")
        check(dth["default"] == "shatter" and "shatter" in dth["options"], "ART91: death defaults to shatter")
        check(cp["runner"]["tool"] == "gen_art" and cp["refs"]["2d"] is True, "ART91: runs gen_art, takes 2D pictures")
    check("shatter" in next(f for f in meths["creature_proc"]["recipe_fields"] if f["key"] == "death")["options"], "ART91: creature_proc offers shatter")
    check(any(d["value"] == "shatter" for d in m["deaths"]), "ART91: the deaths list describes shatter")
    dh = next(f for f in meths["creature_proc"]["recipe_fields"] if f["key"] == "dead_hint")
    check("edit of the front" in dh["help"], "ART91: dead_hint says the dead still is an edit of the front")

    import jobs
    check("creature_pictures" in jobs.LOOK_METHODS and "creature_pictures" in jobs.CREATURE_STILL_METHODS, "ART91: jobs.py knows the method")
    T = {"kind": "enemy", "id": "testbeast", "code": "TB-P"}
    spec = {"recipe": {"walk": "hop", "death": "shatter", "stills": "p", "front_ref": "x.png"}}
    st = [s["name"] for s in jobs.expected_stages("creature_pictures", spec, T)]
    check(st == ["front", "back", "pack"], "ART91: stages of a shatter (no dead still): %s" % st)
    st = [s["name"] for s in jobs.expected_stages("creature_pictures", {"recipe": {"walk": "hop", "death": "squash"}}, T)]
    check(st == ["front", "back", "dead", "pack"], "ART91: stages of a squash: %s" % st)
    ck = jobs.cache_keys("creature_pictures", spec, T)
    check(ck["clips"] == [] and ck["stills"][0] == "testbeast_p_front", "ART91: no clips, the slug's stills: %s" % ck)

    import artkit
    from PIL import Image
    green = artkit.key_background(_figure((110, 160, 60)))
    a = np.asarray(green)[..., 3]
    ys = np.nonzero(a.max(axis=1) > 127)[0]
    # the disc's lowest point is y 330 (+ the rim): the bottom of its body must survive the key
    check(len(ys) and ys.max() >= 325, "ART91: a green figure on green keeps its lower body (bottom %s)" % (ys.max() if len(ys) else None))
    row = a[315, 150:250]
    check((row > 127).mean() > 0.9, "ART91: no hole across the green figure's bottom (row 315 %.2f opaque; 0.21 before the guard)" % float((row > 127).mean()))
    # a brown figure with a green cast shadow under it: the shadow cut still runs
    im = _figure((140, 90, 50))
    from PIL import ImageDraw
    ImageDraw.Draw(im).ellipse((120, 318, 280, 345), fill=(40, 140, 30))
    brown = np.asarray(artkit.key_background(im))[..., 3]
    check(brown[340, 200] < 128, "ART91: a brown figure's green cast shadow is still cut")

    cell = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    ImageDraw.Draw(cell).ellipse((30, 30, 98, 118), fill=(100, 160, 60, 255))
    fr = artkit.shatter(cell, 6, 3)
    check(len(fr) == 6 and all(f.size == (128, 128) for f in fr), "ART91: shatter gives 6 cells")
    last = np.asarray(fr[-1])[..., 3] > 60
    ly = np.nonzero(last.any(axis=1))[0]
    check(len(ly) and ly.max() >= 112 and ly.min() > 45, "ART91: the pile rests on the ground and lies lower than the figure stood (%s..%s)" % (ly.min() if len(ly) else None, ly.max() if len(ly) else None))
    check(last.sum() > 0.3 * (np.asarray(cell)[..., 3] > 60).sum(), "ART91: the pile keeps the pieces")

    import gen_art as g
    tmp = tempfile.mkdtemp(prefix="art91_")
    pic = os.path.join(tmp, "cactus.png")
    rgba = Image.new("RGBA", (300, 300), (0, 0, 0, 0))
    ImageDraw.Draw(rgba).ellipse((40, 40, 260, 280), fill=(90, 150, 60, 255), outline=(10, 10, 10, 255), width=5)
    rgba.save(pic)
    check(g.auto_screen(pic) == g.BG_BLUE, "ART91: a green picture goes on the blue screen")
    red = os.path.join(tmp, "red.png")
    r2 = Image.new("RGBA", (300, 300), (0, 0, 0, 0))
    ImageDraw.Draw(r2).ellipse((40, 40, 260, 280), fill=(170, 60, 50, 255))
    r2.save(red)
    check(g.auto_screen(red) == g.BG_GREEN, "ART91: a red picture stays on green")
    raw0 = g.RAW
    try:
        g.RAW = tmp
        info = {"renders": {}}
        img = g.picture_still({"picture_use": "as_is"}, "art91_front", pic, "front", "a cactus", g.BG_BLUE, [], 1, info)
        check(img is not None and img.size == (1024, 1024) and img.getpixel((5, 5)) == (0, 0, 255), "ART91: the picture laid on blue, 1024 square")
        check(os.path.isfile(os.path.join(tmp, "art91_front.png")) and info["renders"]["front"].get("as_is"), "ART91: the still cached as a painting")
        keyed = np.asarray(g.artkit.key_background(img))[..., 3]
        check(keyed[512, 512] > 200 and keyed[5, 5] == 0, "ART91: the picture keys clean off the blue screen")
    finally:
        g.RAW = raw0
