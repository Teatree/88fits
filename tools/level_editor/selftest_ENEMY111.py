"""Pass 111, lane ENEMY: the Level Editor's side of four creature changes. selftest.py discovers this file
(`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing
here writes.

Groups: the map's `far_speed` rows in fields.js (five keys in the Scaling card, explained, their grey numbers
WaveTimeline.FAR_SPEED_DEFAULTS) and model.js's farSpeedMult / farSpeedIssues (the game's curve: 1 inside the distance, a
smoothstep to max_mult over the ramp, never an Elite or a special, bosses only while `bosses`); the game reading the block
(JsonContent), handing it over (WaveDirector) and playing it (EnemyManager); Red Canyon's block; the Creatures form's
ranged rows for the throwers and the harpoon (release_hold, throw_jump, dynamite, bomb, harpoon_fx) and the two new
shot looks; the Spit Cactus's bomb block and the harpooner's harpoon_fx in the content; the two models on disk.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const dir = path.dirname(process.argv[2]);
global.U = {};
global.AssetsModel = require(path.join(dir, 'assets_model.js'));
const AF = require(path.join(dir, 'assets_fields.js'));
const Model = require(path.join(dir, 'model.js'));
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src || '{}');
  const out = {};
  out.rows = FIELDS.SCALARS.filter((d) => d.key.startsWith('far_speed.')).map((d) => [d.key, d.group, d.type, d.def, !!d.help, d.block || null]);
  out.defaults = Model.FAR_SPEED_DEFAULTS;
  const tl = q.tl || {};
  out.mult = [5, 14, 17, 20, 40].map((d) => Model.farSpeedMult(tl, d, 'regular'));
  out.never = Model.farSpeedMult(tl, 40, 'never');
  out.boss = Model.farSpeedMult(tl, 40, 'boss');
  out.bossOff = Model.farSpeedMult({ far_speed: { bosses: false } }, 40, 'boss');
  out.off = Model.farSpeedMult({ far_speed: { enabled: false } }, 40, 'regular');
  out.issues = Model.farSpeedIssues({ far_speed: { max_mult: 0.5, ramp: -1 } }).length;
  out.cleanIssues = Model.farSpeedIssues(tl).length;
  const ranged = (AF.BLOCKS && AF.BLOCKS.ranged) ? AF.BLOCKS.ranged.rows : [];
  out.ranged = ranged.map((r) => [r.key, r.type, !!r.help]);
  out.shots = (AF.VOCAB && AF.VOCAB.shotKinds ? AF.VOCAB.shotKinds : []).map((o) => o.v);
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def checks(check, run_node, server):
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    m = re.search(r"const FAR_SPEED_DEFAULTS := (\{.*?\})", wt)
    dflt = json.loads(m.group(1)) if m else {}
    check(dflt == {"enabled": True, "distance": 14.0, "max_mult": 2.0, "ramp": 6.0, "bosses": True},
          "ENEMY111: WaveTimeline.FAR_SPEED_DEFAULTS are the rule's numbers (on, 14 m, x2, 6 m ramp, bosses): %s" % dflt)
    check("func far_speed_cfg() -> Dictionary" in wt and "@export var far_speed: Dictionary" in wt, "ENEMY111: WaveTimeline carries the block and fills it")
    mp = json.loads(_read(CONTENT, "maps", "red_canyon", "red_canyon.json"))
    tl = mp.get("timeline_data", {})
    res = run_node({"tl": tl}, RUNNER)
    if not res:
        check(False, "ENEMY111: node ran fields.js, model.js and assets_fields.js")
    else:
        rows = {r[0]: r for r in res["rows"]}
        want = {"far_speed." + k for k in dflt}
        check(set(rows) == want, "ENEMY111: fields.js has exactly the five far_speed rows: %s" % sorted(rows))
        check(all(r[1] == "Scaling" and r[4] and r[5] is None for r in rows.values()), "ENEMY111: every far_speed row sits in the Scaling card, explained, no block")
        defs = {k: rows["far_speed." + k][3] for k in dflt if "far_speed." + k in rows}
        check(all(float(defs[k]) == float(dflt[k]) if not isinstance(dflt[k], bool) else defs[k] == dflt[k] for k in defs),
              "ENEMY111: the rows' grey numbers are the game's: %s" % defs)
        check({k: res["defaults"][k] for k in dflt} == {k: (dflt[k] if isinstance(dflt[k], bool) else dflt[k]) for k in dflt},
              "ENEMY111: model.js FAR_SPEED_DEFAULTS are the game's: %s" % res["defaults"])
        fs = dict(dflt)
        fs.update(tl.get("far_speed", {}) if isinstance(tl.get("far_speed"), dict) else {})

        def game_mult(d):
            if not fs["enabled"] or d <= fs["distance"]:
                return 1.0
            f = 1.0 if fs["ramp"] <= 0 else min(max((d - fs["distance"]) / fs["ramp"], 0.0), 1.0)
            return 1.0 + (fs["max_mult"] - 1.0) * f * f * (3.0 - 2.0 * f)
        want_m = [game_mult(d) for d in (5, 14, 17, 20, 40)]
        check(all(abs(a - b) < 1e-9 for a, b in zip(res["mult"], want_m)), "ENEMY111: farSpeedMult is the game's curve on the map's block: %s" % res["mult"])
        check(res["never"] == 1 and res["off"] == 1 and res["bossOff"] == 1 and abs(res["boss"] - want_m[-1]) < 1e-9,
              "ENEMY111: never an Elite or a special, nothing when off, bosses by their switch")
        check(res["issues"] == 2 and res["cleanIssues"] == 0, "ENEMY111: farSpeedIssues warns of a multiplier under 1 and a negative ramp, nothing on the map's block")
        keys = [r[0] for r in res["ranged"]]
        for k in ("release_hold", "throw_jump", "dynamite", "bomb", "harpoon_fx"):
            check(k in keys, "ENEMY111: the Creatures form's Ranged block has the %s row" % k)
        check(all(r[2] for r in res["ranged"] if r[0] in ("dynamite", "bomb", "harpoon_fx")), "ENEMY111: the three json rows are explained")
        check("bomb" in res["shots"] and "dynamite" in res["shots"], "ENEMY111: the Shot look list offers dynamite and bomb: %s" % res["shots"])
    import sys
    sys.path.insert(0, HERE)
    import vocab
    check("bomb" in vocab.SHOT_KINDS and "dynamite" in vocab.SHOT_KINDS and all(k in vocab.BLOCKS["ranged"] for k in ("bomb", "harpoon_fx", "dynamite")),
          "ENEMY111: vocab.py knows the two shot looks and the three blocks")
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    check('t.get("far_speed", {})' in jc and "w.far_speed = fsp if fsp is Dictionary else {}" in jc, "ENEMY111: JsonContent reads the map's far_speed block as it is")
    wd = _read(GAME, "core", "systems", "WaveDirector.gd")
    check("em.set_far_speed(timeline.far_speed_cfg())" in wd, "ENEMY111: the director hands the block to the crowd")
    em = _read(GAME, "core", "systems", "EnemyManager.gd")
    check("func set_far_speed(cfg: Dictionary) -> void" in em and "static func far_speed_mult(dist: float, distance: float, ramp: float, max_mult: float) -> float" in em
          and "spd *= far_speed_k(i, dist)" in em, "ENEMY111: EnemyManager plays it on the walk its brain chooses")
    blk = tl.get("far_speed")
    check(blk is None or (isinstance(blk, dict) and all(k in dflt and isinstance(v, (int, float, bool)) for k, v in blk.items())),
          "ENEMY111: Red Canyon's far_speed block holds only the rule's keys: %s" % blk)
    # the content
    sc = json.loads(_read(CONTENT, "enemies", "spit_cactus", "spit_cactus.json"))
    rg = sc.get("ranged", {})
    bomb = rg.get("bomb", {})
    check(rg.get("shot") in ("bomb", "dynamite") and isinstance(bomb, dict) and bomb.get("model", "").endswith("enemy_bomb.glb")
          and float(bomb.get("arc_height", 0)) > 0 and isinstance(bomb.get("trail"), dict),
          "ENEMY111: the Spit Cactus has its bomb block (model, arc_height, trail): shot %s" % rg.get("shot"))
    check(os.path.exists(os.path.join(GAME, "art", "props", "enemy_bomb.glb")) and os.path.exists(os.path.join(GAME, "art", "props", "harpoon_hook.glb")),
          "ENEMY111: the bomb and the hook models are on disk")
    hp = json.loads(_read(CONTENT, "enemies", "harpoon_troglodyte", "harpoon_troglodyte.json"))
    hf = hp.get("ranged", {}).get("harpoon_fx", {})
    check(isinstance(hf, dict) and isinstance(hf.get("chain"), dict) and isinstance(hf.get("windup"), dict), "ENEMY111: the harpooner has its harpoon_fx (chain, windup)")
    print("ENEMY111: far_speed %s; bomb arc %s m; chain link %s m" % (fs if res else dflt, bomb.get("arc_height"), hf.get("chain", {}).get("link")))
