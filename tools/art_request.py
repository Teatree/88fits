#!/usr/bin/env python3
"""The one-command art workflow for Claude (pass 96, lane REQ; the assessment's AI-05): one request in, a request id
out, one paragraph back. Stdlib only; talks to the running Level Editor (tools\\level_editor.cmd) over HTTP.

    python tools/art_request.py start --kind enemy --id desert_spider [--code SP-G] [--from SP-B] [--method creature_ctl]
                                      --goal "a cleaner side walk" [--mode auto|step|observe]
                                      [--rerolls N] [--repair-rounds N] [--minutes N] [--evals N] [--cloud-dollars X]
                                      [--prompt "..."] [--appearance "..."] [--word key=value ...] [--title "..."]
    python tools/art_request.py status <rid> [--wait [--timeout S]]      one line: state, iteration k of n, the job, the budget
    python tools/art_request.py result <rid> [--wait [--timeout S]]      the paragraph and the paths; "waiting for Garry's
                                                                         approval" while it is (the approval is his, in the page)
    python tools/art_request.py sheet <rid>                              the review sheet's path (the rare case Claude is asked to look)
    python tools/art_request.py cancel|pause|resume <rid>
    python tools/art_request.py list                                     every request, newest first
    python tools/art_request.py job <job id>                             GET /api/job/<id>/summary as lines

Options everywhere: --editor http://127.0.0.1:8787 (else LEVEL_EDITOR, else the port in the jobs lock's note, as
tools/puppet.py finds it); --json prints the server's answer as JSON.

Exit codes: 0 done / ok; 2 not final yet (running, paused, waiting for a pick or for Garry's approval); 1 failed, stopped,
cancelled, or a refused call; 3 no Level Editor answers.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
NOT_FINAL = ("queued", "running", "paused", "waiting", "approved")
FAILED = ("failed", "stopped", "cancelled")


def le_base(explicit=None):
    """The running Level Editor's address, or None. An explicit --editor (or LEVEL_EDITOR) is the only one tried: a
    test's or a tool's address must never fall through to another editor's queue."""
    cands = []
    if explicit:
        cands.append(explicit.rstrip("/"))
    elif os.environ.get("LEVEL_EDITOR"):
        cands.append(os.environ["LEVEL_EDITOR"].rstrip("/"))
    if cands:
        return _answers(cands[0])
    try:
        with open(os.path.join(REPO, "tools", "dl", "locks", "jobs.lock", "owner.json"), encoding="utf-8") as f:
            owner = json.load(f)
        m = re.search(r"port (\d+)", owner.get("note", ""))
        if m:
            cands.append("http://127.0.0.1:%s" % m.group(1))
    except Exception:
        pass
    cands.append("http://127.0.0.1:8787")
    for base in cands:
        if _answers(base):
            return base
    return None


def _answers(base):
    try:
        with urllib.request.urlopen(base + "/api/status", timeout=5) as r:
            d = json.load(r)
        return base if isinstance(d, dict) and d.get("ok") else None
    except Exception:
        return None


def api(base, method, path, body=None, timeout=60):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        txt = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(txt)
        except ValueError:
            return e.code, {"ok": False, "error": txt[:800]}
    except Exception as e:   # noqa: BLE001
        return 0, {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}


def status_line(fold):
    it = fold.get("iteration") or {}
    cur = fold.get("current_job")
    job = next((j for j in fold.get("jobs") or [] if j.get("id") == cur), None)
    bits = ["%s %s" % (fold.get("rid"), fold.get("state"))]
    if fold.get("waiting_for"):
        bits.append("waiting for %s" % ("Garry's approval" if fold["waiting_for"] == "approval" else "a pick"))
    bits.append("iteration %s of %s" % (it.get("n", 0), it.get("of", "?")))
    if job:
        bits.append("job %s %s%s" % (job["id"], job.get("state"), (" (%s)" % job["stage"]) if job.get("stage") else ""))
    bits.append(fold.get("budget_line") or "")
    if fold.get("error"):
        bits.append("error: %s" % fold["error"])
    return " · ".join(b for b in bits if b)


def result_lines(fold):
    out = [fold.get("summary") or ""]
    st = fold.get("state")
    if st == "waiting" and fold.get("waiting_for") == "approval":
        out.append("waiting for Garry's approval (the page: %s)" % fold.get("page"))
        prov = fold.get("provisional") or {}
        if prov:
            out.append("provisional: %s %s" % (prov.get("code"), json.dumps(prov.get("groups") or {})))
    if fold.get("sheet"):
        out.append("sheet: %s" % fold["sheet"])
    r = fold.get("result") or {}
    if st == "done":
        if r.get("strip"):
            out.append("strip: %s" % r["strip"])
        if r.get("entry"):
            out.append("entry: %s" % json.dumps(r["entry"], ensure_ascii=False))
        if r.get("import_job"):
            out.append("import: %s" % r["import_job"])
        if r.get("flags"):
            out.append("flags: %s" % json.dumps(r["flags"]))
        if r.get("verdicts"):
            out.append("verdicts: %s" % json.dumps(r["verdicts"]))
    if st in FAILED:
        out.append("%s%s" % (st, (": " + fold["error"]) if fold.get("error") else ""))
    return [x for x in out if x]


def exit_code(fold):
    st = fold.get("state")
    if st == "done":
        return 0
    if st in FAILED:
        return 1
    return 2


def wait_for(base, rid, timeout, poll=3.0):
    """Poll until the request is final or waits for a human; returns the last fold."""
    t0 = time.time()
    fold = None
    while True:
        st, fold = api(base, "GET", "/api/requests/%s" % rid)
        if st != 200:
            return fold
        if fold.get("state") not in NOT_FINAL or (fold.get("state") == "waiting"):
            return fold
        if timeout and time.time() - t0 > timeout:
            return fold
        time.sleep(poll)


def main(argv=None):
    ap = argparse.ArgumentParser(description="one art request for the Level Editor's loop (pass 96)")
    ap.add_argument("verb", choices=("start", "status", "result", "sheet", "cancel", "pause", "resume", "list", "job"))
    ap.add_argument("rid", nargs="?", help="the request id (or the job id for `job`)")
    ap.add_argument("--editor", default=None, help="the Level Editor's address (else LEVEL_EDITOR, else the jobs lock's note)")
    ap.add_argument("--json", action="store_true", help="print the server's answer as JSON")
    ap.add_argument("--wait", action="store_true", help="status/result: poll until final or waiting for a human")
    ap.add_argument("--timeout", type=float, default=0, help="--wait: give up after this many seconds (0 = never)")
    # start
    ap.add_argument("--kind", choices=("enemy", "boss", "hero"))
    ap.add_argument("--id")
    ap.add_argument("--code", default=None, help="the look to paint (absent: the next free code is allocated)")
    ap.add_argument("--from", dest="from_code", default=None, help="the look whose recipe the new look copies")
    ap.add_argument("--method", default=None)
    ap.add_argument("--goal", default=None)
    ap.add_argument("--mode", choices=("auto", "step", "observe"), default="auto")
    ap.add_argument("--rerolls", type=int, default=None)
    ap.add_argument("--repair-rounds", dest="repair_rounds", type=int, default=None)
    ap.add_argument("--minutes", type=float, default=None, help="lane minutes (the budget's lane_seconds)")
    ap.add_argument("--evals", type=int, default=None, help="evaluator calls")
    ap.add_argument("--cloud-dollars", dest="cloud_dollars", type=float, default=None)
    ap.add_argument("--prompt", default=None, help="brief.art_prompt")
    ap.add_argument("--appearance", default=None, help="brief.appearance")
    ap.add_argument("--word", action="append", default=[], help="brief.words key=value (a recipe word laid on the look)")
    ap.add_argument("--title", default=None)
    args = ap.parse_args(argv)

    base = le_base(args.editor)
    if base is None:
        print("no Level Editor answers (start tools\\level_editor.cmd, or pass --editor http://127.0.0.1:8787)")
        return 3

    if args.verb == "start":
        missing = [k for k in ("kind", "id", "goal") if not getattr(args, k)]
        if missing:
            print("start needs --%s" % ", --".join(missing))
            return 1
        budget = {}
        if args.rerolls is not None:
            budget["rerolls"] = args.rerolls
        if args.repair_rounds is not None:
            budget["repair_rounds"] = args.repair_rounds
        if args.minutes is not None:
            budget["lane_seconds"] = int(args.minutes * 60)
        if args.evals is not None:
            budget["evaluator_calls"] = args.evals
        if args.cloud_dollars is not None:
            budget["cloud_dollars"] = args.cloud_dollars
        words = {}
        for w in args.word:
            if "=" not in w:
                print("--word is key=value (got %s)" % w)
                return 1
            k, v = w.split("=", 1)
            words[k.strip()] = v
        brief = {k: v for k, v in (("art_prompt", args.prompt), ("appearance", args.appearance)) if v}
        if words:
            brief["words"] = words
        asset = {"kind": args.kind, "id": args.id, "code": args.code, "method": args.method, "from": args.from_code}
        body = {"goal": args.goal, "asset": asset, "mode": args.mode, "budget": budget, "brief": brief, "title": args.title}
        st, d = api(base, "POST", "/api/requests", body)
        if args.json:
            print(json.dumps(d, indent=1, ensure_ascii=False))
        if st != 200 or not d.get("ok"):
            if not args.json:
                print("refused: %s" % d.get("error", "?"))
            return 1
        fold = d.get("fold") or {}
        if not args.json:
            print("request %s started (%s %s %s): %s" % (d.get("rid"), args.kind, args.id, (fold.get("asset") or {}).get("code"), args.goal))
            print(status_line(fold))
            print("page: %s/%s" % (base, (fold.get("page") or "").lstrip("/")))
        return 0

    if args.verb == "list":
        st, d = api(base, "GET", "/api/requests")
        if args.json:
            print(json.dumps(d, indent=1, ensure_ascii=False))
        elif st == 200:
            for f in d.get("requests") or []:
                print(status_line(f))
            if not d.get("requests"):
                print("no requests yet")
        else:
            print("error: %s" % d.get("error"))
        return 0 if st == 200 else 1

    if args.verb == "job":
        if not args.rid:
            print("job needs a job id")
            return 1
        st, d = api(base, "GET", "/api/job/%s/summary" % args.rid)
        if args.json:
            print(json.dumps(d, indent=1, ensure_ascii=False))
        elif st == 200:
            print(d.get("paragraph"))
            for o in d.get("outputs") or []:
                print("  %s: %s" % (o.get("label"), o.get("file") or o.get("url") or o.get("type")))
            if d.get("sheet"):
                print("  sheet: %s" % d["sheet"])
        else:
            print("error: %s" % d.get("error"))
        if st != 200:
            return 1
        return 0 if d.get("state") == "done" else 1 if d.get("state") in ("failed", "cancelled", "interrupted") else 2

    if not args.rid:
        print("%s needs a request id" % args.verb)
        return 1
    if args.verb in ("cancel", "pause", "resume"):
        st, d = api(base, "POST", "/api/requests/%s/%s" % (args.rid, args.verb), {})
        if args.json:
            print(json.dumps(d, indent=1, ensure_ascii=False))
        elif st == 200:
            print(status_line(d))
        else:
            print("refused: %s" % d.get("error"))
        return 0 if st == 200 else 1

    if args.wait:
        fold = wait_for(base, args.rid, args.timeout)
        st = 200 if fold and fold.get("rid") else 404
    else:
        st, fold = api(base, "GET", "/api/requests/%s" % args.rid)
    if st != 200:
        print("error: %s" % (fold or {}).get("error", "no request %s" % args.rid))
        return 1
    if args.json:
        print(json.dumps(fold, indent=1, ensure_ascii=False))
        return exit_code(fold)
    if args.verb == "status":
        print(status_line(fold))
    elif args.verb == "sheet":
        print(fold.get("sheet") or "no review sheet yet")
        return 0 if fold.get("sheet") else 2
    else:
        for line in result_lines(fold):
            print(line)
    return exit_code(fold)


if __name__ == "__main__":
    sys.exit(main())
