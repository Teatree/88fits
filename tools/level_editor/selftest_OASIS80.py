"""Pass 80, lane OASIS: the Level Editor's side of the water's slow and the oases' count. selftest.py discovers this file
(`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing
here writes.

Groups: the World card's rows in fields.js (water_slow and oases.min / max / extra_chance / gap, with help, their grey
defaults the game's own: WaveTimeline.WATER_SLOW_DEFAULT / OASES_DEFAULTS); the game reading the keys (JsonContent ->
WaveTimeline -> RedCanyon, Player, EnemyManager); Red Canyon's file naming only values the game can play.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

KEYS = ["water_slow", "oases.min", "oases.max", "oases.extra_chance", "oases.gap"]

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const dir = path.dirname(process.argv[2]);
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const out = {};
  out.rows = FIELDS.SCALARS.filter((d) => d.key === 'water_slow' || d.key.startsWith('oases.')).map((d) => [d.key, d.group, d.type, d.def, !!d.help, d.min, d.max]);
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _defaults():
    """WaveTimeline.WATER_SLOW_DEFAULT and OASES_DEFAULTS, read from the script."""
    src = _read(GAME, "core", "data", "WaveTimeline.gd")
    out = {}
    m = re.search(r"const WATER_SLOW_DEFAULT := ([0-9.]+)", src)
    if m:
        out["water_slow"] = float(m.group(1))
    m = re.search(r"const OASES_DEFAULTS := \{([^}]*)\}", src)
    if m:
        for k, v in re.findall(r'"(\w+)": ([0-9.]+)', m.group(1)):
            out["oases." + k] = float(v)
    return out


def checks(check, run_node, server):
    res = run_node({}, RUNNER)
    if not res:
        check(False, "OASIS80: node ran fields.js")
        return
    rows = {r[0]: r for r in res["rows"]}
    check(sorted(rows) == sorted(KEYS), "OASIS80: the World card has the water's slow and the four oases rows: %s" % sorted(rows))
    check(all(r[1] == "World" and r[4] for r in rows.values()) and "World" in res["groups"],
          "OASIS80: every row sits in the World card with its help: %s" % list(rows.values()))
    check(rows.get("oases.min", [None, None, None])[2] == "int" and rows.get("oases.max", [None, None, None])[2] == "int",
          "OASIS80: the oases' counts are whole numbers")
    dflt = _defaults()
    check(len(dflt) == 5, "OASIS80: WaveTimeline names WATER_SLOW_DEFAULT and the four OASES_DEFAULTS: %s" % dflt)
    wrong = [(k, rows[k][3], dflt.get(k)) for k in KEYS if k in rows and abs(float(rows[k][3]) - float(dflt.get(k, -1))) > 1e-6]
    check(not wrong, "OASIS80: each row's grey default is the game's own: %s" % wrong)
    # the game reads the keys and plays them
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    rc = _read(GAME, "world", "maps", "red_canyon", "RedCanyon.gd")
    pl = _read(GAME, "player", "Player.gd")
    em = _read(GAME, "core", "systems", "EnemyManager.gd")
    check('t.get("water_slow"' in jc and 't.get("oases"' in jc, "OASIS80: JsonContent reads water_slow and oases")
    check("@export var water_slow" in wt and "@export var oases" in wt, "OASIS80: WaveTimeline carries the two keys")
    check("func _roll_oases" in rc and "tl.oases" in rc and "func lakes()" in rc, "OASIS80: Red Canyon rolls its oases from the file")
    check("planar *= _wade_mult()" in pl and "tl.water_slow" in pl, "OASIS80: the hero wades at the file's slow")
    check("vel[i] * _wade_k[i] + kb[i]" in em and "tl.water_slow" in em and "func _wade_tick" in em, "OASIS80: the creatures wade at the file's slow (never their push)")
    # Red Canyon's file: when it names them, values the game can play
    tl = json.loads(_read(GAME, "content", "maps", "red_canyon", "red_canyon.json")).get("timeline_data", {})
    bad = []
    if "water_slow" in tl and not (isinstance(tl["water_slow"], (int, float)) and 0 <= tl["water_slow"] <= 0.95):
        bad.append(("water_slow", tl["water_slow"]))
    o = tl.get("oases", {})
    if not isinstance(o, dict):
        bad.append(("oases", o))
    else:
        bad += [(k, v) for k, v in o.items() if k not in ("min", "max", "extra_chance", "gap") or not isinstance(v, (int, float))]
        if isinstance(o.get("min", 2), (int, float)) and isinstance(o.get("max", 3), (int, float)) and o.get("max", 3) < o.get("min", 2):
            bad.append(("max < min", o))
    check(not bad, "OASIS80: Red Canyon's water and oases are numbers the game plays: %s" % bad)
