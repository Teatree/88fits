"""Pass 100, lane SMALL: the one-shot passive item (`single` in the JSON: Phoenix Feather, Garry: "should still be a
revive item with 50% HP on revive. It can only be used once and doesn't feature any upgrades").

  content  Phoenix Feather is `single`, one level (one free revive), max_level 1, no revive_hp rungs;
  fields   assets_fields.js under Node: onLadder is false for a single item, the One-shot field is in the Levels tab,
           a single item with 2 levels / max_level 5 warns, a single card warns, a plain single item says nothing;
  page     assets.js's one-shot line; vocab.py's PASSIVE_DEFAULTS carries single False; server.py owns `single` and
           lists it on the passive record;
  tools    passive_ladder.py --check passes and refuses a single item; evolved_icons.items leaves it out;
  game     PassiveDef.single / on_ladder, JsonContent reads it, the UI reads on_ladder, the gdUnit suite is there.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
PASSIVES = os.path.join(ROOT, "game", "content", "passives")

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = M;
const F = require(path.join(dir, 'assets_fields.js'));
global.AFIELDS = F;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.onLadder = q.docs.map((d) => F.onLadder(d));
  const rules = F.RULES.passive.filter((r) => ['levels', 'max_level', 'single'].includes(r.key));
  out.issues = q.docs.map((d) => rules.filter((r) => r.when(d, { id: d.id, kind: 'passive' })).map((r) => [r.level, r.key, typeof r.msg === 'function' ? r.msg(d, { id: d.id, kind: 'passive' }) : r.msg]));
  const f = F.passive.find((r) => r.key === 'single');
  out.field = f ? { type: f.type, def: f.def, help: f.help || '', onItem: f.only ? f.only({}) : true, onCard: f.only ? f.only({ line: true }) : true } : null;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def content_checks(check):
    j = json.loads(_read(os.path.join(PASSIVES, "phoenix_feather", "phoenix_feather.json")) or "{}")
    levels = j.get("levels") or []
    check(j.get("single") is True and int(j.get("max_level", 0)) == 1 and len(levels) == 1
          and [e.get("stat") for e in levels[0]][:1] == ["phoenix_revive"] and float(levels[0][0].get("value", 0)) == 1.0
          # pass 115 (lane META): beside it the feather's own least revive health (phoenix_hp 0.5, Player.revive_share)
          and all(e.get("stat") in ("phoenix_revive", "phoenix_hp") for e in levels[0]),
          "SMALL100 content: Phoenix Feather is a one-shot item: single, max_level 1, one level of one free revive")
    check("revive_hp" not in json.dumps(levels), "SMALL100 content: Phoenix Feather carries no revive health rungs")


def field_checks(check, run_node):
    m = [[{"stat": "might", "op": "mul", "value": 0.1}]]
    docs = [
        {"id": "s_one", "name": "x", "rarity": "uncommon", "single": True, "levels": m, "max_level": 1},
        {"id": "s_two", "name": "x", "rarity": "uncommon", "single": True, "levels": m * 2, "max_level": 5},
        {"id": "s_card", "name": "x", "rarity": "common", "single": True, "line": True, "levels": m, "max_level": 4},
        {"id": "s_plain", "name": "x", "rarity": "uncommon", "levels": m * 5, "max_level": 5},
    ]
    r = run_node({"docs": docs}, RUNNER) or {}
    if not r:
        check(False, "SMALL100 fields: assets_fields.js ran under Node")
        return
    check(r.get("onLadder") == [False, False, False, True], "SMALL100 fields: onLadder: a single item is off the ladder: %s" % r.get("onLadder"))
    iss = r.get("issues") or [[], [], [], []]
    check(iss[0] == [], "SMALL100 fields: a single item with one level and max_level 1 says nothing: %s" % iss[0])
    keys1 = sorted({(m_[0], m_[1]) for m_ in iss[1]})
    check(("warn", "levels") in keys1 and ("warn", "max_level") in keys1 and not [x for x in iss[1] if x[0] == "error"],
          "SMALL100 fields: a single item with two levels and max_level 5 warns on both: %s" % iss[1])
    check([x for x in iss[2] if x[1] == "single" and x[0] == "warn"], "SMALL100 fields: a single card warns: %s" % iss[2])
    check(iss[3] == [], "SMALL100 fields: an uncommon ladder item with 5 levels is untouched: %s" % iss[3])
    f = r.get("field") or {}
    check(f.get("type") == "bool" and f.get("def") is False and f.get("onItem") is True and f.get("onCard") is False and "one level" in f.get("help", ""),
          "SMALL100 fields: the One-shot field (bool, off by default, on passive items only): %s" % f)


def page_checks(check):
    js = _read(os.path.join(HERE, "assets.js"))
    check("a one-shot item (pass 100): one level, never offered again once held, no rarity ladder" in js, "SMALL100 page: assets.js's one-shot line under the levels")
    saved = list(sys.path)
    sys.path.insert(0, HERE)
    try:
        import vocab
        check(vocab.PASSIVE_DEFAULTS.get("single") is False, "SMALL100 page: vocab.py: PASSIVE_DEFAULTS single False")
    finally:
        sys.path[:] = saved
    srv = _read(os.path.join(HERE, "server.py"))
    check('"evolves_from", "text", "single"}' in srv and '"single": bool(d.get("single", False))' in srv,
          "SMALL100 page: server.py owns `single` on a passive and lists it on the record")


def tool_checks(check):
    import subprocess
    p = subprocess.run([sys.executable, os.path.join(TOOLS, "passive_ladder.py"), "--check"], capture_output=True, text=True, encoding="utf-8", timeout=120)
    check(p.returncode == 0, "SMALL100 tools: passive_ladder.py --check passes without Phoenix Feather")
    pl = _read(os.path.join(TOOLS, "passive_ladder.py"))
    check('if doc.get("single"):' in pl and '"phoenix_feather": [[' not in pl, "SMALL100 tools: passive_ladder.py leaves the one-shot item alone")
    saved = list(sys.path)
    sys.path.insert(0, TOOLS)
    try:
        import evolved_icons
        check("phoenix_feather" not in [d for d, _dir, _j in evolved_icons.items()], "SMALL100 tools: evolved_icons.items leaves the one-shot item out")
    finally:
        sys.path[:] = saved


def game_checks(check):
    g = os.path.join(ROOT, "game")
    pd = _read(os.path.join(g, "core", "data", "PassiveDef.gd"))
    check("@export var single: bool = false" in pd and "func on_ladder() -> bool:" in pd, "SMALL100 game: PassiveDef.single and on_ladder")
    jc = _read(os.path.join(g, "core", "data", "JsonContent.gd"))
    check('p.single = bool(d.get("single", false))' in jc, "SMALL100 game: JsonContent reads single")
    for rel in (("core", "systems", "TextGen.gd"), ("ui", "CollectionScreen.gd"), ("ui", "wanted", "W.gd"), ("ui", "wanted", "WItem.gd")):
        check("on_ladder()" in _read(os.path.join(g, *rel)), "SMALL100 game: %s asks on_ladder" % rel[-1])
    t = _read(os.path.join(g, "tests", "pass100_SMALL_test.gd"))
    check("func test_phoenix_is_one_level_off_the_ladder() -> void:" in t, "SMALL100 game: the gdUnit suite is there")


def checks(check, run_node, server):
    content_checks(check)
    field_checks(check, run_node)
    page_checks(check)
    tool_checks(check)
    game_checks(check)
