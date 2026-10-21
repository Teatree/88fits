"""Pass 96, lane PAGE: Garry's changes to the frame layer (1.5) and the request card with the page's minimum (1.7).

On selftest_VACE95's temporary world (a creature "bug" with looks BG-A and BG-B): Garry's label form (`SP-A / Run /
Side / Frame 07 / v2`) from the one formatter and on every served version and slot; the batch a confirm box lists
(before / after pairs, the flag deltas, the pinned re-applies, in_play, the backup folder) and the route that refuses
EVERY export without confirm; the pin re-apply at a landing (a fake queue receives the frames_export, the export packs
the pinned cell back) and the hook's in-process re-pack; a landing whose slot count or frame_px changed reports the
pins that no longer fit and keeps their versions; delete_version refusing always (retired); the render-ok harvest on a
canned line (idempotent); the landing note on the card; under Node: the labels, the picker's filters, the batch lines,
the card signature without the clock, the connection line's words, the request fold and the findings badges; the wiring.
"""
import io
import json
import os
import shutil
import sys
import tempfile
import threading
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const F = require(path.join(dir, 'frames_model.js'));
const J = require(path.join(dir, 'jobs_model.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.labels = [F.frameLabel('SP-A', 'run', 'side', 7, 2), F.frameLabel('SP-A', 'run', 'fd', 3), F.frameLabel('X', 'die', 'back'), F.nameOf({ name: 'given' }, {}), F.nameOf({ slot: 1, n: 3 }, { code: 'BG-B', base: 'idle', view: 'front' })];
  out.vtext = F.versionText({ name: 'SP-B / Run / Side / Frame 02 / v2', label: 'SP-B-2', source: 'vace', seed: 5 });
  out.vtext_old = F.versionText({ label: 'SP-B-2', source: 'vace' });
  out.marks = [F.sourceMark({ source: 'old_roll' }), F.sourceMark({ source: 'archived' }), F.sourceMark({ source: 'vace' })];
  const now = new Date('2026-10-21T12:00:00').getTime();
  const vs = [{ n: 1, time: '2026-09-01T10:00:00', source: 'installed' }, { n: 2, time: '2026-10-21T10:00:00', source: 'vace', raw: true }, { n: 3, time: '2026-10-20T10:00:00', source: 'copied' }, { n: 4, time: '2026-10-21T10:00:00', source: 'reroll' }];
  out.filt = [F.filterVersions(vs, {}, now).map((v) => v.n), F.filterVersions(vs, { days: 7 }, now).map((v) => v.n), F.filterVersions(vs, { source: 'vace' }, now).map((v) => v.n), F.filterVersions(vs, { raw: true }, now).map((v) => v.n), F.filterVersions(vs, { days: 1, source: 'reroll' }, now).map((v) => v.n)];
  out.lines = F.batchLines(q.batch).map((l) => [l.line, l.deltas, l.why]);
  out.sum = F.batchSummary(q.batch);
  out.opts = [F.SOURCE_OPTIONS.map((o) => o.v), F.TIME_OPTIONS.map((o) => o.v)];
  // jobs_model
  const j = { id: 'j1', state: 'running', progress: { stage: 'side', done: 1, total: 3 }, log_tail: ['a', 'b'], outputs: [{ url: 'x' }], started: '2026-10-21T10:00:00' };
  const s1 = J.sig(j, { hidden: false, ext: null }), s2 = J.sig(j, { hidden: false, ext: null });
  const s3 = J.sig(Object.assign({}, j, { state: 'done' }), { hidden: false, ext: null });
  const s4 = J.sig(Object.assign({}, j, { log_tail: ['a', 'c'] }), { hidden: false, ext: null });
  out.sig = [s1 === s2, s1 !== s3, s1 !== s4, !/\d{13}/.test(s1)];
  out.elapsed = [J.elapsedText('2026-10-21T10:00:00', 240, new Date('2026-10-21T10:01:23').getTime()), J.elapsedText('2026-10-21T10:00:00', null, new Date('2026-10-21T11:02:03').getTime())];
  const t = new Date('2026-10-21T13:14:15').getTime();
  out.conn = [J.connectionLine({ now: t + 20000, downSince: t, lastContact: t - 60000, netError: 'Failed to fetch' }), J.connectionLine({ now: t, lastContact: t }), J.connectionLine({ now: t, lastContact: t, apiMissing: true, apiError: 'no jobs' }), J.connectionLine({ now: t, lastContact: t, readonly: { who: 'level_editor', pid: 7 } }), J.connectionLine({ now: t, lastContact: t, readonly: { view_only: true } }), J.connectionLine({ now: t })].map((c) => [c.cls, c.text]);
  out.budget = J.budgetBars(q.fold.budget, q.fold.spent).map((b) => [b.unit, b.text, b.pct, b.full]);
  const f = J.requestFold(q.fold, new Map());
  out.fold = { chip: f.chip, iteration: f.iteration, buttons: f.buttons, lastOp: f.lastOp && f.lastOp.text, waiting: f.waiting.slice(0, 25), prov: f.provisional, jobsLine: f.jobsLine, latest: f.latestJob && f.latestJob.id, title: f.title, final: f.final };
  out.buttons = ['queued', 'running', 'paused', 'waiting', 'approved', 'done', 'failed', 'stopped', 'cancelled'].map((st) => J.buttonsFor({ state: st, waiting_for: st === 'waiting' ? 'approval' : null }));
  out.buttons_pick = J.buttonsFor({ state: 'waiting', waiting_for: 'pick' });
  const fb = J.findingsBadges(q.findings);
  out.findings = { n: fb.badges.length, texts: fb.badges.map((b) => b.text), titles: fb.badges.map((b) => b.title), cls: fb.badges.map((b) => b.cls), gates: fb.gates, ok: fb.ok };
  process.stdout.write(JSON.stringify(out));
});
"""


class FakeJobs:
    def __init__(self):
        self.calls = []
        self.n = 0

    def enqueue(self, kind, target, spec, title=None, **kw):
        self.n += 1
        job = {"id": "jfake-%04d" % self.n, "kind": kind, "target": target, "spec": spec, "title": title, "state": "queued"}
        self.calls.append(job)
        return job


def _offset(order, anims, key):
    off = 0
    for a in order:
        if a == key:
            return off
        off += int(anims.get(a, 0) or 0)
    return off


def checks(check, run_node, server):
    import numpy as np
    from PIL import Image
    import artkit
    import frames_store as FS
    import frames_io as FRIO
    import selftest_VACE95 as V95

    # ---- the one formatter
    check(FS.label_of({"slot": 7, "n": 2}, code="SP-A", base="run", view="side") == "SP-A / Run / Side / Frame 07 / v2", "label_of: Garry's form from a version record and the parts")
    check(FS.label_of(None, code="SP-A", base="run", view="fd", slot=3) == "SP-A / Run / Front ¾ / Frame 03" and FS.label_of(None, code="X", base="die", view="back") == "X / Die / Back",
          "label_of: the slot's name without a version; the view words (Front ¾, Back)")
    check(FS.NEVER_DELETED and "never deleted" in FS.NEVER_DELETED, "the never-deleted rule has its words")

    tmp = tempfile.mkdtemp(prefix="le_page96_")
    saved = {k: getattr(FS, k) for k in ("STORE", "CONTENT", "ANIM", "DRIVERS", "RAW", "BACKUPS")}
    try:
        w = V95._make_world(tmp)
        FS.STORE = os.path.join(tmp, "dl", "frames")
        FS.CONTENT = w["content"]
        FS.ANIM = os.path.join(tmp, "dl", "ai_anim")
        FS.DRIVERS = os.path.join(tmp, "dl", "drivers")
        FS.RAW = os.path.join(tmp, "dl", "ai_raw_anime")
        FS.BACKUPS = os.path.join(tmp, "backups")
        px = w["px"]
        FS.register_look("enemy", "bug", "BG-B")
        FS.register_look("enemy", "bug", "BG-A")
        look = FS.Look("enemy", "bug", "BG-B")
        g = FS.Group(look, "run", "side")

        # ---- names on every served version and slot
        d = g.detail(lambda p: "/x/" + os.path.basename(p))
        check(d["slots"][1]["name"] == "BG-B / Run / Side / Frame 01" and d["slots"][1]["versions"][0]["name"] == "BG-B / Run / Side / Frame 01 / v1" and d["slots"][1]["versions"][0]["label"] == "BG-B-1",
              "the detail: every slot and version carries Garry's name, the record's label stays: %s" % d["slots"][1]["versions"][0].get("name"))
        check(g.name_of(3) == "BG-B / Run / Side / Frame 03" and g.name_of(3, g.versions(3)[0]) == "BG-B / Run / Side / Frame 03 / v1", "Group.name_of")

        # ---- the batch a confirm box lists
        edited = w["cells_b"]["run_s"][1].copy()
        edited.paste((255, 0, 0, 255), (10, 10, 20, 20))
        v2 = g.add_version(1, edited, "cell", "repaint", by="human")
        empty = g.add_version(2, Image.new("RGBA", (px, px), (0, 0, 0, 0)), "cell", "vace", by="ai", seed=7)
        g.stage(1, v2["id"], why="test")
        g.stage(2, empty["id"], why="vace")
        b = FS.staged_batch("enemy", "bug", "BG-B", lambda p: "/x/" + os.path.basename(p))
        items = b["items"]
        check(b["ok"] and b["staged"] == 2 and b["pinned_reapply"] == 0 and b["in_play"] is True and b["backup_dir"].endswith("backups/bug") and b["strip_file"].endswith("bug_sprite_b.png") and b["replaces_installed"],
              "staged_batch: two staged, none pinned, in play, the backup folder, the strip it replaces")
        i1 = next(i for i in items if i["slot"] == 1)
        i2 = next(i for i in items if i["slot"] == 2)
        check(i1["name"] == "BG-B / Run / Side / Frame 01" and i1["from"]["name"].endswith("Frame 01 / v1") and i1["to"]["name"].endswith("Frame 01 / v2") and i1["to"]["source"] == "repaint"
              and i1["from"]["url"].startswith("/x/") and i1["to"]["url"].startswith("/x/") and i1["why"] == "staged",
              "a batch item: the slot's name, the before (v1) and the after (v2) named, pictured and sourced")
        # the deltas are those of the composed batch (the animation as the export would pack it): the empty frame raises
        # `empty` (and a jump on itself and its neighbour), the red patch widens slot 1's box (footprint)
        check("empty" in i2["flags"]["raised"] and isinstance(i2["flags"]["after"].get("empty"), str) and "footprint" in i1["flags"]["raised"] and i1["flags"]["cleared"] == []
              and isinstance(i1["flags"]["after"].get("footprint"), str),
              "the flag deltas: staging an empty frame raises `empty` with its rule; the red patch raises footprint: %s / %s" % (i2["flags"]["raised"], i1["flags"]["raised"]))
        check(FRIO.batch_line(i1) == "Run / Side / Frame 01 <- BG-B / Run / Side / Frame 01 / v2 (repainted)", "batch_line: %s" % FRIO.batch_line(i1))
        g.unstage()
        check(FS.staged_batch("enemy", "bug", "BG-B")["items"] == [], "nothing staged: an empty batch")

        # ---- delete retired
        rd = FS.delete_version(g, 1, v2["id"])
        check(not rd.get("ok") and rd.get("retired") and "never deleted" in rd["error"] and "Frame 01 / v2" in rd["error"] and os.path.isfile(v2["file"]) and len(g.versions(1)) == 2,
              "delete_version refuses always, names the version in Garry's form, removes nothing: %s" % rd["error"][:70])
        rd2 = FS.delete_version(g, 1, "nope")
        check(not rd2.get("ok") and rd2.get("retired"), "an unknown version is refused the same way")

        # ---- the pin re-apply at a landing (a job): a re-roll's strip lands on a look with a pinned slot
        g.pin(2, True)
        pinned_v = g.version(2, g.selected()["2"]["id"])
        cells = {k: list(v) for k, v in w["cells_b"].items()}
        for k in (0, 2):
            c = cells["run_s"][k].copy()
            c.paste((0, 0, 255, 255), (40, 40, 50, 50))
            cells["run_s"][k] = c
        strip2, counts2, cols2 = artkit.pack_strip(cells, w["order"], px)
        strip2.save(look.strip_path)
        fake = FakeJobs()
        r = FRIO.on_look_landed("enemy", "bug", "BG-B", enqueue=lambda kind, target, spec, title=None: {"job": fake.enqueue(kind, target, spec, title)})
        rp = r.get("reapply") or {}
        check(r.get("ok") and rp.get("pinned") == 1 and rp.get("job") == "jfake-0001" and rp.get("note") == "re-applied 1 pinned frame" and rp["names"] == ["BG-B / Run / Side / Frame 02 / v1"]
              and fake.calls and fake.calls[-1]["kind"] == "frames_export" and fake.calls[-1]["spec"]["reapply"]["pinned"] == 1 and fake.calls[-1]["spec"]["reapply"]["slots"] == [["run_s", 2]]
              and fake.calls[-1]["title"].endswith("re-applied 1 pinned frame") and "confirm" not in fake.calls[-1]["spec"],
              "on_look_landed queues a frames_export that re-applies the pinned slot (no confirm), the card note named: %s" % {k: rp.get(k) for k in ("pinned", "job", "note")})
        check(len(g.versions(2)) == 3 and g.versions(2)[2]["source"] == "reroll" and g.selected()["2"]["pinned"] and g.selected()["2"]["installed_differs"] == g.versions(2)[2]["id"] and not g.staged(),
              "the landing's new cell is a version too (nothing lost), the pin still says the strip differs, nothing staged")
        check(r.get("misfit") == [] and r.get("misfit_text") == "", "no misfit on a plain landing")
        # the queued export packs the pinned version back (what the job runs): changed lists it as `pinned`
        ex = FS.export_look("enemy", "bug", "BG-B", job="jfake-0001", sidecar=os.path.join(tmp, "side_reapply.json"))
        strip_after = Image.open(look.strip_path).convert("RGBA")
        off2 = _offset(w["order"], w["anims"], "run_s") + 2
        cell2 = strip_after.crop((off2 * px, 0, off2 * px + px, px))
        check(ex.get("ok") and not ex.get("unchanged") and ex["reapplied"] == 1 and [c["why"] for c in ex["changed"]] == ["pinned"] and ex["changed"][0]["slot"] == 2
              and ex["names"] == ["BG-B / Run / Side / Frame 02 / v1"] and np.array_equal(np.asarray(cell2), np.asarray(g.cell_of(2, pinned_v))),
              "export_look with nothing staged but a pinned differing slot packs the pinned cell back and lists it as a pinned re-apply: %s" % ex.get("changed"))
        side = json.load(open(os.path.join(tmp, "side_reapply.json"), encoding="utf-8"))
        check(side["info"]["reapplied"] == 1 and side["info"]["names"] == ex["names"] and side["info"]["changed"][0]["name"].endswith("Frame 02 / v1"), "the sidecar says what was re-applied, in Garry's form")
        r2 = FRIO.on_look_landed("enemy", "bug", "BG-B", enqueue=lambda *a, **k: {"job": fake.enqueue(*a, **k)})
        check(r2.get("ok") and not r2.get("reapply") and len(fake.calls) == 1 and not g.selected()["2"].get("installed_differs") and g.selected()["2"]["pinned"],
              "after the export the landing finds the pinned choice in the strip: nothing queued, the pin kept, installed_differs cleared")
        # a landing without any queue (a script): the reapply says where the export command is
        g.pin(0, True)
        strip3, _, _ = artkit.pack_strip(w["cells_b"], w["order"], px)
        strip3.save(look.strip_path)
        r3 = FRIO.on_look_landed("enemy", "bug", "BG-B", enqueue=lambda *a, **k: {"job": None, "error": "the queue is not here"})
        # slot 2's pin equals the original strip's cell again, slot 0's (pinned on its re-roll) does not: one pin to re-apply
        check(r3.get("ok") and (r3.get("reapply") or {}).get("pinned") == 1 and r3["reapply"]["job"] is None and "queue" in r3["reapply"]["error"] and g.selected()["0"]["pinned"] and g.selected()["2"]["pinned"],
              "a landing whose queue refuses says so in the reapply record (nothing is lost: the pins stay): %s" % r3.get("reapply", {}).get("error"))
        ex2 = FS.export_look("enemy", "bug", "BG-B", job="jx", sidecar=os.path.join(tmp, "side2.json"))
        check(ex2.get("ok") and ex2["reapplied"] == 1 and ex2["changed"][0]["slot"] == 0, "the next export re-applies the pin the strip did not show")
        FS.register_look("enemy", "bug", "BG-B")
        g.pin(0, False)

        # ---- the hand run's hook re-packs in-process and logs it (the misfit line when any)
        said = []
        cells4 = {k: list(v) for k, v in w["cells_b"].items()}
        c4 = cells4["run_s"][2].copy()
        c4.paste((255, 255, 0, 255), (20, 20, 30, 30))
        cells4["run_s"][2] = c4
        strip4, counts4, cols4 = artkit.pack_strip(cells4, w["order"], px)
        strip4.save(look.strip_path)
        hk = FS.hook_after_save(w["folder"], "bug", "BG-B", counts4, cols4, "bug_sprite_b.png", log=lambda *a: said.append(" ".join(str(x) for x in a)))
        strip_h = Image.open(look.strip_path).convert("RGBA")
        cell_h = strip_h.crop((off2 * px, 0, off2 * px + px, px))
        check(hk and hk["ok"] and hk["reapplied"]["pinned"] == 1 and hk["reapplied"]["names"] == ["BG-B / Run / Side / Frame 02 / v1"] and np.array_equal(np.asarray(cell_h), np.asarray(g.cell_of(2, pinned_v)))
              and not g.selected()["2"].get("installed_differs") and os.path.isfile(os.path.join(ROOT, hk["reapplied"]["backup"])) and hk["misfit"] == [],
              "hook_after_save: the pinned cell is packed back in-process, the run's strip backed up, no misfit: %s" % (hk or {}).get("reapplied"))
        logs = json.load(open(os.path.join(g.dir, "exports.json"), encoding="utf-8"))
        check(logs[-1].get("why") == "reapply" and logs[-1]["changed"][0]["why"] == "pinned" and logs[-1]["changed"][0]["name"].endswith("Frame 02 / v1"), "exports.json logs the re-apply")
        check(any("re-applied 1 pinned frame" in s for s in said), "the hook logs the re-apply: %s" % (said[-1][:90] if said else ""))
        hk_none = FS.hook_after_save(w["folder"], "bug", "BG-B", counts4, cols4, "bug_sprite_b.png", log=lambda *a: said.append(" ".join(str(x) for x in a)))
        check(hk_none and hk_none["ok"] and hk_none.get("reapplied") is None and "registered again" in said[-1], "a hand run on a look whose pins the strip shows: registered again, nothing re-packed")

        # ---- a landing whose slot count shrank: the pin past the new count is reported, its version kept
        g.pin(3, True)
        v3_pinned = g.selected()["3"]["id"]
        cells5 = {k: list(v) for k, v in w["cells_b"].items()}
        cells5["run_s"] = cells5["run_s"][:3]
        anims5 = dict(w["anims"], run_s=3)
        strip5, counts5, cols5 = artkit.pack_strip(cells5, w["order"], px)
        strip5.save(look.strip_path)
        docp = os.path.join(w["folder"], "bug.json")
        doc = json.load(open(docp, encoding="utf-8"))
        doc["variants"]["BG-B"]["anims"] = counts5
        doc["variants"]["BG-B"]["strip_cols"] = cols5
        json.dump(doc, open(docp, "w", encoding="utf-8", newline="\n"), indent=2)
        fake2 = FakeJobs()
        r5 = FRIO.on_look_landed("enemy", "bug", "BG-B", enqueue=lambda *a, **k: {"job": fake2.enqueue(*a, **k)})
        g5 = FS.Group(FS.Look("enemy", "bug", "BG-B"), "run", "side")
        gj = json.load(open(os.path.join(g5.dir, "group.json"), encoding="utf-8"))
        check(r5.get("ok") and g5.n == 3 and len(r5["misfit"]) == 1 and r5["misfit"][0]["slot"] == 3 and r5["misfit"][0]["why"] == "count" and r5["misfit"][0]["group"] == "run_s"
              and r5["misfit_text"].startswith("1 pinned frame could not be re-applied: the animation has 3 frames now") and "Frame 03" in r5["misfit_text"],
              "a landing with fewer frames reports the pin that no longer fits: %s" % r5.get("misfit_text"))
        check("3" not in g5.selected() and gj.get("lost_pins") and gj["lost_pins"][0]["slot"] == 3 and gj["lost_pins"][0]["id"] == v3_pinned and os.path.isfile(g5.version(3, v3_pinned)["file"]),
              "the lost pin moves to group.json lost_pins; the version's files stay")
        check(not r5.get("reapply") and not fake2.calls and g5.selected()["2"]["pinned"] and not g5.selected()["2"].get("installed_differs"),
              "no re-apply export for a pin that cannot be placed; the pin that still fits (slot 2, same cell) stays quiet")
        d5 = g5.detail(lambda p: p)
        check(d5["lost_pins"] and d5["lost_pins"][0]["slot"] == 3 and len(d5["slots"]) == 3, "the detail tells the page about the lost pins")
        # frame_px changed: the pinned cell of another size cannot be placed: reported, unpinned, the version kept
        g5.pin(1, True)
        px2 = 32
        cells6 = {key: [im.resize((px2, px2)) for im in seq] for key, seq in cells5.items()}
        strip6, counts6, cols6 = artkit.pack_strip(cells6, w["order"], px2)
        strip6.save(look.strip_path)
        doc = json.load(open(docp, encoding="utf-8"))
        doc["variants"]["BG-B"]["frame_px"] = px2
        doc["variants"]["BG-B"]["strip_cols"] = cols6
        json.dump(doc, open(docp, "w", encoding="utf-8", newline="\n"), indent=2)
        r6 = FRIO.on_look_landed("enemy", "bug", "BG-B", enqueue=lambda *a, **k: {"job": fake2.enqueue(*a, **k)})
        g6 = FS.Group(FS.Look("enemy", "bug", "BG-B"), "run", "side")
        s6 = g6.selected()
        check(r6.get("ok") and g6.look.frame_px == px2 and any(m["why"] == "frame_px" and m["slot"] == 1 for m in r6["misfit"]) and "32 px now" in r6["misfit_text"]
              and not s6["1"]["pinned"] and s6["1"].get("was_pinned") and len(g6.versions(1)) >= 3 and not fake2.calls,
              "a landing with another frame_px: the pinned cell cannot be placed: reported, unpinned (was_pinned kept), nothing queued: %s" % r6.get("misfit_text"))
        check(FS.misfit_text([]) == "" and FS.misfit_text([{"slot": 5, "text": "the animation has 2 frames now", "name": "A / Run / Side / Frame 05"}, {"slot": 6, "text": "the animation has 2 frames now", "name": "B"}]).startswith("2 pinned frames could not be re-applied: the animation has 2 frames now (A / Run / Side / Frame 05, B;"),
              "misfit_text: the count, the reasons once each, the names")

        # ---- the routes on a temporary server with a jobs stand-in
        shutil.rmtree(tmp, ignore_errors=False) if False else None
        w = V95._make_world(tmp)   # a fresh world (the JSON and strips as made): the store is kept, BG-B's groups re-register on the mtime
        shutil.rmtree(os.path.join(FS.STORE, "enemy", "bug"), ignore_errors=True)
        saved_srv = {k: getattr(server, k) for k in ("CONTENT", "DL", "DRIVERS", "JOBS")}
        fake3 = FakeJobs()
        server.CONTENT, server.DL, server.DRIVERS, server.JOBS = w["content"], os.path.join(tmp, "dl"), FS.DRIVERS, fake3
        httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        httpd.daemon_threads = True
        port = httpd.server_address[1]
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % port

        def get(path):
            try:
                with urllib.request.urlopen(base + path, timeout=10) as r:
                    return r.status, json.loads(r.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                return e.code, json.loads(e.read().decode("utf-8") or "{}")

        def post(path, body):
            req = urllib.request.Request(base + path, data=json.dumps(body).encode("utf-8"), method="POST", headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=10) as r:
                    return r.status, json.loads(r.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                return e.code, json.loads(e.read().decode("utf-8") or "{}")
        try:
            st, d = get("/api/frames/enemy/bug/BG-A/run/side")
            check(st == 200 and d["ok"] and d["slots"][1]["name"] == "BG-A / Run / Side / Frame 01" and d["slots"][1]["versions"][0]["name"].endswith("Frame 01 / v1"), "GET the detail: the names are served")
            vid_a = d["slots"][1]["versions"][0]["id"]
            st, o = get("/api/frames/enemy/bug/BG-B/run/side/others")
            check(st == 200 and o["looks"][0]["code"] == "BG-A" and o["looks"][0]["slots"][1]["versions"][0]["name"] == "BG-A / Run / Side / Frame 01 / v1" and "seed" in o["looks"][0]["slots"][1]["versions"][0],
                  "GET others: the picker's versions carry the name and the filter fields")
            st, b0 = get("/api/frames/enemy/bug/BG-A/batch")
            check(st == 200 and b0["ok"] and b0["items"] == [] and b0["in_play"] is False and b0["lines"] == [], "GET batch on a look with nothing staged: empty, not in play")
            st, r1 = post("/api/frames/enemy/bug/BG-A/run/side/copy", {"slot": 1, "from": {"code": "BG-B", "slot": 1}})
            check(st == 200 and r1["ok"] and r1["group"]["slots"][1]["staged"], "a copy staged on BG-A (not the look in play)")
            st, b1 = get("/api/frames/enemy/bug/BG-A/batch")
            check(st == 200 and b1["staged"] == 1 and b1["items"][0]["to"]["source"] == "copied" and b1["items"][0]["from"]["name"] == "BG-A / Run / Side / Frame 01 / v1" and b1["lines"][0].startswith("Run / Side / Frame 01 <- BG-A / Run / Side / Frame 01 / v2 (copied)"),
                  "GET batch: the staged copy as a before / after pair with its line: %s" % b1["lines"])
            st, r2 = post("/api/frames/enemy/bug/BG-A/export", {})
            check(st == 400 and not r2["ok"] and r2.get("needs_confirm") and r2.get("in_play") is False and r2["batch"]["staged"] == 1 and "Confirm the batch first" in r2["error"] and not fake3.calls,
                  "POST export WITHOUT confirm is refused for a look the game does not play too (pass 96): the answer carries the batch")
            st, r3 = post("/api/frames/enemy/bug/BG-A/export", {"confirm": True})
            check(st == 200 and r3["ok"] and fake3.calls[-1]["kind"] == "frames_export" and fake3.calls[-1]["spec"]["in_play"] is False, "POST export WITH confirm queues the job")
            st, r4 = post("/api/frames/enemy/bug/BG-A/run/side/delete", {"slot": 1, "version": vid_a})
            check(st == 400 and not r4["ok"] and r4.get("retired") and "never deleted" in r4.get("error", ""), "POST delete answers the refusal (retired)")
            st, r5 = post("/api/frames/enemy/bug/BG-B/run/side/copy", {"slot": 0, "from": {"code": "BG-A", "base": "idle", "view": "front", "slot": 0}})
            check(st == 200 and r5["ok"] and r5["group"]["slots"][0]["staged"], "a copy from another animation / view of the other look (the picker's explicit override) is a version here")
        finally:
            httpd.shutdown()
            httpd.server_close()
            for n, v in saved_srv.items():
                setattr(server, n, v)
            FRIO.DL_DIR = os.path.join(ROOT, "tools", "dl")

        # ---- jobs.py: the render-ok harvest on a canned line, idempotent; the landing note
        try:
            import jobs
        except ImportError as e:
            jobs = None
            check(False, "jobs.py could not be imported: %s" % e)
        if jobs is not None:
            tmpj = tempfile.mkdtemp(prefix="le_page96_jobs_")
            saved_j = {"JOBS_DIR": jobs.JOBS_DIR, "RAW": jobs.RAW, "_hooks": jobs._hooks}
            jobs.JOBS_DIR = tmpj
            jobs.RAW = os.path.join(tmpj, "raw")
            os.makedirs(jobs.RAW)
            try:
                Image.new("RGBA", (8, 8), (255, 0, 0, 255)).save(os.path.join(jobs.RAW, "bug_bgb_side.png"))
                with open(os.path.join(jobs.RAW, "bug_bgb_side.json"), "w", encoding="utf-8") as f:
                    json.dump({"seed": 3, "qa": {"problems": []}}, f)
                job = {"id": "jp96-1", "kind": "look", "method": "creature_ctl", "target": {"kind": "enemy", "id": "nobody_here", "code": "XX-A"}, "spec": {}, "state": "running",
                       "progress": {"stages": [{"name": "side", "key": "bug_bgb_side", "type": "still", "state": "pending"}]}, "cache_keys": {"stills": ["bug_bgb_side"], "clips": []}, "outputs": [], "started": "2026-01-01T00:00:00"}

                class L:
                    pass
                live = L()
                live.logf = io.StringIO()
                live.tail = []
                live.key_to_stage = None
                live.marker = None
                live.last_save = 0.0
                check(jobs._render_ok(("render", "k"), "  render k seed 1 2.0s ok") and not jobs._render_ok(("render", "k"), "  render k seed 1 2.0s retry: x") and not jobs._render_ok(("clip", "k"), "x ok") and not jobs._render_ok(None, "ok"),
                      "_render_ok: only a finished render line")
                jobs._on_line(job, live, "  render bug_bgb_side seed 3 12.3s retry: two heads")
                check(job["outputs"] == [] and job["progress"]["stages"][0]["state"] == "running", "a retry line marks the stage running and harvests nothing")
                jobs._on_line(job, live, "  render bug_bgb_side seed 3 12.3s ok")
                outs = job["outputs"]
                check(len(outs) == 1 and outs[0]["type"] == "still" and outs[0]["cache_key"] == "bug_bgb_side" and outs[0]["url"].endswith("bug_bgb_side.png") and job["progress"]["stages"][0]["state"] == "done" and live.last_save,
                      "a `render ... ok` line lists the still on the card at once: %s" % [o.get("label") for o in outs])
                again = jobs._harvest(job)
                check(again == outs, "_harvest is idempotent (the same list from disk)")
                jobs._on_line(job, live, "  render bug_bgb_side seed 3 12.3s ok")
                check(job["outputs"] == outs, "the same line again changes nothing")
                check(live.logf.getvalue().count("render bug_bgb_side") == 3 and len(live.tail) == 3, "the lines still reach the log and the tail")
                # the landing note on the card (written.frames) from the merge hook's `frames`
                note = jobs._frames_landed_note({"ok": True, "reapply": {"pinned": 2, "job": "jq-1", "note": "re-applied 2 pinned frames", "names": ["a", "b"]}})
                check(note["note"] == "re-applied 2 pinned frames (export job jq-1)" and note["reapply"]["pinned"] == 2 and "misfit" not in note, "_frames_landed_note: the re-apply with its job")
                note2 = jobs._frames_landed_note({"ok": True, "misfit": [{"slot": 3}], "misfit_text": "1 pinned frame could not be re-applied: the animation has 3 frames now"})
                check(note2["note"].startswith("1 pinned frame could not be re-applied") and note2["misfit"], "_frames_landed_note: the misfit line")
                note3 = jobs._frames_landed_note({"ok": True, "reapply": {"pinned": 1, "job": None, "error": "no queue"}, "misfit": [{"slot": 9}], "misfit_text": "m"})
                check(note3["note"] == "re-applied 1 pinned frames: no queue; m", "_frames_landed_note: both, the queue's refusal said")
                check(jobs._frames_landed_note({"ok": True}) == {}, "nothing to say: an empty note")
                os.makedirs(os.path.join(tmpj, "jp96-2"))
                with open(os.path.join(tmpj, "jp96-2", "result.json"), "w", encoding="utf-8") as f:
                    json.dump({"entry": {"sprite": "x.png"}, "info": {"pipeline": "gen_ctl"}}, f)
                jobs._hooks = {"merge_look": lambda kind, cid, code, entry, info=None: {"ok": True, "layout": "block", "backup": "", "frames": {"ok": True, "reapply": {"pinned": 1, "job": "jq-2", "note": "re-applied 1 pinned frame", "names": ["n"]}}}}
                wr, er = jobs._post({"id": "jp96-2", "kind": "look", "method": "creature_ctl", "target": {"kind": "enemy", "id": "nobody_here", "code": "XX-A"}, "spec": {}})
                check(not er and wr.get("frames", {}).get("note") == "re-applied 1 pinned frame (export job jq-2)", "_post carries the store's landing note into written.frames: %s" % (wr or {}).get("frames"))
            finally:
                jobs.JOBS_DIR, jobs.RAW, jobs._hooks = saved_j["JOBS_DIR"], saved_j["RAW"], saved_j["_hooks"]
                shutil.rmtree(tmpj, ignore_errors=True)
    finally:
        for k, v in saved.items():
            setattr(FS, k, v)
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- the page's maths under Node (frames_model.js, jobs_model.js)
    fold = {"rid": "r20261021-120000-ab12", "state": "waiting", "waiting_for": "approval", "goal": "a clean side walk", "mode": "auto",
            "asset": {"kind": "enemy", "id": "desert_spider", "code": "SP-B", "method": "creature_ctl"}, "iteration": {"n": 2, "of": 5},
            "budget": {"rerolls": 2, "repair_rounds": 2, "lane_seconds": 5400, "evaluator_calls": 60, "cloud_dollars": 0.0},
            "spent": {"rerolls": 1, "repair_rounds": {"run/side": 2, "run/front": 0}, "lane_seconds": 840, "evaluator_calls": 14, "cloud_dollars": 0.0},
            "provisional": {"code": "SP-B", "groups": {"run/side": {"staged": [7, 12]}}}, "summary": "one paragraph", "sheet": "tools/dl/x.png",
            "jobs": [{"id": "j1", "kind": "look", "state": "done"}, {"id": "j2", "kind": "evaluate", "state": "done"}, {"id": "j3", "kind": "frames_repair", "state": "running"}],
            "history_tail": [{"t": "a", "event": "created"}, {"t": "b", "event": "op", "op": {"op": "repair", "target": {"code": "SP-B", "group": "run/side", "slots": [7]}, "why": "jump on Frame 07"}}, {"t": "c", "event": "job"}]}
    findings = {"v": 1, "items": [{"field": "jump", "slot": 7, "group": "run/side", "ok": False, "kind": "measured", "rule": "differs 2.3x", "value": 2.3},
                                  {"field": "legs", "ok": False, "kind": "model", "model": "qwen2.5-vl-7b", "rule": "seven legs"}, {"field": "face", "ok": True, "kind": "model"}],
                "gates": {"hard_failures": 1, "advisory": 1, "pass": False}, "model_calls": [{"backend": "openai_chat", "model": "qwen2.5-vl-7b", "images": 2, "ms": 900, "dollars": 0}]}
    batch = {"ok": True, "code": "SP-B", "in_play": True, "backup_dir": "tools/level_editor/backups/desert_spider",
             "items": [{"name": "SP-B / Run / Side / Frame 07", "slot": 7, "group": "run_s", "why": "staged", "to": {"name": "SP-B / Run / Side / Frame 07 / v2", "source": "vace"}, "from": {"name": "SP-B / Run / Side / Frame 07 / v1"}, "flags": {"raised": ["footprint"], "cleared": ["jump"]}},
                       {"name": "SP-B / Run / Side / Frame 03", "slot": 3, "group": "run_s", "why": "pinned", "to": {"name": "SP-B / Run / Side / Frame 03 / v1", "source": "installed"}, "from": None, "flags": {"raised": [], "cleared": []}}]}
    out = run_node({"fold": fold, "findings": findings, "batch": batch}, RUNNER)
    if out is None:
        print("selftest_PAGE96: no node: the page maths were not checked")
    elif out:
        check(out["labels"] == ["SP-A / Run / Side / Frame 07 / v2", "SP-A / Run / Front ¾ / Frame 03", "X / Die / Back", "given", "BG-B / Idle / Front / Frame 01 / v3"], "frameLabel / nameOf: Garry's form, the JS twin: %s" % out["labels"])
        check(out["vtext"].startswith("SP-B / Run / Side / Frame 02 / v2 · painted anew by VACE · seed 5") and out["vtext_old"].startswith("SP-B-2 ·"), "versionText leads with the name, the short label when there is none")
        check(out["marks"] == ["old roll", "archived", ""], "sourceMark: old roll / archived where the store says so")
        check(out["filt"] == [[4, 2, 3, 1], [4, 2, 3], [2], [2], [4]], "filterVersions: newest first (the same time: the higher n first); by time, source, raw, both: %s" % out["filt"])
        check(out["lines"][0] == ["Run / Side / Frame 07 <- SP-B / Run / Side / Frame 07 / v2 (VACE)", "raises footprint; clears jump", "staged"] and out["lines"][1][0].endswith("(the strip; a pinned choice re-applied)") and out["lines"][1][1] == "no flag changes",
              "batchLines: the line, the flag deltas, the pinned re-apply: %s" % out["lines"])
        check(out["sum"].startswith("Export replaces 2 frames of SP-B's installed strip · 1 staged, 1 pinned choice re-applied · the game PLAYS this look · the old strip is kept under tools/level_editor/backups/desert_spider/"), "batchSummary: %s" % out["sum"][:90])
        check(out["opts"][0] == ["", "installed", "reroll", "vace", "copied", "repaint", "neighbour", "old_roll", "archived"] and out["opts"][1] == [0, 1, 7, 30], "the filter options")
        check(out["sig"] == [True, True, True, True], "JobsModel.sig: stable across calls, changes with the state or the log, no clock in it: %s" % out["sig"])
        check(out["elapsed"] == ["1:23 / ~4:00", "1:02:03"], "elapsedText: %s" % out["elapsed"])
        conn = out["conn"]
        check(conn[0][0] == "down" and conn[0][1].startswith("no answer from the Level Editor since 13:14:15 (Failed to fetch): retrying every 15 s") and "last answer 13:13:15" in conn[0][1],
              "connectionLine: a network failure says since when, the error, the retry, the last answer: %s" % conn[0][1])
        check(conn[1] == ["ok", "connected · last answer 13:14:15"] and conn[2][0] == "noapi" and "no jobs API (no jobs)" in conn[2][1] and conn[3][0] == "readonly" and "another editor runs the queue (level_editor, pid 7)" in conn[3][1]
              and conn[4][0] == "readonly" and "--no-jobs" in conn[4][1] and conn[5][0] == "never",
              "connectionLine: connected, no jobs API, another editor, view-only, never: distinct words: %s" % [c[0] for c in conn])
        check(out["budget"] == [["rerolls", "1 of 2", 50, False], ["repair_rounds", "2 of 2 (run/side)", 100, True], ["lane_seconds", "14 of 90 min", 16, False], ["evaluator_calls", "14 of 60", 23, False], ["cloud_dollars", "$0.00 of $0.00 (cloud off)", 0, False]],
              "budgetBars: spent / budget per unit, the worst group of the repair rounds, a full bar marked: %s" % out["budget"])
        f = out["fold"]
        check(f["chip"] == {"text": "WAITING", "cls": "waiting"} and f["iteration"] == "iteration 2 of 5" and f["buttons"] == ["Approve", "Reject", "Pick another", "Stop"] and f["lastOp"] == "repair on SP-B run/side slots 7 · jump on Frame 07"
              and f["waiting"] == "waiting for your approval" and f["prov"] == "provisional winner: SP-B · run/side: 2 staged" and f["jobsLine"] == "3 jobs (1 live)" and f["latest"] == "j2" and f["title"] == "enemy desert_spider · SP-B · creature_ctl" and f["final"] is False,
              "requestFold: the chip, iteration k of n, the buttons, the last op and why, the waiting words, the provisional winner, the jobs line: %s" % f)
        check(out["buttons"] == [["Pause", "Stop"], ["Pause", "Stop"], ["Resume", "Step", "Pick another", "Stop"], ["Approve", "Reject", "Pick another", "Stop"], ["Cancel"], [], [], [], []] and out["buttons_pick"] == ["Pick another", "Stop"],
              "buttonsFor: Pause / Stop / Resume / Step / Approve / Reject / Pick another by state: %s" % out["buttons"])
        fb = out["findings"]
        check(fb["n"] == 2 and fb["texts"] == ["jump f07 · run/side", "legs"] and fb["titles"] == ["differs 2.3x (2.3) · measured", "seven legs · qwen2.5-vl-7b"] and fb["cls"] == ["measured", "model"] and fb["ok"] == 1
              and fb["gates"] == "gates failed · 1 hard, 1 advisory · 1 model call (qwen2.5-vl-7b), $0.00",
              "findingsBadges: a badge per failed item with the rule text and the model's name, the gates line: %s" % fb)

    # ---- the wiring
    rd = lambda n: open(os.path.join(HERE, n), encoding="utf-8").read()  # noqa: E731
    idx = rd("index.html")
    check('src="jobs_model.js"' in idx and idx.index('src="jobs_model.js"') < idx.index('src="jobs.js"') and 'href="requests.css"' in idx, "index.html: jobs_model.js before jobs.js, requests.css linked")
    jj = rd("jobs.js")
    check("ui: new Map()" in jj and "function ui(id)" in jj and "u.picked = key" in jj and "Math.floor(Date.now() / 2000)" not in jj and "JobsModel.sig(j, ctx)" in jj and "setInterval(tickElapsed, 1000)" in jj and "class: 'jelapsed'" in jj,
          "jobs.js: S.ui holds the pick, sig has no time term, the elapsed clock ticks on its own timer")
    check("drawRequests()" in jj and "'/api/requests'" in jj and "requestCard(" in jj and "Frames.confirmBox(" in jj and "/approve" not in jj.replace("requestAct(r, 'approve'", "") and "findings.json" in jj
          and "'pause'" in jj and "'resume'" in jj and "'step'" in jj and "'stop'" in jj and "'reject'" in jj and "'pick'" in jj and "drawConnection(" in jj and "S.downSince" in jj,
          "jobs.js: the Requests group, its card, Approve through the batch box, the verbs, the findings, the connection line")
    fj = rd("frames.js")
    check("'Delete'" not in fj and "deleteVersion" not in fj and "/delete" not in fj and "batchPanel(" in fj and "confirmBox" in fj and "'/batch'" in fj and "fr-filters" in fj and "filterVersions(" in fj and "drawStaged(" in fj and "sourceMark(" in fj,
          "frames.js: no Delete, the batch box (one click for the whole batch), the picker's filters, the staged list, the marks")
    fm = rd("frames_model.js")
    check("function frameLabel" in fm and "function filterVersions" in fm and "function batchLines" in fm and "old_roll" in fm, "frames_model.js: the label, the filters, the batch lines, the marks")
    fio = rd("frames_io.py")
    check("def batch(" in fio and 'parts[3] == "batch"' in fio and "def _default_enqueue" in fio and "enqueue=None" in fio and 'if body.get("confirm") is not True:' in fio and "RETIRED" in fio,
          "frames_io.py: the batch route, the re-apply at a landing, every export confirmed, delete retired")
    fs = open(os.path.join(ROOT, "tools", "frames_store.py"), encoding="utf-8").read()
    check("def label_of(" in fs and "def staged_batch(" in fs and "def reapply_pins(" in fs and "def misfit_text(" in fs and "NEVER_DELETED" in fs and "lost_pins" in fs and "def selected_version" in fs and "def flags(self, staged=True)" in fs,
          "frames_store.py: the formatter, the batch, the re-pack, the misfit words, the rule, the lost pins, the before flags")
    jb = rd("jobs.py")
    check("def _render_ok(" in jb and "if _render_ok(seen, line):" in jb and "def _frames_landed_note(" in jb and 'written["frames"] = _frames_landed_note(r["frames"])' in jb, "jobs.py: the render-ok harvest and the landing note")
    doc = open(os.path.join(ROOT, "docs", "level_editor.md"), encoding="utf-8").read()
    check("## Pass 96: the request card and the frame layer's rules" in doc and "Frame 07 / v2" in doc, "docs/level_editor.md: the Pass 96 section")
