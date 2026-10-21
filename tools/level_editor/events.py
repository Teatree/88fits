"""The events log (pass 97, lane PROGRESS; the assessment's WF-02): one ordered, append-only record of what happened to
the jobs, the looks, the content and the art requests, so "why did SP-B change at 12:40" is one grep.

    tools/dl/jobs/events.jsonl        one JSON object a line, `seq` strictly increasing:
                                      {seq, t, kind, event, job?, rid?, look?: {kind, id, code}, ...fields}
    tools/dl/jobs/<job>/events.jsonl  a copy of that job's own events (written beside its log.txt)

kinds: job (queued, started, finished, landed, picked, requeued, cancel, edited), look (approve, shelve, unshelve, remove,
note, recipe, default), icon (set, install_guard), content (write), frames (stage, unstage, pin, copy, export, rollback),
evaluator (a verdict), request (every entry of a request's history[], mirrored), server (start, archive).

One writer: the server process (`configure()` is called by server.main() only; a test points it at a temporary folder).
Nothing else writes: a tool, a script that imports jobs.py, a selftest that never configures it: `emit` does nothing.
Within the process one lock orders the appends; a second editor appending to the same file is noticed (the file grew
under us) and `seq` continues after its last line. `emit` never raises: a failing log never fails the operation it
records.

Reading: `since(seq, limit)` (the page's cursor: GET /api/events?since=<seq>&limit=N), `for_job(id)` (the job's own
copy), `for_look(kind, id, code)`, `for_request(rid)`. The request's history[] stays where it is (requests.py writes it as
before); each append is mirrored here as a `request` event with the same `t` and `event`.
"""
import json
import os
import threading
import time

FILE_NAME = "events.jsonl"
TAIL_BYTES = 65536          # how far back `configure` reads to find the last seq
DEFAULT_LIMIT = 200
MAX_LIMIT = 5000
ROLL_BYTES = 32 * 1024 * 1024   # the daily tick (jobs.archive_tick) moves a log this big into archive/events_<stamp>.jsonl

_lock = threading.Lock()
_dir = None
_seq = 0
_sig = None        # (size, mtime_ns) of the file after our last append: anything else = another writer appended
_errors = []       # the last few emit failures (for /api/ops and the selftest), never raised


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def configure(directory):
    """Turn the log on (server.main: tools/dl/jobs) or off (None). Reads the file's last seq so a restart continues."""
    global _dir, _seq, _sig
    with _lock:
        _dir = os.path.abspath(directory) if directory else None
        _seq, _sig = 0, None
        if _dir:
            p = os.path.join(_dir, FILE_NAME)
            _seq = _last_seq(p)
            _sig = _file_sig(p)
    return _dir


def enabled():
    return _dir is not None


def path():
    return os.path.join(_dir, FILE_NAME) if _dir else None


def _file_sig(p):
    try:
        st = os.stat(p)
        return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None


def _last_seq(p):
    """The highest seq among the file's last lines (0 for no file)."""
    try:
        with open(p, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - TAIL_BYTES))
            chunk = f.read()
    except OSError:
        return 0
    best = 0
    for raw in chunk.splitlines():
        try:
            e = json.loads(raw.decode("utf-8"))
            best = max(best, int(e.get("seq") or 0))
        except Exception:   # noqa: BLE001  (the first line of the chunk may be cut)
            continue
    return best


def look_of(kind, cid, code):
    """The `look` field: {kind, id, code} (code "" = the base)."""
    return {"kind": str(kind or ""), "id": str(cid or ""), "code": str(code or "")}


def _clean(v, depth=0):
    """A JSON-safe copy of a field (sets as lists, anything odd as its text), kept small."""
    if depth > 6:
        return str(v)[:200]
    if v is None or isinstance(v, (bool, int, float)):
        return v
    if isinstance(v, str):
        return v if len(v) <= 2000 else v[:2000] + "..."
    if isinstance(v, dict):
        return {str(k): _clean(x, depth + 1) for k, x in list(v.items())[:60]}
    if isinstance(v, (list, tuple, set)):
        return [_clean(x, depth + 1) for x in list(v)[:60]]
    return str(v)[:500]


def emit(kind, event, job=None, rid=None, look=None, **fields):
    """Append one event; returns it (with its seq), or None when the log is off or the append failed. Never raises."""
    global _seq, _sig
    if _dir is None:
        return None
    try:
        e = {"seq": 0, "t": fields.pop("t", None) or _now(), "kind": str(kind), "event": str(event)}
        if job:
            e["job"] = str(job)
        if rid:
            e["rid"] = str(rid)
        if look:
            e["look"] = look_of(look.get("kind"), look.get("id"), look.get("code")) if isinstance(look, dict) else str(look)
        for k, v in fields.items():
            if v is not None and k not in e:
                e[k] = _clean(v)
        with _lock:
            if _dir is None:
                return None
            p = os.path.join(_dir, FILE_NAME)
            if _file_sig(p) != _sig:
                _seq = max(_seq, _last_seq(p))   # another writer appended (a second editor): continue after it
            e["seq"] = _seq + 1
            line = json.dumps(e, ensure_ascii=False) + "\n"
            os.makedirs(_dir, exist_ok=True)
            with open(p, "a", encoding="utf-8", newline="\n") as f:
                f.write(line)
                f.flush()
            _seq = e["seq"]
            _sig = _file_sig(p)
            if job:
                jd = os.path.join(_dir, str(job))
                if os.path.isdir(jd):   # the job's own copy, beside its log.txt (an unknown id gets none)
                    with open(os.path.join(jd, FILE_NAME), "a", encoding="utf-8", newline="\n") as f:
                        f.write(line)
        return e
    except Exception as ex:   # noqa: BLE001  (the log must never fail what it records)
        _errors.append("%s %s: %s: %s" % (_now(), event, type(ex).__name__, ex))
        del _errors[:-20]
        return None


def errors():
    return list(_errors)


# ---------------------------------------------------------------- helpers the choke points call (one line each there)

def job_event(job, event, **fields):
    """A job's event: its id, request, look (a look-kind target with a code), state, attempt, phase."""
    if _dir is None or not isinstance(job, dict):
        return None
    t = job.get("target") or {}
    look = look_of(t.get("kind"), t.get("id"), t.get("code")) if t.get("kind") in ("enemy", "boss", "hero") and t.get("id") else None
    base = {"state": job.get("state"), "attempt": job.get("attempt"), "phase": job.get("phase"), "kind_of_job": job.get("kind"),
            "method": job.get("method")}
    base.update(fields)
    return emit("job", event, job=job.get("id"), rid=job.get("request"), look=look, **base)


def request_event(rec, entry):
    """One entry of a request's history[] mirrored (the same t and event; the request's asset as the look)."""
    if _dir is None or not isinstance(rec, dict) or not isinstance(entry, dict):
        return None
    a = rec.get("asset") or {}
    fields = {k: v for k, v in entry.items() if k not in ("event", "seq", "kind", "rid", "look", "job")}
    return emit("request", entry.get("event") or "note", rid=rec.get("rid"), job=entry.get("job") if isinstance(entry.get("job"), str) else None,
                look=look_of(a.get("kind"), a.get("id"), a.get("code")) if a.get("id") else None, **fields)


def look_events(kind, cid, codes, event, **fields):
    """One `look` event per code of a (bulk) look op."""
    out = []
    for c in (codes if isinstance(codes, (list, tuple)) else [codes]):
        out.append(emit("look", event, look=look_of(kind, cid, c), **fields))
    return out


# ---------------------------------------------------------------- reading

def _iter_file(p):
    try:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    e = json.loads(raw)
                except ValueError:
                    continue
                if isinstance(e, dict):
                    yield e
    except OSError:
        return


def _tail_after(p, since):
    """Every event with seq > since, read backwards from the end until a seq <= since (cheap for a recent cursor)."""
    out = []
    try:
        with open(p, "rb") as f:
            f.seek(0, 2)
            pos = f.tell()
            buf = b""
            done = False
            while pos > 0 and not done:
                step = min(65536, pos)
                pos -= step
                f.seek(pos)
                buf = f.read(step) + buf
                lines = buf.split(b"\n")
                buf = lines[0] if pos > 0 else b""
                body = lines[1:] if pos > 0 else lines
                for raw in reversed(body):
                    if not raw.strip():
                        continue
                    try:
                        e = json.loads(raw.decode("utf-8"))
                    except Exception:   # noqa: BLE001
                        continue
                    if int(e.get("seq") or 0) <= since:
                        done = True
                        break
                    out.append(e)
    except OSError:
        return []
    out.reverse()
    return out


def since(seq=0, limit=DEFAULT_LIMIT, job=None, look=None, rid=None, directory=None):
    """{seq, last, more, events}: the events after `seq` (oldest first, at most `limit`), filtered by job, look
    ({kind, id, code}: code "" or None = every look of the asset) or request. `seq` in the answer is the cursor for the
    next call (the last event returned, else the file's last seq); a cursor beyond the file's end (the log was reset)
    starts again from the beginning with `reset: true`."""
    d = os.path.abspath(directory) if directory else _dir
    limit = max(1, min(int(limit or DEFAULT_LIMIT), MAX_LIMIT))
    seq = max(0, int(seq or 0))
    if not d:
        return {"seq": seq, "last": 0, "more": False, "events": [], "enabled": False}
    p = os.path.join(d, FILE_NAME)
    last = _last_seq(p)
    reset = seq > last
    if reset:
        seq = 0
    evs = list(_iter_file(p)) if seq == 0 else _tail_after(p, seq)
    evs = [e for e in evs if int(e.get("seq") or 0) > seq and _match(e, job, look, rid)]
    more = len(evs) > limit
    evs = evs[:limit]
    cur = int(evs[-1]["seq"]) if evs else max(seq, last if not more else seq)
    out = {"seq": cur, "last": last, "more": more, "events": evs, "enabled": d == _dir}
    if reset:
        out["reset"] = True
    return out


def _match(e, job, look, rid):
    if job and e.get("job") != job:
        return False
    if rid and e.get("rid") != rid:
        return False
    if look:
        lk = e.get("look") if isinstance(e.get("look"), dict) else None
        if not lk or lk.get("kind") != look.get("kind") or lk.get("id") != look.get("id"):
            return False
        if look.get("code") not in (None, "") and lk.get("code") != look.get("code"):
            return False
    return True


def for_job(job_id, limit=MAX_LIMIT, directory=None):
    """A job's events from its own copy (oldest first)."""
    d = os.path.abspath(directory) if directory else _dir
    if not d or not job_id:
        return []
    return list(_iter_file(os.path.join(d, str(job_id), FILE_NAME)))[-limit:]


def for_look(kind, cid, code=None, limit=DEFAULT_LIMIT, directory=None):
    """The newest `limit` events of a look (oldest first)."""
    d = os.path.abspath(directory) if directory else _dir
    if not d:
        return []
    want = {"kind": kind, "id": cid, "code": code}
    return [e for e in _iter_file(os.path.join(d, FILE_NAME)) if _match(e, None, want, None)][-limit:]


def for_request(rid, limit=MAX_LIMIT, directory=None):
    d = os.path.abspath(directory) if directory else _dir
    if not d:
        return []
    return [e for e in _iter_file(os.path.join(d, FILE_NAME)) if e.get("rid") == rid][-limit:]


def roll_if_big(max_bytes=ROLL_BYTES):
    """The daily tick: a log above max_bytes moves to archive/events_<stamp>.jsonl (seq continues in the new file)."""
    global _sig
    if _dir is None:
        return None
    with _lock:
        p = os.path.join(_dir, FILE_NAME)
        try:
            if os.path.getsize(p) <= max_bytes:
                return None
        except OSError:
            return None
        ad = os.path.join(_dir, "archive")
        os.makedirs(ad, exist_ok=True)
        dest = os.path.join(ad, "events_%s.jsonl" % time.strftime("%Y%m%d-%H%M%S"))
        try:
            os.replace(p, dest)
        except OSError:
            return None
        _sig = _file_sig(p)
        return dest
