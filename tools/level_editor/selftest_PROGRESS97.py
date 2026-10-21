"""Pass 97, lane PROGRESS: ComfyUI's live progress (WF-07), the events log and the archive (WF-02), Ops (OPS-02).

Groups (nothing under game/ or the real tools/dl is written; every world is a temporary folder):
  1. comfy.run's progress thread against a fake ComfyUI (HTTP + a stdlib WebSocket on one port) replaying the recorded
     fixture tools/level_editor/testdata/comfy_ws/ (the live `status` capture + the documented message shapes): the
     lines and their order after `comfy: prompt`, the 2 s throttle and the line at once on a new node, the error line at
     once, binary previews ignored, /history still the completion (a socket that refuses, one that drops: at most two
     reconnects, then quiet, the render returns all the same), the socket closed when run() returns, no thread outside a
     Level Editor job or with COMFY_PROGRESS=0, the library fallback; one real subprocess (the job's stdout as the
     Level Editor reads it).
  2. jobs.parse_line: the lines -> progress.substage {node, value, max, at, since, prompt, view} and progress.comfy_error;
     cleared when the stage moves, on a newer prompt, at a new attempt, at the end; the recorded logs in testdata/ parse
     to exactly what they parsed to without the hook; the card's tail without the step lines.
  3. events.py: one writer under threads (strictly increasing seq), the per-job copy, since/limit/filters, a restart
     continues, a second writer noticed, never raises, off unless configured.
  4. The choke points on REQ96's temporary world: a job's events folded = its record (state, attempt, phase), a request's
     history[] = its `request` events, a look op, a content write, an icon set, a frames stage, an evaluator verdict.
  5. The archive: old finished records out to archive/queue_<month>.json and read back byte-equal, the live queue kept,
     GET /api/job/<id> and the folders still there, since=0 the live queue only, /api/jobs/archived, the count in
     /api/status, requeue of an archived id, a failing archive write removes nothing, idempotent.
  6. Ops on a synthetic queue of 50 records: outcomes, measured medians rendered vs cached, lock waits, failures as
     sentences (an ANSI-only error re-derived from its log, the record untouched), QA offline, interrupted, stalled,
     dollars per request from a ledger, the ETA from the measured median at >= 5 samples (eta_source), under 200 ms.
  7. The error-line rule (ANSI-only, Traceback, SCRIPT ERROR, a Godot crash's exit code), the server.log rotation.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import base64
import hashlib
import io
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
for p in (HERE, TOOLS):
    if p not in sys.path:
        sys.path.insert(0, p)
FIXTURES = os.path.join(HERE, "testdata", "comfy_ws")
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
PNG_1PX = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")


def _fixture(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as f:
        return json.load(f)["messages"]


# ---------------------------------------------------------------- the fake ComfyUI (HTTP + WebSocket, stdlib only)

class FakeComfy:
    """POST /prompt, GET /history/<id>, GET /view, and /ws?clientId=<id> as ComfyUI answers them. `ws_mode`: replay (the
    fixture, PROMPT and SID filled in, after the prompt of that client id is posted), refuse (no upgrade: a 404), drop
    (the socket cut after `drop_after` messages, on every connection). /history answers once the replay ended (or at
    once when the socket is refused or dropped)."""

    def __init__(self, messages=None, ws_mode="replay", drop_after=3):
        self.messages, self.ws_mode, self.drop_after = messages or [], ws_mode, drop_after
        self.posted = {}            # client id -> prompt id
        self.prompt_event = {}      # client id -> Event
        self.done = set()           # prompt ids whose replay ended
        self.ws_connects = 0
        self.ws_open = 0
        self.ws_closed_at = []
        self.n = 0
        self.lock = threading.Lock()
        fake = self

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

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
                if path.startswith("/ws"):
                    return fake._ws(self)
                if path.startswith("/history/"):
                    pid = path.split("/")[2]
                    if pid in fake.done:
                        return self._send(200, {pid: {"status": {"status_str": "success"}, "outputs": {"9": {"images": [{"filename": "x.png", "subfolder": "", "type": "output"}]}}}})
                    return self._send(200, {})
                if path.startswith("/view"):
                    return self._send(200, PNG_1PX, "image/png")
                return self._send(404, {"error": "no %s" % path})

            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(n).decode("utf-8")) if n else {}
                if self.path == "/prompt":
                    with fake.lock:
                        fake.n += 1
                        pid = "fake-%04d-%s" % (fake.n, "ab12cd34")
                        cid = str(body.get("client_id") or "")
                        fake.posted[cid] = pid
                        ev = fake.prompt_event.setdefault(cid, threading.Event())
                    if fake.ws_mode == "refuse" or not fake.messages:
                        fake.done.add(pid)
                    ev.set()
                    return self._send(200, {"prompt_id": pid, "number": fake.n, "node_errors": {}})
                return self._send(404, {"error": "no %s" % self.path})

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.httpd.daemon_threads = True
        self.url = "http://127.0.0.1:%d" % self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    # -- the WebSocket side
    @staticmethod
    def _frame(op, payload):
        n = len(payload)
        head = bytes([0x80 | op])
        if n < 126:
            head += bytes([n])
        elif n < 65536:
            head += bytes([126]) + n.to_bytes(2, "big")
        else:
            head += bytes([127]) + n.to_bytes(8, "big")
        return head + payload

    @staticmethod
    def _read_frame(rfile):
        """One client frame (masked): (opcode, payload) or None at EOF."""
        b = rfile.read(2)
        if len(b) < 2:
            return None
        op, ln = b[0] & 0x0F, b[1] & 0x7F
        if ln == 126:
            ln = int.from_bytes(rfile.read(2), "big")
        elif ln == 127:
            ln = int.from_bytes(rfile.read(8), "big")
        mask = rfile.read(4) if b[1] & 0x80 else b"\0\0\0\0"
        data = bytearray(rfile.read(ln))
        for i in range(len(data)):
            data[i] ^= mask[i % 4]
        return op, bytes(data)

    def _ws(self, h):
        if self.ws_mode == "refuse":
            return h._send(404, {"error": "no websocket here"})
        key = h.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        h.send_response(101, "Switching Protocols")
        h.send_header("Upgrade", "websocket")
        h.send_header("Connection", "Upgrade")
        h.send_header("Sec-WebSocket-Accept", accept)
        h.end_headers()
        h.wfile.flush()
        h.close_connection = True
        cid = h.path.split("clientId=", 1)[-1].split("&")[0]
        with self.lock:
            self.ws_connects += 1
            self.ws_open += 1
        try:
            if self.ws_mode == "drop":
                for k, m in enumerate(self.messages[: self.drop_after]):
                    h.wfile.write(self._frame(1, json.dumps(m["msg"]).encode("utf-8")))
                h.wfile.flush()
                time.sleep(0.1)
                h.connection.shutdown(socket.SHUT_RDWR)
                return
            ev = self.prompt_event.setdefault(cid, threading.Event())
            sent_first = False
            for m in self.messages:
                if not sent_first:
                    sent_first = True   # the `status` on connect goes before the prompt exists
                else:
                    ev.wait(10)
                time.sleep(float(m.get("delay") or 0))
                pid = self.posted.get(cid, "?")
                if "binary" in m:
                    h.wfile.write(self._frame(2, bytes.fromhex(m["binary"])))
                else:
                    txt = json.dumps(m["msg"]).replace("PROMPT", pid).replace("SID", cid)
                    h.wfile.write(self._frame(1, txt.encode("utf-8")))
                h.wfile.flush()
            self.done.add(self.posted.get(cid, "?"))
            # hold the socket until the client closes it (a close frame or EOF), at most 20 s
            h.connection.settimeout(20)
            while True:
                fr = self._read_frame(h.rfile)
                if fr is None:
                    break
                if fr[0] == 8:
                    try:
                        h.wfile.write(self._frame(8, fr[1][:2]))
                        h.wfile.flush()
                    except OSError:
                        pass
                    break
        except OSError:
            pass
        finally:
            with self.lock:
                self.ws_open -= 1
                self.ws_closed_at.append(time.time())

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def _graph(comfy):
    """Nodes 1..9 as a Klein graph numbers them: 3 = positive, 7 = KSampler, 8 = VAE Decode, 9 = SaveImage."""
    g = comfy.Graph()
    g.add("UNETLoader", unet_name="x")
    g.add("CLIPLoader", clip_name="y")
    g.add("CLIPTextEncode", _title="positive", text="a bug", clip=("2", 0))
    g.add("EmptyLatentImage", width=64, height=64, batch_size=1)
    g.add("VAELoader", vae_name="v")
    g.add("ConditioningZeroOut", conditioning=("3", 0))
    g.add("KSampler", _title="KSampler", model=("1", 0), positive=("3", 0), negative=("6", 0), latent_image=("4", 0), seed=1, steps=4, cfg=1.0)
    g.add("VAEDecode", _title="VAE Decode", samples=("7", 0), vae=("5", 0))
    g.add("SaveImage", images=("8", 0), filename_prefix="88fits/test")
    return g


class _InProcess:
    """comfy.run in this process against a fake: the server, the lock pass-through, the watch's lines collected with
    their times; everything put back."""

    def __init__(self, comfy, fake, env=None, seconds=None):
        self.comfy, self.fake, self.env, self.seconds = comfy, fake, dict(env or {}), seconds
        self.lines, self.watches = [], []

    def __enter__(self):
        c = self.comfy
        self.saved = (c.SERVER, c._LOCK, c.progress_watch, {k: os.environ.get(k) for k in ("LOCK_HELD_COMFY", "ASSET_JOB_ID", "ASSET_JOB_SIDECAR", "COMFY_PROGRESS")})
        c.SERVER = self.fake.url
        os.environ["LOCK_HELD_COMFY"] = "1"
        for k in ("ASSET_JOB_ID", "ASSET_JOB_SIDECAR", "COMFY_PROGRESS"):
            os.environ.pop(k, None)
        os.environ.update(self.env)
        orig_cls = c.ProgressWatch
        me = self

        def watch(client_id, graph=None):
            if not c.progress_enabled():
                return None
            w = orig_cls(client_id, graph, out=lambda line: me.lines.append((time.time(), line)), seconds=me.seconds)
            me.watches.append(w)
            return w.start() if w.backend is not None else None
        c.progress_watch = watch
        return self

    def __exit__(self, *exc):
        c = self.comfy
        c.SERVER, c._LOCK, c.progress_watch, env = self.saved
        for k, v in env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        return False


# ---------------------------------------------------------------- 1. the progress thread

def _group_ws(check):
    import comfy
    import jobs
    check(comfy._ws_backend() is not None and comfy._ws_backend()[0] in ("websocket-client", "websockets"), "a WebSocket client imports on this PC: %s" % (comfy._ws_backend() or ("none",))[0])
    # the library fallback: websocket-client missing -> websockets' sync client; both missing -> no thread
    saved_mods = {k: sys.modules.get(k) for k in ("websocket", "websockets", "websockets.sync", "websockets.sync.client")}
    try:
        sys.modules["websocket"] = None
        b = comfy._ws_backend()
        check(b is not None and b[0] == "websockets", "without websocket-client the websockets sync client is used: %s" % (b or ("none",))[0])
        sys.modules["websockets.sync.client"] = None
        sys.modules["websockets.sync"] = None
        sys.modules["websockets"] = None
        check(comfy._ws_backend() is None, "with neither library there is no thread (/history alone, as before)")
    finally:
        for k, v in saved_mods.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v

    # the gate: off outside a Level Editor job, on under one, COMFY_PROGRESS overrides
    saved_env = {k: os.environ.get(k) for k in ("ASSET_JOB_ID", "ASSET_JOB_SIDECAR", "COMFY_PROGRESS")}
    try:
        for k in saved_env:
            os.environ.pop(k, None)
        off = comfy.progress_enabled()
        os.environ["ASSET_JOB_ID"] = "jtest"
        on = comfy.progress_enabled()
        os.environ["COMFY_PROGRESS"] = "0"
        forced_off = comfy.progress_enabled()
        os.environ.pop("ASSET_JOB_ID")
        os.environ["COMFY_PROGRESS"] = "1"
        forced_on = comfy.progress_enabled()
        check(not off and on and not forced_off and forced_on, "the gate: off for a hand run, on under a job (ASSET_JOB_ID), COMFY_PROGRESS=0/1 override: %s" % [off, on, forced_off, forced_on])
    finally:
        for k, v in saved_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    # the Klein replay in process: lines, order, the substage they make
    fake = FakeComfy(_fixture("render_klein.json"))
    try:
        with _InProcess(comfy, fake, env={"ASSET_JOB_ID": "jtest"}) as ip:
            t0 = time.time()
            out, secs = comfy.run(_graph(comfy), timeout=30)
            t_ret = time.time()
            check(len(out) == 1 and out[0] == PNG_1PX, "run() returns the picture from /history + /view as before")
            lines = [l for _, l in ip.lines]
            pid = fake.posted.get(ip.watches[0].client_id) if ip.watches else None
            check(len(ip.watches) == 1 and pid and ip.watches[0].connects == 1, "one watch, one connection, the POST's client id: %s" % (ip.watches[0].client_id if ip.watches else None))
            check(all(jobs.RE_COMFY_STEP.match(l) for l in lines) and all(l.startswith("comfy: %s " % pid) for l in lines),
                  "every line is `comfy: <prompt> <node> <v>/<max>` with this run's prompt id: %s" % lines)
            nodes = [jobs.RE_COMFY_STEP.match(l).group(2) for l in lines]
            check(nodes[:2] == ["positive", "KSampler"] and "VAE Decode" in nodes and "SaveImage" in nodes,
                  "a line at once on every new node, the node's title (Graph.add's _title, else the class): %s" % nodes)
            check(lines[1].endswith("KSampler 0/0") and lines[0].endswith("positive 0/0"),
                  "a node starting prints 0/0 at once (its steps follow, at most every 2 s): %s" % lines)
            check(not any("binary" in l or "status" in l for l in lines), "status messages and binary previews print nothing")
            time.sleep(0.8)
            check(fake.ws_open == 0 and ip.watches[0].thread.is_alive() is False, "the socket is closed and the thread ended after run() returned (open %d)" % fake.ws_open)
            check(t_ret - t0 < 6.0, "run() is not slowed by the watch: %.2f s for a %.2f s replay" % (t_ret - t0, sum(m["delay"] for m in _fixture("render_klein.json"))))
            # the lines through the parser: the substage a card draws
            job = {"id": "jt", "kind": "look", "progress": {"stage": "", "stages": [{"name": "side", "key": "bug_bgb_side", "type": "still", "state": "pending"}]}}
            for l in lines:
                jobs.parse_line(job, l)
            sub = job["progress"].get("substage") or {}
            check(sub.get("node") == nodes[-1] and sub.get("prompt") == pid and set(sub) >= {"node", "value", "max", "at", "since", "prompt"} and sub.get("view") == "side",
                  "the last line is the job's substage with its view: %s" % sub)
    finally:
        fake.close()

    # the throttle: 30 steps 0.15 s apart on one node -> at most one line per 2 s, the first at once
    fake = FakeComfy(_fixture("render_slow.json"))
    try:
        with _InProcess(comfy, fake, env={"ASSET_JOB_ID": "jtest"}) as ip:
            comfy.run(_graph(comfy), timeout=30)
            ks = [(t, l) for t, l in ip.lines if " KSampler " in l]
            gaps = [round(b[0] - a[0], 2) for a, b in zip(ks, ks[1:])]
            check(len(ks) >= 2 and all(g >= 1.9 for g in gaps) and len(ks) <= 4, "one line per 2 s at most on one node: %d lines, gaps %s" % (len(ks), gaps))
            vals = [int(jobs.RE_COMFY_STEP.match(l).group(3)) for _, l in ks]
            check(vals[0] == 0 and vals == sorted(vals) and vals[-1] >= 20, "the values climb (the newest state each time): %s" % vals)
            vae = [l for _, l in ip.lines if " VAE Decode " in l]
            check(len(vae) == 1 and ks and ip.lines.index(next(x for x in ip.lines if " VAE Decode " in x[1])) == len(ks), "the next node prints at once, without waiting for the throttle")
    finally:
        fake.close()

    # an execution_error: the error line at once; /history still says how the render ended
    fake = FakeComfy(_fixture("render_error.json"))
    try:
        with _InProcess(comfy, fake, env={"ASSET_JOB_ID": "jtest"}) as ip:
            comfy.run(_graph(comfy), timeout=30)
            errs = [l for _, l in ip.lines if jobs.RE_COMFY_ERROR.match(l)]
            check(len(errs) == 1 and "KSampler #7: torch.OutOfMemoryError: Allocation on device 0" in errs[0] and "\n" not in errs[0] and len(errs[0]) < 400,
                  "execution_error prints one line at once (node, exception, message on one line): %s" % errs)
            job = {"id": "je", "kind": "look", "progress": {"stage": "", "stages": []}}
            for _, l in ip.lines:
                jobs.parse_line(job, l)
            check(job["progress"].get("comfy_error", "").startswith("KSampler #7: torch.OutOfMemoryError") and job["progress"].get("comfy_error_prompt") == fake.posted[ip.watches[0].client_id],
                  "the error line sets progress.comfy_error: %s" % job["progress"].get("comfy_error"))
    finally:
        fake.close()

    # a socket that refuses: no line, no retry storm, the render ends through /history
    fake = FakeComfy(_fixture("render_klein.json"), ws_mode="refuse")
    try:
        with _InProcess(comfy, fake, env={"ASSET_JOB_ID": "jtest"}) as ip:
            t0 = time.time()
            out, _ = comfy.run(_graph(comfy), timeout=30)
            time.sleep(3.5)
            w = ip.watches[0]
            check(len(out) == 1 and not ip.lines and w.connects == 0 and w.failures <= 3 and (w.gave_up or not w.thread.is_alive()),
                  "a refused socket: the render returns through /history, no line, at most 1 + 2 tries (%d failures, %.1f s)" % (w.failures, time.time() - t0))
    finally:
        fake.close()

    # a socket that drops mid-render: at most two reconnects, then quiet; /history still ends the render
    fake = FakeComfy(_fixture("render_klein.json"), ws_mode="drop", drop_after=3)
    try:
        with _InProcess(comfy, fake, env={"ASSET_JOB_ID": "jtest"}) as ip:
            fake_done = threading.Timer(4.5, lambda: fake.done.update(fake.posted.values()))
            fake_done.start()
            out, _ = comfy.run(_graph(comfy), timeout=30)
            time.sleep(0.5)
            w = ip.watches[0]
            check(len(out) == 1 and fake.ws_connects == 3 and w.connects == 3 and w.gave_up and not w.thread.is_alive(),
                  "a dropped socket is tried again twice (3 connections in all), then the thread goes quiet; the render still returns: %d connections" % fake.ws_connects)
    finally:
        fake.close()

    # outside a Level Editor job: no socket at all (a hand run prints exactly what it printed before)
    fake = FakeComfy(_fixture("render_klein.json"), ws_mode="refuse")
    try:
        with _InProcess(comfy, fake, env={}) as ip:
            fake.done.clear()
            out, _ = comfy.run(_graph(comfy), timeout=30)
            check(len(out) == 1 and not ip.watches and fake.ws_connects == 0, "a hand run opens no socket and prints no progress line")
    finally:
        fake.close()

    # the real thing: a subprocess as a job runs it, its stdout as the Level Editor reads it
    fake = FakeComfy(_fixture("render_klein.json"))
    tmp = tempfile.mkdtemp(prefix="le_p97_ws_")
    try:
        script = os.path.join(tmp, "run_one.py")
        with open(script, "w", encoding="utf-8", newline="\n") as f:
            f.write("import sys\nsys.path.insert(0, %r)\nsys.path.insert(0, %r)\nsys.argv.append('--server=' + sys.argv[1])\n"
                    "import comfy, selftest_PROGRESS97 as T\nout, secs = comfy.run(T._graph(comfy), timeout=30)\nprint('RESULT %%d' %% len(out), flush=True)\n" % (TOOLS, HERE))
        env = dict(os.environ, ASSET_JOB_ID="jsub", LOCK_HELD_COMFY="1", PYTHONIOENCODING="utf-8", PYTHONUNBUFFERED="1")
        env.pop("COMFY_PROGRESS", None)
        env.pop("ASSET_JOB_SIDECAR", None)
        p = subprocess.run([sys.executable, "-u", script, fake.url], capture_output=True, text=True, encoding="utf-8", timeout=60, env=env, cwd=tmp)
        lines = [l for l in p.stdout.splitlines() if l.strip()]
        prompt_at = next((i for i, l in enumerate(lines) if l.startswith("comfy: prompt ")), None)
        steps = [i for i, l in enumerate(lines) if jobs.RE_COMFY_STEP.match(l)]
        check(p.returncode == 0 and lines and lines[-1] == "RESULT 1" and prompt_at is not None and steps and min(steps) > prompt_at,
              "a job's stdout: `comfy: prompt <id>` first, then the progress lines, then the tool's own output: rc %s, %s" % (p.returncode, lines[:8]))
        job = {"id": "js", "kind": "look", "progress": {"stage": "", "stages": []}}
        markers = jobs.parse_log(job, p.stdout)
        check(job.get("comfy_prompt") and (job["progress"].get("substage") or {}).get("prompt") == job["comfy_prompt"] and markers == [],
              "parse_log on that stdout: comfy_prompt and the substage agree, no stop marker: %s" % job["progress"].get("substage"))
    finally:
        fake.close()
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- 2. parse_line

def _group_parse(check):
    import jobs
    job = {"id": "jp", "kind": "look", "method": "creature_ctl", "progress": {"stage": "", "stages": [
        {"name": "side", "key": "bug_bgb_side", "type": "still", "state": "pending"},
        {"name": "front", "key": "bug_bgb_front", "type": "still", "state": "pending"}]}}
    idx = jobs._stage_index(job)
    jobs.parse_line(job, "comfy: prompt p-1", idx)
    check(job.get("comfy_prompt") == "p-1" and "substage" not in job["progress"], "`comfy: prompt` keeps its pass 96 meaning and makes no substage")
    jobs.parse_line(job, "comfy: p-1 KSampler 3/4", idx)
    s1 = dict(job["progress"]["substage"])
    check(s1["node"] == "KSampler" and s1["value"] == 3 and s1["max"] == 4 and s1["prompt"] == "p-1" and s1["view"] == "side", "a step line -> the substage: %s" % s1)
    time.sleep(1.1)
    jobs.parse_line(job, "comfy: p-1 KSampler 4/4", idx)
    s2 = job["progress"]["substage"]
    check(s2["since"] == s1["since"] and s2["at"] != s1["at"] and s2["value"] == 4, "the same node keeps `since` (the time on this node) and moves `at`")
    jobs.parse_line(job, "comfy: p-1 Wan Video Sampler (VACE) 1/20", idx)
    check(job["progress"]["substage"]["node"] == "Wan Video Sampler (VACE)", "a node title with spaces and brackets")
    jobs.parse_line(job, "  render bug_bgb_side seed 5 12.3s ok", idx)
    check("substage" not in job["progress"] and job["progress"]["stages"][0]["state"] == "done", "a finished render (the stage moved) clears the substage")
    jobs.parse_line(job, "comfy: p-2 error KSampler #7: torch.OutOfMemoryError: out of memory", idx)
    check(job["progress"]["comfy_error"] == "KSampler #7: torch.OutOfMemoryError: out of memory" and job["progress"]["comfy_error_prompt"] == "p-2", "an error line -> comfy_error")
    jobs.parse_line(job, "comfy: prompt p-2", idx)
    check(job["progress"].get("comfy_error"), "the same prompt's line keeps the error")
    jobs.parse_line(job, "comfy: prompt p-3", idx)
    check("comfy_error" not in job["progress"] and job["comfy_prompt"] == "p-3", "a newer prompt (a retry) clears the error")
    for line in ("comfy: the workflow was not saved into the page's sidebar (HTTP Error 404: x)", "comfy: prompt 1/2", "random 3/4", "comfy: x"):
        before = json.dumps(job["progress"], sort_keys=True)
        jobs.parse_line(job, line, idx)
        check(json.dumps(job["progress"], sort_keys=True) == before or line == "comfy: prompt 1/2", "an unrelated line leaves the progress alone: %r" % line)
    # a new attempt and the end clear what is stale
    job["progress"]["substage"] = {"node": "x", "value": 1, "max": 2}
    job["progress"]["comfy_error"] = "e"
    job["attempt"] = 2
    jobs._on_attempt_start(job)
    check("substage" not in job["progress"] and "comfy_error" not in job["progress"] and job["lock_wait_s"] == {} and job["lock_wait_attempt"] == 2,
          "a run starts: no stale substage or error; the lock wait starts again for attempt 2")
    job["progress"]["substage"] = {"node": "x"}
    job["progress"]["comfy_error"] = "kept"
    jobs._on_finish(job, "failed")
    check("substage" not in job["progress"] and job["progress"]["comfy_error"] == "kept", "the end clears the substage and keeps the error for the card")
    jobs._add_lock_wait(job, "comfy", 12.34)
    jobs._add_lock_wait(job, "comfy", 2.0)
    check(job["lock_wait_s"] == {"comfy": 14.3} and job["lock_wait_total_s"]["comfy"] == 14.3, "lock waits add up per attempt: %s" % job["lock_wait_s"])
    job["attempt"] = 3
    jobs._add_lock_wait(job, "comfy", 1.0)
    check(job["lock_wait_s"] == {"comfy": 1.0} and job["lock_wait_total_s"]["comfy"] == 15.3, "a new attempt starts its own sum; the total keeps every attempt")

    # the recorded logs parse exactly as they did without the hook (nothing in them is a ComfyUI progress line)
    td = os.path.join(HERE, "testdata")
    logs = [f for f in sorted(os.listdir(td)) if f.endswith(".log")]
    saved = jobs._comfy_progress
    same = 0
    for name in logs:
        with open(os.path.join(td, name), encoding="utf-8", errors="replace") as f:
            text = f.read()
        recs = []
        for hook in (saved, lambda *a, **k: None):
            jobs._comfy_progress = hook
            j = {"id": "jl", "kind": "look", "method": "creature_ctl" if "ctl" in name else "creature_free2",
                 "progress": {"stage": "", "stages": [{"name": "side", "key": "x_side", "type": "still", "state": "pending"}]}}
            jobs.parse_log(j, text)
            recs.append(json.dumps(j, sort_keys=True))
        jobs._comfy_progress = saved
        same += recs[0] == recs[1]
    check(logs and same == len(logs), "the %d recorded logs in testdata/ parse to the same record with and without the hook" % len(logs))

    # the card's tail: ComfyUI's step lines go to log.txt only
    class L:
        pass
    live = L()
    live.logf, live.tail, live.key_to_stage, live.marker, live.last_save = io.StringIO(), [], None, None, 0.0
    j = {"id": "jt2", "kind": "look", "progress": {"stage": "", "stages": []}, "outputs": []}
    for line in ("comfy: prompt p-9", "comfy: p-9 KSampler 1/4", "comfy: p-9 KSampler 2/4", "  render k seed 1 2.0s ok", "comfy: p-9 error X #1: E: m"):
        jobs._on_line(j, live, line)
    check(live.tail == ["comfy: prompt p-9", "  render k seed 1 2.0s ok", "comfy: p-9 error X #1: E: m"] and live.logf.getvalue().count("KSampler") == 2,
          "the card's tail keeps the prompt, the tool's lines and the error; the step lines are in log.txt: %s" % live.tail)


# ---------------------------------------------------------------- 3. events.py

def _group_events(check):
    import events as E
    saved = (E._dir, E._seq, E._sig)
    tmp = tempfile.mkdtemp(prefix="le_p97_ev_")
    try:
        E.configure(None)
        check(E.emit("job", "x") is None and not os.listdir(tmp), "off unless configured: nothing written")
        E.configure(tmp)
        os.makedirs(os.path.join(tmp, "j1"))
        e1 = E.emit("job", "queued", job="j1", look={"kind": "enemy", "id": "bug", "code": "BG-B"}, state="queued", odd={1, 2})
        e2 = E.emit("look", "approve", look=E.look_of("enemy", "bug", "BG-B"))
        check(e1["seq"] == 1 and e2["seq"] == 2 and e1["look"] == {"kind": "enemy", "id": "bug", "code": "BG-B"} and isinstance(e1["odd"], list),
              "seq starts at 1 and climbs; the look field; any value made JSON-safe")
        with open(os.path.join(tmp, "j1", "events.jsonl"), encoding="utf-8") as f:
            own = [json.loads(x) for x in f if x.strip()]
        check(len(own) == 1 and own[0]["seq"] == 1, "the job's own copy holds its events only")
        check(E.emit("job", "x", job="nofolder") is not None and not os.path.exists(os.path.join(tmp, "nofolder")), "an unknown job gets no folder made for it")
        # one writer under threads
        def burst(k):
            for i in range(50):
                E.emit("frames", "stage", job="j1" if i % 10 == 0 else None, n=k * 100 + i)
        ths = [threading.Thread(target=burst, args=(k,)) for k in range(16)]
        for t in ths:
            t.start()
        for t in ths:
            t.join()
        with open(os.path.join(tmp, "events.jsonl"), encoding="utf-8") as f:
            seqs = [json.loads(x)["seq"] for x in f if x.strip()]
        check(seqs == list(range(1, 804)), "16 threads x 50 events: every line whole, seq 1..803 strictly increasing in file order (%d lines)" % len(seqs))
        # since / limit / filters
        r = E.since(0, 10)
        check(r["seq"] == 10 and r["more"] and [e["seq"] for e in r["events"]] == list(range(1, 11)) and r["last"] == 803, "since 0, limit 10: the first ten, the cursor 10, more")
        r = E.since(800, 50)
        check([e["seq"] for e in r["events"]] == [801, 802, 803] and r["seq"] == 803 and not r["more"], "since 800: the last three, read from the end")
        r = E.since(803, 50)
        check(r["events"] == [] and r["seq"] == 803, "nothing new: the same cursor")
        r = E.since(9999, 5)
        check(r.get("reset") and r["events"][0]["seq"] == 1, "a cursor beyond the end (a reset log) starts again from the beginning")
        r = E.since(0, 1000, job="j1")
        check(all(e.get("job") == "j1" for e in r["events"]) and len(r["events"]) == 1 + 16 * 5, "the job filter: %d" % len(r["events"]))
        r = E.since(0, 1000, look={"kind": "enemy", "id": "bug", "code": None})
        check([e["event"] for e in r["events"]] == ["queued", "approve"], "the look filter (every code of the asset)")
        check(len(E.for_job("j1")) == 81 and E.for_look("enemy", "bug", "BG-B")[-1]["event"] == "approve", "for_job reads the job's copy; for_look the log")
        # a restart continues; a second writer is noticed
        E.configure(tmp)
        check(E.emit("server", "start")["seq"] == 804, "a restart reads the last seq and continues")
        with open(os.path.join(tmp, "events.jsonl"), "a", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps({"seq": 900, "t": "x", "kind": "look", "event": "approve"}) + "\n")
        check(E.emit("server", "x")["seq"] == 901, "another editor's append is noticed: seq continues after it")
        # never raises
        bad = os.path.join(tmp, "a_file")
        open(bad, "w").close()
        E.configure(bad)
        check(E.emit("job", "x") is None and E.errors(), "a log that cannot be written: emit returns None, never raises")
        E.configure(tmp)
        check(E.request_event({"rid": "r1", "asset": {"kind": "enemy", "id": "bug", "code": "BG-B"}}, {"t": "2026-10-22T01:00:00", "event": "job", "job": "j1", "why": "w"})["t"] == "2026-10-22T01:00:00",
              "a request's history entry mirrored with its own t")
        # the big log rolls into the archive, seq goes on
        dest = E.roll_if_big(max_bytes=10)
        check(dest and os.path.isfile(dest) and not os.path.exists(os.path.join(tmp, "events.jsonl")) and E.emit("server", "after")["seq"] == 903,
              "the daily tick moves a big log into archive/events_<stamp>.jsonl and seq continues")
    finally:
        E._dir, E._seq, E._sig = saved
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- 4 + 5. the choke points and the archive

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


def _fold(events):
    """A job's record rebuilt from its events: the last event's state, attempt, phase."""
    st = {}
    for e in events:
        for k in ("state", "attempt", "phase"):
            if e.get(k) is not None:
                st[k] = e[k]
    return st


def _group_world(check, server):
    from selftest_REQ96 import TempWorld
    import events as E
    saved_ev = (E._dir, E._seq, E._sig)
    with TempWorld() as W:
        jobs, R, FS, FRIO = W.jobs, W.R, W.FS, W.FRIO
        E.configure(jobs.JOBS_DIR)
        try:
            # ---- a request and its look job, run by hand: queued, started, finished, landed; then requeued, picked
            rec = R.create("a cleaner side walk", {"kind": "enemy", "id": "bug", "code": "BG-B"}, mode="auto", budget={"rerolls": 1})
            rid, jid = rec["rid"], rec["jobs"][0]
            W.run_by_hand(jid, rc=1)
            jrec = jobs._find(jid)
            check(jrec["state"] == "failed" and jrec["error"] == "RuntimeError: the fake tool failed", "a failed run's error is the exception's line (as before): %s" % jrec["error"])
            jobs.requeue(jid)
            W.run_by_hand(jid, rc=0)
            own = E.for_job(jid)
            evs = [e for e in own if e["kind"] == "job"]
            check(any(e["kind"] == "request" for e in own), "the job's own copy also holds the request's entries about it")
            names = [e["event"] for e in evs]
            check(names[:4] == ["queued", "started", "finished", "requeued"] and "landed" in names and names[-1] in ("finished",),
                  "a job's events in order: %s" % names)
            f = _fold(evs)
            j = jobs._find(jid)
            check(f == {"state": j["state"], "attempt": j["attempt"], "phase": j["phase"]}, "fold(its events) == the record: %s vs %s" % (f, {k: j[k] for k in ("state", "attempt", "phase")}))
            check(all(e.get("rid") == rid and e.get("look") == {"kind": "enemy", "id": "bug", "code": "BG-B"} for e in evs), "every job event carries its request and its look")
            check(any(e["event"] == "finished" and e.get("error") == "RuntimeError: the fake tool failed" and e.get("state") == "failed" for e in evs), "the failed run's event says why")
            # the request's history[] is a view: its entries are the `request` events (same t, same event)
            rec2 = R.load(rid)
            revs = E.for_request(rid)
            rq = [(e["t"], e["event"]) for e in revs if e["kind"] == "request"]
            check(rq == [(h.get("t"), h.get("event")) for h in rec2.get("history") or []] and len(rq) >= 2,
                  "the request's history[] == its request events: %d entries" % len(rq))
            # ---- a look op, a content write, an icon, a frames stage, an evaluator verdict
            n0 = E._seq
            res = server.look_op("enemy", "bug", ["BG-B"], "note", {"note": "pass 97 test"})
            check(res.get("ok") and E.for_look("enemy", "bug", "BG-B")[-1]["event"] == "note" and E.for_look("enemy", "bug", "BG-B")[-1].get("note") == "pass 97 test",
                  "look_op: one `look` event per code: %s" % res.get("error"))
            doc = W.doc()
            doc2 = dict(doc, name="Bug (pass 97)")
            wr = server.write_content("enemy", "bug", doc2)
            ce = [e for e in E.since(n0, 100)["events"] if e["kind"] == "content"]
            check(wr.get("ok") and ce and ce[-1]["event"] == "write" and ce[-1].get("changed") == ["name"] and ce[-1].get("id") == "bug", "write_content: a `content` event with the keys it changed")
            vid = W.second_version(1)
            r = FRIO.stage("enemy", "bug", "BG-B", "run", "side", {"slot": 1, "version": vid})
            fe = [e for e in E.since(n0, 100)["events"] if e["kind"] == "frames"]
            check(r.get("ok") and fe and fe[-1]["event"] == "stage" and fe[-1].get("group") == "run/side" and fe[-1].get("slot") == 1 and fe[-1].get("version") == vid,
                  "a frames stage: its event names the group, the slot and the version")
            FRIO.unstage("enemy", "bug", "BG-B", "run", "side", {"slot": 1})
            check(E.since(n0, 100)["events"][-1]["event"] == "unstage", "unstage too")
            folder = os.path.join(W.content, "enemies", "bug")
            icons = [n for n in os.listdir(folder) if n.startswith("bug_icon") and n.endswith(".png")]
            if icons:
                ir = server.set_look_icon("enemy", "bug", "BG-B", icons[0], why="pass 97 test")
                ie = [e for e in E.since(n0, 100)["events"] if e["kind"] == "icon"]
                check(ir.get("ok") and (ir.get("unchanged") or (ie and ie[-1]["event"] == "set" and ie[-1].get("file") == icons[0])), "set_look_icon: an `icon` event: %s" % ir.get("error"))
            ev_job = {"id": "jev", "kind": "evaluate", "spec": {"kind": "enemy", "id": "bug", "code": "BG-B", "request": rid}, "request": rid, "progress": {}}
            jobs._evaluate_post(ev_job, {"info": {"findings": "tools/dl/jobs/jev/findings.json", "gates": {"pass": True}, "summary": "0 hard", "dollars": 0.0}})
            ve = [e for e in E.since(n0, 100)["events"] if e["kind"] == "evaluator"]
            check(ve and ve[-1]["event"] == "verdict" and ve[-1].get("gates") == {"pass": True} and ve[-1].get("rid") == rid, "an evaluator verdict is an event")
            # the HTTP route
            httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
            httpd.daemon_threads = True
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            get, post = _http("http://127.0.0.1:%d" % httpd.server_address[1])
            try:
                st, body = get("/api/events?since=0&limit=5")
                check(st == 200 and body["ok"] and len(body["events"]) == 5 and body["seq"] == 5 and body["more"], "GET /api/events?since=0&limit=5")
                st, body = get("/api/events?since=0&limit=500&look=enemy/bug/BG-B")
                check(st == 200 and body["events"] and all((e.get("look") or {}).get("code") == "BG-B" for e in body["events"]), "the look filter over HTTP")
                st, body = get("/api/events?since=0&job=%s" % jid)
                check(st == 200 and all(e.get("job") == jid for e in body["events"]) and body["events"], "the job filter over HTTP")
                check(get("/api/events?since=x")[0] == 400 and get("/api/events?look=weapon/x")[0] == 400, "bad cursors and looks are a 400")

                # ---- the archive: old finished records leave the queue, read back byte-equal, still reachable
                now = time.time()
                old_t = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now - 45 * 86400))
                older_t = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now - 80 * 86400))
                new_t = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now - 2 * 86400))

                def rec_(i, state, ended, **kw):
                    r = {"id": "jarc-%02d" % i, "kind": "import", "method": "import", "lane": "godot", "state": state, "title": "t%d" % i, "target": {"kind": "enemy", "id": "bug", "code": ""},
                         "spec": {"targets": ["enemies/bug"]}, "phase": 1, "attempt": 1, "created": ended, "started": ended, "ended": ended, "pid": None, "cmd": [], "equiv": "",
                         "progress": {"done": 1, "total": 1, "stage": "done", "stages": [], "last_output": None, "stalled": False}, "eta_s": 0, "outputs": [], "choices": [],
                         "error": "", "written": None, "lock_waits": {}, "front": False, "note": "é ✓"}
                    r.update(kw)
                    os.makedirs(os.path.join(jobs.JOBS_DIR, r["id"]), exist_ok=True)
                    with open(os.path.join(jobs.JOBS_DIR, r["id"], "log.txt"), "w", encoding="utf-8") as fh:
                        fh.write("--- %s attempt 1 phase 1: x\nline for %s\n" % (ended, r["id"]))
                    return r
                arc = [rec_(1, "done", old_t), rec_(2, "failed", old_t, error="\x1b[0m"), rec_(3, "cancelled", older_t), rec_(4, "done", older_t),
                       rec_(5, "done", new_t), rec_(6, "interrupted", old_t), rec_(7, "done", old_t), rec_(8, "running", None, started=old_t),
                       rec_(10, "done", old_t, kind="icon_cands", method="icon_cands", lane="comfy", target={"kind": "enemy", "id": "bug", "code": "BG-B"},
                            spec={"seeds": 2}, choices=[{"id": "0", "label": "c0", "url": "/dl/x.png"}, {"id": "1", "label": "c1", "url": "/dl/y.png"}],
                            plan={"icon_job": {"id": "bug", "type": "enemies"}, "key": "bug", "type": "enemies"})]
                live_import = {"id": "jarc-09", "kind": "import", "lane": "godot", "state": "queued", "spec": {"targets": ["enemies/bug"], "after_export": ["jarc-07"]},
                               "target": {}, "progress": {"stages": []}, "phase": 1, "attempt": 1, "created": new_t}
                with jobs._lock:
                    jobs._state["jobs"].extend(arc + [live_import])
                    jobs._save()
                before = {r["id"]: json.dumps(r, sort_keys=True, ensure_ascii=False) for r in arc}
                n_before = len(jobs._state["jobs"])
                qbytes_before = os.path.getsize(jobs.QUEUE_FILE)
                res = jobs.archive_finished(now=now)
                ids_now = [j["id"] for j in jobs._state["jobs"]]
                moved = sorted(set(before) - set(ids_now))
                check(res["ok"] and res["archived"] == 5 and moved == ["jarc-01", "jarc-02", "jarc-03", "jarc-04", "jarc-10"],
                      "done / failed / cancelled older than 30 days leave; recent, interrupted, running and one an import still points at stay: %s" % moved)
                check(len(ids_now) == n_before - 5 and os.path.getsize(jobs.QUEUE_FILE) < qbytes_before, "the queue file shrinks: %d -> %d bytes" % (qbytes_before, os.path.getsize(jobs.QUEUE_FILE)))
                months = sorted(m["month"] for m in res["months"])
                check(months == sorted({old_t[:7], older_t[:7]}) and all(os.path.isfile(os.path.join(jobs.JOBS_DIR, "archive", "queue_%s.json" % m)) for m in months),
                      "one archive file per month the jobs ended: %s" % months)
                back = {r["id"]: json.dumps(r, sort_keys=True, ensure_ascii=False) for _, r in jobs.archived_records()}
                check(all(back.get(i) == before[i] for i in moved), "every archived record reads back exactly as it was (never rewritten)")
                check(all(os.path.isfile(os.path.join(jobs.JOBS_DIR, i, "log.txt")) for i in moved), "their folders are untouched")
                st, body = get("/api/job/jarc-02")
                check(st == 200 and body["job"]["archived"].startswith("queue_") and body["job"]["error"] == "\x1b[0m" and body["job"]["log_tail"][-1] == "line for jarc-02",
                      "GET /api/job/<id> finds an archived job (its log tail from its folder, its record as it was)")
                st, body = get("/api/jobs?since=0")
                check(st == 200 and not any(j["id"] in moved for j in body["jobs"]) and any(j["id"] == "jarc-05" for j in body["jobs"]), "since=0 lists the live queue only")
                st, body = get("/api/jobs/archived")
                check(st == 200 and body["total"] == 5 and {m["month"] for m in body["months"]} == set(months), "GET /api/jobs/archived: %s" % body.get("months"))
                st, body = get("/api/jobs/archived?month=%s" % older_t[:7])
                check(st == 200 and sorted(j["id"] for j in body["jobs"]) == ["jarc-03", "jarc-04"] and all(j["archived"] and j["log_tail"] == [] for j in body["jobs"]), "one month's records")
                check(get("/api/jobs/archived?month=2026-1")[0] == 400, "a bad month is a 400")
                st, body = get("/api/status")
                check(st == 200 and (body.get("jobs") or {}).get("archived") == 5, "/api/status: jobs.archived = 5")
                inst = jobs.install("jarc-10", "c1")
                check(inst["kind"] == "install" and not (inst.get("plan") or {}).get("error") and (inst.get("plan") or {}).get("tool") == "gen_icon_cands"
                      and (inst.get("plan") or {}).get("choice") == "1", "a candidate of an archived icon job can still be installed: %s" % (inst.get("plan") or {}).get("error"))
                again = jobs.archive_finished(now=now)
                check(again["ok"] and again["archived"] == 0, "a second run moves nothing")
                rq2 = jobs.requeue("jarc-01")
                check(rq2["state"] == "queued" and rq2["attempt"] == 2 and jobs._find("jarc-01") is not None, "requeue of an archived id brings it back into the queue (attempt 2)")
                check(jobs.get("jarc-01").get("archived") is None, "get() prefers the live record")
                # a failing archive write removes nothing
                with jobs._lock:
                    for r in arc:
                        if r["id"] in ("jarc-07",):
                            r["ended"] = old_t
                    live_import["state"] = "done"
                    live_import["ended"] = new_t
                ad = jobs.archive_dir()
                shutil.move(ad, ad + "_aside")
                with open(ad, "w") as fh:
                    fh.write("not a folder")
                n_keep = len(jobs._state["jobs"])
                bad = jobs.archive_finished(now=now)
                check(not bad["ok"] and bad["archived"] == 0 and len(jobs._state["jobs"]) == n_keep, "a failing archive write keeps every record in the queue: %s" % bad.get("error"))
                os.remove(ad)
                shutil.move(ad + "_aside", ad)
                ok2 = jobs.archive_finished(now=now)
                check(ok2["ok"] and ok2["archived"] == 1 and jobs._find("jarc-07") is None, "once the import is done, its export leaves too")
                # read-only editors never archive
                saved_ro = jobs._readonly
                jobs._readonly = {"who": "x"}
                check(jobs.archive_finished(now=now)["skipped"] == "read-only", "a read-only editor never archives")
                jobs._readonly = saved_ro
                check(any(e["event"] == "archive" and e["kind"] == "server" for e in E.since(0, 5000)["events"]), "the archive is an event")
            finally:
                httpd.shutdown()
                httpd.server_close()
        finally:
            E._dir, E._seq, E._sig = saved_ev


# ---------------------------------------------------------------- 6. Ops

def _synthetic_queue(jobs_dir, now):
    """50 records: 20 creature_ctl done (12 rendered 100..210 s, 8 cached 10..17 s), 6 hero_pose5 done (300..550 s), 8
    import done (2 waited 30 s for the Godot lock), 5 failed (2 the same Traceback, 1 ANSI-only with a log, 2 a Godot
    crash), 3 interrupted, 2 running (one stalled), 3 queued, 3 cancelled; two on the comfy lane with QA offline."""
    def t(sec_ago):
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now - sec_ago))
    recs = []

    def add(i, kind, method, state, dur=None, ago=3600, lane="comfy", **kw):
        r = {"id": "jops-%02d" % i, "kind": kind, "method": method, "lane": lane, "state": state, "phase": 2 if method == "creature_ctl" else 1, "attempt": 1,
             "spec": {"use_side": "k0"} if method == "creature_ctl" else {}, "created": t(ago + (dur or 0) + 10), "started": t(ago + (dur or 0)) if dur is not None else None,
             "ended": t(ago) if state not in ("running", "queued") and dur is not None else None, "progress": {"stages": [], "stalled": False}, "error": ""}
        r.update(kw)
        recs.append(r)
        return r
    i = 0
    for k in range(12):
        i += 1
        add(i, "look", "creature_ctl", "done", 100 + 10 * k, progress={"stages": [{"type": "still", "secs": 30.0, "state": "done"}], "stalled": False})
    for k in range(8):
        i += 1
        add(i, "look", "creature_ctl", "done", 10 + k, progress={"stages": [{"type": "still", "note": "cached", "state": "done"}], "stalled": False})
    for k in range(6):
        i += 1
        add(i, "look", "hero_pose5", "done", 300 + 50 * k, progress={"stages": [{"type": "clip", "secs": 99.0, "state": "done"}], "stalled": False})
    for k in range(8):
        i += 1
        add(i, "import", "import", "done", 60 + k, lane="godot", lock_wait_s={"godot": 30.0} if k < 2 else {}, lock_wait_total_s={"godot": 30.0} if k < 2 else {})
    i += 1
    add(i, "look", "creature_ctl", "failed", 50, error="RuntimeError: ComfyUI error: out of memory 12")
    i += 1
    add(i, "look", "creature_ctl", "failed", 50, error="RuntimeError: ComfyUI error: out of memory 34")
    i += 1
    ansi = add(i, "import", "import", "failed", 20, lane="godot", error="\x1b[0m")
    os.makedirs(os.path.join(jobs_dir, ansi["id"]), exist_ok=True)
    with open(os.path.join(jobs_dir, ansi["id"], "log.txt"), "w", encoding="utf-8") as f:
        f.write("--- x attempt 1 phase 1: import\n\x1b[92m[ DONE ]\x1b[39m \x1b[1mloading_editor_layout\x1b[22m\n\x1b[0m\n")
    for k in range(2):
        i += 1
        add(i, "import", "import", "failed", 20, lane="godot", error="exit code 0xC0000005: an access violation (a crash) after: [ DONE ] loading_editor_layout")
    for k in range(3):
        i += 1
        add(i, "look", "creature_ctl", "interrupted", 40, error="the editor server stopped while this ran")
    i += 1
    add(i, "look", "creature_ctl", "running", 30, progress={"stages": [], "stalled": True})
    i += 1
    add(i, "look", "creature_ctl", "running", 30)
    for k in range(3):
        i += 1
        add(i, "look", "creature_ctl", "queued", None)
    for k in range(3):
        i += 1
        add(i, "look", "creature_ctl", "cancelled", 5, qa_online=False if k < 2 else None)
    return recs


def _group_ops(check, server):
    from selftest_REQ96 import TempWorld
    import ops_io as O
    import jobs as J0
    with TempWorld() as W:
        jobs = W.jobs
        now = time.time()
        recs = _synthetic_queue(jobs.JOBS_DIR, now)
        check(len(recs) == 50, "the synthetic queue has 50 records")
        ledger = os.path.join(W.tmp, "ledger.json")
        with open(ledger, "w", encoding="utf-8") as f:
            stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now - 3600))
            json.dump({"v": 1, "calls": [
                {"backend": "anthropic", "model": "claude-x", "dollars": 0.012, "request": "r1", "t": stamp},
                {"backend": "anthropic", "model": "claude-x", "dollars": 0.008, "request": "r1", "t": stamp},
                {"backend": "openai_chat", "model": "qwen", "dollars": 0.0, "request": "r2", "t": stamp},
                {"backend": "anthropic", "model": "claude-x", "dollars": 9.0, "request": "r1", "t": stamp, "refused": True},
                {"backend": "anthropic", "model": "claude-x", "dollars": 5.0, "request": "r3", "t": "2020-01-01T00:00:00"}]}, f)
        before = json.dumps(recs, sort_keys=True)
        o = O.compute(7, records=recs, archived=[], ledger_path=ledger, now=now)
        check(json.dumps(recs, sort_keys=True) == before, "the roll-up never changes a record")
        oc = o["outcomes"]
        check(oc["done"]["look"]["creature_ctl"] == 20 and oc["done"]["look"]["hero_pose5"] == 6 and oc["done"]["import"]["import"] == 8 and oc["failed"]["look"]["creature_ctl"] == 2
              and oc["failed"]["import"]["import"] == 3 and oc["interrupted"]["look"]["creature_ctl"] == 3 and oc["running"]["look"]["creature_ctl"] == 2
              and oc["queued"]["look"]["creature_ctl"] == 3 and oc["cancelled"]["look"]["creature_ctl"] == 3, "outcomes by state x kind x method: %s" % oc)
        m = o["medians"]
        cr, cc = m["creature_ctl"]["rendered"], m["creature_ctl"]["cached"]
        check(cr == {"median": 155.0, "p90": 200.0, "n": 12} and cc == {"median": 13.5, "p90": 17.0, "n": 8}, "creature_ctl: rendered %s, cached %s" % (cr, cc))
        check(m["hero_pose5"]["rendered"] == {"median": 425.0, "p90": 550.0, "n": 6} and m["hero_pose5"]["builtin"] == 570 and m["hero_pose5"]["eta_uses"] == "measured",
              "hero_pose5 beside its built-in 570 s: %s" % m["hero_pose5"])
        check(o["lock_wait"] == {"godot": 60.0} and o["interrupted"] == 3 and o["stalled"] == 1 and o["qa_offline"] == 2, "lock waits, interrupted, stalled, QA offline: %s" % {k: o[k] for k in ("lock_wait", "interrupted", "stalled", "qa_offline")})
        f = o["failures"]
        reasons = [(x["reason"], x["n"]) for x in f]
        check(reasons[0][1] == 2 and len(f) == 3 and any(x["reason"].startswith("RuntimeError: ComfyUI error: out of memory") and x["n"] == 2 for x in f)
              and any("0xC0000005" in x["reason"] and x["n"] == 2 for x in f), "failures grouped by sentence (numbers aside): %s" % reasons)
        an = [x for x in f if x["last_job"] == "jops-37"]
        check(an and an[0]["reason"] == "the step failed after: [ DONE ] loading_editor_layout" and an[0]["sample"] == "\x1b[0m" and o["failures_rederived"] == 1,
              "an ANSI-only error is re-derived from its log for this view (the record keeps its own): %s" % (an[0]["reason"] if an else None))
        c = o["cost"]
        check(c["total_dollars"] == 0.02 and c["calls"] == 3 and c["requests"][0] == {"rid": "r1", "dollars": 0.02, "calls": 2} and c["by_model"]["claude-x"]["calls"] == 2,
              "dollars per request from the ledger (refused and out-of-window calls left out): %s" % c)
        check(o["eta_source"] == "measured" and o["jobs_seen"] == 50 and o["generated_ms"] < 200, "eta_source measured; %d ms on 50 records" % o["generated_ms"])
        # the ETA reads the measured median at >= 5 samples
        with jobs._lock:
            jobs._state["jobs"][:] = recs
        jobs._measured["t"] = 0.0
        jq = {"kind": "look", "method": "hero_pose5", "spec": {}, "progress": {"stages": []}, "phase": 1}
        e1 = jobs._eta(jq)
        check(e1 == 425 and jq["eta_source"] == "measured" and jq["eta_samples"] == 6, "the ETA uses the measured median (425 s from 6 runs, not 570): %s %s" % (e1, jq.get("eta_source")))
        with jobs._lock:
            jobs._state["jobs"][:] = [r for r in recs if r["method"] != "hero_pose5"][:] + [r for r in recs if r["method"] == "hero_pose5"][:4]
        jobs._measured["t"] = 0.0
        jq2 = {"kind": "look", "method": "hero_pose5", "spec": {}, "progress": {"stages": []}, "phase": 1}
        e2 = jobs._eta(jq2)
        check(jq2["eta_source"] in ("builtin", "methods") and e2 != 425, "under 5 samples the card keeps the table's number (%s: %s s)" % (jq2["eta_source"], e2))
        jqi = {"kind": "icon_cands", "method": "icon_cands", "spec": {"seeds": 4}, "progress": {"stages": []}}
        with jobs._lock:
            jobs._state["jobs"][:] = [dict(r, kind="icon_cands", method="icon_cands", spec={"seeds": 4}, lane="comfy", id="jic-%d" % k, progress={"stages": []},
                                           started=time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now - 1000)), ended=time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now - 920)))
                                      for k, r in enumerate(recs[:5])]
        jobs._measured["t"] = 0.0
        check(jobs._eta(jqi) == 80 and jqi["eta_source"] == "measured", "a candidate set is measured per seed (4 seeds x 20 s = 80 s)")
        # the HTTP route on today's shape, its time
        with jobs._lock:
            jobs._state["jobs"][:] = recs
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        httpd.daemon_threads = True
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        get, _ = _http("http://127.0.0.1:%d" % httpd.server_address[1])
        try:
            t0 = time.time()
            st, body = get("/api/ops?days=7")
            ms = (time.time() - t0) * 1000
            keys = {"days", "outcomes", "medians", "lock_wait", "failures", "qa_offline", "interrupted", "stalled", "cost", "eta_source"}
            check(st == 200 and keys <= set(body) and body["jobs_seen"] == 50, "GET /api/ops?days=7 carries INTERFACES' keys (%d ms over HTTP)" % ms)
            check(get("/api/ops?days=x")[0] == 400, "a bad days is a 400")
        finally:
            httpd.shutdown()
            httpd.server_close()


# ---------------------------------------------------------------- 7. the error line, server.log

def _group_error_and_log(check):
    import jobs
    import ops_io as O
    el = jobs.error_line
    check(el(["\x1b[92m[ DONE ]\x1b[39m \x1b[1mloading_editor_layout\x1b[22m", "\x1b[0m"], 3221225477)
          == "exit code 0xC0000005: an access violation (a crash) after: [ DONE ] loading_editor_layout", "a Godot crash at its teardown reads as a sentence, never an ANSI code")
    check(el(["\x1b[0m", "  ", "\x1b[0m"], 1) == "exit code 1" and el([], 2) == "exit code 2", "nothing telling: the exit code")
    check(el(["Traceback (most recent call last):", '  File "x.py", line 3, in <module>', "RuntimeError: ComfyUI timeout after 1200s", "asset_job: FAILED"], 1)
          == "RuntimeError: ComfyUI timeout after 1200s", "a Traceback: the exception's own line")
    check(el(["\x1b[1;31mSCRIPT ERROR: Parse Error: x\x1b[0m", "   at: GDScript::reload (res://a.gd:3)"], 1) == "SCRIPT ERROR: Parse Error: x", "Godot's SCRIPT ERROR without its colour codes")
    check(el(["import_json: FAILED for enemies/bug", "done"], 1) == "import_json: FAILED for enemies/bug", "a FAILED line")
    check(el(["gen_ctl: no drivers for x", "\x1b[0m"], 1) == "gen_ctl: no drivers for x", "a tool's message (as before)")
    check(el(["comfy: p-1 error KSampler #7: torch.OutOfMemoryError: oom", "asset_job: FAILED"], 1) == "asset_job: FAILED", "the newest telling line wins (as before)")
    check(el(["some output", "more output"], 1) == "exit code 1 after: more output", "a quiet failure: how it ended and the last line")
    check(jobs.error_is_noise("\x1b[0m") and not jobs.error_is_noise("x") and not jobs.error_is_noise(""), "error_is_noise")
    # server.log: the tee and the rotation
    tmp = tempfile.mkdtemp(prefix="le_p97_log_")
    try:
        p = os.path.join(tmp, "server.log")
        sink = O.RotatingSink(p, max_bytes=2000, backups=3)
        console = io.StringIO()
        tee = O._Tee(console, sink)
        for k in range(400):
            tee.write("GET /api/jobs?since=%d line %d\n" % (k, k))
        tee.write("partial ")
        tee.write("line\n")
        tee.flush()
        sink.close()
        names = sorted(os.listdir(tmp))
        check(names == ["server.log", "server.log.1", "server.log.2", "server.log.3"], "rotated at its size, three old files kept, none beyond: %s" % names)
        check(all(os.path.getsize(os.path.join(tmp, n)) <= 2000 + 200 for n in names), "no file grows past the limit (by more than a line)")
        text = ""
        for n in ("server.log.3", "server.log.2", "server.log.1", "server.log"):
            with open(os.path.join(tmp, n), encoding="utf-8") as f:
                text += f.read()
        rows = text.splitlines()
        check(console.getvalue().count("\n") == 401 and rows[-1].endswith("partial line") and rows[-1][:4].isdigit() and rows[-1].count("partial") == 1
              and all(r[:4].isdigit() and r.count(" line ") <= 1 for r in rows[:-1]), "the console gets every line as before; the files stamp each line once: %r" % rows[-1])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def checks(check, run_node, server):
    for name, fn in (("ws", lambda: _group_ws(check)), ("parse", lambda: _group_parse(check)), ("events", lambda: _group_events(check)),
                     ("world", lambda: _group_world(check, server)), ("ops", lambda: _group_ops(check, server)),
                     ("error/log", lambda: _group_error_and_log(check))):
        try:
            fn()
        except Exception as e:   # noqa: BLE001  (one broken group is one failure, the others still run)
            import traceback
            traceback.print_exc()
            check(False, "selftest_PROGRESS97 %s: %s: %s" % (name, type(e).__name__, e))
