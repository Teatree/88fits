"""The loop's planner (pass 96, lane LOOP; the assessment's AI-04 / AN-12): ONE op per iteration from the findings,
cheapest first, a pure function of the request record and the findings (nothing read from disk but methods.json's
repair rule; nothing written). REQ's step function runs it: `next_op(record, findings) -> op | None`; None = nothing
more to do on its own (the gates passed, or the budget leaves no move) -> waiting for Garry's approval.

The order:
  1. no findings for the last landed job                 -> ask (an evaluate job; the findings are re-made after every change)
  2. the hard gates pass (no measured failure)            -> select_provisional once (the effective versions staged as the winner), then None
  3. a hard finding on frames of a group with a clip
     and a driver (repairable)                            -> repair of those slots (spans), the profile's first rung; when the previous
                                                            repair of the same slots did not lower their hard count, the next rung
                                                            (single -> double), after the last rung -> reroll_view of that view
  4. a hard finding on a still (geometry: empty, touches-edge)
     or on frames of a procedural group (no clip/driver)  -> requeue of the look job with a prompt edit from DEFECT_WORDS and a new seed
  5. a view whose walk failed twice (two ops on that group
     without improvement)                                 -> reroll_view
  6. only advisory findings (the models') remain          -> select_provisional then None
Pass 98 (lane GEMINI; Garry: "just use Gemini first ... the local as backups"): a request stamped `eyes.tier2`
(requests.create, from request_defaults.json tiers["2"] = antigravity) asks tiers [0, 1, 2] every time: tier 0 on every
frame, Gemini on a sheet of the flagged frames + a clean one a group, the local model only on the frames of a Gemini call
that failed (vision_eval's fallback). Before select_provisional, findings made without tier 2 get one ask [0, 1, 2]
first. What a Gemini finding may drive (the blind bench: legs 2/11, ghost 22/25, face 21/28): a ghost, a smear or a
wrong / missing face (`defects` on the item) counts; a leg count (or another defect) counts only where tier 0's
silhouette or footprint flag is on the same frame; a leg count alone is a badge. Counting frames (and frames both eyes
flag, when both actually ran) put their group first among the repairs; with the hard gates passing, they earn one repair
of a repairable group (never twice on the same slots). A record without `eyes` plans exactly as pass 96.
The plateau rule: never the same op twice in a row on the same target (op + group + slots): the next rung instead, else
the next cheaper-to-dearer move, else select_provisional. Budget units are checked here before an op is proposed and
counted by REQ's step (requests.count_op) when it is dispatched.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)

METHODS_JSON = os.path.join(HERE, "methods.json")
ESCALATION_DEFAULT = ["single", "double", "reroll_view"]
PROFILE_DEFAULT = {"window": "single", "frames": 13, "strength": 1.0, "steps": 4, "lora": True}
HARD_FRAME_FIELDS = ("empty", "footprint", "jump", "seam", "silhouette")
STILL_FIELDS = ("empty", "touches-edge", "unreadable")
# the defect -> words table (a still-level failure's requeue): short, generic, no counts the eyes cannot check
DEFECT_WORDS = {
    "legs": "every leg fully drawn and attached, the right number of legs, no extra limbs",
    "ghost": "no ghost limbs, no faint or see-through duplicates of any part",
    "face": "a clear face on the head with two eyes, no skull, no second face",
    "smear": "crisp clean line art, no blurred or smeared parts",
    "empty": "one whole figure centred in the frame, clearly visible against the flat background",
    "touches-edge": "the whole figure well inside the frame with a clear margin on every side, nothing cut by the border",
    "broken": "every limb, the head and the body whole and attached, nothing cut, doubled or missing",
    "colour": "one consistent palette over the whole figure, no patch of a foreign colour",
    "silhouette": "a clean readable silhouette, the limbs in natural poses",
    "footprint": "the figure the same size and in the same place in every frame",
    "jump": "smooth continuous motion between frames",
    "seam": "a walk cycle that loops seamlessly",
}
SEED_STEP = 7919   # gen_art.render's own stride between tries: a new seed the painter has not tried


def repair_profile(method):
    """methods.json's `repair.profile` and `repair.escalation` of a method (GATES writes them from G1's benchmark), with
    the built-in defaults where they are absent."""
    prof, esc = dict(PROFILE_DEFAULT), list(ESCALATION_DEFAULT)
    try:
        with open(METHODS_JSON, "r", encoding="utf-8") as f:
            for m in (json.load(f).get("methods") or []):
                if isinstance(m, dict) and str(m.get("id")) == str(method or "") and isinstance(m.get("repair"), dict):
                    r = m["repair"]
                    if isinstance(r.get("profile"), dict):
                        prof.update(r["profile"])
                    if isinstance(r.get("escalation"), list) and r["escalation"]:
                        esc = [str(x) for x in r["escalation"]]
                    break
    except (OSError, ValueError):
        pass
    return {"profile": prof, "escalation": esc}


def next_rung(escalation, rung):
    """The rung after `rung` in the escalation list (None after the last, or when the ladder is empty)."""
    esc = list(ESCALATION_DEFAULT if escalation is None else escalation)
    if not esc:
        return None
    if rung not in esc:
        return esc[0]
    i = esc.index(rung)
    return esc[i + 1] if i + 1 < len(esc) else None


# ---------------------------------------------------------------- reading the record and the findings

def _iterations(record):
    return [it for it in ((record or {}).get("iterations") or []) if isinstance(it, dict)]


def _last_op(record):
    its = _iterations(record)
    return (its[-1].get("op") or {}) if its else {}


def _budget_left(record, unit, group=None):
    b, s = (record or {}).get("budget") or {}, (record or {}).get("spent") or {}
    cap = b.get(unit)
    if cap is None:
        return 1.0
    if unit == "repair_rounds":
        rr = s.get("repair_rounds") or {}
        used = int(rr.get(str(group or "*"), 0)) if isinstance(rr, dict) else int(rr or 0)
    else:
        used = s.get(unit) or 0
    return float(cap) - float(used)


def _target(record, **extra):
    a = (record or {}).get("asset") or {}
    t = {"kind": a.get("kind"), "id": a.get("id"), "code": a.get("code")}
    t.update({k: v for k, v in extra.items() if v is not None})
    return t


def _op(verb, record, why, args=None, **target):
    return {"op": verb, "target": _target(record, **target), "args": args or {}, "why": why}


def findings_fresh(record, findings):
    """Whether the findings describe the look as it stands: they belong to the last landed job of the request (the last
    iteration's op was `ask` and its job is the findings' job), or no iteration ran yet (a look job just landed:
    nothing is fresh until an evaluate ran)."""
    if not isinstance(findings, dict) or not findings.get("items") and not findings.get("gates"):
        return False
    its = _iterations(record)
    if not its:
        return False
    last = its[-1]
    if (last.get("op") or {}).get("op") != "ask":
        return False
    fj, lj = findings.get("job"), last.get("job")
    return (not fj or not lj) or fj == lj


def hard_items(findings):
    return [it for it in (findings.get("items") or []) if it.get("kind") == "measured" and it.get("ok") is False]


def _spans(slots):
    """Consecutive slots grouped: [3, 4, 5, 9] -> [[3, 4, 5], [9]]."""
    out = []
    for s in sorted(set(int(x) for x in slots)):
        if out and s == out[-1][-1] + 1:
            out[-1].append(s)
        else:
            out.append([s])
    return out


def _hard_by_group(findings):
    """{group label: {slot: [fields]}} of the measured failures on frames; the stills' under the key None."""
    out = {}
    for it in hard_items(findings):
        g = it.get("group")
        if g:
            out.setdefault(g, {}).setdefault(int(it.get("slot") or 0), []).append(str(it.get("field")))
        else:
            out.setdefault(None, {}).setdefault(str(it.get("image") or "still"), []).append(str(it.get("field")))
    return out


def _group_info(findings, label):
    for g in (findings.get("groups") or []):
        if g.get("label") == label:
            return g
    return {}


def _ops_on_group(record, group):
    """The repair / reroll_view ops on a group, newest first, with the facts the planner wrote on them: `slots`, `rung`,
    `hard_before` (the hard count on the op's slots when it was proposed) and `improved_prev` (whether the op before it
    on this group had lowered the count, judged when this op was proposed). REQ keeps the op whole on the iteration, so
    the facts are read from the op (or from the iteration when the step copied them there)."""
    out = []
    for it in reversed(_iterations(record)):
        op = it.get("op") or {}
        t = op.get("target") or {}
        if op.get("op") not in ("repair", "reroll_view"):
            continue
        a = op.get("args") or {}
        g = t.get("group") or ("%s/%s" % (a.get("base") or "run", a.get("view") or "") if op.get("op") == "reroll_view" else "")
        if g != group:
            continue
        out.append({"verb": op["op"], "slots": [int(s) for s in (t.get("slots") or [])], "rung": a.get("rung") or ("single" if op["op"] == "repair" else None),
                    "hard_before": it.get("hard_before", op.get("hard_before")), "improved_prev": it.get("improved_prev", op.get("improved_prev"))})
    return out


def _ladder(record, findings, group, esc):
    """What the previous ops on a group say: (prev, improved, streak): the newest op, whether it lowered the hard count on
    its own slots (None when none ran), and how many ops in a row ended without improvement (the newest judged on the
    findings, the earlier ones on what was recorded when their successor was proposed)."""
    ops = _ops_on_group(record, group)
    if not ops:
        return None, None, 0
    prev = ops[0]
    if prev["hard_before"] is not None and prev["slots"]:
        improved = _hard_count(findings, group, prev["slots"]) < int(prev["hard_before"])
    else:
        improved = False   # nothing recorded = nothing shown to have improved
    streak = 0
    if not improved:
        streak = 1
        for p in ops:
            if p.get("improved_prev") is False:
                streak += 1
            else:
                break
    return prev, improved, streak


def _same_as_last(record, op):
    """The plateau rule's test: the same verb on the same group and slots as the last iteration."""
    last = _last_op(record)
    if not last or last.get("op") != op.get("op"):
        return False
    lt, t = last.get("target") or {}, op.get("target") or {}
    if (lt.get("group") or "") != (t.get("group") or ""):
        return False
    if sorted(lt.get("slots") or []) != sorted(t.get("slots") or []):
        return False
    la, a = last.get("args") or {}, op.get("args") or {}
    return la.get("rung") == a.get("rung") and la.get("view") == a.get("view") and la.get("words") == a.get("words")


def _hard_count(findings, group, slots):
    return sum(1 for it in hard_items(findings) if it.get("group") == group and int(it.get("slot") or 0) in set(slots))


def _seed_for(record):
    """A seed the painter has not tried: the look job's seed moved by the render stride per re-roll so far."""
    s = (record or {}).get("spent") or {}
    base = int(((record or {}).get("asset") or {}).get("seed") or 0)
    return base + SEED_STEP * (int(s.get("rerolls") or 0) + 1)


# ---------------------------------------------------------------- the planner

def next_op(record, findings):
    """One op or None. See the module's docstring for the order."""
    record = record or {}
    last = _last_op(record)
    # 2/6 the provisional winner is chosen: nothing more on its own
    if record.get("provisional") and last.get("op") in ("select_provisional", "stop"):
        return None
    if last.get("op") == "stop":
        return None
    # 1 fresh findings first
    if not findings_fresh(record, findings):
        if last.get("op") == "ask":
            # the evaluate job did not yield findings: do not loop on asking
            return _select_or_none(record, "the evaluator gave no findings: the frames as they stand are the provisional winner")
        if _budget_left(record, "evaluator_calls") <= 0:
            return _select_or_none(record, "no evaluator calls left: the frames as they stand are the provisional winner")
        if _tier2_on(record):   # pass 98 (lane GEMINI; Garry: Gemini first, the local model only when Gemini fails)
            return _op("ask", record, ("the look landed" if _look_just_landed(record) else "the look changed") + ": flag every frame (tier 0), Gemini on a sheet of the "
                       "flagged ones and a clean one a group (the local model only if Gemini fails)", {"tiers": [0, 1, 2], "scope": "flagged"})
        return _op("ask", record, "the look changed: flag every frame again (tier 0, the local eye on the flagged ones)", {"tiers": [0, 1]})
    gates = findings.get("gates") or {}
    if int(gates.get("hard_failures") or 0) == 0:
        agreed = _agreed_repair(record, findings)   # pass 98 (lane GEMINI): both eyes flag a frame: one repair of it
        if agreed:
            return agreed
        seen = _gemini_repair(record, findings)   # pass 98: Gemini's trusted defects (ghost, smear, face): one repair
        if seen:
            return seen
        return _decide(record, "the hard gates pass (only advisory findings remain): the effective frames are the provisional winner", findings)
    hard = _hard_by_group(findings)
    # 3 hard findings on frames of a repairable group -> repair (spans), the rung from the escalation
    candidates = []
    for group, slots in hard.items():
        if group is None:
            continue
        gi = _group_info(findings, group)
        if not gi.get("repairable", True):
            continue
        prof = repair_profile(gi.get("method"))
        esc = prof["escalation"]
        first = esc[0] if esc and esc[0] != "reroll_view" else "single"
        all_slots = sorted(slots)
        fields = ", ".join(sorted({f for fs in slots.values() for f in fs}))
        prev, improved, streak = _ladder(record, findings, group, esc)
        if len(all_slots) >= max(2, int(gi.get("n") or 2)):
            candidates.append(("reroll_view", group, all_slots, None, "every frame of %s fails: that is a new clip, not a repair" % group, improved))
            continue
        if streak >= 2:
            # rule 5: the view's walk failed twice without improvement: roll it again
            candidates.append(("reroll_view", group, all_slots, None, "%s failed twice without improvement (%s): roll the view's walk again" % (group, fields), improved))
            continue
        if prev is None:
            rung, why = first, "hard findings on %s slots %s (%s): repair them (%s window)" % (group, ",".join(str(s) for s in all_slots), fields, first)
        elif prev["verb"] == "reroll_view":
            # a fresh clip: the ladder starts again
            rung, why = first, "%s re-rolled, still %s on slots %s: repair them (%s window)" % (group, fields, ",".join(str(s) for s in all_slots), first)
        elif improved:
            rung = prev["rung"] or first   # it helped: the same rung again on what is left
            why = "the %s repair of %s lowered its hard count %d -> %d: once more on slots %s" % (rung, group, int(prev["hard_before"]), _hard_count(findings, group, prev["slots"]), ",".join(str(s) for s in all_slots))
        else:
            rung = next_rung(esc, prev["rung"])
            if rung is None or rung == "reroll_view":
                candidates.append(("reroll_view", group, all_slots, None, "the %s repair of %s did not improve its frames: the next rung is a re-roll of the view" % (prev["rung"], group), improved))
                continue
            why = "the %s repair of %s did not improve its frames (%s hard before, %d now): the next rung, %s" % (
                prev["rung"], group, prev["hard_before"] if prev["hard_before"] is not None else "?", _hard_count(findings, group, prev["slots"] or all_slots), rung)
        candidates.append(("repair", group, all_slots, rung, why, improved))
    # cheapest first: repairs before re-rolls; within repairs the lower rung first
    order = {"repair": 0, "reroll_view": 1}
    rung_order = {"single": 0, "double": 1, None: 2}
    agreed_groups = {g for g, _ in (_agreed(findings) | _gemini_counts(findings))} if _tier2_on(record) else set()   # pass 98: the eyes agree -> first
    candidates.sort(key=lambda c: (order[c[0]], 0 if c[1] in agreed_groups else 1, rung_order.get(c[3], 2), c[1]))
    for verb, group, slots, rung, why, improved in candidates:
        if verb == "repair":
            if _budget_left(record, "repair_rounds", group) <= 0:
                continue
            op = _op("repair", record, why, {"rung": rung}, group=group, slots=slots)
        else:
            if _budget_left(record, "rerolls") <= 0:
                continue
            base, view = group.split("/", 1)
            op = _op("reroll_view", record, why, {"view": view, "base": base}, group=group, slots=slots)
        if _same_as_last(record, op):
            continue   # the plateau rule: never the same op twice in a row on the same target
        # the facts the next step reads back (REQ keeps the op whole): the hard count on these slots now, and whether
        # the previous op on this group lowered its own
        op["hard_before"] = _hard_count(findings, group, slots)
        if improved is not None:
            op["improved_prev"] = bool(improved)
        return op
    # 4 a still-level failure, or frames of a procedural group -> requeue with words and a new seed
    still_fields = []
    for img, fields in (hard.get(None) or {}).items():
        still_fields += fields
    proc_fields = []
    for group, slots in hard.items():
        if group is None:
            continue
        if not _group_info(findings, group).get("repairable", True):
            for fs in slots.values():
                proc_fields += fs
    defects = [f for f in still_fields + proc_fields if f in DEFECT_WORDS]
    if defects and _budget_left(record, "rerolls") > 0:
        words = ", ".join(dict.fromkeys(DEFECT_WORDS[f] for f in defects))
        op = _op("requeue", record, "a still-level failure (%s): the look painted again with the words and a new seed" % ", ".join(dict.fromkeys(defects)),
                 {"words": words, "seed": _seed_for(record)})
        if not _same_as_last(record, op):
            return op
    # nothing left the budget or the plateau rule allows: the best so far is the provisional winner
    return _decide(record, "no further move within the budget (or the same move would repeat): the frames as they stand are the provisional winner", findings)


# ---------------------------------------------------------------- pass 98 (lane GEMINI): tier 2 at the decision points

def _tier2_on(record):
    """Whether the request asks Gemini at its decision points (requests.create stamps `eyes.tier2`; absent = pass 96)."""
    return bool(((record or {}).get("eyes") or {}).get("tier2"))


def _look_just_landed(record):
    """No op yet (the request's look job landed), or the last op painted the look again (requeue, reroll_view)."""
    last = _last_op(record)
    return not last or last.get("op") in ("requeue", "reroll_view")


def _tier2_seen(findings):
    """The findings were made with tier 2 asked (whatever came of it: ran, refused by the cap, nothing in scope)."""
    try:
        return 2 in [int(t) for t in ((findings or {}).get("tiers") or [])]
    except (TypeError, ValueError):
        return False


TRUSTED = ("ghost", "smear", "face")   # the blind bench (pass 98): Gemini's ghost 22/25, face 21/28; legs 2/11 (never alone)
TIER0_SHAPE = ("silhouette", "footprint")   # the deterministic flags a Gemini leg count must agree with


def _gemini_counts(findings):
    """{(group, slot)} where a Gemini (tier 2) finding may count toward a repair: it names a trusted defect (ghost, smear,
    face), or it is a leg count / other defect AND tier 0's silhouette or footprint flag is on the same frame. A leg count
    alone is a badge only. Items without `defects` (pass 96's paid eye) never count."""
    shape = {(str(it.get("group")), int(it.get("slot"))) for it in (findings or {}).get("items") or []
             if it.get("kind") == "measured" and it.get("ok") is False and it.get("field") in TIER0_SHAPE and it.get("group") and it.get("slot") is not None}
    out = set()
    for it in (findings or {}).get("items") or []:
        if it.get("kind") != "model" or it.get("ok") is not False or int(it.get("tier") or 1) != 2 or not it.get("group") or it.get("slot") is None:
            continue
        kinds = it.get("defects") or []
        key = (str(it["group"]), int(it["slot"]))
        if any(k in TRUSTED for k in kinds) or (kinds and key in shape):
            out.add(key)
    return out


def _agreed(findings):
    """{(group, slot)} a tier-1 item and a COUNTING tier-2 item (_gemini_counts) both flag (ok false): only when both ran."""
    t1 = set()
    for it in (findings or {}).get("items") or []:
        if it.get("kind") != "model" or it.get("ok") is not False or not it.get("group") or it.get("slot") is None:
            continue
        if int(it.get("tier") or 1) != 2:
            t1.add((str(it["group"]), int(it["slot"])))
    return t1 & _gemini_counts(findings)


def _gemini_repair(record, findings):
    """One repair of the frames Gemini flags with a trusted defect (ghost, smear, face; a leg count only where tier 0's
    silhouette / footprint agrees), the gates passing; the same guards as the agreement repair."""
    return _agreed_repair(record, findings, _gemini_counts(findings),
                          "Gemini flags %s slots %s with a defect it sees well (ghost, smear or face): one repair of them (%s window; a hint the gates do not enforce)")


def _agreed_repair(record, findings, keys=None, words=None):
    """One repair of the slots both eyes flag in a repairable group (gates passing), cheapest group first; never twice on
    the same slots of a group, never past the group's repair_rounds. None when there is none to make."""
    if not _tier2_on(record):
        return None
    by_group = {}
    for g, s in (_agreed(findings) if keys is None else keys):
        by_group.setdefault(g, set()).add(s)
    for group in sorted(by_group):
        gi = _group_info(findings, group)
        if not gi or not gi.get("repairable", False):
            continue
        slots = sorted(by_group[group])
        if len(slots) >= max(2, int(gi.get("n") or 2)):
            continue
        if any(set(slots) <= set(p["slots"]) for p in _ops_on_group(record, group) if p["verb"] == "repair"):
            continue
        if _budget_left(record, "repair_rounds", group) <= 0:
            continue
        prof = repair_profile(gi.get("method"))
        esc = prof["escalation"]
        rung = esc[0] if esc and esc[0] != "reroll_view" else "single"
        op = _op("repair", record, (words or "both eyes (the local model and Gemini) flag %s slots %s: one repair of them (%s window; a hint the gates do not enforce)")
                 % (group, ",".join(str(s) for s in slots), rung), {"rung": rung}, group=group, slots=slots)
        if _same_as_last(record, op):
            continue
        op["hard_before"] = _hard_count(findings, group, slots)
        return op
    return None


def _decide(record, why, findings):
    """The decision point before select_provisional: with tier 2 on and the fresh findings made without it, one ask of
    tiers [0, 1, 2] first (evaluator calls permitting); else select_provisional (once), then None."""
    if _tier2_on(record) and not (record or {}).get("provisional") and findings_fresh(record, findings) and not _tier2_seen(findings)             and _budget_left(record, "evaluator_calls") > 0:
        return _op("ask", record, "a decision point: Gemini looks at the flagged frames and a clean one a group before the provisional winner is chosen",
                   {"tiers": [0, 1, 2], "scope": "flagged"})
    return _select_or_none(record, why, findings)


def _select_or_none(record, why, findings=None):
    """select_provisional once (the effective frames of every group as they stand), then None."""
    if (record or {}).get("provisional"):
        return None
    groups = {}
    for g in ((findings or {}).get("groups") or []):
        groups[g["label"]] = {"versions": {}}
    return _op("select_provisional", record, why, {"groups": groups})
