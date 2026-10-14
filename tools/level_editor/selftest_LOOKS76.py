"""Pass 76, lane LOOKS: a weapon family's looks in the Level Editor (game/core/data/ItemLooks.gd is the game's side).
A weapon, an evolution or a mutation carries `variants` + `variant_base` ("A" when it names none); the WEAPON's
`variant` is the look its whole family plays; every member wears its entry for that code or its base. selftest.py
discovers this file (`extra_checks`) and hands it its `check` counter. Everything that writes works on a temporary copy
(no Godot: the import is reported as not run).

  server   family_base_code / family_playable_codes (an entry plays when every file it names is on disk, an entry naming
           none plays) / item_playable_codes by kind; item_looks for a family kind (names, own, the base first, the
           default the weapon's variant); family_weapon_id (an evolution, a mutation, a mutation of the evolution);
           family_member_play; list_items: the weapon's family_looks (per code its members, own or base) and the members'
           play / icon_play / name_play following the weapon; write_variant_kind on a weapon (one line, CRLF kept, an
           unplayable look refused) and refused on an evolution and a mutation (they wear the weapon's look);
           read_content of a member (its looks' default follows the weapon); icon_path falls back to the top icon;
           set_item_looks_all stays the cards'.
  page     items.js: familyLooks in the weapon, evolution and mutation editors (Art), Play this look on the weapon's
           variant route, the played name on the cards.
  content  every weapon with looks plays one it can play (its files on disk), no evolution or mutation names a
           `variant` of its own (the family plays its weapon's), every look code is a plain code.
"""
import json
import os
import re
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CONTENT = os.path.join(ROOT, "game", "content")
CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _touch(folder, name):
    open(os.path.join(folder, name), "wb").close()


def _write(folder, cid, d, crlf=False):
    os.makedirs(folder, exist_ok=True)
    text = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
    if crlf:
        text = text.replace("\n", "\r\n")
    path = os.path.join(folder, cid + ".json")
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))
    return path, text


def _family(content, crlf=False):
    """A test family: w76_gun (looks A-E, plays B), its evolution w76_gun_evo (a B of its own), w76_mut_a (a B of its
    own), w76_mut_b (no looks) and w76_mut_e (a mutation of the evolution)."""
    wf = os.path.join(content, "weapons", "w76_gun")
    os.makedirs(wf, exist_ok=True)
    for n in ("w76_gun_icon.png", "w76_gun_icon_b.png", "w76_gun_d_visual.tscn"):
        _touch(wf, n)
    wd = {"id": "w76_gun", "name": "Test Grenade", "flavour": "Plain.", "rarity": "rare", "behavior": "Lobber",
          "base": {"damage": 25, "area": 2.5}, "max_level": 5, "levels": [[]], "evolves_into": "w76_gun_evo",
          "params": {"model": "res://art/props/golden_grenade.glb"},
          "variant": "B",
          "variants": {"A": {"note": "the grenade"},
                       "B": {"name": "Test Stick", "icon": "w76_gun_icon_b.png", "nouns": "sticks", "params": {"model_form": "stick"}},
                       "C": {"name": "Lost Look", "icon": "w76_gun_icon_c.png"},
                       "D": {"name": "Visual Look", "visual": "w76_gun_d_visual.tscn", "shelved": True},
                       "E": {"name": "Words Look", "fresh": True}}}
    wpath, wtext = _write(wf, "w76_gun", wd, crlf)
    ef = os.path.join(content, "evolutions", "w76_gun_evo")
    os.makedirs(ef, exist_ok=True)
    _touch(ef, "w76_gun_evo_icon.png")
    _touch(ef, "w76_gun_evo_icon_b.png")
    _write(ef, "w76_gun_evo", {"id": "w76_gun_evo", "name": "Test Pineapple", "is_evolution": True, "evolved_from": "w76_gun",
                               "behavior": "Lobber", "max_level": 1, "levels": [[]],
                               "variants": {"B": {"name": "Test Boomtown", "icon": "w76_gun_evo_icon_b.png"}}})
    for mid, kind, weapon, looks in (("w76_mut_a", "volume", "w76_gun", {"B": {"name": "Coffin Test", "text": "Nails.", "icon": "w76_mut_a_icon_b.png"}}),
                                     ("w76_mut_b", "motion", "w76_gun", None),
                                     ("w76_mut_e", "element", "w76_gun_evo", None)):
        mf = os.path.join(content, "mutations", mid)
        os.makedirs(mf, exist_ok=True)
        _touch(mf, mid + "_icon.png")
        md = {"id": mid, "name": "Mut " + mid, "weapon": weapon, "kind": kind, "hero": "", "text": "Base text.",
              "effects": [], "params": {"burst_spawn": {"count": 6}}}
        if looks:
            _touch(mf, mid + "_icon_b.png")
            md["variants"] = looks
        _write(mf, mid, md)
    return wpath, wtext


def server_checks(check, server):
    tmp = tempfile.mkdtemp(prefix="le_looks76_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        wpath, wtext = _family(server.CONTENT)
        wd = json.loads(wtext)
        wf = os.path.dirname(wpath)
        check("weapon" in server.ITEM_LOOK_KINDS and "evolution" in server.ITEM_LOOK_KINDS and "mutation" in server.ITEM_LOOK_KINDS,
              "LOOKS76 server: ITEM_LOOK_KINDS has the weapon family's kinds: %s" % (server.ITEM_LOOK_KINDS,))
        check(server.family_base_code(wd) == "A" and server.family_base_code({"id": "x"}) == "",
              "LOOKS76 server: a family's base is A when it names none, none without looks")
        check(server.family_playable_codes(wf, wd) == {"A", "B", "D", "E"},
              "LOOKS76 server: a look plays when its named files are on disk (C's icon is not), one naming none plays: %s" % sorted(server.family_playable_codes(wf, wd)))
        check(server.item_playable_codes(wf, wd, "weapon") == {"A", "B", "D", "E"} and server.item_playable_codes(wf, wd) == {"B"} | (set() if not wd.get("variant_base") else {"A"}),
              "LOOKS76 server: item_playable_codes answers by kind (a card's rule stays icons only)")
        looks = server.item_looks("weapon", "w76_gun", wf, wd)
        check([x["code"] for x in looks] == ["A", "B", "C", "D", "E"] and looks[0]["base"] and [x["code"] for x in looks if x["default"]] == ["B"],
              "LOOKS76 server: a weapon's looks, the base first, B played: %s" % [(x["code"], x["default"]) for x in looks])
        check(looks[1]["name"] == "Test Stick" and looks[0]["name"] == "Test Grenade" and looks[1]["own"] and not looks[2]["exists"]
              and looks[3]["shelved"] and looks[4]["fresh"] and looks[4]["icon_file"] == "w76_gun_icon.png",
              "LOOKS76 server: each look's name (else the item's), own, exists, shelved, fresh, icon file (else the top icon): %s" % looks)
        st = server.item_look_state("weapon", "w76_gun", wf, wd)
        check(st["play"] == "B" and st["name_play"] == "Test Stick" and st["icon_play"] == "/icon/weapon/w76_gun/B",
              "LOOKS76 server: item_look_state's play, name_play, icon_play: %s" % {k: st[k] for k in ("play", "name_play", "icon_play")})
        # the family
        ed = json.loads(_read(os.path.join(server.CONTENT, "evolutions", "w76_gun_evo", "w76_gun_evo.json")))
        mad = json.loads(_read(os.path.join(server.CONTENT, "mutations", "w76_mut_a", "w76_mut_a.json")))
        med = json.loads(_read(os.path.join(server.CONTENT, "mutations", "w76_mut_e", "w76_mut_e.json")))
        check(server.family_weapon_id("evolution", "w76_gun_evo", ed) == "w76_gun" and server.family_weapon_id("mutation", "w76_mut_a", mad) == "w76_gun"
              and server.family_weapon_id("mutation", "w76_mut_e", med) == "w76_gun" and server.family_weapon_id("weapon", "w76_gun", wd) == "w76_gun",
              "LOOKS76 server: family_weapon_id finds the weapon of an evolution, a mutation and a mutation of the evolution")
        check(server.family_member_play("mutation", "w76_mut_a", mad) == "B" and server.family_member_play("weapon", "w76_gun", wd) is None,
              "LOOKS76 server: a member wears its weapon's played look")
        items = server.list_items()
        w = next((x for x in items["weapons"] if x["id"] == "w76_gun"), None)
        check(w is not None and [x["code"] for x in w.get("family_looks", [])] == ["A", "B", "C", "D", "E"],
              "LOOKS76 server: the weapon's record carries the family's looks: %s" % (w or {}).get("family_looks"))
        if w:
            fb = next(x for x in w["family_looks"] if x["code"] == "B")
            mem = {m["id"]: m for m in fb["members"]}
            check(set(mem) == {"w76_gun_evo", "w76_mut_a", "w76_mut_b"} and mem["w76_gun_evo"]["own"] and mem["w76_mut_a"]["own"]
                  and not mem["w76_mut_b"]["own"] and mem["w76_mut_a"]["icon"] == "/icon/mutation/w76_mut_a/B"
                  and mem["w76_mut_b"]["icon"] == "/icon/mutation/w76_mut_b" and mem["w76_mut_a"]["name"] == "Coffin Test"
                  and mem["w76_mut_a"]["role"] == "volume",
                  "LOOKS76 server: a look's members, each with its own icon and name or its base's: %s" % fb["members"])
            check(fb["default"] and fb["name"] == "Test Stick" and w["name_play"] == "Test Stick" and w["play"] == "B",
                  "LOOKS76 server: the weapon plays B and goes by its name")
            evo = w.get("evolution") or {}
            muts = {m["id"]: m for m in w.get("mutations", [])}
            check(evo.get("play") == "B" and evo.get("name_play") == "Test Boomtown" and evo.get("family") == "w76_gun"
                  and muts["w76_mut_a"]["play"] == "B" and muts["w76_mut_a"]["icon_play"] == "/icon/mutation/w76_mut_a/B"
                  and muts["w76_mut_b"]["play"] == "" and muts["w76_mut_b"]["icon_play"] == "/icon/mutation/w76_mut_b"
                  and muts["w76_mut_b"]["name_play"] == "Mut w76_mut_b",
                  "LOOKS76 server: the members' records follow the weapon's look (a member without looks keeps its own): %s"
                  % [(m["id"], m.get("play"), m.get("icon_play")) for m in [evo] + list(muts.values())])
        # Play this look: the weapon's variant, one line
        res = server.write_variant_kind("weapon", "w76_gun", "E")
        after = _read(wpath)
        changed = [(a, b) for a, b in zip(wtext.splitlines(True), after.splitlines(True)) if a != b]
        check(res.get("ok") and not res.get("import_ok") and len(changed) == 1 and '"E"' in changed[0][1],
              "LOOKS76 server: Play this look writes the weapon's variant line only: %s %s" % (res.get("error"), changed))
        bad = server.write_variant_kind("weapon", "w76_gun", "C")
        check(not bad.get("ok") and "not on disk" in str(bad.get("error")),
              "LOOKS76 server: a look whose files are missing is refused, and says so: %s" % bad.get("error"))
        check(not server.write_variant_kind("weapon", "w76_gun", "Z").get("ok"), "LOOKS76 server: an unknown look is refused")
        for kind, cid in (("evolution", "w76_gun_evo"), ("mutation", "w76_mut_a")):
            r = server.write_variant_kind(kind, cid, "B")
            check(not r.get("ok") and "w76_gun" in str(r.get("error")),
                  "LOOKS76 server: a %s's look is played on its weapon: %s" % (kind, r.get("error")))
        # a member's document: its looks' default follows the weapon (now E, which mut_a lacks: its base)
        doc = server.read_content("mutation", "w76_mut_a")
        check(doc.get("ok") and [x["code"] for x in doc["looks"] if x["default"]] == ["A"],
              "LOOKS76 server: a member's document marks the look it wears (its base: no E of its own): %s" % doc.get("looks"))
        server.write_variant_kind("weapon", "w76_gun", "B")
        doc = server.read_content("mutation", "w76_mut_a")
        check([x["code"] for x in doc["looks"] if x["default"]] == ["B"], "LOOKS76 server: and B once the weapon plays B")
        doc = server.read_content("weapon", "w76_gun")
        check(doc.get("ok") and [x["code"] for x in doc["looks"]] == ["A", "B", "C", "D", "E"], "LOOKS76 server: a weapon's document carries its looks")
        # the icons the page draws: a look without its own (or with its file missing) shows the top icon
        top = os.path.join(wf, "w76_gun_icon.png")
        check(server.icon_path("weapon", "w76_gun", "C") == top and server.icon_path("weapon", "w76_gun", "E") == top
              and server.icon_path("weapon", "w76_gun", "B") == os.path.join(wf, "w76_gun_icon_b.png")
              and server.icon_path("mutation", "w76_mut_b", "B") == os.path.join(server.CONTENT, "mutations", "w76_mut_b", "w76_mut_b_icon.png"),
              "LOOKS76 server: icon_path falls back to the top icon")
        check(not server.set_item_looks_all("weapon", "B").get("ok"), "LOOKS76 server: Set every card to look X stays the cards'")
        # a CRLF weapon keeps its line endings
        shutil.rmtree(os.path.join(server.CONTENT, "weapons", "w76_gun"))
        wpath, wtext = _family(server.CONTENT, crlf=True)
        server.write_variant_kind("weapon", "w76_gun", "D")
        raw = open(wpath, "rb").read().decode("utf-8")
        check(raw.count("\r\n") == wtext.count("\r\n") and json.loads(raw)["variant"] == "D",
              "LOOKS76 server: a CRLF weapon keeps its line endings")
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def page_checks(check):
    items = _read(os.path.join(HERE, "items.js"))
    check("function familyLooks(doc)" in items and "kind === 'weapon' || kind === 'evolution' || kind === 'mutation'" in items,
          "LOOKS76 page: the weapon, evolution and mutation editors show the family's looks (Art)")
    check("async function playFamilyLook(doc, code)" in items and "/api/content/weapon/${encodeURIComponent(doc.id)}/variant" in items
          and "Play this look" in items and "family_looks" in items,
          "LOOKS76 page: Play this look writes the weapon's variant")
    check("x.name_play || x.name || x.id" in items, "LOOKS76 page: the cards show the name a family member plays under")


def content_checks(check):
    bad = []
    n = 0
    for kind, sub in (("weapon", "weapons"), ("evolution", "evolutions"), ("mutation", "mutations")):
        folder = os.path.join(CONTENT, sub)
        if not os.path.isdir(folder):
            continue
        for cid in sorted(os.listdir(folder)):
            jp = os.path.join(folder, cid, cid + ".json")
            if not os.path.isfile(jp):
                continue
            try:
                d = json.loads(_read(jp))
            except ValueError:
                continue
            vs = d.get("variants")
            if not isinstance(vs, dict) or not vs:
                if kind != "weapon" and "variant" in d:
                    bad.append("%s %s names a variant but has no looks" % (kind, cid))
                continue
            n += 1
            for code, e in vs.items():
                if not CODE_RE.match(str(code)) or not isinstance(e, dict):
                    bad.append("%s %s: look %r is not a plain code with an object" % (kind, cid, code))
            if kind != "weapon":
                if "variant" in d:
                    bad.append("%s %s names its own variant (the family plays its weapon's)" % (kind, cid))
                continue
            base = str(d.get("variant_base") or "A")
            want = str(d.get("variant") or base)
            ok = {base}
            for code, e in vs.items():
                if isinstance(e, dict) and all(os.path.isfile(os.path.join(folder, cid, os.path.basename(str(e[k]))))
                                               if not str(e[k]).startswith("res://") else
                                               os.path.isfile(os.path.join(ROOT, "game", str(e[k])[6:].replace("/", os.sep)))
                                               for k in ("icon", "visual") if e.get(k)):
                    ok.add(str(code))
            if want not in ok:
                bad.append("weapon %s plays %s, which it cannot (files missing)" % (cid, want))
    check(not bad, "LOOKS76 content: %d weapon-family items with looks, each weapon playing a look it can, no member with a variant of its own: %s" % (n, bad[:6]))


def checks(check, run_node, server):
    server_checks(check, server)
    page_checks(check)
    content_checks(check)
