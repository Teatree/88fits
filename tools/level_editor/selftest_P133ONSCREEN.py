"""Pass 133, lane ONSCREEN: "Show on screen" (Garry, 2026-11-07: the On screen estimate drawn as the Outlaw and the
creatures round him at one second, each with its row's settings, laid out as the spawning sets them, a respectable
distance apart, fractions by random select, from a button into a pop-up with a time slider).

  model   onscreen_model.js under Node: the count rule (the whole part, one more with the fraction as the chance: the mean
          over many seeds follows the fraction, never below the floor nor above the ceiling), a fixed seed is
          deterministic, no two bodies overlap (nor the Outlaw), a ring row's bodies lie on its ring when nobody has
          walked yet, an in_front row's come from the top, a Special row's bodies are all specials (x their size), an
          Elite row's wear the crown (x ELITE_SCALE), a size range is rolled inside it, the row attribution follows the
          past window's tallies, the pool's limit cuts the biggest counts, the facing and the phases, the filter's
          factors; the real Red Canyon estimate at the Dust Bowl's peak lays out in bounded time
  page    timeline.js's button on the On screen section, index.html's script order, onscreen.js's words (Outlaw, never
          Hero, the slider, the +/- buttons, Re-roll, the three phases), style.css, instructions.js's how-to,
          docs/level_editor.md's section
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

RUNNER = r"""
const path = require('path');
const M = require(process.argv[2]);
const dir = path.dirname(process.argv[2]);
const O = require(path.join(dir, 'onscreen_model.js'));
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  const cr = q.creatures;
  const rows = q.rows;
  const still = { turnover: 1000, sides: q.sides };   // a mean life of a millisecond: nobody has walked in
  // 1. the count rule over many seeds
  const pt = { t: 100, aliveBy: { gob: 10.3, brute: 0.7, ringer: 0 }, by: {}, src: {}, cap: 50 };
  const ns = { gob: [], brute: [], ringer: [] };
  for (let s = 1; s <= 400; s++) { const L = O.layout(pt, null, rows, cr, Object.assign({ seed: s }, still)); for (const c of L.counts) ns[c.id].push(c.n); }
  out.counts = { gob: [Math.min(...ns.gob), Math.max(...ns.gob), ns.gob.reduce((a, b) => a + b, 0) / ns.gob.length], brute: [Math.min(...ns.brute), Math.max(...ns.brute), ns.brute.reduce((a, b) => a + b, 0) / ns.brute.length], ringer: ns.ringer.length };
  // 2. determinism and the overlap on a big crowd that has walked in
  const big = { t: 100, aliveBy: { gob: 180.6, brute: 12.2, ringer: 24, fronter: 9 }, by: { gob: [1000, 30, 50], brute: [60, 0, 0] }, src: {}, cap: 300 };
  const A = O.layout(big, null, rows, cr, { seed: 9, turnover: 0.06, sides: q.sides });
  const B = O.layout(big, null, rows, cr, { seed: 9, turnover: 0.06, sides: q.sides });
  out.same = JSON.stringify(A.bodies.map((b) => [b.id, b.x, b.z, b.size, b.special, b.elite])) === JSON.stringify(B.bodies.map((b) => [b.id, b.x, b.z, b.size, b.special, b.elite]));
  out.overlap = O.worstOverlap(A.bodies);
  out.total = [A.total, A.counts.map((c) => [c.id, c.n])];
  out.minDist = Math.min(...A.bodies.map((b) => Math.hypot(b.x, b.z) - b.radius));
  out.gobSpecials = A.bodies.filter((b) => b.id === 'gob' && b.special).length;
  out.gobElites = A.bodies.filter((b) => b.id === 'gob' && b.elite).length;
  out.gobN = A.bodies.filter((b) => b.id === 'gob').length;
  out.ages = A.bodies.filter((b) => b.id === 'gob').map((b) => b.age);
  out.walked = A.bodies.filter((b) => b.id === 'gob').map((b) => b.dist);
  // 3. a ring row on its ring, in_front from the top, a Special row, an Elite row, a size range (nobody walked)
  const S = O.layout({ t: 100, aliveBy: { ringer: 12, fronter: 8, spec: 5, crowned: 4, ranged: 30 }, by: {}, src: {}, cap: 50 }, null, rows, cr, Object.assign({ seed: 3 }, still));
  const ring = S.bodies.filter((b) => b.id === 'ringer');
  out.ring = ring.map((b) => Math.hypot(b.x, b.z));
  out.ringR = rows.find((r) => r.enemy === 'ringer').ring_radius;
  out.front = S.bodies.filter((b) => b.id === 'fronter').map((b) => [b.x, b.z, Math.atan2(b.x, -b.z) * 180 / Math.PI]);
  out.spec = S.bodies.filter((b) => b.id === 'spec').map((b) => [b.special, b.size, b.tint, b.glow, b.elite]);
  out.crowned = S.bodies.filter((b) => b.id === 'crowned').map((b) => [b.elite, b.crown, b.size, b.special]);
  out.ranged = S.bodies.filter((b) => b.id === 'ranged').map((b) => b.size);
  out.looks = S.bodies.filter((b) => b.id === 'spec').map((b) => b.look);
  out.eliteArch = O.layout({ t: 100, aliveBy: { bossy: 1 }, by: {}, src: {}, cap: 1 }, null, rows, cr, Object.assign({ seed: 1 }, still)).bodies.map((b) => [b.crown, b.elite]);
  // 4. the row attribution: the past window's tallies pick the row (two gob rows, one spawned lately)
  const now = { t: 100, aliveBy: { gob: 20 }, by: {}, src: { 'roster:0': 100, 'roster:1': 100 }, cap: 50 };
  const before = { t: 80, src: { 'roster:0': 100, 'roster:1': 40 } };
  const R = O.layout(now, before, rows, cr, Object.assign({ seed: 5 }, still));
  out.attrib = [...new Set(R.bodies.map((b) => b.ri))];
  out.weights = [O.rowWeights('gob', rows, now.src, before.src, 100), O.rowWeights('gob', rows, {}, {}, 100), O.rowWeights('gob', rows, {}, {}, 5000), O.rowWeights('nobody', rows, {}, {}, 100)];
  // 5. the pool's limit
  const P = O.layout({ t: 1, aliveBy: { gob: 300, brute: 100 }, by: {}, src: {}, cap: 500 }, null, rows, cr, Object.assign({ seed: 2, maxBodies: 320 }, still));
  out.pool = [P.total, P.counts.map((c) => [c.id, c.n])];
  // 6. the facing, the phases, the filter, the angles
  out.facing = [O.facingOf(0, -10, false, false), O.facingOf(0, 10, false, false), O.facingOf(-10, 0, true, false), O.facingOf(10, 0, true, false), O.facingOf(0, -10, false, true), O.facingOf(7, -7, true, false), O.facingOf(-7, 7, true, false)];
  out.phases = [O.phaseAt(0), O.phaseAt(1.9), O.phaseAt(2), O.phaseAt(4.5), O.phaseAt(6)].map((p) => [p.k, p.phase.anim, p.phase.turned, Math.round(p.into * 10) / 10]);
  out.filter = [O.filterMults(null), O.filterMults({ color: '#3D55C8', strength: 0.48 }), O.filterMults({ color: '#B08A60', strength: 0.34, actors: 0.15 }), O.filterMults({ color: 'nope', strength: 2 })];
  const r = O.rng(11);
  const angs = []; for (let k = 0; k < 400; k++) angs.push(O.spawnAngle({ mode: 'sides', top: 0, bottom: 0, left: 1, right: 0 }, r) * 180 / Math.PI);
  out.leftArc = [Math.min(...angs), Math.max(...angs)];
  const angs2 = []; for (let k = 0; k < 400; k++) angs2.push(O.spawnAngle({ mode: 'sides', top: 30, bottom: 20, left: 20, right: 20 }, r) * 180 / Math.PI);
  out.sidesUsed = [angs2.some((a) => Math.abs(a) < 45), angs2.some((a) => Math.abs(a) > 135), angs2.some((a) => a > 45 && a < 135), angs2.some((a) => a < -45 && a > -135)];
  out.project = O.project(2, -3, 10, 100, 200);
  out.roll = (() => { const rr = O.rng(1); return [O.rollCount(3, rr), O.rollCount(0, rr), O.rollCount(-2, rr)]; })();
  // 7. the real map's estimate at the Dust Bowl's peak
  if (q.rc) {
    const tl = q.rc.timeline_data;
    M.normaliseRoster(tl);
    const byId = {}; for (const c of q.enemies) byId[c.id] = c;
    const est = M.spawnEstimate(tl, q.enemies, { stage: 2 });
    const w = M.stageWindow(tl, 2);
    let best = null;
    for (const p of est.points) if (!p.after && p.t >= w.start && p.t <= w.end && (!best || p.alive > best.alive)) best = p;
    const t0 = Date.now();
    const L = O.layout(best, M.estimateAt(est, best.t - O.ATTRIB_WINDOW), tl.roster, byId, { seed: 7, sides: tl.spawn_sides, specialDefaults: tl.special_defaults, maxBodies: M.MAX_BODIES });
    const rowIds = new Set(); for (const r of tl.roster) for (const x of O.rowIds(r)) rowIds.add(x.id);
    out.rc = { ms: Date.now() - t0, alive: best.alive, total: L.total, overlap: O.worstOverlap(L.bodies), looks: L.bodies.every((b) => b.look === (b.ri >= 0 && tl.roster[b.ri].variant ? tl.roster[b.ri].variant : (byId[b.id].play || byId[b.id].variant || ''))),
      rows: L.bodies.every((b) => b.ri >= 0 || !rowIds.has(b.id)),
      far: Math.max(...L.bodies.map((b) => b.dist)), rowsSeen: [...new Set(L.bodies.map((b) => tl.roster[b.ri] && tl.roster[b.ri].id))].length, sizes: L.bodies.every((b) => b.size > 0 && b.radius > 0) };
  }
  process.stdout.write(JSON.stringify(out));
});
"""

CREATURES = {
    "gob": {"id": "gob", "size": 1.2, "radius": 0.45, "speed": 3, "pack_size": 3, "archetype": "regular", "play": "G-B", "variance": {"special": {"size": 1.5, "tint": "#8A1428"}}},
    "brute": {"id": "brute", "size": 2.5, "radius": 1.0, "speed": 1.5, "pack_size": 1, "archetype": "regular", "play": "B-A"},
    "ringer": {"id": "ringer", "size": 1.0, "radius": 0.4, "speed": 2, "pack_size": 12, "archetype": "regular", "play": "R-A"},
    "fronter": {"id": "fronter", "size": 1.0, "radius": 0.4, "speed": 2, "pack_size": 2, "archetype": "regular", "play": "F-A"},
    "spec": {"id": "spec", "size": 1.0, "radius": 0.4, "speed": 2, "pack_size": 1, "archetype": "regular", "play": "S-A", "variance": {"special": {"size": 2.0, "tint": "#00ff00", "glow": 0.9}}},
    "crowned": {"id": "crowned", "size": 1.0, "radius": 0.4, "speed": 2, "pack_size": 1, "archetype": "regular", "play": "C-A"},
    "ranged": {"id": "ranged", "size": 1.0, "radius": 0.4, "speed": 2, "pack_size": 1, "archetype": "regular", "play": "N-A"},
    "bossy": {"id": "bossy", "size": 2.0, "radius": 0.8, "speed": 2, "pack_size": 1, "archetype": "elite", "play": "E-A"},
}
ROWS = [
    {"id": "g1", "t": 0, "until": 50, "enemy": "gob", "pattern": "scatter"},
    {"id": "g2", "t": 50, "until": 3000, "enemy": "gob", "pattern": "pack", "variant": "G-C"},
    {"id": "b1", "t": 0, "enemy": "brute", "pattern": "scatter"},
    {"id": "r1", "t": 0, "enemy": "ringer", "pattern": "ring", "ring_radius": 14, "pack": 12},
    {"id": "f1", "t": 0, "enemy": "fronter", "pattern": "in_front"},
    {"id": "s1", "t": 0, "enemy": "spec", "special": True, "variant": "S-B"},
    {"id": "c1", "t": 0, "enemy": "crowned", "elite": "shielded"},
    {"id": "n1", "t": 0, "enemy": "ranged", "stats": {"size": [2, 3]}},
    {"id": "e1", "t": 0, "enemy": "bossy"},
]
SIDES = {"mode": "sides", "top": 30, "bottom": 20, "left": 20, "right": 20}


def _read(*parts):
    with open(os.path.join(*parts), encoding="utf-8") as f:
        return f.read()


def model_checks(check, run_node, server):
    q = {"creatures": CREATURES, "rows": ROWS, "sides": SIDES, "rc": None, "enemies": []}
    try:
        q["rc"] = server.load_json(server.map_path("red_canyon"))
        q["enemies"] = server.list_creatures()
    except Exception as e:  # noqa: BLE001
        print("P133ONSCREEN: Red Canyon not read (%s)" % e)
    res = run_node(q, RUNNER)
    if not res:
        check(False, "P133ONSCREEN: onscreen_model.js ran under node")
        return
    c = res["counts"]
    check(c["gob"][0] == 10 and c["gob"][1] == 11 and 0.2 <= c["gob"][2] - 10 <= 0.4, "P133ONSCREEN model: 10.3 expected draws 10 or 11, one more about 30%% of the time: %s" % c["gob"])
    check(c["brute"][0] == 0 and c["brute"][1] == 1 and 0.6 <= c["brute"][2] <= 0.8, "P133ONSCREEN model: 0.7 expected draws 0 or 1, about 70%% of the time: %s" % c["brute"])
    check(c["ringer"] == 0, "P133ONSCREEN model: a creature the estimate has none of alive is not listed")
    check(res["same"] is True, "P133ONSCREEN model: the same seed lays the same crowd out")
    check(res["overlap"] < 0.1, "P133ONSCREEN model: no two of %d bodies overlap by more than 10 cm (worst %.3f m)" % (res["total"][0], res["overlap"]))
    check(res["minDist"] >= 0.5 - 0.05, "P133ONSCREEN model: nobody stands inside the Outlaw's 0.5 m (nearest edge %.2f m)" % res["minDist"])
    check(res["total"][0] == sum(n for _, n in res["total"][1]) and 220 <= res["total"][0] <= 232, "P133ONSCREEN model: the total is the counts' sum: %s" % res["total"])
    gn = res["gobN"]
    check(gn and 0 < res["gobSpecials"] < gn * 0.1 and 0 < res["gobElites"] < gn * 0.12, "P133ONSCREEN model: the gobs roll specials and elites by their shares so far (3%% coloured, 5%% modified): %d / %d of %d" % (res["gobSpecials"], res["gobElites"], gn))
    walked = sorted(res["walked"])
    check(walked[0] < 3 and walked[-1] > 15 and walked[len(walked) // 2] < 12, "P133ONSCREEN model: old gobs close round the Outlaw, fresh ones far out (near %.1f, median %.1f, far %.1f m)" % (walked[0], walked[len(walked) // 2], walked[-1]))
    ring = res["ring"]
    check(len(ring) == 12 and all(abs(d - res["ringR"]) < 1.0 for d in ring), "P133ONSCREEN model: a ring row's 12 lie on its %s m ring (nobody walked): %s" % (res["ringR"], [round(d, 1) for d in ring]))
    fr = res["front"]
    check(len(fr) == 8 and all(z < 0 and abs(a) <= 46 for _, z, a in fr) and all(18 <= (x * x + z * z) ** 0.5 <= 25 for x, z, _ in fr), "P133ONSCREEN model: an in_front row's come from the top, about 19-24 m out, within 45 degrees: %s" % [round(a) for _, _, a in fr])
    sp = res["spec"]
    check(len(sp) == 5 and all(s[0] is True and abs(s[1] - 2.0) < 1e-9 and s[2] == "#00ff00" and abs(s[3] - 0.9) < 1e-9 and s[4] is False for s in sp), "P133ONSCREEN model: a Special row's bodies are all specials, x their size, in their tint and glow: %s" % sp[:2])
    check(res["looks"] == ["S-B"] * 5, "P133ONSCREEN model: a row's variant is the look its bodies wear: %s" % res["looks"][:2])
    cw = res["crowned"]
    check(len(cw) == 4 and all(s[0] is True and s[1] is True and abs(s[2] - 1.4) < 1e-9 and s[3] is False for s in cw), "P133ONSCREEN model: an Elite row's bodies wear the crown at x1.4: %s" % cw[:2])
    rg = res["ranged"]
    check(len(rg) == 30 and all(2 <= s <= 3 for s in rg) and max(rg) - min(rg) > 0.3, "P133ONSCREEN model: a size range [2, 3] is rolled per body: %.2f..%.2f" % (min(rg), max(rg)))
    check(res["eliteArch"] == [[True, False]], "P133ONSCREEN model: an Elite mini-boss (archetype elite) wears the crown without the modifier's scale: %s" % res["eliteArch"])
    check(res["attrib"] == [1], "P133ONSCREEN model: the row that spawned in the past window gets the bodies: rows %s" % res["attrib"])
    w = res["weights"]
    check(len(w[0]) == 1 and w[0][0]["ri"] == 1 and abs(w[0][0]["w"] - 60) < 1e-9, "P133ONSCREEN model: rowWeights by the tallies' difference: %s" % w[0])
    check([x["ri"] for x in w[1]] == [1] and [x["ri"] for x in w[2]] == [0] and w[3] == [], "P133ONSCREEN model: no tallies: the rows open now, else the first row of it, none for a stranger: %s" % [w[1], w[2], w[3]])
    check(res["pool"][0] == 320 and dict(res["pool"][1])["brute"] == 100 and dict(res["pool"][1])["gob"] == 220, "P133ONSCREEN model: the pool's 320 cuts the biggest count: %s" % res["pool"])
    f = res["facing"]
    check(f[0] == {"dir": "front", "facing": "right"} and f[1] == {"dir": "back", "facing": "right"} and f[2] == {"dir": "side", "facing": "right"} and f[3] == {"dir": "side", "facing": "left"} and f[4] == {"dir": "back", "facing": "right"} and f[5]["dir"] == "fd" and f[5]["facing"] == "left" and f[6]["dir"] == "bd" and f[6]["facing"] == "right",
          "P133ONSCREEN model: the facing from where a body walks (above the Outlaw its front, below its back, the sides mirrored, turned round in phase 2): %s" % f)
    check(res["phases"] == [[0, "run", False, 0], [0, "run", False, 1.9], [1, "run", True, 0], [2, "die", False, 0.5], [0, "run", False, 0]], "P133ONSCREEN model: three phases of 2 s, run, run turned, die, round again: %s" % res["phases"])
    fl = res["filter"]
    check(fl[0]["on"] is False and fl[0]["actors"] == [1, 1, 1] and fl[1]["on"] is True and abs(fl[1]["world"][0] - (1 + (0x3D / 255 - 1) * 0.48)) < 1e-9 and abs(fl[1]["actors"][2] - (1 + (0xC8 / 255 - 1) * 0.48 * 0.35)) < 1e-9
          and abs(fl[2]["actors"][0] - (1 + (0xB0 / 255 - 1) * 0.34 * 0.15)) < 1e-9 and fl[3]["world"] == [0, 0, 0],
          "P133ONSCREEN model: the filter's factors (StageLook.filter_mults: white.lerp(colour, strength), the creatures at x actors, 0.35 by default; a bad colour is black): %s" % [fl[1]["world"], fl[2]["actors"]])
    check(45 <= res["leftArc"][0] and res["leftArc"][1] <= 135 and res["leftArc"][1] - res["leftArc"][0] > 70, "P133ONSCREEN model: a left-only spawn_sides lands within 45 degrees of the left: %s" % res["leftArc"])
    check(res["sidesUsed"] == [True, True, True, True], "P133ONSCREEN model: Red Canyon's sides use all four")
    check(res["project"]["sx"] == 120 and abs(res["project"]["sy"] - (200 - 30 * 0.72)) < 1e-9, "P133ONSCREEN model: project: x across at ppm, z down at ppm x 0.72 (the 46 degree pitch): %s" % res["project"])
    check(res["roll"] == [3, 0, 0], "P133ONSCREEN model: rollCount of a whole number is itself, nothing below zero: %s" % res["roll"])
    rc = res.get("rc")
    if rc:
        check(rc["ms"] < 3000 and abs(rc["total"] - rc["alive"]) < 1.0 + 1e-9 or rc["total"] == 320, "P133ONSCREEN model: the Dust Bowl's peak (%.1f alive) lays out %d bodies in %d ms" % (rc["alive"], rc["total"], rc["ms"]))
        check(rc["overlap"] < 0.1 and rc["looks"] and rc["rows"] and rc["sizes"] and rc["far"] <= 24.6 and rc["rowsSeen"] >= 3,
              "P133ONSCREEN model: on the real map every body has its row (one the roster spawns), its look and a size, none overlap (worst %.3f m), none past the spawn band (%.1f m), %d rows seen" % (rc["overlap"], rc["far"], rc["rowsSeen"]))
    else:
        check(False, "P133ONSCREEN model: the real Red Canyon estimate laid out")


def page_checks(check):
    tl = _read(HERE, "timeline.js")
    check("'Show on screen'" in tl and "OnScreen.open(" in tl and "data-path': 'onscreen.show'" in tl and tl.index("Show on screen") > tl.index("if (id === 'onscreen')"), "P133ONSCREEN page: the On screen section's bar carries the Show on screen button")
    html = _read(HERE, "index.html")
    check('<script src="onscreen_model.js"></script>' in html and '<script src="onscreen.js"></script>' in html and html.index("onscreen_model.js") < html.index("onscreen.js") and html.index("strip_player.js") < html.index("onscreen.js") and html.index("sim.js") < html.index("onscreen.js"),
          "P133ONSCREEN page: index.html loads onscreen_model.js then onscreen.js after strip_player.js and sim.js")
    js = _read(HERE, "onscreen.js")
    words = re.findall(r"(?:text|title): ['`]([^'`]*)['`]", js)
    said = " ".join(words)
    check(not re.search(r"\bHero(es)?\b", said) and "Outlaw" in said, "P133ONSCREEN page: the pop-up's words say Outlaw, never Hero")
    for want in ["onscreen-slider", "'−1 s'", "'+1 s'", "'Re-roll'", "'Peak'", "'Close'", "ArrowLeft", "requestAnimationFrame", "StripPlayer.animKey", "StripPlayer.cell", "Model.estimateAt", "Model.spawnEstimate", "/api/heroes", "88fits-sim-form", "'multiply'", "drawCrown", "drawRim", "O.PHASES"]:
        check(want in js, "P133ONSCREEN page: onscreen.js has %s" % want)
    css = _read(HERE, "style.css")
    check(".amodal.onscreen" in css and ".onscreen-canvas" in css and ".onscreen-list" in css, "P133ONSCREEN page: style.css styles the pop-up")
    ins = _read(HERE, "instructions.js")
    check("Show on screen" in ins and "Pass 133" in ins and "Re-roll" in ins, "P133ONSCREEN page: instructions.js explains the pop-up")
    doc = _read(ROOT, "docs", "level_editor.md")
    check("## Pass 133" in doc and "Show on screen" in doc and "onscreen_model.js" in doc, "P133ONSCREEN docs: docs/level_editor.md has the pass 133 section")
    for name in ("onscreen.js", "onscreen_model.js", "selftest_P133ONSCREEN.py"):
        with open(os.path.join(HERE, name), "rb") as f:
            check(b"\r\n" not in f.read(), "P133ONSCREEN: %s has LF line endings" % name)


def checks(check, run_node, server):
    model_checks(check, run_node, server)
    page_checks(check)
