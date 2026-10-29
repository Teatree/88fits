"""Pass 113, lane BOSS: the bullet-heaven patterns (kind "pattern") in the Level Editor's Boss attacks tab. selftest.py
discovers this file (`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server`
module. Nothing here writes under game/: the routes run on a temporary copy.

Groups: the tables (BossAttackDef.gd's EMITTER_SHAPES / EMITTER_AIMS / TELL_LOOKS / SHELLS / EMITTER_DEFAULTS and
BossAttackFx.BB_RADIUS are boss_model.js's, EMITTER_DEFAULTS is boss_attacks_io.py's; the kind and the three looks are in
every KINDS / LOOKS); the tab's emitter rows (every EMITTER_DEFAULTS key a row with help, real shapes); the pattern rows in
FIELDS read by the pattern kind; the maths under Node (the emitter geometry, the trigger, and simulate's counts on the four
fixed emitter sets game/tests/pass113_BOSS_test.gd pins with the game's own BossAttackDef.simulate); the three contents
(no error, each named by its boss, the doc in words); a blank pattern from the page and from the server alike; the routes
on a temporary copy (a new pattern, a save of its emitters, a pattern without emitters refused); the Enemies tab leaves a
pattern out of the cycle line.
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
TRIO = (("tumbleweed_king", "royal_dust_devil"), ("gila_grande", "venom_monsoon"), ("brander", "hellbrand_mandala"))

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'boss_model.js'));
global.BossModel = M;
global.U = {};
const BA = require(path.join(dir, 'boss_attacks.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.tables = { KINDS: M.KINDS, LOOKS: M.LOOKS, EMITTER_SHAPES: M.EMITTER_SHAPES, EMITTER_AIMS: M.EMITTER_AIMS, TELL_LOOKS: M.TELL_LOOKS, SHELLS: M.SHELLS, EMITTER_DEFAULTS: M.EMITTER_DEFAULTS, BB_RADIUS: M.BB_RADIUS, DEFAULTS: M.DEFAULTS };
  out.efields = BA.EMITTER_FIELDS.map((f) => [f.k, !!f.help, f.shapes, f.type]);
  out.pfields = BA.FIELDS.filter((f) => f.kinds.includes('pattern')).map((f) => f.g + '.' + f.k);
  out.cases = q.cases.map((c) => { const s = M.simulate(c[0], 1 / 30); return [s.peak, s.fired, s.volleys]; });
  const E = (o) => M.emitterFull(o);
  const deg = (r) => r * 180 / Math.PI;
  const sp = M.volley(E({ shape: 'spiral', arms: 3, count: 1 }), 0, 8, 0);
  const ring = M.volley(E({ shape: 'ring', count: 10, gap: 90 }), 0, 8, 0).map((v) => ((deg(v[0]) + 540) % 360) - 180);
  const rose = M.volley(E({ shape: 'rose', count: 20, petals: 5, depth: 0.75, speed: 4 }), 0, 9, 0);
  const sw = E({ shape: 'sweep', sweep_deg: 140, sweep_hz: 0.25 });
  const pu = E({ pulse_every: 4, pulse_on: 2, pulse_at: 2 });
  const tu = E({ spin: 30, reverse_at: 0.5 });
  const tt = E({ turn_every: 3, turn_deg: 36 });
  const wall = M.volley(E({ shape: 'wall', count: 9, width: 8 }), 0, 8, 0);
  out.geo = {
    spiral: [sp.length, deg(sp[1][0] - sp[0][0])],
    ringMin: Math.min(...ring.map((a) => Math.abs(a))),
    rose: [rose[0][1], rose[2][1], rose[4][1]],
    sweep: [deg(M.emitterAngle(sw, 1, 7, 0)), deg(M.emitterAngle(sw, 3, 7, 0))],
    pulse: [M.emitterOn(pu, 1, 7), M.emitterOn(pu, 2.5, 7), M.emitterOn(pu, 4.5, 7), M.emitterOn(pu, 6.5, 7)],
    turned: [M.emitterTurned(tu, 2, 8), M.emitterTurned(tu, 4, 8), M.emitterTurned(tu, 6, 8)],
    turn: deg(M.emitterAngle(tt, 3.01, 9, 0) - M.emitterAngle(tt, 2.99, 9, 0)),
    wall: [wall.length, wall[0][2], wall[8][2]],
    pull: [M.pulling(E({ finale_pull: 1 }), 7.5, 8), M.emitterOn(E({ finale_pull: 1 }), 7.5, 8), M.pulling(E({ finale_pull: 1 }), 6.5, 8)],
    times: M.emitterVolleyTimes(E({ rate: 4 }), 2).length,
    bloom: [M.roseDepth(E({ depth: 0.8, bloom_hz: 0.5 }), 0), M.roseDepth(E({ depth: 0.8, bloom_hz: 0.5 }), 1)],
  };
  const a0 = q.trig;
  out.trig = [M.patternDue(a0, 14.9, 0.1, 0, -1e9), M.patternDue(a0, 15, 0.6, 0, -1e9), M.patternDue(a0, 20, 0.61, 0, -1e9), M.patternDue(a0, 45, 0.99, 0, -1e9), M.patternDue(a0, 104.9, 0.1, 1, 60), M.patternDue(a0, 105, 0.9, 1, 60)];
  out.trio = q.trio.map((a) => ({ issues: M.issues(a), sim: M.simulate(a, 1 / 30) }));
  out.blank = M.blank('pattern', 't_pat', 'T');
  out.blankIssues = M.issues(out.blank);
  out.bad = [M.issues({ id: 't_e', kind: 'pattern', emitters: [] }), M.issues({ id: 't_s', kind: 'pattern', emitters: [{ shape: 'blob' }] }), M.issues({ id: 't_w', kind: 'pattern', emitters: [{ shape: 'ring' }], timing: { duration: 3 }, tell: { seconds: 0.5 }, trigger: { cooldown: 5, first_after: 1 }, hit: { hit_frac: 0.5 } })];
  process.stdout.write(JSON.stringify(out));
});
"""


def _gd_array(text, name):
    m = re.search(r"const %s := \[(.*?)\]" % name, text, re.S)
    return re.findall(r'"([^"]*)"', m.group(1)) if m else None


def _gd_dict(text, name):
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
                body = re.sub(r",(\s*[}\]])", r"\1", text[j:k + 1])
                return json.loads(body)
    return None


def _gd_cases(text):
    """The MIRROR_CASES the gdUnit test pins: [[attack, [peak, fired, volleys]], ...]."""
    i = text.find("const MIRROR_CASES := [")
    if i < 0:
        return None
    j = text.index("[", i)
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "[":
            depth += 1
        elif text[k] == "]":
            depth -= 1
            if depth == 0:
                return json.loads(re.sub(r",(\s*[}\]])", r"\1", text[j:k + 1]))
    return None


def checks(check, run_node, server):
    import boss_attacks_io as BAIO
    gd = open(os.path.join(GAME, "core", "data", "BossAttackDef.gd"), encoding="utf-8").read()
    fx = open(os.path.join(GAME, "core", "systems", "BossAttackFx.gd"), encoding="utf-8").read()
    test = open(os.path.join(GAME, "tests", "pass113_BOSS_test.gd"), encoding="utf-8").read()
    gd_t = {n: _gd_array(gd, n) for n in ("KINDS", "LOOKS", "EMITTER_SHAPES", "EMITTER_AIMS", "TELL_LOOKS", "SHELLS")}
    gd_em = _gd_dict(gd, "EMITTER_DEFAULTS")
    gd_bb = _gd_dict(fx, "BB_RADIUS")
    cases = _gd_cases(test)
    check(all(gd_t.values()) and gd_em and gd_bb and cases, "BOSS113: BossAttackDef's pattern tables, BossAttackFx.BB_RADIUS and the test's MIRROR_CASES read")
    if not (all(gd_t.values()) and gd_em and gd_bb and cases):
        return
    check("pattern" in gd_t["KINDS"] and "pattern" in BAIO.KINDS and all(x in gd_t["LOOKS"] for x in ("burning_tumbleweed", "venom_blob", "brand_fireball")),
          "BOSS113: the pattern kind and the three bullet looks are in every table")
    check(BAIO.EMITTER_DEFAULTS == gd_em, "BOSS113: boss_attacks_io.EMITTER_DEFAULTS is BossAttackDef.EMITTER_DEFAULTS")
    trio = []
    for _boss, aid in TRIO:
        trio.append(json.load(open(os.path.join(CONTENT, "boss_attacks", aid, aid + ".json"), encoding="utf-8")))
    q = {"cases": cases, "trig": {"kind": "pattern"}, "trio": trio}
    res = run_node(q, RUNNER)
    if not res:
        check(False, "BOSS113: node ran boss_model.js / boss_attacks.js")
        return
    t = res["tables"]
    for n in ("KINDS", "LOOKS", "EMITTER_SHAPES", "EMITTER_AIMS", "TELL_LOOKS", "SHELLS"):
        check(t[n] == gd_t[n], "BOSS113: boss_model.%s is BossAttackDef's: %s / %s" % (n, t[n], gd_t[n]))
    check(t["EMITTER_DEFAULTS"] == gd_em, "BOSS113: boss_model.EMITTER_DEFAULTS is BossAttackDef.EMITTER_DEFAULTS")
    check({k: float(v) for k, v in t["BB_RADIUS"].items()} == {k: float(v) for k, v in gd_bb.items()}, "BOSS113: boss_model.BB_RADIUS is BossAttackFx.BB_RADIUS")
    # the emitter rows: every key one row with help, shapes real
    ek = [f[0] for f in res["efields"]]
    check(sorted(ek) == sorted(gd_em.keys()) and len(ek) == len(set(ek)), "BOSS113: the tab has one emitter row for every EMITTER_DEFAULTS key: missing %s, extra %s"
          % (sorted(set(gd_em) - set(ek)), sorted(set(ek) - set(gd_em))))
    check(all(f[1] for f in res["efields"]) and all(set(f[2]) <= set(gd_t["EMITTER_SHAPES"]) and f[2] for f in res["efields"]),
          "BOSS113: every emitter row is explained and shows for real shapes")
    want = {"projectile.look", "projectile.tint", "projectile.size", "projectile.glow", "projectile.range", "projectile.hit_radius", "projectile.trail",
            "projectile.wobble", "timing.duration", "timing.clear", "timing.cooldown", "sounds.windup", "sounds.fire", "_top.knockback"}
    for g in ("hit", "trigger", "guard", "spent", "tell", "shell"):
        want |= {g + "." + k for k in t["DEFAULTS"][g]}
    check(want <= set(res["pfields"]), "BOSS113: the pattern kind shows its rows: missing %s" % sorted(want - set(res["pfields"])))
    # the maths: the same counts as the game's BossAttackDef.simulate on the test's fixed emitters
    for k, c in enumerate(cases):
        check(res["cases"][k] == c[1], "BOSS113: simulate on mirror case %d gives the game's [peak, fired, volleys]: %s / %s" % (k, res["cases"][k], c[1]))
    g = res["geo"]
    near = lambda a, b, e=1e-6: abs(float(a) - float(b)) <= e
    check(g["spiral"][0] == 3 and near(g["spiral"][1], 120), "BOSS113: three spiral arms 120 degrees apart: %s" % g["spiral"])
    check(g["ringMin"] >= 45 - 1e-6, "BOSS113: a ring's 90 degree opening faces its aim: %s" % g["ringMin"])
    check(near(g["rose"][0], 4) and near(g["rose"][1], 1) and near(g["rose"][2], 4), "BOSS113: a rose's petal tip at full speed, its dip at speed x (1 - depth): %s" % g["rose"])
    check(near(g["sweep"][0], 70) and near(g["sweep"][1], -70), "BOSS113: a sweep swings half its width each way: %s" % g["sweep"])
    check(g["pulse"] == [False, True, False, True], "BOSS113: a pulse comes on every second sweep: %s" % g["pulse"])
    check(all(near(a, b) for a, b in zip(g["turned"], [60, 120, 60])), "BOSS113: the spin turns back halfway: %s" % g["turned"])
    check(near(g["turn"], 36), "BOSS113: the mandala's jump: %s" % g["turn"])
    check(g["wall"][0] == 9 and near(g["wall"][1], -4) and near(g["wall"][2], 4), "BOSS113: a wall spans its length across the aim: %s" % g["wall"])
    check(g["pull"] == [True, False, False], "BOSS113: the finale pulls the last second and fires nothing then: %s" % g["pull"])
    check(g["times"] == 8 and near(g["bloom"][0], 0.8) and near(g["bloom"][1], 0), "BOSS113: four volleys a second, the petals breathing: %s %s" % (g["times"], g["bloom"]))
    check(res["trig"] == [False, True, False, True, False, True], "BOSS113: the trigger: not before 15 s, under 60%% HP, by 45 s, then 45 s after the end: %s" % res["trig"])
    # the three contents: no error, a doc in words, a peak of bullets, the bosses naming them
    for (boss, aid), a, r in zip(TRIO, trio, res["trio"]):
        check(not r["issues"]["errors"], "BOSS113: %s has no error: %s" % (aid, r["issues"]))
        check(a.get("kind") == "pattern" and len(str(a.get("doc", ""))) > 80 and 40 <= r["sim"]["peak"] <= 400,
              "BOSS113: %s is a pattern with its doc and %d bullets at its peak" % (aid, r["sim"]["peak"]))
        bj = json.load(open(os.path.join(CONTENT, "bosses", boss, boss + ".json"), encoding="utf-8"))
        names = [x.get("name") for x in bj.get("boss", {}).get("attacks", []) if isinstance(x, dict)]
        check(aid in names, "BOSS113: %s's script names %s: %s" % (boss, aid, names))
    # a blank pattern: the page's and the server's alike, no error; the refusals and the warnings
    py_blank = BAIO.blank("pattern", "t_pat", "T")
    check(py_blank == res["blank"] and not res["blankIssues"]["errors"], "BOSS113: a blank pattern is the same from the page and the server, and clean: %s" % res["blankIssues"])
    b = res["bad"]
    check(any("emitter" in e for e in b[0]["errors"]) and any("shape" in e for e in b[1]["errors"]), "BOSS113: no emitters, an unknown shape: refused")
    check(not b[2]["errors"] and len(b[2]["warnings"]) >= 5, "BOSS113: a short pattern, a short tell, a quick cooldown, an early first and a one-shot are warned: %s" % b[2]["warnings"])
    # the routes on a temporary copy
    tmp = tempfile.mkdtemp(prefix="le_selftest_boss113_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        os.makedirs(os.path.join(server.CONTENT, "boss_attacks"))
        os.makedirs(os.path.join(server.CONTENT, "sounds"))
        with open(os.path.join(server.CONTENT, "sounds", "soundmap.json"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"sounds": {"en_boss_attack": {}, "en_boss_pattern_warn": {}}}))
        r = BAIO.create(server, "t_pat", "Test Pattern", "", "pattern")
        p = os.path.join(server.CONTENT, "boss_attacks", "t_pat", "t_pat.json")
        d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
        check(r["ok"] and d.get("kind") == "pattern" and isinstance(d.get("emitters"), list) and d["emitters"],
              "BOSS113: a new pattern from a blank, with its emitters: %s" % {k: r.get(k) for k in ("ok", "error")})
        obj = json.loads(open(p, encoding="utf-8").read())
        obj["emitters"].append({"shape": "rose", "count": 24, "petals": 5})
        obj["emitters"][0]["spin"] = 45.0
        s1 = BAIO.save(server, "t_pat", obj, server.mtime_of(p))
        check(s1["ok"] and json.load(open(p, encoding="utf-8"))["emitters"] == obj["emitters"], "BOSS113: a save writes the emitters: %s" % {k: s1.get(k) for k in ("ok", "changed", "error")})
        bad = dict(obj, emitters=[])
        check(not BAIO.save(server, "t_pat", bad, None)["ok"], "BOSS113: a pattern without emitters is refused")
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)
    # the Enemies tab: a pattern is left out of the cycle line, its card says so
    en = open(os.path.join(HERE, "enemies.js"), encoding="utf-8").read()
    check("isPattern" in en and "c.kind === 'pattern'" in en and "never in this cycle" in en, "BOSS113: the Enemies tab leaves a pattern out of the cycle line and says why on its card")
