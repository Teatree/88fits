"""The art requests' routes (pass 96, lane REQ; AI-05 / WF-01). server.py hands /api/requests... and
/api/job/<id>/summary here (api_get / api_post with the handler and the server module), as it does the frames and the
drivers. The record and the loop's frame live in tools/level_editor/requests.py (one module object through
jobs.requests_module()); the CLI Claude uses is tools/art_request.py.

    POST /api/requests                      {goal, asset: {kind, id, code?, method?, spec?, from?}, brief?, mode?, budget?}
                                            -> {ok, rid, fold}: the record written, the request's look job queued
    GET  /api/requests                      -> {ok, requests: [folds]} (newest first)
    GET  /api/requests/<rid>                -> {ok, ...the fold...} (state, waiting_for, iteration k of n, budget, spent,
                                               provisional, summary = one paragraph, sheet, jobs, history_tail, result)
    POST /api/requests/<rid>/pause|resume|stop|cancel|step      -> {ok, fold}
    POST /api/requests/<rid>/approve        {confirm: true} -> {ok, fold, export_job}; without confirm a 409
                                            {ok: false, needs_confirm: true, batch: {code, groups, staged}}
    POST /api/requests/<rid>/reject         {why} -> {ok, fold}
    POST /api/requests/<rid>/pick           {code} | {group: "run/side", slot, version} -> {ok, fold}
    GET  /api/job/<id>/summary              -> {ok, state, stages, hard, advisory, outputs, sheet, paragraph, ...}

Errors: 404 no such request or job; 400 a bad body or a refused create; 409 a state that refuses the verb.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

RID_RE = re.compile(r"^r\d{8}-\d{6}-[0-9a-f]{4}$")
JOB_RE = re.compile(r"^[A-Za-z0-9_-]+$")
VERBS = ("pause", "resume", "stop", "cancel", "step", "approve", "reject", "pick")


def _req(srv):
    """The requests module, told which jobs module the server uses (the real one, or a test stand-in)."""
    import jobs
    R = jobs.requests_module()
    m = srv.jobs_module() if hasattr(srv, "jobs_module") else None
    R.set_jobs(m if m is not None and m is not jobs else None)
    return R


def requests_module():
    """The record module as one shared object (LOOP's requests_api shim may look here first)."""
    import jobs
    return jobs.requests_module()


def load(rid):
    return requests_module().load(rid)


def save(record):
    return requests_module().save(record)


def record_event(rid, event):
    return requests_module().record_event(rid, event)


def set_provisional(rid, prov):
    return requests_module().set_provisional(rid, prov)


def charge(rid, unit, n=1, group=None):
    return requests_module().charge(rid, unit, n, group)


def api_get(h, srv, parts, query=None):
    """parts after /api/: ["requests"], ["requests", rid], ["job", id, "summary"]."""
    try:
        R = _req(srv)
    except Exception as e:   # noqa: BLE001
        return h._send(503, {"ok": False, "error": "the requests module could not be loaded: %s: %s" % (type(e).__name__, e)})
    if parts == ["requests"]:
        return h._send(200, {"ok": True, "requests": R.list_folds()})
    if len(parts) == 2 and parts[0] == "requests":
        if not RID_RE.match(parts[1]):
            return h._error(404, "a request id is r<YYYYMMDD-HHMMSS>-<4hex>")
        rec = R.load(parts[1])
        if rec is None:
            return h._error(404, "no request %s" % parts[1])
        out = R.fold(rec)
        out["ok"] = True
        return h._send(200, out)
    if len(parts) == 3 and parts[0] == "job" and parts[2] == "summary":
        if not JOB_RE.match(parts[1]):
            return h._error(400, "bad job id")
        try:
            s = R.job_summary(parts[1])
        except Exception as e:   # noqa: BLE001
            return h._error(503, "the summary could not be read: %s: %s" % (type(e).__name__, e))
        if s is None:
            return h._error(404, "no job %s" % parts[1])
        return h._send(200, s)
    return h._error(404, "unknown requests route")


def api_post(h, srv, parts, body=None):
    """parts after /api/requests/: [] (create), [rid, verb]."""
    body = body if isinstance(body, dict) else {}
    try:
        R = _req(srv)
    except Exception as e:   # noqa: BLE001
        return h._send(503, {"ok": False, "error": "the requests module could not be loaded: %s: %s" % (type(e).__name__, e)})
    if not parts:
        try:
            rec = R.create(body.get("goal"), body.get("asset") or {}, brief=body.get("brief"), mode=body.get("mode") or "auto",
                           budget=body.get("budget"), srv=srv, title=body.get("title"))
        except ValueError as e:
            return h._error(400, str(e))
        except Exception as e:   # noqa: BLE001
            return h._error(409, "the request could not be created: %s: %s" % (type(e).__name__, e))
        return h._send(200, {"ok": True, "rid": rec["rid"], "fold": R.fold(rec)})
    rid = parts[0]
    if not RID_RE.match(rid):
        return h._error(404, "a request id is r<YYYYMMDD-HHMMSS>-<4hex>")
    if len(parts) != 2 or parts[1] not in VERBS:
        return h._error(404, "requests verbs are %s" % ", ".join(VERBS))
    verb = parts[1]
    try:
        if verb == "pause":
            rec = R.pause(rid)
        elif verb == "resume":
            rec = R.resume(rid)
        elif verb == "stop":
            rec = R.stop(rid)
        elif verb == "cancel":
            rec = R.cancel(rid)
        elif verb == "step":
            rec = R.step_once(rid)
        elif verb == "approve":
            r = R.approve(rid, confirm=body.get("confirm"), srv=srv)
            if not r.get("ok"):
                out = {k: v for k, v in r.items() if k != "record"}
                return h._send(409, out)
            rec = r["record"]
            out = R.fold(rec)
            out.update({"ok": True, "export_job": r.get("export_job"), "batch": r.get("batch")})
            return h._send(200, out)
        elif verb == "reject":
            rec = R.reject(rid, why=str(body.get("why") or ""))
        else:
            rec = R.pick(rid, body, srv=srv)
    except LookupError as e:
        return h._error(404, str(e))
    except ValueError as e:
        return h._error(409, str(e))
    except Exception as e:   # noqa: BLE001
        return h._error(500, "%s: %s" % (type(e).__name__, e))
    if rec is None:
        return h._error(404, "no request %s" % rid)
    out = R.fold(rec)
    out["ok"] = True
    return h._send(200, out)
