"""Pass 111, lane CHEST: the map's own chests and what each chest type holds (Garry: "Chests should respawn every now and
then. They should also have a chance of a power up dropping from them ... I should be able to set the frequency and
content probabilities of both chest types on LevelEditor ... Chests never spawn where Player can see them").
selftest.py discovers this file (`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and
the `server` module. Nothing here writes.

Groups: the tables (game/core/systems/WorldChests.gd's DEFAULTS and CONTENT_DEFAULTS are chest_model.js's); the readers
(cfgOf, contentsOf, weightList) on purpose-built blocks against a Python copy of the GDScript's rules; the count a stage
(expectedIn) against the same sum; the page's checks (errors and warnings on purpose-built blocks; the map file raises
no error); fields.js (a row with help for every key, greyed with the game's number, in the Chests card); the page's
wiring (index.html, settings.js, app.js) and the game's (JsonContent, WaveTimeline, PickupManager, HUD, Run).
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
const M = require(path.join(dir, 'chest_model.js'));
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
  out.tables = { DEFAULTS: M.DEFAULTS, CONTENT_DEFAULTS: M.CONTENT_DEFAULTS, TYPES: M.TYPES, EVERY_MIN: M.EVERY_MIN };
  out.cfg = q.cfgCases.map((b) => M.cfgOf(b));
  out.contents = q.contentCases.map(([b, ty]) => M.contentsOf(b, ty));
  out.expected = q.expectCases.map(([b, len]) => M.expectedIn(M.cfgOf(b), len));
  out.issues = q.issueCases.map((tl) => M.issues(tl, q.pickups));
  out.mapIssues = M.issues(q.map, q.pickups);
  out.draw = [M.drawList(q.map, 'normal'), M.drawList({ pickups: q.map.pickups }, 'boss')];
  out.shares = M.shares([{ id: 'a', weight: 1 }, { id: 'b', weight: 3 }]);
  out.rows = FIELDS.SCALARS.filter((d) => d.key.startsWith('world_chests.') || d.key.startsWith('chest_contents.')).map((d) => [d.key, d.group, d.type, d.def, !!d.help, d.block || '']);
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
        return a is b or a == b and type(a) == type(b)
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) < 1e-9
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a) == set(b) and all(_same(a[k], b[k]) for k in a)
    return a == b


# ------------------------------------------------------------------ a Python copy of WorldChests.gd's readers

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


def py_cfg(gd, block):
    has = isinstance(block, dict) and len(block) > 0
    o = dict(gd["DEFAULTS"])
    if has:
        o.update(block)
    o["enabled"] = has and _bool(o["enabled"])
    o["first"] = max(_num(o["first"], 60.0), 0.0)
    ev = _range(o["every"], [90.0, 130.0])
    o["every"] = [max(ev[0], gd["EVERY_MIN"]), max(ev[1], gd["EVERY_MIN"])]
    o["max_on_map"] = max(int(_num(o["max_on_map"], 2.0)), 0)
    o["max_per_stage"] = max(int(_num(o["max_per_stage"], 0.0)), 0)
    o["min_dist"] = max(_num(o["min_dist"], 25.0), 0.0)
    o["max_dist"] = max(_num(o["max_dist"], 45.0), o["min_dist"])
    o["boss_chance"] = min(max(_num(o["boss_chance"], 0.0), 0.0), 1.0)
    o["lifetime"] = max(_num(o["lifetime"], 150.0), 0.0)
    o["view_margin"] = max(_num(o["view_margin"], 3.0), 0.0)
    for k in ("in_boss", "in_portal", "in_endless", "pointer"):
        o[k] = _bool(o[k])
    return o


def py_expected(gd, c, length):
    if not c["enabled"] or length < c["first"]:
        return 0
    mean = max((c["every"][0] + c["every"][1]) * 0.5, gd["EVERY_MIN"])
    n = 1 + int((length - c["first"]) // mean)
    return min(n, c["max_per_stage"]) if c["max_per_stage"] > 0 else n


CFG_CASES = [
    None, {}, {"enabled": True}, {"enabled": False, "first": 10},
    {"enabled": True, "every": 70}, {"enabled": True, "every": [2, 3]}, {"enabled": True, "every": [130, 90]},
    {"enabled": True, "min_dist": 30, "max_dist": 20}, {"enabled": True, "boss_chance": 4}, {"enabled": 1, "pointer": 0},
]
CONTENT_CASES = [
    [None, "normal"], [None, "boss"], [{"normal": {"powerup_chance": 0.35}}, "normal"], [{"normal": {"powerup_chance": 0.35}}, "boss"],
    [{"boss": {"powerups": {"nuke": 2, "heart": 0}, "throw_distance": 6, "mutation": False}}, "boss"],
    [{"normal": {"powerups": [{"id": "rage", "weight": 0}, {"id": "sprint"}, {"weight": 3}], "powerup_chance": 3, "gold": -5}}, "normal"],
]
# (timeline_data, errors, warnings, a word in the first message)
ISSUE_CASES = [
    ({}, 0, 0, None),
    ({"world_chests": 5}, 1, 0, "block"),
    ({"world_chests": {"enabled": True, "every": [130, 90]}}, 1, 0, "every"),
    ({"world_chests": {"enabled": True, "every": 10}}, 0, 1, "a lot"),
    ({"world_chests": {"enabled": True, "first": -1}}, 1, 0, "first"),
    ({"world_chests": {"enabled": True, "max_on_map": 0, "lifetime": 0}}, 0, 1, "pile up"),
    ({"chest_contents": {"normal": {"powerups": [{"id": "pineapple", "weight": 1}]}}}, 1, 0, "unknown"),
    ({"chest_contents": {"boss": {"powerup_chance": 1.5}}, "pickups": {"roster": [{"id": "heart", "weight": 1}]}}, 1, 0, "chance"),
    ({"chest_contents": {"normal": {"throw_distance": 1}}}, 0, 1, "feet"),
    ({"chest_contents": {"golden": {}}}, 0, 1, "not a chest type"),
    ({"chest_contents": {"normal": {"powerup_chance": 0.5}}}, 0, 1, "nothing comes out"),
]
PICKUPS = ["heart", "rage", "sprint", "shield", "magnet_pulse", "nuke", "coin_bag", "cake_slice", "timeout"]


def checks(check, run_node, server):
    src = _read(GAME, "core", "systems", "WorldChests.gd")
    gd = {"DEFAULTS": _gd_dict(src, "DEFAULTS"), "CONTENT_DEFAULTS": _gd_dict(src, "CONTENT_DEFAULTS"), "EVERY_MIN": _gd_const(src, "EVERY_MIN")}
    check(all(v is not None for v in gd.values()), "CHEST111: WorldChests.gd's DEFAULTS, CONTENT_DEFAULTS, EVERY_MIN read: %s" % [k for k, v in gd.items() if v is None])
    if any(v is None for v in gd.values()):
        return
    map_json = json.load(open(os.path.join(GAME, "content", "maps", "red_canyon", "red_canyon.json"), encoding="utf-8"))
    tl = map_json.get("timeline_data", {})
    lens = [float(s.get("length", 0)) for s in tl.get("stage_list", [])] or [430.0, 600.0, 780.0]
    q = {"cfgCases": CFG_CASES, "contentCases": CONTENT_CASES,
         "expectCases": [[tl.get("world_chests"), L] for L in lens] + [[{"enabled": True, "max_per_stage": 2}, 780], [{"enabled": True, "first": 500}, 430]],
         "issueCases": [c for c, _, _, _ in ISSUE_CASES], "map": tl, "pickups": PICKUPS}
    res = run_node(q, RUNNER)
    if not res:
        check(False, "CHEST111: chest_model.js ran under Node")
        return

    # the tables
    t = res["tables"]
    check(_same(t["DEFAULTS"], gd["DEFAULTS"]), "CHEST111: chest_model.js DEFAULTS are WorldChests.DEFAULTS: %s vs %s" % (t["DEFAULTS"], gd["DEFAULTS"]))
    check(_same(t["CONTENT_DEFAULTS"], gd["CONTENT_DEFAULTS"]), "CHEST111: chest_model.js CONTENT_DEFAULTS are WorldChests.CONTENT_DEFAULTS: %s vs %s" % (t["CONTENT_DEFAULTS"], gd["CONTENT_DEFAULTS"]))
    check(t["TYPES"] == ["normal", "boss"] and _same(t["EVERY_MIN"], gd["EVERY_MIN"]), "CHEST111: the two chest types and the least gap: %s %s" % (t["TYPES"], t["EVERY_MIN"]))
    check(gd["DEFAULTS"]["enabled"] is False and gd["CONTENT_DEFAULTS"]["normal"]["powerup_chance"] == 0 and gd["CONTENT_DEFAULTS"]["boss"]["powerup_chance"] == 0
          and gd["CONTENT_DEFAULTS"]["normal"]["new_item_weight"] == 0.45 and gd["CONTENT_DEFAULTS"]["normal"]["gold"] == 50 and gd["CONTENT_DEFAULTS"]["boss"]["mutation"] is True,
          "CHEST111: the game's defaults are today's: no map chests, no power-up, the reel's 0.45 and 50 gold, the boss chest's mutation")

    # the readers against the Python copy
    bad = []
    for b, got in zip(CFG_CASES, res["cfg"]):
        want = py_cfg(gd, b)
        if not _same(got, want):
            bad.append((b, got, want))
    check(not bad, "CHEST111: cfgOf == WorldChests.cfg_of on %d blocks: %s" % (len(CFG_CASES), bad[:2]))
    c0, c2, c5 = res["cfg"][0], res["cfg"][2], res["cfg"][5]
    check(c0["enabled"] is False and c2["enabled"] is True and c5["every"] == [5, 5], "CHEST111: no block = off, enabled on, every floored at 5 s: %s %s %s" % (c0["enabled"], c2["enabled"], c5["every"]))
    cs = res["contents"]
    check(_same(cs[0], gd["CONTENT_DEFAULTS"]["normal"] | {"throw_distance": [5, 7]}) and cs[1]["mutation"] is True, "CHEST111: an empty block gives today's contents: %s" % cs[:2])
    check(cs[2]["powerup_chance"] == 0.35 and cs[3]["powerup_chance"] == 0, "CHEST111: each type reads its own block only: %s %s" % (cs[2]["powerup_chance"], cs[3]["powerup_chance"]))
    check(cs[4]["powerups"] == [{"id": "nuke", "weight": 2}] and cs[4]["throw_distance"] == [6, 6] and cs[4]["mutation"] is False,
          "CHEST111: a {id: weight} list, a weight of 0 dropped, one throw number, the boss's mutation off: %s" % cs[4])
    check(cs[5]["powerups"] == [{"id": "sprint", "weight": 1}] and cs[5]["powerup_chance"] == 1 and cs[5]["gold"] == 0,
          "CHEST111: rows without an id or weight dropped, a weight left out is 1, the chance clamped to 1, gold at least 0: %s" % cs[5])

    # the count a stage
    cfgs = [py_cfg(gd, b) for b, _ in q["expectCases"]]
    want = [py_expected(gd, c, L) for c, (_, L) in zip(cfgs, q["expectCases"])]
    check(res["expected"] == want, "CHEST111: expectedIn == WorldChests.expected_in: %s vs %s" % (res["expected"], want))
    print("CHEST111: Red Canyon's map chests a stage (its own time, every turn finding room): %s" % dict(zip([s.get("name", "") for s in tl.get("stage_list", [])], res["expected"][:len(lens)])))

    # the page's checks
    for (tlc, ne, nw, word), got in zip(ISSUE_CASES, res["issues"]):
        errs = [m for m in got if m["level"] == "error"]
        warns = [m for m in got if m["level"] == "warn"]
        ok = len(errs) == ne and len(warns) == nw and (word is None or (got and word in got[0]["msg"]))
        check(ok, "CHEST111: the page's checks on %s: %d errors, %d warnings%s: %s" % (json.dumps(tlc)[:90], ne, nw, " (%r)" % word if word else "", got))
    map_errs = [m for m in res["mapIssues"] if m["level"] == "error"]
    check(not map_errs, "CHEST111: Red Canyon's chests raise no error: %s" % map_errs)
    d0, d1 = res["draw"]
    check(d1["from"] == "drops" and [r["id"] for r in d1["list"]] == [r["id"] for r in tl.get("pickups", {}).get("roster", [])],
          "CHEST111: a chest type without a list draws from the Power-up drops roster: %s" % d1)
    check(_same(res["shares"], [0.25, 0.75]), "CHEST111: shares are each weight's part of the total: %s" % res["shares"])

    # fields.js: the Chests card's rows
    rows = {r[0]: r for r in res["rows"]}
    want_keys = {"world_chests." + k for k in gd["DEFAULTS"]} | {"chest_contents.%s.%s" % (ty, k) for ty in ("normal", "boss") for k in gd["CONTENT_DEFAULTS"][ty]}
    check(set(rows) == want_keys, "CHEST111: fields.js has a row for every key: missing %s, extra %s" % (sorted(want_keys - set(rows)), sorted(set(rows) - want_keys)))
    greys = []
    for key, (k, group, typ, dv, helped, blk) in rows.items():
        part = key.split(".")
        game = gd["DEFAULTS"][part[1]] if part[0] == "world_chests" else gd["CONTENT_DEFAULTS"][part[1]][part[2]]
        shown = game[0] if typ == "interval" and isinstance(game, list) else game
        if not (_same(dv, shown) and helped and group == "Chests"):
            greys.append((key, dv, shown, helped, group))
        if part[0] == "chest_contents" and blk != "chest_contents":
            greys.append((key, "not in the contents block"))
    check(not greys, "CHEST111: every row is in the Chests card, has help and is greyed with the game's number: %s" % greys[:4])
    check("Chests" in res["groups"], "CHEST111: the Chests card is drawn: %s" % res["groups"])

    # the page wiring
    idx = _read(HERE, "index.html")
    order = [idx.find(s) for s in ('src="fields.js"', 'src="chest_model.js"', 'src="chest_card.js"')]
    check(all(i >= 0 for i in order) and order[0] < order[1] < order[2], "CHEST111: index.html loads chest_model.js then chest_card.js")
    st = _read(HERE, "settings.js")
    check("def.block === 'chest_contents'" in st and "ChestCard.block(tl)" in st and "ChestCard.summary(tl)" in st, "CHEST111: settings.js draws the Chests card's block and its count line")
    check("ChestModel.issues(d" in _read(HERE, "app.js"), "CHEST111: app.js checks the chests (errors block Save)")

    # the game's wiring
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    check('t.get("world_chests"' in jc and 't.get("chest_contents"' in jc and "var world_chests: Dictionary" in wt and "var chest_contents: Dictionary" in wt,
          "CHEST111: JsonContent reads world_chests and chest_contents into WaveTimeline")
    pm = _read(GAME, "core", "systems", "PickupManager.gd")
    check("throw_chest_powerup(c.global_position, c.boss)" in pm and "func pointer_chest()" in pm and "_tick_world(delta)" in pm,
          "CHEST111: PickupManager throws a chest's power-up on opening, ticks the map chests and names the one to point at")
    check("pointer_chest()" in _read(GAME, "ui", "HUD.gd"), "CHEST111: the HUD's edge tags point at the map's chest")
    run = _read(GAME, "core", "autoload", "Run.gd")
    check("WorldChests.contents_of(" in run and "chest_candidates(float(cc[\"new_item_weight\"]))" in run, "CHEST111: Run.chest_roll reads the chest type's reel knobs")
    wc = tl.get("world_chests", {})
    print("CHEST111: Red Canyon world_chests %s; chest_contents power-up chance normal %s, boss %s" % (
        json.dumps({k: wc.get(k) for k in ("enabled", "first", "every", "max_on_map", "lifetime")}),
        tl.get("chest_contents", {}).get("normal", {}).get("powerup_chance"), tl.get("chest_contents", {}).get("boss", {}).get("powerup_chance")))
