"""Lane GEMINI's selftest group (pass 98): Garry's Gemini subscription as an art checker (tools/vision_eval.py's
`antigravity` backend through a FAKE agy: a small Python script standing in for agy.exe that reads the prompt and the
pictures in its folder and answers like agy's print mode; never the real exe), the inbox and its cleanup, a refusal,
a timeout, an empty answer, a log-in error, the contact sheet's numbering round trip (cell k -> frame k), the daily cap
and the request's calls, the ledger rows, the settings append on a temp copy (never the real file), Garry's order
(2026-10-22: tier 0, then Gemini, the local model ONLY on the frames of a failed Gemini call, surfaced as an error), the
planner's decision points and the agreement rule, requests' eyes stamp, eyes_io (the frames' qa.eyes, the look's line),
the routes over HTTP on REQ96's temp world, and the page's model (EyesModel, findingsBadges) under Node and its wiring.
Discovered by selftest.py: `checks(check, run_node, server)`. Everything on temp folders."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)

FAKE_AGY = r'''
import json, os, sys, time
prompt = ""
for a in sys.argv[1:]:
    if a.startswith("-p="):
        prompt = a[3:]
files = sorted(os.listdir("."))
log = os.environ.get("FAKE_AGY_LOG")
if log:
    with open(log, "a", encoding="utf-8") as f:
        f.write(json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd(), "files": files, "prompt": prompt}) + "\n")
mode = os.environ.get("FAKE_AGY_MODE", "ok")
usage = {"input_tokens": 17000, "output_tokens": 900, "thinking_tokens": 800, "cache_read_tokens": 5, "total_tokens": 17900}
if mode == "timeout":
    time.sleep(float(os.environ.get("FAKE_AGY_SLEEP", "30")))
if mode == "deny":
    print(json.dumps({"response": "", "status": "completed", "denied_actions": [{"tool": "view_file", "path": files[0] if files else "?"}], "usage": usage}))
    sys.exit(0)
if mode == "empty":
    print(json.dumps({"response": "", "status": "completed", "usage": usage}))
    sys.exit(0)
if mode == "quota":
    cl = os.environ.get("FAKE_AGY_CLILOG")
    if cl:
        with open(cl, "a", encoding="utf-8") as f:
            f.write(time.strftime("E%m%d %H:%M:%S") + ".123456       1 session.go:273] Print mode: run ended with error and no response: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 2h0m0s." + chr(10))
    print(json.dumps({"response": "", "status": "ERROR", "usage": {}}))
    sys.exit(3)
if mode == "login":
    print("Error: you are not logged in. Run agy to sign in.")
    sys.exit(3)
n = int(os.environ.get("FAKE_AGY_N", "16"))
bad = {int(x) for x in os.environ.get("FAKE_AGY_BAD", "").split(",") if x.strip()}
skip = {int(x) for x in os.environ.get("FAKE_AGY_SKIP", "").split(",") if x.strip()}
cells = [{"n": k, "ok": k not in bad, "legs": 9 if k in bad else 8, "ghost": False, "face": "ok", "why": "extra leg" if k in bad else "fine"} for k in range(1, n + 1) if k not in skip]
txt = json.dumps({"cells": cells})
if mode == "fenced":
    txt = "```json\n" + txt + "\n```\n"
print("a progress line agy prints first")
print(json.dumps({"response": txt, "status": "completed", "usage": usage}))
'''
FINE = {"legs": 8, "arms": 0, "broken": False, "ghost": False, "face": "ok", "smear": False, "colour": False, "note": "fine"}
GHOST = {"legs": 8, "arms": 0, "broken": False, "ghost": True, "face": "ok", "smear": False, "colour": False, "note": "a ghost leg"}
ENV_KEYS = ("FAKE_AGY_MODE", "FAKE_AGY_N", "FAKE_AGY_BAD", "FAKE_AGY_SKIP", "FAKE_AGY_LOG", "FAKE_AGY_SLEEP", "FAKE_AGY_CLILOG", "AGY_FAKE_EXE", "ASSET_JOB_SIDECAR")


def _env(**kw):
    for k in ENV_KEYS:
        if k.startswith("FAKE_AGY"):
            os.environ.pop(k, None)
    for k, v in kw.items():
        os.environ["FAKE_AGY_" + k.upper()] = str(v)


def checks(check, run_node, server):
    import vision_eval as VE
    tmp = tempfile.mkdtemp(prefix="le_gemini98_")
    keys = ("LEDGER", "CACHE_DIR", "DEFAULTS", "AGY_EXE", "AGY_INBOX", "AGY_LOCK", "AGY_SETTINGS", "AGY_STATE", "AGY_CLI_LOG")
    saved = {k: getattr(VE, k) for k in keys}
    saved_env = {k: os.environ.get(k) for k in ENV_KEYS}
    real_settings = saved["AGY_SETTINGS"]
    real_bytes = open(real_settings, "rb").read() if os.path.isfile(real_settings) else None
    fake = os.path.join(tmp, "fake_agy.py")
    with open(fake, "w", encoding="utf-8") as f:
        f.write(FAKE_AGY)
    try:
        VE.LEDGER = os.path.join(tmp, "qa", "ledger.json")
        VE.CACHE_DIR = os.path.join(tmp, "qa", "cache")
        VE.DEFAULTS = os.path.join(tmp, "request_defaults.json")
        VE.AGY_EXE = fake                       # never the real agy.exe in a test
        VE.AGY_INBOX = os.path.join(tmp, "qa", "agy_inbox")
        VE.AGY_LOCK = os.path.join(tmp, "qa", "agy.lock")
        VE.AGY_SETTINGS = os.path.join(tmp, "agy_settings.json")
        VE.AGY_STATE = os.path.join(tmp, "qa", "agy_state.json")      # never the real quota state
        VE.AGY_CLI_LOG = os.path.join(tmp, "agy_cli.log")            # never Garry's agy log
        os.environ["AGY_FAKE_EXE"] = fake
        _settings_checks(check, VE, tmp)
        _backend_checks(check, VE, tmp, fake)
        _sheet_checks(check, VE, fake)
        _cap_checks(check, VE, tmp, fake)
        _planner_checks(check)
        _stamp_checks(check, tmp)
        _world_checks(check, VE, tmp, fake)
        _page_checks(check, run_node)
    finally:
        for k, v in saved.items():
            setattr(VE, k, v)
        for k, v in saved_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(tmp, ignore_errors=True)
    now_bytes = open(real_settings, "rb").read() if os.path.isfile(real_settings) else None
    check(now_bytes == real_bytes, "GEMINI98: Garry's real agy settings.json was never touched by the tests")


# ---------------------------------------------------------------- the settings append (a temp copy)

def _settings_checks(check, VE, tmp):
    p = os.path.join(tmp, "settings_copy.json")
    orig = '{\n  "permissions": {\n    "allow": [\n      "read_file(D:/_projects/88fits/tools/dl/qa_bench)"\n    ]\n  }\n}'
    with open(p, "w", encoding="utf-8") as f:
        f.write(orig)
    inbox = os.path.join(tmp, "qa", "agy_inbox")
    ok, why = VE.agy_rule_present(p, inbox)
    check(not ok and "no read_file(" in why, "GEMINI98: the inbox rule is not in Garry's file yet: %s" % why)
    bdir = os.path.join(tmp, "backups")
    r = VE.ensure_agy_rule(p, inbox, bdir)
    d = json.load(open(p, encoding="utf-8"))
    rule = VE.agy_rule(inbox)
    check(r["ok"] and r["added"] and d["permissions"]["allow"] == ["read_file(D:/_projects/88fits/tools/dl/qa_bench)", rule], "GEMINI98: ensure_agy_rule appends the one rule after Garry's own: %s" % d)
    check("\\" not in rule and rule.startswith("read_file(") and rule.endswith("/qa/agy_inbox)"), "GEMINI98: the rule has forward slashes only (a backslash breaks the JSON): %s" % rule)
    check(r["backup"] and open(r["backup"], encoding="utf-8").read() == orig, "GEMINI98: the file is backed up byte for byte before the write")
    r2 = VE.ensure_agy_rule(p, inbox, bdir)
    check(r2["ok"] and not r2["added"] and len(json.load(open(p, encoding="utf-8"))["permissions"]["allow"]) == 2, "GEMINI98: a second call writes nothing")
    check(VE.agy_rule_present(p, inbox)[0], "GEMINI98: the rule is present now")
    p2 = os.path.join(tmp, "settings_parent.json")
    with open(p2, "w", encoding="utf-8") as f:
        json.dump({"permissions": {"allow": ["read_file(%s)" % os.path.join(tmp, "qa").replace("\\", "/")]}}, f)
    check(VE.agy_rule_present(p2, inbox)[0], "GEMINI98: a rule on a folder above the inbox counts as present")
    p3 = os.path.join(tmp, "settings_broken.json")
    with open(p3, "w", encoding="utf-8") as f:
        f.write("{ not json")
    r3 = VE.ensure_agy_rule(p3, inbox, bdir)
    check(not r3["ok"] and open(p3, encoding="utf-8").read() == "{ not json", "GEMINI98: a broken settings file is never rewritten: %s" % r3.get("error"))
    # the module's own settings path (a temp file) gets the rule for the later checks
    VE.ensure_agy_rule(VE.AGY_SETTINGS, None, bdir)
    h = VE.agy_health()
    check(h["ok"] and h["exe_ok"] and h["rule_ok"] and h["today"]["cap"] == 40, "GEMINI98: agy_health: the exe and the rule found, the cap 40 by default, no call made: %s" % h["why"])
    h2 = VE.agy_health(exe=os.path.join(tmp, "nowhere", "agy.exe"))
    check(not h2["ok"] and "not at" in h2["why"], "GEMINI98: agy_health says when agy.exe is missing: %s" % h2["why"])


# ---------------------------------------------------------------- the backend through the fake agy

def _backend_checks(check, VE, tmp, fake):
    from PIL import Image
    log = os.path.join(tmp, "agy_log.jsonl")
    img = VE.png_bytes(Image.new("RGBA", (64, 64), (200, 40, 40, 255)))
    be = VE.backend_for("antigravity")
    check(isinstance(be, VE.AgyBackend) and be.free and be.model == "gemini-3.8-flash-medium" and be.daily_calls == VE.agy_daily_cap() and be.daily_calls >= 1, "GEMINI98: backend_for('antigravity') is the agy eye, free, Gemini 3.8 Flash medium, capped by tiers[2].daily_calls")
    _env(mode="ok", n=6, bad="2,5", log=log)
    r = VE.ask(be, [img], VE.rubric_text("sheet_agy"), rubric_id="sheet_agy", request="rX", use_cache=False)
    check(isinstance(r["answer"], dict) and len(r["answer"]["cells"]) == 6 and not r["error"], "GEMINI98: the fake agy's answer parsed from `response` (after a progress line): %s" % r["error"])
    rec = json.loads(open(log, encoding="utf-8").read().splitlines()[-1])
    argv = rec["argv"]
    check(argv[0].startswith("-p=Call view_file once on img_0.png") and "--mode" in argv and argv[argv.index("--mode") + 1] == "plan"
          and argv[argv.index("--output-format") + 1] == "json" and argv[argv.index("--model") + 1] == "gemini-3.8-flash-medium"
          and argv[argv.index("--print-timeout") + 1] == "420s", "GEMINI98: the call agy_run.py proved: -p, plan mode, json, the model, a print timeout: %s" % argv[1:])
    check("--dangerously-skip-permissions" not in " ".join(argv), "GEMINI98: never --dangerously-skip-permissions")
    check(rec["files"] == ["img_0.png"] and os.path.dirname(rec["cwd"]).replace("\\", "/").lower() == VE.AGY_INBOX.replace("\\", "/").lower(),
          "GEMINI98: agy runs in inbox/<call id>/ holding only img_0.png: %s" % rec)
    check(VE.rubric_text("sheet_agy") in rec["prompt"] and "Do not list folders" in rec["prompt"], "GEMINI98: the prompt = the view_file instruction + the fixed rubric")
    check(os.listdir(VE.AGY_INBOX) == [] and not os.path.exists(VE.AGY_LOCK), "GEMINI98: the call's folder is removed after the call and the agy lock released")
    led = json.load(open(VE.LEDGER, encoding="utf-8"))
    row = led["calls"][-1]
    check(row["backend"] == "antigravity" and row["model"] == "gemini-3.8-flash-medium" and row["tokens_in"] == 17000 and row["tokens_out"] == 900
          and row["tokens_thinking"] == 800 and row["dollars"] == 0.0 and "seconds" in row and row["request"] == "rX" and row["verdict"] is True,
          "GEMINI98: the ledger row: backend, model, seconds, agy's tokens, no dollars, the request: %s" % row)
    _env(mode="fenced", n=3)
    r = VE.ask(be, [img], "p", rubric_id="sheet_agy", use_cache=False)
    check(isinstance(r["answer"], dict) and len(r["answer"]["cells"]) == 3, "GEMINI98: a fenced ```json answer parses")
    for mode, want in (("deny", "denied"), ("login", "not logged in"), ("empty", None)):
        _env(mode=mode)
        r = VE.ask(be, [img], "p", rubric_id="sheet_agy", use_cache=False)
        check(r["answer"] is None and ((want in r["error"]) if want else not r["error"]), "GEMINI98: %s = no verdict, never ok: %s" % (mode, r["error"] or "an empty answer"))
        check(os.listdir(VE.AGY_INBOX) == [], "GEMINI98: the inbox is clean after a %s" % mode)
    check("refused the read" in VE._short_reason({"error": "RuntimeError: denied: agy was refused [..]"}) and "log-in" in VE._short_reason({"error": "RuntimeError: agy answered no JSON (exit 3): Error: you are not logged in"}),
          "GEMINI98: the red line's reasons in Garry's words (refused read, log in)")
    _env(mode="timeout", sleep=20)
    slow = VE.AgyBackend(timeout=2)
    r = VE.ask(slow, [img], "p", rubric_id="sheet_agy", use_cache=False)
    check(r["answer"] is None and "timeout" in r["error"] and os.listdir(VE.AGY_INBOX) == [] and not os.path.exists(VE.AGY_LOCK), "GEMINI98: a timeout = no verdict, the inbox cleaned, the lock released: %s" % r["error"])
    # a spent subscription quota (what the blind bench did to Garry's: agy prints status ERROR, the reason in its cli.log)
    _env(mode="quota", clilog=VE.AGY_CLI_LOG)
    r = VE.ask(be, [img], "p", rubric_id="sheet_agy", use_cache=False)
    q = VE.agy_quota()
    check(r["answer"] is None and "Individual quota reached" in r["error"] and q and "Resets in 2h0m0s" in q["reason"] and 7000 < q["quota_until"] - __import__("time").time() <= 7200,
          "GEMINI98: a spent quota: no verdict, the reason read from agy's cli.log, remembered until it resets: %s" % r["error"])
    check(VE._short_reason(r) == "Gemini's subscription quota is spent (it resets in 2h0m0s)", "GEMINI98: the red line says the quota is spent and when it resets")
    n_before = len(open(log, encoding="utf-8").read().splitlines())
    r = VE.ask(be, [img], "p2", rubric_id="sheet_agy", use_cache=False)
    check(r["answer"] is None and "quota is spent until" in r["refused"] and len(open(log, encoding="utf-8").read().splitlines()) == n_before,
          "GEMINI98: while the quota is spent no agy call is made (refused at once, the fallback follows): %s" % r["refused"])
    h = VE.agy_health()
    check(not h["ok"] and "quota is spent until" in h["why"] and VE.agy_today()["quota_until"], "GEMINI98: health and today say the quota is spent and until when")
    import eyes_io as EIO
    check("quota is spent until" in EIO._refusal(), "GEMINI98: the buttons refuse with the quota's words (Ask the local vision model meanwhile)")
    os.remove(VE.AGY_STATE)
    check(VE.agy_quota() is None and VE.agy_health()["ok"], "GEMINI98: without the state file Gemini is ready again")
    gone = VE.AgyBackend(exe=os.path.join(tmp, "nowhere", "agy.exe"))
    r = VE.ask(gone, [img], "p", rubric_id="sheet_agy", use_cache=False)
    check(r["answer"] is None and "not installed" in r["error"], "GEMINI98: agy missing = no verdict with the reason: %s" % r["error"])
    _env()


# ---------------------------------------------------------------- the contact sheet's numbering

def _sheet_checks(check, VE, fake):
    from PIL import Image
    cells = [("run/side/%d" % k, "run/side", k, Image.new("RGBA", (128, 128), (20 * k % 255, 120, 60, 255)), "v%02d" % k) for k in range(20)]
    sheets = VE.agy_sheets(cells)
    check(len(sheets) == 2 and len(sheets[0][1]) == 16 and len(sheets[1][1]) == 4, "GEMINI98: 20 frames make two sheets (16 + 4)")
    w0, w1 = sheets[0][1], sheets[1][1]
    check(all(w0[k]["slot"] == k - 1 and w0[k]["version"] == "v%02d" % (k - 1) for k in range(1, 17)) and all(w1[k]["slot"] == 15 + k for k in range(1, 5)),
          "GEMINI98: cell k of a sheet is frame k-1 of its chunk (numbers restart on every sheet)")
    im = sheets[0][0]
    px = [im.getpixel((x, y)) for x in range(10, 60) for y in range(10, 50)]
    check(any(p[0] < 10 and p[1] < 10 and p[2] < 10 for p in px) and any(p[0] > 200 and p[1] > 200 and p[2] < 120 for p in px), "GEMINI98: the number is drawn big, yellow on a black box, at the cell's top left")
    ans = {"cells": [{"n": k, "ok": k not in (2, 5), "legs": 9 if k in (2, 5) else 8, "why": "extra leg" if k in (2, 5) else "fine"} for k in range(1, 17) if k != 7]}
    its = VE._agy_items(ans, w0, "gemini-3.8-flash-medium")
    bad = sorted((i["slot"], i["version"]) for i in its if i["ok"] is False)
    check(bad == [(1, "v01"), (4, "v04")], "GEMINI98: the round trip: cells 2 and 5 flagged = frames 1 and 4 with their versions: %s" % bad)
    skipped = [i for i in its if i["slot"] == 6]
    check(len(skipped) == 1 and skipped[0]["ok"] is None and "skipped" in skipped[0]["rule"], "GEMINI98: a cell the answer skipped is no verdict, never ok")
    one = [i for i in its if i["slot"] == 1][0]
    check(one["eye"] == "gemini" and one["backend"] == "antigravity" and one["label"] == "extra leg" and one["legs"] == 9 and one["tier"] == 2 and "a hint, not a verdict" in one["rule"],
          "GEMINI98: an item carries the eye, the badge's words, legs, tier 2 and the hint: %s" % one)
    check(one["defects"] == ["legs"] and VE.defect_kinds({"ok": False, "ghost": True, "why": "ghost leg"}) == ["ghost", "legs"]
          and VE.defect_kinds({"ok": False, "smear": True, "why": "blurred"}) == ["smear"] and VE.defect_kinds({"ok": False, "face": "missing", "why": "no face"}) == ["face"]
          and VE.defect_kinds({"ok": False, "why": "odd colour"}) == ["other"], "GEMINI98: a flagged cell's defect kinds (ghost / smear / face trusted, legs a badge)")
    none = VE._agy_items(None, w1, "m")
    check(len(none) == 4 and all(i["ok"] is None for i in none), "GEMINI98: an unparsable sheet answer = no verdict on every cell")


# ---------------------------------------------------------------- the daily cap and the request's calls

def _cap_checks(check, VE, tmp, fake):
    from PIL import Image
    img = VE.png_bytes(Image.new("RGBA", (32, 32), (10, 200, 10, 255)))
    os.makedirs(os.path.dirname(VE.DEFAULTS), exist_ok=True)
    keep_ledger = VE.LEDGER
    VE.LEDGER = os.path.join(tmp, "qa", "ledger_cap.json")
    with open(VE.DEFAULTS, "w", encoding="utf-8") as f:
        json.dump({"tiers": {"2": {"backend": "antigravity", "model": "gemini-3.8-flash-medium", "daily_calls": 2}}}, f)
    try:
        be = VE.AgyBackend()
        check(be.daily_calls == 2 and VE.agy_daily_cap() == 2, "GEMINI98: tiers[\"2\"].daily_calls sets the cap")
        _env(mode="ok", n=1)
        r1 = VE.ask(be, [img], "p1", rubric_id="sheet_agy", use_cache=False)
        r2 = VE.ask(be, [img], "p2", rubric_id="sheet_agy", use_cache=False)
        r3 = VE.ask(be, [img], "p3", rubric_id="sheet_agy", use_cache=False)
        check(r1["answer"] and r2["answer"] and r3["answer"] is None and "today's Gemini cap: 2 of 2" in r3["refused"], "GEMINI98: the third call of a day capped at 2 is refused: %s" % r3["refused"])
        t = VE.agy_today()
        check(t["calls"] == 2 and t["left"] == 0, "GEMINI98: agy_today counts the day's calls (a refusal is not a call): %s" % t)
        led = json.load(open(VE.LEDGER, encoding="utf-8"))
        check(led["calls"][-1].get("refused") and led["totals"]["calls"] == 2, "GEMINI98: the refusal is a ledger row of its own, not counted")
        with open(VE.DEFAULTS, "w", encoding="utf-8") as f:
            json.dump({"tiers": {"2": {"backend": "antigravity", "daily_calls": 40}}}, f)
        r4 = VE.ask(VE.AgyBackend(), [img], "p4", rubric_id="sheet_agy", use_cache=False, budget={"calls_left": 0})
        check(r4["answer"] is None and "evaluator_calls" in r4["refused"], "GEMINI98: a request with no evaluator calls left is refused: %s" % r4["refused"])
        r5 = VE.ask(VE.AgyBackend(), [img], "p1", rubric_id="sheet_agy", use_cache=True)
        r6 = VE.ask(VE.AgyBackend(), [img], "p1", rubric_id="sheet_agy", use_cache=True)
        check(r5["answer"] and r6["cached"] and VE.agy_today()["calls"] == 3, "GEMINI98: the same sheet and rubric again is answered from the cache, no call")
    finally:
        os.remove(VE.DEFAULTS)
        VE.LEDGER = keep_ledger
        _env()


# ---------------------------------------------------------------- the planner (pure)

def _planner_checks(check):
    import loop as LOOP
    import commands as CMD
    asset = {"kind": "enemy", "id": "bug", "code": "BG-B", "method": "creature_ctl"}
    groups = [{"label": "run/side", "n": 12, "repairable": True, "method": "creature_ctl", "flagged": []},
              {"label": "die/front", "n": 8, "repairable": True, "method": "creature_ctl", "flagged": []}]
    base = {"rid": "r1", "mode": "auto", "asset": asset, "budget": {"rerolls": 2, "repair_rounds": 2, "evaluator_calls": 60, "cloud_dollars": 0.0},
            "spent": {"rerolls": 0, "repair_rounds": {}, "evaluator_calls": 0}, "iterations": [], "provisional": None}

    def rec(iters=None, eyes=True, **kw):
        r = json.loads(json.dumps(base))
        r["iterations"] = iters or []
        if eyes:
            r["eyes"] = {"tier2": True, "backend": "antigravity"}
        r.update(kw)
        return r

    def it(n, op, job):
        return {"n": n, "job": job, "op": op}

    def m(group, slot, tier, ok=False, defects=None):
        d = {"image": "%s/%d" % (group, slot), "group": group, "slot": slot, "kind": "model", "field": "sheet" if tier == 2 else "ghost", "ok": ok, "tier": tier}
        if defects:
            d["defects"] = defects
        return d

    def shape(group, slot, field="silhouette"):
        return {"image": "%s/%d" % (group, slot), "group": group, "slot": slot, "kind": "measured", "field": field, "ok": False}

    def hard(group, slots):
        return [{"image": "%s/%d" % (group, s), "group": group, "slot": s, "kind": "measured", "field": "jump", "ok": False} for s in slots]

    def fnd(job, items, tiers):
        h = sum(1 for i in items if i["kind"] == "measured" and i["ok"] is False)
        return {"v": 1, "job": job, "items": items, "gates": {"hard_failures": h, "advisory": 0, "pass": h == 0}, "groups": groups, "tiers": tiers}
    op = LOOP.next_op(rec(eyes=False), None)
    check(op["op"] == "ask" and op["args"] == {"tiers": [0, 1]}, "GEMINI98: a record without `eyes` (pass 96) asks [0, 1] exactly as before: %s" % op["args"])
    op = LOOP.next_op(rec(), None)
    check(op["op"] == "ask" and op["args"] == {"tiers": [0, 1, 2], "scope": "flagged"} and "Gemini" in op["why"], "GEMINI98: tier 2 on: the first ask is tiers [0, 1, 2], scope flagged: %s" % op)
    ask = it(1, {"op": "ask", "target": asset, "args": {"tiers": [0, 1]}}, "j2")
    op = LOOP.next_op(rec([ask]), fnd("j2", [], [0, 1]))
    check(op["op"] == "ask" and op["args"]["tiers"] == [0, 1, 2] and "decision point" in op["why"], "GEMINI98: gates passing on findings made without tier 2: one Gemini ask before the provisional winner: %s" % op)
    ask2 = it(1, {"op": "ask", "target": asset, "args": {"tiers": [0, 1, 2]}}, "j3")
    op = LOOP.next_op(rec([ask2]), fnd("j3", [m("run/side", 3, 2)], [0, 1, 2]))
    check(op["op"] == "select_provisional", "GEMINI98: findings with tier 2 and only Gemini's advisory flags: select_provisional (a hint is never a gate): %s" % op["op"])
    op = LOOP.next_op(rec([ask2], eyes=False), fnd("j3", [], [0, 1]))
    check(op["op"] == "select_provisional", "GEMINI98: without `eyes` the gates passing select at once (pass 96)")
    op = LOOP.next_op(rec([ask2]), fnd("j3", [m("run/side", 3, 2, defects=["legs"])], [0, 1, 2]))
    check(op["op"] == "select_provisional", "GEMINI98: a Gemini leg count alone never drives a repair (the bench: legs 2/11): %s" % op["op"])
    op = LOOP.next_op(rec([ask2]), fnd("j3", [m("run/side", 4, 2, defects=["ghost", "legs"])], [0, 1, 2]))
    check(op["op"] == "repair" and op["target"]["slots"] == [4] and "Gemini flags" in op["why"], "GEMINI98: a Gemini ghost (trusted: 22/25) drives one repair: %s" % op.get("why"))
    for kind in ("smear", "face"):
        op = LOOP.next_op(rec([ask2]), fnd("j3", [m("run/side", 4, 2, defects=[kind])], [0, 1, 2]))
        check(op["op"] == "repair", "GEMINI98: a Gemini %s drives one repair" % kind)
    op = LOOP.next_op(rec([ask2]), fnd("j3", [m("run/side", 4, 1), m("run/side", 4, 2, defects=["legs"])], [0, 1, 2]))
    check(op["op"] == "select_provisional", "GEMINI98: the local model agreeing with a Gemini leg count is still not enough without tier 0's shape flags")
    agreed = [m("run/side", 3, 1), m("run/side", 3, 2, defects=["ghost"]), m("run/side", 5, 2, defects=["legs"])]
    op = LOOP.next_op(rec([ask2]), fnd("j3", agreed, [0, 1, 2]))
    check(op["op"] == "repair" and op["target"]["group"] == "run/side" and op["target"]["slots"] == [3] and "both eyes" in op["why"], "GEMINI98: both eyes flag frame 3 (both ran): one repair of it: %s" % op)
    ok, why = CMD.validate({k: op[k] for k in CMD.OP_KEYS if k in op}, dict(rec([ask2]), mode="auto"), frames_store=_FakeFS())
    check(ok, "GEMINI98: the agreement repair validates as an op: %s" % why)
    rep = it(2, {"op": "repair", "target": {"kind": "enemy", "id": "bug", "code": "BG-B", "group": "run/side", "slots": [3]}, "args": {"rung": "single"}}, "j4")
    ask3 = it(3, {"op": "ask", "target": asset, "args": {"tiers": [0, 1, 2]}}, "j5")
    op = LOOP.next_op(rec([ask2, rep, ask3]), fnd("j5", agreed, [0, 1, 2]))
    check(op["op"] == "select_provisional", "GEMINI98: the agreed slots never repaired twice: %s" % op["op"])
    op = LOOP.next_op(rec([ask2], eyes=False), fnd("j3", agreed, [0, 1, 2]))
    check(op["op"] == "select_provisional", "GEMINI98: the agreement rule needs the request's eyes (pass 96 records unchanged)")
    legs_shape = hard("die/front", [2]) + [shape("run/side", 6), m("run/side", 6, 2, defects=["legs"])]
    op = LOOP.next_op(rec([ask2]), fnd("j3", legs_shape, [0, 1, 2]))
    check(op["op"] == "repair" and op["target"]["group"] == "run/side", "GEMINI98: a Gemini leg count where tier 0's silhouette flag agrees counts: that group first: %s" % op["target"])
    two = hard("die/front", [2]) + hard("run/side", [6]) + [m("run/side", 6, 1), m("run/side", 6, 2, defects=["face"])]
    op = LOOP.next_op(rec([ask2]), fnd("j3", two, [0, 1, 2]))
    check(op["op"] == "repair" and op["target"]["group"] == "run/side", "GEMINI98: of two hard groups, the one both eyes flag is repaired first (else die/front by name): %s" % op["target"])
    op = LOOP.next_op(rec([ask2], eyes=False), fnd("j3", two, [0, 1, 2]))
    check(op["op"] == "repair" and op["target"]["group"] == "die/front", "GEMINI98: without eyes the order is pass 96's: %s" % op["target"])
    # commands: the scope arg and the calls left travel into the evaluate spec
    ctx = _FakeCtx()
    r = dict(rec([ask2]), spent={"rerolls": 0, "repair_rounds": {}, "evaluator_calls": 7})
    res = CMD.dispatch({"op": "ask", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {"tiers": [0, 1, 2], "scope": "flagged"}, "why": "w"}, r, ctx)
    sp = ctx.enqueued[-1]["spec"] if ctx.enqueued else {}
    check(res.get("job") and sp.get("scope") == "flagged" and sp.get("calls_left") == 53 and sp.get("tiers") == [0, 1, 2], "GEMINI98: dispatch ask: scope and calls_left (60 - 7) in the spec: %s" % sp)
    CMD.dispatch({"op": "ask", "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}, "args": {"tiers": [0, 1]}, "why": "w"}, r, ctx)
    sp = ctx.enqueued[-1]["spec"]
    check("scope" not in sp and "calls_left" not in sp, "GEMINI98: a pass 96 ask's spec is unchanged (no scope, no calls_left): %s" % sorted(sp))


class _FakeFS:
    class Look:
        def __init__(self, *a):
            pass

    class Group:
        n = 12

        def __init__(self, *a):
            pass

        def exists(self):
            return True

        def selected(self):
            return {}


class _FakeCtx:
    def __init__(self):
        self.enqueued = []
        self.frames_store = _FakeFS
        self.frames_io = None
        self.requests_api = None
        self.jobs_call = lambda *a, **k: (404, {})

    def enqueue(self, kind, target, spec, title=None):
        j = {"id": "jf%d" % len(self.enqueued), "kind": kind, "target": target, "spec": spec}
        self.enqueued.append(j)
        return {"job": j}


# ---------------------------------------------------------------- the request's stamp

def _stamp_checks(check, tmp):
    import jobs
    R = jobs.requests_module()
    saved = R.DEFAULTS_FILE
    try:
        R.DEFAULTS_FILE = os.path.join(tmp, "rd_stamp.json")
        with open(R.DEFAULTS_FILE, "w", encoding="utf-8") as f:
            json.dump({"tiers": {"2": {"backend": "antigravity", "model": "gemini-3.8-flash-medium"}}}, f)
        s = R.eyes_stamp({})
        check(s == {"tier2": True, "backend": "antigravity", "model": "gemini-3.8-flash-medium"}, "GEMINI98: a new request gets Gemini at its decision points by default: %s" % s)
        check(R.eyes_stamp({"gemini": False})["tier2"] is False, "GEMINI98: brief.gemini false turns it off for one request")
        with open(R.DEFAULTS_FILE, "w", encoding="utf-8") as f:
            json.dump({"tiers": {"2": {"backend": "antigravity", "requests": False}}}, f)
        check(R.eyes_stamp({})["tier2"] is False, "GEMINI98: tiers[\"2\"].requests false turns it off for new requests")
        with open(R.DEFAULTS_FILE, "w", encoding="utf-8") as f:
            json.dump({"tiers": {"2": {"backend": "anthropic", "ceiling_dollars": 0.0}}}, f)
        check(R.eyes_stamp({})["tier2"] is False, "GEMINI98: a paid tier 2 (pass 96's table) stamps no Gemini")
    finally:
        R.DEFAULTS_FILE = saved
    rd = json.load(open(os.path.join(HERE, "request_defaults.json"), encoding="utf-8"))
    t2 = rd["tiers"]["2"]
    check(t2["backend"] == "antigravity" and t2["model"] == "gemini-3.8-flash-medium" and t2["daily_calls"] == 6 and t2["alternates"]["anthropic"]["backend"] == "anthropic"
          and t2["alternates"]["gemini_api"]["backend"] == "gemini" and rd["tiers"]["1"]["backend"] == "openai_chat", "GEMINI98: request_defaults: tier 2 = Gemini through agy (cap 6 a day), the paid eyes kept as alternates, tier 1 still the local model")


# ---------------------------------------------------------------- the temp world: evaluate_look, the fallback, eyes_io, the routes

def _world_checks(check, VE, tmp, fake):
    import selftest_REQ96 as RQ
    import eyes_io as EIO
    with RQ.TempWorld() as w:
        import frames_store as FS
        jobs, server = w.jobs, w.server
        # Gemini first on every frame of run/side (scope all): cells 2 and 5 flagged
        _env(mode="ok", n=16, bad="2,3")
        calls = []
        local = VE.FakeBackend(lambda imgs, p: calls.append(1) or json.dumps(GHOST), model="fake-local")
        out = os.path.join(tmp, "ev1")
        f = VE.evaluate_look("enemy", "bug", "BG-B", tiers=[0, 1, 2], groups=["run/side"], backend=local, cloud_backend="antigravity", scope="all", out_dir=out, job="jG1")
        g_items = [i for i in f["items"] if i.get("eye") == "gemini"]
        n = [g["n"] for g in f["groups"] if g["label"] == "run/side"][0]
        check(len(g_items) == n and sorted(i["slot"] for i in g_items if i["ok"] is False) == [1, 2] and all(i["version"] for i in g_items),
              "GEMINI98: Check with Gemini: every frame of run/side on one sheet, cells 2 and 3 = frames 1 and 2, each with its version: %s" % sorted(i["slot"] for i in g_items if i["ok"] is False))
        check(not calls and not any(i.get("tier") == 1 for i in f["items"]), "GEMINI98: Garry's order: Gemini answered, so the local model was never asked")
        check(f["eye"] == "gemini" and "gemini_error" not in f and f["eyes"]["gemini"]["line"].startswith("Gemini flagged 2 frames in run/side (1,2)") and "Gemini flagged 2 frames" in f["summary"],
              "GEMINI98: the record names its eye and the line: %s" % f["eyes"]["gemini"]["line"])
        check(len(f["tier2"]["sheets"]) == 1 and os.path.isfile(os.path.join(out, "gemini_sheet_1.png")), "GEMINI98: the sheet Gemini saw is kept beside the findings")
        # the fallback: agy refused -> the local model on exactly those frames, surfaced as an error
        _env(mode="deny")
        out2 = os.path.join(tmp, "ev2")
        f2 = VE.evaluate_look("enemy", "bug", "BG-B", tiers=[0, 1, 2], groups=["run/side"], backend=local, cloud_backend="antigravity", scope="slots", slots={"run/side": [3]}, out_dir=out2, job="jG2")
        loc = [i for i in f2["items"] if i.get("tier") == 1]
        check(sorted({i["slot"] for i in loc}) == [3] and all(i.get("fallback") and i.get("eye") == "local" and i.get("version") for i in loc) and len(calls) == 1,
              "GEMINI98: Gemini refused: the local model checked exactly frame 3, its items marked fallback: %s" % sorted({i["slot"] for i in loc}))
        check(f2["eye"] == "local (fallback)" and "refused the read" in f2["gemini_error"] and "Gemini failed: " in f2["summary"] and "checked by the local model instead" in f2["fallback"]["line"],
              "GEMINI98: the record carries eye 'local (fallback)', gemini_error and the red line: %s" % f2.get("fallback", {}).get("line"))
        led = json.load(open(VE.LEDGER, encoding="utf-8"))
        fb_rows = [c for c in led["calls"] if c.get("fallback")]
        check(len(fb_rows) == 1 and all(c["model"] == "fake-local" and c["fallback_id"] == f2["fallback"]["id"] for c in fb_rows) and VE.agy_today()["fallbacks"] >= 1,
              "GEMINI98: the fallback's local calls are ledger rows carrying the reason; the day counts the fallback")
        f3 = VE.evaluate_look("enemy", "bug", "BG-B", tiers=[2], groups=["run/side"], backend=local, cloud_backend="antigravity", scope="slots", slots={"run/side": [2]}, allow_fallback=False, job="jG3")
        check(f3["fallback"]["frames"] == 0 and "no fallback" in f3["fallback"]["line"] and not any(i.get("tier") == 1 for i in f3["items"]), "GEMINI98: fallback false: the error still surfaced, no local call")
        _env(mode="ok", n=16, skip="2")
        k0 = len(calls)
        f3b = VE.evaluate_look("enemy", "bug", "BG-B", tiers=[0, 1, 2], groups=["run/side"], backend=local, cloud_backend="antigravity", scope="slots", slots={"run/side": [1, 2]}, job="jG3b", use_cache=False)
        check(len(calls) == k0 + 1 and [i["slot"] for i in f3b["items"] if i.get("fallback")][:1] == [2] and "no verdict on 1 frame" in f3b.get("gemini_error", ""),
              "GEMINI98: a cell Gemini skipped (a partial answer) goes to the local model too, surfaced: %s" % f3b.get("gemini_error"))
        # pass 96's paths unchanged: tiers [0, 1] runs the local model; tiers [0, 1, 2] with a paid table and $0 is off
        f4 = VE.evaluate_look("enemy", "bug", "BG-B", tiers=[0, 1], groups=["run/side"], backend=VE.FakeBackend([json.dumps(FINE)], model="fake-7b"), job="jP")
        check(any(i.get("tier") == 1 for i in f4["items"]) and "eye" not in f4 and "eyes" not in f4, "GEMINI98: a pass 96 job (tiers 0, 1) still asks the local model and carries no eye keys")
        f5 = VE.evaluate_look("enemy", "bug", "BG-B", tiers=[0, 1, 2], groups=["run/side"], backend=VE.FakeBackend([json.dumps(FINE)], model="fake-7b"), cloud_dollars=0.0, job="jQ")
        check(f5["tier2"]["ran"] is False and "cloud_dollars is 0" in f5["tier2"]["why"] and any(i.get("tier") == 1 for i in f5["items"]),
              "GEMINI98: with pass 96's built-in table (no antigravity), tier 2 is off at $0 and tier 1 runs: %s" % f5["tier2"])
        # eyes_io: the findings into the frames store
        ew = EIO.on_findings({"id": "jG1"}, {"findings": os.path.join(out, "findings.json")})
        look = FS.Look("enemy", "bug", "BG-B")
        g = FS.Group(look, "run", "side")
        v1, _ = g.effective(1)
        le = EIO.latest_by_eye(v1.get("qa") or {})
        check(ew["written"] == n and le["gemini"]["ok"] is False and le["gemini"]["label"] == "extra leg" and le["gemini"]["job"] == "jG1" and le["gemini"]["hint"] == "a hint, not a verdict",
              "GEMINI98: on_findings writes one qa.eyes entry per frame: frame 1's Gemini entry: %s" % le.get("gemini"))
        ew2 = EIO.on_findings({"id": "jG2"}, {"findings": os.path.join(out2, "findings.json")})
        v2, _ = g.effective(3)
        le2 = EIO.latest_by_eye(v2.get("qa") or {})
        check(ew2.get("gemini_error") and le2["local"]["name"] == "Local (fallback)" and le2["local"]["fallback"] and le2["local"]["label"] == "ghost part",
              "GEMINI98: the fallback's entries are named 'Local (fallback)': %s" % le2.get("local"))
        g.update_version(1, v1["id"], qa=dict(v1.get("qa") or {}, vision={"answer": {"ghost": True, "note": "ghost"}, "model": "qwen", "time": "2099-01-01T00:00:00"}))
        ly = EIO.look_eyes("enemy", "bug", "BG-B")
        rs = ly["groups"]["run/side"]
        check(rs["gemini"] == [1, 2] and 1 in rs["local"] and 3 in rs["local"] and 1 in rs["both"] and "Gemini flagged 2 frames in run/side" in ly["line"] and "both flag 1" in ly["line"],
              "GEMINI98: look_eyes: Gemini's frames, the local button's answer counted as Local, both on frame 1: %s" % ly["line"])
        # the routes over HTTP
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        httpd.daemon_threads = True
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        get, post = RQ._http("http://127.0.0.1:%d" % httpd.server_address[1])
        try:
            st, d = get("/api/eyes")
            check(st == 200 and d["ok"] and d["ready"] and d["today"]["cap"] >= 1 and d["model"] == "gemini-3.8-flash-medium", "GEMINI98: GET /api/eyes: ready, today's calls, the model: %s" % d.get("why"))
            st, d = get("/api/eyes/look/enemy/bug/BG-B")
            check(st == 200 and "Gemini flagged" in d["line"], "GEMINI98: GET /api/eyes/look/...: the look's line")
            st, d = post("/api/frames/enemy/bug/BG-B/run/side/ask_gemini", {"slots": [1, 2]})
            jid = (d.get("job") or {}).get("id")
            jb = jobs._find(jid) if jid else None
            check(st == 200 and jb and jb["kind"] == "evaluate" and jb["lane"] == "local" and jb["spec"]["tiers"] == [2] and jb["spec"]["scope"] == "slots"
                  and jb["spec"]["slots"] == {"run/side": [1, 2]} and jb["spec"]["cloud_backend"] == "antigravity", "GEMINI98: POST .../ask_gemini queues an evaluate job (tiers [2], the slots): %s" % (jb or d).get("spec", d))
            ej = json.load(open(os.path.join(jobs._job_dir(jid), "evaluate.json"), encoding="utf-8"))
            check(ej["scope"] == "slots" and ej["slots"] == {"run/side": [1, 2]} and ej["cloud_backend"] == "antigravity", "GEMINI98: evaluate.json carries scope, slots and the eye")
            st, d = post("/api/frames/enemy/bug/BG-B/run/side/ask_gemini", {"slots": []})
            check(st == 400 and "which frames" in d.get("error", ""), "GEMINI98: no frames chosen: refused")
            st, d = post("/api/eyes/check", {"kind": "enemy", "id": "bug", "code": "BG-B"})
            jc = jobs._find((d.get("job") or {}).get("id")) if d.get("job") else None
            check(st == 200 and jc and jc["spec"]["tiers"] == [0, 1, 2] and jc["spec"]["scope"] == "all", "GEMINI98: POST /api/eyes/check queues tiers 0, 1, 2 over the whole look")
            st, d = post("/api/eyes/check", {"kind": "enemy", "id": "../x", "code": "BG-B"})
            check(st == 400, "GEMINI98: a bad look is a 400")
            # run the queued Ask job the way the worker does (the tool on its evaluate.json), then the landing
            _env(mode="ok", n=2, bad="1")
            os.environ["ASSET_JOB_SIDECAR"] = os.path.join(jobs._job_dir(jid), "result.json")
            try:
                VE.run_job(os.path.join(jobs._job_dir(jid), "evaluate.json"))
            finally:
                os.environ.pop("ASSET_JOB_SIDECAR", None)
            written, err = jobs._post(jb)
            check(err == "" and jb.get("eyes", {}).get("written") == 2 and "Gemini flagged 1 frame" in jb["eyes"]["line"], "GEMINI98: the landing writes Gemini's answer onto both frames: %s" % jb.get("eyes"))
            st, d = get("/api/frames/enemy/bug/BG-B/run/side")
            s1 = [s for s in d["slots"] if s["slot"] == 1][0]
            v = [x for x in s1["versions"] if x["id"] == s1["effective"]][0]
            check(st == 200 and any(e.get("job") == jid and e.get("ok") is False for e in v["qa"]["eyes"]), "GEMINI98: the Frames view's group carries the new entry on frame 1 (the badge's data)")
            # a failed Gemini call through the job: the red line on the job
            _env(mode="login")
            st, d = post("/api/frames/enemy/bug/BG-B/run/side/ask_gemini", {"slots": [3]})
            jid2 = d["job"]["id"]
            ejp = os.path.join(jobs._job_dir(jid2), "evaluate.json")
            ejd = json.load(open(ejp, encoding="utf-8"))
            ejd["backend"] = "fake"   # the fallback's local model: the selftest's fake eye
            json.dump(ejd, open(ejp, "w", encoding="utf-8"))
            os.environ["ASSET_JOB_SIDECAR"] = os.path.join(jobs._job_dir(jid2), "result.json")
            try:
                VE.run_job(ejp)
            finally:
                os.environ.pop("ASSET_JOB_SIDECAR", None)
            jb2 = jobs._find(jid2)
            written, err = jobs._post(jb2)
            check(err == "" and "log-in" in (jb2.get("eyes") or {}).get("gemini_error", "") and "checked by the local model instead" in jb2["eyes"]["fallback_line"],
                  "GEMINI98: Gemini not logged in: the job carries the red line: %s" % (jb2.get("eyes") or {}).get("fallback_line"))
        finally:
            httpd.shutdown()
            _env()
        # pass 96's plain evaluate job: its evaluate.json has none of the new keys
        j = jobs.enqueue("evaluate", {"kind": "enemy", "id": "bug", "code": "BG-A"}, {"kind": "enemy", "id": "bug", "code": "BG-A", "tiers": [0, 1]}, title="plain")
        ej = json.load(open(os.path.join(jobs._job_dir(j["id"]), "evaluate.json"), encoding="utf-8"))
        check(set(ej) == {"kind", "id", "code", "groups", "tiers", "request", "cloud_dollars", "backend", "model", "note", "job"}, "GEMINI98: a plain evaluate job's evaluate.json is pass 96's exactly: %s" % sorted(ej))


# ---------------------------------------------------------------- the page

NODE = r"""
const M = require(process.argv[2]);
const J = require(process.argv[3]);
const v = { id: 'a', qa: { eyes: [
  { eye: 'gemini', name: 'Gemini', model: 'gemini-3.8-flash-medium', ok: false, label: '9 legs, extra leg', note: '{"legs": 9}', time: '2026-10-22T15:00:00', job: 'j1234' },
  { eye: 'local', name: 'Local (fallback)', fallback: true, model: 'qwen', ok: false, label: 'ghost part', time: '2026-10-22T15:01:00', job: 'j1235' } ] } };
const out = {};
out.badges = M.badges(v).map((b) => [b.text, b.cls, b.bad]);
out.title = M.badges(v)[1].title;
out.mark = M.cellMark({ effective: 'a', versions: [v] });
out.fine = M.cellMark({ effective: 'b', versions: [{ id: 'b', qa: { eyes: [{ eye: 'gemini', ok: true, label: 'fine' }] } }] });
out.none = M.cellMark({ effective: 'c', versions: [{ id: 'c', qa: {} }] });
out.vision = M.badges({ qa: { vision: { answer: { ghost: true, note: 'ghost' }, model: 'qwen', time: 't' } } }).map((b) => [b.text, b.legacy]);
out.ops = M.opsLine({ ready: true, auto: true, today: { calls: 3, cap: 40, left: 37, fallbacks: 1, last_fallback: { why: 'timeout' } } });
out.ops0 = M.opsLine({ ready: false, why: 'no rule', today: { calls: 0, cap: 40, left: 40 } });
const fb = J.findingsBadges({ items: [{ kind: 'model', ok: false, field: 'sheet', value: 'extra leg', label: 'extra leg', eye: 'gemini', group: 'run/side', slot: 4, model: 'gemini-3.8-flash-medium', note: 'n' },
  { kind: 'model', ok: false, field: 'legs', group: 'run/side', slot: 2, model: 'qwen2.5-vl-7b', rule: 'seven legs' }], gates: { pass: true, hard_failures: 0, advisory: 2 }, model_calls: [] });
out.fb = fb.badges.map((b) => [b.text, b.cls]);
process.stdout.write(JSON.stringify(out));
"""


def _page_checks(check, run_node):
    node = shutil.which("node")
    if not node:
        print("GEMINI98: node is not here: the page model is not checked")
        return
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
        f.write(NODE)
        runner = f.name
    try:
        p = subprocess.run([node, runner, os.path.join(HERE, "eyes.js"), os.path.join(HERE, "jobs_model.js")], capture_output=True, text=True, encoding="utf-8", timeout=60)
    finally:
        os.remove(runner)
    check(p.returncode == 0, "GEMINI98: eyes.js's model runs under Node: %s" % p.stderr[-400:])
    if p.returncode != 0:
        return
    o = json.loads(p.stdout)
    check(o["badges"][0][0] == "Gemini + Local both flag it" and "eye-both" in o["badges"][0][1], "GEMINI98: two eyes flag the frame: the strong mark first: %s" % o["badges"][0])
    check(o["badges"][1][0] == "Gemini: 9 legs, extra leg" and "eye-gemini" in o["badges"][1][1] and o["badges"][2][0] == "Local (fallback): ghost part" and "fallback" in o["badges"][2][1],
          "GEMINI98: a badge per eye with its name and colour, the fallback's labelled: %s" % o["badges"][1:])
    check("a hint, not a verdict" in o["title"] and "2026-10-22 15:00" in o["title"] and "#1234" in o["title"], "GEMINI98: the hover holds the note, the time, the job and 'a hint, not a verdict'")
    check(o["mark"]["text"] == "G+L" and "both" in o["mark"]["cls"] and o["fine"]["text"] == "✓" and o["none"] is None, "GEMINI98: the sheet cell's mini mark: G+L, a quiet tick, nothing: %s" % o["mark"])
    check(o["vision"] == [["Local: ghost part", True]], "GEMINI98: the old local button's answer reads as a Local badge (legacy, not drawn twice)")
    check(o["ops"] == "Gemini today: 3 of 40 calls (37 left) · ready · on for new requests · 1 fallback to the local model (Gemini failed: timeout)" and "not ready: no rule" in o["ops0"],
          "GEMINI98: the Ops line: %s" % o["ops"])
    check(o["fb"][0] == ["Gemini: extra leg f04 · run/side", "model eye-gemini"] and o["fb"][1] == ["legs f02 · run/side", "model"], "GEMINI98: the request card's badges: Gemini named and coloured, pass 96's unchanged: %s" % o["fb"])
    rd = lambda n: open(os.path.join(HERE, n), encoding="utf-8").read()  # noqa: E731
    idx = rd("index.html")
    check('src="eyes.js"' in idx and idx.index('src="eyes.js"') < idx.index('src="jobs.js"') and 'href="eyes.css"' in idx, "GEMINI98: index.html loads eyes.js (before jobs.js) and eyes.css")
    fr, lk, jj = rd("frames.js"), rd("looks.js"), rd("jobs.js")
    check("B('Ask Gemini'" in fr and "Eyes.askFrames(" in fr and "Eyes.markCell(" in fr and "Eyes.badgeSpans(" in fr and "B('Ask the local vision model'" in fr,
          "GEMINI98: the Frames view: Ask Gemini beside Ask the local vision model, the badges and the cell marks")
    check("b('Check with Gemini'" in lk and "Eyes.lookLine(" in lk, "GEMINI98: the look card: Check with Gemini and the eyes' line")
    check("text: 'Check with Gemini'" in jj and "Eyes.opsInto(box)" in jj and "eye-fallback" in jj, "GEMINI98: the job card's Check with Gemini, the Ops line, the red fallback lines")
    ey = rd("eyes.js")
    check("'/api/eyes/check'" in ey and "/ask_gemini" in ey, "GEMINI98: eyes.js posts the two routes")
