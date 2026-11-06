"""Pass 131 (lane RECUI): "Recolour an existing look" made clear, and able to make grey and white.

- methods.json: every recolour field carries a plain label, a help, an example and its sensible values (the form-only
  controls and the mode list apart), the mode offers hue / tint / lift with one line each, the fields of a mode show only
  in that mode, the presets name looks and hold valid settings, the method has a guide.
- recolour_io: the flags of each mode, the recorded line read back, plain-words refusals, the job's command lines for one
  pass and for extra passes, RUN for real on a small strip in a temp folder (hue, tint, lift, a second pass on one
  frame), the preview in memory equal to what the tool writes.
- jobs.py: the spec check, the recipe's `recolour_of` + `recolour_passes` (the shape the shell-made looks have), the
  plan's steps on a temp creature, the source look's files (a base look's unlettered strip).
- the page: recolour_ui.js parses, is loaded before jobs.js, and its pure helpers behave (Node).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)

NODE_SCRIPT = r"""
const F = require(process.argv[1]);
const fields = JSON.parse(process.argv[2]);
const out = {};
const get = (rc) => (k) => rc[k.replace('recolour.', '')];
const keysFor = (rc) => fields.filter((f) => F.shown(f, get(rc), fields)).map((f) => f.key.replace('recolour.', ''));
out.hue = keysFor({});
out.tint = keysFor({ mode: 'tint' });
out.lift = keysFor({ mode: 'lift' });
out.drives = fields.filter((f) => F.drives(f, fields)).map((f) => f.key);
out.ranges = [F.parseRanges('340-360, 0-20'), F.parseRanges('340-20'), F.parseRanges([[55, 135]]), F.parseRanges('5-'), F.parseRanges('0-400'), F.parseRanges('')];
out.text = F.rangesText([[340, 360], [0, 20]]);
out.names = [0, 30, 65, 120, 222, 280, 357].map((h) => F.hueName(h));
out.starts = F.animStarts({ idle: 4, run: 12, attack: 2, hit: 1, die: 8 });
out.preset = F.applyPreset({ from: 'CC-B', to: 1, passes: [{ to: 2 }] }, { values: { mode: 'lift', to: 40 } });
out.pass = F.passFrom({ from: 'CC-B', mode: 'lift', to: 40, passes: [{}], keep_edge: 4, ranges: [[0, 360]] }, { cells: [18] });
console.log(JSON.stringify(out));
"""


def _strip(path, n=6, cell=16):
    """A small strip: every frame a green body (hue 120) with a black outline, a white eye and a red (hue 0) club;
    frame 3 is a washed-out flash of the body (pale green, low saturation)."""
    from PIL import Image
    im = Image.new("RGBA", (n * cell, cell), (0, 0, 0, 0))
    px = im.load()
    for f in range(n):
        body = (190, 235, 190, 255) if f == 3 else (40, 200, 40, 255)
        for y in range(2, cell - 2):
            for x in range(2, cell - 2):
                edge = x in (2, cell - 3) or y in (2, cell - 3)
                px[f * cell + x, y] = (8, 8, 8, 255) if edge else body
        px[f * cell + 5, 5] = (255, 255, 255, 255)
        px[f * cell + 9, 9] = (220, 20, 20, 255)
    im.save(path)
    return im


def _px(path, x, y):
    from PIL import Image
    return Image.open(path).convert("RGBA").getpixel((x, y))


def _method():
    with open(os.path.join(HERE, "methods.json"), encoding="utf-8") as f:
        d = json.load(f)
    return [m for m in d["methods"] if m["id"] == "recolour"][0], d


def _fields_checks(check, RC):
    m, d = _method()
    fields = m["recipe_fields"]
    by = {}
    for f in fields:
        by.setdefault(f["key"], []).append(f)
    for f in fields:
        k = f["key"]
        check(isinstance(f.get("label"), str) and f["label"] and "recolour." not in f["label"] and isinstance(f.get("help"), str) and len(f["help"]) > 20,
              "RECUI: %s has a plain label and a sentence of help" % k)
        if not f.get("form_only") and k != "recolour.mode":
            check(isinstance(f.get("example"), str) and f["example"] and isinstance(f.get("guide"), str) and f["guide"], "RECUI: %s has an example and its sensible values" % k)
    mode = by["recolour.mode"][0]
    check(mode["options"] == ["hue", "tint", "lift"] and set(mode.get("options_guide", {})) == {"hue", "tint", "lift"} and mode["default"] == "hue",
          "RECUI: the mode offers hue, tint and lift, each with a line saying when to pick it")
    frm = by["recolour.from"][0]
    check(frm.get("widget") == "look_code" and "CC-B" in frm["example"] and "code alone" in frm["help"], "RECUI: `from` is a pick list of looks and says the code alone, with an example")
    rg = by["recolour.ranges"][0]
    check(rg.get("widget") == "hue_ranges" and "340-360, 0-20" in rg["guide"] and "red 0" in rg["guide"] and "blue 240" in rg["guide"], "RECUI: ranges has the hue strip, the colour names and the wrap through red")
    check(by["recolour.passes"][0].get("widget") == "passes" and by["recolour._preview"][0].get("form_only") and by["recolour._preset"][0].get("form_only"),
          "RECUI: extra passes, the preview and the presets are in the form")
    # every flag the tool reads in a mode is a field that shows in that mode (mass_sat is the one left to the raw JSON)
    for md in RC.MODES:
        keys = set()
        for f in fields:
            c = f.get("show_if")
            if not c or md in c["in"]:
                keys.add(f["key"].replace("recolour.", ""))
        missing = [k for k in RC.MODE_KEYS[md] if k not in keys and k != "mass_sat"]
        check(not missing, "RECUI: mode %s: every flag it reads has a box (%s)" % (md, missing or "all"))
    check("keep_edge" in {f["key"].replace("recolour.", "") for f in fields if (f.get("show_if") or {}).get("in") == ["lift"]}, "RECUI: keep_edge (the icon's rim) is a lift box")
    for k, fs in by.items():
        if len(fs) > 1:
            modes = [x for f in fs for x in (f.get("show_if") or {}).get("in", ["*"])]
            check(len(modes) == len(set(modes)) and "*" not in modes, "RECUI: %s has one field per mode, never two in one mode (%s)" % (k, modes))
    # the tool's own defaults are the ones the form names
    for k, md, want in (("min_sat", "hue", 0.2), ("sat", "hue", 1.0), ("set_sat", "tint", 0.55), ("value", "tint", 0.6), ("min_val", "tint", 0.3),
                        ("v_lo", "lift", 0.5), ("v_hi", "lift", 1.0), ("gamma", "lift", 1.0), ("min_val", "lift", 0.0), ("soft", "lift", 0.04), ("src_hi", "lift", 1.0)):
        f = [x for x in by["recolour." + k] if not x.get("show_if") or md in x["show_if"]["in"]][0]
        check(f.get("default") == want, "RECUI: %s in mode %s names the tool's default %s (%r)" % (k, md, want, f.get("default")))
    presets = by["recolour._preset"][0]["presets"]
    names = " | ".join(p["name"] for p in presets)
    check(all(w in names for w in ("(hue)", "(tint)", "white", "grey", "gold", "green")) and len(presets) >= 6, "RECUI: the presets: hue, tint, white, grey, gold, green (%s)" % names)
    for p in presets:
        try:
            c = RC.clean(dict(p["values"], **{"from": "X-A"}))
            ok = c.get("mode") in RC.MODES and c.get("ranges") and "to" in c and any(ch.isupper() for ch in p["line"]) and "-" in p["line"]
        except ValueError as e:
            ok = False
            print("   ", e)
        check(ok, "RECUI: preset %r holds valid settings and names the look it comes from" % p["name"])
    g = m.get("guide") or {}
    faults = " ".join("%s %s" % (x.get("see"), x.get("do")) for x in g.get("faults", []))
    check(len(g.get("steps", [])) >= 3 and g.get("sheet") and all(w in faults for w in ("outline", "eyes", "flash", "flat")) and all(x.get("example") for x in g["faults"]),
          "RECUI: the method's guide: three steps, the preview sheet, the usual faults each with its box and an example")
    # no other method's fields carry the new keys by accident, and none lost its fields
    others = [x for x in d["methods"] if x["id"] != "recolour"]
    check(len(others) >= 20 and all(isinstance(x.get("recipe_fields"), list) for x in others), "RECUI: every other method keeps its fields (%d methods)" % len(others))
    # tools/vace_bench.write_profiles rewrites each method's `"repair": {...}` in place and needs it on one line
    with open(os.path.join(HERE, "methods.json"), encoding="utf-8") as f:
        rl = [ln.strip() for ln in f.read().splitlines() if ln.strip().startswith('"repair":')]
    ok = len(rl) == len(d["methods"])
    for ln in rl:
        try:
            json.loads(ln[len('"repair":'):].strip().rstrip(","))
        except ValueError:
            ok = False
    check(ok, "RECUI: every method's repair rule is still one line of JSON (vace_bench rewrites it in place): %d lines" % len(rl))
    return fields


def _io_checks(check, RC):
    hue = {"from": "GOB-D", "ranges": [[55, 135]], "to": 357, "sat": 1.0, "value": 0.6, "v_lo": 0.3}
    check(RC.pass_args(RC.passes_of(RC.clean(hue))[0]) == ["--ranges", "55-135", "--to", "357", "--sat", "1"],
          "RECUI: hue (no mode named): only the flags hue reads, numbers without a trailing .0")
    tint = RC.clean({"from": "SK-A", "mode": "tint", "ranges": "10-75", "to": 222, "set_sat": 0.55, "value": 0.6, "min_val": 0.3, "gamma": 2, "sat": 3})
    check(RC.pass_args(RC.passes_of(tint)[0]) == ["--mode", "tint", "--ranges", "10-75", "--to", "222", "--set-sat", "0.55", "--value", "0.6", "--min-val", "0.3"],
          "RECUI: tint: its own flags, ranges typed as words, another mode's boxes left out")
    lift = RC.clean({"from": "RG-A", "mode": "lift", "ranges": [[340, 360], [0, 12]], "to": 26, "to_dark": 10, "set_sat": 0.3, "v_lo": 0.68, "v_hi": 1.0, "gamma": 0.85,
                     "min_sat": 0.3, "min_val": 0.16, "src_hi": 0.9, "soft": 0.05, "value": 9})
    line = RC.record(lift)["recolour_passes"][0]
    check(line == "--mode lift --ranges 340-360,0-12 --to 26 --to-dark 10 --set-sat 0.3 --v-lo 0.68 --v-hi 1 --gamma 0.85 --min-sat 0.3 --min-val 0.16 --src-hi 0.9 --soft 0.05",
          "RECUI: lift: the recorded line reads like the shell-made looks' (%s)" % line)
    check(RC.parse_pass(line) == {k: v for k, v in lift.items() if k not in ("from", "value")}, "RECUI: a recorded line reads back as the same boxes")
    shell = "--mode lift --ranges 350-360,0-26 --hue-soft 3 --mass 3 --grow 4 --mass-sat 0.46 --to 38 --set-sat 0.10 --v-lo 0.50 --v-hi 1.0 --gamma 0.9 --min-sat 0.62 --min-val 0.28 --src-hi 0.95 --soft 0.06"
    back = RC.parse_pass(shell)
    check(back["mass"] == 3 and back["grow"] == 4 and back["mass_sat"] == 0.46 and back["ranges"] == [[350, 360], [0, 26]]
          and sorted(RC.pass_args(back)) == sorted(shell.replace("0.10", "0.1").replace("0.50", "0.5").replace("1.0", "1").split()),
          "RECUI: a shell-made look's line (the white beetle BB-E) reads back and writes out with the same flags")
    two = RC.clean({"from": "CC-B", "mode": "lift", "ranges": [[0, 360]], "to": 40, "keep_edge": 4, "cells": [3],
                    "passes": [{"mode": "lift", "ranges": "0-360", "to": 40, "min_sat": 0.05, "cells": "18, 61", "keep_edge": 9}, {}]})
    rec = RC.record(two)
    check("cells" not in two and len(two["passes"]) == 1 and two["passes"][0]["cells"] == [18, 61] and "keep_edge" not in two["passes"][0]
          and rec == {"recolour_of": "CC-B", "recolour_passes": ["--mode lift --ranges 0-360 --to 40", "--mode lift --ranges 0-360 --to 40 --min-sat 0.05 --cells 18,61"],
                      "recolour_icon_extra": "--keep-edge 4"},
          "RECUI: extra passes: recolour_of + recolour_passes in order, the frames on the pass that names them, the icon's rim apart: %s" % rec)
    for bad, word in (({"ranges": [[340, 20]]}, "340-360 and 0-20"), ({"mode": "bleach"}, "hue, tint, lift"), ({"to": 400}, "0 to 360"), ({"sat": "lots"}, "a number"),
                      ({"passes": [{"cells": "hit"}]}, "frame numbers"), ({"passes": {"to": 1}}, "a list")):
        try:
            RC.clean(dict({"from": "A-A"}, **bad))
            msg = ""
        except ValueError as e:
            msg = str(e)
        check(word in msg, "RECUI: %s is refused in plain words (%s)" % (bad, msg))
    try:
        RC.clean({"to": 3})
        msg = ""
    except ValueError as e:
        msg = str(e)
    check("recolour.from" in msg, "RECUI: no source look is refused (%s)" % msg)


def _run_checks(check, RC, tmp):
    """The command lines run for real on a small strip: each mode does what its line says, a second pass reaches the
    flash frame, the preview in memory equals the files."""
    from PIL import Image
    folder = os.path.join(tmp, "beast")
    os.makedirs(folder)
    src = {"sprite": os.path.join(folder, "beast_sprite_a.png"), "icon": os.path.join(folder, "beast_icon_a.png")}
    _strip(src["sprite"])
    _strip(src["icon"], n=1)
    before = open(src["sprite"], "rb").read()

    def run(rc, letter):
        dst = {k: os.path.join(folder, "beast_%s_%s.png" % (k, letter)) for k in src}
        prev = os.path.join(tmp, "review", "beast_%s_recolour.png" % letter)
        os.makedirs(os.path.dirname(prev), exist_ok=True)
        st = RC.steps(RC.clean(rc), sys.executable, src, dst, preview=prev)
        for a in st:
            r = subprocess.run(a, capture_output=True, text=True, timeout=120)
            if r.returncode != 0:
                print(r.stdout[-400:], r.stderr[-800:])
                return st, dst, prev, False
        return st, dst, prev, True

    # hue: green body to red; the outline, the white eye and the red club stay
    st, dst, prev, ok = run({"from": "B-A", "ranges": [[90, 150]], "to": 0, "sat": 1.0}, "h")
    body, line_, eye, club = _px(dst["sprite"], 7, 7), _px(dst["sprite"], 2, 2), _px(dst["sprite"], 5, 5), _px(dst["sprite"], 9, 9)
    check(ok and len(st) == 2 and body[0] > 150 and body[1] < 80 and line_[:3] == (8, 8, 8) and eye[:3] == (255, 255, 255) and club[:3] == (220, 20, 20) and os.path.isfile(prev)
          and _px(dst["icon"], 7, 7)[0] > 150, "RECUI: hue runs: the green body is red, the outline, eye and club untouched, the icon too, a preview written (%s)" % (body,))
    # tint: the pale flash frame's body (low saturation) made dark blue; the vivid body left by max_sat
    st, dst, prev, ok = run({"from": "B-A", "mode": "tint", "ranges": [[90, 150]], "to": 222, "set_sat": 0.55, "value": 0.6, "min_val": 0.3, "min_sat": 0.05, "max_sat": 0.5}, "t")
    pale, vivid = _px(dst["sprite"], 3 * 16 + 7, 7), _px(dst["sprite"], 7, 7)
    check(ok and pale[2] > pale[0] and pale[2] > pale[1] and max(pale[:3]) < 180 and vivid[:3] == (40, 200, 40),
          "RECUI: tint runs: the pale material is a dark blue, the vivid body outside its limits stays (%s)" % (pale,))
    # lift: the green body to white; one pass with a strict min_sat misses the washed-out flash frame, a second pass on that frame takes it
    one = {"from": "B-A", "mode": "lift", "ranges": [[90, 150]], "to": 40, "set_sat": 0.04, "v_lo": 0.8, "v_hi": 1.0, "min_sat": 0.5, "min_val": 0.2, "keep_edge": 1}
    st, dst, prev, ok = run(one, "w")
    white, flash = _px(dst["sprite"], 7, 7), _px(dst["sprite"], 3 * 16 + 7, 7)
    check(ok and min(white[:3]) > 190 and max(white[:3]) - min(white[:3]) < 20 and flash[:3] == (190, 235, 190) and _px(dst["sprite"], 2, 2)[:3] == (8, 8, 8),
          "RECUI: lift runs: the body is white, the outline kept; the pale flash frame is missed by one strict pass (%s, %s)" % (white, flash))
    check(st[1][-2:] == ["--keep-edge", "1"] and "--keep-edge" not in st[0], "RECUI: keep_edge rides on the icon's command alone")
    two = dict(one, passes=[dict({k: v for k, v in one.items() if k not in ("from", "keep_edge")}, min_sat=0.05, cells=[3])])
    st, dst, prev, ok = run(two, "x")
    flash2, other = _px(dst["sprite"], 3 * 16 + 7, 7), _px(dst["sprite"], 16 + 7, 7)
    check(ok and len(st) == 4 and st[1][st[1].index("--src") + 1] == dst["sprite"] and st[0][st[0].index("--src") + 1] == src["sprite"]
          and "--preview" in st[1] and "--preview" not in st[0] and st[1][st[1].index("--preview-src") + 1] == src["sprite"] and st[1][st[1].index("--preview-cells") + 1] == "3"
          and st[2][st[2].index("--src") + 1] == src["icon"] and st[3][st[3].index("--src") + 1] == dst["icon"],
          "RECUI: extra passes: one command a pass for the strip then the icon, a later pass reads the result so far, the last strip pass writes the preview against the source")
    check(ok and min(flash2[:3]) > 190 and max(flash2[:3]) - min(flash2[:3]) < 20 and other == white,
          "RECUI: the second pass on frame 3 alone turns the flash white and leaves the other frames as the first pass made them (%s)" % (flash2,))
    sheet = Image.open(prev)
    check(sheet.size == (16 * 2 * 3, 16) and sheet.getpixel((7, 7))[:3] == (40, 200, 40) and min(sheet.getpixel((16 + 7, 7))[:3]) > 190,
          "RECUI: the preview sheet pairs the SOURCE look with the result (first, the middle one that is also the pass's frame 3, last): %s" % (sheet.size,))
    check(open(src["sprite"], "rb").read() == before, "RECUI: the source look's strip is never written")
    # the form's preview: in memory, the same pixels as the files
    p = RC.preview(two, src["sprite"], src["icon"], frame=1, names={1: "run 1 (frame 1)"})
    import base64
    import io
    shots = {s["frame"]: Image.open(io.BytesIO(base64.b64decode(s["after"].split(",", 1)[1]))).convert("RGBA") for s in p["shots"]}
    check(p["ok"] and [s["label"] for s in p["shots"]] == ["run 1 (frame 1)", "frame 3", "icon"] and len(p["passes"]) == 2
          and shots[1].getpixel((7, 7)) == other and shots[3].getpixel((7, 7)) == flash2 and shots[-1].getpixel((7, 7)) == _px(dst["icon"], 7, 7)
          and shots[-1].getpixel((3, 3)) == _px(dst["icon"], 3, 3),
          "RECUI: the before / after (in memory, nothing written) shows the first run frame, the pass's frame and the icon, pixel for pixel what the job writes")
    check(sorted(os.listdir(folder)) == sorted(["beast_sprite_a.png", "beast_icon_a.png"] + ["beast_%s_%s.png" % (k, x) for k in ("sprite", "icon") for x in "htwx"]),
          "RECUI: the preview wrote no file")


def _jobs_checks(check, RC, tmp):
    import jobs
    sp = jobs.validate_spec("look", {"method": "recolour", "recipe": {"recolour": {
        "from": "CC-B", "mode": "lift", "ranges": "0-360", "to": 40, "set_sat": 0.05, "v_lo": 0.7, "keep_edge": 4,
        "passes": [{"mode": "lift", "ranges": [[0, 360]], "to": 40, "min_sat": 0.02, "cells": [18]}]}}})
    check(sp["recolour"]["ranges"] == [[0, 360]] and sp["recolour"]["passes"][0]["cells"] == [18], "RECUI: the form's recipe.recolour reaches spec.recolour, checked and tidied")
    jobs._seed_recipe({"kind": "enemy", "id": "nope_recui", "code": "CC-X"}, sp)
    r = sp["recipe"]
    check(r.get("method") == "recolour" and "painter" not in r and r.get("recolour_of") == "CC-B"
          and r.get("recolour_passes") == ["--mode lift --ranges 0-360 --to 40 --set-sat 0.05 --v-lo 0.7", "--mode lift --ranges 0-360 --to 40 --min-sat 0.02 --cells 18"]
          and r.get("recolour_icon_extra") == "--keep-edge 4" and r.get("recolour", {}).get("from") == "CC-B",
          "RECUI: the look's recipe records recolour_of + recolour_passes (+ the icon's extra) beside the form's own block: %s" % {k: r[k] for k in r if k != "recolour"})
    for bad, word in (({"from": "A-A", "ranges": [[300, 20]]}, "two ranges"), ({"ranges": [[0, 20]]}, "recolour.from")):
        try:
            jobs.validate_spec("look", {"method": "recolour", "recolour": bad})
            msg = ""
        except ValueError as e:
            msg = str(e)
        check(word in msg, "RECUI: Queue refuses %s in plain words (%s)" % (bad, msg))

    # the plan on a temp creature: jobs.content_path pointed at a folder of our own
    folder = os.path.join(tmp, "content", "enemies", "recbeast")
    os.makedirs(folder)
    doc = {"id": "recbeast", "variant_base": "RB-A", "anims": {"idle": 1, "run": 2, "attack": 1, "hit": 1, "die": 1},
           "variants": {"RB-A": {"note": "the base"}, "RB-B": {"sprite": "recbeast_sprite_b.png", "icon": "recbeast_icon_b.png", "anims": {"idle": 1, "run": 2, "attack": 1, "hit": 1, "die": 1}}}}
    with open(os.path.join(folder, "recbeast.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f)
    for name in ("recbeast_sprite.png", "recbeast_sprite_b.png"):
        _strip(os.path.join(folder, name))
    for name in ("recbeast_icon.png", "recbeast_icon_b.png"):
        _strip(os.path.join(folder, name), n=1)
    saved = (jobs.content_path, jobs.content_doc, jobs.REVIEW)
    try:
        jobs.content_path = lambda kind, cid: ("enemies", os.path.join(folder, "recbeast.json")) if cid == "recbeast" else saved[0](kind, cid)
        jobs.content_doc = lambda kind, cid: doc if cid == "recbeast" else saved[1](kind, cid)
        jobs.REVIEW = os.path.join(tmp, "review")
        t = {"kind": "enemy", "id": "recbeast"}
        fa, fb = jobs.recolour_files(t, "RB-A"), jobs.recolour_files(t, "RB-B")
        check(os.path.basename(fa["sprite"]) == "recbeast_sprite.png" and os.path.basename(fa["icon"]) == "recbeast_icon.png" and os.path.basename(fb["sprite"]) == "recbeast_sprite_b.png",
              "RECUI: the base look's strip is the unlettered file, another look's the file its entry names")
        for md, rc, want in (
                ("hue", {"from": "RB-B", "ranges": [[90, 150]], "to": 0}, ["--ranges", "90-150", "--to", "0"]),
                ("tint", {"from": "RB-B", "mode": "tint", "ranges": [[90, 150]], "to": 222, "set_sat": 0.5}, ["--mode", "tint", "--ranges", "90-150", "--to", "222", "--set-sat", "0.5"]),
                ("lift", {"from": "RB-A", "mode": "lift", "ranges": [[90, 150], [0, 10]], "to": 40, "v_lo": 0.7, "max_val": 0.9}, ["--mode", "lift", "--ranges", "90-150,0-10", "--to", "40", "--v-lo", "0.7", "--max-val", "0.9"])):
            job = {"id": "recui131", "kind": "look", "method": "recolour", "target": dict(t, code="RB-C"), "spec": jobs.validate_spec("look", {"method": "recolour", "recolour": rc})}
            p = jobs._plan(job)
            s0 = p["steps"][0]
            srcname = "recbeast_sprite.png" if rc["from"] == "RB-A" else "recbeast_sprite_b.png"
            check(p["mode"] == "steps" and len(p["steps"]) == 2 and s0[1].endswith("recolour_strip.py") and s0[s0.index("--src") + 1].replace("\\", "/").endswith("/" + srcname)
                  and s0[s0.index("--dst") + 1].replace("\\", "/").endswith("/recbeast_sprite_c.png") and s0[6:6 + len(want)] == want and s0[-2] == "--preview"
                  and p["steps"][1][6:] == want and "recolour_strip.py" in p["equiv"],
                  "RECUI: the plan's command line, mode %s: %s" % (md, " ".join(s0[6:])))
        rc = {"from": "RB-B", "mode": "lift", "ranges": [[90, 150]], "to": 40, "min_sat": 0.5, "keep_edge": 2, "passes": [{"mode": "lift", "ranges": [[90, 150]], "to": 40, "min_sat": 0.05, "cells": [4]}]}
        job = {"id": "recui131", "kind": "look", "method": "recolour", "target": dict(t, code="RB-C"), "spec": jobs.validate_spec("look", {"method": "recolour", "recolour": rc})}
        st = jobs._plan(job)["steps"]
        check(len(st) == 4 and "--cells" not in st[0] and st[1][st[1].index("--cells") + 1] == "4" and st[1][st[1].index("--src") + 1] == st[0][st[0].index("--dst") + 1]
              and "--preview-src" in st[1] and st[1][st[1].index("--preview-cells") + 1] == "4" and st[2][-2:] == ["--keep-edge", "2"] and st[3][-2:] == ["--keep-edge", "2"],
              "RECUI: the plan with an extra pass on the hit frame: four commands, the second reads the first's result, the icon's keep its rim")
        pv = jobs.recolour_preview({"kind": "enemy", "id": "recbeast", "recolour": rc})
        check(pv["ok"] and [s["frame"] for s in pv["shots"]] == [1, 4, -1] and pv["shots"][0]["label"].startswith("run 1") and pv["shots"][1]["label"].startswith("hit 1") and pv["seconds"] < 5,
              "RECUI: the preview route's call: the first run frame, the hit frame the pass names, the icon (%s, %.2f s)" % ([s["label"] for s in pv["shots"]], pv["seconds"]))
        try:
            jobs.recolour_preview({"kind": "enemy", "id": "recbeast", "recolour": {"from": "Beast RB-B"}})
            msg = ""
        except ValueError as e:
            msg = str(e)
        check("code alone" in msg and "RB-A, RB-B" in msg, "RECUI: a name in place of the code is answered with the creature's codes (%s)" % msg)
    finally:
        jobs.content_path, jobs.content_doc, jobs.REVIEW = saved


def _page_checks(check, run_node, fields):
    with open(os.path.join(HERE, "index.html"), encoding="utf-8") as f:
        html = f.read()
    check('src="recolour_ui.js"' in html and html.index('src="recolour_ui.js"') < html.index('src="jobs.js"'), "RECUI: index.html loads recolour_ui.js before jobs.js")
    with open(os.path.join(HERE, "jobs.js"), encoding="utf-8") as f:
        js = f.read()
    check("FUI.shown(" in js and "FUI.line(" in js and "FUI.notes(" in js and "FUI.guideBox(" in js, "RECUI: the job form asks FieldUI for show_if, widgets, notes and the guide")
    with open(os.path.join(HERE, "recolour_ui.js"), encoding="utf-8") as f:
        ui = f.read()
    for w in ("look_code", "hue_ranges", "hue", "presets", "passes", "recolour_preview"):
        check(("    %s(f, value, set" % w) in ui, "RECUI: widget %s is defined" % w)
    used = {f["widget"] for f in fields if f.get("widget")}
    check(used == {"look_code", "hue_ranges", "hue", "presets", "passes", "recolour_preview"}, "RECUI: every widget methods.json names exists (%s)" % sorted(used))
    for name in ("recolour_ui.js", "jobs.js", "assets.js", "selftest_RECUI131.py", "recolour_io.py", "methods.json", "preview.css", "index.html"):
        with open(os.path.join(HERE, name), "rb") as f:
            check(b"\r\n" not in f.read(), "RECUI: %s keeps LF line endings" % name)
    node = shutil.which("node")
    if not node:
        print("RECUI131: node is not here: the page helpers are not run")
        return
    for name in ("recolour_ui.js", "jobs.js", "assets.js"):
        r = subprocess.run([node, "--check", os.path.join(HERE, name)], capture_output=True, text=True, timeout=60)
        check(r.returncode == 0, "RECUI: %s parses%s" % (name, "" if r.returncode == 0 else ": " + r.stderr[:300]))
    slim = [{k: f[k] for k in ("key", "default", "show_if") if k in f} for f in fields if not f.get("form_only")]
    r = subprocess.run([node, "-e", NODE_SCRIPT, os.path.join(HERE, "recolour_ui.js"), json.dumps(slim)], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        check(False, "RECUI: the page helpers run under Node: " + r.stderr[:400])
        return
    o = json.loads(r.stdout)
    common = ["from", "mode", "ranges", "to"]
    check(o["hue"] == common + ["sat", "min_sat", "max_sat", "passes"], "RECUI: mode hue (the default, nothing chosen) shows only its boxes: %s" % o["hue"])
    check(o["tint"] == common + ["set_sat", "value", "min_sat", "max_sat", "min_val", "passes"], "RECUI: mode tint shows only its boxes: %s" % o["tint"])
    check(o["lift"] == common + ["to_dark", "sat", "set_sat", "v_lo", "v_hi", "gamma", "min_sat", "max_sat", "min_val", "max_val", "src_hi", "soft", "hue_soft", "mass", "grow", "keep_edge", "passes"],
          "RECUI: mode lift shows only its boxes: %s" % o["lift"])
    check(o["drives"] == ["recolour.mode"], "RECUI: changing the mode redraws the form")
    rg = o["ranges"]
    check(rg[0] == {"ranges": [[340, 360], [0, 20]], "error": ""} and "340-360, 0-20" in rg[1]["error"] and rg[2]["ranges"] == [[55, 135]] and rg[3]["error"] and "0 to 360" in rg[4]["error"]
          and rg[5] == {"ranges": [], "error": ""} and o["text"] == "340-360, 0-20",
          "RECUI: the hue ranges box reads words, and says how to wrap through red (%s)" % rg[1]["error"])
    check(o["names"] == ["red", "orange", "yellow", "green", "blue", "purple", "red"], "RECUI: a hue's colour word: %s" % o["names"])
    check(o["starts"] == {"idle": 0, "run": 4, "attack": 16, "hit": 18, "die": 19}, "RECUI: the hit frame's number from the look's own frames: %s" % o["starts"])
    check(o["preset"] == {"from": "CC-B", "mode": "lift", "to": 40}, "RECUI: a preset fills the boxes and keeps the source look: %s" % o["preset"])
    check(o["pass"] == {"mode": "lift", "to": 40, "ranges": [[0, 360]], "cells": [18]}, "RECUI: + Add a pass starts from the boxes above: %s" % o["pass"])


def checks(check, run_node=None, server=None):
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    import recolour_io as RC
    tmp = tempfile.mkdtemp(prefix="le_recui131_")
    try:
        fields = _fields_checks(check, RC)
        _io_checks(check, RC)
        _run_checks(check, RC, tmp)
        _jobs_checks(check, RC, tmp)
        _page_checks(check, run_node, fields)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    n = [0, 0]

    def _check(ok, msg):
        n[0 if ok else 1] += 1
        if not ok:
            print("FAIL " + msg)

    checks(_check)
    print("RECUI131: %d passed, %d failed" % (n[0], n[1]))
    sys.exit(1 if n[1] else 0)
