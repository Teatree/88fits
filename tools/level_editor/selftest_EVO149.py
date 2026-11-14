"""Pass 149, lane EDITOR (the lead's extra task): a passive item's Evolved icon follows its icon. Garry: "Hot Streak - I've
updated the Icon for Hot Streak, but the Evolution icon didn't update. And it's not great that I can't make those icons
from Level Editor itself." selftest.py discovers this file and hands it its `check` counter. Everything that writes works
on a temporary tree (server.CONTENT, BACKUPS, JOBS pointed there; no Godot: an import is queued on a stand-in).

  install   an icon going on a passive item's base through set_look_icon (Use for ..., the page) and through
            Hooks.set_look_files (an install job's landing) remakes <id>_icon_evolved.png from the new icon with
            tools/evolved_icons.evolved_icon, a copy of the old one under backups/<id>/ first
  revert    Revert icon remakes it from the icon it goes back to, and queues the import with the PNG step
  skip      a JSON that names its own `icon_evolved`, a Card (line), an evolved form and a one-shot item are left alone
  button    POST .../evolved_icon ("Remake Evolved icon from the icon"): the same picture again is "unchanged"; a newer
            icon is remade, backed up, the import queued; its own icon_evolved needs confirm (409 without); no rung: 400;
            the info route (stale, own, the picture)
  jobs      an item_icon job's landing remakes it through the server's hook before the import
  page      the server routes GET/POST .../evolved_icon; the Items tab's passive page shows the Evolved icon on its dark
            plate with the button; looks.js says when an icon change remade it
"""
import io
import json
import os
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
_TAG = "EVO149"


def _pic(colour, size=48, ring=False):
    """An icon as the painter leaves it: a disc of `colour` on a transparent ground (RGBA PNG bytes)."""
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((size // 4, size // 4, size * 3 // 4, size * 3 // 4), fill=colour + (255,))
    if ring:
        ImageDraw.Draw(im).rectangle((0, 0, 3, 3), fill=(9, 9, 9, 255))
    b = io.BytesIO()
    im.save(b, "PNG")
    return b.getvalue()


def _evolved_bytes(png):
    import evolved_icons as EVI
    from PIL import Image
    b = io.BytesIO()
    EVI.evolved_icon(Image.open(io.BytesIO(png))).save(b, "PNG")
    return b.getvalue()


def _same_picture(a, b):
    from PIL import Image
    try:
        x, y = Image.open(io.BytesIO(a)).convert("RGBA"), Image.open(io.BytesIO(b)).convert("RGBA")
    except Exception:   # noqa: BLE001
        return False
    return x.size == y.size and x.tobytes() == y.tobytes()


def _put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def _bytes(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return b""


def _write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")


class _FakeJobs:
    def __init__(self):
        self.enqueued = []

    def enqueue(self, kind, target, spec, title=None, request=None):
        rec = {"id": "jq%d" % (len(self.enqueued) + 1), "kind": kind, "target": target, "spec": spec, "title": title, "state": "queued"}
        self.enqueued.append(rec)
        return rec


class _Pointed:
    def __init__(self, server, tmp, fake):
        self.server, self.tmp, self.fake = server, tmp, fake

    def __enter__(self):
        s = self.server
        self.saved = (s.CONTENT, s.GODOT, s.BACKUPS, s.JOBS)
        s.CONTENT, s.GODOT, s.BACKUPS, s.JOBS = os.path.join(self.tmp, "content"), os.path.join(self.tmp, "no-godot.exe"), os.path.join(self.tmp, "backups"), self.fake
        return self

    def __exit__(self, *a):
        s = self.server
        s.CONTENT, s.GODOT, s.BACKUPS, s.JOBS = self.saved
        return False


RED, BLUE, GREEN, GOLD = (200, 30, 30), (30, 60, 220), (30, 180, 60), (230, 180, 40)


def _tree(tmp):
    p = os.path.join(tmp, "content", "passives")
    _write_json(os.path.join(p, "hs", "hs.json"), {"id": "hs", "name": "Hot S", "rarity": "rare", "max_level": 4})
    _put(os.path.join(p, "hs", "hs_icon.png"), _pic(RED))
    _put(os.path.join(p, "hs", "hs_icon_evolved.png"), _evolved_bytes(_pic(RED)))
    _put(os.path.join(p, "hs", "hs_icon_c1.png"), _pic(BLUE))
    _put(os.path.join(p, "hs", "hs_icon_c2.png"), _pic(GREEN))
    _write_json(os.path.join(p, "own", "own.json"), {"id": "own", "name": "Own", "rarity": "epic", "icon_evolved": "own_evo_painted.png"})
    _put(os.path.join(p, "own", "own_icon.png"), _pic(RED))
    _put(os.path.join(p, "own", "own_icon_c1.png"), _pic(BLUE))
    _put(os.path.join(p, "own", "own_evo_painted.png"), _pic(GOLD, ring=True))
    _write_json(os.path.join(p, "cc", "cc.json"), {"id": "cc", "name": "Card C", "line": True})
    _put(os.path.join(p, "cc", "cc_icon.png"), _pic(RED))
    _put(os.path.join(p, "cc", "cc_icon_c1.png"), _pic(BLUE))
    _write_json(os.path.join(p, "one", "one.json"), {"id": "one", "name": "One", "single": True})
    _put(os.path.join(p, "one", "one_icon.png"), _pic(RED))
    _put(os.path.join(p, "one", "one_icon_c1.png"), _pic(BLUE))
    return p


def _install_checks(check, server, tmp, fake):
    p = _tree(tmp)
    ev = os.path.join(p, "hs", "hs_icon_evolved.png")
    old = _bytes(ev)
    r = server.set_look_icon("passive", "hs", "", "hs_icon_c1.png", "use folder/hs_icon_c1.png", confirm=True)
    e = r.get("evolved") or {}
    check(r.get("ok") and e.get("ok") and not e.get("skipped") and not e.get("unchanged") and e.get("file") == "hs_icon_evolved.png" and e.get("from") == "hs_icon_c1.png",
          "%s install: a new icon on a passive item remakes its Evolved icon (%s)" % (_TAG, e))
    check(_same_picture(_bytes(ev), _evolved_bytes(_pic(BLUE))) and not _same_picture(_bytes(ev), old), "%s install: the Evolved icon is evolved_icon() of the new icon" % _TAG)
    bk = server._abs_path(e.get("backup"))
    check(bool(e.get("backup")) and os.path.dirname(os.path.abspath(bk)) == os.path.abspath(os.path.join(server.BACKUPS, "hs")) and _bytes(bk) == old,
          "%s install: the old Evolved icon is copied under backups/hs/ first (%s)" % (_TAG, e.get("backup")))
    # the job landing (Hooks.set_look_files, an install job)
    hooks = server.Hooks()
    r2 = hooks.set_look_files("passive", "hs", "", {"icon": "hs_icon_c2.png"}, {"why": "install c2 of #ab12"})
    check(r2.get("ok") and (r2.get("evolved") or {}).get("ok") and _same_picture(_bytes(ev), _evolved_bytes(_pic(GREEN))),
          "%s install: an install job's landing (set_look_files) remakes it too (%s)" % (_TAG, r2.get("evolved")))
    return p


def _revert_checks(check, server, tmp, fake, p):
    ev = os.path.join(p, "hs", "hs_icon_evolved.png")
    n = len(fake.enqueued)
    r = server.revert_icon("passive", "hs", "", confirm=True)
    e = r.get("evolved") or {}
    check(r.get("ok") and r.get("file") == "hs_icon_c1.png" and e.get("ok") and not e.get("skipped") and _same_picture(_bytes(ev), _evolved_bytes(_pic(BLUE))),
          "%s revert: Revert icon remakes the Evolved icon from the icon it goes back to (%s, %s)" % (_TAG, r.get("file"), e))
    q = fake.enqueued[n:]
    check(len(q) == 1 and q[0]["kind"] == "import" and q[0]["spec"].get("targets") == ["passives/hs"] and r.get("job"),
          "%s revert: the import is queued with the PNG step (an import job: --import first) (%s)" % (_TAG, q))
    copies = sorted(os.listdir(os.path.join(server.BACKUPS, "hs")))
    check(sum(1 for c in copies if c.startswith("hs_icon_evolved_")) >= 2, "%s revert: every Evolved icon replaced has its copy under backups/hs/ (%s)" % (_TAG, copies))


def _skip_checks(check, server, tmp, fake, p):
    own_before = _bytes(os.path.join(p, "own", "own_evo_painted.png"))
    r = server.set_look_icon("passive", "own", "", "own_icon_c1.png", "use", confirm=True)
    e = r.get("evolved") or {}
    check(r.get("ok") and e.get("ok") and "icon_evolved" in str(e.get("skipped")) and _bytes(os.path.join(p, "own", "own_evo_painted.png")) == own_before
          and not os.path.exists(os.path.join(p, "own", "own_icon_evolved.png")), "%s skip: a JSON naming its own icon_evolved keeps it on a new icon (%s)" % (_TAG, e.get("skipped")))
    for cid, word in (("cc", "Card"), ("one", "one-shot")):
        r = server.set_look_icon("passive", cid, "", "%s_icon_c1.png" % cid, "use", confirm=True)
        e = r.get("evolved") or {}
        check(r.get("ok") and e.get("ok") and word in str(e.get("skipped")) and not os.path.exists(os.path.join(p, cid, "%s_icon_evolved.png" % cid)),
              "%s skip: %s has no Evolved rung: nothing made (%s)" % (_TAG, cid, e.get("skipped")))
    r = server.set_look_icon("weapon", "nope", "", "x.png", "", confirm=True)
    check(not r.get("ok") and "evolved" not in r, "%s skip: other kinds are not touched" % _TAG)


def _button_checks(check, server, tmp, fake, p):
    ev = os.path.join(p, "hs", "hs_icon_evolved.png")
    n = len(fake.enqueued)
    same = server.evolved_icon_op("passive", "hs", {"confirm": True})
    check(same.get("ok") and same.get("unchanged") and len(fake.enqueued) == n, "%s button: the same picture again changes nothing and queues nothing (%s)" % (_TAG, same.get("output")))
    # Garry paints over the icon file by hand: the info says the Evolved icon is older, the button remakes it
    _put(os.path.join(p, "hs", "hs_icon_c1.png"), _pic(GOLD))
    t = os.path.getmtime(os.path.join(p, "hs", "hs_icon_c1.png")) - 5
    os.utime(ev, (t, t))   # the Evolved icon older than the icon
    info = server.evolved_icon_info("passive", "hs")
    check(info.get("ok") and info["rung"] and not info["own"] and info["exists"] and info["stale"] and info["base"] == "hs_icon_c1.png" and info["file"] == "hs_icon_evolved.png"
          and "evolved_icon?picture=1" in str(info.get("url")) and info.get("plate", {}).get("fill") == "#241b14",
          "%s button: the info: the rung, the file, older than the icon, the picture's address, the dark plate (%s)" % (_TAG, info))
    r = server.evolved_icon_op("passive", "hs", {})
    q = fake.enqueued[n:]
    check(r.get("ok") and not r.get("unchanged") and r.get("backup") and _same_picture(_bytes(ev), _evolved_bytes(_pic(GOLD))) and len(q) == 1 and q[0]["kind"] == "import"
          and r.get("evolved", {}).get("stale") is False, "%s button: Remake Evolved icon from the icon: remade, backed up, the import queued (%s)" % (_TAG, {k: r.get(k) for k in ("file", "backup", "job")}))
    own = os.path.join(p, "own", "own_evo_painted.png")
    before = _bytes(own)
    ask = server.evolved_icon_op("passive", "own", {})
    check(ask.get("status") == 409 and ask.get("confirm_needed") and _bytes(own) == before, "%s button: its own icon_evolved is asked about first (409, nothing written)" % _TAG)
    go = server.evolved_icon_op("passive", "own", {"confirm": True})
    bk = server._abs_path(go.get("backup"))
    check(go.get("ok") and go.get("file") == "own_evo_painted.png" and _same_picture(_bytes(own), _evolved_bytes(_pic(BLUE))) and _bytes(bk) == before,
          "%s button: with confirm, its own file is painted over after a copy (%s)" % (_TAG, go.get("backup")))
    no = server.evolved_icon_op("passive", "cc", {"confirm": True})
    check(no.get("status") == 400 and "Card" in no.get("error", ""), "%s button: a Card has no Evolved rung (400: %s)" % (_TAG, no.get("error")))
    gone = server.evolved_icon_op("passive", "zz", {})
    check(gone.get("status") == 404, "%s button: an unknown item is a 404" % _TAG)
    info = server.evolved_icon_info("weapon", "x")
    check(info.get("ok") and info.get("rung") is False, "%s button: a weapon has no Evolved icon to make" % _TAG)


def _jobs_checks(check, server, tmp, fake, p):
    import jobs
    ev = os.path.join(p, "hs", "hs_icon_evolved.png")
    saved = (jobs._hooks, jobs.enqueue)
    seen = []
    try:
        jobs._hooks = server.Hooks()
        jobs.enqueue = lambda kind, target, spec, title=None, request=None: seen.append((kind, spec)) or {"id": "x"}
        _put(os.path.join(p, "hs", "hs_icon_c1.png"), _pic(GREEN))   # an item_icon job painted the icon
        jobs._after_done({"id": "j-item", "kind": "item_icon", "target": {"kind": "passive", "id": "hs", "code": ""}})
    finally:
        jobs._hooks, jobs.enqueue = saved
    check(_same_picture(_bytes(ev), _evolved_bytes(_pic(GREEN))) and seen and seen[0][0] == "import",
          "%s jobs: an item_icon job's landing remakes the Evolved icon through the hook, then the import (%s)" % (_TAG, seen))


def _page_checks(check):
    def rd(*p):
        with open(os.path.join(*p), encoding="utf-8") as f:
            return f.read()
    srv, a, lk, jb = rd(HERE, "server.py"), rd(HERE, "assets.js"), rd(HERE, "looks.js"), rd(HERE, "jobs.py")
    check('if parts[3] == "evolved_icon":' in srv and 'if op == "evolved_icon":' in srv and "def remake_evolved_icon(self" in srv,
          "%s page: server.py routes GET/POST /api/content/<kind>/<id>/evolved_icon and hands jobs the hook" % _TAG)
    check("evolvedPanel(doc)" in a and "Remake Evolved icon from the icon" in a and "/evolved_icon`, { confirm: true }" in a and "doc.kind === 'passive' && !doc.data.line && !doc.data.evolves_from && !doc.data.single" in a,
          "%s page: the Items tab's passive page shows the Evolved icon with its button (same filter as evolved_icons.items)" % _TAG)
    check("Evolved icon remade" in lk and '_hook("remake_evolved_icon")' in jb, "%s page: looks.js says it after an icon change; jobs.py calls the hook" % _TAG)
    import evolved_icons as EVI
    check("evolved_icons as EVI" in srv and "EVI.evolved_icon(" in srv and "def evolved_icon(" not in srv, "%s page: the server uses tools/evolved_icons.py's evolved_icon (no copy of it)" % _TAG)
    check(callable(EVI.evolved_icon), "%s page: tools/evolved_icons.evolved_icon is there" % _TAG)


def checks(check, run_node=None, server=None):
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("%s: Pillow is not here: the Evolved icon is not checked" % _TAG)
        return
    if server is None:
        import server as _server
        server = _server
    tmp = tempfile.mkdtemp(prefix="le_evo149_")
    fake = _FakeJobs()
    try:
        with _Pointed(server, tmp, fake):
            p = None
            for g in (_install_checks, _revert_checks, _skip_checks, _button_checks, _jobs_checks):
                try:
                    if g is _install_checks:
                        p = g(check, server, tmp, fake)
                    else:
                        g(check, server, tmp, fake, p)
                except Exception as e:   # noqa: BLE001
                    import traceback
                    traceback.print_exc()
                    check(False, "%s %s: %s: %s" % (_TAG, g.__name__, type(e).__name__, e))
        _page_checks(check)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    import sys
    sys.path.insert(0, HERE)
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import selftest as _st
    import server as _server
    checks(_st.check, _st.run_node, _server)
    print("%s: %d checks passed, %d failed" % (_TAG, _st.PASSES[0], len(_st.FAILS)))
    sys.exit(1 if _st.FAILS else 0)
