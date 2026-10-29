"""Pass 103, lane LE: the cap's units, the Composition colours and the Save that never ends (Garry, 2026-10-24: "the cap in
bodies line in the OnScreen row gives me a different set of numbers that don't match. Which is the correct one?"; "add a
colour box next to the enemy icon (to the left of it) so I can tell which enemy is which in the composition view";
"Stage 2 save is not working, it's just saying `Saving and importing...` and nothing is happening").

Groups:
  caps     timeline_model.js under Node: effectiveLimit (the cap in load at the mix against the hard cap in bodies, the
           one that binds), capBinding per stage window (a stage where the cap never binds, the cap that would count),
           on the fixture's estimate second by second (limit = min(cap in bodies, hard cap) at every point); app.js's
           capRawAt / capCut (cap_max cutting the curve) on hand-made timelines and on Red Canyon as the file says it
  swatch   compColor: the chart's colour for a drawn creature, the others' grey for a folded one; timeline.js draws the
           areas, the hover card's swatch (left of the icon) and the legend with the one function
  save     server.write_map on a temp copy of the map with a fake Godot lock holder and a fake job queue: a short wait
           (SAVE_LOCK_WAIT, not LOCK_WAIT), the queued import job and the holder in the answer, a second Save joining
           the queued job, a free lock with no runnable Godot failing with the reason, run_import's old answer; over
           HTTP a Save from every stage window (an edit to a row of that stage) answers within seconds and lands in the
           file; the page's words for every answer and job state (saveOutcome, importJobLine, fmtAge extracted from
           app.js) never "Saving and importing…", and save() always ends (finally, the abort)
Nothing here writes under game/ or tools/dl/jobs/ (the real queue file's sha1 is compared before and after).
"""
import hashlib
import json
import os
import re
import shutil
import tempfile
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QUEUE = os.path.join(ROOT, "tools", "dl", "jobs", "queue.json")

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const M = require(process.argv[2]);
const dir = path.dirname(process.argv[2]);
const T = require(path.join(dir, 'timeline_model.js'));
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.el = q.el.map((a) => T.effectiveLimit(...a));
  out.el = out.el.map((r) => Object.assign({}, r, { hard: isFinite(r.hard) ? r.hard : 'inf', limit: isFinite(r.limit) ? r.limit : 'inf' }));
  out.bind = T.capBinding(q.limits.map((L) => Object.assign({}, L, { hard: L.hard === 'inf' ? Infinity : L.hard })), q.windows)
    .map((r) => Object.assign({}, r, { hard: isFinite(r.hard) ? r.hard : 'inf', minCapBodies: isFinite(r.minCapBodies) ? r.minCapBodies : 'inf' }));
  out.col = q.col.map(([id, shown, folded]) => T.compColor(id, shown, (x) => 'C:' + x, folded));
  out.other = T.OTHER_COLOR;
  out.pal = T.compPalette(['a', 'b', 'c', 'd'], (x) => ({ a: '#111111', b: '#222222', c: '#111111', d: '#222222' })[x], ['#111111', '#5a5955', '#333333', '#222222', '#444444']);
  // the fixture's estimate, second by second: the limit at every point against min(cap in bodies, hard cap)
  out.est = q.fix.map((tl) => {
    const est = M.spawnEstimate(tl, q.creatures, { turnover: 0.08, bossSeconds: 20, portalSeconds: 10, end: 300 });
    const srcCreature = (k) => { const p = k.split(':'); if (p[0] !== 'roster') return ''; const r = tl.roster[Number(p[1])]; return r && typeof r.enemy === 'string' ? r.enemy : ''; };
    const ser = T.aliveSeries(est, srcCreature, () => 0);
    const shareOf = (id) => (q.creatures[id] || {}).cap_share || 1;
    let bad = 0, cap = 0, hard = 0, n = 0;
    const limits = [];
    for (let j = 0; j < ser.n; j++) {
      const L = T.loadAt(ser, j, shareOf, () => false);
      const pt = est.points[j] || {};
      const c = pt.cap != null ? Number(pt.cap) : 0;
      const load = pt.load != null ? Number(pt.load) : L.load;
      const E = T.effectiveLimit(c, load, L.bodies, tl.hard_cap, 1);
      const cb = T.capBodies(c, load, L.bodies, 1);
      const want = Math.min(cb, tl.hard_cap);
      if (Math.abs(E.limit - want) > 1e-9 || (E.binds === 'cap') !== (cb <= tl.hard_cap)) bad++;
      if (E.binds === 'cap') cap++; else hard++;
      n++;
      limits.push({ t: ser.t[j], binds: E.binds, capBodies: E.capBodies, hard: E.hard, per: E.per, alive: L.bodies });
    }
    const b = T.capBinding(limits, [{ i: 0, a: 0, b: 300 }])[0];
    return { n, bad, cap, hard, never: b.never, capToBind: b.capToBind, per: b.per };
  });
  // app.js's pure helpers, cut out of the file and run against stand-ins
  const app = fs.readFileSync(path.join(dir, 'app.js'), 'utf8');
  const fn = (name) => {
    const i = app.indexOf(`function ${name}(`);
    if (i < 0) return '';
    let k = app.indexOf('{', i), depth = 0;
    for (; k < app.length; k++) { const ch = app[k]; if (ch === '{') depth++; else if (ch === '}') { depth--; if (depth === 0) break; } }
    return app.slice(i, k + 1);
  };
  out.found = ['capRawAt', 'capCut', 'saveOutcome', 'fmtAge', 'importJobLine', 'watchImport', 'save'].map((n) => [n, fn(n).length > 0]);
  const ctx = { M, Infinity, Math, Number, String, Object, Date, isFinite, Array, console };
  vm.createContext(ctx);
  vm.runInContext([fn('capRawAt'), fn('capCut'), fn('lockWords'), fn('importOutcome'), fn('saveOutcome'), fn('fmtAge'), fn('importJobLine')].join('\n') +
    `\nlet TL = null; const tl = () => TL; const curveAt = (t) => { const cc = TL.cap_curve || []; if (!cc.length) return (Number(TL.cap_start) || 0) + (Number(TL.cap_per_minute) || 0) * t / 60; return M.samplePoints(cc.slice().sort((a, b) => a[0] - b[0]), t); };
     const stageList = () => M.stageList(TL); const runEnd = () => { const l = M.stageList(TL); return l[l.length - 1].end; };
     const stageAt = (t) => { const l = M.stageList(TL); let s = 0; for (const w of l) if (t >= w.start) s = w.i; return s; };
     this.cutOf = (tl) => { TL = tl; return capCut(); }; this.rawAt = (tl, t) => { TL = tl; return capRawAt(t); };
     this.outcome = saveOutcome; this.age = fmtAge; this.jobLine = importJobLine;`, ctx);
  out.cut = q.cuts.map((tl) => { const c = ctx.cutOf(tl); return Object.assign({}, c, { max: isFinite(c.max) ? c.max : 'inf' }); });
  out.raw = q.raws.map(([tl, t]) => ctx.rawAt(tl, t));
  out.outcomes = q.answers.map((r) => ctx.outcome(r, '1:12:03 AM'));
  out.ages = [5, 119, 120, 4856, 7260].map((s) => ctx.age(s));
  out.lines = q.jobs.map(([job, base, lk, now]) => ctx.jobLine(job, base, lk, now));
  process.stdout.write(JSON.stringify(out));
});
"""

CREATURES = {
    "goblin": {"id": "goblin", "name": "Goblin", "kind": "enemy", "hp": 10, "damage": 2, "speed": 2, "pack_size": 3, "cap_share": 0.5, "radius": 0.4, "size": 1},
    "brute": {"id": "brute", "name": "Brute", "kind": "enemy", "hp": 80, "damage": 9, "speed": 1.2, "pack_size": 1, "cap_share": 2.5, "radius": 0.7, "size": 2},
}


def _fixture(cap, hard, cap_max=2000):
    return {"stage_length": 300, "stages": 1, "cap_curve": [[0, cap]], "hard_cap": hard, "cap_max": cap_max, "spawn_interval": 0.5,
            "burst_min": 5, "burst_max": 12,
            "roster": [{"id": "r1", "t": 0, "enemy": "goblin", "weights": [[0, 8], [300, 8]]},
                       {"id": "r2", "t": 60, "until": 260, "enemy": "brute", "weights": [[60, 2], [260, 2]]}],
            "events": [{"t": 300, "type": "boss", "enemy": "brute"}]}


def _read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def _sha1(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha1(f.read()).hexdigest()
    except OSError:
        return None


# ---------------------------------------------------------------- caps + swatch (Node)

def _node_checks(check, run_node, server):
    rc = {}
    try:
        rc = (server.load_json(server.map_path("red_canyon")) or {}).get("timeline_data") or {}
    except Exception as e:  # noqa: BLE001
        print("LE103: Red Canyon not read (%s)" % e)
    inf = "inf"
    limits = ([{"t": t, "binds": "hard", "capBodies": 600 + t, "hard": 300, "per": 0.5, "alive": 10} for t in range(0, 100)]
              + [{"t": t, "binds": "cap" if t % 2 else "hard", "capBodies": 250, "hard": 300, "per": 1.2, "alive": 10} for t in range(100, 200)]
              + [{"t": t, "binds": "hard", "capBodies": 900, "hard": 300, "per": 0.8, "alive": 0} for t in range(200, 250)])
    windows = [{"i": 0, "a": 0, "b": 100}, {"i": 1, "a": 100, "b": 200}, {"i": 2, "a": 200, "b": 250}, {"i": 3, "a": 400, "b": 500}]
    cuts = [_fixture(500, 300, 150), _fixture(120, 300, 150), _fixture(500, 300, None), {"stage_length": 300, "stages": 2, "cap_start": 100, "cap_per_minute": 30, "cap_max": 200, "roster": []},
            {"stage_length": 300, "stages": 3, "cap_curve": [[0, 100]], "cap_per_stage": 60, "cap_max": 200, "roster": []}]
    cuts[2].pop("cap_max")
    if rc:
        cuts.append(rc)
    raws = [[cuts[0], 50], [cuts[3], 600], [cuts[4], 650]]
    answers = [
        {"ok": True, "wrote": "game/content/maps/red_canyon/red_canyon.json", "backup": "tools/level_editor/backups/red_canyon-x.json", "import_ok": True, "output": "import_json: wrote 1"},
        {"ok": True, "wrote": "m.json", "import_ok": None, "import_job": "j1", "import_joined": False, "lock": {"who": "cli godot", "age_s": 4856}, "output": "held"},
        {"ok": True, "wrote": "m.json", "import_ok": None, "import_job": "j1", "import_joined": True, "lock": {"who": "cli godot", "age_s": 30}, "output": "held"},
        {"ok": True, "wrote": "m.json", "import_ok": None, "import_job": None, "lock": {"who": "cli godot", "age_s": 30}, "output": "no import job could be queued: the jobs module is not here yet"},
        {"ok": True, "wrote": "m.json", "import_ok": False, "output": "line 1\nSCRIPT ERROR: res://x.gd:3"},
    ]
    base = "Saved m.json at 1:12:03 AM · import queued as job j1: the Godot lock is held by cli godot for 1 h 21 min; it runs when the lock frees"
    lk = {"who": "cli godot", "age_s": 600, "at": 1000000}
    jobs = [[{"id": "j1", "state": "queued", "lock_waits": {"godot": "cli godot since 01:21"}}, base, lk, 1000000 + 60000],
            [{"id": "j1", "state": "queued", "lock_waits": {}}, base, None, None],
            [{"id": "j1", "state": "running", "lock_waits": {}}, base, None, None],
            [{"id": "j1", "state": "done"}, base, None, None],
            [{"id": "j1", "state": "failed", "error": "SCRIPT ERROR"}, base, None, None],
            [{"id": "j1", "state": "cancelled"}, base, None, None],
            [None, base, None, None],
            [{"id": "j1", "state": "queued", "lock_waits": {"godot": "sim lane since 01:00"}}, base, lk, 1000000]]
    q = {"el": [[150, 50, 100, 300, 1], [500, 50, 100, 300, 1], [600, 0, 0, 300, 0.5], [100, 250, 100, 0, 1], [300, 150, 100, 200, 1]],
         "limits": limits, "windows": windows,
         "col": [["goblin", ["goblin", "brute"], True], ["imp", ["goblin", "brute"], True], ["imp", ["goblin", "brute"], False], ["__other", [], True], ["brute", ["brute"], False]],
         "fix": [_fixture(60, 200), _fixture(5000, 120)], "creatures": CREATURES, "cuts": cuts, "raws": raws, "answers": answers, "jobs": jobs}
    res = run_node(q, RUNNER)
    if not res:
        check(False, "LE103: timeline_model.js and app.js's helpers ran under node")
        return
    el = res["el"]
    # 150 load, 0.5 load a body -> 300 bodies = the hard cap: a tie is the cap's
    check(el[0]["capBodies"] == 300 and el[0]["limit"] == 300 and el[0]["binds"] == "cap" and el[0]["per"] == 0.5, "LE103 caps: 150 load at half a unit a body = 300 bodies, a tie with the hard cap is the cap's: %s" % el[0])
    check(el[1]["capBodies"] == 1000 and el[1]["limit"] == 300 and el[1]["binds"] == "hard", "LE103 caps: 500 load at half a unit = 1,000 bodies, the hard cap 300 binds: %s" % el[1])
    check(el[2]["capBodies"] == 1200 and el[2]["binds"] == "hard" and el[2]["per"] == 0.5, "LE103 caps: nobody alive reads the default share: %s" % el[2])
    check(el[3]["hard"] == inf and el[3]["limit"] == 40 and el[3]["binds"] == "cap", "LE103 caps: no hard cap: the cap alone (2.5 load a body: 100 load = 40 bodies): %s" % el[3])
    check(abs(el[4]["capBodies"] - 200) < 1e-9 and el[4]["binds"] == "cap", "LE103 caps: 300 load at 1.5 a body = 200 bodies, the tie with hard 200 is the cap's: %s" % el[4])
    b = res["bind"]
    check(b[0]["never"] and b[0]["hardSecs"] == 100 and b[0]["capToBind"] == 150 and b[0]["minCapBodies"] == 600,
          "LE103 caps: a window where the hard cap always binds is 'never', the cap counts under hard × the median load a body (300 × 0.5 = 150): %s" % b[0])
    check(not b[1]["never"] and b[1]["capSecs"] == 50 and b[1]["capToBind"] == 360, "LE103 caps: a window where the cap binds half the time is not 'never': %s" % b[1])
    check(b[2]["never"] and b[2]["per"] == 1 and b[2]["capToBind"] == 300, "LE103 caps: nobody alive: the median share falls back to 1: %s" % b[2])
    check(b[3]["n"] == 0 and not b[3]["never"], "LE103 caps: a window with no seconds is never flagged: %s" % b[3])
    est = res["est"]
    check(est[0]["n"] > 200 and est[0]["bad"] == 0 and est[0]["cap"] > 0 and not est[0]["never"],
          "LE103 caps: the fixture (cap 60 load, hard 200): the limit is min(cap in bodies, hard cap) at every second and the cap binds: %s" % est[0])
    check(est[1]["n"] > 200 and est[1]["bad"] == 0 and est[1]["cap"] == 0 and est[1]["never"] and est[1]["capToBind"] == int(120 * est[1]["per"]),
          "LE103 caps: cap 5,000 load under a hard cap of 120: the cap never binds, it would count under hard × the mix: %s" % est[1])
    cut = res["cut"]
    check(cut[0]["cut"] and cut[0]["raw"] == 500 and cut[0]["max"] == 150, "LE103 caps: cap_max 150 under a curve at 500 is a cut: %s" % cut[0])
    check(not cut[1]["cut"] and cut[1]["raw"] == 120, "LE103 caps: a curve under cap_max is no cut: %s" % cut[1])
    check(not cut[2]["cut"] and cut[2]["max"] == inf, "LE103 caps: no cap_max, no cut: %s" % cut[2])
    check(cut[3]["cut"] and cut[3]["raw"] >= 399, "LE103 caps: the straight line (cap_start + a minute's growth) checked to the run's end: %s" % cut[3])
    check(cut[4]["cut"] and cut[4]["raw"] == 220, "LE103 caps: cap_per_stage counted per stage (100 + 2 × 60 in stage 3): %s" % cut[4])
    check(res["raw"] == [500, 400, 220], "LE103 caps: capRawAt is the curve and the stage step before cap_max: %s" % res["raw"])
    if rc:
        pts = [p[1] for p in rc.get("cap_curve") or [] if isinstance(p, list) and len(p) > 1]
        mx = rc.get("cap_max")
        want = bool(pts) and mx is not None and max(pts) > float(mx)   # the map file's own numbers (Garry's), never pinned
        check(cut[5]["cut"] == want and (not want or cut[5]["raw"] >= max(pts)),
              "LE103 caps: Red Canyon as the file says it: cap_max %s against the curve's top %s -> cut %s: %s" % (mx, max(pts) if pts else None, want, cut[5]))
    # ---------------------------------------------------------------- swatch
    col, other = res["col"], res["other"]
    check(col[0] == "C:goblin" and col[1] == other and col[2] == "C:imp" and col[3] == other and col[4] == "C:brute",
          "LE103 swatch: compColor: a drawn creature its own colour, a folded one the others' grey, nothing folded = its own: %s" % col)
    tlj = _read("timeline.js")
    check("const compColorOf = (id) => TimelineModel.compColor(id, compShown, (c) => compMap[c] || App.creatureColor(c), compFolded);" in tlj
          and "compMap = TimelineModel.compPalette(shown, App.creatureColor, App.CREATURE_COLORS);" in tlj,
          "LE103 swatch: one colour function for the Composition lane (App.creatureColor made unique among the layers)")
    pal = res["pal"]
    check(pal["a"] == "#111111" and pal["b"] == "#222222" and pal["c"] == "#333333" and pal["d"] == "#444444" and len(set(pal.values())) == 4,
          "LE103 swatch: compPalette: two creatures sharing a colour get different ones (the first unused palette colour): %s" % pal)
    check("class: 'comp-area', fill: compColorOf(id)" in tlj and "'#5a5955' : App.creatureColor(id)" not in tlj, "LE103 swatch: the chart's areas are filled by compColorOf")
    m = re.search(r"function compCard\(t\) \{(.*?)\n  \}\n", tlj, re.S)
    body = m.group(1) if m else ""
    i_sw, i_img = body.find("el('i', { class: 'vc-sw', style: `background:${compColorOf(o.id)}`"), body.find("el('img', { src: App.iconFor(o.id)")
    check(0 < i_sw < i_img, "LE103 swatch: the hover card's swatch comes first, to the LEFT of the icon, in the chart's colour (%d, %d)" % (i_sw, i_img))
    m2 = re.search(r"function fillCompLegend\(layers\) \{(.*?)\n  \}\n", tlj, re.S)
    leg = m2.group(1) if m2 else ""
    check("compColorOf(id)" in leg and "App.iconFor(id)" in leg and "fillCompLegend(layers);" in tlj and "compShown = shown; compFolded = ids.length > 10;" in tlj,
          "LE103 swatch: the legend lists every layer the lane draws with the same colours")
    css = _read("style.css")
    check(".vc-r.vc-comp { grid-template-columns: 10px 16px 1fr auto auto; }" in css, "LE103 swatch: the card's row has a column for the swatch before the icon")
    # ---------------------------------------------------------------- the On screen lane and the Cap lane
    check("TimelineModel.effectiveLimit(cap, load, L.bodies, hardCap, 1)" in tlj and "y(isFinite(v.lim[j]) ? v.lim[j] : maxV)" in tlj,
          "LE103 caps: the On screen lane draws the effective limit (the lower of the cap in bodies and the hard cap)")
    check("function limitLines(box, j)" in tlj and "Limit now: " in tlj and "The hard cap binds here" in tlj and "The cap binds here" in tlj,
          "LE103 caps: the hover names the three numbers and the one that binds")
    check("kind: 'cap never binds'" in tlj and "TimelineModel.capBinding(" in tlj and "else if (wn.key === 'cap')" in tlj, "LE103 caps: the warning when the cap never binds in a stage, and Go to selects the cap")
    check("cap: ['Cap (load)'," in tlj and "load units (a goblin counts 0.5)" in tlj and "class: 'cap-max-line'" in tlj and "hard-cap-load" in tlj,
          "LE103 caps: the Cap lane says its unit, draws cap_max's cut and the hard cap in load at the mix")
    app = _read("app.js")
    check("{ const cc = capCut(); if (cc.cut) mark('cap', 'warn'," in app and "capRawAt, capCut," in app, "LE103 caps: a cap_max under the curve is a warning of the checks")
    for n, ok in res["found"]:
        check(ok, "LE103: app.js has function %s" % n)
    # ---------------------------------------------------------------- the page's words for a Save
    oc = res["outcomes"]
    check(oc[0]["kind"] == "good" and "import OK" in oc[0]["text"] and "red_canyon-x.json" in oc[0]["text"], "LE103 save: an import that ran: %s" % oc[0])
    # (pass 114, lane EDITOR: re-pinned to importOutcome's words, the same intent: the line names the queued job, the
    # holder and how long it has held Godot; the tooltip says the import runs by itself)
    check(oc[1]["kind"] == "busy" and oc[1]["watch"] == "j1" and "queued as job j1" in oc[1]["text"] and "the import waits for cli godot, 1 h 21 min" in oc[1]["text"]
          and "it runs by itself" in oc[1]["detail"],
          "LE103 save: the lock held: saved + import queued with the job and the holder: %s" % oc[1])
    check(oc[2]["watch"] == "j1" and "queued as job j1" in oc[2]["text"] and "joined the import job j1 already queued" in oc[2]["detail"], "LE103 save: a second Save joins the queued job: %s" % oc[2])
    check(oc[3]["kind"] == "bad" and not oc[3].get("watch") and "NOT IMPORTED" in oc[3]["text"] and "jobs module" in oc[3]["detail"], "LE103 save: no job could be queued: failed with the reason: %s" % oc[3])
    check(oc[4]["kind"] == "bad" and "IMPORT FAILED" in oc[4]["text"] and "SCRIPT ERROR" in oc[4]["text"], "LE103 save: a failed import names its last line: %s" % oc[4])
    check(all("Saving and importing" not in o["text"] for o in oc), "LE103 save: no answer leaves the line at 'Saving and importing…'")
    check(res["ages"] == ["5 s", "119 s", "2 min", "1 h 21 min", "2 h 1 min"], "LE103 save: fmtAge: %s" % res["ages"])
    ln = res["lines"]
    check(not ln[0]["done"] and ln[0]["kind"] == "busy" and "waiting for the Godot lock, held by cli godot since 01:21 for 11 min" in ln[0]["text"],
          "LE103 save: a queued job waiting for the lock: who and for how long: %s" % ln[0]["text"])
    check(not ln[1]["done"] and "queued behind other jobs" in ln[1]["text"] and not ln[2]["done"] and "importing now" in ln[2]["text"], "LE103 save: queued behind others, running")
    check(ln[3]["done"] and ln[3]["kind"] == "good" and ln[3]["text"].endswith("· import OK (job j1 ran)") and ln[3]["text"].startswith("Saved m.json at 1:12:03 AM"),
          "LE103 save: the job ran: import OK: %s" % ln[3]["text"])
    check(ln[4]["done"] and ln[4]["kind"] == "bad" and "IMPORT FAILED in job j1: SCRIPT ERROR" in ln[4]["text"], "LE103 save: the job failed, with its error: %s" % ln[4]["text"])
    check(ln[5]["done"] and "cancelled" in ln[5]["text"] and ln[6]["done"] and "no longer in the queue" in ln[6]["text"], "LE103 save: cancelled, gone")
    check("for " not in ln[7]["text"].split("held by sim lane")[1].split(";")[0], "LE103 save: another holder than the Save saw: no age claimed: %s" % ln[7]["text"])
    sv = re.search(r"  async function save\(\) \{(.*?)\n  \}\n", app, re.S)
    sb = sv.group(1) if sv else ""
    check("} finally {" in sb and "S.saving = false;" in sb.split("} finally {")[-1] and "ctl.abort()" in sb and "SAVE_TIMEOUT_MS" in sb and "updateTopBar();" in sb.split("try {")[1],
          "LE103 save: save() always ends: S.saving reset in finally, an abort after SAVE_TIMEOUT_MS, the top bar inside the try")
    check("rec.merged_into" in app and "setTimeout(step, 3000)" in app and "saveSeq !== token" in app, "LE103 save: the watch follows a merged job, polls every 3 s and stops at a new Save")


# ---------------------------------------------------------------- save (the server on temp copies)

class _FakeLocks:
    def __init__(self, real, held):
        self.real, self.held, self.timeouts = real, held, []

    def acquire(self, name, who, note="", timeout=None, log=None, **kw):
        self.timeouts.append((name, timeout))
        if self.held:
            return None

        class _L:
            def release(self_inner):
                pass
        return _L()

    def status(self, name=None):
        return {"who": "cli godot", "age_s": 4856} if self.held else None

    def keep_save(self):
        pass

    def restore_save(self):
        pass

    def __getattr__(self, k):
        return getattr(self.real, k)


class _FakeJobs:
    def __init__(self):
        self.jobs, self.calls = [], []

    def enqueue(self, kind, target, spec, title=None):
        j = {"id": "jT%03d" % (len(self.jobs) + 1), "kind": kind, "state": "queued", "spec": dict(spec), "target": target, "title": title or "",
             "lock_waits": {}}
        self.jobs.append(j)
        self.calls.append(("enqueue", kind, tuple(spec.get("targets") or [])))
        return dict(j)

    def list(self, since_rev=None):
        return {"rev": 1, "jobs": [dict(j) for j in self.jobs]}

    def get(self, job_id):
        for j in self.jobs:
            if j["id"] == job_id:
                return dict(j)
        return None


def _save_checks(check, server):
    tmp = tempfile.mkdtemp(prefix="le_le103_")
    names = ("CONTENT", "GODOT", "BACKUPS", "JOBS", "locks")
    saved = {k: getattr(server, k) for k in names}
    httpd = None
    try:
        content = os.path.join(tmp, "content")
        os.makedirs(os.path.join(content, "maps", "red_canyon"))
        src = server.map_path("red_canyon")
        dst = os.path.join(content, "maps", "red_canyon", "red_canyon.json")
        shutil.copy2(src, dst)
        fake_godot = os.path.join(tmp, "fake-godot.exe")
        open(fake_godot, "wb").close()
        server.CONTENT, server.GODOT, server.BACKUPS = content, fake_godot, os.path.join(tmp, "backups")
        os.makedirs(server.BACKUPS)
        fj = _FakeJobs()
        server.JOBS = fj
        fl = _FakeLocks(saved["locks"], True)
        server.locks = fl
        check(0 < server.SAVE_LOCK_WAIT <= 15, "LE103 save: a map Save waits %s s for the Godot lock" % server.SAVE_LOCK_WAIT)
        data = server.load_json(dst)
        t0 = time.time()
        r1 = server.write_map("red_canyon", json.loads(json.dumps(data)))
        check(r1["ok"] and r1["import_ok"] is None and r1["import_job"] == "jT001" and r1["import_joined"] is False and r1["lock"]["who"] == "cli godot"
              and r1["lock"]["age_s"] == 4856 and r1["lock"]["kind"] == "claude"
              and "an import job was queued instead (jT001)" in r1["output"] and time.time() - t0 < 10,
              "LE103 save: the lock held: written, the import queued, the holder and its age in the answer: %s" % {k: r1.get(k) for k in ("import_ok", "import_job", "lock", "output")})
        check(fl.timeouts[-1] == ("godot", server.SAVE_LOCK_WAIT), "LE103 save: write_map waits SAVE_LOCK_WAIT, not LOCK_WAIT: %s" % fl.timeouts)
        r2 = server.write_map("red_canyon", json.loads(json.dumps(data)))
        check(r2["import_job"] == "jT001" and r2["import_joined"] is True and len(fj.jobs) == 1 and "already queued" in r2["output"],
              "LE103 save: a second Save joins the queued import (no pile-up): %s %s" % (r2.get("output"), fj.calls))
        fj.jobs[0]["state"] = "running"
        r3 = server.write_map("red_canyon", json.loads(json.dumps(data)))
        check(r3["import_job"] == "jT002" and r3["import_joined"] is False and len(fj.jobs) == 2, "LE103 save: a running import is not joined (it may have read the file already): a new job: %s" % r3.get("output"))
        ok, out = server.run_import("maps/red_canyon")
        # (pass 114, lane EDITOR: every Save path waits SAVE_LOCK_WAIT, not LOCK_WAIT's two minutes)
        check(ok is None and "queued" in out and fl.timeouts[-1] == ("godot", server.SAVE_LOCK_WAIT), "LE103 save: run_import keeps its old answer and waits SAVE_LOCK_WAIT: %s %s" % (ok, fl.timeouts[-1]))
        server.locks = _FakeLocks(saved["locks"], False)
        r4 = server.write_map("red_canyon", json.loads(json.dumps(data)))
        check(r4["ok"] and r4["import_ok"] is False and r4["import_job"] is None and r4["lock"] is None and r4["output"].startswith(("could not run the import", "the import did not finish")),
              "LE103 save: the lock free, Godot not runnable: failed with the reason: %s" % r4.get("output"))
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        r5 = server.write_map("red_canyon", json.loads(json.dumps(data)))
        check(r5["import_ok"] is False and "Godot binary not found" in r5["output"], "LE103 save: no Godot binary: failed with the reason")
        # over HTTP: a Save from every stage window (an edit to one of its rows), the lock held
        server.GODOT = fake_godot
        server.locks = fl
        fj.jobs[:] = []
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        httpd.daemon_threads = True
        port = httpd.server_address[1]
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        tld = data["timeline_data"]
        lens = [float(e.get("length") or 0) for e in tld.get("stage_list") or [] if isinstance(e, dict)] or [float(tld.get("stage_length") or 300)]
        starts = [sum(lens[:i]) for i in range(len(lens))]
        done = 0
        for si, (a, ln) in enumerate(zip(starts, lens)):
            body = json.loads(json.dumps(data))
            rows = body["timeline_data"].get("roster") or []
            idx = next((i for i, r in enumerate(rows) if a <= float(r.get("t") or 0) < a + ln), None)
            if idx is None:
                continue
            rows[idx]["name"] = "p103 stage %d" % (si + 1)
            req = urllib.request.Request("http://127.0.0.1:%d/api/map/red_canyon" % port, data=json.dumps(body).encode("utf-8"), method="POST",
                                         headers={"Content-Type": "application/json"})
            t0 = time.time()
            try:
                with urllib.request.urlopen(req, timeout=30) as resp:
                    st, res = resp.status, json.loads(resp.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                st, res = e.code, {"raw": e.read().decode("utf-8", "replace")}
            took = time.time() - t0
            on_disk = server.load_json(dst)["timeline_data"]["roster"][idx].get("name")
            check(st == 200 and res.get("ok") and res.get("import_ok") is None and res.get("import_job") and took < 15 and on_disk == "p103 stage %d" % (si + 1),
                  "LE103 save: stage %d's Save over HTTP answers in %.1f s, written, the import queued: %s" % (si + 1, took, {k: res.get(k) for k in ("ok", "import_ok", "import_job", "import_joined")}))
            done += 1
        check(done >= 2 and len(fj.jobs) == 1, "LE103 save: %d stage Saves, one import job between them (the later ones join): %s" % (done, fj.calls))
        try:
            with urllib.request.urlopen("http://127.0.0.1:%d/api/job/%s" % (port, fj.jobs[0]["id"]), timeout=10) as resp:
                jb = json.loads(resp.read().decode("utf-8"))
        except Exception as e:  # noqa: BLE001
            jb = {"error": str(e)}
        check(jb.get("ok") and (jb.get("job") or {}).get("state") == "queued", "LE103 save: the page can follow the job at /api/job/<id>: %s" % jb)
    finally:
        if httpd is not None:
            httpd.shutdown()
            httpd.server_close()
        for k, v in saved.items():
            setattr(server, k, v)
        shutil.rmtree(tmp, ignore_errors=True)


def checks(check, run_node, server):
    before = _sha1(QUEUE)
    _node_checks(check, run_node, server)
    _save_checks(check, server)
    check(_sha1(QUEUE) == before, "LE103: tools/dl/jobs/queue.json untouched by these checks")
    md = open(os.path.join(ROOT, "docs", "level_editor.md"), encoding="utf-8").read()
    check("Pass 103" in md and "load" in md.split("Pass 103", 1)[1][:3000] and "swatch" in md.split("Pass 103", 1)[1][:3000],
          "LE103: docs/level_editor.md has the Pass 103 note (the cap's units, the swatches, the Save)")
