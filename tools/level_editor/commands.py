"""The loop's commands (pass 96, lane LOOP; the assessment's WF-05): the one shape an evaluator or planner may propose,
the allow-list per request mode, `validate` (schema, verbs, the target inside the request's own asset and look, no
pinned slot, budget left) and `dispatch` through the SAME functions the page uses (server.jobs_call / server._enqueue /
frames_io): nothing here writes a file, holds a lock or talks to ComfyUI.

    op = {"op": "repair", "target": {"kind": "enemy", "id": "desert_spider", "code": "SP-B", "group": "run/side", "slots": [3, 4]},
          "args": {"rung": "single"}, "why": "jump on slots 3-4"}
    ok, why = commands.validate(op, record)
    res = commands.dispatch(op, record)        # {"job": "j..."} | {"result": {...}} | {"error": "..."}

Auto-iterate (the default mode `auto`, and `step` = the same one op at a time): requeue (the request's look job queued
again with prompt words and/or a seed), reroll_view (one view's clip rolled again: a requeue with that clip moved aside),
repair (frames_io.repair_job: VACE on chosen slots with the method's profile rung), stage, copy (a version of another
look OF THE SAME ASSET into a slot), ask (an evaluate job), note, select_provisional (the chosen versions staged and
recorded as the provisional winner: never a pin, never an export, never the JSON's `variant`), stop.
Never: export, install, default, approve, pin, unpin, remove, delete, unstage, a pinned slot, anything outside the
request's asset. Observe: no op at all. Every dispatched op is an iteration and a budget count in REQ's step function
(requests.count_op); dispatch itself counts nothing (one counter).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)

OP_KEYS = ("op", "target", "args", "why")
TARGET_KEYS = ("kind", "id", "code", "group", "slots", "job")
VERBS = ("requeue", "reroll_view", "repair", "stage", "copy", "ask", "note", "select_provisional", "stop")
ALLOW = {"auto": set(VERBS), "step": set(VERBS), "observe": set()}
NEVER = ("export", "install", "default", "approve", "pin", "unpin", "remove", "delete", "unstage", "shelve", "variant", "icon", "merge", "push_workflows")
UNITS = {"requeue": "rerolls", "reroll_view": "rerolls", "repair": "repair_rounds", "ask": "evaluator_calls"}
KINDS = ("enemy", "boss", "hero")
ARGS_ALLOWED = {
    "requeue": ("words", "seed", "job", "keys"),
    "reroll_view": ("view", "base", "job", "seed"),
    "repair": ("rung", "window", "prompt", "seed", "guide", "note"),
    "stage": ("slot", "version", "why"),
    "copy": ("slot", "from", "stage"),
    "ask": ("tiers", "groups", "cloud_dollars", "backend", "model", "scope"),   # scope: pass 98 (lane GEMINI), tier 2's frames
    "note": ("text",),
    "select_provisional": ("code", "groups", "staged"),
    "stop": ("why",),
}


def unit_of(op):
    """(budget unit, group) an op costs, or None (stage, copy, note, select_provisional, stop are free)."""
    u = UNITS.get(str((op or {}).get("op")))
    if not u:
        return None
    return u, (str(((op or {}).get("target") or {}).get("group") or "*") if u == "repair_rounds" else None)


def _mode(record):
    return str((record or {}).get("mode") or "auto")


def _asset(record):
    return (record or {}).get("asset") or {}


def _budget_left(record, unit, group=None):
    """How many units of a kind the request may still spend (INTERFACES' budget / spent shapes)."""
    b, s = (record or {}).get("budget") or {}, (record or {}).get("spent") or {}
    cap = b.get(unit)
    if cap is None:
        return 1
    if unit == "repair_rounds":
        rr = s.get("repair_rounds") or {}
        used = int(rr.get(str(group or "*"), 0)) if isinstance(rr, dict) else int(rr or 0)
    else:
        used = s.get(unit) or 0
    return float(cap) - float(used)


def _parse_group(group):
    g = str(group or "")
    if "/" not in g:
        return None, None
    base, view = g.split("/", 1)
    return base, view


def _group_of(record, target, frames_store=None):
    """The frames_store Group of the target (None when the look has no such group)."""
    FS = frames_store
    if FS is None:
        import frames_store as FS
    base, view = _parse_group(target.get("group"))
    if not base:
        return None
    try:
        look = FS.Look(target["kind"], target["id"], target["code"])
        g = FS.Group(look, base, view)
    except ValueError:
        return None
    return g if g.exists() else None


def validate(op, record, frames_store=None):
    """(ok, reason): the schema (exactly op/target/args/why; args keys per verb), the mode's allow-list, the target inside
    the request's asset and look, no pinned slot, budget left for the op's unit."""
    if not isinstance(op, dict):
        return False, "an op is an object {op, target, args, why}"
    extra = sorted(set(op) - set(OP_KEYS))
    if extra:
        return False, "unknown keys on the op: %s" % ", ".join(extra)
    verb = op.get("op")
    if not isinstance(verb, str) or not verb:
        return False, "op is the verb's name"
    if verb in NEVER:
        return False, "%s is never an automatic op (Garry's click)" % verb
    allowed = ALLOW.get(_mode(record), set())
    if verb not in VERBS:
        return False, "unknown verb %r (one of %s)" % (verb, ", ".join(VERBS))
    if verb not in allowed:
        return False, "%s is not allowed in mode %s" % (verb, _mode(record))
    t = op.get("target")
    if not isinstance(t, dict):
        return False, "target is an object {kind, id, code, group?, slots?, job?}"
    extra = sorted(set(t) - set(TARGET_KEYS))
    if extra:
        return False, "unknown keys on the target: %s" % ", ".join(extra)
    a = _asset(record)
    if t.get("kind") not in KINDS:
        return False, "target.kind is enemy, boss or hero"
    if t.get("kind") != a.get("kind") or t.get("id") != a.get("id"):
        return False, "the target %s/%s is outside the request's asset %s/%s" % (t.get("kind"), t.get("id"), a.get("kind"), a.get("id"))
    if a.get("code") and t.get("code") != a.get("code"):
        return False, "the target look %s is not the request's look %s" % (t.get("code"), a.get("code"))
    if not t.get("code"):
        return False, "target.code is the look's code"
    args = op.get("args")
    if args is None:
        args = {}
    if not isinstance(args, dict):
        return False, "args is an object"
    extra = sorted(set(args) - set(ARGS_ALLOWED.get(verb, ())))
    if extra:
        return False, "unknown args for %s: %s" % (verb, ", ".join(extra))
    if not isinstance(op.get("why", ""), str):
        return False, "why is a sentence"
    if t.get("slots") is not None:
        if not isinstance(t["slots"], list) or not all(isinstance(s, int) and s >= 0 for s in t["slots"]):
            return False, "target.slots is a list of slot numbers"
    if verb in ("repair", "stage", "copy"):
        if not t.get("group"):
            return False, "%s needs target.group (base/view)" % verb
        if verb == "repair" and not t.get("slots"):
            return False, "repair needs target.slots"
        if verb in ("stage", "copy") and args.get("slot") is None:
            return False, "%s needs args.slot" % verb
        if verb == "copy":
            frm = args.get("from")
            if not isinstance(frm, dict) or not frm.get("code"):
                return False, "copy needs args.from {code, slot?, version?} of another look of the same asset"
        slots = list(t.get("slots") or []) + ([int(args["slot"])] if args.get("slot") is not None else [])
        g = _group_of(record, t, frames_store)
        if g is None:
            return False, "the look %s has no group %s in the frames store" % (t.get("code"), t.get("group"))
        sel = g.selected()
        for s in slots:
            if s >= g.n:
                return False, "slot %d is outside %s (%d frames)" % (s, t["group"], g.n)
            if (sel.get(str(s)) or {}).get("pinned"):
                return False, "slot %d of %s is pinned (a human's choice): never written by the loop" % (s, t["group"])
    if verb == "repair":
        rung = args.get("rung") or args.get("window") or "single"
        if rung not in ("single", "double", "auto"):
            return False, "repair rung is single, double or auto"
    if verb == "reroll_view" and not args.get("view"):
        return False, "reroll_view needs args.view"
    if verb == "select_provisional":
        if args.get("code") and args["code"] != t.get("code"):
            return False, "select_provisional names the request's own look"
    u = unit_of(op)
    if u:
        left = _budget_left(record, u[0], u[1])
        if left <= 0:
            return False, "no %s left in the budget%s" % (u[0], (" for " + u[1]) if u[1] else "")
    return True, ""


# ---------------------------------------------------------------- dispatch

class Ctx:
    """Where an op goes: the server's jobs_call / _enqueue and the frames_io module (the page's own functions). A selftest
    hands fakes."""

    def __init__(self, jobs_call=None, enqueue=None, frames_io=None, frames_store=None, requests_api=None):
        self.jobs_call, self.enqueue, self.frames_io, self.frames_store, self.requests_api = jobs_call, enqueue, frames_io, frames_store, requests_api

    @staticmethod
    def server():
        import server
        import frames_io
        import frames_store
        import requests_api
        return Ctx(server.jobs_call, server._enqueue, frames_io, frames_store, requests_api)

    class _Srv:
        """What frames_io.repair_job wants of a server: `_enqueue`."""
        def __init__(self, enqueue):
            self._enqueue = enqueue


def _look_job_of(record, target, ctx):
    """The request's look job to requeue: target.job, else the newest job of kind look in the record."""
    jid = target.get("job")
    if jid:
        return jid
    for j in reversed((record or {}).get("jobs") or []):
        st, body = ctx.jobs_call("get", j)
        if st == 200 and (body.get("job") or body).get("kind") == "look":
            return j
    return None


def _clip_key_of(target, view, base, ctx):
    g = _group_of(None, dict(target, group="%s/%s" % (base, view)), ctx.frames_store)
    if g is not None and (g.meta.get("clip") or {}).get("key"):
        return g.meta["clip"]["key"]
    FS = ctx.frames_store
    if FS is None:
        import frames_store as FS
    try:
        look = FS.Look(target["kind"], target["id"], target["code"])
        keys = look.clip_keys(base, view)
        return keys[0] if keys else None
    except ValueError:
        return None


def dispatch(op, record, ctx=None):
    """Run one validated op through the page's functions. Returns {"job": id} for a queued job, {"result": ...} for a
    direct one, {"error": ...} when the function refused; never raises on a refusal."""
    ctx = ctx or Ctx.server()
    ok, why = validate(op, record, ctx.frames_store)
    if not ok:
        return {"error": "refused: " + why, "refused": True}
    verb, t, args = op["op"], op["target"], op.get("args") or {}
    rid = (record or {}).get("rid")
    try:
        if verb == "note":
            e = ctx.requests_api.record_event(rid, {"event": "note", "text": str(args.get("text") or op.get("why") or ""), "by": "loop"}) if ctx.requests_api else None
            return {"result": {"noted": True, "event": e}}
        if verb == "stop":
            return {"result": {"stop": True, "why": str(args.get("why") or op.get("why") or "")}}
        if verb == "ask":
            spec = {"kind": t["kind"], "id": t["id"], "code": t["code"], "groups": list(args.get("groups") or ([t["group"]] if t.get("group") else [])),
                    "tiers": list(args.get("tiers") or [0, 1]), "request": rid or "", "cloud_dollars": float(args.get("cloud_dollars") or ((record or {}).get("budget") or {}).get("cloud_dollars") or 0.0),
                    "backend": str(args.get("backend") or ""), "model": str(args.get("model") or ""), "note": str(op.get("why") or "")}
            if args.get("scope"):   # pass 98 (lane GEMINI): which frames tier 2 sees, and the request's evaluator calls left
                spec["scope"] = str(args["scope"])
            if 2 in [int(x) for x in spec["tiers"] if str(x).lstrip("-").isdigit()]:
                spec["calls_left"] = max(0, int(_budget_left(record, "evaluator_calls")))
            res = ctx.enqueue("evaluate", {"kind": t["kind"], "id": t["id"], "code": t["code"]}, spec, "evaluate %s %s (the loop)" % (t["id"], t["code"]))
            j = (res or {}).get("job")
            if not j:
                return {"error": (res or {}).get("error") or "the evaluate job could not be queued"}
            return {"job": j["id"] if isinstance(j, dict) else j}
        if verb == "repair":
            rung = args.get("rung") or args.get("window") or "single"
            body = {"slots": [int(s) for s in t["slots"]], "window": rung if rung in ("single", "double") else "auto", "note": str(args.get("note") or op.get("why") or "")}
            if args.get("prompt"):
                body["prompt"] = str(args["prompt"])
            if args.get("seed"):
                body["seed"] = int(args["seed"])
            if args.get("guide"):
                body["guide"] = str(args["guide"])
            base, view = _parse_group(t["group"])
            res = ctx.frames_io.repair_job(Ctx._Srv(ctx.enqueue), t["kind"], t["id"], t["code"], base, view, body)
            if not res.get("ok"):
                return {"error": res.get("error") or "the repair was refused", "detail": res}
            return {"job": res["job"]["id"] if isinstance(res["job"], dict) else res["job"], "slots": res.get("slots")}
        if verb == "stage":
            base, view = _parse_group(t["group"])
            res = ctx.frames_io.stage(t["kind"], t["id"], t["code"], base, view, {"slot": int(args["slot"]), "version": str(args.get("version") or ""), "why": str(args.get("why") or op.get("why") or "the loop's choice")})
            return {"result": {"staged": res.get("staged"), "slot": res.get("slot")}} if res.get("ok") else {"error": res.get("error") or "stage refused"}
        if verb == "copy":
            base, view = _parse_group(t["group"])
            frm = dict(args.get("from") or {})
            res = ctx.frames_io.copy(t["kind"], t["id"], t["code"], base, view, {"slot": int(args["slot"]), "from": frm, "stage": bool(args.get("stage", True))})
            return {"result": {"version": res.get("version"), "staged": res.get("staged")}} if res.get("ok") else {"error": res.get("error") or "copy refused"}
        if verb == "select_provisional":
            return _select_provisional(op, record, ctx)
        if verb in ("requeue", "reroll_view"):
            jid = args.get("job") or _look_job_of(record, t, ctx)
            if not jid:
                return {"error": "no look job of this request to re-queue"}
            reroll = {}
            if verb == "reroll_view":
                base = str(args.get("base") or "run")
                key = _clip_key_of(t, str(args["view"]), base, ctx)
                if not key:
                    return {"error": "no clip cache key for %s/%s of %s" % (base, args["view"], t["code"])}
                reroll["clips"] = [key]
            if args.get("seed") is not None:
                reroll["seed"] = int(args["seed"])
            words = args.get("words")
            if verb == "requeue" and words:
                # the spec edit first (jobs.edit keeps the job's other fields), the words laid on the recipe's art_prompt
                st, body = ctx.jobs_call("get", jid)
                if st != 200:
                    return {"error": "no job %s" % jid}
                job = body.get("job") or body
                spec = dict(job.get("spec") or {})
                recipe = dict(spec.get("recipe") or {})
                recipe["art_prompt"] = (str(recipe.get("art_prompt") or "").rstrip(". ") + ", " + str(words)).strip(", ")
                recipe["loop_words"] = str(words)
                spec["recipe"] = recipe
                st, body = ctx.jobs_call("edit", jid, spec)
                if st != 200:
                    return {"error": "the spec edit was refused: %s" % (body.get("error") or st)}
                if args.get("keys"):
                    reroll["stills"] = list(args["keys"])
            st, body = ctx.jobs_call("requeue", jid, reroll or None)
            if st != 200:
                return {"error": "the re-queue was refused: %s" % (body.get("error") or st)}
            j = body.get("job") or body
            return {"job": j.get("id") if isinstance(j, dict) else jid, "reroll": reroll}
    except Exception as e:   # noqa: BLE001  (a function that raises is a refusal, never a crash of the step)
        return {"error": "%s: %s" % (type(e).__name__, e)}
    return {"error": "unknown verb %s" % verb}


def _select_provisional(op, record, ctx):
    """The provisional winner: the chosen versions staged (frames_io.stage: the preview plays them, nothing is written to
    the strip) and recorded on the request. Never a pin, never an export, never the JSON's `variant`."""
    t, args = op["target"], op.get("args") or {}
    groups = args.get("groups") or {}
    staged = {}
    for label, choice in (groups.items() if isinstance(groups, dict) else []):
        base, view = _parse_group(label)
        for slot, vid in (choice.get("versions") or {}).items():
            res = ctx.frames_io.stage(t["kind"], t["id"], t["code"], base, view, {"slot": int(slot), "version": str(vid), "why": "the loop's provisional winner"})
            if not res.get("ok"):
                return {"error": "stage refused on %s slot %s: %s" % (label, slot, res.get("error"))}
            staged.setdefault(label, {})[str(slot)] = str(vid)
    prov = {"code": t["code"], "groups": {label: {"staged": sorted(int(s) for s in v)} for label, v in staged.items()}, "why": str(op.get("why") or ""),
            "by": "loop", "note": "staged, not exported: Garry's one confirm exports it"}
    if not staged:
        # nothing to stage: the effective versions as they stand are the winner (recorded, so the page and `result` can say so)
        prov["groups"] = {label: {"staged": []} for label in (groups if isinstance(groups, dict) else [])}
    if ctx.requests_api and (record or {}).get("rid"):
        ctx.requests_api.set_provisional(record["rid"], prov)
    return {"result": {"provisional": prov}}
