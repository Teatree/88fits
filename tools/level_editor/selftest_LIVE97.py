"""Pass 97, lane LIVE: the live page (Phase 2 steps 2.1, 2.2, 2.5 and the page side of 2.3 / 2.6 / 2.7).

  delta      jobs.list_delta on a temporary queue state (never saved, the module's state put back after): since=0 is
             everything (full + order); one record changed -> only it, with its rev; a Delete -> its id in `removed` and
             the order; a move -> the order alone; a `held` that flips because another job moved, and a running job's log
             tail that moved without its record, count as changed; `unchanged` at the queue's rev; a cursor ahead of the
             queue or older than the bookkeeping -> full. Over HTTP (server.Handler on a free port): GET /api/jobs?since=N
             WITHOUT delta answers byte for byte what pass 96's list() answered (an inline copy of it is the reference),
             with no per-record rev; with delta=1 the {rev, changed, removed, delta} answer, kilobytes for one change.
  model      under Node: JobsModel.merge (a delta, a removal, an order, the old whole list, a full delta), slotSigs (a
             substage moves only the stage slot, a log line only the log, a move only stage + actions), the routes'
             parse / format (and what they refuse), the substage words, the look card's live and history models, the Ops
             model, the offline pill.
  page       under Node's DOM stub (selftest_V's): the Jobs tab polls with delta=1 (501 -> the whole list again); a running
             creature_ctl card keeps its node and its two clip players across ten polls (no player made again, none
             destroyed); another job finishing leaves an open re-roll panel, an open fold, a pick and a scrolled-up log
             where they were; a request card's Reject draft survives; the groups are never cleared; a state change hands
             the clips over; Jobs.subscribe hears {changed, removed}; the look stage's live block shows the running job
             and the request (Approve), follows a poll without drawing the grid again; the filter (#jobs?look=);
             Re-queue all; the Ops fold; the offline pill; assets.js refreshRecord draws the Looks section alone (an
             Identity input typed in keeps its node) and the whole pane when a key outside the looks changed.
  wiring     index.html loads jobs_view.js between jobs_model.js and jobs.js; server.py's delta branch; app.js's routes;
             looks.js's live host; docs/level_editor.md "Pass 97: the live page".
"""
import json
import os
import shutil
import sys
import tempfile
import threading
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)


def _rd(name):
    with open(os.path.join(HERE, name), "r", encoding="utf-8") as f:
        return f.read()


# ---------------------------------------------------------------- the delta, on a temporary state

def _job(jid, state="done", kind="look", target=None, **kw):
    j = {"id": jid, "kind": kind, "state": state, "lane": "comfy", "target": target or {"kind": "enemy", "id": "bug", "code": "BG-A"},
         "title": "job " + jid, "spec": {"method": "creature_ctl"}, "progress": {"stage": "side", "done": 0, "total": 3, "stages": []},
         "outputs": [], "created": "2026-10-22T10:00:00", "plan": {"env": {"SECRET": "x"}, "cmd": ["python"]}}
    j.update(kw)
    return j


def delta_checks(check, server):
    import jobs
    saved = {k: getattr(jobs, k) for k in ("_state", "JOBS_DIR", "QUEUE_FILE", "_readonly")}
    saved_delta = dict(jobs._delta)
    saved_live = dict(jobs._live)
    tmp = tempfile.mkdtemp(prefix="le_live97_")
    try:
        jobs.JOBS_DIR = tmp
        jobs.QUEUE_FILE = os.path.join(tmp, "queue.json")
        jobs._readonly = None
        jobs._live.clear()
        jobs._delta.update(rev=None, floor=None, state=None, sig={}, at={}, tomb={}, order=None, order_at=0)
        os.makedirs(os.path.join(tmp, "B"), exist_ok=True)
        with open(os.path.join(tmp, "B", "log.txt"), "w", encoding="utf-8") as f:
            f.write("line 1\nline 2\n")
        st = {"rev": 10, "jobs": [_job("A"), _job("B", "running", started="2026-10-22T10:01:00"), _job("C", "failed", error="boom")]}
        jobs._state = st
        d0 = jobs.list_delta(0)
        check(d0.get("delta") is True and d0.get("full") is True and [j["id"] for j in d0["changed"]] == ["A", "B", "C"] and d0.get("order") == ["A", "B", "C"] and d0["removed"] == [] and d0["rev"] == 10,
              "LIVE97 delta: since=0 answers everything (full, the order, rev 10)")
        check(all(j.get("rev") == 10 for j in d0["changed"]) and all("env" not in (j.get("plan") or {}) for j in d0["changed"]),
              "LIVE97 delta: every served record carries its rev; plan.env stays out (as _public)")
        b = st["jobs"][1]
        b["progress"]["done"] = 1
        st["rev"] = 11
        d1 = jobs.list_delta(10)
        check([j["id"] for j in d1["changed"]] == ["B"] and d1["removed"] == [] and "order" not in d1 and "full" not in d1 and d1["changed"][0]["rev"] == 11 and d1["changed"][0]["progress"]["done"] == 1,
              "LIVE97 delta: one record changed -> only it, with rev 11, no order: %s" % [j["id"] for j in d1["changed"]])
        d1b = jobs.list_delta(11)
        check(d1b.get("unchanged") is True and d1b["changed"] == [] and d1b["removed"] == [], "LIVE97 delta: at the queue's rev: unchanged")
        # a field lane PROGRESS writes (progress.substage) is a change like any other
        b["progress"]["substage"] = {"node": "KSampler", "value": 3, "max": 4, "at": "2026-10-22T10:02:00", "prompt": "p1"}
        st["rev"] = 12
        d2 = jobs.list_delta(11)
        check([j["id"] for j in d2["changed"]] == ["B"] and d2["changed"][0]["progress"]["substage"]["value"] == 3, "LIVE97 delta: progress.substage moved -> the job is in changed")
        # the running job's tail moves on disk without its record (a read-only editor reads it from log.txt)
        with open(os.path.join(tmp, "B", "log.txt"), "a", encoding="utf-8") as f:
            f.write("line 3\n")
        st["rev"] = 13
        d3 = jobs.list_delta(12)
        check([j["id"] for j in d3["changed"]] == ["B"] and d3["changed"][0]["log_tail"][-1] == "line 3", "LIVE97 delta: a running job's new log line counts as a change (its served view moved)")
        # a Delete: the tombstone and the order
        st["jobs"] = [j for j in st["jobs"] if j["id"] != "C"]
        st["rev"] = 14
        d4 = jobs.list_delta(13)
        check(d4["changed"] == [] and d4["removed"] == ["C"] and d4.get("order") == ["A", "B"], "LIVE97 delta: a removed job -> its id in removed and the order: %s" % d4)
        d4b = jobs.list_delta(10)
        check(sorted(j["id"] for j in d4b["changed"]) == ["B"] and d4b["removed"] == ["C"] and d4b.get("order") == ["A", "B"], "LIVE97 delta: an older cursor gets every change since (B) and the removal (C)")
        # a move: the records are the same, only the order moved
        st["jobs"] = [st["jobs"][1], st["jobs"][0]]
        st["rev"] = 15
        d5 = jobs.list_delta(14)
        check(d5["changed"] == [] and d5["removed"] == [] and d5.get("order") == ["B", "A"], "LIVE97 delta: a move -> the order alone: %s" % d5)
        # held flips because ANOTHER job changed: the candidate job is in changed although its record did not move
        cand = _job("D", "queued", kind="icon_cands", target={"kind": "enemy", "id": "bug", "code": "BG-Z"}, spec={"method": "icon_cands", "ref": "tools/dl/ai_raw_anime/__live97_no_such_front__.png"})
        look = _job("E", "queued", kind="look", target={"kind": "enemy", "id": "bug", "code": "BG-Z"})
        st["jobs"] = st["jobs"] + [cand, look]
        st["rev"] = 16
        d6 = jobs.list_delta(15)
        held = {j["id"]: j.get("held") for j in d6["changed"]}
        check(held.get("D") is True and held.get("E") is False, "LIVE97 delta: the new candidate job is held while its look job is queued: %s" % held)
        look["state"] = "done"
        st["rev"] = 17
        d7 = jobs.list_delta(16)
        ids = sorted(j["id"] for j in d7["changed"])
        check(ids == ["D", "E"] and [j for j in d7["changed"] if j["id"] == "D"][0]["held"] is False, "LIVE97 delta: the look job done -> the candidate's held flips and it is served again: %s" % ids)
        # a cursor ahead of the queue (another file, a reset) and one older than the bookkeeping: everything again
        d8 = jobs.list_delta(999)
        check(d8.get("full") is True and len(d8["changed"]) == len(st["jobs"]) and d8["removed"] == [], "LIVE97 delta: a cursor ahead of the queue -> full")
        d9 = jobs.list_delta(3)
        check(d9.get("full") is True and len(d9["changed"]) == len(st["jobs"]), "LIVE97 delta: a cursor older than this process's bookkeeping -> full")
        # a fresh state with a LOWER rev (a test's world, another file): the bookkeeping starts over
        jobs._state = {"rev": 2, "jobs": [_job("Z")]}
        d10 = jobs.list_delta(1)
        check(d10.get("full") is True and [j["id"] for j in d10["changed"]] == ["Z"], "LIVE97 delta: a queue loaded again with a lower rev -> the bookkeeping starts over (full)")
        jobs._state = st

        # ---- over HTTP: the old answer byte for byte; the delta beside it
        def old_list(since_rev):   # pass 96's jobs.list(), the reference (copied, not called)
            with jobs._lock:
                jobs._sync_from_disk()
                if since_rev is not None and int(since_rev) == jobs._state["rev"]:
                    return {"rev": jobs._state["rev"], "unchanged": True}
                return {"rev": jobs._state["rev"], "jobs": [jobs._public(j, jobs.LOG_TAIL_SHORT) for j in jobs._state["jobs"]]}
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        th = threading.Thread(target=httpd.serve_forever, daemon=True)
        th.start()
        base = "http://127.0.0.1:%d" % httpd.server_address[1]

        def get(path):
            with urllib.request.urlopen(base + path, timeout=10) as r:
                return r.status, r.read()
        try:
            for q in ("/api/jobs", "/api/jobs?since=0", "/api/jobs?since=5", "/api/jobs?since=%d" % st["rev"], "/api/jobs?since=junk"):
                stc, body = get(q)
                since = q.split("since=")[1] if "since=" in q else None
                try:
                    since_v = int(since) if since is not None else None
                except ValueError:
                    since_v = None
                want = dict(old_list(since_v))
                want.setdefault("ok", True)
                check(stc == 200 and body == json.dumps(want, ensure_ascii=False).encode("utf-8"),
                      "LIVE97 http: GET %s without delta answers byte for byte as pass 96 (%d bytes)" % (q, len(body)))
            stc, body = get("/api/jobs?since=0")
            d = json.loads(body)
            check("delta" not in d and "changed" not in d and all("rev" not in j for j in d["jobs"]), "LIVE97 http: the old answer has no delta keys and no per-record rev")
            stc, body = get("/api/jobs?since=0&delta=1")
            d = json.loads(body)
            check(d.get("delta") is True and d.get("full") is True and len(d["changed"]) == len(st["jobs"]) and d.get("ok") is True, "LIVE97 http: since=0&delta=1 -> everything, full")
            r0 = d["rev"]
            # 200 more finished records, then one change: the delta is kilobytes, the old answer is not
            for k in range(200):
                st["jobs"].append(_job("F%03d" % k, "done", outputs=[{"type": "still", "url": "/dl/x/%d.png" % k, "label": "front"}] * 6, log_tail=[]))
            st["rev"] += 1
            get("/api/jobs?since=%d&delta=1" % r0)
            r1 = st["rev"]
            st["jobs"][0]["progress"]["done"] = 2
            st["rev"] += 1
            _, body_d = get("/api/jobs?since=%d&delta=1" % r1)
            _, body_o = get("/api/jobs?since=%d" % r1)
            dd = json.loads(body_d)
            check([j["id"] for j in dd["changed"]] == [st["jobs"][0]["id"]] and len(body_d) < 8000 < len(body_o),
                  "LIVE97 http: one change on a %d-job queue: the delta %d bytes, the old answer %d bytes" % (len(st["jobs"]), len(body_d), len(body_o)))
            _, body_u = get("/api/jobs?since=%d&delta=1" % st["rev"])
            check(json.loads(body_u).get("unchanged") is True, "LIVE97 http: the delta at the queue's rev says unchanged")
        finally:
            httpd.shutdown()
            httpd.server_close()
    finally:
        for k, v in saved.items():
            setattr(jobs, k, v)
        jobs._delta.clear()
        jobs._delta.update(saved_delta)
        jobs._live.clear()
        jobs._live.update(saved_live)
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- the model under Node

MODEL_RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const J = require(path.join(dir, 'jobs_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const out = {};
  const ids = (m) => m.jobs.map((j) => j.id);
  const a = [{ id: 'a', x: 1 }, { id: 'b', x: 1 }, { id: 'c', x: 1 }];
  let m = J.merge(a, { delta: true, rev: 5, changed: [{ id: 'b', x: 2 }, { id: 'd', x: 1 }], removed: ['a'] });
  out.m1 = [ids(m), m.changed, m.removed, m.full, m.unchanged, m.jobs[0].x];
  m = J.merge(a, { delta: true, rev: 5, changed: [], removed: [], order: ['c', 'a', 'b'] });
  out.m2 = [ids(m), m.unchanged, m.moved];
  m = J.merge(a, { rev: 3, jobs: [{ id: 'x' }] });
  out.m3 = [ids(m), m.removed, m.full];
  m = J.merge(a, { delta: true, rev: 9, full: true, changed: [{ id: 'q' }, { id: 'a' }], removed: [], order: ['a', 'q'] });
  out.m4 = [ids(m), m.removed, m.full];
  m = J.merge(a, { delta: true, rev: 5, unchanged: true, changed: [], removed: [] });
  out.m5 = [ids(m), m.unchanged];
  m = J.merge(a, { delta: true, rev: 6, changed: [], removed: [] });
  out.m6 = m.unchanged;
  // slot signatures
  const base = { id: 'j1', state: 'running', kind: 'look', title: 't', target: { kind: 'enemy', id: 'bug', code: 'BG-A' }, progress: { stage: 'side', done: 1, total: 3, stages: [{ name: 'front', state: 'done', secs: 41 }] }, log_tail: ['a', 'b'], outputs: [{ type: 'clip', url: '/dl/c/', frames: 12 }], started: '2026-10-22T10:00:00', eta_s: 300, spec: { method: 'creature_ctl' } };
  const s0 = J.slotSigs(base, {}, {});
  const diff = (b) => { const s1 = J.slotSigs(b, {}, b.__x || {}); return Object.keys(s0).filter((k) => s0[k] !== s1[k]).sort(); };
  out.sub = diff(Object.assign({}, base, { progress: Object.assign({}, base.progress, { substage: { node: 'KSampler', value: 2, max: 4 } }) }));
  out.log = diff(Object.assign({}, base, { log_tail: ['a', 'b', 'c'] }));
  out.outs = diff(Object.assign({}, base, { outputs: base.outputs.concat([{ type: 'still', url: '/dl/s.png' }]) }));
  out.done = diff(Object.assign({}, base, { progress: Object.assign({}, base.progress, { done: 2 }) }));
  out.same = diff(Object.assign({}, base));
  const q = Object.assign({}, base, { state: 'queued' });
  const sq = J.slotSigs(q, {}, { pos: 0, n: 2, up: 0, down: 1 }), sq2 = J.slotSigs(q, {}, { pos: 1, n: 2, up: -1, down: 0 });
  out.where = Object.keys(sq).filter((k) => sq[k] !== sq2[k]).sort();
  out.clock = Object.values(s0).some((v) => /\d{13}/.test(v));
  // routes
  const hs = ['#jobs', '#jobs/j20261022-000038-d13f', '#jobs?look=SP-B&id=desert_spider', '#jobs?look=SP-B&id=desert_spider&kind=enemy', '#requests/r20261022-000038-84ed',
    '#frames/enemy/desert_spider/SP-B/run/side/7', '#frames/hero/may/MAY-G/run/back', '#frames/boss/gila/GG-A', '#sim', '#timeline', '#creatures'];
  out.rt = hs.map((h) => [h, J.parseHash(h), J.formatHash(J.parseHash(h))]);
  out.bad = ['', '#', '#nope', '#frames/weapon/x/A', '#frames/enemy/../SP-B', '#jobs/<script>', '#frames/enemy/a b/SP-B', '#sim/extra'].map((h) => J.parseHash(h));
  out.filter = [J.filterMatch({ target: { id: 'desert_spider', code: 'SP-B', kind: 'enemy' } }, { look: 'SP-B', id: 'desert_spider' }), J.filterMatch({ target: { id: 'desert_spider', code: 'SP-A' } }, { look: 'SP-B' }), J.filterMatch({ target: { id: 'gila', code: 'SP-B', kind: 'boss' } }, { look: 'SP-B', kind: 'enemy' })];
  // the substage words
  const now = new Date('2026-10-22T10:00:41').getTime();
  const sub = { node: 'KSampler', value: 3, max: 4, view: 'side', at: '2026-10-22T10:00:40', prompt: 'p1' };
  out.st = [J.substageText({ substage: sub }, now, new Date('2026-10-22T10:00:00').getTime()), J.substageText({ substage: Object.assign({}, sub, { started: '2026-10-22T09:59:00' }) }, now, null),
    J.substageText({ substage: Object.assign({}, sub, { at: '2026-10-22T09:59:30' }) }, now, null), J.substageText({ comfy_error: 'out of memory' }, now, null), J.substageText({}, now, null),
    J.substageText({ substage: { node: 'VAEDecode', at: '2026-10-22T10:00:40' } }, now, null),
    J.substageText({ substage: { node: 'VAE Decode', value: 0, max: 0, since: '2026-10-22T10:00:30', at: '2026-10-22T10:00:40', prompt: 'p2' } }, now, null)];
  out.waited = J.liveModel([{ id: 'w1', state: 'running', kind: 'look', target: { kind: 'enemy', id: 'x', code: 'X-A' }, lock_wait_s: { comfy: 125.4, godot: 0.2 }, progress: {} }], [], 'enemy', 'x', 'X-A').jobs[0].lock;
  // the live model
  const jobs = [
    { id: 'j-run', state: 'running', kind: 'look', title: 'SP-B look', target: { kind: 'enemy', id: 'desert_spider', code: 'SP-B' }, started: '2026-10-22T10:00:00', eta_s: 600, progress: { stage: 'side', done: 1, total: 4, substage: sub }, lock_waits: { comfy: '2 min' },
      outputs: [{ type: 'still', url: '/dl/a.png', label: 'front' }, { type: 'workflow', url: '/dl/w.json' }, { type: 'clip', url: '/dl/clip/', label: 'side walk' }, { type: 'still', url: '/dl/b.png', label: 'back' }, { type: 'still', url: '/dl/c.png', label: 'side' }] },
    { id: 'j-q', state: 'queued', kind: 'icon_cands', title: 'icons', target: { kind: 'enemy', id: 'desert_spider', code: 'SP-B' }, eta_s: 80 },
    { id: 'j-other', state: 'running', kind: 'look', target: { kind: 'enemy', id: 'desert_spider', code: 'SP-A' } },
    { id: 'j-done', state: 'done', kind: 'look', target: { kind: 'enemy', id: 'desert_spider', code: 'SP-B' } },
    { id: 'j-fail', state: 'failed', kind: 'frames_repair', target: { kind: 'enemy', id: 'desert_spider', code: 'SP-B' } },
  ];
  const reqs = [{ rid: 'r1', state: 'waiting', waiting_for: 'approval', asset: { kind: 'enemy', id: 'desert_spider', code: 'SP-B' }, iteration: { n: 2, of: 5 }, budget: { rerolls: 2 }, spent: { rerolls: 1 }, provisional: { code: 'SP-B' }, jobs: [] }];
  const lm = J.liveModel(jobs, reqs, 'enemy', 'desert_spider', 'SP-B', new Date('2026-10-22T10:01:23').getTime());
  out.live = { ids: lm.jobs.map((x) => x.id), stage: lm.jobs[0].stage, elapsed: lm.jobs[0].elapsed, lock: lm.jobs[0].lock, sub: lm.jobs[0].sub && lm.jobs[0].sub.text, thumbs: lm.jobs[0].thumbs.map((t) => t.url), link: lm.jobs[0].link,
    q: [lm.jobs[1].stage, lm.jobs[1].elapsed], req: lm.request && [lm.request.iteration, lm.request.approve, lm.request.link, lm.request.budgets.length], n: lm.n };
  out.live_none = J.liveModel(jobs, [], 'enemy', 'desert_spider', 'SP-Z').n;
  const hm = J.historyModel(jobs, [{ time: '2026-10-21T12:40:00', why: 'export', changed: [{}, {}] }, { time: '2026-10-20T09:00:00' }], [{ seq: 4, t: '2026-10-21T12:40:00', kind: 'frames', event: 'export', look: { kind: 'enemy', id: 'desert_spider', code: 'SP-B' }, job: 'jexp-aaaa' }, { seq: 2, t: '2026-10-21T10:00:00', kind: 'look', event: 'approve', look: { kind: 'enemy', id: 'desert_spider', code: 'SP-A' } }], 'enemy', 'desert_spider', 'SP-B');
  out.hist = [hm.line, hm.jobsLink, hm.events, hm.past, hm.exports];
  out.hist_noex = J.historyModel([], null, null, 'enemy', 'x', 'X-A').line;
  // the Ops model
  const om = J.opsModel({ days: 7, outcomes: { done: { look: { creature_ctl: 5, hero_fit: 2 }, icon_cands: { icon_cands: 3 } }, failed: { look: { creature_ctl: 1 } } },
    medians: { creature_ctl: { rendered: { median: 700, p90: 900, n: 6 }, cached: { median: 30, p90: 40, n: 2 } }, hero_fit: { rendered: { median: 250, p90: 260, n: 2 } } },
    lock_wait: { comfy: 125 }, failures: [{ reason: 'Traceback: CUDA out of memory', n: 2, last_job: 'j20261022-000038-d13f' }], qa_offline: 1, interrupted: 0, stalled: 0,
    cost: { requests: [{ rid: 'r20261022-000038-84ed', dollars: 0.042, calls: 3 }], total_dollars: 0.042, by_model: { 'haiku': 0.042 } }, eta_source: 'measured' }, { methods: [{ id: 'creature_ctl', time: { median_s: 720 } }] });
  out.ops = { cols: om.cols, rows: om.outcomes.map((r) => [r.kind, r.method, r.cells, r.total]), med: om.medians.map((r) => [r.method, r.rendered, r.cached, r.table, r.measured]), lock: om.lock, fail: om.failures, req: om.requests, total: om.total, byModel: om.byModel, counts: om.counts, eta: om.etaSource };
  out.ops_flat = J.opsModel({ outcomes: { 'done|look|creature_ctl': 4 } }, null).outcomes.map((r) => [r.kind, r.method, r.cells]);
  out.pill = [J.offlinePill({ downSince: new Date('2026-10-22T13:14:15').getTime() }), J.offlinePill({ downSince: 0 })];
  process.stdout.write(JSON.stringify(out));
});
"""


def model_checks(check, run_node):
    res = run_node({}, MODEL_RUNNER.replace("process.argv[2]", json.dumps(os.path.join(HERE, "jobs_model.js").replace("\\", "/"))))
    if not res:
        check(True, "LIVE97 model: node is not here: the page-free checks skipped")
        return
    check(res["m1"] == [["b", "c", "d"], ["b", "d"], ["a"], False, False, 2], "LIVE97 merge: a delta replaces b, appends d, drops a: %s" % res["m1"])
    check(res["m2"] == [["c", "a", "b"], False, True], "LIVE97 merge: an order alone reorders (and is a change): %s" % res["m2"])
    check(res["m3"] == [["x"], ["a", "b", "c"], True], "LIVE97 merge: a server without the delta: the whole list replaces, the rest removed: %s" % res["m3"])
    check(res["m4"] == [["a", "q"], ["b", "c"], True], "LIVE97 merge: a full delta replaces the list in its order: %s" % res["m4"])
    check(res["m5"] == [["a", "b", "c"], True] and res["m6"] is True, "LIVE97 merge: unchanged and an empty delta change nothing")
    check(res["sub"] == ["stage"], "LIVE97 slots: a substage tick moves only the stage slot: %s" % res["sub"])
    check(res["log"] == ["log"], "LIVE97 slots: a new log line moves only the log slot: %s" % res["log"])
    check(res["outs"] == ["outputs"], "LIVE97 slots: a new output moves only the outputs slot: %s" % res["outs"])
    check(res["done"] == ["bar", "stage"], "LIVE97 slots: a stage done moves the stage line and the bar: %s" % res["done"])
    check(res["same"] == [] and res["clock"] is False, "LIVE97 slots: the same record, the same signatures; no clock in them")
    check(res["where"] == ["actions", "stage"], "LIVE97 slots: a queued job moving in its lane patches its place and its arrows only: %s" % res["where"])
    rt = {h: (p, f) for h, p, f in res["rt"]}
    check(all(f == h for h, (p, f) in rt.items()), "LIVE97 routes: parse then format gives the hash back: %s" % [(h, f) for h, (p, f) in rt.items() if f != h])
    check(rt["#frames/enemy/desert_spider/SP-B/run/side/7"][0] == {"tab": "creatures", "frames": {"kind": "enemy", "id": "desert_spider", "code": "SP-B", "anim": "run", "view": "side", "slot": 7}}
          and rt["#frames/hero/may/MAY-G/run/back"][0]["tab"] == "heroes" and rt["#requests/r20261022-000038-84ed"][0] == {"tab": "jobs", "request": "r20261022-000038-84ed"}
          and rt["#jobs?look=SP-B&id=desert_spider"][0] == {"tab": "jobs", "filter": {"look": "SP-B", "id": "desert_spider"}} and rt["#jobs/j20261022-000038-d13f"][0] == {"tab": "jobs", "job": "j20261022-000038-d13f"},
          "LIVE97 routes: a frame, a hero's frame, a request, a look's jobs and a job parse to their routes")
    check(res["bad"][:3] == [None, None, None] and res["bad"][3] is None and res["bad"][4] is None and res["bad"][5] == {"tab": "jobs"} and res["bad"][6] is None and res["bad"][7] is None,
          "LIVE97 routes: nothing, unknown words, an item's frames, a path climbing out, a script and spaces are refused: %s" % res["bad"])
    check(res["filter"] == [True, False, True], "LIVE97 routes: the look filter matches its look only (a boss is an enemy's kin)")
    st = res["st"]
    check(st[0]["text"] == "side · KSampler step 3 of 4 · 41 s" and st[0]["stale"] is False, "LIVE97 substage: \"%s\"" % st[0]["text"])
    check(st[1]["text"] == "side · KSampler step 3 of 4 · 1:41", "LIVE97 substage: the server's start wins and long renders read m:ss: %s" % st[1]["text"])
    check(st[2]["stale"] is True and "no tick for 71 s" in st[2]["text"], "LIVE97 substage: ticks stopped are said: %s" % st[2]["text"])
    check(st[3] == {"text": "", "error": "out of memory", "stale": False} and st[4] is None and st[5]["text"].startswith("VAEDecode · "), "LIVE97 substage: an error alone, nothing, a node without steps: %s" % st[3:])
    check(st[6]["text"] == "VAE Decode · 11 s", "LIVE97 substage: lane PROGRESS's shape (max 0 = the node's name alone; `since` = when the node began): %s" % st[6])
    check(res["waited"] == "waited for the comfy lock 2:05", "LIVE97 live: an attempt's lock_wait_s (lane PROGRESS) when it waits no more: %s" % res["waited"])
    lv = res["live"]
    check(lv["ids"] == ["j-run", "j-q"] and lv["stage"] == "stage side (1 of 4)" and lv["elapsed"] == "1:23 / ~10:00" and lv["lock"] == "waiting for a lock: comfy 2 min" and lv["sub"].startswith("side · KSampler step 3 of 4"),
          "LIVE97 live: the look's running job first, its stage k of N, elapsed / ETA, the lock wait, the substage: %s" % lv)
    check(lv["thumbs"] == ["/dl/c.png", "/dl/b.png", "/dl/clip/out_00.png"] and lv["link"] == "#jobs/j-run" and lv["q"] == ["in the queue", "~1:20 once it runs"],
          "LIVE97 live: the 3 newest outputs (no workflow; a clip's first frame), the link to its card, the queued job's line: %s" % [lv["thumbs"], lv["q"]])
    check(lv["req"] == ["iteration 2 of 5", True, "#requests/r1", 1] and lv["n"] == 3 and res["live_none"] == 0, "LIVE97 live: the request on the look (iteration, Approve, its link, the budget): %s" % lv["req"])
    h = res["hist"]
    check(h[0] == "past jobs: 2 (1 done, 1 failed) · exports: 2 (last 10/21 12:40 · export · 2 frames)" and h[1] == "#jobs?look=SP-B&id=desert_spider" and h[2] == ["10/21 12:40 export #aaaa"] and h[3] == 2 and h[4] == 2,
          "LIVE97 history: the past jobs, the exports, the look's own events, the filtered link: %s" % h)
    check(res["hist_noex"] == "no past jobs in the list", "LIVE97 history: without exports or jobs it says so briefly: %s" % res["hist_noex"])
    o = res["ops"]
    check(o["cols"] == ["done", "failed"] and o["rows"] == [["icon_cands", "icon_cands", [3, 0], 3], ["look", "creature_ctl", [5, 1], 6], ["look", "hero_fit", [2, 0], 2]],
          "LIVE97 ops: outcomes per kind and method x state: %s" % o["rows"])
    check(o["med"] == [["creature_ctl", "11:40 (p90 15:00, 6 runs)", "0:30 (2 runs)", "12:00", True], ["hero_fit", "4:10 (p90 4:20, 2 runs)", "–", "–", False]],
          "LIVE97 ops: medians rendered vs cached beside methods.json's, measured from 5 runs: %s" % o["med"])
    check(o["lock"] == "comfy 2:05" and o["fail"] == ["2× Traceback: CUDA out of memory (last: #d13f)"] and o["req"] == ["request 84ed: $0.04 in 3 calls"] and o["total"] == "$0.04" and o["byModel"] == "haiku $0.04" and o["counts"] == "1 with the QA offline" and "measured" in o["eta"],
          "LIVE97 ops: lock waits, failures as sentences, dollars per request, the counts: %s" % [o["lock"], o["fail"], o["req"], o["counts"]])
    check(res["ops_flat"] == [["look", "creature_ctl", [4]]], "LIVE97 ops: flat 'state|kind|method' keys read too")
    check(res["pill"][0]["text"] == "offline since 13:14" and res["pill"][1] is None, "LIVE97 pill: \"%s\"" % res["pill"][0]["text"])


# ---------------------------------------------------------------- the page under Node's DOM stub

PAGE_MAIN = r"""
// argv[2] = tools/level_editor/jobs.js. Drives jobs.js, jobs_view.js, looks.js and assets.js under selftest_V's DOM stub.
const fs = require('fs'), path = require('path');
const dir = path.dirname(process.argv[2]);
const out = [];
const check = (name, ok, detail) => out.push([name, !!ok, detail === undefined ? '' : (typeof detail === 'string' ? detail : JSON.stringify(detail))]);
const tick = (n) => new Promise((r) => setTimeout(r, n || 0));
function done() { process.stdout.write(JSON.stringify(out), () => process.exit(0)); }
process.on('unhandledRejection', (e) => { out.push(['unhandled rejection', false, String(e && e.stack || e)]); });

async function main() {
  const { document } = makeDom();
  global.document = document;
  global.window = global;
  global.requestAnimationFrame = (fn) => setTimeout(fn, 0);
  global.CSS = { escape: (s) => s };
  global.confirm = () => true;
  global.window.addEventListener = () => {};
  document.body.appendChild(document.createElement('header')).className = 'top';
  document.querySelector('header.top').appendChild(document.createElement('div')).className = 'brand';
  // a little delta server: the page's records, per-record revs, tombstones, the order
  const srv = { rev: 1, jobs: [], at: {}, tomb: {}, order: [], orderAt: 0, delta: true, down: false, status: {}, requests: [], ops: null, posts: [], urls: [] };
  srv.put = (j) => { srv.rev++; const i = srv.jobs.findIndex((x) => x.id === j.id); if (i >= 0) srv.jobs[i] = j; else srv.jobs.push(j); srv.at[j.id] = srv.rev; const ids = srv.jobs.map((x) => x.id).join(); if (ids !== srv.order.join()) { srv.order = srv.jobs.map((x) => x.id); srv.orderAt = srv.rev; } };
  srv.del = (id) => { srv.rev++; srv.jobs = srv.jobs.filter((x) => x.id !== id); srv.tomb[id] = srv.rev; srv.order = srv.jobs.map((x) => x.id); srv.orderAt = srv.rev; };
  const json = (data, status) => ({ ok: (status || 200) < 400, status: status || 200, json: async () => data });
  global.fetch = async (url, opts) => {
    const u = String(url);
    srv.urls.push(u);
    if (srv.down) throw new Error('Failed to fetch');
    const method = (opts && opts.method) || 'GET';
    if (method === 'POST') {
      const body = opts && opts.body ? JSON.parse(opts.body) : null;
      srv.posts.push({ url: u, body });
      if (u === '/api/jobs/requeue_interrupted') return json({ ok: true, requeued: ['j-i1', 'j-i2'] });
      return json({ ok: true });
    }
    if (u.startsWith('/api/jobs?since=')) {
      const q = new URLSearchParams(u.split('?')[1]);
      const since = Number(q.get('since')) || 0;
      if (q.get('delta') === '1') {
        if (!srv.delta) return json({ ok: false, error: 'jobs.list_delta is not implemented' }, 501);
        if (since && since === srv.rev) return json({ ok: true, rev: srv.rev, delta: true, unchanged: true, changed: [], removed: [] });
        if (!since) return json({ ok: true, rev: srv.rev, delta: true, full: true, changed: srv.jobs, removed: [], order: srv.order });
        const d = { ok: true, rev: srv.rev, delta: true, changed: srv.jobs.filter((j) => srv.at[j.id] > since), removed: Object.keys(srv.tomb).filter((k) => srv.tomb[k] > since) };
        if (srv.orderAt > since) d.order = srv.order;
        return json(d);
      }
      return json({ rev: srv.rev, jobs: srv.jobs, ok: true });
    }
    if (u === '/api/status') return json(srv.status);
    if (u === '/api/requests') return json({ ok: true, requests: srv.requests });
    if (u === '/api/methods') return json({ methods: [{ id: 'creature_ctl', name: 'Creature on a 3D model', time: { median_s: 720 } }] });
    if (u.startsWith('/api/ops')) return srv.ops ? json(srv.ops) : json({ ok: false, error: 'no route' }, 404);
    if (u.startsWith('/api/events')) return json({ seq: 0, last: 0, events: [] });
    if (u.startsWith('/dl/jobs/')) return json({}, 404);
    if (u.startsWith('/api/content/enemy/bug')) return json(srv.content || { ok: false }, srv.content ? 200 : 404);
    return json({ ok: false, error: 'no route ' + u }, 404);
  };
  const statuses = [];
  const routes = [];
  global.App = { S: { tab: 'jobs', enemies: [] }, status: (t, k) => statuses.push([t, k]), toast() {}, switchTab(t) { global.App.S.tab = t; }, render() {}, refreshCreatures: async () => {}, route: (r) => routes.push(r) };
  let made = 0, destroyed = 0;
  const player = (o) => { made++; const p = { el: document.createElement('figure'), opts: o, destroyed: false, destroy() { if (!this.destroyed) { this.destroyed = true; destroyed++; } }, setStrip() {}, url: o && (o.url || o.pattern) || '' }; p.el.className = 'sp'; p.el.__sp = p; return p; };
  global.StripPlayer = { create: player, createSeq: player, openImage() {}, HERO_SIZE: 1.9, totalFrames: () => 0, MAX_ANIMATING: 12, LRU_MAX: 16 };
  global.U = new Function(fs.readFileSync(path.join(dir, 'util.js'), 'utf8') + '\nreturn U;')();
  global.JobsModel = require(path.join(dir, 'jobs_model.js'));
  global.JobsView = require(path.join(dir, 'jobs_view.js'));
  global.Frames = { open() {}, confirmBox: async () => true, summary: async () => ({ ok: true, groups: [] }) };
  global.Assets = { ensureSaved: async () => true, refreshRecord: async () => null, methodOf: () => 'creature_ctl', recipeEditor: () => null };
  global.LookGrid = require(path.join(dir, 'looks.js'));
  global.Jobs = require(path.join(dir, 'jobs.js'));
  const J = global.Jobs;
  const clipJob = (extra) => Object.assign({ id: 'j-run-0001', kind: 'look', method: 'creature_ctl', state: 'running', lane: 'comfy', title: 'bug BG-B look', target: { kind: 'enemy', id: 'bug', code: 'BG-B' }, started: '2026-10-22T10:00:00', eta_s: 720,
    progress: { stage: 'side', done: 1, total: 4, stages: [{ name: 'front', state: 'done', secs: 40 }] }, log_tail: ['start'], outputs: [{ type: 'clip', url: '/dl/ai_anim/bug_b_ctl_side/', frames: 12, label: 'side walk' }, { type: 'clip', url: '/dl/ai_anim/bug_b_ctl_back/', frames: 12, label: 'back walk' }] }, extra || {});
  srv.put(clipJob());
  srv.put({ id: 'j-done-0002', kind: 'look', method: 'creature_ctl', state: 'done', lane: 'comfy', title: 'bug BG-C look', target: { kind: 'enemy', id: 'bug', code: 'BG-C' }, ended: '2026-10-22T09:00:00', cache_keys: { stills: ['bug_c_front'], clips: ['bug_c_ctl_side'] }, outputs: [], equiv: 'python tools/asset_job.py ...', spec: { method: 'creature_ctl' } });
  srv.put({ id: 'j-wait-0003', kind: 'icon_cands', state: 'waiting', lane: 'comfy', waiting_for: 'pick', title: 'icons', target: { kind: 'enemy', id: 'bug', code: 'BG-C' }, choices: [{ key: 'c0', label: 'c0', url: '/dl/i0.png' }, { key: 'c1', label: 'c1', url: '/dl/i1.png' }] });
  srv.put({ id: 'j-q-0004', kind: 'icon_cands', state: 'queued', lane: 'comfy', title: 'more icons', target: { kind: 'enemy', id: 'bug', code: 'BG-D' } });
  srv.requests = [{ rid: 'r-0001', state: 'waiting', waiting_for: 'approval', asset: { kind: 'enemy', id: 'bug', code: 'BG-B' }, iteration: { n: 1, of: 3 }, budget: { rerolls: 2 }, spent: { rerolls: 0 }, jobs: [{ id: 'j-run-0001', state: 'running' }] }];
  srv.status = { interrupted: 2 };
  const subs = [];
  J.subscribe((ev) => subs.push({ changed: ev.changed, removed: ev.removed, full: ev.full, requests: !!ev.requests }));
  const panel = document.createElement('div'); document.body.appendChild(panel);
  J.render(panel); await tick(10); await J.poll(); await tick(10);
  check('page: the first poll asks the delta', srv.urls.some((u) => u === '/api/jobs?since=0&delta=1'), srv.urls.filter((u) => u.startsWith('/api/jobs')).slice(0, 3));
  const cardOf = (id) => panel.querySelectorAll('article.jcard').find((c) => c.dataset.id === id);
  const rc = cardOf('j-run-0001');
  check('page: the running card is drawn with its two clips', !!rc && rc.querySelectorAll('figure.sp').length === 2, rc && rc.textContent.slice(0, 120));
  const groupsEl = panel.querySelector('div.jobs-groups');
  const runGroup = rc && rc.parentNode;
  const madeBefore = made, destroyedBefore = destroyed;
  const clipEls = rc ? rc.querySelectorAll('figure.sp') : [];
  // ten polls with the running job moving (a log line, a substage tick, a stage done)
  for (let k = 0; k < 10; k++) {
    const cur = srv.jobs.find((j) => j.id === 'j-run-0001');
    const p = Object.assign({}, cur.progress, { substage: { node: 'KSampler', value: (k % 4) + 1, max: 4, view: 'side', at: `2026-10-22T10:01:${String(10 + k).padStart(2, '0')}`, prompt: 'p' + Math.floor(k / 4) } });
    if (k === 5) p.done = 2;
    srv.put(Object.assign({}, cur, { progress: p, log_tail: cur.log_tail.concat(['line ' + k]) }));
    await J.poll(); await tick(2);
  }
  const rc2 = cardOf('j-run-0001');
  check('UI-04: the running card is the same node after ten polls', rc2 === rc && rc2.parentNode === runGroup && runGroup.parentNode === groupsEl);
  check('UI-04: no clip player made again, none destroyed: the clips keep playing', made === madeBefore && destroyed === destroyedBefore && clipEls.every((e) => e.isConnected && rc.contains(e)), { made: made - madeBefore, destroyed: destroyed - destroyedBefore });
  check('UI-04: the log took its new lines in place', rc.querySelector('pre.jlog').textContent.includes('line 9'));
  const sl = rc.querySelector('div.jsubstage');
  check('2.3: the running card shows the ComfyUI substage', !!sl && /side · KSampler step \d of 4/.test(sl.textContent), sl && sl.textContent);
  check('2.2: the later polls ask only what changed since', srv.urls.filter((u) => /^\/api\/jobs\?since=[1-9]\d*&delta=1$/.test(u)).length >= 10);
  check('2.2: Jobs.subscribe heard each change with its ids', subs.filter((e) => JSON.stringify(e.changed) === '["j-run-0001"]').length >= 10 && subs[0].full === true, subs.slice(0, 2));
  // an open re-roll panel, a fold, a pick and a scrolled-up log survive another job finishing
  const dc = cardOf('j-done-0002');
  const btn = (c, text) => c.querySelectorAll('button').find((b) => b.textContent === text);
  btn(dc, 'Re-roll…').click(); await tick(1);
  const panelR = dc.querySelector('div.jreroll');
  const fold = dc.querySelectorAll('details.jfold')[0];
  fold.open = true; fold.dispatch('toggle');
  const wc = cardOf('j-wait-0003');
  wc.querySelectorAll('div.jchoice')[1].click(); await tick(1);
  const pre = rc.querySelector('pre.jlog');
  J.S.ui.get('j-run-0001').log = 3; pre.scrollTop = 3;
  const reqCard = panel.querySelectorAll('article.rcard')[0];
  if (reqCard) { btn(reqCard, 'Reject…').click(); await tick(1); const ta = reqCard.querySelector('div.rpanel textarea'); if (ta) { ta.value = 'legs too thin'; ta.dispatch('input'); } }
  srv.put(Object.assign({}, srv.jobs.find((j) => j.id === 'j-q-0004'), { state: 'running', started: '2026-10-22T10:05:00' }));
  await J.poll(); await tick(2);
  srv.put(Object.assign({}, srv.jobs.find((j) => j.id === 'j-q-0004'), { state: 'done', ended: '2026-10-22T10:06:00' }));
  const cur = srv.jobs.find((j) => j.id === 'j-run-0001');
  srv.put(Object.assign({}, cur, { log_tail: cur.log_tail.concat(['after']) }));
  await J.poll(); await tick(2);
  check('UI-04: an open re-roll panel survives another job finishing (the same node)', dc.isConnected && dc.querySelector('div.jreroll') === panelR && panelR.isConnected);
  check('UI-04: an open fold survives', fold.isConnected && fold.open === true);
  const wc2 = cardOf('j-wait-0003');
  const pb = wc2 && wc2.querySelector('button.jpick');
  check('UI-04: the pick survives (the picked candidate, the Pick button armed)', wc2 === wc && wc2.querySelectorAll('div.jchoice')[1].classList.contains('picked') && pb && !pb.disabled && pb.textContent === 'Pick c1', pb && pb.textContent);
  check('UI-04: a scrolled-up log keeps its place while new lines come', pre.isConnected && pre.scrollTop === 3 && pre.textContent.includes('after'), pre.scrollTop);
  const reqCard2 = panel.querySelectorAll('article.rcard')[0];
  check('UI-04: the request card keeps its open Reject panel and its draft', !!reqCard && reqCard2 === reqCard && reqCard.querySelector('div.rpanel textarea') && reqCard.querySelector('div.rpanel textarea').value === 'legs too thin');
  // a state change: the card is built again and the clips are handed over
  const runNow = srv.jobs.find((j) => j.id === 'j-run-0001');
  srv.put(Object.assign({}, runNow, { state: 'done', ended: '2026-10-22T10:10:00' }));
  const m0 = made, d0 = destroyed;
  await J.poll(); await tick(2);
  const rc3 = cardOf('j-run-0001');
  check('UI-04: a state change builds the card again in Finished, its clips handed over (none made, none destroyed)', rc3 && rc3 !== rc && rc3.dataset.state === 'done' && made === m0 && destroyed === d0 && clipEls.every((e) => rc3.contains(e)), { made: made - m0, destroyed: destroyed - d0 });
  // a removal
  srv.del('j-q-0004');
  await J.poll(); await tick(2);
  check('2.2: a removed job leaves the page', !cardOf('j-q-0004') && subs.some((e) => JSON.stringify(e.removed) === '["j-q-0004"]'));
  // the header: Re-queue all; the Ops fold
  const hdr = panel.querySelector('div.jinterrupted');
  check('2.7: "2 jobs were interrupted by the restart" with Re-queue all', !!hdr && hdr.textContent.includes('2 jobs were interrupted by the restart'), hdr && hdr.textContent);
  if (hdr) { btn(hdr, 'Re-queue all').click(); await tick(10); }
  check('2.7: Re-queue all posts /api/jobs/requeue_interrupted once', srv.posts.filter((p) => p.url === '/api/jobs/requeue_interrupted').length === 1 && statuses.some(([t]) => t.startsWith('2 interrupted jobs queued again')), statuses.slice(-2));
  srv.ops = { days: 7, outcomes: { done: { look: { creature_ctl: 3 } } }, medians: { creature_ctl: { rendered: { median: 700, p90: 800, n: 5 } } }, lock_wait: {}, failures: [{ reason: 'the error line', n: 1 }], cost: { requests: [], total_dollars: 0 } };
  const ops = panel.querySelector('details.jops');
  ops.open = true; ops.dispatch('toggle'); await tick(10);
  check('2.6: the Ops fold asks /api/ops?days=7 when opened and draws the outcomes, medians and failures', srv.urls.includes('/api/ops?days=7') && ops.querySelectorAll('table.jops-table').length === 2 && ops.textContent.includes('1× the error line'), ops.textContent.slice(0, 200));
  J.poll(); await tick(10);
  check('2.6: the 2 s header redraw leaves the Ops fold open', panel.querySelector('details.jops') === ops && ops.open);
  // the filter
  J.setFilter({ look: 'BG-C', id: 'bug' }); await tick(1);
  const shown = panel.querySelectorAll('article.jcard').filter((c) => !c.classList.contains('rcard')).map((c) => c.dataset.id).sort();
  check('UI-05: #jobs?look=BG-C shows that look\'s jobs only, with a way back', JSON.stringify(shown) === JSON.stringify(['j-done-0002', 'j-wait-0003']) && !!panel.querySelector('div.jfilter') && routes.some((r) => r.filter && r.filter.look === 'BG-C'), shown);
  btn(panel.querySelector('div.jfilter'), 'Show all jobs').click(); await tick(1);
  check('UI-05: Show all jobs brings every card back', !panel.querySelector('div.jfilter') && panel.querySelectorAll('article.jcard').filter((c) => !c.classList.contains('rcard')).length === 3);
  // a server without list_delta: 501 -> the whole list from then on
  srv.delta = false;
  await J.poll(); await tick(60); await J.poll(); await tick(2);
  check('2.2: a server without the delta (501): the page asks the whole list again, as before', J.S.noDelta === true && srv.urls.slice(-3).some((u) => /^\/api\/jobs\?since=\d+$/.test(u)));
  srv.delta = true; J.S.noDelta = false;
  // the offline pill
  srv.down = true;
  await J.poll(); await tick(2);
  const pill = document.getElementById('offline-pill');
  check('2.7: the offline pill says since when', !!pill && !pill.hidden && /^offline since \d\d:\d\d$/.test(pill.textContent), pill && pill.textContent);
  srv.down = false;
  await J.poll(); await tick(2);
  check('2.7: the pill goes when the server answers', pill.hidden === true);
  App.S.tab = 'creatures';

  // the look stage's live block
  const run2 = clipJob({ id: 'j-run-0009', target: { kind: 'enemy', id: 'bug', code: 'BG-B' }, outputs: [{ type: 'still', url: '/dl/f.png', label: 'front' }] });
  srv.put(run2);
  await J.poll(); await tick(2);
  const grid = document.createElement('div'); document.body.appendChild(grid);
  const looks = [{ code: 'BG-A', ready: true, sprite: '/sprite/enemy/bug/BG-A', default: true }, { code: 'BG-B', ready: true, sprite: '/sprite/enemy/bug/BG-B' }];
  const rec = { kind: 'enemy', id: 'bug', name: 'Bug', variants: looks, looks, variant: 'BG-A' };
  LookGrid.render(grid, rec, { kind: 'enemy', id: 'bug', data: { id: 'bug' }, ui: { look: 'BG-B' }, looks }, { kind: 'enemy', id: 'bug', selected: 'BG-B' });
  await tick(2);
  const live = grid.querySelector('div.lg-live');
  check('UI-05: the selected look\'s stage shows its running job and its request', !!live && !live.hidden && live.textContent.includes('stage side') && live.textContent.includes('request · WAITING') && live.textContent.includes('iteration 1 of 3'), live && live.textContent.slice(0, 200));
  check('UI-05: Approve on the stage (the request waits for approval) and the links into the Jobs tab', !!live && live.querySelectorAll('button').some((b) => b.textContent === 'Approve…') && live.querySelectorAll('a').some((a) => a.href === '#jobs/j-run-0009') && live.querySelectorAll('a').some((a) => a.href === '#requests/r-0001'));
  const hist = grid.querySelector('div.lg-history');
  check('UI-05: the history line with the look\'s jobs link', !!hist && hist.querySelectorAll('a').some((a) => a.href === '#jobs?look=BG-B&id=bug'), hist && hist.textContent);
  const cardsBefore = grid.querySelectorAll('article.lg-card');
  const liveBefore = grid.querySelector('div.lg-live');
  const cur9 = srv.jobs.find((j) => j.id === 'j-run-0009');
  srv.put(Object.assign({}, cur9, { progress: Object.assign({}, cur9.progress, { substage: { node: 'KSampler', value: 2, max: 4, view: 'side', at: '2026-10-22T10:07:00', prompt: 'z' } }) }));
  await J.poll(); await tick(2);
  const cardsAfter = grid.querySelectorAll('article.lg-card');
  const liveAfter = grid.querySelector('div.lg-live');
  check('UI-05: a poll redraws the live block (the substage) and never the grid', cardsAfter.length === cardsBefore.length && cardsAfter.every((c, i) => c === cardsBefore[i]) && liveAfter !== liveBefore && liveAfter.textContent.includes('KSampler step 2 of 4'), liveAfter && liveAfter.textContent.slice(0, 160));
  srv.put(Object.assign({}, srv.jobs.find((j) => j.id === 'j-done-0002'), { note: 'another asset\'s change' }));
  const liveKeep = grid.querySelector('div.lg-live');
  await J.poll(); await tick(2);
  check('UI-05: a change that does not touch the look leaves its live block alone', grid.querySelector('div.lg-live') === liveKeep);

  // assets.js refreshRecord: the Looks section alone
  global.AssetsModel = require(path.join(dir, 'assets_model.js'));
  global.AFIELDS = require(path.join(dir, 'assets_fields.js'));
  global.Forms = { closePop() {} };
  const A = new Function(fs.readFileSync(path.join(dir, 'assets.js'), 'utf8') + '\nreturn Assets;')();
  global.Assets = A;
  let builds = 0;
  const build = (pane, doc) => {
    builds++;
    const hd = document.createElement('div'); hd.className = 'ahead'; hd.textContent = 'head ' + builds; pane.appendChild(hd);
    pane.appendChild(A.section(doc, 'Identity', [Object.assign(document.createElement('input'), { value: doc.data.name })], { open: true }));
    pane.appendChild(A.section(doc, 'Looks', [document.createTextNode('looks ' + JSON.stringify(doc.data.variants || {}))], { open: true }));
  };
  global.Creatures = { redraw(doc, what) { if (!A.swapPane(doc, (pane) => build(pane, doc))) App.render('tab'); } };
  App.S.tab = 'creatures';
  const host = document.createElement('div'); document.body.appendChild(host);
  const data0 = { id: 'bug', name: 'Bug', variants: { 'BG-A': { sprite: 'a.png' } } };
  A.S.docs['enemy:bug'] = { key: 'enemy:bug', kind: 'enemy', id: 'bug', data: JSON.parse(JSON.stringify(data0)), saved: JSON.stringify(data0), history: [], future: [], ui: { open: {} }, looks: [], files: {}, badJson: {} };
  const doc = A.S.docs['enemy:bug'];
  const pane = A.buildPane(doc, (p) => build(p, doc)); host.appendChild(pane);
  const input = pane.querySelector('input'); input.value = 'typed but not applied';
  const identity = pane.querySelectorAll('details.asection')[0];
  srv.content = { ok: true, json: { id: 'bug', name: 'Bug', variants: { 'BG-A': { sprite: 'a.png' }, 'BG-B': { sprite: 'b.png', fresh: true } } }, looks: [], files: {}, mtime: 2 };
  await A.refreshRecord('enemy', 'bug'); await tick(1);
  const secs = doc.pane.querySelectorAll('details.asection');
  check('UI-04: refreshRecord draws the Looks section alone (the pane, the Identity section and its input are the same nodes)', doc.pane === pane && secs[0] === identity && pane.querySelector('input') === input && input.value === 'typed but not applied' && secs[1].textContent.includes('BG-B') && pane.querySelector('div.ahead').textContent === 'head ' + builds, [doc.pane === pane, secs[0] === identity, builds]);
  srv.content = { ok: true, json: { id: 'bug', name: 'Bug Renamed On Disk', variants: { 'BG-A': { sprite: 'a.png' } } }, looks: [], files: {}, mtime: 3 };
  await A.refreshRecord('enemy', 'bug'); await tick(1);
  check('UI-04: a key outside the looks changed on disk: the whole pane is drawn again, as before', doc.pane !== pane && doc.pane.isConnected && doc.pane.querySelector('input').value === 'Bug Renamed On Disk');
  done();
}
main().catch((e) => { out.push(['harness crashed', false, String(e && e.stack || e)]); done(); });
"""


def page_checks(check, run_node):
    import selftest_V as V
    dom = V.FLOWS_RUNNER.split("// Drive the job form")[0]
    src = dom + PAGE_MAIN
    res = run_node({}, src.replace("process.argv[2]", json.dumps(os.path.join(HERE, "jobs.js").replace("\\", "/"))))
    if res is None or res == {}:
        check(True, "LIVE97 page: node is not here (or it failed: see above): the DOM checks skipped")
        return
    for name, ok, detail in res:
        check(ok, "LIVE97 %s%s" % (name, (": " + detail[:400]) if (detail and not ok) else ""))


def wiring_checks(check):
    idx = _rd("index.html")
    # every page script parsing: the lead's selftest_JSSYNTAX97.py (frames.js did not parse at 51b037d)
    i_m, i_v, i_j = idx.find('src="jobs_model.js"'), idx.find('src="jobs_view.js"'), idx.find('src="jobs.js"')
    check(0 <= i_m < i_v < i_j, "LIVE97 wiring: index.html loads jobs_view.js between jobs_model.js and jobs.js")
    srv = _rd("server.py")
    check('jobs_call("list_delta", since)' in srv and 'jobs_call("list", since)' in srv and '(query.get("delta") or [""])[0] in ("1", "true")' in srv,
          "LIVE97 wiring: server.py answers delta=1 from list_delta and everything else from list() as before")
    jp = _rd("jobs.py")
    check("def list_delta(since_rev=None):" in jp and "def list(since_rev=None):" in jp and 'return {"rev": _state["rev"], "jobs": [_public(j, LOG_TAIL_SHORT) for j in _state["jobs"]]}' in jp,
          "LIVE97 wiring: jobs.py has list_delta beside the untouched list()")
    app = _rd("app.js")
    check("function initRoutes()" in app and "history.replaceState" in app and "'hashchange'" in app and "Frames.__routed" in app and "route(here());   // pass 97" in app,
          "LIVE97 wiring: app.js writes and restores the routes (tabs, jobs, requests, frames)")
    lk = _rd("looks.js")
    check("info.appendChild(liveHost(kind, id, look.code));" in lk and "Jobs.subscribe(onJobsChanged)" in lk and "JobsView.liveBlock(model" in lk, "LIVE97 wiring: the look stage's live block listens to Jobs.subscribe")
    jj = _rd("jobs.js")
    check("&delta=1" in jj and "JM.merge(S.jobs, d)" in jj and "function subscribe(fn)" in jj and "function patchCard(c, j, x)" in jj and "syncChildren(S.groups, blocks)" in jj and "clear(S.groups)" not in jj,
          "LIVE97 wiring: jobs.js polls the delta, merges it, patches cards by slot and never clears the groups")
    doc = open(os.path.join(ROOT, "docs", "level_editor.md"), encoding="utf-8").read()
    check("Pass 97: the live page" in doc, "LIVE97 docs: docs/level_editor.md has \"Pass 97: the live page\"")


def checks(check, run_node, server):
    delta_checks(check, server)
    model_checks(check, run_node)
    page_checks(check, run_node)
    wiring_checks(check)
