"""Pass 82, lane XP: the XP growth types (Garry: "types of EXP growth displayed in a dropdown, each one with it's own 2 charts
for cumulative and per level EXP requirements"). selftest.py discovers this file (`extra_checks`) and hands it its
`check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes.

Groups: the tables (game/core/data/XpCurve.gd's TYPES / DEFAULTS / MIN_NEED / MAX_NEED are xp_model.js's and fields.js'
XP_TYPES rows'); the maths under Node against a Python copy of XpCurve.gd's need() for every type, many blocks and levels
0..150 (absent = 15 + 6L + 0.5L^2 to the bit; the hand-computed values game/tests/pass82_xp_test.gd pins); every type's
default lands near today's total by level 30; the cumulative series, levelAt and secondsToLevel; the page's checks
(errors and warnings on purpose-built blocks); fields.js (the XP per level card's rows with help and the game's
defaults, xp_need_mult moved there); the page wiring (index.html, settings.js, app.js); the map file's curve, if it names
one, raises no error.
"""
import json
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'xp_model.js'));
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.tables = { TYPES: M.TYPES, DEFAULTS: M.DEFAULTS, MIN_NEED: M.MIN_NEED, MAX_NEED: M.MAX_NEED, DEFAULT_TYPE: M.DEFAULT_TYPE };
  out.need = q.curves.map((c) => q.levels.map((L) => M.need(c, L)));
  out.types = q.curves.map((c) => M.typeOf(c));
  out.hand = q.hand.map(([c, L]) => M.need(c, L));
  out.total30 = M.TYPES.map((t) => M.total({ type: t }, 30));
  out.series = M.series({ type: 'linear', linear: { base: 10, step: 10 } }, 2, 5);
  out.levelAt = q.levelAt.map(([c, m, xp]) => M.levelAt(c, m, xp));
  out.secs = M.secondsToLevel({}, 1, q.xpByT, 4);
  out.secsNever = M.secondsToLevel({}, 1, q.xpByT, 40);
  out.mult = [M.multOf({}), M.multOf({ xp_need_mult: 1.65 }), M.multOf({ xp_need_mult: 0 }), M.multOf({ xp_need_mult: '' })];
  out.issues = q.issueCases.map((tl) => M.issues(tl));
  out.mapIssues = M.issues(q.map);
  out.xpTypes = FIELDS.XP_TYPES.map((t) => ({ v: t.v, label: t.label, formula: t.formula, help: !!t.help, params: t.params.map((p) => [p.key, p.type, p.def, !!p.help]) }));
  out.rows = FIELDS.SCALARS.filter((d) => d.key === 'xp_need_mult' || d.key.startsWith('xp_curve.')).map((d) => [d.key, d.group, d.block || '', !!d.help, d.type]);
  out.groups = FIELDS.SCALAR_GROUPS;
  out.typeOptions = (FIELDS.SCALARS.find((d) => d.key === 'xp_curve.type') || {}).options;
  process.stdout.write(JSON.stringify(out));
});
"""


# ------------------------------------------------------------------ a Python copy of game/core/data/XpCurve.gd

def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _gd_dict(text, name):
    i = text.find("const %s := {" % name)
    if i < 0:
        return None
    j = text.index("{", i)
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                body = re.sub(r",(\s*[}\]])", r"\1", text[j:k + 1])
                return json.loads(body)
    return None


def _gd_tables():
    src = _read(GAME, "core", "data", "XpCurve.gd")
    types = re.search(r"const TYPES := \[(.*?)\]", src, re.S)
    mn = re.search(r"const MIN_NEED := ([0-9.eE+-]+)", src)
    mx = re.search(r"const MAX_NEED := ([0-9.eE+-]+)", src)
    dt = re.search(r'const DEFAULT_TYPE := "(\w+)"', src)
    return {
        "TYPES": re.findall(r'"([^"]*)"', types.group(1)) if types else None,
        "DEFAULTS": _gd_dict(src, "DEFAULTS"),
        "MIN_NEED": float(mn.group(1)) if mn else None,
        "MAX_NEED": float(mx.group(1)) if mx else None,
        "DEFAULT_TYPE": dt.group(1) if dt else None,
    }


class GdXp:
    """XpCurve.gd line by line (GDScript floats are doubles; `x is float or x is int` never holds for a bool)."""

    def __init__(self, t):
        self.T = t

    @staticmethod
    def _num(v):
        return isinstance(v, (int, float)) and not isinstance(v, bool)

    def type_of(self, c):
        t = str(c.get("type", self.T["DEFAULT_TYPE"])) if isinstance(c, dict) else self.T["DEFAULT_TYPE"]
        return t if t in self.T["TYPES"] else self.T["DEFAULT_TYPE"]

    def params_of(self, c, ty):
        out = json.loads(json.dumps(self.T["DEFAULTS"][ty]))
        own = c.get(ty, {}) if isinstance(c, dict) else {}
        if not isinstance(own, dict):
            return out
        for k in list(out.keys()):
            v = own.get(k)
            if k == "points":
                if isinstance(v, list) and self.table_points(v):
                    out[k] = v
            elif self._num(v):
                out[k] = float(v)
        return out

    def table_points(self, raw):
        by = {}
        for p in raw:
            if not isinstance(p, list) or len(p) < 2:
                continue
            a, b = p[0], p[1]
            if not (self._num(a) and self._num(b)):
                continue
            # GDScript round(): halves away from zero
            r = math.floor(abs(float(a)) + 0.5) * (1 if float(a) >= 0 else -1)
            by[max(int(r), 1)] = float(b)
        return [[lv, by[lv]] for lv in sorted(by)]

    def table_need(self, pts, g, level):
        if not pts:
            pts = self.table_points(self.T["DEFAULTS"]["table"]["points"])
        if level <= pts[0][0]:
            return pts[0][1]
        for k in range(1, len(pts)):
            a, b = pts[k - 1], pts[k]
            if level <= b[0]:
                f = float(level - a[0]) / float(b[0] - a[0])
                return a[1] + (b[1] - a[1]) * f
        last = pts[-1]
        return last[1] * math.pow(1.0 + g, float(level - last[0]))

    def clean(self, x):
        if math.isnan(x) or math.isinf(x):
            return self.T["MAX_NEED"]
        return min(max(x, self.T["MIN_NEED"]), self.T["MAX_NEED"])

    def need(self, c, level):
        ty = self.type_of(c)
        p = self.params_of(c, ty)
        L = float(max(level, 1))
        try:
            if ty == "linear":
                return self.clean(p["base"] + p["step"] * (L - 1.0))
            if ty == "exponential":
                x = p["base"] * math.pow(p["growth"], L - 1.0)
                return self.clean(min(x, p["cap"]) if p["cap"] > 0.0 else x)
            if ty == "power":
                return self.clean(p["base"] * math.pow(L, p["power"]))
            if ty == "table":
                return self.clean(self.table_need(self.table_points(p["points"]), p["after_growth"], level))
        except OverflowError:
            return self.T["MAX_NEED"]
        except ValueError:   # pow of a negative to a fraction: NaN in GDScript
            return self.T["MAX_NEED"]
        return self.clean(p["base"] + p["linear"] * level + p["quad"] * level * level)


def _close(a, b, eps=1e-9):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(a)), abs(float(b)))


def _same(a, b):
    """Equal numbers (125 == 125.0), lists element by element."""
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return _close(a, b)
    return a == b


# the blocks the maths are compared on (every type, defaults, own numbers, gaps, junk, the guards)
CURVES = [
    {}, {"type": "quadratic"}, {"type": "cubic"}, {"type": None}, {"linear": {"base": 1}},
    {"type": "quadratic", "quadratic": {"base": 10, "linear": 0, "quad": 1}},
    {"type": "quadratic", "quadratic": {"base": 30, "linear": -2, "quad": 0.2}},
    {"type": "linear"}, {"type": "linear", "linear": {"base": 10, "step": 5}}, {"type": "linear", "linear": {"base": 0, "step": 0}},
    {"type": "linear", "linear": {"base": 10, "step": -5}}, {"type": "linear", "linear": "junk"},
    {"type": "exponential"}, {"type": "exponential", "exponential": {"base": 10, "growth": 2, "cap": 50}},
    {"type": "exponential", "exponential": {"base": 30, "growth": 1.2}}, {"type": "exponential", "exponential": {"growth": "fast"}},
    {"type": "exponential", "exponential": {"base": 1e300, "growth": 1e10}}, {"type": "exponential", "exponential": {"growth": 0.9, "cap": 0}},
    {"type": "power"}, {"type": "power", "power": {"base": 2, "power": 2}}, {"type": "power", "power": {"base": -3}},
    {"type": "power", "power": {"power": 0.5, "base": True}},
    {"type": "table"}, {"type": "table", "table": {"points": [[5, 40], [1, 10], [3, 30]], "after_growth": 0.1}},
    {"type": "table", "table": {"points": [[3, 30], [6, 60]]}}, {"type": "table", "table": {"points": [[1, 10], [2, 12]], "after_growth": 0}},
    {"type": "table", "table": {"points": [["a", 2], [1]]}}, {"type": "table", "table": {"points": [[2.5, 7], [2.4, 9], [0, 1], [-4, 3]]}},
    {"type": "table", "table": {"points": [[1, 10], [10, 100], [10, 50]], "after_growth": -0.5}},
]
LEVELS = list(range(0, 151))
# (block, level) -> the value game/tests/pass82_xp_test.gd pins (worked by hand)
HAND = [
    ({"type": "quadratic", "quadratic": {"base": 10, "linear": 0, "quad": 1}}, 3, 19.0),
    ({"type": "linear"}, 1, 21.5), ({"type": "linear"}, 10, 21.5 + 16.5 * 9), ({"type": "linear", "linear": {"base": 10, "step": 5}}, 3, 20.0),
    ({"type": "exponential"}, 1, 40.0), ({"type": "exponential"}, 3, 40.0 * 1.11 * 1.11),
    ({"type": "exponential", "exponential": {"base": 10, "growth": 2, "cap": 50}}, 3, 40.0),
    ({"type": "exponential", "exponential": {"base": 10, "growth": 2, "cap": 50}}, 4, 50.0),
    ({"type": "power", "power": {"base": 2, "power": 2}}, 3, 18.0), ({"type": "power"}, 1, 6.5),
    ({"type": "table", "table": {"points": [[5, 40], [1, 10], [3, 30]], "after_growth": 0.1}}, 4, 35.0),
    ({"type": "table", "table": {"points": [[5, 40], [1, 10], [3, 30]], "after_growth": 0.1}}, 7, 48.4),
    ({"type": "table", "table": {"points": [[3, 30], [6, 60]]}}, 1, 30.0),
    ({"type": "table", "table": {"points": [[1, 10], [2, 12]], "after_growth": 0}}, 50, 12.0),
    ({"type": "linear", "linear": {"base": 0, "step": 0}}, 5, 0.01),
]
TODAY_30 = 7322.5

# the page's checks: (timeline, the errors' count, the warnings' count, a word the first message has)
ISSUE_CASES = [
    ({}, 0, 0, None),
    ({"xp_curve": {}}, 0, 0, None),
    ({"xp_curve": {"type": "exponential"}}, 0, 0, None),                       # the default exponential passes 1e12 only past level 150
    ({"xp_curve": "exponential"}, 1, 0, "block"),
    ({"xp_curve": {"type": "cubic"}}, 1, 0, "unknown"),
    ({"xp_curve": {"type": "linear", "linear": {"base": 0, "step": 0}}}, 1, 0, "0 or less"),
    ({"xp_curve": {"type": "linear", "linear": {"base": 100, "step": -5}}}, 1, 0, "0 or less"),
    ({"xp_curve": {"type": "linear", "linear": {"base": "ten"}}}, 1, 0, "not a number"),
    ({"xp_curve": {"type": "exponential", "exponential": {"growth": 1.3}}}, 0, 1, "counts"),
    ({"xp_curve": {"type": "exponential", "exponential": {"growth": 0.9}}}, 0, 2, "under 1"),
    ({"xp_curve": {"type": "exponential", "exponential": {"cap": -1}}}, 1, 0, "cap"),
    ({"xp_curve": {"type": "table", "table": {"points": [["a", 1]]}}}, 1, 0, "no [level, XP]"),
    ({"xp_curve": {"type": "table", "table": {"points": [[1, 10], [1, 20], [5, 40]]}}}, 0, 1, "two points"),
    ({"xp_curve": {"type": "table", "table": {"points": [[1, 10], [5, 4]]}}}, 0, 1, "less XP"),
    ({"xp_curve": {"type": "power", "exponentail": {}}}, 0, 1, "not a growth type"),
    ({"xp_curve": {"type": "power", "power": {"base": 6.5, "slope": 3}}}, 0, 1, "means nothing"),
]


def checks(check, run_node, server):
    gd = _gd_tables()
    check(all(v is not None for v in gd.values()), "XP82: XpCurve.gd's TYPES, DEFAULTS, MIN_NEED, MAX_NEED, DEFAULT_TYPE read: %s" % [k for k, v in gd.items() if v is None])
    py = GdXp(gd)
    map_json = json.load(open(os.path.join(GAME, "content", "maps", "red_canyon", "red_canyon.json"), encoding="utf-8"))
    tl = map_json.get("timeline_data", {})
    q = {"curves": CURVES, "levels": LEVELS, "hand": [[c, L] for c, L, _ in HAND],
         "levelAt": [[{}, 1, TODAY_30], [{}, 1, TODAY_30 - 0.01], [{}, 1.65, TODAY_30 * 1.65 + 1e-6], [{"type": "linear", "linear": {"base": 10, "step": 10}}, 1, 60.5]],
         "xpByT": [0, 10, 25, 50, 70, 101, 140, 200],
         "issueCases": [c for c, _, _, _ in ISSUE_CASES], "map": tl}
    res = run_node(q, RUNNER)
    if not res:
        check(False, "XP82: xp_model.js ran under Node")
        return

    # the tables
    t = res["tables"]
    check(t["TYPES"] == gd["TYPES"] and t["DEFAULT_TYPE"] == gd["DEFAULT_TYPE"], "XP82: xp_model.js's TYPES are XpCurve.gd's: %s vs %s" % (t["TYPES"], gd["TYPES"]))
    check(t["DEFAULTS"] == gd["DEFAULTS"], "XP82: xp_model.js's DEFAULTS are XpCurve.gd's: %s vs %s" % (t["DEFAULTS"], gd["DEFAULTS"]))
    check(_close(t["MIN_NEED"], gd["MIN_NEED"]) and _close(t["MAX_NEED"], gd["MAX_NEED"]), "XP82: MIN_NEED / MAX_NEED agree")

    # the maths: JS == the GDScript copy for every block and level; absent = today's to the bit
    bad = []
    for ci, c in enumerate(CURVES):
        for li, L in enumerate(LEVELS):
            want = py.need(c, L)
            got = res["need"][ci][li]
            if not _close(got, want):
                bad.append((c, L, got, want))
    check(not bad, "XP82: xp_model.need == XpCurve.need for %d blocks x levels 0-150: %s" % (len(CURVES), bad[:4]))
    today = [15.0 + 6.0 * L + 0.5 * L * L for L in LEVELS]
    exact = all(res["need"][0][i] == today[i] and py.need({}, L) == today[i] for i, L in enumerate(LEVELS))
    check(exact, "XP82: no xp_curve = 15 + 6L + 0.5L^2 exactly (JS and the GDScript copy), levels 0-150")
    check(res["types"][:5] == ["quadratic"] * 5, "XP82: absent, quadratic, an unknown type, a null type, a stray block all play the quadratic: %s" % res["types"][:5])
    hand_bad = [(c, L, g, w) for (c, L, w), g in zip(HAND, res["hand"]) if not _close(g, w) or not _close(py.need(c, L), w)]
    check(not hand_bad, "XP82: the hand-worked values pass82_xp_test.gd pins: %s" % hand_bad)
    ratios = {ty: tot / TODAY_30 for ty, tot in zip(gd["TYPES"], res["total30"])}
    check(all(0.95 <= r <= 1.05 for r in ratios.values()), "XP82: every type's default lands within 5%% of today's total by level 30: %s" % {k: round(v, 3) for k, v in ratios.items()})
    print("XP82: totals by level 30 (before the multiplier), against today's 7,322.5: %s" % {k: round(v, 3) for k, v in ratios.items()})

    # the series and the readers
    s = res["series"]
    check([p["L"] for p in s] == [1, 2, 3, 4, 5] and [p["need"] for p in s] == [20, 40, 60, 80, 100] and [p["cum"] for p in s] == [0, 20, 60, 120, 200],
          "XP82: series = per level times the multiplier and the XP to reach each level: %s" % s)
    check(res["levelAt"] == [30, 29, 30, 4], "XP82: levelAt reaches a level when the XP meets its need (as Run.add_xp): %s" % res["levelAt"])
    # today's x1: level 1 -> 2 needs 21.5, 2 -> 3 29, 3 -> 4 37.5: level 4 at 88 XP, first reached at second 5 (101)
    check(res["secs"] == 5 and res["secsNever"] is None, "XP82: secondsToLevel = the first second the XP reaches the level, null when never: %s %s" % (res["secs"], res["secsNever"]))
    check(res["mult"] == [1, 1.65, 0.01, 1], "XP82: the multiplier as the game reads it (1 when unset, never under 0.01): %s" % res["mult"])

    # the page's checks
    for (tlc, ne, nw, word), got in zip(ISSUE_CASES, res["issues"]):
        errs = [m for m in got if m["level"] == "error"]
        warns = [m for m in got if m["level"] == "warn"]
        ok = len(errs) == ne and len(warns) == nw and (word is None or (got and word in got[0]["msg"]))
        check(ok, "XP82: the page's checks on %s: %d errors, %d warnings%s: %s" % (json.dumps(tlc)[:90], ne, nw, " (%r)" % word if word else "", got))
    map_errs = [m for m in res["mapIssues"] if m["level"] == "error"]
    check(not map_errs, "XP82: Red Canyon's curve (%s) raises no error: %s" % (json.dumps(tl.get("xp_curve")), map_errs))
    print("XP82: Red Canyon: xp_need_mult %s, xp_curve %s" % (tl.get("xp_need_mult"), json.dumps(tl.get("xp_curve"))))

    # fields.js: the card's rows
    xt = res["xpTypes"]
    check([x["v"] for x in xt] == gd["TYPES"], "XP82: fields.js XP_TYPES are the game's types in order: %s" % [x["v"] for x in xt])
    for x in xt:
        keys = [p[0] for p in x["params"]]
        defs = {p[0]: p[2] for p in x["params"]}
        want = gd["DEFAULTS"].get(x["v"], {})
        check(set(keys) == set(want) and all(_same(defs[k], want[k]) for k in want),
              "XP82: fields.js %s's numbers and their greys are XpCurve.DEFAULTS: %s vs %s" % (x["v"], defs, want))
        check(x["help"] and x["label"] and x["formula"] and all(p[3] for p in x["params"]), "XP82: fields.js %s has a label, a formula and help on every number" % x["v"])
    rows = {r[0]: r for r in res["rows"]}
    want_rows = {"xp_curve.type", "xp_need_mult"} | {"xp_curve.%s.%s" % (ty, k) for ty in gd["TYPES"] for k in gd["DEFAULTS"][ty]}
    check(set(rows) == want_rows, "XP82: fields.js has a row for every xp_curve key and XP needed x: missing %s, extra %s" % (sorted(want_rows - set(rows)), sorted(set(rows) - want_rows)))
    check(all(r[1] == "XP per level" and r[2] == "xp_curve" and r[3] for r in rows.values()), "XP82: every XP row is in the XP per level card, drawn by the card's block, with help")
    check("XP per level" in res["groups"] and res["groups"].index("XP per level") == res["groups"].index("Scaling") + 1, "XP82: the XP per level card follows Scaling: %s" % res["groups"])
    check([o["v"] for o in (res["typeOptions"] or [])] == gd["TYPES"], "XP82: the Growth dropdown offers every type")

    # the page wiring
    idx = _read(HERE, "index.html")
    order = [idx.find(s) for s in ('src="fields.js"', 'src="xp_model.js"', 'src="xp_card.js"', 'src="settings.js"')]
    check(all(i >= 0 for i in order) and order[1] < order[2] and 'href="xp.css"' in idx, "XP82: index.html loads xp.css, xp_model.js and xp_card.js")
    check("def.block === 'xp_curve'" in _read(HERE, "settings.js") and "XpCard.block(tl)" in _read(HERE, "settings.js"), "XP82: settings.js draws the XP card's block")
    check("XpModel.issues(d)" in _read(HERE, "app.js"), "XP82: app.js validates the curve (errors block Save)")
    run = _read(GAME, "core", "autoload", "Run.gd")
    check("XpCurve.need(xp_curve(), L) * xp_need_mult()" in run, "XP82: Run.xp_to_next reads the curve times the map's pace")
    check('t.get("xp_curve"' in _read(GAME, "core", "data", "JsonContent.gd") and "var xp_curve: Dictionary" in _read(GAME, "core", "data", "WaveTimeline.gd"),
          "XP82: JsonContent reads xp_curve into WaveTimeline.xp_curve")
