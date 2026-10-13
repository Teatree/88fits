"""Pass 72, lane BOSS: the boss HP scaling and the custom boss attacks in the Level Editor. selftest.py discovers this file
(`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here
writes under game/: the routes run on a temporary copy.

Groups: the tables (boss_model.js, boss_attacks_io.py and BossAttackDef.gd's KINDS / SHAPES / LOOKS / ORDERS / AIMS /
CENTERS / TELEGRAPHS / SCRIPTS / DEFAULTS agree, the built-in names are vocab.py's ATTACKS, WaveTimeline's
BOSS_HP_SCALING_DEFAULTS are boss_model's and fields.js's Boss HP rows'); the maths under Node (boss_hp_mult's values,
the relative fight, the boss events and their stages, the gap rule in every shape, the three fixed layouts the game's
pass72_boss_test pins, the landing times, blank attacks, the issues); the Boss attacks tab's field table (every
BossAttackDef key has a row with help); the routes on a temporary copy (list, new from a blank and from a copy, the
refusals, save key by key with its 409, assign / unassign writing only the boss block, delete refused while used and
with cascade); the map's Save keeps boss_hp_scaling.
"""
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
const M = require(path.join(dir, 'boss_model.js'));
global.BossModel = M;
global.U = {};
const BA = require(path.join(dir, 'boss_attacks.js'));
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
  out.tables = { KINDS: M.KINDS, SHAPES: M.SHAPES, LOOKS: M.LOOKS, ORDERS: M.ORDERS, AIMS: M.AIMS, CENTERS: M.CENTERS, TELEGRAPHS: M.TELEGRAPHS, SCRIPTS: M.SCRIPTS, DEFAULTS: M.DEFAULTS, SCALING_DEFAULTS: M.SCALING_DEFAULTS, REF_DEFAULTS: M.REF_DEFAULTS, TOP: M.TOP_DEFAULTS };
  // pass 72, lane INTEG: no block plays the defaults (on, the measured references); a ref of 0 = never scaled
  out.dflt = [M.scalingOf({}).enabled, M.scalingOf({}).ref, M.scalingOf({ boss_hp_scaling: { ref_dps: { gila_grande: 900, brander: 0 } } }).ref];
  const cfg = M.scalingOf({ boss_hp_scaling: { enabled: true } });
  out.mult = q.mult.map(([d, r]) => M.hpMult(cfg, d, r));
  out.off = [M.hpMult(M.scalingOf({}), 900, 400), M.hpMult(M.scalingOf({ boss_hp_scaling: { enabled: false } }), 900, 400), M.hpMult(cfg, 900, 0)];
  out.fight = [M.fightRel(cfg, 800, 400), M.fightRel(cfg, 400, 400), M.fightRel(cfg, 100, 400)];
  out.corners = [M.dpsForMult(cfg, 400, 0.75), M.dpsForMult(cfg, 400, 3)];
  out.series = M.chartSeries(cfg, 400, 3, 4, 7).map((p) => [Math.round(p.dps), +p.mult.toFixed(4)]);
  out.events = M.bossEvents(q.tl);
  out.base = M.bossBaseHp({ hp: 2400, boss: { hp_mult_per_stage: 2 } }, q.tl, 1);
  // the gap rule in every shape, over seeds
  out.gaps = [];
  for (const shape of M.SHAPES) for (const seed of [1, 7, 42, 99]) {
    const pts = M.points({ shape, radius_min: 3, radius_max: 16, spacing: 3.2, jitter: 0.6, gap: 1.0, turn: true, order: 'random' }, 0.9, M.rng(seed));
    out.gaps.push([shape, seed, pts.length, M.smallestGap(pts, 0.9), Math.max(...pts.map((p) => Math.hypot(p[0], p[1])))]);
  }
  out.fixed = {};
  for (const shape of ['rings', 'grid', 'spiral']) out.fixed[shape] = M.points({ shape, radius_min: 3.6, radius_max: 16, spacing: 3.2, jitter: 0, gap: 1.0, turn: false, order: 'out' }, 0.9, M.rng(1)).length;
  out.count = M.points({ shape: 'grid', radius_max: 14, count: 9 }, 0.9, M.rng(3)).length;
  out.times = M.landTimes(5, 1.5, 1.1);
  out.blank = M.KINDS.map((k) => M.blank(k, 't_' + k, 'T'));
  out.issues = q.docs.map((d) => M.issues(d));
  out.layout = (() => { const l = M.rainLayout(q.rain, 3); return [l.pts.length, l.gap, l.cover, l.lasts]; })();
  // the tab's field table
  out.fields = BA.FIELDS.map((f) => [f.g, f.k, f.kinds, !!f.help, f.type]);
  out.sections = BA.SECTIONS.map((s) => s[0]);
  out.scalars = FIELDS.SCALARS.filter((d) => d.key.startsWith('boss_hp_scaling.')).map((d) => [d.key, d.group, d.def, !!d.help]);
  out.groups = FIELDS.SCALAR_GROUPS;
  process.stdout.write(JSON.stringify(out));
});
"""


def _gd_const_array(text, name):
    m = re.search(r"const %s := \[(.*?)\]" % name, text, re.S)
    return re.findall(r'"([^"]*)"', m.group(1)) if m else None


def _gd_const_dict(text, name):
    i = text.find("const %s := {" % name)
    if i < 0:
        return None
    j = text.index("{", i)
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                body = text[j:k + 1]
                body = re.sub(r",(\s*[}\]])", r"\1", body)
                return json.loads(body)
    return None


def _close(a, b, eps=1e-6):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


def checks(check, run_node, server):
    import boss_attacks_io as BAIO
    import vocab as VOCAB
    gd = open(os.path.join(GAME, "core", "data", "BossAttackDef.gd"), encoding="utf-8").read()
    wt = open(os.path.join(GAME, "core", "data", "WaveTimeline.gd"), encoding="utf-8").read()
    gd_tables = {n: _gd_const_array(gd, n) for n in ("KINDS", "SHAPES", "LOOKS", "ORDERS", "AIMS", "CENTERS", "TELEGRAPHS", "SCRIPTS")}
    gd_defaults = _gd_const_dict(gd, "DEFAULTS")
    gd_scaling = _gd_const_dict(wt, "BOSS_HP_SCALING_DEFAULTS")
    gd_refs = _gd_const_dict(wt, "BOSS_REF_DPS_DEFAULTS")
    check(all(v for v in gd_tables.values()) and gd_defaults and gd_scaling, "BOSS: BossAttackDef.gd's tables and WaveTimeline's defaults read: %s" % [k for k, v in gd_tables.items() if not v])
    # the built-ins are the runner's names (vocab.py checks them against EnemyManager.gd)
    check(set(gd_tables["SCRIPTS"] or []) == set(VOCAB.ATTACKS) == set(BAIO.BUILTINS), "BOSS: the built-in names agree: BossAttackDef.SCRIPTS, vocab.ATTACKS, boss_attacks_io.BUILTINS")
    check(BAIO.KINDS == gd_tables["KINDS"] and BAIO.DEFAULTS == gd_defaults, "BOSS: boss_attacks_io.py's KINDS and DEFAULTS are BossAttackDef's")

    rain_json = json.load(open(os.path.join(CONTENT, "boss_attacks", "cactus_rain", "cactus_rain.json"), encoding="utf-8"))
    map_json = json.load(open(os.path.join(CONTENT, "maps", "red_canyon", "red_canyon.json"), encoding="utf-8"))
    q = {"mult": [[400, 400], [800, 400], [100, 400], [0, 400], [40000, 400], [1600, 400]],
         "tl": {"stage_length": 430, "stage_mults": [1, 2.2, 3.34], "events": [{"t": 860, "type": "boss", "enemy": "gila_grande"}, {"t": 430, "type": "boss", "enemy": "tumbleweed_king"}, {"t": 215, "type": "elite_boss", "enemy": ["x"]}, {"t": 1290, "type": "boss", "enemy": "brander"}]},
         "docs": [rain_json, {"id": "slam", "kind": "rain"}, {"id": "Bad Id", "kind": "rain"}, {"id": "t_x", "kind": "laser"}, {"id": "t_s", "kind": "script", "script": "nope"},
                  {"id": "t_r", "kind": "rain", "pattern": {"radius_min": 10, "radius_max": 5}}, {"id": "t_c", "kind": "volley", "projectile": {"tint": "red"}},
                  {"id": "t_g", "name": "G", "kind": "rain", "pattern": {"gap": 0.3}, "telegraph": {"seconds": 0.2}}],
         "rain": rain_json}
    res = run_node(q, RUNNER)
    if not res:
        check(False, "BOSS: node ran boss_model.js / boss_attacks.js")
        return
    t = res["tables"]
    for n, v in gd_tables.items():
        check(t[n] == v, "BOSS: boss_model.%s is BossAttackDef's: %s / %s" % (n, t[n], v))
    check(t["DEFAULTS"] == gd_defaults, "BOSS: boss_model.DEFAULTS is BossAttackDef.DEFAULTS")
    check({k: t["SCALING_DEFAULTS"][k] for k in gd_scaling} == gd_scaling, "BOSS: boss_model.SCALING_DEFAULTS is WaveTimeline.BOSS_HP_SCALING_DEFAULTS: %s / %s" % (t["SCALING_DEFAULTS"], gd_scaling))
    # the maths (the same numbers as pass72_boss_test)
    m = res["mult"]
    check(_close(m[0], 1) and _close(m[1], 2 ** 0.5) and _close(m[2], 0.75) and _close(m[3], 0.75) and _close(m[4], 3) and _close(m[5], 2),
          "BOSS: hpMult is (dps/ref)^0.5 inside 0.75..3: %s" % m)
    # pass 72, lane INTEG: no block plays the game's defaults (on: 900 against 400 is x1.5); off, or no reference: x1
    check(_close(res["off"][0], 1.5) and res["off"][1:] == [1, 1], "BOSS: no block = the defaults (on); off, or no reference: x1: %s" % res["off"])
    d = res["dflt"]
    check(gd_refs and d[0] is True and {k: float(v) for k, v in d[1].items()} == {k: float(v) for k, v in gd_refs.items()}
          and d[2]["gila_grande"] == 900 and d[2]["brander"] == 0 and _close(d[2]["tumbleweed_king"], gd_refs["tumbleweed_king"]),
          "BOSS: boss_model.REF_DEFAULTS is WaveTimeline.BOSS_REF_DPS_DEFAULTS, a boss the block leaves out takes it, 0 stays 0: %s / %s" % (d, gd_refs))
    check(_close(res["fight"][0], 0.5 ** 0.5) and _close(res["fight"][1], 1) and _close(res["fight"][2], 3.0),
          "BOSS: twice the DPS is a fight 71%% as long; a quarter on the floor is 3x as long: %s" % res["fight"])
    check(_close(res["corners"][0], 400 * 0.5625) and _close(res["corners"][1], 3600), "BOSS: the floor holds below 0.5625x the reference, the ceiling from 9x: %s" % res["corners"])
    check([s[0] for s in res["series"]] == [50, 100, 200, 400, 800, 1600, 3200, 6400], "BOSS: the chart doubles the DPS a step from ref/8 to ref*16: %s" % res["series"])
    ev = res["events"]
    check([e["id"] for e in ev] == ["tumbleweed_king", "gila_grande", "brander"] and [e["stage"] for e in ev] == [0, 1, 2],
          "BOSS: the boss events in time order with the stage each closes (WaveDirector.boss_stage_of): %s" % ev)
    check(_close(res["base"], 2400 * 2 * 2.2), "BOSS: a boss's HP before the scaling: hp x 2^stage x the stage mult: %s" % res["base"])
    bad = [g for g in res["gaps"] if g[3] < 1.0 - 1e-3 or g[2] < 20 or g[4] > 16 + 1.01]
    check(not bad, "BOSS: the gap rule holds in every shape and seed (at least 1 m, 20+ spots inside the radius): %s" % (bad or [g[:3] for g in res["gaps"]]))
    check(res["fixed"] == {"rings": 89, "grid": 84, "spiral": 82}, "BOSS: the fixed layouts are the game's (pass72_boss_test pins 89 / 84 / 82): %s" % res["fixed"])
    check(res["count"] == 9, "BOSS: count keeps that many")
    check([round(x, 6) for x in res["times"]] == [1.1, 1.475, 1.85, 2.225, 2.6], "BOSS: the landing times: the flight, then the stagger shared: %s" % res["times"])
    kinds = [b["kind"] for b in res["blank"]]
    check(kinds == t["KINDS"] and res["blank"][4].get("script") in t["SCRIPTS"] and "landing" in res["blank"][0] and "landing" not in res["blank"][1],
          "BOSS: a blank of every kind (a script one names a built-in, only a rain has a landing)")
    py_blanks = [BAIO.blank(k, "t_" + k, "T") for k in BAIO.KINDS]
    check(py_blanks == res["blank"], "BOSS: the server's blank attacks are the page's")
    iss = res["issues"]
    check(not iss[0]["errors"], "BOSS: cactus_rain has no error: %s" % iss[0])
    check(any("built-in" in e for e in iss[1]["errors"]) and iss[2]["errors"] and any("unknown kind" in e for e in iss[3]["errors"])
          and iss[4]["errors"] and any("outer radius" in e for e in iss[5]["errors"]) and any("colour" in e for e in iss[6]["errors"]),
          "BOSS: the refusals: a built-in's name, a bad id, an unknown kind, a script without a built-in, radii the wrong way round, a colour")
    check(len(iss[7]["warnings"]) >= 2 and not iss[7]["errors"], "BOSS: a gap narrower than the hero and a short warning are warned: %s" % iss[7])
    lay = res["layout"]
    check(lay[0] >= 30 and lay[1] >= float(rain_json.get("pattern", {}).get("gap", 1.0)) - 1e-6 and 0.05 < lay[2] < 0.6,
          "BOSS: cactus_rain lays out 30+ spots with the gap kept, covering a share of the ring: %s" % lay)
    # the tab's field table: every BossAttackDef key has a row with help, and every row a known key
    rows = {(f[0], f[1]) for f in res["fields"]}
    want = {(g, k) for g, keys in gd_defaults.items() for k in keys} | {("_top", "damage"), ("_top", "knockback"), ("_top", "lift")}
    check(rows == want, "BOSS: the Boss attacks tab edits every key BossAttackDef reads: missing %s, unknown %s" % (sorted(want - rows), sorted(rows - want)))
    check(all(f[3] for f in res["fields"]) and all(set(f[2]) <= set(t["KINDS"]) for f in res["fields"]), "BOSS: every row is explained and names real kinds")
    check(set(res["sections"]) == {f[0] for f in res["fields"]}, "BOSS: every group has its section")
    sc = {s[0]: s for s in res["scalars"]}
    check(set(sc) == {"boss_hp_scaling." + k for k in ("enabled", "exponent", "window", "min", "max")} and all(s[1] == "Boss HP" and s[3] for s in sc.values())
          and "Boss HP" in res["groups"], "BOSS: fields.js has the Boss HP card's five rows, explained: %s" % list(sc))
    check(all(_close(sc["boss_hp_scaling." + k][2], gd_scaling[k]) for k in ("exponent", "window", "min", "max")) and sc["boss_hp_scaling.enabled"][2] == gd_scaling["enabled"],
          "BOSS: the rows' grey defaults are the game's")
    # the content: Red Canyon's block (Garry tunes it: shapes only; lane INTEG: a key it leaves out plays the default)
    bhs = map_json.get("timeline_data", {}).get("boss_hp_scaling", {})
    refs = dict(gd_refs or {})
    refs.update((bhs.get("ref_dps") or {}) if isinstance(bhs, dict) else {})
    check(isinstance(bhs, dict) and bhs.get("enabled", gd_scaling["enabled"]) is True and all(refs.get(e["id"], 0) > 0 for e in ev),
          "BOSS: Red Canyon pegs every boss its timeline brings: %s" % bhs)

    # ---------------------------------------------------------------- the routes on a temporary copy
    tmp = tempfile.mkdtemp(prefix="le_selftest_boss_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        os.makedirs(os.path.join(server.CONTENT, "boss_attacks", "cactus_rain"))
        shutil.copy(os.path.join(CONTENT, "boss_attacks", "cactus_rain", "cactus_rain.json"), os.path.join(server.CONTENT, "boss_attacks", "cactus_rain"))
        os.makedirs(os.path.join(server.CONTENT, "bosses", "gila_grande"))
        gila_src = os.path.join(CONTENT, "bosses", "gila_grande", "gila_grande.json")
        gila = os.path.join(server.CONTENT, "bosses", "gila_grande", "gila_grande.json")
        shutil.copy(gila_src, gila)
        os.makedirs(os.path.join(server.CONTENT, "enemies", "plain"))
        with open(os.path.join(server.CONTENT, "enemies", "plain", "plain.json"), "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps({"id": "plain", "name": "Plain", "hp": 5}, indent=2) + "\n")
        os.makedirs(os.path.join(server.CONTENT, "sounds"))
        with open(os.path.join(server.CONTENT, "sounds", "soundmap.json"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"sounds": {"en_boss_attack": {}, "en_cactus_spit": {}}}))
        lst = BAIO.list_all(server)
        rec = {a["id"]: a for a in lst["attacks"]}
        check(lst["ok"] and rec.get("cactus_rain", {}).get("used_by") == ["gila_grande"] and [c["id"] for c in lst["creatures"]] == ["gila_grande"]
              and lst["sounds"] == ["en_boss_attack", "en_cactus_spit"] and lst["builtins"] == BAIO.BUILTINS,
              "BOSS: list: cactus_rain in the Gila's script, only scripted creatures, the sounds: %s" % [(a["id"], a["used_by"]) for a in lst["attacks"]])
        r = BAIO.create(server, "t_volley", "Test Volley", "", "volley")
        p = os.path.join(server.CONTENT, "boss_attacks", "t_volley", "t_volley.json")
        check(r["ok"] and os.path.isfile(p) and json.load(open(p, encoding="utf-8"))["kind"] == "volley" and r["import_ok"] is False,
              "BOSS: new from a blank volley (the import reported as not run): %s" % {k: r.get(k) for k in ("ok", "error", "import_ok")})
        r2 = BAIO.create(server, "t_rain2", "", "cactus_rain")
        d2 = json.load(open(os.path.join(server.CONTENT, "boss_attacks", "t_rain2", "t_rain2.json"), encoding="utf-8"))
        check(r2["ok"] and d2["id"] == "t_rain2" and d2["name"].endswith("(copy)") and d2["pattern"] == rain_json["pattern"], "BOSS: new as a copy keeps the numbers")
        for bad_id, why in (("slam", "built-in"), ("t_volley", "taken"), ("gila_grande", "a creature's id"), ("Bad", "bad id"), ("9x", "starts with a digit")):
            check(not BAIO.create(server, bad_id, "", "", "rain")["ok"], "BOSS: new refuses %s (%s)" % (bad_id, why))
        # save: one key changed in place, the other lines kept; a stale base is a 409
        before = open(p, encoding="utf-8").read()
        obj = json.loads(before)
        mt = server.mtime_of(p)
        obj["projectile"]["tint"] = "#00AA33"
        obj["note"] = "a hand note"
        s1 = BAIO.save(server, "t_volley", obj, mt)
        after = open(p, encoding="utf-8").read()
        check(s1["ok"] and set(s1["changed"]) == {"projectile", "note"} and json.loads(after) == obj and after.split("\n")[:4] == before.split("\n")[:4],
              "BOSS: save writes the changed keys in place: %s" % {k: s1.get(k) for k in ("ok", "changed", "error")})
        check(BAIO.save(server, "t_volley", obj, mt - 100).get("status") == 409, "BOSS: a stale base_mtime is a 409")
        check(BAIO.save(server, "t_volley", dict(obj, id="other"), None)["ok"] is False and BAIO.save(server, "t_volley", dict(obj, kind="laser"), None)["ok"] is False,
              "BOSS: save refuses another id and an unknown kind")
        check(BAIO.save(server, "t_none", obj, None).get("status") in (400, 404), "BOSS: save refuses an attack that is not there")
        # assign / unassign: only the boss block changes
        g0 = open(gila, encoding="utf-8").read()
        a1 = BAIO.assign(server, "t_volley", "gila_grande", True)
        g1 = open(gila, encoding="utf-8").read()
        d_g1 = json.loads(g1)
        check(a1["ok"] and a1["attacks"][-1] == "t_volley" and d_g1["boss"]["attacks"][-1] == {"name": "t_volley"}
              and {k: v for k, v in d_g1.items() if k != "boss"} == {k: v for k, v in json.loads(g0).items() if k != "boss"},
              "BOSS: assign appends {name: id} to the script, nothing else changes: %s" % a1.get("attacks"))
        check(BAIO.assign(server, "t_volley", "gila_grande", True).get("unchanged"), "BOSS: assigning twice adds it once")
        a2 = BAIO.assign(server, "t_volley", "gila_grande", False)
        check(a2["ok"] and json.loads(open(gila, encoding="utf-8").read()) == json.loads(g0), "BOSS: unassign takes it out again")
        check(BAIO.assign(server, "t_volley", "plain", True)["ok"], "BOSS: a creature without a script gets one")
        check(json.load(open(os.path.join(server.CONTENT, "enemies", "plain", "plain.json"), encoding="utf-8"))["boss"] == {"attacks": [{"name": "t_volley"}]},
              "BOSS: ... a boss block with the attack")
        check(not BAIO.assign(server, "t_none", "gila_grande", True)["ok"] and not BAIO.assign(server, "t_volley", "nobody", True)["ok"],
              "BOSS: assign refuses an unknown attack or creature")
        # delete: refused while used, cascade takes it out of the scripts, the folder is moved aside
        dr = BAIO.delete(server, "cactus_rain", False)
        check(not dr["ok"] and dr.get("used_by") == ["gila_grande"] and os.path.isdir(os.path.join(server.CONTENT, "boss_attacks", "cactus_rain")),
              "BOSS: delete is refused while a script names it")
        dc = BAIO.delete(server, "cactus_rain", True)
        names = [a.get("name") for a in json.loads(open(gila, encoding="utf-8").read())["boss"]["attacks"]]
        check(dc["ok"] and "cactus_rain" not in names and len(names) == 3 and not os.path.exists(os.path.join(server.CONTENT, "boss_attacks", "cactus_rain"))
              and os.path.isdir(os.path.join(server.BACKUPS, "boss_attacks")) and os.listdir(os.path.join(server.BACKUPS, "boss_attacks")),
              "BOSS: delete with cascade leaves the scripts and moves the folder to the backups: %s" % names)
        # the server's own routes are wired
        src = open(os.path.join(HERE, "server.py"), encoding="utf-8").read()
        check("BAIO.api_get(self, sys.modules[__name__]" in src and "BAIO.api_post(self, sys.modules[__name__]" in src and '"boss_attacks"]' in src,
              "BOSS: server.py routes /api/boss_attacks to boss_attacks_io.py and counts the type's ids as taken")
        html = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
        check(all(x in html for x in ('data-tab="bossattacks"', 'id="tab-bossattacks"', 'boss_model.js', 'boss_scaling.js', 'boss_attacks.js', 'boss.css')),
              "BOSS: index.html has the tab, its panel, the scripts and the stylesheet")
        check(html.index('boss_attacks.js') < html.index('instructions.js'), "BOSS: the page modules load before the Instructions")
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)
