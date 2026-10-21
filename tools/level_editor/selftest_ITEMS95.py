"""Pass 95, lane ITEMS: the Level Editor knows the pass's keys. `fire_forward` (a weapon the "Fire forward" debug switch
covers, core/systems/FireForward.gd) is a shared params key in vocab.py and assets_fields.js and is read by the game; the
Frisbee's `disc.trail` block has typed rows (style, length, width, alpha, colour) in the disc group and the old bool row is
gone; the content carries the keys (the six weapons and their evolutions; the three trail blocks, one style per look).
selftest.py discovers this file and hands `checks` its counter. Nothing here writes.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

FORWARD = ["weapons/sabre", "weapons/pike", "weapons/hammer", "weapons/frisbee", "weapons/tumbleweed", "weapons/basketball",
           "evolutions/whirlwind", "evolutions/thunder_lance", "evolutions/earthshaker", "evolutions/flying_saucer",
           "evolutions/dust_devil", "evolutions/slam_dunk"]
TRAILS = {"weapons/frisbee": "streak", "mutations/poison_razors": "sparks", "evolutions/flying_saucer": "glow"}


def _json(rel):
    p = os.path.join(GAME, "content", rel, rel.split("/")[1] + ".json")
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def _read(*parts):
    with open(os.path.join(*parts), "r", encoding="utf-8") as f:
        return f.read()


def checks(check, run_node, server):
    import vocab
    check("fire_forward" in vocab.PARAMS_KEYS["*"], "ITEMS95 vocab.py lists fire_forward as a shared params key")
    check(any(p.endswith("FireForward.gd") for p in vocab._PARAMS_SHARED), "ITEMS95 vocab.py reads core/systems/FireForward.gd for the shared keys")
    probs = [p for p in vocab.check_against_source(GAME) if "fire_forward" in p]
    check(not probs, "ITEMS95 fire_forward is read by the game (check_against_source): %s" % probs)
    js = _read(HERE, "assets_fields.js")
    shared = js.split("const PARAMS_SHARED")[1].split("];")[0] if "const PARAMS_SHARED" in js else ""
    check("'fire_forward'" in shared, "ITEMS95 assets_fields.js PARAMS_SHARED has fire_forward")
    for leaf in ["style", "length", "width", "alpha", "colour"]:
        check("P('disc.trail.%s'" % leaf in js, "ITEMS95 the disc group has a typed row disc.trail.%s" % leaf)
    check("P('disc.trail'," not in js, "ITEMS95 the old disc.trail bool row is gone (the block replaced it)")
    src = _read(GAME, "core", "behaviors", "Frisbee.gd")
    check(all('"%s"' % k in src for k in ("style", "length", "width", "alpha", "colour")) and "func trail_params" in src,
          "ITEMS95 Frisbee.gd reads every key of the trail block (trail_params)")
    ff = _read(GAME, "core", "systems", "FireForward.gd")
    check('"fire_forward"' in ff and "NEAR_FRAC := 0.75" in ff, "ITEMS95 FireForward.gd reads params.fire_forward and holds the 75% rule")
    for rel in FORWARD:
        d = _json(rel)
        check((d.get("params") or {}).get("fire_forward") is True, "ITEMS95 %s carries params.fire_forward" % rel)
    for rel, style in TRAILS.items():
        d = _json(rel)
        tr = ((d.get("params") or {}).get("disc") or {}).get("trail")
        check(isinstance(tr, dict) and tr.get("style") == style and all(k in tr for k in ("length", "width", "alpha")),
              "ITEMS95 %s has a disc.trail block in the %s style with its numbers: %s" % (rel, style, tr))
    st = _read(GAME, "core", "autoload", "Settings.gd")
    check('var fire_forward: bool = false' in st and '"fire_forward": false' in st, "ITEMS95 Settings.fire_forward is off by default and PROD_LOCKED off")
