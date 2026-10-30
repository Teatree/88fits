"""Pass 114, lane EDITOR: editable JSON windows, a clear Godot-lock message, the bullet-heaven trigger ranges (Garry,
2026-10-29: "Allow for editing the JSON directly in the 'Show JSON' window"; "Make the message about the Godot lock
clearer - oftentimes this is happening because the build is being built and I'm trying to make changes in the level
editor. This is preventing me from making saves"; "add the option of randomization for the starting pattern ... make it
a range between 10 and 15 for example. Also ... those cooldowns should be after the attack is actually over").

Groups:
  json   json_edit.js under Node: a typed mistake found with its line and column in plain words, nothing taken; an
         object replaced in place (the same object, every key as typed); the pages that showed a JSON peek use it
         (assets.js, inspector.js, boss_attacks.js, settings.js), index.html loads it, the derived peeks say so
  lock   app.js's lockWords / importOutcome under Node: Garry's example sentence for the build, the build's three cases
         (in it, not in it, cannot say), the tests, Claude's script, a Test-in-game window, an unknown and a stale lock
         (with how to clear it), one short line with the detail beside it; server.godot_holder on stand-in lock records;
         locks.py's note and its named Godot runs on a temporary lock folder; every Save waits SAVE_LOCK_WAIT and its
         answer carries the job and the holder (Handler._send); ship.sh / ship_prod.sh name the build and note their
         steps; every page's Save line goes through App.saveStatus
  boss   boss_model.js's ranges (rangeOf, triggerProblem, patternSchedule, patternDue with this fight's rolls) against
         BossAttackDef.TRIGGER_RANGES and boss_attacks_io.trigger_problem; the tab's three range rows, its help and its
         how-to (the same boxes as docs/howto/boss_bullet_heaven.md); the save route on a temporary copy refuses a
         min above its max and keeps a range as a list; the three shipped attacks clean and under 600 bullets
Nothing here writes under game/ or tools/dl/locks/.
"""
import io
import json
import os
import re
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const dir = path.dirname(process.argv[2]);
const J = require(path.join(dir, 'json_edit.js'));
const BM = require(path.join(dir, 'boss_model.js'));
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  // json
  out.parse = q.texts.map((t) => { const r = J.parse(t); return { ok: r.ok, line: r.line, col: r.col, where: J.where(r) }; });
  const target = { a: 1, keep: 'x', nested: { b: 2 } };
  const same = J.replaceInto(target, { a: 5, extra: [1, 2], nested: { c: 3 } });
  out.replace = { same: same === target, keys: Object.keys(target), a: target.a, extra: target.extra, nested: target.nested };
  out.obj = [J.mustBeObject({}), J.mustBeObject([1]), J.mustBeObject(3), J.mustBeObject(null)];
  // lock: app.js's pure helpers cut out of the file
  const app = fs.readFileSync(path.join(dir, 'app.js'), 'utf8');
  const fn = (name) => {
    const i = app.indexOf(`function ${name}(`);
    if (i < 0) return '';
    let k = app.indexOf('{', i), depth = 0;
    for (; k < app.length; k++) { const ch = app[k]; if (ch === '{') depth++; else if (ch === '}') { depth--; if (depth === 0) break; } }
    return app.slice(i, k + 1);
  };
  const ctx = { Math, Number, String, Object, Array, isFinite, console };
  vm.createContext(ctx);
  vm.runInContext([fn('fmtAge'), fn('lockWords'), fn('importOutcome'), fn('saveOutcome')].join('\n') + '\nthis.oc = importOutcome; this.lw = lockWords; this.so = saveOutcome;', ctx);
  out.oc = q.answers.map((r) => ctx.oc(r, 'Saved enemies/goblin.json at 12:03'));
  out.map = ctx.so({ ok: true, wrote: 'm.json', import_ok: null, import_job: 'j9', lock: q.answers[0].lock }, '12:03');
  // boss
  out.range = q.ranges.map((v) => BM.rangeOf(v, 45));
  out.prob = q.ranges.map((v) => BM.triggerProblem('first_after', v));
  const a = { kind: 'pattern', id: 'x', name: 'x', emitters: [{ shape: 'ring' }], tell: { seconds: 2 }, timing: { duration: 16 }, spent: { seconds: 2.5 },
    trigger: { first_after: [10, 15], first_by: [30, 40], cooldown: [20, 30], first_at_hp: 0.6 } };
  out.sched = BM.patternSchedule(a, 3);
  out.due = [BM.patternDue(a, 12.4, 0.1, 0, -1e9, { first_after: 12.5 }), BM.patternDue(a, 12.5, 0.1, 0, -1e9, { first_after: 12.5 }),
    BM.patternDue(a, 10, 0.1, 0, -1e9), BM.patternDue(a, 69.9, 0.1, 1, 50, { cooldown: 20 }), BM.patternDue(a, 70, 0.1, 1, 50, { cooldown: 20 })];
  out.fmt = [BM.fmtRange([10, 15]), BM.fmtRange([45, 45])];
  out.tr = BM.TRIGGER_RANGES;
  out.issues = q.trio.map((t) => { const i = BM.issues(t); return { errors: i.errors, warnings: i.warnings, peak: BM.simulate(t, 1 / 20).peak }; });
  out.bad = BM.issues(Object.assign({}, a, { trigger: { first_after: [15, 10], first_by: 'soon', cooldown: [-1, 4] } })).errors;
  out.okRange = BM.issues(a).errors;
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(rel):
    with open(os.path.join(ROOT, rel), "r", encoding="utf-8") as f:
        return f.read()


class _FakeJobs:
    def __init__(self, kinds):
        self.kinds = kinds

    def get(self, job_id):
        k = self.kinds.get(job_id)
        return {"id": job_id, "kind": k, "title": "a title"} if k else None


def _holder_checks(check, server):
    saved = server.JOBS
    try:
        server.JOBS = _FakeJobs({"j1": "launch", "j2": "import", "j3": "art"})
        H = server.godot_holder
        base = {"owner_file": True, "alive": True, "pid": 7, "job": "", "note": "", "age_s": 360}
        b1 = H(dict(base, who="the build (ship.sh --quick)", note="tests", imported=True))
        check(b1["kind"] == "build" and b1["label"] == "the build (ship.sh)" and b1["in_build"] is False and b1["step"] == "tests"
              and b1["until"] == "when the build finishes" and b1["age_s"] == 360, "EDITOR114 lock: the build past its import: not in this build: %s" % b1)
        b2 = H(dict(base, who="ship.sh", note="import", imported=False))
        check(b2["kind"] == "build" and b2["in_build"] is True, "EDITOR114 lock: an older ship.sh name at its first step: in this build: %s" % b2)
        b3 = H(dict(base, who="the build (ship.sh)", note="json -> tres", imported=False))
        check(b3["in_build"] is None, "EDITOR114 lock: the build reading the JSON now: cannot say: %s" % b3)
        b4 = H(dict(base, who="the production build (ship_prod.sh)", note="plan", imported=True))
        check(b4["label"] == "the production build (ship_prod.sh)" and b4["in_build"] is False, "EDITOR114 lock: the production build: %s" % b4)
        t = H(dict(base, who="cli godot", note="gdUnit tests res://tests/pass113_BOSS_test.gd"))
        check(t["kind"] == "tests" and "the tests" in t["label"] and t["until"] == "when the tests finish", "EDITOR114 lock: the tests: %s" % t)
        c = H(dict(base, who="cli godot", note="smoke_run.gd"))
        check(c["kind"] == "claude" and c["label"] == "a script from Claude: smoke_run.gd", "EDITOR114 lock: Claude's script by name: %s" % c)
        ln = H(dict(base, who="level_editor", job="j1"))
        check(ln["kind"] == "launch" and "Test-in-game" in ln["label"] and "close that game window" in ln["until"], "EDITOR114 lock: a Test-in-game window: %s" % ln)
        im = H(dict(base, who="level_editor", job="j2"))
        jb = H(dict(base, who="level_editor", job="j3"))
        check(im["kind"] == "import" and jb["kind"] == "job" and "j3" in jb["label"], "EDITOR114 lock: an import job, another job: %s %s" % (im, jb))
        sv = H(dict(base, who="level_editor save", note="import_json only=maps/red_canyon"))
        check(sv["kind"] == "save", "EDITOR114 lock: another Save's import: %s" % sv)
        un = H({"owner_file": False, "who": "unknown process", "age_s": 9000, "alive": None})
        check(un["kind"] == "unknown" and "python tools/locks.py status" in un["until"], "EDITOR114 lock: an unknown holder says how to look and clear: %s" % un)
        st = H(dict(base, who="cli godot", alive=False))
        check(st["kind"] == "stale" and "python tools/locks.py status" in st["until"], "EDITOR114 lock: a dead holder: %s" % st)
        check(H({"who": "cli godot", "age_s": 4856})["kind"] == "claude", "EDITOR114 lock: an old-style record (who, age_s) still reads")
    finally:
        server.JOBS = saved


def _locks_checks(check):
    import locks
    tmp = tempfile.mkdtemp(prefix="le_editor114_locks_")
    saved = locks.LOCK_DIR
    try:
        locks.LOCK_DIR = tmp
        lk = locks.acquire("sim", "the build (ship.sh --quick)", wait=False, log=lambda m: None)
        ok = locks.set_note("sim", "tests", {"imported": True})
        s = locks.status("sim")
        check(lk is not None and ok and s["note"] == "tests" and s.get("imported") is True and s["who"] == "the build (ship.sh --quick)",
              "EDITOR114 lock: locks.set_note writes the holder's step and fields: %s" % s)
        owner = os.path.join(tmp, "sim.lock", "owner.json")
        with open(owner, "r", encoding="utf-8") as f:
            o = json.load(f)
        mine = o["pid"]
        o["pid"] = 4   # someone else's (the System process: alive, never this one)
        with open(owner, "w", encoding="utf-8") as f:
            json.dump(o, f)
        check(not locks.set_note("sim", "x") and locks.status("sim")["note"] == "tests", "EDITOR114 lock: only the holder notes")
        o["pid"] = mine
        with open(owner, "w", encoding="utf-8") as f:
            json.dump(o, f)
        lk.release()
        check(locks.status("sim") is None and not locks.set_note("sim", "x"), "EDITOR114 lock: a free lock takes no note")
    finally:
        locks.LOCK_DIR = saved
        shutil.rmtree(tmp, ignore_errors=True)
    n = [locks.godot_note(["--headless", "--path", "g", "--script", "res://tools/smoke_run.gd", "--", "seconds=90"]),
         locks.godot_note(["--headless", "-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", "--ignoreHeadlessMode", "-a", "res://tests/x_test.gd"]),
         locks.godot_note(["--headless", "--path", "g", "--export-release", "Android", "export/88fits.apk"]),
         locks.godot_note(["--path", "g", "-e"])]
    check(n == ["smoke_run.gd", "gdUnit tests res://tests/x_test.gd", "export Android", "the editor"], "EDITOR114 lock: a Godot command's note: %s" % n)
    src = _read("tools/locks.py")
    check('os.environ.get("GODOT_LOCK_WHO") or "cli godot"' in src and "note=godot_note(args)" in src and 'if cmd == "note":' in src,
          "EDITOR114 lock: tools/godot.sh's runs carry their note; GODOT_LOCK_WHO names another owner; the note command")


class _FakeLocks:
    def __init__(self, real, rec):
        self.real, self.rec, self.timeouts = real, rec, []

    def acquire(self, name, who, note="", timeout=None, log=None, **kw):
        self.timeouts.append(timeout)
        return None

    def status(self, name=None):
        return dict(self.rec)

    def __getattr__(self, k):
        return getattr(self.real, k)


class _FakeHandler:
    def __init__(self):
        self.wfile = io.BytesIO()
        self.code = None

    def send_response(self, c):
        self.code = c

    def send_header(self, *a):
        pass

    def end_headers(self):
        pass


def _send_checks(check, server):
    saved = (server.locks, server.GODOT, server.JOBS)
    tmp = tempfile.mkdtemp(prefix="le_editor114_send_")
    try:
        fake_godot = os.path.join(tmp, "fake-godot.exe")
        open(fake_godot, "wb").close()
        server.GODOT = fake_godot

        class _Q:
            def __init__(self):
                self.jobs = []

            def enqueue(self, kind, target, spec, title=None):
                j = {"id": "jQ%d" % (len(self.jobs) + 1), "kind": kind, "state": "queued", "spec": dict(spec)}
                self.jobs.append(j)
                return dict(j)

            def list(self, since_rev=None):
                return {"jobs": [dict(j) for j in self.jobs]}

            def get(self, jid):
                return None
        server.JOBS = _Q()
        fl = _FakeLocks(saved[0], {"owner_file": True, "alive": True, "who": "the build (ship.sh)", "note": "tests", "imported": True, "age_s": 400, "pid": 5})
        server.locks = fl
        server._IMPORT_INFO.last = None
        ok, out = server.run_import("enemies/goblin")
        check(ok is None and fl.timeouts[-1] == server.SAVE_LOCK_WAIT and "the build (ship.sh)" in out,
              "EDITOR114 lock: every Save's import waits SAVE_LOCK_WAIT (%s s), then queues, naming the build: %s / %s" % (server.SAVE_LOCK_WAIT, fl.timeouts, out))
        h = _FakeHandler()
        body = {"ok": True, "changed": ["hp"], "import_ok": ok, "output": out}
        server.Handler._send(h, 200, body)
        sent = json.loads(h.wfile.getvalue().decode("utf-8"))
        check(sent.get("import_job") == "jQ1" and isinstance(sent.get("lock"), dict) and sent["lock"]["kind"] == "build" and sent["lock"]["in_build"] is False,
              "EDITOR114 lock: an answer whose import waits carries the queued job and the holder: %s" % {k: sent.get(k) for k in ("import_job", "lock")})
        h2 = _FakeHandler()
        server.Handler._send(h2, 200, {"ok": True, "import_ok": True, "output": "import_json: wrote 1"})
        sent2 = json.loads(h2.wfile.getvalue().decode("utf-8"))
        check("lock" not in sent2 and "import_job" not in sent2, "EDITOR114 lock: an import that ran carries no holder")
        server._IMPORT_INFO.last = None
    finally:
        server.locks, server.GODOT, server.JOBS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def _page_checks(check):
    page = {n: _read("tools/level_editor/" + n) for n in ("assets.js", "inspector.js", "boss_attacks.js", "settings.js", "drivers.js", "jobs.js", "index.html",
                                                            "creatures.js", "looks.js", "skins.js", "items.js", "app.js", "boss_model.js")}
    idx = page["index.html"]
    check(0 < idx.find('src="util.js"') < idx.find('src="json_edit.js"') < idx.find('src="inspector.js"'), "EDITOR114 json: index.html loads json_edit.js after util.js, before the tabs")
    check("JsonEdit.modal({" in page["assets.js"] and "replaceInto(data, v)" in page["assets.js"] and "Show / edit the JSON" in page["assets.js"]
          and "onSave: () => save(tabOf(doc.kind))" in page["assets.js"], "EDITOR114 json: the Enemies / Heroes / Items window is editable (Apply, Ctrl+S saves)")
    check("JsonEdit.inline(container, {" in page["inspector.js"] and "App.apply(() => { JsonEdit.replaceInto(obj, v); });" in page["inspector.js"],
          "EDITOR114 json: a roster row, a wave and an event take their JSON as typed (one undoable edit)")
    check("function jsonWindow()" in page["boss_attacks.js"] and "text: 'JSON…'" in page["boss_attacks.js"] and "document.querySelector('.jedit-back')" in page["boss_attacks.js"],
          "EDITOR114 json: the Boss attacks tab has its JSON window, which owns the keys while open")
    check("JsonEdit.inline(card, {" in page["settings.js"], "EDITOR114 json: the map's other keys are editable")
    check("read-only (derived)" in page["drivers.js"] and "read-only (derived" in page["jobs.js"], "EDITOR114 json: the derived peeks (a driver's meta, a job's spec) say read-only (derived)")
    css = _read("tools/level_editor/style.css")
    check(".amodal.jedit {" in css and "height: 92vh" in css and "monospace" in css.split(".jedit-text {")[1].split("}")[0], "EDITOR114 json: the window is big and monospace")
    for f, n in (("assets.js", 1), ("boss_attacks.js", 3), ("creatures.js", 2), ("looks.js", 3), ("skins.js", 1), ("items.js", 3)):
        got = page[f].count("App.saveStatus(")
        check(got >= n, "EDITOR114 lock: %s's Save lines go through App.saveStatus (%d of %d)" % (f, got, n))
    check("importOutcome, lockWords, saveStatus, fmtAge," in page["app.js"] and "IMPORT NOT RUN" not in page["boss_attacks.js"],
          "EDITOR114 lock: App exports the wording; the Boss attacks tab no longer says IMPORT NOT RUN when the import is only queued")
    for f, who, mark in (("tools/ship.sh", '"the build (ship.sh $*)"', 'import_json.gd 2>&1 | tail -n 1; IMPORTED=1'),
                         ("tools/ship_prod.sh", '"the production build (ship_prod.sh)"', 'die "the staging copy"\nIMPORTED=1')):
        s = _read(f)
        check(("acquire godot %s" % who) in s and 'python tools/locks.py note godot "$1" --pid "${SHELL_PID:-0}" --set "imported=$IMPORTED"' in s and mark in s,
              "EDITOR114 lock: %s takes the lock as the build and notes every step (imported after its JSON step)" % f)


def _boss_route_checks(check, server):
    import boss_attacks_io as BAIO
    tmp = tempfile.mkdtemp(prefix="le_editor114_boss_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        os.makedirs(os.path.join(server.CONTENT, "boss_attacks"))
        os.makedirs(os.path.join(server.CONTENT, "sounds"))
        with open(os.path.join(server.CONTENT, "sounds", "soundmap.json"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"sounds": {}}))
        r = BAIO.create(server, "t_rng", "Range", "", "pattern")
        p = os.path.join(server.CONTENT, "boss_attacks", "t_rng", "t_rng.json")
        d = json.load(open(p, encoding="utf-8"))
        bad = json.loads(json.dumps(d))
        bad["trigger"]["first_after"] = [15, 10]
        rb = BAIO.save(server, "t_rng", bad, None)
        check(r["ok"] and not rb["ok"] and rb.get("status") == 400 and "above its max" in rb["error"], "EDITOR114 boss: a min above its max is refused: %s" % rb)
        good = json.loads(json.dumps(d))
        good["trigger"]["first_after"] = [10, 15]
        good["trigger"]["cooldown"] = [40, 50]
        rg = BAIO.save(server, "t_rng", good, None)
        back = json.load(open(p, encoding="utf-8"))
        check(rg["ok"] and back["trigger"]["first_after"] == [10, 15] and back["trigger"]["cooldown"] == [40, 50] and back["trigger"]["first_by"] == d["trigger"]["first_by"],
              "EDITOR114 boss: a range is written as a list, the other keys kept: %s" % back.get("trigger"))
        neg = json.loads(json.dumps(good))
        neg["trigger"]["first_by"] = -3
        check(not BAIO.save(server, "t_rng", neg, None)["ok"], "EDITOR114 boss: a number below 0 is refused")
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def checks(check, run_node, server):
    import boss_attacks_io as BAIO
    trio = []
    for aid in ("royal_dust_devil", "venom_monsoon", "hellbrand_mandala"):
        with open(os.path.join(ROOT, "game", "content", "boss_attacks", aid, aid + ".json"), encoding="utf-8") as f:
            trio.append(json.load(f))
    texts = ['{"a": 1,\n  "b": }', '{"a": 1,}', '{"a": 1\n "b": 2}', '{"a": 1', '', '{"ok": [1, {"b": null}], "c": -1.5e3}']
    build = {"kind": "build", "label": "the build (ship.sh)", "age_s": 360, "step": "tests", "in_build": False, "until": "when the build finishes", "who": "the build (ship.sh)"}
    answers = [
        {"ok": True, "import_ok": None, "import_job": "j1", "import_joined": False, "lock": build, "output": "held"},
        {"ok": True, "import_ok": None, "import_job": "j1", "import_joined": False, "lock": dict(build, in_build=True, step="import"), "output": ""},
        {"ok": True, "import_ok": None, "import_job": "j1", "import_joined": True, "lock": dict(build, in_build=None, step="json -> tres"), "output": ""},
        {"ok": True, "import_ok": None, "import_job": "j2", "lock": {"kind": "tests", "label": "the tests (a script from Claude: gdUnit tests)", "age_s": 240, "until": "when the tests finish"}, "output": ""},
        {"ok": True, "import_ok": None, "import_job": "j3", "lock": {"kind": "claude", "label": "a script from Claude: smoke_run.gd", "age_s": 90, "until": "when that script finishes"}, "output": ""},
        {"ok": True, "import_ok": None, "import_job": "j4", "lock": {"kind": "launch", "label": "a Test-in-game window (job j7)", "age_s": 30, "until": "when you close that game window"}, "output": ""},
        {"ok": True, "import_ok": None, "import_job": "j5", "lock": {"kind": "unknown", "label": "an unknown process (the lock has no owner file)", "age_s": 9000, "until": "only when someone clears it"}, "output": ""},
        {"ok": True, "import_ok": None, "import_job": "j6", "lock": {"kind": "stale", "label": "a process that has ended (pid 4, cli godot)", "age_s": 50, "until": "as soon as the next import takes the lock"}, "output": ""},
        {"ok": True, "import_ok": True, "output": "import_json: wrote 1"},
        {"ok": True, "import_ok": False, "output": "a\nSCRIPT ERROR: res://x.gd:3"},
        {"ok": True, "import_ok": None, "import_job": None, "lock": build, "output": "no import job could be queued: the jobs module is not here yet"},
    ]
    ranges = [12, [10, 15], [15, 10], [-3, 5], [7], "soon", [1, 2, 3]]
    res = run_node({"texts": texts, "answers": answers, "ranges": ranges, "trio": trio}, RUNNER)
    if not res:
        check(False, "EDITOR114: json_edit.js, app.js's helpers and boss_model.js ran under node")
        return
    # ---------------------------------------------------------------- json
    pr = res["parse"]
    check(not pr[0]["ok"] and pr[0]["line"] == 2 and pr[0]["col"] == 8 and "expected a value" in pr[0]["where"] and "nothing was changed" in pr[0]["where"],
          "EDITOR114 json: a missing value is found on its line and column: %s" % pr[0])
    check("comma before }" in pr[1]["where"] and pr[2]["line"] == 2 and "missing comma" in pr[2]["where"] and "ends too soon" in pr[3]["where"] and "empty" in pr[4]["where"],
          "EDITOR114 json: a trailing comma, a missing comma, a missing }, an empty box: %s" % [p["where"] for p in pr[1:5]])
    check(pr[5]["ok"], "EDITOR114 json: good JSON parses")
    rp = res["replace"]
    check(rp["same"] and rp["keys"] == ["a", "extra", "nested"] and rp["a"] == 5 and rp["extra"] == [1, 2] and rp["nested"] == {"c": 3},
          "EDITOR114 json: replaceInto keeps the object and takes every key as typed (a key left out goes): %s" % rp)
    check(res["obj"][0] == "" and all(res["obj"][1:]), "EDITOR114 json: only one JSON object is taken: %s" % res["obj"])
    _page_checks(check)
    # ---------------------------------------------------------------- lock (the words)
    oc = res["oc"]
    want = ("Saved. The build (ship.sh) has been running for 6 min and holds Godot (now at its tests), so the import waits; it runs by itself when the "
            "build finishes. This build will NOT include this change; the next one will.")
    check(oc[0]["kind"] == "busy" and oc[0]["watch"] == "j1" and oc[0]["detail"].startswith(want) and "not in this build" in oc[0]["text"]
          and "queued as job j1" in oc[0]["text"] and len(oc[0]["text"]) < 160 and "\n" not in oc[0]["text"],
          "EDITOR114 lock: Garry's example: one short line, the sentence in the detail: %s" % oc[0])
    check("goes into this build" in oc[1]["text"] and "will include this change" in oc[1]["detail"], "EDITOR114 lock: a build before its JSON step takes the change: %s" % oc[1]["text"])
    check("may miss this build" in oc[2]["text"] and "may not include" in oc[2]["detail"] and "joined the import job j1" in oc[2]["detail"], "EDITOR114 lock: a build reading the JSON now: %s" % oc[2]["text"])
    check("the tests" in oc[3]["text"] and "when the tests finish" in oc[3]["detail"], "EDITOR114 lock: the tests: %s" % oc[3])
    check("a script from Claude: smoke_run.gd" in oc[4]["text"] and "when that script finishes" in oc[4]["detail"], "EDITOR114 lock: Claude's script: %s" % oc[4])
    check("Test-in-game window: close it" in oc[5]["text"] and "close that game window" in oc[5]["detail"], "EDITOR114 lock: a Test-in-game window: %s" % oc[5])
    check("unknown process" in oc[6]["text"] and "python tools/locks.py status" in oc[6]["detail"] and "release godot --force" in oc[6]["detail"],
          "EDITOR114 lock: an unknown holder: how to look and clear: %s" % oc[6]["detail"])
    check("has ended" in oc[7]["text"] and "python tools/locks.py status" in oc[7]["detail"], "EDITOR114 lock: a stale lock: %s" % oc[7])
    check(oc[8]["kind"] == "good" and oc[8]["text"].endswith("· import OK") and oc[9]["kind"] == "bad" and "SCRIPT ERROR" in oc[9]["text"],
          "EDITOR114 lock: an import that ran, one that failed")
    check(oc[10]["kind"] == "bad" and "NOT IMPORTED" in oc[10]["text"] and "jobs module" in oc[10]["detail"], "EDITOR114 lock: no job could be queued: %s" % oc[10])
    check(all("Saving and importing" not in o["text"] for o in oc), "EDITOR114 lock: no answer leaves the line at 'Saving and importing…'")
    check(res["map"]["kind"] == "busy" and "not in this build" in res["map"]["text"] and res["map"]["text"].startswith("Saved m.json at 12:03"),
          "EDITOR114 lock: the map's Save uses the same words: %s" % res["map"])
    _holder_checks(check, server)
    _locks_checks(check)
    _send_checks(check, server)
    # ---------------------------------------------------------------- boss
    rr = res["range"]
    check(rr == [[12, 12], [10, 15], [10, 15], [0, 5], [7, 7], [45, 45], [45, 45]], "EDITOR114 boss: rangeOf is BossAttackDef.range_of: %s" % rr)
    pb = res["prob"]
    check(pb[0] == "" and pb[1] == "" and "above its max" in pb[2] and "below 0" in pb[3] and "two numbers" in pb[4] and "a number or a range" in pb[5] and "two numbers" in pb[6],
          "EDITOR114 boss: triggerProblem: %s" % pb)
    check([BAIO.trigger_problem("first_after", v) == "" for v in ranges] == [p == "" for p in pb], "EDITOR114 boss: the server refuses what the page marks: %s" % pb)
    gd = _read("game/core/data/BossAttackDef.gd")
    m = re.search(r"const TRIGGER_RANGES := \[(.*?)\]", gd)
    gd_keys = [x.strip().strip('"') for x in m.group(1).split(",")] if m else []
    check(res["tr"] == gd_keys == list(BAIO.TRIGGER_RANGES) == ["first_after", "first_by", "cooldown"], "EDITOR114 boss: TRIGGER_RANGES agree (game, page, server): %s %s" % (res["tr"], gd_keys))
    sc = res["sched"]
    near = lambda a, b: abs(float(a) - float(b)) < 1e-6
    # 2 s tell + 16 s + 2.5 s spent = 20.5 s; the first 10 s (HP at once) to 40 s (full HP: At the latest's top)
    check(near(sc[0]["start"][0], 10) and near(sc[0]["start"][1], 40) and near(sc[0]["end"][0], 30.5) and near(sc[0]["end"][1], 60.5)
          and near(sc[1]["start"][0], 50.5) and near(sc[1]["start"][1], 90.5) and near(sc[2]["start"][0], 91) and near(sc[2]["start"][1], 141),
          "EDITOR114 boss: the readout's earliest-latest: each next one the cooldown after the last one was completely over: %s" % sc)
    check(res["due"] == [False, True, True, False, True], "EDITOR114 boss: patternDue plays this fight's rolls (the low end without): %s" % res["due"])
    check(res["fmt"] == ["10–15 s", "45 s"], "EDITOR114 boss: fmtRange: %s" % res["fmt"])
    check(any("above its max" in e for e in res["bad"]) and any("first_by" in e for e in res["bad"]) and any("below 0" in e for e in res["bad"]) and not res["okRange"],
          "EDITOR114 boss: the page's issues refuse a bad range and take a good one: %s" % res["bad"])
    for aid, r in zip(("royal_dust_devil", "venom_monsoon", "hellbrand_mandala"), res["issues"]):
        check(not r["errors"] and 30 <= r["peak"] <= 600, "EDITOR114 boss: %s clean, %d bullets at its peak (under 600): %s" % (aid, r["peak"], r))
    ba = _read("tools/level_editor/boss_attacks.js")
    rows = re.findall(r"\{ g: 'trigger', k: '(\w+)', label: '[^']*', type: '(\w+)'", ba)
    check(dict(rows) == {"first_after": "range", "first_at_hp": "number", "first_by": "range", "cooldown": "range"}, "EDITOR114 boss: the three trigger rows are fixed / range boxes: %s" % rows)
    check("function rangeInput(" in ba and "completely over" in ba and "COMPLETELY over" in ba and "M.patternSchedule(d, 3)" in ba,
          "EDITOR114 boss: the range control, the cooldown's start in its help and the facts, the In a fight readout")
    howto = _read("docs/howto/boss_bullet_heaven.md")
    for box in ("Bullets for (s)", "Range (m)", "Bullets a volley", "Spread (°)", "Opening", "Volleys a second", "Not before (s)", "Then every (s)", "Save attack"):
        check(box in howto and box in ba.split("const HOWTO = [")[1].split("];")[0], "EDITOR114 boss: the how-to (the doc and the tab's fold) names %s" % box)
    check("howtoBox()" in ba, "EDITOR114 boss: the tab shows the how-to")
    _boss_route_checks(check, server)
