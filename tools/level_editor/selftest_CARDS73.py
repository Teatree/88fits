"""Pass 73, lane CARDS: the line items became fortune cards with looks (A the old icon, B-E the four card framings), and
the Items tab picks them: a card's looks in its editor, "Play this look" (write_variant_kind for a passive), "Set every
card to look X" (set_item_looks_all, POST /api/item_looks/set_all), a candidate installed into a card's look
(set_look_files for a passive), the records the page reads (item_look_state in /api/items, item_looks in a document).
selftest.py discovers this file (`extra_checks`) and hands it its `check` counter. Everything that writes works on a
temporary copy (no Godot: the import is reported as not run).

  server   item_playable_codes / item_looks / item_look_state; write_variant_kind on a passive (one line, the import
           named, an unpainted look refused); set_item_looks_all (every card that can play the look, the rest kept,
           line endings kept); set_look_files takes a card's icon and refuses a title;
  page     items.js says Cards (the filter, the heading, the create dialog), draws the looks bar and a card's looks;
           assets_fields.js names the flag Card (line item);
  content  every line card that has looks has A (the base) and its framings among B-E, their icons on disk, and plays a
           look it has (all four B-E once painted: game/tests/pass73_cards_test.gd pins that).
"""
import json
import os
import re
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CONTENT = os.path.join(ROOT, "game", "content")


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _card(folder, cid, looks, play="B", crlf=False, line=True):
    os.makedirs(folder, exist_ok=True)
    d = {"id": cid, "name": "The Test", "flavour": "The card says hi.", "rarity": "common", "weight": 10.0, "line": line,
         "max_level": 4, "levels": [[{"stat": "might", "op": "mul", "value": 0.1, "target": "player"}]],
         "art_prompt": "a test", "variant_base": "A", "variant": play,
         "variants": {"A": {"note": "the old icon"}}}
    open(os.path.join(folder, cid + "_icon.png"), "wb").close()
    for code in looks:
        name = "%s_icon_%s.png" % (cid, code.lower())
        d["variants"][code] = {"icon": name, "note": code}
        if not code.startswith("X"):
            open(os.path.join(folder, name), "wb").close()
    text = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
    if crlf:
        text = text.replace("\n", "\r\n")
    path = os.path.join(folder, cid + ".json")
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))
    return path, text


def server_checks(check, server):
    tmp = tempfile.mkdtemp(prefix="le_cards73_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        p1, t1 = _card(os.path.join(server.CONTENT, "passives", "card_one"), "card_one", ["B", "C", "XE"])
        p2, t2 = _card(os.path.join(server.CONTENT, "passives", "card_two"), "card_two", ["B"], crlf=True)
        p3, t3 = _card(os.path.join(server.CONTENT, "passives", "item_three"), "item_three", ["C"], play="A", line=False)
        d1 = json.loads(t1)
        f1 = os.path.dirname(p1)
        check(server.item_playable_codes(f1, d1) == {"A", "B", "C"},
              "CARDS73 server: a card plays A (the top-level icon) and the looks whose icon is on disk: %s" % server.item_playable_codes(f1, d1))
        looks = server.item_looks("passive", "card_one", f1, d1)
        check([x["code"] for x in looks] == ["A", "B", "C", "XE"] and looks[0]["base"] and looks[0]["icon_file"] == "card_one_icon.png",
              "CARDS73 server: item_looks lists the base first, then the codes: %s" % [x["code"] for x in looks])
        check([x["code"] for x in looks if x["default"]] == ["B"] and not looks[3]["exists"],
              "CARDS73 server: the played look is B, XE is not painted: %s" % looks)
        st = server.item_look_state("passive", "card_one", f1, d1)
        check(st["play"] == "B" and st["icon_play"] == "/icon/passive/card_one/B", "CARDS73 server: item_look_state's play and icon: %s" % st)
        # Play this look
        res = server.write_variant_kind("passive", "card_one", "C")
        after = open(p1, "rb").read().decode("utf-8")
        changed = [(a, b) for a, b in zip(t1.splitlines(True), after.splitlines(True)) if a != b]
        check(res.get("ok") and not res.get("import_ok") and len(changed) == 1 and '"C"' in changed[0][1],
              "CARDS73 server: write_variant_kind on a card writes its variant line only: %s %s" % (res.get("error"), changed))
        check(not server.write_variant_kind("passive", "card_one", "XE").get("ok"), "CARDS73 server: an unpainted look is refused")
        check("icon is not painted" in str(server.write_variant_kind("passive", "card_one", "XE").get("error")),
              "CARDS73 server: the refusal says the icon is not painted")
        check(not server.write_variant_kind("passive", "card_one", "ZZ").get("ok"), "CARDS73 server: an unknown look is refused")
        # Set every card to look B: card_one changes, card_two already plays it, item_three is not a card
        res = server.set_item_looks_all("passive", "B")
        check(res.get("ok") and res["changed"] == ["card_one"] and res["kept"] == ["card_two"] and not any(s["id"] == "item_three" for s in res["skipped"]),
              "CARDS73 server: set_item_looks_all changes the cards that can play it, keeps the ones that do, leaves items: %s" % res)
        res = server.set_item_looks_all("passive", "C")
        check(res["changed"] == ["card_one"] and [s["id"] for s in res["skipped"]] == ["card_two"],
              "CARDS73 server: a card without the look keeps its own and is named: %s" % res)
        raw2 = open(p2, "rb").read().decode("utf-8")
        check(raw2 == t2, "CARDS73 server: the skipped CRLF card is untouched")
        server.write_variant_kind("passive", "card_two", "A")
        raw2 = open(p2, "rb").read().decode("utf-8")
        check(raw2.count("\r\n") == t2.count("\r\n") and json.loads(raw2)["variant"] == "A",
              "CARDS73 server: a CRLF card keeps its line endings")
        check(not server.set_item_looks_all("enemy", "B").get("ok") and not server.set_item_looks_all("passive", "../x").get("ok"),
              "CARDS73 server: set_item_looks_all refuses another kind and a bad code")
        ids = server.set_item_looks_all("passive", "B", ids=["card_two"])
        check(ids["changed"] == ["card_two"], "CARDS73 server: set_item_looks_all with ids touches those only: %s" % ids)
        # a candidate installed into a card's look (the job's hook)
        hooks = server.HOOKS
        r = hooks.set_look_files("passive", "card_one", "C", {"icon": "card_one_icon_c.png"})
        check(r.get("ok"), "CARDS73 server: set_look_files takes a card look's icon: %s" % r)
        check(json.loads(open(p1, encoding="utf-8").read())["variants"]["C"].get("icon_picked") is True,
              "CARDS73 server: the picked icon is marked icon_picked")
        r = hooks.set_look_files("passive", "card_one", "C", {"title": "hero_x.png"})
        check(not r.get("ok"), "CARDS73 server: a card has no title cut-out")
        rec = server.read_content("passive", "card_one")
        check(rec.get("ok") and [x["code"] for x in rec["looks"]][:3] == ["A", "B", "C"],
              "CARDS73 server: a card's document carries its looks: %s" % rec.get("looks"))
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def page_checks(check):
    items = _read(os.path.join(HERE, "items.js"))
    check("['lines', 'cards']" in items and "`Cards · ${ls.length}`" in items and "`Lines · " not in items,
          "CARDS73 page: the Items tab says Cards (the filter chip, the heading)")
    check("function cardLooksBar(fl)" in items and "'/api/item_looks/set_all'" in items and "Set every card to look" in items,
          "CARDS73 page: the cards' list has the Set every card to look bar")
    check("function itemLooks(doc)" in items and "Play this look" in items and "/variant`" in items,
          "CARDS73 page: a card's editor shows its looks with Play this look")
    fields = _read(os.path.join(HERE, "assets_fields.js"))
    check("{ key: 'line', label: 'Card (line item)'" in fields, "CARDS73 page: the passive form's flag is Card (line item)")
    css = _read(os.path.join(HERE, "style.css"))
    check(".ilooks-grid" in css and ".cardlooks" in css, "CARDS73 page: the looks' styles are there")


def content_checks(check):
    folder = os.path.join(CONTENT, "passives")
    bad = []
    n = 0
    for cid in sorted(os.listdir(folder)):
        jp = os.path.join(folder, cid, cid + ".json")
        if not os.path.isfile(jp):
            continue
        d = json.loads(_read(jp))
        if not d.get("line") or not isinstance(d.get("variants"), dict):
            continue
        n += 1
        vs = d["variants"]
        # A (the old icon, the base) and any of the four framings B-E (all four once painted: pass73_cards_test pins it)
        if "A" not in vs or not set(vs) <= {"A", "B", "C", "D", "E"} or d.get("variant_base") != "A":
            bad.append("%s: looks %s base %s" % (cid, sorted(vs), d.get("variant_base")))
            continue
        for code in [c for c in "BCDE" if c in vs]:
            f = str(vs[code].get("icon", ""))
            if f != "%s_icon_%s.png" % (cid, code.lower()) or not os.path.isfile(os.path.join(folder, cid, f)):
                bad.append("%s %s: %s" % (cid, code, f))
        if d.get("variant") not in vs:
            bad.append("%s plays %s" % (cid, d.get("variant")))
    check(not bad, "CARDS73 content: %d line cards with looks, each A-E with its icons, playing one it has: %s" % (n, bad[:6]))


def checks(check, run_node, server):
    server_checks(check, server)
    page_checks(check)
    content_checks(check)
