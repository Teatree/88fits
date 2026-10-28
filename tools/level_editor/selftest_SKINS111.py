"""Pass 111, lane SKINS: a hero's looks sold to the players (skins) and the currency registry in the Level Editor.
selftest.py discovers this file (`extra_checks`) and hands it its `check` counter; `python selftest_SKINS111.py` runs it
alone. Every write happens on a temporary content tree (server.CONTENT / GODOT / BACKUPS / LEDGER re-pointed, as
selftest_S does; the import is replaced by a recorder, so Godot never runs); the real content is only read.

  record    /api/heroes and /api/content/hero/<id> carry each look's `skin`, the goal quests by code, the count on sale
  write     the skin route writes the look entry in place (the file's key order kept, every other key and entry
            untouched, LF, a backup first), the goal quest {unlocks {type skin, id hero:CODE}, condition pruned to its
            type's keys, the badge as its icon} and the skin's unlock_quest, then imports both
  refuse    the played look, a shelved look, an unpainted look, an unknown currency, a negative or broken price, an
            unknown condition type, a stage past the map's, an unknown look or hero; a refusal writes nothing
  edit      a later save edits only what changed (the quest in place), the same values write nothing
  remove    Remove goal moves the quest folder to backups/deleted and clears unlock_quest
  currency  /api/currencies lists the registry (gold, its icon served); the hero availability op takes any registry
            currency and refuses others ("gems" until a gems folder exists); no folder = gold stands in
  words     assets_model.js says beat_stage as "Beat Nightfall with May." (any hero: "Beat Nightfall."); the condition
            rows and vocab know beat_stage; the page files load skins.js
"""
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
REAL_CONTENT = os.path.join(ROOT, "game", "content")
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import content_io as cio  # noqa: E402
import vocab  # noqa: E402
import skins_io  # noqa: E402

HERO = {
    "id": "hero_s", "name": "Hero S", "flavour": "A test hero.", "order": 9, "pronoun": "she", "hidden": False,
    "availability": "purchase", "price": 50, "currency_type": "gold", "trait": [], "frame_px": 256,
    "variant_base": "HS-A", "variant": "HS-B", "sprite": "hero_s_sprite.png", "icon": "hero_s_icon.png",
    "anims": {"idle": 1, "run": 2}, "strip_cols": 0, "fps": {},
    "variants": {
        "HS-A": {"note": "the base", "recipe": {"painter": {"seed": 1}}},
        "HS-B": {"sprite": "hero_s_sprite_b.png", "note": "played", "anims": {"idle": 1, "run": 2}, "strip_cols": 3},
        "HS-C": {"sprite": "hero_s_sprite_c.png", "icon": "hero_s_icon_c.png", "note": "the one to sell", "fresh": True,
                 "anims": {"idle": 1, "run": 2}, "strip_cols": 3, "fps": {"run": 12.0}},
        "HS-D": {"sprite": "hero_s_sprite_d.png", "note": "shelved", "shelved": True},
        "HS-E": {"sprite": "hero_s_sprite_e.png", "note": "not painted yet"},
    },
    "badge": {"head_width": 0.5},
}
MAP = {"id": "red_canyon", "name": "Red Canyon",
       "timeline_data": {"stage_list": [{"id": "s1", "name": "Sundown", "length": 430}, {"id": "s2", "name": "Nightfall", "length": 600},
                                        {"id": "s3", "name": "Blood Moon", "length": 780}]}}


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))


def _read(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8")


def build_tree(root):
    content = os.path.join(root, "content")
    _write(os.path.join(content, "characters", "hero_s", "hero_s.json"), json.dumps(HERO, indent=2, ensure_ascii=False) + "\n")
    folder = os.path.join(content, "characters", "hero_s")
    for f in ("hero_s_sprite.png", "hero_s_sprite_b.png", "hero_s_sprite_c.png", "hero_s_sprite_d.png", "hero_s_icon.png", "hero_s_icon_c.png"):
        open(os.path.join(folder, f), "wb").close()
    _write(os.path.join(content, "maps", "red_canyon", "red_canyon.json"), json.dumps(MAP, indent=2) + "\n")
    build_tree_currencies(content)
    os.makedirs(os.path.join(content, "quests"))
    return content


def build_tree_currencies(content):
    """The registry: the real gold.json (only gold exists), else one like it."""
    gold = os.path.join(REAL_CONTENT, "currencies", "gold", "gold.json")
    text = _read(gold) if os.path.isfile(gold) else json.dumps({"id": "gold", "name": "Gold", "order": 0, "icon": "res://art/ui/wanted/coin.png", "colour": "#C9932F", "word": "gold"}, indent=2) + "\n"
    _write(os.path.join(content, "currencies", "gold", "gold.json"), text)


class Pointed:
    """The server's folders on a temp tree, and its import replaced by a recorder, for the length of a `with`."""

    def __init__(self, server, content):
        self.server, self.content, self.imports = server, content, []

    def __enter__(self):
        s = self.server
        self.saved = (s.CONTENT, s.GODOT, s.BACKUPS, s.LEDGER, s.UPLOADS, s.run_import)
        root = os.path.dirname(self.content)
        s.CONTENT = self.content
        s.GODOT = os.path.join(root, "no-godot.exe")
        s.BACKUPS = os.path.join(root, "backups")
        s.LEDGER = os.path.join(root, "jobs", "created.json")
        s.UPLOADS = os.path.join(root, "uploads")
        s.run_import = lambda target, who="level_editor save": (self.imports.append(target) or (True, "recorded: %s" % target))
        return self

    def __exit__(self, *exc):
        s = self.server
        s.CONTENT, s.GODOT, s.BACKUPS, s.LEDGER, s.UPLOADS, s.run_import = self.saved
        return False


def _hero(content):
    return os.path.join(content, "characters", "hero_s", "hero_s.json")


def _qpath(content, qid):
    return os.path.join(content, "quests", qid, qid + ".json")


def content_checks(check, server):
    tmp = tempfile.mkdtemp(prefix="le_skins111_")
    try:
        content = build_tree(tmp)
        with Pointed(server, content) as pt:
            hpath = _hero(content)
            src0 = _read(hpath)
            # ---- the record before any skin
            hs = {h["id"]: h for h in server.list_heroes()}
            h = hs.get("hero_s") or {}
            looks = {lk["code"]: lk for lk in h.get("looks", [])}
            check(set(looks) == {"HS-A", "HS-B", "HS-C", "HS-D", "HS-E"} and all("skin" in lk and lk["skin"] is None for lk in looks.values())
                  and h.get("skin_quests") == {} and h.get("skins_on_sale") == 0,
                  "SKINS111 the hero record carries every look's skin (none yet), skin_quests {} and 0 on sale: %s" % {k: v.get("skin") for k, v in looks.items()})
            check(looks.get("HS-B", {}).get("default") is True and looks.get("HS-D", {}).get("shelved") is True and looks.get("HS-E", {}).get("ready") is False,
                  "SKINS111 the test hero plays HS-B, HS-D is shelved, HS-E is not painted")

            # ---- refusals write nothing
            cases = [
                ("the played look", "HS-B", {"purchasable": True, "price": 10}, 400),
                ("the played look's goal", "HS-B", {"quest": {"condition": {"type": "runs_total", "count": 3}}}, 400),
                ("a shelved look", "HS-D", {"purchasable": True}, 400),
                ("an unpainted look", "HS-E", {"purchasable": True}, 400),
                ("an unknown currency", "HS-C", {"purchasable": True, "currency_type": "gems"}, 400),
                ("a negative price", "HS-C", {"purchasable": True, "price": -5}, 400),
                ("a broken price", "HS-C", {"purchasable": True, "price": 1.5}, 400),
                ("a text price", "HS-C", {"purchasable": True, "price": "100"}, 400),
                ("purchasable not a bool", "HS-C", {"purchasable": "yes"}, 400),
                ("an unknown condition type", "HS-C", {"purchasable": True, "quest": {"condition": {"type": "dance"}}}, 400),
                ("a stage past the map's", "HS-C", {"purchasable": True, "quest": {"condition": {"type": "beat_stage", "map": "red_canyon", "stage": 4, "hero": "hero_s"}}}, 400),
                ("an unknown map", "HS-C", {"purchasable": True, "quest": {"condition": {"type": "beat_stage", "map": "nowhere", "stage": 1}}}, 400),
                ("an unknown hero in the goal", "HS-C", {"purchasable": True, "quest": {"condition": {"type": "beat_stage", "map": "red_canyon", "stage": 1, "hero": "nobody"}}}, 400),
                ("an unknown look", "HS-Z", {"purchasable": True}, 400),
            ]
            for what, code, body, want in cases:
                r = server.SKINIO.set_skin(server, "hero_s", code, body)
                check(not r.get("ok") and r.get("status") == want and r.get("error"), "SKINS111 refuses %s (%s): %s" % (what, want, r.get("error")))
            r = server.SKINIO.set_skin(server, "nobody", "HS-C", {"purchasable": True})
            check(not r.get("ok") and r.get("status") == 404, "SKINS111 refuses a hero that is not there (404)")
            check(_read(hpath) == src0 and not os.listdir(os.path.join(content, "quests")) and not pt.imports
                  and not (os.path.isdir(server.BACKUPS) and [f for f in os.listdir(server.BACKUPS) if f.startswith("hero_s-")]),
                  "SKINS111 a refusal writes nothing, makes no backup and imports nothing")

            # ---- the first write: skin + goal
            body = {"purchasable": True, "name": "Black Beret", "price": 2000, "currency_type": "gold",
                    "quest": {"condition": {"type": "beat_stage", "map": "red_canyon", "stage": 2, "hero": "hero_s", "count": 5}, "quest_text": ""}}
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", body)
            qid = "skin_hero_s_hs_c"
            src1 = _read(hpath)
            d1 = json.loads(src1)
            sk = (d1.get("variants") or {}).get("HS-C", {}).get("skin")
            check(r.get("ok") and sk == {"purchasable": True, "name": "Black Beret", "price": 2000, "currency_type": "gold", "unlock_quest": qid}
                  and list(sk.keys()) == ["purchasable", "name", "price", "currency_type", "unlock_quest"],
                  "SKINS111 the skin is written into HS-C in the contract's order with its unlock_quest: %s / %s" % (sk, r.get("error")))
            check(list(d1.keys()) == list(HERO.keys()) and list(d1["variants"].keys()) == list(HERO["variants"].keys())
                  and all(d1[k] == HERO[k] for k in HERO if k != "variants")
                  and all(d1["variants"][c] == HERO["variants"][c] for c in HERO["variants"] if c != "HS-C")
                  and {k: v for k, v in d1["variants"]["HS-C"].items() if k != "skin"} == HERO["variants"]["HS-C"]
                  and list(d1["variants"]["HS-C"].keys())[:-1] == list(HERO["variants"]["HS-C"].keys()),
                  "SKINS111 the file's key order, every other key and entry, and HS-C's own keys are untouched (skin last in the entry)")
            check(cio.diff_within_entry(src0, src1, "HS-C") and "\r" not in src1 and src1.endswith("}\n") and '\n  "variants": {\n' in src1,
                  "SKINS111 only HS-C's lines changed, LF, the 2-space layout kept")
            backups = [f for f in os.listdir(server.BACKUPS) if f.startswith("hero_s-")]
            check(len(backups) == 1 and _read(os.path.join(server.BACKUPS, backups[0])) == src0, "SKINS111 a backup of the hero JSON as it was: %s" % backups)
            qp = _qpath(content, qid)
            qd = json.loads(_read(qp)) if os.path.isfile(qp) else {}
            check(qd.get("id") == qid and qd.get("unlocks") == {"type": "skin", "id": "hero_s:HS-C"}
                  and qd.get("condition") == {"type": "beat_stage", "map": "red_canyon", "stage": 2, "hero": "hero_s"}
                  and qd.get("name") == "Hero S · Black Beret" and qd.get("icon") == "res://content/characters/hero_s/hero_s_icon_c.png"
                  and "quest_text" not in qd and list(qd.keys()) == ["id", "name", "condition", "unlocks", "icon"],
                  "SKINS111 the goal quest: unlocks skin hero_s:HS-C, the condition pruned to beat_stage's keys, its name and the look's badge: %s" % qd)
            qsrc = _read(qp) if os.path.isfile(qp) else ""
            check(qsrc.endswith("}\n") and "\r" not in qsrc and '\n  "unlocks": {\n    "type": "skin",' in qsrc, "SKINS111 the quest file is LF, 2-space")
            led = json.loads(_read(server.LEDGER)) if os.path.isfile(server.LEDGER) else {}
            check(qid in (led.get("ids") or {}), "SKINS111 the new quest is in the created-ids ledger")
            check(pt.imports == ["characters/hero_s,quests/%s" % qid] and r.get("wrote") == ["variants.HS-C.skin", "quest %s" % qid]
                  and (r.get("quest") or {}).get("id") == qid and r.get("skin") == sk,
                  "SKINS111 both are imported in one go, the result says what it wrote: %s / %s" % (pt.imports, r.get("wrote")))

            # ---- the record after
            hs = {h["id"]: h for h in server.list_heroes()}
            h = hs["hero_s"]
            lk = {x["code"]: x for x in h["looks"]}
            check(lk["HS-C"]["skin"] == sk and (h.get("skin_quests") or {}).get("HS-C", {}).get("id") == qid
                  and (h["skin_quests"]["HS-C"].get("condition") or {}).get("type") == "beat_stage" and h.get("skins_on_sale") == 1,
                  "SKINS111 /api/heroes: HS-C's skin, its goal's record and 1 on sale")
            rc = server.read_content("hero", "hero_s")
            check(rc.get("ok") and {x["code"]: x for x in rc["looks"]}["HS-C"]["skin"] == sk and rc.get("skin_quests", {}).get("HS-C", {}).get("id") == qid,
                  "SKINS111 /api/content/hero/<id> carries the skins and their goals too")

            # ---- the same values again: nothing written
            pt.imports.clear()
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", body)
            check(r.get("ok") and r.get("unchanged") and _read(hpath) == src1 and _read(qp) == qsrc and not pt.imports,
                  "SKINS111 the same values write nothing: %s" % r.get("wrote"))

            # ---- an edit: the name only (the goal left as it is), then the goal's condition
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", {"name": "Night Beret"})
            d2 = json.loads(_read(hpath))
            check(r.get("ok") and d2["variants"]["HS-C"]["skin"]["name"] == "Night Beret" and d2["variants"]["HS-C"]["skin"]["price"] == 2000
                  and d2["variants"]["HS-C"]["skin"]["unlock_quest"] == qid and _read(qp) == qsrc and pt.imports == ["characters/hero_s"],
                  "SKINS111 a field left out keeps its value; no quest in the body leaves the goal alone: %s" % pt.imports)
            pt.imports.clear()
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", {"quest": {"condition": {"type": "hero_level", "hero": "hero_s", "level": 15}, "quest_text": "Grow up."}})
            qd2 = json.loads(_read(qp))
            check(r.get("ok") and qd2.get("condition") == {"type": "hero_level", "hero": "hero_s", "level": 15} and qd2.get("quest_text") == "Grow up."
                  and qd2.get("name") == "Hero S · Night Beret" and qd2.get("unlocks") == {"type": "skin", "id": "hero_s:HS-C"}
                  and pt.imports == ["quests/%s" % qid] and len([f for f in os.listdir(server.BACKUPS) if f.startswith(qid + "-")]) == 1,
                  "SKINS111 a goal edit rewrites the quest in place (condition, words, name), a backup first, only the quest imported: %s" % pt.imports)
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", {"quest": {"condition": {"type": "hero_level", "hero": "hero_s", "level": 15}, "quest_text": ""}})
            check(r.get("ok") and "quest_text" not in json.loads(_read(qp)), "SKINS111 empty words take quest_text out (the game writes its own)")

            # ---- off sale keeps the name, price and goal
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", {"purchasable": False})
            d3 = json.loads(_read(hpath))
            check(r.get("ok") and d3["variants"]["HS-C"]["skin"]["purchasable"] is False and d3["variants"]["HS-C"]["skin"]["name"] == "Night Beret"
                  and os.path.isfile(qp), "SKINS111 Purchasable off keeps the rest (and the goal)")
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", {"purchasable": True})

            # ---- remove the goal
            pt.imports.clear()
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", {"quest": None})
            d4 = json.loads(_read(hpath))
            moved = os.path.join(server.BACKUPS, "deleted", qid)
            stamps = os.listdir(moved) if os.path.isdir(moved) else []
            led = json.loads(_read(server.LEDGER))
            check(r.get("ok") and not os.path.exists(os.path.dirname(qp)) and len(stamps) == 1
                  and os.path.isfile(os.path.join(moved, stamps[0], qid, qid + ".json")) and d4["variants"]["HS-C"]["skin"]["unlock_quest"] == ""
                  and qid not in led.get("ids", {}) and r.get("moved_to") and pt.imports == ["characters/hero_s"],
                  "SKINS111 Remove goal moves the quest folder to backups/deleted, clears unlock_quest, leaves the ledger: %s" % r.get("wrote"))
            hs = {h["id"]: h for h in server.list_heroes()}
            check(hs["hero_s"].get("skin_quests") == {} and hs["hero_s"].get("skins_on_sale") == 1, "SKINS111 no goal in the record, still on sale")

            # ---- a look that was never offered: an empty write records nothing
            r = server.SKINIO.set_skin(server, "hero_s", "HS-A", {})
            check(r.get("ok") and r.get("unchanged") and "skin" not in json.loads(_read(hpath))["variants"]["HS-A"], "SKINS111 an empty write on a look never offered records nothing")
            # the played look may be tidied (purchasable false is allowed, true never)
            r = server.SKINIO.set_skin(server, "hero_s", "HS-B", {"purchasable": False, "name": "x"})
            check(r.get("ok"), "SKINS111 the played look can still be written off sale: %s" % r.get("error"))

            # ---- a quest id taken by something else
            os.makedirs(os.path.join(content, "quests", "skin_hero_s_hs_a"))
            _write(_qpath(content, "skin_hero_s_hs_a"), json.dumps({"id": "skin_hero_s_hs_a", "name": "x", "condition": {"type": "runs_total", "count": 1}, "unlocks": {"type": "weapon", "id": "x"}}, indent=2) + "\n")
            r = server.SKINIO.set_skin(server, "hero_s", "HS-A", {"purchasable": True, "quest": {"condition": {"type": "runs_total", "count": 3}}})
            check(not r.get("ok") and r.get("status") == 409, "SKINS111 a goal id already taken by another quest is a 409: %s" % r.get("error"))

            # ---- currencies
            cur = server.SKINIO.currencies(server)
            check([c["id"] for c in cur] == ["gold"] and cur[0].get("icon_url") == "/api/currencies/gold/icon" and cur[0].get("name") == "Gold"
                  and cur[0].get("icon") == "res://art/ui/wanted/coin.png", "SKINS111 the registry lists gold with its icon: %s" % cur)
            ic = server.SKINIO.currency_icon_file(server, "gold")
            check(ic and os.path.isfile(ic) and ic.replace("\\", "/").endswith("game/art/ui/wanted/coin.png"), "SKINS111 gold's icon is served from game/art/ui/wanted/coin.png: %s" % ic)
            check(server.SKINIO.currency_icon_file(server, "gems") is None, "SKINS111 no icon for a currency not in the registry")
            t = vocab.table(server.CONTENT, server.GAME, set())
            check(t["currencies"] == ["gold"] and [r["id"] for r in t["currency_records"]] == ["gold"] and t.get("maps") == ["red_canyon"],
                  "SKINS111 /api/vocab: currencies from the registry, their records, the maps")
            # the hero availability op: gems refused today, accepted the day a gems folder exists
            r = server.set_availability("hero", "hero_s", {"availability": "purchase", "currency_type": "gems"})
            check(r.get("status") == 400, "SKINS111 availability refuses a currency not in the registry (gems)")
            _write(os.path.join(content, "currencies", "gems", "gems.json"), json.dumps({"id": "gems", "name": "Gems", "order": 1, "icon": "res://art/ui/wanted/coin.png"}, indent=2) + "\n")
            check(vocab.currency_ids(content) == ["gold", "gems"], "SKINS111 the registry sorts by order, then id")
            r = server.set_availability("hero", "hero_s", {"availability": "purchase", "currency_type": "gems"})
            check(r.get("ok") and json.loads(_read(hpath)).get("currency_type") == "gems", "SKINS111 a currency in the registry is accepted (gems once its folder exists): %s" % r.get("error"))
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", {"currency_type": "gems"})
            check(r.get("ok") and json.loads(_read(hpath))["variants"]["HS-C"]["skin"]["currency_type"] == "gems", "SKINS111 a skin takes any registry currency")
            shutil.rmtree(os.path.join(content, "currencies"))
            check(vocab.currency_ids(content) == ["gold"] and vocab.currency_records(content)[0].get("fallback") is True,
                  "SKINS111 no currencies folder: gold stands in (the game's default)")

            # ---- over HTTP
            build_tree_currencies(content)
            r = server.SKINIO.set_skin(server, "hero_s", "HS-C", {"name": "Gone"})
            check(r.get("status") == 400 and "gems" not in vocab.currency_ids(content), "SKINS111 a skin whose currency left the registry saves only with a currency of the registry")
            _http_checks(check, server, content)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _http_checks(check, server, content):
    keep = server.Handler.log_message
    server.Handler.log_message = lambda self, fmt, *args: None   # the server's log lines
    httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    th = threading.Thread(target=httpd.serve_forever, daemon=True)
    th.start()
    base = "http://127.0.0.1:%d" % httpd.server_address[1]

    def call(url, body=None):
        req = urllib.request.Request(base + url, data=None if body is None else json.dumps(body).encode("utf-8"),
                                     method="GET" if body is None else "POST", headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
                return r.status, (json.loads(data.decode("utf-8")) if r.headers.get("Content-Type", "").startswith("application/json") else data), r.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            data = e.read()
            try:
                return e.code, json.loads(data.decode("utf-8")), ""
            except ValueError:
                return e.code, data, ""
    try:
        st, body, _ = call("/api/currencies")
        check(st == 200 and isinstance(body, list) and body and body[0]["id"] == "gold" and body[0]["icon_url"] == "/api/currencies/gold/icon",
              "SKINS111 GET /api/currencies: %s" % body)
        st, body, ct = call("/api/currencies/gold/icon")
        check(st == 200 and ct.startswith("image/png") and isinstance(body, bytes) and body[:4] == b"\x89PNG", "SKINS111 GET /api/currencies/gold/icon is the PNG")
        st, body, _ = call("/api/currencies/nothing/icon")
        check(st == 404, "SKINS111 an unknown currency's icon is a 404")
        st, body, _ = call("/api/content/hero/hero_s/skin/HS-C", {"purchasable": True, "name": "Dust Devil", "price": 300, "currency_type": "gold"})
        check(st == 200 and body.get("ok") and body["skin"]["name"] == "Dust Devil" and body["skin"]["price"] == 300, "SKINS111 POST the skin route: %s" % body)
        st, body, _ = call("/api/content/hero/hero_s/skin/HS-B", {"purchasable": True})
        check(st == 400 and not body.get("ok") and "played" in str(body.get("error")), "SKINS111 POST refuses the played look with a 400: %s" % body)
        st, body, _ = call("/api/content/weapon/revolver/skin/A", {"purchasable": True})
        check(st in (400, 404) and not body.get("ok"), "SKINS111 the skin route is for heroes only")
        st, body, _ = call("/api/heroes")
        h = {x["id"]: x for x in body}.get("hero_s", {})
        check(st == 200 and {x["code"]: x for x in h.get("looks", [])}.get("HS-C", {}).get("skin", {}).get("name") == "Dust Devil", "SKINS111 GET /api/heroes shows the new skin")
    finally:
        server.Handler.log_message = keep
        httpd.shutdown()
        httpd.server_close()


# ---------------------------------------------------------------- the page side (Node) and the real content (read only)

RUNNER = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = M;
const F = require(path.join(dir, 'assets_fields.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const stages = ['Sundown', 'Nightfall', 'Blood Moon'];
  const nm = { hero: (id) => (id === 'may' ? 'May' : ''), stage: (m, k) => stages[k - 1] || '' };
  const out = {};
  out.named = M.questText({ condition: { type: 'beat_stage', map: 'red_canyon', stage: 2, hero: 'may' } }, nm);
  out.any = M.questText({ condition: { type: 'beat_stage', map: 'red_canyon', stage: 3, hero: '' } }, nm);
  out.bare = M.questText({ condition: { type: 'beat_stage', map: 'red_canyon', stage: 2, hero: 'may' } });
  out.custom = M.questText({ quest_text: 'Do it.', condition: { type: 'beat_stage', stage: 1 } }, nm);
  out.types = F.VOCAB.questTypes.map((o) => o.v);
  out.shown = F.QUEST_ROWS.filter((r) => typeof r.only !== 'function' || r.only({ condition: { type: 'beat_stage' } })).map((r) => r.key);
  out.mapRow = F.QUEST_ROWS.find((r) => r.key === 'condition.map');
  out.mapOpts = F.options(out.mapRow, F.VOCAB).map((o) => o.v);
  out.currencies = F.VOCAB.currencies;
  const rule = F.RULES && F.RULES.hero ? F.RULES.hero : null;
  out.ruleFound = !!rule;
  process.stdout.write(JSON.stringify(out));
});
"""


def page_checks(check, run_node):
    r = run_node({}, RUNNER) if run_node else None
    if not r:
        check(False, "SKINS111 assets_model.js / assets_fields.js ran under node")
        return
    check(r.get("named") == "Beat Nightfall with May." and r.get("any") == "Beat Blood Moon." and r.get("bare") == "Beat stage 2 with May."
          and r.get("custom") == "Do it.", "SKINS111 beat_stage's words: %s / %s / %s" % (r.get("named"), r.get("any"), r.get("bare")))
    check("beat_stage" in (r.get("types") or []), "SKINS111 the Condition list offers beat_stage")
    check(set(r.get("shown") or []) == {"name", "condition.type", "condition.map", "condition.stage", "condition.hero", "quest_text"},
          "SKINS111 the beat_stage form shows its map, stage and hero: %s" % r.get("shown"))
    check((r.get("mapRow") or {}).get("type") == "select" and r.get("mapOpts") == ["red_canyon"], "SKINS111 the map is a select over the maps")
    check([o.get("v") for o in (r.get("currencies") or [])] == ["gold"], "SKINS111 the page's built-in currency list is only gold, the stand-in until the registry is read")
    check(vocab.QUEST_TYPES.get("beat_stage") == ["map", "stage", "hero"] and "skin" in vocab.UNLOCK_TYPES, "SKINS111 vocab: beat_stage {map, stage, hero}, unlocks type skin")
    probs = [p for p in vocab.check_against_source(os.path.join(ROOT, "game")) if p.startswith("quest types")]
    check(not probs, "SKINS111 QuestTracker plays beat_stage (vocab's quest types match the game's): %s" % probs)

    def src(name):
        with open(os.path.join(HERE, name), encoding="utf-8") as f:
            return f.read()
    html = src("index.html")
    check('<script src="skins.js"></script>' in html and 'href="skins.css"' in html, "SKINS111 index.html loads skins.js and skins.css")
    check("Skins.section(doc)" in src("heroes.js") and "Skins.cardLine(h)" in src("heroes.js"), "SKINS111 the Heroes tab draws the Skins section and the card's line")
    check("Skins.instructions(root)" in src("instructions.js"), "SKINS111 the Instructions tab has the Pass 111 section")
    sj = src("skins.js")
    check("/api/content/hero/${encodeURIComponent(doc.id)}/skin/" in sj and "F.QUEST_ROWS" in sj and "LookGrid.playerOpts" in sj and "/api/currencies" in sj,
          "SKINS111 skins.js posts the skin route, reuses the quest rows, the strip player and the currency registry")
    check("stage: (mapId, k)" in src("typed_forms.js"), "SKINS111 the goal's words name the stage from the map (TypedForms.questWords)")
    check("if (Array.isArray(sv.currency_records) && sv.currency_records.length) v.currencies = sv.currency_records.map(" in src("assets.js"),
          "SKINS111 the page's currency list is the registry's records once the vocab is read (Assets.vocab)")


def real_checks(check, server):
    """The real content, read only: every hero record carries the skins and the goals."""
    try:
        hs = server.list_heroes()
    except Exception as e:  # noqa: BLE001
        check(False, "SKINS111 list_heroes on the real content: %s" % e)
        return
    check(hs and all(isinstance(h.get("skin_quests"), dict) and isinstance(h.get("skins_on_sale"), int) and all("skin" in lk for lk in h.get("looks", [])) for h in hs),
          "SKINS111 every real hero record has skin_quests, skins_on_sale and each look's skin")
    check(vocab.currency_ids(REAL_CONTENT)[:1] == ["gold"], "SKINS111 the real registry starts with gold")


def checks(check, run_node, server):
    content_checks(check, server)
    page_checks(check, run_node)
    real_checks(check, server)


if __name__ == "__main__":
    import selftest as _st
    import server as _server
    checks(_st.check, _st.run_node, _server)
    print("SKINS111: %d checks passed, %d failed" % (_st.PASSES[0], len(_st.FAILS)))
    sys.exit(1 if _st.FAILS else 0)
