"""Pass 95, lane BOSS: the Level Editor knows the two new built-in boss scripts (the King's `stomp`: a jump and three
landings; the Scorpion Elite's `tail_sniper`: the Saiga's beam from the tail, three in a row) and the common attack key
`chance`: vocab.ATTACKS / ATTACK_COMMON, assets_fields.js ATTACKS / ATTACK_COMMON (labels, help, keys; the nested blocks as
`json` rows, which enemies.js attackField renders), BossAttackDef.SCRIPTS, boss_attacks_io.BUILTINS and boss_model.js
SCRIPTS all agree; the content rows the game plays (the King's stomp and the volley's `trail`, the Scorpion's tail row)
and EnemyManager's match cases are there.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")
if HERE not in sys.path:
    sys.path.insert(0, HERE)

NEW = ("stomp", "tail_sniper")
STOMP_KEYS = ["stomps", "gap", "jump", "radius", "damage", "knockback", "lift"]
TAIL_KEYS = ["count", "gap", "aim", "lock", "lines", "cone_deg", "damage", "damage_from", "damage_mult", "beam", "muzzle", "sfx"]

RUNNER = r"""
const path = require('path');
const fs = require('fs');
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
  out.names = F.ATTACK_NAMES;
  out.attacks = {};
  for (const n of q.names) {
    const a = F.ATTACKS[n];
    out.attacks[n] = a ? { label: a.label, telegraph: a.telegraph, help: a.help || '', keys: a.keys.map((k) => [k.key, k.type, k.def === undefined ? null : k.def, !!k.help]),
      bad: a.keys.filter((k) => !k.key || !k.label || !k.type).length } : null;
  }
  out.common = F.ATTACK_COMMON.map((r) => [r.key, r.type]);
  out.options = F.attackOptions().map((o) => o.v);
  out.telegraph = { stomp: F.attackTelegraph({ name: 'stomp' }), tail: F.attackTelegraph({ name: 'tail_sniper' }), ownRing: F.attackTelegraph({ name: 'tail_sniper', telegraph: 'ring' }) };
  // the stomp's ring geometry: the radius as the row says
  out.geom = M.telegraphGeometry({ name: 'stomp', radius: 6 }, 'ring', 2.2);
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _js_array(src, name):
    m = re.search(r"const %s\s*(?::=|=)\s*\[(.*?)\];" % name, src, re.S)
    return re.findall(r"'([a-z_]+)'", m.group(1)) if m else []


def _gd_array(src, name):
    m = re.search(r"const %s\s*:?=\s*\[(.*?)\]" % name, src, re.S)
    return re.findall(r'"([a-z_]+)"', m.group(1)) if m else []


def checks(check, run_node, server):
    import vocab as VOCAB
    import boss_attacks_io as BAIO
    # 1. the Python tables
    for n in NEW:
        check(n in VOCAB.ATTACKS, "BOSS95: vocab.ATTACKS has %s" % n)
        check(n in BAIO.BUILTINS, "BOSS95: boss_attacks_io.BUILTINS has %s" % n)
    check(list(VOCAB.ATTACKS["stomp"]["keys"]) == STOMP_KEYS, "BOSS95: vocab's stomp keys are %s" % STOMP_KEYS)
    check(list(VOCAB.ATTACKS["tail_sniper"]["keys"]) == TAIL_KEYS, "BOSS95: vocab's tail_sniper keys are %s" % TAIL_KEYS)
    check(VOCAB.ATTACKS["stomp"]["telegraph"] == "ring" and VOCAB.ATTACKS["tail_sniper"]["telegraph"] == "none", "BOSS95: the stomp draws a ring, the tail sniper nothing")
    check(VOCAB.ATTACKS["stomp"]["keys"]["stomps"] == 3 and VOCAB.ATTACKS["stomp"]["keys"]["damage"] == 18.0 and VOCAB.ATTACKS["stomp"]["keys"]["gap"] == 0.45,
          "BOSS95: the stomp's defaults are the game's (3 stomps, 18 a stomp, a 0.45 s gap)")
    check(VOCAB.ATTACKS["tail_sniper"]["keys"]["count"] == 3 and VOCAB.ATTACKS["tail_sniper"]["keys"]["damage_mult"] == 2.0 and VOCAB.ATTACKS["tail_sniper"]["keys"]["aim"] == 1.0,
          "BOSS95: the tail sniper's defaults are the game's (3 beams, x2 the Saiga, a 1 s aim)")
    check("chance" in VOCAB.ATTACK_COMMON and VOCAB.ATTACK_COMMON["chance"] is None, "BOSS95: vocab.ATTACK_COMMON has `chance` with no default")
    check(VOCAB.check_against_source(GAME) == [], "BOSS95: vocab's tables agree with the game's code (the two new match cases)")
    # 2. the GDScript and JS tables
    gd = _read(GAME, "core", "data", "BossAttackDef.gd")
    scripts = _gd_array(gd, "SCRIPTS")
    check(all(n in scripts for n in NEW), "BOSS95: BossAttackDef.SCRIPTS has both")
    bm = _read(HERE, "boss_model.js")
    js_scripts = _js_array(bm, "SCRIPTS")
    check(all(n in js_scripts for n in NEW), "BOSS95: boss_model.js SCRIPTS has both")
    check(set(scripts) == set(js_scripts) == set(BAIO.BUILTINS) == set(VOCAB.ATTACKS), "BOSS95: the four built-in lists are one list")
    em = _read(GAME, "core", "systems", "EnemyManager.gd")
    for n in NEW:
        check(('\t\t\t\t"%s":\n' % n) in em, "BOSS95: EnemyManager's runner has the case %s" % n)
    for fn in ("_stomp_start", "_tick_stomps", "_stomp_land", "_stomp_end", "_tail_start", "_tick_tails", "_tail_fire", "_tail_end", "beam_hit", "tail_damage", "_attack_chance_misses", "_tumbleweed_volley_call"):
        check(("func %s(" % fn) in em, "BOSS95: EnemyManager has %s" % fn)
    check("_tick_stomps(delta, ppos)" in em and "_tick_tails(delta, ppos)" in em, "BOSS95: the runs are ticked")
    check(em.index("_tick_snipers(delta, ppos)") < em.index("_tick_tails(delta, ppos)"), "BOSS95: the tails tick after the Saiga's aims (SniperFx.begin())")
    enemies_js = _read(HERE, "enemies.js")
    check("r.type === 'json'" in enemies_js, "BOSS95: enemies.js attackField renders a json row (the nested blocks)")
    check("the 16 names EnemyManager knows" in enemies_js, "BOSS95: the add-attack hint counts 16 names")
    # 3. the page's tables under Node
    res = run_node({"names": list(NEW)}, RUNNER)
    if not res:
        check(False, "BOSS95: node ran assets_fields.js")
    else:
        for n in NEW:
            a = res["attacks"].get(n)
            check(bool(a), "BOSS95: assets_fields.js ATTACKS has %s" % n)
            if not a:
                continue
            check(a["bad"] == 0 and a["label"] and a["help"], "BOSS95: %s has a label, help and whole key rows" % n)
            keys = [k[0] for k in a["keys"]]
            want = STOMP_KEYS if n == "stomp" else TAIL_KEYS
            check(keys == want, "BOSS95: assets_fields.js %s keys are vocab's (%s)" % (n, keys))
            check(all(k[3] for k in a["keys"] if k[1] == "json"), "BOSS95: every json row of %s says what goes in it" % n)
            jsonkeys = [k[0] for k in a["keys"] if k[1] == "json"]
            check(jsonkeys == (["jump"] if n == "stomp" else ["beam", "muzzle", "sfx"]), "BOSS95: the nested blocks of %s are json rows (%s)" % (n, jsonkeys))
        check(res["attacks"]["stomp"]["telegraph"] == "ring" and res["attacks"]["tail_sniper"]["telegraph"] == "none", "BOSS95: the JS telegraphs are vocab's")
        check(["chance", "number"] in res["common"], "BOSS95: assets_fields.js ATTACK_COMMON has `chance`")
        check(all(n in res["names"] for n in NEW) and all(n in res["options"] for n in NEW), "BOSS95: both are offered in the attack select")
        check(res["telegraph"] == {"stomp": "ring", "tail": "none", "ownRing": "ring"}, "BOSS95: attackTelegraph reads the usual, or the row's own")
        g = res["geom"]
        check(isinstance(g, dict) and any(abs(float(v) - 6.0) < 1e-6 for v in _numbers(g)), "BOSS95: the stomp's ring picture is 6 m (%s)" % json.dumps(g)[:120])
    # 4. the content
    king = json.load(open(os.path.join(CONTENT, "bosses", "tumbleweed_king", "tumbleweed_king.json"), encoding="utf-8"))
    rows = {a["name"]: a for a in king["boss"]["attacks"]}
    check("stomp" in rows and "slam" not in rows, "BOSS95: the King's slam row is the stomp")
    st = rows.get("stomp", {})
    # (pass 115, lane BOSS: the radius 6.0 -> 7.5, Garry's "Increase the range of the Tumbleweed King thump attack ... by 25%")
    check(st.get("stomps") == 3 and abs(float(st.get("gap", 0)) - 0.45) < 1e-9 and st.get("jump") == {"height": 2.2, "up": 0.35, "down": 0.2} and st.get("damage") == 18 and st.get("radius") == 7.5 and st.get("telegraph") == "ring",
          "BOSS95: the King's stomp row carries the brief's numbers")
    tr = rows.get("tumbleweed_volley", {}).get("trail", {})
    check(all(k in tr for k in ("style", "colour", "alpha", "width", "life", "puffs")), "BOSS95: the King's volley row carries its trail look")
    sc = json.load(open(os.path.join(CONTENT, "enemies", "dune_scorpion", "dune_scorpion.json"), encoding="utf-8"))
    srows = {a["name"]: a for a in sc["boss"]["attacks"]}
    tl = srows.get("tail_sniper", {})
    check(tl.get("count") == 3 and tl.get("damage_from") == "saiga_sniper" and tl.get("damage_mult") == 2.0 and tl.get("chance") == 0.7 and tl.get("min_range") == 5.0
          and tl.get("muzzle", {}).get("up") == 2.0 and tl.get("beam", {}).get("length") == 60.0 and tl.get("telegraph") == "none",
          "BOSS95: the Scorpion's tail row carries the brief's numbers")
    check(king["hp"] >= 1440 and sc["hp"] >= 260, "BOSS95: Garry's health numbers stand (never lowered by the lane)")
    # every row's keys are ones the page knows (no yellow "keys it does not read")
    for name, row, keys in (("stomp", st, STOMP_KEYS), ("tail_sniper", tl, TAIL_KEYS)):
        common = set(VOCAB.ATTACK_COMMON) | set(keys)
        unknown = [k for k in row if k not in common]
        check(not unknown, "BOSS95: the %s row has no key the page does not read (%s)" % (name, unknown))


def _numbers(obj):
    if isinstance(obj, dict):
        for v in obj.values():
            yield from _numbers(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _numbers(v)
    elif isinstance(obj, (int, float)) and not isinstance(obj, bool):
        yield obj
