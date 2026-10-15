"""Pass 78, lane DASH: the Sim's charts and averages in analytics/dashboard.html, and the runs from PostHog.
selftest.py discovers this file and hands it `check`, `run_node` and the `server` module. Nothing here runs Godot or
touches the network: every folder is a temporary one, the PostHog answers are recorded ones.

Groups:
  round    sim_avg.js pyRound against Python's round() (half to even on the exact binary value)
  agg      sim_avg.js aggregate() against tools/sim_batch.py aggregate() on the same player files: made-up runs of four
           settings, three hand-made runs with a gap and a failed one, and the real sims under tools/dl/sim/runs when there
           are any: every series, band, breakdown, marker, summary number and run, equal
  series   sim_avg.js series() on testdata/dash78_series_in.json equals game/tools/sim_run.gd series()'s own output
           (dash78_series_out.json, written by game/tools/series_fixture.gd); fromRecord's meta and the keys an older
           record never wrote left out; one run averages to itself with no bands and no "runs playing" chart
  parts    tools/posthog_runs.py join_parts on the game's own run_record parts (dash78_parts.json): the text back, in any
           order; a part missing, a broken one, a wrong md5 refused
  download posthog_runs.download on recorded API answers: the runs written (.json with its remote block, the .js twin),
           index.js / index.json, players by name (two installs of one name apart, an unnamed one by its id), a run with
           a part missing waits, a broken one is named, --player, a second download fetches nothing, --force, --list, the
           read budget's 429, the key never written
  page     the dashboard loads the Sim's modules and styles from tools/level_editor/, index.html loads sim_plot.js
           between sim_model.js and sim.js, the scripts parse, the CSV column lists of the page and analytics_csv.py match
"""
import base64
import gzip
import hashlib
import io
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
TESTDATA = os.path.join(HERE, "testdata")

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
  if (q.round) out.round = q.round.map(([v, nd]) => A.pyRound(v, nd));
  if (q.agg) out.agg = q.agg.map((c) => { const r = A.aggregate(c.players, c.settings, {}, {}); return { t: r.t, playing: r.playing, series: r.series, breakdowns: r.breakdowns, markers: r.markers, summary: r.summary, players: r.players, rules: r.rules }; });
  if (q.series) { const rec = q.series.record; out.series = A.series(rec.samples, rec.events, [], q.series.end_ev, q.series.evo_ids); }
  if (q.records) out.records = q.records.map((rec) => { const p = A.fromRecord(rec); return { keys: Object.keys(p).sort(), meta: p.meta, held: Object.keys(p.held_by || {}).sort(), n: p.t.length }; });
  if (q.one) {
    const p = A.fromRecord(q.one);
    const res = A.aggregate([{ k: 1, d: p, rec: {} }], { limit: 100000, hero: p.meta.hero }, {}, q.one.names || {});
    const defs = M.charts(res, null, {});
    out.one = { ids: defs.map((c) => c.id), bands: defs.reduce((a, c) => a + c.bands.length, 0), playing: res.playing.every((v) => v === 1), how: defs.find((c) => c.id === 'hp').how, T: res.t.length - 1 };
    const res2 = A.aggregate([{ k: 1, d: p, rec: {} }, { k: 2, d: p, rec: {} }], { limit: 100000, hero: p.meta.hero }, {}, {});
    const defs2 = M.charts(res2, null, {});
    out.two = { ids: defs2.map((c) => c.id), bands: defs2.reduce((a, c) => a + c.bands.length, 0) };
  }
  process.stdout.write(JSON.stringify(out));
});
"""


def _diff(a, b, path="", out=None, limit=8):
    """Where two JSON values differ (exactly: the two sides must give the same numbers)."""
    if out is None:
        out = []
    if len(out) >= limit:
        return out
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b), key=str):
            if k not in a or k not in b:
                out.append("%s/%s only in %s" % (path, k, "python" if k in a else "js"))
            else:
                _diff(a[k], b[k], "%s/%s" % (path, k), out, limit)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append("%s: %d vs %d entries" % (path, len(a), len(b)))
        else:
            for i, (x, y) in enumerate(zip(a, b)):
                _diff(x, y, "%s[%d]" % (path, i), out, limit)
    elif a != b or type(a) is bool and type(b) is not bool:
        out.append("%s: %r vs %r" % (path, a, b))
    return out


def _tiny_players():
    """Three hand-made runs of 10 s (as selftest_SIM77): A to 10, B dies at 5, C to 10 with a gap at t=4; and a failed run."""
    def run(ts, hp, dps, kills, deaths, level, kills_by=None, events=None, end_reason="limit"):
        n = len(ts)
        return {"t": ts, "hp": hp, "hp_max": [100] * n, "dps": dps, "est": [10] * n, "alive": [5] * n, "press_hp": [50] * n,
                "press_dmg": [5] * n, "kills": kills, "deaths": deaths, "level": level, "gold_total": list(range(n)),
                "xp_total": [x * 2 for x in range(n)], "clock": ts, "stage": [1] * n, "took": [3] * n, "healed": [1] * n, "hits": [1] * n,
                "kills_by": kills_by or {"goblin": kills}, "alive_by": {"goblin": [5] * n},
                "dmg_by": {"revolver": [sum(dps[:i + 1]) for i in range(n)]}, "events": events or [],
                "meta": {"end_reason": end_reason, "end_t": float(ts[-1]), "wall_s": 20.0, "boot_s": 10.0, "build_text": "Revolver 1"}}
    a = run(list(range(1, 11)), [100] * 10, [10, 0, 0, 0, 0, 10, 0, 0, 0, 0], list(range(1, 11)), [0] * 10, [1, 1, 2, 2, 2, 3, 3, 3, 4, 4],
            kills_by={"goblin": list(range(1, 11)), "slime": [0] * 7 + [1, 2, 3]},
            events=[{"t": 0, "kind": "stage", "stage": 1}, {"t": 4, "kind": "boss_start", "id": "king", "mult": 1.2, "hp": 500},
                    {"t": 7, "kind": "boss_end", "id": "king"}, {"t": 8, "kind": "stage", "stage": 2}])
    b = run([1, 2, 3, 4, 5], [100, 80, 60, 20, 0], [20] * 5, [1, 2, 3, 4, 5], [0, 0, 0, 0, 1], [1, 1, 1, 2, 2],
            events=[{"t": 3, "kind": "boss_start", "id": "king", "mult": 0.8, "hp": 400}, {"t": 5, "kind": "death"}], end_reason="death")
    c = run([1, 2, 3, 5, 6, 7, 8, 9, 10], [90, 90, 90, 70, 70, 70, 70, 70, 70], [0] * 9, [2, 4, 6, 8, 10, 12, 14, 16, 18], [0] * 9,
            [1, 1, 1, 1, 2, 2, 2, 2, 2], events=[{"t": 6, "kind": "boss_start", "id": "king"}, {"t": 9, "kind": "boss_end", "id": "king"},
                                                 {"t": 10, "kind": "stage", "stage": 2}])
    return [(1, a, {"seed": 1}), (2, b, {"seed": 2}), (3, c, {"seed": 3}), (4, None, {"seed": 4, "problem": "no JSON written", "end_t": 0})]


def _agg_cases(SB, real_max=1):
    cases = [("three hand-made runs and a failed one", _tiny_players(), {"players": 4, "limit": 10, "death": "end"})]
    for st in ({"players": 4, "limit": 600, "death": "gold"}, {"players": 3, "limit": 300, "death": "keep"},
               {"players": 7, "limit": 900, "death": "end"}, {"players": 1, "limit": 200, "death": "end"}):
        cases.append(("made-up %s" % st, [(k, SB.synthetic_player(k, 10 * k + 3, st), {"seed": k}) for k in range(1, st["players"] + 1)], st))
    real = sorted(d for d in (os.listdir(os.path.join(SB.SIM_DIR, "runs")) if os.path.isdir(os.path.join(SB.SIM_DIR, "runs")) else []))
    for name in real[:real_max]:
        folder = os.path.join(SB.SIM_DIR, "runs", name)
        files = sorted(f for f in os.listdir(os.path.join(folder, "players")) if re.match(r"^p\d+\.json$", f)) if os.path.isdir(os.path.join(folder, "players")) else []
        if not files:
            continue
        ps = []
        for k, f in enumerate(files, 1):
            d, prob = SB.load_player(os.path.join(folder, "players", f))
            ps.append((k, d, {"seed": k, "problem": prob}))
        cases.append(("the real sim " + name, ps, SB.read_json(os.path.join(folder, "settings.json")) or {"limit": 1500}))
    return cases


def _record_parts(text, part_max=100000, run_id="r", extra=None):
    """run_record parts the way the game makes them (Analytics.record_parts), for made-up runs."""
    raw = text.encode("utf-8")
    gz = gzip.compress(raw)
    b64 = base64.b64encode(gz).decode("ascii")
    n = max(1, -(-len(b64) // part_max))
    out = []
    for i in range(n):
        p = {"part": i + 1, "parts": n, "data": b64[i * part_max:(i + 1) * part_max], "enc": "gzip+base64", "format": 1,
             "raw_bytes": len(raw), "gz_bytes": len(gz), "md5": hashlib.md5(raw).hexdigest(), "run_id": run_id, "dev": False,
             "app_version": "0.64", "distinct_id": "?", "hero": "astro"}
        p.update(extra or {})
        out.append(p)
    return out


class _Answer:
    """A recorded PostHog answer as urlopen gives it."""
    def __init__(self, body, headers=None):
        self._body = json.dumps(body).encode("utf-8")
        self.headers = headers or {}

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class _FakePostHog:
    """The query API on recorded events: the list query (uuid, timestamp, distinct_id, the person's names) and the
    payload query (uuid, properties as a JSON string), as /api/projects/@current/query/ answers them."""
    def __init__(self, events):
        self.events = sorted(events, key=lambda e: e["ts"])
        self.lists = 0
        self.fetches = 0
        self.fetched = []
        self.budget_after = None

    def urlopen(self, req, timeout=None):
        import urllib.error
        if self.budget_after is not None and self.lists + self.fetches >= self.budget_after:
            raise urllib.error.HTTPError(req.full_url, 429, "Too Many Requests", {"Retry-After": "1800"}, io.BytesIO(b'{"code": "api_queries_budget_exceeded"}'))
        assert req.get_header("Authorization") == "Bearer phx_test", "the key goes as a bearer header"
        q = json.loads(req.data.decode("utf-8"))["query"]["query"]
        lo = re.search(r"timestamp >= toDateTime\('([^']+)'\)", q).group(1)
        if "properties FROM events" in q:
            self.fetches += 1
            want = set(re.findall(r"'([0-9a-f-]{36})'", q.split(" IN (", 1)[1]))
            rows = [[e["uuid"], json.dumps(e["props"])] for e in self.events if e["uuid"] in want]
            self.fetched.extend(r[0] for r in rows)
            return _Answer({"columns": ["toString(uuid)", "properties"], "results": rows, "hasMore": False},
                           {"X-PostHog-Query-Bytes-Read": "1000", "X-PostHog-Query-Budget-Remaining-Bytes": "5000000"})
        self.lists += 1
        rows = [[e["uuid"], e["ts"], e["distinct_id"], e["name"], e["label"]] for e in self.events if e["ts"][:19] >= lo]
        limit = int(re.search(r"LIMIT (\d+)", q).group(1))
        return _Answer({"columns": ["toString(uuid)", "toString(timestamp)", "distinct_id", "name", "label"], "results": rows[:limit], "hasMore": len(rows) > limit},
                       {"X-PostHog-Query-Bytes-Read": "100", "X-PostHog-Query-Budget-Remaining-Bytes": "5000000"})


def _events_for(runs):
    """[{uuid, ts, distinct_id, name, label, props}] for made-up runs: (distinct_id, name, label, parts, ts)."""
    out = []
    n = 0
    for did, name, label, parts, ts in runs:
        for p in parts:
            n += 1
            out.append({"uuid": "0192aaaa-0000-7000-8000-%012d" % n, "ts": "%s.%06d" % (ts, n), "distinct_id": did, "name": name, "label": label,
                        "props": dict(p, distinct_id=did)})
    return out


def _download_checks(check, P, tmp):
    fixture = json.load(open(os.path.join(TESTDATA, "dash78_parts.json"), encoding="utf-8"))
    rec1 = json.loads(fixture["json"])
    p1 = [dict(p, run_id=rec1.get("run_id", "run-one"), dev=True, app_version="0.64") for p in fixture["parts"]]
    rec2 = {"schema": 2, "run_id": "0192bbbb-run2", "stamp": "2026-10-14T20-00-00", "started": "2026-10-14T20:00:00", "hero": "drifter",
            "hero_name": "Drifter", "result": "death", "length": 61.0, "level": 7, "kills": 120, "samples": [{"t": 1.0, "hp": 100.0}], "events": []}
    rec3 = dict(rec2, run_id="0192cccc-run3", stamp="2026-10-14T21-00-00", started="2026-10-14T21:00:00")
    rec4 = dict(rec2, run_id="0192dddd-run4", stamp="2026-10-14T22-00-00", started="2026-10-14T22:00:00", hero="astro")
    rec5 = dict(rec2, run_id="0192eeee-run5", stamp="2026-10-14T23-00-00", started="2026-10-14T23:00:00")
    rec6 = dict(rec2, run_id="0192ffff-run6", stamp="2026-10-15T00-00-00", started="2026-10-15T00:00:00")
    t2 = json.dumps(rec2)
    p3 = _record_parts(json.dumps(rec3), part_max=200, run_id=rec3["run_id"])
    bad6 = [dict(p, md5="0" * 32) for p in _record_parts(json.dumps(rec6), run_id=rec6["run_id"])]
    ia, ib, ic, idd = ("0192a001-0000-7000-8000-000000000001", "0192b002-0000-7000-8000-000000000002", "0192c003-0000-7000-8000-000000000003",
                       "0192d004-0000-7000-8000-000000000004")
    runs = [(ia, "Dusty Coyote 41", "Garry's phone", p1, "2026-10-14 19:00:00"),
            (ia, "Dusty Coyote 41", "Garry's phone", _record_parts(t2, run_id=rec2["run_id"], extra={"recovered": True}), "2026-10-14 20:10:00"),
            (ib, "Hungry Outlaw 94", "", p3[:1], "2026-10-14 21:10:00"),
            (ic, "Dusty Coyote 41", "", _record_parts(json.dumps(rec4), run_id=rec4["run_id"]), "2026-10-14 22:10:00"),
            (idd, "", "", _record_parts(json.dumps(rec5), run_id=rec5["run_id"]), "2026-10-14 23:10:00"),
            (ib, "Hungry Outlaw 94", "", bad6, "2026-10-15 00:10:00")]
    fake = _FakePostHog(_events_for(runs))
    saved = (P._key, P.urllib.request.urlopen, dict(P.STATS))
    P._key = lambda: "phx_test"
    P.urllib.request.urlopen = fake.urlopen
    out = os.path.join(tmp, "remote")
    logs = []
    try:
        import datetime
        since = datetime.datetime(2026, 10, 1)
        rep = P.download(out, since, (), False, False, log=logs.append)
        check(rep["new"] == 4 and rep["found"] == len(fake.events), "download: four whole runs written of %d parts found: %s" % (rep["found"], rep))
        check(len(rep["incomplete"]) == 1 and "0192cccc" in rep["incomplete"][0] and "parts missing" in rep["incomplete"][0],
              "download: a run with a part not in PostHog yet waits (not written): %s" % rep["incomplete"])
        check(len(rep["bad"]) == 1 and "md5" in rep["bad"][0], "download: a run whose md5 does not check is named: %s" % rep["bad"])
        keys = sorted(d for d in os.listdir(out) if os.path.isdir(os.path.join(out, d)))
        check(keys == ["Dusty_Coyote_41", "Dusty_Coyote_41_0192c0", "id_0192d004"], "download: a folder a player, two installs of one name apart, an unnamed one by its id: %s" % keys)
        f1 = [f for f in os.listdir(os.path.join(out, "Dusty_Coyote_41")) if f.endswith(".json")]
        check(len(f1) == 2 and all(os.path.isfile(os.path.join(out, "Dusty_Coyote_41", f[:-5] + ".js")) for f in f1), "download: a .json and its .js twin a run: %s" % f1)
        got1 = json.load(open(os.path.join(out, "Dusty_Coyote_41", sorted(f1)[0]), encoding="utf-8"))
        rm = got1.pop("remote")
        check(got1 == rec1, "download: the record exactly as the game sent it (the remote block apart)")
        check(rm["player"] == "Dusty Coyote 41" and rm["label"] == "Garry's phone" and rm["distinct_id"] == ia and rm["parts"] == len(p1)
              and len(rm["uuids"]) == len(p1) and rm["dev"] is True and rm["app_version"] == "0.64", "download: the remote block: %s" % {k: v for k, v in rm.items() if k != "uuids"})
        got2 = json.load(open(os.path.join(out, "Dusty_Coyote_41", sorted(f1)[1]), encoding="utf-8"))
        check(got2["remote"].get("recovered") is True and got2["result"] == "death", "download: a run sent at the next launch says so (recovered)")
        js = open(os.path.join(out, "Dusty_Coyote_41", sorted(f1)[0][:-5] + ".js"), encoding="utf-8").read()
        m = re.match(r'^\(window\.RUN_FILES = window\.RUN_FILES \|\| \{\}\)\[("[^"]+")\] = (.*);\n$', js, re.S)
        check(m is not None and json.loads(m.group(1)) == "Dusty_Coyote_41/" + sorted(f1)[0] and json.loads(m.group(2))["run_id"] == got1["run_id"],
              "download: the .js twin sets window.RUN_FILES[<its .json path>] for a file:// page")
        idx_js = open(os.path.join(out, "index.js"), encoding="utf-8").read()
        check(idx_js.startswith("window.REMOTE = ") and idx_js.rstrip().endswith(";"), "download: index.js sets window.REMOTE")
        idx = json.loads(idx_js[len("window.REMOTE = "):].rstrip().rstrip(";"))
        check(len(idx["runs"]) == 4 and len(idx["players"]) == 3 and all(set(r) >= {"file", "js", "player", "player_name", "started", "hero", "result", "length", "dev", "run_id"} for r in idx["runs"]),
              "download: the index: four runs, three players, each row its file, .js, player and the history fields: %s" % sorted(idx["runs"][0])[:12])
        pa = [p for p in idx["players"] if p["key"] == "Dusty_Coyote_41"][0]
        check(pa["runs"] == 2 and pa["label"] == "Garry's phone" and pa["dev_runs"] == 1, "download: a player's line: runs, Garry's label, dev runs: %s" % pa)
        check(json.load(open(os.path.join(out, "index.json"), encoding="utf-8")) == idx, "download: index.json is index.js's data")
        # again: nothing fetched for what is on disk
        before = fake.fetches
        fake.fetched = []
        rep2 = P.download(out, since, (), False, False, log=logs.append)
        check(rep2["new"] == 0 and rep2["skipped"] == len(p1) + 3, "download: a second time writes nothing new and skips every part on disk: %s" % rep2)
        on_disk_ids = (rec2["run_id"], rec4["run_id"], rec5["run_id"], rec1.get("run_id", "run-one"))
        check(not [u for u in fake.fetched if any(u == e["uuid"] for e in fake.events if e["props"]["run_id"] in on_disk_ids)],
              "download: a second time fetches no payload of a run on disk, only the ones still waiting (%d fetch queries)" % (fake.fetches - before))
        # one player only
        out2 = os.path.join(tmp, "remote2")
        rep3 = P.download(out2, since, ("hungry outlaw 94",), False, False, log=logs.append)
        check(rep3["new"] == 0 and rep3["found"] == 2 and len(rep3["incomplete"]) == 1, "download: --player keeps that player's parts only: %s" % rep3)
        rep4 = P.download(out2, since, ("Garry's phone",), False, False, log=logs.append)
        check(rep4["new"] == 2, "download: --player matches Garry's label too: %s" % rep4["new"])
        # --force fetches again; --list writes nothing
        rep5 = P.download(out2, since, ("Garry's phone",), True, False, log=logs.append)
        check(rep5["new"] == 2 and len([f for f in os.listdir(os.path.join(out2, "Dusty_Coyote_41")) if f.endswith(".json")]) == 2, "download: --force writes them again, once")
        out3 = os.path.join(tmp, "remote3")
        lines = []
        P.download(out3, since, (), False, True, log=lines.append)
        check(not os.path.exists(out3) and len(lines) == 4, "download: --list lists the players and writes nothing: %s" % lines)
        # the read budget spent: what came is kept, the rest waits
        fake.budget_after = fake.lists + fake.fetches + 1
        out4 = os.path.join(tmp, "remote4")
        rep6 = P.download(out4, since, (), False, False, log=logs.append)
        check(rep6["budget"] and "1800" in rep6["budget"], "download: PostHog's 429 (the read budget) stops it politely: %s" % rep6["budget"])
        fake.budget_after = None
        # the key is never written anywhere
        leaked = []
        for d, _, fs in os.walk(tmp):
            for f in fs:
                if "phx_" in open(os.path.join(d, f), encoding="utf-8", errors="replace").read():
                    leaked.append(f)
        check(not leaked and not any("phx_" in str(x) for x in logs), "download: the personal key is in no file and no line printed: %s" % leaked)
    finally:
        P._key, P.urllib.request.urlopen = saved[0], saved[1]
        P.STATS.clear()
        P.STATS.update(saved[2])


def _parts_checks(check, P):
    fixture = json.load(open(os.path.join(TESTDATA, "dash78_parts.json"), encoding="utf-8"))
    parts = fixture["parts"]
    check(len(parts) >= 2 and all(set(p) >= {"part", "parts", "data", "enc", "format", "raw_bytes", "gz_bytes", "md5"} for p in parts),
          "parts: the game's run_record parts carry their keys: %s" % sorted(parts[0]))
    text, why = P.join_parts(parts)
    check(text == fixture["json"] and not why, "parts: Python joins the game's own parts back into its record (gzip, base64, md5): %s" % why)
    text, why = P.join_parts(list(reversed(parts)))
    check(text == fixture["json"], "parts: in any order")
    text, why = P.join_parts(parts[1:])
    check(text is None and "parts missing" in why, "parts: a part missing is named: %s" % why)
    broken = [dict(p) for p in parts]
    broken[0]["data"] = "A" * len(broken[0]["data"])
    text, why = P.join_parts(broken)
    check(text is None and why, "parts: a broken part is refused: %s" % why)
    wrong = [dict(p, md5="0" * 32) for p in parts]
    text, why = P.join_parts(wrong)
    check(text is None and "md5" in why, "parts: a wrong md5 is refused: %s" % why)


def _page_checks(check):
    html = open(os.path.join(ROOT, "analytics", "dashboard.html"), encoding="utf-8").read()
    for f in ("sim_model.js", "sim_avg.js", "sim_plot.js"):
        check('src="../tools/level_editor/%s"' % f in html and os.path.isfile(os.path.join(HERE, f)), "page: the dashboard loads %s from the Level Editor" % f)
    check('href="../tools/level_editor/sim.css"' in html, "page: the dashboard links the Sim's styles")
    order = [html.find(x) for x in ('src="../tools/level_editor/sim_model.js"', 'src="../tools/level_editor/sim_avg.js"', 'src="../tools/level_editor/sim_plot.js"', '<script id="csv-lib">')]
    check(order == sorted(order) and order[0] > 0, "page: the modules before the page's own scripts: %s" % order)
    idx = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
    o2 = [idx.find('src="%s"' % n) for n in ("sim_model.js", "sim_plot.js", "sim.js")]
    check(all(x > 0 for x in o2) and o2 == sorted(o2), "page: index.html loads sim_plot.js between sim_model.js and sim.js: %s" % o2)
    node = shutil.which("node")
    if node:
        for f in ("sim_avg.js", "sim_plot.js", "sim.js", "sim_model.js"):
            p = subprocess.run([node, "--check", os.path.join(HERE, f)], capture_output=True, text=True)
            check(p.returncode == 0, "page: %s parses: %s" % (f, p.stderr[-200:]))
        scripts = re.findall(r"<script(?: id=\"[^\"]*\")?>(.*?)</script>", html, re.S)
        tmp = tempfile.mkdtemp(prefix="le_dash78_")
        try:
            for i, s in enumerate(scripts):
                path = os.path.join(tmp, "s%d.js" % i)
                open(path, "w", encoding="utf-8").write(s)
                p = subprocess.run([node, "--check", path], capture_output=True, text=True)
                check(p.returncode == 0, "page: the dashboard's script %d parses: %s" % (i, p.stderr[-200:]))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    # the page's CSV columns and tools/analytics_csv.py's (their CSVs must stay byte for byte the same)
    import analytics_csv as AC
    base = re.search(r"const BASE = \[(.*?)\];", html, re.S).group(1)
    check([x.strip().strip("'") for x in base.split(",")] == AC.BASE, "page: the row columns the page and analytics_csv.py write are the same list")
    check(all(k in AC.BASE for k in ("xp_total", "near3", "near6", "hp_lost", "hp_healed", "boss_now")) and "boss_now" in AC.EMPTY_WHEN_MISSING,
          "page: the CSVs carry pass 77's row keys (boss_now empty without a boss)")


def checks(check, run_node, server):
    import sim_batch as SB
    import posthog_runs as P
    random.seed(78)
    vals = [0.125, 1.125, 2.675, 0.5, 1.5, 2.5, -2.5, -0.125, 1234.25, 0.0005, 100.05, 0.25, 0.375, 3.0, -1.125, 99.995, 123456.75]
    for _ in range(1500):
        vals.append(random.randint(-100000, 100000) / random.choice([1, 2, 4, 8, 16, 32]))
        vals.append(random.uniform(-1000, 1000))
    rq = [[v, nd] for v in vals for nd in (0, 1, 2, 3)]
    cases = _agg_cases(SB)
    fixture_in = json.load(open(os.path.join(TESTDATA, "dash78_series_in.json"), encoding="utf-8"))
    fixture_out = json.load(open(os.path.join(TESTDATA, "dash78_series_out.json"), encoding="utf-8"))
    rec = fixture_in["record"]
    old = json.loads(json.dumps(rec))
    for r in old["samples"]:
        for k in ("near3", "near6", "xp_total", "boss_now", "lines", "gold_in", "hp_lost", "hp_healed"):
            r.pop(k, None)
    old["schema"] = 1
    q = {"round": rq, "agg": [{"players": [{"k": k, "d": d, "rec": r} for k, d, r in ps], "settings": st} for _, ps, st in cases],
         "series": fixture_in, "records": [rec, old], "one": rec}
    out = run_node(q, RUNNER)
    if out is None:
        print("DASH78: node is not here: the page maths checks are skipped")
    elif out:
        bad = [(v, nd, round(v, nd), o) for (v, nd), o in zip(rq, out["round"]) if round(v, nd) != o]
        check(not bad, "round: pyRound is Python's round() on %d values (ties to even): %s" % (len(rq), bad[:4]))
        for (name, ps, st), js in zip(cases, out["agg"]):
            py = json.loads(json.dumps(SB.aggregate(ps, st, {}, game_dir=os.path.join(ROOT, "nogame"))))
            d = []
            for k in ("t", "playing", "series", "breakdowns", "markers", "summary", "players", "rules"):
                _diff(py[k], js[k], k, d)
            check(not d, "agg: sim_avg.js aggregate() is sim_batch.py's on %s: %s" % (name, d[:4]))
        d = _diff(fixture_out, out["series"], "series")
        check(not d, "series: sim_avg.js series() is game/tools/sim_run.gd's on the fixture (exactly): %s" % d[:4])
        new, oldr = out["records"]
        check(all(k in new["keys"] for k in ("near3", "near6", "xp_total", "boss_hp_abs", "gold_total", "gold_by")) and "lines" in new["held"],
              "series: fromRecord keeps what a record wrote: %s" % new["keys"])
        check(not any(k in oldr["keys"] for k in ("near3", "near6", "xp_total", "boss_hp_abs", "gold_total", "gold_by")) and "lines" not in oldr["held"],
              "series: fromRecord leaves out what an older record never wrote (its charts hide): %s" % oldr["keys"])
        m = new["meta"]
        check(m["end_reason"] == rec["result"] and abs(m["end_t"] - rec["length"]) < 0.01 and m["hero"] == rec["hero"] and m["source"] == "record"
              and m["rows"] == len(rec["samples"]) and m["deaths"] == sum(1 for e in rec["events"] if e["kind"] == "death"),
              "series: fromRecord's meta in the runner's words (end_reason the result, end_t the length, the deaths): %s" % {k: m[k] for k in ("end_reason", "end_t", "deaths", "rows")})
        one, two = out["one"], out["two"]
        check(one["playing"] and one["bands"] == 0 and "playing" not in one["ids"] and "this run" in one["how"] and "band" not in one["how"],
              "series: one run averages to itself: no bands, no runs-playing chart, 'this run' in the words: %s" % one["how"])
        check(two["bands"] > 0 and "playing" in two["ids"], "series: two runs draw the bands and the runs playing")
    _parts_checks(check, P)
    tmp = tempfile.mkdtemp(prefix="le_dash78_")
    try:
        _download_checks(check, P, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    _page_checks(check)
