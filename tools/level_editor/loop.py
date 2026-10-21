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
        return _op("ask", record, "the look changed: flag every frame again (tier 0, the local eye on the flagged ones)", {"tiers": [0, 1]})
    gates = findings.get("gates") or {}
    if int(gates.get("hard_failures") or 0) == 0:
        return _select_or_none(record, "the hard gates pass (only advisory findings remain): the effective frames are the provisional winner", findings)
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
    candidates.sort(key=lambda c: (order[c[0]], rung_order.get(c[3], 2), c[1]))
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
    return _select_or_none(record, "no further move within the budget (or the same move would repeat): the frames as they stand are the provisional winner", findings)


def _select_or_none(record, why, findings=None):
    """select_provisional once (the effective frames of every group as they stand), then None."""
    if (record or {}).get("provisional"):
        return None
    groups = {}
    for g in ((findings or {}).get("groups") or []):
        groups[g["label"]] = {"versions": {}}
    return _op("select_provisional", record, why, {"groups": groups})
