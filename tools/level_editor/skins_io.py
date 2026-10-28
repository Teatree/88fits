"""Pass 111, lane SKINS: a hero's looks sold to the players ("skins") in the Level Editor, and the currency registry.

The data (the game reads exactly this; docs/level_editor.md "Pass 111"):

  a hero's look entry   content/characters/<hero>/<hero>.json  variants[CODE].skin =
                        {"purchasable": bool, "name": "Black Beret", "price": 2000, "currency_type": "gold",
                         "unlock_quest": "skin_may_may_b" | ""}
                        (no `skin` or purchasable false: not offered; the look he is played in is owned by everyone)
  its goal              content/quests/skin_<hero>_<code lower, - -> _>/<id>.json =
                        {"id", "name": "May · Black Beret", "condition": {...}, "unlocks": {"type": "skin",
                         "id": "may:MAY-B"}, "quest_text"?, "icon": "res://content/characters/may/<badge>"}
  a currency            content/currencies/<id>/<id>.json  {id, name, flavour, order, icon (res://), colour, word}

server.py hands the routes here with itself as `srv` (CONTENT, BACKUPS, the write lock, backup, run_import, the
ledger, look_records ...), so a selftest that re-points those at a temporary copy tests these on it too:

  GET  /api/currencies                       [{id, name, flavour, icon (res://), icon_url, colour, word, order}]
  GET  /api/currencies/<id>/icon             that currency's icon picture
  POST /api/content/hero/<id>/skin/<CODE>    {purchasable?, name?, price?, currency_type?, quest?: {condition,
                                             quest_text?, name?} | null (remove the goal) | absent (leave it)}
                                             -> {ok, wrote: [...], skin, quest, backup, import_ok, output, moved_to}
                                             a field left out keeps its value on disk; errors {ok: false, error}, 400
                                             (404 no hero, 409 a quest id taken by something else)
"""
import json
import os
import re
import shutil

import content_io as cio
import vocab as VOCAB

SKIN_KEYS = ("purchasable", "name", "price", "currency_type", "unlock_quest")
_CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def code_slug(code):
    """MAY-B -> may_b (the quest folder's suffix)."""
    return str(code).lower().replace("-", "_")


def quest_id(hero, code):
    """The goal's quest id: skin_<hero>_<code slug> (skin_may_may_b)."""
    return "skin_%s_%s" % (hero, code_slug(code))


def unlock_key(hero, code):
    """What the goal's `unlocks.id` names: "<hero>:<CODE>"."""
    return "%s:%s" % (hero, code)


# ---------------------------------------------------------------- the currency registry

def currencies(srv):
    """The registry's records, each with the URL its icon is served at."""
    out = []
    for r in VOCAB.currency_records(srv.CONTENT):
        r = dict(r)
        r["icon_url"] = "/api/currencies/%s/icon" % r["id"]
        out.append(r)
    return out


def currency_ids(srv):
    return VOCAB.currency_ids(srv.CONTENT)


def currency_icon_file(srv, cid):
    """The icon picture of currency `cid` (its res:// path under game/, a content path under the content folder), or
    None. Only a picture inside the game folder is ever served."""
    rec = next((r for r in VOCAB.currency_records(srv.CONTENT) if r["id"] == cid), None)
    if rec is None or not rec.get("icon"):
        return None
    icon = str(rec["icon"])
    if icon.startswith("res://content/"):
        root, rel_path = srv.CONTENT, icon[len("res://content/"):]
    elif icon.startswith("res://"):
        root, rel_path = srv.GAME, icon[len("res://"):]
    else:
        root, rel_path = os.path.join(srv.CONTENT, "currencies", cid), os.path.basename(icon)
    full = os.path.abspath(os.path.join(root, rel_path.replace("/", os.sep)))
    if not full.startswith(os.path.abspath(root) + os.sep) or os.path.splitext(full)[1].lower() not in (".png", ".jpg", ".jpeg", ".webp", ".svg"):
        return None
    return full if os.path.isfile(full) else None


# ---------------------------------------------------------------- reading

def skin_of(entry):
    """A look entry's `skin` dict, or None."""
    return dict(entry["skin"]) if isinstance(entry, dict) and isinstance(entry.get("skin"), dict) else None


def skin_quests(cid, looks, quests):
    """{code: the quest record of that look's goal} for one hero: the quest whose unlocks is {type skin, id <hero>:<CODE>},
    else the quest the skin's unlock_quest names. `looks` are look_records (each with its `skin`), `quests` the server's
    quests_by_unlock()."""
    out = {}
    for lk in looks or []:
        code = str(lk.get("code", ""))
        q = quests.get(("skin", unlock_key(cid, code)))
        sk = lk.get("skin") if isinstance(lk.get("skin"), dict) else None
        if q is None and sk and sk.get("unlock_quest"):
            q = quests.get(("quest", str(sk["unlock_quest"])))
        if q is not None:
            out[code] = q
    return out


def on_sale(looks):
    """How many of a hero's looks are offered to players (purchasable, not shelved, not the one he is played in)."""
    return sum(1 for lk in looks or [] if isinstance(lk.get("skin"), dict) and lk["skin"].get("purchasable")
               and not lk.get("default") and not lk.get("shelved"))


def _stage_list(srv, map_id):
    try:
        with open(srv.map_path(map_id), "r", encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    sl = (d.get("timeline_data") or {}).get("stage_list") if isinstance(d.get("timeline_data"), dict) else None
    return [e for e in sl if isinstance(e, dict)] if isinstance(sl, list) else None


def stage_name(srv, map_id, stage):
    """The name a stage goes by (timeline_data.stage_list[stage - 1].name), else "stage <n>"."""
    sl = _stage_list(srv, map_id) or []
    if isinstance(stage, int) and 1 <= stage <= len(sl) and sl[stage - 1].get("name"):
        return str(sl[stage - 1]["name"])
    return "stage %s" % stage


# ---------------------------------------------------------------- checking a goal

def _whole(v):
    return isinstance(v, int) and not isinstance(v, bool) or (isinstance(v, float) and v.is_integer())


def clean_condition(srv, cond):
    """(condition, error): the condition with only its type's keys (QuestDef's; a key left from another type is dropped),
    or an error text. beat_stage checks its map, stage (1 .. the map's stages) and hero ("" = any hero)."""
    if not isinstance(cond, dict) or str(cond.get("type", "")) not in VOCAB.QUEST_TYPES:
        return None, "the goal needs a condition whose type is one of %s" % ", ".join(sorted(VOCAB.QUEST_TYPES))
    ctype = str(cond["type"])
    out = {"type": ctype}
    for k in VOCAB.QUEST_TYPES[ctype]:
        if k in cond and cond[k] is not None:
            out[k] = cond[k]
    if ctype == "beat_stage":
        mid = str(out.get("map") or "red_canyon")
        if not srv.ID_RE.match(mid) or not os.path.isfile(srv.map_path(mid)):
            return None, "beat_stage: no map %s" % mid
        out["map"] = mid
        st = out.get("stage", 1)
        if not _whole(st) or int(st) < 1:
            return None, "beat_stage: the stage is a whole number from 1"
        st = int(st)
        sl = _stage_list(srv, mid)
        if sl and st > len(sl):
            return None, "beat_stage: %s has %d stages, not %d" % (mid, len(sl), st)
        out["stage"] = st
        hero = str(out.get("hero") or "")
        if hero and srv.content_path("hero", hero)[1] is None:
            return None, "beat_stage: no hero %s" % hero
        out["hero"] = hero
        out = {"type": ctype, "map": out["map"], "stage": out["stage"], "hero": out["hero"]}
    return out, None


# ---------------------------------------------------------------- writing

def _icon_res(srv, cid, folder, d, entry):
    """The goal's icon: the look's own badge when its file is on disk, else the hero's icon (res://content/...)."""
    names = []
    if isinstance(entry, dict) and entry.get("icon"):
        names.append(os.path.basename(str(entry["icon"])))
    names.append(os.path.basename(str(d.get("icon") or cid + "_icon.png")))
    for n in names:
        if os.path.isfile(os.path.join(folder, n)):
            return "res://content/characters/%s/%s" % (cid, n)
    return "res://content/characters/%s/%s" % (cid, names[-1])


def _new_skin(old, purchasable, name, price, currency, unlock_quest):
    """The skin dict: the keys on disk keep their place (and any key this editor does not know stays), new ones follow in
    the contract's order."""
    out = dict(old) if isinstance(old, dict) else {}
    for k, v in zip(SKIN_KEYS, (purchasable, name, price, currency, unlock_quest)):
        out[k] = v
    return out


def set_skin(srv, cid, code, body):
    """POST /api/content/hero/<id>/skin/<CODE> (the module docstring). The look entry is written in place (only its text
    changes, a backup first); the goal's quest is made, edited in place (only the keys that changed) or moved to
    backups/deleted; then both are imported."""
    tfolder, path = srv.content_path("hero", cid)
    if path is None:
        return {"ok": False, "error": "no hero %s" % cid, "status": 404}
    if not isinstance(code, str) or not _CODE_RE.match(code):
        return {"ok": False, "error": "bad look code", "status": 400}
    body = body if isinstance(body, dict) else {}
    ids = currency_ids(srv)
    folder = os.path.dirname(path)
    wrote, imports, moved, backup_rel = [], [], None, ""
    with srv._write_lock:
        src = cio.read_text(path)
        d = json.loads(src)
        looks = {str(lk["code"]): lk for lk in srv.look_records("hero", cid, folder, d, path)}
        if code not in looks:
            return {"ok": False, "error": "%s has no look %s" % (cid, code), "status": 400}
        look = looks[code]
        vs = d.get("variants") if isinstance(d.get("variants"), dict) else {}
        entry = vs.get(code) if isinstance(vs.get(code), dict) else {}
        old = skin_of(entry) or {}
        # ---- the values (a field left out keeps the one on disk)
        purchasable = body.get("purchasable", old.get("purchasable", False))
        if not isinstance(purchasable, bool):
            return {"ok": False, "error": "purchasable is true or false", "status": 400}
        name = body.get("name", old.get("name", ""))
        if name is None:
            name = ""
        if not isinstance(name, str):
            return {"ok": False, "error": "the name is a text", "status": 400}
        name = name.strip()
        price = body.get("price", old.get("price", 0))
        if not _whole(price) or price < 0:
            return {"ok": False, "error": "the price is a whole number of 0 or more", "status": 400}
        price = int(price)
        currency = body.get("currency_type", old.get("currency_type", ids[0] if ids else "gold"))
        if currency not in ids:
            return {"ok": False, "error": "currency_type must be one of the currencies in content/currencies: %s" % ", ".join(ids), "status": 400}
        # ---- what this look can be
        if look.get("default") and (purchasable or isinstance(body.get("quest"), dict)):
            return {"ok": False, "error": "%s is the look %s is played in: every player owns it, so it is never sold" % (code, d.get("name", cid)), "status": 400}
        if purchasable and look.get("shelved"):
            return {"ok": False, "error": "%s is shelved: the game never offers a shelved look (unshelve it first)" % code, "status": 400}
        if purchasable and not look.get("ready", True):
            return {"ok": False, "error": "%s is not painted yet: the game leaves it out, so it cannot be sold" % code, "status": 400}
        # ---- the goal
        quests = srv.quests_by_unlock()
        have = quests.get(("skin", unlock_key(cid, code)))
        if have is None and old.get("unlock_quest"):
            q2 = quests.get(("quest", str(old["unlock_quest"])))
            if q2 is not None and (q2.get("unlocks") or {}).get("type") == "skin" and str((q2.get("unlocks") or {}).get("id")) == unlock_key(cid, code):
                have = q2
        unlock_quest = have["id"] if have else ""
        quest_plan = None   # ("new", qid, obj) | ("edit", qid, path, text, old_src) | ("remove", qid)
        if "quest" in body:
            q = body["quest"]
            if q is None:
                if have:
                    quest_plan = ("remove", have["id"])
                unlock_quest = ""
            elif isinstance(q, dict):
                cond, err = clean_condition(srv, q.get("condition"))
                if err:
                    return {"ok": False, "error": err, "status": 400}
                qname = str(q.get("name") or "").strip() or "%s · %s" % (str(d.get("name", cid)), name or "Look %s" % code)
                qtext = str(q.get("quest_text") or "").strip()
                icon = _icon_res(srv, cid, folder, d, entry)
                if have:
                    qid = have["id"]
                    qpath = os.path.join(srv.CONTENT, "quests", qid, qid + ".json")
                    qsrc = cio.read_text(qpath)
                    qold = json.loads(qsrc)
                    qtxt = qsrc
                    for key, value, places in (("name", qname, [("after", "id"), ("end", None)]),
                                               ("condition", cond, [("after", "name"), ("end", None)]),
                                               ("unlocks", {"type": "skin", "id": unlock_key(cid, code)}, [("after", "condition"), ("end", None)]),
                                               ("quest_text", qtext, [("after", "unlocks"), ("end", None)]),
                                               ("icon", icon, [("after", "quest_text"), ("after", "unlocks"), ("end", None)])):
                        if key == "quest_text" and value == "":
                            if key in qold:
                                qtxt = cio.del_top_block(qtxt, key)
                        elif qold.get(key) != value:
                            qtxt = cio.set_top_block(qtxt, key, value, places)
                        if qtxt is None:
                            return {"ok": False, "error": srv._layout_error(qpath, key), "status": 400}
                    if qtxt != qsrc:
                        quest_plan = ("edit", qid, qpath, qtxt)
                else:
                    qid = quest_id(cid, code)
                    if srv.id_exists_anywhere(qid):
                        return {"ok": False, "error": "the quest id %s exists already but does not unlock the look %s" % (qid, unlock_key(cid, code)), "status": 409}
                    qobj = {"id": qid, "name": qname, "condition": cond, "unlocks": {"type": "skin", "id": unlock_key(cid, code)}}
                    if qtext:
                        qobj["quest_text"] = qtext
                    qobj["icon"] = icon
                    quest_plan = ("new", qid, qobj)
                unlock_quest = qid
            else:
                return {"ok": False, "error": "quest is {condition, quest_text?, name?}, or null to remove the goal", "status": 400}
        # ---- the look entry's text (worked out before anything is written)
        skin = _new_skin(old if old else None, purchasable, name, price, currency, unlock_quest)
        if not old and not (purchasable or name or price or unlock_quest):
            skin = None   # nothing to record: a look that was never offered stays without a `skin` key
        text = src
        if skin is not None and skin != (skin_of(entry) or None):
            if not isinstance(d.get("variants"), dict):
                return {"ok": False, "error": "%s has no variants block: add the look in Looks first" % cid, "status": 400}
            text = cio.set_variant_entry(src, code, {"skin": skin})
            if text is None:
                return {"ok": False, "error": srv._layout_error(path, "variants.%s" % code), "status": 400}
        # ---- the writes: the quest first, then the hero (a refused layout above wrote nothing)
        if quest_plan is not None:
            kind = quest_plan[0]
            if kind == "remove":
                qid = quest_plan[1]
                dest = srv.deleted_dir(qid)
                shutil.move(os.path.join(srv.CONTENT, "quests", qid), os.path.join(dest, qid))
                srv.ledger_remove(qid)
                moved = srv.rel(dest)
                wrote.append("quest %s removed" % qid)
            elif kind == "edit":
                _, qid, qpath, qtxt = quest_plan
                srv.backup(qid, qpath)
                cio.write_atomic(qpath, qtxt)
                wrote.append("quest %s" % qid)
                imports.append("quests/%s" % qid)
            else:
                _, qid, qobj = quest_plan
                qfolder = os.path.join(srv.CONTENT, "quests", qid)
                os.makedirs(qfolder)
                cio.write_atomic(os.path.join(qfolder, qid + ".json"), cio.dump_new(qobj))
                srv.ledger_add(qid, "quest", cid)
                wrote.append("quest %s" % qid)
                imports.append("quests/%s" % qid)
        if text != src:
            backup_rel = srv.backup(cid, path)
            cio.write_atomic(path, text)
            wrote.insert(0, "variants.%s.skin" % code)
            imports.insert(0, "%s/%s" % (tfolder, cid))
    quest_rec = None
    if unlock_quest:
        qpath = os.path.join(srv.CONTENT, "quests", unlock_quest, unlock_quest + ".json")
        try:
            qd = json.loads(cio.read_text(qpath))
            quest_rec = {"id": unlock_quest, "name": str(qd.get("name", unlock_quest)), "condition": qd.get("condition") or {},
                         "unlocks": qd.get("unlocks") or {}, "quest_text": str(qd.get("quest_text", "")), "icon": str(qd.get("icon", "")),
                         "file": srv.rel(qpath)}
        except (OSError, ValueError):
            quest_rec = None
    if not wrote:
        return {"ok": True, "unchanged": True, "wrote": [], "skin": skin_of(entry), "quest": quest_rec, "backup": "",
                "import_ok": True, "output": "nothing changed", "moved_to": None}
    import_ok, output = (True, "nothing to import") if not imports else srv.run_import(",".join(imports))
    return {"ok": True, "wrote": wrote, "skin": skin, "quest": quest_rec, "backup": backup_rel, "import_ok": import_ok,
            "output": output, "moved_to": moved}


# ---------------------------------------------------------------- routes

def api_get(handler, srv, parts, query):
    """GET /api/currencies[/<id>/icon] (parts start with "currencies")."""
    if parts == ["currencies"]:
        return handler._send(200, currencies(srv))
    if len(parts) == 3 and parts[0] == "currencies" and parts[2] == "icon" and srv.ID_RE.match(parts[1]):
        full = currency_icon_file(srv, parts[1])
        if not full:
            return handler._error(404, "no icon for currency %s" % parts[1])
        return handler._file(full)
    return handler._error(404, "unknown API path")
