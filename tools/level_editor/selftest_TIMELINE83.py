"""Pass 83, lane TIMELINE: what the Timeline shows about who spawns (Garry: "I'd expect that if I hover over enemies and
specifically over those yellow notches it actually shows the % of enemies that will be spawning. And for Continuous
spawning, I would still like to control the interval of continuous spawning, the 0.7s can be a default. And since
continuous spawning has these inevitable intervals the notches on the enemy node should reflect that ... the highlight
actually just shows the share of roster draw as the % of enemies that spawned in the past 5 seconds (controllable value
next to 'snap on') with a hint explaining that that value is. Remove the 'Share section'").

Groups: model.js's own-interval maths against the game's rule in Python (WaveDirector.row_has_interval /
row_draw_interval, the draw seconds a continuous row's notches mark); the Spawned so far estimate with own-interval rows
(model.js and the Python copy in selftest.py agree on a mixed fixture of continuous rows with and without intervals,
waves rows and waves[] blocks; hand-checked counts: a row on its own clock draws at its start and every interval, the
spawn check's rhythm with the key equal to it keeps the shares, half the interval doubles what the row brings, the
burst is cut to the row's share of the weight); windowShares (the past N seconds: each row's and wave's spawns and share,
the rest as "other", against the estimate's points in Python); fields.js (the Draw every field, the help, the Share lane
gone); the page's words (timeline.js, index.html's window box, inspector.js, app.js's validation); Red Canyon's rows
untouched by the lane (no `interval` written).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import math
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
INF = float("inf")

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const M = require(process.argv[2]);
const dir = path.dirname(process.argv[2]);
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.flags = q.flags.map((r) => [M.rowHasInterval(r), M.rowDrawInterval(r, 0.7)]);
  out.draws = q.draws.map(([r, t0, t1, si, late]) => M.rowDrawTimes(r, t0, t1, si, late));
  out.min = M.ROW_INTERVAL_MIN;
  out.est = q.est.map(([tl, cr, opts]) => { const e = M.spawnEstimate(tl, cr, opts); return { points: e.points, ids: e.ids, marks: e.marks, fights: e.fights, colourAt: e.colourAt }; });
  out.win = q.win.map(([k, t0, t1]) => { const e = out.est[k]; return M.windowShares(e, t0, t1); });
  out.fields = {
    roster: FIELDS.roster.map((d) => ({ key: d.key, label: d.label, type: d.type, min: d.min == null ? null : d.min, drawn: !!d.drawn, paced: !!d.paced, help: d.help || '' })),
    si: (FIELDS.SCALARS.find((d) => d.key === 'spawn_interval') || {}).help || '',
    lanes: FIELDS.LANES.map((l) => ({ id: l.id, text: l.text })),
  };
  process.stdout.write(JSON.stringify(out));
});
"""


def _main_module():
    mod = sys.modules.get("__main__")
    if mod is not None and hasattr(mod, "spawn_estimate") and hasattr(mod, "row_has_interval_py"):
        return mod
    import selftest  # run on its own: the module beside it
    return selftest


def _close(a, b, eps=1e-9):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


def _same_list(a, b):
    return len(a) == len(b) and all(_close(x, y) for x, y in zip(a, b))


def row_draw_times_py(st, r, t0, t1, si, late, limit=20000):
    """The draw seconds of a drawn row (WaveDirector: its own clock from its start every interval, else the spawn
    check's rhythm k x spawn_interval from 0:00), before its until and where it weighs above 0."""
    out = []
    if not isinstance(r, dict) or not st.row_drawn_py(r):
        return out
    iv = st.row_draw_interval_py(r, si)
    if not iv > 0:
        return out
    start = float(r.get("t", 0) or 0)
    until = INF if r.get("until") in (None, "") else float(r["until"])
    base = start if st.row_has_interval_py(r) else 0.0
    lo, hi = max(t0, start), min(t1, until)
    k = max(0, math.ceil((lo - base) / iv - 1e-9))
    while len(out) < limit:
        t = base + k * iv
        if t > hi or t >= until:
            break
        if st.roster_weight(r, t, late) > 0:
            out.append(t)
        k += 1
    return out


def _point_at(est, t):
    pts = est["points"]
    if t < pts[0]["t"]:
        return pts[0]
    best = pts[0]
    for p in pts:
        if p["t"] <= t:
            best = p
        else:
            break
    return best


def window_py(est, t0, t1):
    a, b = _point_at(est, t0), _point_at(est, t1)
    all_n = max(b["all"] - a["all"], 0)
    src = {}
    for k, v in b["src"].items():
        n = max(v - a["src"].get(k, 0), 0)
        if n > 1e-9:
            src[k] = n
    return {"all": all_n, "src": src, "other": max(all_n - sum(src.values()), 0)}


# the creatures: one plain walker for the hand counts, a mix for the agreement
CR = [
    {"id": "q", "kind": "enemy", "archetype": "walker", "cap_share": 1.0, "pack_size": 1, "max_alive": 0},
    {"id": "a", "kind": "enemy", "archetype": "walker", "cap_share": 1.0, "pack_size": 5, "max_alive": 0, "variance": {"special_chance": 0.1}},
    {"id": "b", "kind": "enemy", "archetype": "runner", "cap_share": 0.5, "pack_size": 4, "max_alive": 0},
    {"id": "h", "kind": "enemy", "archetype": "runner", "cap_share": 0.6, "pack_size": 6},
    {"id": "m", "kind": "enemy", "archetype": "brute", "cap_share": 2.0, "pack_size": 1, "max_alive": 4},
    {"id": "bossy", "kind": "boss", "archetype": "boss", "cap_share": 1.0, "pack_size": 1},
]
# the mixed fixture: continuous rows with and without their own interval (one below the least, one hell, one with
# max_alive, one starting late), waves rows (one trickling with an interval, one not trickling with a stray interval),
# waves[] blocks, a swarm, a boss
MIX_TL = {
    "stage_length": 200, "stages": 2, "cap_curve": [[0, 20], [100, 40]], "cap_max": 100, "hard_cap": 120, "burst_min": 4,
    "burst_max": 9, "spawn_interval": 0.7, "hell_cap": [0, 0.5], "colour_after_kills": 10,
    "events": [{"t": 60, "type": "swarm", "enemy": "b", "count": 12}, {"t": 200, "type": "boss", "enemy": "bossy"}],
    "roster": [
        {"id": "r1", "t": 0, "until": 150, "enemy": "a", "weights": [[0, 5], [60, 0], [70, 0], [80, 5]]},
        {"id": "r2", "t": 0, "until": 180, "enemy": "b", "weights": [[0, 2]], "interval": 2.5},
        {"id": "r3", "t": 20, "enemy": "a", "weights": [[20, 1]], "interval": 0.05},
        {"id": "r4", "t": 40, "until": 190, "enemy": "b", "weights": [[40, 3]], "pace": "waves", "every": 15, "trickle": True, "interval": 1.4, "pack": 4},
        {"id": "r5", "t": 10, "until": 260, "enemy": "b", "weights": [[10, 2]], "pace": "waves", "every": 25, "count": 18, "interval": 3},
        {"id": "r6", "t": 200, "enemy": "h", "weights": [[200, 2]], "channel": "hell", "interval": 1.1},
        {"id": "r7", "t": 200, "enemy": "h", "weights": [[200, 1]], "channel": "hell"},
        {"id": "r8", "t": 30, "enemy": "m", "weights": [[30, 1]], "interval": 0.7, "pattern": "single"},
    ],
    "waves": [
        {"id": "w1", "t": 15, "count": 12, "burst": 4, "every": 3,
         "alts": [{"chance": 0.75, "enemy": "a", "pack": 4}, {"chance": 0.25, "enemy": "b"}]},
        {"id": "w2", "t": 90, "until": 110, "burst": 6, "every": 5, "respect_cap": False, "enemy": "m"},
    ],
}
MIX_OPTS = {"turnover": [0.06, 0.08], "bossSeconds": 15, "portalSeconds": 10, "boss": "bossy", "end": 330}
NOTHING_DIES = {"turnover": 0, "end": 30}


def _tl(rows, cap=1000, lo=8, hi=8, si=0.7, extra=None):
    tl = {"stage_length": 100, "stages": 1, "cap_curve": [[0, cap]], "cap_max": 2000, "hard_cap": 2000, "burst_min": lo,
          "burst_max": hi, "spawn_interval": si, "colour_after_kills": 0, "roster": rows}
    tl.update(extra or {})
    return tl


def _src_at(est, t, key):
    return _point_at(est, t)["src"].get(key, 0.0)


def checks(check, run_node, server):
    st = _main_module()
    rnd = random.Random(83)
    # ---------------------------------------------------------------- the key and the draw seconds
    flag_q = [{}, {"interval": 0}, {"interval": -1}, {"interval": "2"}, {"interval": True}, {"interval": None}, {"interval": 2},
              {"interval": 0.05}, {"interval": 0.7}, {"interval": 12.5}]
    draw_q = []
    for _ in range(140):
        t = rnd.choice([0, 0, 13, 120.5, rnd.uniform(0, 900)])
        r = {"t": t, "enemy": "x"}
        if rnd.random() < 0.6:
            r["interval"] = rnd.choice([0.05, 0.35, 0.7, 1.3, 2, 5, rnd.uniform(0.1, 9), 0, -2, "3"])
        if rnd.random() < 0.3:
            r["pace"] = "waves"
            r["every"] = 20
            if rnd.random() < 0.5:
                r["trickle"] = True
        if rnd.random() < 0.6:
            r["until"] = t + rnd.uniform(1, 300)
        if rnd.random() < 0.6:
            pts, tt = [], t
            for _k in range(rnd.randint(1, 4)):
                pts.append([round(tt, 3), rnd.choice([0, 0, 1, 3])])
                tt += rnd.uniform(1, 80)
            r["weights"] = pts
        else:
            r["weight"] = rnd.choice([0, 1, 4])
        t0 = rnd.choice([0, t, t + rnd.uniform(0, 50)])
        draw_q.append([r, t0, t0 + rnd.choice([10, 60, 400]), rnd.choice([0.5, 0.7]), 600])
    # ---------------------------------------------------------------- the estimate
    est_cases = [
        [MIX_TL, CR, MIX_OPTS],
        # 1: one row on its own clock (2 s), a burst of 4, nothing dies: 4 at its start and every 2 s
        [_tl([{"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 1]], "interval": 2}], lo=4, hi=4), CR, NOTHING_DIES],
        # 2: two rows by weight 3 : 1 at the spawn check (the reference)
        [_tl([{"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 3]]}, {"id": "r2", "t": 0, "enemy": "q", "weights": [[0, 1]]}]), CR, NOTHING_DIES],
        # 3: the same with the second on its own clock at the spawn check's 0.7 s: the same counts
        [_tl([{"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 3]]}, {"id": "r2", "t": 0, "enemy": "q", "weights": [[0, 1]], "interval": 0.7}]), CR, NOTHING_DIES],
        # 4: the second at 0.35 s: twice its creatures, the first's unchanged
        [_tl([{"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 3]]}, {"id": "r2", "t": 0, "enemy": "q", "weights": [[0, 1]], "interval": 0.35}]), CR, NOTHING_DIES],
        # 5: a row starting at 5.0 with its own 3 s clock: draws at 5, 8, 11 ...
        [_tl([{"id": "r1", "t": 5, "enemy": "q", "weights": [[5, 1]], "interval": 3}], lo=2, hi=2), CR, NOTHING_DIES],
        # 6: an interval on a closed row changes nothing against case 2
        [_tl([{"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 3]]}, {"id": "r2", "t": 0, "enemy": "q", "weights": [[0, 1]]},
              {"id": "r3", "t": 500, "enemy": "q", "weights": [[500, 1]], "interval": 0.2}]), CR, NOTHING_DIES],
    ]
    win_q = []
    for _ in range(60):
        t1 = rnd.uniform(0, 330)
        win_q.append([0, t1 - rnd.choice([1, 5, 10, 30]), t1])
    win_q += [[0, -5, 0], [0, 55, 65], [0, 195, 205]]
    q = {"flags": flag_q, "draws": draw_q, "est": est_cases, "win": win_q}
    res = run_node(q, RUNNER)
    if res is None:
        print("node not found: lane TIMELINE's model.js checks are skipped")
        return
    if not res:
        return
    want_flags = [[False, 0.7], [False, 0.7], [False, 0.7], [False, 0.7], [False, 0.7], [False, 0.7], [True, 2], [True, 0.1], [True, 0.7], [True, 12.5]]
    check(all(g[0] == w[0] and _close(g[1], w[1]) for g, w in zip(res["flags"], want_flags)),
          "TIMELINE83: rowHasInterval / rowDrawInterval read like WaveDirector (a number above 0; '2', true, 0 and -1 are none; under 0.1 counts as 0.1): %s" % res["flags"])
    check(all((g[0], round(g[1], 9)) == (st.row_has_interval_py(r), round(st.row_draw_interval_py(r, 0.7), 9)) for g, r in zip(res["flags"], flag_q)),
          "TIMELINE83: the Python copy reads the key the same way")
    wd = open(os.path.join(REPO, "game", "core", "systems", "WaveDirector.gd"), encoding="utf-8").read()
    check(_close(res["min"], 0.1) and "const ROW_INTERVAL_MIN := 0.1" in wd, "TIMELINE83: the least interval is the game's (WaveDirector.ROW_INTERVAL_MIN 0.1): %s" % res["min"])
    check("func _tick_row_intervals(delta: float)" in wd and "_tick_row_intervals(delta)" in wd and "func _interval_part(" in wd,
          "TIMELINE83: WaveDirector ticks the own-interval rows every frame and cuts the burst to their share")
    bad = []
    for (r, t0, t1, si, late), got in zip(draw_q, res["draws"]):
        want = row_draw_times_py(st, r, t0, t1, si, late)
        if not _same_list(got, want):
            bad.append((r, t0, t1, si, got[:5], want[:5]))
    check(not bad, "TIMELINE83: rowDrawTimes = the game's draw seconds (own clock from the start, else k x spawn_interval), gated by the weight, on %d random rows: %s" % (len(draw_q), bad[:2]))
    some = sum(1 for g in res["draws"] if len(g) > 3)
    check(some > 30, "TIMELINE83: the random rows draw (%d with more than 3 draws)" % some)
    # ---------------------------------------------------------------- the estimate: model.js against the Python copy
    import time
    t0 = time.time()
    pys = [st.spawn_estimate(tl, cr, opts) for tl, cr, opts in est_cases]
    print("lane TIMELINE: the estimate with own-interval rows: the Python copy %.1f s" % (time.time() - t0))
    names = ["the mixed fixture", "one row every 2 s", "3:1 at the check", "3:1, its own 0.7 s", "3:1, its own 0.35 s", "from 5 s every 3 s", "a closed row's interval"]
    for name, js, py in zip(names, res["est"], pys):
        diff = st.estimate_diff(js, py)
        check(not diff, "TIMELINE83: the estimate of %s: model.js and the Python copy agree: %s" % (name, diff[:4]))
    e = res["est"]
    mix_keys = set()
    for p in e[0]["points"]:
        mix_keys |= set(p["src"])
    check({"roster:1", "roster:2", "roster:3", "roster:4", "roster:5", "roster:7", "wave:0:0", "wave:1:0"} <= mix_keys,
          "TIMELINE83: the mixed fixture spawns from its own-interval rows, its waves rows and its waves[] blocks: %s" % sorted(mix_keys))
    one = [_src_at(e[1], t, "roster:0") for t in (1, 2, 3, 10, 29)]
    check(all(_close(a, b) for a, b in zip(one, [4, 4, 8, 20, 60])), "TIMELINE83: a row on its own 2 s clock (burst 4): 4 at its start, then 4 every 2 s: %s" % one)
    ref = (_src_at(e[2], 29, "roster:0"), _src_at(e[2], 29, "roster:1"))
    same = (_src_at(e[3], 29, "roster:0"), _src_at(e[3], 29, "roster:1"))
    half = (_src_at(e[4], 29, "roster:0"), _src_at(e[4], 29, "roster:1"))
    check(_close(ref[0], 3 * ref[1]) and ref[1] > 50, "TIMELINE83: the reference draws 3 : 1 by weight: %s" % (ref,))
    check(_close(same[0], ref[0]) and _close(same[1], ref[1]), "TIMELINE83: its own clock at the spawn check's 0.7 s brings what the spawn check did, the other row unchanged: %s vs %s" % (same, ref))
    check(_close(half[0], ref[0]) and abs(half[1] / ref[1] - 2) < 0.03, "TIMELINE83: half the interval brings about twice (%s vs %s), the other row unchanged" % (half, ref))
    late = [_src_at(e[5], t, "roster:0") for t in (4.9, 5.1, 7.9, 8.1, 11.1)]
    check(all(_close(a, b) for a, b in zip(late, [0, 0, 2, 4, 6])) or all(_close(a, b) for a, b in zip(late, [0, 2, 2, 4, 6])),
          "TIMELINE83: from 5 s every 3 s, 2 a draw (points a second apart): %s" % late)
    check(all(_close(p2["all"], p6["all"]) for p2, p6 in zip(e[2]["points"], e[6]["points"])), "TIMELINE83: an interval on a row that never opens changes nothing")
    # ---------------------------------------------------------------- the window's shares
    bad = []
    for (k, a, b), got in zip(win_q, res["win"]):
        want = window_py(e[k], a, b)
        ok = got is not None and _close(got["all"], want["all"]) and set(got["src"]) == set(want["src"]) and all(_close(got["src"][x], want["src"][x]) for x in want["src"]) \
            and _close(got["other"], want["other"]) and all(_close(got["share"][x], (want["src"][x] / want["all"]) if want["all"] > 0 else 0) for x in want["src"])
        if not ok:
            bad.append(((a, b), got and {kk: got[kk] for kk in ("all", "other")}, {kk: want[kk] for kk in ("all", "other")}))
    check(not bad, "TIMELINE83: windowShares = the estimate's spawns between the window's points, each row's share of all, the rest as other (%d windows): %s" % (len(win_q), bad[:2]))
    sw = res["win"][-2]
    check(sw and sw["other"] > 5, "TIMELINE83: the swarm at 60 s lands in the window's other (swarms, Elites, specials, bosses): %s" % (sw and sw["other"]))
    sums = [w for w in res["win"] if w and w["all"] > 0 and abs(sum(w["share"].values()) + w["other"] / w["all"] - 1) > 1e-9]
    check(not sums, "TIMELINE83: the rows' and waves' shares and the other add up to everything spawned in the window: %s" % sums[:1])
    # ---------------------------------------------------------------- fields.js
    fl = res["fields"]
    by = {d["key"]: d for d in fl["roster"]}
    keys = [d["key"] for d in fl["roster"]]
    iv = by.get("interval")
    check(iv is not None and iv["type"] == "number" and iv["drawn"] and not iv["paced"] and _close(iv["min"], 0.1) and iv["label"] == "Draw every (s)",
          "TIMELINE83: the row form has Draw every (s), a number from 0.1, shown while the row is drawn: %s" % iv)
    if iv:
        check("spawn check" in iv["help"] and "0.7" in iv["help"] and "own clock" in iv["help"] and "share" in iv["help"] and "3 px" in iv["help"],
              "TIMELINE83: its help says what the game does (the spawn check by default, its own clock, the burst cut to its share, the ticks)")
        check(keys.index("interval") > keys.index("trickle") and keys.index("interval") < keys.index("variant"), "TIMELINE83: Draw every sits after the pacing fields: %s" % keys)
    check("Draw every" in fl["si"], "TIMELINE83: Spawn check every's help names a row's own Draw every")
    lane_ids = [l["id"] for l in fl["lanes"]]
    roster_text = {l["id"]: l["text"] for l in fl["lanes"]}.get("roster", "")
    check("share" not in lane_ids, "TIMELINE83: the Share lane is gone from FIELDS.LANES: %s" % lane_ids)
    check("yellow etches" in roster_text and "3 px" in roster_text and "past N seconds" in roster_text and "each draw" in roster_text,
          "TIMELINE83: the Roster lane's help names the draw ticks and the past N seconds")
    # ---------------------------------------------------------------- the page's words
    tlj = open(os.path.join(HERE, "timeline.js"), encoding="utf-8").read()
    check("renderShare" not in tlj and "shareCard" not in tlj and "lanes.share" not in tlj and "'share', 'Share'" not in tlj,
          "TIMELINE83: timeline.js draws no Share lane any more")
    for frag in ["Model.rowDrawTimes(r, a, b, si, lateT)", "etch-dots", "Model.windowShares(est", "const WIN_DEF = 5", "function readoutShares(t)",
                 "function etchCard(i, t)", "function burstCard(i, t)", "function lightRows(t)", "win-zero", "WIN_HELP"]:
        check(frag in tlj, "TIMELINE83: timeline.js has %s" % frag)
    html = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
    i_snap, i_win = html.find('id="snap-toggle"'), html.find('id="win-secs"')
    check(0 < i_snap < i_win and html.find('id="zoom-out"') > i_win, "TIMELINE83: the window box sits right after Snap on, before the zoom")
    m = re.search(r'<label class="win-box" title="([^"]+)"', html)
    check(bool(m) and "N seconds" in m.group(1) and "Spawned so far" in m.group(1), "TIMELINE83: the window box carries its hint")
    insp = open(os.path.join(HERE, "inspector.js"), encoding="utf-8").read()
    # pass 110 (lane BOSS): intervalNote(r, env) takes a boss fight window row too
    check("shareForm" not in insp and "if (def.drawn && !Model.rowDrawn(r)) continue;" in insp and "function intervalNote(r" in insp,
          "TIMELINE83: inspector.js: no Share table; Draw every only on a drawn row, with its note")
    app = open(os.path.join(HERE, "app.js"), encoding="utf-8").read()
    for frag in ["draw every must be a number of seconds above 0", "draw every means nothing on a row paced as waves", "over 4× as often as the spawn check"]:
        check(frag in app, "TIMELINE83: app.js's validation says \"%s\"" % frag)
    css = open(os.path.join(HERE, "style.css"), encoding="utf-8").read()
    check(".share-area" not in css and ".etch-draw" in css and ".bar.win-zero" in css, "TIMELINE83: style.css: the Share lane's rules gone, the draw ticks and the highlight in")
    # ---------------------------------------------------------------- Red Canyon untouched
    rc = server.load_json(server.map_path("red_canyon"))
    rows = (rc.get("timeline_data") or {}).get("roster") or []
    with_iv = [r.get("id") for r in rows if isinstance(r, dict) and "interval" in r]
    print("lane TIMELINE: Red Canyon rows with their own interval: %s" % (with_iv or "none"))
    print("lane TIMELINE: interval maths, estimate, window, fields and page words checked (%d random rows, %d windows)" % (len(draw_q), len(win_q)))
