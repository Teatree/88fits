"""Pass 113, lane TWISTER: the map's dust devils, rarer and readable (Garry: "Tornadoes still don't look like tornadoes and
are quite confusing. Make them rarer too."). selftest.py discovers this file (`extra_checks`) and hands it its `check`
counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes.

Groups: the table (game/core/systems/DustDevils.gd's DEFAULTS, EVERY_MIN, HERO_REACH, WANDERS are dustdevil_card.js's);
the reader (configOf) on purpose-built blocks against a Python copy of DustDevils.config_of; the count a stage
(countIn) against the same sum; the line under the card and its warnings; fields.js (a row with help for every key,
greyed with the game's number, in the Dust devils card, the card after Barrels); the page's wiring (index.html,
settings.js) and the game's (JsonContent, WaveTimeline, RedCanyon: the clock, no always-on dust devil).
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
const M = require(path.join(dir, 'dustdevil_card.js'));
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.tables = { DEFAULTS: M.DEFAULTS, EVERY_MIN: M.EVERY_MIN, HERO_REACH: M.HERO_REACH, WANDERS: M.WANDERS };
  out.configs = q.cases.map((b) => M.configOf(b));
  out.counts = q.countCases.map(([b, len]) => M.countIn(M.configOf(b), len));
  out.summary = M.summaryText(q.map.dust_devils, q.stages);
  out.offSummary = M.summaryText({ enabled: false }, q.stages);
  out.issues = q.issueCases.map((b) => M.issues({ dust_devils: b }));
  out.mapIssues = M.issues(q.map);
  out.rows = FIELDS.SCALARS.filter((d) => d.key.startsWith('dust_devils.')).map((d) => [d.key, d.group, d.type, d.def, !!d.help, (d.options || []).map((o) => o.v)]);
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""

CASES = [
    None,
    {},
    {"enabled": False},
    {"every": 2, "life": [1, 3], "wander": "zigzag", "toss": {"up": 5}, "max_alive": -2},
    {"first": "30", "every": [200, 100], "life": 12, "radius": 0.05, "speed": -1, "form_dist": [9, 4], "lift": 0},
    {"wander": "loop", "miss": 0, "warn": "no", "in_boss": 1, "toss": {"out": -2, "cooldown": -1}, "form_seconds": 0, "fade_seconds": 5},
]

ISSUE_CASES = [
    ({"every": [20, 30], "life": [25, 30]}, 1, "nearly always up"),
    ({"max_alive": 0}, 1, "none ever comes"),
    ({"form_dist": [2, 5]}, 1, "no warning"),
    ({"enabled": False, "max_alive": 0}, 0, None),
    ({}, 0, None),
]


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _gd_dict(text, name):
    i = text.find("const %s := {" % name)
    if i < 0:
        return None
    j = text.index("{", i)
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                body = re.sub(r",(\s*[}\]])", r"\1", text[j:k + 1])
                return json.loads(body)
    return None


def _gd_const(text, name):
    m = re.search(r"^const %s := ([0-9.]+)" % name, text, re.M)
    return float(m.group(1)) if m else None


def _same(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) < 1e-9
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a) == set(b) and all(_same(a[k], b[k]) for k in a)
    return a == b


# ------------------------------------------------------------------ a Python copy of DustDevils.config_of

def _num(v, fb):
    if isinstance(v, bool):
        return 1.0 if v else 0.0
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            return float(v)
        except ValueError:
            return fb
    return fb


def _bool(v):
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return float(v) != 0.0
    if isinstance(v, str):
        return v.lower() in ("true", "1", "yes", "on")
    return False


def _range(v, fb):
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return [float(v), float(v)]
    if isinstance(v, list) and v:
        a = _num(v[0], fb[0])
        b = _num(v[-1], a)
        return [min(a, b), max(a, b)]
    return list(fb)


def py_config(gd, block):
    o = json.loads(json.dumps(gd["DEFAULTS"]))
    if isinstance(block, dict):
        for k, v in block.items():
            if k == "toss" and isinstance(v, dict):
                o["toss"].update(v)
            else:
                o[k] = v
    o["enabled"] = _bool(o["enabled"])
    o["first"] = max(_num(o["first"], 90.0), 0.0)
    ev = _range(o["every"], [120.0, 180.0])
    o["every"] = [max(ev[0], gd["EVERY_MIN"]), max(ev[1], gd["EVERY_MIN"])]
    lf = _range(o["life"], [20.0, 30.0])
    o["form_seconds"] = max(_num(o["form_seconds"], 2.5), 0.1)
    o["fade_seconds"] = max(_num(o["fade_seconds"], 2.0), 0.1)
    least = o["form_seconds"] + o["fade_seconds"] + 1.0
    o["life"] = [max(lf[0], least), max(lf[1], least)]
    o["max_alive"] = max(int(_num(o["max_alive"], 1.0)), 0)
    o["radius"] = max(_num(o["radius"], 2.4), 0.2)
    o["speed"] = max(_num(o["speed"], 1.4), 0.0)
    o["wander"] = str(o["wander"]) if str(o["wander"]) in gd["WANDERS"] else "cross"
    o["miss"] = _num(o["miss"], 3.0)
    fd = _range(o["form_dist"], [7.0, 11.0])
    o["form_dist"] = [max(fd[0], 0.0), max(fd[1], max(fd[0], 0.0))]
    ts = o["toss"] if isinstance(o["toss"], dict) else {}
    o["toss"] = {"up": max(_num(ts.get("up", 8.0), 8.0), 0.0), "out": _num(ts.get("out", 3.6), 3.6),
                 "cooldown": max(_num(ts.get("cooldown", 1.2), 1.2), 0.0)}
    o["lift"] = max(_num(o["lift"], 1.7), 0.0)
    for k in ("warn", "in_boss", "in_portal", "in_endless"):
        o[k] = _bool(o[k])
    return o


def py_count(gd, c, length):
    if not c["enabled"] or length < c["first"]:
        return 0
    return 1 + int((length - c["first"]) // max((c["every"][0] + c["every"][1]) / 2.0, gd["EVERY_MIN"]))


def checks(check, run_node, server):
    src = _read(GAME, "core", "systems", "DustDevils.gd")
    wanders = re.search(r'^const WANDERS := \[([^\]]*)\]', src, re.M)
    gd = {"DEFAULTS": _gd_dict(src, "DEFAULTS"), "EVERY_MIN": _gd_const(src, "EVERY_MIN"), "HERO_REACH": _gd_const(src, "HERO_REACH"),
          "WANDERS": json.loads("[%s]" % wanders.group(1)) if wanders else None}
    check(all(v is not None for v in gd.values()), "TWISTER113: DustDevils.gd's DEFAULTS, EVERY_MIN, HERO_REACH, WANDERS read: %s" % [k for k, v in gd.items() if v is None])
    if any(v is None for v in gd.values()):
        return
    map_json = json.load(open(os.path.join(GAME, "content", "maps", "red_canyon", "red_canyon.json"), encoding="utf-8"))
    tl = map_json.get("timeline_data", {})
    stages = [{"name": s.get("name", "Stage %d" % (k + 1)), "length": float(s.get("length", 0))} for k, s in enumerate(tl.get("stage_list", []))] or \
        [{"name": "Stage 1", "length": 430.0}, {"name": "Stage 2", "length": 600.0}, {"name": "Stage 3", "length": 780.0}]
    count_cases = [[tl.get("dust_devils"), s["length"]] for s in stages] + [[None, 60], [None, 90], [{"first": 0, "every": 30}, 100], [{"enabled": False}, 900]]
    q = {"cases": CASES, "countCases": count_cases, "map": tl, "stages": stages, "issueCases": [c for c, _, _ in ISSUE_CASES]}
    res = run_node(q, RUNNER)
    if not res:
        check(False, "TWISTER113: dustdevil_card.js ran under Node")
        return

    # the table
    t = res["tables"]
    check(_same(t["DEFAULTS"], gd["DEFAULTS"]), "TWISTER113: dustdevil_card.js DEFAULTS are DustDevils': %s vs %s" % (t["DEFAULTS"], gd["DEFAULTS"]))
    check(_same(t["EVERY_MIN"], gd["EVERY_MIN"]) and _same(t["HERO_REACH"], gd["HERO_REACH"]) and t["WANDERS"] == gd["WANDERS"],
          "TWISTER113: the least gap, the hero's reach past the radius and the wanders match: %s" % t)
    d = gd["DEFAULTS"]
    check(d["enabled"] is True and d["first"] == 90 and d["every"] == [120, 180] and d["life"] == [20, 30] and d["max_alive"] == 1
          and d["toss"] == {"up": 8.0, "out": 3.6, "cooldown": 1.2} and d["lift"] == 1.7 and d["radius"] == 2.4,
          "TWISTER113: the game's defaults: rare (from 1:30, one every 2 to 3 minutes, 20 to 30 s each, one at a time), pass 44's toss and lift")

    # the reader against the Python copy
    bad = [(b, got, py_config(gd, b)) for b, got in zip(CASES, res["configs"]) if not _same(got, py_config(gd, b))]
    check(not bad, "TWISTER113: configOf == DustDevils.config_of on %d blocks: %s" % (len(CASES), bad[:2]))
    c = res["configs"]
    check(c[0]["enabled"] is True and c[2]["enabled"] is False and c[3]["every"] == [gd["EVERY_MIN"]] * 2 and c[3]["wander"] == "cross"
          and c[3]["toss"]["up"] == 5 and c[3]["toss"]["out"] == 3.6 and c[3]["max_alive"] == 0 and c[4]["every"] == [100, 200] and c[4]["form_dist"] == [4, 9],
          "TWISTER113: no block = on, the floors, an unknown wander, a half toss, ranges in order: %s" % c[3])

    # the count a stage
    want = [py_count(gd, py_config(gd, b), L) for b, L in count_cases]
    check(res["counts"] == want, "TWISTER113: countIn == DustDevils.count_in: %s vs %s" % (res["counts"], want))
    check(res["counts"][len(stages):] == [0, 1, 4, 0], "TWISTER113: none before the first, one at it, then one a gap: %s" % res["counts"][len(stages):])
    print("TWISTER113: Red Canyon's dust devils a stage (its own time): %s" % dict(zip([s["name"] for s in stages], res["counts"][:len(stages)])))
    print("TWISTER113: the card says: %s" % res["summary"])
    check(res["summary"].startswith("About ") and "ring" in res["summary"] and res["offSummary"].startswith("Off"),
          "TWISTER113: the line under the card names the count, the ring, and Off when off")

    # the warnings
    for (blk, n, word), got in zip(ISSUE_CASES, res["issues"]):
        check(len(got) == n and (word is None or word in got[0]), "TWISTER113: warnings on %s: %d%s: %s" % (json.dumps(blk), n, " (%r)" % word if word else "", got))
    check(not res["mapIssues"], "TWISTER113: Red Canyon's dust devils raise no warning: %s" % res["mapIssues"])

    # fields.js: the Dust devils card's rows
    rows = {x[0]: x for x in res["rows"]}
    want_keys = {"dust_devils." + k for k in d if k != "toss"} | {"dust_devils.toss." + k for k in d["toss"]}
    check(set(rows) == want_keys, "TWISTER113: fields.js has a row for every key: missing %s, extra %s" % (sorted(want_keys - set(rows)), sorted(set(rows) - want_keys)))
    greys = []
    for key, (k, group, typ, dv, helped, opts) in rows.items():
        part = key.split(".")
        game = d[part[1]] if len(part) == 2 else d[part[1]][part[2]]
        shown = game[0] if typ == "interval" and isinstance(game, list) else game
        if not (_same(dv, shown) and helped and group == "Dust devils"):
            greys.append((key, dv, shown, helped, group))
        if typ == "select" and opts != gd["WANDERS"]:
            greys.append((key, "options", opts))
    check(not greys, "TWISTER113: every row is in the Dust devils card, has help and is greyed with the game's number: %s" % greys[:4])
    g = res["groups"]
    check("Dust devils" in g and "Barrels" in g and g.index("Dust devils") == g.index("Barrels") + 1, "TWISTER113: the Dust devils card comes next to Barrels: %s" % g)

    # the page wiring
    idx = _read(HERE, "index.html")
    order = [idx.find(s) for s in ('src="fields.js"', 'src="barrel_card.js"', 'src="dustdevil_card.js"', 'src="settings.js"')]
    check(all(i >= 0 for i in order) and order[0] < order[2] and order[1] < order[2], "TWISTER113: index.html loads dustdevil_card.js after fields.js: %s" % order)
    st = _read(HERE, "settings.js")
    check("group === 'Dust devils'" in st and "DustDevilCard.block(tl)" in st, "TWISTER113: settings.js draws the line under the Dust devils card")

    # the game's wiring
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    check('t.get("dust_devils"' in jc and "var dust_devils: Dictionary" in wt, "TWISTER113: JsonContent reads dust_devils into WaveTimeline")
    rc = _read(GAME, "world", "maps", "red_canyon", "RedCanyon.gd")
    check("DustDevils.new()" in rc and "DustDevil.new()" not in rc and "loop_center" not in rc, "TWISTER113: the map makes the clock, not an always-on dust devil")
    dd = _read(GAME, "world", "features", "DustDevil.gd")
    check("TornadoFx.new()" in dd and "lift_radius" in dd and "pl.launch(" in dd, "TWISTER113: a dust devil wears a TornadoFx, lifts creatures and throws the hero")
    check(os.path.exists(os.path.join(GAME, "core", "systems", "TornadoFx.gd")) and "func set_strength(" in _read(GAME, "core", "systems", "TornadoFx.gd")
          and "func burst(" in _read(GAME, "core", "systems", "TornadoFx.gd"), "TWISTER113: TornadoFx's API (set_strength, burst) is there for the King's shell")
    blk = tl.get("dust_devils")
    print("TWISTER113: Red Canyon dust_devils %s" % (json.dumps(blk) if blk is not None else "(none: the game's defaults)"))
