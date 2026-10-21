"""Ops (pass 97, lane PROGRESS; the assessment's OPS-02 and WF-02's routes): what the job queue did, rolled up on demand,
the events log's reader, the archive's listing, and the server's own log file.

    GET /api/ops?days=7          -> {ok, days, outcomes: {state: {kind: {method: n}}}, medians: {key: {rendered: {median,
                                    p90, n}, cached: {...}, builtin, methods}}, lock_wait: {lock: seconds}, failures: [{reason,
                                    n, last_job, sample}], qa_offline, interrupted, stalled, cost: {requests: [{rid, dollars,
                                    calls}], total_dollars, calls, by_model: {model: {calls, dollars}}}, eta_source:
                                    "measured" | "builtin", generated_ms, jobs_seen, archived_read, window: {from, to}}
    GET /api/events?since=<seq>&limit=N[&job=<id>][&rid=<rid>][&look=<kind>/<id>[/<code>]]
                                 -> {ok, seq, last, more, events: [...]} (events.py; `seq` is the cursor for the next call)
    GET /api/jobs/archived[?month=YYYY-MM]
                                 -> {ok, total, months: [{month, n, file}]} | {ok, month, jobs: [...]}

Everything is computed from tools/dl/jobs/queue.json's records (the live queue in memory), the archive files and the
evaluator's ledger (tools/dl/qa/ledger.json); nothing is stored. A failed record whose `error` was only an ANSI code
(before pass 97) gets its reason re-derived from its log.txt for this view; the record itself is never rewritten.

server.log: `install_server_log()` tees the server's stdout and stderr (every print, every API line of log_message, every
traceback) into tools/dl/jobs/server.log, rotated at 5 MB with three old files kept (server.log.1 .. .3). `server_boot()`
(the top of server.main) installs it and turns the events log on; `server_start()` (after jobs.init) runs the archive at
start and once a day.
"""
import json
import os
import re
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

LEDGER = os.path.join(ROOT, "tools", "dl", "qa", "ledger.json")
LOG_MAX_BYTES = 5 * 1024 * 1024
LOG_BACKUPS = 3
ARCHIVE_EVERY = 24 * 3600.0
FAIL_STATES = ("failed",)
MONTH_RE = re.compile(r"^\d{4}-\d{2}$")
LOOK_RE = re.compile(r"^(enemy|boss|hero)/([a-z0-9_]+)(?:/([A-Za-z0-9_-]*))?$")


def _jobs():
    import jobs
    return jobs


def _rel(p):
    try:
        return os.path.relpath(p, ROOT).replace("\\", "/")
    except ValueError:   # another drive (a temporary folder in the selftest)
        return str(p).replace("\\", "/")


def _events():
    j = _jobs()
    return j._ev()


# ---------------------------------------------------------------- the roll-up

def _epoch(x):
    return _jobs()._epoch(x)


def _reason_key(text):
    """Failures grouped by their sentence with the numbers, ids and paths taken out."""
    t = re.sub(r"[A-Za-z]:[\\/][^\s'\"]+|/[^\s'\"]+/[^\s'\"]+", "<path>", text)
    t = re.sub(r"\bj\d{8}-\d{6}-[0-9a-f]{4}\b", "<job>", t)
    t = re.sub(r"0x[0-9A-Fa-f]+|\d+(\.\d+)?", "N", t)
    return t[:160]


def _reason_of(j):
    """A failed record's sentence: its `error`, or (an ANSI code alone, before pass 97) the rule on its log's tail."""
    J = _jobs()
    err = str(j.get("error") or "")
    if err and not J.error_is_noise(err):
        return J.strip_ansi(err).strip(), False
    tail = J.last_attempt_tail(j.get("id") or "")
    return J.error_line(tail, None), True


def _ledger(path=None, since_epoch=None, until_epoch=None):
    """{requests, total_dollars, calls, by_model} of the evaluator's ledger within the window (cached and refused calls
    are not counted, as the ledger's own totals do not)."""
    p = path or LEDGER
    try:
        with open(p, "r", encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return {"requests": [], "total_dollars": 0.0, "calls": 0, "by_model": {}, "file": _rel(p), "missing": True}
    reqs, models, total, calls = {}, {}, 0.0, 0
    for c in d.get("calls") or []:
        if not isinstance(c, dict) or c.get("refused") or c.get("cached"):
            continue
        t = _epoch(c.get("t"))
        if since_epoch is not None and (t is None or t < since_epoch):
            continue
        if until_epoch is not None and t is not None and t > until_epoch:
            continue
        dollars = float(c.get("dollars") or 0.0)
        total += dollars
        calls += 1
        m = models.setdefault(str(c.get("model") or "?"), {"calls": 0, "dollars": 0.0, "backend": c.get("backend")})
        m["calls"] += 1
        m["dollars"] = round(m["dollars"] + dollars, 6)
        rid = c.get("request")
        if rid:
            r = reqs.setdefault(str(rid), {"rid": str(rid), "dollars": 0.0, "calls": 0})
            r["calls"] += 1
            r["dollars"] = round(r["dollars"] + dollars, 6)
    return {"requests": sorted(reqs.values(), key=lambda r: -r["dollars"]), "total_dollars": round(total, 6), "calls": calls,
            "by_model": models, "file": _rel(p)}


def compute(days=7, records=None, archived=None, ledger_path=None, now=None):
    """The roll-up over the records whose run touched the window (ended, else started, else created within `days`):
    the live queue (`records`, default the jobs module's) and the archive (`archived`, default every archive file)."""
    J = _jobs()
    t_start = time.time()
    now = now if now is not None else time.time()
    days = max(0.0, float(days or 0)) or 7.0
    since = now - days * 86400.0
    if records is None:
        with J._lock:
            records = [dict(j) for j in J._state["jobs"]]
    arch_read = 0
    if archived is None:
        archived = [r for _, r in J.archived_records()] if since < now - J.ARCHIVE_DAYS * 86400.0 + 86400.0 * 2 else []
    arch_read = len(archived)
    seen, pool = set(), []
    for j in list(records) + list(archived):
        jid = j.get("id")
        if not jid or jid in seen:
            continue
        seen.add(jid)
        t = _epoch(j.get("ended")) or _epoch(j.get("started")) or _epoch(j.get("created"))
        if t is None or t < since or t > now + 60:
            continue
        pool.append(j)
    outcomes = {}
    for j in pool:
        st, kind = str(j.get("state") or "?"), str(j.get("kind") or "?")
        meth = str(j.get("method") or kind)
        outcomes.setdefault(st, {}).setdefault(kind, {})
        outcomes[st][kind][meth] = outcomes[st][kind].get(meth, 0) + 1
    med = J.measured_medians(pool)
    methods = {}
    try:
        methods = J._methods()
    except Exception:   # noqa: BLE001
        pass
    medians = {}
    any_measured = False
    for key, row in sorted(med.items()):
        r = dict(row)
        r["builtin"] = J.BUILTIN_MEDIAN.get(key)
        mt = (methods.get(key) or {}).get("time") if isinstance(methods.get(key), dict) else None
        r["methods"] = (mt or {}).get("median_s") if isinstance(mt, dict) else None
        r["eta_uses"] = "measured" if (row.get("rendered") or {}).get("n", 0) >= J.MEASURED_MIN_SAMPLES else ("methods" if r["methods"] else "builtin")
        any_measured = any_measured or r["eta_uses"] == "measured"
        medians[key] = r
    lock_wait = {}
    for j in pool:
        for name, secs in (j.get("lock_wait_total_s") or j.get("lock_wait_s") or {}).items():
            try:
                lock_wait[name] = round(lock_wait.get(name, 0.0) + float(secs), 1)
            except (TypeError, ValueError):
                continue
    groups = {}
    rederived = 0
    for j in sorted((x for x in pool if x.get("state") in FAIL_STATES), key=lambda x: str(x.get("ended") or "")):
        reason, re_d = _reason_of(j)
        rederived += 1 if re_d else 0
        k = _reason_key(reason)
        g = groups.setdefault(k, {"reason": reason, "n": 0, "last_job": None, "sample": "", "kinds": {}})
        g["n"] += 1
        g["reason"], g["last_job"], g["sample"] = reason, j.get("id"), str(j.get("error") or "")[:300]
        kk = str(j.get("method") or j.get("kind") or "?")
        g["kinds"][kk] = g["kinds"].get(kk, 0) + 1
    failures = sorted(groups.values(), key=lambda g: (-g["n"], g["reason"]))
    qa_offline = sum(1 for j in pool if j.get("lane") == "comfy" and j.get("qa_online") is False)
    out = {"ok": True, "days": days, "window": {"from": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(since)),
                                                 "to": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now))},
           "jobs_seen": len(pool), "archived_read": arch_read, "outcomes": outcomes, "medians": medians, "lock_wait": lock_wait,
           "failures": failures, "failures_rederived": rederived, "qa_offline": qa_offline,
           "interrupted": sum(1 for j in pool if j.get("state") == "interrupted"),
           "stalled": sum(1 for j in pool if (j.get("progress") or {}).get("stalled")),
           "cost": _ledger(ledger_path, since, now + 60), "eta_source": "measured" if any_measured else "builtin",
           "min_samples": J.MEASURED_MIN_SAMPLES}
    out["generated_ms"] = int(round((time.time() - t_start) * 1000))
    return out


# ---------------------------------------------------------------- routes

def _q(query, name, default=None):
    v = (query or {}).get(name)
    return v[0] if isinstance(v, list) and v else (v if isinstance(v, str) else default)


def api_get(h, srv, parts, query=None):
    """parts after /api/: ["ops"], ["events"], ["jobs", "archived"]."""
    query = query or {}
    try:
        if parts == ["ops"]:
            try:
                days = float(_q(query, "days", "7") or 7)
            except ValueError:
                return h._error(400, "days is a number")
            return h._send(200, compute(days))
        if parts == ["events"]:
            E = _events()
            if E is None:
                return h._send(200, {"ok": True, "seq": 0, "last": 0, "more": False, "events": [], "enabled": False})
            try:
                since = int(_q(query, "since", "0") or 0)
                limit = int(_q(query, "limit", str(E.DEFAULT_LIMIT)) or E.DEFAULT_LIMIT)
            except ValueError:
                return h._error(400, "since and limit are whole numbers")
            look = None
            lk = _q(query, "look")
            if lk:
                m = LOOK_RE.match(lk)
                if not m:
                    return h._error(400, "look is <kind>/<id>[/<code>]")
                look = {"kind": m.group(1), "id": m.group(2), "code": m.group(3) or None}
            job = _q(query, "job")
            if job and not re.match(r"^[A-Za-z0-9_-]+$", job):
                return h._error(400, "bad job id")
            rid = _q(query, "rid")
            out = E.since(since, limit, job=job, look=look, rid=rid)
            out["ok"] = True
            return h._send(200, out)
        if parts == ["jobs", "archived"]:
            J = _jobs()
            month = _q(query, "month")
            if month:
                if not MONTH_RE.match(month) and month != "unknown":
                    return h._error(400, "month is YYYY-MM")
                return h._send(200, {"ok": True, "month": month, "jobs": J.archived_month(month)})
            out = J.archived_summary()
            out["ok"] = True
            return h._send(200, out)
    except Exception as e:   # noqa: BLE001
        import traceback
        traceback.print_exc()
        return h._error(500, "%s: %s" % (type(e).__name__, e))
    return h._error(404, "unknown API path")


# ---------------------------------------------------------------- server.log

class _Tee:
    """A stream that writes to the console as before AND to a rotating file (each file line stamped with the time)."""

    def __init__(self, stream, sink):
        self.stream, self.sink = stream, sink

    def write(self, s):
        try:
            n = self.stream.write(s)
        except Exception:   # noqa: BLE001  (a console gone away must not stop the server)
            n = len(s) if isinstance(s, str) else 0
        self.sink.write(s)
        return n

    def flush(self):
        try:
            self.stream.flush()
        except Exception:   # noqa: BLE001
            pass
        self.sink.flush()

    def __getattr__(self, name):
        return getattr(self.stream, name)


class RotatingSink:
    """Appends text to `path`, a timestamp at the start of each line; at `max_bytes` the file becomes path.1 (path.1 ->
    path.2 ... the oldest beyond `backups` is deleted). Thread-safe; a failing write or rotation is swallowed (another
    process holding the file: the next write tries again)."""

    def __init__(self, path, max_bytes=LOG_MAX_BYTES, backups=LOG_BACKUPS):
        self.path, self.max_bytes, self.backups = path, int(max_bytes), int(backups)
        self.lock = threading.RLock()
        self.f = None
        self.at_line_start = True
        self.errors = 0

    def _open(self):
        if self.f is None:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            self.f = open(self.path, "a", encoding="utf-8", newline="\n", errors="replace")
        return self.f

    def _rotate(self):
        try:
            if self.f is not None:
                self.f.close()
                self.f = None
            for k in range(self.backups, 0, -1):
                src = self.path if k == 1 else "%s.%d" % (self.path, k - 1)
                dst = "%s.%d" % (self.path, k)
                if os.path.exists(src):
                    if os.path.exists(dst):
                        os.remove(dst)
                    os.replace(src, dst)
        except OSError:
            self.errors += 1

    def write(self, s):
        if not s:
            return
        with self.lock:
            try:
                f = self._open()
                stamp = time.strftime("%Y-%m-%d %H:%M:%S ")
                out = []
                for piece in str(s).splitlines(True):
                    if self.at_line_start:
                        out.append(stamp)
                    out.append(piece)
                    self.at_line_start = piece.endswith("\n")
                f.write("".join(out))
                f.flush()
                if f.tell() >= self.max_bytes:
                    self._rotate()
            except Exception:   # noqa: BLE001
                self.errors += 1

    def flush(self):
        with self.lock:
            try:
                if self.f is not None:
                    self.f.flush()
            except Exception:   # noqa: BLE001
                pass

    def close(self):
        with self.lock:
            try:
                if self.f is not None:
                    self.f.close()
            except Exception:   # noqa: BLE001
                pass
            self.f = None


_installed = {"sink": None}


def install_server_log(path=None, max_bytes=LOG_MAX_BYTES, backups=LOG_BACKUPS):
    """The server's stdout and stderr also into tools/dl/jobs/server.log (rotating). Once per process; returns the sink."""
    if _installed["sink"] is not None:
        return _installed["sink"]
    try:
        p = path or os.path.join(_jobs().JOBS_DIR, "server.log")
        sink = RotatingSink(p, max_bytes, backups)
        sys.stdout = _Tee(sys.stdout, sink)
        sys.stderr = _Tee(sys.stderr, sink)
        _installed["sink"] = sink
        return sink
    except Exception:   # noqa: BLE001  (no log file: the console as before)
        return None


# ---------------------------------------------------------------- the server's start

_archive_thread = {"t": None, "stop": threading.Event(), "last": None}


def server_boot(log=True):
    """The top of server.main(): the server.log tee and the events log on (tools/dl/jobs). Never raises."""
    out = {}
    try:
        if log:
            out["log"] = bool(install_server_log())
        E = _events()
        if E is not None:
            out["events"] = E.configure(_jobs().JOBS_DIR)
    except Exception as e:   # noqa: BLE001
        out["error"] = "%s: %s" % (type(e).__name__, e)
    return out


def server_start(jobs_mod=None, port=None, every=ARCHIVE_EVERY, first_delay=5.0):
    """After jobs.init: the `start` event, and (the editor that runs the queue only) the archive now and once a day."""
    J = jobs_mod or _jobs()
    try:
        E = _events()
        if E is not None:
            E.emit("server", "start", port=port, pid=os.getpid(), readonly=bool(J.is_readonly()) if hasattr(J, "is_readonly") else None)
    except Exception:   # noqa: BLE001
        pass
    if hasattr(J, "is_readonly") and J.is_readonly():
        return None
    if _archive_thread["t"] is not None:
        return _archive_thread["t"]

    def loop():
        if _archive_thread["stop"].wait(first_delay):
            return
        while True:
            try:
                r = J.archive_tick()
                _archive_thread["last"] = r
                a = (r or {}).get("archive") or {}
                if a.get("archived"):
                    print("jobs: %d finished jobs older than %d days moved to tools/dl/jobs/archive/" % (a["archived"], J.ARCHIVE_DAYS))
            except Exception as e:   # noqa: BLE001
                print("jobs: the archive tick failed: %s: %s" % (type(e).__name__, e))
            if _archive_thread["stop"].wait(every):
                return
    t = threading.Thread(target=loop, name="jobs-archive", daemon=True)
    _archive_thread["t"] = t
    t.start()
    return t
