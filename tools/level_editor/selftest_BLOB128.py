"""Pass 128, lane BLOB: the Level Editor's side of relocation. selftest.py discovers this file (`extra_checks`) and hands
it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes.

Groups: the map's `relocate` rows in fields.js (eleven keys since pass 134 in their own Relocation card, explained, their grey numbers
WaveTimeline.RELOCATE_DEFAULTS) and the row field `relocate` (in the row card's Where and how group, in the save order);
model.js's relocateCfg (the game's block: gaps filled, the ring [near, far], at least one sector, no negative number),
rowRelocate (the effective value and its source: a regular creature on by default, a squad creature off by default and
on by its row or by the map's `squads`, an Elite row, a special row, a boss, an Elite by its kind, a special type and a
dummy locked off, a list of different creatures "mixed", the roster draw) and setRowRelocate (sparse: a value equal to
the row's default takes the key out); the game reading the block (JsonContent), handing it over (WaveDirector) and
playing it (EnemyManager, CrowdRelocate); Red Canyon's block and its far-speed numbers; the two docs.
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
  out.rows = FIELDS.SCALARS.filter((d) => d.key.startsWith('relocate.')).map((d) => [d.key, d.group, d.type, d.def === undefined ? null : d.def, !!d.help, d.block || null, d.label]);
  out.groups = FIELDS.SCALAR_GROUPS;
  const rf = FIELDS.roster.find((d) => d.key === 'relocate');
  out.rowField = rf ? [rf.key, rf.type, rf.def, !!rf.help, rf.label] : null;
  out.defaults = Model.RELOCATE_DEFAULTS;
  const tl = q.tl || {};
  out.cfg = Model.relocateCfg(tl);
  out.cfgEmpty = Model.relocateCfg({});
  out.cfgBad = Model.relocateCfg({ relocate: { distance: 20, ring: [30, 22], sectors: 0, squads: true, seconds: 'soon', sink: -1 } });
  out.cfgOne = Model.relocateCfg({ relocate: { ring: 21 } }).ring;
  out.text = Model.relocateText(tl);
  out.textOff = Model.relocateText({ relocate: { enabled: false } });
  out.issues = Model.relocateIssues(tl);
  out.issuesBad = Model.relocateIssues({ relocate: { ring: [10, 12], every: 0 } }).length;
  const sk = { id: 'skeleton', kind: 'enemy', archetype: 'walker', brain: 'chase' };
  const mk = { id: 'monk', kind: 'enemy', archetype: 'spitter', brain: 'squad' };
  const el = { id: 'stone_golem', kind: 'enemy', archetype: 'elite', brain: 'chase' };
  const bs = { id: 'gila_grande', kind: 'boss', archetype: 'boss' };
  const gr = { id: 'saiga_sniper', kind: 'enemy', archetype: 'spitter', brain: 'sniper', badge: 'gear' };
  const dm = { id: 'training_dummy', kind: 'enemy', archetype: 'brute', brain: 'dummy' };
  const st = (t, r, cs) => { const s = Model.rowRelocate(t, r, cs); return [s.value, s.def, s.own, s.locked, s.source, s.mapOff, s.text]; };
  out.st = {
    regular: st({}, { enemy: 'skeleton' }, [sk]),
    regularOff: st({}, { enemy: 'skeleton', relocate: false }, [sk]),
    regularOn: st({}, { enemy: 'skeleton', relocate: true }, [sk]),
    squad: st({}, { enemy: 'monk' }, [mk]),
    squadOn: st({}, { enemy: 'monk', relocate: true }, [mk]),
    squadMap: st({ relocate: { squads: true } }, { enemy: 'monk' }, [mk]),
    squadMapOff: st({ relocate: { squads: true } }, { enemy: 'monk', relocate: false }, [mk]),
    elite: st({}, { enemy: 'skeleton', elite: 'random', relocate: true }, [sk]),
    special: st({}, { enemy: 'skeleton', special: true }, [sk]),
    eliteKind: st({}, { enemy: 'stone_golem' }, [el]),
    boss: st({}, { enemy: 'gila_grande' }, [bs]),
    gear: st({}, { enemy: 'saiga_sniper' }, [gr]),
    dummy: st({}, { enemy: 'training_dummy' }, [dm]),
    mixed: st({}, { enemy: ['skeleton', 'monk'] }, [sk, mk]),
    listWithElite: st({}, { enemy: ['skeleton', 'stone_golem'] }, [sk, el]),
    roster: st({}, { enemy: 'roster' }, []),
    mapOff: st({ relocate: { enabled: false } }, { enemy: 'skeleton' }, [sk]),
    unknown: st({}, { enemy: 'nobody' }, []),
  };
  // the box written sparsely
  const write = (t, r, cs, v) => { const ok = Model.setRowRelocate(t, r, cs, v); return [ok, Object.prototype.hasOwnProperty.call(r, 'relocate') ? r.relocate : null]; };
  out.wr = {
    regularOff: write({}, { enemy: 'skeleton' }, [sk], false),
    regularBackOn: write({}, { enemy: 'skeleton', relocate: false }, [sk], true),
    regularOnAgain: write({}, { enemy: 'skeleton' }, [sk], true),
    squadOn: write({}, { enemy: 'monk' }, [mk], true),
    squadBackOff: write({}, { enemy: 'monk', relocate: true }, [mk], false),
    squadMapOff: write({ relocate: { squads: true } }, { enemy: 'monk' }, [mk], false),
    mixedOn: write({}, { enemy: ['skeleton', 'monk'] }, [sk, mk], true),
    mixedOff: write({}, { enemy: ['skeleton', 'monk'] }, [sk, mk], false),
    rosterOff: write({}, { enemy: 'roster' }, [], false),
    rosterOn: write({}, { enemy: 'roster', relocate: false }, [], true),
    eliteLocked: write({}, { enemy: 'skeleton', elite: 'random' }, [sk], true),
    bossLocked: write({}, { enemy: 'gila_grande' }, [bs], true),
  };
  // every row of the map as the card would show it (the creature records: the query's)
  const cr = q.creatures || {};
  out.mapRows = (Array.isArray(tl.roster) ? tl.roster : []).map((r) => {
    const ids = r.enemy === 'roster' ? [] : (Array.isArray(r.enemy) ? r.enemy : [r.enemy]);
    const s = Model.rowRelocate(tl, r, ids.map((id) => cr[id]).filter(Boolean));
    return [r.id || '', s.value, s.locked, s.source, Object.prototype.hasOwnProperty.call(r, 'relocate') ? r.relocate : null, s.def];
  });
  // the save order keeps the key where the row's other switches are
  out.order = (() => { const m = fs.readFileSync(path.join(dir, 'model.js'), 'utf8').match(/const ROW84_ORDER = \[([^\]]*)\]/); return m ? m[1].replace(/['\s]/g, '').split(',') : []; })();
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _creatures():
    """The creature records the page would hold for the rows, as far as relocation reads them."""
    out = {}
    for kind_dir, kind in (("enemies", "enemy"), ("bosses", "boss")):
        base = os.path.join(CONTENT, kind_dir)
        if not os.path.isdir(base):
            continue
        for cid in sorted(os.listdir(base)):
            p = os.path.join(base, cid, cid + ".json")
            if not os.path.exists(p):
                continue
            try:
                d = json.loads(_read(p))
            except ValueError:
                continue
            out[cid] = {"id": cid, "kind": kind, "archetype": str(d.get("archetype", "")), "brain": str(d.get("brain", "")), "badge": str(d.get("badge", ""))}
    return out


def checks(check, run_node, server):
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    m = re.search(r"const RELOCATE_DEFAULTS := (\{.*?\})\n", wt)
    dflt = json.loads(m.group(1)) if m else {}
    # pass 134 (lane RELOC): `hidden` (off) and `chance` (1) joined them; selftest_RELOC134.py checks their rows
    check(dflt == {"enabled": True, "distance": 16.0, "seconds": 5.0, "every": 0.4, "ring": [19.0, 24.0], "sectors": 12, "sink": 0.35, "scan": 0.5, "squads": False, "hidden": False, "chance": 1.0},
          "BLOB128: WaveTimeline.RELOCATE_DEFAULTS are the rule's numbers (on, 16 m, 5 s, one every 0.4 s, ring 19-24 m, 12 sectors, sink 0.35 s, scan 0.5 s, no squads, not hidden, chance 1): %s" % dflt)
    check("func relocate_cfg() -> Dictionary" in wt and "@export var relocate: Dictionary" in wt and "static func row_relocate(r) -> int" in wt,
          "BLOB128: WaveTimeline carries the block, fills it and reads a row's say")
    mp = json.loads(_read(CONTENT, "maps", "red_canyon", "red_canyon.json"))
    tl = mp.get("timeline_data", {})
    creatures = _creatures()
    res = run_node({"tl": tl, "creatures": creatures}, RUNNER)
    if not res:
        check(False, "BLOB128: node ran fields.js and model.js")
    else:
        rows = {r[0]: r for r in res["rows"]}
        want = {"relocate." + k for k in dflt}
        check(set(rows) == want, "BLOB128: fields.js has exactly the relocate rows of the defaults (eleven): %s" % sorted(rows))
        check(all(r[1] == "Relocation" and r[4] and r[5] is None for r in rows.values()), "BLOB128: every relocate row sits in the Relocation card, explained, no block")
        check("Relocation" in res["groups"], "BLOB128: the Settings tab has the Relocation card")
        defs = {k: rows["relocate." + k][3] for k in dflt if "relocate." + k in rows}
        # the ring's two boxes show the near distance as their grey number (its help names both)
        check(all((defs[k] == dflt[k][0]) if isinstance(dflt[k], list) else (defs[k] == dflt[k]) if isinstance(dflt[k], bool) else float(defs[k]) == float(dflt[k]) for k in defs),
              "BLOB128: the rows' grey numbers are the game's: %s" % defs)
        check(rows.get("relocate.ring", [None] * 3)[2] == "interval" and rows.get("relocate.sectors", [None] * 3)[2] == "int"
              and rows.get("relocate.enabled", [None] * 3)[2] == "bool" and rows.get("relocate.squads", [None] * 3)[2] == "bool",
              "BLOB128: the ring is a range, the sectors a whole number, the two switches boxes")
        check(not any("hero" in str(r[6]).lower() for r in rows.values()), "BLOB128: no row's label says hero")
        md = res["defaults"]
        check(all((md[k] == dflt[k]) if isinstance(dflt[k], (bool, list)) else float(md[k]) == float(dflt[k]) for k in dflt) and set(md) == set(dflt),
              "BLOB128: model.js RELOCATE_DEFAULTS are the game's: %s" % md)
        check(res["cfgEmpty"] == md, "BLOB128: relocateCfg fills an empty map with the defaults")
        bad = res["cfgBad"]
        check(bad["distance"] == 20 and bad["ring"] == [22, 30] and bad["sectors"] == 1 and bad["squads"] is True and bad["seconds"] == 5 and bad["sink"] == 0 and bad["every"] == 0.4,
              "BLOB128: relocateCfg mends a block as the game does (ring sorted, one sector at least, a word = the default, no negative time): %s" % bad)
        check(res["cfgOne"] == [21, 21], "BLOB128: one number for the ring is that distance")
        blk = tl.get("relocate")
        check(isinstance(blk, dict) and set(blk) == set(dflt), "BLOB128: Red Canyon's relocate block names every key and no other: %s" % blk)
        if isinstance(blk, dict):
            cfg = res["cfg"]
            check(all((cfg[k] == sorted(blk[k])) if isinstance(blk.get(k), list) else cfg[k] == blk.get(k, dflt[k]) for k in dflt), "BLOB128: relocateCfg reads Red Canyon's block as it is: %s" % cfg)
            check(cfg["ring"][0] >= cfg["distance"], "BLOB128: Red Canyon's creatures rise no nearer than they count as far (%s m >= %s m)" % (cfg["ring"][0], cfg["distance"]))
        check(res["issues"] == [] and res["issuesBad"] == 2, "BLOB128: relocateIssues warns of a ring inside the far distance and a clock of 0, nothing on the map's block: %s" % res["issues"])
        check("joins the queue" in res["text"] and "Not a spawn" in res["text"] and "hero" not in res["text"].lower() and res["textOff"].startswith("Relocation: off"),
              "BLOB128: the card reads the block back in one sentence, and says off when it is")
        st = res["st"]
        # [value, def, own, locked, source, mapOff, text]
        check(st["regular"][:5] == [True, True, None, False, "default"], "BLOB128: a regular creature's row relocates by default: %s" % st["regular"])
        check(st["regularOff"][:5] == [False, True, False, False, "row"] and st["regularOn"][:5] == [True, True, True, False, "row"], "BLOB128: a row's own value wins and is named as the row's")
        check(st["squad"][:5] == [False, False, None, False, "squad"], "BLOB128: a Monk row is off by default, not locked: %s" % st["squad"])
        check(st["squadOn"][:5] == [True, False, True, False, "row"], "BLOB128: a Monk row can be switched on")
        check(st["squadMap"][:5] == [True, True, None, False, "default"] and st["squadMapOff"][:5] == [False, True, False, False, "row"], "BLOB128: the map's Squads too makes Monks relocate by default, a row's no still holds")
        for k, src in (("elite", "elite"), ("special", "special"), ("eliteKind", "kind"), ("boss", "kind"), ("gear", "kind"), ("dummy", "kind")):
            check(st[k][0] is False and st[k][3] is True and st[k][4] == src and st[k][6].startswith("off: "), "BLOB128: %s: locked off with its reason: %s" % (k, st[k][6]))
        check("Elite row never relocates" in st["elite"][6] and "special row never relocates" in st["special"][6] and "boss never relocates" in st["boss"][6],
              "BLOB128: the locked rows say why in plain words")
        check(st["mixed"][:5] == [True, None, None, False, "mixed"], "BLOB128: a list of a regular and a squad creature has no one default: %s" % st["mixed"])
        check(st["listWithElite"][:5] == [True, True, None, False, "default"], "BLOB128: a list with an Elite beside a regular creature is not locked (the Elite stays put on its own)")
        check(st["roster"][:5] == [True, True, None, False, "roster"] and "drawn from" in st["roster"][6], "BLOB128: the roster draw follows the rows it draws from")
        check(st["mapOff"][5] is True and "switched off for the whole map" in st["mapOff"][6] and st["regular"][5] is False, "BLOB128: a map with relocation off says so on every row")
        check(st["unknown"][:5] == [True, True, None, False, "default"], "BLOB128: a row whose creature the page does not know plays the default")
        check(not any("hero" in s[6].lower() for s in st.values()), "BLOB128: no row line says hero")
        wr = res["wr"]
        check(wr["regularOff"] == [True, False] and wr["regularBackOn"] == [True, None] and wr["regularOnAgain"] == [True, None], "BLOB128: a regular row stores only `relocate: false`: %s" % [wr["regularOff"], wr["regularBackOn"], wr["regularOnAgain"]])
        check(wr["squadOn"] == [True, True] and wr["squadBackOff"] == [True, None], "BLOB128: a Monk row stores only `relocate: true`")
        check(wr["squadMapOff"] == [True, False], "BLOB128: with Squads too on, a Monk row stores `relocate: false`")
        check(wr["mixedOn"] == [True, True] and wr["mixedOff"] == [True, False], "BLOB128: a row of different defaults stores whatever the box says")
        check(wr["rosterOff"] == [True, False] and wr["rosterOn"] == [True, None], "BLOB128: a roster-draw row stores only a no")
        check(wr["eliteLocked"] == [False, None] and wr["bossLocked"] == [False, None], "BLOB128: a locked row is never written")
        rf = res["rowField"]
        check(rf is not None and rf[1] == "bool" and rf[2] is True and rf[3] and rf[4] == "Relocates when far", "BLOB128: the row field is the box Relocates when far, explained: %s" % rf)
        check("relocate" in res["order"] and res["order"].index("relocate") == res["order"].index("special") + 1, "BLOB128: the save order writes relocate after special")
        # every row of the map: sparse (a stored value differs from the row's default), and a locked row carries none
        mr = res["mapRows"]
        stored = [r for r in mr if r[4] is not None]
        check(all(r[5] is None or r[4] != r[5] for r in stored if not r[2]), "BLOB128: every `relocate` the map's rows store differs from that row's default: %s" % stored)
        monks = [r for r in mr if r[3] == "squad"]
        regular_on = [r for r in mr if r[1] and not r[2]]
        print("BLOB128: Red Canyon: %d rows; %d relocate, %d locked off (Elite, special, kind), %d squad rows off by default, %d store their own value" % (
            len(mr), len(regular_on), len([r for r in mr if r[2]]), len(monks), len(stored)))
    ins = _read(HERE, "inspector.js")
    check("'relocate'], help: 'where they spawn" in ins and "function relocateRow(def, r)" in ins and "Model.setRowRelocate(App.tl(), r, creatures, cb.checked)" in ins
          and "cb.disabled = st.locked" in ins and "if (def.key === 'relocate') { host.appendChild(relocateRow(def, r)); continue; }" in ins,
          "BLOB128: the row card draws the box in Where and how, disabled when locked, written through the model")
    se = _read(HERE, "settings.js")
    check("group === 'Relocation'" in se and "Model.relocateText(tl)" in se and "Model.relocateIssues(tl)" in se, "BLOB128: the Relocation card reads the block back and warns")
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    check('t.get("relocate", {})' in jc and "w.relocate = rlc if rlc is Dictionary else {}" in jc, "BLOB128: JsonContent reads the map's relocate block as it is")
    wd = _read(GAME, "core", "systems", "WaveDirector.gd")
    check("em.set_relocate({} if Run.arena else timeline.relocate_cfg())" in wd, "BLOB128: the director hands the block to the crowd, nothing in the arena")
    check(wd.count("_spawn_group_row(") >= 8 and "em.row_relocate = WaveTimeline.row_relocate(r)" in wd and wd.count("em.row_relocate = -1") >= 2,
          "BLOB128: every row's spawn call carries the row's say and takes it down again")
    bf = _read(GAME, "core", "systems", "BossFightWindow.gd")
    check("em.row_relocate = WaveTimeline.row_relocate(r)" in bf and "em.row_relocate = -1" in bf, "BLOB128: a boss-fight window's rows carry it too")
    em = _read(GAME, "core", "systems", "EnemyManager.gd")
    check("func set_relocate(cfg: Dictionary) -> void" in em and "var row_relocate := -1" in em and "_relocate_note_spawn(i)" in em
          and "relocate.tick(delta, player.global_position)" in em, "BLOB128: EnemyManager keeps the flags, notes every spawn and ticks the rule before its grid")
    cr = _read(GAME, "core", "systems", "CrowdRelocate.gd")
    check("class_name CrowdRelocate" in cr and 'Dice.rng_for("crowd_relocate")' in cr and "em.despawn_kind(i)" in cr and "func pick_spot(" in cr
          and "randomize()" not in cr and "randf()" in cr and not re.search(r"(?<![\w.])rand[fi](_range)?\(", cr),
          "BLOB128: CrowdRelocate has its own seeded dice (never the global stream) and reuses the despawn rule's who")
    # the native twin is not touched: it hands every creature that is not walking, is buried, rising or sinking back
    nat = _read(ROOT, "native", "src", "crowd_core.cpp")
    check("st != STATE_MOVE" in nat and "hidden[i] != 0" in nat and "rise_v[i] != 0.0f" in nat and "reloc" not in nat,
          "BLOB128: the compiled crowd needs no change (it hands a standing, buried, rising or sinking creature back to the script)")
    fs = tl.get("far_speed", {})
    check(isinstance(fs, dict) and float(fs.get("max_mult", 0)) >= 4.0 and (float(fs.get("max_speed", 0)) == 0 or float(fs.get("max_speed", 0)) >= 8.0),
          "BLOB128: Red Canyon's far speed is raised (max_mult %s, max_speed %s)" % (fs.get("max_mult"), fs.get("max_speed")))
    ws = _read(ROOT, "docs", "waves_schema.md")
    le = _read(ROOT, "docs", "level_editor.md")
    check("## Pass 128: far creatures relocate (lane BLOB)" in ws and "timeline_data.relocate" in ws and "| `relocate` | bool |" in ws, "BLOB128: docs/waves_schema.md has the block and the row key")
    check("## Pass 128: Relocation (lane BLOB)" in le and "Relocates when far" in le, "BLOB128: docs/level_editor.md explains the card and the row's box")
    print("BLOB128: relocate %s; far_speed max_mult %s, max_speed %s" % (tl.get("relocate"), fs.get("max_mult"), fs.get("max_speed")))
