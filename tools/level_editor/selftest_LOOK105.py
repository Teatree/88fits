"""Pass 105 (lane LOOK): the stage card's two new shares of the stage's filter.

The game (game/core/systems/StageLook.gd) reads a stage's `filter.structures` (the structures, the portal and the
barrels; STRUCTURES_DEFAULT when unset) and `filter.items` (the weapons' own 3D models; ITEMS_DEFAULT when unset) beside
lane SLOOK's `actors`. The stage card (stage_tabs.js) shows a slider for each, writes it only when it is set or moved off
the default (as `actors`), and its defaults must be the game's.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", "..", "game", "core", "systems", "StageLook.gd"))


def _const(src, name):
    m = re.search(r"const\s+%s\s*:=\s*([0-9.]+)" % name, src)
    return float(m.group(1)) if m else None


def checks(check, run_node=None, server=None):
    with open(os.path.join(HERE, "stage_tabs.js"), encoding="utf-8") as f:
        js = f.read()
    with open(GAME, encoding="utf-8") as f:
        gd = f.read()
    for key, js_name, gd_name in (("structures", "STRUCTURES_DEF", "STRUCTURES_DEFAULT"), ("items", "ITEMS_DEF", "ITEMS_DEFAULT")):
        m = re.search(r"const\s+%s\s*=\s*([0-9.]+)\s*;" % js_name, js)
        check(m is not None, "LOOK105: stage_tabs.js names %s" % js_name)
        g = _const(gd, gd_name)
        check(g is not None, "LOOK105: StageLook.gd names %s" % gd_name)
        if m and g is not None:
            check(abs(float(m.group(1)) - g) < 1e-9, "LOOK105: the card's default for `%s` is the game's (%s vs %s)" % (key, m.group(1), g))
        check("shareRow('%s'" % key in js, "LOOK105: the stage card has a slider for `%s`" % key)
        check("stage.filter.${k}" in js, "LOOK105: the sliders carry a data-path (stage.filter.<key>)")
    check("for (const k of ['structures', 'items'])" in js and "ee.filter[k] =" in js,
          "LOOK105: writeFilter keeps the two shares when the colour or strength is written again")
    check("share_of(f, \"structures\", STRUCTURES_DEFAULT)" in gd and "share_of(f, \"items\", ITEMS_DEFAULT)" in gd,
          "LOOK105: the game reads both keys with their defaults")
