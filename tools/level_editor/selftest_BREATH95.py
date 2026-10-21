"""Pass 95, lane BREATH: the Dragon's Breath in the Level Editor's vocabulary and its content on disk.

Groups: vocab.py knows the FireBreath behaviour and its `breath` params key (every key it lists is one the behaviour
reads); assets_fields.js offers FireBreath with a `breath` param group whose rows name keys the behaviour reads; the
weapon, its three path mutations (element / volume / motion, one each) and its evolution parse and point at each other;
the soundmap carries the breath's start and its loop. Nothing here talks to the AI server or Godot.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

CONTENT = os.path.join(ROOT, "game", "content")
BEHAVIOUR = os.path.join(ROOT, "game", "core", "behaviors", "FireBreath.gd")
WEAPON = "dragons_breath"
PATH = {"blue_flame": "element", "held_breath": "volume", "backdraft": "motion"}
EVOLUTION = "fire_eater"


def _json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def checks(check, run_node, server):
    import vocab
    check("FireBreath" in vocab.BEHAVIOURS, "vocab.BEHAVIOURS lists FireBreath")
    keys = vocab.PARAMS_KEYS.get("FireBreath", [])
    check("breath" in keys, "vocab.PARAMS_KEYS[FireBreath] has `breath`: %s" % keys)
    src = open(BEHAVIOUR, encoding="utf-8").read()
    for k in keys:
        check('"%s"' % k in src or k == "fire_blue", "FireBreath.gd reads params key %s" % k)
    # the behaviour's own breath keys are the ones the page's rows offer
    read = set(re.findall(r'"(cone_deg|tick|seconds_per_amount|max_seconds|wait|knock|still|look|face_up|face_forward)"', src))
    af = open(os.path.join(HERE, "assets_fields.js"), encoding="utf-8").read()
    check("opt('FireBreath'" in af, "assets_fields.js offers the FireBreath behaviour")
    check(re.search(r"FireBreath:\s*\['breath'\]", af) is not None, "assets_fields.js PARAMS_KEYS.FireBreath = ['breath']")
    check("id: 'breath'" in af and "behaviors: ['FireBreath']" in af, "assets_fields.js has the `breath` param group for FireBreath")
    rows = re.findall(r"P\('breath\.([a-z_.]+)'", af)
    check(len(rows) >= 8, "the breath group has rows: %s" % rows)
    for r in rows:
        head = r.split(".")[0]
        check(head in read, "row breath.%s names a key FireBreath.gd reads (%s)" % (r, head))
    # the content
    w = _json(os.path.join(CONTENT, "weapons", WEAPON, WEAPON + ".json"))
    check(w["behavior"] == "FireBreath" and w["targeting"] == "forward", "the weapon runs FireBreath, facing")
    check(w["evolves_into"] == EVOLUTION and not w.get("hidden", False), "the weapon evolves into %s and is in play" % EVOLUTION)
    check(len(w["levels"]) == 5 and w["levels"][0] == [], "five levels, the first empty")
    # Garry's rule is relative ("the slowest weapon in the game"): slower than every other weapon's base cooldown, and
    # the evolution slower than every other evolution's (the number itself is his to tune in the editor)
    slow = {"weapons": [], "evolutions": []}
    for folder in ("weapons", "evolutions"):
        root = os.path.join(CONTENT, folder)
        for d in sorted(os.listdir(root)):
            p = os.path.join(root, d, d + ".json")
            if d in (WEAPON, EVOLUTION) or not os.path.isfile(p):
                continue
            j = _json(p)
            cd = (j.get("base") or {}).get("cooldown")
            if cd is not None:
                slow[folder].append((float(cd), d))
    nxt = max(slow["weapons"])
    check(float(w["base"]["cooldown"]) > nxt[0], "the slowest weapon in the game: %s s, the next %s at %s s" % (w["base"]["cooldown"], nxt[1], nxt[0]))
    ev0 = _json(os.path.join(CONTENT, "evolutions", EVOLUTION, EVOLUTION + ".json"))
    nxe = max(slow["evolutions"])
    check(float(ev0["base"]["cooldown"]) > nxe[0], "the slowest evolution: %s s, the next %s at %s s" % (ev0["base"]["cooldown"], nxe[1], nxe[0]))
    b = w["params"]["breath"]
    for k in ("cone_deg", "tick", "seconds_per_amount", "max_seconds", "wait"):
        check(k in b, "the weapon's breath block has %s" % k)
    kinds = {}
    for mid, kind in PATH.items():
        m = _json(os.path.join(CONTENT, "mutations", mid, mid + ".json"))
        check(m["weapon"] == WEAPON and m["kind"] == kind, "%s is a %s mutation of %s" % (mid, kind, WEAPON))
        check(bool(m.get("text")), "%s has card text" % mid)
        kinds[m["kind"]] = mid
    check(sorted(kinds) == ["element", "motion", "volume"], "one path mutation of each kind: %s" % kinds)
    bf = _json(os.path.join(CONTENT, "mutations", "blue_flame", "blue_flame.json"))
    check(bf["params"].get("fire_blue") is True and bf["element"] == "fire", "Blue Flame burns blue")
    bd = _json(os.path.join(CONTENT, "mutations", "backdraft", "backdraft.json"))
    check(float(bd["params"]["breath"]["knock"]) > 0, "Backdraft shoves")
    hb = _json(os.path.join(CONTENT, "mutations", "held_breath", "held_breath.json"))
    st = hb["params"]["breath"]["still"]
    check(st["seconds"] == 2.0 and st["duration_mult"] == 2.0 and st["damage_mult"] == 1.5 and st["ring"] is True, "Held Breath's still block: %s" % st)
    ev = _json(os.path.join(CONTENT, "evolutions", EVOLUTION, EVOLUTION + ".json"))
    check(ev["is_evolution"] is True and ev["evolved_from"] == WEAPON and ev["behavior"] == "FireBreath", "the Fire Eater is the weapon's evolution")
    th = [e for lv in ev["levels"] for e in lv if e.get("stat") == "thorns"]
    check(len(th) == 1 and th[0].get("target") == "player" and float(th[0]["value"]) == 8.0, "the Fire Eater's thorns +8 aimed at the player: %s" % th)
    # the sounds
    sm = _json(os.path.join(CONTENT, "sounds", "soundmap.json"))["sounds"]
    check("w_breath_start" in sm and "w_breath_loop" in sm and sm["w_breath_loop"].get("loop") is True, "the breath's start and loop in the soundmap")
    for sid in ("w_breath_start", "w_breath_loop"):
        check(os.path.exists(os.path.join(CONTENT, "sounds", sm[sid]["file"])), "%s's file is on disk" % sid)
    check(w["sfx"].get("fire") == "w_breath_start" and w["sfx"].get("loop") == "w_breath_loop", "the weapon names its sounds")
