## Pass 82 (lane XP; Garry: "EXP requirements ... Say I want to make the EXP requirements exponential instead of linear,
## it doesn't look like I can. I want that section to include types of EXP growth displayed in a dropdown"): the XP a
## hero level needs, by growth type.
##
## The map's `timeline_data.xp_curve` = {"type": <one of TYPES>, <type>: {its numbers}} names the type and keeps each
## type's numbers in a block of its own (the Level Editor switches the type and keeps the other blocks); a number a block
## leaves out is DEFAULTS'. Absent, {} or an unknown type = "quadratic" with 15, 6, 0.5: the curve every pass before
## played, to the bit. Everything here is BEFORE the map's `xp_need_mult` (Run.xp_to_next multiplies). L is the level the
## hero is at: level 1 needs need(1) XP to reach level 2.
##
## The types (each default lands near today's total by level 30, 7,322.5 XP before the multiplier):
##   quadratic    base + linear x L + quad x L^2                      15, 6, 0.5 (today's)
##   linear       base + step x (L - 1)                               21.5, 16.5 (base = what level 1 needs)
##   exponential  base x growth^(L - 1), never above cap (0 = no cap) 40, 1.11, 0
##   power        base x L^power                                      6.5, 1.33
##   table        [[level, XP], ...]: linear between the listed levels, the first's XP before it, past the last level
##                the last XP grown by after_growth a level (0 = it repeats); default: today's curve at 1, 5, 10 ... 60, +2.5%
## A level always needs at least MIN_NEED (a zero would level forever) and at most MAX_NEED (no infinity, no NaN).
## tools/level_editor/xp_model.js is a copy of this maths for the charts; selftest_XP82.py keeps the two equal.
class_name XpCurve
extends RefCounted

const TYPES := ["quadratic", "linear", "exponential", "power", "table"]
const DEFAULT_TYPE := "quadratic"
const DEFAULTS := {
	"quadratic": {"base": 15.0, "linear": 6.0, "quad": 0.5},
	"linear": {"base": 21.5, "step": 16.5},
	"exponential": {"base": 40.0, "growth": 1.11, "cap": 0.0},
	"power": {"base": 6.5, "power": 1.33},
	"table": {"points": [[1, 21.5], [5, 57.5], [10, 125.0], [20, 335.0], [30, 645.0], [40, 1055.0], [50, 1565.0], [60, 2175.0]], "after_growth": 0.025},
}
const MIN_NEED := 0.01
const MAX_NEED := 1.0e12


## The growth type a curve block names (DEFAULT_TYPE when it names none or one the game does not know).
static func type_of(curve: Dictionary) -> String:
	var t := str(curve.get("type", DEFAULT_TYPE))
	return t if TYPES.has(t) else DEFAULT_TYPE


## The numbers the type plays: its own block's, DEFAULTS' where the block leaves one out (or holds a non-number).
static func params_of(curve: Dictionary, type: String = "") -> Dictionary:
	var ty := type if TYPES.has(type) else type_of(curve)
	var out: Dictionary = (DEFAULTS[ty] as Dictionary).duplicate(true)
	var own = curve.get(ty, {})
	if not (own is Dictionary):
		return out
	for k: String in out.keys():
		var v = own.get(k)
		if k == "points":
			if v is Array and not _table_points(v).is_empty():
				out[k] = v
		elif v is float or v is int:
			out[k] = float(v)
	return out


## The XP level `level` needs to reach the next, before the map's xp_need_mult.
static func need(curve: Dictionary, level: int) -> float:
	var ty := type_of(curve)
	var p := params_of(curve, ty)
	match ty:
		"linear":
			var L := float(maxi(level, 1))
			return _clean(float(p.base) + float(p.step) * (L - 1.0))
		"exponential":
			var L := float(maxi(level, 1))
			var x := float(p.base) * pow(float(p.growth), L - 1.0)
			var cap := float(p.cap)
			return _clean(minf(x, cap) if cap > 0.0 else x)
		"power":
			var L := float(maxi(level, 1))
			return _clean(float(p.base) * pow(L, float(p.power)))
		"table":
			return _clean(_table_need(_table_points(p.points), float(p.after_growth), level))
	# quadratic: the same float maths as Run.xp_to_next before pass 82 (15.0 + 6.0 * L + 0.5 * L * L with the defaults)
	return _clean(float(p.base) + float(p.linear) * level + float(p.quad) * level * level)


## The XP from level 1 to `level` (the sum of need(1) .. need(level - 1)), before the multiplier.
static func total(curve: Dictionary, level: int) -> float:
	var s := 0.0
	for L in range(1, level):
		s += need(curve, L)
	return s


## A table's points as [[level (int >= 1), XP (float)], ...] sorted by level, one per level (the last listed wins);
## anything that is not a [number, number] pair is skipped.
static func _table_points(raw: Array) -> Array:
	var by_level := {}
	for p in raw:
		if not (p is Array) or (p as Array).size() < 2:
			continue
		var a = p[0]
		var b = p[1]
		if not ((a is float or a is int) and (b is float or b is int)):
			continue
		by_level[maxi(int(round(float(a))), 1)] = float(b)
	var levels: Array = by_level.keys()
	levels.sort()
	var out: Array = []
	for lv: int in levels:
		out.append([lv, by_level[lv]])
	return out


static func _table_need(pts: Array, after_growth: float, level: int) -> float:
	if pts.is_empty():
		pts = _table_points(DEFAULTS.table.points)
	var first: Array = pts[0]
	if level <= int(first[0]):
		return float(first[1])
	for k in range(1, pts.size()):
		var a: Array = pts[k - 1]
		var b: Array = pts[k]
		if level <= int(b[0]):
			var f := float(level - int(a[0])) / float(int(b[0]) - int(a[0]))
			return float(a[1]) + (float(b[1]) - float(a[1])) * f
	var last: Array = pts[pts.size() - 1]
	return float(last[1]) * pow(1.0 + after_growth, float(level - int(last[0])))


static func _clean(x: float) -> float:
	if is_nan(x) or is_inf(x):
		return MAX_NEED
	return clampf(x, MIN_NEED, MAX_NEED)
