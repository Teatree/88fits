"""Pass 112, lane BARREL: broken barrels coming back and what each barrel kind holds (Garry: "when I was talking about chest
appearing and stuff I actually meant barrels. Not chests. So apply whatever I said in that prompt to barrels, and revert
the chests to be as they were"). selftest.py discovers this file (`extra_checks`) and hands it its `check` counter, its
`run_node(query, runner_src)` and the `server` module. Nothing here writes.

Groups: the tables (game/core/systems/BarrelSpawns.gd's RESPAWN_DEFAULTS and CONTENT_DEFAULTS are barrel_model.js's);
the readers (respawnOf, contentsOf) on purpose-built blocks against a Python copy of the GDScript's rules; the turns a
stage (turnsIn) against the same sum; the page's checks (errors and warnings on purpose-built blocks; the map file raises
no error); fields.js (a row with help for every key, greyed with the game's number, in the Barrels card); the page's
wiring (index.html, settings.js, app.js) and the game's (JsonContent, WaveTimeline, BarrelField, PickupManager); pass
111's map chests gone (no world_chests / chest_contents anywhere, no CHEST tag, no Chests card).
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
const M = require(path.join(dir, 'barrel_model.js'));
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
  out.tables = { RESPAWN_DEFAULTS: M.RESPAWN_DEFAULTS, CONTENT_DEFAULTS: M.CONTENT_DEFAULTS, TYPES: M.TYPES, EVERY_MIN: M.EVERY_MIN, START_COUNT: M.START_COUNT };
  out.respawn = q.respawnCases.map((b) => M.respawnOf(b));
  out.contents = q.contentCases.map(([b, ty]) => M.contentsOf(b, ty));
  out.turns = q.turnCases.map(([b, len]) => M.turnsIn(M.respawnOf(b), len));
  out.issues = q.issueCases.map((tl) => M.issues(tl, q.pickups));
  out.mapIssues = M.issues(q.map, q.pickups);
  out.draw = M.drawList({ pickups: q.map.pickups }, 'brown');
  out.shares = M.shares([{ id: 'a', weight: 1 }, { id: 'b', weight: 3 }]);
  out.rows = FIELDS.SCALARS.filter((d) => d.key.startsWith('barrels.')).map((d) => [d.key, d.group, d.type, d.def, !!d.help, d.block || '']);
  out.chestRows = FIELDS.SCALARS.filter((d) => d.key.startsWith('world_chests.') || d.key.startsWith('chest_contents.')).length;
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""


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


# ------------------------------------------------------------------ a Python copy of BarrelSpawns.gd's readers

def _num(v, fb):
    if isinstance(v, bool):
        return 1.0 if v else 0.0
    if isinstance(v, (int, float)):
        return float(v)
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


def py_respawn(gd, block):
    own = block.get("respawn") if isinstance(block, dict) else None
    has = isinstance(own, dict) and len(own) > 0
    o = dict(gd["RESPAWN_DEFAULTS"])
    if has:
        o.update(own)
    o["enabled"] = has and _bool(o["enabled"])
    o["first"] = max(_num(o["first"], 45.0), 0.0)
    ev = _range(o["every"], [40.0, 60.0])
    o["every"] = [max(ev[0], gd["EVERY_MIN"]), max(ev[1], gd["EVERY_MIN"])]
    o["max_lying"] = max(int(_num(o["max_lying"], 35.0)), 0)
    o["max_per_stage"] = max(int(_num(o["max_per_stage"], 0.0)), 0)
    o["min_dist"] = max(_num(o["min_dist"], 20.0), 0.0)
    o["max_dist"] = max(_num(o["max_dist"], 40.0), o["min_dist"])
    o["black_chance"] = min(max(_num(o["black_chance"], 0.22), 0.0), 1.0)
    o["view_margin"] = max(_num(o["view_margin"], 2.0), 0.0)
    for k in ("in_boss", "in_portal", "in_endless"):
        o[k] = _bool(o[k])
    return o


def py_turns(gd, c, length):
    if not c["enabled"] or length < c["first"]:
        return 0
    mean = max((c["every"][0] + c["every"][1]) * 0.5, gd["EVERY_MIN"])
    n = 1 + int((length - c["first"]) // mean)
    return min(n, c["max_per_stage"]) if c["max_per_stage"] > 0 else n


RESPAWN_CASES = [
    None, {}, {"respawn": {}}, {"respawn": {"enabled": True}}, {"respawn": {"first": 10}},
    {"respawn": {"enabled": True, "every": 70}}, {"respawn": {"enabled": True, "every": [2, 3]}},
    {"respawn": {"enabled": True, "every": [60, 40]}}, {"respawn": {"enabled": True, "min_dist": 30, "max_dist": 20}},
    {"respawn": {"enabled": 1, "black_chance": 4, "in_boss": 0}},
]
CONTENT_CASES = [
    [None, "brown"], [None, "black"], [{"brown": {"powerup_chance": 0.1}}, "brown"], [{"brown": {"powerup_chance": 0.1}}, "black"],
    [{"black": {"powerups": {"nuke": 2, "heart": 0}, "throw_distance": 6, "coins": 3}}, "black"],
    [{"brown": {"powerups": [{"id": "rage", "weight": 0}, {"id": "sprint"}, {"weight": 3}], "powerup_chance": 3, "gems_small": -2, "coins": [5, 2]}}, "brown"],
]
# (timeline_data, errors, warnings, a word in the first message)
ROSTER = {"roster": [{"id": "heart", "weight": 1}]}
ISSUE_CASES = [
    ({}, 0, 0, None),
    ({"barrels": 5}, 1, 0, "block"),
    ({"barrels": {"respawn": {"enabled": True, "every": [60, 40]}}}, 1, 0, "every"),
    ({"barrels": {"respawn": {"enabled": True, "every": 5}}}, 0, 1, "free XP"),
    ({"barrels": {"respawn": {"enabled": True, "first": -1}}}, 1, 0, "first"),
    ({"barrels": {"respawn": {"enabled": True, "max_lying": 0}}}, 0, 1, "fills up"),
    ({"barrels": {"brown": {"powerups": [{"id": "pineapple", "weight": 1}]}}}, 1, 0, "unknown"),
    ({"barrels": {"black": {"powerup_chance": 1.5}}, "pickups": ROSTER}, 1, 1, "chance"),
    ({"barrels": {"brown": {"throw_distance": 1}}}, 0, 1, "feet"),
    ({"barrels": {"golden": {}}}, 0, 1, "not respawn"),
    ({"barrels": {"brown": {"powerup_chance": 0.3}}}, 0, 1, "nothing comes out"),
    ({"barrels": {"black": {"gems_small": 2.5, "coins": [4, 1]}}}, 2, 0, "gems_small"),
]
PICKUPS = ["heart", "rage", "sprint", "shield", "magnet_pulse", "nuke", "coin_bag", "cake_slice", "timeout"]


def checks(check, run_node, server):
    src = _read(GAME, "core", "systems", "BarrelSpawns.gd")
    gd = {"RESPAWN_DEFAULTS": _gd_dict(src, "RESPAWN_DEFAULTS"), "CONTENT_DEFAULTS": _gd_dict(src, "CONTENT_DEFAULTS"), "EVERY_MIN": _gd_const(src, "EVERY_MIN")}
    check(all(v is not None for v in gd.values()), "BARREL112: BarrelSpawns.gd's RESPAWN_DEFAULTS, CONTENT_DEFAULTS, EVERY_MIN read: %s" % [k for k, v in gd.items() if v is None])
    if any(v is None for v in gd.values()):
        return
    bf = _read(GAME, "core", "systems", "BarrelField.gd")
    count = int(re.search(r"^const COUNT := (\d+)", bf, re.M).group(1))
    frac = float(re.search(r"^const LIGHT_FRAC := ([0-9.]+)", bf, re.M).group(1))
    map_json = json.load(open(os.path.join(GAME, "content", "maps", "red_canyon", "red_canyon.json"), encoding="utf-8"))
    tl = map_json.get("timeline_data", {})
    lens = [float(s.get("length", 0)) for s in tl.get("stage_list", [])] or [430.0, 600.0, 780.0]
    q = {"respawnCases": RESPAWN_CASES, "contentCases": CONTENT_CASES,
         "turnCases": [[tl.get("barrels"), L] for L in lens] + [[{"respawn": {"enabled": True, "max_per_stage": 2}}, 780], [{"respawn": {"enabled": True, "first": 500}}, 430]],
         "issueCases": [c for c, _, _, _ in ISSUE_CASES], "map": tl, "pickups": PICKUPS}
    res = run_node(q, RUNNER)
    if not res:
        check(False, "BARREL112: barrel_model.js ran under Node")
        return

    # the tables
    t = res["tables"]
    check(_same(t["RESPAWN_DEFAULTS"], gd["RESPAWN_DEFAULTS"]), "BARREL112: barrel_model.js RESPAWN_DEFAULTS are BarrelSpawns': %s vs %s" % (t["RESPAWN_DEFAULTS"], gd["RESPAWN_DEFAULTS"]))
    check(_same(t["CONTENT_DEFAULTS"], gd["CONTENT_DEFAULTS"]), "BARREL112: barrel_model.js CONTENT_DEFAULTS are BarrelSpawns': %s vs %s" % (t["CONTENT_DEFAULTS"], gd["CONTENT_DEFAULTS"]))
    check(t["TYPES"] == ["brown", "black"] and _same(t["EVERY_MIN"], gd["EVERY_MIN"]) and t["START_COUNT"] == count,
          "BARREL112: the two kinds, the least gap, the start's %d barrels: %s %s %s" % (count, t["TYPES"], t["EVERY_MIN"], t["START_COUNT"]))
    cd = gd["CONTENT_DEFAULTS"]
    check(gd["RESPAWN_DEFAULTS"]["enabled"] is False and gd["RESPAWN_DEFAULTS"]["max_lying"] == count and abs(gd["RESPAWN_DEFAULTS"]["black_chance"] - frac) < 1e-9
          and cd["brown"]["powerup_chance"] == 0 and cd["black"]["powerup_chance"] == 0 and cd["brown"]["gems_small"] == 8 and cd["brown"]["gems_medium"] == 0
          and cd["brown"]["coins"] == 0 and cd["black"]["gems_small"] == 10 and cd["black"]["gems_medium"] == 4 and cd["black"]["coins"] == [1, 5],
          "BARREL112: the game's defaults are today's barrels: no respawn (Most standing = the start's %d, black %s), no power-up, 8 / 10+4 gems, 1-5 coins in a black one" % (count, frac))
    check("const COIN_MIN := 1" in bf and "const COIN_MAX := 5" in bf, "BARREL112: BarrelField's COIN_MIN..COIN_MAX still 1..5 (the black kind's default)")

    # the readers against the Python copy
    bad = [(b, got, py_respawn(gd, b)) for b, got in zip(RESPAWN_CASES, res["respawn"]) if not _same(got, py_respawn(gd, b))]
    check(not bad, "BARREL112: respawnOf == BarrelSpawns.respawn_of on %d blocks: %s" % (len(RESPAWN_CASES), bad[:2]))
    r = res["respawn"]
    check(r[0]["enabled"] is False and r[2]["enabled"] is False and r[3]["enabled"] is True and r[4]["enabled"] is False and r[6]["every"] == [5, 5],
          "BARREL112: no block / an empty one / one without enabled = off, enabled on, every floored at 5 s: %s" % [x["enabled"] for x in r[:5]])
    cs = res["contents"]
    check(cs[0]["coins"] == [0, 0] and cs[1]["coins"] == [1, 5] and cs[1]["gems_medium"] == 4 and cs[0]["throw_distance"] == [5, 7], "BARREL112: an empty block gives today's contents: %s" % cs[:2])
    check(cs[2]["powerup_chance"] == 0.1 and cs[3]["powerup_chance"] == 0, "BARREL112: each kind reads its own block only: %s %s" % (cs[2]["powerup_chance"], cs[3]["powerup_chance"]))
    check(cs[4]["powerups"] == [{"id": "nuke", "weight": 2}] and cs[4]["throw_distance"] == [6, 6] and cs[4]["coins"] == [3, 3],
          "BARREL112: a {id: weight} list, a weight of 0 dropped, one throw number, one coin number: %s" % cs[4])
    check(cs[5]["powerups"] == [{"id": "sprint", "weight": 1}] and cs[5]["powerup_chance"] == 1 and cs[5]["gems_small"] == 0 and cs[5]["coins"] == [2, 5],
          "BARREL112: rows without an id or weight dropped, a weight left out is 1, the chance clamped to 1, gems at least 0, a coin range in order: %s" % cs[5])

    # the turns a stage
    cfgs = [py_respawn(gd, b) for b, _ in q["turnCases"]]
    want = [py_turns(gd, c, L) for c, (_, L) in zip(cfgs, q["turnCases"])]
    check(res["turns"] == want, "BARREL112: turnsIn == BarrelSpawns.turns_in: %s vs %s" % (res["turns"], want))
    print("BARREL112: Red Canyon's respawn turns a stage (its own time, at most): %s" % dict(zip([s.get("name", "") for s in tl.get("stage_list", [])], res["turns"][:len(lens)])))

    # the page's checks
    for (tlc, ne, nw, word), got in zip(ISSUE_CASES, res["issues"]):
        errs = [m for m in got if m["level"] == "error"]
        warns = [m for m in got if m["level"] == "warn"]
        ok = len(errs) == ne and len(warns) == nw and (word is None or (got and word in got[0]["msg"]))
        check(ok, "BARREL112: the page's checks on %s: %d errors, %d warnings%s: %s" % (json.dumps(tlc)[:90], ne, nw, " (%r)" % word if word else "", got))
    map_errs = [m for m in res["mapIssues"] if m["level"] == "error"]
    check(not map_errs, "BARREL112: Red Canyon's barrels raise no error: %s" % map_errs)
    d = res["draw"]
    check(d["from"] == "drops" and [x["id"] for x in d["list"]] == [x["id"] for x in tl.get("pickups", {}).get("roster", [])],
          "BARREL112: a kind without a list draws from the Power-up drops roster: %s" % d)
    check(_same(res["shares"], [0.25, 0.75]), "BARREL112: shares are each weight's part of the total: %s" % res["shares"])

    # fields.js: the Barrels card's rows
    rows = {x[0]: x for x in res["rows"]}
    want_keys = {"barrels.respawn." + k for k in gd["RESPAWN_DEFAULTS"]} | {"barrels.%s.%s" % (ty, k) for ty in ("brown", "black") for k in cd[ty]}
    check(set(rows) == want_keys, "BARREL112: fields.js has a row for every key: missing %s, extra %s" % (sorted(want_keys - set(rows)), sorted(set(rows) - want_keys)))
    greys = []
    for key, (k, group, typ, dv, helped, blk) in rows.items():
        part = key.split(".")
        game = gd["RESPAWN_DEFAULTS"][part[2]] if part[1] == "respawn" else cd[part[1]][part[2]]
        shown = game[0] if typ == "interval" and isinstance(game, list) else game
        if not (_same(dv, shown) and helped and group == "Barrels"):
            greys.append((key, dv, shown, helped, group))
        if part[1] != "respawn" and blk != "barrel_contents":
            greys.append((key, "not in the contents block"))
    check(not greys, "BARREL112: every row is in the Barrels card, has help and is greyed with the game's number: %s" % greys[:4])
    check("Barrels" in res["groups"] and "Chests" not in res["groups"] and res["chestRows"] == 0, "BARREL112: the Barrels card is drawn, the Chests card gone: %s" % res["groups"])

    # the page wiring
    idx = _read(HERE, "index.html")
    order = [idx.find(s) for s in ('src="fields.js"', 'src="barrel_model.js"', 'src="barrel_card.js"')]
    check(all(i >= 0 for i in order) and order[0] < order[1] < order[2] and "chest_model.js" not in idx and "chest_card.js" not in idx,
          "BARREL112: index.html loads barrel_model.js then barrel_card.js, no chest scripts")
    st = _read(HERE, "settings.js")
    check("def.block === 'barrel_contents'" in st and "BarrelCard.block(tl)" in st and "BarrelCard.summary(tl)" in st and "ChestCard" not in st,
          "BARREL112: settings.js draws the Barrels card's block and its count line")
    app = _read(HERE, "app.js")
    check("BarrelModel.issues(d" in app and "ChestModel" not in app, "BARREL112: app.js checks the barrels (errors block Save)")

    # the game's wiring, and pass 111's map chests gone
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    check('t.get("barrels"' in jc and "var barrels: Dictionary" in wt, "BARREL112: JsonContent reads barrels into WaveTimeline")
    pm = _read(GAME, "core", "systems", "PickupManager.gd")
    check("func throw_powerup(" in pm and "BarrelField._throw_powerup" not in pm and "_throw_powerup(cc, at, pk)" in bf and "_tick_spawns(delta)" in bf,
          "BARREL112: a smashed barrel throws its power-up through PickupManager.throw_powerup and ticks the respawn clock")
    gone = []
    for parts in (("core", "data", "WaveTimeline.gd"), ("core", "data", "JsonContent.gd"), ("core", "systems", "PickupManager.gd"),
                  ("core", "systems", "Chest.gd"), ("ui", "HUD.gd"), ("core", "autoload", "Run.gd")):
        txt = _read(GAME, *parts)
        for w in ("world_chests", "chest_contents", "pointer_chest", "WorldChests", "throw_chest_powerup"):
            if w in txt:
                gone.append((parts[-1], w))
    check(not gone and not os.path.exists(os.path.join(GAME, "core", "systems", "WorldChests.gd")), "BARREL112: pass 111's map chests are gone from the game: %s" % gone)
    check("world_chests" not in tl and "chest_contents" not in tl, "BARREL112: the map file names no map chests")
    rb = tl.get("barrels", {})
    print("BARREL112: Red Canyon barrels respawn %s; power-up chance brown %s, black %s" % (
        json.dumps({k: rb.get("respawn", {}).get(k) for k in ("enabled", "first", "every", "max_lying")}),
        rb.get("brown", {}).get("powerup_chance"), rb.get("black", {}).get("powerup_chance")))
