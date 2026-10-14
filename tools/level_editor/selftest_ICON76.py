"""Pass 76, lane ICON: the icon guard. Garry: "Bring back the old Solenne icon, I made a variant of an Icon and can't find
the old one. Make a fix in LevelEditor to make sure that this doesn't happen." selftest.py discovers this file
(`extra_checks`) and hands it its `check` counter. Everything that writes works on a temporary tree (no Godot: an import
is reported as not run; a stand-in jobs module records what the server asks of it).

  guard     an icon install (icon_cands, hero_badge) into the look in play or the base is a 409 confirm_needed without
            confirm: true (now -> new, the file names, played / base, the looks that share the base's icon), over HTTP
            too; with confirm it goes to jobs.install with a file of its own (fresh_icon_name, never an existing one);
            any other look goes at once; a title cut-out is not asked about
  pick      after a pick lands (Hooks.set_look_files -> set_look_icon) the old file's bytes are unchanged and reachable
            (the gallery lists it); the entry has icon, icon_picked and icon_history; a copy of the old picture under
            backups/<id>/; only that entry's lines change
  revert    Revert icon steps back (the look's own icon gone again; a picture painted over since put back from its
            copy); a pick made before pass 76 (no history: Solenne's SOL-B) drops its icon; nothing to revert says so;
            the base and an item without looks too
  gallery   every icon on disk (the folder's, backups/<id>/, removed looks', the older tools' copies), one tile per
            picture, which looks show it; /iconfile serves the pictures and nothing else; "Use for this look" from the
            folder, from a backup and from an older tool's copy (put back under its own name)
  backups   the copies land under backups/<id>/, each picture once; snapshot_icons before a job
  jobs      install() carries the file; the plan hands it to the tools (--icon-file, keep_old); the landing goes through
            set_look_files (a base: the top-level icon and the badge block); merge_look keeps a picked icon
  tools     gen_badge_cands --icon-file and gen_icon_cands keep_old write a file of their own (gen_art.free_icon_name)
  page      looks.js asks before an install (now -> new), has Revert icon and the gallery; jobs.js and typed_forms.js ask
            too; assets.js shows the gallery for items and takes icon_history from disk; docs/level_editor.md "Pass 76"
  content   Solenne's SOL-B names no icon of its own (she shows solenne_icon.png again); solenne_icon_b.png is kept
"""
import json
import os
import re
import shutil
import struct
import sys
import tempfile
import threading
import urllib.error
import urllib.request
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")


def _png(rgb, size=4):
    """A tiny valid PNG of one colour (standard library only): the pictures here differ by their bytes."""
    raw = b"".join(b"\x00" + bytes(rgb) * size for _ in range(size))

    def chunk(t, data):
        return struct.pack(">I", len(data)) + t + data + struct.pack(">I", zlib.crc32(t + data) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


RED, GREEN, BLUE, YELLOW, PURPLE, ORANGE, MAGENTA, CYAN, GREY = (_png(c) for c in (
    (200, 0, 0), (0, 200, 0), (0, 0, 200), (220, 220, 0), (120, 0, 160), (240, 140, 0), (255, 0, 255), (0, 220, 220), (90, 90, 90)))


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


def _json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


class FakeJobs:
    """A stand-in for jobs.py: the finished candidate jobs the guard reads (get), the installs and imports it asks for."""

    def __init__(self):
        self.jobs = {}
        self.installs = []
        self.enqueued = []

    def get(self, job_id):
        return self.jobs.get(job_id)

    def install(self, job_id, choice, options=None):
        self.installs.append((job_id, str(choice), dict(options or {})))
        return {"id": "jinstall%d" % len(self.installs), "kind": "install", "state": "queued", "spec": dict(options or {})}

    def enqueue(self, kind, target, spec, title=None):
        rec = {"id": "jq%d" % (len(self.enqueued) + 1), "kind": kind, "target": target, "spec": spec, "title": title, "state": "queued"}
        self.enqueued.append(rec)
        return rec


def _tree(tmp):
    """The test assets: a hero (base HH-A, HH-B in play inheriting the hero's badge, HH-C with a picked badge of its own),
    a creature (BB-0 the base in play, BB-A a look with its own icon), a weapon without looks, a card with looks."""
    c = os.path.join(tmp, "content")
    hp = os.path.join(c, "characters", "hh", "hh.json")
    _write_json(hp, {"id": "hh", "name": "Hero H", "flavour": "A test hero.", "portrait_prompt": "smiling", "variant_base": "HH-A", "variant": "HH-B",
                     "variants": {"HH-A": {"note": "base", "sprite": "hh_sprite.png"},
                                  "HH-B": {"note": "b", "sprite": "hh_sprite_b.png"},
                                  "HH-C": {"note": "c", "sprite": "hh_sprite_c.png", "icon": "hh_icon_c.png", "icon_picked": True}}})
    for n, data in (("hh_icon.png", RED), ("hh_icon_c.png", GREEN), ("hh_sprite.png", GREY), ("hh_sprite_b.png", GREY), ("hh_sprite_c.png", GREY)):
        _put(os.path.join(c, "characters", "hh", n), data)
    bp = os.path.join(c, "enemies", "bb", "bb.json")
    _write_json(bp, {"id": "bb", "name": "Beast B", "variant_base": "BB-0", "variant": "BB-0",
                     "variants": {"BB-0": {"note": "base"}, "BB-A": {"note": "a", "sprite": "bb_sprite_a.png", "icon": "bb_icon_a.png"}}})
    for n, data in (("bb_icon.png", PURPLE), ("bb_icon_a.png", ORANGE), ("bb_sprite.png", GREY), ("bb_sprite_a.png", GREY)):
        _put(os.path.join(c, "enemies", "bb", n), data)
    wp = os.path.join(c, "weapons", "ww", "ww.json")
    _write_json(wp, {"id": "ww", "name": "Weapon W", "flavour": "Bang.", "rarity": "common"})
    _put(os.path.join(c, "weapons", "ww", "ww_icon.png"), CYAN)
    _put(os.path.join(c, "weapons", "ww", "ww_icon_alt.png"), MAGENTA)
    cp = os.path.join(c, "passives", "cc", "cc.json")
    _write_json(cp, {"id": "cc", "name": "Card C", "line": True, "variant_base": "A", "variant": "B",
                     "variants": {"A": {"note": "the old icon"}, "B": {"note": "b", "icon": "cc_icon_b.png"}}})
    _put(os.path.join(c, "passives", "cc", "cc_icon.png"), YELLOW)
    _put(os.path.join(c, "passives", "cc", "cc_icon_b.png"), BLUE)
    return c, hp, bp, wp, cp


class Pointed:
    """The server's folders and jobs module pointed at the temp tree for the length of a `with`."""

    def __init__(self, server, tmp, fake):
        self.server, self.tmp, self.fake = server, tmp, fake

    def __enter__(self):
        s = self.server
        self.saved = (s.CONTENT, s.GODOT, s.BACKUPS, s.JOBS, s.LEGACY_ICON_BACKUPS)
        s.CONTENT = os.path.join(self.tmp, "content")
        s.GODOT = os.path.join(self.tmp, "no-godot.exe")
        s.BACKUPS = os.path.join(self.tmp, "backups")
        s.JOBS = self.fake
        s.LEGACY_ICON_BACKUPS = os.path.join(self.tmp, "dl_backup")
        return self

    def __exit__(self, *a):
        s = self.server
        s.CONTENT, s.GODOT, s.BACKUPS, s.JOBS, s.LEGACY_ICON_BACKUPS = self.saved
        return False


def _src_jobs(fake):
    """Finished candidate jobs as jobs.get returns them."""
    fake.jobs["j20261014-100000-ab12"] = {"id": "j20261014-100000-ab12", "kind": "hero_badge", "state": "done", "target": {"kind": "hero", "id": "hh", "code": ""},
                                          "spec": {}, "plan": {}, "choices": [{"id": "2", "label": "c2", "url": "/dl/ai_raw_anime/hh_portrait_ab12_c2.png"}]}
    fake.jobs["j20261014-100100-cd34"] = {"id": "j20261014-100100-cd34", "kind": "icon_cands", "state": "done", "target": {"kind": "enemy", "id": "bb", "code": "BB-A"},
                                          "spec": {}, "plan": {"icon_job": {}}, "choices": [{"id": "0", "label": "c0", "url": "/dl/icons_le_x/bb_c0.png"}]}
    fake.jobs["j20261014-100200-ef56"] = {"id": "j20261014-100200-ef56", "kind": "hero_title", "state": "done", "target": {"kind": "hero", "id": "hh", "code": "HH-B"},
                                          "spec": {}, "plan": {}, "choices": [{"id": "0", "label": "#0", "url": "/dl/title_heroes/x.png"}]}
    fake.jobs["j20261014-100300-aa77"] = {"id": "j20261014-100300-aa77", "kind": "icon_cands", "state": "done", "target": {"kind": "weapon", "id": "ww", "code": ""},
                                          "spec": {}, "plan": {"icon_job": {}}, "choices": [{"id": "1", "label": "c1", "url": "/dl/icons_le_y/ww_c1.png"}]}
    fake.jobs["j20261014-100400-bb88"] = {"id": "j20261014-100400-bb88", "kind": "icon_cands", "state": "running", "target": {"kind": "enemy", "id": "bb", "code": "BB-A"},
                                          "spec": {}, "plan": {}, "choices": []}


def guard_checks(check, server, tmp, fake):
    c, hp, bp, wp, cp = _tree(tmp)
    _src_jobs(fake)
    # 1. a badge painted for the base, installed for the base: asked (the base; HH-B shows it too)
    st, body = server.install_guard("j20261014-100000-ab12", {"choice": "2"})
    check(st == 409 and body.get("confirm_needed") and body["base"] and not body["played"] and body["look"] == "HH-A"
          and body["now"]["file"] == "hh_icon.png" and body["next"]["file"] == "hh_icon_ab12_c2.png" and body["shared_by"] == ["HH-B"]
          and body["what"] == "badge" and body["next"].get("candidate") and body["next"]["url"].endswith("hh_portrait_ab12_c2.png"),
          "ICON76 guard: a badge for the base waits for confirm (now hh_icon.png -> new hh_icon_ab12_c2.png; HH-B shows it too): %s" % {k: body.get(k) for k in ("look", "base", "played", "now", "next", "shared_by")})
    check("HH-B" in body.get("error", "") and "Nothing is overwritten" in body.get("error", "") and body.get("play") == "HH-B"
          and "HH-B, the look the game plays, is one of them" in body.get("error", ""),
          "ICON76 guard: the refusal says who shares it (the look in play among them) and that nothing is overwritten: %s" % body.get("error"))
    # 2. into the look in play (Garry's case: a base painting landed on SOL-B): asked, the look named played
    st, body = server.install_guard("j20261014-100000-ab12", {"choice": "2", "options": {"variant": "HH-B"}})
    check(st == 409 and body["played"] and not body["base"] and body["look"] == "HH-B" and body["now"]["file"] == "hh_icon.png" and not body["now"]["own"]
          and body["next"]["file"] == "hh_icon_b_ab12_c2.png" and "the look the game plays" in body["error"],
          "ICON76 guard: a badge for the look in play waits for confirm (it shows the hero's own now): %s" % {k: body.get(k) for k in ("look", "played", "now", "next")})
    # 3. with confirm: the options jobs.install gets name the install's own file
    st, opts = server.install_guard("j20261014-100000-ab12", {"choice": "2", "options": {"variant": "HH-B"}, "confirm": True})
    check(st is None and opts.get("icon_file") == "hh_icon_b_ab12_c2.png" and opts.get("icon_code") == "HH-B" and opts.get("variant") == "HH-B"
          and opts.get("why") == "install c2 of #ab12", "ICON76 guard: confirmed, the install gets a file of its own and the look: %s" % opts)
    # 3b. the Jobs tab and an item's candidates send the label ("c2"): the same candidate, the same name
    st, body = server.install_guard("j20261014-100000-ab12", {"choice": "c2", "options": {"variant": "HH-B"}})
    check(st == 409 and body["next"]["file"] == "hh_icon_b_ab12_c2.png" and body["next"]["url"].endswith("hh_portrait_ab12_c2.png") and body.get("choice") == "2"
          and body["next"]["label"] == "c2 of #ab12", "ICON76 guard: a choice sent by its label is the same candidate: %s" % body.get("next"))
    import jobs
    check(jobs.choice_id({"choices": [{"id": "0", "label": "c0"}, {"id": "2", "label": "c2"}]}, "c2") == "2"
          and jobs.choice_id({"choices": [{"id": "1", "label": "#1"}]}, "#1") == "1" and jobs.choice_id({"choices": [{"id": "2", "label": "c2"}]}, "2") == "2"
          and jobs.choice_id({"choices": []}, "c5") == "c5", "ICON76 jobs: choice_id turns a label into the candidate's id (gen_icon_cands read <key>_cc2.png)")
    # 4. a look neither in play nor the base: no question, a file of its own all the same
    st, opts = server.install_guard("j20261014-100000-ab12", {"choice": "2", "options": {"variant": "HH-C"}})
    check(st is None and opts.get("icon_file") == "hh_icon_c_ab12_c2.png" and opts.get("icon_code") == "HH-C",
          "ICON76 guard: a look not in play goes at once, with a new file name: %s" % opts)
    _put(os.path.join(c, "characters", "hh", "hh_icon_c_ab12_c2.png"), PURPLE)
    st, opts = server.install_guard("j20261014-100000-ab12", {"choice": "2", "options": {"variant": "HH-C"}})
    check(st is None and opts.get("icon_file") == "hh_icon_c_ab12_c2_2.png", "ICON76 guard: a name already taken is never reused: %s" % opts.get("icon_file"))
    os.remove(os.path.join(c, "characters", "hh", "hh_icon_c_ab12_c2.png"))
    # 5. a creature look's icon (not in play): at once; the creature's base (in play) is asked
    st, opts = server.install_guard("j20261014-100100-cd34", {"choice": "0"})
    check(st is None and opts.get("icon_file") == "bb_icon_a_cd34_c0.png" and opts.get("icon_code") == "BB-A", "ICON76 guard: a creature look's icon: %s" % opts)
    st, body = server.install_guard("j20261014-100100-cd34", {"choice": "0", "options": {"variant": "BB-0"}})
    check(st == 409 and body["base"] and body["played"] and body["what"] == "icon" and body["now"]["file"] == "bb_icon.png" and body["next"]["file"] == "bb_icon_cd34_c0.png",
          "ICON76 guard: the creature's base in play is asked: %s" % {k: body.get(k) for k in ("base", "played", "now", "next")})
    # 6. an item without looks: its icon is the base and the one in play
    st, body = server.install_guard("j20261014-100300-aa77", {"choice": "1"})
    check(st == 409 and body["base"] and body["played"] and body["now"]["file"] == "ww_icon.png" and body["next"]["file"] == "ww_icon_aa77_c1.png"
          and body["look"] == "" and "has no other looks" in body.get("error", ""),
          "ICON76 guard: a weapon's own icon (no looks) is asked: %s" % {k: body.get(k) for k in ("base", "played", "now", "next", "error")})
    # 6b. a weapon family (lane LOOKS): a mutation wears its weapon's look; its icon for that look is the one in play
    _write_json(os.path.join(c, "weapons", "fw", "fw.json"), {"id": "fw", "name": "Family W", "variant": "B", "variants": {"B": {"name": "Stick", "icon": "fw_icon_b.png"}}})
    _put(os.path.join(c, "weapons", "fw", "fw_icon.png"), RED)
    _put(os.path.join(c, "weapons", "fw", "fw_icon_b.png"), GREEN)
    _write_json(os.path.join(c, "mutations", "fm", "fm.json"), {"id": "fm", "name": "Family M", "weapon": "fw", "kind": "volume",
                                                                "variants": {"B": {"name": "Bundle", "icon": "fm_icon_b.png"}, "C": {"name": "Other"}}})
    _put(os.path.join(c, "mutations", "fm", "fm_icon.png"), BLUE)
    _put(os.path.join(c, "mutations", "fm", "fm_icon_b.png"), YELLOW)
    fdir = os.path.join(c, "mutations", "fm")
    check(server.icon_played_code("weapon", "fw", os.path.join(c, "weapons", "fw"), _json(os.path.join(c, "weapons", "fw", "fw.json"))) == "B"
          and server.icon_played_code("mutation", "fm", fdir, _json(os.path.join(fdir, "fm.json"))) == "B",
          "ICON76 guard: a weapon family plays its weapon's look (B), the mutation with it")
    fake.jobs["j20261014-100500-ff11"] = {"id": "j20261014-100500-ff11", "kind": "icon_cands", "state": "done", "target": {"kind": "mutation", "id": "fm", "code": "B"},
                                          "spec": {}, "plan": {"icon_job": {}}, "choices": [{"id": "0", "label": "c0", "url": "/dl/icons_le_z/fm_c0.png"}]}
    st, body = server.install_guard("j20261014-100500-ff11", {"choice": "0"})
    check(st == 409 and body["played"] and not body["base"] and body["look"] == "B" and body["now"]["file"] == "fm_icon_b.png" and body["next"]["file"] == "fm_icon_b_ff11_c0.png",
          "ICON76 guard: a mutation's icon for the look its family plays is asked: %s" % {k: body.get(k) for k in ("look", "played", "now", "next")})
    st, body = server.install_guard("j20261014-100500-ff11", {"choice": "0", "options": {"variant": "A"}})
    check(st == 409 and body["base"] and body["shared_by"] == ["C"] and body["now"]["file"] == "fm_icon.png",
          "ICON76 guard: the family member's base (A) is asked; C (no icon of its own) wears it: %s" % {k: body.get(k) for k in ("base", "shared_by", "now")})
    # 7. not asked: a title cut-out, an unfinished job, an unknown job (the options go on as sent)
    for jid, what in (("j20261014-100200-ef56", "a title cut-out"), ("j20261014-100400-bb88", "a job still running"), ("jnope", "an unknown job")):
        st, opts = server.install_guard(jid, {"choice": "0", "options": {"variant": "HH-B"}})
        check(st is None and opts == {"variant": "HH-B"}, "ICON76 guard: %s is not asked about: %s" % (what, opts))
    # 8. the job form's named file is used when it is free
    fake.jobs["j20261014-100100-cd34"]["plan"]["icon_job"]["file"] = "bb_named.png"
    st, opts = server.install_guard("j20261014-100100-cd34", {"choice": "0"})
    check(st is None and opts.get("icon_file") == "bb_named.png", "ICON76 guard: the job form's named file wins when it is free: %s" % opts)
    _put(os.path.join(c, "enemies", "bb", "bb_named.png"), GREY)
    st, opts = server.install_guard("j20261014-100100-cd34", {"choice": "0"})
    check(st is None and opts.get("icon_file") == "bb_icon_a_cd34_c0.png", "ICON76 guard: a named file that exists is not overwritten: %s" % opts)
    os.remove(os.path.join(c, "enemies", "bb", "bb_named.png"))
    fake.jobs["j20261014-100100-cd34"]["plan"]["icon_job"].pop("file")


def http_checks(check, server, fake):
    httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    th = threading.Thread(target=httpd.serve_forever, daemon=True)
    th.start()
    base = "http://127.0.0.1:%d" % httpd.server_address[1]

    def req(method, url, body=None):
        data = json.dumps(body).encode("utf-8") if body is not None else None
        r = urllib.request.Request(base + url, data=data, method=method, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(r, timeout=30) as resp:
                raw = resp.read()
                ct = resp.headers.get("Content-Type", "")
                return resp.status, (json.loads(raw.decode("utf-8")) if ct.startswith("application/json") else raw)
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw.decode("utf-8"))
            except ValueError:
                return e.code, raw

    import io
    keep, sys.stdout = sys.stdout, io.StringIO()   # the handler's one-line log of each API call
    try:
        n0 = len(fake.installs)
        st, body = req("POST", "/api/jobs/j20261014-100000-ab12/install", {"choice": "2", "options": {"variant": "HH-B"}})
        check(st == 409 and body.get("confirm_needed") and body.get("next", {}).get("file") == "hh_icon_b_ab12_c2.png" and len(fake.installs) == n0,
              "ICON76 http: POST install into the look in play is a 409 confirm_needed and nothing is queued: %s %s" % (st, body.get("error") if isinstance(body, dict) else body))
        st, body = req("POST", "/api/jobs/j20261014-100000-ab12/install", {"choice": "2", "options": {"variant": "HH-B"}, "confirm": True})
        check(st == 200 and body.get("ok") and len(fake.installs) == n0 + 1 and fake.installs[-1][2].get("icon_file") == "hh_icon_b_ab12_c2.png",
              "ICON76 http: with confirm the install is queued with its own file: %s" % (fake.installs[-1:] if fake.installs else body))
        st, body = req("GET", "/api/content/hero/hh/icons")
        check(st == 200 and body.get("ok") and [x["code"] for x in body["looks"]] == ["HH-A", "HH-B", "HH-C"], "ICON76 http: GET icons lists the looks, the base first: %s" % (body.get("looks") if isinstance(body, dict) else body))
        st, raw = req("GET", "/iconfile/hero/hh/folder/hh_icon.png")
        check(st == 200 and raw == RED, "ICON76 http: /iconfile serves a folder icon's bytes")
        for bad in ("/iconfile/hero/hh/folder/hh_sprite.png", "/iconfile/hero/hh/folder/..%2Fhh.json", "/iconfile/hero/hh/legacy/notes/hh_icon.png",
                    "/iconfile/hero/hh/backup/..%5Chh.json", "/iconfile/hero/nobody/folder/x_icon.png", "/iconfile/hero/hh/folder/hh.json"):
            st, raw = req("GET", bad)
            check(st == 404, "ICON76 http: %s is a 404 (%s)" % (bad, st))
        st, body = req("POST", "/api/content/hero/hh/icon", {"op": "revert", "code": "HH-B"})
        check(st == 409 and "nothing to revert" in body.get("error", ""), "ICON76 http: POST icon revert with nothing to revert is a 409: %s" % body.get("error"))
        st, body = req("POST", "/api/content/hero/hh/look/HH-C", {"op": "revert_icon"})
        check(st == 200 and body.get("ok") and "icon" not in _json(os.path.join(server.CONTENT, "characters", "hh", "hh.json"))["variants"]["HH-C"],
              "ICON76 http: the look op revert_icon drops a pick made before the guard (no history)")
    finally:
        sys.stdout = keep
        httpd.shutdown()
        httpd.server_close()


def pick_revert_checks(check, server, tmp, fake):
    c = os.path.join(tmp, "content")
    hp = os.path.join(c, "characters", "hh", "hh.json")
    hdir = os.path.dirname(hp)
    bdir = server.icon_backup_dir("hh")
    hooks = server.HOOKS
    # the install job's tool wrote the new badge under its own name (BLUE); the landing goes through set_look_files
    _put(os.path.join(hdir, "hh_icon_b_ab12_c2.png"), BLUE)
    src = _read(hp)
    r = hooks.set_look_files("hero", "hh", "HH-B", {"icon": "hh_icon_b_ab12_c2.png"}, {"why": "install c2 of #ab12"})
    d = _json(hp)
    e = d["variants"]["HH-B"]
    h = e.get("icon_history") or []
    check(r.get("ok") and r.get("layout") == "entry" and r.get("backup") and e.get("icon") == "hh_icon_b_ab12_c2.png" and e.get("icon_picked") is True
          and len(h) == 1 and h[0]["icon"] == "" and h[0]["shown"] == "hh_icon.png" and h[0]["to"] == "hh_icon_b_ab12_c2.png" and h[0]["why"] == "install c2 of #ab12"
          and h[0]["picked"] is False and h[0]["at"], "ICON76 pick: the landing names the new badge, marks it picked and keeps the step in icon_history: %s" % e)
    check(server.cio.diff_within_entry(src, _read(hp), "HH-B") and {k: v for k, v in d.items() if k != "variants"} == {k: v for k, v in json.loads(src).items() if k != "variants"},
          "ICON76 pick: only HH-B's entry changed")
    check(_bytes(os.path.join(hdir, "hh_icon.png")) == RED, "ICON76 pick: the hero's own badge (the old one) is untouched on disk")
    copy = server._abs_path(h[0]["backup"])
    same_dir = os.path.normcase(os.path.normpath(os.path.dirname(copy))) == os.path.normcase(os.path.normpath(os.path.abspath(bdir)))
    check(same_dir and _bytes(copy) == RED and re.match(r"^hh_icon_\d{8}-\d{6}(-\d+)?\.png$", os.path.basename(copy)),
          "ICON76 backups: a copy of the replaced picture under backups/<id>/: %s" % h[0]["backup"])
    g = server.icon_gallery("hero", "hh")
    red = [t for t in g["files"] if t["digest"] == server._file_digest(os.path.join(hdir, "hh_icon.png"))[:12]]
    check(g.get("ok") and len(red) == 1 and red[0]["ref"] == "folder/hh_icon.png" and red[0]["used_by"] == ["HH-A", "HH-C"] and [x["ref"] for x in red[0]["copies"]] == ["backup/" + os.path.basename(copy)],
          "ICON76 gallery: the old badge is one tile (the folder's, its backup a copy), still shown by the base and HH-C: %s" % red)
    looks = {x["code"]: x for x in g["looks"]}
    check(looks["HH-B"]["shown"] == "hh_icon_b_ab12_c2.png" and looks["HH-B"]["played"] and looks["HH-B"]["revertable"] and looks["HH-A"]["base"] and looks["HH-A"]["shown"] == "hh_icon.png",
          "ICON76 gallery: each look's icon now: %s" % {k: (v["shown"], v["played"], v["revertable"]) for k, v in looks.items()})
    r = hooks.set_look_files("hero", "hh", "HH-B", {"icon": "hh_icon_b_ab12_c2.png"}, {"why": "again"})
    check(r.get("ok") and r.get("unchanged") and not r.get("backup") and len(_json(hp)["variants"]["HH-B"]["icon_history"]) == 1, "ICON76 pick: the same file again writes nothing")
    # revert: asked (the look in play), then the step undone; the reverted-from file stays on disk
    r = server.revert_icon("hero", "hh", "HH-B", confirm=False)
    check(not r.get("ok") and r.get("status") == 409 and r.get("confirm_needed") and r["now"]["file"] == "hh_icon_b_ab12_c2.png" and r["next"]["file"] == "hh_icon.png",
          "ICON76 revert: the look in play asks first (now -> back to): %s" % {k: r.get(k) for k in ("now", "next")})
    check("icon_history" in _json(hp)["variants"]["HH-B"], "ICON76 revert: nothing changed before the answer")
    r = server.revert_icon("hero", "hh", "HH-B", confirm=True)
    e = _json(hp)["variants"]["HH-B"]
    check(r.get("ok") and "icon" not in e and "icon_picked" not in e and "icon_history" not in e and r["file"] == "hh_icon.png" and r.get("import_ok") is False
          and os.path.isfile(os.path.join(hdir, "hh_icon_b_ab12_c2.png")),
          "ICON76 revert: HH-B shows the hero's own badge again (its own icon, mark and history gone; the new badge stays on disk): %s" % e)
    r = server.revert_icon("hero", "hh", "HH-B", confirm=True)
    check(not r.get("ok") and r.get("status") == 409 and "nothing to revert" in r.get("error", ""), "ICON76 revert: nothing more to revert says so: %s" % r.get("error"))
    # a picture painted over since: put back from its copy (the creature's look, not in play: no question)
    bdir2 = os.path.join(c, "enemies", "bb")
    _put(os.path.join(bdir2, "bb_icon_a_x1.png"), CYAN)
    r = server.set_look_icon("enemy", "bb", "BB-A", "bb_icon_a_x1.png", "use folder/bb_icon_a_x1.png", confirm=False)
    check(r.get("ok") and _json(os.path.join(bdir2, "bb.json"))["variants"]["BB-A"]["icon"] == "bb_icon_a_x1.png", "ICON76 use: a look not in play takes another icon without a question: %s" % r.get("error"))
    _put(os.path.join(bdir2, "bb_icon_a.png"), MAGENTA)   # an older tool paints over the old icon
    n0 = len(fake.enqueued)
    r = server.revert_icon("enemy", "bb", "BB-A", confirm=False)
    e = _json(os.path.join(bdir2, "bb.json"))["variants"]["BB-A"]
    back = e.get("icon", "")
    check(r.get("ok") and r.get("put_back") and back.startswith("bb_icon_a_") and back != "bb_icon_a.png" and _bytes(os.path.join(bdir2, back)) == ORANGE
          and "icon_picked" not in e and "icon_history" not in e and len(fake.enqueued) == n0 + 1 and fake.enqueued[-1]["kind"] == "import",
          "ICON76 revert: a picture painted over since comes back from its copy under its own name, an import (the PNG first) queued: %s %s" % (back, r.get("output")))
    # Solenne's case: a pick from before the guard (no history) on a look not in play
    _write_json(os.path.join(c, "characters", "hh", "hh.json"), dict(_json(hp), variants=dict(_json(hp)["variants"], **{"HH-C": {"note": "c", "sprite": "hh_sprite_c.png", "icon": "hh_icon_c.png", "icon_picked": True}})))
    r = server.revert_icon("hero", "hh", "HH-C", confirm=False)
    e = _json(hp)["variants"]["HH-C"]
    check(r.get("ok") and "icon" not in e and "icon_picked" not in e and e.get("sprite") == "hh_sprite_c.png" and os.path.isfile(os.path.join(hdir, "hh_icon_c.png")),
          "ICON76 revert: a pick from before the guard (no history) drops the look's icon; the file stays on disk: %s" % e)
    # a look's own icon that was never picked (a creature look's front crop): nothing to revert
    r = server.revert_icon("enemy", "bb", "BB-A", confirm=True)
    check(not r.get("ok") and "nothing to revert" in r.get("error", ""), "ICON76 revert: a look's own painting (not a pick, no history) is not reverted: %s" % r.get("error"))


def gallery_use_checks(check, server, tmp, fake):
    c = os.path.join(tmp, "content")
    hp = os.path.join(c, "characters", "hh", "hh.json")
    hdir = os.path.dirname(hp)
    # an older tool's copy and a removed look's file
    _put(os.path.join(server.LEGACY_ICON_BACKUPS, "icons_le", "hh_icon_20261013-211112.png"), YELLOW)
    _put(os.path.join(server.LEGACY_ICON_BACKUPS, "icons73", "hh_icon.png"), RED)
    _put(os.path.join(server.LEGACY_ICON_BACKUPS, "icons73", "other_icon.png"), GREEN)
    _put(os.path.join(server.BACKUPS, "deleted", "hh", "20261001-000000", "hh_icon_d.png"), PURPLE)
    g = server.icon_gallery("hero", "hh")
    by = {t["ref"]: t for t in g["files"]}
    allrefs = [t["ref"] for t in g["files"]] + [x["ref"] for t in g["files"] for x in t["copies"]]
    check("legacy/icons_le/hh_icon_20261013-211112.png" in by and by["legacy/icons_le/hh_icon_20261013-211112.png"]["where"] == "legacy"
          and "deleted/20261001-000000/hh_icon_d.png" in by and "legacy/icons73/hh_icon.png" in allrefs and "legacy/icons73/hh_icon.png" not in by
          and not any("other_icon" in x for x in allrefs),
          "ICON76 gallery: the older tools' copies and removed looks' files are listed (a copy of a known picture under its tile; another asset's never): %s" % allrefs)
    pics = [t["digest"] for t in g["files"]]
    check(len(pics) == len(set(pics)) and {"folder/hh_icon.png", "folder/hh_icon_c.png", "folder/hh_icon_b_ab12_c2.png"} <= set(by),
          "ICON76 gallery: one tile per picture, every folder icon there: %s" % sorted(by))
    check(server.icon_ref_path("hero", "hh", "legacy/icons_le/hh_icon_20261013-211112.png") and not server.icon_ref_path("hero", "hh", "legacy/icons73/other_icon.png")
          and not server.icon_ref_path("hero", "hh", "folder/../hh.json") and not server.icon_ref_path("hero", "hh", "deleted/x/hh_sprite.png"),
          "ICON76 gallery: a ref names this asset's icons only")
    # Use for this look: an older tool's copy onto the base (asked first: nothing copied before the answer)
    ref = "legacy/icons_le/hh_icon_20261013-211112.png"
    r = server.use_icon("hero", "hh", "", ref, confirm=False)
    check(not r.get("ok") and r.get("confirm_needed") and r["base"] and r["next"]["file"] == "hh_icon_20261013-211112.png" and not os.path.exists(os.path.join(hdir, "hh_icon_20261013-211112.png")),
          "ICON76 use: the base asks first, nothing copied yet: %s" % {k: r.get(k) for k in ("base", "next")})
    n0 = len(fake.enqueued)
    r = server.use_icon("hero", "hh", "", ref, confirm=True)
    d = _json(hp)
    check(r.get("ok") and r.get("put_back") and d.get("icon") == "hh_icon_20261013-211112.png" and _bytes(os.path.join(hdir, "hh_icon_20261013-211112.png")) == YELLOW
          and isinstance(d.get("icon_history"), list) and d["icon_history"][-1]["icon"] == "" and d["icon_history"][-1]["shown"] == "hh_icon.png"
          and _bytes(os.path.join(hdir, "hh_icon.png")) == RED and len(fake.enqueued) == n0 + 1,
          "ICON76 use: the copy is put back under its own name, the top-level icon names it, the base's history at the top level, the old badge kept: %s" % {k: d.get(k) for k in ("icon", "icon_history")})
    # the base's revert: the top-level icon key goes again
    r = server.revert_icon("hero", "hh", "HH-A", confirm=True)
    d = _json(hp)
    check(r.get("ok") and "icon" not in d and "icon_history" not in d and r["file"] == "hh_icon.png", "ICON76 revert: the base back to the hero's own <id>_icon.png: %s" % {k: d.get(k) for k in ("icon", "icon_history")})
    # a folder file onto a look not in play, then a backup copy with the same bytes as a folder file (no second copy)
    r = server.use_icon("hero", "hh", "HH-C", "folder/hh_icon_c.png", confirm=False)
    e = _json(hp)["variants"]["HH-C"]
    check(r.get("ok") and not r.get("put_back") and e.get("icon") == "hh_icon_c.png" and e.get("icon_picked") is True and len(e.get("icon_history", [])) == 1,
          "ICON76 use: a folder icon onto a look not in play: %s" % e)
    before = sorted(os.listdir(hdir))
    copy_ref = next(x["ref"] for t in server.icon_gallery("hero", "hh")["files"] for x in [t] + t["copies"] if x["ref"].startswith("backup/") and t["file"] == "hh_icon.png")
    r = server.use_icon("hero", "hh", "HH-C", copy_ref, confirm=False)
    e = _json(hp)["variants"]["HH-C"]
    check(r.get("ok") and not r.get("put_back") and e.get("icon") == "hh_icon.png" and sorted(os.listdir(hdir)) == before,
          "ICON76 use: a backup whose picture is in the folder uses that file (no second copy): %s" % e.get("icon"))
    # an item without looks: its own icon, asked, with the history at the top level; and back
    wp = os.path.join(c, "weapons", "ww", "ww.json")
    r = server.use_icon("weapon", "ww", "", "folder/ww_icon_alt.png", confirm=False)
    check(not r.get("ok") and r.get("confirm_needed") and r["base"] and r["played"], "ICON76 use: a weapon's own icon asks first")
    r = server.use_icon("weapon", "ww", "", "folder/ww_icon_alt.png", confirm=True)
    d = _json(wp)
    check(r.get("ok") and d.get("icon") == "ww_icon_alt.png" and len(d.get("icon_history", [])) == 1 and r.get("import_ok") is False,
          "ICON76 use: a weapon's icon (no looks) names the new file at the top level: %s" % {k: d.get(k) for k in ("icon", "icon_history")})
    r = server.icon_op("weapon", "ww", "", "revert", {"confirm": True})
    d = _json(wp)
    check(r.get("ok") and "icon" not in d and "icon_history" not in d, "ICON76 revert: a weapon back to <id>_icon.png")
    # a card's look in play through the job's hook (no question at the landing: it was asked when queued)
    _put(os.path.join(c, "passives", "cc", "cc_icon_b_9z9z_c0.png"), GREY)
    r = server.HOOKS.set_look_files("passive", "cc", "B", {"icon": "cc_icon_b_9z9z_c0.png"}, {"why": "install c0 of #9z9z"})
    e = _json(os.path.join(c, "passives", "cc", "cc.json"))["variants"]["B"]
    check(r.get("ok") and e.get("icon") == "cc_icon_b_9z9z_c0.png" and e["icon_history"][0]["icon"] == "cc_icon_b.png" and _bytes(os.path.join(c, "passives", "cc", "cc_icon_b.png")) == BLUE,
          "ICON76 pick: a card look's icon through the hook keeps its history (the old card stays): %s" % e)
    r = server.revert_icon("passive", "cc", "B", confirm=True)
    e = _json(os.path.join(c, "passives", "cc", "cc.json"))["variants"]["B"]
    check(r.get("ok") and e.get("icon") == "cc_icon_b.png" and "icon_picked" not in e and "icon_history" not in e, "ICON76 revert: the card look back to its own icon (not marked picked: it was not): %s" % e)


def backup_checks(check, server, tmp):
    bdir = server.icon_backup_dir("hh")
    check(os.path.abspath(bdir) == os.path.abspath(os.path.join(server.BACKUPS, "hh")), "ICON76 backups: the icon copies live under backups/<id>/")
    n = len(os.listdir(bdir))
    made = server.snapshot_icons("hero", "hh")
    n1 = len(os.listdir(bdir))
    again = server.snapshot_icons("hero", "hh")
    check(made and len(again) == len(made) and len(os.listdir(bdir)) == n1 and n1 >= n, "ICON76 backups: a snapshot copies each picture once (%d -> %d files)" % (n, n1))
    digests = [server._file_digest(os.path.join(bdir, f)) for f in os.listdir(bdir)]
    check(len(digests) == len(set(digests)), "ICON76 backups: no picture twice under backups/hh/")
    check(os.path.isfile(os.path.join(server.BACKUPS, ".gitignore")), "ICON76 backups: backups/ keeps its .gitignore")
    name = server.fresh_icon_name(os.path.join(server.CONTENT, "characters", "hh"), "hh", "HH-B", "ab12_c2")
    check(name == "hh_icon_b_ab12_c2_2.png", "ICON76 names: a fresh name skips the taken one: %s" % name)
    check(server.fresh_icon_name(os.path.join(tmp, "nowhere"), "hh", "", "") == "hh_icon.png", "ICON76 names: the base's plain name when it is free")


def jobs_checks(check, server, tmp):
    import jobs
    saved = (jobs._hooks, jobs._state, getattr(jobs, "_inited", None))
    try:
        jobs._hooks = {"content_path": server.content_path, "set_look_files": server.HOOKS.set_look_files, "merge_top": server.HOOKS.merge_top,
                       "snapshot_icons": server.HOOKS.snapshot_icons}
        src = {"id": "j20261014-100000-ab12", "kind": "hero_badge", "state": "done", "target": {"kind": "hero", "id": "hh", "code": ""}, "spec": {}, "plan": {},
               "choices": [{"id": "2", "label": "c2"}]}
        src2 = {"id": "j20261014-100100-cd34", "kind": "icon_cands", "state": "done", "target": {"kind": "enemy", "id": "bb", "code": "BB-A"}, "spec": {},
                "plan": {"key": "bb", "icon_job": {"kind": "enemies", "id": "bb", "subject": "a beast", "set": "_le_x"}}, "choices": [{"id": "0"}]}
        jobs._state = {"rev": 1, "jobs": [src, src2]}
        inst = {"id": "j20261014-110000-1111", "kind": "install", "method": "install", "target": {"kind": "hero", "id": "hh", "code": "HH-B"}, "attempt": 1,
                "spec": {"source_job": src["id"], "choice": "2", "variant": "HH-B", "icon_file": "hh_icon_b_ab12_c2.png", "icon_code": "HH-B", "why": "install c2 of #ab12"}}
        p = jobs._plan(inst)
        check("--icon-file" in p.get("argv", []) and p["argv"][p["argv"].index("--icon-file") + 1] == "hh_icon_b_ab12_c2.png",
              "ICON76 jobs: a badge install's plan hands the tool its own file (--icon-file): %s" % p.get("argv"))
        inst2 = {"id": "j20261014-110100-2222", "kind": "install", "method": "install", "target": {"kind": "enemy", "id": "bb", "code": "BB-A"}, "attempt": 1,
                 "spec": {"source_job": src2["id"], "choice": "0", "icon_file": "bb_icon_a_cd34_c0.png", "icon_code": "BB-A", "why": "install c0 of #cd34"}}
        p = jobs._plan(inst2)
        check(p.get("icon_job", {}).get("file") == "bb_icon_a_cd34_c0.png" and p["icon_job"].get("keep_old") is True,
              "ICON76 jobs: an icon install's plan names the file and keep_old: %s" % p.get("icon_job"))
        # install() carries the guard's options into the spec
        fake_find = jobs._find
        saved_enqueue, saved_writable = jobs.enqueue, jobs._writable
        got = {}
        try:
            jobs.enqueue = lambda kind, target, spec, title=None: got.update(kind=kind, target=target, spec=spec) or {"id": "jx"}
            jobs._writable = lambda: None
            jobs.install(src["id"], "2", {"variant": "HH-B", "icon_file": "hh_icon_b_ab12_c2.png", "icon_code": "HH-B", "why": "install c2 of #ab12"})
        finally:
            jobs.enqueue, jobs._writable = saved_enqueue, saved_writable
        check(got.get("spec", {}).get("icon_file") == "hh_icon_b_ab12_c2.png" and got["spec"].get("icon_code") == "HH-B" and got["spec"].get("why") == "install c2 of #ab12",
              "ICON76 jobs: install() keeps the file, the look and why in the spec: %s" % got.get("spec"))
        # the landing: through set_look_files (the look's history), a base badge's block after it
        hp = os.path.join(server.CONTENT, "characters", "hh", "hh.json")
        _put(os.path.join(os.path.dirname(hp), "hh_icon_b_ab12_c2_3.png"), CYAN)
        w, err = jobs._post_install_icon(dict(inst, spec=dict(inst["spec"])), {"variant": "HH-B", "entry": {"icon": "hh_icon_b_ab12_c2_3.png"}, "info": {}})
        e = _json(hp)["variants"]["HH-B"]
        check(not err and w and w.get("layout") == "entry" and e.get("icon") == "hh_icon_b_ab12_c2_3.png" and e["icon_history"][-1]["why"] == "install c2 of #ab12",
              "ICON76 jobs: a look's install lands through set_look_files with its reason: %s %s" % (err, e))
        _put(os.path.join(os.path.dirname(hp), "hh_icon_ab12_c2.png"), ORANGE)
        base_inst = dict(inst, target={"kind": "hero", "id": "hh", "code": ""}, spec=dict(inst["spec"], icon_file="hh_icon_ab12_c2.png", icon_code="", variant=""))
        w, err = jobs._post_install_icon(base_inst, {"variant": "", "entry": {}, "info": {"icon_file": "hh_icon_ab12_c2.png"},
                                                     "top": {"badge": {"still": "hh_portrait_ab12_c2", "head_width": 0.0, "top_pad": 0.03}}})
        d = _json(hp)
        check(not err and d.get("icon") == "hh_icon_ab12_c2.png" and d.get("badge", {}).get("still") == "hh_portrait_ab12_c2" and d["icon_history"][-1]["shown"] == "hh_icon.png"
              and _bytes(os.path.join(os.path.dirname(hp), "hh_icon.png")) == RED and "badge" in w.get("keys", []),
              "ICON76 jobs: a base install names the new badge at the top level and writes the badge block; the old badge stays: %s %s" % (err, {k: d.get(k) for k in ("icon", "badge")}))
        w, err = jobs._post_install_icon(dict(inst2, spec=dict(inst2["spec"], icon_file="bb_missing.png")), {"entry": {}, "info": {}})
        check(w is None and "wrote no icon file" in err, "ICON76 jobs: an install that wrote nothing says so: %s" % err)
        # the snapshot before a job
        server.snapshot_icons("enemy", "bb")
        n = len(os.listdir(server.icon_backup_dir("bb")))
        _put(os.path.join(server.CONTENT, "enemies", "bb", "bb_icon_a.png"), _png((1, 2, 3)))
        jobs._snapshot_icons({"kind": "look", "target": {"kind": "enemy", "id": "bb", "code": "BB-A"}})
        check(len(os.listdir(server.icon_backup_dir("bb"))) == n + 1, "ICON76 jobs: a look job's run starts with a snapshot of the creature's icons")
        jobs._snapshot_icons({"kind": "launch", "target": {"kind": "enemy", "id": "bb"}})
        check(len(os.listdir(server.icon_backup_dir("bb"))) == n + 1, "ICON76 jobs: other jobs take no snapshot")
        del fake_find
    finally:
        jobs._hooks, jobs._state = saved[0], saved[1]
    # merge_look keeps a picked icon when a re-roll lands
    bp = os.path.join(server.CONTENT, "enemies", "bb", "bb.json")
    _put(os.path.join(os.path.dirname(bp), "bb_icon_a_pick.png"), GREEN)
    server.set_look_icon("enemy", "bb", "BB-A", "bb_icon_a_pick.png", "use folder/bb_icon_a_pick.png", confirm=None)
    r = server.HOOKS.merge_look("enemy", "bb", "BB-A", {"sprite": "bb_sprite_a.png", "icon": "bb_icon_a.png", "anims": {"idle": 2, "run": 6}}, {})
    e = _json(bp)["variants"]["BB-A"]
    check(r.get("ok") and e.get("icon") == "bb_icon_a_pick.png" and e.get("icon_picked") is True and e.get("fresh") is True,
          "ICON76 jobs: a re-roll landing on a look with a picked icon keeps the pick: %s" % e.get("icon"))


def tool_checks(check, tmp):
    """gen_badge_cands --icon-file and gen_icon_cands keep_old: a file of their own, never over another picture."""
    try:
        from PIL import Image, ImageDraw   # noqa: F401
    except ImportError:
        print("ICON76: PIL is not here: the pick tools are not run")
        return
    saved_argv, saved_path = list(sys.argv), list(sys.path)
    sys.path.insert(0, TOOLS)
    try:
        import gen_badge_cands as gbc
        sys.argv = list(saved_argv)
        import gen_icon_cands as gic
        import gen_art as ga
    finally:
        sys.argv = saved_argv
        sys.path[:] = saved_path
    keep = {"ga": (ga.RAW, ga.SIDECAR), "gbc": gbc.CHARS, "gic": (gic.CONTENT, gic.DL), "env": os.environ.pop("ASSET_JOB_SIDECAR", None)}
    jobs_keep = dict(gic.JOBS)

    def figure(path, screen):
        from PIL import Image, ImageDraw
        os.makedirs(os.path.dirname(path), exist_ok=True)
        im = Image.new("RGB", (256, 256), screen)
        dr = ImageDraw.Draw(im)
        dr.ellipse((92, 30, 164, 102), fill=(235, 190, 150))
        dr.rectangle((76, 97, 180, 230), fill=(200, 80, 30))
        im.save(path)

    try:
        root = os.path.join(tmp, "tools_run")
        ga.RAW = os.path.join(root, "raw")
        chars = os.path.join(root, "characters")
        gbc.CHARS = chars
        jp = os.path.join(chars, "tt", "tt.json")
        _write_json(jp, {"id": "tt", "name": "T", "variant_base": "TT-A", "variants": {"TT-A": {"note": "base"}, "TT-B": {"note": "b", "sprite": "tt_sprite_b.png"}}})
        _put(os.path.join(chars, "tt", "tt_icon.png"), RED)
        _put(os.path.join(chars, "tt", "tt_icon_b_ab12_c2.png"), GREEN)   # the name is taken by another picture
        figure(os.path.join(ga.RAW, "tt_portrait_ab12_c2.png"), (0, 0, 255))
        side = os.path.join(root, "result.json")
        os.environ["ASSET_JOB_SIDECAR"] = side
        ga.SIDECAR = side
        gbc.pick("tt", "2", 0.0, 0.03, "TT-B", "j20261014-100000-ab12", icon_file="tt_icon_b_ab12_c2.png")
        r = _json(side)
        check(r.get("entry") == {"icon": "tt_icon_b_ab12_c2_2.png"} and r["info"].get("icon_file") == "tt_icon_b_ab12_c2_2.png"
              and _bytes(os.path.join(chars, "tt", "tt_icon_b_ab12_c2.png")) == GREEN and os.path.isfile(os.path.join(chars, "tt", "tt_icon_b_ab12_c2_2.png")),
              "ICON76 tools: gen_badge_cands --icon-file never writes over another picture (a taken name gets _2): %s" % r.get("entry"))
        gbc.pick("tt", "2", 0.0, 0.03, "", "j20261014-100000-ab12", icon_file="tt_icon_ab12_c2.png")
        r = _json(side)
        check(r.get("entry") == {} and r["info"].get("icon_file") == "tt_icon_ab12_c2.png" and r.get("top", {}).get("badge", {}).get("still") == "tt_portrait_ab12_c2"
              and _bytes(os.path.join(chars, "tt", "tt_icon.png")) == RED,
              "ICON76 tools: a base badge with --icon-file leaves <id>_icon.png alone and says its file: %s" % r.get("info"))
        gic.CONTENT = os.path.join(root, "content")
        gic.DL = os.path.join(root, "dl")
        cj = os.path.join(gic.CONTENT, "enemies", "tb", "tb.json")
        _write_json(cj, {"id": "tb", "variant_base": "TB-0", "variants": {"TB-0": {"note": "base"}, "TB-B": {"note": "b", "sprite": "tb_sprite_b.png", "icon": "tb_icon_b.png"}}})
        _put(os.path.join(gic.CONTENT, "enemies", "tb", "tb_icon_b.png"), ORANGE)
        figure(os.path.join(gic.DL, "icons_le_j9", "tb_c1.png"), (0, 255, 0))
        gic.JOBS["tb"] = {"kind": "enemies", "id": "tb", "subject": "a beast", "set": "_le_j9", "variant": "TB-B", "file": "tb_icon_b.png", "keep_old": True}
        gic.pick(["tb=1"])
        r = _json(side)
        check(r.get("entry") == {"icon": "tb_icon_b_2.png"} and r["info"].get("icon_file") == "tb_icon_b_2.png" and _bytes(os.path.join(gic.CONTENT, "enemies", "tb", "tb_icon_b.png")) == ORANGE,
              "ICON76 tools: gen_icon_cands keep_old writes a file of its own beside the old icon: %s" % r.get("entry"))
        check(ga.free_icon_name(os.path.join(gic.CONTENT, "enemies", "tb"), "tb_icon_b_2.png", _bytes(os.path.join(gic.CONTENT, "enemies", "tb", "tb_icon_b_2.png")))[0] == "tb_icon_b_2.png",
              "ICON76 tools: free_icon_name reuses a name whose file holds the very same picture")
    finally:
        ga.RAW, ga.SIDECAR = keep["ga"]
        gbc.CHARS = keep["gbc"]
        gic.CONTENT, gic.DL = keep["gic"]
        gic.JOBS.clear()
        gic.JOBS.update(jobs_keep)
        if keep["env"] is None:
            os.environ.pop("ASSET_JOB_SIDECAR", None)
        else:
            os.environ["ASSET_JOB_SIDECAR"] = keep["env"]


def page_checks(check):
    looks = _read(os.path.join(HERE, "looks.js"))
    jobsjs = _read(os.path.join(HERE, "jobs.js"))
    tf = _read(os.path.join(HERE, "typed_forms.js"))
    assets = _read(os.path.join(HERE, "assets.js"))
    css = _read(os.path.join(HERE, "style.css"))
    doc = _read(os.path.join(ROOT, "docs", "level_editor.md"))
    check("function confirmIconChange" in looks and "confirm_needed" in looks and "Revert icon" in looks and "All icons on disk" in looks and "Use for " in looks
          and "function iconPanel" in looks and "installPick" in looks, "ICON76 page: looks.js has the question, Revert icon, the gallery and installPick")
    check("confirmIconChange" in jobsjs and "confirm: true" in jobsjs, "ICON76 page: the Jobs tab's Install asks first (jobs.js)")
    check("confirmIconChange" in tf and "confirm: true" in tf, "ICON76 page: an item's icon candidates ask first (typed_forms.js)")
    check("iconPanel" in assets and "'icon_history'" in assets, "ICON76 page: assets.js shows the gallery for items and takes icon_history from disk")
    check(".lg-iconpanel" in css and ".icg-tile" in css, "ICON76 page: the panel's styles are in style.css")
    check("## Pass 76" in doc and "Revert icon" in doc and "All icons on disk" in doc and "backups/<id>/" in doc, "ICON76 docs: docs/level_editor.md has the Pass 76 section")
    instr = _read(os.path.join(HERE, "instructions.js"))
    check("function pass76Icons(root)" in instr and "pass76Icons(root);" in instr and "Revert icon" in instr, "ICON76 docs: the Instructions tab has the pass 76 how-tos")


def content_checks(check):
    sj = os.path.join(ROOT, "game", "content", "characters", "solenne", "solenne.json")
    d = _json(sj)
    b = d.get("variants", {}).get("SOL-B", {})
    check(d.get("variant") == "SOL-B" and "icon" not in b and "icon_picked" not in b and not d.get("icon"),
          "ICON76 content: Solenne plays SOL-B and it names no icon of its own (her badge is solenne_icon.png again)")
    folder = os.path.dirname(sj)
    check(os.path.isfile(os.path.join(folder, "solenne_icon.png")) and os.path.isfile(os.path.join(folder, "solenne_icon_b.png")),
          "ICON76 content: both badges are on disk (solenne_icon_b.png kept for the gallery)")


def checks(check, run_node, server):
    tmp = tempfile.mkdtemp(prefix="le_icon76_")
    fake = FakeJobs()
    try:
        with Pointed(server, tmp, fake):
            guard_checks(check, server, tmp, fake)
            http_checks(check, server, fake)
            pick_revert_checks(check, server, tmp, fake)
            gallery_use_checks(check, server, tmp, fake)
            backup_checks(check, server, tmp)
            jobs_checks(check, server, tmp)
        tool_checks(check, tmp)
        page_checks(check)
        content_checks(check)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
