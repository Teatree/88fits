"""Pass 82, lane SAND: the Level Editor's side of the five sands. selftest.py discovers this file (`extra_checks`) and
hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes.

Groups: the World card's Sand row in fields.js (a select of the five, the default pass 81's, every option with its help);
the game reading the key (JsonContent -> WaveTimeline.sand -> RedCanyon.SANDS, the shader's sand_scale); every option one
of RedCanyon.SANDS and every painting there; Red Canyon's file naming only a sand the game knows.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

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
  out.rows = FIELDS.SCALARS.filter((d) => d.key === 'sand').map((d) => ({ key: d.key, group: d.group, type: d.type, def: d.def, help: !!d.help,
    options: (d.options || []).map((o) => [o.v, o.label, !!o.help]) }));
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _game_sands():
    """RedCanyon.SANDS as {id: file} and SAND_DEFAULT, read from the script."""
    src = _read(GAME, "world", "maps", "red_canyon", "RedCanyon.gd")
    m = re.search(r"const SANDS := \{(.*?)\n\}", src, re.S)
    sands = dict(re.findall(r'"(\w+)": \{"file": "res://([^"]+)"', m.group(1))) if m else {}
    d = re.search(r'const SAND_DEFAULT := "(\w+)"', src)
    return sands, d.group(1) if d else None


def checks(check, run_node, server):
    res = run_node({}, RUNNER)
    if not res:
        check(False, "SAND82: node ran fields.js")
        return
    rows = res["rows"]
    check(len(rows) == 1, "SAND82: the World card has one Sand row: %s" % rows)
    if not rows:
        return
    row = rows[0]
    check(row["group"] == "World" and row["type"] == "select" and row["help"] and "World" in res["groups"],
          "SAND82: the Sand row is a select in the World card with its help: %s" % row)
    sands, default = _game_sands()
    check(len(sands) == 5 and default == "pass81", "SAND82: Red Canyon knows five sands, pass 81's the default: %s %s" % (sands, default))
    check(row["def"] == default, "SAND82: the row's default is the game's (%s): %s" % (default, row["def"]))
    opts = {o[0]: o for o in row["options"]}
    check(sorted(opts) == sorted(sands), "SAND82: the row offers exactly the game's sands: %s against %s" % (sorted(opts), sorted(sands)))
    check(all(o[1] and o[2] for o in row["options"]), "SAND82: every sand is named in words with its help: %s" % row["options"])
    missing = [f for f in sands.values() if not os.path.isfile(os.path.join(GAME, f))]
    check(not missing, "SAND82: every sand's painting is in the game: %s" % missing)
    # the preview strip: one 300 px shot a sand, in the row's order (settings.js shows the chosen one)
    prev = os.path.join(HERE, "sand_previews.png")
    size = None
    if os.path.isfile(prev):
        with open(prev, "rb") as f:
            head = f.read(24)
        size = (int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")) if head[1:4] == b"PNG" else None
    check(size == (300 * len(row["options"]), 300), "SAND82: sand_previews.png holds one 300 px shot a sand: %s" % (size,))
    gs = _read(ROOT, "tools", "gen_sand.py")
    m = re.search(r"^SANDS = \{(.*?)^\}", gs, re.S | re.M)
    order = ["pass81"] + (re.findall(r'^    "(\w+)": \{', m.group(1), re.M) if m else [])
    check(order == [o[0] for o in row["options"]], "SAND82: the previews' order (gen_sand.SANDS) is the row's: %s" % order)
    # the game reads the key and plays it
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    rc = _read(GAME, "world", "maps", "red_canyon", "RedCanyon.gd")
    sh = _read(GAME, "core", "shaders", "terrain_painted.gdshader")
    check('w.sand = str(t.get("sand", ""))' in jc and "@export var sand: String" in wt, "SAND82: JsonContent reads `sand` into WaveTimeline")
    check("func map_sand_id" in rc and "func set_sand" in rc and "_apply_sand(mat, map_sand_id())" in rc,
          "SAND82: Red Canyon paints the terrain with the file's sand")
    check("uniform float sand_scale" in sh and "texture(sand_tex, uv * sand_scale)" in sh, "SAND82: the shader samples the sand at its own scale")
    # Red Canyon's file: when it names a sand, one the game knows
    tl = json.loads(_read(GAME, "content", "maps", "red_canyon", "red_canyon.json")).get("timeline_data", {})
    check("sand" not in tl or tl["sand"] in sands, "SAND82: Red Canyon's file names a sand the game knows: %s" % tl.get("sand"))
