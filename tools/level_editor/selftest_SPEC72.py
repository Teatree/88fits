"""Pass 72, lane SPEC: the coloured specials' new numbers in the Level Editor. selftest.py discovers this file
(`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing
here writes under game/.

Groups: model.js (SPECIAL_DEFAULTS x1.5 / x15 / chest 0.35, specialMaxAlive: the map's max_alive, else 3, 0 = no limit;
the spawn estimate keeps the coloured specials alive under the cap, a forced swarm past it); fields.js (Settings ->
Coloured specials: Chest chance and Max alive); assets_fields.js (the Enemies tab's Special block: Chest chance, its 0..1
rule); the game's EnemyDef constants are the page's.
"""
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
const Model = require(process.argv[2]);
const AM = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = AM;
const F = require(path.join(dir, 'assets_fields.js'));
global.AFIELDS = F;
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
  out.defaults = Model.SPECIAL_DEFAULTS;
  out.capConst = Model.SPECIAL_MAX_ALIVE;
  out.caps = q.caps.map((d) => { const n = Model.specialMaxAlive(d); return isFinite(n) ? n : -1; });
  out.chest = q.chest.map(([sp, d]) => [Model.specialValue(sp, d, 'chest_chance'), Model.specialSource(sp, d, 'chest_chance')]);
  out.scalars = FIELDS.SCALARS.filter((d) => d.key === 'special_defaults.chest_chance' || d.key === 'special_defaults.max_alive').map((d) => [d.key, d.group, d.type, d.def, !!d.help]);
  const rows = F.table('enemy');
  out.section = rows.filter((r) => r.section === 'Special').map((r) => [r.key, r.def == null ? null : r.def]);
  out.issues = q.docs.map((d) => { const r = AM.issues('enemy', d, { id: d.id, kind: 'enemy', lists: { items: {}, heroes: [], enemies: [d] }, seenCombos: new Set(), saved: d }); return r.errors.map((e) => e.key); });
  out.est = q.est.map(([tl, cr, o]) => { const e = Model.spawnEstimate(tl, cr, o); const p = Model.estimateAt(e, q.estAt, false); return [p.col, p.reg]; });
  process.stdout.write(JSON.stringify(out));
});
"""


def _creature(cid, chance=1.0, sp=None):
    return {"id": cid, "name": cid, "kind": "enemy", "archetype": "walker", "hp": 10, "damage": 4, "speed": 2, "size": 1.2,
            "radius": 0.5, "doc": "x", "blood": "#C70D0D", "knockback": 3.0, "cap_share": 1, "pack_size": 5, "max_alive": 0,
            "variance": {"special_chance": chance, "special": sp if sp is not None else {"tint": "#8A1428"}}}


def _tl(spd=None, events=None):
    tl = {"stage_length": 100, "stages": 1, "cap_curve": [[0, 30]], "cap_max": 100, "hard_cap": 300, "burst_min": 10,
          "burst_max": 10, "spawn_interval": 0.5, "colour_after_kills": 0,
          "roster": [{"id": "r1", "t": 0, "enemy": "a", "weights": [[0, 1]]}], "events": events or []}
    if spd is not None:
        tl["special_defaults"] = spd
    return tl


def checks(check, run_node, server):
    cr = [_creature("a")]
    no_kills = {"turnover": 0.0, "end": 40}
    q = {
        "caps": [{}, {"max_alive": 5}, {"max_alive": 0}, {"max_alive": ""}, None],
        "chest": [[{}, {}], [{}, {"chest_chance": 0.5}], [{"chest_chance": 0.1}, {"chest_chance": 0.5}]],
        "docs": [_creature("ok", 0.04, {"chest_chance": 0.35}), _creature("bad", 0.04, {"chest_chance": 1.5})],
        "est": [[_tl(), cr, no_kills], [_tl({"max_alive": 0}), cr, no_kills], [_tl({"max_alive": 5}), cr, no_kills],
                [_tl(None, [{"t": 20, "type": "swarm", "enemy": "a", "count": 4, "special": True}]), cr, no_kills],
                [_tl(), cr, {"turnover": 0.5, "end": 40}]],
        "estAt": 30,
    }
    res = run_node(q, RUNNER)
    if res is None:
        check(True, "lane SPEC72: node not found, the page checks skipped")
        return
    if not res:
        check(False, "lane SPEC72: the page runner failed")
        return
    d = res["defaults"]
    check(d.get("size") == 1.5 and d.get("hp") == 15 and d.get("damage") == 2 and d.get("chest_chance") == 0.35,
          "model.js: SPECIAL_DEFAULTS are pass 72's x1.5 size, x15 HP, chest 0.35: %s" % d)
    check(res["capConst"] == 3 and res["caps"] == [3, 5, -1, 3, 3],
          "model.js: specialMaxAlive is the map's max_alive, else 3; 0 = no limit: %s %s" % (res["capConst"], res["caps"]))
    check(res["chest"] == [[0.35, "game"], [0.5, "map"], [0.1, "own"]],
          "model.js: a special's chest chance is the creature's own, else the map's, else the game's 0.35: %s" % res["chest"])
    sc = {k: (g, t, dv, h) for k, g, t, dv, h in res["scalars"]}
    check(sc.get("special_defaults.chest_chance") == ("Coloured specials", "number", 0.35, True)
          and sc.get("special_defaults.max_alive") == ("Coloured specials", "int", 3, True),
          "fields.js: Settings -> Coloured specials holds Chest chance (0.35) and Max alive (3), with help: %s" % res["scalars"])
    sec = dict((k, dv) for k, dv in res["section"])
    check(sec.get("variance.special.chest_chance") == 0.35 and sec.get("variance.special.size") == 1.5 and sec.get("variance.special.hp") == 15,
          "assets_fields.js: the Enemies tab's Special block has Chest chance (0.35) and the x1.5 / x15 defaults: %s" % res["section"])
    ok_issues, bad_issues = res["issues"]
    check("variance.special.chest_chance" not in ok_issues and "variance.special.chest_chance" in bad_issues,
          "assets_fields.js: a chest chance outside 0..1 is an error: %s" % res["issues"])
    (c3, r3), (c0, r0), (c5, r5), (cf, rf), (ck, rk) = res["est"]
    check(c3 <= 3 + 1e-9 and abs(c3 - 3) < 1e-6 and abs(r3 - r0) < 1e-9,
          "model.js: the estimate keeps the coloured specials alive under the game's 3 (nobody dies here): %s" % res["est"][0])
    check(c0 > 20, "model.js: max_alive 0 lifts the cap (every one coloured at chance 1): %s" % res["est"][1])
    check(abs(c5 - 5) < 1e-6, "model.js: the map's max_alive 5 holds them at 5: %s" % res["est"][2])
    check(abs(cf - 7) < 1e-6, "model.js: a forced swarm of 4 comes past the cap (3 + 4): %s" % res["est"][3])
    check(ck > 6, "model.js: with kills the cap frees room again, so more come coloured over time than the cap: %s" % res["est"][4])
    # the game's constants are the page's
    ed = open(os.path.join(GAME, "core", "data", "EnemyDef.gd"), encoding="utf-8").read()
    m = re.search(r"const SPECIAL_MAX_ALIVE\s*:?=\s*([0-9]+)", ed)
    check(m is not None and int(m.group(1)) == 3, "EnemyDef.SPECIAL_MAX_ALIVE is 3, as model.js and fields.js say")
    m2 = re.search(r'"chest_chance":\s*([0-9.]+)', ed)
    check(m2 is not None and abs(float(m2.group(1)) - 0.35) < 1e-9, "EnemyDef.SPECIAL_DEFAULTS chest_chance is 0.35, as the page says")
