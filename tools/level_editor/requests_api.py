"""The thin shim lane LOOP calls for a request's record (pass 96): forwards to lane REQ's `requests.py` when it has the
name, else reads and writes `tools/dl/jobs/requests/<rid>.json` itself (the INTERFACES record), so commands.py and
loop.py never depend on REQ's module being there (the selftests run without it).

    load(rid) -> record | None          save(record)
    record_event(rid, event)            an entry appended to history[] (t stamped) and saved
    set_provisional(rid, prov)          record["provisional"] = prov, a "provisional" event
    charge(rid, unit, n=1, group=None)  spent.<unit> += n (repair_rounds per group); REQ's step counts the ops itself
                                        (requests.count_op), so dispatch does NOT call this: it is here for a caller
                                        that runs an op outside the step function.
"""
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if HERE not in sys.path:
    sys.path.insert(0, HERE)


def _req_module():
    """REQ's module when it is the Level Editor's (not the HTTP library of the same name) and has the record functions."""
    try:
        import requests as m   # noqa: F401
    except Exception:   # noqa: BLE001
        return None
    if os.path.dirname(os.path.abspath(getattr(m, "__file__", "") or "")) != HERE:
        return None
    return m if hasattr(m, "load") and hasattr(m, "save") else None


def requests_dir():
    m = _req_module()
    if m is not None and hasattr(m, "requests_dir"):
        try:
            return m.requests_dir()
        except Exception:   # noqa: BLE001
            pass
    try:
        import jobs
        base = jobs.JOBS_DIR
    except Exception:   # noqa: BLE001
        base = os.path.join(ROOT, "tools", "dl", "jobs")
    return os.path.join(base, "requests")


def path_of(rid):
    return os.path.join(requests_dir(), "%s.json" % rid)


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def load(rid):
    m = _req_module()
    if m is not None:
        return m.load(rid)
    try:
        with open(path_of(rid), "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save(record):
    m = _req_module()
    if m is not None:
        return m.save(record)
    p = path_of(record["rid"])
    os.makedirs(os.path.dirname(p), exist_ok=True)
    record["updated"] = _now()
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(record, f, indent=1, ensure_ascii=False)
    os.replace(tmp, p)
    return record


def record_event(rid, event):
    m = _req_module()
    if m is not None and hasattr(m, "record_event"):
        return m.record_event(rid, event)
    rec = load(rid)
    if rec is None:
        return None
    e = dict(event)
    e.setdefault("t", _now())
    rec.setdefault("history", []).append(e)
    save(rec)
    return e


def set_provisional(rid, prov):
    m = _req_module()
    if m is not None and hasattr(m, "set_provisional"):
        return m.set_provisional(rid, prov)
    rec = load(rid)
    if rec is None:
        return None
    rec["provisional"] = prov
    rec.setdefault("history", []).append({"t": _now(), "event": "provisional", "code": (prov or {}).get("code"), "groups": sorted((prov or {}).get("groups") or {})})
    save(rec)
    return rec


def charge(rid, unit, n=1, group=None):
    m = _req_module()
    if m is not None and hasattr(m, "charge"):
        return m.charge(rid, unit, n, group)
    rec = load(rid)
    if rec is None:
        return None
    spent = rec.setdefault("spent", {})
    if unit == "repair_rounds":
        rr = spent.setdefault("repair_rounds", {})
        if not isinstance(rr, dict):
            rr = spent["repair_rounds"] = {}
        rr[str(group or "*")] = int(rr.get(str(group or "*"), 0)) + int(n)
    else:
        spent[unit] = (float if unit == "cloud_dollars" else int)(spent.get(unit, 0) or 0) + n
    save(rec)
    return rec
