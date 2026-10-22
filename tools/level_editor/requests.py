"""The art requests (pass 96, lane REQ; the assessment's WF-01 / WF-03 / AI-05): one record above the jobs of one art
request, the home of the Auto-iterate loop's state, and the frame of its step function.

    tools/dl/jobs/requests/<rid>.json        the record (INTERFACES.md draws it; `v` 1)
    requests.create(goal, asset, ...)        the record + the request's first job (a `look` job stamped `request: rid`)
    requests.on_job_end(job)                 jobs.py's hook: a job carrying `request` ended -> step(rid, "job:<state>")
    requests.step(rid, trigger)              the frame: paused / stopped / cancelled -> nothing; a job of the request still
                                             active -> nothing (one op at a time); the budget spent -> `waiting`,
                                             waiting_for "approval"; else LOOP's loop.next_op(record, findings) -> None =
                                             the gates passed (waiting for approval) | an op -> commands.validate ->
                                             commands.dispatch -> the iteration recorded, the budget counted
    requests.fold(record)                    the compact status the routes answer and the page draws, with one paragraph
    pause / resume / stop / cancel / step_once / approve / reject / pick   the controls (every one an event)

The step function ENQUEUES and never schedules: the four lanes of jobs.py do the work; the record only decides what to
queue next. LOOP's modules (`loop.py`, `commands.py`) are imported lazily; while they are not there the step treats
"no planner" as "nothing automatic to do: waiting for Garry's approval", and a minimal built-in dispatcher keeps the
record consistent for the ops `note`, `stop` and `select_provisional`. Tests inject fakes through set_loop /
set_commands / set_jobs.

A job without `request` runs exactly as before this pass: nothing here is called for it.

This file is named requests.py by the brief; it has nothing to do with the PyPI library of that name. Load it through
jobs.requests_module() (which falls back to a file load under the alias `le_requests` when the library got into
sys.modules first) so every caller shares one module object.
"""
import glob
import json
import os
import re
import sys
import threading
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
for _p in (TOOLS, HERE):
    if _p not in sys.path:
        sys.path.insert(0, _p)

V = 1
REQUESTS_DIR = None            # None = <jobs.JOBS_DIR>/requests (the selftests re-point the queue and take their requests along)
DEFAULTS_FILE = os.path.join(HERE, "request_defaults.json")
STATES = ("queued", "running", "paused", "waiting", "approved", "done", "failed", "stopped", "cancelled")
FINAL = ("done", "failed", "stopped", "cancelled")
MODES = ("auto", "step", "observe")
KINDS = ("enemy", "boss", "hero")
BUDGET_KEYS = ("rerolls", "repair_rounds", "lane_seconds", "evaluator_calls", "cloud_dollars")
BUILTIN_BUDGET = {"rerolls": 2, "repair_rounds": 2, "lane_seconds": 5400, "evaluator_calls": 60, "cloud_dollars": 0.0}
ACTIVE = ("queued", "running", "waiting")
FOLLOW_KINDS = ("import",)      # jobs that follow a landing: never an op, never a reason to wait before the next op
REROLL_OPS = ("requeue", "reroll_view")
MAX_DIRECT_OPS = 8              # direct ops (note, select_provisional, ...) one step may chain before a job is queued
HISTORY_TAIL = 8
ID_RE = re.compile(r"^[a-z0-9_]+$")
CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")
RID_RE = re.compile(r"^r\d{8}-\d{6}-[0-9a-f]{4}$")

_lock = threading.RLock()
_jobs = None
_loop = None
_loop_set = False
_commands = None
_commands_set = False
_stepping = {}   # rid -> the record a running step holds in memory (the shim's writes land there, never on disk under it)


# ---------------------------------------------------------------- hooks (tests inject fakes; the server uses the real modules)

def set_jobs(module):
    """The jobs module the record talks to (None = `import jobs`)."""
    global _jobs
    _jobs = module


def set_loop(module):
    """LOOP's planner (`next_op(record, findings) -> op | None`); None = import `loop` lazily; set_loop(False) = none."""
    global _loop, _loop_set
    _loop, _loop_set = module, module is not None


def set_commands(module):
    """LOOP's `commands` (`validate(op, record) -> (ok, why)`, `dispatch(op, record) -> {job, result, note}`)."""
    global _commands, _commands_set
    _commands, _commands_set = module, module is not None


def _jobs_mod():
    if _jobs is not None:
        return _jobs
    import jobs
    return jobs


def _lazy(name):
    try:
        return __import__(name)
    except ImportError:
        return None
    except Exception as e:   # noqa: BLE001  (a half-written module of another lane must not break the record)
        _log("requests: %s could not be imported: %s: %s" % (name, type(e).__name__, e))
        return None


def _loop_mod():
    if _loop_set:
        return _loop or None
    return _lazy("loop")


def _commands_mod():
    if _commands_set:
        return _commands or None
    return _lazy("commands")


def _log(msg):
    try:
        print(msg, flush=True)
    except Exception:
        pass


# ---------------------------------------------------------------- the record on disk

def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def _epoch(x):
    if x in (None, ""):
        return None
    try:
        return float(x)
    except (TypeError, ValueError):
        pass
    try:
        return time.mktime(time.strptime(str(x)[:19], "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        return None


def requests_dir():
    if REQUESTS_DIR:
        return REQUESTS_DIR
    try:
        return os.path.join(_jobs_mod().JOBS_DIR, "requests")
    except Exception:
        return os.path.join(ROOT, "tools", "dl", "jobs", "requests")


def path_of(rid):
    return os.path.join(requests_dir(), rid + ".json")


def new_rid():
    return "r%s-%s" % (time.strftime("%Y%m%d-%H%M%S"), uuid.uuid4().hex[:4])


def load(rid):
    if not rid or not RID_RE.match(str(rid)):
        return None
    p = path_of(rid)
    for _ in range(6):
        try:
            with open(p, "r", encoding="utf-8") as f:
                d = json.load(f)
            return d if isinstance(d, dict) and d.get("rid") == rid else None
        except FileNotFoundError:
            return None
        except (OSError, ValueError):
            time.sleep(0.02)
    return None


def save(rec):
    """The record written atomically (tmp + replace), `updated` bumped. The brief is immutable once created: a record
    whose brief differs from the one on disk is refused (ValueError)."""
    rec["updated"] = _now()
    d = requests_dir()
    os.makedirs(d, exist_ok=True)
    p = path_of(rec["rid"])
    if os.path.isfile(p):
        old = _read_json(p)
        if isinstance(old, dict) and old.get("rid") == rec["rid"] and old.get("brief") != rec.get("brief"):
            raise ValueError("request %s: the brief is immutable once created" % rec["rid"])
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(rec, f, indent=1, ensure_ascii=False)
    for i in range(40):
        try:
            os.replace(tmp, p)
            return p
        except PermissionError:
            if i == 39:
                raise
            time.sleep(0.05)
    return p


def list_records():
    out = []
    for p in glob.glob(os.path.join(requests_dir(), "r*.json")):
        rid = os.path.splitext(os.path.basename(p))[0]
        rec = load(rid)
        if rec:
            out.append(rec)
    out.sort(key=lambda r: r.get("created") or "", reverse=True)
    return out


def list_folds():
    return [fold(r) for r in list_records()]


# ---------------------------------------------------------------- defaults and budgets

def defaults():
    """request_defaults.json merged over the built-in budget; never raises (a missing or broken file = the built-ins)."""
    d = {}
    try:
        with open(DEFAULTS_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
        if not isinstance(d, dict):
            d = {}
    except (OSError, ValueError):
        d = {}
    budget = dict(BUILTIN_BUDGET)
    budget.update({k: v for k, v in (d.get("budget") or {}).items() if k in BUDGET_KEYS})
    out = dict(d)
    out["budget"] = _coerce_budget(budget)
    out.setdefault("tiers", {})
    out.setdefault("cloud_ceiling_dollars_per_day", 0.0)   # LOOP's vision_eval reads this key (the day's cloud ceiling; 0 = off)
    return out


def eyes_stamp(brief=None):
    """pass 98 (lane GEMINI): the request's tier-2 eye, stamped at creation so the planner stays a pure function of the
    record: {tier2, backend, model} from request_defaults.json tiers["2"]; on when tier 2 is antigravity (Gemini through
    Garry's subscription: no dollars) and neither tiers["2"].requests nor the brief's `gemini` is false. A record without
    it (made before pass 98) plans as pass 96 did."""
    t2 = (defaults().get("tiers") or {}).get("2")
    t2 = t2 if isinstance(t2, dict) else {}
    on = t2.get("backend") == "antigravity" and t2.get("requests", True) is not False and (brief or {}).get("gemini", True) is not False
    return {"tier2": bool(on), "backend": t2.get("backend") or "", "model": t2.get("model") or ""}


def _coerce_budget(b):
    out = {}
    for k in BUDGET_KEYS:
        v = (b or {}).get(k, BUILTIN_BUDGET[k])
        try:
            v = float(v) if k == "cloud_dollars" else int(float(v))
        except (TypeError, ValueError):
            v = BUILTIN_BUDGET[k]
        out[k] = max(0, v) if k != "cloud_dollars" else max(0.0, v)
    return out


def budget_for(overrides=None):
    """The request's budget: the defaults file over the built-ins, the request's own values over that."""
    b = dict(defaults()["budget"])
    for k, v in (overrides or {}).items():
        if k in BUDGET_KEYS and v is not None and v != "":
            b[k] = v
    return _coerce_budget(b)


def _empty_spent():
    return {"rerolls": 0, "repair_rounds": {}, "lane_seconds": 0, "evaluator_calls": 0, "cloud_dollars": 0.0}


def budget_left(rec):
    """What is left of every cap and which caps are spent: {rerolls, repair_rounds (the worst group), lane_seconds,
    evaluator_calls, cloud_dollars, exhausted: [names]}. cloud_dollars 0 = the metered tiers are off, never a stop."""
    b, s = rec.get("budget") or {}, rec.get("spent") or {}
    rounds = s.get("repair_rounds") or {}
    worst = max([int(v or 0) for v in rounds.values()] or [0])
    left = {"rerolls": int(b.get("rerolls", 0)) - int(s.get("rerolls", 0) or 0),
            "repair_rounds": int(b.get("repair_rounds", 0)) - worst,
            "lane_seconds": int(b.get("lane_seconds", 0)) - int(s.get("lane_seconds", 0) or 0),
            "evaluator_calls": int(b.get("evaluator_calls", 0)) - int(s.get("evaluator_calls", 0) or 0),
            "cloud_dollars": float(b.get("cloud_dollars", 0.0)) - float(s.get("cloud_dollars", 0.0) or 0.0)}
    ex = [k for k in ("lane_seconds", "evaluator_calls") if left[k] <= 0]
    if float(b.get("cloud_dollars", 0.0)) > 0 and left["cloud_dollars"] <= 0:
        ex.append("cloud_dollars")
    # re-rolls and repair rounds end the loop only once BOTH are spent: the planner may still repair with no re-roll left
    if left["rerolls"] <= 0 and left["repair_rounds"] <= 0:
        ex.extend(["rerolls", "repair_rounds"])
    left["exhausted"] = ex
    return left


def op_allowed_by_budget(rec, op):
    """Whether one op fits the budget left: a re-roll needs a re-roll, a repair a round of its group, an ask a call."""
    left = budget_left(rec)
    name = str((op or {}).get("op") or "")
    if name in REROLL_OPS:
        return left["rerolls"] > 0, "no re-roll left (%d of %d spent)" % (rec["spent"].get("rerolls", 0), rec["budget"].get("rerolls", 0))
    if name == "repair":
        g = _group_of(op)
        used = int((rec["spent"].get("repair_rounds") or {}).get(g, 0) or 0)
        cap = int(rec["budget"].get("repair_rounds", 0))
        return used < cap, "no repair round left for %s (%d of %d spent)" % (g, used, cap)
    if name == "ask":
        return left["evaluator_calls"] > 0, "no evaluator call left"
    return True, ""


def _group_of(op):
    t = (op or {}).get("target") or {}
    g = t.get("group")
    if g:
        return str(g)
    base, view = t.get("anim") or t.get("base"), t.get("view")
    return "%s/%s" % (base, view) if base and view else "*"


def count_op(rec, op):
    """The budget counting of one dispatched op (WF-03: every op is an event and a budget count)."""
    s = rec.setdefault("spent", _empty_spent())
    name = str((op or {}).get("op") or "")
    if name in REROLL_OPS:
        s["rerolls"] = int(s.get("rerolls", 0) or 0) + 1
    elif name == "repair":
        g = _group_of(op)
        rounds = s.setdefault("repair_rounds", {})
        rounds[g] = int(rounds.get(g, 0) or 0) + 1
    elif name == "ask":
        s["evaluator_calls"] = int(s.get("evaluator_calls", 0) or 0) + 1


def _recount(rec, jobs_by_id):
    """`spent` from the facts: lane seconds from the jobs' own clocks, evaluator calls and dollars from the findings'
    model_calls (the ops' counts stay as a floor: an ask op without findings yet still counts)."""
    s = rec.setdefault("spent", _empty_spent())
    secs = 0.0
    now = time.time()
    for jid in rec.get("jobs") or []:
        j = jobs_by_id.get(jid) or {}
        t0 = _epoch(j.get("started"))
        if t0 is None:
            continue
        t1 = _epoch(j.get("ended")) if j.get("ended") else (now if j.get("state") == "running" else None)
        if t1 is not None and t1 >= t0:
            secs += t1 - t0
    s["lane_seconds"] = int(secs)
    calls, dollars = 0, 0.0
    for f in _all_findings(rec):
        for c in f.get("model_calls") or []:
            calls += 1
            try:
                dollars += float(c.get("dollars") or 0.0)
            except (TypeError, ValueError):
                pass
    asks = sum(1 for it in rec.get("iterations") or [] if str((it.get("op") or {}).get("op")) == "ask")
    charged = s.get("charged") or {}
    s["evaluator_calls"] = max(calls, asks, int(charged.get("evaluator_calls", 0) or 0))
    s["cloud_dollars"] = max(round(dollars, 4), round(float(charged.get("cloud_dollars", 0.0) or 0.0), 4))


# ---------------------------------------------------------------- jobs of a request

def _public_job(j):
    """A job as the fold and the paragraph read it (never the log, never the plan)."""
    if not j:
        return {}
    prog = j.get("progress") or {}
    return {"id": j.get("id"), "kind": j.get("kind"), "method": j.get("method"), "state": j.get("state"), "title": j.get("title") or "",
            "lane": j.get("lane"), "started": j.get("started"), "ended": j.get("ended"), "error": j.get("error") or "",
            "waiting_for": j.get("waiting_for"), "stage": prog.get("stage") or "", "done": prog.get("done", 0), "total": prog.get("total", 0),
            "request": j.get("request"), "spec": j.get("spec") or {}, "outputs": j.get("outputs") or [], "target": j.get("target") or {},
            "rolled_back": j.get("rolled_back"), "merged_into": j.get("merged_into")}


def _jobs_of(rec):
    """Every job of the request: those the record lists and those stamped `request: rid` in the queue (an import queued
    by _after_done, a job LOOP's dispatcher queued); the record's list is brought up to date, in creation order. An
    import merged into another (jobs.py's coalescing marks it done with `merged_into`) takes the state of the one that
    really runs, so it reads queued / running / done / failed as that one does."""
    m = _jobs_mod()
    rid = rec["rid"]
    by_id = {}
    all_jobs = {}
    try:
        for j in (m.list() or {}).get("jobs") or []:
            all_jobs[j["id"]] = j
            if j.get("request") == rid or j.get("id") in (rec.get("jobs") or []):
                by_id[j["id"]] = _public_job(j)
    except Exception as e:   # noqa: BLE001  (a stand-in without list(): the record's own list through get())
        _log("requests: the queue could not be listed: %s" % e)
    for jid, pj in by_id.items():
        seen, target = 0, all_jobs.get(pj.get("merged_into") or "")
        while target is not None and target.get("merged_into") and seen < 5:
            target, seen = all_jobs.get(target["merged_into"]), seen + 1
        if target is not None:
            pj["merged_state_of"] = target["id"]
            for k in ("state", "ended", "error", "rolled_back", "started"):
                pj[k] = target.get(k) if k != "error" else (target.get("error") or "")
    for jid in rec.get("jobs") or []:
        if jid not in by_id:
            try:
                j = m.get(jid)
            except Exception:
                j = None
            by_id[jid] = _public_job(j) if j else {"id": jid, "state": "gone", "kind": "?", "title": ""}
    known = [x for x in (rec.get("jobs") or []) if x in by_id]
    extra = sorted([x for x in by_id if x not in known], key=lambda x: (by_id[x].get("started") or "", x))
    rec["jobs"] = known + extra
    return by_id


def _job_dir(jid):
    m = _jobs_mod()
    try:
        return os.path.join(m.JOBS_DIR, jid)
    except Exception:
        return os.path.join(ROOT, "tools", "dl", "jobs", jid)


def _read_json(p):
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def findings_of(rec, jobs_by_id=None):
    """The newest findings.json among the request's jobs (LOOP writes `<job>/findings.json`; GATES' bench the same
    shape), with `job` set and `path` added; None when none exists yet."""
    best = None
    for jid in reversed(rec.get("jobs") or []):
        p = os.path.join(_job_dir(jid), "findings.json")
        if os.path.isfile(p):
            d = _read_json(p)
            if isinstance(d, dict):
                d.setdefault("job", jid)
                d["path"] = _rel(p)
                best = d
                break
    return best


def _all_findings(rec):
    out = []
    for jid in rec.get("jobs") or []:
        p = os.path.join(_job_dir(jid), "findings.json")
        d = _read_json(p) if os.path.isfile(p) else None
        if isinstance(d, dict):
            out.append(d)
    return out


def _rel(p):
    try:
        return os.path.relpath(p, ROOT).replace("\\", "/")
    except ValueError:
        return str(p).replace("\\", "/")


def _result_of(jid):
    return _read_json(os.path.join(_job_dir(jid), "result.json")) or {}


# ---------------------------------------------------------------- events

def _event(rec, event, **fields):
    e = {"t": _now(), "event": event}
    e.update({k: v for k, v in fields.items() if v is not None})
    rec.setdefault("history", []).append(e)
    _events_mirror(rec, e)   # pass 97 (lane PROGRESS, WF-02): the same entry in tools/dl/jobs/events.jsonl
    return e


# LOOP's shim (tools/level_editor/requests_api.py) forwards these here: a call made while a step holds the record in
# memory (commands.dispatch runs inside the step) changes that record and is saved with the step; outside a step it
# loads, changes and saves the file.

def _held(rid):
    rec = _stepping.get(rid)
    if rec is not None:
        return rec, True
    return load(rid), False


def record_event(rid, event):
    """An entry appended to the record's history (t stamped; `event` defaults to "note")."""
    with _lock:
        rec, live = _held(rid)
        if rec is None:
            return None
        e = dict(event or {})
        e.setdefault("t", _now())
        e.setdefault("event", "note")
        rec.setdefault("history", []).append(e)
        _events_mirror(rec, e)   # pass 97 (lane PROGRESS, WF-02): the same entry in tools/dl/jobs/events.jsonl
        if not live:
            save(rec)
        return e


def set_provisional(rid, prov):
    """The provisional winner set on the record (a `provisional` event)."""
    with _lock:
        rec, live = _held(rid)
        if rec is None:
            return None
        rec["provisional"] = prov
        _event(rec, "provisional", code=(prov or {}).get("code"), groups=sorted((prov or {}).get("groups") or {}), by=(prov or {}).get("by"))
        if not live:
            save(rec)
        return rec


def charge(rid, unit, n=1, group=None):
    """spent.<unit> += n (repair_rounds per group) for an op run outside the step function (the step counts its own)."""
    with _lock:
        rec, live = _held(rid)
        if rec is None:
            return None
        s = rec.setdefault("spent", _empty_spent())
        if unit == "repair_rounds":
            rr = s.setdefault("repair_rounds", {})
            if not isinstance(rr, dict):
                rr = s["repair_rounds"] = {}
            rr[str(group or "*")] = int(rr.get(str(group or "*"), 0) or 0) + int(n)
        elif unit in BUDGET_KEYS:
            s[unit] = (float if unit == "cloud_dollars" else int)(s.get(unit, 0) or 0) + n
            if unit in ("evaluator_calls", "cloud_dollars"):
                # these two are recounted from the findings' ledger at every step: a charge made outside it survives as a floor
                ch = s.setdefault("charged", {})
                ch[unit] = (float if unit == "cloud_dollars" else int)(ch.get(unit, 0) or 0) + n
        else:
            raise ValueError("unknown budget unit %s" % unit)
        if not live:
            save(rec)
        return rec


def _toast(rec, text):
    rec["toast"] = {"t": _now(), "text": text}
    rec["note"] = text


# ---------------------------------------------------------------- create

def create(goal, asset, brief=None, mode="auto", budget=None, srv=None, title=None):
    """A new request: the record written and its first job (a `look` job of the asset) queued with `request: rid`.
    `asset` = {kind, id, code | null, method?, spec?, from?}: no code = the next free one is allocated and a stub look
    entry created (srv.next_codes / srv.add_look, the recipe copied from `from`); a code the asset lacks is created the
    same way. ValueError for a bad asset, mode or a job the queue refuses (then nothing is written)."""
    asset = dict(asset or {})
    kind, cid = str(asset.get("kind") or ""), str(asset.get("id") or "")
    if kind not in KINDS:
        raise ValueError("asset.kind is one of %s (got %r)" % (", ".join(KINDS), kind))
    if not ID_RE.match(cid):
        raise ValueError("asset.id is a content id (letters, digits, _): got %r" % cid)
    mode = str(mode or "auto")
    if mode not in MODES:
        raise ValueError("mode is one of %s" % ", ".join(MODES))
    goal = str(goal or "").strip()
    if not goal:
        raise ValueError("a request needs a goal (one sentence)")
    m = _jobs_mod()
    doc = m.content_doc(kind, cid) if hasattr(m, "content_doc") else None
    if doc is None:
        raise ValueError("no %s %s" % (kind, cid))
    code = asset.get("code")
    code = str(code) if code not in (None, "") else ""
    if code and not CODE_RE.match(code):
        raise ValueError("asset.code is a look code such as SP-B (got %r)" % code)
    src = str(asset.get("from") or "")
    if src and not CODE_RE.match(src):
        raise ValueError("asset.from is a look code")
    rid = new_rid()
    brief = dict(brief or {})
    variants = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    base_code = str(doc.get("variant_base") or "")
    have = code and (code in variants or code == base_code)
    recipe = None
    if src:
        if src in variants:
            recipe = dict((variants.get(src) or {}).get("recipe") or {})
        elif src == base_code:
            recipe = {}
        else:
            raise ValueError("%s has no look %s to copy from" % (cid, src))
        recipe["from"] = src
    if isinstance(brief.get("words"), dict) and brief["words"]:
        recipe = dict(recipe or {})
        recipe.update({k: v for k, v in brief["words"].items() if isinstance(k, str)})
    if not have:
        if srv is None or not hasattr(srv, "add_look"):
            raise ValueError("asset.code names a look %s does not have%s; the server allocates one when code is left empty" % (cid, (" (%s)" % code) if code else ""))
        if not code:
            nc = srv.next_codes(kind, cid, 1)
            if not nc.get("ok") or not nc.get("codes"):
                raise ValueError("no free look code for %s: %s" % (cid, nc.get("error") or "?"))
            code = str(nc["codes"][0])
        r = srv.add_look(kind, cid, code, note="request %s: %s" % (rid, goal[:80]), recipe=recipe or None)
        if not r.get("ok"):
            raise ValueError("the look %s could not be created: %s" % (code, r.get("error") or "?"))
        doc = m.content_doc(kind, cid) or doc
        variants = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    entry = variants.get(code) if code in variants else {}
    look_recipe = dict((entry or {}).get("recipe") or {})
    if recipe and have:
        look_recipe.update(recipe)   # the request's words and source laid over an existing look's recipe, for this job only
    method = str(asset.get("method") or look_recipe.get("method") or m.implied_method(kind, look_recipe, doc))
    spec = dict(asset.get("spec") or {})
    spec["method"] = method
    if recipe and "recipe" not in spec:
        spec["recipe"] = look_recipe
    spec.setdefault("note", spec.get("note") or "")
    target = {"kind": kind, "id": cid, "code": code}
    rec = {"rid": rid, "created": _now(), "updated": _now(), "v": V, "goal": goal,
           "brief": {"art_prompt": str(brief.get("art_prompt") or doc.get("art_prompt") or ""),
                     "appearance": str(brief.get("appearance") or doc.get("appearance") or ""),
                     "words": dict(brief.get("words") or {})},
           "asset": {"kind": kind, "id": cid, "code": code, "method": method, "from": src or None},
           "mode": mode, "budget": budget_for(budget), "spent": _empty_spent(),
           "state": "running", "waiting_for": None, "jobs": [], "current_job": None, "iterations": [],
           "provisional": None, "history": [], "result": None, "error": "", "note": "", "toast": None, "title": str(title or "")}
    rec["eyes"] = eyes_stamp(brief)   # pass 98 (lane GEMINI): Gemini at the decision points (tier 2), on by default
    _event(rec, "created", goal=goal, asset=dict(rec["asset"]), mode=mode, budget=dict(rec["budget"]))
    job_title = title or "request %s: %s %s" % (rid, cid, code)
    try:
        job = m.enqueue("look", target, spec, job_title, request=rid)
    except TypeError:   # a jobs stand-in without the kwarg (an older enqueue): stamp it after
        job = m.enqueue("look", target, spec, job_title)
        if (job or {}).get("id") and hasattr(m, "set_request"):
            m.set_request(job["id"], rid)
    jid = (job or {}).get("id")
    if jid:
        rec["jobs"].append(jid)
        rec["current_job"] = jid
        _event(rec, "job", job=jid, kind="look", state="queued", why="the request's look")
    with _lock:
        save(rec)
    return rec


# ---------------------------------------------------------------- the step function (the frame; LOOP fills the body)

def on_job_end(job):
    """jobs.py's hook (pass 96): a job carrying `request` ended (done, failed, cancelled, interrupted, or waiting for a
    human pick). Records the event and runs the step. Never raises."""
    rid = (job or {}).get("request")
    if not rid:
        return None
    with _lock:
        rec = load(rid)
        if rec is None:
            _log("requests: job %s names request %s which has no record" % (job.get("id"), rid))
            return None
        jid = job.get("id")
        if jid and jid not in rec["jobs"]:
            rec["jobs"].append(jid)
        _event(rec, "job", job=jid, kind=job.get("kind"), state=job.get("state"), error=(job.get("error") or "")[:200] or None,
               waiting_for=job.get("waiting_for") if job.get("state") == "waiting" else None)
        if job.get("kind") == "look" and job.get("state") == "done":
            # the look landed: the provisional look is the request's own until the loop names another
            rec.setdefault("landed", []).append({"job": jid, "t": _now()})
        save(rec)
    return step(rid, "job:%s" % job.get("state"))


def step(rid, trigger="", once=False):
    """One step of the loop (INTERFACES: the frame). Returns the record after it, or None without a record."""
    with _lock:
        rec = load(rid)
        if rec is None:
            return None
        _stepping[rid] = rec
        try:
            _step_locked(rec, trigger, once)
        except Exception as e:   # noqa: BLE001  (a broken planner must not lose the record)
            _event(rec, "error", where="step", trigger=trigger, error="%s: %s" % (type(e).__name__, e))
            rec["error"] = "the step failed: %s: %s" % (type(e).__name__, e)
            _wait_for_approval(rec, "the step failed: %s" % e)
        finally:
            _stepping.pop(rid, None)
        try:
            _recount(rec, _jobs_of(rec))   # the ops just dispatched (an ask's findings, a queued job) count at once
        except Exception as e:   # noqa: BLE001
            _log("requests: recount after the step failed: %s" % e)
        save(rec)
        return rec


def _step_locked(rec, trigger, once):
    jobs_by_id = _jobs_of(rec)
    _recount(rec, jobs_by_id)
    st = rec.get("state")
    if st in FINAL or st == "paused":
        return
    if st == "approved":
        _check_done(rec, jobs_by_id)
        return
    active = [jobs_by_id[j] for j in rec["jobs"] if jobs_by_id.get(j, {}).get("state") in ACTIVE and jobs_by_id[j].get("kind") not in FOLLOW_KINDS]
    if active:
        busy = [j for j in active if j.get("state") in ("queued", "running")]
        waiting = [j for j in active if j.get("state") == "waiting"]
        if waiting and not busy:
            if rec.get("waiting_for") != "pick":
                rec["state"], rec["waiting_for"], rec["current_job"] = "waiting", "pick", waiting[0]["id"]
                _event(rec, "waiting", why="pick", job=waiting[0]["id"], what=waiting[0].get("waiting_for"))
                _toast(rec, "job %s waits for a pick (%s)" % (waiting[0]["id"], waiting[0].get("waiting_for") or "?"))
        else:
            rec["state"], rec["waiting_for"], rec["current_job"] = "running", None, (busy[0]["id"] if busy else rec.get("current_job"))
        return
    if st == "waiting" and rec.get("waiting_for") == "approval":
        return   # waiting already: approve / reject / resume move it
    # the newest job of the request (not a follow-up) failed with nothing landed: the request failed
    last = None
    for jid in reversed(rec["jobs"]):
        j = jobs_by_id.get(jid) or {}
        if j.get("kind") not in FOLLOW_KINDS:
            last = j
            break
    if last and last.get("state") in ("failed", "interrupted", "cancelled") and not rec.get("landed") and rec.get("provisional") is None:
        rec["state"], rec["waiting_for"], rec["current_job"] = "failed", None, None
        rec["error"] = "job %s %s: %s" % (last.get("id"), last.get("state"), (last.get("error") or "")[:200])
        _event(rec, "failed", job=last.get("id"), error=rec["error"])
        _toast(rec, rec["error"])
        return
    if rec.get("mode") == "observe":
        _wait_for_approval(rec, "observe: the job landed; nothing automatic runs in this mode")
        return
    for _ in range(MAX_DIRECT_OPS):
        left = budget_left(rec)
        if left["exhausted"]:
            _wait_for_approval(rec, "the budget ended (%s)" % ", ".join(left["exhausted"]), budget=True)
            return
        findings = findings_of(rec, jobs_by_id)
        loop = _loop_mod()
        if loop is None or not hasattr(loop, "next_op"):
            _wait_for_approval(rec, "no planner module (loop.py): nothing automatic to do")
            return
        op = loop.next_op(rec, findings)
        if op is None:
            passed = bool(((findings or {}).get("gates") or {}).get("pass"))
            _wait_for_approval(rec, "the gates passed" if passed else "the planner has nothing more to try")
            return
        # what the planner notes beside the op (LOOP's `hard_before`) lives on the iteration, not on the op the commands module checks
        extra = {k: op.pop(k) for k in [k for k in op if k not in ("op", "target", "args", "why")]} if isinstance(op, dict) else {}
        ok, why = _validate(op, rec)
        if ok:
            ok, why = op_allowed_by_budget(rec, op)
        if not ok:
            _event(rec, "op", op=op, refused=why)
            _wait_for_approval(rec, "the next op was refused: %s" % why)
            return
        it = {"n": len(rec.get("iterations") or []) + 1, "started": _now(), "ended": None, "job": None,
              "findings": (findings or {}).get("path"), "op": op, "gates": ("pass" if ((findings or {}).get("gates") or {}).get("pass") else "fail") if findings else None, "note": ""}
        it.update({k: v for k, v in extra.items() if k not in it})
        try:
            res = _dispatch(op, rec) or {}
        except Exception as e:   # noqa: BLE001
            it["ended"], it["note"] = _now(), "the op failed: %s: %s" % (type(e).__name__, e)
            rec.setdefault("iterations", []).append(it)
            _event(rec, "op", n=it["n"], op=op, error=it["note"])
            _wait_for_approval(rec, it["note"])
            return
        if not isinstance(res, dict):
            res = {"result": res}
        if res.get("error"):
            # commands.dispatch never raises on a refusal: it answers {error, refused?}; the op is recorded, nothing is spent
            it["ended"], it["note"] = _now(), str(res["error"])
            rec.setdefault("iterations", []).append(it)
            _event(rec, "op", n=it["n"], op=op, error=it["note"], refused=bool(res.get("refused")) or None)
            _wait_for_approval(rec, ("the op was refused: %s" if res.get("refused") else "the op failed: %s") % res["error"])
            return
        count_op(rec, op)
        jid = res.get("job") if isinstance(res, dict) else None
        if isinstance(jid, dict):
            jid = jid.get("id")
        if jid:
            it["job"] = jid
            try:
                _jobs_mod().set_request(jid, rec["rid"])
            except Exception as e:   # noqa: BLE001  (a dispatcher that stamped it itself, or a stand-in without set_request)
                _log("requests: %s could not be stamped with %s: %s" % (jid, rec["rid"], e))
            if jid not in rec["jobs"]:
                rec["jobs"].append(jid)
            rec["current_job"] = jid
        else:
            it["ended"] = _now()
        if res.get("note"):
            it["note"] = str(res["note"])
        rec.setdefault("iterations", []).append(it)
        _event(rec, "op", n=it["n"], op=op, job=jid, note=it["note"] or None)
        name = str(op.get("op") or "")
        if name == "select_provisional":
            # the dispatcher's answer ({result: {provisional}} from LOOP's commands, or a plain provisional) laid over
            # what the store has staged and pinned for the look, so the page and `result` see every frame the export packs
            r = res.get("result") if isinstance(res.get("result"), dict) else {}
            prov = r.get("provisional") if isinstance(r.get("provisional"), dict) else (r if r.get("code") else {})
            merged = _provisional_from(rec, {"target": {"code": prov.get("code")}, "args": {"groups": prov.get("groups")}} if prov else op)
            merged.update({k: v for k, v in prov.items() if k not in ("groups", "code")})
            rec["provisional"] = merged
        if name == "stop":
            _wait_for_approval(rec, "the planner stopped: %s" % (op.get("why") or ""))
            return
        if once or rec.get("mode") == "step":
            rec["state"], rec["waiting_for"] = "paused", None
            _event(rec, "paused", why="one op at a time (%s)" % ("Step" if once else "mode step"))
            _toast(rec, "paused after %s (Step runs the next op)" % name)
            return
        if jid:
            rec["state"], rec["waiting_for"] = "running", None
            return
    _wait_for_approval(rec, "%d direct ops in one step: the planner loops" % MAX_DIRECT_OPS)


def _validate(op, rec):
    if not isinstance(op, dict) or not op.get("op"):
        return False, "an op is {op, target, args, why}"
    cm = _commands_mod()
    if cm is not None and hasattr(cm, "validate"):
        r = cm.validate(op, rec)
        if isinstance(r, tuple):
            return bool(r[0]), str(r[1] if len(r) > 1 else "")
        if isinstance(r, dict):
            return bool(r.get("ok")), str(r.get("why") or r.get("error") or "")
        return bool(r), "" if r else "refused by commands.validate"
    return _builtin_validate(op, rec)


BUILTIN_OPS = ("note", "stop", "select_provisional")


def _builtin_validate(op, rec):
    """Without LOOP's commands module only the record-keeping ops run here; anything that would queue work is refused."""
    name = str(op.get("op") or "")
    if name not in BUILTIN_OPS:
        return False, "no commands module: only %s run without it (got %s)" % (", ".join(BUILTIN_OPS), name)
    t = op.get("target") or {}
    a = rec.get("asset") or {}
    if t.get("id") and t.get("id") != a.get("id"):
        return False, "the op targets %s, not the request's %s" % (t.get("id"), a.get("id"))
    return True, ""


def _dispatch(op, rec):
    cm = _commands_mod()
    if cm is not None and hasattr(cm, "dispatch"):
        return cm.dispatch(op, rec)
    name = str(op.get("op") or "")
    if name == "note":
        return {"job": None, "result": None, "note": str((op.get("args") or {}).get("text") or op.get("why") or "")}
    if name == "select_provisional":
        return {"job": None, "result": _provisional_from(rec, op), "note": "provisional: %s" % ((op.get("target") or {}).get("code") or rec["asset"].get("code"))}
    if name == "stop":
        return {"job": None, "result": None, "note": str(op.get("why") or "stop")}
    raise ValueError("no commands module: %s cannot run" % name)


def _provisional_from(rec, op=None):
    """The provisional winner: the op's code (or the request's look) and what the frames store has staged for it."""
    code = str(((op or {}).get("target") or {}).get("code") or rec["asset"].get("code") or "")
    groups = _staged_groups(rec["asset"].get("kind"), rec["asset"].get("id"), code)
    args = (op or {}).get("args") or {}
    if isinstance(args.get("groups"), dict):
        for k, v in args["groups"].items():
            if isinstance(v, dict):
                cur = groups.setdefault(str(k), {"staged": [], "pinned": []})
                cur["staged"] = sorted(set(cur["staged"]) | set(int(s) for s in (v.get("staged") or [])))
    return {"code": code, "groups": groups}


def _staged_groups(kind, cid, code):
    """{"run/side": {"staged": [slots], "pinned": [slots]}}: what the next export of the look changes, from the frames
    store: the staged choices and (PAGE's frames_store.staged_batch, pass 96) the pinned slots whose installed cell
    differs (re-applied by the export). {} without a strip, a store, or when the store refused."""
    out = {}
    try:
        import frames_store as FS
        look = FS.Look(kind, cid, code)
        if not look.has_strip():
            return out
        if hasattr(FS, "staged_batch"):
            b = FS.staged_batch(kind, cid, code) or {}
            for it in b.get("items") or []:
                key = "%s/%s" % (it.get("base"), it.get("view"))
                g = out.setdefault(key, {"staged": [], "pinned": []})
                g["pinned" if it.get("why") == "pinned" else "staged"].append(int(it.get("slot")))
            for g in out.values():
                g["staged"], g["pinned"] = sorted(set(g["staged"])), sorted(set(g["pinned"]))
            return out
        for base, view, key, n in FS.groups_of(look):
            g = FS.Group(look, base, view)
            if not g.exists():
                continue
            st = g.staged()
            if st:
                out["%s/%s" % (base, view)] = {"staged": sorted(int(k) for k in st), "pinned": []}
    except Exception as e:   # noqa: BLE001
        _log("requests: the store could not be read for %s %s: %s" % (cid, code, e))
    return out


def _batch_count(groups):
    return sum(len(v.get("staged") or []) + len(v.get("pinned") or []) for v in (groups or {}).values())


def _wait_for_approval(rec, why, budget=False):
    if rec.get("provisional") is None:
        rec["provisional"] = _provisional_from(rec)
    rec["state"], rec["waiting_for"], rec["current_job"] = "waiting", "approval", None
    rec["stop_reason"] = why
    _event(rec, "waiting", why="budget" if budget else "approval", note=why)
    _toast(rec, "waiting for Garry's approval: %s" % why)


def _check_done(rec, jobs_by_id):
    """`approved`: the export job and the import after it both landed -> `done` with `result`; a failure -> `failed`."""
    ex_id = rec.get("export_job")
    ex = jobs_by_id.get(ex_id) if ex_id else None
    if ex is None:
        return
    if ex.get("state") in ("failed", "cancelled", "interrupted"):
        rec["state"], rec["error"] = "failed", "the export %s %s: %s" % (ex_id, ex.get("state"), (ex.get("error") or "")[:200])
        _event(rec, "failed", job=ex_id, error=rec["error"])
        _toast(rec, rec["error"])
        return
    if ex.get("state") != "done":
        return
    imp = None
    for jid in rec["jobs"]:
        j = jobs_by_id.get(jid) or {}
        if j.get("kind") == "import" and ex_id in ((j.get("spec") or {}).get("after_export") or []):
            imp = j
    if ex.get("rolled_back") or (imp and imp.get("state") in ("failed", "cancelled", "interrupted")):
        rec["state"], rec["error"] = "failed", "the import after the export failed: %s (the export was rolled back)" % ((imp or {}).get("error") or ex.get("error") or "")[:200]
        _event(rec, "failed", job=(imp or {}).get("id"), error=rec["error"])
        _toast(rec, rec["error"])
        return
    if imp is None or imp.get("state") != "done":
        return
    _finish_done(rec, jobs_by_id, ex, imp)


def _finish_done(rec, jobs_by_id, ex=None, imp=None):
    code = (rec.get("provisional") or {}).get("code") or rec["asset"].get("code")
    res = _result_of(ex["id"]) if ex else _result_of(_last_look_job(rec, jobs_by_id) or "")
    info = res.get("info") or {}
    f = findings_of(rec, jobs_by_id) or {}
    gates = f.get("gates") or {}
    flags = {"hard": gates.get("hard_failures"), "advisory": gates.get("advisory"), "pass": gates.get("pass")} if gates else {}
    verdicts = {}
    for it in f.get("items") or []:
        if it.get("ok") is False:
            verdicts.setdefault(str(it.get("field") or "?"), 0)
            verdicts[str(it.get("field") or "?")] += 1
    rec["state"], rec["waiting_for"], rec["current_job"] = "done", None, None
    rec["result"] = {"code": code, "strip_sha1": info.get("strip_sha1"), "entry": res.get("entry") or {}, "import_job": (imp or {}).get("id"),
                     "export_job": (ex or {}).get("id"), "changed": info.get("changed"), "flags": flags, "verdicts": verdicts,
                     "summary": "", "sheet": _sheet_of(rec, jobs_by_id), "strip": _strip_file(rec, code)}
    rec["result"]["summary"] = paragraph(rec, jobs_by_id)
    _event(rec, "done", code=code, export=(ex or {}).get("id"), import_job=(imp or {}).get("id"))
    _toast(rec, "done: %s %s installed" % (rec["asset"].get("id"), code))


def _last_look_job(rec, jobs_by_id):
    for jid in reversed(rec["jobs"]):
        if (jobs_by_id.get(jid) or {}).get("kind") == "look":
            return jid
    return None


def _strip_file(rec, code):
    try:
        m = _jobs_mod()
        tf, jp = m.content_path(rec["asset"]["kind"], rec["asset"]["id"])
        if not jp:
            return None
        letter = m._letter(code) if hasattr(m, "_letter") else code.rsplit("-", 1)[-1].lower()
        p = os.path.join(os.path.dirname(jp), "%s_sprite_%s.png" % (rec["asset"]["id"], letter))
        return _rel(p) if os.path.isfile(p) else None
    except Exception:
        return None


def _sheet_of(rec, jobs_by_id):
    f = findings_of(rec, jobs_by_id)
    if f and f.get("sheet"):
        return f["sheet"]
    for jid in reversed(rec["jobs"]):
        for o in (jobs_by_id.get(jid) or {}).get("outputs") or []:
            if o.get("type") == "sheet":
                return o.get("file") or o.get("url")
    return None


# ---------------------------------------------------------------- the controls

def _need(rid):
    rec = load(rid)
    if rec is None:
        raise LookupError("no request %s" % rid)
    return rec


def pause(rid):
    with _lock:
        rec = _need(rid)
        if rec["state"] in FINAL:
            raise ValueError("request %s is %s" % (rid, rec["state"]))
        if rec["state"] != "paused":
            rec["state"] = "paused"
            _event(rec, "paused", why="by hand")
            _toast(rec, "paused: the running job finishes, then nothing more runs until Resume")
        save(rec)
        return rec


def resume(rid):
    with _lock:
        rec = _need(rid)
        if rec["state"] in FINAL:
            raise ValueError("request %s is %s" % (rid, rec["state"]))
        if rec["state"] in ("paused", "waiting"):
            rec["state"], rec["waiting_for"] = "running", None
            _event(rec, "resumed")
            save(rec)
    return step(rid, "resume")


def stop(rid):
    """Stop keeps what landed: the request's queued and running jobs are cancelled (never a follow-up import). The
    state is written first, so the hook each cancelled job fires sees `stopped` and queues nothing."""
    with _lock:
        rec = _need(rid)
        if rec["state"] in FINAL:
            raise ValueError("request %s is %s" % (rid, rec["state"]))
        rec["state"], rec["waiting_for"], rec["current_job"] = "stopped", None, None
        if rec.get("provisional") is None:
            rec["provisional"] = _provisional_from(rec)
        save(rec)
        cancelled = _cancel_jobs(rec, follow_ups=False)
        rec = load(rid) or rec   # the hooks of the cancelled jobs wrote their events meanwhile
        _event(rec, "stopped", cancelled=cancelled)
        _toast(rec, "stopped: what landed is kept (approve it, or cancel the request)")
        save(rec)
        return rec


def cancel(rid):
    with _lock:
        rec = _need(rid)
        if rec["state"] in ("done", "cancelled"):
            raise ValueError("request %s is %s" % (rid, rec["state"]))
        rec["state"], rec["waiting_for"], rec["current_job"] = "cancelled", None, None
        save(rec)
        cancelled = _cancel_jobs(rec, follow_ups=True)
        rec = load(rid) or rec
        _event(rec, "cancelled", cancelled=cancelled)
        _toast(rec, "cancelled")
        save(rec)
        return rec


def _cancel_jobs(rec, follow_ups):
    m = _jobs_mod()
    jobs_by_id = _jobs_of(rec)
    out = []
    for jid in rec["jobs"]:
        j = jobs_by_id.get(jid) or {}
        if j.get("state") not in ACTIVE:
            continue
        if not follow_ups and j.get("kind") in FOLLOW_KINDS:
            continue
        try:
            m.cancel(jid)
            out.append(jid)
        except Exception as e:   # noqa: BLE001
            _event(rec, "error", where="cancel", job=jid, error=str(e))
    return out


def step_once(rid):
    """One op from a paused (or waiting) request, then paused again (the page's Step; mode step's continue)."""
    with _lock:
        rec = _need(rid)
        if rec["state"] in FINAL:
            raise ValueError("request %s is %s" % (rid, rec["state"]))
        rec["state"], rec["waiting_for"] = "running", None
        _event(rec, "step")
        save(rec)
    return step(rid, "step", once=True)


def staged_batch(rec):
    """What approve would export: the provisional look's staged slots and pinned re-applies per group (the one
    confirmation box's list); `staged` counts every frame the export changes."""
    code = (rec.get("provisional") or {}).get("code") or rec["asset"].get("code")
    groups = _staged_groups(rec["asset"]["kind"], rec["asset"]["id"], code)
    return {"code": code, "groups": groups, "staged": _batch_count(groups)}


def _look_entry(rec, code):
    m = _jobs_mod()
    doc = m.content_doc(rec["asset"]["kind"], rec["asset"]["id"]) or {}
    vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
    return vs.get(code) if isinstance(vs.get(code), dict) else {}


def approve(rid, confirm=False, srv=None):
    """Garry's one confirmation for the whole staged batch: the frames_export queued with confirm: true (+ look_op
    approve for a fresh look) and the request `approved`; with nothing staged the landed look is approved as it is and
    the request is `done` at once. Without confirm: {ok: false, needs_confirm, batch}."""
    with _lock:
        rec = _need(rid)
        if rec["state"] in ("approved", "done", "cancelled"):
            raise ValueError("request %s is %s" % (rid, rec["state"]))
        jobs_by_id = _jobs_of(rec)
        busy = [j for j in rec["jobs"] if (jobs_by_id.get(j) or {}).get("state") in ("queued", "running") and (jobs_by_id.get(j) or {}).get("kind") not in FOLLOW_KINDS]
        if busy:
            raise ValueError("job %s is still %s: pause or stop first" % (busy[0], jobs_by_id[busy[0]].get("state")))
        if not rec.get("landed") and rec.get("provisional") is None:
            raise ValueError("nothing has landed yet for request %s" % rid)
        batch = staged_batch(rec)
        code = batch["code"]
        entry = _look_entry(rec, code)
        fresh = bool(entry.get("fresh"))
        in_play = False
        try:
            m = _jobs_mod()
            doc = m.content_doc(rec["asset"]["kind"], rec["asset"]["id"]) or {}
            in_play = str(doc.get("variant") or doc.get("variant_base") or "") == code
        except Exception:
            pass
        if confirm is not True:
            return {"ok": False, "needs_confirm": True, "batch": batch, "fresh": fresh, "in_play": in_play,
                    "error": "approve %s %s: %d staged frame%s in %d group%s%s. Confirm first." % (
                        rec["asset"]["id"], code, batch["staged"], "" if batch["staged"] == 1 else "s", len(batch["groups"]), "" if len(batch["groups"]) == 1 else "s",
                        " (the look is NEW: approving drops its mark)" if fresh else "")}
        if fresh and srv is not None and hasattr(srv, "look_op"):
            r = srv.look_op(rec["asset"]["kind"], rec["asset"]["id"], [code], "approve")
            _event(rec, "look_approved", code=code, ok=bool(r.get("ok")), error=r.get("error"))
        if batch["staged"] > 0:
            if srv is None:
                raise ValueError("the export needs the server (requests_io hands it)")
            import frames_io as FRIO
            r = FRIO.export_job(srv, rec["asset"]["kind"], rec["asset"]["id"], code, {"confirm": True, "note": "request %s approved" % rid})
            if not r.get("ok"):
                raise ValueError("the export was refused: %s" % (r.get("error") or "?"))
            jid = (r.get("job") or {}).get("id")
            try:
                _jobs_mod().set_request(jid, rid)
            except Exception as e:   # noqa: BLE001
                _log("requests: the export %s could not be stamped: %s" % (jid, e))
            rec["jobs"].append(jid)
            rec["export_job"], rec["current_job"] = jid, jid
            rec["state"], rec["waiting_for"] = "approved", None
            _event(rec, "approved", code=code, export=jid, batch=batch)
            _toast(rec, "approved: export %s queued (%d frames)" % (jid, batch["staged"]))
            save(rec)
            return {"ok": True, "export_job": jid, "batch": batch, "record": rec}
        rec["state"], rec["waiting_for"] = "approved", None
        _event(rec, "approved", code=code, export=None, batch=batch)
        _finish_done(rec, jobs_by_id)
        save(rec)
        return {"ok": True, "export_job": None, "batch": batch, "record": rec}


def reject(rid, why=""):
    """Garry's reject with a reason: the provisional look's staged choices dropped, AN-13's `review` written on those
    versions, the reason recorded; then the loop goes on (mode auto) or waits for Step (mode step)."""
    with _lock:
        rec = _need(rid)
        if rec["state"] in ("done", "cancelled"):
            raise ValueError("request %s is %s" % (rid, rec["state"]))
        code = (rec.get("provisional") or {}).get("code") or rec["asset"].get("code")
        reviewed = _unstage_all(rec, code, why)
        rec.setdefault("rejections", []).append({"t": _now(), "code": code, "why": str(why or ""), "versions": reviewed})
        rec["provisional"] = None
        _event(rec, "rejected", code=code, why=str(why or ""), versions=len(reviewed))
        _toast(rec, "rejected: %s" % (why or "no reason given"))
        if rec["mode"] == "auto" and rec["state"] in ("waiting", "paused", "stopped", "running"):
            rec["state"], rec["waiting_for"] = "running", None
            save(rec)
            return step(rid, "rejected")
        rec["state"], rec["waiting_for"] = "paused", None
        save(rec)
        return rec


def _unstage_all(rec, code, why):
    out = []
    try:
        import frames_store as FS
        look = FS.Look(rec["asset"]["kind"], rec["asset"]["id"], code)
        if not look.has_strip():
            return out
        for base, view, key, n in FS.groups_of(look):
            g = FS.Group(look, base, view)
            if not g.exists():
                continue
            for slot, st in (g.staged() or {}).items():
                vid = st.get("id")
                try:
                    g.update_version(int(slot), vid, review={"verdict": "rejected", "why": str(why or ""), "by": "human", "t": _now(), "request": rec["rid"]})
                    out.append({"group": "%s/%s" % (base, view), "slot": int(slot), "id": vid})
                except Exception as e:   # noqa: BLE001
                    _log("requests: review not written on %s slot %s: %s" % (key, slot, e))
            g.unstage()
    except Exception as e:   # noqa: BLE001
        _log("requests: reject could not touch the store for %s: %s" % (code, e))
    return out


def pick(rid, body, srv=None):
    """Garry's pick: {code} names another look of the asset as the provisional one; {group, slot, version} pins (and
    stages) one version (frames_io.pin). Then mode auto continues from it, mode step waits."""
    body = body if isinstance(body, dict) else {}
    with _lock:
        rec = _need(rid)
        if rec["state"] in ("done", "cancelled", "approved"):
            raise ValueError("request %s is %s" % (rid, rec["state"]))
        kind, cid = rec["asset"]["kind"], rec["asset"]["id"]
        if body.get("code"):
            code = str(body["code"])
            if not CODE_RE.match(code):
                raise ValueError("code is a look code")
            m = _jobs_mod()
            doc = m.content_doc(kind, cid) or {}
            vs = doc.get("variants") if isinstance(doc.get("variants"), dict) else {}
            if code not in vs and code != str(doc.get("variant_base") or ""):
                raise ValueError("%s has no look %s" % (cid, code))
            rec["provisional"] = dict(_provisional_from(rec, {"target": {"code": code}}), by="human")
            _event(rec, "picked", code=code, by="human")
            _toast(rec, "picked %s" % code)
        elif body.get("group") and body.get("version") is not None and body.get("slot") is not None:
            group = str(body["group"])
            if "/" not in group:
                raise ValueError("group is <anim>/<view>, e.g. run/side")
            base, view = group.split("/", 1)
            code = str(body.get("look") or (rec.get("provisional") or {}).get("code") or rec["asset"].get("code"))
            slot, vid = int(body["slot"]), str(body["version"])
            import frames_io as FRIO
            import frames_store as FS
            g = FS.Group(FS.Look(kind, cid, code), base, view)
            prev = (g.selected().get(str(slot)) or {}) if g.exists() else {}
            r = FRIO.pin(kind, cid, code, base, view, {"slot": slot, "version": vid, "pinned": True})
            if not r.get("ok"):
                raise ValueError("the pin was refused: %s" % (r.get("error") or "?"))
            if prev.get("id") and prev["id"] != vid:
                # the pinned choice is not what the installed strip shows: the store's `installed_differs` (set by a
                # landing's re-register) marks it, so the batch lists it and the export packs it (the re-apply)
                try:
                    sel = g.selected()
                    cur = sel.get(str(slot)) or {}
                    cur["installed_differs"] = prev.get("installed_differs") or prev["id"]
                    sel[str(slot)] = cur
                    g._write_sel(sel)
                except Exception as e:   # noqa: BLE001
                    _log("requests: the pick's installed_differs mark was not written: %s" % e)
            g.unstage(slot)   # the pin is the choice now; a staged version of the slot would be a second one
            rec["provisional"] = dict(_provisional_from(rec, {"target": {"code": code}}), by="human")
            _event(rec, "picked", code=code, group=group, slot=int(body["slot"]), version=str(body["version"]), by="human")
            _toast(rec, "picked %s %s frame %d" % (code, group, int(body["slot"])))
        else:
            raise ValueError("pick is {code} or {group, slot, version}")
        if rec["mode"] == "auto" and rec["state"] in ("waiting", "paused", "running", "stopped"):
            rec["state"], rec["waiting_for"] = "running", None
            save(rec)
            return step(rid, "picked")
        rec["state"], rec["waiting_for"] = "paused", None
        save(rec)
        return rec


# ---------------------------------------------------------------- the fold and the paragraph

def iteration_of(rec):
    b = rec.get("budget") or {}
    return {"n": len(rec.get("iterations") or []), "of": int(b.get("rerolls", 0)) + int(b.get("repair_rounds", 0)) + 1}


def _minutes(secs):
    return int(round(float(secs or 0) / 60.0))


def budget_line(rec):
    b, s = rec.get("budget") or {}, rec.get("spent") or {}
    rounds = s.get("repair_rounds") or {}
    worst = max([int(v or 0) for v in rounds.values()] or [0])
    parts = ["%d of %d re-rolls" % (int(s.get("rerolls", 0) or 0), int(b.get("rerolls", 0))),
             "%d of %d repair rounds" % (worst, int(b.get("repair_rounds", 0))),
             "%d min of %d" % (_minutes(s.get("lane_seconds")), _minutes(b.get("lane_seconds"))),
             "%d of %d evaluator calls" % (int(s.get("evaluator_calls", 0) or 0), int(b.get("evaluator_calls", 0)))]
    if float(b.get("cloud_dollars", 0.0)) > 0:
        parts.append("$%.2f of $%.2f" % (float(s.get("cloud_dollars", 0.0) or 0.0), float(b.get("cloud_dollars", 0.0))))
    else:
        parts.append("no cloud spend (the metered tiers are off)")
    return "budget: " + ", ".join(parts)


def _op_text(op):
    if not isinstance(op, dict):
        return ""
    t = op.get("target") or {}
    where = " ".join(str(t[k]) for k in ("code", "group") if t.get(k))
    slots = t.get("slots")
    if slots:
        where += " frames %s" % ",".join(str(s) for s in slots)
    why = str(op.get("why") or "").strip()
    return "%s%s%s" % (op.get("op"), (" on " + where) if where else "", (": " + why) if why else "")


def paragraph(rec, jobs_by_id=None):
    """One paragraph composed by code (never a log, never a picture): what the request is, where it stands, what it
    waits for, the budget, the last op and the sheet."""
    if jobs_by_id is None:
        jobs_by_id = _jobs_of(rec)
    a = rec.get("asset") or {}
    it = iteration_of(rec)
    prov = rec.get("provisional") or {}
    staged = _batch_count(prov.get("groups") or {})
    st = rec.get("state")
    cur = jobs_by_id.get(rec.get("current_job") or "") or {}
    out = ["Request %s for %s %s %s (%s): %s." % (rec["rid"], a.get("kind"), a.get("id"), a.get("code"), a.get("method"), rec.get("goal"))]
    if st == "running":
        if cur:
            out.append("Iteration %d of %d; the %s job %s is %s%s." % (it["n"], it["of"], cur.get("kind"), cur.get("id"), cur.get("state"),
                                                                       (" (%s)" % cur["stage"]) if cur.get("stage") else ""))
        else:
            out.append("Iteration %d of %d; running." % (it["n"], it["of"]))
    elif st == "waiting" and rec.get("waiting_for") == "approval":
        out.append("Iteration %d of %d done; waiting for Garry's approval of the provisional look %s (%d frame%s to export%s)%s." % (
            it["n"], it["of"], prov.get("code") or a.get("code"), staged, "" if staged == 1 else "s",
            (" in " + ", ".join(sorted(prov.get("groups") or {}))) if prov.get("groups") else "",
            (": " + rec["stop_reason"]) if rec.get("stop_reason") else ""))
    elif st == "waiting":
        out.append("Waiting for a human pick on job %s (%s)." % (cur.get("id") or rec.get("current_job"), cur.get("waiting_for") or "?"))
    elif st == "paused":
        out.append("Paused after iteration %d of %d (Resume continues; Step runs one op)." % (it["n"], it["of"]))
    elif st == "stopped":
        out.append("Stopped after iteration %d of %d; what landed is kept (approve it or cancel)." % (it["n"], it["of"]))
    elif st == "cancelled":
        out.append("Cancelled after iteration %d of %d." % (it["n"], it["of"]))
    elif st == "failed":
        out.append("Failed: %s." % (rec.get("error") or "?").rstrip("."))
    elif st == "approved":
        ex = jobs_by_id.get(rec.get("export_job") or "") or {}
        out.append("Approved; the export %s is %s%s." % (ex.get("id") or "?", ex.get("state") or "?", " and its import is next" if ex.get("state") == "done" else ""))
    elif st == "done":
        r = rec.get("result") or {}
        ch = r.get("changed")
        out.append("Done: %s installed%s%s (import %s)." % (r.get("code") or a.get("code"),
                                                             (", %d frame%s changed" % (len(ch), "" if len(ch) == 1 else "s")) if isinstance(ch, list) else "",
                                                             (", strip %s" % r["strip"]) if r.get("strip") else "", r.get("import_job") or "none"))
    out.append(budget_line(rec).capitalize() + ".")
    its = rec.get("iterations") or []
    if its:
        last = its[-1]
        out.append("Last op: %s%s." % (_op_text(last.get("op")), (" (job %s)" % last["job"]) if last.get("job") else ""))
    sheet = _sheet_of(rec, jobs_by_id)
    if sheet:
        out.append("Review sheet: %s." % sheet)
    f = findings_of(rec, jobs_by_id)
    if f and f.get("gates"):
        g = f["gates"]
        out.append("Findings: %s hard, %s advisory (%s)." % (g.get("hard_failures", 0), g.get("advisory", 0), "pass" if g.get("pass") else "fail"))
    return " ".join(out)


def fold(rec, jobs_by_id=None):
    """The compact status (GET /api/requests/<rid>): the record's facts, the iteration k of n, the budget, the
    provisional look, the paragraph, the sheet, the jobs {id, kind, state, title}, the history's tail."""
    if jobs_by_id is None:
        jobs_by_id = _jobs_of(rec)
    jobs = [{"id": jid, "kind": (jobs_by_id.get(jid) or {}).get("kind"), "state": (jobs_by_id.get(jid) or {}).get("state"),
             "title": (jobs_by_id.get(jid) or {}).get("title") or "", "stage": (jobs_by_id.get(jid) or {}).get("stage") or "",
             "error": (jobs_by_id.get(jid) or {}).get("error") or ""} for jid in rec.get("jobs") or []]
    f = findings_of(rec, jobs_by_id)
    return {"rid": rec["rid"], "v": rec.get("v", V), "created": rec.get("created"), "updated": rec.get("updated"), "goal": rec.get("goal"),
            "asset": rec.get("asset"), "mode": rec.get("mode"), "state": rec.get("state"), "waiting_for": rec.get("waiting_for"),
            "iteration": iteration_of(rec), "budget": rec.get("budget"), "spent": rec.get("spent"), "budget_line": budget_line(rec),
            "provisional": rec.get("provisional"), "summary": paragraph(rec, jobs_by_id), "sheet": _sheet_of(rec, jobs_by_id),
            "jobs": jobs, "current_job": rec.get("current_job"), "export_job": rec.get("export_job"),
            "history_tail": (rec.get("history") or [])[-HISTORY_TAIL:], "iterations": rec.get("iterations") or [],
            "findings": {"job": f.get("job"), "path": f.get("path"), "gates": f.get("gates"), "sheet": f.get("sheet")} if f else None,
            "result": rec.get("result"), "error": rec.get("error") or "", "toast": rec.get("toast"), "note": rec.get("note") or "",
            "stop_reason": rec.get("stop_reason"), "title": rec.get("title") or "", "page": "#jobs?request=%s" % rec["rid"]}


# ---------------------------------------------------------------- a job's summary (GET /api/job/<id>/summary)

def job_summary(jid, jobs_mod=None):
    """{id, kind, state, request, stages: [{name, state, secs}], hard, advisory, gates, outputs: [{label, type, file?,
    url?}], sheet, paragraph, error}: state, stage ticks, the findings' counts, output paths, the sheet, one paragraph;
    no log, no pictures. None without the job."""
    m = jobs_mod or _jobs_mod()
    j = m.get(jid)
    if not j:
        return None
    prog = j.get("progress") or {}
    stages = [{"name": s.get("name"), "state": s.get("state"), "secs": s.get("secs")} for s in prog.get("stages") or []]
    outs = []
    sheet = None
    for o in j.get("outputs") or []:
        rec = {"label": o.get("label"), "type": o.get("type")}
        for k in ("file", "url", "cache_key"):
            if o.get(k):
                rec[k] = o[k]
        if o.get("qa") and (o["qa"].get("problems") or o["qa"].get("offline")):
            rec["qa"] = o["qa"]
        outs.append(rec)
        if o.get("type") == "sheet" and sheet is None:
            sheet = o.get("file") or o.get("url")
    jd = os.path.join(getattr(m, "JOBS_DIR", os.path.join(ROOT, "tools", "dl", "jobs")), jid)
    f = _read_json(os.path.join(jd, "findings.json")) if os.path.isdir(jd) else None
    gates = (f or {}).get("gates") if isinstance(f, dict) else None
    hard = gates.get("hard_failures") if gates else None
    adv = gates.get("advisory") if gates else None
    if f and f.get("sheet"):
        sheet = f["sheet"]
    done, total = prog.get("done", 0), prog.get("total", 0)
    bits = ["%s job %s%s is %s" % (j.get("kind"), jid, (" (%s)" % j["title"]) if j.get("title") else "", j.get("state"))]
    if total:
        bits.append("%d of %d stages done%s" % (done, total, (", at %s" % prog["stage"]) if prog.get("stage") and j.get("state") == "running" else ""))
    if j.get("state") == "waiting":
        bits.append("waiting for a human pick (%s)" % (j.get("waiting_for") or "?"))
    if j.get("request"):
        bits.append("part of request %s" % j["request"])
    if outs:
        bits.append("%d output%s" % (len(outs), "" if len(outs) == 1 else "s"))
    if gates:
        bits.append("findings: %s hard, %s advisory (%s)" % (hard, adv, "pass" if gates.get("pass") else "fail"))
    if j.get("error"):
        bits.append("error: %s" % j["error"])
    if sheet:
        bits.append("review sheet: %s" % sheet)
    return {"ok": True, "id": jid, "kind": j.get("kind"), "method": j.get("method"), "state": j.get("state"), "request": j.get("request"),
            "target": j.get("target"), "title": j.get("title") or "", "stages": stages, "done": done, "total": total, "stage": prog.get("stage") or "",
            "hard": hard, "advisory": adv, "gates": gates, "outputs": outs, "sheet": sheet, "error": j.get("error") or "",
            "started": j.get("started"), "ended": j.get("ended"), "paragraph": "; ".join(bits) + "."}


def _events_mirror(rec, entry):
    """pass 97 (lane PROGRESS, WF-02): a history entry mirrored into the events log as a `request` event (the same t and
    event; the history stays the record's own). Never raises; nothing when the log is off (outside the server)."""
    try:
        m = sys.modules.get("events") or sys.modules.get("le_events")
        if m is None or not hasattr(m, "request_event"):
            import jobs as _j
            m = _j._ev()
        if m is not None:
            m.request_event(rec, entry)
    except Exception:   # noqa: BLE001
        pass
