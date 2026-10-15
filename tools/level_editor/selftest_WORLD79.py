"""Pass 79, lane WORLD: the Level Editor's side of the map's colours. selftest.py discovers this file (`extra_checks`)
and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes.

Groups: the World card's colour rows in fields.js (rock_color and the eight wall_colors, swatches with help, their grey
defaults the game's own: RedCanyon.ROCK_COLOR / WALL_COLORS as hex); the Settings tab handing a swatch its default and
"the game's" wording (forms.js `own`); the game reading the keys (JsonContent -> WaveTimeline -> RedCanyon); Red
Canyon's file naming only colours the game can read, when it names them.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

WALL_KEYS = ["near", "far", "farther", "stone", "light", "cap", "riser", "boulders"]

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
  out.rows = FIELDS.SCALARS.filter((d) => d.key === 'rock_color' || d.key.startsWith('wall_colors.')).map((d) => [d.key, d.group, d.type, d.def, !!d.help]);
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _hex(rgb):
    return "#%02X%02X%02X" % tuple(int(round(float(v) * 255)) for v in rgb)


def _defaults():
    """RedCanyon.ROCK_COLOR and WALL_COLORS as hex, read from the script."""
    src = _read(GAME, "world", "maps", "red_canyon", "RedCanyon.gd")
    out = {}
    m = re.search(r"const ROCK_COLOR := Color\(([^)]*)\)", src)
    if m:
        out["rock_color"] = _hex(m.group(1).split(","))
    block = re.search(r"const WALL_COLORS := \{(.*?)\n\}", src, re.S)
    if block:
        for k, rgb in re.findall(r'"(\w+)": Color\(([^)]*)\)', block.group(1)):
            out["wall_colors." + k] = _hex(rgb.split(","))
    return out


def checks(check, run_node, server):
    res = run_node({}, RUNNER)
    if not res:
        check(False, "WORLD79: node ran fields.js")
        return
    rows = {r[0]: r for r in res["rows"]}
    want = ["rock_color"] + ["wall_colors." + k for k in WALL_KEYS]
    check(sorted(rows) == sorted(want), "WORLD79: the World card has the rock colour and the eight wall colours: %s" % sorted(rows))
    check(all(r[1] == "World" and r[2] == "swatch" and r[4] for r in rows.values()) and "World" in res["groups"],
          "WORLD79: every colour row is a swatch in the World card with its help: %s" % list(rows.values()))
    dflt = _defaults()
    check(len(dflt) == 9, "WORLD79: RedCanyon.gd names ROCK_COLOR and the eight WALL_COLORS: %s" % dflt)
    wrong = [(k, rows[k][3], dflt.get(k)) for k in want if k in rows and str(rows[k][3]).upper() != str(dflt.get(k, "")).upper()]
    check(not wrong, "WORLD79: each row's grey default is the game's own (RedCanyon's consts): %s" % wrong)
    # the Settings tab hands a swatch its default and "the game's" wording; forms.js passes `own` to the swatch
    st = _read(HERE, "settings.js")
    fm = _read(HERE, "forms.js")
    check("def.type === 'swatch' ? { placeholder: def.def, own:" in st, "WORLD79: Settings hands a colour row its default as the faded placeholder")
    check("own: o.own" in fm and "const own = o.own ||" in fm, "WORLD79: forms.js names whose default an empty swatch plays")
    # the game reads the keys
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    rc = _read(GAME, "world", "maps", "red_canyon", "RedCanyon.gd")
    check('t.get("rock_color"' in jc and 't.get("wall_colors"' in jc, "WORLD79: JsonContent reads rock_color and wall_colors")
    check("@export var rock_color" in wt and "@export var wall_colors" in wt and "static func color_of" in wt,
          "WORLD79: WaveTimeline carries the two keys and parses a colour")
    check("func _read_colours" in rc and 'set_shader_parameter("rock_flat", rock_color)' in rc,
          "WORLD79: Red Canyon builds in the file's colours (the rock into the terrain shader)")
    # Red Canyon's file: when it names the colours, each is one the game can read
    tl = json.loads(_read(GAME, "content", "maps", "red_canyon", "red_canyon.json")).get("timeline_data", {})
    hexre = re.compile(r"^#[0-9A-Fa-f]{6}$")
    bad = []
    if "rock_color" in tl and not hexre.match(str(tl["rock_color"])):
        bad.append(("rock_color", tl["rock_color"]))
    wc = tl.get("wall_colors", {})
    if not isinstance(wc, dict):
        bad.append(("wall_colors", wc))
    else:
        bad += [(k, v) for k, v in wc.items() if k not in WALL_KEYS or not hexre.match(str(v))]
    check(not bad, "WORLD79: Red Canyon's colours are #RRGGBB under known keys: %s" % bad)
