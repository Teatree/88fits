"""Pass 69, lane EN: the coloured specials in the Level Editor. selftest.py discovers this file (`extra_checks`) and hands
it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes under game/.

Groups: fields.js (a swarm's Special flag, a row's Special glow override, the map's Coloured specials defaults matching
the game's EnemyDef.SPECIAL_DEFAULTS); model.js (specialValue / specialSource: the creature's own, the map's, the
game's; varianceSpecial with the map's defaults; creatureAt's special at x10 / x2; the spawn estimate counts a special
swarm's creatures as coloured, colour open or not); assets_fields.js (the Enemies tab's Special section and its rules: any
colour, a light one only warned, the glow and the chance 0..1); the content (Red Canyon's one special swarm, the special
Goblin at the end of the first row, and every creature in play with a chance carries the pass-69 numbers); the server's
map Save keeps the event's flag and the map's special_defaults.
"""
import glob
import json
import os
import re
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")

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
// fields.js is a page script (no exports): run it with the names it reads at load
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
  const ev = FIELDS.event.find((d) => d.key === 'special');
  out.event = ev ? { type: ev.type, only: ev.only, def: ev.def, help: !!ev.help } : null;
  const ov = FIELDS.OVERRIDES.find((d) => d.path === 'variance.special.glow');
  out.override = ov ? { group: ov.group, min: ov.min, max: ov.max } : null;
  out.scalars = FIELDS.SCALARS.filter((d) => d.key.startsWith('special_defaults.')).map((d) => [d.key, d.group, d.def]);
  out.groups = FIELDS.SCALAR_GROUPS;
  out.swarmHelp = FIELDS.EVENT_TYPES.swarm.help;
  // model.js
  out.value = q.value.map(([sp, dflt, key]) => [Model.specialValue(sp, dflt, key), Model.specialSource(sp, dflt, key)]);
  out.vs = q.vs.map(([c, st, dflt]) => { const r = Model.varianceSpecial(c, st, dflt); return [r.chance, r.size, r.strength, r.glow]; });
  out.at = q.at.map(([tl, c, t]) => { const r = Model.creatureAt(tl, c, {}, t, 1); return r.special ? [r.hp, r.atk, r.special.hp, r.special.atk] : [r.hp, r.atk, null, null]; });
  out.est = q.est.map(([tl, cr, o]) => { const e = Model.spawnEstimate(tl, cr, o); const p = Model.estimateAt(e, q.estAt, false); return [p.col, p.reg, (e.marks || []).filter((m) => m.kind === 'swarm').length]; });
  out.defaults = Model.SPECIAL_DEFAULTS;
  // assets_fields.js: the Enemies tab
  const rows = F.table('enemy');
  out.section = rows.filter((r) => r.section === 'Special').map((r) => [r.key, r.type, r.def == null ? null : r.def]);
  out.variance = rows.filter((r) => r.section === 'Variance').map((r) => r.key);
  out.issues = q.docs.map((d) => { const r = AM.issues('enemy', d, { id: d.id, kind: 'enemy', lists: { items: {}, heroes: [], enemies: [d] }, seenCombos: new Set(), saved: d }); return [r.errors.map((e) => e.key), r.warnings.map((e) => e.key)]; });
  process.stdout.write(JSON.stringify(out));
});
"""

# (pass 72, lane SPEC, re-pinned: the game's specials are x1.5 size, x15 HP and drop a chest at 0.35 now)
GAME_DEFAULTS = {"size": 1.5, "hp": 15.0, "damage": 2.0, "xp": 2.0, "tint_strength": 0.6, "glow": 0.6, "chest_chance": 0.35}
# pass 72: the map-only cap on how many live at once (EnemyDef.SPECIAL_MAX_ALIVE), a Settings row of its own
GAME_MAX_ALIVE = 3


def _creature(cid, extra=None):
    d = {"id": cid, "name": cid, "kind": "enemy", "archetype": "walker", "hp": 10, "damage": 4, "speed": 2, "size": 1.2,
         "radius": 0.5, "doc": "x", "blood": "#C70D0D", "knockback": 3.0, "cap_share": 1, "pack_size": 10, "max_alive": 0,
         "variance": {"special_chance": 0.1, "special": {"tint": "#8A1428"}}}
    if extra:
        d.update(extra)
    return d


def checks(check, run_node, server):
    # ---------------------------------------------------------------- the page's tables and maths under Node
    est_tl = {"stage_length": 100, "stages": 1, "cap_curve": [[0, 10]], "cap_max": 100, "hard_cap": 300, "burst_min": 10,
              "burst_max": 10, "spawn_interval": 0.5, "colour_after_kills": 100000, "roster": [],
              "events": [{"t": 10, "type": "swarm", "enemy": "g", "count": 1, "special": True}]}
    plain_tl = json.loads(json.dumps(est_tl))
    del plain_tl["events"][0]["special"]
    cr = [_creature("g")]
    light = _creature("lt", {"variance": {"special_chance": 0.04, "special": {"tint": "#FFE0A0", "glow": 0.5}}})
    bad = _creature("bd", {"variance": {"special_chance": 1.5, "special": {"tint": "zz", "glow": 1.5}}})
    dark = _creature("dk", {"variance": {"special_chance": 0.04, "special": {"tint": "#8A1428"}}})
    tl_at = {"stage_length": 430, "stages": 3, "stage_mults": [1.0, 2.2, 3.34], "creature_hp_mult": 1.0, "creature_damage_mult": 1.0}
    tl_map = dict(tl_at, special_defaults={"hp": 6, "damage": 3})
    q = {
        "value": [[{}, {}, "hp"], [{}, {"hp": 7}, "hp"], [{"hp": 4}, {"hp": 7}, "hp"], [{}, {}, "glow"], [{"glow": 0}, {"glow": 0.9}, "glow"],
                  [{"hp": ""}, {}, "hp"], [{}, {"size": "x"}, "size"]],
        "vs": [[{"variance": {"special_chance": 0.04, "special": {}}}, {}, {}], [{"variance": {"special_chance": 0.04, "special": {}}}, {}, {"glow": 0.3, "size": 1.5}],
               [{"variance": {"special_chance": 0.04, "special": {"glow": 0.8}}}, {"variance": {"special": {"glow": 0.1}}}, {"glow": 0.3}]],
        "at": [[tl_at, _creature("a"), 0], [tl_map, _creature("b"), 0], [tl_map, _creature("c", {"variance": {"special_chance": 0.1, "special": {"hp": 2}}}), 0]],
        "est": [[est_tl, cr, {"turnover": 0.0, "end": 30}], [plain_tl, cr, {"turnover": 0.0, "end": 30}]],
        "estAt": 20,
        "docs": [light, bad, dark],
    }
    res = run_node(q, RUNNER)
    if res is None:
        check(True, "lane EN: node not found, the page checks skipped")
    elif res:
        check(res["event"] == {"type": "bool", "only": ["swarm"], "def": False, "help": True}, "fields.js: a swarm event's Special flag (bool, swarm only, off by default): %s" % res["event"])
        check(res["override"] == {"group": "Elite", "min": 0, "max": 1}, "fields.js: a row's Special glow override in the Elite group, 0..1: %s" % res["override"])
        got = {k.split(".", 1)[1]: (g, dv) for k, g, dv in res["scalars"]}
        cap_row = got.pop("max_alive", None)
        check(set(got) == set(GAME_DEFAULTS) and all(g == "Coloured specials" and abs(float(dv) - GAME_DEFAULTS[k]) < 1e-9 for k, (g, dv) in got.items()),
              "fields.js: Settings → Coloured specials holds the seven map defaults, each greyed with the game's number: %s" % res["scalars"])
        check(cap_row == ("Coloured specials", GAME_MAX_ALIVE), "fields.js: Settings → Coloured specials holds Max alive, the game's 3 (pass 72): %s" % (cap_row,))
        check("Coloured specials" in res["groups"], "fields.js: the Coloured specials card is drawn: %s" % res["groups"])
        check("Special" in res["swarmHelp"], "fields.js: the swarm's help names the Special flag")
        check(res["defaults"] == GAME_DEFAULTS, "model.js: SPECIAL_DEFAULTS are the game's: %s" % res["defaults"])
        # (pass 72, lane SPEC, re-pinned: the game's specials are x1.5 size, x15 HP and drop a chest at 0.35 now)
        want = [[15, "game"], [7, "map"], [4, "own"], [0.6, "game"], [0, "own"], [15, "game"], [1.5, "game"]]
        check(res["value"] == want, "model.js: specialValue / specialSource: the creature's own, else the map's, else the game's (empty or not a number skipped): %s" % res["value"])
        vs = res["vs"]
        check(vs[0] == [0.04, 1.5, 0.6, 0.6], "model.js: varianceSpecial with nothing named: the game's size 1.5 (pass 72), strength 0.6, glow 0.6: %s" % vs[0])
        check(vs[1] == [0.04, 1.5, 0.6, 0.3], "model.js: varianceSpecial takes the map's defaults where the creature names none: %s" % vs[1])
        check(vs[2][3] == 0.1, "model.js: a row's override of the glow wins over the creature's and the map's: %s" % vs[2])
        a, b, c = res["at"]
        check(abs(a[2] / a[0] - 15) < 1e-9 and abs(a[3] / a[1] - 2) < 1e-9, "model.js: creatureAt's special is x15 HP (pass 72) and x2 ATK by the game's defaults: %s" % a)
        check(abs(b[2] / b[0] - 6) < 1e-9 and abs(b[3] / b[1] - 3) < 1e-9, "model.js: creatureAt's special takes the map's special_defaults: %s" % b)
        check(abs(c[2] / c[0] - 2) < 1e-9 and abs(c[3] / c[1] - 3) < 1e-9, "model.js: the creature's own HP x wins, the map's ATK x fills in: %s" % c)
        (col_sp, reg_sp, sw_sp), (col_pl, reg_pl, sw_pl) = res["est"]
        check(abs(col_sp - 1) < 1e-9 and sw_sp == 1, "model.js: the estimate counts a special swarm's one creature as coloured, colour shut: %s" % res["est"][0])
        check(abs(col_pl) < 1e-12 and sw_pl == 1, "model.js: the same swarm without the flag brings it plain while colour is shut: %s" % res["est"][1])
        keys = [k for k, _, _ in res["section"]]
        check(keys == ["variance.special_chance", "variance.special.size", "variance.special.hp", "variance.special.damage", "variance.special.xp",
                       "variance.special.tint", "variance.special.tint_strength", "variance.special.glow", "variance.special.chest_chance"],
              "assets_fields.js: the Enemies tab's Special section, in order, with the glow: %s" % keys)
        defs = {k: dv for k, _, dv in res["section"]}
        check(all(abs(float(defs["variance.special." + k]) - GAME_DEFAULTS[k]) < 1e-9 for k in ("size", "hp", "damage", "xp", "tint_strength", "glow")),
              "assets_fields.js: the Special rows grey in the game's defaults: %s" % defs)
        check(not any(k.startswith("variance.special") for k in res["variance"]), "assets_fields.js: the Variance section keeps the spread and the tints only: %s" % res["variance"])
        (e_lt, w_lt), (e_bd, w_bd), (e_dk, w_dk) = res["issues"]
        check(not [k for k in e_lt if k.startswith("variance")] and "variance.special.tint" in w_lt,
              "assets_fields.js: a light special colour is a warning, not an error (Garry picks it): errors %s warnings %s" % (e_lt, w_lt))
        check({"variance.special.tint", "variance.special.glow", "variance.special_chance"} <= set(e_bd), "assets_fields.js: a non-colour, a glow past 1 and a chance past 1 are errors: %s" % e_bd)
        check(not [k for k in e_dk + w_dk if k.startswith("variance")], "assets_fields.js: a dark, saturated colour is quiet: %s %s" % (e_dk, w_dk))

    # ---------------------------------------------------------------- the content on disk
    with open(os.path.join(CONTENT, "maps", "red_canyon", "red_canyon.json"), encoding="utf-8") as f:
        tl = json.load(f)["timeline_data"]
    sp_events = [e for e in tl.get("events", []) if e.get("special")]
    # pass 84 (lane SPAWN, re-pinned): the special Goblin is a "once" row with `special` now (an old map's event still counts)
    sp_events += [r for r in tl.get("roster", []) if r.get("special") and r.get("pace") == "once"]
    check(len(sp_events) == 1 and (sp_events[0].get("type") == "swarm" or sp_events[0].get("pace") == "once") and int(sp_events[0].get("count", 0)) == 1,
          "Red Canyon: one special swarm event of one creature: %s" % sp_events)
    if sp_events:
        ev = sp_events[0]
        with open(os.path.join(CONTENT, "enemies", ev["enemy"], ev["enemy"] + ".json"), encoding="utf-8") as f:
            cdef = json.load(f)
        check(isinstance(cdef.get("variance"), dict) and cdef["variance"].get("special"), "the special event's creature (%s) has a special block" % ev["enemy"])
        # (pass 72, lane SPEC, re-pinned: Garry rebuilt stage 1 in the Level Editor (the red goblins' row now 2:03-4:05)
        # and kept the special Goblin at 2:00; where it stands is his to drag, so only that it comes in stage 1 is pinned)
        check(0 <= float(ev["t"]) <= float(tl.get("stage_length", 430)),
              "the special Goblin comes in the first stage: %s s" % ev.get("t"))
    bad_rows = []
    for p in sorted(glob.glob(os.path.join(CONTENT, "enemies", "*", "*.json"))):
        cid = os.path.basename(os.path.dirname(p))
        if os.path.basename(p) != cid + ".json":
            continue
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        vr = d.get("variance") if isinstance(d.get("variance"), dict) else {}
        if float(vr.get("special_chance", 0) or 0) <= 0:
            continue
        sp = vr.get("special") or {}
        # (pass 72, lane SPEC, re-pinned: the game's specials are x1.5 size, x15 HP and drop a chest at 0.35 now)
        if not (float(vr["special_chance"]) <= 0.0401 and sp.get("size") == 1.5 and sp.get("hp") == 15.0 and sp.get("damage") == 2.0):
            bad_rows.append(cid)
    check(not bad_rows, "every creature with a special chance: a third of the old chance at most 0.04 (pass 69), size 1.5, HP x15 (pass 72), ATK x2: %s" % bad_rows)

    # ---------------------------------------------------------------- the server's map Save keeps the new keys
    tmp = tempfile.mkdtemp(prefix="le_selftest_EN_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        folder = os.path.join(server.CONTENT, "maps", "testmap")
        os.makedirs(folder)
        path = os.path.join(folder, "testmap.json")
        on_disk = {"id": "testmap", "name": "Test Map", "skins": {"walker": "testbeast"}, "boss": "bigboss",
                   "timeline_data": {"stage_length": 100.0, "roster": [], "events": []}}
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(on_disk, indent=2) + "\n")
        body = json.loads(json.dumps(on_disk))
        body["timeline_data"]["events"] = [{"t": 120, "type": "swarm", "enemy": "red_goblin", "variant": "RG-B", "count": 1,
                                             "pattern": "in_front", "special": True, "name": "Special Goblin"}]
        body["timeline_data"]["special_defaults"] = {"glow": 0.8}
        r = server.write_map("testmap", body)
        with open(path, encoding="utf-8") as f:
            back = json.load(f)
        check(r.get("ok") is True and back["timeline_data"]["events"][0].get("special") is True and back["timeline_data"].get("special_defaults") == {"glow": 0.8},
              "write_map keeps a swarm's special flag and the map's special_defaults: %s" % back["timeline_data"])
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)

    # ---------------------------------------------------------------- the game's numbers the page mirrors
    with open(os.path.join(GAME, "core", "data", "EnemyDef.gd"), encoding="utf-8") as f:
        ed = f.read()
    m = re.search(r"const SPECIAL_DEFAULTS\s*:?=\s*\{(.*?)\}", ed)
    got = {k: float(v) for k, v in re.findall(r'"([a-z_]+)":\s*([0-9.]+)', m.group(1))} if m else {}
    check(got == GAME_DEFAULTS, "EnemyDef.SPECIAL_DEFAULTS is what the page greys in: %s" % got)
    with open(os.path.join(GAME, "core", "systems", "WaveDirector.gd"), encoding="utf-8") as f:
        wd = f.read()
    check('bool(ev.get("special", false))' in wd and "em.special_defaults = timeline.special_defaults" in wd,
          "WaveDirector reads a swarm's special flag and hands the map's special_defaults to the crowd")
