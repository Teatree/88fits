"""Pass 132c: a look's History row (look_history.py; look ops `snapshot` and `restore`; GET .../look/<CODE>/history).

  git      the real Skeleton Knight's KN-D lists its commits (a strip and an icon each), newest first, and a past
           version's strip is served
  restore  on a temporary creature with no git: "Keep a copy" makes a snapshot, a changed strip / icon / entry go back
           to it on restore, the state before the restore is kept as a copy, bad refs are refused
  page     looks.js has the row (Show history, Keep a copy, Restore this version through the look op)
"""
import json
import os
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def _read(*parts):
    with open(os.path.join(*parts), "rb") as f:
        return f.read()


def git_checks(check, server, lh):
    folder = os.path.join(server.CONTENT, "enemies", "skeleton_knight")
    path = os.path.join(folder, "skeleton_knight.json")
    h = lh.history("enemy", "skeleton_knight", "KN-D", folder, path)
    gits = [v for v in h.get("versions", []) if v["kind"] == "git"]
    check(h.get("ok") and len(gits) >= 3 and all(v["has_sprite"] and v["has_icon"] and v["ref"].startswith("git:") for v in gits),
          "P132C git: KN-D's commits are listed with a strip and an icon each: %s" % [v["ref"] for v in gits][:5])
    check(all(gits[i]["when"] >= gits[i + 1]["when"] for i in range(len(gits) - 1)), "P132C git: newest first")
    pic = lh.picture("enemy", "skeleton_knight", "KN-D", gits[-1]["ref"], "sprite", folder, path) if gits else None
    check(bool(pic) and pic[:8] == b"\x89PNG\r\n\x1a\n", "P132C git: a past version's strip is served as a PNG")
    check(lh.picture("enemy", "skeleton_knight", "KN-D", "git:0000000", "sprite", folder, path) is None, "P132C git: an unknown commit serves nothing")
    r = lh.history("enemy", "skeleton_knight", "KN-ZZ", folder, path)
    check(not r.get("ok") and r.get("status") == 404, "P132C git: an unknown look is a 404")


def restore_checks(check, server, lh):
    tmp = tempfile.mkdtemp(prefix="le_p132c_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS, lh.SNAPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        lh.SNAPS = os.path.join(tmp, "backups", "looks")
        folder = os.path.join(server.CONTENT, "enemies", "p132crab")
        path = os.path.join(folder, "p132crab.json")
        os.makedirs(folder)
        png = b"\x89PNG\r\n\x1a\n" + b"one"
        with open(os.path.join(folder, "p132crab_sprite_b.png"), "wb") as f:
            f.write(png)
        with open(os.path.join(folder, "p132crab_icon_b.png"), "wb") as f:
            f.write(png + b"icon")
        with open(os.path.join(folder, "p132crab_b_ai.json"), "w", encoding="utf-8", newline="\n") as f:
            f.write('{"seed": 1}\n')
        doc = {"id": "p132crab", "name": "Crab", "sprite": "p132crab_sprite.png", "anims": {"idle": 2, "run": 4, "die": 3},
               "variant_base": "CR-A", "variant": "CR-B",
               "variants": {"CR-B": {"note": "first", "sprite": "p132crab_sprite_b.png", "icon": "p132crab_icon_b.png", "anims": {"idle": 2, "run": 4, "die": 3}, "strip_cols": 9, "fresh": True}}}
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(doc, indent=2) + "\n")
        r = server.look_op("enemy", "p132crab", ["CR-B"], "snapshot", {"why": "the test"})
        snap = r.get("snapshot")
        check(r.get("ok") and snap and os.path.isfile(os.path.join(lh.SNAPS, "p132crab", "CR-B", snap, "sprite.png")) and os.path.isfile(os.path.join(lh.SNAPS, "p132crab", "CR-B", snap, "ai.json")),
              "P132C restore: Keep a copy writes the strip, icon, provenance file and entry under backups/looks: %s" % (r.get("error") or snap))
        h = r.get("history") or {}
        check(h.get("ok") and len(h["versions"]) == 1 and h["versions"][0]["ref"] == "snap:" + snap and h["versions"][0]["same_as_now"], "P132C restore: the copy is listed and reads as the same as now")
        # a re-roll: new pictures, another entry
        with open(os.path.join(folder, "p132crab_sprite_b.png"), "wb") as f:
            f.write(png + b"two")
        with open(os.path.join(folder, "p132crab_icon_b.png"), "wb") as f:
            f.write(png + b"icon2")
        with open(os.path.join(folder, "p132crab_b_ai.json"), "w", encoding="utf-8", newline="\n") as f:
            f.write('{"seed": 2}\n')
        r2 = server.look_op("enemy", "p132crab", ["CR-B"], "note", {"note": "second"})
        r3 = server.look_op("enemy", "p132crab", ["CR-B"], "approve", {})
        h = lh.history("enemy", "p132crab", "CR-B", folder, path)
        check(r2.get("ok") and r3.get("ok") and h["ok"] and not h["versions"][0]["same_as_now"] and not h["now_committed"], "P132C restore: after a change the copy differs and the look is in no commit")
        r = server.look_op("enemy", "p132crab", ["CR-B"], "restore", {"ref": "snap:" + snap})
        d = json.loads(_read(path).decode("utf-8"))
        check(r.get("ok") and _read(folder, "p132crab_sprite_b.png") == png and _read(folder, "p132crab_icon_b.png") == png + b"icon" and _read(folder, "p132crab_b_ai.json") == b'{"seed": 1}\n',
              "P132C restore: the strip, the icon and the provenance file are the copy's again: %s" % r.get("error"))
        check(d["variants"]["CR-B"].get("note") == "first" and d["variants"]["CR-B"].get("fresh") is True and d["variant"] == "CR-B" and "\r" not in _read(path).decode("utf-8"),
              "P132C restore: the entry is the copy's (a key the copy had not is dropped), the rest of the file untouched: %s" % d["variants"]["CR-B"])
        h = r.get("history") or {}
        kept = [v for v in h.get("versions", []) if v["ref"] != "snap:" + snap]
        check(len(kept) == 1 and "before restoring" in kept[0]["title"] and not kept[0]["same_as_now"], "P132C restore: what the restore replaced is kept as a copy: %s" % [v["title"] for v in h.get("versions", [])])
        bad = [server.look_op("enemy", "p132crab", ["CR-B"], "restore", {"ref": "snap:19990101-000000"}), server.look_op("enemy", "p132crab", ["CR-B"], "restore", {"ref": "../x"}),
               server.look_op("enemy", "p132crab", ["CR-Q"], "restore", {"ref": "snap:" + snap})]
        check(all(not x.get("ok") and x.get("status") in (400, 404) for x in bad), "P132C restore: a missing copy, a bad ref and an unknown look are refused: %s" % [x.get("status") for x in bad])
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS, lh.SNAPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def page_checks(check):
    looks = _read(HERE, "looks.js").decode("utf-8")
    check("function historyRow(kind, id, record, look, s)" in looks and "{ op: 'restore', ref: v.ref }" in looks and "{ op: 'snapshot', why: 'kept from the page' }" in looks
          and "if (!isStub(look)) info.appendChild(historyRow(" in looks, "P132C page: looks.js has the History row (Keep a copy, Restore this version through the look op)")
    check("/look/${encodeURIComponent(look.code)}/history" in looks and "/lookhist/${kind}/${id}/${look.code}/${v.ref}/sprite" in looks and ".lg-hist-list" in _read(HERE, "preview.css").decode("utf-8"),
          "P132C page: the row reads the history route and plays each version from /lookhist/")


def checks(check, run_node, server):
    import look_history as lh
    git_checks(check, server, lh)
    restore_checks(check, server, lh)
    page_checks(check)
