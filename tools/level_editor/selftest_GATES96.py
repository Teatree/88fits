"""Pass 96, lane GATES (the gates G1 and G2): the VACE repair profile per method class and the blind calibration set.

Groups: the blind manifest's shape and blindness (tools/qa_bench/manifest.json: ids C01.., images under tools/dl/qa_bench,
no verdict in a name, a deterministic shuffle that is not the source order); qa_bench's scoring on a canned result (legs /
ghost / face right, the miss and false-alarm rates, no verdict never "ok", the weak labels apart, the run-to-run agreement);
the tier table's shape (request_defaults.json `tiers`: 0 deterministic, 1 a local model on flagged frames + a sample at zero
cost, 2 the cloud eye on sheets with a 0.0 ceiling); vace_repair's profile reading (profile_for: the method's own rule, the
class's representative, the built-in default; explicit arguments over the profile over the clip's wan; `--help` keeps every
old argument), next_rung, the partial mask helpers, the window plan unchanged; vace_bench's plan, the lone / span split, the
colour distance, the checks on VACE95's temporary world, choose() (ties to the cheaper, under PASS_MIN = conditional +
reroll_view) and write_profiles() on a temp copy of methods.json (one line per rule changes, every other line byte-identical);
the profile keys on every method of the real methods.json. Nothing under game/ or tools/dl is written.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
for p in (HERE, TOOLS):
    if p not in sys.path:
        sys.path.insert(0, p)

HINT_WORDS = ("ghost", "leg", "face", "skull", "pick", "clean", "lost", "smear", "bad", "good", "wrong", "missing", "defect")
OLD_ARGS = ("--job", "--kind", "--id", "--code", "--anim", "--view", "--slots", "--prompt", "--negative", "--seed", "--window", "--size", "--steps", "--cfg",
            "--shift", "--strength", "--guide", "--free-fill", "--no-stage", "--dry-run", "--out")


def _canned_results(man, variant):
    """A fake run over the manifest: every strong defect caught except two misses (a no-verdict and an 'ok'), one false alarm
    on a clean case; variant 'b' flips one more case so the agreement is measurable."""
    res = {}
    strong = [c for c in man["cases"] if c["strength"] == "strong"]
    defects = [c for c in strong if c["verdict"].get("clean") is False]
    clean = [c for c in strong if c["verdict"].get("clean") is True]
    miss_ok, miss_empty = defects[0], defects[1]
    alarm = clean[0]
    for c in man["cases"]:
        v = c["verdict"]
        exp = c.get("expect_legs") or 8
        if c is miss_empty:
            res[c["id"]] = {"parsed": {}, "seconds": 1.0}   # no verdict
            continue
        if c is miss_ok:
            ans = {"legs_total": exp, "ghost_legs": False, "smears": False, "face": "ok"}
        elif c["strength"] != "strong":
            ans = {"legs_total": exp, "ghost_legs": False, "smears": False, "face": "ok"}
        elif v.get("clean") is False:
            ans = {"legs_total": v["legs"] if v.get("legs") is not None else exp, "ghost_legs": bool(v.get("ghost")), "smears": bool(v.get("smear")),
                   "face": "missing" if v.get("face") else "ok"}
            if not (ans["legs_total"] != exp or ans["ghost_legs"] or ans["smears"] or ans["face"] != "ok"):
                ans["smears"] = True   # a defect recorded only as 'worse': flagged as a smear
        else:
            ans = {"legs_total": v["legs"] if v.get("legs") is not None else exp, "ghost_legs": False, "smears": False, "face": "ok"}
            if c is alarm:
                ans["ghost_legs"] = True
        if variant == "b" and c is clean[1]:
            ans = dict(ans, smears=True)
        res[c["id"]] = {"parsed": ans, "seconds": 1.0}
    return {"v": 1, "backend": "openai_chat", "model": "fake-vl", "rubric": "anchored", "total_seconds": float(len(res)), "dollars": 0.0, "results": res}


def checks(check, run_node, server):
    import numpy as np
    from PIL import Image
    import frames_store as FS
    import vace_repair as VR
    import vace_bench as VB
    import qa_bench as QB

    # ---- G2: the manifest's shape and blindness
    man = QB.manifest()
    cases = man.get("cases") or []
    check(len(cases) >= 30 and all(c["id"] == "C%02d" % (k + 1) for k, c in enumerate(cases)), "the manifest: %d cases with consecutive blind ids C01.." % len(cases))
    check(all(set(("id", "image", "kind", "species", "expect_legs", "verdict", "strength", "source", "rater", "origin")) <= set(c) for c in cases), "every case: id, image, kind, species, expect_legs, verdict, strength, source, rater, origin")
    check(all(c["kind"] in ("still", "frame") and c["strength"] in ("strong", "weak") and "clean" in c["verdict"] for c in cases), "kinds still | frame, strengths strong | weak, a clean key in every verdict")
    check(all(c["image"] == "tools/dl/qa_bench/%s.png" % c["id"] for c in cases), "the images live under tools/dl/qa_bench (ignored) under the blind id")
    check(all(not any(w in os.path.basename(c["image"]).lower() for w in HINT_WORDS) for c in cases), "no hint word in any image name")
    strong = [c for c in cases if c["strength"] == "strong"]
    check(sum(1 for c in strong if c["verdict"]["clean"] is False) >= 15 and sum(1 for c in strong if c["verdict"]["clean"] is True) >= 10, "the strong set holds at least 15 defects and 10 clean cases")
    check(len({c["species"] for c in cases}) >= 3 and all(c["expect_legs"] == QB.EXPECT_LEGS[c["species"]] for c in cases), "three species with their expected leg counts")
    again = QB.prepare(write=False, quiet=True)
    check([c["origin"] for c in again["cases"]] == [c["origin"] for c in cases], "prepare is deterministic: the same shuffle again")
    check([c["origin"] for c in cases] != ["tools/dl/" + s["origin"] for s in QB.SOURCES][: len(cases)], "the blind order is not the source order")
    for rub in (QB.rubric(cases[0]), QB.rubric(cases[0], unanchored=True)):
        check("JSON" in rub and "legs_total" in rub and "ghost_legs" in rub and "smears" in rub and "face" in rub, "the rubric asks for the JSON fields")
    check("exactly" in QB.rubric({"species": "spider"}) and "exactly" not in QB.rubric({"species": "spider"}, unanchored=True) and "do not assume" in QB.rubric({"species": "spider"}, unanchored=True),
          "the anchor names the species' count; --unanchored drops it")
    check(not any(os.path.basename(c["origin"]).replace(".png", "") in QB.RUBRIC for c in cases), "no case name reaches the rubric")

    # ---- G2: the scoring on a canned result
    tmp = tempfile.mkdtemp(prefix="le_gates96_")
    try:
        pa, pb = os.path.join(tmp, "a.json"), os.path.join(tmp, "b.json")
        for p, variant in ((pa, "a"), (pb, "b")):
            with open(p, "w", encoding="utf-8") as f:
                json.dump(_canned_results(man, variant), f)
        sa = QB.score_file(pa, man)
        n_def = sum(1 for c in strong if c["verdict"]["clean"] is False)
        n_cln = len(strong) - n_def
        check(sa["misses"] == [2, n_def] and abs(sa["miss_rate"] - 2.0 / n_def) < 1e-3, "two misses of %d defects: miss rate %s" % (n_def, sa["miss_rate"]))
        check(sa["false_alarms"] == [1, n_cln] and abs(sa["false_alarm_rate"] - 1.0 / n_cln) < 1e-3, "one false alarm of %d clean: %s" % (n_cln, sa["false_alarm_rate"]))
        check(sa["no_verdict"] == 1 and sa["cases"][[c for c in strong if c["verdict"]["clean"] is False][1]["id"]]["outcome"] == "MISSED", "an empty answer is no verdict: a miss, never ok")
        legs_cases = [c for c in strong if c["verdict"].get("legs") is not None]
        check(sa["legs"][1] == len(legs_cases) and sa["legs"][0] >= len(legs_cases) - 2, "legs scored on the %d cases with a recorded count: %s" % (len(legs_cases), sa["legs"]))
        check(sa["ghost"][1] == sum(1 for c in strong if c["verdict"].get("ghost") is not None) and sa["face"][1] == sum(1 for c in strong if c["verdict"].get("face") is not None), "ghost and face scored where recorded")
        weak = [c for c in cases if c["strength"] == "weak"]
        check(sum(sa["weak"][k][1] for k in sa["weak"]) == len(weak) and all(k not in [x for x in sa["cases"] if "outcome" in sa["cases"][x]] for k in [c["id"] for c in weak]), "weak labels are reported apart, never in the miss rate")
        sb = QB.score_file(pb, man)
        ag = QB.agreement(sa, sb)
        check(ag["cases"] == len(cases) and ag["flag"] < 1.0 and ag["all_fields"] < 1.0 and ag["flag"] >= ag["all_fields"], "the agreement of two runs: flag %s, all fields %s" % (ag["flag"], ag["all_fields"]))
        check(QB.flagged_of({"legs_total": 9, "ghost_legs": False, "smears": False, "face": "ok"}, 8)["flagged"] and not QB.flagged_of({"legs_total": 8, "ghost_legs": False, "smears": False, "face": "ok"}, 8)["flagged"]
              and QB.flagged_of({}, 8) is None and QB.flagged_of({"legs_total": 8, "face": "wrong"}, 8)["face_bad"], "flagged_of: a wrong count, a wrong face flag; an empty answer is None")
        check(QB.parse_json("```json\n{\"a\": 1}\n```") == {"a": 1} and QB.parse_json("no json here") == {}, "parse_json: a fenced object, else nothing")
        # the tier table from a canned scores record
        canned = {"made": "t", "strong": len(strong), "defects": n_def, "clean": n_cln, "per_model": [
            {"backend": "openai_chat", "model": "slow-but-better", "rubric": "anchored", "miss_rate": 0.5, "false_alarm_rate": 0.1, "seconds_per_image": 8.0, "runs": 2, "agreement": None, "dollars": 0.0},
            {"backend": "openai_chat", "model": "fast-but-blind", "rubric": "anchored", "miss_rate": 0.8, "false_alarm_rate": 0.0, "seconds_per_image": 1.0, "runs": 2, "agreement": None, "dollars": 0.0}]}
        tt = QB.tiers(write=False, scores=canned, quiet=True)
        check(tt["0"] == "deterministic" and tt["1"]["model"] == "slow-but-better" and tt["1"]["backend"] == "openai_chat" and tt["1"]["on"] == "flagged+sample",
              "tier 1 = the local model with the best miss rate")
        check(tt["2"]["backend"] == "anthropic" and tt["2"]["on"] == "sheets" and tt["2"]["ceiling_dollars"] == 0.0 and tt["2"]["model"], "tier 2 on sheets, off at ceiling 0.0, a pinned model id")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- the tier table as written
    rd = os.path.join(HERE, "request_defaults.json")
    doc = json.load(open(rd, encoding="utf-8")) if os.path.isfile(rd) else {}
    t = doc.get("tiers") or {}
    check(t.get("0") == "deterministic" and isinstance(t.get("1"), dict) and isinstance(t.get("2"), dict), "request_defaults.json carries the tier table (0, 1, 2)")
    check(t.get("1", {}).get("backend") == "openai_chat" and t.get("1", {}).get("model") and t.get("1", {}).get("on") == "flagged+sample", "tier 1: a local openai_chat model on flagged frames + a sample")
    check(t.get("2", {}).get("on") == "sheets" and float(t.get("2", {}).get("ceiling_dollars", 1)) == 0.0 and t.get("2", {}).get("backend") in ("anthropic", "gemini"), "tier 2: sheets only, ceiling 0.0 (off)")
    check(isinstance(t.get("_measured"), dict) and t["_measured"].get("models"), "the measured numbers travel with the table")

    # ---- G1: vace_repair's profile reading and next_rung
    rules = {"creature_ctl": {"vace": "yes", "fill": "cell", "profile": {"window": "single", "frames": 13, "strength": 0.7, "steps": 4, "cfg": 1.0, "lora": True}, "escalation": ["single", "double", "reroll_view"]},
             "creature_pose2": {"vace": "conditional", "fill": "cell", "profile": {"window": "double", "frames": 25, "strength": 1.0, "steps": 20, "cfg": 3.5, "lora": False}, "escalation": ["double", "reroll_view"]},
             "creature_proc": {"vace": "no", "fill": "still", "escalation": ["reroll_view"]}}
    p = VR.profile_for("creature_ctl", rules=rules)
    check(p["window"] == "single" and p["strength"] == 0.7 and p["steps"] == 4 and p["lora"] is True and p["class"] == "ctl" and p["source"] == "methods.json creature_ctl", "the method's own profile")
    p = VR.profile_for("hero_puppet", rules=rules)
    check(p["class"] == "ctl" and p["window"] == "single" and p["source"] == "methods.json creature_ctl", "a method without a profile follows its class's representative")
    p = VR.profile_for("creature", {"driver": {"kind": "pose"}, "clip": {"key": "x"}}, rules=rules)
    check(p["class"] == "pose" and p["window"] == "double" and p["steps"] == 20 and p["lora"] is False and p["cfg"] == 3.5, "an old look's 'creature' method is classed by its driver's kind")
    p = VR.profile_for("creature_proc", rules=rules)
    check(p["window"] == "auto" and p["strength"] == 1.0 and p["steps"] == 4 and p["escalation"] == ["reroll_view"] and p["source"] == "default", "a rule without a profile: the defaults, its own escalation")
    p = VR.profile_for("creature_free2", rules={})
    check(p == dict(VR.DEFAULT_PROFILE, escalation=list(VR.DEFAULT_ESCALATION), **{"class": "free", "method": "creature_free2", "source": "default"}), "no rules at all: pass 95's defaults")
    check(VR.class_of(None, {}) == "cell" and VR.class_of("hero", {"clip": {"key": "k"}}) == "free" and VR.class_of("item_icon") == "cell" and VR.class_of("creature_ctl") == "ctl", "class_of")
    esc = {"escalation": ["single", "double", "reroll_view"]}
    check([VR.next_rung(esc, r) for r in (None, "single", "double", "reroll_view", "bogus")] == ["single", "double", "reroll_view", None, None], "next_rung walks the rungs and ends in None")
    check(VR.next_rung(["reroll_view"]) == "reroll_view" and VR.next_rung(["reroll_view"], "reroll_view") is None and VR.next_rung(None) == "single", "next_rung on a plain list and on nothing")
    check(VR.parse_mask("5:0.1,0.5,0.45,1; 9: 0 0 0.5 0.5") == {5: [0.1, 0.5, 0.45, 1.0], 9: [0.0, 0.0, 0.5, 0.5]} and VR.clean_mask({"5": [0.9, 0.2, 0.1, 0.8], "40": [0, 0, 1, 1], "x": [0, 0, 1, 1], "6": [0.5, 0.5, 0.5, 0.5]}, 12) == {5: [0.1, 0.2, 0.9, 0.8]},
          "parse_mask / clean_mask: fractions, ordered, clamped, bad slots dropped")
    m = VR.mask_image([0.25, 0.5, 0.75, 1.0], 64)
    a = np.asarray(m)[..., 0]
    check(a[40, 32] == 255 and a[10, 32] == 0 and a[40, 5] == 0, "mask_image: white inside the rectangle")
    kept = Image.new("RGB", (64, 64), (10, 200, 10))
    guide = Image.new("RGB", (64, 64), (128, 128, 128))
    pf = np.asarray(VR.partial_frame(kept, guide, [0.25, 0.5, 0.75, 1.0], 64))
    check(tuple(pf[40, 32]) == (128, 128, 128) and tuple(pf[10, 32]) == (10, 200, 10), "partial_frame: the guide inside, the kept frame outside")
    merged = VR.partial_merge(Image.new("RGBA", (64, 64), (255, 0, 0, 255)), Image.new("RGBA", (64, 64), (0, 0, 255, 255)), [0.25, 0.5, 0.75, 1.0], 64, feather=0)
    mm = np.asarray(merged)
    check(tuple(mm[40, 32]) == (0, 0, 255, 255) and tuple(mm[10, 32]) == (255, 0, 0, 255), "partial_merge: the new pixels inside, the original outside")
    check(len(VR.window_plan(12, True, "single")[0]) == 13 and len(VR.window_plan(12, True, "double")[0]) == 25 and VR.window_plan(12, True, "auto")[1] == "double"
          and VR.window_plan(24, True, "auto")[1] == "single" and len(VR.window_plan(8, False, "auto")[0]) == 9, "window_plan unchanged: single 13, double 25, auto = double for short loops")
    out = subprocess.run([sys.executable, os.path.join(TOOLS, "vace_repair.py"), "--help"], capture_output=True, text=True, cwd=ROOT)
    check(out.returncode == 0 and all(a in out.stdout for a in OLD_ARGS) and "--mask" in out.stdout and "--store" in out.stdout, "vace_repair --help lists every old argument and the new ones")

    # ---- vace_bench: the plan, the split, the colour distance, choose(), write_profiles() on a temp copy
    plan = VB.plan()
    ids = [r["id"] for r in plan]
    check(len(plan) == 27 and len(set(ids)) == 27 and sum(1 for r in plan if r["cls"] == "ctl" and not r.get("mask")) == 16 and sum(1 for r in plan if r.get("mask")) == 1
          and {r["cls"] for r in plan} == {"ctl", "pose", "free", "cell"}, "the matrix: 27 runs, 16 ctl, one mask, four classes")
    check([r["sampler"] for r in plan[:8]] == ["lora4"] * 8 and all(r["sampler"] == "steps20" for r in plan[-8:]), "the cheap runs first, the 20-step runs last")
    check(VB.classify_slots([3, 4, 5, 9], 12) == {3: "span", 4: "span", 5: "span", 9: "lone"} and VB.classify_slots([0, 11], 12)[0] == "span" and VB.classify_slots([0, 11], 12, loop=False)[0] == "lone",
          "lone = no redone neighbour (the loop wraps)")
    red = Image.new("RGBA", (16, 16), (255, 0, 0, 255))
    blue = Image.new("RGBA", (16, 16), (0, 0, 255, 255))
    check(VB.colour_dist(VB.colour_hist(red), VB.colour_hist(red)) == 0.0 and abs(VB.colour_dist(VB.colour_hist(red), VB.colour_hist(blue)) - 1.0) < 1e-9 and VB.alpha_area(red) == 256
          and VB.colour_hist(Image.new("RGBA", (4, 4), (0, 0, 0, 0))).sum() == 0, "colour_dist 0 for the same, 1 for disjoint colours; an empty picture an empty histogram")
    table = [dict(cls="ctl", window="single", strength=1.0, sampler="lora4", score=0.9, render_s=100.0), dict(cls="ctl", window="double", strength=1.0, sampler="lora4", score=0.91, render_s=150.0),
             dict(cls="ctl", window="double", strength=0.7, sampler="steps20", score=0.95, render_s=400.0), dict(cls="pose", window="single", strength=1.0, sampler="lora4", score=0.5, render_s=90.0),
             dict(cls="pose", window="double", strength=1.0, sampler="lora4", score=0.55, render_s=140.0), dict(cls="free", window="single", strength=1.0, sampler="lora4", score=0.8, render_s=90.0),
             dict(cls="free", window="double", strength=1.0, sampler="lora4", score=0.5, render_s=140.0)]
    ch = VB.choose(table)
    check(ch["ctl"]["profile"]["window"] == "double" and ch["ctl"]["profile"]["steps"] == 20 and ch["ctl"]["profile"]["lora"] is False and ch["ctl"]["profile"]["cfg"] == 3.5 and ch["ctl"]["reliable"]
          and ch["ctl"]["escalation"] == ["single", "double", "reroll_view"], "choose: the best score wins outright when it is more than a tie ahead; the ladder stays single -> double -> reroll_view")
    table2 = [t for t in table if not (t["cls"] == "ctl" and t["sampler"] == "steps20")]
    ch2 = VB.choose(table2)
    check(ch2["ctl"]["profile"]["window"] == "single" and ch2["ctl"]["escalation"] == ["single", "double", "reroll_view"], "choose: a tie within %.2f goes to the cheaper; the ladder is the fixed one" % VB.TIE)
    check(ch["pose"]["profile"] is not None and not ch["pose"]["reliable"] and ch["pose"]["escalation"] == ["reroll_view"], "a class under PASS_MIN: not reliable, escalate to a re-roll at once")
    check(ch["free"]["escalation"] == ["single", "double", "reroll_view"] and ch["free"]["other_window_score"] == 0.5 and ch["cell"]["profile"] is None and ch["cell"]["escalation"] == ["reroll_view"], "a reliable class keeps the fixed ladder whatever its window; a class without runs has no profile")
    tmp = tempfile.mkdtemp(prefix="le_gates96m_")
    try:
        src = os.path.join(HERE, "methods.json")
        dst = os.path.join(tmp, "methods.json")
        shutil.copyfile(src, dst)
        before = open(dst, "r", encoding="utf-8", newline="").read()
        summary = {"chosen": {"ctl": {"profile": {"window": "single", "frames": 13, "strength": 1.0, "steps": 4, "cfg": 1.0, "lora": True}, "escalation": ["single", "double", "reroll_view"], "reliable": True},
                              "pose": {"profile": {"window": "double", "frames": 25, "strength": 1.0, "steps": 4, "cfg": 1.0, "lora": True}, "escalation": ["reroll_view"], "reliable": False},
                              "free": {"profile": {"window": "single", "frames": 13, "strength": 1.0, "steps": 4, "cfg": 1.0, "lora": True}, "escalation": ["single", "double", "reroll_view"], "reliable": True},
                              "cell": {"profile": {"window": "double", "frames": 25, "strength": 1.0, "steps": 4, "cfg": 1.0, "lora": True}, "escalation": ["reroll_view"], "reliable": False}}}
        changed = VB.write_profiles(dry=False, summary=summary, path=dst)
        after = open(dst, "r", encoding="utf-8", newline="").read()
        nl = "\r\n" if "\r\n" in before else "\n"
        lb, la = before.split(nl), after.split(nl)
        check(len(lb) == len(la) and sum(1 for x, y in zip(lb, la) if x != y) == len(changed) and all(y.strip().startswith('"repair":') for x, y in zip(lb, la) if x != y),
              "write_profiles: only the repair lines change (%d), the rest byte-identical, the line count kept" % len(changed))
        d2 = json.loads(after)
        ms = {m["id"]: m for m in d2["methods"]}
        check(len(changed) == len(ms) and all(isinstance(m["repair"].get("profile"), dict) and m["repair"]["escalation"][-1] == "reroll_view" for m in ms.values()), "every method's rule gained profile + escalation")
        check(ms["creature_ctl"]["repair"]["profile"]["window"] == "single" and ms["hero_puppet"]["repair"]["profile"]["window"] == "single" and ms["creature_pose2"]["repair"]["profile"]["window"] == "double"
              and ms["creature_free8"]["repair"]["escalation"] == ["single", "double", "reroll_view"] and ms["item_icon"]["repair"]["profile"]["window"] == "double", "the classes map onto the 21 methods")
        check(ms["creature_pose2"]["repair"]["vace"] == "conditional" and ms["creature_ctl"]["repair"]["vace"] == "yes", "an unreliable class never says vace: yes; a reliable one keeps its word")
        again = VB.write_profiles(dry=True, summary=summary, path=dst)
        check(again == [], "writing the same profiles again changes nothing")
        check(VR.repair_rules(dst)["creature_ctl"]["profile"]["frames"] == 13, "vace_repair reads the rules of the written file")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- the real methods.json: a profile and an escalation on every method
    real = VR.repair_rules()
    check(len(real) == 21 and all(isinstance(r.get("profile"), dict) and set(("window", "frames", "strength", "steps", "cfg", "lora")) <= set(r["profile"]) for r in real.values()),
          "methods.json: the 21 repair rules carry a full profile")
    check(all(isinstance(r.get("escalation"), list) and r["escalation"] and r["escalation"][-1] == "reroll_view" and all(x in ("single", "double", "reroll_view") for x in r["escalation"]) for r in real.values()),
          "every escalation ends in reroll_view and names only known rungs")
    check(all(real[m].get("profile") == real.get(VR.CLASS_METHODS[VR.METHOD_CLASSES.get(m, "cell")], {}).get("profile") and real[m].get("profile") for m in real), "every method carries its class's profile")
    for m, r in real.items():
        if r.get("vace") == "yes":
            check((r.get("escalation") or [None])[0] in ("single", "double"), "%s says vace: yes, so its first rung is a repair window" % m)
    p = VR.profile_for("creature_ctl")
    check(p["source"].startswith("methods.json") and p["window"] in ("single", "double"), "profile_for follows the real catalogue: %s" % p["source"])

    # ---- a dry repair on VACE95's temporary world follows the profile, an explicit argument wins, a mask narrows the paint
    import selftest_VACE95 as V95
    tmp = tempfile.mkdtemp(prefix="le_gates96w_")
    saved = {k: getattr(FS, k) for k in ("STORE", "CONTENT", "ANIM", "DRIVERS", "RAW", "BACKUPS")}
    try:
        w = V95._make_world(tmp)
        FS.STORE = os.path.join(tmp, "dl", "frames")
        FS.CONTENT = w["content"]
        FS.ANIM = os.path.join(tmp, "dl", "ai_anim")
        FS.DRIVERS = os.path.join(tmp, "dl", "drivers")
        FS.RAW = os.path.join(tmp, "dl", "ai_raw_anime")
        FS.BACKUPS = os.path.join(tmp, "backups")
        out_dir = os.path.join(tmp, "out")
        prof = {"window": "single", "frames": 13, "strength": 0.7, "steps": 20, "cfg": 3.5, "lora": False, "escalation": ["single", "reroll_view"], "class": "ctl", "method": "creature_ctl", "source": "test"}
        info = VR.repair("enemy", "bug", "BG-B", "run", "side", [1, 2], dry=True, out_dir=out_dir, profile=prof)
        check(info["window"] == "single" and info["frames"] == 5 and info["wan"]["strength"] == 0.7 and info["wan"]["steps"] == 20 and info["wan"]["cfg"] == 3.5 and info["wan"]["lora"] is False
              and info["profile"]["class"] == "ctl", "a repair with no explicit settings follows the profile: single window, strength 0.7, 20 steps without the LoRAs")
        info2 = VR.repair("enemy", "bug", "BG-B", "run", "side", [1, 2], dry=True, out_dir=out_dir, profile=prof, window="double", strength=1.0, steps=4, lora=True, cfg=1.0)
        check(info2["window"] == "double" and info2["frames"] == 9 and info2["wan"]["strength"] == 1.0 and info2["wan"]["steps"] == 4 and info2["wan"]["lora"] is True, "explicit arguments win over the profile")
        info3 = VR.repair("enemy", "bug", "BG-B", "run", "side", [1, 2], dry=True, out_dir=out_dir)
        check(info3["profile"]["source"].startswith("methods.json") and info3["window"] in ("single", "double") and info3["wan"]["strength"] == VR.profile_for("creature_ctl")["strength"],
              "with no profile given, the group's method finds the catalogue's: %s" % info3["profile"]["source"])
        info4 = VR.repair("enemy", "bug", "BG-B", "run", "side", [1, 2], dry=True, out_dir=out_dir, profile=prof, mask={1: [0.0, 0.5, 0.5, 1.0], 7: [0, 0, 1, 1]})
        check(info4["mask"] == {"1": [0.0, 0.5, 0.5, 1.0]} and info4["frames"] == 5 and len([p for p in info4["plan"] if p["redo"]]) == 2, "a mask on a redone slot is kept (a slot outside the redo set dropped), the plan unchanged")
        other = os.path.join(tmp, "store2")
        info5 = VR.repair("enemy", "bug", "BG-B", "run", "side", [1], dry=True, out_dir=out_dir, store=other)
        check(os.path.isdir(os.path.join(other, "enemy", "bug", "BG-B", "run", "side")) and info5["store"] and not os.path.exists(os.path.join(FS.STORE, "enemy", "bug", "BG-B", "run", "side", "slot_01", "v002.json")),
              "another store root registers the look there and leaves the default store alone")
        # the benchmark's checks on this world: a staged copy of a kept frame is clean; nothing stays staged
        g = FS.Group(FS.Look("enemy", "bug", "BG-B"), "run", "side")
        VB.OUT = os.path.join(tmp, "bench")
        base = VB.baseline(g, "bug")
        check(base["n"] == 4 and set(base["colour"]) == {"0", "1", "2", "3"} and all(v > 0 for v in base["area"].values()), "the baseline: a colour distance and an area per slot")
        raw = g.raw_of(2, g.versions(2)[0])
        v = g.add_version(1, raw, "raw", "vace", by="test")
        res = VB.checks(g, {"slots": [1], "versions": [{"slot": 1, "id": v["id"]}]}, base)
        check(res["of"] >= 5 and 0.0 <= res["score"] <= 1.0 and res["slots"] == 1 and res["per_slot"]["1"]["kind"] == "lone" and not g.staged(), "checks: scored, lone, and nothing left staged (score %s, %s)" % (res["score"], res["per_slot"]["1"]["checks"]))
        check("colour" in res["per_slot"]["1"]["checks"] and "area" in res["per_slot"]["1"]["checks"] and "jump" in res["per_slot"]["1"]["checks"], "the E4 checks are named per slot")
    finally:
        for k, val in saved.items():
            setattr(FS, k, val)
        VB.OUT = os.path.join(ROOT, "tools", "dl", "p96", "GATES", "bench")
        shutil.rmtree(tmp, ignore_errors=True)
