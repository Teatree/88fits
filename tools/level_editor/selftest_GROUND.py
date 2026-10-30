"""Pass 73, lane GROUND: the Level Editor's side of the ground work. selftest.py discovers this file (`extra_checks`)
and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes.

Groups: the volley rain in boss_model.js (volleyTimes: every shot within the stagger, the farthest last, the burst; the
same numbers as BossAttackDef.volley_times' formula with no burst; isVolley / litAtOnce / windupSeconds on the cactus
rain; its layout's flights) and the Boss attacks tab's rows for the new keys (landing.mode, telegraph.all_at_once, the
spew group, each explained, a Spew section); the burrow's new keys in the creature form (assets_fields.js) and the
vocabulary (vocab.py) agreeing, every one read by EnemyManager.gd; the ring-at-hero warning's exception for a burrow
that predicts its spot; the map's spawn_rise rows in fields.js with WaveTimeline.SPAWN_RISE_DEFAULTS as their grey
numbers; the content (the Gila's and the Dune Scorpion's burrows, the cactus rain, Red Canyon's block).
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
const M = require(path.join(dir, 'boss_model.js'));
global.BossModel = M;
global.U = {};
const BA = require(path.join(dir, 'boss_attacks.js'));
global.AssetsModel = require(path.join(dir, 'assets_model.js'));
const F = require(path.join(dir, 'assets_fields.js'));
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
  const pts = q.pts;
  const R = M.rng(5);
  out.vt = M.volleyTimes(pts, 1.1, 0.25, 0.12, R);
  out.vt0 = M.volleyTimes(pts, 1.1, 0.25, 0.0, M.rng(1));
  out.rain = [M.isVolley(q.rain), M.litAtOnce(q.rain), M.windupSeconds(q.rain)];
  const lay = M.rainLayout(q.rain, 3);
  out.layout = { n: lay.pts.length, spread: lay.lasts - lay.first, flights: lay.flights.length, minFl: Math.min(...lay.flights), gap: lay.gap, cover: lay.cover };
  out.stagger = M.rainLayout(Object.assign({}, q.rain, { landing: { radius: 1.4, mode: 'stagger' } }), 3).flights.every((f) => f === M.rainLayout(q.rain, 3).flight);
  out.fields = BA.FIELDS.filter((f) => ['landing.mode', 'telegraph.all_at_once'].includes(f.g + '.' + f.k) || f.g === 'spew').map((f) => [f.g, f.k, !!f.help, f.kinds]);
  out.sections = BA.SECTIONS.map((s) => s[0]);
  out.iss = M.issues(q.rain);
  out.badMode = M.issues(Object.assign({}, q.rain, { landing: { radius: 1.4, mode: 'sideways' } })).errors;
  out.burrowKeys = F.ATTACKS.burrow.keys.map((k) => [k.key, k.def === undefined ? null : k.def, !!k.help]);
  out.scalars = FIELDS.SCALARS.filter((d) => d.key.startsWith('spawn_rise.')).map((d) => [d.key, d.group, d.def, !!d.help]);
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def checks(check, run_node, server):
    import vocab as VOCAB
    rain = json.loads(_read(CONTENT, "boss_attacks", "cactus_rain", "cactus_rain.json"))
    pts = [[4, 0], [0, 8], [-12, 0], [0, -16], [6, 6]]
    res = run_node({"pts": pts, "rain": rain}, RUNNER)
    if not res:
        check(False, "GROUND: node ran boss_model.js / boss_attacks.js / assets_fields.js / fields.js")
        return
    vt = res["vt"]
    lands, deps = vt["land"], vt["dep"]
    check(max(lands) - min(lands) <= 0.25 + 1e-9 and all(0 <= d <= 0.12 for d in deps)
          and abs((lands[3] - deps[3]) - 1.23) < 1e-9 and abs((lands[0] - deps[0]) - 1.1) < 1e-9,
          "GROUND: volleyTimes: every shot within the stagger, left within the burst, the farthest flies longest: %s" % vt)
    # BossAttackDef.volley_times' formula with no burst: land = flight + stagger x (d - dmin) / (dmax - dmin)
    ds = [(x * x + z * z) ** 0.5 for x, z in pts]
    want = [1.1 + 0.25 * (d - min(ds)) / (max(ds) - min(ds)) for d in ds]
    check(all(abs(a - b) < 1e-9 for a, b in zip(res["vt0"]["land"], want)), "GROUND: volleyTimes is BossAttackDef.volley_times' formula: %s / %s" % (res["vt0"]["land"], want))
    gd = _read(GAME, "core", "data", "BossAttackDef.gd")
    check("land[k] = dep[k] + fl + (st - b) * dn" in gd and "dep[k] = b * rng.randf()" in gd, "GROUND: BossAttackDef.volley_times still reads as the page's mirror")
    check(res["rain"][0] is True and res["rain"][1] is True and res["rain"][2] >= float(rain["telegraph"]["seconds"]) - 1e-9,
          "GROUND: the cactus rain is a volley lit all at once, its wind-up at least its circles' time: %s" % res["rain"])
    lay = res["layout"]
    check(lay["n"] >= 30 and lay["spread"] <= float(rain["timing"]["stagger"]) + 1e-9 and lay["flights"] == lay["n"] and lay["minFl"] >= float(rain["projectile"]["flight"]) - 1e-9
          and lay["gap"] >= float(rain["pattern"]["gap"]) - 1e-6 and 0.05 < lay["cover"] < 0.6,
          "GROUND: the cactus rain's layout: 30+ spots landing within the stagger, a flight each, the gap kept: %s" % lay)
    check(res["stagger"] is True, "GROUND: a staggered rain's shots all fly the one flight")
    check(not res["iss"]["errors"] and any("unknown landing" in e for e in res["badMode"]), "GROUND: the cactus rain has no error; an unknown landing is one: %s / %s" % (res["iss"], res["badMode"]))
    rows = {(f[0], f[1]) for f in res["fields"]}
    check(rows == {("landing", "mode"), ("telegraph", "all_at_once"), ("spew", "crouch"), ("spew", "squash"), ("spew", "stretch"), ("spew", "mouth"), ("spew", "burst")}
          and all(f[2] and f[3] == ["rain"] for f in res["fields"]) and "spew" in res["sections"],
          "GROUND: the Boss attacks tab edits landing.mode, telegraph.all_at_once and the spew group (rain only, explained, a Spew section): %s" % sorted(rows))
    # the burrow's keys: the form and the vocabulary agree, every one explained, every one read by the game
    form = {k[0]: k[1] for k in res["burrowKeys"]}
    voc = VOCAB.ATTACKS["burrow"]["keys"]
    new = ["sink", "rise", "predict", "warn", "mound", "throw_up", "throw_out", "throw_air", "throw_control", "creature_up", "creature_out", "creature_damage"]
    check(set(form) == set(voc) and all(k in form for k in new) and all(k[2] for k in res["burrowKeys"] if k[0] in new),
          "GROUND: the burrow's keys in the form and vocab.py agree and are explained: %s / %s" % (sorted(form), sorted(voc)))
    check(all((form[k] == voc[k]) or (form[k] in (None, 0) and voc[k] in (None, 0.0)) for k in new),
          "GROUND: the form's grey numbers are vocab's: %s" % {k: (form[k], voc[k]) for k in new if form[k] != voc[k]})
    em = _read(GAME, "core", "systems", "EnemyManager.gd")
    missing = [k for k in new if 'atk.get("%s"' % k not in em]
    check(not missing, "GROUND: EnemyManager.gd reads every burrow key: missing %s" % missing)
    af = _read(HERE, "assets_fields.js")
    check("!(str(a.name) === 'burrow' && Number(a.predict) > 0)" in af, "GROUND: a burrow that predicts its spot is not warned for lacking the ring at the hero")
    # the map's spawn_rise rows: the four keys, explained, their grey numbers WaveTimeline.SPAWN_RISE_DEFAULTS
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    m = re.search(r"const SPAWN_RISE_DEFAULTS := (\{.*?\})", wt)
    dflt = json.loads(m.group(1)) if m else {}
    sc = {s[0]: s for s in res["scalars"]}
    check(set(sc) == {"spawn_rise." + k for k in ("seconds", "big_seconds", "targetable", "dust")} and all(s[3] and s[1] in res["groups"] for s in sc.values())
          and dflt and all(abs(float(sc["spawn_rise." + k][2]) - float(v)) < 1e-9 for k, v in dflt.items()),
          "GROUND: fields.js has the spawn_rise rows, explained, the game's defaults in grey: %s / %s" % (list(sc), dflt))
    jc = _read(GAME, "core", "data", "JsonContent.gd")
    check('t.get("spawn_rise", {})' in jc and '"spew"' in jc, "GROUND: JsonContent reads the map's spawn_rise and a boss attack's spew")
    # the content: the two burrows, the map's block
    gila = json.loads(_read(CONTENT, "bosses", "gila_grande", "gila_grande.json"))
    scorp = json.loads(_read(CONTENT, "enemies", "dune_scorpion", "dune_scorpion.json"))
    gb = [a for a in gila["boss"]["attacks"] if a.get("name") == "burrow"]
    sb = [a for a in scorp["boss"]["attacks"] if a.get("name") == "burrow"]
    check(gb and float(gb[0].get("predict", 0)) > 0 and gb[0].get("telegraph") == "none" and float(gb[0].get("sink", 0)) > 0
          and float(gb[0].get("throw_up", 0)) > float(sb[0].get("throw_up", 0)) > 0 if (gb and sb) else False,
          "GROUND: the Gila's burrow predicts unseen and throws harder than the scorpion's, both sink in sight")
    mp = json.loads(_read(CONTENT, "maps", "red_canyon", "red_canyon.json"))
    sr = mp.get("timeline_data", {}).get("spawn_rise", {})
    check(isinstance(sr, dict) and float(sr.get("seconds", dflt.get("seconds", 0))) > 0,
          "GROUND: Red Canyon grows its spawns out of the ground (its block or the defaults): %s" % sr)
