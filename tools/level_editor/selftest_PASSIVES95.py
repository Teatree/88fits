"""Pass 95, lane PASSIVES: the passive items climb the rarity ladder (common 6 levels, uncommon 5, rare 4, epic 3; the
top is Evolved; PassiveDef.ladder_levels), their JSON holds every rung (tools/passive_ladder.py), every item has its
Evolved icon (tools/evolved_icons.py), and the Items tab knows the ladder (assets_fields.js: ladderLevels / rungAt /
onLadder, the levels rules, the help; assets.js names the rung beside each level; vocab.py's defaults). selftest.py
discovers this file (`extra_checks`) and hands it its `check` counter. Nothing here writes anything.

  content  every passive item (not a card, not an evolved form): levels == its ladder, max_level == its ladder, no
           empty rung, <id>_icon_evolved.png beside it; the CRLF files kept their line endings; the 21 cards and their
           Risen forms untouched (4 / 1 levels, no Evolved icon);
  tools    passive_ladder.py --check passes against the content; evolved_icons.evolved_icon draws a white rim round
           a subject and leaves the far ground clear;
  fields   assets_fields.js under Node: the ladder helpers, a 7-level common item is an error, a 3-level one a
           warning, a wrong max_level a warning, a card with 4 levels says nothing, the help names the ladder;
  page     assets.js names the rung beside each level and the ladder line; vocab.py: PASSIVE_DEFAULTS max_level 6,
           PASSIVE_LADDER in the served vocabulary;
  game     PassiveDef.gd carries the rule, W.gd the rung colours, TextGen the rung names (file greps only).
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
PASSIVES = os.path.join(ROOT, "game", "content", "passives")
LADDER = {"common": 6, "uncommon": 5, "rare": 4, "epic": 3, "legendary": 2}
CRLF_FILES = ["cold_snap", "guillotine", "hush_money", "vulture"]

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
  out.levels = q.rarities.map((r) => F.ladderLevels(r));
  out.rungs = q.rungs.map(([r, lv]) => F.rungAt(r, lv));
  out.names = q.rungs.map(([r, lv]) => F.rungName(r, lv));
  out.onLadder = q.docs.map((d) => F.onLadder(d));
  const rules = F.RULES.passive.filter((r) => r.key === 'levels' || r.key === 'max_level');
  out.issues = q.docs.map((d) => rules.filter((r) => r.when(d, { id: d.id, kind: 'passive' })).map((r) => [r.level, r.key, typeof r.msg === 'function' ? r.msg(d, { id: d.id, kind: 'passive' }) : r.msg]));
  out.help = F.passive.filter((r) => ['levels', 'max_level'].includes(r.key)).map((r) => r.help || '');
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(path, binary=False):
    try:
        with open(path, "rb" if binary else "r", **({} if binary else {"encoding": "utf-8"})) as f:
            return f.read()
    except OSError:
        return b"" if binary else ""


def _items():
    out = []
    for d in sorted(os.listdir(PASSIVES)):
        f = os.path.join(PASSIVES, d, d + ".json")
        if not os.path.isfile(f):
            continue
        j = json.loads(_read(f))
        out.append((d, j))
    return out


def content_checks(check):
    items = [(d, j) for d, j in _items() if not j.get("line") and not j.get("evolves_from")]
    cards = [(d, j) for d, j in _items() if j.get("line")]
    check(len(items) == 34, "PASSIVES95 content: 34 passive items on the ladder (%d)" % len(items))
    bad = []
    for d, j in items:
        want = LADDER.get(str(j.get("rarity", "common")), 6)
        levels = j.get("levels") or []
        if len(levels) != want or int(j.get("max_level", 0)) != want:
            bad.append("%s: %d levels, max_level %s, wants %d" % (d, len(levels), j.get("max_level"), want))
        if any(not lv for lv in levels):
            bad.append("%s: an empty rung" % d)
        if not os.path.isfile(os.path.join(PASSIVES, d, d + "_icon_evolved.png")):
            bad.append("%s: no Evolved icon" % d)
    check(not bad, "PASSIVES95 content: every item lists its ladder's rungs, max_level agrees, every rung gives something, the Evolved icon is beside it: %s" % bad)
    crlf_bad = [d for d in CRLF_FILES if b"\r\n" not in _read(os.path.join(PASSIVES, d, d + ".json"), binary=True)]
    check(not crlf_bad, "PASSIVES95 content: the CRLF files kept their line endings: %s" % crlf_bad)
    lf_bad = [d for d, j in items if d not in CRLF_FILES and b"\r\n" in _read(os.path.join(PASSIVES, d, d + ".json"), binary=True)]
    check(not lf_bad, "PASSIVES95 content: the LF files kept theirs: %s" % lf_bad)
    card_bad = [d for d, j in cards if int(j.get("max_level", 0)) != (1 if j.get("evolves_from") else 4) or os.path.isfile(os.path.join(PASSIVES, d, d + "_icon_evolved.png"))]
    check(len(cards) == 42 and not card_bad, "PASSIVES95 content: the 21 cards (4 levels) and their Risen forms (1) are untouched, none has an Evolved icon: %s" % card_bad)
    # the first level is higher than the committed one for every item (Garry: "stats on the 1st level will be higher")
    old_dir = os.path.join(TOOLS, "dl", "p95", "PASSIVES", "old")
    if os.path.isdir(old_dir):
        lower = []
        for d, j in items:
            o = os.path.join(old_dir, d + ".json")
            if not os.path.isfile(o):
                continue
            old = json.loads(_read(o))
            e_old = (old.get("levels") or [[]])[0]
            e_new = (j.get("levels") or [[]])[0]
            for a, b in zip(e_old, e_new):
                if a.get("stat") == b.get("stat") and abs(float(b.get("value", 0))) < abs(float(a.get("value", 0))) - 1e-9:
                    lower.append("%s %s %s -> %s" % (d, a.get("stat"), a.get("value"), b.get("value")))
        check(not lower, "PASSIVES95 content: no item's first level is lower than before: %s" % lower)


def tool_checks(check):
    p = subprocess.run([sys.executable, os.path.join(TOOLS, "passive_ladder.py"), "--check"], capture_output=True, text=True, encoding="utf-8", timeout=120)
    check(p.returncode == 0, "PASSIVES95 tools: passive_ladder.py --check matches the content: %s" % (p.stdout.strip().splitlines()[-1:] if p.stdout else p.stderr[-300:]))
    saved = list(sys.path)
    sys.path.insert(0, TOOLS)
    try:
        import evolved_icons
        from PIL import Image
        im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        for y in range(24, 40):
            for x in range(24, 40):
                im.putpixel((x, y), (200, 40, 40, 255))
        out = evolved_icons.evolved_icon(im, 4)
        rim = out.getpixel((21, 32))
        far = out.getpixel((4, 4))
        inside = out.getpixel((32, 32))
        check(out.size == im.size and rim[3] > 200 and rim[0] > 240 and rim[1] > 240 and far[3] == 0 and inside[:3] == (200, 40, 40),
              "PASSIVES95 tools: evolved_icon draws a white rim round the subject, keeps it, leaves the far ground clear (rim %s, far %s, inside %s)" % (rim, far, inside))
        check(len(evolved_icons.items()) == 34, "PASSIVES95 tools: evolved_icons.items lists the 34 items")
    finally:
        sys.path[:] = saved


def field_checks(check, run_node):
    docs = [
        {"id": "p95_common7", "name": "x", "rarity": "common", "levels": [[{"stat": "might", "op": "mul", "value": 0.1}]] * 7, "max_level": 7},
        {"id": "p95_common3", "name": "x", "rarity": "common", "levels": [[{"stat": "might", "op": "mul", "value": 0.1}]] * 3, "max_level": 6},
        {"id": "p95_epic3", "name": "x", "rarity": "epic", "levels": [[{"stat": "might", "op": "mul", "value": 0.1}]] * 3, "max_level": 5},
        {"id": "p95_card", "name": "x", "rarity": "common", "line": True, "levels": [[{"stat": "might", "op": "mul", "value": 0.1}]], "max_level": 4},
        {"id": "p95_risen", "name": "x", "rarity": "rare", "line": True, "evolves_from": "p95_card", "levels": [[{"stat": "might", "op": "mul", "value": 0.5}]], "max_level": 1},
        {"id": "p95_rare4", "name": "x", "rarity": "rare", "levels": [[{"stat": "might", "op": "mul", "value": 0.1}]] * 4, "max_level": 4},
    ]
    q = {"rarities": ["common", "uncommon", "rare", "epic", "legendary", "", "mythic"],
         "rungs": [["common", 1], ["common", 3], ["common", 6], ["rare", 2], ["rare", 4], ["epic", 3], ["legendary", 2], ["uncommon", 9]],
         "docs": docs}
    r = run_node(q, RUNNER) or {}
    if not r:
        check(False, "PASSIVES95 fields: assets_fields.js ran under Node")
        return
    check(r.get("levels") == [6, 5, 4, 3, 2, 6, 6], "PASSIVES95 fields: ladderLevels common 6 .. legendary 2, an unknown rarity common: %s" % r.get("levels"))
    check(r.get("rungs") == ["common", "rare", "evolved", "epic", "evolved", "evolved", "evolved", "evolved"], "PASSIVES95 fields: rungAt climbs a rarity a level and says evolved at the top and past it: %s" % r.get("rungs"))
    check(r.get("names") == ["Common", "Rare", "Evolved", "Epic", "Evolved", "Evolved", "Evolved", "Evolved"], "PASSIVES95 fields: rungName: %s" % r.get("names"))
    check(r.get("onLadder") == [True, True, True, False, False, True], "PASSIVES95 fields: onLadder: items yes, a card and a Risen card no: %s" % r.get("onLadder"))
    iss = r.get("issues") or []
    levels_of = lambda i, level: [m for m in iss[i] if m[0] == level and m[1] == "levels"]
    check(len(iss) == 6 and levels_of(0, "error") and "level 7 and up" in levels_of(0, "error")[0][2] and [m for m in iss[0] if m[1] == "max_level" and m[0] == "warn"],
          "PASSIVES95 fields: a common item with 7 levels is an error (and its max_level 7 a warning): %s" % (iss[0] if iss else iss))
    check(iss and levels_of(1, "warn") and not levels_of(1, "error") and not [m for m in iss[1] if m[1] == "max_level"], "PASSIVES95 fields: a common item with 3 levels is a warning, its max_level 6 fine: %s" % (iss[1] if iss else iss))
    check(iss and not levels_of(2, "warn") and not levels_of(2, "error") and [m for m in iss[2] if m[1] == "max_level" and "3 for epic" in m[2]], "PASSIVES95 fields: an epic item with 3 levels is right, its max_level 5 a warning: %s" % (iss[2] if iss else iss))
    check(iss and not iss[3] and not iss[4], "PASSIVES95 fields: a card with 4 levels and its Risen card say nothing: %s" % (iss[3:5] if iss else iss))
    check(iss and not iss[5], "PASSIVES95 fields: a rare item with 4 levels and max_level 4 says nothing: %s" % (iss[5] if iss else iss))
    help_ = r.get("help") or []
    check(len(help_) == 2 and "rarity ladder" in help_[0] and "common 6, uncommon 5, rare 4, epic 3" in help_[1], "PASSIVES95 fields: the levels and max_level help name the ladder: %s" % help_)


def page_checks(check):
    js = _read(os.path.join(HERE, "assets.js"))
    check("const ladder = doc.kind === 'passive' && F.onLadder(doc.data);" in js and "F.rungName(doc.data.rarity, lv)" in js and "rung(i + 1)" in js,
          "PASSIVES95 page: assets.js names the rung beside each level of a passive item")
    check("the rarity ladder (pass 95): ${F.ladderLevels(doc.data.rarity)} levels" in js, "PASSIVES95 page: assets.js's ladder line under the levels")
    af = _read(os.path.join(HERE, "assets_fields.js"))
    check("LADDER, ladderLevels, rungAt, rungName, onLadder," in af, "PASSIVES95 page: assets_fields.js exports the ladder helpers")
    saved = list(sys.path)
    sys.path.insert(0, HERE)
    try:
        import vocab
        check(vocab.PASSIVE_DEFAULTS.get("max_level") == 6 and vocab.PASSIVE_LADDER == LADDER, "PASSIVES95 page: vocab.py: a new (common) item defaults to 6 levels, PASSIVE_LADDER is the rule")
        served = vocab.table(os.path.join(ROOT, "game", "content"))
        check(served.get("passive_ladder") == LADDER and served.get("passive_defaults", {}).get("max_level") == 6, "PASSIVES95 page: the served vocabulary carries passive_ladder and the 6-level default")
    finally:
        sys.path[:] = saved


def game_checks(check):
    g = os.path.join(ROOT, "game")
    pd = _read(os.path.join(g, "core", "data", "PassiveDef.gd"))
    check("static func ladder_levels(p_rarity: String) -> int:" in pd and "func rung_at(level: int) -> String:" in pd and "func is_evolved_rung(level: int) -> bool:" in pd
          and "@export var evolved_icon: Texture2D" in pd and "func apply_ladder() -> void:" in pd, "PASSIVES95 game: PassiveDef.gd carries the ladder rule and the Evolved icon")
    jc = _read(os.path.join(g, "core", "data", "JsonContent.gd"))
    check("(res as PassiveDef).apply_ladder()" in jc and '_icon_evolved.png' in jc, "PASSIVES95 game: JsonContent derives max_level and loads the Evolved icon")
    w = _read(os.path.join(g, "ui", "wanted", "W.gd"))
    check("static func rung_of(def: ContentDef, level: int = 0) -> String:" in w and "static func is_evolved_rung(def: ContentDef, level: int) -> bool:" in w and "static func icon_at(def: ContentDef, level: int = 0) -> Texture2D:" in w,
          "PASSIVES95 game: W.gd: rung_of, is_evolved_rung, icon_at")
    tg = _read(os.path.join(g, "core", "systems", "TextGen.gd"))
    check("static func rung_name(def: PassiveDef, level: int) -> String:" in tg and '"Next level (%s): %s"' in tg, "PASSIVES95 game: TextGen names the rungs")
    wi = _read(os.path.join(g, "ui", "wanted", "WItem.gd"))
    check("static func rung_word(card: Dictionary) -> String:" in wi and '"EVOLVED": W.EMBER' in wi, "PASSIVES95 game: WItem: the rung after the kind's word, the EVOLVED tag")
    t = _read(os.path.join(g, "tests", "pass95_PASSIVES_test.gd"))
    check("func test_the_ladder_rule_per_rarity() -> void:" in t and "func test_a_level_past_the_top_loads_without_error() -> void:" in t, "PASSIVES95 game: the gdUnit suite is there")


def checks(check, run_node, server):
    content_checks(check)
    tool_checks(check)
    field_checks(check, run_node)
    page_checks(check)
    game_checks(check)
