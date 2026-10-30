"""Pass 115, lane BOSS: a bullet heaven's barrier in the Level Editor's Boss attacks tab. selftest.py discovers this file
(`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here
writes under game/: the routes run on a temporary copy.

Groups: the tables (BossAttackDef.gd's BARRIER_LOOKS / MODES / HOLDS / CREATURES / BULLETS and BARRIER_HERO_R / KEEP /
MIN_R are boss_model.js's, the choices boss_attacks_io.py's; every DEFAULTS.barrier key one row of the tab with its help,
for the pattern kind; the looks' and the choices' rows offer exactly the game's choices); the maths under Node (the same
radius, hero limit, reach and bullets' reach as the game's own on the cases game/tests/pass115_BOSS_test.gd pins in
MIRROR); the three contents (each boss's own look, no error, the reach inside the range, the bullets stopped at the wall,
fewer bullets in the air than pass 114's); the speeds 50% up from pass 114's; the preview draws the wall and the reach
circle; the server refuses an unknown choice and saves a barrier on a temporary copy.
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
TRIO = (("tumbleweed_king", "royal_dust_devil", "tumbleweed_fence"), ("gila_grande", "venom_monsoon", "cactus_fence"),
        ("brander", "hellbrand_mandala", "iron_fence"))
# pass 114's peaks (no barrier, the old speeds; BALANCING 57.EDITOR): faster bullets stopped at the wall make fewer
PEAK_114 = {"royal_dust_devil": 452, "venom_monsoon": 205, "hellbrand_mandala": 401}

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
  out.tables = { BARRIER_LOOKS: M.BARRIER_LOOKS, BARRIER_MODES: M.BARRIER_MODES, BARRIER_HOLDS: M.BARRIER_HOLDS, BARRIER_CREATURES: M.BARRIER_CREATURES,
    BARRIER_BULLETS: M.BARRIER_BULLETS, BARRIER_HERO_R: M.BARRIER_HERO_R, BARRIER_KEEP: M.BARRIER_KEEP, BARRIER_MIN_R: M.BARRIER_MIN_R, barrier: M.DEFAULTS.barrier };
  out.fields = BA.FIELDS.filter((f) => f.g === 'barrier').map((f) => ({ k: f.k, help: !!f.help && f.help.length > 30, pat: f.kinds.includes('pattern'), type: f.type, opts: f.opts ? f.opts.map((o) => o.v) : null }));
  out.sections = BA.SECTIONS.map((s) => s[0]);
  const num = (x) => (x === Infinity ? 'INF' : x);
  out.mirror = q.mirror.map((c) => { const a = Object.assign({ id: 'm', kind: 'pattern', emitters: [{ shape: 'ring' }] }, c[0]); return [M.barrierRadius(a), M.barrierHeroLimit(a), num(M.barrierReach(a)), M.bulletReach(a)]; });
  out.trio = q.trio.map((a) => ({ on: M.barrierOn(a), look: M.val(a, 'barrier', 'look'), r: M.barrierRadius(a), reach: M.barrierReach(a), br: M.bulletReach(a), issues: M.issues(a), sim: M.simulate(a, 1 / 30) }));
  out.bad = M.issues({ id: 'b', kind: 'pattern', emitters: [{ shape: 'ring' }], barrier: { look: 'moat', hold: 'forever', creatures: 'eat', bullets: 'bounce', radius_mode: 'far', color: 'red' } });
  out.warn = M.issues({ id: 'w', kind: 'pattern', emitters: [{ shape: 'ring' }], projectile: { range: 10 }, tell: { seconds: 1.0 }, barrier: { look: 'iron_fence', radius_mode: 'fixed', radius: 16, hero_block: false } });
  out.cramped = M.issues({ id: 'c', kind: 'pattern', emitters: [{ shape: 'ring' }], projectile: { range: 5 }, barrier: { look: 'cactus_fence' } });
  out.off = { on: M.barrierOn({ kind: 'pattern' }), reach: num(M.barrierReach({ kind: 'pattern' })), rainOn: M.barrierOn({ kind: 'rain', barrier: { look: 'iron_fence' } }) };
  process.stdout.write(JSON.stringify(out));
});
"""


def _gd_array(text, name):
    m = re.search(r"const %s := \[(.*?)\]" % name, text, re.S)
    return re.findall(r'"([^"]*)"', m.group(1)) if m else None


def _gd_float(text, name):
    m = re.search(r"const %s := ([0-9.]+)" % name, text)
    return float(m.group(1)) if m else None


def _gd_mirror(text):
    """The MIRROR cases the gdUnit test pins: [[attack, [radius, hero limit, reach, bullets' reach]], ...] (INF kept)."""
    i = text.find("const MIRROR := [")
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
                body = re.sub(r",(\s*[}\]])", r"\1", text[j:k + 1]).replace("INF", '"INF"')
                return json.loads(body)
    return None


def _near(a, b, e=1e-6):
    if a == "INF" or b == "INF":
        return a == b
    return abs(float(a) - float(b)) <= e


def checks(check, run_node, server):
    import boss_attacks_io as BAIO
    gd = open(os.path.join(GAME, "core", "data", "BossAttackDef.gd"), encoding="utf-8").read()
    test = open(os.path.join(GAME, "tests", "pass115_BOSS_test.gd"), encoding="utf-8").read()
    names = ("BARRIER_LOOKS", "BARRIER_MODES", "BARRIER_HOLDS", "BARRIER_CREATURES", "BARRIER_BULLETS")
    gd_t = {n: _gd_array(gd, n) for n in names}
    gd_c = {n: _gd_float(gd, n) for n in ("BARRIER_HERO_R", "BARRIER_KEEP", "BARRIER_MIN_R")}
    mirror = _gd_mirror(test)
    check(all(gd_t.values()) and all(v is not None for v in gd_c.values()) and mirror, "BOSS115: BossAttackDef's barrier tables and the test's MIRROR read")
    if not (all(gd_t.values()) and mirror):
        return
    trio = [json.load(open(os.path.join(CONTENT, "boss_attacks", aid, aid + ".json"), encoding="utf-8")) for _b, aid, _l in TRIO]
    res = run_node({"mirror": mirror, "trio": trio}, RUNNER)
    if not res:
        check(False, "BOSS115: node ran boss_model.js / boss_attacks.js")
        return
    t = res["tables"]
    for n in names:
        check(t[n] == gd_t[n], "BOSS115: boss_model.%s is BossAttackDef's: %s / %s" % (n, t[n], gd_t[n]))
    for n, v in gd_c.items():
        check(_near(t[n], v), "BOSS115: boss_model.%s is BossAttackDef's: %s / %s" % (n, t[n], v))
    py = {"look": "BARRIER_LOOKS", "radius_mode": "BARRIER_MODES", "hold": "BARRIER_HOLDS", "creatures": "BARRIER_CREATURES", "bullets": "BARRIER_BULLETS"}
    check(all(BAIO.BARRIER_CHOICES[k] == gd_t[n] for k, n in py.items()), "BOSS115: boss_attacks_io.BARRIER_CHOICES are BossAttackDef's")
    # the rows: every DEFAULTS.barrier key one row with its help, for the pattern kind; the select rows offer the choices
    keys = [f["k"] for f in res["fields"]]
    check(sorted(keys) == sorted(t["barrier"].keys()) and len(keys) == len(set(keys)),
          "BOSS115: one barrier row for every DEFAULTS.barrier key: missing %s, extra %s" % (sorted(set(t["barrier"]) - set(keys)), sorted(set(keys) - set(t["barrier"]))))
    check(all(f["help"] and f["pat"] for f in res["fields"]), "BOSS115: every barrier row is explained and shows for a pattern")
    for f in res["fields"]:
        if f["k"] in py:
            check(f["type"] == "select" and f["opts"] == gd_t[py[f["k"]]], "BOSS115: the %s row offers the game's choices: %s" % (f["k"], f["opts"]))
    check("barrier" in res["sections"], "BOSS115: the tab has its Barrier section")
    # the maths: the game's numbers on the test's cases
    for k, c in enumerate(mirror):
        got = res["mirror"][k]
        check(all(_near(a, b, 1e-4) for a, b in zip(got, c[1])), "BOSS115: mirror case %d: radius, hero limit, reach, bullets' reach %s / %s" % (k, got, c[1]))
    # the three contents
    for (boss, aid, look), a, r in zip(TRIO, trio, res["trio"]):
        rng = float(a["projectile"]["range"])
        check(r["on"] and r["look"] == look, "BOSS115: %s raises the %s" % (aid, look))
        check(not r["issues"]["errors"] and not r["issues"]["warnings"], "BOSS115: %s has no error and no warning: %s" % (aid, r["issues"]))
        # the lead (pass 115, 58.LEAD): the wall a fixed 14 m round the boss, well inside the range, where the phone shows it
        check(r["reach"] < r["br"] < rng and _near(r["r"], 14.0), "BOSS115: %s's wall at 14 m inside its %.0f m range, the bullets stopped at it (%.2f), the reach inside (%.2f)" % (aid, rng, r["br"], r["reach"]))
        check(30 <= r["sim"]["peak"] < PEAK_114[aid], "BOSS115: %s has fewer bullets in the air than pass 114's %d: %d" % (aid, PEAK_114[aid], r["sim"]["peak"]))
        bj = json.load(open(os.path.join(CONTENT, "bosses", boss, boss + ".json"), encoding="utf-8"))
        check(aid in [x.get("name") for x in bj.get("boss", {}).get("attacks", []) if isinstance(x, dict)], "BOSS115: %s still names %s" % (boss, aid))
    # the refusals and the warnings
    b = res["bad"]["errors"]
    check(sum(1 for e in b if "barrier" in e) >= 5 and any("#rrggbb" in e for e in b), "BOSS115: unknown barrier choices and a bad colour are refused: %s" % b)
    w = res["warn"]["warnings"]
    check(any("past the bullets" in x for x in w) and any("still rising" in x for x in w) and any("does not hold the hero" in x for x in w),
          "BOSS115: a wall past the range, one still rising at the bullets, one that does not hold the hero are warned: %s" % w)
    check(any("very little room" in x for x in res["cramped"]["warnings"]), "BOSS115: a cramped barrier is warned: %s" % res["cramped"]["warnings"])
    check(not res["off"]["on"] and res["off"]["reach"] == "INF" and not res["off"]["rainOn"], "BOSS115: no look, no barrier and no reach rule; only a pattern has one: %s" % res["off"])
    # the preview draws the wall and the reach circle
    ba = open(os.path.join(HERE, "boss_attacks.js"), encoding="utf-8").read()
    check("M.barrierOn(d)" in ba and "M.barrierReach(d)" in ba and "Barrier:" in ba, "BOSS115: the preview draws the barrier and the reach circle and says them in words")
    # the server: an unknown choice refused, a barrier saved (a temporary copy)
    tmp = tempfile.mkdtemp(prefix="le_selftest_boss115_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        os.makedirs(os.path.join(server.CONTENT, "boss_attacks"))
        os.makedirs(os.path.join(server.CONTENT, "sounds"))
        with open(os.path.join(server.CONTENT, "sounds", "soundmap.json"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"sounds": {"en_boss_attack": {}, "en_boss_pattern_warn": {}}}))
        r = BAIO.create(server, "t_wall", "Test Wall", "", "pattern")
        p = os.path.join(server.CONTENT, "boss_attacks", "t_wall", "t_wall.json")
        d = json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else {}
        check(r["ok"] and isinstance(d.get("barrier"), dict) and d["barrier"].get("look") == "none",
              "BOSS115: a new pattern carries the barrier group, off: %s" % {k: r.get(k) for k in ("ok", "error")})
        obj = json.loads(open(p, encoding="utf-8").read())
        obj["barrier"]["look"] = "iron_fence"
        obj["barrier"]["radius_mode"] = "fixed"
        obj["barrier"]["radius"] = 14.0
        s1 = BAIO.save(server, "t_wall", obj, server.mtime_of(p))
        check(s1["ok"] and json.load(open(p, encoding="utf-8"))["barrier"]["look"] == "iron_fence", "BOSS115: a save writes the barrier: %s" % {k: s1.get(k) for k in ("ok", "error")})
        bad = json.loads(json.dumps(obj))
        bad["barrier"]["look"] = "moat"
        s2 = BAIO.save(server, "t_wall", bad, None)
        check(not s2["ok"] and "barrier.look" in str(s2.get("error", "")), "BOSS115: an unknown barrier look is refused: %s" % s2.get("error"))
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)
