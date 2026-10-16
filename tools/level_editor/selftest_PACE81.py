"""Pass 81, lane PACE: a roster row's pacing and the yellow etches (Garry: "Add the ability to control the pacing of the
waves ... on top of the enemy node in the rows you should etch the yellow etches to show when the enemies will spawn. If
it's continuous (choose an option) it's shown as a continuous yellow line").

Groups: model.js's pacing maths under Node against the game's rule in Python (WaveTimeline.row_*: the wave seconds, the
etch seconds gated by the presence weight, a waves[] entry's burst seconds, the presence spans of the continuous line,
the thinning under 3 px, the count, the flags); fields.js (the Pacing select and its five waves-only fields with their
defaults and help; the global pacing's help in Settings -> Spawning; the roster lane's text names the etches); the
"Spawned so far" estimate with waves rows (model.js and the Python copy in selftest.py agree; hand-checked counts: a wave
off the cap brings its count at each wave and nothing between, a capped wave brings the room and its rest as room frees,
a presence of 0 holds a wave, a trickling row is drawn between its waves); the page's validation words in app.js; Red
Canyon's rows untouched by the lane (no row of the map file carries a pace the lane wrote).

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
INF = float("inf")

PACE_RUNNER = r"""
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
  out.times = q.times.map(([r, end]) => M.rowWaveTimes(r, end));
  out.etch = q.etch.map(([r, end, late]) => M.rowEtchTimes(r, end, late));
  out.bursts = q.bursts.map(([w, end]) => M.waveBurstTimes(w, end));
  out.spans = q.spans.map(([r, t0, t1, late]) => M.presenceSpans(r, t0, t1, late));
  out.thin = q.thin.map(([ts, d]) => M.thinTimes(ts, d));
  out.count = q.count.map(([r, c]) => M.rowWaveCount(r, c));
  out.flags = q.flags.map((r) => [M.rowPaced(r), M.rowDrawn(r), M.rowWaveEvery(r), M.rowWaveStart(r)]);
  out.consts = { paces: M.ROW_PACES, every: M.ROW_WAVE_EVERY_DEF, keys: M.ROW_WAVE_KEYS, px: M.ETCH_MIN_PX };
  out.fields = {
    roster: FIELDS.roster.map((d) => ({ key: d.key, label: d.label, type: d.type, def: d.def === undefined ? null : d.def, paced: !!d.paced, help: d.help || '', options: (d.options || []).map((o) => o.v) })),
    scalars: FIELDS.SCALARS.filter((d) => ['burst_min', 'burst_max', 'spawn_interval'].includes(d.key)).map((d) => ({ key: d.key, group: d.group, help: d.help })),
    lanes: FIELDS.LANES.filter((l) => l.id === 'roster' || l.id === 'waves').map((l) => ({ id: l.id, text: l.text })),
    paces: (FIELDS.PACES || []).map((o) => o.v),
  };
  const t0 = Date.now();
  out.est = q.est.map(([tl, cr, opts]) => { const e = M.spawnEstimate(tl, cr, opts); return { points: e.points, ids: e.ids, marks: e.marks, fights: e.fights, colourAt: e.colourAt }; });
  out.ms = Date.now() - t0;
  process.stdout.write(JSON.stringify(out));
});
"""


def _main_module():
    """selftest.py's own module (the Python copy of the estimate, roster_weight, the pacing helpers in Python)."""
    mod = sys.modules.get("__main__")
    if mod is not None and hasattr(mod, "spawn_estimate") and hasattr(mod, "row_wave_times_py"):
        return mod
    import selftest  # run on its own: the module beside it
    return selftest


def _close(a, b, eps=1e-9):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


def _same_list(a, b):
    return len(a) == len(b) and all(_close(x, y) for x, y in zip(a, b))


def wave_burst_times_py(w, end, limit=10000):
    """WaveDirector._tick_waves's burst seconds, room permitting: t + k x every until ceil(count / burst) or until."""
    t0 = float(w.get("t", 0) or 0)
    every = float(w.get("every", 0) or 0)
    burst = max(1, int(w.get("burst", 5)))
    count = int(w.get("count", 0) or 0)
    until = INF if w.get("until") in (None, "") else float(w["until"])
    n = min(math.ceil(count / burst) if count > 0 else INF, limit)
    out, k = [], 0
    while k < n:
        t = t0 + (k * every if every > 0 else 0)
        if t >= until or t > end:
            break
        out.append(t)
        if not every > 0:
            break
        k += 1
    return out


# a timeline with every kind of waves row, for the estimate (model.js against the Python copy)
EST_P_CR = [
    {"id": "a", "kind": "enemy", "archetype": "walker", "cap_share": 1.0, "pack_size": 5, "max_alive": 0, "variance": {"special_chance": 0.1}},
    {"id": "b", "kind": "enemy", "archetype": "runner", "cap_share": 0.5, "pack_size": 4, "max_alive": 0},
    {"id": "h", "kind": "enemy", "archetype": "runner", "cap_share": 0.6, "pack_size": 6},
    {"id": "m", "kind": "enemy", "archetype": "brute", "cap_share": 2.0, "pack_size": 1, "max_alive": 0},
    {"id": "bossy", "kind": "boss", "archetype": "boss", "cap_share": 1.0, "pack_size": 1},
]
EST_P_TL = {
    "stage_length": 200, "stages": 2, "cap_curve": [[0, 20], [100, 40]], "cap_max": 100, "hard_cap": 120, "burst_min": 4,
    "burst_max": 9, "spawn_interval": 0.5, "hell_cap": [0, 0.5], "colour_after_kills": 10, "events": [{"t": 200, "type": "boss", "enemy": "bossy"}],
    "roster": [
        {"id": "r1", "t": 0, "until": 150, "enemy": "a", "weights": [[0, 5], [60, 0], [70, 0], [80, 5]]},
        {"id": "r2", "t": 10, "until": 260, "enemy": "b", "weights": [[10, 2]], "pace": "waves", "every": 25, "count": 18},
        {"id": "r3", "t": 30, "enemy": "a", "weights": [[30, 1], [100, 1], [101, 0], [140, 0], [141, 1]], "pace": "waves", "every": 40, "count": 30, "respect_cap": False, "offset": 5},
        {"id": "r4", "t": 50, "until": 190, "enemy": "b", "weights": [[50, 3]], "pace": "waves", "every": 15, "trickle": True, "pack": 4},
        {"id": "r5", "t": 200, "enemy": "h", "weights": [[200, 2]], "pace": "waves", "every": 20, "count": 12, "channel": "hell"},
        {"id": "r6", "t": 0, "enemy": "m", "weights": [[0, 1]], "pace": "waves", "every": 0, "count": 9, "stats": {"max_alive": 5}},
    ],
}
# hand-checked: one row, nothing dies
EST_Q_CR = [{"id": "q", "kind": "enemy", "archetype": "walker", "cap_share": 1.0, "pack_size": 5, "max_alive": 0}]


def _q_tl(row, cap=10, extra=None):
    tl = {"stage_length": 100, "stages": 1, "cap_curve": [[0, cap]], "cap_max": 100, "hard_cap": 300, "burst_min": 10,
          "burst_max": 10, "spawn_interval": 0.5, "colour_after_kills": 0, "roster": [row]}
    tl.update(extra or {})
    return tl


def _src_at(est, t, key="roster:0"):
    pts = [p for p in est["points"] if p["t"] <= t + 1e-9]
    return pts[-1]["src"].get(key, 0.0) if pts else 0.0


def checks(check, run_node, server):
    st = _main_module()
    rnd = random.Random(81)
    # ---------------------------------------------------------------- the schedule's maths
    times_q, etch_q, burst_q, count_q, flag_q = [], [], [], [], []
    for _ in range(160):
        t = rnd.choice([0, 0, 13, 120.5, rnd.uniform(0, 900)])
        r = {"t": t, "enemy": "x", "pace": rnd.choice(["waves", "waves", "waves", "continuous", None, "WAVES"])}
        if r["pace"] is None:
            del r["pace"]
        ev = rnd.choice([None, -5, 0, 0.5, 7, 30, 61.5, rnd.uniform(1, 90)])
        if ev is not None:
            r["every"] = ev
        off = rnd.choice([None, 0, 13, -4, rnd.uniform(0, 50)])
        if off is not None:
            r["offset"] = off
        if rnd.random() < 0.6:
            r["until"] = t + rnd.uniform(1, 400)
        if rnd.random() < 0.7:
            # presence with gaps at 0
            pts, tt = [], t
            for _k in range(rnd.randint(1, 5)):
                pts.append([round(tt, 3), rnd.choice([0, 0, 1, 2.5, 6])])
                tt += rnd.uniform(1, 120)
            r["weights"] = pts
        else:
            r["weight"] = rnd.choice([0, 1, 4])
        if rnd.random() < 0.3:
            r["trickle"] = rnd.random() < 0.5
        end = rnd.choice([t + 200, 1500, rnd.uniform(0, 2000)])
        times_q.append([r, end])
        etch_q.append([r, end, 600])
        flag_q.append(r)
    for _ in range(60):
        w = {"t": rnd.uniform(0, 600), "every": rnd.choice([0, 1, 2, 2.5, 15]), "burst": rnd.choice([1, 3, 5, 10]), "count": rnd.choice([0, 7, 20, 100])}
        if rnd.random() < 0.5:
            w["until"] = w["t"] + rnd.uniform(1, 200)
        if rnd.random() < 0.2:
            del w["every"]
        burst_q.append([w, rnd.choice([w["t"] + 50, 2000])])
    c4 = {"pack_size": 4}
    count_q = [[{"count": 7}, c4], [{"pack": 3}, c4], [{"stats": {"pack": 6}}, c4], [{}, c4], [{"count": 0}, c4], [{"count": 2.9}, c4],
               [{"pack": 3, "stats": {"pack": 6}}, c4], [{}, None]]
    spans_q = [
        [{"t": 100, "until": 300, "weights": [[100, 5], [150, 0], [200, 0], [250, 3]]}, 100, 300, 600],
        [{"t": 0, "weight": 2}, 0, 500, 600],
        [{"t": 0, "weights": [[0, 0], [100, 0]]}, 0, 200, 600],
        [{"t": 0, "weights": [[0, 0], [60, 0], [61, 4]]}, 0, 120, 600],
        [{"t": 0, "weights": [[0, 3], [50, 3], [60, 0]]}, 0, 120, 600],
        [{"t": 10, "weight": 4, "weight_late": 0}, 10, 900, 600],
        [{"t": 5, "weights": [[5, 1]]}, 5, 5, 600],
    ]
    want_spans = [[[100, 150], [200, 300]], [[0, 500]], [], [[60, 120]], [[0, 60]], [[10, 600]], []]
    thin_q = [[list(range(11)), 3], [[0, 5, 10], 3], [[0, 1, 2, 3], 1], [[], 3], [[0, 2.9999999999, 6], 3]]
    want_thin = [([0, 3, 6, 9], True), ([0, 5, 10], False), ([0, 1, 2, 3], False), ([], False), ([0, 2.9999999999, 6], False)]
    # ---------------------------------------------------------------- the estimate with waves rows
    nothing_dies = {"turnover": 0, "end": 60}
    est_cases = [
        [EST_P_TL, EST_P_CR, {"turnover": 0.06, "bossSeconds": 15, "portalSeconds": 10, "boss": "bossy", "end": 330}],
        [EST_P_TL, EST_P_CR, {"turnover": 0, "bossSeconds": 15, "portalSeconds": 10, "boss": "bossy", "end": 330}],
        # 0: off the cap: 7 at each of the waves at 0, 10, 20, 30 (until 35), nothing between
        [_q_tl({"id": "r1", "t": 0, "until": 35, "enemy": "q", "weights": [[0, 1]], "pace": "waves", "every": 10, "count": 7, "respect_cap": False}), EST_Q_CR, nothing_dies],
        # 1: capped at 10, nothing dies: the first wave fills the room, the rest waits for room that never frees
        [_q_tl({"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 1]], "pace": "waves", "every": 20, "count": 25}), EST_Q_CR, nothing_dies],
        # 2: the same with a cap that grows to 16 at 5 s: the rest comes as the room grows
        [_q_tl({"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 1]], "pace": "waves", "every": 20, "count": 25}, extra={"cap_curve": [[0, 10], [4, 10], [5, 16]]}), EST_Q_CR, nothing_dies],
        # 3: presence 0 at the waves at 0 and 10: the first wave is the one at 20
        [_q_tl({"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 0], [10, 0], [11, 1]], "pace": "waves", "every": 10, "count": 4, "respect_cap": False}), EST_Q_CR, nothing_dies],
        # 4: a trickling waves row: its wave at 0 and the continuous draw fill the cap of 10 at once
        [_q_tl({"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 1]], "pace": "waves", "every": 30, "count": 3, "trickle": True}), EST_Q_CR, nothing_dies],
        # 5: the same row continuous (the reference: the cap of 10 filled by the draw)
        [_q_tl({"id": "r1", "t": 0, "enemy": "q", "weights": [[0, 1]]}), EST_Q_CR, nothing_dies],
    ]
    q = {"times": times_q, "etch": etch_q, "bursts": burst_q, "spans": spans_q, "thin": thin_q, "count": count_q, "flags": flag_q, "est": est_cases}
    res = run_node(q, PACE_RUNNER)
    if res is None:
        print("node not found: lane PACE's model.js checks are skipped")
        return
    if not res:
        return
    bad = [(a, g, st.row_wave_times_py(a[0], a[1])) for a, g in zip(times_q, res["times"]) if not _same_list(g, st.row_wave_times_py(a[0], a[1]))]
    check(not bad, "PACE: rowWaveTimes = WaveTimeline.row_wave_times on %d random rows: %s" % (len(times_q), bad[:2]))
    bad = []
    for (r, end, late), g in zip(etch_q, res["etch"]):
        want = [t for t in st.row_wave_times_py(r, end) if st.roster_weight(r, t, late) > 0]
        if not _same_list(g, want):
            bad.append((r, g, want))
    check(not bad, "PACE: rowEtchTimes = the wave seconds where the row weighs above 0 (WaveDirector's gate): %s" % bad[:2])
    some = sum(1 for (r, end, late), g in zip(etch_q, res["etch"]) if len(g) < len(st.row_wave_times_py(r, end)))
    check(some > 5, "PACE: the random rows include waves held back by a presence of 0 (%d rows)" % some)
    bad = [(w, g, wave_burst_times_py(w, e)) for (w, e), g in zip(burst_q, res["bursts"]) if not _same_list(g, wave_burst_times_py(w, e))]
    check(not bad, "PACE: waveBurstTimes = a waves[] entry's bursts (WaveDirector._tick_waves) on %d waves: %s" % (len(burst_q), bad[:2]))
    for (r, t0, t1, late), got, want in zip(spans_q, res["spans"], want_spans):
        check(len(got) == len(want) and all(_same_list(a, b) for a, b in zip(got, want)), "PACE: presenceSpans(%s, %s..%s): %s, want %s" % (r, t0, t1, got, want))
    for (ts, d), got, (wt, wth) in zip(thin_q, res["thin"], want_thin):
        check(_same_list(got["times"], wt) and got["thinned"] == wth, "PACE: thinTimes(%s, %s): %s, want %s %s" % (ts, d, got, wt, wth))
    check(res["count"] == [7, 3, 6, 4, 1, 2, 3, 1], "PACE: rowWaveCount: count, else the row's pack, else the creature's (after stats.pack), at least 1: %s" % res["count"])
    bad = []
    for r, (paced, drawn, every, start) in zip(flag_q, res["flags"]):
        want_p = st.row_paced_py(r)
        if paced != want_p or drawn != st.row_drawn_py(r) or not _close(every, st.row_wave_every_py(r)) or not _close(start, st.row_wave_start_py(r)):
            bad.append((r, [paced, drawn, every, start]))
    check(not bad, "PACE: rowPaced / rowDrawn / rowWaveEvery / rowWaveStart = WaveTimeline's: %s" % bad[:2])
    check(any(r.get("pace") == "WAVES" for r in flag_q) and all(not p for r, (p, _d, _e, _s) in zip(flag_q, res["flags"]) if r.get("pace") == "WAVES"),
          "PACE: only \"waves\" paces a row (\"WAVES\" plays continuous, as the game reads it)")
    c = res["consts"]
    # pass 84 (lane SPAWN, re-pinned on purpose): "once" joined the paces (WaveTimeline.ROW_PACES)
    check(c["paces"] == ["continuous", "waves", "once"] and c["every"] == 30 and c["keys"] == ["every", "count", "offset", "respect_cap", "trickle"] and c["px"] == 3,
          "PACE: the constants match WaveTimeline (ROW_PACES, ROW_WAVE_EVERY_DEFAULT 30) and the brief (3 px): %s" % c)
    # ---------------------------------------------------------------- fields.js
    fl = res["fields"]
    by = {d["key"]: d for d in fl["roster"]}
    keys = [d["key"] for d in fl["roster"]]
    check(all(k in by for k in ["pace", "every", "count", "offset", "respect_cap", "trickle"]), "PACE: fields.js has the row's Pacing and its five fields: %s" % keys)
    if all(k in by for k in ["pace", "every", "count", "offset", "respect_cap", "trickle"]):
        p = by["pace"]
        # pass 84 (lane TIMELINE, re-pinned on purpose): the row form's Pacing gained Once (INTERFACES.md)
        check(p["type"] == "select" and p["options"] == ["continuous", "waves", "once"] and p["def"] == "continuous" and not p["paced"] and fl["paces"] == ["continuous", "waves", "once"],
              "PACE: Pacing is a select Continuous / Waves / Once, Continuous by default, always shown: %s" % p)
        check("continuous yellow line" in p["help"] or "yellow line" in p["help"], "PACE: Pacing's help names the yellow line and ticks: %s" % p["help"][:120])
        # pass 84 (lane TIMELINE, re-pinned on purpose): Every may be [min, max] (an interval box)
        want = {"every": ("interval", 30), "count": ("int", None), "offset": ("number", 0), "respect_cap": ("bool", True), "trickle": ("bool", False)}
        for k, (typ, dflt) in want.items():
            d = by[k]
            check(d["paced"] and d["type"] == typ and d["def"] == dflt and len(d["help"]) > 40, "PACE: %s is a waves-only %s field, default %s, with help: %s" % (k, typ, dflt, d))
        check(keys.index("pace") > keys.index("pattern") and keys.index("trickle") < keys.index("variant"), "PACE: the pacing fields sit after Pattern, before Art variant: %s" % keys)
        check("only switches its waves on and off" in by["weights"]["help"], "PACE: Presence's help says what a waves row's weight does")
    sc = {d["key"]: d for d in fl["scalars"]}
    check(set(sc) == {"burst_min", "burst_max", "spawn_interval"} and all(d["group"] == "Spawning" for d in sc.values()),
          "PACE: the global pacing (Burst min / max, Spawn check every) is in Settings -> Spawning: %s" % list(sc))
    check("continuous rows' pacing" in sc.get("burst_min", {}).get("help", "") and "own clock" in sc.get("spawn_interval", {}).get("help", ""),
          "PACE: their help says they pace the continuous rows, a waves row keeps its own clock")
    lanes = {l["id"]: l["text"] for l in fl["lanes"]}
    check("yellow etches" in lanes.get("roster", "") and "3 px" in lanes.get("roster", "") and "yellow tick" in lanes.get("waves", ""),
          "PACE: the Roster and Waves lanes' help names the etches and the thinning")
    # ---------------------------------------------------------------- the estimate
    names = ["every kind of waves row", "every kind, nothing dies", "off the cap", "capped", "capped, the cap grows", "presence 0", "trickle", "continuous"]
    import time
    t0 = time.time()
    pys = [st.spawn_estimate(tl, cr, opts) for tl, cr, opts in est_cases]
    print("lane PACE: the estimate with waves rows: model.js %d ms, the Python copy %.1f s" % (res["ms"], time.time() - t0))
    for name, js, py in zip(names, res["est"], pys):
        diff = st.estimate_diff(js, py)
        check(not diff, "PACE: the estimate of %s: model.js and the Python copy agree: %s" % (name, diff[:4]))
    e = res["est"]
    off = [_src_at(e[2], t) for t in (1, 5, 9.95, 11, 25, 31, 59)]
    check(all(_close(a, b) for a, b in zip(off, [7, 7, 7, 14, 21, 28, 28])), "PACE: a wave off the cap: 7 at 0, 10, 20 and 30 (until 35), nothing between (the 0:00 point is before the first tick): %s" % off)
    cap = [_src_at(e[3], t) for t in (1, 10, 19.95, 21, 59)]
    check(all(_close(a, b) for a, b in zip(cap, [10, 10, 10, 10, 10])), "PACE: a capped wave of 25 under a cap of 10, nothing dies: the room only: %s" % cap)
    grow = [_src_at(e[4], t) for t in (1, 4, 6, 7, 59)]
    check(all(_close(a, b) for a, b in zip(grow, [10, 10, 16, 16, 16])), "PACE: the cap grows from 10 to 16 between 4 and 5 s: the wave's rest takes the room: %s" % grow)
    held = [_src_at(e[5], t) for t in (1, 11, 19.95, 21, 31)]
    check(all(_close(a, b) for a, b in zip(held, [0, 0, 0, 4, 8])), "PACE: presence 0 holds the waves at 0 and 10, then 4 a wave: %s" % held)
    tr, co = _src_at(e[6], 1), _src_at(e[7], 1)
    check(_close(tr, 10) and _close(co, 10), "PACE: a trickling waves row fills the cap like a continuous one: %s / %s" % (tr, co))
    a_src = [(p["t"], p["src"].get("roster:2", 0)) for p in e[1]["points"] if p["t"] in (34, 35, 36, 74, 75, 115, 116, 155)]
    check(len(a_src) >= 6 and _close(dict(a_src).get(34, -1), 0) and _close(dict(a_src).get(35, -1), 30) and _close(dict(a_src).get(75, -1), 60)
          and _close(dict(a_src).get(115, -1), 60) and dict(a_src).get(155, -1) > 60,
          "PACE: the every-kind timeline, nothing dies: r3 brings 30 off the cap at 35 and 75, none at 115 (its presence is 0), more at 155 (the hard cap may cut it): %s" % a_src)
    once = [p["src"].get("roster:5", 0) for p in e[1]["points"] if p["t"] in (1, 100, 300)]
    check(len(once) == 3 and all(_close(x, 5) for x in once), "PACE: every 0 = one wave, cut to max_alive 5: %s" % once)
    # ---------------------------------------------------------------- app.js / inspector.js / timeline.js words
    app = open(os.path.join(HERE, "app.js"), encoding="utf-8").read()
    for frag in ["unknown pacing", "every must be 0 (one wave) or more seconds", "is over the hard cap", "never spawns", "nothing on a continuous row"]:
        check(frag in app, "PACE: app.js's validation says \"%s\"" % frag)
    tlj = open(os.path.join(HERE, "timeline.js"), encoding="utf-8").read()
    check("rowEtches(inner, r, t, tEnd, y0 + bh)" in tlj and "waveEtches(inner, wv" in tlj and "Model.ETCH_MIN_PX * spp" in tlj,
          "PACE: timeline.js etches every roster bar and every waves block, thinned by the zoom")
    insp = open(os.path.join(HERE, "inspector.js"), encoding="utf-8").read()
    check("if (def.paced && !Model.rowPaced(r)) continue;" in insp and "for (const k of Model.ROW_WAVE_KEYS) delete r[k];" in insp,
          "PACE: the row form shows the waves-only fields only for a waves row, and Continuous drops them")
    # ---------------------------------------------------------------- Red Canyon untouched
    rc = server.load_json(server.map_path("red_canyon"))
    rows = (rc.get("timeline_data") or {}).get("roster") or []
    stray = [r.get("id") for r in rows if isinstance(r, dict) and any(k in r for k in ("pace", "every", "count", "offset", "respect_cap", "trickle")) and not r.get("pace")]
    check(not stray, "PACE: no Red Canyon row carries a waves-only key without a pace: %s" % stray)
    print("lane PACE: pacing maths, fields, estimate and validation checked (%d random rows, %d waves)" % (len(times_q), len(burst_q)))
