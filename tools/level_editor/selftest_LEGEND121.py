"""Pass 121, lane LEGEND (Garry: "up until 4:30 in every run of any Stage there is 0 chance of getting a Legendary and
after 4:30 there is some (small) chance of getting it (so whatever it is now)"; "No guarantee, just the hold"): the
Level Editor knows the map's `timeline_data.legendary` {from, guarantee_at} and a stage entry's own `legendary` block.
fields.js has the two Settings rows (group "Legendary items") whose defaults are the game's
(WaveTimeline.LEGENDARY_DEFAULTS) and stage_model.js's LEGENDARY_DEF; stage_model.js setField writes a stage's own
numbers (whole seconds >= 0, empty removes the key, an emptied block goes), legendaryOf reads stage over map over game,
legendaryText words it, issues() warns on a bad one; the stage card and the Settings card show them; model.js lists the
stage key; the game reads the block (JsonContent, WaveTimeline.legendary_value, LegendaryHold); Red Canyon carries it.
selftest.py discovers this file and hands `checks` its counter. Nothing here writes.
"""
import json
import os
import re
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

RUNNER = r"""
const SM = require(process.argv[2]);
const tl = () => ({ legendary: { from: 200 }, stage_list: [{ id: 's1', name: 'A', length: 300 }, { id: 's2', name: 'B', length: 300 }] });
const out = {};
out.def = SM.LEGENDARY_DEF;
let d = tl(); SM.setField(d, 1, 'legendary.from', 60); out.set = d.stage_list[1].legendary; out.other = ('legendary' in d.stage_list[0]);
d = tl(); SM.setField(d, 1, 'legendary.from', '90.6'); out.str = d.stage_list[1].legendary.from;
d = tl(); SM.setField(d, 1, 'legendary.from', -5); out.neg = d.stage_list[1].legendary.from;
d = tl(); SM.setField(d, 1, 'legendary.guarantee_at', 400); SM.setField(d, 1, 'legendary.from', 30); SM.setField(d, 1, 'legendary.from', null); out.left = JSON.parse(JSON.stringify(d.stage_list[1].legendary));
SM.setField(d, 1, 'legendary.guarantee_at', ''); out.gone = ('legendary' in d.stage_list[1]);
d = tl(); out.mapOnly = SM.legendaryOf(d, -1); out.s0 = SM.legendaryOf(d, 0);
d.stage_list[1].legendary = { guarantee_at: 500 }; out.s1 = SM.legendaryOf(d, 1);
out.bare = SM.legendaryOf({}, 0);
out.text0 = SM.legendaryText(d, 0); out.text1 = SM.legendaryText(d, 1);
d.stage_list[1].legendary = { guarantee_at: 100 }; out.textWait = SM.legendaryText(d, 1);
d = tl(); d.stage_list[0].legendary = { from: 'soon' }; out.issues = SM.issues(d).map((x) => x.msg);
d = tl(); d.stage_list[0].legendary = 5; out.issuesObj = SM.issues(d).map((x) => x.msg);
d = tl(); d.stage_list[0].legendary = { from: 30, guarantee_at: 0 }; out.okIssues = SM.issues(d).filter((x) => /legendary/.test(x.msg)).length;
process.stdout.write(JSON.stringify(out));
"""


def _read(*parts):
    with open(os.path.join(*parts), "r", encoding="utf-8") as f:
        return f.read()


def checks(check, run_node, server):
    # the game: the defaults, the reader, the hold
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    m = re.search(r'const LEGENDARY_DEFAULTS := \{"from": ([0-9.]+), "guarantee_at": ([0-9.]+)\}', wt)
    check(m is not None, "LEGEND121 WaveTimeline.gd has LEGENDARY_DEFAULTS {from, guarantee_at}")
    game_def = {"from": float(m.group(1)), "guarantee_at": float(m.group(2))} if m else {}
    check(game_def == {"from": 270.0, "guarantee_at": 0.0}, "LEGEND121 the game's defaults are 4:30 and off: %s" % game_def)
    check("func legendary_value" in wt and '"legendary"' in wt, "LEGEND121 WaveTimeline.legendary_value reads a stage's own block")
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    check('t.get("legendary"' in jc and "w.legendary =" in jc, "LEGEND121 JsonContent reads timeline_data.legendary")
    lh = _read(GAME, "core", "systems", "LegendaryHold.gd")
    check("class_name LegendaryHold" in lh and 'const RARITY := "legendary"' in lh, "LEGEND121 LegendaryHold holds by rarity")
    # the map file
    with open(os.path.join(GAME, "content", "maps", "red_canyon", "red_canyon.json"), "r", encoding="utf-8") as f:
        tl = json.load(f).get("timeline_data") or {}
    blk = tl.get("legendary")
    check(isinstance(blk, dict) and all(isinstance(blk.get(k), (int, float)) and blk.get(k) >= 0 for k in ("from", "guarantee_at")),
          "LEGEND121 Red Canyon's timeline_data carries legendary {from, guarantee_at}: %s" % blk)
    # the page: the Settings rows and their defaults
    fj = _read(HERE, "fields.js")
    for key, want in (("legendary.from", 270), ("legendary.guarantee_at", 0)):
        mm = re.search(r"\{ key: '%s', group: 'Legendary items',[^\n]*?type: 'seconds',[^\n]*?def: ([0-9.]+)," % re.escape(key), fj)
        check(mm is not None, "LEGEND121 fields.js has the %s row (seconds, group Legendary items)" % key)
        if mm:
            check(float(mm.group(1)) == want == game_def.get(key.split(".")[1]), "LEGEND121 fields.js %s def %s is the game's" % (key, mm.group(1)))
    groups = fj.split("const SCALAR_GROUPS = [")[1].split("]")[0] if "const SCALAR_GROUPS = [" in fj else ""
    check("'Legendary items'" in groups, "LEGEND121 SCALAR_GROUPS shows the Legendary items card")
    st = _read(HERE, "stage_tabs.js")
    check("'No legendary before'" in st and "set('legendary.from'" in st and "set('legendary.guarantee_at'" in st and "'Guarantee one by'" in st,
          "LEGEND121 the stage card edits the stage's own legendary numbers")
    se = _read(HERE, "settings.js")
    check("group === 'Legendary items'" in se and "StageModel.legendaryText" in se, "LEGEND121 the Settings card says what each stage plays")
    mj = _read(HERE, "model.js")
    keys = mj.split("const STAGE_LIST_KEYS = [")[1].split("]")[0] if "const STAGE_LIST_KEYS = [" in mj else ""
    check("'legendary'" in keys, "LEGEND121 model.js STAGE_LIST_KEYS has legendary")
    # stage_model.js under node
    node = shutil.which("node")
    if not node:
        check(False, "LEGEND121 node is needed for the stage_model checks")
        return
    rp = os.path.join(HERE, "_legend121_runner.js")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(RUNNER)
    try:
        p = subprocess.run([node, rp, os.path.join(HERE, "stage_model.js")], capture_output=True, text=True, encoding="utf-8", timeout=60)
    finally:
        os.remove(rp)
    check(p.returncode == 0, "LEGEND121 stage_model.js ran under node: %s" % p.stderr[-400:])
    if p.returncode != 0:
        return
    r = json.loads(p.stdout)
    check(r["def"] == {"from": 270, "guarantee_at": 0} and {k: float(v) for k, v in r["def"].items()} == game_def,
          "LEGEND121 stage_model LEGENDARY_DEF is the game's: %s" % r["def"])
    check(r["set"] == {"from": 60} and r["other"] is False, "LEGEND121 setField writes the stage's own from only there: %s" % r["set"])
    check(r["str"] == 91 and r["neg"] == 0, "LEGEND121 setField rounds to whole seconds and clamps at 0: %s / %s" % (r["str"], r["neg"]))
    check(r["left"] == {"guarantee_at": 400} and r["gone"] is False, "LEGEND121 setField: empty removes the key, an emptied block goes: %s" % r["left"])
    check(r["mapOnly"]["from"] == 200 and r["mapOnly"]["src"]["from"] == "map" and r["mapOnly"]["guarantee_at"] == 0 and r["mapOnly"]["src"]["guarantee_at"] == "game",
          "LEGEND121 legendaryOf(-1): the map's, else the game's: %s" % r["mapOnly"])
    check(r["s0"]["from"] == 200 and r["s1"]["guarantee_at"] == 500 and r["s1"]["src"]["guarantee_at"] == "stage" and r["s1"]["from"] == 200,
          "LEGEND121 legendaryOf: a stage's own key wins, the rest is the map's: %s" % r["s1"])
    check(r["bare"]["from"] == 270 and r["bare"]["guarantee_at"] == 0, "LEGEND121 legendaryOf with no block: 4:30, off")
    check("3:20" in r["text0"] and "guarantee off" in r["text0"], "LEGEND121 legendaryText words the map's: %s" % r["text0"])
    check("8:20" in r["text1"], "LEGEND121 legendaryText words a stage's guarantee: %s" % r["text1"])
    check("waits for the hold" in r["textWait"] and "3:20" in r["textWait"], "LEGEND121 a guarantee before the hold waits for it: %s" % r["textWait"])
    check(any("legendary.from" in x for x in r["issues"]) and any("legendary must be an object" in x for x in r["issuesObj"]) and r["okIssues"] == 0,
          "LEGEND121 issues() warns on a bad legendary block only: %s %s" % (r["issues"], r["issuesObj"]))
