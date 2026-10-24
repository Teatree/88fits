"""Pass 102, lane STEADY: the run record's work times (schema 4: every row's steps, steps_max, phys_ms, phys_max, proc_ms,
proc_max, rest_ms, lost_ms; the header's work, heat and frame_timing.max_steps) where Garry reads them. selftest.py
discovers this file and hands it `check`, `run_node` and the `server` module. Nothing here runs Godot or the network.

Groups:
  record  sim_avg.js fromRecord on a schema 4 record (FPS101's schema 3 record with the work keys added): the work
          series (world_ms, proc_ms, rest_ms, work_ms, steps_frame, world_speed), one value a row, a frameless second
          carrying the last; the schema 3 record gains none of them; the charts: What a frame cost and World speed and
          steps in Performance after FPS101's two, none for the older record; two runs average
  csv     the dashboard's csv-lib and tools/analytics_csv.py give the same rows CSV byte for byte on the schema 4 record
          (the work columns after pickups; a frameless second empty, lost_ms 0)
  page    the dashboard parses, draws the work part of the Frame time card and the heat table; SCHEMA.md documents the keys
"""
import copy
import json
import os
import re
import shutil
import subprocess
import tempfile

import selftest_FPS101 as F

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TESTDATA = os.path.join(HERE, "testdata")
WORK_SERIES = ("world_ms", "proc_ms", "rest_ms", "work_ms", "steps_frame", "world_speed")
WORK_COLS = ["steps", "steps_max", "phys_ms", "phys_max", "proc_ms", "proc_max", "rest_ms", "lost_ms"]

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const A = require(path.join(dir, 'sim_avg.js'));
const M = require(path.join(dir, 'sim_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.records = q.records.map((rec) => {
    const p = A.fromRecord(rec);
    const res = A.aggregate([{ k: 1, d: p, rec: {} }], { limit: 100000, hero: p.meta.hero }, {}, {});
    const defs = M.charts(res, null, {});
    const two = A.aggregate([{ k: 1, d: p, rec: {} }, { k: 2, d: p, rec: {} }], { limit: 100000, hero: p.meta.hero }, {}, {});
    const pick = {};
    for (const k of ['world_ms', 'proc_ms', 'rest_ms', 'work_ms', 'steps_frame', 'world_speed']) if (p[k]) pick[k] = p[k];
    return { keys: Object.keys(p).sort(), n: p.t.length, series: pick,
      charts: defs.map((c) => [c.id, c.section, c.lines.map((l) => l.key)]),
      avg_work: two.series.work_ms ? two.series.work_ms.mean.slice(0, 5) : null };
  });
  process.stdout.write(JSON.stringify(out));
});
"""


def new_record(rec):
    """FPS101's schema 3 record as schema 4 writes it: every row with frames its work times (lost time from row 10)."""
    r = F.new_record(rec)
    r["schema"] = 4
    r["frame_timing"]["max_steps"] = 2
    for i, row in enumerate(r["samples"]):
        if row.get("frames", 0) > 0:
            row["steps"] = 60 + (i % 3)
            row["steps_max"] = 2 if i % 4 == 0 else 1
            row["phys_ms"] = round(3.0 + (i % 5) * 0.11, 2)
            row["phys_max"] = round(row["phys_ms"] + 2.5, 1)
            row["proc_ms"] = round(4.0 + (i % 7) * 0.13, 2)
            row["proc_max"] = round(row["proc_ms"] + 3.0, 1)
            row["rest_ms"] = round(8.0 + (i % 3) * 0.4, 1)
            if i >= 10:
                row["lost_ms"] = 25 * (i % 3)
                if row["lost_ms"] == 0:
                    del row["lost_ms"]
    r["work"] = {"frames": 999, "steps": 1000, "lost_s": 0.5}
    r["heat"] = {"band": 50, "bucket_s": 60, "minutes": 1, "frame_ms": {"0": [16.5]}, "work_ms": {"0": [7.3]}}
    return r


def _csv_checks(check, rec):
    node = shutil.which("node")
    if not node:
        print("STEADY102: node is not here: the CSV comparison is skipped")
        return
    import sys
    tools = os.path.join(ROOT, "tools")
    if tools not in sys.path:
        sys.path.insert(0, tools)
    import analytics_csv as AC
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    lib = re.search(r'<script id="csv-lib">(.*?)</script>', html, re.S).group(1)
    tmp = tempfile.mkdtemp(prefix="le_steady102_")
    try:
        libp = os.path.join(tmp, "csvlib.js")
        open(libp, "w", encoding="utf-8").write(lib)
        runp = os.path.join(tmp, "run.js")
        open(runp, "w", encoding="utf-8").write(F.CSV_RUNNER)
        recp = os.path.join(tmp, "new.json")
        open(recp, "w", encoding="utf-8").write(json.dumps(rec))
        pr = subprocess.run([node, runp, os.path.join(HERE, "sim_model.js"), libp, recp], capture_output=True)
        check(pr.returncode == 0, "STEADY102 csv: the page's csv-lib ran on the schema 4 record: %s" % pr.stderr.decode("utf-8", "replace")[-300:])
        if pr.returncode != 0:
            return
        js_csv = pr.stdout.decode("utf-8")
        cols, rows = AC.rows_table(rec)
        py = AC.to_csv(cols, rows)
        check(py == js_csv, "STEADY102 csv: the page and analytics_csv.py give the same rows CSV (%d vs %d chars)" % (len(py), len(js_csv)))
        head = js_csv.split("\r\n")[0].split(",")
        k = head.index("pickups") if "pickups" in head else -1
        check(k >= 0 and head[k + 1:k + 1 + len(WORK_COLS)] == WORK_COLS, "STEADY102 csv: the work columns follow pickups: %s" % head[k + 1:k + 9])
        line6 = js_csv.split("\r\n")[6].split(",")
        si, li = head.index("steps"), head.index("lost_ms")
        check(line6[si] == "" and line6[head.index("phys_ms")] == "" and line6[li] == "0",
              "STEADY102 csv: a frameless second: steps and phys_ms empty, lost_ms 0: %s" % line6[si:li + 1])
        line12 = js_csv.split("\r\n")[12].split(",")
        check(line12[li] == str(rec["samples"][11].get("lost_ms", 0)), "STEADY102 csv: lost_ms as recorded: %s" % line12[li])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _page_checks(check):
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    check("function renderWork(c, S)" in html and "renderWork(c, S);" in html, "STEADY102 page: the Frame time card draws its work part")
    for frag in ("r.steps", "r.phys_ms", "r.proc_ms", "r.rest_ms", "r.lost_ms", "S.run.heat"):
        check(frag in html, "STEADY102 page: prep()/renderWork read %s" % frag)
    node = shutil.which("node")
    if node:
        scripts = re.findall(r"<script(?: id=\"[^\"]*\")?>(.*?)</script>", html, re.S)
        tmp = tempfile.mkdtemp(prefix="le_steady102_")
        try:
            for i, s in enumerate(scripts):
                path = os.path.join(tmp, "s%d.js" % i)
                open(path, "w", encoding="utf-8").write(s)
                p = subprocess.run([node, "--check", path], capture_output=True, text=True)
                check(p.returncode == 0, "STEADY102 page: the dashboard's script %d parses: %s" % (i, p.stderr[-200:]))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    sch = open(os.path.join(ROOT, "analytics", "SCHEMA.md"), encoding="utf-8").read()
    for frag in ("schema 4", "max_steps", "`work`", "`heat`", "`steps`, `steps_max`", "`phys_ms`, `phys_max`", "`proc_ms`, `proc_max`",
                 "`rest_ms`", "`lost_ms`", "m_work_ms", "heat_work_ms", "WorkClock"):
        check(frag in sch, "STEADY102 page: SCHEMA.md documents %s" % frag)


def checks(check, run_node, server):
    fixture_in = json.load(open(os.path.join(TESTDATA, "dash78_series_in.json"), encoding="utf-8"))
    old3 = F.new_record(fixture_in["record"])
    new = new_record(fixture_in["record"])
    out = run_node({"records": [new, old3]}, RUNNER)
    if out is None:
        print("STEADY102: node is not here: the record checks are skipped")
    elif out:
        rn, ro = out["records"]
        n = rn["n"]
        s = rn["series"]
        check(all(k in s and len(s[k]) == n for k in WORK_SERIES), "STEADY102 record: fromRecord gives the work series, one value a row: %s" % sorted(s))
        if all(k in s for k in WORK_SERIES):
            rows = new["samples"]
            r1 = rows[1]
            world = r1["steps"] * r1["phys_ms"] / r1["frames"]
            check(abs(s["world_ms"][1] - round(world, 2)) < 0.006 and abs(s["work_ms"][1] - round(world + r1["proc_ms"], 2)) < 0.006,
                  "STEADY102 record: world_ms = steps x phys_ms / frames, work_ms = world + process: %s %s" % (s["world_ms"][:2], s["work_ms"][:2]))
            check(s["proc_ms"][5] == s["proc_ms"][4] and s["rest_ms"][5] == s["rest_ms"][4], "STEADY102 record: a frameless second carries the last: %s" % s["proc_ms"][3:7])
            check(abs(s["steps_frame"][1] - round(r1["steps"] / r1["frames"], 2)) < 0.006, "STEADY102 record: steps a frame: %s" % s["steps_frame"][:3])
            lost = rows[11].get("lost_ms", 0)
            check(abs(s["world_speed"][11] - round(1000.0 / (1000.0 + lost), 3)) < 0.0006 and s["world_speed"][2] == 1.0,
                  "STEADY102 record: world speed = 1000 / (1000 + lost_ms): %s" % s["world_speed"][9:13])
        perf = [c for c in rn["charts"] if c[1] == "perf"]
        check([c[0] for c in perf] == ["frame_time", "frame_load", "frame_work", "world_speed"]
              and perf[2][2] == ["world_ms", "proc_ms", "rest_ms"] and perf[3][2] == ["world_speed", "steps_frame"],
              "STEADY102 record: Performance ends with What a frame cost and World speed and steps: %s" % perf)
        t0 = int(round(new["samples"][1]["t"]))
        check(rn["avg_work"] is not None and t0 < len(rn["avg_work"]) and abs(rn["avg_work"][t0] - s["work_ms"][1]) < 1e-9,
              "STEADY102 record: two runs average their work (second %d): %s" % (t0, rn["avg_work"]))
        check(not any(k in ro["keys"] for k in WORK_SERIES) and not any(c[0] in ("frame_work", "world_speed") for c in ro["charts"]),
              "STEADY102 record: a schema 3 record gains no work series and no work chart: %s" % [k for k in ro["keys"] if k in WORK_SERIES])
        check(sorted(set(rn["keys"]) - set(WORK_SERIES)) == ro["keys"], "STEADY102 record: the rest of fromRecord is unchanged by the work keys")
    _csv_checks(check, new)
    _page_checks(check)
