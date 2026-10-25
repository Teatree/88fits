"""Pass 107, lane XPT: the Level Editor knows the pass's two keys. A stage's `xp_mult` (stage_list entry; the game's
WaveTimeline.stage_xp_mult, applied to every kill's XP in Game._drop_from_kill): stage_model.js setField writes it as a
number (empty or 1 removes it, below 0 clamps to 0), issues() warns on a bad one, the stage card has its row, model.js
lists it among the stage keys, and Red Canyon's Nightfall carries one below 1 (Sundown and Blood Moon none). A weapon's
`night_tint` (ProjectileEmitter.night_look_on: the shot's colours while the stage plays a filter) is a ProjectileEmitter
params key in vocab.py and assets_fields.js, read by the game, carried by the Tumbleweed and the Dust Devil.
selftest.py discovers this file and hands `checks` its counter. Nothing here writes.
"""
import json
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

RUNNER = r"""
const SM = require(process.argv[2]);
const tl = () => ({ stage_list: [{ id: 's1', name: 'A', length: 100 }, { id: 's2', name: 'B', length: 100 }] });
const out = {};
let d = tl(); SM.setField(d, 1, 'xp_mult', 0.7); out.set = d.stage_list[1].xp_mult;
d = tl(); SM.setField(d, 1, 'xp_mult', '0.45'); out.str = d.stage_list[1].xp_mult;
d = tl(); SM.setField(d, 1, 'xp_mult', 0.7); SM.setField(d, 1, 'xp_mult', null); out.cleared = ('xp_mult' in d.stage_list[1]);
d = tl(); SM.setField(d, 1, 'xp_mult', 1); out.one = ('xp_mult' in d.stage_list[1]);
d = tl(); SM.setField(d, 1, 'xp_mult', -3); out.neg = d.stage_list[1].xp_mult;
d = tl(); SM.setField(d, 0, 'xp_mult', 0.123456); out.round = d.stage_list[0].xp_mult; out.other = ('xp_mult' in d.stage_list[1]);
d = tl(); d.stage_list[1].xp_mult = 'lots'; out.issues = SM.issues(d).map((x) => x.msg);
d = tl(); d.stage_list[1].xp_mult = 0.7; out.ok_issues = SM.issues(d).filter((x) => /xp_mult/.test(x.msg)).length;
process.stdout.write(JSON.stringify(out));
"""


def _read(*parts):
    with open(os.path.join(*parts), "r", encoding="utf-8") as f:
        return f.read()


def _json(rel):
    with open(os.path.join(GAME, "content", rel, rel.split("/")[1] + ".json"), "r", encoding="utf-8") as f:
        return json.load(f)


def checks(check, run_node, server):
    import vocab
    # night_tint: a ProjectileEmitter params key the game reads
    check("night_tint" in vocab.PARAMS_KEYS["ProjectileEmitter"], "XPT107 vocab.py lists night_tint for ProjectileEmitter")
    probs = [p for p in vocab.check_against_source(GAME) if "night_tint" in p]
    check(not probs, "XPT107 night_tint is read by the game (check_against_source): %s" % probs)
    js = _read(HERE, "assets_fields.js")
    pe = js.split("ProjectileEmitter: [")[1].split("],")[0] if "ProjectileEmitter: [" in js else ""
    check("'night_tint'" in pe, "XPT107 assets_fields.js PARAMS_KEYS.ProjectileEmitter has night_tint")
    for rel in ("weapons/tumbleweed", "evolutions/dust_devil"):
        nt = (_json(rel).get("params") or {}).get("night_tint")
        check(isinstance(nt, dict) and str(nt.get("albedo", "")).startswith("#"), "XPT107 %s carries params.night_tint: %s" % (rel, nt))
    src = _read(GAME, "core", "behaviors", "ProjectileEmitter.gd")
    check('"night_tint"' in src and "func night_look_on" in src and "static func stage_filter_on" in src,
          "XPT107 ProjectileEmitter.gd reads night_tint (night_look_on, stage_filter_on)")
    # xp_mult: the game reads it
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    check("func stage_xp_mult" in wt and '"xp_mult"' in wt, "XPT107 WaveTimeline.gd reads the stage entry's xp_mult")
    gm = _read(GAME, "game", "Game.gd")
    check("director.stage_xp_mult()" in gm, "XPT107 Game._drop_from_kill applies the stage's XP multiplier")
    # the page: the stage card row, the stage keys
    st = _read(HERE, "stage_tabs.js")
    check("'XP from kills'" in st and "stage.xp_mult" in st and "set('xp_mult'" in st, "XPT107 the stage card has the XP from kills row")
    mj = _read(HERE, "model.js")
    keys = mj.split("const STAGE_LIST_KEYS = [")[1].split("]")[0] if "const STAGE_LIST_KEYS = [" in mj else ""
    check("'xp_mult'" in keys, "XPT107 model.js STAGE_LIST_KEYS has xp_mult")
    # Red Canyon: only Nightfall slowed
    tl = _json("maps/red_canyon").get("timeline_data") or {}
    sl = [e for e in tl.get("stage_list") or [] if isinstance(e, dict)]
    check(len(sl) >= 3, "XPT107 Red Canyon has its three stages")
    if len(sl) >= 3:
        check("xp_mult" not in sl[0] and "xp_mult" not in sl[2], "XPT107 Sundown and Blood Moon keep the XP as it was (no xp_mult)")
        v = sl[1].get("xp_mult")
        check(isinstance(v, (int, float)) and 0 < v < 1, "XPT107 Nightfall's xp_mult is below 1: %s" % v)
    # stage_model.js under node
    node = shutil.which("node")
    if not node:
        check(False, "XPT107 node is needed for the stage_model checks")
        return
    rp = os.path.join(HERE, "_xpt107_runner.js")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(RUNNER)
    try:
        p = subprocess.run([node, rp, os.path.join(HERE, "stage_model.js")], capture_output=True, text=True, encoding="utf-8", timeout=60)
    finally:
        os.remove(rp)
    check(p.returncode == 0, "XPT107 stage_model.js ran under node: %s" % p.stderr[-400:])
    if p.returncode != 0:
        return
    r = json.loads(p.stdout)
    check(r["set"] == 0.7 and r["str"] == 0.45, "XPT107 setField writes xp_mult as a number: %s / %s" % (r["set"], r["str"]))
    check(r["cleared"] is False and r["one"] is False, "XPT107 setField: empty or 1 removes xp_mult (the default)")
    check(r["neg"] == 0, "XPT107 setField clamps a negative xp_mult to 0: %s" % r["neg"])
    check(r["round"] == 0.123 and r["other"] is False, "XPT107 setField rounds to 0.001 and touches only its stage: %s" % r["round"])
    check(any("xp_mult" in m for m in r["issues"]) and r["ok_issues"] == 0, "XPT107 issues() warns on a bad xp_mult only: %s" % r["issues"])
