"""Pass 137, lane LOCKIT: the Texts tab's io (strings_io.py) on a temporary copy of a few content folders. selftest.py
discovers this file and hands it `check`, `run_node` and the `server` module. Nothing here runs Godot or the network.

Groups:
  render   strings_io's renderer and strings_model.js (under node) read every case of fixtures/loc_cases.json as Loc.gd
           does (game/tests/pass137_loc_test.gd reads the same file)
  rows     the rows: en.json's, a content item's own fields, an Outlaw's skin name, the Trail's and the Wanted tasks'
           words, each with its group, its variables, its icon
  save     a save writes each text where it lives (en.json sorted with LF and no BOM; a content JSON with only that line
           changed; the skin entry; trail.json; wanted.json), a backup each, the content folders imported; one wrong text
           (an unknown variable, a broken brace, an empty text, an unknown key) writes nothing
  csv      export -> import gives no change; one edited cell is one change with its old and new text; every error (the
           header, an unknown key, a key twice, an empty text, a broken brace, an unknown variable, Excel's mangled
           characters, a short line) is named with its line and nothing is written; a dropped variable warns; smart quotes
           pass; apply writes
  page     index.html loads strings_model.js and strings.js, server.py routes /api/strings
"""
import json
import os
import shutil
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CONTENT = os.path.join(ROOT, "game", "content")
FIXTURE = os.path.join(HERE, "fixtures", "loc_cases.json")


class _Srv:
    def __init__(self, tmp):
        self.ROOT = tmp
        self.GAME = os.path.join(tmp, "game")
        self.CONTENT = os.path.join(tmp, "game", "content")
        self._write_lock = threading.Lock()
        self.backups = []
        self.imports = []

    def rel(self, p):
        return os.path.relpath(p, self.ROOT).replace("\\", "/")

    def backup(self, name, path):
        self.backups.append(name)
        return "backup-%s" % name

    def run_import(self, target, who=""):
        self.imports.append(target)
        return True, "imported %s" % target

    def mtime_of(self, p):
        return os.path.getmtime(p)

    @staticmethod
    def restore_numbers(old, new):
        import content_io
        return content_io.restore_numbers(old, new)


def _copy(tmp):
    for rel in ["weapons/revolver", "characters/drifter", "trail", "wanted", "strings"]:
        src = os.path.join(CONTENT, rel)
        dst = os.path.join(tmp, "game", "content", rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns("*.import", "*.tres", "*.png", "*.tscn"))
    # one icon to find
    shutil.copy(os.path.join(CONTENT, "weapons", "revolver", "revolver_icon.png"), os.path.join(tmp, "game", "content", "weapons", "revolver"))
    # a sample the tab shows beside a variable
    os.makedirs(os.path.join(tmp, "tools", "dl", "loc"))
    with open(os.path.join(tmp, "tools", "dl", "loc", "samples.json"), "w", encoding="utf-8") as f:
        json.dump({"ui.portal.kills": {"vars": {"kills": "1,234"}, "text": "1,234 kills"}}, f)


def _read(p):
    with open(p, encoding="utf-8", newline="") as f:
        return f.read()


def checks(check, run_node, server):
    import strings_io as SI
    fx = json.load(open(FIXTURE, encoding="utf-8"))

    # ---- render
    bad = [c["t"] for c in fx["cases"] if SI.render(c["t"], c["v"]) != c["out"]]
    check(not bad, "render: strings_io renders every fixture case as Loc.gd does: %s" % bad[:3])
    bad = [c["t"] for c in fx["variables"] if SI.variables(c["t"]) != c["names"]]
    check(not bad, "render: strings_io names every fixture text's variables in order: %s" % bad[:3])
    check(all(SI.problems(t) for t in fx["broken"]) and not any(SI.problems(c["t"]) for c in fx["cases"]),
          "render: every broken fixture text has a problem and no good one does")
    if shutil.which("node"):
        import subprocess
        p = subprocess.run(["node", os.path.join(HERE, "strings_model.js"), FIXTURE], capture_output=True, text=True, encoding="utf-8")
        check(p.returncode == 0, "render: strings_model.js under node reads every fixture case the same: %s" % (p.stdout.strip() or p.stderr.strip())[-200:])

    tmp = tempfile.mkdtemp(prefix="loc137_")
    try:
        _copy(tmp)
        srv = _Srv(tmp)
        en_p = os.path.join(srv.CONTENT, "strings", "en.json")
        rev_p = os.path.join(srv.CONTENT, "weapons", "revolver", "revolver.json")
        dri_p = os.path.join(srv.CONTENT, "characters", "drifter", "drifter.json")
        trail_p = os.path.join(srv.CONTENT, "trail", "trail.json")
        wanted_p = os.path.join(srv.CONTENT, "wanted", "wanted.json")

        # ---- rows
        rs = {r["key"]: r for r in SI.rows(srv)}
        check("ui.portal.kills" in rs and rs["ui.portal.kills"]["group"] == "screens" and rs["ui.portal.kills"]["samples"] == {"kills": "1,234"}
              and rs["ui.portal.kills"]["vars"] == ["kills"], "rows: an en.json row with its group, its variable and its sample value")
        rv = rs.get("weapon.revolver.name")
        check(rv is not None and rv["group"] == "weapons" and rv["icon"] == "weapon.revolver.name" and "revolver.json" in rv["where"],
              "rows: a content item's own name, in Weapons, with its icon")
        check("weapon.revolver.desc" in rs and rs["weapon.revolver.desc"]["group"] == "weapons" and set(rs["weapon.revolver.desc"]["vars"]) >= {"amount", "range"},
              "rows: the Revolver's one description row sits beside its name, its variables {amount} {range}")
        check("outlaw.drifter.skin.dri_b.name" in rs and rs["outlaw.drifter.skin.dri_b.name"]["group"] == "outlaws", "rows: an Outlaw's skin name")
        check("trail.end.text" in rs and any(k.startswith("trail.upgrade.") for k in rs) and any(k.startswith("trail.section.") for k in rs),
              "rows: the Trail's end, upgrade and section words")
        check(any(k.startswith("wanted.") and k.endswith(".text") for k in rs), "rows: the Wanted tasks' words")
        check(SI.icon_path(srv, "weapon.revolver.desc") is not None and SI.icon_path(srv, "ui.portal.kills") is None
              and SI.icon_path(srv, "weapon.../x") is None, "rows: an item row has its icon, a screen row none, a bad key none")
        rd = SI.read(srv)
        check(rd["ok"] and all("loc" not in r for r in rd["rows"]) and [g["id"] for g in rd["groups"]][:3] == ["outlaws", "enemies", "weapons"],
              "rows: the page's answer (no write locations, the sub-tabs in order)")

        # ---- save: one wrong text writes nothing
        before = {p: _read(p) for p in (en_p, rev_p, dri_p, trail_p, wanted_p)}
        for changes, why in [({"ui.portal.kills": "{kills} kills and {gold}"}, "an unknown variable"),
                             ({"ui.portal.kills": "{kills kills"}, "a broken brace"),
                             ({"ui.portal.kills": "  "}, "an empty text"),
                             ({"ui.no_such.key": "x"}, "an unknown key"),
                             ({"weapon.revolver.name": "Six Gun", "ui.portal.kills": "{kills} kills {"}, "one good and one wrong")]:
            r = SI.save(srv, changes)
            same = all(_read(p) == t for p, t in before.items())
            check(not r["ok"] and same and r.get("errors"), "save: %s writes nothing and says why (%s)" % (why, (r.get("errors") or [{}])[0].get("error", r.get("error"))))
        # ---- save: every kind of place
        changes = {"ui.portal.kills": "{kills} downed", "weapon.revolver.name": "Six Gun", "weapon.revolver.flavour": "Old iron.\nStill sings.",
                   "outlaw.drifter.skin.dri_b.name": "Blacker Hat", "trail.end.text": "More soon"}
        wkey = next(k for k in rs if k.startswith("wanted.") and k.endswith(".text"))
        changes[wkey] = rs[wkey]["text"] + "!"
        r = SI.save(srv, changes)
        check(r["ok"] and r["changed"] == 6, "save: six texts in five files saved: %s" % r.get("error"))
        en = _read(en_p)
        d = json.loads(en)
        check(d["ui.portal.kills"] == "{kills} downed" and list(d) == sorted(d) and "\r" not in en and not en.startswith("﻿") and en.endswith("}\n"),
              "save: en.json has the text, keys sorted, LF, no BOM")
        rev_old, rev_new = before[rev_p].splitlines(), _read(rev_p).splitlines()
        diff = [i for i, (a, b) in enumerate(zip(rev_old, rev_new)) if a != b]
        check(len(rev_old) == len(rev_new) and len(diff) == 2 and json.loads(_read(rev_p))["flavour"] == "Old iron.\nStill sings.",
              "save: the content JSON changed on its two lines only, a line break kept as \\n")
        check(json.loads(_read(dri_p))["variants"]["DRI-B"]["skin"]["name"] == "Blacker Hat"
              and json.loads(_read(dri_p))["variants"]["DRI-B"]["skin"]["price"] == json.loads(before[dri_p])["variants"]["DRI-B"]["skin"]["price"],
              "save: the skin's name, its price kept")
        check(json.loads(_read(trail_p))["end"]["text"] == "More soon", "save: the Trail's end text")
        check(changes[wkey] in _read(wanted_p), "save: the Wanted task's text")
        check(sorted(srv.imports) == ["characters/drifter,weapons/revolver"], "save: the two content folders imported once: %s" % srv.imports)
        check(len(srv.backups) >= 3, "save: a backup of each file: %s" % srv.backups)
        r = SI.save(srv, {"ui.portal.kills": "{kills} downed"})
        check(r["ok"] and r.get("unchanged"), "save: the same text again changes nothing")
        r = SI.save(srv, {"ui.portal.kills": "{kills} downed today"})
        check(r["ok"], "save: a text that drops no variable saves")

        # ---- csv
        text = SI.export_csv(srv)
        check(text.startswith("﻿key,group,text,variables,where\r\n"), "csv: UTF-8 with a BOM, the header first")
        r = SI.import_csv(srv, text)
        check(r["ok"] and r["changes"] == [] and r["rows"] == len(SI.rows(srv)), "csv: the export read back changes nothing (%s)" % r["summary"])
        one = SI.export_csv(srv, "screens")
        # pass 137 (lane W2-RUN): read as CSV, not line by line: a text may hold a line break (ui.results.new_best, a
        # quoted cell)
        import csv as _csv
        import io as _io
        recs = list(_csv.reader(_io.StringIO(one[1:], newline="")))[1:]
        check(bool(recs) and all(rec[1] == "screens" for rec in recs if rec), "csv: one sub-tab's export holds its rows only")

        def with_cell(key, new):
            import csv
            import io
            rows = list(csv.reader(io.StringIO(text[1:], newline="")))
            for row in rows:
                if row and row[0] == key:
                    row[2] = new
            buf = io.StringIO()
            csv.writer(buf, lineterminator="\r\n").writerows(rows)
            return buf.getvalue()
        r = SI.import_csv(srv, with_cell("ui.portal.kills", "{kills} gone, “quoted”"))
        check(r["ok"] and len(r["changes"]) == 1 and r["changes"][0]["old"] == "{kills} downed today" and r["summary"].startswith("1 text changes"),
              "csv: one edited cell (smart quotes and all) is one change, old and new named: %s" % r["summary"])
        en_before = _read(en_p)
        cases = [
            ("wrong header", "name,text\r\nui.portal.kills,x\r\n", "header"),
            ("unknown key", text + "ui.nope.nope,group,hi,,\r\n", "unknown key"),
            ("a key twice", text + "ui.portal.kills,screens,{kills} again,,\r\n", "twice"),
            ("empty text", with_cell("ui.portal.kills", ""), "empty"),
            ("broken brace", with_cell("ui.portal.kills", "{kills kills"), "with no }"),
            ("unknown variable", with_cell("ui.portal.kills", "{kills} {gold}"), "unknown variable"),
            ("mangled characters", with_cell("ui.portal.kills", "{kills} donâ€™t"), "UTF-8"),
            ("a short line", text + "ui.portal.kills\r\n", "column"),
        ]
        for why, csvtext, word in cases:
            r = SI.import_csv(srv, csvtext, apply=True)
            check(not r["ok"] and any(word in e["error"] for e in r["errors"]) and all("line" in e for e in r["errors"]) and _read(en_p) == en_before,
                  "csv: %s is an error with its line, nothing written: %s" % (why, [e["error"] for e in r["errors"]][:2]))
        r = SI.import_csv(srv, with_cell("ui.portal.kills", "Gone"))
        check(r["ok"] and any("{kills}" in w["warning"] for w in r["warnings"]), "csv: a dropped variable warns")
        r = SI.import_csv(srv, with_cell("ui.portal.kills", "{kills} gone\r\nfor good"), apply=True)
        check(r["ok"] and json.loads(_read(en_p))["ui.portal.kills"] == "{kills} gone\nfor good", "csv: apply writes; a cell's line break is \\n")
        # a text with a line break goes out as one quoted cell and comes back unchanged (pass 137, lane W2-RUN)
        text2 = SI.export_csv(srv)
        recs = {rec[0]: rec for rec in _csv.reader(_io.StringIO(text2[1:], newline="")) if rec}
        r = SI.import_csv(srv, text2)
        check(recs.get("ui.portal.kills", ["", "", ""])[2] == "{kills} gone\nfor good" and r["ok"] and r["changes"] == [],
              "csv: a text with a line break is one quoted cell and reads back unchanged (%s)" % r.get("summary", ""))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- loc_verify's matching (tools/loc_verify.py: a removed literal against the added keys' texts)
    import sys
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import loc_verify as V
    cases = [
        ("Fires %d pellet%s in a %d° cone where you face.", "Fires {amount} {amount?pellet:pellets} in a {cone}° cone where you face.", True),
        ("Fires %d pellet%s in a %d° cone where you face.", "Fires {amount} {amount?pellet:pellets} in a {cone}° cone at your face.", False),
        (" Every %s shot fires twice in quick succession.", "Every {nth} shot fires twice in quick succession.", True),
        ("Every %s shot fires twice.", "Every {nth} shot fires twice in quick succession.", False),
        ("STAGE %d CLEAR", "STAGE {stage} CLEARED", False),
        ("DEAL", "DEALS", False),
        ("a spear", "Throws {amount?a spear:{amount} spears} at {who}.", True),
        ("%d spears", "Throws {amount?a spear:{amount} spears} at {who}.", True),
        ("Knocks enemies back.", "Knocks enemies back. Hard.", False),
        ("%d%% of rounds are mini crits.", "{pct}% of rounds are mini crits.", True),
    ]
    bad = [c[0] for c in cases if V.covered(c[0], V._expansions(c[1])) != c[2]]
    check(not bad, "loc_verify: a removed literal matches its row's text (holes both ways, selectors, pieces between word boundaries) and a changed word does not: %s" % bad)
    kinds = {"DEAL": "yes", "Extract": "yes", "Bank it before the horde comes.": "yes", "second": "maybe", "s": "", "ExtractCard": "",
             "separation": "maybe", "res://ui/x.tscn": "", "%s → %s": "", "ui.portal.kills": ""}
    bad = [k for k, v in kinds.items() if V.is_player_text(k) != v]
    check(not bad, "loc_verify: what reads as player text (a button's DEAL yes, a node name no, a lone lowercase word maybe): %s" % bad)

    # ---- page
    html = _read(os.path.join(HERE, "index.html"))
    check('src="strings_model.js"' in html and 'src="strings.js"' in html and 'data-tab="strings"' in html and 'id="tab-strings"' in html,
          "page: index.html has the Texts tab and loads its scripts")
    src = _read(os.path.join(HERE, "server.py"))
    check('parts[:1] == ["strings"]' in src and 'parts[:2] == ["api", "strings"]' in src, "page: server.py routes /api/strings")
