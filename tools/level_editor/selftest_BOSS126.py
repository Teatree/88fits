"""Pass 126, lane BOSS: the Level Editor knows Black Sunday's kit: the new built-in attack `whirl` (vocab.ATTACKS, assets_fields.js
ATTACKS, BossAttackDef.SCRIPTS, boss_attacks_io.BUILTINS, boss_model.js SCRIPTS and EnemyManager's match all agree, its
defaults are BossWhirl.DEFAULTS'), the new bullet look `grit_clod` and barrier look `cross_fence` (every table), his row and
his bullet heaven as content, his HP tables.

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

KEYS = ["radius", "seconds", "speed", "turn", "damage", "toss", "lift", "lift_height", "fling", "landing_damage",
        "landing_damage_big", "dazed", "look", "sound", "end_sound"]

JS = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const AM = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = AM;
const F = require(path.join(dir, 'assets_fields.js'));
const M = require(path.join(dir, 'boss_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const out = {};
  const A = F.ATTACKS.whirl;
  out.keys = A.keys.map((k) => k.key);
  out.defs = {};
  for (const k of A.keys) out.defs[k.key] = k.def;
  out.jsons = A.keys.filter((k) => k.type === 'json').map((k) => k.key);
  out.telegraph = A.telegraph;
  out.scripts = M.SCRIPTS.includes('whirl');
  out.looks = M.LOOKS.includes('grit_clod');
  out.barrier = (M.BARRIER_LOOKS || []).includes('cross_fence');
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    with open(os.path.join(*parts), encoding="utf-8") as f:
        return f.read()


def checks(check, run_node, server):
    import vocab as VOCAB
    import boss_attacks_io as BAIO
    # 1. the tables
    check("whirl" in VOCAB.ATTACKS, "BOSS126: vocab.ATTACKS has whirl")
    row = VOCAB.ATTACKS.get("whirl", {})
    check(list(row.get("keys", {})) == KEYS, "BOSS126: vocab's whirl keys are %s" % KEYS)
    check(row.get("telegraph") == "ring" and row.get("needs_ring_at_hero") is False, "BOSS126: the whirl draws a ring round him")
    check("whirl" in BAIO.BUILTINS, "BOSS126: boss_attacks_io.BUILTINS has whirl")
    check("cross_fence" in BAIO.BARRIER_CHOICES["look"], "BOSS126: the io's barrier looks have the fence of crosses")
    gd = _read(GAME, "core", "data", "BossAttackDef.gd")
    check('"whirl"' in re.search(r"const SCRIPTS := \[(.*?)\]", gd, re.S).group(1), "BOSS126: BossAttackDef.SCRIPTS has whirl")
    check('"grit_clod"' in re.search(r"const LOOKS := \[(.*?)\]", gd).group(1), "BOSS126: BossAttackDef.LOOKS has grit_clod")
    check('"cross_fence"' in re.search(r"const BARRIER_LOOKS := \[(.*?)\]", gd).group(1), "BOSS126: BossAttackDef.BARRIER_LOOKS has cross_fence")
    fx = _read(GAME, "core", "systems", "BossAttackFx.gd")
    check('"grit_clod"' in re.search(r"const BILLBOARD_LOOKS := \[(.*?)\]", fx).group(1) and '"grit_clod": 0.34' in fx, "BOSS126: the bullet draws, its radius named")
    em = _read(GAME, "core", "systems", "EnemyManager.gd")
    check('"whirl":' in em and "whirls.tick(delta, ppos)" in em, "BOSS126: EnemyManager's fire step and tick know the whirl")
    # 2. the defaults are the game's
    w = _read(GAME, "core", "systems", "BossWhirl.gd")
    block = re.search(r"const DEFAULTS := \{(.*?)\n\}", w, re.S).group(1)
    for key in ("radius", "seconds", "speed", "turn", "damage", "lift", "lift_height", "fling", "landing_damage", "landing_damage_big"):
        m = re.search(r'"%s":\s*([0-9.]+)' % key, block)
        check(m is not None and float(m.group(1)) == float(row["keys"][key]), "BOSS126: vocab's %s is BossWhirl.DEFAULTS'" % key)
    # 3. the page's tables
    res = run_node({}, JS)
    check(isinstance(res, dict), "BOSS126: the page's tables load")
    if isinstance(res, dict):
        check(res["keys"] == KEYS, "BOSS126: assets_fields' whirl keys are vocab's: %s" % res["keys"])
        check(res["jsons"] == ["toss", "dazed", "look"], "BOSS126: its nested blocks are json rows: %s" % res["jsons"])
        check(res["telegraph"] == "ring" and res["scripts"] and res["looks"] and res["barrier"], "BOSS126: telegraph, SCRIPTS, LOOKS, BARRIER_LOOKS")
        check(all(float(res["defs"][k]) == float(row["keys"][k]) for k in ("radius", "seconds", "speed", "damage", "fling", "landing_damage")), "BOSS126: the page's numbers are the game's")
    # 4. the content
    d = json.loads(_read(CONTENT, "bosses", "black_sunday", "black_sunday.json"))
    rows = {a["name"]: a for a in d["boss"]["attacks"]}
    check(set(("roll", "spawn_ring", "tumbleweed_volley", "whirl", "black_blizzard")) <= set(rows), "BOSS126: his five rows")
    check(all(k in KEYS or k in ("name", "windup", "telegraph", "max_range") for k in rows["whirl"]), "BOSS126: his whirl row names only keys the game reads: %s" % sorted(rows["whirl"]))
    check(d["boss"]["chest"]["name"] == "Collection Box" and d["boss"]["chest"]["shine"] == "#d9a35a", "BOSS126: the chest's name and light")
    bz = json.loads(_read(CONTENT, "boss_attacks", "black_blizzard", "black_blizzard.json"))
    check(bz["kind"] == "pattern" and bz["projectile"]["look"] == "grit_clod" and bz["barrier"]["look"] == "cross_fence", "BOSS126: the blizzard's bullets and fence")
    md = _read(HERE, "boss_model.js")
    check("black_sunday: 50" in md and "black_sunday: 10000" in md, "BOSS126: boss_model's tables name him as WaveTimeline does")
