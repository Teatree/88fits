"""Pass 83, lane SCALE: the boss HP by seconds of full DPS and the hero's power in the Level Editor. selftest.py discovers
this file (`checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing
here writes.

Groups: the tables (WaveTimeline.gd's BOSS_HP_MODE_DEFAULT, BOSS_SECONDS_DEFAULTS, POWER_HP_SCALING_DEFAULT,
POWER_HP_MAX_DEFAULT and HeroPower.gd's BASE_DPS, BASE_EHP, SUSTAIN_SECONDS are boss_model.js's / power_model.js's and
fields.js's greys); the maths under Node against Python copies of WaveTimeline.boss_seconds_hp, power_hp_factor and
HeroPower.ehp / power_from (the twins); fields.js's rows (the mode on top, the pegged numbers shown only in that mode, the
two power rows with help, the Hero power card after Boss HP); the page wiring (index.html loads power_model.js and
power_card.js, settings.js draws the card and honours showIf, instructions.js has the section); the map file's block.
"""
import json
import math
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
const B = require(path.join(dir, 'boss_model.js'));
const P = require(path.join(dir, 'power_model.js'));
const ctx = { console, BossModel: B };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.tables = { MODE: B.MODE_DEFAULT, SECONDS: B.SECONDS_DEFAULTS, BASE_DPS: P.BASE_DPS, BASE_EHP: P.BASE_EHP, SUSTAIN: P.SUSTAIN_SECONDS,
    SCALING: P.SCALING_DEFAULT, MAX: P.MAX_DEFAULT };
  out.secondsHp = q.secs.map(([b, d, s, r]) => B.secondsHp(b, d, s, r));
  out.modes = q.modes.map((tl) => B.modeOf(tl));
  out.secondsOf = B.secondsOf({ boss_hp_scaling: { seconds: { gila_grande: 90 } } });
  out.factor = q.factor.map(([s, m, p]) => P.hpFactor(s, m, p));
  out.ehp = q.ehp.map(([st, d]) => P.ehp(st, d));
  out.power = q.power.map(([d, e]) => P.powerFrom(d, e));
  out.rows = FIELDS.SCALARS.filter((d) => d.key.startsWith('boss_hp_scaling.') || d.key.startsWith('power_hp')).map((d) => [d.key, d.group, d.def, !!d.help, typeof d.showIf === 'function', d.type, (d.options || []).map((o) => o.v)]);
  // the pegged numbers show only in the dps mode
  const peg = FIELDS.SCALARS.filter((d) => typeof d.showIf === 'function');
  global.BossModel = B;
  out.show = [peg.map((d) => d.showIf({ boss_hp_scaling: { mode: 'dps' } })), peg.map((d) => d.showIf({})), peg.map((d) => d.showIf({ boss_hp_scaling: { mode: 'seconds' } }))];
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    with open(os.path.join(*parts), encoding="utf-8") as f:
        return f.read()


def _num(text, name):
    m = re.search(r"const %s := ([0-9.]+)" % name, text)
    return float(m.group(1)) if m else None


def _gd_dict(text, name):
    m = re.search(r"const %s := \{(.*?)\}" % name, text, re.S)
    if not m:
        return None
    return {k: float(v) for k, v in re.findall(r'"([^"]+)":\s*([0-9.]+)', m.group(1))}


# ------------------------------------------------------------------ Python copies of the GDScript

def seconds_hp(base, dps, secs, dr=0.0):
    """WaveTimeline.boss_seconds_hp."""
    if secs <= 0 or dps <= 0:
        return base
    return max(base, dps * (1.0 - min(max(dr, 0.0), 0.95)) * secs)


def power_factor(s, ceiling, p):
    """WaveTimeline.power_hp_factor."""
    if abs(s - 1.0) < 0.000001:
        return 1.0
    hi = max(ceiling, 1.0)
    return min(max(math.pow(max(p, 0.01), s - 1.0), 1.0 / hi), hi)


def ehp(st, dps, sustain):
    """HeroPower.ehp."""
    mh = st.get("max_hp", 100.0)
    hp = mh + max(st.get("shield_max", 0.0), 0.0)
    regen = max(st.get("regen", 0.0), 0.0)
    ls = min(max(st.get("lifesteal", 0.0), 0.0) * max(dps, 0.0), mh * st.get("lifesteal_cap", 0.04))
    dr = min(max(st.get("damage_reduction", 0.0), 0.0), 0.8)
    ev = min(max(st.get("evade", 0.0), 0.0), 0.9)
    return (hp + sustain * (regen + ls)) / ((1.0 - dr) * (1.0 - ev))


def checks(check, run_node, server):
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    hp = _read(GAME, "core", "systems", "HeroPower.gd")
    gd = {"MODE": (re.search(r'const BOSS_HP_MODE_DEFAULT := "(\w+)"', wt) or [None, None])[1],
          "SECONDS": _gd_dict(wt, "BOSS_SECONDS_DEFAULTS"), "BASE_DPS": _num(hp, "BASE_DPS"), "BASE_EHP": _num(hp, "BASE_EHP"),
          "SUSTAIN": _num(hp, "SUSTAIN_SECONDS"), "SCALING": _num(wt, "POWER_HP_SCALING_DEFAULT"), "MAX": _num(wt, "POWER_HP_MAX_DEFAULT")}
    check(all(v is not None for v in gd.values()), "SCALE83: the GDScript tables read: %s" % [k for k, v in gd.items() if v is None])
    secs = [[1440, 300, 25, 0], [1440, 40, 25, 0], [1440, 300, 0, 0], [1440, 0, 25, 0], [0, 300, 25, 0.2], [10560, 2920, 40, 0], [72678, 866, 60, 0.5]]
    facs = [[s, m, p] for s in (0, 0.5, 1, 1.5, 2, 2.5) for m in (1, 4, 10) for p in (0.005, 0.5, 1, 2, 4, 9, 50)]
    stats = [{}, {"max_hp": 200, "shield_max": 20, "regen": 1, "lifesteal": 0.01, "lifesteal_cap": 0.04, "damage_reduction": 0.2, "evade": 0.5},
             {"max_hp": 150, "damage_reduction": 0.95, "evade": 0.95}, {"max_hp": 120, "lifesteal": 0.5}]
    ehps = [[st, d] for st in stats for d in (0, 100, 300, 100000)]
    pows = [[20.4, 100], [81.6, 100], [40.8, 200], [8800, 565], [0, 100]]
    q = {"secs": secs, "modes": [{}, {"boss_hp_scaling": {"mode": "dps"}}, {"boss_hp_scaling": {"mode": "nonsense"}}, {"boss_hp_scaling": {"mode": "seconds"}}],
         "factor": facs, "ehp": ehps, "power": pows}
    res = run_node(q, RUNNER)
    if res is None:
        print("SCALE83: node not found; the maths checks are skipped")
        return
    t = res["tables"]
    check(t["MODE"] == gd["MODE"] and {k: float(v) for k, v in t["SECONDS"].items()} == gd["SECONDS"],
          "SCALE83: boss_model.js's MODE_DEFAULT / SECONDS_DEFAULTS are WaveTimeline's: %s / %s" % (t, gd))
    check(all(abs(float(t[k]) - gd[k]) < 1e-9 for k in ("BASE_DPS", "BASE_EHP", "SUSTAIN", "SCALING", "MAX")),
          "SCALE83: power_model.js's constants are HeroPower.gd's and WaveTimeline's: %s / %s" % (t, gd))
    bad = [(a, r) for a, r in zip(secs, res["secondsHp"]) if abs(seconds_hp(*a) - r) > 1e-6]
    check(not bad, "SCALE83: boss_model.secondsHp == WaveTimeline.boss_seconds_hp: %s" % bad)
    check(res["secondsHp"][:5] == [7500, 1440, 1440, 1440, 6000], "SCALE83: the hand-worked seconds pass83_scale_test.gd pins: %s" % res["secondsHp"][:5])
    check(res["modes"] == ["seconds", "dps", "seconds", "seconds"], "SCALE83: the mode as the game reads it (none or nonsense = seconds): %s" % res["modes"])
    check(res["secondsOf"] == {"tumbleweed_king": 25, "gila_grande": 90, "brander": 60}, "SCALE83: a boss the block names takes its seconds, the others the game's: %s" % res["secondsOf"])
    bad = [(a, r) for a, r in zip(facs, res["factor"]) if abs(power_factor(*a) - r) > 1e-9 * max(1, abs(r))]
    check(not bad, "SCALE83: power_model.hpFactor == WaveTimeline.power_hp_factor over %d cases: %s" % (len(facs), bad[:4]))
    check(all(abs(r - 1) < 1e-12 for a, r in zip(facs, res["factor"]) if a[0] == 1), "SCALE83: scaling 1 is x1 at every power")
    bad = [(a, r) for a, r in zip(ehps, res["ehp"]) if abs(ehp(a[0], a[1], gd["SUSTAIN"]) - r) > 1e-6 * max(1, r)]
    check(not bad, "SCALE83: power_model.ehp == HeroPower.ehp: %s" % bad[:3])
    bad = [(a, r) for a, r in zip(pows, res["power"]) if abs(math.sqrt(max(a[0], 0) / gd["BASE_DPS"] * max(a[1], 0) / gd["BASE_EHP"]) - r) > 1e-9]
    check(not bad and abs(res["power"][0] - 1) < 1e-12 and abs(res["power"][1] - 2) < 1e-12, "SCALE83: power = sqrt(full DPS / 20.4 x effective HP / 100), a fresh Drifter 1: %s" % res["power"])

    # fields.js
    rows = {r[0]: r for r in res["rows"]}
    want = {"boss_hp_scaling." + k for k in ("mode", "enabled", "exponent", "window", "min", "max")} | {"power_hp_scaling", "power_hp_max"}
    check(set(rows) == want, "SCALE83: fields.js has the Boss HP rows and the two power rows: missing %s, extra %s" % (sorted(want - set(rows)), sorted(set(rows) - want)))
    check(all(r[3] for r in rows.values()), "SCALE83: every row explained")
    m = rows.get("boss_hp_scaling.mode", [None] * 7)
    check(m[1] == "Boss HP" and m[2] == gd["MODE"] and m[5] == "select" and m[6] == ["seconds", "dps"], "SCALE83: the mode row is a select with the game's default: %s" % m)
    check(all(rows[k][4] for k in ("boss_hp_scaling.exponent", "boss_hp_scaling.window", "boss_hp_scaling.min", "boss_hp_scaling.max"))
          and not rows["boss_hp_scaling.enabled"][4] and not m[4], "SCALE83: only the pegged numbers hide outside their mode")
    check(res["show"][0] == [True] * 4 and res["show"][1] == [False] * 4 and res["show"][2] == [False] * 4, "SCALE83: they show in the dps mode only: %s" % res["show"])
    check(rows["power_hp_scaling"][1] == "Hero power" and abs(rows["power_hp_scaling"][2] - gd["SCALING"]) < 1e-9 and abs(rows["power_hp_max"][2] - gd["MAX"]) < 1e-9,
          "SCALE83: the power rows in the Hero power card with the game's greys")
    g = res["groups"]
    check("Hero power" in g and g.index("Hero power") == g.index("Boss HP") + 1, "SCALE83: the Hero power card follows Boss HP: %s" % g)

    # the page wiring
    idx = _read(HERE, "index.html")
    order = [idx.find(s) for s in ('src="boss_model.js"', 'src="power_model.js"', 'src="power_card.js"', 'src="instructions.js"')]
    check(all(i >= 0 for i in order) and order == sorted(order), "SCALE83: index.html loads power_model.js and power_card.js before the Instructions")
    st = _read(HERE, "settings.js")
    check("PowerCard.block(tl)" in st and "def.showIf" in st, "SCALE83: settings.js draws the Hero power card and honours showIf")
    check("PowerCard.instructions(root)" in _read(HERE, "instructions.js"), "SCALE83: the Instructions tab has the boss HP / power section")
    bs = _read(HERE, "boss_scaling.js")
    check("howBox(" in bs and "secondsChart(" in bs and "bigger reference makes the boss" in bs, "SCALE83: the Boss HP card has the How it works box, the seconds chart and the reference warning")
    for k in ("sim_model.js",):
        check("id: 'power'" in _read(HERE, k), "SCALE83: %s charts the hero's power" % k)
    check("S.power.push(" in _read(HERE, "sim_avg.js") and 'out["power"] = power' in _read(GAME, "tools", "sim_run.gd"), "SCALE83: sim_avg.js and sim_run.gd carry the power series")

    # the map file
    mp = json.loads(_read(GAME, "content", "maps", "red_canyon", "red_canyon.json"))
    tl = mp.get("timeline_data", {})
    bhs = tl.get("boss_hp_scaling", {}) if isinstance(tl.get("boss_hp_scaling"), dict) else {}
    mode = bhs.get("mode", gd["MODE"])
    secs_m = dict(gd["SECONDS"])
    secs_m.update(bhs.get("seconds", {}) if isinstance(bhs.get("seconds"), dict) else {})
    bosses = [e.get("enemy") for e in tl.get("events", []) if isinstance(e, dict) and e.get("type") == "boss"]
    check(mode in ("seconds", "dps"), "SCALE83: Red Canyon's boss mode is one the game knows: %s" % mode)
    if mode == "seconds":
        check(all(secs_m.get(b, 0) > 0 for b in bosses), "SCALE83: Red Canyon gives every boss it brings its seconds: %s" % secs_m)
    print("SCALE83: Red Canyon: boss mode %s, seconds %s, power_hp_scaling %s" % (mode, {b: secs_m.get(b) for b in bosses}, tl.get("power_hp_scaling", "1 (default)")))
