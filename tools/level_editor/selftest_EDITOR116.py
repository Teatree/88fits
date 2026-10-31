"""Pass 116, lane EDITOR: the Mirror tab, icon re-rolls, stage clocks, row numbers.

Groups:
  clock   stage_model.js under Node: a map second shown on a stage tab and typed back (both ways, the whole map
          unchanged), rows numbered within their stage by start second with each stage's count
  mirror  mirror.js's pure helpers (the board order = TalentDef.board_before, the rank words); talents_io on a temporary
          copy of game/content/talents: read in board order, a save of one price rewrites only that key, backed up and
          imported, a 409 on a stale mtime, a bad cost refused
  icon    jobs.candidate_defaults fills a card look's own words and style (not the base art_prompt) and its painted
          seed; jobs._plan carries the subject (with typed fix words), the seeds N and the first seed into the argv and
          the JOBS entry gen_icon_cands paints
  page    index.html loads mirror.js / mirror.css and has the Mirror tab; app.js renders it; the clock fields are marked
Nothing here writes under game/.
"""
import json
import os
import shutil
import subprocess
import tempfile
import threading

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

MIRROR_JS = r"""
const M = require('./mirror.js');
const list = [{id: 'b', cost: [300], order: 2}, {id: 'a', cost: [300], order: 1}, {id: 'c', cost: [100], order: 9}];
console.log(JSON.stringify({ order: M.boardSort(list).map((x) => x.id),
  mul: M.effectAt({stat: 'max_hp', op: 'mul', value: 0.1}, 3, null), add: M.effectAt({stat: 'damage_reduction', op: 'add', value: 0.06}, 2, null),
  base: M.effectAt({stat: 'revive_hp', op: 'add', value: 0.1}, 6, {revive_hp: 0.4}), tot: M.totalCost([1, 2, 3, 4], 3) }));
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


class _Srv:
    def __init__(self, content):
        import content_io as cio
        self.CONTENT = content
        self._write_lock = threading.Lock()
        self.backups = []
        self.imports = []
        self.restore_numbers = cio.restore_numbers

    def rel(self, p):
        return os.path.relpath(p, self.CONTENT).replace("\\", "/")

    def mtime_of(self, p):
        return os.path.getmtime(p)

    def backup(self, name, p):
        self.backups.append(name)
        return "backup/" + name

    def run_import_info(self, target, who=""):
        self.imports.append(target)
        return {"ok": True, "output": "stub"}


def _mirror_checks(check):
    r = _node(MIRROR_JS)
    check(r["order"] == ["c", "a", "b"], "EDITOR116 mirror: the board order is the first price, then order (%s)" % r["order"])
    check(r["mul"] == "+30% max hp" and r["add"] == "+12% damage reduction" and r["base"] == "revive hp 100%" and r["tot"] == 6,
          "EDITOR116 mirror: the rank words (%s | %s | %s)" % (r["mul"], r["add"], r["base"]))
    import talents_io as T
    tmp = tempfile.mkdtemp(prefix="le116_")
    try:
        shutil.copytree(os.path.join(ROOT, "game", "content", "talents"), os.path.join(tmp, "talents"))
        srv = _Srv(tmp)
        d = T.read(srv)
        firsts = [T.first_price(t["json"]) for t in d["talents"]]
        check(d["ok"] and len(d["talents"]) >= 8 and firsts == sorted(firsts), "EDITOR116 mirror: talents read in board order (%s)" % d["order"])
        g = next(t for t in d["talents"] if t["id"] == "grit")
        check(bool(g["icons"]["talent"]) and len(g["icons"]["forms"]) == 2 and all(g["icons"]["forms"]), "EDITOR116 mirror: the talent's and its forms' pictures")
        p = os.path.join(tmp, "talents", "grit", "grit.json")
        src = open(p, encoding="utf-8", newline="").read()
        new = json.loads(src)
        new["cost"][2] = new["cost"][2] + 5
        res = T.save(srv, "grit", new, g["mtime"])
        after = open(p, encoding="utf-8", newline="").read()
        check(res.get("ok") and json.loads(after) == new and srv.imports == ["talents/grit"] and srv.backups,
              "EDITOR116 mirror: a price saved, backed up and imported (%s)" % res)
        a_lines, s_lines = after.split("\n"), src.split("\n")
        diff = [k for k in range(min(len(a_lines), len(s_lines))) if a_lines[k] != s_lines[k]]
        check(len(a_lines) == len(s_lines) and len(diff) == 1, "EDITOR116 mirror: only the changed price's line differs (%s)" % diff)
        back = T.read(srv)["talents"]
        check(next(t for t in back if t["id"] == "grit")["json"]["cost"][2] == new["cost"][2], "EDITOR116 mirror: the save reads back")
        new["cost"][3] += 1
        stale = T.save(srv, "grit", new, 1.0)
        check(stale.get("status") == 409, "EDITOR116 mirror: a stale page is refused")
        check(T.save(srv, "grit", dict(new, cost=[1, "x"]), None).get("status") == 400, "EDITOR116 mirror: a bad price list is refused")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


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
    check('data-tab="mirror"' in idx and 'src="mirror.js"' in idx and 'href="mirror.css"' in idx and 'id="tab-mirror"' in idx,
          "EDITOR116 page: the Mirror tab is on the page")
    check("Mirror.render(panel)" in app and "Mirror.save()" in app and "fmtClock" in app, "EDITOR116 page: app.js renders and saves it; the stage clock")
    check(fields.count("clock: true") == 5, "EDITOR116 page: the five run-clock fields (rows, waves, events) are marked")
    for f in ("mirror.js", "jobs.js", "items.js", "assets.js", "forms.js", "timeline.js", "stage_tabs.js", "inspector.js", "stage_model.js"):
        p = subprocess.run(["node", "--check", os.path.join(HERE, f)], capture_output=True, text=True)
        check(p.returncode == 0, "EDITOR116 page: %s parses" % f)


def checks(check, run_node=None, server=None):
    for g in (_clock_checks, _mirror_checks, _icon_checks, _page_checks):
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
