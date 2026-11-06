"""Pass 132: the Level Editor's Frame rate row (a look's own fps, look op `fps`).

  fps   server.look_op `fps` on a temporary creature: a look's own fps keeps its other rates, a look without its own
        starts from the creature's, a base look without an entry writes the top-level key, bad values are refused
  page  looks.js has the row (two players, a box, a slider, Save through the look op)
"""
import json
import os
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def _read(*parts):
    with open(os.path.join(*parts), "rb") as f:
        return f.read().decode("utf-8")


def _write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(obj, indent=2) + "\n")


def fps_checks(check, server):
    tmp = tempfile.mkdtemp(prefix="le_p132_fps_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        folder = os.path.join(server.CONTENT, "enemies", "p132bird")
        path = os.path.join(folder, "p132bird.json")
        _write(path, {"id": "p132bird", "name": "Bird", "sprite": "p132bird_sprite.png", "anims": {"idle": 2, "run": 4, "die": 3}, "fps": {"run": 24, "die": 12},
                      "variant_base": "PB-A", "variant": "PB-B",
                      "variants": {"PB-B": {"sprite": "p132bird_sprite_b.png", "fps": {"run": 16, "die": 12}}, "PB-C": {"sprite": "p132bird_sprite_c.png"}}})
        _write(os.path.join(server.CONTENT, "characters", "p132hero", "p132hero.json"), {"id": "p132hero", "name": "H", "variant_base": "PH-A", "variants": {"PH-A": {"note": "x"}}})
        load = lambda: json.loads(_read(path))
        r = server.look_op("enemy", "p132bird", ["PB-B"], "fps", {"anim": "run", "value": 8})
        d = load()
        check(r.get("ok") and d["variants"]["PB-B"]["fps"] == {"run": 8, "die": 12} and d["fps"] == {"run": 24, "die": 12} and r.get("backup"),
              "P132 fps: a look's own run rate is written, its death rate and the creature's rates stay: %s" % (r.get("error") or d["variants"]["PB-B"]))
        r = server.look_op("enemy", "p132bird", ["PB-C"], "fps", {"anim": "die", "value": 6})
        check(r.get("ok") and load()["variants"]["PB-C"]["fps"] == {"run": 24, "die": 6}, "P132 fps: a look without its own starts from the creature's rates: %s" % (r.get("error") or load()["variants"]["PB-C"]))
        r = server.look_op("enemy", "p132bird", ["PB-A"], "fps", {"anim": "run", "value": 10})
        d = load()
        check(r.get("ok") and d["fps"] == {"run": 10, "die": 12} and "PB-A" not in d["variants"], "P132 fps: the base look without an entry writes the creature's top-level fps: %s" % (r.get("error") or d.get("fps")))
        before = _read(path)
        bad = [server.look_op("enemy", "p132bird", ["PB-B"], "fps", {"anim": "idle", "value": 8}), server.look_op("enemy", "p132bird", ["PB-B"], "fps", {"anim": "run", "value": 0}),
               server.look_op("enemy", "p132bird", ["PB-B"], "fps", {"anim": "run", "value": 61}), server.look_op("enemy", "p132bird", ["PB-B"], "fps", {"anim": "run", "value": "8"}),
               server.look_op("enemy", "p132bird", ["PB-Z"], "fps", {"anim": "run", "value": 8})]
        check(all(not x.get("ok") and x.get("status") in (400, 404) for x in bad) and _read(path) == before, "P132 fps: another strip, a rate out of 1..60, a text and an unknown look are refused, nothing written: %s" % [x.get("status") for x in bad])
        check("\r" not in _read(path) and load()["anims"] == {"idle": 2, "run": 4, "die": 3}, "P132 fps: the file keeps LF and its other keys")
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def page_checks(check):
    looks = _read(HERE, "looks.js")
    check("function fpsRow(kind, id, record, look, s)" in looks and "{ op: 'fps', anim, value: tryRate }" in looks and "if (kind !== 'hero' && !isStub(look)) info.appendChild(fpsRow(" in looks,
          "P132 page: looks.js has the Frame rate row on a creature's open look, saved through the look op")
    check("(saved)" in looks and "(trying)" in looks and "type: 'range'" in looks and ".lg-fps-slide" in _read(HERE, "preview.css"), "P132 page: the row plays the saved rate beside the one in the box, with a slider")


def checks(check, run_node, server):
    fps_checks(check, server)
    page_checks(check)
