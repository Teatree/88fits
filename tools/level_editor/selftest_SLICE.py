"""The offline vertical slice (pass 96, lane REQ; the plan's 1.8 / OPS-01(a)): Garry's sentence end to end without a
GPU, in under 60 s, on a temp queue with the real workers:

    art_request.py start (over HTTP) -> the request's look job (a stand-in tool replaying a recorded log, writing the
    sidecar and touching the strip) -> the landing (the server's real merge_look, the frames store synced, the import
    stand-in) -> the fake evaluator's findings.json -> the fake planner's ops (stage a re-rolled frame, a note) ->
    waiting_for: approval -> Garry's one confirm (POST approve {confirm: true}) -> the frames_export (the REAL
    frames_store.export_look on the temp store) -> the import stand-in -> done -> `art_request.py result` prints the
    paragraph and the paths.

Plus the no-regression proofs Garry asked for: a plain job without a request runs exactly as before (no `request` key,
the same import follows), `since=0` returns everything, and WF-06(c): a cancel while a comfy job runs (the real
comfy.run against a fake ComfyUI that never finishes the prompt) sends `/queue {delete: [its id]}` and `/interrupt`,
never `clear`. The fakes: FakeComfy (REQ96), the stand-in tool written into the temp folder, FakeLoop / FakeCommands.
"""
import json
import os
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)
PY = sys.executable

STANDIN = r'''
"""The slice's stand-in for the art tools (pass 96): look | export | import | slow."""
import json, os, sys, time
mode, job_dir = sys.argv[1], sys.argv[2]
if mode == "look":
    content_json, code = sys.argv[3], sys.argv[4]
    with open(content_json, encoding="utf-8") as f:
        d = json.load(f)
    e = d["variants"]["BG-B"]
    print("comfy: prompt fake-look-%s" % os.path.basename(job_dir)[-4:], flush=True)
    for line in ("  render bug_bgb_side seed 5 2.0s  ok", "  ctl bug_bgb_ctl_side seed 5 40.0s ok", "gen_ctl: bug %s packed, 4 frames" % code):
        print(line, flush=True)
    strip = os.path.join(os.path.dirname(content_json), "bug_sprite_b.png")
    with open(strip, "rb") as f:
        data = f.read()
    with open(strip, "wb") as f:   # the landing: the same strip written again (a new mtime)
        f.write(data)
    res = {"id": "bug", "folder": "enemies/bug", "variant": code,
           "entry": {"sprite": "bug_sprite_b.png", "icon": "bug_icon_b.png", "anims": e["anims"], "strip_cols": e["strip_cols"], "fps": e["fps"], "head": 0.8},
           "top": {}, "info": {"clip_kind": {"side": "control"}, "qa_online": False}}
    side = os.environ.get("ASSET_JOB_SIDECAR") or os.path.join(job_dir, "result.json")
    with open(side, "w", encoding="utf-8") as f:
        json.dump(res, f)
    print("sidecar written: %s" % side, flush=True)
elif mode == "export":
    store, content, backups, tools = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
    sys.path.insert(0, tools)
    import frames_store as FS
    r = FS.export_look("enemy", "bug", "BG-B", job=os.environ.get("ASSET_JOB_ID"), store=store, content=content, backups=backups,
                       sidecar=os.path.join(job_dir, "result.json"))
    print("export: " + json.dumps({k: r.get(k) for k in ("ok", "changed", "strip_sha1", "unchanged", "error")}), flush=True)
    sys.exit(0 if r.get("ok") else 1)
elif mode == "import":
    print("import: ok (stand-in, no Godot)", flush=True)
elif mode == "slow":
    server, tools = sys.argv[3], sys.argv[4]
    sys.argv.append("--server=" + server)
    sys.path.insert(0, tools)
    import comfy
    g = comfy.Graph()
    g.add("SaveImage", images=("1", 0), filename_prefix="88fits/slice")
    comfy.run(g, timeout=40)   # prints `comfy: prompt <id>`; the fake never finishes this prompt: the cancel ends it
'''


def _http(base):
    import urllib.error
    import urllib.request

    def get(path):
        try:
            with urllib.request.urlopen(base + path, timeout=20) as r:
                return r.status, json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode("utf-8") or "{}")

    def post(path, body):
        req = urllib.request.Request(base + path, data=json.dumps(body).encode("utf-8"), method="POST", headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode("utf-8") or "{}")
    return get, post


def _wait(fn, timeout, poll=0.25):
    """Poll fn() until it returns something true, or the timeout; returns the last value."""
    t0 = time.time()
    v = None
    while time.time() - t0 < timeout:
        v = fn()
        if v:
            return v
        time.sleep(poll)
    return v


class SliceLoop:
    """The fake planner of the slice: writes the fake evaluator's findings beside the landed look job, then stages the
    re-rolled frame, notes, and has nothing more."""

    def __init__(self, world, vid):
        self.world, self.vid, self.calls = world, vid, []

    def next_op(self, rec, findings):
        self.calls.append(len(rec.get("iterations") or []))
        look_job = next((j for j in rec["jobs"] if j.startswith("j")), None)
        if findings is None and look_job:
            self.world.findings(look_job, passed=True, hard=0, advisory=1, calls=3, dollars=0.0)
        n = len(rec.get("iterations") or [])
        a = rec["asset"]
        if n == 0:
            return {"op": "stage", "target": {"kind": a["kind"], "id": a["id"], "code": a["code"], "group": "run/side"}, "args": {"slot": 1, "version": self.vid}, "why": "the re-rolled frame is cleaner"}
        if n == 1:
            return {"op": "note", "target": {"kind": a["kind"], "id": a["id"], "code": a["code"]}, "args": {"text": "0 hard, 1 advisory: the gates pass"}, "why": "tier 0"}
        return None


def checks(check, run_node, server):
    from selftest_REQ96 import TempWorld, FakeComfy, FakeCommands, cli
    t_start = time.time()
    with TempWorld() as W:
        jobs, R, FS = W.jobs, W.R, W.FS
        tool = os.path.join(W.tmp, "standin_tool.py")
        with open(tool, "w", encoding="utf-8", newline="\n") as f:
            f.write(STANDIN)
        fake = FakeComfy()
        fake.hold = True   # the slow job's prompt never finishes
        bug_json = os.path.join(W.content, "enemies", "bug", "bug.json")
        real_plan = jobs._plan

        def fake_plan(job):
            kind, t = job["kind"], job.get("target") or {}
            jd = os.path.join(jobs.JOBS_DIR, job["id"])
            os.makedirs(jd, exist_ok=True)
            env = {"ASSET_JOB_SIDECAR": os.path.join(jd, "result.json"), "ASSET_JOB_ID": job["id"], "PYTHONIOENCODING": "utf-8", "PYTHONUNBUFFERED": "1",
                   "LOCK_HELD_COMFY": "1", "COMFY_LOCK_HELD": "1"}
            if kind == "look" and (job.get("spec") or {}).get("note") == "slow":
                step = [PY, tool, "slow", jd, fake.url, os.path.join(ROOT, "tools")]
            elif kind == "look":
                step = [PY, tool, "look", jd, bug_json, t.get("code", "BG-B")]
            elif kind == "frames_export":
                step = [PY, tool, "export", jd, FS.STORE, FS.CONTENT, FS.BACKUPS, os.path.join(ROOT, "tools")]
            elif kind == "import":
                step = [PY, tool, "import", jd]
            else:
                return real_plan(job)
            return {"mode": "steps", "lock": None, "steps": [step], "env_steps": env, "equiv": "stand-in %s" % kind, "tool": "", "call": "", "argv": [],
                    "env": {}, "type": "enemies", "folder": "", "id": t.get("id", ""), "launch": None}

        jobs._plan = fake_plan
        vid = W.second_version(1)
        loop = SliceLoop(W, vid)
        cmds = FakeCommands(W)
        R.set_loop(loop)
        R.set_commands(cmds)
        saved_cs = jobs.COMFY_SERVER
        jobs.COMFY_SERVER = fake.url
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        httpd.daemon_threads = True
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % httpd.server_address[1]
        get, post = _http(base)
        strip_path = os.path.join(W.content, "enemies", "bug", "bug_sprite_b.png")
        with open(strip_path, "rb") as f:
            strip_before = f.read()
        n_requests_before = len(R.list_records())
        try:
            jobs.start_workers()
            check(jobs.status()["workers"] == len(jobs.LANES), "the slice runs the real workers (%d lanes)" % len(jobs.LANES))
            # 1. Claude's one command
            rc, out = cli("start", "--kind", "enemy", "--id", "bug", "--code", "BG-B", "--goal", "a cleaner side walk for the bug", "--rerolls", "1", editor=base)
            rid = next((w for w in out.split() if R.RID_RE.match(w)), None)
            check(rc == 0 and rid is not None, "art_request.py start over HTTP: exit 0 and a request id: %s" % out.strip().splitlines()[:1])
            # 2. the loop runs on its own: the look lands, the import follows, the evaluator's findings, two ops, waiting for approval
            fold = _wait(lambda: (lambda f: f if f and f.get("state") == "waiting" else None)(get("/api/requests/%s" % rid)[1]), 40)
            check(fold is not None and fold["state"] == "waiting" and fold["waiting_for"] == "approval", "the loop ran to waiting_for approval on its own: %s %s" % ((fold or {}).get("state"), (fold or {}).get("stop_reason")))
            if fold:
                kinds = [(j["kind"], j["state"]) for j in fold["jobs"]]
                check(("look", "done") in kinds, "the request's look job landed through the stand-in: %s" % kinds)
                imp = _wait(lambda: (lambda f: f if any(j["kind"] == "import" and j["state"] == "done" for j in f["jobs"]) else None)(get("/api/requests/%s" % rid)[1]), 20)
                check(imp is not None, "the import after the look landed (the stand-in): %s" % [(j["kind"], j["state"]) for j in (imp or fold)["jobs"]])
                ops = [it["op"]["op"] for it in fold["iterations"]]
                check(ops == ["stage", "note"] and fold["iteration"] == {"n": 2, "of": 4} and fold["stop_reason"] == "the gates passed",
                      "the planner's ops ran (stage, note) and the gates passed: %s / %s" % (ops, fold["stop_reason"]))
                check(fold["findings"] and fold["findings"]["gates"]["pass"] is True and fold["spent"]["evaluator_calls"] == 3 and fold["sheet"],
                      "the fake evaluator's findings are on the fold (3 calls, a sheet): %s" % fold["findings"])
                check(fold["provisional"] == {"code": "BG-B", "groups": {"run/side": {"staged": [1], "pinned": []}}}, "the provisional winner is the staged slot: %s" % fold["provisional"])
                check("waiting for Garry's approval of the provisional look BG-B (1 frame to export in run/side)" in fold["summary"], "the paragraph: %s" % fold["summary"])
                look_job = jobs._find(fold["jobs"][0]["id"])
                check(look_job.get("comfy_prompt", "").startswith("fake-look-") and look_job.get("request") == rid and look_job["progress"]["done"] >= 1,
                      "the look job kept its prompt id and its request, its stages ticked: %s" % {k: look_job.get(k) for k in ("comfy_prompt", "request")})
                with open(strip_path, "rb") as f:
                    check(f.read() == strip_before and W.entry().get("fresh") is True, "before the approval the game's strip is untouched and the look is NEW")
            rc, out = cli("result", rid, editor=base)
            check(rc == 2 and "waiting for Garry's approval" in out and "page:" in out, "art_request.py result says 'waiting for Garry's approval' (exit 2): %s" % out.strip().splitlines()[1:2])
            # 3. Garry's one confirm
            st, d = post("/api/requests/%s/approve" % rid, {})
            check(st == 409 and d.get("needs_confirm") and d["batch"]["staged"] == 1 and d["batch"]["groups"] == {"run/side": {"staged": [1], "pinned": []}}, "approve without confirm: the batch box: %s" % d.get("batch"))
            st, d = post("/api/requests/%s/approve" % rid, {"confirm": True})
            check(st == 200 and d["ok"] and d["state"] == "approved" and d["export_job"], "approve {confirm: true}: approved, the export queued: %s" % d.get("export_job"))
            # 4. the export (the real frames_store.export_look) and its import land; the request is done
            fold = _wait(lambda: (lambda f: f if f and f.get("state") in ("done", "failed") else None)(get("/api/requests/%s" % rid)[1]), 40)
            check(fold is not None and fold["state"] == "done", "the export and its import landed -> done: %s %s" % ((fold or {}).get("state"), (fold or {}).get("error")))
            if fold and fold["state"] == "done":
                res = fold["result"]
                with open(strip_path, "rb") as f:
                    strip_after = f.read()
                check(strip_after != strip_before and res["strip_sha1"] == FS.sha_of(strip_after) and len(res["changed"]) == 1 and res["changed"][0]["slot"] == 1,
                      "the strip was packed again with the staged frame; the result names its sha1 and the change: %s" % res["changed"])
                check(res["code"] == "BG-B" and res["entry"].get("sprite") == "bug_sprite_b.png" and res["import_job"] and res["export_job"] and res["flags"] == {"hard": 0, "advisory": 1, "pass": True}
                      and res["verdicts"] == {"jump": 1} and res["summary"].startswith("Request") and res["strip"],
                      "the result: code, entry, the import, the flags and verdicts from the findings, the paragraph, the strip: %s" % {k: res.get(k) for k in ("code", "import_job", "flags", "verdicts")})
                e = W.entry()
                check("fresh" not in e and e["anims"] and e["strip_cols"], "the look was approved (no NEW mark) and the export's entry merged")
                g = W.group()
                logp = os.path.join(g.dir, "exports.json")
                exports = json.load(open(logp, encoding="utf-8")) if os.path.isfile(logp) else []
                check(exports and exports[-1]["job"] == res["export_job"] and exports[-1]["strip_sha1"] == res["strip_sha1"] and g.staged() == {} and g.selected()["1"]["id"] == vid and g.selected()["1"]["pinned"],
                      "the store logged the export under the request's job; the staged choice is now selected and pinned")
                ex = jobs._find(res["export_job"])
                check(ex["kind"] == "frames_export" and ex["spec"].get("in_play") is True and ex["spec"]["note"] == "request %s approved" % rid and ex["request"] == rid, "the export job carries confirm's note and the request")
            rc, out = cli("result", rid, editor=base)
            check(rc == 0 and "Done: BG-B installed, 1 frame changed" in out and "strip:" in out and "entry:" in out and "import:" in out, "art_request.py result on the done request: exit 0, the paragraph and the paths: %s" % out.strip().splitlines()[-4:])
            rc, out = cli("status", rid, editor=base)
            check(rc == 0 and out.startswith("%s done" % rid), "status: done, exit 0")
            events = [e["event"] for e in R.load(rid)["history"]]
            check(events[:2] == ["created", "job"] and "waiting" in events and "approved" in events and events[-1] == "done" and events.count("op") == 2, "the history tells the whole story: %s" % events)
            # 5. no regression: a plain job without a request runs exactly as before
            st, d = post("/api/jobs", {"kind": "look", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "spec": {"method": "creature_ctl"}, "title": "a plain look"})
            pj = d["job"]["id"]
            check(st == 200 and "request" not in d["job"], "a plain POST /api/jobs has no request key")
            pdone = _wait(lambda: (lambda j: j if j and j["job"]["state"] == "done" else None)(get("/api/job/%s" % pj)[1]), 30)
            check(pdone is not None and "request" not in pdone["job"] and pdone["job"]["written"]["layout"] in ("entry", "block"), "the plain look ran and merged as before: %s" % (pdone or {}).get("job", {}).get("written"))
            pimp = _wait(lambda: [j for j in get("/api/jobs?since=0")[1]["jobs"] if j["kind"] == "import" and j["title"].endswith("(after %s)" % pj)] or None, 10)
            check(pimp and "request" not in pimp[0] and pimp[0]["spec"]["targets"] == ["enemies/bug"], "its import follows without a request, as before")
            check(len(R.list_records()) == n_requests_before + 1, "a plain job wrote no request record")
            st, d = get("/api/jobs?since=0")
            check(st == 200 and len(d["jobs"]) == len(jobs._state["jobs"]) and d["rev"] > 0, "since=0 returns everything (%d jobs)" % len(d["jobs"]))
            st, d2 = get("/api/jobs?since=%d" % d["rev"])
            check(d2.get("unchanged") is True or d2["rev"] > d["rev"], "since=<rev> is unchanged (or a newer rev)")
            # 6. WF-06(c): a cancel while a comfy job runs: the real comfy.run against the fake, its own prompt deleted + interrupted, never clear
            fake.requests.clear()
            st, d = post("/api/jobs", {"kind": "look", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "spec": {"method": "creature_ctl", "note": "slow"}, "title": "a slow look to cancel"})
            sj = d["job"]["id"]
            running = _wait(lambda: (lambda j: j if j and j["job"].get("comfy_prompt") else None)(get("/api/job/%s" % sj)[1]), 30)
            pid = (running or {}).get("job", {}).get("comfy_prompt")
            check(running is not None and pid and pid.startswith("fake-"), "the running job's `comfy: prompt <id>` line reached its record: %s" % pid)
            fake.running = [pid] if pid else []
            prompts = [b for p, b in fake.posts() if p == "/prompt"]
            check(len(prompts) == 1 and "prompt" in prompts[0] and prompts[0].get("client_id", "").startswith("88fits-"), "the real comfy.run posted the graph to the fake /prompt")
            st, d = post("/api/jobs/%s/cancel" % sj, {})
            ended = _wait(lambda: (lambda j: j if j and j["job"]["state"] == "cancelled" else None)(get("/api/job/%s" % sj)[1]), 30)
            check(st == 200 and ended is not None, "the cancel ended the job: %s" % ((ended or {}).get("job", {}).get("state")))
            sent = [(p, b) for p, b in fake.posts() if p != "/prompt"]
            check(sent == [("/queue", {"delete": [pid]}), ("/interrupt", {})], "cancel sent /queue delete [its id] then /interrupt: %s" % sent)
            check(not any("clear" in json.dumps(b) for _, b in fake.posts()), "never /queue clear (a hand run's prompt survives a Stop)")
            fake.hold = False
        finally:
            httpd.shutdown()
            httpd.server_close()
            jobs.COMFY_SERVER = saved_cs
            jobs._plan = real_plan
            try:
                jobs.stop(timeout=5.0)
            except Exception:
                pass
            fake.close()
    elapsed = time.time() - t_start
    check(elapsed < 60, "the slice runs offline in under 60 s (%.1f s)" % elapsed)
    print("selftest_SLICE: %.1f s" % elapsed)
