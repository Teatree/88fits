# -*- coding: utf-8 -*-
"""Pass 124: the Stage 2 performance report for Garry -> docs/perf/stage2_slowdown.html, charts drawn from his run record
(analytics/remote/Hungry_Outlaw_94/2026-11-04T14-57-42_01a1a6a3.json) and the PC probes (tools/dl/p124/LEAD/probes.txt).
Pass 125: updated with his Stage 1 run of the same evening (RUN1), its replay's frames (REPLAY1: each frame's delta and
world steps) and the same replay played on the PC with its script work measured second by second (PC1), made by:

    GODOT_TIMEOUT=1500 bash tools/godot.sh --audio-driver Dummy --fixed-fps 64 --disable-vsync --resolution 504x1122 \
      --path D:/_projects/88fits/game --script res://tools/_p125_PERF_replay.gd -- mode=replay assist=1 \
      file=<REPLAY1> out=tools/dl/p125/PERF/probe_full_report.json perf_out=<PC1> res=504x1122

    python tools/posthog_runs.py --player "Hungry Outlaw 94" --since 2026-11-04   (the runs and replays, if missing)
    python tools/make_perf_report.py
"""
import base64
import gzip
import html
import json
import os
import statistics as st
import struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
RUN = os.path.join(ROOT, "analytics", "remote", "Hungry_Outlaw_94", "2026-11-04T14-57-42_01a1a6a3.json")
OUT = os.path.join(ROOT, "docs", "perf", "stage2_slowdown.html")
# pass 125: Garry's Stage 1 run of the same evening (Drifter, 13:06, into Endless), its replay (every frame's delta and
# world steps), the same run replayed on the PC (tools/dl/p125/PERF: the run record that replay wrote, its samples), and
# the earlier long runs the slow windows are counted in
REMOTE = os.path.join(ROOT, "analytics", "remote", "Hungry_Outlaw_94")
RUN1 = os.path.join(REMOTE, "2026-11-04T19-26-26_01a1a799.json")
REPLAY1 = os.path.join(REMOTE, "replays", "20261104_192627_replay.json")
PC1 = os.path.join(ROOT, "tools", "dl", "p125", "PERF", "pc_replay_record.json")
WINDOW_RUNS = [("27 Oct", "Stage 1", "2026-10-27T19-42-14_01a17e74.json"), ("31 Oct", "Stage 2", "2026-10-31T19-58-57_01a1931d.json"),
               ("4 Nov, afternoon", "Stage 2", "2026-11-04T14-57-42_01a1a6a3.json"), ("4 Nov, evening", "Stage 1", "2026-11-04T19-26-26_01a1a799.json")]
# Stage 1's phases in this run (run seconds): the stage, the King's fight, the portal's minute, Endless
PHASES1 = [(0, 430, "Stage 1"), (430, 667, "Boss fight"), (667, 727, "Portal"), (727, 786, "Endless")]

C_STEP = "#f5b82a"
C_PROC = "#4a8ae0"
C_REST = "#5b6780"
C_CROWD = "#ff6b6b"
C_INK = "#e9eefb"
C_DIM = "#9aa7c4"
C_GRID = "#2a3552"
C_OK = "#5fc43a"


def timeline(samples):
    """The frame stacked by what took it, ten-second-free: three second means; the crowd on its own scale."""
    W, H = 900, 380
    L, R, T, B = 52, 56, 24, 40
    pts = []
    for i in range(0, len(samples), 2):
        w = samples[i:i + 2]
        def m(k):
            v = [x[k] for x in w if isinstance(x.get(k), (int, float))]
            return st.mean(v) if v else 0.0
        fr = max(m("frames"), 1.0)
        step = m("steps") * m("phys_ms") / fr
        proc = m("proc_ms")
        frame = m("frame_ms")
        rest = max(frame - step - proc, 0.0)
        pts.append((m("t"), step, proc, rest, m("alive")))
    tmax = 184.0
    ymax = 45.0
    cmax = 350.0
    X = lambda t: L + (W - L - R) * t / tmax
    Y = lambda v: H - B - (H - T - B) * min(v, ymax) / ymax
    YC = lambda v: H - B - (H - T - B) * min(v, cmax) / cmax
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="Frame time and crowd over the run">' % (W, H)]
    # the slow window
    o.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="#ff6b6b" opacity="0.09"/>' % (X(149), T, X(172) - X(149), H - T - B))
    o.append('<text x="%.1f" y="%d" fill="%s" font-size="13" text-anchor="middle">everything twice as slow</text>' % ((X(149) + X(172)) / 2, T + 14, C_CROWD))
    for v in (0, 10, 20, 30, 40):
        o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s"/>' % (L, W - R, Y(v), Y(v), C_GRID))
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12" text-anchor="end">%d</text>' % (L - 8, Y(v) + 4, C_DIM, v))
    for v in (0, 100, 200, 300):
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12">%d</text>' % (W - R + 8, YC(v) + 4, C_CROWD, v))
    for t in range(0, 181, 30):
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">%d:%02d</text>' % (X(t), H - B + 20, C_DIM, t // 60, t % 60))
    # stacked areas
    base = [0.0] * len(pts)
    for idx, col in ((1, C_STEP), (2, C_PROC), (3, C_REST)):
        top = [b + p[idx] for b, p in zip(base, pts)]
        d = "M" + " L".join("%.1f %.1f" % (X(p[0]), Y(t)) for p, t in zip(pts, top))
        d += " L" + " L".join("%.1f %.1f" % (X(p[0]), Y(b)) for p, b in zip(pts[::-1], base[::-1])) + " Z"
        o.append('<path d="%s" fill="%s" opacity="0.92"/>' % (d, col))
        base = top
    o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2" stroke-dasharray="6 5"/>' % (L, W - R, Y(16.7), Y(16.7), C_OK))
    o.append('<text x="%d" y="%.1f" fill="%s" font-size="12">60 fps budget, 16.7 ms</text>' % (L + 8, Y(16.7) - 7, C_OK))
    d = "M" + " L".join("%.1f %.1f" % (X(p[0]), YC(p[4])) for p in pts)
    o.append('<path d="%s" fill="none" stroke="%s" stroke-width="2.5"/>' % (d, C_CROWD))
    o.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="middle" transform="rotate(-90 %d %d)">milliseconds a frame</text>' % (14, (T + H - B) // 2, C_DIM, 14, (T + H - B) // 2))
    o.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="middle" transform="rotate(90 %d %d)">creatures alive</text>' % (W - 12, (T + H - B) // 2, C_CROWD, W - 12, (T + H - B) // 2))
    o.append("</svg>")
    return "".join(o)


def slow_windows(samples, ms=22.0, least=5):
    """Runs of at least `least` seconds whose mean frame was over `ms`: [(first t, last t, [samples])]."""
    s = [x for x in samples if x.get("frame_ms")]
    out, cur = [], []
    for x in s:
        if x["frame_ms"] > ms:
            cur.append(x)
        else:
            if len(cur) >= least:
                out.append((cur[0]["t"], cur[-1]["t"], cur))
            cur = []
    if len(cur) >= least:
        out.append((cur[0]["t"], cur[-1]["t"], cur))
    return out


def script_ms(x):
    """A second's script work a frame: its world steps' share plus the per-frame scripts (ms)."""
    fr = max(float(x.get("frames", 0) or 0), 1.0)
    return float(x.get("steps", 0) or 0) * float(x.get("phys_ms", 0) or 0) / fr + float(x.get("proc_ms", 0) or 0)


def timeline1(samples):
    """Stage 1's run, frame stacked by what took it (3-second means), the crowd on its own scale, slow windows shaded."""
    W, H = 900, 400
    L, R, T, B = 52, 56, 44, 40
    pts = []
    for i in range(0, len(samples), 3):
        w = [x for x in samples[i:i + 3] if x.get("frame_ms")]
        if not w:
            continue
        def m(k):
            v = [x[k] for x in w if isinstance(x.get(k), (int, float))]
            return st.mean(v) if v else 0.0
        fr = max(m("frames"), 1.0)
        step = m("steps") * m("phys_ms") / fr
        proc = m("proc_ms")
        rest = max(m("frame_ms") - step - proc, 0.0)
        pts.append((m("t"), step, proc, rest, m("alive")))
    tmax, ymax, cmax = 790.0, 45.0, 350.0
    X = lambda t: L + (W - L - R) * t / tmax
    Y = lambda v: H - B - (H - T - B) * min(v, ymax) / ymax
    YC = lambda v: H - B - (H - T - B) * min(v, cmax) / cmax
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="Frame time and crowd over the Stage 1 run">' % (W, H)]
    for a, b, _w in slow_windows(samples):
        o.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="#ff6b6b" opacity="0.13"/>' % (X(a - 0.5), T, max(X(b + 0.5) - X(a - 0.5), 2), H - T - B))
    for a, b, name in PHASES1:
        o.append('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="%s" stroke-dasharray="3 4"/>' % (X(a), X(a), T - 22, H - B, C_DIM))
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="13" text-anchor="middle">%s</text>' % ((X(a) + X(b)) / 2, T - 10, C_INK, name))
    for v in (0, 10, 20, 30, 40):
        o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s"/>' % (L, W - R, Y(v), Y(v), C_GRID))
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12" text-anchor="end">%d</text>' % (L - 8, Y(v) + 4, C_DIM, v))
    for v in (0, 100, 200, 300):
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12">%d</text>' % (W - R + 8, YC(v) + 4, C_CROWD, v))
    for t in range(0, 781, 120):
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">%d:%02d</text>' % (X(t), H - B + 20, C_DIM, t // 60, t % 60))
    base = [0.0] * len(pts)
    for idx, col in ((1, C_STEP), (2, C_PROC), (3, C_REST)):
        top = [b + p[idx] for b, p in zip(base, pts)]
        d = "M" + " L".join("%.1f %.1f" % (X(p[0]), Y(t)) for p, t in zip(pts, top))
        d += " L" + " L".join("%.1f %.1f" % (X(p[0]), Y(b)) for p, b in zip(pts[::-1], base[::-1])) + " Z"
        o.append('<path d="%s" fill="%s" opacity="0.92"/>' % (d, col))
        base = top
    o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2" stroke-dasharray="6 5"/>' % (L, W - R, Y(16.7), Y(16.7), C_OK))
    d = "M" + " L".join("%.1f %.1f" % (X(p[0]), YC(p[4])) for p in pts)
    o.append('<path d="%s" fill="none" stroke="%s" stroke-width="2.5"/>' % (d, C_CROWD))
    o.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="middle" transform="rotate(-90 %d %d)">milliseconds a frame</text>' % (14, (T + H - B) // 2, C_DIM, 14, (T + H - B) // 2))
    o.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="middle" transform="rotate(90 %d %d)">creatures alive</text>' % (W - 12, (T + H - B) // 2, C_CROWD, W - 12, (T + H - B) // 2))
    o.append("</svg>")
    return "".join(o)


def same_crowd(samples):
    """About 77 creatures three ways: the first 3:30, later at full speed, later in a slow window (ms a frame)."""
    groups = [("First 3:30 of the run", lambda x: x["t"] < 210 and x["frame_ms"] < 17.5),
              ("3:30 to 7:10, full speed", lambda x: 210 <= x["t"] < 430 and x["frame_ms"] < 17.5),
              ("3:30 to 7:10, in a slow window", lambda x: 210 <= x["t"] < 430 and x["frame_ms"] > 24)]
    rows = []
    for name, f in groups:
        xs = [x for x in samples if x.get("frame_ms") and 60 <= (x.get("alive") or 0) <= 100 and f(x)]
        fr = st.mean(max(float(x["frames"]), 1.0) for x in xs)
        step = st.mean(float(x["steps"]) * x["phys_ms"] / max(float(x["frames"]), 1.0) for x in xs)
        rows.append((name, len(xs), st.mean(x["alive"] for x in xs), step, st.mean(x["proc_ms"] for x in xs), st.mean(x["frame_ms"] for x in xs), fr))
    W = 900
    H = 70 * len(rows) + 34
    L = 300
    X = lambda v: L + (W - L - 210) * v / 31.0
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="The same crowd at three moments of the run">' % (W, H)]
    o.append('<line x1="%.1f" x2="%.1f" y1="4" y2="%d" stroke="%s" stroke-width="2" stroke-dasharray="6 5"/>' % (X(16.7), X(16.7), H - 24, C_OK))
    o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">16.7 ms = 60 fps</text>' % (X(16.7), H - 6, C_OK))
    for i, (name, n, alive, step, proc, frame, fr) in enumerate(rows):
        y = 10 + i * 70
        o.append('<text x="%d" y="%d" fill="%s" font-size="15" text-anchor="end">%s</text>' % (L - 12, y + 20, C_INK, html.escape(name)))
        o.append('<text x="%d" y="%d" fill="%s" font-size="12.5" text-anchor="end">%d seconds, %d creatures on average</text>' % (L - 12, y + 38, C_DIM, n, round(alive)))
        o.append('<rect x="%d" y="%d" width="%.1f" height="30" fill="%s"/>' % (L, y + 6, X(step) - L, C_STEP))
        o.append('<rect x="%.1f" y="%d" width="%.1f" height="30" fill="%s"/>' % (X(step), y + 6, X(step + proc) - X(step), C_PROC))
        o.append('<rect x="%.1f" y="%d" width="%.1f" height="30" fill="%s" opacity="0.55"/>' % (X(step + proc), y + 6, max(X(frame) - X(step + proc), 0), C_REST))
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="13">scripts %.1f ms, frame %.1f ms</text>' % (X(max(frame, step + proc)) + 8, y + 26, C_DIM, step + proc, frame))
    o.append("</svg>")
    return "".join(o), rows


def window_rows():
    """Every slow window (5 s or longer over 22 ms) in four long phone runs: when, how long, the crowd in it."""
    out = []
    for day, stage, fn in WINDOW_RUNS:
        r = json.load(open(os.path.join(REMOTE, fn), encoding="utf-8"))
        s = [x for x in r["samples"] if x.get("frame_ms")]
        ws = slow_windows(s)
        secs = sum(len(w) for _a, _b, w in ws)
        small = [w for _a, _b, w in ws if max(x.get("alive", 0) or 0 for x in w) < 150]
        least = min((min(x.get("alive", 0) or 0 for x in w) for _a, _b, w in ws), default=0)
        first = ws[0][0] if ws else 0
        out.append((day, stage, r.get("hero_name") or r.get("hero"), len(s), len(ws), secs, len(small), least, first,
                    max((len(w) for _a, _b, w in ws), default=0)))
    return out


def step_split(replay_path, windows):
    """In the slow windows, a frame's own length (the next frame's delta) by the world steps it ran: (1-step ms, 2-step ms, share of frames with 2)."""
    r = json.load(open(replay_path, encoding="utf-8"))
    s = r["frames"]
    raw = gzip.decompress(base64.b64decode(s[:s.rfind(":")]))
    fr = []
    o = 0
    while o + 29 <= len(raw):
        n, kr = struct.unpack_from("<IB", raw, o)
        _pd, d, ts = struct.unpack_from("<ddd", raw, o + 5)
        o += 29
        fr.extend([(kr & 15, (kr >> 4) & 1, d, ts)] * n)
    run, rt = [], 0.0
    for k, ran, d, ts in fr:
        if ran:
            rt += d * ts
        run.append(rt)
    one, two = [], []
    for i in range(len(fr) - 1):
        if fr[i][1] and fr[i + 1][1] and any(a <= run[i] <= b + 1 for a, b in windows):
            (one if fr[i][0] == 1 else two).append(fr[i + 1][2] * 1000.0)
    return st.median(one), st.median(two), len(two) / max(len(one) + len(two), 1)


def work_s(x):
    """A second of play's script work (ms): its world steps' time plus its frames' per-frame time. The PC's replay runs
    the phone's own frames and world steps, so the two seconds hold the same number of each."""
    return float(x.get("steps", 0) or 0) * float(x.get("phys_ms", 0) or 0) + float(x.get("frames", 0) or 0) * float(x.get("proc_ms", 0) or 0)


def pc_compare(ph, pc, tmax=700):
    """The phone's speed against its own start: (the PC's work / the phone's) over 9-second windows, divided by the same
    figure for the first 3:30. Plus phase rows: (name, creatures, PC ms a frame, phone ms a frame, phone fps, share of
    seconds under 45 fps)."""
    P = {int(x["t"]): x for x in ph if x.get("frame_ms")}
    C = {int(x["t"]): x for x in pc if work_s(x) > 0}
    ts = [t for t in range(1, tmax) if t in P and t in C]
    base = sum(work_s(C[t]) for t in ts if t < 210) / sum(work_s(P[t]) for t in ts if t < 210)
    series = []
    for t in ts:
        win = [u for u in ts if abs(u - t) <= 4]
        series.append((t, sum(work_s(C[u]) for u in win) / sum(work_s(P[u]) for u in win) / base))
    rows = []
    for a, b, name in [(0, 210, "First 3:30"), (210, 430, "3:30 to 7:10"), (430, 667, "Boss fight")]:
        u = [t for t in ts if a <= t < b]
        fr = sum(float(P[t]["frames"]) for t in u)
        rows.append((name, st.mean(P[t].get("alive", 0) or 0 for t in u), sum(work_s(C[t]) for t in u) / fr, sum(work_s(P[t]) for t in u) / fr,
                     fr / len(u), sum(1 for t in u if P[t]["frame_ms"] > 22.2) / len(u), sum(work_s(P[t]) for t in u) / sum(work_s(C[t]) for t in u)))
    return series, rows, 1.0 / base


def speed_chart(series, samples):
    """The phone's speed through the run (1 = as fast as in its first 3:30), slow windows shaded."""
    W, H = 900, 300
    L, R, T, B = 52, 20, 40, 40
    tmax = 700.0
    X = lambda t: L + (W - L - R) * t / tmax
    Y = lambda v: H - B - (H - T - B) * min(max(v, 0.0), 1.25) / 1.25
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="The phone\'s speed through the run">' % (W, H)]
    for a, b, _w in slow_windows(samples):
        if a < tmax:
            o.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="#ff6b6b" opacity="0.13"/>' % (X(a - 0.5), T, max(X(min(b, tmax) + 0.5) - X(a - 0.5), 2), H - T - B))
    for a, b, name in PHASES1[:3]:
        o.append('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="%s" stroke-dasharray="3 4"/>' % (X(a), X(a), T - 22, H - B, C_DIM))
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="13" text-anchor="middle">%s</text>' % ((X(a) + X(min(b, tmax))) / 2, T - 10, C_INK, name))
    for v in (0.0, 0.25, 0.5, 0.75, 1.0):
        o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s"/>' % (L, W - R, Y(v), Y(v), C_GRID))
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12" text-anchor="end">%d%%</text>' % (L - 8, Y(v) + 4, C_DIM, round(v * 100)))
    for t in range(0, 700, 120):
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">%d:%02d</text>' % (X(t), H - B + 20, C_DIM, t // 60, t % 60))
    o.append('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="%s" stroke-width="1.5"/>' % (X(160), X(160), T, H - B, C_INK))
    o.append('<text x="%.1f" y="%d" fill="%s" font-size="12">replay exact up to 2:40</text>' % (X(160) + 6, H - B - 8, C_DIM))
    d = "M" + " L".join("%.1f %.1f" % (X(t), Y(v)) for t, v in series)
    o.append('<path d="%s" fill="none" stroke="%s" stroke-width="2.5"/>' % (d, C_PROC))
    o.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="middle" transform="rotate(-90 %d %d)">speed against its start</text>' % (14, (T + H - B) // 2, C_DIM, 14, (T + H - B) // 2))
    o.append("</svg>")
    return "".join(o)


# Pass 125: game/tools/_p125_CROWD_bench.gd on the PC (tools/dl/p125/NATIVE/step2.txt): creatures, the crowd's own ms a frame
# (enemies.sim + enemies.render) and the whole frame, by the script (None: not run) and compiled
BENCH = [(300, 4.22, 7.08, 0.66, 3.10), (500, 6.33, 8.98, 0.85, 3.33), (800, 10.60, 13.77, 1.22, 3.87), (1200, None, None, 1.70, 4.49), (2000, None, None, 2.70, 5.76)]


def bench_chart():
    """The whole frame on the PC by crowd size, script against compiled."""
    W, H = 900, 300
    L, R, T, B = 52, 20, 18, 42
    nmax, ymax = 2000.0, 15.0
    X = lambda n: L + (W - L - R) * n / nmax
    Y = lambda v: H - B - (H - T - B) * min(v, ymax) / ymax
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="Frame time by crowd size, script against compiled">' % (W, H)]
    for v in (0, 5, 10, 15):
        o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s"/>' % (L, W - R, Y(v), Y(v), C_GRID))
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12" text-anchor="end">%d</text>' % (L - 8, Y(v) + 4, C_DIM, v))
    for n in (300, 500, 800, 1200, 2000):
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">%d</text>' % (X(n), H - B + 20, C_DIM, n))
    o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">creatures alive</text>' % ((L + W - R) / 2, H - 6, C_DIM))
    scr = [(r[0], r[2]) for r in BENCH if r[2] is not None]
    nat = [(r[0], r[4]) for r in BENCH]
    for pts, col, name in ((scr, C_CROWD, "the script"), (nat, C_OK, "compiled")):
        d = "M" + " L".join("%.1f %.1f" % (X(n), Y(v)) for n, v in pts)
        o.append('<path d="%s" fill="none" stroke="%s" stroke-width="3"/>' % (d, col))
        for n, v in pts:
            o.append('<circle cx="%.1f" cy="%.1f" r="4.5" fill="%s"/>' % (X(n), Y(v), col))
            o.append('<text x="%.1f" y="%.1f" fill="%s" font-size="12.5" text-anchor="middle">%.1f</text>' % (X(n), Y(v) - 10, C_INK, v))
        n, v = pts[-1]
        o.append('<text x="%.1f" y="%.1f" fill="%s" font-size="13" text-anchor="%s">%s</text>' % (X(n) + (10 if name == "the script" else -4), Y(v) - (0 if name == "the script" else 24), col, "start" if name == "the script" else "end", name))
    o.append('<text x="%d" y="%d" fill="%s" font-size="12" text-anchor="middle" transform="rotate(-90 %d %d)">ms a frame, PC</text>' % (14, (T + H - B) // 2, C_DIM, 14, (T + H - B) // 2))
    o.append("</svg>")
    return "".join(o)


def budget_lines():
    """Phone cost by crowd size, cool and warm: straight lines fitted to its runs (see the numbers under the chart)."""
    W, H = 900, 300
    L, R, T, B = 52, 20, 18, 38
    cool = lambda n: 7.5 + 3.89 + 0.0142 * n     # rest 7.5, phys 1.5 + .0113 n, proc 2.39 + .0029 n (first 5 minutes of a fresh run, 10-24)
    warm = lambda n: 5.8 + 3.82 + 0.034 * n      # rest 5.8, phys 1.27 + .0185 n, proc 2.55 + .0155 n (this run before 2:28)
    nmax = 500.0
    ymax = 30.0
    X = lambda n: L + (W - L - R) * n / nmax
    Y = lambda v: H - B - (H - T - B) * min(v, ymax) / ymax
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="Frame cost by crowd size on the phone">' % (W, H)]
    for v in (0, 10, 20, 30):
        o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s"/>' % (L, W - R, Y(v), Y(v), C_GRID))
        o.append('<text x="%d" y="%.1f" fill="%s" font-size="12" text-anchor="end">%d</text>' % (L - 8, Y(v) + 4, C_DIM, v))
    for n in range(0, 501, 100):
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="12" text-anchor="middle">%d</text>' % (X(n), H - B + 20, C_DIM, n))
    o.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2" stroke-dasharray="6 5"/>' % (L, W - R, Y(16.7), Y(16.7), C_OK))
    for f, col, name in ((cool, C_PROC, "phone cool"), (warm, C_STEP, "phone warm")):
        o.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="3"/>' % (X(0), Y(f(0)), X(500), Y(f(500)), col))
    nw = (16.67 - 5.8 - 3.82) / 0.034
    nc = (16.67 - 7.5 - 3.89) / 0.0142
    for n, col, name in ((nc, C_PROC, "about %d creatures, cool" % round(nc, -1)), (nw, C_STEP, "about %d creatures, warm" % round(nw, -1))):
        o.append('<circle cx="%.1f" cy="%.1f" r="6" fill="%s"/>' % (X(n), Y(16.67), col))
        o.append('<text x="%.1f" y="%.1f" fill="%s" font-size="13" text-anchor="middle">%s</text>' % (X(n), Y(16.67) + 24, C_INK, name))
    o.append('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="%s" stroke-width="2"/>' % (X(318), X(318), T, H - B, C_CROWD))
    o.append('<text x="%.1f" y="%d" fill="%s" font-size="13">318: your run at 3:01</text>' % (X(318) + 6, T + 14, C_CROWD))
    o.append("</svg>")
    return "".join(o)


def bars():
    """What a frame's CPU time went on with 288 creatures, PC measure (tools/dl/p124/LEAD/probes.txt, fire300)."""
    rows = [("Moving and colliding the crowd", 2.99, C_STEP, "enemies.sim"), ("Writing the crowd to the GPU", 1.87, C_STEP, "enemies.render"),
            ("Everything the timers don't name (engine, sending draw calls)", 2.09, C_REST, "the frame less the timed systems"),
            ("The hero", 0.43, C_PROC, "player"), ("Shots, flying and drawn", 0.29, C_PROC, "projectiles"), ("HUD", 0.14, C_PROC, "hud"),
            ("Weapons", 0.09, C_PROC, "weapons"), ("Particles", 0.07, C_PROC, "fx"), ("Gems and coins, 281 lying", 0.09, C_PROC, "pickups"), ("Structures", 0.06, C_PROC, "structures")]
    W = 900
    H = 34 * len(rows) + 10
    L = 410
    X = lambda v: L + (W - L - 70) * v / 3.2
    o = ['<svg viewBox="0 0 %d %d" role="img" aria-label="Where a frame goes">' % (W, H)]
    for i, (name, v, col, key) in enumerate(rows):
        y = 8 + i * 34
        o.append('<text x="%d" y="%d" fill="%s" font-size="14" text-anchor="end">%s</text>' % (L - 12, y + 17, C_INK, html.escape(name)))
        o.append('<rect x="%d" y="%d" width="%.1f" height="22" fill="%s"/>' % (L, y + 2, X(v) - L, col))
        o.append('<text x="%.1f" y="%d" fill="%s" font-size="13">%.2f ms</text>' % (X(v) + 8, y + 18, C_DIM, v))
    o.append("</svg>")
    return "".join(o)


SOLUTIONS = [
    dict(k="B", name="Take away the cliff", gain="Now the biggest: it helps every slow stretch, on every stage",
         ms="Stage 1's slow windows: a frame with one world step took 22 ms, a frame with two 31 ms, and two thirds of the frames ran two. One step a frame: about 30 fps to about 45. Stage 2's worst stretch: 38 ms to about 25-28.",
         lose="Nothing you can see in a screenshot. While the phone runs slow, the world either moves in slight slow motion (about three quarters speed in those windows) or takes slightly bigger steps.",
         work="Small to medium. One setting to try (one world step a frame), then a choice between slow motion and a longer step",
         risk="Replays record the steps, so they stay correct for new runs but need a re-test",
         note="Today the catch-up step doubles the world's work at exactly the moment the phone has least to give. With one step a frame, a phone at two thirds of its speed gives about two thirds of the frame rate, not half. EVE Online makes the same trade with its time dilation."),
    dict(k="G", name="Work with the phone's heat: Android's ADPF", gain="Large if it works on your phone: it goes after the main cause. Unproven until tried",
         ms="I can't promise a number before trying it. It has two parts. The performance hint tells Android each frame's deadline and how long the work took, so Android can pick clock speeds and cores. The heat warning (thermal headroom) says how close the phone is to slowing down, some seconds ahead.",
         lose="Only while the phone is hot, and only what you choose. For example the 3D resolution from 0.8 to 0.7 (23% fewer pixels, slightly softer sand and creatures), fewer particles, or option A's crowd budget. On a cool phone, nothing.",
         work="Medium: a small Android plugin (Kotlin) and the Gradle build the Play build already uses. No Godot plugin exists; Unity, Unreal and Defold have one",
         risk="Low to moderate: it needs Android 12 or later (your Pixel has it), and a plugin is one more part of the build",
         note="The same plugin would write the phone's heat into the run record every second, so the next report can show the cause as a measurement. Android also has a sustained performance mode (steady, lower clocks instead of swings). Whether a Pixel 8 Pro supports it is up to Google; the plugin can ask in one line, and we can try it."),
    dict(k="A", name="Set a crowd budget for the phone", gain="Large for Stage 2 and Endless, little for Stage 1",
         ms="Stage 2's worst frames: 38 ms to about 18-20 ms. Endless is similar (here 230-300 creatures at 29 fps). Stage 1's slow windows had 35-140 creatures, so a budget can't fix those.",
         lose="Fewer bodies at the worst moment: at most about 250 instead of 320 and rising. At 319 creatures their pictures cover 77% of a screen, so 250 still looks like a swarm. Rows may run a little thin, which the Level Editor shows as starving.",
         work="Tiny as a fixed cap (map data). Small as the automatic version",
         risk="Balance: fewer kills means slightly less XP in that stretch",
         note="Better automatic: hold new spawns only while recent frames run over budget. Then it also reacts to a hot phone, and a cool phone and the PC keep the full crowd. That's a small rule, and it would be named in BALANCING."),
    dict(k="C", name="Rewrite the crowd's loops in compiled code (GDExtension, C++): BUILT", gain="Built, in your Drive build. Largest for big crowds",
         ms="Measured on the PC at 300 creatures: the crowd's own cost from 4.2 ms to 0.7 ms a frame, the whole frame from 7.1 ms to 3.1 ms. 800 creatures now cost about what 300 did. Stage 1 as you played it gains less: script work down by about 30% early, 25% later and 9% in the boss fight.",
         lose="Nothing. The pictures match to within 1/255 of a colour channel.",
         work="Done. The library is in game/bin, and tools/build_native.py rebuilds it",
         risk="Not measured on your phone yet. If the library doesn't load, the game runs the script instead and plays the same",
         note="Six full runs replayed the other way round matched at all 1,967 checkpoints. The developer menu's Compiled crowd switch compares the two on your phone, and each run record says which ran."),
    dict(k="I", name="Trim the smaller costs the replay found", gain="Small to medium",
         ms="From the PC's timers during Stage 1: the wave director 0.3-0.4 ms a frame, drawing the shots 0.4 ms late in the stage, the hero 0.45 ms. On a slow phone that's 3 to 4 times as much: perhaps 2-4 ms together.",
         lose="Nothing, if each turns out to be wasted work. I haven't looked at why yet.",
         work="Small to medium, one at a time", risk="Low",
         note="The first report couldn't see these: its PC probe used a different build and no boss fight. The director stands out. It's the code that decides spawns, and it's worth checking why it costs a third of a millisecond every frame."),
    dict(k="D", name="Move the crowd less often: BUILT, LEFT OFF", gain="Measured: not worth it now",
         ms="Steering every 3rd tick instead of every 2nd saves about 0.03-0.05 ms a frame at 300-800 creatures, now that steering is compiled",
         lose="The crowd overlaps about 18-26% more.",
         work="Done. A map setting, timeline_data.crowd, with today's numbers as the default",
         risk="None while it's off",
         note="It would have helped the script's version more. See the section at the top."),
    dict(k="E", name="Draw far-away creatures half as often", gain="Small to medium",
         ms="Writing the crowd to the GPU down by about 30-40%: Stage 2's frames down by 2-3 ms, Stage 1's by under 1 ms",
         lose="Creatures at the screen's edge update 30 times a second. On a slow walker that's hard to see; on a fast creature at the edge you may see a very slight step if you look for it.",
         work="Small to medium", risk="Low",
         note="The game writes every drawn creature's position and frame to the GPU every frame, one call at a time."),
    dict(k="F", name="Fewer draw calls for scenery", gain="Small to medium",
         ms="1-2 ms off the part that sends draw calls, more on a slow phone", lose="Nothing.", work="Medium", risk="Low",
         note="The PC probe counts about 170 draw calls and 700-790 objects. Scenery, walls and shadows could merge further. It also lowers power use, which means a little less heat."),
    dict(k="H", name="Change the sprite sheets' file type or compression", gain="Doesn't fix this slowdown",
         ms="About 0-1 ms. Helps memory and loading instead",
         lose="If you use GPU compression (ETC2): small blocky artefacts along outlines and soft edges, most visible on hero close-ups and pale creatures. You'd want to check it by eye on 3 or 4 strips first.",
         work="Small to test, medium to roll out", risk="Low. It's per file and easy to undo", note="See the section below."),
]

SOURCES = [
    ("Godot docs: Optimization using MultiMeshes", "https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html", "We already draw this way. It says GDScript is fine for a few thousand instances, and other languages for far more."),
    ("Godot docs: importing images", "https://docs.godotengine.org/en/latest/classes/class_resourceimportertexture.html", "Lossy quality affects disk size only; VRAM compression lowers memory and sampling bandwidth; on the Compatibility renderer it means ETC2, since the high-quality ASTC option is ignored there."),
    ("Godot docs: General optimization", "https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html", "Measure first; the frame is set by the slower of CPU and GPU, so a GPU fix can't help a CPU-bound frame."),
    ("Horde add-on devlog (Spare Parts Studio)", "https://spare-parts-studio.itch.io/horde/devlog/1733372/horde-is-out-thousands-of-2d-enemies-for-godot-4", "Thousands of Godot enemies in plain GDScript, using flat arrays and one draw call per type. 3,300 enemies at 150 fps against 7 as nodes in a browser demo: the seller's own number, desktop. We already do both techniques."),
    ("Ezcha: Rendering a million objects in Godot", "https://ezcha.net/news/5-16-26-rendering-a-million-objects-in-godot", "A million static objects at 160 fps through server calls. It shows drawing isn't the limit when nothing moves: the cost is updating moving things from script, which is our case."),
    ("Godot forum: native code instead of GDScript", "https://forum.godotengine.org/t/performance-implications-of-using-native-code-instead-of-gdscript/120365", "The common advice: write it in GDScript first and move only proven hot spots to native code. No hard numbers."),
    ("r/godot: C# vs GDScript with large for loops", "https://axebps-redlib.hf.space/r/godot/comments/1g50mlq/c_vs_gdscript_performance_with_large_for_loops", "Community view that a hybrid works best. Anecdotal."),
    ("Viblo: Godot 4 on Android, 5 tips", "https://viblo.asia/p/toi-uu-hieu-nang-game-godot-4-tren-android-5-meo-thuc-te-G24B8GlGLz3", "ETC2/ASTC, profiling on the device, MultiMesh for hundreds of sprites. An anecdote; its numbers aren't verified."),
    ("Beebom: Tensor G3 benchmarks and thermals", "https://beebom.com/google-tensor-g3-benchmarks/", "A 15-minute CPU stress test lost about 60% of peak."),
    ("Notebookcheck: Pixel 8 stress tests", "https://www.notebookcheck.net/First-Pixel-8-and-Pixel-8-Pro-3D-Mark-stress-test-results-surface-paint-a-potentially-ugly-picture-for-Tensor-G3.757268.0.html", "A 58% CPU drop under sustained load. 2023 launch-era tests; updates may have changed this."),
    ("Android: ADPF story, NCSoft Lineage W", "https://developer.android.com/stories/games/lineagew-adpf", "60 fps fell to 32 on a Pixel 6 in 30 minutes; with thermal-aware quality it held 60."),
    ("Android: ADPF overview", "https://developer.android.com/games/optimize/adpf", "Mobile chips change clock speed and core type as they heat. ADPF's Thermal API lets a game adjust before that, and its performance hint describes the game's frame work to Android."),
    ("Android: best practices for ADPF", "https://developer.android.com/games/optimize/adpf/best-practices-adpf", "Scale individual settings (resolution, particles, effects) in small steps as heat rises, rather than whole presets, and test sessions of 15 minutes or more."),
    ("Android: Thermal API", "https://developer.android.com/games/optimize/adpf/thermal", "Thermal headroom runs from 0 (no throttling) to 1 (heavy throttling), and a game can ask for it ahead of time."),
    ("Android: sustained performance mode", "https://source.android.com/docs/core/power/performance", "A phone maker can offer steady, lower clocks instead of a fast start that throttles. Their example: a steady 45 fps instead of 60 falling to 30. Support depends on the device."),
    ("Defold: ADPF extension", "https://defold.com/extension-adpf", "Another engine's wrapper for both APIs: a hint session for the main thread and a headroom forecast. The closest model for a Godot plugin; I found none for Godot."),
    ("Imagination: Do Not Use Discard", "https://docs.imgtec.com/starter-guides/powervr-architecture/html/topics/rules/do-not-use-discard.html", "Alpha test is costly on tile-based GPUs. This is PowerVR's guidance, not Mali's; I didn't find Arm numbers."),
]


def page(d):
    s = d["samples"]
    sol_rows = "".join(
        '<tr><td class="k">%s</td><td><b>%s</b><br><span class="dim">%s</span></td><td>%s</td><td>%s</td><td>%s</td></tr>' % (
            x["k"], html.escape(x["name"]), html.escape(x["gain"]), html.escape(x["ms"]), html.escape(x["lose"]), html.escape(x["work"]).replace("`", ""))
        for x in SOLUTIONS)
    sol_cards = "".join(
        '<div class="opt"><h3><span class="k">%s</span> %s</h3><p class="note">%s</p><p class="dim"><b>Risk:</b> %s</p></div>' % (
            x["k"], html.escape(x["name"]), html.escape(x["note"]).replace("`", ""), html.escape(x["risk"]))
        for x in SOLUTIONS)
    src = "".join('<li><a href="%s">%s</a>: %s</li>' % (html.escape(u), html.escape(n), html.escape(w)) for n, u, w in SOURCES)
    # pass 125: the Stage 1 run, its replay and the PC's replay of it
    s1 = json.load(open(RUN1, encoding="utf-8"))["samples"]
    pc = json.load(open(PC1, encoding="utf-8"))["samples"]
    same_svg, same = same_crowd(s1)
    series, prow, _base = pc_compare(s1, pc)
    pre = [(a, b) for a, b, _w in slow_windows(s1) if b < 430]
    one, two, share = step_split(REPLAY1, pre)
    phase_rows = "".join('<tr><td><b>%s</b></td><td>%d</td><td>%.1f ms</td><td>%.1f ms</td><td>%d</td><td>%d%%</td></tr>' % (
        name, round(alive), pcw, phw, round(fps), round(100 * under)) for name, alive, pcw, phw, fps, under, _x in prow)
    win_rows = "".join('<tr><td><b>%s</b>, %s</td><td>%d:%02d</td><td>%d</td><td>%d</td><td>%d</td><td>%d</td><td>%d:%02d</td><td>%d s</td></tr>' % (
        day, stage, played // 60, played % 60, n, secs, small, least, int(first) // 60, int(first) % 60, longest)
        for day, stage, _hero, played, n, secs, small, least, first, longest in window_rows())
    boss = prow[2]
    first = prow[0]
    bench_rows = "".join('<tr><td><b>%d</b></td><td>%s</td><td>%.2f ms</td><td>%s</td><td>%.2f ms</td></tr>' % (
        n, ("%.2f ms" % a) if a is not None else "not run", c, ("%.2f ms" % b) if b is not None else "not run", d) for n, a, b, c, d in BENCH)
    rep = {
        "@@BENCH@@": bench_chart(), "@@BENCHROWS@@": bench_rows,
        "@@T1@@": timeline1(s1), "@@SAME@@": same_svg, "@@SPEED@@": speed_chart(series, s1), "@@PHASEROWS@@": phase_rows, "@@WINROWS@@": win_rows,
        "@@BOSSSLOW@@": "%d%%" % round(100 * boss[5]), "@@BOSSX@@": "%.1f" % (boss[6] / first[6]),
        "@@S0@@": "%.1f" % (same[0][3] + same[0][4]), "@@S1@@": "%.1f" % (same[1][3] + same[1][4]), "@@S2@@": "%.0f" % (same[2][3] + same[2][4]),
        "@@F2@@": "%.0f" % same[2][5], "@@PCB@@": "%.1f" % boss[2], "@@PC0@@": "%.1f" % first[2], "@@PHB@@": "%.1f" % boss[3], "@@PH0@@": "%.1f" % first[3],
        "@@ONE@@": "%.0f" % one, "@@TWO@@": "%.0f" % two, "@@TWOSHARE@@": "two thirds" if 0.6 <= share <= 0.72 else "%d%%" % round(100 * share),
        "@@TIMELINE@@": timeline(s), "@@BARS@@": bars(), "@@LINES@@": budget_lines(), "@@SOLROWS@@": sol_rows, "@@SOLCARDS@@": sol_cards, "@@SOURCES@@": src,
    }
    out = TEMPLATE
    for k, v in rep.items():
        out = out.replace(k, v)
    assert "@@" not in out, out[out.index("@@") - 40:out.index("@@") + 40]
    return out


TEMPLATE = """<title>Phone Slowdown Report</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;700&family=Ultra&display=swap">
<style>
/* Layout: one reading column in the game's own navy and gold; charts run the column's full width */
:root { --bg:#10172c; --panel:#1a2440; --ink:#e9eefb; --dim:#9aa7c4; --gold:#ffd35c; --line:#2f3b5c; --red:#ff6b6b; --green:#5fc43a; --blue:#6ea5ef;
  --display:'Ultra', Georgia, serif; --body:'Rubik', system-ui, sans-serif; color-scheme: dark; }
body { background:var(--bg); color:var(--ink); font:400 17px/1.55 var(--body); padding-block:32px 64px; padding-left:max(16px, env(safe-area-inset-left, 0px)); padding-right:max(16px, env(safe-area-inset-right, 0px)); }
main { max-width:980px; margin:0 auto; display:flex; flex-direction:column; gap:40px; }
h1 { font:400 clamp(34px,6vw,54px)/1.1 var(--display); margin:0 0 10px; color:#fff6dc; text-wrap:balance; }
h2 { font:400 clamp(23px,3.4vw,30px)/1.2 var(--display); margin:0 0 12px; color:#fff6dc; text-wrap:balance; }
h3 { font:700 18px/1.3 var(--body); margin:0 0 6px; }
p { margin:0 0 12px; max-width:72ch; }
.lead { font-size:20px; }
.eyebrow { font:700 13px/1 var(--body); letter-spacing:.14em; text-transform:uppercase; color:var(--gold); margin-bottom:10px; }
.dim { color:var(--dim); }
.causes { display:grid; gap:14px; }
.cause { background:var(--panel); padding:16px 18px; border-left:4px solid var(--gold); }
.cause.second { border-color:var(--red); }
.cause.third { border-color:var(--blue); }
.cause h3 { font-size:19px; }
.cause p { margin:0; }
figure { margin:0; background:var(--panel); padding:16px; }
figure svg { width:100%; height:auto; display:block; font-family:var(--body); }
figcaption { color:var(--dim); font-size:14.5px; margin-top:10px; }
.legend { display:flex; flex-wrap:wrap; gap:6px 18px; margin:0 0 10px; font-size:14px; color:var(--dim); }
.legend i { display:inline-block; width:12px; height:12px; margin-right:6px; vertical-align:-1px; }
.tablewrap { overflow-x:auto; }
table { border-collapse:collapse; width:100%; min-width:760px; font-size:15px; }
th { text-align:left; font-weight:700; color:var(--gold); padding:8px 10px; border-bottom:2px solid var(--line); vertical-align:bottom; }
td { padding:10px; border-bottom:1px solid var(--line); vertical-align:top; }
td.k, .k { font:400 20px/1 var(--display); color:var(--gold); }
.opts { display:grid; gap:14px; grid-template-columns:repeat(auto-fit,minmax(300px,1fr)); }
.opt { background:var(--panel); padding:14px 16px; min-width:0; }
.opt p { font-size:15.5px; margin-bottom:8px; }
.notcause { display:grid; gap:10px; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); }
.notcause div { border-top:2px solid var(--line); padding-top:8px; min-width:0; font-size:15.5px; }
.notcause b { display:block; }
.pick { background:#2b2410; padding:18px 20px; border-left:4px solid var(--gold); }
ul { margin:0; padding-left:20px; display:grid; gap:7px; max-width:80ch; }
a { color:var(--blue); }
code { font-size:.92em; color:var(--gold); }
</style>
<main>
<header>
<div class="eyebrow">Performance report, updated after your Stage 1 run, for your decision</div>
<h1>Why the game slows down on your Pixel 8 Pro</h1>
<p class="lead">The first version of this report put the crowd first. Your Stage 1 run this evening (Drifter, 13:06, into Endless) shows that the bigger cause is the phone itself slowing down, and that the game's catch-up rule makes each slowdown about twice as bad. The crowd still matters in Stage 2 and Endless. You chose options C and D: C, the compiled crowd, is built and in your Drive build, and D is built but left off, because it turned out to cost more than it gives. The results come first below.</p>
</header>

<section>
<h2>Built: the crowd in compiled code (C)</h2>
<p>The crowd's busiest loops now run as compiled C++ instead of GDScript: both grids, deciding who is drawn, a walking creature's whole tick, every creature's push, a dying body's tick and most of the draw. Everything else, such as other brains, attacks, damage and bosses, stays in the script.</p>
<figure>
@@BENCH@@
<figcaption>The whole frame on the PC with a hero who has no weapons, walking through a mix of seven creatures. These aren't phone numbers. Your phone did the same work about 2.2 times slower at the start of your run and about 3.7 times slower in the boss fight.</figcaption>
</figure>
<div class="tablewrap" style="margin-top:16px"><table>
<thead><tr><th>Creatures</th><th>The crowd's own cost, script</th><th>The crowd's own cost, compiled</th><th>Whole frame, script</th><th>Whole frame, compiled</th></tr></thead>
<tbody>@@BENCHROWS@@</tbody>
</table></div>
<div class="causes" style="margin-top:16px">
<div class="cause"><h3>Nothing about the game changed</h3><p>Six full bot-played runs across all three stages, recorded one way and replayed the other, in both directions: all 1,967 checkpoints were identical. In 152 busy frames, the pictures matched to within 1/255 of a colour channel, the rounding of overlapping shadows.</p></div>
<div class="cause second"><h3>What to expect on your phone</h3><p>Big crowds gain the most. At 300 creatures the crowd's own cost falls from 4.2 ms to 0.7 ms on the PC, which I'd estimate saves about 8 ms a frame on a cool phone and about 13 ms on a slowed one. <b>Stage 1 gains less, because its crowd is small.</b> Replaying your own run, the PC's script work a frame fell from 2.5 to 1.8 ms in the first 3:30, from 4.1 to 3.1 ms from 3:30 to 7:10, and from 2.7 to 2.5 ms in the boss fight. So the slow stretches should shrink, not vanish: the phone still slows down, and the cliff still doubles the damage. None of this has been measured on your phone yet.</p></div>
<div class="cause third"><h3>How to compare on your phone</h3><p>The developer menu has a <b>Compiled crowd</b> switch, read when a run starts. Play the same stage with it on and off, and every run record now says which it was. If the library ever fails to load, the game runs the script instead and plays the same.</p></div>
</div>
</section>

<section>
<h2>Built and left off: moving the crowd less often (D)</h2>
<p>I built it as a map setting (<code>timeline_data.crowd</code>: <code>steer_every</code>, <code>steer_far_every</code>) and measured it against today's. With steering now compiled, it isn't worth what it costs, so the game stays at every 2nd tick on screen and every 4th off it.</p>
<div class="tablewrap"><table>
<thead><tr><th>Steering on screen / off it</th><th>The crowd's script time at 300 / 800 creatures</th><th>Overlapping pairs per creature, standing / walking</th><th>How deep they overlap, standing / walking</th></tr></thead>
<tbody>
<tr><td><b>Every 2nd / 4th tick (today)</b></td><td>0.51 / 0.95 ms</td><td>5.44 / 4.00</td><td>1.48 / 1.02</td></tr>
<tr><td><b>Every 3rd / 6th tick</b></td><td>0.48 / 0.90 ms</td><td>6.43 / 4.77</td><td>1.85 / 1.29</td></tr>
</tbody>
</table></div>
<p style="margin-top:12px">So it saves about 0.03-0.05 ms a frame and makes the crowd overlap about 18-26% more. It would help the script's version more, but the script's version is now only the fallback. If you'd like to see it anyway, it's those two numbers in the map's JSON.</p>
</section>

<section>
<h2>What your Stage 1 run shows</h2>
<div class="causes">
<div class="cause"><h3>Slow with a small crowd</h3><p>Before the boss, Stage 1 never had more than 140 creatures. Still, from 3:35 the game fell to about 30 fps four times, for 9 to 38 seconds each time, and then came back with about the same crowd. In the boss fight, with 17 creatures on average, @@BOSSSLOW@@ of the seconds ran under 45 fps.</p></div>
<div class="cause second"><h3>The same work, a slower phone</h3><p>I replayed your run on the PC, whose speed doesn't change. The boss fight asks for about the same work as the first three and a half minutes, when your phone ran a steady 60 fps with room to spare. On your phone it took @@BOSSX@@ times as long. So through the boss fight the phone ran at about 60% of the speed it started the run with, and at about two thirds in the slow windows before it.</p></div>
<div class="cause third"><h3>Every long run has it</h3><p>It isn't this build. Your runs of 27 and 31 October show the same windows, some with only 2 or 3 creatures alive. They start 2:30 to 6 minutes into a run, which is how a phone that heats up behaves.</p></div>
</div>
</section>

<section>
<h2>Stage 1, second by second</h2>
<figure>
<div class="legend"><span><i style="background:#f5b82a"></i>World steps (moving the crowd, shots, hero)</span><span><i style="background:#4a8ae0"></i>Per-frame scripts</span><span><i style="background:#5b6780"></i>The rest (drawing, waiting for the screen)</span><span><i style="background:#ff6b6b"></i>Creatures alive</span></div>
@@T1@@
<figcaption>Your phone's own numbers, averaged over 3 seconds. The red bands are the slow windows: 5 seconds or more at over 22 ms a frame. The crowd stays low until Endless, yet the frame jumps from about 17 ms to about 30 in each band.</figcaption>
</figure>
</section>

<section>
<h2>The same crowd, three times</h2>
<p>Three groups of seconds from this run, each with about 77 creatures alive.</p>
<figure>
<div class="legend"><span><i style="background:#f5b82a"></i>World steps</span><span><i style="background:#4a8ae0"></i>Per-frame scripts</span><span><i style="background:#5b6780;opacity:.55"></i>The rest of the frame</span></div>
@@SAME@@
<figcaption>At the start the scripts take @@S0@@ ms a frame. Later, with a bigger build, @@S1@@ ms, and the game still holds 60 fps. In a slow window the same crowd needs @@S2@@ ms of scripts and the frame takes @@F2@@ ms. Look at the yellow world steps: in a slow window almost every frame runs two of them. That's the cliff.</figcaption>
</figure>
</section>

<section>
<h2>The phone's speed, measured against the PC</h2>
<p>For each second, I divided the work the PC needed by the time your phone took, and scaled the result so that the first 3:30 is 100%. The PC replays your phone's own frames and world steps, so both machines did the same work. The replay matched your run exactly up to 2:40. After that, small differences built up, so later it's a close copy with about the same crowd and build, not the identical run.</p>
<figure>
@@SPEED@@
<figcaption>About 100% for the first three and a half minutes. Then it dips to about two thirds in each red band, and stays near 60% through the whole boss fight. The game didn't get heavier in the boss fight; the phone got slower.</figcaption>
</figure>
<div class="tablewrap" style="margin-top:16px"><table>
<thead><tr><th>Stretch</th><th>Creatures</th><th>PC's script work a frame</th><th>Phone's script work a frame</th><th>Phone fps</th><th>Seconds under 45 fps</th></tr></thead>
<tbody>@@PHASEROWS@@</tbody>
</table></div>
<p class="dim" style="margin-top:12px">Reading across: the boss fight needs about the same work from the PC as the first 3:30 (@@PCB@@ against @@PC0@@ ms a frame), yet your phone spent @@PHB@@ ms on it against @@PH0@@. From 3:30 to 7:10 the work really did grow, by about 60%: four, then five weapons and more shots. The phone's dips came on top of that.</p>
</section>

<section>
<h2>Every long run on your phone has these windows</h2>
<div class="tablewrap"><table>
<thead><tr><th>Run</th><th>Played</th><th>Slow windows</th><th>Seconds in them</th><th>Windows with under 150 creatures</th><th>Fewest creatures in one</th><th>First one at</th><th>Longest</th></tr></thead>
<tbody>@@WINROWS@@</tbody>
</table></div>
<p class="dim" style="margin-top:12px">A slow window here is 5 seconds or more at over 22 ms a frame. The afternoon Stage 2 run lasted only 3 minutes, and its one window came with 210-260 creatures alive: that one is the crowd and the phone together.</p>
</section>

<section>
<h2>The causes, re-ranked</h2>
<div class="causes">
<div class="cause"><h3>1. The phone slows down</h3><p>Your phone runs at full speed for the first few minutes of a run, then dips to about two thirds for 10 to 40 seconds at a time, and later stays near 60%. Heat is the most likely reason. Reviews of the Tensor G3 measured its CPU losing 58-60% under long load, and the windows start 2:30 to 6 minutes into a run. It could also be battery saver or charging, which I can't see from here. The replay proves that the phone changed speed; it doesn't prove why. Option G's plugin would log the heat and settle it.</p></div>
<div class="cause second"><h3>2. The cliff makes every dip about twice as bad</h3><p>When a frame runs over 16.7 ms, the next one runs two world steps to catch up, which makes it later still. In Stage 1's slow windows, a frame with one world step took @@ONE@@ ms and a frame with two took @@TWO@@ ms, and @@TWOSHARE@@ of the frames ran two. Without the cliff, a phone at two thirds of its speed would give about 45 fps, not 30.</p></div>
<div class="cause third"><h3>3. The crowd, in Stage 2 and Endless</h3><p>Stage 2's 15 spiders every 5 seconds pushed the crowd to 318, and Endless in this run reached 300 at 29 fps. That's still too much for a warm phone at 60 fps, as the first version found. But it isn't what slowed Stage 1.</p></div>
</div>
</section>

<section>
<h2>Your options, re-ranked</h2>
<p>Ranked again with both runs in mind. The letters are the same as in the first version, so you can still refer to them; I is new. C and D are now built, and their rows say what was measured. For the others, the numbers are my estimates from the measurements above, not tests of the changes.</p>
<div class="tablewrap"><table>
<thead><tr><th></th><th>Option</th><th>Effect</th><th>What you lose visually</th><th>Work</th></tr></thead>
<tbody>@@SOLROWS@@</tbody>
</table></div>
<div class="opts" style="margin-top:16px">@@SOLCARDS@@</div>
</section>

<section>
<h2>The Stage 2 run in detail</h2>
<p>This is the first version's analysis of your run of 4 November, afternoon (Drifter, Stage 2, 3:04 long). It held 60 fps for 2:28, then fell to about 26 fps within 8 seconds. The numbers are unchanged. The one thing the Stage 1 run changes is the room for creatures in the second chart: those lines fit the phone at normal speed, and in a slow window the room shrinks a lot. Stage 1 fell to 30 fps with 35-140 creatures.</p>
</section>

<section>
<h3>The run, second by second</h3>
<figure>
<div class="legend"><span><i style="background:#f5b82a"></i>World steps (moving the crowd, shots, hero)</span><span><i style="background:#4a8ae0"></i>Per-frame scripts (mostly writing the crowd to the GPU)</span><span><i style="background:#5b6780"></i>The rest (sending draw calls, waiting for the screen)</span><span><i style="background:#ff6b6b"></i>Creatures alive</span></div>
@@TIMELINE@@
<figcaption>Your phone's own numbers, averaged over 2 seconds. Up to 2:28 the "rest" is mostly idle waiting: there's spare time. In the red window the frame more than doubles while the crowd grows slowly. After 2:52 the crowd is bigger but the frame is much cheaper: the phone back at full speed.</figcaption>
</figure>
</section>

<section>
<h3>How many creatures fit</h3>
<figure>
@@LINES@@
<figcaption>Frame time on your phone by crowd size: straight lines fitted to two stretches of play. Warm: this run before 2:28. Cool: the first five minutes of your long run of 24 October (version 0.88). Above the dashed line you lose 60 fps, and then the cliff adds about 10 ms more. The fits are approximate and don't include heavy builds with many shots.</figcaption>
</figure>
</section>

<section>
<h3>Where the time goes</h3>
<figure>
@@BARS@@
<figcaption>Milliseconds a frame with 288 creatures, measured on the PC with your run's creature mix and a stronger build so that gems pile up. Your phone runs the same work about 2 to 2.5 times slower when warm. Yellow is the crowd: 60% of the frame's total and 80% of the part we can name.</figcaption>
</figure>
<h3 style="margin-top:18px">What I ruled out</h3>
<div class="notcause">
<div><b>The spider's art</b>300 spiders against 300 skeletons on the PC: 7.67 ms against 7.43 ms. The count matters, not the creature.</div>
<div><b>Too many pixels of creatures</b>At 319 creatures, their pictures cover 0.77 of a screen. That's not much overdraw for a mobile GPU.</div>
<div><b>Damage numbers</b>About 0.35 ms at 288 creatures on the PC, when turned off. They have already been thinned since pass 102.</div>
<div><b>Gems lying around</b>281 gems cost 0.09 ms. Your run had 217 by the end.</div>
<div><b>Your build</b>Two weapons at level 2 and 1. Few shots were flying (0-5).</div>
<div><b>The new UI</b>The HUD costs 0.14 ms. I can't fully rule out the phone's GPU from here, but its load shows up in the "rest", which stayed at 5-6 ms outside the slow window.</div>
</div>
</section>

<section>
<h2>Would changing the sprite sheets help?</h2>
<p>Short answer: for this slowdown, barely. It would help memory and loading times. Here's why, and what each change does.</p>
<div class="tablewrap"><table>
<thead><tr><th>Change</th><th>What it does</th><th>Helps speed in a fight?</th><th>Visual cost</th></tr></thead>
<tbody>
<tr><td><b>PNG to WebP, or a better lossy setting</b></td><td>Our strips are already imported as lossy WebP. This only changes the size of the install: on the GPU each one is decoded back to full colour, 4 bytes a pixel. Godot's docs say so directly.</td><td>No</td><td>Slight at very low quality</td></tr>
<tr><td><b>GPU compression (ETC2)</b></td><td>Pictures stay compressed on the GPU at a quarter of the memory: Stage 2's played strips, about 123 MB, become about 31 MB. Less memory traffic means a little less heat, and pictures load faster at the start of a run with no decoding. Our renderer can't use the better ASTC format: the docs say that option is ignored in Compatibility.</td><td>Very little: the GPU isn't what's limiting these frames</td><td>Small blocks along outlines and soft edges. Godot's docs warn against it for 2D UI, but our sprites are drawn in the 3D scene. I'd test 3 or 4 strips by eye</td></tr>
<tr><td><b>Smaller frames</b> (say 256 px cells to 128-160 px for small creatures and looks)</td><td>Less memory, and at the phone's real size a creature shows at roughly 100-160 pixels, so large cells are partly wasted.</td><td>Very little</td><td>Softer sprites in close-ups: the arena's zoom and store captures would show it, normal play hardly</td></tr>
<tr><td><b>Trim the empty space round each frame</b> (tight quads)</td><td>Fewer see-through pixels for the GPU to test. On tile-based mobile GPUs, alpha-tested overdraw is costly.</td><td>Little: creature quads only cover 77% of a screen, so there's little to save</td><td>None</td></tr>
<tr><td><b>Fewer frames in a cycle</b> (12 to 8)</td><td>Saves memory, not time: a frame's cost is the same either way.</td><td>No</td><td>Choppier walks</td></tr>
</tbody>
</table></div>
<p style="margin-top:14px">The reason is simple: these frames are limited by script work on the CPU. A picture's format doesn't change how long the script takes to move a creature. Worth doing at some point for memory, install size and start-up, but not as the cure. I'd do it after the crowd work.</p>
</section>

<section>
<h2>What others do</h2>
<p>I found little written specifically about Godot survivor games on phones, so treat these as nearby experience. Reliable sources are the Godot and Android docs; the rest are reports from individuals.</p>
<ul>@@SOURCES@@</ul>
</section>

<section class="pick">
<h2>My recommendation, updated</h2>
<p><b>First, play the new build.</b> C is in it. Try Stage 2 or Endless, where the crowd is big. The next report can then use real numbers from your phone, because each run record says whether the compiled crowd ran.</p>
<p><b>Next, B.</b> It's small, costs nothing you can see, and helps every slow stretch on every stage, which C can't fully do for a small crowd. Stage 1's slow windows should go from about 30 fps to about 45, and more with C on top.</p>
<p><b>Then G, as a small Android plugin</b>, which goes after the main cause. First it writes the phone's heat into the run record, so we know rather than guess. Then it tells Android each frame's deadline, and eases the game off when the phone is close to slowing down.</p>
<p><b>Then more creatures.</b> The pool still stops at 320, so the map's cap of 500 can't be reached. Raising it is one number, but it changes how hard the stages are, so I'd rather you see the phone's numbers first and choose. A automatic budget and I are still there if you want them.</p>
<p style="margin:0"><b>Two questions that would help:</b> were you charging the phone during this evening's Stage 1 run? And is Battery Saver on? Both change how a Pixel slows down.</p>
</section>
</main>
"""


def main():
    d = json.load(open(RUN, encoding="utf-8"))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page(d))
    print("wrote", OUT, os.path.getsize(OUT))


if __name__ == "__main__":
    main()
