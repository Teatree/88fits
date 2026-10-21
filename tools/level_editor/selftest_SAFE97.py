"""Pass 97, lane SAFE: the toolchain's health (OPS-03) and the request guard (WF-08).

Groups: tools/ai_hosts.py (the file, no file, a broken file, an empty value, AI_HOSTS_FILE) and the five readers in a
child process (comfy.SERVER / SERVER_SSH, jobs.COMFY_SERVER / LMSTUDIO_MODELS, server.QA_URL, gen_art.LMSTUDIO,
vision_eval.LMSTUDIO: today's literals with the file as shipped and with no file, the file's values when it changes, and
COMFY_SERVER over the file); the request guard on a stand-in handler (Host, Origin, Content-Type, the upload's own body,
the GET that writes) and over HTTP with every in-repo caller's own request code replayed (art_request.api, puppet.api,
the page's fetch shape with its Origin, the upload, the selftests' post, selftest_S's raw requests) and the hostile shapes
refused; the loopback bind asserted in main() and free_port(); "Re-queue all" (jobs.interrupted_ids /
requeue_interrupted on a temporary queue: only what the restart interrupted, a launch skipped, the same requeue as the
card's button; the route and /api/status.interrupted); /api/status.doctor (off unless main() turned it on; cached;
never waited for); doctor.py on a fake probe (all present -> exit 0; an empty home and checkout -> every missing piece
named; services down = warnings; the lock verdicts; quick = no ssh login; no real network); net_check's parsers and
verdicts on canned netstat/tasklist text; the console-close handler called directly (close -> the jobs lock released on a
temp lock dir; Ctrl+C / Ctrl+Break left to Python; once only) and its install undone; requirements.txt against an import
scan of tools/; tools/keys/README.md tracked while the keys stay ignored; the evaluator reads keys only from tools/keys.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import ast
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
for p in (HERE, TOOLS):
    if p not in sys.path:
        sys.path.insert(0, p)

TODAY = {"comfy": "http://192.168.137.54:8188", "ssh": "teatree@192.168.137.54", "ssh_key": "~/.ssh/id_ed25519_ai_server",
         "lmstudio": "http://127.0.0.1:1234", "ollama": "http://192.168.137.54:11434"}
READERS_CHILD = r"""
import json, os, sys
ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "tools")); sys.path.insert(0, os.path.join(ROOT, "tools", "level_editor"))
out = {}
import comfy
out["comfy.SERVER"], out["comfy.SERVER_SSH"] = comfy.SERVER, comfy.SERVER_SSH
import jobs
out["jobs.COMFY_SERVER"], out["jobs.LMSTUDIO_MODELS"] = jobs.COMFY_SERVER, jobs.LMSTUDIO_MODELS
import server
out["server.QA_URL"] = server.QA_URL
import gen_art
out["gen_art.LMSTUDIO"] = gen_art.LMSTUDIO
import vision_eval
out["vision_eval.LMSTUDIO"] = vision_eval.LMSTUDIO
out["vision_eval.backend_url"] = vision_eval.OpenAIChatBackend().url
out["vision_eval.json_url"] = vision_eval.openai_chat_json.__defaults__[1]
print("READERS " + json.dumps(out))
"""


class _Headers(dict):
    def get(self, k, d=None):
        for key, v in self.items():
            if key.lower() == k.lower():
                return v
        return d


class _FakeHandler:
    """What _request_guard reads: headers, path, server.server_address; records what _guard_refuse sends."""

    def __init__(self, path, headers, port=8787):
        self.path, self.headers = path, _Headers(headers)
        self.server = type("S", (), {"server_address": ("127.0.0.1", port)})()
        self.sent = None
        self.close_connection = False

    def _error(self, code, msg, **extra):
        self.sent = (code, msg, extra)


class _FakeJobs:
    """A stand-in for jobs.py on the routes the callers use (enqueue, install, cancel, requeue, requeue_interrupted)."""

    def __init__(self):
        self.calls = []

    def enqueue(self, kind, target, spec, title=None):
        self.calls.append(("enqueue", kind, target, spec, title))
        return {"id": "jF%d" % len(self.calls), "kind": kind, "state": "queued"}

    def get(self, job_id):
        raise KeyError(job_id)

    def install(self, job_id, choice, options=None):
        self.calls.append(("install", job_id, choice, options))
        return {"id": job_id, "state": "queued"}

    def cancel(self, job_id):
        self.calls.append(("cancel", job_id))
        return {"id": job_id, "state": "cancelled"}

    def requeue(self, job_id, reroll=None):
        self.calls.append(("requeue", job_id, reroll))
        return {"id": job_id, "state": "queued"}

    def requeue_interrupted(self, ids=None, scope="restart"):
        self.calls.append(("requeue_interrupted", ids, scope))
        return {"requeued": ["jA"], "skipped": [], "refused": []}

    def interrupted_ids(self, scope="restart"):
        return ["jA", "jB"]

    def status(self):
        return {"queued": 0, "running": 0, "waiting": 0, "lanes": {}, "qa_online": None}


class _StubIO:
    """server.REQIO / server.FRIO for the replay: answers 200 with what reached it, writes nothing."""

    def __init__(self, name):
        self.name, self.seen = name, []

    def api_post(self, h, srv, parts, data=None):
        self.seen.append(("POST", parts, data))
        return h._send(200, {"ok": True, "stub": self.name, "parts": parts, "data": data})

    def api_get(self, h, srv, parts, query=None):
        self.seen.append(("GET", parts))
        return h._send(200, {"ok": True, "stub": self.name, "parts": parts})


def _run_readers(env_extra):
    env = dict(os.environ)
    env.pop("COMFY_SERVER", None)
    env.pop("AI_HOSTS_FILE", None)
    env.update(env_extra)
    p = subprocess.run([sys.executable, "-c", READERS_CHILD, ROOT], capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env=env, timeout=180, cwd=ROOT)
    line = next((l for l in (p.stdout or "").splitlines() if l.startswith("READERS ")), None)
    return (json.loads(line[8:]) if line else None), (p.stderr or "")[-600:]


def _expected(h, comfy_env=None):
    comfy = comfy_env or h["comfy"]
    lm = h["lmstudio"].rstrip("/")
    return {"comfy.SERVER": comfy, "jobs.COMFY_SERVER": comfy,
            "comfy.SERVER_SSH": ["ssh", "-i", os.path.expanduser(h["ssh_key"]), "-o", "ConnectTimeout=10", h["ssh"]],
            "jobs.LMSTUDIO_MODELS": lm + "/v1/models", "server.QA_URL": lm + "/v1/models",
            "gen_art.LMSTUDIO": lm + "/v1/chat/completions", "vision_eval.LMSTUDIO": lm + "/v1/chat/completions",
            "vision_eval.backend_url": lm + "/v1/chat/completions", "vision_eval.json_url": lm + "/v1/chat/completions"}


def _check_hosts(check, tmp):
    import ai_hosts
    saved_env = os.environ.get("AI_HOSTS_FILE")
    try:
        f = os.path.join(tmp, "hosts.json")
        with open(f, "w", encoding="utf-8") as fh:
            json.dump({"comfy": "http://10.0.0.9:8188", "lmstudio": "http://127.0.0.1:4321/", "ssh": "  "}, fh)
        os.environ["AI_HOSTS_FILE"] = f
        check(ai_hosts.path() == f and ai_hosts.get("comfy", "x") == "http://10.0.0.9:8188", "ai_hosts: AI_HOSTS_FILE names the file, its value is read")
        check(ai_hosts.get("ssh", "teatree@x") == "teatree@x" and ai_hosts.get("ollama", "o") == "o", "ai_hosts: an empty or missing key = the reader's own default")
        check(ai_hosts.get("ollama") == TODAY["ollama"], "ai_hosts: no default given = the built-in value")
        check(ai_hosts.lmstudio("/v1/models") == "http://127.0.0.1:4321/v1/models", "ai_hosts: lmstudio() strips a trailing slash before the path")
        check(ai_hosts.source("comfy") == "file" and ai_hosts.source("ssh") == "default", "ai_hosts: source() says file or default")
        os.environ["AI_HOSTS_FILE"] = os.path.join(tmp, "absent.json")
        check(all(ai_hosts.get(k, v) == v for k, v in TODAY.items()), "ai_hosts: no file = every reader's old literal")
        bad = os.path.join(tmp, "bad.json")
        with open(bad, "w", encoding="utf-8") as fh:
            fh.write("{not json")
        os.environ["AI_HOSTS_FILE"] = bad
        err = io.StringIO()
        keep = sys.stderr
        sys.stderr = err
        try:
            got = ai_hosts.get("comfy", "http://old")
        finally:
            sys.stderr = keep
        check(got == "http://old" and "could not be read" in err.getvalue(), "ai_hosts: a broken file = the old values, said once on stderr")
        os.environ.pop("AI_HOSTS_FILE", None)
        shipped = ai_hosts.load(ai_hosts.FILE)
        check(shipped == TODAY, "tools/ai_hosts.json ships today's five values: %s" % shipped)
    finally:
        if saved_env is None:
            os.environ.pop("AI_HOSTS_FILE", None)
        else:
            os.environ["AI_HOSTS_FILE"] = saved_env

    # the five readers, each in a fresh process (their constants are read at import)
    other = {"comfy": "http://10.1.2.3:8188", "ssh": "someone@10.1.2.3", "ssh_key": "~/.ssh/other_key",
             "lmstudio": "http://127.0.0.1:5555", "ollama": "http://10.1.2.3:11434"}
    of = os.path.join(tmp, "other.json")
    with open(of, "w", encoding="utf-8") as fh:
        json.dump(other, fh)
    for label, env, exp in (("the shipped file", {}, _expected(TODAY)),
                            ("no file", {"AI_HOSTS_FILE": os.path.join(tmp, "absent.json")}, _expected(TODAY)),
                            ("another file", {"AI_HOSTS_FILE": of}, _expected(other)),
                            ("COMFY_SERVER over the file", {"AI_HOSTS_FILE": of, "COMFY_SERVER": "http://env:1"}, _expected(other, "http://env:1"))):
        got, err = _run_readers(env)
        if got is None:
            check(False, "readers (%s): the child failed: %s" % (label, err))
            continue
        bad = {k: (got.get(k), v) for k, v in exp.items() if got.get(k) != v}
        check(not bad, "readers (%s): every constant as expected%s" % (label, "" if not bad else ": %s" % bad))


def _check_guard(check, server):
    G = server._request_guard
    ok_json = {"Host": "127.0.0.1:8787", "Content-Type": "application/json", "Content-Length": "2"}
    cases = [
        ("no Origin, loopback Host, JSON", "/api/jobs", ok_json, None),
        ("localhost Host", "/api/jobs", dict(ok_json, Host="localhost:8787"), None),
        ("a Host without the port", "/api/jobs", dict(ok_json, Host="127.0.0.1"), None),
        ("no Host at all", "/api/jobs", {"Content-Type": "application/json", "Content-Length": "2"}, None),
        ("the page's own Origin", "/api/jobs", dict(ok_json, Origin="http://127.0.0.1:8787"), None),
        ("the page's Origin as localhost", "/api/jobs", dict(ok_json, Host="localhost:8787", Origin="http://localhost:8787"), None),
        ("JSON with a charset", "/api/jobs", dict(ok_json, **{"Content-Type": "application/json; charset=utf-8"}), None),
        ("JSON in capitals", "/api/jobs", dict(ok_json, **{"Content-Type": "Application/JSON"}), None),
        ("no body, any type", "/api/jobs/j1/cancel", {"Host": "127.0.0.1:8787", "Content-Length": "0", "Content-Type": "text/plain"}, None),
        ("the upload's raw body", "/api/upload", {"Host": "127.0.0.1:8787", "Content-Type": "application/octet-stream", "Content-Length": "10", "Origin": "http://127.0.0.1:8787"}, None),
        ("a rebinding Host", "/api/jobs", dict(ok_json, Host="evil.example:8787"), 403),
        ("the LAN address as Host", "/api/jobs", dict(ok_json, Host="192.168.0.43:8787"), 403),
        ("another port in Host", "/api/jobs", dict(ok_json, Host="127.0.0.1:9999"), 403),
        ("another site's Origin", "/api/jobs", dict(ok_json, Origin="http://evil.example"), 403),
        ("Origin null (a file page)", "/api/jobs", dict(ok_json, Origin="null"), 403),
        ("the editor's address on another port", "/api/jobs", dict(ok_json, Origin="http://127.0.0.1:8788"), 403),
        ("https of the same address", "/api/jobs", dict(ok_json, Origin="https://127.0.0.1:8787"), 403),
        ("a form's text/plain body", "/api/jobs", dict(ok_json, **{"Content-Type": "text/plain"}), 415),
        ("a urlencoded body", "/api/jobs", dict(ok_json, **{"Content-Type": "application/x-www-form-urlencoded"}), 415),
        ("a multipart body on a JSON route", "/api/content/enemy/x/save", dict(ok_json, **{"Content-Type": "multipart/form-data; boundary=x"}), 415),
        ("a body without a type", "/api/map/red_canyon", {"Host": "127.0.0.1:8787", "Content-Length": "5"}, 415),
        ("an upload from another site", "/api/upload", {"Host": "127.0.0.1:8787", "Content-Type": "application/octet-stream", "Content-Length": "10", "Origin": "http://evil.example"}, 403),
    ]
    for label, path, headers, want in cases:
        r = G(_FakeHandler(path, headers))
        check((r is None) if want is None else (r is not None and r[0] == want), "guard: %s -> %s (got %s)" % (label, want or "passes", r and r[0]))
    h = _FakeHandler("/api/frames/enemy/x/A", {"Host": "127.0.0.1:8787", "Content-Type": "text/plain", "Content-Length": "4"})
    check(G(h, body_check=False) is None, "guard on a GET: the content type is not looked at")
    check(server._state_changing_get(["api", "frames", "enemy", "x", "XA"]) and not server._state_changing_get(["api", "frames", "enemy", "x", "XA", "run", "side"])
          and not server._state_changing_get(["api", "jobs"]), "the one GET that writes: /api/frames/<kind>/<id>/<code> (registers a new look)")
    h = _FakeHandler("/api/jobs", dict(ok_json, Origin="http://evil.example"))
    server._guard_refuse(h, G(h))
    check(h.sent and h.sent[0] == 403 and h.sent[2].get("guard") and h.close_connection, "a refusal answers {error, guard} and closes the connection (the body is never read)")
    check(server._split_host("[::1]:8787") == ("::1", "8787") and server._split_host("LOCALHOST") == ("localhost", ""), "_split_host: IPv6 brackets and no port")


def _check_http(check, server, tmp):
    """Every in-repo caller's own request code against a temp server with stand-ins behind the routes."""
    import art_request
    import puppet
    saved = {k: getattr(server, k) for k in ("JOBS", "REQIO", "FRIO", "add_look", "UPLOADS")}
    fake = _FakeJobs()
    req_stub, fr_stub = _StubIO("requests"), _StubIO("frames")
    looks_seen = []
    server.JOBS, server.REQIO, server.FRIO = fake, req_stub, fr_stub
    server.add_look = lambda kind, cid, code=None, note="", recipe=None: looks_seen.append((kind, cid, code)) or {"ok": True, "code": code}
    server.UPLOADS = os.path.join(tmp, "uploads")
    httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    httpd.daemon_threads = True
    port = httpd.server_address[1]
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % port

    def raw(method, path, body=b"", headers=None):
        req = urllib.request.Request(base + path, data=body if method == "POST" else None, method=method, headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, json.loads(r.read().decode("utf-8") or "{}")
        except urllib.error.HTTPError as e:
            txt = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(txt)
            except ValueError:
                return e.code, {"raw": txt}

    def sock(lines):
        import socket
        s = socket.create_connection(("127.0.0.1", port), timeout=10)
        try:
            s.sendall(("\r\n".join(lines) + "\r\n\r\n").encode("ascii"))
            data = b""
            while b"\r\n\r\n" not in data:
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
            return data.decode("utf-8", "replace").split("\r\n")[0]
        finally:
            s.close()
    try:
        # art_request.py (Claude's one command): create, a verb with an empty body
        st, d = art_request.api(base, "POST", "/api/requests", {"goal": "x", "asset": {"kind": "enemy", "id": "bug"}})
        check(st == 200 and d.get("stub") == "requests" and d["data"]["goal"] == "x", "caller art_request.api POST /api/requests passes: %s %s" % (st, d))
        st, d = art_request.api(base, "POST", "/api/requests/r20261022-000000-abcd/pause", {})
        check(st == 200 and d.get("parts") == ["r20261022-000000-abcd", "pause"], "caller art_request.api POST a verb passes")
        st, d = art_request.api(base, "POST", "/api/jobs/jX/cancel")
        check(st == 200 and ("cancel", "jX") in fake.calls, "caller art_request.api POST with no body passes")
        # puppet.py: a look entry, a job, an install
        d = puppet.api(base, "POST", "/api/content/hero/may/look", {"code": "MAY-Z", "note": "n", "recipe": {}})
        check(d.get("ok") and looks_seen[-1] == ("hero", "may", "MAY-Z"), "caller puppet.api POST .../look passes: %s" % d)
        d = puppet.api(base, "POST", "/api/jobs", {"kind": "look", "target": {"kind": "hero", "id": "may", "code": "MAY-Z"}, "spec": {"method": "hero_puppet"}})
        check(d.get("ok") and fake.calls[-1][0] == "enqueue", "caller puppet.api POST /api/jobs passes")
        d = puppet.api(base, "POST", "/api/jobs/jY/install", {"choice": "c0", "options": {"variant": "MAY-Z"}})
        check(d.get("ok") and fake.calls[-1][:3] == ("install", "jY", "c0"), "caller puppet.api POST .../install passes")
        # the page: fetch(url, {method: 'POST', headers: {'Content-Type': 'application/json'}, body}) from its own origin
        for origin in ("http://127.0.0.1:%d" % port, "http://localhost:%d" % port):
            st, d = raw("POST", "/api/jobs", json.dumps({"kind": "look", "target": {}, "spec": {}}).encode(), {"Content-Type": "application/json", "Origin": origin})
            check(st == 200 and d.get("ok"), "caller the page (Origin %s): a JSON POST passes" % origin)
        st, d = raw("POST", "/api/upload", b"x" * 10, {"Content-Type": "application/octet-stream", "Origin": "http://127.0.0.1:%d" % port, "X-Kind": "4d", "X-Filename": "a.png"})
        check(st == 400 and "X-Kind" in d.get("error", ""), "caller the page's upload (octet-stream, its Origin) reaches the upload's own checks: %s" % d)
        st, d = raw("GET", "/api/frames/enemy/bug/BG-A", headers={})
        check(st == 200 and d.get("stub") == "frames", "caller frames.js: the look summary GET (no Origin, same origin) passes")
        # the selftests' post(): JSON, no Origin; and selftest_S's raw requests with a loopback Host
        st, d = raw("POST", "/api/jobs/requeue_interrupted", b"{}", {"Content-Type": "application/json"})
        check(st == 200 and d.get("requeued") == ["jA"] and fake.calls[-1] == ("requeue_interrupted", None, "restart"), "route POST /api/jobs/requeue_interrupted: %s" % d)
        st, d = raw("POST", "/api/jobs/requeue_interrupted", json.dumps({"ids": ["jA"], "all": True}).encode(), {"Content-Type": "application/json"})
        check(st == 200 and fake.calls[-1] == ("requeue_interrupted", ["jA"], "all"), "route requeue_interrupted passes ids and all")
        line = sock(["POST /api/upload HTTP/1.1", "Host: 127.0.0.1", "X-Kind: 2d", "X-Filename: big.png", "Content-Length: 300000000", "Connection: close"])
        check(" 413 " in line, "selftest_S's raw upload (loopback Host): still a 413 before any byte: %s" % line)
        line = sock(["POST /api/upload HTTP/1.1", "Host: 127.0.0.1", "X-Kind: 2d", "X-Filename: nolength.png", "Connection: close"])
        check(" 411 " in line, "selftest_S's raw upload without a length: still a 411: %s" % line)
        # the hostile shapes
        n_calls = len(fake.calls)
        st, d = raw("POST", "/api/jobs", b'{"kind": "look"}', {"Content-Type": "application/json", "Origin": "http://evil.example"})
        check(st == 403 and d.get("guard"), "another site's POST is a 403")
        st, d = raw("POST", "/api/jobs", b'{"kind": "look"}', {"Content-Type": "text/plain"})
        check(st == 415 and d.get("guard"), "a text/plain body (a simple cross-site request) is a 415")
        line = sock(["POST /api/jobs HTTP/1.1", "Host: attacker.example:%d" % port, "Content-Type: application/json", "Content-Length: 2", "Connection: close"])
        check(" 403 " in line, "a rebinding Host is a 403: %s" % line)
        line = sock(["GET /api/frames/enemy/bug/BG-A HTTP/1.1", "Host: attacker.example:%d" % port, "Connection: close"])
        check(" 403 " in line, "the GET that writes refuses a rebinding Host: %s" % line)
        check(len(fake.calls) == n_calls and len(fr_stub.seen) == 1, "nothing refused reached a route")
        st, d = raw("GET", "/api/status")
        check(st == 200 and d.get("interrupted") == 2 and d.get("interrupted_ids") == ["jA", "jB"] and d.get("doctor") is None
              and (d.get("ai_hosts") or {}).get("comfy") and d.get("jobs_available"), "/api/status: interrupted, interrupted_ids, doctor (off), ai_hosts: %s" % {k: d.get(k) for k in ("interrupted", "doctor")})
        line = sock(["GET /api/status HTTP/1.1", "Host: attacker.example", "Connection: close"])
        check(" 200 " in line, "a read-only GET is not guarded (unchanged)")
    finally:
        httpd.shutdown()
        httpd.server_close()
        for k, v in saved.items():
            setattr(server, k, v)


def _fn_source(path, name):
    """A top-level function's source as the file holds it now (ast, not inspect: inspect reads the file through line
    numbers of the module as imported, and other lanes edit server.py while a selftest runs)."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    for node in ast.parse(text).body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return ast.get_source_segment(text, node) or ""
    return ""


def _check_loopback(check, server):
    src_main, src_free = _fn_source(server.__file__, "main"), _fn_source(server.__file__, "free_port")
    check('ThreadingHTTPServer(("127.0.0.1", port), Handler)' in src_main and "0.0.0.0" not in src_main, "main() binds 127.0.0.1 only")
    check('s.bind(("127.0.0.1", port))' in src_free, "free_port() probes 127.0.0.1")
    check("_install_exit_handlers(jobs)" in src_main and "DOCTOR_LIVE[0] = True" in src_main, "main() installs the exit handlers and turns the doctor on")


def _check_requeue(check, tmp):
    import jobs
    import locks
    keys = ("JOBS_DIR", "QUEUE_FILE", "LAUNCH_FILE", "STARTED_AT")
    saved = {k: getattr(jobs, k) for k in keys}
    saved_l = {k: getattr(locks, k) for k in ("LOCK_DIR", "KEEP_DIR", "RESTORE_PENDING")}
    saved_s = (jobs._state, jobs._hooks, jobs._inited, jobs._readonly, jobs._queue_lock)
    try:
        jobs.JOBS_DIR = os.path.join(tmp, "jobs")
        jobs.QUEUE_FILE = os.path.join(jobs.JOBS_DIR, "queue.json")
        jobs.LAUNCH_FILE = os.path.join(tmp, "user", "debug_launch.json")
        locks.LOCK_DIR = os.path.join(tmp, "locks")
        locks.KEEP_DIR = os.path.join(locks.LOCK_DIR, "save_keep")
        locks.RESTORE_PENDING = os.path.join(locks.KEEP_DIR, "restore_pending.json")
        jobs._state = {"rev": 0, "jobs": []}
        jobs._readonly, jobs._queue_lock = None, None
        jobs.init({}, ROOT, claim=False)
        mk = lambda: jobs.enqueue("import", {}, {"targets": ["enemies/goblin"]})   # noqa: E731
        a, b, old, done = mk(), mk(), mk(), mk()
        la = jobs.enqueue("launch", {}, {"character": "solenne"})
        now = jobs._now()
        jobs.STARTED_AT = time.time() - 5
        for j, st, ended in ((a, "interrupted", now), (b, "interrupted", now), (old, "interrupted", "2026-10-01T10:00:00"),
                             (done, "done", now), (la, "interrupted", now)):
            rec = jobs._find(j["id"])
            rec["state"], rec["ended"] = st, ended
        check(jobs.interrupted_ids() == [a["id"], b["id"], la["id"]], "interrupted_ids: the jobs the restart interrupted, queue order (an older one left out)")
        check(jobs.interrupted_ids("all") == [a["id"], b["id"], old["id"], la["id"]], "interrupted_ids('all'): every interrupted job")
        r = jobs.requeue_interrupted(ids=[b["id"], done["id"]])
        check(r["requeued"] == [b["id"]] and r["skipped"] == [{"id": done["id"], "why": "not interrupted by the restart"}], "requeue_interrupted(ids): only those, the rest named: %s" % r)
        rec_b = jobs._find(b["id"])
        check(rec_b["state"] == "queued" and rec_b["attempt"] == 2 and rec_b["ended"] is None, "the same requeue as the card's button (attempt 2, queued)")
        r = jobs.requeue_interrupted()
        check(r["requeued"] == [a["id"]] and [s["id"] for s in r["skipped"]] == [la["id"]] and not r["refused"],
              "Re-queue all: the restart's jobs, a test in game skipped: %s" % r)
        check(jobs._find(old["id"])["state"] == "interrupted" and jobs._find(la["id"])["state"] == "interrupted", "the older interrupted job and the launch stay as they were")
        r = jobs.requeue_interrupted(scope="all")
        check(r["requeued"] == [old["id"]], "scope all takes the older one too")
        check(jobs.interrupted_ids() == [la["id"]], "after Re-queue all only the skipped launch is left")
        jobs._readonly = {"who": "another Level Editor", "pid": 1, "since": time.time()}
        try:
            jobs.requeue_interrupted()
            check(False, "a read-only editor refuses Re-queue all")
        except ValueError as e:
            check("another Level Editor" in str(e), "a read-only editor refuses Re-queue all with the holder named")
        jobs._readonly = None
        with open(jobs.QUEUE_FILE, "r", encoding="utf-8") as f:
            onfile = json.load(f)
        check(next(j for j in onfile["jobs"] if j["id"] == a["id"])["state"] == "queued", "the requeues are saved to the temp queue file")
    finally:
        for k, v in saved.items():
            setattr(jobs, k, v)
        for k, v in saved_l.items():
            setattr(locks, k, v)
        jobs._state, jobs._hooks, jobs._inited, jobs._readonly, jobs._queue_lock = saved_s


def _check_doctor_status(check, server):
    saved = (server.DOCTOR_LIVE[0], dict(server._doctor_cache), server._doctor_refresh)
    try:
        server.DOCTOR_LIVE[0] = False
        check(server.doctor_status() is None, "doctor_status: None unless main() turned it on (the selftests start no thread)")
        server.DOCTOR_LIVE[0] = True
        server._doctor_cache.update(t=time.time(), summary={"ok": True, "missing": []}, running=False, error="")
        n0 = threading.active_count()
        d = server.doctor_status()
        check(d == {"ok": True, "missing": [], "refreshing": False} and threading.active_count() == n0, "a fresh summary is served as cached, no refresh started")
        ran = threading.Event()

        def fake_refresh():
            with server._doctor_lock:
                server._doctor_cache.update(t=time.time(), running=False, summary={"ok": False, "missing": ["node"]})
            ran.set()
        server._doctor_refresh = fake_refresh
        server._doctor_cache.update(t=0.0, summary=None, running=False)
        t0 = time.time()
        d = server.doctor_status()
        check(d.get("pending") is True and time.time() - t0 < 0.5, "a stale summary starts a refresh and the request does not wait: %s" % d)
        check(ran.wait(5.0) and server.doctor_status().get("missing") == ["node"], "the refreshed summary is served next")
    finally:
        server.DOCTOR_LIVE[0] = saved[0]
        server._doctor_cache.clear()
        server._doctor_cache.update(saved[1])
        server._doctor_refresh = saved[2]


class _FakeProbe:
    """doctor's world on a plate: which programs, URLs and modules answer; records every URL and command asked."""

    def __init__(self, present=True, services=True, ssh_ok=True, editor_port=None):
        self.present, self.services, self.ssh_ok, self.editor_port = present, services, ssh_ok, editor_port
        self.urls, self.cmds = [], []
        self.files = set()

    def which(self, name):
        return ("C:/bin/%s.exe" % name) if self.present else None

    def run(self, argv, timeout=15):
        self.cmds.append(list(argv))
        if "true" in argv:
            return (0, "") if self.ssh_ok else (255, "Permission denied (publickey).")
        if argv[-1] == "-version":
            return 0, 'openjdk version "17.0.20.1"'
        return 0, "v24.0.0" if "node" in argv[0] else "git version 2.47"

    def http_json(self, url, timeout=3.0):
        self.urls.append(url)
        if url.startswith("http://127.0.0.1:") and "/api/status" in url:
            return (True, {"ok": True, "jobs_available": True}) if self.editor_port and (":%d/" % self.editor_port) in url else (False, "refused")
        if not self.services:
            return False, "URLError: timed out"
        if url.endswith("/system_stats"):
            return True, {"system": {"comfyui_version": "0.3"}, "devices": [{"name": "gpu"}]}
        if url.endswith("/v1/models"):
            return True, {"data": [1, 2]}
        return True, {"models": [1]}

    def exists(self, path):
        return self.present or os.path.exists(path) and path.startswith(tempfile.gettempdir())

    def isdir(self, path):
        return os.path.isdir(path)

    def glob(self, pattern):
        return [pattern.replace("*", "x")] if self.present else []

    def disk_free(self, path):
        return 50e9

    def module(self, name):
        return (True, "99.0") if self.present else (False, "")

    def read_json(self, path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def read_text(self, path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read()
        except OSError:
            return None

    def pid_alive(self, pid):
        return int(pid or 0) == 4242

    def listdir(self, path):
        return []

    def now(self):
        return time.time()


def _check_doctor(check, tmp):
    import doctor
    root, home = os.path.join(tmp, "root"), os.path.join(tmp, "home")
    os.makedirs(os.path.join(root, "tools", "dl", "locks"), exist_ok=True)
    os.makedirs(home, exist_ok=True)
    with open(os.path.join(root, "tools", "requirements.txt"), "w", encoding="utf-8") as f:
        f.write("# x\nnumpy>=1.22.0\nPillow>=10.0.0  # pictures\nscipy>=1.11.2\nwebsocket-client>=1.9.0\n")
    with open(os.path.join(root, "tools", "ai_hosts.json"), "w", encoding="utf-8") as f:
        json.dump(dict(TODAY, ssh="me@10.9.9.9"), f)
    lk = os.path.join(root, "tools", "dl", "locks")
    for name, owner in (("comfy", {"pid": 4242, "who": "gen_art", "since": time.time() - 30}), ("godot", {"pid": 99999999, "who": "a test", "since": time.time() - 4000}),
                        ("jobs", {"pid": 4242, "who": "level_editor", "note": "the Level Editor that runs the job queue (port 8790)", "since": time.time()}),
                        ("sim", None)):
        os.makedirs(os.path.join(lk, name + ".lock"), exist_ok=True)
        if owner:
            with open(os.path.join(lk, name + ".lock", "owner.json"), "w", encoding="utf-8") as f:
                json.dump(owner, f)
    p = _FakeProbe(present=True, services=True, ssh_ok=True, editor_port=8790)
    rep = doctor.run(root=root, home=home, quick=False, probe=p)
    by = {c["name"]: c for c in rep.checks}
    check(not rep.missing and doctor.summary(rep)["ok"], "doctor (all present): no essential missing: %s" % rep.missing)
    check([r for r in ("numpy", "pillow", "scipy", "websocket-client") if r in by] == ["numpy", "pillow", "scipy", "websocket-client"]
          and by["numpy"]["essential"] and not by["websocket-client"]["essential"], "doctor reads tools/requirements.txt (numpy, Pillow, scipy essential; the rest optional)")
    check(all(u.split("/")[2] in ("192.168.137.54:8188", "127.0.0.1:1234", "192.168.137.54:11434", "127.0.0.1:8790") for u in p.urls), "doctor asks only the hosts of ai_hosts.json (and the editor's own port): %s" % p.urls)
    ssh_cmd = next((c for c in p.cmds if "true" in c), None)
    check(ssh_cmd is not None and "BatchMode=yes" in ssh_cmd and ssh_cmd[-2] == "me@10.9.9.9" and ssh_cmd[ssh_cmd.index("-i") + 1].startswith(home),
          "the ssh login probe: BatchMode, the login and key from ai_hosts.json under the given home: %s" % ssh_cmd)
    check(by["lock comfy"]["status"] == "ok" and "alive" in by["lock comfy"]["detail"], "lock verdict: an alive holder")
    check(by["lock godot"]["status"] == "warn" and "dead" in by["lock godot"]["detail"], "lock verdict: a dead holder (reclaimed by the next taker)")
    check(by["lock jobs"]["status"] == "ok" and "port 8790" in by["lock jobs"]["detail"], "lock verdict: the jobs lock's editor answers on its port")
    check(by["lock sim"]["status"] == "warn" and "unknown" in by["lock sim"]["value"], "lock verdict: a folder without owner.json = an unknown process")
    check(all(os.path.isdir(os.path.join(lk, n + ".lock")) for n in ("comfy", "godot", "jobs", "sim")), "doctor released no lock, the dead one either (read-only)")
    p2 = _FakeProbe(present=True, services=False, editor_port=None)
    rep2 = doctor.run(root=root, home=home, quick=True, probe=p2)
    by2 = {c["name"]: c for c in rep2.checks}
    check(not rep2.missing and {"comfyui", "lmstudio", "ollama"} <= set(rep2.warnings), "services down = warnings, never a failure: %s" % rep2.warnings)
    check(by2["lock jobs"]["status"] == "warn" and "takes the queue over" in by2["lock jobs"]["detail"], "a jobs lock whose port does not answer: a phantom")
    check(not any("true" in c for c in p2.cmds) and "ssh_login" not in by2, "quick: no ssh login probe")
    empty_root, empty_home = os.path.join(tmp, "eroot"), os.path.join(tmp, "ehome")
    os.makedirs(empty_root, exist_ok=True)
    os.makedirs(empty_home, exist_ok=True)
    p3 = _FakeProbe(present=False, services=False)
    rep3 = doctor.run(root=empty_root, home=empty_home, quick=True, probe=p3)
    want_missing = {"numpy", "pillow", "scipy", "node", "godot", "checkout"}
    want_absent = {"git", "blender", "jdk", "ssh_key"}
    check(want_missing <= set(rep3.missing) and want_absent <= set(rep3.absent), "an empty home and checkout name every missing piece: %s / %s" % (rep3.missing, rep3.absent))
    txt = doctor.as_text(rep3)
    check("essentials MISSING: " in txt and "MISSING  godot" in txt and "pip install -r tools/requirements.txt" in txt, "the text names what is missing and how to fix it")
    s = doctor.summary(rep3)
    check(s["ok"] is False and set(s) >= {"ok", "at", "missing", "absent", "warnings", "checks"} and json.dumps(s), "summary(): the JSON shape /api/status.doctor carries")
    check(not any(c["name"] == "tools/keys" and ("=" in c["value"]) for c in rep.checks), "doctor names key files, never their contents")
    with open(doctor.__file__, "r", encoding="utf-8") as f:
        src = f.read()
    check(not any(w in src for w in ('"w"', "'w'", '"a"', "os.remove", "os.rmdir", "rmtree", "force_release", "os.replace", "os.rename")),
          "doctor writes, removes and releases nothing (read-only)")


NETSTAT = """
Active Connections

  Proto  Local Address          Foreign Address        State           PID
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       2348
  TCP    127.0.0.1:8787         0.0.0.0:0              LISTENING       5000
  TCP    192.168.0.43:8788      0.0.0.0:0              LISTENING       61888
  TCP    0.0.0.0:8790           0.0.0.0:0              LISTENING       7000
  TCP    192.168.0.43:5555      10.0.0.1:443           ESTABLISHED     7001
  TCP    [::]:135               [::]:0                 LISTENING       2348
  TCP    [::1]:8787             [::]:0                 LISTENING       5000
"""
TASKLIST = '"svchost.exe","2348","Services","0","8 K"\n"python.exe","5000","Console","1","50 K"\n"ssh.exe","61888","Console","1","9 K"\n"node.exe","7000","Console","1","9 K"\n'


def _check_net(check):
    import net_check as NC
    ls = NC.parse_netstat(NETSTAT)
    check(len(ls) == 6 and ls[0] == {"proto": "TCP", "address": "0.0.0.0", "port": 135, "pid": 2348} and ls[-1]["address"] == "[::1]", "net_check: LISTENING lines parsed, IPv6 kept, ESTABLISHED left out")
    names = NC.parse_tasklist(TASKLIST)
    check(names == {2348: "svchost.exe", 5000: "python.exe", 61888: "ssh.exe", 7000: "node.exe"}, "net_check: tasklist CSV parsed")
    cmd = '"C:\\WINDOWS\\System32\\OpenSSH\\ssh.exe" -N -T -o BatchMode=yes -L 192.168.0.43:8788:192.168.137.54:8788 teatree@192.168.137.54'
    check(NC.forward_of(cmd, 8788) == ("192.168.0.43", "192.168.137.54", "8788") and NC.forward_of(cmd, 9000) is None and NC.forward_of("ssh -L 8000:h:80 x", 8000) == ("", "h", "80"),
          "net_check: an ssh -L spec read for its port")
    rows = NC.verdicts(ls, names, {61888: cmd})
    check(all(not NC.is_loopback(r["address"]) for r in rows) and len(rows) == 4, "net_check: loopback listeners left out: %s" % [(r["address"], r["port"]) for r in rows])
    fwd = next(r for r in rows if r["port"] == 8788)
    check(fwd["flag"] == "forward" and "-L 127.0.0.1:8788:192.168.137.54:8788" in fwd["advice"] and "Your call" in fwd["advice"], "net_check: the forward flagged with the one command, nothing done")
    ed = next(r for r in rows if r["port"] == 8790)
    check(ed["flag"] == "editor" and "127.0.0.1" in ed["note"], "net_check: a listener in the editor's range on 0.0.0.0 is flagged")
    check([r["flag"] for r in rows][:2] == ["forward", "editor"] and rows[-1]["flag"] == "", "net_check: the flagged ones first")
    txt = NC.as_text(rows, {61888: cmd})
    check("FLAGGED" in txt and "This tool changed nothing." in txt, "net_check's text ends by saying it changed nothing")
    with open(NC.__file__, "r", encoding="utf-8") as f:
        src = f.read()
    check(not any(w in src for w in ("taskkill", "Stop-Process", "netsh ", "New-NetFirewall")), "net_check runs no command that changes anything")


def _check_console(check, server, tmp):
    import jobs
    import locks
    saved_l = locks.LOCK_DIR
    saved_j = (jobs._queue_lock, jobs._stop.is_set(), list(jobs._workers))
    saved_x = dict(server._exit_state)
    try:
        locks.LOCK_DIR = os.path.join(tmp, "locks_console")
        lk = locks.acquire("jobs", who="selftest SAFE97", note="the Level Editor that runs the job queue (port 1)", wait=False)
        check(lk is not None and os.path.isdir(locks.lock_path("jobs")), "a jobs lock taken in a temp lock dir")
        jobs._queue_lock = lk
        jobs._workers.clear()
        server._exit_state.update(done=False, jobs=jobs)
        out = io.StringIO()
        keep = sys.stdout
        sys.stdout = out
        try:
            r0, r1 = server._console_ctrl(0), server._console_ctrl(1)
            check(r0 is False and r1 is False and os.path.isdir(locks.lock_path("jobs")) and not server._exit_state["done"],
                  "Ctrl+C and Ctrl+Break are left to Python (False, nothing released)")
            r2 = server._console_ctrl(2)
        finally:
            sys.stdout = keep
        check(r2 is True and not os.path.isdir(locks.lock_path("jobs")) and jobs._queue_lock is None and server._exit_state["done"],
              "closing the window (CTRL_CLOSE_EVENT) releases the jobs lock: %s" % out.getvalue().strip())
        check("the job queue's lock is released" in out.getvalue(), "the close says so on the console")
        lk2 = locks.acquire("jobs", who="selftest SAFE97 again", wait=False)
        jobs._queue_lock = lk2
        check(server._console_ctrl(6) is True and os.path.isdir(locks.lock_path("jobs")), "the cleanup runs once (a second event does nothing)")
        lk2.release()
        jobs._queue_lock = None
        # the install: atexit, SIGBREAK, SetConsoleCtrlHandler; then undone
        import atexit
        import signal

        class _J:
            stopped = []

            def stop(self, timeout=3.0):
                self.stopped.append(timeout)
        old_break = signal.getsignal(signal.SIGBREAK) if hasattr(signal, "SIGBREAK") else None
        n_ref = len(server._console_handler_ref)
        server._exit_state.update(done=False)
        server._install_exit_handlers(_J())
        try:
            if hasattr(signal, "SIGBREAK"):
                check(signal.getsignal(signal.SIGBREAK) is signal.default_int_handler, "Ctrl+Break now raises KeyboardInterrupt like Ctrl+C")
            if os.name == "nt":
                check(len(server._console_handler_ref) == n_ref + 1, "the console handler is registered with Windows")
            check(server._exit_cleanup("exit") is True and _J.stopped == [0.5] and server._exit_cleanup("exit") is False, "atexit's cleanup stops the queue once, half a second a worker")
        finally:
            atexit.unregister(server._exit_cleanup)
            if hasattr(signal, "SIGBREAK"):
                signal.signal(signal.SIGBREAK, old_break)
            if os.name == "nt" and len(server._console_handler_ref) > n_ref:
                import ctypes
                ctypes.windll.kernel32.SetConsoleCtrlHandler(server._console_handler_ref.pop(), False)
    finally:
        locks.LOCK_DIR = saved_l
        jobs._queue_lock = saved_j[0]
        if not saved_j[1]:
            jobs._stop.clear()
        jobs._workers[:] = saved_j[2]
        server._exit_state.clear()
        server._exit_state.update(saved_x)


def _check_requirements(check):
    req = os.path.join(TOOLS, "requirements.txt")
    with open(req, "r", encoding="utf-8") as f:
        lines = [l.split("#", 1)[0].strip() for l in f]
    names = {l.split(">=")[0].strip().lower() for l in lines if l}
    check({"numpy", "pillow", "scipy"} <= names and all(">=" in l and "==" not in l for l in lines if l), "requirements.txt: numpy, Pillow, scipy as minimums (>=, never ==)")
    std = set(getattr(sys, "stdlib_module_names", ()))
    if not std:
        return
    local, files = set(), []
    for d, dirs, fs in os.walk(TOOLS):
        dirs[:] = [x for x in dirs if x not in ("dl", "jdk17", "__pycache__", "node_modules", "keys")]
        local.update(dirs)
        for f in fs:
            if f.endswith(".py"):
                files.append(os.path.join(d, f))
                local.add(f[:-3])
    blender = {"bpy", "bmesh", "mathutils", "bpy_extras"}
    import_to_req = {"PIL": "pillow", "websocket": "websocket-client", "gradio_client": "gradio_client"}
    missing = {}
    for p in files:
        try:
            with open(p, "r", encoding="utf-8") as f:
                tree = ast.parse(f.read())
        except (SyntaxError, UnicodeDecodeError, OSError):
            continue
        for node in ast.walk(tree):
            mods = [a.name for a in node.names] if isinstance(node, ast.Import) else ([node.module] if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module else [])
            for m in mods:
                top = m.split(".")[0]
                if top in std or top in local or top in blender or top == "__future__" or top.startswith("websockets"):
                    continue
                if import_to_req.get(top, top).lower() not in names:
                    missing.setdefault(top, os.path.relpath(p, ROOT))
    check(not missing, "every third-party import under tools/ is in requirements.txt (Blender's own modules aside): %s" % missing)


def _check_keys(check):
    readme = os.path.join(TOOLS, "keys", "README.md")
    check(os.path.isfile(readme), "tools/keys/README.md exists")
    with open(os.path.join(ROOT, ".gitignore"), "r", encoding="utf-8") as f:
        gi = [l.strip() for l in f]
    check("tools/keys/*" in gi and "!tools/keys/README.md" in gi and "tools/keys/" not in gi, ".gitignore: every file in tools/keys ignored but the README")
    import vision_eval
    check(os.path.normcase(os.path.abspath(vision_eval.KEYS_DIR)) == os.path.normcase(os.path.join(TOOLS, "keys")), "the evaluator reads its keys from tools/keys only")


def checks(check, run_node, server):
    tmp = tempfile.mkdtemp(prefix="le_safe97_")
    try:
        for name, fn in (("hosts", lambda: _check_hosts(check, tmp)), ("guard", lambda: _check_guard(check, server)),
                         ("http", lambda: _check_http(check, server, tmp)), ("loopback", lambda: _check_loopback(check, server)),
                         ("requeue", lambda: _check_requeue(check, tmp)), ("doctor_status", lambda: _check_doctor_status(check, server)),
                         ("doctor", lambda: _check_doctor(check, tmp)), ("net", lambda: _check_net(check)),
                         ("console", lambda: _check_console(check, server, tmp)), ("requirements", lambda: _check_requirements(check)),
                         ("keys", lambda: _check_keys(check))):
            try:
                fn()
            except Exception as e:   # noqa: BLE001  (one broken part is one failure)
                import traceback
                traceback.print_exc()
                check(False, "SAFE97 %s: %s: %s" % (name, type(e).__name__, e))
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
