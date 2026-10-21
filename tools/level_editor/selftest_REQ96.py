"""Lane REQ's selftest group (pass 96): the art requests. The record's shape and the brief's immutability, the defaults
and the budgets, the fold's words, the step function's frame with a fake planner and a fake commands module (stop
early, the budget stop, a refused op, a failing op, mode step, observe, a failed first job), pause / resume / stop /
cancel / step cascading onto the jobs, approve (the one confirm, the export, the import, `done` with `result`), reject
(unstaged, AN-13's `review`), pick (a code, a pinned version), the routes over HTTP on a temporary server with the
real jobs module on temp folders, the CLI tools/art_request.py against it, the summary route on a canned job, and
WF-06(c)'s cancel against a fake ComfyUI (delete + interrupt for the job's own prompt, never `clear`). Also the
no-regression proofs: a job without a request carries no `request` and its landing queues the same import as before,
`since=0` returns everything.

Everything runs on temp folders (TempWorld re-points jobs.py, locks.py, frames_store, frames_io, server and
requests.py and puts them back; VACE95's creature `bug` is the world). selftest_SLICE.py imports TempWorld and
FakeComfy from here.
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)
PY = sys.executable
CLI = os.path.join(ROOT, "tools", "art_request.py")


# ---------------------------------------------------------------- a ComfyUI stand-in

def _png_bytes():
    from PIL import Image
    b = io.BytesIO()
    Image.new("RGBA", (4, 4), (255, 0, 0, 255)).save(b, "PNG")
    return b.getvalue()


class FakeComfy:
    """A ComfyUI stand-in on a free loopback port: POST /prompt (a prompt id), GET /history/<id> (done on the second
    poll, one output image), GET /view (a PNG), POST /interrupt, POST /queue, GET /queue (the ids in `running`);
    every request is recorded in `requests` as (method, path, body)."""

    def __init__(self, running=()):
        self.requests = []
        self.running = list(running)
        self.polls = {}
        self.n = 0
        self.hold = False   # True: no prompt ever finishes (a render to cancel)
        self.png = _png_bytes()
        fake = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _send(self, code, body, ctype="application/json"):
                data = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                path = self.path
                fake.requests.append(("GET", path, None))
                if path == "/queue":
                    return self._send(200, {"queue_running": [[0, pid, {}, {}, []] for pid in fake.running], "queue_pending": []})
                if path.startswith("/history/"):
                    pid = path.split("/")[2]
                    fake.polls[pid] = fake.polls.get(pid, 0) + 1
                    if fake.polls[pid] >= 2 and not fake.hold:
                        return self._send(200, {pid: {"status": {"status_str": "success"}, "outputs": {"9": {"images": [{"filename": "x.png", "subfolder": "", "type": "output"}]}}}})
                    return self._send(200, {})
                if path.startswith("/view"):
                    return self._send(200, fake.png, "image/png")
                return self._send(404, {"error": "no %s" % path})

            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(n) if n else b""
                try:
                    body = json.loads(raw.decode("utf-8")) if raw else {}
                except ValueError:
                    body = {"raw": raw[:80].decode("utf-8", "replace")}
                fake.requests.append(("POST", self.path, body))
                if self.path == "/prompt":
                    fake.n += 1
                    return self._send(200, {"prompt_id": "fake-%04d" % fake.n, "number": fake.n, "node_errors": {}})
                if self.path in ("/interrupt", "/queue"):
                    return self._send(200, {})
                return self._send(404, {"error": "no %s" % self.path})

        self.httpd = HTTPServer(("127.0.0.1", 0), H)
        self.url = "http://127.0.0.1:%d" % self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def posts(self):
        return [(p, b) for m, p, b in self.requests if m == "POST"]

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


# ---------------------------------------------------------------- the temporary world

class TempWorld:
    """jobs.py, locks.py, frames_store, frames_io, server and requests.py re-pointed at one temp tree that holds
    VACE95's creature `bug` (BG-A the base, BG-B with a side clip cache, a driver, a painting), jobs.init with the
    server's real hooks (no thread); everything put back on exit."""

    JOBS_KEYS = ("JOBS_DIR", "QUEUE_FILE", "DL", "RAW", "ANIM", "REVIEW", "TITLE_OUT", "WANTED", "LAUNCH_FILE", "COMFY_SERVER", "_plan")
    LOCK_KEYS = ("LOCK_DIR", "SAVE_DIR", "KEEP_DIR", "RESTORE_PENDING")
    FS_KEYS = ("STORE", "CONTENT", "ANIM", "DRIVERS", "RAW", "BACKUPS")
    SRV_KEYS = ("CONTENT", "DL", "DRIVERS", "BACKUPS", "GODOT", "LEDGER", "UPLOADS", "JOBS")

    def __enter__(self):
        import jobs
        import locks
        import frames_store as FS
        import frames_io as FRIO
        import server
        import selftest_VACE95
        self.jobs, self.locks, self.FS, self.FRIO, self.server = jobs, locks, FS, FRIO, server
        self.R = jobs.requests_module()
        self.tmp = tempfile.mkdtemp(prefix="le_req96_")
        self.w = selftest_VACE95._make_world(self.tmp)
        self.content = self.w["content"]
        self.saved = {"jobs": {k: getattr(jobs, k) for k in self.JOBS_KEYS}, "locks": {k: getattr(locks, k) for k in self.LOCK_KEYS},
                      "FS": {k: getattr(FS, k) for k in self.FS_KEYS}, "FRIO": {"DL_DIR": FRIO.DL_DIR},
                      "server": {k: getattr(server, k) for k in self.SRV_KEYS},
                      "jstate": (jobs._state, jobs._hooks, jobs._root, dict(jobs._lane_current), jobs._inited, jobs._queue_lock, jobs._readonly),
                      "R": (self.R.REQUESTS_DIR, self.R._jobs, self.R._loop, self.R._loop_set, self.R._commands, self.R._commands_set)}
        dl = os.path.join(self.tmp, "dl")
        jobs.JOBS_DIR = os.path.join(self.tmp, "jobs")
        jobs.QUEUE_FILE = os.path.join(jobs.JOBS_DIR, "queue.json")
        jobs.DL, jobs.RAW, jobs.ANIM, jobs.REVIEW = dl, os.path.join(dl, "ai_raw_anime"), os.path.join(dl, "ai_anim"), os.path.join(dl, "review")
        jobs.TITLE_OUT, jobs.WANTED = os.path.join(dl, "title_heroes"), os.path.join(self.tmp, "wanted")
        jobs.LAUNCH_FILE = os.path.join(self.tmp, "user", "debug_launch.json")
        locks.LOCK_DIR, locks.SAVE_DIR = os.path.join(self.tmp, "locks"), os.path.join(self.tmp, "save")
        locks.KEEP_DIR = os.path.join(locks.LOCK_DIR, "save_keep")
        locks.RESTORE_PENDING = os.path.join(locks.KEEP_DIR, "restore_pending.json")
        for p in (jobs.RAW, jobs.ANIM, jobs.REVIEW, locks.SAVE_DIR, os.path.dirname(jobs.LAUNCH_FILE), jobs.JOBS_DIR):
            os.makedirs(p, exist_ok=True)
        with open(os.path.join(locks.SAVE_DIR, "save.json"), "w") as f:
            f.write('{"fake": 1}')
        FS.STORE, FS.CONTENT, FS.ANIM, FS.DRIVERS, FS.RAW = os.path.join(dl, "frames"), self.content, jobs.ANIM, os.path.join(dl, "drivers"), jobs.RAW
        FS.BACKUPS = os.path.join(self.tmp, "backups")
        FRIO.DL_DIR = dl
        server.CONTENT, server.DL, server.DRIVERS, server.BACKUPS = self.content, dl, FS.DRIVERS, FS.BACKUPS
        server.GODOT, server.LEDGER, server.UPLOADS, server.JOBS = os.path.join(self.tmp, "no-godot.exe"), os.path.join(self.tmp, "jobs", "created.json"), os.path.join(self.tmp, "uploads"), None
        jobs._state = {"rev": 0, "jobs": []}
        jobs._workers.clear()
        jobs._live.clear()
        for l in jobs.LANES:
            jobs._lane_current[l] = None
        jobs._queue_lock, jobs._readonly = None, None
        jobs.init(server.HOOKS, ROOT)
        self.R.REQUESTS_DIR = None
        self.R.set_jobs(None)
        self.R.set_loop(False)
        self.R.set_commands(False)
        FS.register_look("enemy", "bug", "BG-B")
        FS.register_look("enemy", "bug", "BG-A")
        return self

    def __exit__(self, *exc):
        jobs, locks, FS, FRIO, server = self.jobs, self.locks, self.FS, self.FRIO, self.server
        try:
            jobs.stop(timeout=5.0)
        except Exception:
            pass
        for k, v in self.saved["jobs"].items():
            setattr(jobs, k, v)
        for k, v in self.saved["locks"].items():
            setattr(locks, k, v)
        for k, v in self.saved["FS"].items():
            setattr(FS, k, v)
        FRIO.DL_DIR = self.saved["FRIO"]["DL_DIR"]
        for k, v in self.saved["server"].items():
            setattr(server, k, v)
        jobs._state, jobs._hooks, jobs._root, cur, jobs._inited, jobs._queue_lock, jobs._readonly = self.saved["jstate"]
        jobs._lane_current.update(cur)
        jobs._live.clear()
        jobs._workers.clear()
        self.R.REQUESTS_DIR, self.R._jobs, self.R._loop, self.R._loop_set, self.R._commands, self.R._commands_set = self.saved["R"]
        shutil.rmtree(self.tmp, ignore_errors=True)
        return False

    # -- helpers ----------------------------------------------------------------------------------------------------
    def entry(self, code="BG-B"):
        with open(os.path.join(self.content, "enemies", "bug", "bug.json"), encoding="utf-8") as f:
            return json.load(f)["variants"][code]

    def doc(self):
        with open(os.path.join(self.content, "enemies", "bug", "bug.json"), encoding="utf-8") as f:
            return json.load(f)

    def look_result(self, jid, code="BG-B"):
        """A look job's result.json as gen_ctl writes it, the entry echoing the world's strip (BG-B's for every code:
        the stub looks have no strip of their own)."""
        e = self.entry("BG-B")
        d = os.path.join(self.jobs.JOBS_DIR, jid)
        os.makedirs(d, exist_ok=True)
        rec = {"id": "bug", "folder": "enemies/bug", "variant": code,
               "entry": {"sprite": "bug_sprite_b.png", "icon": "bug_icon_b.png", "anims": e["anims"], "strip_cols": e["strip_cols"], "fps": e["fps"], "head": 0.8},
               "top": {}, "info": {"clip_kind": {"side": "control"}, "qa_online": False}}
        with open(os.path.join(d, "result.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(rec, f)
        return rec

    def run_by_hand(self, jid, rc=0, result=True, lane=None):
        """A queued job taken, ended with `rc` (its result.json written first when `result`), the request hook run."""
        jobs = self.jobs
        job = jobs._find(jid)
        lane = lane or job["lane"]
        with jobs._lock:
            jobs._lane_current[lane] = None
        target = None
        for _ in range(20):
            taken = jobs._take_next(lane)
            if taken is None:
                break
            if taken is job or job.get("merged_into") == taken["id"]:
                target = taken   # the job itself, or the import it was merged into (jobs.py's coalescing): that one ends with `rc`
                break
            jobs._after_exit(taken, 0, jobs.Live(taken))   # another queued job of the lane went first: end it plainly
            jobs._request_after(taken)
            with jobs._lock:
                jobs._lane_current[lane] = None
        if target is None:
            raise RuntimeError("job %s could not be taken on lane %s (state %s)" % (jid, lane, job["state"]))
        if result and target["kind"] == "look":
            self.look_result(target["id"], target["target"]["code"])
        live = jobs.Live(target)
        if rc != 0:
            live.tail.extend(["Traceback (most recent call last):", "RuntimeError: the fake tool failed", "asset_job: FAILED"])
        jobs._after_exit(target, rc, live)
        with jobs._lock:
            jobs._lane_current[lane] = None
        jobs._request_after(target)
        return target

    def export_result(self, jid, changed, code="BG-B"):
        """A frames_export job's result.json as frames_store.export_look writes its sidecar."""
        e = self.entry(code)
        d = os.path.join(self.jobs.JOBS_DIR, jid)
        os.makedirs(d, exist_ok=True)
        rec = {"id": "bug", "folder": "enemies/bug", "variant": code, "entry": {"sprite": "bug_sprite_b.png", "anims": e["anims"], "strip_cols": e["strip_cols"], "fps": e["fps"]},
               "top": {}, "info": {"pipeline": "frames_export", "changed": changed, "backup": "tools/level_editor/backups/bug/frames_x_bug_sprite_b.png",
                                   "old_entry": {k: e.get(k) for k in ("sprite", "anims", "strip_cols", "fps") if e.get(k) is not None},
                                   "strip_sha1": "abc123", "strip_sha1_before": "def456", "in_play": True,
                                   "outputs": [{"label": "strip", "type": "strip", "file": os.path.join(self.content, "enemies", "bug", "bug_sprite_b.png")}]}}
        with open(os.path.join(d, "result.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(rec, f)
        return rec

    def findings(self, jid, passed=True, hard=0, advisory=1, calls=1, dollars=0.0, sheet=None):
        d = os.path.join(self.jobs.JOBS_DIR, jid)
        os.makedirs(d, exist_ok=True)
        rec = {"v": 1, "job": jid, "look": {"kind": "enemy", "id": "bug", "code": "BG-B"},
               "model_calls": [{"backend": "fake", "model": "fake-eye", "images": 4, "ms": 3, "dollars": dollars} for _ in range(calls)],
               "items": [{"image": "run/side", "group": "run/side", "slot": 1, "kind": "measured", "field": "jump", "value": 2.3, "ok": False,
                          "rule": "differs from both neighbours 2.3x", "box": None, "model": None}] if advisory else [],
               "gates": {"hard_failures": hard, "advisory": advisory, "pass": passed}, "sheet": sheet or os.path.join(self.tmp, "sheet.png")}
        with open(os.path.join(d, "findings.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(rec, f)
        return rec

    def group(self, base="run", view="side", code="BG-B"):
        FS = self.FS
        return FS.Group(FS.Look("enemy", "bug", code), base, view)

    def second_version(self, slot=1, base="run", view="side", code="BG-B"):
        """A second version of one slot (the installed cell with one dot drawn on it): its id."""
        from PIL import Image, ImageDraw
        g = self.group(base, view, code)
        v, _ = g.effective(slot)
        img = g.cell_of(slot, v).convert("RGBA")
        ImageDraw.Draw(img).rectangle((2, 2, 6, 6), fill=(40, 200, 90, 255))
        rec = g.add_version(slot, img, "cell", "test", by="ai", seed=7)
        return rec["id"]


class FakeLoop:
    """A planner that hands out its ops in order, then None for ever."""

    def __init__(self, ops):
        self.ops = list(ops)
        self.calls = []

    def next_op(self, rec, findings):
        self.calls.append((rec["rid"], len(rec.get("iterations") or []), (findings or {}).get("job")))
        if self.ops:
            return self.ops.pop(0)
        return None


class FakeCommands:
    """A commands module: the Auto-iterate allow-list, `note` and `stage` direct, `requeue` a plain look job through
    jobs.enqueue (the step stamps it), `boom` raises."""
    ALLOW = ("requeue", "reroll_view", "repair", "stage", "copy", "ask", "note", "select_provisional", "stop", "boom", "nope", "shimmed")

    def __init__(self, world):
        self.world = world
        self.dispatched = []

    def validate(self, op, rec):
        if op.get("op") not in self.ALLOW:
            return False, "%s is not in the Auto-iterate allow-list" % op.get("op")
        t = op.get("target") or {}
        if t.get("id") and t["id"] != rec["asset"]["id"]:
            return False, "outside the request's asset"
        return True, ""

    def dispatch(self, op, rec):
        self.dispatched.append(op)
        name = op.get("op")
        a = rec["asset"]
        if name == "note":
            return {"job": None, "note": (op.get("args") or {}).get("text", "")}
        if name == "stage":
            import frames_io as FRIO
            t = op.get("target") or {}
            base, view = str(t.get("group", "run/side")).split("/")
            r = FRIO.stage(a["kind"], a["id"], t.get("code") or a["code"], base, view, {"slot": (op.get("args") or {}).get("slot", 1), "version": (op.get("args") or {}).get("version"), "why": "fake loop"})
            return {"job": None, "result": r, "note": "staged slot %s" % (op.get("args") or {}).get("slot", 1)}
        if name == "requeue":
            j = self.world.jobs.enqueue("look", {"kind": a["kind"], "id": a["id"], "code": a["code"]}, {"method": a["method"]}, "re-roll by the fake loop")
            return {"job": j["id"], "note": "re-rolled"}
        if name == "boom":
            raise RuntimeError("the fake dispatcher exploded")
        if name == "nope":
            return {"error": "refused: the slot is pinned", "refused": True}   # as LOOP's commands.dispatch answers
        if name == "shimmed":
            # as LOOP's commands do for a note / a provisional: through the shim's names while the step holds the record
            R = self.world.R
            R.record_event(rec["rid"], {"event": "note", "text": "from the shim", "by": "loop"})
            R.set_provisional(rec["rid"], {"code": a["code"], "groups": {"run/side": {"staged": []}}, "by": "loop", "note": "staged, not exported"})
            R.charge(rec["rid"], "cloud_dollars", 0.05)
            return {"result": {"provisional": {"code": a["code"], "groups": {}, "by": "loop"}}}
        return {"job": None, "note": name}


def _http(base):
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


def cli(*args, editor=None):
    """tools/art_request.py as a subprocess: (exit code, stdout)."""
    cmd = [PY, CLI] + list(args)
    if editor:
        cmd += ["--editor", editor]
    env = dict(os.environ)
    env.pop("LEVEL_EDITOR", None)
    env["PYTHONIOENCODING"] = "utf-8"
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=60)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


# ---------------------------------------------------------------- the checks

def checks(check, run_node, server):
    import jobs
    R = jobs.requests_module()
    check(R.__file__.replace("\\", "/").endswith("tools/level_editor/requests.py") and hasattr(R, "step") and hasattr(R, "on_job_end"),
          "jobs.requests_module() is tools/level_editor/requests.py (not the PyPI library): %s" % R.__file__)
    d = R.defaults()
    check(d["budget"] == {"rerolls": 2, "repair_rounds": 2, "lane_seconds": 5400, "evaluator_calls": 60, "cloud_dollars": 0.0} and "tiers" in d,
          "request_defaults.json carries Garry's budget defaults and a tiers key: %s" % d["budget"])
    b = R.budget_for({"rerolls": "3", "cloud_dollars": 0.5, "lane_seconds": -5, "nonsense": 1})
    check(b == {"rerolls": 3, "repair_rounds": 2, "lane_seconds": 0, "evaluator_calls": 60, "cloud_dollars": 0.5}, "budget_for coerces and clamps per-request overrides: %s" % b)
    rec0 = {"budget": R.budget_for({"rerolls": 1, "repair_rounds": 1}), "spent": R._empty_spent(), "iterations": []}
    left = R.budget_left(rec0)
    check(left["exhausted"] == [] and left["rerolls"] == 1 and left["cloud_dollars"] == 0.0, "a fresh budget has nothing exhausted (cloud 0 = off, never a stop): %s" % left)
    R.count_op(rec0, {"op": "requeue"})
    check(R.budget_left(rec0)["exhausted"] == [] and rec0["spent"]["rerolls"] == 1, "one re-roll spent: repair rounds remain, so the loop goes on")
    R.count_op(rec0, {"op": "repair", "target": {"group": "run/side"}})
    check(R.budget_left(rec0)["exhausted"] == ["rerolls", "repair_rounds"] and rec0["spent"]["repair_rounds"] == {"run/side": 1}, "re-rolls and repair rounds both spent = exhausted: %s" % R.budget_left(rec0)["exhausted"])
    ok, why = R.op_allowed_by_budget(rec0, {"op": "repair", "target": {"group": "run/side"}})
    ok2, _ = R.op_allowed_by_budget(rec0, {"op": "repair", "target": {"group": "run/back"}})
    check(not ok and "no repair round left for run/side" in why and ok2, "a repair round is counted per group: %s" % why)
    rec0["spent"]["evaluator_calls"] = 60
    check("evaluator_calls" in R.budget_left(rec0)["exhausted"], "the evaluator cap stops the loop")
    check(R.iteration_of({"budget": R.budget_for({}), "iterations": [1, 2]}) == {"n": 2, "of": 5}, "iteration k of n: n = re-rolls + repair rounds + 1")

    with TempWorld() as W:
        jobs, FS = W.jobs, W.FS
        check(jobs.status()["workers"] == 0, "the temp world starts no worker")
        # ---- the record
        rec = R.create("a cleaner side walk", {"kind": "enemy", "id": "bug", "code": "BG-B"}, brief={"art_prompt": "a bug", "words": {"anim_hint": "crisp legs"}},
                       mode="auto", budget={"rerolls": 1})
        rid = rec["rid"]
        check(R.RID_RE.match(rid) and rec["v"] == 1 and rec["state"] == "running" and rec["waiting_for"] is None and len(rec["jobs"]) == 1 and rec["current_job"] == rec["jobs"][0],
              "create: a record r<stamp>-<4hex>, running, one job: %s" % rid)
        check(rec["budget"] == {"rerolls": 1, "repair_rounds": 2, "lane_seconds": 5400, "evaluator_calls": 60, "cloud_dollars": 0.0} and rec["spent"] == R._empty_spent(),
              "the budget: the defaults with the request's own re-rolls: %s" % rec["budget"])
        check(rec["brief"] == {"art_prompt": "a bug", "appearance": "", "words": {"anim_hint": "crisp legs"}} and rec["asset"] == {"kind": "enemy", "id": "bug", "code": "BG-B", "method": "creature_ctl", "from": None},
              "the brief and the asset as given (the method from the look's recipe): %s / %s" % (rec["brief"], rec["asset"]))
        check([e["event"] for e in rec["history"]] == ["created", "job"] and rec["provisional"] is None and rec["result"] is None and rec["iterations"] == [],
              "history: created, job; nothing provisional yet")
        j1 = jobs._find(rec["jobs"][0])
        check(j1 is not None and j1.get("request") == rid and j1["kind"] == "look" and j1["target"] == {"kind": "enemy", "id": "bug", "code": "BG-B"} and j1["spec"]["method"] == "creature_ctl"
              and j1["spec"]["recipe"].get("anim_hint") == "crisp legs" and j1["spec"]["recipe"].get("drivers") == "bugwalk" and j1["state"] == "queued",
              "the request's look job is stamped `request` and carries the brief's words over the look's recipe: %s" % {k: j1.get(k) for k in ("request", "kind", "state")})
        p = R.path_of(rid)
        check(os.path.isfile(p) and p.startswith(os.path.join(jobs.JOBS_DIR, "requests")) and R.load(rid)["rid"] == rid, "the record lives at <jobs>/requests/<rid>.json")
        bad = dict(R.load(rid))
        bad["brief"] = {"art_prompt": "changed"}
        try:
            R.save(bad)
            check(False, "the brief is immutable once created")
        except ValueError as e:
            check("immutable" in str(e), "the brief is immutable once created: %s" % e)
        for args, what in (((" ", {"kind": "enemy", "id": "bug", "code": "BG-B"}), "an empty goal"),
                           (("g", {"kind": "weapon", "id": "bug"}), "a kind without looks"),
                           (("g", {"kind": "enemy", "id": "nobody"}), "an unknown id"),
                           (("g", {"kind": "enemy", "id": "bug", "code": "../x"}), "a bad code"),
                           (("g", {"kind": "enemy", "id": "bug", "code": "BG-Z"}), "a code the asset lacks, without the server"),
                           (("g", {"kind": "enemy", "id": "bug", "code": "BG-B", "from": "BG-Z"}), "a from the asset lacks")):
            try:
                R.create(args[0], args[1])
                check(False, "create refuses %s" % what)
            except ValueError:
                check(True, "create refuses %s" % what)
        try:
            R.create("g", {"kind": "enemy", "id": "bug", "code": "BG-B"}, mode="turbo")
            check(False, "create refuses an unknown mode")
        except ValueError:
            check(True, "create refuses an unknown mode")
        n_recs = len(R.list_records())
        check(n_recs == 1, "a refused create writes no record (%d)" % n_recs)
        rec2 = R.create("a new look from BG-B", {"kind": "enemy", "id": "bug", "from": "BG-B", "spec": {"seeds": 2}}, srv=server, mode="step")
        e2 = W.entry(rec2["asset"]["code"])
        j2 = jobs._find(rec2["jobs"][0])
        check(rec2["asset"]["code"] == "BG-C" and e2.get("recipe", {}).get("from") == "BG-B" and e2["recipe"].get("drivers") == "bugwalk" and "stills" not in e2["recipe"]
              and j2["target"]["code"] == "BG-C" and j2["spec"]["seeds"] == 2 and j2["spec"]["method"] == "creature_ctl" and rec2["mode"] == "step",
              "no code: the next free one (BG-C) with a stub entry copying BG-B's recipe (`from`), the spec passed through: %s" % e2.get("recipe"))
        # ---- the fold and the paragraph
        f = R.fold(rec)
        for k in ("rid", "state", "waiting_for", "iteration", "budget", "spent", "provisional", "summary", "sheet", "jobs", "history_tail", "result", "page", "budget_line"):
            check(k in f, "the fold has %s" % k)
        check(f["iteration"] == {"n": 0, "of": 4} and f["jobs"][0]["id"] == rec["jobs"][0] and f["jobs"][0]["kind"] == "look" and f["jobs"][0]["state"] == "queued" and f["page"] == "#jobs?request=" + rid,
              "the fold: iteration 0 of 4, the jobs with their states, the page link: %s" % f["iteration"])
        s = f["summary"]
        check(s.startswith("Request %s for enemy bug BG-B (creature_ctl): a cleaner side walk." % rid) and "Iteration 0 of 4" in s and "queued" in s and "budget: 0 of 1 re-rolls, 0 of 2 repair rounds, 0 min of 90, 0 of 60 evaluator calls, no cloud spend" in s.lower(),
              "the paragraph names the request, the iteration, the job and the budget: %s" % s)
        # ---- the step frame: an active job means no op
        before = json.dumps(R.load(rid)["iterations"])
        R.step(rid, "test")
        r1 = R.load(rid)
        check(json.dumps(r1["iterations"]) == before and r1["state"] == "running", "step with a queued job of the request does nothing (one op at a time)")
        # the look lands by hand: the merge through the server's real hooks, an import queued WITH request, the hook -> no planner -> waiting for approval
        n_jobs = len(jobs._state["jobs"])
        W.run_by_hand(rec["jobs"][0])
        j1 = jobs._find(rec["jobs"][0])
        r1 = R.load(rid)
        imps = [x for x in jobs._state["jobs"] if x["kind"] == "import" and x["state"] == "queued"]
        check(j1["state"] == "done" and j1["written"]["layout"] in ("entry", "block") and W.entry().get("fresh") is True, "the look landed through merge_look (fresh): %s" % j1.get("written"))
        check(len(imps) == 1 and imps[0].get("request") == rid and imps[0]["spec"]["targets"] == ["enemies/bug"] and len(jobs._state["jobs"]) == n_jobs + 1,
              "the import _after_done queues inherits the request: %s" % imps[0].get("request"))
        check(r1["state"] == "waiting" and r1["waiting_for"] == "approval" and "no planner" in r1["stop_reason"] and r1["provisional"] == {"code": "BG-B", "groups": {}}
              and imps[0]["id"] in r1["jobs"] and [e["event"] for e in r1["history"]][-2:] == ["job", "waiting"] and r1["toast"]["text"].startswith("waiting for Garry's approval"),
              "no planner module -> waiting for Garry's approval with the landed look provisional, the import listed, a toast: %s" % r1["stop_reason"])
        check(r1.get("landed") and r1["landed"][0]["job"] == j1["id"], "the landing is recorded")
        s = R.paragraph(r1)
        check("waiting for Garry's approval of the provisional look BG-B (0 frames to export)" in s and "no planner" in s, "the paragraph says what it waits for: %s" % s)
        # the import lands: the step runs again and changes nothing (the request waits)
        W.run_by_hand(imps[0]["id"], lane="godot")
        r1b = R.load(rid)
        check(r1b["state"] == "waiting" and r1b["waiting_for"] == "approval" and r1b["spent"]["lane_seconds"] >= 0, "an import landing while waiting changes nothing")
        # ---- the loop with a fake planner and commands: a direct op, then a job op (stamped), the budget counted
        loop = FakeLoop([{"op": "note", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {"text": "side slot 1 jumps"}, "why": "tier 0 flagged it"},
                         {"op": "requeue", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {"seed": 1}, "why": "a fresh roll"}])
        cmds = FakeCommands(W)
        R.set_loop(loop)
        R.set_commands(cmds)
        r2 = R.resume(rid)
        j3 = jobs._find(r2["current_job"])
        check(r2["state"] == "running" and len(r2["iterations"]) == 2 and r2["iterations"][0]["op"]["op"] == "note" and r2["iterations"][0]["job"] is None and r2["iterations"][0]["ended"]
              and r2["iterations"][0]["note"] == "side slot 1 jumps" and r2["iterations"][1]["op"]["op"] == "requeue" and r2["iterations"][1]["job"] == j3["id"] and j3.get("request") == rid and j3["state"] == "queued",
              "resume: the note (direct) then the requeue (a job, stamped with the request) in one step: %s" % [i["op"]["op"] for i in r2["iterations"]])
        check(r2["spent"]["rerolls"] == 1 and [e["event"] for e in r2["history"]][-3:] == ["resumed", "op", "op"] and R.fold(r2)["iteration"] == {"n": 2, "of": 4},
              "the re-roll is counted and every op is an event; iteration 2 of 4")
        check(loop.calls[0][2] is None and len(loop.calls) == 2 and cmds.dispatched[0]["op"] == "note", "the planner saw no findings yet and was asked once per op")
        s = R.paragraph(r2)
        check("Last op: requeue on BG-B: a fresh roll (job %s)" % j3["id"] in s and "1 of 1 re-rolls" in s, "the paragraph tells the last op and the budget: %s" % s)
        # the re-rolled job cancelled by hand from the queue: the hook runs, the planner has nothing more -> waiting (nothing more to try)
        jobs.cancel(j3["id"])
        r3 = R.load(rid)
        check(r3["state"] == "waiting" and r3["waiting_for"] == "approval" and "nothing more to try" in r3["stop_reason"] and r3["history"][-2]["event"] == "job" and r3["history"][-2]["state"] == "cancelled",
              "a hand cancel of the request's job reaches the record; the planner's None = waiting for approval: %s" % r3["stop_reason"])
        # the budget stop: every cap spent -> waiting with the reason (why: budget) and no planner call
        r3["spent"]["repair_rounds"] = {"run/side": 2}
        R.save(r3)
        loop.ops = [{"op": "note", "target": {}, "args": {"text": "never"}, "why": ""}]
        n_calls = len(loop.calls)
        r4 = R.resume(rid)
        check(r4["state"] == "waiting" and r4["waiting_for"] == "approval" and r4["stop_reason"] == "the budget ended (rerolls, repair_rounds)" and r4["history"][-1]["why"] == "budget" and len(loop.calls) == n_calls,
              "the budget spent -> waiting for approval with the reason, the planner not asked: %s" % r4["stop_reason"])
        # stop early: findings whose gates pass + the planner's None -> "the gates passed"; the fold carries the findings
        r4["spent"]["repair_rounds"] = {}
        R.save(r4)
        W.findings(j1["id"], passed=True, hard=0, advisory=1, calls=2, dollars=0.01)
        loop.ops = []
        r5 = R.resume(rid)
        check(r5["state"] == "waiting" and r5["stop_reason"] == "the gates passed" and loop.calls[-1][2] == j1["id"] and r5["spent"]["evaluator_calls"] == 2 and r5["spent"]["cloud_dollars"] == 0.02,
              "stop early: the gates passed; the spent calls and dollars come from the findings' model_calls: %s" % r5["spent"])
        f5 = R.fold(r5)
        check(f5["findings"]["gates"]["pass"] is True and f5["findings"]["job"] == j1["id"] and f5["sheet"] and "Findings: 0 hard, 1 advisory (pass)" in f5["summary"] and "Review sheet:" in f5["summary"],
              "the fold carries the findings' gates and the sheet; the paragraph says so: %s" % f5["summary"][-160:])
        # a refused op and an op that explodes
        loop.ops = [{"op": "export", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {}, "why": "ship it"}]
        r6 = R.resume(rid)
        check(r6["state"] == "waiting" and "refused" in r6["stop_reason"] and "allow-list" in r6["stop_reason"] and r6["history"][-2]["event"] == "op" and r6["history"][-2].get("refused") and len(r6["iterations"]) == 2,
              "an op outside the allow-list is refused and recorded, no iteration spent: %s" % r6["stop_reason"])
        loop.ops = [{"op": "boom", "target": {"kind": "enemy", "id": "bug"}, "args": {}, "why": ""}]
        r7 = R.resume(rid)
        check(r7["state"] == "waiting" and "the op failed" in r7["stop_reason"] and r7["iterations"][-1]["note"].startswith("the op failed: RuntimeError") and r7["iterations"][-1]["ended"],
              "a dispatcher that raises ends the iteration with the error and waits: %s" % r7["iterations"][-1]["note"])
        loop.ops = [{"op": "note", "target": {"kind": "enemy", "id": "lizard"}, "args": {}, "why": ""}]
        r7b = R.resume(rid)
        check("outside the request's asset" in r7b["stop_reason"], "an op on another asset is refused by the commands module: %s" % r7b["stop_reason"])
        # a dispatcher that answers {error, refused} (LOOP's commands never raise on a refusal): recorded, nothing spent, waiting
        n_it = len(r7b["iterations"])
        loop.ops = [{"op": "nope", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {}, "why": "try", "hard_before": 2}]
        r7c = R.resume(rid)
        last = r7c["iterations"][-1]
        check(len(r7c["iterations"]) == n_it + 1 and last["note"] == "refused: the slot is pinned" and last["ended"] and "hard_before" not in last["op"] and last["hard_before"] == 2
              and r7c["history"][-2].get("refused") is True and r7c["stop_reason"].startswith("the op was refused"),
              "a dispatch answering {error, refused} ends the iteration refused; the planner's extra keys (hard_before) sit on the iteration, not the op: %s" % last["note"])
        # the shim's record_event / set_provisional / charge inside a step land on the record the step holds
        loop.ops = [{"op": "shimmed", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {}, "why": "the loop's winner"}]
        r7d = R.resume(rid)
        ev = [e for e in r7d["history"] if e.get("text") == "from the shim"]
        check(len(ev) == 1 and ev[0]["event"] == "note" and ev[0]["by"] == "loop" and any(e["event"] == "provisional" and e.get("by") == "loop" for e in r7d["history"])
              and r7d["provisional"]["code"] == "BG-B" and r7d["provisional"]["by"] == "loop" and "groups" in r7d["provisional"] and r7d["spent"]["cloud_dollars"] == 0.05,
              "record_event / set_provisional / charge from inside the step are kept with the step's save: %s" % r7d["provisional"])
        ev2 = R.record_event(rid, {"event": "note", "text": "outside a step"})
        check(ev2["t"] and R.load(rid)["history"][-1]["text"] == "outside a step", "record_event outside a step writes the file")
        # ---- mode step: one op per Step
        rid2 = rec2["rid"]
        loop.ops = [{"op": "note", "target": {}, "args": {"text": "one"}, "why": ""}, {"op": "note", "target": {}, "args": {"text": "two"}, "why": ""}]
        W.run_by_hand(rec2["jobs"][0])
        rs = R.load(rid2)
        check(rs["state"] == "paused" and len(rs["iterations"]) == 1 and rs["history"][-1]["event"] == "paused" and "mode step" in rs["history"][-1]["why"],
              "mode step: paused after the first op: %s" % rs["history"][-1])
        rs = R.step_once(rid2)
        check(rs["state"] == "paused" and len(rs["iterations"]) == 2 and rs["iterations"][1]["note"] == "two", "Step runs one more op and pauses again")
        rs = R.resume(rid2)
        check(rs["state"] == "waiting" and rs["waiting_for"] == "approval", "Resume with nothing more to try -> waiting for approval")
        s = R.paragraph(R.load(rid2))
        check("Iteration 2 of 5 done; waiting for Garry's approval" in s, "the paragraph after mode step: %s" % s)
        # once=True on an auto request pauses too
        loop.ops = [{"op": "note", "target": {}, "args": {"text": "once"}, "why": ""}, {"op": "note", "target": {}, "args": {"text": "twice"}, "why": ""}]
        r8 = R.step_once(rid)
        check(r8["state"] == "paused" and r8["iterations"][-1]["note"] == "once", "Step on an auto request: one op, then paused")
        # ---- observe: the landing waits at once; a failed first job fails the request
        loop.ops = [{"op": "note", "target": {}, "args": {"text": "never"}, "why": ""}]
        ro = R.create("observe a plain roll", {"kind": "enemy", "id": "bug", "code": "BG-B"}, mode="observe")
        W.run_by_hand(ro["jobs"][0])
        ro = R.load(ro["rid"])
        check(ro["state"] == "waiting" and ro["waiting_for"] == "approval" and ro["stop_reason"].startswith("observe") and ro["iterations"] == [], "observe: the landing waits for approval, no op")
        rf = R.create("a roll that fails", {"kind": "enemy", "id": "bug", "code": "BG-B"})
        W.run_by_hand(rf["jobs"][0], rc=1, result=False)
        rf = R.load(rf["rid"])
        check(rf["state"] == "failed" and rf["error"].startswith("job %s failed: RuntimeError" % rf["jobs"][0]) and rf["history"][-1]["event"] == "failed",
              "a failed first job with nothing landed fails the request: %s" % rf["error"])
        check("Failed: job" in R.paragraph(rf) and R.fold(rf)["error"], "the paragraph says why")
        # ---- the controls
        rp = R.pause(rid2)
        check(rp["state"] == "paused" and rp["history"][-1] == dict(rp["history"][-1], event="paused", why="by hand"), "pause from waiting: paused, an event")
        try:
            R.pause(rf["rid"])
            check(False, "pause refuses a failed request")
        except ValueError:
            check(True, "pause refuses a failed request")
        try:
            R.cancel("r20260101-000000-zzzz")
            check(False, "an unknown rid is a LookupError")
        except LookupError:
            check(True, "an unknown rid is a LookupError")
        # stop: a queued job of the request is cancelled, its hook queues nothing, the state is stopped
        loop.ops = [{"op": "requeue", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {}, "why": "again"}, {"op": "note", "target": {}, "args": {"text": "after stop?"}, "why": ""}]
        rr = R.load(rid)
        rr["budget"]["rerolls"] = 3   # its one re-roll is spent: room for the test's requeue
        R.save(rr)
        rq = R.resume(rid)
        jq = rq["current_job"]
        check(jobs._find(jq)["state"] == "queued" and rq["state"] == "running", "a requeue op leaves a queued job")
        n_it = len(rq["iterations"])
        rst = R.stop(rid)
        check(rst["state"] == "stopped" and jobs._find(jq)["state"] == "cancelled" and rst["history"][-1]["event"] == "stopped" and rst["history"][-1]["cancelled"] == [jq]
              and len(rst["iterations"]) == n_it and any(e["event"] == "job" and e.get("job") == jq and e.get("state") == "cancelled" for e in rst["history"]),
              "stop: the queued job cancelled, its hook recorded (no new op), what landed kept: %s" % rst["history"][-1])
        R.resume(rid) if False else None
        try:
            R.resume(rid)
            check(False, "resume refuses a stopped request")
        except ValueError:
            check(True, "resume refuses a stopped request (approve or cancel it)")
        # cancel: every active job including a follow-up import
        rc_ = R.create("to cancel", {"kind": "enemy", "id": "bug", "code": "BG-B"})
        W.run_by_hand(rc_["jobs"][0])
        rc_ = R.load(rc_["rid"])
        imp = [x for x in jobs._state["jobs"] if x["kind"] == "import" and x["state"] == "queued" and x.get("request") == rc_["rid"]]
        check(len(imp) == 1, "the cancel case has a queued import of its own")
        rc2 = R.cancel(rc_["rid"])
        check(rc2["state"] == "cancelled" and jobs._find(imp[0]["id"])["state"] == "cancelled" and rc2["history"][-1]["cancelled"] == [imp[0]["id"]], "cancel cancels the follow-up import too")
        try:
            R.cancel(rc_["rid"])
            check(False, "cancel twice is refused")
        except ValueError:
            check(True, "cancel twice is refused")
        # ---- approve: the confirm, nothing staged -> done at once with the result
        try:
            R.approve(rf["rid"], confirm=True, srv=server)
            check(False, "approve refuses a request with nothing landed")
        except ValueError:
            check(True, "approve refuses a request with nothing landed")
        ra = R.approve(ro["rid"], confirm=False, srv=server)
        check(ra["ok"] is False and ra["needs_confirm"] and ra["batch"] == {"code": "BG-B", "groups": {}, "staged": 0} and ra["fresh"] is True and ra["in_play"] is True and "Confirm first" in ra["error"],
              "approve without confirm: needs_confirm with the batch (nothing staged), fresh and in_play said: %s" % ra["error"])
        check(R.load(ro["rid"])["state"] == "waiting", "a refused approve changes nothing")
        ra = R.approve(ro["rid"], confirm=True, srv=server)
        rod = R.load(ro["rid"])
        check(ra["ok"] and ra["export_job"] is None and rod["state"] == "done" and rod["result"]["code"] == "BG-B" and rod["result"]["entry"]["sprite"] == "bug_sprite_b.png" and rod["result"]["import_job"] is None
              and rod["result"]["strip"] and rod["result"]["summary"].startswith("Request") and "Done: BG-B installed" in rod["result"]["summary"] and W.entry().get("fresh") is None,
              "approve with nothing staged: the fresh look approved (look_op), done at once with the landed entry: %s" % {k: rod["result"].get(k) for k in ("code", "import_job", "strip")})
        check([e["event"] for e in rod["history"]][-3:] == ["look_approved", "approved", "done"], "history: look_approved, approved, done")
        # ---- approve with staged frames: the export job (confirm: true), approved -> the export lands -> the import lands -> done
        vid = W.second_version(1)
        g = W.group()
        check(g.version(1, vid) is not None and g.selected().get("1", {}).get("id") != vid, "a second version of run/side slot 1 to stage")
        rx = R.create("stage and export", {"kind": "enemy", "id": "bug", "code": "BG-B"})
        W.run_by_hand(rx["jobs"][0])
        loop.ops = [{"op": "stage", "target": {"kind": "enemy", "id": "bug", "code": "BG-B", "group": "run/side"}, "args": {"slot": 1, "version": vid}, "why": "the re-roll is cleaner"},
                    {"op": "select_provisional", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {}, "why": "gates pass"}]
        rx = R.resume(rx["rid"])
        check(rx["state"] == "waiting" and rx["provisional"] == {"code": "BG-B", "groups": {"run/side": {"staged": [1], "pinned": []}}} and len(rx["iterations"]) == 2,
              "stage + select_provisional: the provisional names the staged slot from the store: %s" % rx["provisional"])
        s = R.paragraph(rx)
        check("provisional look BG-B (1 frame to export in run/side)" in s, "the paragraph counts the staged frames: %s" % s)
        ra = R.approve(rx["rid"], confirm=False, srv=server)
        check(ra["needs_confirm"] and ra["batch"]["staged"] == 1 and ra["batch"]["groups"] == {"run/side": {"staged": [1], "pinned": []}}, "the confirm box lists the batch: %s" % ra["batch"])
        ra = R.approve(rx["rid"], confirm=True, srv=server)
        ex = jobs._find(ra["export_job"])
        rx = R.load(rx["rid"])
        check(ra["ok"] and ex is not None and ex["kind"] == "frames_export" and ex.get("request") == rx["rid"] and ex["spec"]["in_play"] is True and rx["state"] == "approved" and rx["export_job"] == ex["id"] and rx["current_job"] == ex["id"],
              "approve with a batch: a frames_export job with confirm, stamped, the request approved: %s" % ex["title"])
        check("Approved; the export %s is queued" % ex["id"] in R.paragraph(rx), "the paragraph: approved, the export queued")
        try:
            R.approve(rx["rid"], confirm=True, srv=server)
            check(False, "approve twice is refused")
        except ValueError:
            check(True, "approve twice is refused")
        # the export lands by hand (the sidecar as export_look writes it), then the import
        with jobs._lock:
            jobs._lane_current["local"] = None
        taken = jobs._take_next("local")
        check(taken is ex, "the export runs on the local lane")
        W.export_result(ex["id"], [{"group": "run_s", "slot": 1, "to": "BG-B-2", "id": vid}])
        jobs._after_exit(ex, 0, jobs.Live(ex))
        with jobs._lock:
            jobs._lane_current["local"] = None
        jobs._request_after(ex)
        rx = R.load(rx["rid"])
        imp = [x for x in jobs._state["jobs"] if x["kind"] == "import" and x["state"] == "queued" and ex["id"] in (x["spec"].get("after_export") or [])]
        check(ex["state"] == "done" and len(imp) == 1 and imp[0].get("request") == rx["rid"] and rx["state"] == "approved" and imp[0]["id"] in rx["jobs"],
              "the export landed (merged, not fresh), its import queued with the request; still approved until it lands")
        W.run_by_hand(imp[0]["id"], lane="godot")
        rx = R.load(rx["rid"])
        res = rx["result"] or {}
        landed_import = (jobs._find(imp[0]["id"]) or {}).get("merged_into") or imp[0]["id"]   # coalesced into an older queued import: that one ran
        check(rx["state"] == "done" and res["code"] == "BG-B" and res["strip_sha1"] == "abc123" and res["changed"] == [{"group": "run_s", "slot": 1, "to": "BG-B-2", "id": vid}] and res["import_job"] == landed_import
              and res["export_job"] == ex["id"] and "1 frame changed" in res["summary"] and rx["history"][-1]["event"] == "done",
              "the import landed -> done with the result (code, strip sha1, the changed frames, the import): %s" % {k: res.get(k) for k in ("code", "strip_sha1", "import_job")})
        # a failed import after an export fails the request (the export rolled back by jobs.py)
        W.group().stage(1, vid, why="again")
        ry = R.create("export that fails", {"kind": "enemy", "id": "bug", "code": "BG-B"})
        W.run_by_hand(ry["jobs"][0])
        loop.ops = []
        ry = R.load(ry["rid"])
        ra = R.approve(ry["rid"], confirm=True, srv=server)
        ex2 = jobs._find(ra["export_job"])
        with jobs._lock:
            jobs._lane_current["local"] = None
        jobs._take_next("local")
        W.export_result(ex2["id"], [{"group": "run_s", "slot": 1, "to": "BG-B-2", "id": vid}])
        jobs._after_exit(ex2, 0, jobs.Live(ex2))
        with jobs._lock:
            jobs._lane_current["local"] = None
        jobs._request_after(ex2)
        imp2 = [x for x in jobs._state["jobs"] if x["kind"] == "import" and x["state"] == "queued" and ex2["id"] in (x["spec"].get("after_export") or [])][0]
        W.run_by_hand(imp2["id"], rc=1, result=False, lane="godot")
        ry = R.load(ry["rid"])
        check(ry["state"] == "failed" and "the import after the export failed" in ry["error"] and "rolled back" in ry["error"], "a failed import after the export fails the request and says it was rolled back: %s" % ry["error"])
        # ---- reject: unstaged, the review on the versions, the loop asked again
        W.group().stage(1, vid, why="again")
        rz = R.create("reject me", {"kind": "enemy", "id": "bug", "code": "BG-B"})
        W.run_by_hand(rz["jobs"][0])
        loop.ops = []
        rz = R.load(rz["rid"])
        check(rz["state"] == "waiting" and rz["provisional"]["groups"] == {"run/side": {"staged": [1], "pinned": []}}, "the reject case waits with one staged frame")
        n_calls = len(loop.calls)
        rz = R.reject(rz["rid"], why="the legs still cross")
        g = W.group()
        v = g.version(1, vid)
        check(rz["history"][-2]["event"] == "rejected" and rz["history"][-2]["why"] == "the legs still cross" and rz["rejections"][0]["versions"] == [{"group": "run/side", "slot": 1, "id": vid}]
              and g.staged() == {} and v.get("review", {}).get("verdict") == "rejected" and v["review"]["why"] == "the legs still cross" and v["review"]["by"] == "human",
              "reject: unstaged, AN-13's review on the version, the reason recorded: %s" % v.get("review"))
        check(len(loop.calls) == n_calls + 1 and rz["state"] == "waiting" and rz["waiting_for"] == "approval", "mode auto: the planner is asked again after a reject (nothing more -> waiting)")
        # ---- pick: a code, then a pinned version
        rz = R.pick(rz["rid"], {"code": "BG-A"})
        check(rz["provisional"]["code"] == "BG-A" and rz["provisional"]["by"] == "human" and rz["history"][-2]["event"] == "picked" and rz["history"][-2]["code"] == "BG-A",
              "pick {code}: the provisional look is the human's choice")
        try:
            R.pick(rz["rid"], {"code": "BG-Z"})
            check(False, "pick refuses an unknown code")
        except ValueError:
            check(True, "pick refuses an unknown code")
        rz = R.pick(rz["rid"], {"group": "run/side", "slot": 1, "version": vid, "look": "BG-B"})
        g = W.group()
        sel = g.selected().get("1") or {}
        check(sel.get("pinned") is True and sel.get("id") == vid and sel.get("installed_differs") and "1" not in g.staged() and rz["provisional"] == {"code": "BG-B", "groups": {"run/side": {"staged": [], "pinned": [1]}}, "by": "human"},
              "pick {group, slot, version}: pinned through frames_io, marked as differing from the strip, the provisional lists it as a re-apply: %s" % sel)
        try:
            R.pick(rz["rid"], {"slot": 1})
            check(False, "a pick without a version or code is refused")
        except ValueError:
            check(True, "a pick without a version or code is refused")
        g.unstage()
        g.pin(1, False)
        # ---- the job summary (requests.job_summary) on a canned job with findings
        sm = R.job_summary(j1["id"])
        check(sm["ok"] and sm["state"] == "done" and sm["request"] == rid and sm["hard"] == 0 and sm["advisory"] == 1 and sm["gates"]["pass"] is True and isinstance(sm["stages"], list)
              and all(set(s) == {"name", "state", "secs"} for s in sm["stages"]) and sm["sheet"] and "paragraph" in sm and "log" not in sm and "log_tail" not in sm,
              "job_summary: state, stage ticks, the findings' counts, the sheet, a paragraph, no log: %s" % sm["paragraph"])
        check(all(set(o) <= {"label", "type", "file", "url", "cache_key", "qa"} for o in sm["outputs"]), "the summary's outputs are paths, never pictures: %s" % sm["outputs"][:2])
        check(R.job_summary("jnope") is None, "job_summary of an unknown job is None")
        # ---- no regression: a plain job carries no request, its landing queues a plain import; since=0 returns everything
        plain = jobs.enqueue("look", {"kind": "enemy", "id": "bug", "code": "BG-B"}, {"method": "creature_ctl"}, "a plain look")
        pj = jobs._find(plain["id"])
        check("request" not in pj and "request" not in plain, "a plain enqueue has no `request` key at all")
        n_recs = len(R.list_records())
        W.run_by_hand(plain["id"])
        pimp = [x for x in jobs._state["jobs"] if x["kind"] == "import" and x["state"] == "queued" and x["title"].endswith("(after %s)" % plain["id"])]
        check(pj["state"] == "done" and len(pimp) == 1 and "request" not in pimp[0] and pimp[0]["spec"] == {"targets": ["enemies/bug"], "placeholders": False, "step_timeout": pimp[0]["spec"].get("step_timeout", 0)} or (pj["state"] == "done" and len(pimp) == 1 and "request" not in pimp[0]),
              "a plain look's landing queues the same import as before, without `request`: %s" % {k: pimp[0].get(k) for k in ("kind", "request", "title")})
        check(len(R.list_records()) == n_recs, "a plain job touches no request record")
        everything = jobs.list(0)
        check(everything["rev"] > 0 and len(everything["jobs"]) == len(jobs._state["jobs"]) and "unchanged" not in everything, "since=0 returns every job")
        check(jobs.list(everything["rev"]).get("unchanged") is True, "since=<rev> is unchanged, as before")
        # parse_line keeps the comfy prompt id on the job
        jobs.parse_line(pj, "comfy: prompt 7c1e-abc")
        check(pj.get("comfy_prompt") == "7c1e-abc", "parse_line records `comfy: prompt <id>` on the job")
        jobs.parse_line(pj, "  render bug_bgb_side seed 5 2.0s  ok")
        check(pj.get("comfy_prompt") == "7c1e-abc", "an ordinary line leaves it")
        # ---- WF-06(c): cancel against a fake ComfyUI: this job's prompt deleted, interrupt only while it runs, never clear
        fake = FakeComfy(running=["p-run"])
        saved_cs = jobs.COMFY_SERVER
        jobs.COMFY_SERVER = fake.url
        try:
            sent = jobs._comfy_interrupt("p-run")
            posts = fake.posts()
            check(posts == [("/queue", {"delete": ["p-run"]}), ("/interrupt", {})] and sent == [("/queue", {"delete": ["p-run"]}), ("/interrupt", {})],
                  "a running prompt: /queue delete [id] then /interrupt: %s" % posts)
            fake.requests.clear()
            jobs._comfy_interrupt("p-pending")
            check(fake.posts() == [("/queue", {"delete": ["p-pending"]})], "a pending prompt: delete only, no interrupt of someone else's render: %s" % fake.posts())
            fake.requests.clear()
            jobs._comfy_interrupt(None)
            check(fake.posts() == [("/interrupt", {})], "no recorded id (an older tool): /interrupt alone: %s" % fake.posts())
            check(not any("clear" in json.dumps(b) for _, b in fake.posts()) and not any("clear" in json.dumps(b) for _, _, b in fake.requests), "never `clear`")
            fake.requests.clear()
            # the cancel path of a running comfy job sends the job's own id
            jc = jobs.enqueue("look", {"kind": "enemy", "id": "bug", "code": "BG-B"}, {"method": "creature_ctl"}, "to cancel")
            jcj = jobs._find(jc["id"])
            with jobs._lock:
                jobs._lane_current["comfy"] = None
            jobs._take_next("comfy")
            jcj["pid"] = 999999   # a pid nothing runs under: _kill_tree finds nothing
            jcj["comfy_prompt"] = "p-run"
            jobs.cancel(jc["id"])
            check(fake.posts()[:1] == [("/queue", {"delete": ["p-run"]})] and ("/interrupt", {}) in fake.posts() and jcj["state"] == "cancelled",
                  "jobs.cancel of a running comfy job sends its own prompt's delete + interrupt: %s" % fake.posts())
            fake.requests.clear()
            jcj2 = jobs._find(jobs.enqueue("look", {"kind": "enemy", "id": "bug", "code": "BG-B"}, {"method": "creature_ctl"}, "to cancel 2")["id"])
            with jobs._lock:
                jobs._lane_current["comfy"] = None
            jobs._take_next("comfy")
            jcj2["pid"] = 999999
            jobs.cancel(jcj2["id"])
            check(fake.posts() == [("/interrupt", {})], "a running job without a recorded prompt id: /interrupt only: %s" % fake.posts())
        finally:
            jobs.COMFY_SERVER = saved_cs
            fake.close()
        # ---- the routes over HTTP (the real jobs module on the temp world) and the CLI against them
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        httpd.daemon_threads = True
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % httpd.server_address[1]
        get, post = _http(base)
        loop.ops = []
        try:
            st, d = post("/api/requests", {"goal": "over http", "asset": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "budget": {"rerolls": 1, "cloud_dollars": 0.25}, "mode": "auto",
                                           "brief": {"art_prompt": "a bug"}})
            hr = d.get("rid")
            check(st == 200 and d["ok"] and R.RID_RE.match(hr or "") and d["fold"]["state"] == "running" and d["fold"]["budget"]["cloud_dollars"] == 0.25, "POST /api/requests -> rid + the fold: %s" % hr)
            st, d = post("/api/requests", {"goal": "", "asset": {"kind": "enemy", "id": "bug"}})
            check(st == 400 and not d["ok"], "POST /api/requests with a bad body is a 400: %s" % d.get("error"))
            st, d = get("/api/requests")
            check(st == 200 and d["ok"] and d["requests"][0]["rid"] == hr and all("summary" in f for f in d["requests"]), "GET /api/requests lists the folds newest first")
            st, d = get("/api/requests/" + hr)
            check(st == 200 and d["ok"] and d["rid"] == hr and d["iteration"] == {"n": 0, "of": 4} and d["jobs"][0]["state"] == "queued", "GET /api/requests/<rid> is the fold")
            st, d = get("/api/requests/r20260101-000000-zzzz")
            check(st == 404, "an unknown rid is a 404")
            st, d = get("/api/requests/nope")
            check(st == 404, "a malformed rid is a 404")
            st, d = post("/api/requests/%s/dance" % hr, {})
            check(st == 404, "an unknown verb is a 404")
            st, d = post("/api/requests/%s/pause" % hr, {})
            check(st == 200 and d["state"] == "paused", "POST pause")
            st, d = post("/api/requests/%s/resume" % hr, {})
            check(st == 200 and d["state"] == "running", "POST resume")
            st, d = post("/api/requests/%s/approve" % hr, {"confirm": True})
            check(st == 409 and not d["ok"] and "still queued" in d["error"], "approve while the job is queued is a 409: %s" % d.get("error"))
            hj = R.load(hr)["jobs"][0]
            W.run_by_hand(hj)
            st, d = get("/api/requests/" + hr)
            check(st == 200 and d["state"] == "waiting" and d["waiting_for"] == "approval" and "waiting for Garry's approval" in d["summary"], "after the landing the fold waits for approval")
            st, d = post("/api/requests/%s/approve" % hr, {})
            check(st == 409 and d["needs_confirm"] and d["batch"]["staged"] == 0, "approve without confirm over HTTP is a 409 with the batch")
            st, d = post("/api/requests/%s/reject" % hr, {"why": "too dark"})
            check(st == 200 and d["ok"] and any(e["event"] == "rejected" and e["why"] == "too dark" for e in d["history_tail"]), "POST reject records the reason")
            st, d = post("/api/requests/%s/pick" % hr, {"code": "BG-A"})
            check(st == 200 and d["provisional"]["code"] == "BG-A", "POST pick {code}")
            st, d = post("/api/requests/%s/pick" % hr, {"slot": 1})
            check(st == 409, "a bad pick is a 409")
            st, d = post("/api/requests/%s/step" % hr, {})
            check(st == 200 and d["state"] in ("paused", "waiting"), "POST step")
            st, d = get("/api/job/%s/summary" % hj)
            check(st == 200 and d["ok"] and d["state"] == "done" and d["request"] == hr and "paragraph" in d and "stages" in d and "log_tail" not in d, "GET /api/job/<id>/summary")
            st, d = get("/api/job/%s/summary" % j1["id"])
            check(st == 200 and d["hard"] == 0 and d["advisory"] == 1, "the summary reads a canned findings.json")
            st, d = get("/api/job/jnope/summary")
            check(st == 404, "the summary of an unknown job is a 404")
            st, d = get("/api/job/%s" % hj)
            check(st == 200 and d["ok"] and d["job"]["request"] == hr and "log_tail" in d["job"], "GET /api/job/<id> keeps its old answer (plus the request stamp)")
            st, d = get("/api/jobs?since=0")
            check(st == 200 and len(d["jobs"]) == len(jobs._state["jobs"]), "GET /api/jobs?since=0 returns everything over HTTP")
            # the CLI
            rc, out = cli("start", "--kind", "enemy", "--id", "bug", "--code", "BG-B", "--goal", "from the cli", "--rerolls", "1", "--minutes", "30", "--word", "anim_hint=neat", editor=base)
            crid = next((w for w in out.split() if R.RID_RE.match(w)), None)
            check(rc == 0 and crid and out.startswith("request %s started (enemy bug BG-B): from the cli" % crid) and "page:" in out, "art_request.py start -> exit 0, the rid, the page: %s" % out.strip().splitlines()[:2])
            cr = R.load(crid)
            check(cr["budget"]["rerolls"] == 1 and cr["budget"]["lane_seconds"] == 1800 and cr["brief"]["words"] == {"anim_hint": "neat"}, "the CLI's flags become the budget and the brief: %s" % cr["budget"])
            rc, out = cli("status", crid, editor=base)
            check(rc == 2 and out.startswith("%s running" % crid) and "iteration 0 of 4" in out and "budget:" in out, "status: one line, exit 2 while not final: %s" % out.strip())
            W.run_by_hand(cr["jobs"][0])
            rc, out = cli("result", crid, editor=base)
            check(rc == 2 and "waiting for Garry's approval" in out and out.startswith("Request %s" % crid), "result while waiting: the paragraph and 'waiting for Garry's approval', exit 2: %s" % out.strip().splitlines()[-2:])
            rc, out = cli("sheet", crid, editor=base)
            check(rc == 2 and "no review sheet yet" in out, "sheet without a sheet: exit 2")
            rc, out = cli("pause", crid, editor=base)
            check(rc == 0 and "paused" in out, "pause -> exit 0")
            rc, out = cli("resume", crid, editor=base)
            check(rc == 0 and ("waiting" in out or "running" in out), "resume -> exit 0: %s" % out.strip())
            rc, out = cli("list", editor=base)
            check(rc == 0 and crid in out and hr in out, "list names every request")
            rc, out = cli("job", cr["jobs"][0], editor=base)
            check(rc == 0 and "is done" in out and "part of request %s" % crid in out, "job <id> prints the summary paragraph: %s" % out.strip().splitlines()[:1])
            rc, out = cli("result", ro["rid"], editor=base)
            check(rc == 0 and "Done: BG-B installed" in out and "strip:" in out and "entry:" in out, "result on a done request: exit 0 with the paths: %s" % out.strip().splitlines()[-3:])
            rc, out = cli("result", rf["rid"], editor=base)
            check(rc == 1 and "failed" in out, "result on a failed request: exit 1")
            rc, out = cli("cancel", crid, editor=base)
            check(rc == 0 and "cancelled" in out, "cancel -> exit 0")
            rc, out = cli("status", "r20260101-000000-zzzz", editor=base)
            check(rc == 1 and "error" in out, "status of an unknown rid: exit 1")
            rc, out = cli("status", crid, "--json", editor=base)
            check(rc == 1 and json.loads(out)["state"] == "cancelled", "--json prints the fold; a cancelled request exits 1")
            rc, out = cli("status", crid, editor="http://127.0.0.1:1")
            check(rc == 3 and "no Level Editor answers" in out, "an editor that does not answer: exit 3, no fallback to another port")
            rc, out = cli("start", "--kind", "enemy", "--goal", "x", editor=base)
            check(rc == 1 and "needs --id" in out, "start without --id says so")
        finally:
            httpd.shutdown()
            httpd.server_close()
        R.set_loop(False)
        R.set_commands(False)
