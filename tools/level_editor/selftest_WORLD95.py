"""Pass 95, lane WORLD: the Level Editor's side of the despawn rule and the Magnet power-up. selftest.py discovers this
file (`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module.
Nothing here writes.

Groups: the map's `despawn` rows in fields.js (five keys in the Scaling card, explained, their grey numbers
WaveTimeline.DESPAWN_DEFAULTS, no `block:` on them: the settings page skips a block it has no drawer for); the game
reading the block (JsonContent), handing it over (WaveDirector, never in the arena) and playing it (EnemyManager's
_tick_despawn before the grid, can_despawn, despawn); the analytics row; Red Canyon's block when Garry sets one; the
Magnet pickup's data (effect "magnet", 10 s, radius_mult 2.5, its .tres in step) and the code that plays it (Game,
PickupManager, MagnetBuff, the bot's price).
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
require(path.join(dir, 'assets_fields.js'));
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const out = {};
  out.rows = FIELDS.SCALARS.filter((d) => d.key.startsWith('despawn.')).map((d) => [d.key, d.group, d.type, d.def, !!d.help, d.block || null]);
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def checks(check, run_node, server):
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    m = re.search(r"const DESPAWN_DEFAULTS := (\{.*?\})", wt)
    dflt = json.loads(m.group(1)) if m else {}
    check(dflt == {"enabled": True, "distance": 40.0, "grace": 6.0, "every": 0.5, "keep_share": 0.0},
          "WORLD95: WaveTimeline.DESPAWN_DEFAULTS are the rule's numbers (on, 40 m, 6 s grace, every 0.5 s, keep 0): %s" % dflt)
    check("func despawn_value(key: String) -> float" in wt and "func despawn_cfg() -> Dictionary" in wt,
          "WORLD95: WaveTimeline reads one despawn number and the whole block with the defaults filled")
    res = run_node({}, RUNNER)
    if not res:
        check(False, "WORLD95: node ran fields.js")
    else:
        rows = {r[0]: r for r in res["rows"]}
        want = {"despawn." + k for k in dflt}
        check(set(rows) == want, "WORLD95: fields.js has exactly the five despawn rows: %s" % sorted(rows))
        check(all(r[1] == "Scaling" and r[4] for r in rows.values()) and "Scaling" in res["groups"],
              "WORLD95: every despawn row sits in the Scaling card and is explained: %s" % [(r[0], r[1], r[4]) for r in rows.values()])
        check(all(r[5] is None for r in rows.values()), "WORLD95: no `block:` on a despawn row (the settings page draws a block only with a drawer for it)")
        types = {k: rows["despawn." + k][2] for k in dflt if "despawn." + k in rows}
        check(types == {"enabled": "bool", "distance": "number", "grace": "number", "every": "number", "keep_share": "percent"},
              "WORLD95: the rows' types: a switch, three numbers, a share: %s" % types)
        defs = {k: rows["despawn." + k][3] for k in dflt if "despawn." + k in rows}
        check(all((defs.get(k) is dflt[k]) if isinstance(dflt[k], bool) else abs(float(defs.get(k, -1)) - float(dflt[k])) < 1e-9 for k in dflt),
              "WORLD95: the rows' grey numbers are the game's defaults: %s / %s" % (defs, dflt))
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    check('t.get("despawn", {})' in jc and "w.despawn = dsp if dsp is Dictionary else {}" in jc, "WORLD95: JsonContent reads the map's despawn block as it is")
    wd = _read(GAME, "core", "systems", "WaveDirector.gd")
    check("em.set_despawn({} if Run.arena else timeline.despawn_cfg())" in wd, "WORLD95: the director hands the block to the crowd, off in the arena")
    em = _read(GAME, "core", "systems", "EnemyManager.gd")
    check("func _tick_despawn(delta: float, ppos: Vector3) -> int" in em and "func can_despawn(i: int, ppos: Vector3) -> bool" in em
          and "func despawn(i: int) -> bool" in em and "func set_despawn(cfg: Dictionary) -> void" in em,
          "WORLD95: EnemyManager has the rule (set_despawn, _tick_despawn, can_despawn, despawn)")
    tick = em.find("_tick_despawn(delta, player.global_position)")
    grid = em.find("_rebuild_grid()\n\t_obstacle_cells()")
    check(0 < tick < grid, "WORLD95: the despawn tick runs before the tick builds its grid (no freed slot in this tick's cells)")
    check("RunAnalytics.I.despawned(def)" in em and "_despawn_note_spawn(i)" in em, "WORLD95: a despawn is counted, every spawn notes its birth and its summoner")
    for word in ["Run.add_kill", "enemy_died.emit", "creature_dying.emit", "_kill_effects", "spawn_chest", "drop_from"]:
        body = em[em.find("func despawn(i: int) -> bool"):em.find("func despawn(i: int) -> bool") + 1200]
        check(word not in body, "WORLD95: despawn() does nothing of a death: no %s" % word)
    ra = _read(GAME, "core", "systems", "RunAnalytics.gd")
    check('_put_map(row, "despawned", _despawns, false)' in ra and '"despawned"]' in ra and 'out["despawned_by"]' in ra,
          "WORLD95: the run record carries the despawned a second and the run's crowd totals")
    mp = json.loads(_read(CONTENT, "maps", "red_canyon", "red_canyon.json"))
    blk = mp.get("timeline_data", {}).get("despawn", None)
    check(blk is None or (isinstance(blk, dict) and all(k in dflt and isinstance(v, (int, float, bool)) for k, v in blk.items())),
          "WORLD95: Red Canyon's despawn block (when Garry sets one) holds only the rule's keys as numbers: %s" % blk)
    # the Magnet power-up
    pk = json.loads(_read(CONTENT, "pickups", "magnet_pulse", "magnet_pulse.json"))
    check(pk.get("effect") == "magnet" and float(pk.get("duration", 0)) == 10.0 and float(pk.get("params", {}).get("radius_mult", 0)) == 2.5
          and pk.get("name") == "Magnet" and float(pk.get("lifetime", 0)) >= 40,
          "WORLD95: the Magnet pickup is effect magnet, 10 s, 2.5 x the card's reach, named Magnet: %s" % {k: pk.get(k) for k in ("name", "effect", "duration", "params")})
    tres = _read(CONTENT, "pickups", "magnet_pulse", "magnet_pulse.tres")
    check('effect_kind = "magnet"' in tres and "duration = 10.0" in tres and '"radius_mult": 2.5' in tres, "WORLD95: the pickup's .tres is in step with its JSON")
    gm = _read(GAME, "game", "Game.gd")
    check('"magnet":' in gm and "func _apply_magnet_pickup(def: PickupDef) -> void" in gm and "pickups.magnet_start(def, Run.powerup_seconds(def.duration))" in gm,
          "WORLD95: Game.apply_pickup plays the magnet effect with the Pocket Watch's seconds")
    pm = _read(GAME, "core", "systems", "PickupManager.gd")
    check("func magnet_start(def: PickupDef, seconds: float) -> float" in pm and "func magnet_pull(c: Vector3, r: float) -> int" in pm
          and "func _tick_magnet(delta: float, hero: Vector3) -> void" in pm and "static func magnet_item_reach() -> float" in pm
          and "if kind[i] != KIND_VACUUM:" in pm and "_tick_magnet(delta, hero)" in pm,
          "WORLD95: PickupManager runs the Magnet (start, the tick's pull round the hero, never a vacuum gem, the card's level-1 reach)")
    check(os.path.exists(os.path.join(GAME, "core", "systems", "MagnetBuff.gd")) and "class_name MagnetBuff" in _read(GAME, "core", "systems", "MagnetBuff.gd"),
          "WORLD95: the 2D magnet (core/systems/MagnetBuff.gd) exists")
    bg = _read(GAME, "tools", "bot", "BotGoals.gd")
    bt = _read(GAME, "tools", "bot", "Bot.gd")
    check(bg.count('"vacuum", "magnet":') == 2 and '["vacuum", "magnet"]' in bt, "WORLD95: the bot prices the Magnet as it priced the vacuum")
    print("WORLD95: despawn defaults %s; the Magnet %s s x %s of the card's reach" % (dflt, pk.get("duration"), pk.get("params", {}).get("radius_mult")))
