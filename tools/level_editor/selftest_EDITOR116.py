"""Pass 116, lane EDITOR: icon re-rolls, stage clocks, row numbers (its Mirror tab left with the Upgrade board in pass 129).

Groups:
  clock   stage_model.js under Node: a map second shown on a stage tab and typed back (both ways, the whole map
          unchanged), rows numbered within their stage by start second with each stage's count
  icon    jobs.candidate_defaults fills a card look's own words and style (not the base art_prompt) and its painted
          seed; jobs._plan carries the subject (with typed fix words), the seeds N and the first seed into the argv and
          the JOBS entry gen_icon_cands paints
  page    the Mirror tab is off the page and out of app.js and server.py (pass 129); the clock fields are marked
Nothing here writes under game/.
"""
import json
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def _node(src):
    p = subprocess.run(["node", "-e", src], capture_output=True, text=True, cwd=HERE, timeout=60)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[-800:])
    return json.loads(p.stdout)


CLOCK_JS = r"""
const S = require('./stage_model.js');
const W = [{start: 0, end: 430}, {start: 430, end: 1030}, {start: 1030, end: 1810}];
const rows = [{t: 500}, {t: 10}, {t: 20, until: 900}, {t: 1100}, {t: 430}, {t: 5000}];
console.log(JSON.stringify({
  a: S.toStageClock(495, 430), b: S.fromStageClock(65, 430), c: S.toStageClock(495, null), d: S.fromStageClock(65, null),
  e: S.fromStageClock(S.toStageClock(1234, 1030), 1030), f: S.toStageClock(null, 430), g: S.toStageClock('', 430),
  n: S.rowNumbers(rows, W), z: S.rowNumbers([], W).counts }));
"""

def _clock_checks(check):
    r = _node(CLOCK_JS)
    check(r["a"] == 65 and r["b"] == 495, "EDITOR116 clock: 8:15 on the map is 1:05 on stage 2's tab and back (%s, %s)" % (r["a"], r["b"]))
    check(r["c"] == 495 and r["d"] == 65, "EDITOR116 clock: the whole-map view keeps absolute times")
    check(r["e"] == 1234 and r["f"] is None and r["g"] == "", "EDITOR116 clock: round trip exact, empty stays empty")
    by = r["n"]["byRow"]
    check([(x["stage"], x["n"]) for x in by] == [(1, 2), (0, 1), (0, 2), (2, 1), (1, 1), (2, 2)],
          "EDITOR116 index: rows numbered within their stage by start (a boundary start belongs to the later stage; past the end, the last): %s" % by)
    check(r["n"]["counts"] == [2, 2, 2] and r["z"] == [0, 0, 0], "EDITOR116 index: each stage's count")


def _icon_checks(check):
    import jobs
    d = jobs.candidate_defaults("icon_cands", {"kind": "passive", "id": "aegis", "code": "B"})
    check("tarot card" in d["fields"]["subject"] and "recipe" in d["sources"]["subject"] and d["fields"].get("style"),
          "EDITOR116 icon: a card look re-rolls from its own words and style, not the base art_prompt")
    check(isinstance(d.get("painted"), dict) and d["painted"].get("seed") and d.get("words", {}).get("style"),
          "EDITOR116 icon: the painted seed and the words' pieces for the form's preview")
    base = jobs.candidate_defaults("icon_cands", {"kind": "passive", "id": "aegis", "code": ""})
    check("tarot" not in base["fields"]["subject"], "EDITOR116 icon: the base icon keeps the item's art_prompt")
    spec = {"seeds": 5, "first_seed": 4242, "subject": "a brass key. Fix: two teeth, not three", "style": "", "screen": "blue"}
    jobs._seed_candidates("icon_cands", {"kind": "passive", "id": "aegis", "code": "B"}, spec)
    p = jobs._plan({"id": "selftest116", "kind": "icon_cands", "method": "icon_cands", "target": {"kind": "passive", "id": "aegis", "code": "B"}, "spec": spec})
    argv = p.get("argv") or []
    check(p["tool"] == "gen_icon_cands" and "--seeds" in argv and argv[argv.index("--seeds") + 1] == "5"
          and "--first-seed" in argv and argv[argv.index("--first-seed") + 1] == "4242",
          "EDITOR116 icon: N candidates and the first seed reach the argv (%s)" % argv)
    check(p["icon_job"]["subject"] == spec["subject"] and p["icon_job"].get("screen") == "blue" and p["icon_job"].get("style"),
          "EDITOR116 icon: the typed prompt (with its fix words), the screen and the look's style reach the painter's JOBS entry")


def _page_checks(check):
    idx = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
    app = open(os.path.join(HERE, "app.js"), encoding="utf-8").read()
    fields = open(os.path.join(HERE, "fields.js"), encoding="utf-8").read()
    srv = open(os.path.join(HERE, "server.py"), encoding="utf-8").read()
    check('data-tab="mirror"' not in idx and "mirror.js" not in idx and "mirror.css" not in idx and 'id="tab-mirror"' not in idx,
          "EDITOR116 page: the Mirror tab is off the page (pass 129: the Upgrade board is gone)")
    check("Mirror." not in app and "talents_io" not in srv and '"talents"' not in srv and "fmtClock" in app,
          "EDITOR116 page: app.js and server.py no longer know the Mirror tab; the stage clock stays")
    for f in ("mirror.js", "mirror.css", "talents_io.py"):
        check(not os.path.exists(os.path.join(HERE, f)), "EDITOR116 page: %s is gone" % f)
    check(fields.count("clock: true") == 5, "EDITOR116 page: the five run-clock fields (rows, waves, events) are marked")
    for f in ("jobs.js", "items.js", "assets.js", "forms.js", "timeline.js", "stage_tabs.js", "inspector.js", "stage_model.js"):
        p = subprocess.run(["node", "--check", os.path.join(HERE, f)], capture_output=True, text=True)
        check(p.returncode == 0, "EDITOR116 page: %s parses" % f)


def checks(check, run_node=None, server=None):
    for g in (_clock_checks, _icon_checks, _page_checks):
        try:
            g(check)
        except Exception as e:
            import traceback
            traceback.print_exc()
            check(False, "EDITOR116 %s: %s: %s" % (g.__name__, type(e).__name__, e))


if __name__ == "__main__":
    import sys
    sys.path.insert(0, HERE)
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    n = [0, 0]

    def check(ok, msg):
        n[0 if ok else 1] += 1
        if not ok:
            print("FAIL", msg)
    checks(check)
    print("%d passed, %d failed" % tuple(n))
    sys.exit(1 if n[1] else 0)
