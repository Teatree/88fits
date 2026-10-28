"""Pass 84, lane TIMELINE: the Timeline rebuilt in sections (Garry: "allow for the option to collapse some sections ...
easy to tell where a section was collapsed. Mark somehow (in a subtle way) which sections are view only, and which are
tools for editing things"; "I would prefer the charts ... to be not too abstract"; "better add too many controls than
too few"; "the ability to modify the enemy by the stats that they have, the colouring, the behaviour, the everything in
the timeline itself").

Groups: timeline_model.js's page-free maths under Node (a row's schedule in words, the kill rate per second, who is
alive by source and by creature against the estimate's own counts, the composition, the cap in bodies, cap full and the
starving rows, the challenge's two measures and their zones, the typical hero, the crowd's HP and bite, overlapping
identical rows, a floor above the cap, the jumps); fields.js (the sections and their kinds, the view lanes, every row
field with its help, the pass 84 row keys, Once, Every as a range, the who switch, the Behaviour override groups with
their help, the floor curve); the conversion on load (lane SPAWN's convertLegacy: an old timeline converts, a converted
or a plain one is left byte for byte as it was: no churn); the warnings' pieces on a fixture; the page's words
(sections, marks, collapsed bars, the explanation boxes, the warnings panel, the Sim overlay route, the inspector's
groups, its mini-chart, split and convert, index.html's script order and glyphs, style.css's recess and hatch).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const M = require(process.argv[2]);
const dir = path.dirname(process.argv[2]);
const T = require(path.join(dir, 'timeline_model.js'));
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.pace = q.rows.map((r) => [T.paceOf(r), T.everyRange(r), T.quantityText(r, 12, 41.7), T.roleOf(r), T.suggestRole(r, q.creatures[Array.isArray(r.enemy) ? r.enemy[0] : r.enemy] || null)]);
  out.tv = q.tv.map(([tv, t, s]) => T.turnoverAt(tv, t, s));
  // the estimate of a fixture, then who is alive
  const est = M.spawnEstimate(q.tl, q.creatures, { turnover: 0.08, bossSeconds: 20, portalSeconds: 10, end: 400 });
  const srcCreature = (k) => { const p = k.split(':'); if (p[0] !== 'roster') return ''; const r = q.tl.roster[Number(p[1])]; return r && typeof r.enemy === 'string' && r.enemy !== 'roster' ? r.enemy : ''; };
  const ser = T.aliveSeries(est, srcCreature, (t) => Math.floor(t / (q.tl.stage_length || 300)));
  const sums = [];
  for (let j = 0; j < ser.n; j += 7) {
    let s = 0; for (const k of Object.keys(ser.src)) s += ser.src[k][j];
    let si = 0; for (const id of Object.keys(ser.id)) si += ser.id[id][j];
    const p = est.points[j];
    const want = p.aliveBy ? Object.values(p.aliveBy).reduce((a, b) => a + b, 0) : p.alive;
    const comp = T.compositionAt(ser, j);
    sums.push([ser.t[j], s, si, want, comp.reduce((a, o) => a + o.share, 0), comp.length, p.aliveBy ? 1 : 0]);
  }
  out.sums = sums;
  out.idx = [T.indexAt(ser, -5), T.indexAt(ser, 0), T.indexAt(ser, 10.5), T.indexAt(ser, 1e9) === ser.n - 1];
  const j = T.indexAt(ser, 200);
  const L = T.loadAt(ser, j, (id) => (q.creatures[id] || {}).cap_share || 1, () => false);
  out.load = [L.load, L.bodies, T.capBodies(60, L.load, L.bodies, 1), T.capBodies(60, 0, 0, 0.5)];
  out.spawned = T.spawnedBetween(est, M.estimateAt(est, 100), M.estimateAt(est, 150)).map((o) => [o.id, o.n, o.share]);
  out.crowd = (() => { const c = T.crowdAt(ser, j, (k) => (k.includes('brute') ? { hp: 100, atk: 10, bite: 0.5, boss: false, spHp: 1 } : { hp: 10, atk: 2, bite: 0.6, boss: false, spHp: 1 })); return [c.hp, c.bite, c.threat, c.n, c.top.map((o) => o.id)]; })();
  out.crowdHand = T.crowdAt({ n: 1, t: [5], src: { 'roster:0': [3], 'other:boss': [1] }, id: { a: [3], boss: [1] }, col: { a: [1], boss: [0] }, keyId: { 'roster:0': 'a', 'other:boss': 'boss' } }, 0,
    (k) => (k === 'other:boss' ? { hp: 999, atk: 99, bite: 1, boss: true, spHp: 1 } : { hp: 20, atk: 3, bite: 0.5, boss: false, spHp: 15 }));
  out.zones = [T.zoneOf(5, T.ZONES), T.zoneOf(10, T.ZONES), T.zoneOf(30, T.ZONES), T.zoneOf(30.5, T.ZONES), T.zoneOf(null, T.ZONES), T.zoneOf(0.5, T.BAR_ZONES), T.zoneOf(4, T.BAR_ZONES)];
  const marks = [{ t: 0, power: 1 }, { t: 430, power: 3.5 }, { t: 860, power: 9 }, { t: 1290, power: 23 }];
  out.hero = [0, 215, 430, 860, 1290, 1500].map((t) => T.typicalHero(t, marks, 20.4, 100));
  out.twins = T.overlappingTwins(q.twins, 1000);
  out.floor = T.floorOverCap((t) => (t < 100 ? 10 : 80), () => 50, 300, 5);
  out.floorNone = T.floorOverCap(() => 10, () => 50, 300, 5);
  out.starve = T.starvingAt({ points: [{ starve: { 'roster:1': 0.5, 'roster:2': 0.1, 'roster:3': 0.9 } }] }, { n: 1, t: [0] }, 0, [], () => true);
  out.recipes = Object.fromEntries(Object.entries(T.RECIPES).map(([k, r]) => [k, { what: r.what, lines: r.lines.map((l) => l[0] + ': ' + l[1]) }]));
  out.roles = T.ROLES.map((r) => [r.v, r.color, r.help]);
  out.fields = {
    sections: FIELDS.SECTIONS.map((s) => ({ id: s.id, kind: s.kind, name: s.name, what: s.what, lanes: s.lanes })),
    view: FIELDS.VIEW_LANES,
    roster: FIELDS.roster.map((d) => ({ key: d.key, label: d.label, type: d.type, help: d.help || '', paceIn: d.paceIn || null, options: (d.options || []).map((o) => o.v) })),
    paces: FIELDS.PACES.map((o) => [o.v, o.help]),
    modes: FIELDS.ENEMY_MODES.map((o) => [o.v, o.help]),
    groups: FIELDS.OVERRIDE_GROUPS,
    ghelp: FIELDS.OVERRIDE_GROUP_HELP,
    overrides: FIELDS.OVERRIDES.map((d) => ({ path: d.path, group: d.group, help: d.help || '' })),
    floor: (FIELDS.SCALARS.find((d) => d.key === 'floor_curve') || null),
    lanes: FIELDS.LANES.map((l) => ({ id: l.id, text: l.text })),
  };
  // the conversion on load (lane SPAWN's converter): an old timeline converts; a plain or converted one is untouched
  out.conv = null;
  if (typeof M.convertLegacy === 'function') {
    const old = JSON.parse(JSON.stringify(q.legacy));
    const r1 = M.convertLegacy(old, { skin: 'goblin' });
    const once = JSON.stringify(old);
    const r2 = M.convertLegacy(old, { skin: 'goblin' });
    const plain = JSON.parse(JSON.stringify(q.tl));
    const before = JSON.stringify(plain);
    M.convertLegacy(plain, { skin: 'goblin' });
    out.conv = { r1, again: JSON.stringify(old) === once, r2, plainSame: JSON.stringify(plain) === before, rows: old.roster.length, evTypes: (old.events || []).map((e) => e.type), paces: old.roster.map((r) => r.pace || 'continuous') };
    if (q.rc) {
      const rc = JSON.parse(JSON.stringify(q.rc));
      M.convertLegacy(rc, { skin: q.skin || '' });
      const rcOnce = JSON.stringify(rc);
      M.convertLegacy(rc, { skin: q.skin || '' });
      out.rc = { again: JSON.stringify(rc) === rcOnce, legacyLeft: (rc.events || []).filter((e) => ['swarm', 'elite', 'elite_every'].includes(e.type)).length, waves: (rc.waves || []).length };
    }
  }
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def _close(a, b, eps=1e-6):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


CREATURES = {
    "goblin": {"id": "goblin", "name": "Goblin", "kind": "enemy", "hp": 10, "damage": 2, "speed": 2, "pack_size": 3, "cap_share": 0.5, "radius": 0.4, "size": 1},
    "brute": {"id": "brute", "name": "Brute", "kind": "enemy", "hp": 80, "damage": 9, "speed": 1.2, "pack_size": 1, "cap_share": 1, "radius": 0.7, "size": 2},
    "spitter": {"id": "spitter", "name": "Spitter", "kind": "enemy", "hp": 20, "damage": 3, "speed": 1.5, "pack_size": 2, "cap_share": 1, "radius": 0.5, "size": 1.2, "ranged": {"range": 8}},
}

FIXTURE = {
    "stage_length": 300, "stages": 1, "cap_curve": [[0, 40], [200, 60]], "hard_cap": 200, "cap_max": 250, "spawn_interval": 0.5,
    "burst_min": 5, "burst_max": 12,
    "roster": [
        {"id": "r1", "t": 0, "enemy": "goblin", "weights": [[0, 8], [300, 8]]},
        {"id": "r2", "t": 60, "until": 260, "enemy": "brute", "weights": [[60, 3], [260, 3]]},
        {"id": "r3", "t": 120, "enemy": "spitter", "weights": [[120, 2], [300, 2]], "pace": "waves", "every": 30, "count": 6},
        {"id": "r4", "t": 180, "enemy": "goblin", "weights": [[180, 1], [200, 1]], "pace": "once", "count": 20, "respect_cap": False, "pattern": "ring", "ring_radius": 16, "banner": "SWARM!"},
    ],
    "events": [{"t": 300, "type": "boss", "enemy": "brute"}],
}

LEGACY = {
    "stage_length": 300, "stages": 1, "cap_curve": [[0, 40]], "hard_cap": 200,
    "roster": [{"id": "r1", "t": 0, "enemy": "goblin", "weights": [[0, 5], [300, 5]]}],
    "events": [{"t": 100, "type": "swarm", "enemy": "goblin", "count": 24, "name": "Gob swarm"}, {"t": 150, "type": "elite"},
               {"t": 160, "type": "elite_every", "interval": [60, 90]}, {"t": 300, "type": "boss", "enemy": "brute"}],
    "waves": [],
}


def checks(check, run_node, server):
    # ---------------------------------------------------------------- the model under Node
    rows = [{}, {"pace": "waves", "every": 15}, {"pace": "waves", "every": [60, 90], "trickle": True}, {"pace": "once"}, {"pace": "WAVES"},
            {"pace": "waves", "every": 0}, {"role": "tank"}, {"role": "nonsense"}, {"special": True}, {"elite": "random"},
            {"pace": "once", "respect_cap": False}, {"enemy": "spitter"}, {"enemy": "brute"}, {"enemy": ["goblin", "brute"]}]
    rc = None
    skin = ""
    try:
        rcmap = server.load_json(server.map_path("red_canyon"))
        rc = rcmap.get("timeline_data") or {}
        skins = rcmap.get("skins") or {}
        skin = str(list(skins.values())[0]) if isinstance(skins, dict) and skins else ""
    except Exception as e:  # noqa: BLE001
        print("TIMELINE84: Red Canyon not read (%s)" % e)
    twins = [{"t": 0, "until": 100, "enemy": "goblin", "stats": {"hp": 3}}, {"t": 50, "until": 200, "enemy": "goblin", "stats": {"hp": 3}},
             {"t": 150, "until": 300, "enemy": "goblin", "stats": {"hp": 4}}, {"t": 300, "enemy": "goblin", "stats": {"hp": 3}}]
    q = {"rows": rows, "creatures": CREATURES, "tl": FIXTURE, "legacy": LEGACY, "twins": twins, "rc": rc, "skin": skin,
         "tv": [[0.06, 10, 0], [[0.05, 0.1, 0.2], 10, 1], [[0.05, 0.1], 99, 9], [[[0, 0.02], [60, 0.1]], 30, 0], [[[0, 0.02], [60, 0.1]], 999, 0], [3, 0, 0]]}
    res = run_node(q, RUNNER)
    if not res:
        check(False, "TIMELINE84: timeline_model.js and fields.js ran under node")
        return
    pace = res["pace"]
    check([p[0] for p in pace[:6]] == ["continuous", "waves", "waves", "once", "continuous", "waves"], "TIMELINE84: paceOf (WAVES plays continuous): %s" % [p[0] for p in pace])
    check(pace[1][1] == [15, 15] and pace[2][1] == [60, 90] and pace[0][1] == [30, 30], "TIMELINE84: everyRange (a number, a range, empty = 30): %s" % [p[1] for p in pace[:3]])
    check(pace[1][2] == "12 every 15 s" and pace[2][2] == "12 every 60–90 s + drawn" and pace[3][2] == "once 12" and pace[0][2] == "≈42/min" and pace[5][2] == "once 12",
          "TIMELINE84: the bars' quantity words: %s" % [p[2] for p in pace[:6]])
    check(pace[6][3] == "tank" and pace[7][3] == "" and pace[0][3] == "", "TIMELINE84: roleOf keeps the six roles only")
    sug = {i: p[4] for i, p in enumerate(pace)}
    check(sug[8] == "special" and sug[9] == "elite" and sug[10] == "swarm" and sug[11] == "ranged" and sug[12] == "tank" and sug[13] == "fodder",
          "TIMELINE84: Suggest roles: special, elite, a burst, a ranged creature, a heavy one, else fodder: %s" % sug)
    tv = res["tv"]
    check(_close(tv[0], 0.06) and _close(tv[1], 0.1) and _close(tv[2], 0.1) and _close(tv[3], 0.06) and _close(tv[4], 0.1) and _close(tv[5], 1),
          "TIMELINE84: turnoverAt (flat, per stage, the last stage on, minute points straight between, never above 1): %s" % tv)
    sums = res["sums"]
    bad = [s for s in sums if not (_close(s[1], s[2], 1e-6) and _close(s[1], s[3], 1e-6))]
    check(len(sums) > 20 and not bad, "TIMELINE84: alive by source = alive by creature = the estimate's own count at every point (%d sampled): %s" % (len(sums), bad[:3]))
    badc = [s for s in sums if s[3] > 0.5 and not _close(s[4], 1, 1e-6)]
    check(not badc and any(s[5] >= 2 for s in sums), "TIMELINE84: the composition's shares add up to 100%% wherever anyone is alive: %s" % badc[:3])
    print("TIMELINE84: the estimate's per-creature alive counts (lane SPAWN's aliveBy) %s" % ("used" if any(s[6] for s in sums) else "absent: scaled to the total"))
    check(res["idx"][0] == 0 and res["idx"][1] == 0 and res["idx"][3] is True, "TIMELINE84: indexAt at the edges: %s" % res["idx"])
    ld = res["load"]
    check(ld[1] > 0 and ld[0] > 0 and ld[0] < ld[1] + 1e-9 and _close(ld[2], 60 * ld[1] / ld[0]) and _close(ld[3], 120),
          "TIMELINE84: the load (goblins half a unit) and the cap in bodies at the crowd's mix: %s" % ld)
    sp = res["spawned"]
    check(sp and _close(sum(x[2] for x in sp), 1) and all(sp[k][1] >= sp[k + 1][1] for k in range(len(sp) - 1)), "TIMELINE84: spawnedBetween: shares of what spawned, largest first: %s" % sp)
    cr = res["crowd"]
    check(cr[0] > 0 and cr[1] > 0 and cr[2] > 0 and cr[3] > 0, "TIMELINE84: the crowd's HP, bite and threat on a fixture: %s" % cr[:4])
    ch = res["crowdHand"]
    # 3 alive of HP 20 (one of them coloured: x15), the boss left out: HP 3 x 20 + 1 x 20 x 14 = 340; bite 3 x 3 / 0.5 = 18;
    # threat = HP x ATK / bite interval = 340 x 3 / 0.5 = 2040
    check(_close(ch["hp"], 340) and _close(ch["bite"], 18) and _close(ch["threat"], 2040) and _close(ch["n"], 3) and [o["id"] for o in ch["top"]] == ["a"],
          "TIMELINE84: crowdAt by hand (a coloured special's HP, the boss left out): %s" % ch)
    check(res["zones"] == ["easy", "fair", "fair", "hard", "", "easy", "hard"], "TIMELINE84: the zones (under easy, to hard inclusive, past it): %s" % res["zones"])
    hero = res["hero"]
    check(_close(hero[0]["dps"], 20.4) and _close(hero[2]["power"], 3.5) and _close(hero[2]["dps"], 20.4 * 3.5 ** 2) and _close(hero[3]["power"], 9) and _close(hero[0]["ehp"], 100)
          and hero[1]["power"] > 1 and hero[1]["power"] < 3.5 and hero[5]["power"] > 23,
          "TIMELINE84: the typical hero: power on the probe's marks, straight between on a log scale, growing on; DPS 20.4 x power^2, EHP 100: %s" % [round(h["power"], 3) for h in hero])
    check(res["twins"] == [[0, 1], [0, 3]] or res["twins"] == [[0, 1]], "TIMELINE84: overlapping identical rows: rows 1 and 2 (row 3 differs, row 4 starts after row 1 ends): %s" % res["twins"])
    check(res["floor"] and res["floor"]["t"] == 100 and res["floorNone"] is None, "TIMELINE84: a floor above the cap is found at its first second: %s" % res["floor"])
    check(res["starve"] == ["roster:3", "roster:1"], "TIMELINE84: lane SPAWN's starve shares: a row starves at a quarter or more, the hungriest first: %s" % res["starve"])
    rec = res["recipes"]
    check(set(rec) >= {"onscreen", "challenge", "challenge_bars", "composition"}, "TIMELINE84: every view chart has its recipe: %s" % list(rec))
    for k, words in [("onscreen", ["estimate", "Sim", "cap", "floor", "red"]), ("challenge", ["crowd HP", "hero damage a second", "Sim", "zones", "dots"]),
                     ("challenge_bars", ["crowd HP × bite", "Sim", "zones"]), ("composition", ["on screen", "spawned", "colours"])]:
        r = rec.get(k) or {"what": "", "lines": []}
        names = [ln.split(":")[0] for ln in r["lines"]]
        check(len(r["what"]) > 60 and all(any(w == n or n.startswith(w) for n in names) for w in words) and all(len(ln) > 40 for ln in r["lines"]),
              "TIMELINE84: the %s recipe says what it is and names every line: %s" % (k, names))
    check(len(res["roles"]) == 7 and all(re.match(r"^#[0-9a-f]{6}$", c) and len(h) > 10 for _v, c, h in res["roles"]), "TIMELINE84: seven roles (untagged too), each a colour and a help")
    # ---------------------------------------------------------------- fields.js
    fl = res["fields"]
    secs = fl["sections"]
    # pass 110 (lane BOSS): "Boss fights" after the spawn rows
    check([s["id"] for s in secs] == ["controls", "onscreen", "challenge", "composition", "spawned", "rows", "bossfight", "events", "curves", "warnings"],
          "TIMELINE84: the sections top to bottom: %s" % [s["id"] for s in secs])
    kinds = {s["id"]: s["kind"] for s in secs}
    check(all(kinds[k] == "view" for k in ["onscreen", "challenge", "composition", "spawned", "warnings"]) and all(kinds[k] == "edit" for k in ["controls", "rows", "bossfight", "events", "curves"]),
          "TIMELINE84: every section is marked view only or editing: %s" % kinds)
    check(all(len(s["what"]) > 30 for s in secs), "TIMELINE84: every section says what it is")
    lanes_in = [ln for s in secs for ln in s["lanes"]]
    check(set(fl["view"]) == {"alive", "challenge", "composition", "spawned", "hp_act", "dmg_act"} and set(fl["view"]) <= set(lanes_in), "TIMELINE84: the view lanes: %s" % fl["view"])
    lane_ids = [ln["id"] for ln in fl["lanes"]]
    check(all(x in lane_ids for x in ["alive", "challenge", "composition", "floor"]), "TIMELINE84: the Instructions' lane list has the new lanes")
    by = {d["key"]: d for d in fl["roster"]}
    check(all(len(d["help"]) > 30 for d in fl["roster"]), "TIMELINE84: every row field has its help: %s" % [d["key"] for d in fl["roster"] if len(d["help"]) <= 30])
    for k in ["name", "role", "elite", "special", "ring_radius", "banner", "chance", "t_jitter"]:
        check(k in by, "TIMELINE84: the row form has %s" % k)
    check(by.get("pace", {}).get("options") == ["continuous", "waves", "once"] and [p[0] for p in fl["paces"]] == ["continuous", "waves", "once"], "TIMELINE84: Pacing offers Once")
    check(by.get("every", {}).get("type") == "interval" and by["every"]["paceIn"] == ["waves"] and "min and max" in by["every"]["help"], "TIMELINE84: Every is a number or [min, max], on a waves row")
    check(all(by[k]["paceIn"] == ["waves", "once"] for k in ["count", "offset", "respect_cap", "trickle", "banner", "chance", "t_jitter"]), "TIMELINE84: the wave fields show on a waves and a once row")
    check(by.get("role", {}).get("options") == ["", "fodder", "swarm", "tank", "ranged", "elite", "special"], "TIMELINE84: Role offers the six roles and untagged")
    check([m[0] for m in fl["modes"]] == ["one", "list", "roster"] and all(len(m[1]) > 30 for m in fl["modes"]), "TIMELINE84: who a row brings: one, a list, the roster draw")
    for g in ["Kamikaze", "Artillery", "Sniper", "Flee on hit"]:
        check(g in fl["groups"] and any(d["group"] == g for d in fl["overrides"]), "TIMELINE84: the %s override group" % g)
    ov = {d["path"]: d for d in fl["overrides"]}
    for path in ["size_mult", "radius_mult", "ranged.keep_distance", "ranged.damage", "charge.windup", "kamikaze.radius", "artillery.missile.speed", "sniper.lock", "flee_on_hit.seconds"]:
        check(path in ov and len(ov[path]["help"]) > 20, "TIMELINE84: the override %s with its help" % path)
    fd = fl["floor"]
    check(bool(fd) and fd["type"] == "floor_points" and "least creatures alive" in fd["help"], "TIMELINE84: the floor curve in Settings -> Cap: %s" % (fd or {}).get("type"))
    # ---------------------------------------------------------------- the conversion on load (lane SPAWN's converter)
    cv = res.get("conv")
    if cv is None:
        print("TIMELINE84: model.js has no convertLegacy yet (lane SPAWN): the load-time conversion is not checked")
    else:
        check(cv["again"] and cv["plainSame"], "TIMELINE84: converting twice changes nothing, a timeline with nothing old is left as it was (no churn)")
        check(cv["rows"] == 4 and cv["evTypes"] == ["boss"] and "once" in cv["paces"] and "waves" in cv["paces"],
              "TIMELINE84: the swarm, the coloured elite and Elites every became rows, the boss stays: %s %s" % (cv["paces"], cv["evTypes"]))
        if res.get("rc"):
            check(res["rc"]["again"] and res["rc"]["legacyLeft"] == 0 and res["rc"]["waves"] == 0, "TIMELINE84: Red Canyon converts once and is stable after: %s" % res["rc"])
    # ---------------------------------------------------------------- the page's words
    tlj = _read("timeline.js")
    for frag in ["function buildSection(sec)", "collapsed: click to open", "function kindMark(kind, small)", "function explainStrip(id, legend)",
                 "'How it is worked out (the recipe and the units)'", "function renderAlive(w)", "function renderChallenge(w)", "function renderComposition(w)",
                 "function renderFloor(w)", "function renderWarnings()", "function warningsOf()", "/api/sim/overlay?map=", "function rosterLayout(rows)",
                 "secState['group:' +", "function setAll(on)", "SEC_KEY", "function wireInspectorFold()", "function rowMenu(anchor)", "TimelineModel.quantityText",
                 "Model.creatureDifficulty", "lifetimes from the Sim", "function goTo(wn)"]:
        check(frag in tlj, "TIMELINE84: timeline.js has %s" % frag)
    insp = _read("inspector.js")
    # pass 110 (lane BOSS): rowEnemyControl, convertRow and the → once action take a window row too (env, row)
    for frag in ["const ROW_GROUPS = [", "function igroup(g, sub)", "function rowEnemyControl(r", "function miniChart(i, r)", "App.splitRow(i, cutT)",
                 "App.convertRow(i, pace)", "function floorForm(container)", "function portalForm(container)", "enemy_weights"]:
        check(frag in insp, "TIMELINE84: inspector.js has %s" % frag)
    app = _read("app.js")
    for frag in ["function legacyConvert(tld)", "M.convertLegacy(tld", "function newRowPreset(kind, t)", "function splitRow(i, t)", "function convertRow(i, pace",
                 "function rowKeyIssues(r, key, mark)", "a floor point is not [seconds, creatures]", "life: S.useSimLife && S.simLife"]:
        check(frag in app, "TIMELINE84: app.js has %s" % frag)
    html = _read("index.html")
    i_m, i_tm, i_t = html.find('<script src="model.js">'), html.find('<script src="timeline_model.js">'), html.find('<script src="timeline.js">')
    check(0 < i_m < i_tm < i_t, "TIMELINE84: index.html loads timeline_model.js after model.js, before timeline.js")
    check('id="g-eye"' in html and 'id="g-pencil"' in html, "TIMELINE84: index.html has the eye and the pencil")
    css = _read("style.css")
    for frag in [".tl-sec.collapsed .tl-sec-head", "repeating-linear-gradient", ".lane.lane-view", "--recess", ".kmark-view", ".kmark-edit", ".full-band", ".zone-hard",
                 ".insp-folded-bar", ".igroup:not([open])", ".tl-warn-row"]:
        check(frag in css, "TIMELINE84: style.css has %s" % frag)
    ins = _read("instructions.js")
    check("function pass84Timeline(root)" in ins and "The marks." in ins and "FIELDS.SECTIONS" in ins, "TIMELINE84: the Instructions tab explains the sections and the marks")
    print("TIMELINE84: model, fields, conversion and page words checked (%d alive samples)" % len(sums))
