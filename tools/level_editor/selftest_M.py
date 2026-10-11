"""Pass 67, lane M: the map Save keeps a top-level key the page never saw.

`weapon_grade` (how the 3D weapon models are graded under the map's light) sits beside `skins` in the map JSON; the page
edits `timeline_data` and sends the whole map back as it loaded it, so a key added to the file while the page was open
would be dropped by a Save unless write_map carries the file's keys the body lacks. Run by selftest.py's extra_checks
(every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import shutil
import tempfile


def checks(check, run_node, server):
    tmp = tempfile.mkdtemp(prefix="le_selftest_M_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        folder = os.path.join(server.CONTENT, "maps", "testmap")
        os.makedirs(folder)
        path = os.path.join(folder, "testmap.json")
        on_disk = {"id": "testmap", "name": "Test Map", "skins": {"walker": "testbeast"},
                   "weapon_grade": {"value": 0.78, "saturation": 1.3, "glow": 0.3},
                   "boss": "bigboss", "timeline_data": {"stage_length": 100.0, "roster": []}}
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(on_disk, indent=2) + "\n")
        # the page's body: loaded before weapon_grade was added, one timeline number changed
        body = {"id": "testmap", "name": "Test Map", "skins": {"walker": "testbeast"}, "boss": "bigboss",
                "timeline_data": {"stage_length": 120, "roster": []}}
        r = server.write_map("testmap", body)
        check(r.get("ok") is True and r.get("import_ok") is False, "write_map: saved, the import reported as not run (no Godot): %s" % r)
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
        back = json.loads(text)
        check(back.get("weapon_grade") == on_disk["weapon_grade"], "a top-level key the page never saw rides along: %s" % back.get("weapon_grade"))
        check(list(back.keys()) == ["id", "name", "skins", "weapon_grade", "boss", "timeline_data"], "the file's key order is kept: %s" % list(back.keys()))
        check(back["timeline_data"]["stage_length"] == 120.0 and '"stage_length": 120.0' in text, "the page's change lands, the file's float stays a float")
        # a body that carries the key changed: the body's numbers win
        body2 = dict(body)
        body2["weapon_grade"] = {"value": 0.7, "saturation": 1.4, "glow": 0.25}
        r2 = server.write_map("testmap", body2)
        with open(path, "r", encoding="utf-8") as f:
            back2 = json.load(f)
        check(r2.get("ok") is True and back2["weapon_grade"] == body2["weapon_grade"], "a body that carries weapon_grade sets it: %s" % back2.get("weapon_grade"))
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)
