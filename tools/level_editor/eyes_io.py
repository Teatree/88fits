"""Gemini as a checker in the Level Editor (pass 98, lane GEMINI). Garry: "I wanted to make these kinds of checks when I'm
using the level editor on my own as well ... how I will be able to tell that Gemini discovered something that's wrong".

The eye itself is tools/vision_eval.py's `antigravity` backend (Gemini through Garry's Antigravity CLI, his subscription:
no dollars, a daily call cap). Every check is an `evaluate` job on the local lane (the page never waits on a model); when
it lands, jobs._evaluate_post hands its findings to on_findings(), which writes one entry per frame and eye into the
version's `qa.eyes` in the frames store (the Frames view's badges read it) beside the local button's `qa.vision`.

    GET  /api/eyes                                   the Gemini eye's health without a call (agy.exe, the read rule,
                                                     today's calls against the cap, the tier table's tier 2)
    GET  /api/eyes/look/<kind>/<id>/<code>           what the eyes say of the frames each group shows now: per group the
                                                     slots Gemini flags, the slots the local model flags, both; one line
    POST /api/eyes/check  {kind, id, code, groups?, fresh?}
                                                     Check with Gemini: an evaluate job, tiers 0, 1, 2 over the whole
                                                     look (Gemini on sheets per animation x view, up to 16 frames a sheet)
    POST /api/frames/<kind>/<id>/<code>/<anim>/<view>/ask_gemini  {slots: [..], fresh?}
                                                     Ask Gemini (frames_io hands it here): one contact-sheet call on the
                                                     chosen frames, an evaluate job (tiers [2], scope slots)
A finding is advisory: a badge with the model's name ("Gemini: 9 legs", "Local: ghost part"), never a gate.
Garry (2026-10-22): Gemini first; the local model only checks the frames of a Gemini call that failed, and that is shown
as an error: the findings' `gemini_error`, a red line on the job and request cards, the frames' "Local (fallback)"
badges, an events.jsonl entry (evaluator/fallback), the fallback calls' ledger rows, the Ops line's count.
"""
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for _p in (HERE, os.path.join(ROOT, "tools")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import frames_store as FS  # noqa: E402
import vision_eval as VE  # noqa: E402

ID_RE = re.compile(r"^[a-z0-9_]+$")
CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")
KINDS = ("enemy", "boss", "hero")
KEEP = 8                    # entries a version keeps in qa.eyes (the newest)
EYE_NAMES = {"gemini": "Gemini", "local": "Local"}
FIELD_WORDS = {"broken": "broken part", "ghost": "ghost part", "smear": "smear", "colour": "odd colour", "face": "face"}


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def _check(kind, cid, code):
    if kind not in KINDS or not ID_RE.match(cid or "") or not CODE_RE.match(code or ""):
        return "bad look %s/%s/%s" % (kind, cid, code)
    return ""


def eye_of(it):
    """gemini | local | <model>: which eye an item is from (pass 98 items carry `eye`; tier 1 is the local model)."""
    if it.get("eye"):
        return str(it["eye"])
    if it.get("backend") == "antigravity" or "gemini" in str(it.get("model") or "").lower():
        return "gemini"
    if int(it.get("tier") or 1) == 1:
        return "local"
    return str(it.get("model") or "model")


# ---------------------------------------------------------------- status

def status():
    """The Gemini eye's state for the page (no call is made)."""
    h = VE.agy_health()
    t2 = VE.tier_table().get("2")
    return dict(h, ok=True, ready=h["ok"], tier2=t2 if isinstance(t2, dict) else {}, auto=VE.agy_table().get("requests", True) is not False and bool(VE.agy_table()),
                ledger=VE._rel(VE.LEDGER), cap_key='tools/level_editor/request_defaults.json tiers["2"].daily_calls')


def _refusal():
    """Why a Gemini check cannot run now ("" = it can): the exe, the rule, the day's cap."""
    h = VE.agy_health()
    if not h["exe_ok"]:
        return "the Antigravity CLI is not installed here (%s)" % h["exe"]
    if not h["rule_ok"]:
        return "agy may not read the inbox: %s (python tools/vision_eval.py --agy-rule adds it, after a backup)" % h["rule_detail"]
    t = h["today"]
    if t.get("quota_until"):
        return "Gemini's subscription quota is spent until %s (agy said: %s); Ask the local vision model meanwhile" % (t["quota_until"], (t.get("quota_reason") or "")[:120])
    if t["left"] <= 0:
        return "today's Gemini cap is spent: %d of %d calls (request_defaults.json tiers[\"2\"].daily_calls)" % (t["calls"], t["cap"])
    return ""


# ---------------------------------------------------------------- the two buttons: jobs on the local lane

def _enqueue(srv, target, spec, title):
    fn = getattr(srv, "_enqueue", None)
    if not callable(fn):
        return {"ok": False, "error": "the queue is not here"}
    res = fn("evaluate", target, spec, title)
    j = (res or {}).get("job")
    if not j:
        return {"ok": False, "error": (res or {}).get("error") or "the evaluate job could not be queued"}
    return {"ok": True, "job": j}


def check_look(srv, body):
    """Check with Gemini: tiers 0, 1, 2 over the whole look (or `groups`), Gemini on every frame, sheets per group."""
    body = body if isinstance(body, dict) else {}
    kind, cid, code = str(body.get("kind") or ""), str(body.get("id") or ""), str(body.get("code") or "")
    err = _check(kind, cid, code)
    if err:
        return {"ok": False, "error": err}
    why = _refusal()
    if why and not body.get("force"):
        return {"ok": False, "error": why, "health": VE.agy_health()}
    groups = [str(g) for g in (body.get("groups") or []) if re.match(r"^[a-z]+/[a-z]+$", str(g))]
    spec = {"kind": kind, "id": cid, "code": code, "groups": groups, "tiers": [0, 1, 2], "scope": "all", "cloud_backend": "antigravity",
            "fresh": bool(body.get("fresh")), "by": "garry", "note": "Check with Gemini (by hand): every frame on sheets of up to 16, a hint per frame"}
    title = "check %s %s with Gemini%s" % (cid, code, (" (" + ", ".join(groups) + ")") if groups else "")
    return _enqueue(srv, {"kind": kind, "id": cid, "code": code}, spec, title)


def ask_frames(srv, kind, cid, code, base, view, body):
    """Ask Gemini about the chosen frames of one group: one sheet (16 frames a sheet), an evaluate job."""
    body = body if isinstance(body, dict) else {}
    slots = body.get("slots")
    if slots is None and body.get("slot") is not None:
        slots = [body.get("slot")]
    try:
        slots = sorted({int(s) for s in (slots or [])})
    except (TypeError, ValueError):
        return {"ok": False, "error": "slots is a list of frame numbers"}
    if not slots:
        return {"ok": False, "error": "which frames? (select them on the sheet)"}
    why = _refusal()
    if why and not body.get("force"):
        return {"ok": False, "error": why, "health": VE.agy_health()}
    label = "%s/%s" % (base, view)
    spec = {"kind": kind, "id": cid, "code": code, "groups": [label], "tiers": [2], "scope": "slots", "slots": {label: slots},
            "cloud_backend": "antigravity", "fresh": bool(body.get("fresh")), "by": "garry",
            "note": "Ask Gemini (by hand): %s frames %s" % (label, ",".join(str(s) for s in slots))}
    title = "ask Gemini: %s %s %s frames %s" % (cid, code, label, ",".join(str(s) for s in slots))
    res = _enqueue(srv, {"kind": kind, "id": cid, "code": code}, spec, title)
    if res.get("ok"):
        res["slots"] = slots
        res["sheets"] = (len(slots) + VE.AGY_SHEET_MAX - 1) // VE.AGY_SHEET_MAX
    return res


# ---------------------------------------------------------------- findings -> the frames store (one entry per frame and eye)

def _entries(items, job, when):
    """{(group, slot, version): {eye: entry}} from a findings record's model items."""
    out = {}
    for it in items or []:
        if it.get("kind") != "model" or not it.get("group") or it.get("slot") is None or not it.get("version"):
            continue
        key = (str(it["group"]), int(it["slot"]), str(it["version"]))
        eye = eye_of(it)
        e = out.setdefault(key, {}).setdefault(eye, {"eye": eye, "name": "Local (fallback)" if it.get("fallback") else EYE_NAMES.get(eye, eye), "fallback": bool(it.get("fallback")), "model": it.get("model"), "backend": it.get("backend") or ("openai_chat" if eye == "local" else ""),
                                                      "tier": it.get("tier"), "ok": None, "bad": [], "note": "", "label": "", "legs": None, "job": job, "time": when,
                                                      "hint": "a hint, not a verdict"})
        f, ok = it.get("field"), it.get("ok")
        if f == "verdict" and ok is None:
            e["note"] = e["note"] or str(it.get("rule") or "no verdict")
            continue
        if f == "legs":
            e["legs"] = it.get("value")
        if f == "note":
            e["note"] = str(it.get("value") or "")
            continue
        if f == "sheet":
            e["ok"] = ok if e["ok"] is not False else False
            e["label"] = it.get("label") or str(it.get("value") or "")
            e["note"] = it.get("note") or str(it.get("value") or "")
            if it.get("legs") is not None:
                e["legs"] = it.get("legs")
            if it.get("defects"):
                e["defects"] = list(it["defects"])
            continue
        if ok is False:
            e["ok"] = False
            e["bad"].append(FIELD_WORDS.get(f, f) + ((" " + str(it.get("value"))) if f == "face" else ""))
        elif ok is True and e["ok"] is None:
            e["ok"] = True
    for per in out.values():
        for e in per.values():
            if not e["label"]:
                if e["ok"] is False:
                    e["label"] = ", ".join(dict.fromkeys(e["bad"]))[:48] or (e["note"][:48] if e["note"] else "flagged")
                elif e["ok"] is True:
                    e["label"] = "fine"
                else:
                    e["label"] = "no verdict"
            e.pop("bad", None)
    return out


def on_findings(job, info):
    """An evaluate job landed: its model findings written per frame into the frames store (qa.eyes on the version each
    frame showed). Returns {written, frames, line}; never raises (a landing must not fail on the store)."""
    try:
        path = (info or {}).get("findings")
        if not path:
            return {"written": 0}
        p = path if os.path.isabs(path) else os.path.join(ROOT, path)
        with open(p, "r", encoding="utf-8") as f:
            rec = json.load(f)
        look = rec.get("look") or {}
        kind, cid, code = look.get("kind"), look.get("id"), look.get("code")
        if _check(str(kind), str(cid), str(code)):
            return {"written": 0, "error": "no look on the findings"}
        when = rec.get("time") or _now()
        jid = (job or {}).get("id") or rec.get("job")
        ents = _entries(rec.get("items"), jid, when)
        lk = FS.Look(kind, cid, code)
        n = 0
        for (group, slot, vid), per in ents.items():
            base, view = group.split("/", 1)
            g = FS.Group(lk, base, view)
            if not g.exists():
                continue
            v = g.version(slot, vid)
            if not v:
                continue
            qa = dict(v.get("qa") or {})
            prev = [e for e in (qa.get("eyes") or []) if isinstance(e, dict) and not (e.get("job") == jid and e.get("eye") in per)]
            qa["eyes"] = (prev + list(per.values()))[-KEEP:]
            g.update_version(slot, vid, qa=qa)
            n += 1
        line = ((rec.get("eyes") or {}).get("gemini") or {}).get("line") or ""
        out = {"written": n, "line": line}
        if rec.get("gemini_error"):   # Garry: the fallback to the local model surfaced as an error
            out.update(gemini_error=rec["gemini_error"], eye=rec.get("eye"), fallback_line=(rec.get("fallback") or {}).get("line"),
                       fallback_frames=(rec.get("fallback") or {}).get("frames"))
        return out
    except Exception as e:   # noqa: BLE001
        return {"written": 0, "error": "%s: %s" % (type(e).__name__, e)}


# ---------------------------------------------------------------- what the eyes say of a look now

def latest_by_eye(qa):
    """{eye: the newest entry} of a version's qa (qa.eyes, and the old local button's qa.vision as a Local entry)."""
    out = {}
    for e in (qa or {}).get("eyes") or []:
        if isinstance(e, dict) and e.get("eye"):
            if e["eye"] not in out or str(e.get("time") or "") >= str(out[e["eye"]].get("time") or ""):
                out[e["eye"]] = e
    vis = (qa or {}).get("vision")
    if isinstance(vis, dict) and isinstance(vis.get("answer"), dict):
        a = vis["answer"]
        bad = [FIELD_WORDS.get(k, k) for k in ("broken", "ghost", "colour") if a.get(k) is True]
        e = {"eye": "local", "name": "Local", "model": vis.get("model"), "ok": not bad, "label": ", ".join(bad) or "fine", "note": str(a.get("note") or ""),
             "time": vis.get("time"), "hint": "a hint, not a verdict", "button": True}
        if "local" not in out or str(e.get("time") or "") > str(out["local"].get("time") or ""):
            out["local"] = e
    return out


def look_eyes(kind, cid, code):
    """Per group of the look: the frames (the versions shown now) each eye flags, both, and one line for the card."""
    err = _check(kind, cid, code)
    if err:
        return {"ok": False, "error": err}
    lk = FS.Look(kind, cid, code)
    groups = {}
    for base, view, key, n in FS.groups_of(lk):
        g = FS.Group(lk, base, view)
        if not g.exists():
            continue
        label = "%s/%s" % (base, view)
        rec = {"gemini": [], "local": [], "both": [], "seen": {"gemini": 0, "local": 0}, "notes": {}}
        for k in range(g.n):
            v, _ = g.effective(k)
            if not v:
                continue
            le = latest_by_eye(v.get("qa") or {})
            for eye in ("gemini", "local"):
                if eye in le:
                    rec["seen"][eye] += 1
                    if le[eye].get("ok") is False:
                        rec[eye].append(k)
                        rec["notes"]["%s/%d" % (eye, k)] = le[eye].get("label") or ""
            if k in rec["gemini"] and k in rec["local"]:
                rec["both"].append(k)
        if rec["seen"]["gemini"] or rec["seen"]["local"]:
            groups[label] = rec
    parts = []
    for eye in ("gemini", "local"):
        fl = [(lab, r[eye]) for lab, r in groups.items() if r[eye]]
        seen = sum(r["seen"][eye] for r in groups.values())
        if fl:
            n = sum(len(s) for _, s in fl)
            parts.append("%s flagged %d frame%s in %s" % (EYE_NAMES[eye], n, "" if n == 1 else "s", ", ".join(lab for lab, _ in fl)))
        elif seen:
            parts.append("%s flagged nothing (%d frame%s seen)" % (EYE_NAMES[eye], seen, "" if seen == 1 else "s"))
    both = sum(len(r["both"]) for r in groups.values())
    if both:
        parts.append("both flag %d" % both)
    return {"ok": True, "kind": kind, "id": cid, "code": code, "groups": groups, "line": "; ".join(parts), "today": VE.agy_today()}


# ---------------------------------------------------------------- the routes

def api_get(h, srv, parts, query=None):
    """parts after /api/: ["eyes"] | ["eyes", "look", kind, id, code]."""
    if parts == ["eyes"]:
        return h._send(200, status())
    if len(parts) == 5 and parts[1] == "look":
        res = look_eyes(parts[2], parts[3], parts[4])
        return h._send(200 if res.get("ok") else 400, res)
    return h._error(404, "eyes paths are /api/eyes and /api/eyes/look/<kind>/<id>/<code>")


def api_post(h, srv, parts, body=None):
    """parts after /api/eyes/: ["check"]."""
    body = body if isinstance(body, dict) else {}
    if parts == ["check"]:
        res = check_look(srv, body)
        return h._send(200 if res.get("ok") else 400, res)
    return h._error(404, "unknown eyes route")
