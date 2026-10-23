"""Pass 101, lane FPS: the run record's frame times (schema 3: every row's frames, frame_ms, frame_max, frame_p95, proj,
pickups; the header's frame_timing) where Garry reads them. selftest.py discovers this file and hands it `check`,
`run_node` and the `server` module. Nothing here runs Godot or touches the network.

Groups:
  record  sim_avg.js fromRecord on a schema 3 record (the DASH78 fixture with frames added): the frame series, fps,
          the shots and the pickups, one value a row, a frameless second carrying the last; a headless or --fixed-fps
          record keeps its shots and pickups but no frame times; an old record (the fixture as it is) gains nothing
          and keeps its keys; the averaged view (aggregate + sim_model charts) draws Frame time and What the frame drew
          in the Performance section for the new record, nothing of it for the old one
  csv     the dashboard's csv-lib and tools/analytics_csv.py give the same rows CSV byte for byte on the new record (the
          frame columns after near6, a frameless second empty) and on the old one (no frame column)
  page    the dashboard parses, has the Frame time card, reads the rows' frame keys; SCHEMA.md documents them
"""
import copy
import json
import os
import re
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TESTDATA = os.path.join(HERE, "testdata")
FRAME_KEYS = ("frame_ms", "frame_p95", "frame_max", "fps")

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
    const defs2 = M.charts(two, null, {});
    const pick = {};
    for (const k of ['frame_ms', 'frame_p95', 'frame_max', 'fps', 'proj', 'pickups']) if (p[k]) pick[k] = p[k];
    return { keys: Object.keys(p).sort(), n: p.t.length, series: pick,
      charts: defs.map((c) => [c.id, c.section, c.lines.map((l) => l.key)]), charts2: defs2.map((c) => c.id),
      avg_ms: res.series.frame_ms ? res.series.frame_ms.mean.slice(0, 5) : null };
  });
  out.sections = M.SECTIONS.map((s) => s.id);
  process.stdout.write(JSON.stringify(out));
});
"""

CSV_RUNNER = r"""
'use strict';
const fs = require('fs');
const vm = require('vm');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(process.argv[2], 'utf8'), ctx);
vm.runInContext(fs.readFileSync(process.argv[3], 'utf8'), ctx);
const data = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
const t = ctx.RunCSV.rowsTable(data);
process.stdout.write(ctx.RunCSV.toCSV(t.columns, t.rows));
"""


def new_record(rec):
    """The fixture record as schema 3 writes it: every row its frames (a frameless second at row 5), shots, pickups."""
    r = copy.deepcopy(rec)
    r["schema"] = 3
    r["frame_timing"] = {"valid": True, "why": "", "max_fps": 60, "frame_cap": 60, "vsync": 1, "refresh_hz": 120.0, "physics_hz": 60}
    for i, row in enumerate(r["samples"]):
        if i == 5:
            row["frames"] = 0
        else:
            row["frames"] = 60 - (i % 7)
            row["frame_ms"] = round(16.0 + (i % 11) * 0.7, 1)
            row["frame_p95"] = round(row["frame_ms"] + 3.0, 1)
            row["frame_max"] = round(row["frame_ms"] + 9.5, 1)
        row["proj"] = 3 * i
        if i % 4:
            row["pickups"] = 40 + i
    return r


def _csv_checks(check, recs):
    node = shutil.which("node")
    if not node:
        print("FPS101: node is not here: the CSV comparison is skipped")
        return
    import sys
    tools = os.path.join(ROOT, "tools")
    if tools not in sys.path:
        sys.path.insert(0, tools)
    import analytics_csv as AC
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    lib = re.search(r'<script id="csv-lib">(.*?)</script>', html, re.S).group(1)
    tmp = tempfile.mkdtemp(prefix="le_fps101_")
    try:
        libp = os.path.join(tmp, "csvlib.js")
        open(libp, "w", encoding="utf-8").write(lib)
        runp = os.path.join(tmp, "run.js")
        open(runp, "w", encoding="utf-8").write(CSV_RUNNER)
        for name, rec in recs:
            recp = os.path.join(tmp, name + ".json")
            open(recp, "w", encoding="utf-8").write(json.dumps(rec))
            pr = subprocess.run([node, runp, os.path.join(HERE, "sim_model.js"), libp, recp], capture_output=True)
            check(pr.returncode == 0, "FPS101 csv: the page's csv-lib ran on the %s record: %s" % (name, pr.stderr.decode("utf-8", "replace")[-300:]))
            if pr.returncode != 0:
                continue
            # bytes, decoded: text mode would turn the CSV's CR LF into LF
            js_csv = pr.stdout.decode("utf-8")
            cols, rows = AC.rows_table(AC.read_run(recp) if hasattr(AC, "read_run") else rec)
            py = AC.to_csv(cols, rows)
            check(py == js_csv, "FPS101 csv: the page and analytics_csv.py give the same rows CSV on the %s record (%d vs %d chars)" % (name, len(py), len(js_csv)))
            head = js_csv.split("\r\n")[0].split(",")
            if name == "new":
                k = head.index("near6") if "near6" in head else -1
                check(k >= 0 and head[k + 1:k + 7] == ["frames", "frame_ms", "frame_max", "frame_p95", "proj", "pickups"],
                      "FPS101 csv: the frame columns follow near6: %s" % head[k + 1:k + 7])
                line6 = js_csv.split("\r\n")[6].split(",")
                fi = head.index("frame_ms")
                check(line6[head.index("frames")] == "0" and line6[fi] == "", "FPS101 csv: a frameless second: frames 0, frame_ms empty: %s" % line6[fi - 1:fi + 3])
            else:
                check(not any(c in head for c in ("frames", "frame_ms", "proj", "pickups")), "FPS101 csv: an old record has no frame column")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _page_checks(check):
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    check("function renderFrames(grid, S)" in html and "renderCrowd, renderFrames, renderRates" in html, "FPS101 page: the dashboard draws the Frame time card after the crowd")
    check("r.frame_ms" in html and "r.frame_p95" in html and "r.frame_max" in html and "r.proj" in html and "r.pickups" in html,
          "FPS101 page: prep() reads the rows' frame keys")
    node = shutil.which("node")
    if node:
        scripts = re.findall(r"<script(?: id=\"[^\"]*\")?>(.*?)</script>", html, re.S)
        tmp = tempfile.mkdtemp(prefix="le_fps101_")
        try:
            for i, s in enumerate(scripts):
                path = os.path.join(tmp, "s%d.js" % i)
                open(path, "w", encoding="utf-8").write(s)
                p = subprocess.run([node, "--check", path], capture_output=True, text=True)
                check(p.returncode == 0, "FPS101 page: the dashboard's script %d parses: %s" % (i, p.stderr[-200:]))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    sch = open(os.path.join(ROOT, "analytics", "SCHEMA.md"), encoding="utf-8").read()
    for frag in ("frame_timing", "frame_ms", "frame_p95", "frame_max", "`proj`", "`pickups`", "m_frame_ms", "schema 3"):
        check(frag in sch, "FPS101 page: SCHEMA.md documents %s" % frag)


def checks(check, run_node, server):
    fixture_in = json.load(open(os.path.join(TESTDATA, "dash78_series_in.json"), encoding="utf-8"))
    old = fixture_in["record"]
    new = new_record(old)
    headless = copy.deepcopy(new)
    headless["frame_timing"] = dict(new["frame_timing"], valid=False, why="headless")
    out = run_node({"records": [new, old, headless]}, RUNNER)
    if out is None:
        print("FPS101: node is not here: the record checks are skipped")
    elif out:
        rn, ro, rh = out["records"]
        n = rn["n"]
        s = rn["series"]
        check(all(k in s and len(s[k]) == n for k in FRAME_KEYS + ("proj", "pickups")), "FPS101 record: fromRecord gives the frame series, one value a row: %s" % sorted(s))
        if all(k in s for k in FRAME_KEYS):
            rows = new["samples"]
            check(abs(s["frame_ms"][0] - rows[0]["frame_ms"]) < 1e-9 and s["frame_ms"][5] == s["frame_ms"][4] and s["frame_max"][6] == rows[6]["frame_max"],
                  "FPS101 record: a frameless second carries the last frame time: %s" % s["frame_ms"][3:8])
            check(abs(s["fps"][1] - round(1000.0 / rows[1]["frame_ms"], 1)) < 0.051, "FPS101 record: fps = 1000 / frame_ms: %s" % s["fps"][:3])
            check(s["proj"][7] == 21 and s["pickups"][4] == 0 and s["pickups"][5] == 45, "FPS101 record: the shots and the pickups (0 where the row left it out): %s" % s["pickups"][:6])
        ids = [c[0] for c in rn["charts"]]
        perf = [c for c in rn["charts"] if c[1] == "perf"]
        check([c[0] for c in perf] == ["frame_time", "frame_load"] and perf[0][2] == ["frame_ms", "frame_p95", "frame_max"] and perf[1][2] == ["alive", "proj", "pickups"],
              "FPS101 record: one run's charts end with Frame time and What the frame drew in Performance: %s" % perf)
        check("frame_time" in rn["charts2"] and rn["avg_ms"] is not None and abs(rn["avg_ms"][0] - new["samples"][0]["frame_ms"]) < 1e-9,
              "FPS101 record: two runs average their frame times: %s" % rn["avg_ms"])
        check(not any(k in ro["keys"] for k in FRAME_KEYS + ("proj", "pickups")) and "frame_time" not in [c[0] for c in ro["charts"]]
              and not any(c[1] == "perf" for c in ro["charts"]), "FPS101 record: an old record gains no frame series and no Performance chart: %s" % ro["keys"])
        check(sorted(set(rn["keys"]) - set(FRAME_KEYS) - {"proj", "pickups"}) == ro["keys"], "FPS101 record: the rest of fromRecord is unchanged by the frames")
        check(not any(k in rh["keys"] for k in FRAME_KEYS) and "proj" in rh["keys"] and "frame_time" not in [c[0] for c in rh["charts"]] and "frame_load" in [c[0] for c in rh["charts"]],
              "FPS101 record: a headless record keeps its shots and pickups, never its frame times: %s" % [k for k in rh["keys"] if k in FRAME_KEYS + ("proj", "pickups")])
        check(out["sections"][-1] == "perf", "FPS101 record: the Performance section comes last: %s" % out["sections"])
    _csv_checks(check, [("new", new), ("old", old)])
    _page_checks(check)
