## The Results' kills chart (pass 72, Garry: "This chart always starts on the left and ends on the right following the
## sequence of kills that Player had done. On the chart Player's deaths are marked with a grave, boss kills with a skull,
## elites with a crown, specials with a gear"). The run's kills in SLICES equal slices of its play time, drawn as a rock
## red area under an ink line on an aged plot with an ink border; the stages' starts as dashed lines; the marks as the
## game's own painted badges (art/ui/badges: skull, crown, gear, and the grave): a kill's on the line where it came, a
## stack when several kinds meet, a paper chip with ×N when one badge stands for several, a grave standing on the
## ground line. `head` (0..1) is how far the line is drawn; a mark pops in (POP_TIME, a little overshoot) as the head
## reaches it and says so (`popped`). None of the game's fonts has the emoji (🪦 💀 👑 ⚙️), and a phone's own emoji font
## is not something Godot can be trusted to fall back on, so the badges are pictures.
class_name WKillChart
extends Control

signal popped(kind: int)

const SLICES := 48
const BADGE_PX := 46.0
const POP_TIME := 0.3
const BADGE_PATH := "res://art/ui/badges/%s.png"
## Room over the plot's tallest point for the badges that stand on it, and under it for the stages' names.
const TOP_ROOM := 40.0
const FOOT_ROOM := 30.0
const BORDER := 4.0

## Kills per slice, the tallest 1.
var slices := PackedFloat32Array()
## {"x": 0..1, "kind": RunTimeline.KIND_*, "n": how many, "at": the pop clock (-1 not yet), "c": its centre, "hidden":
## joined to a special it would cover}
var marks: Array = []
## [x, stage index] where a stage began.
var stage_x: Array = []
var head := 0.0:
	set(v):
		head = clampf(v, 0.0, 1.0)
		_pop_reached()
		queue_redraw()
var _clock := 0.0
var _tex: Dictionary = {}
## The size the marks were laid out for (_layout runs again when it changes).
var _laid := Vector2(-1, -1)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false


## The chart of a run's story: its kill slices, its stages, its marks (several of one kind closer than a badge merge
## into one with a count; different kinds that meet stack up, _layout).
func setup(tl: RunTimeline, width: float) -> WKillChart:
	var raw := tl.kill_slices(SLICES) if not tl.is_empty() else PackedFloat32Array()
	slices = smooth(raw)
	var top := 0.0
	for v in slices:
		top = maxf(top, v)
	for k in slices.size():
		slices[k] = slices[k] / top if top > 0.0 else 0.0
	stage_x.clear()
	for s in tl.stages:
		stage_x.append([clampf(float(s[0]) / tl.length(), 0.0, 1.0), int(s[1])])
	marks = group_marks(tl.markers, tl.length(), BADGE_PX * 0.9 / maxf(width, 1.0))
	_laid = Vector2(-1, -1)
	return self


## [1, 2, 1] smoothing, so one busy second does not read as a spike.
static func smooth(a: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	for k in a.size():
		var l: float = a[maxi(k - 1, 0)]
		var r: float = a[mini(k + 1, a.size() - 1)]
		out[k] = (l + 2.0 * a[k] + r) * 0.25
	return out


## The run's markers ([t, kind]) as the chart's marks, in time order: one of a kind within its bin (`bin` of the width,
## twice that for a special) of the last of its kind joins it (its count grows; it keeps the first one's place). Where
## each stands is worked out when it is drawn (_layout).
static func group_marks(markers: Array, length: float, bin: float) -> Array:
	var out: Array = []
	var last: Dictionary = {}
	for m in markers:
		var x := clampf(float(m[0]) / maxf(length, 0.001), 0.0, 1.0)
		var kind := int(m[1])
		var b := bin * (2.0 if kind == RunTimeline.KIND_SPECIAL else 1.0)
		if last.has(kind) and x - float(last[kind]["x"]) < b:
			last[kind]["n"] = int(last[kind]["n"]) + 1
			continue
		var mk := {"x": x, "kind": kind, "n": 1, "at": -1.0, "c": Vector2.ZERO, "hidden": false}
		last[kind] = mk
		out.append(mk)
	return out


## A mark's badge size: a boss's biggest, a special's smallest.
static func badge_px(kind: int) -> float:
	match kind:
		RunTimeline.KIND_BOSS:
			return BADGE_PX * 1.3
		RunTimeline.KIND_ELITE:
			return BADGE_PX * 1.1
		RunTimeline.KIND_SPECIAL:
			return BADGE_PX * 0.8
	return BADGE_PX


## Where each mark stands, the most important placed first (a boss, an Elite, a grave, a special): a kill's on the line
## at its moment, a grave on the ground line; one that would cover a placed badge goes up a step, a special that would
## cover another special joins it instead (its count added).
func _layout() -> void:
	_laid = size
	var r := plot_rect()
	var inner := r.grow(-BORDER)
	var placed: Array = []
	for kind in [RunTimeline.KIND_BOSS, RunTimeline.KIND_ELITE, RunTimeline.KIND_DOWN, RunTimeline.KIND_SPECIAL]:
		for mk: Dictionary in marks:
			if int(mk["kind"]) != kind:
				continue
			mk["hidden"] = false
			var px := badge_px(kind)
			var x: float = inner.position.x + float(mk["x"]) * inner.size.x
			x = clampf(x, inner.position.x + px * 0.5, inner.end.x - px * 0.5)
			var c := Vector2(x, inner.end.y - px * 0.5 + 4.0)
			if kind != RunTimeline.KIND_DOWN:
				c.y = _point(r, inner, float(mk["x"])).y - px * 0.42
			var joined := false
			for step in 6:
				var hit: Dictionary = {}
				for p: Dictionary in placed:
					var gap := (badge_px(int(p["kind"])) + px) * 0.42
					if (p["c"] as Vector2).distance_to(c) < gap:
						hit = p
						break
				if hit.is_empty():
					break
				if kind == RunTimeline.KIND_SPECIAL and int(hit["kind"]) == kind:
					hit["n"] = int(hit["n"]) + int(mk["n"])
					mk["hidden"] = true
					joined = true
					break
				c.y = (hit["c"] as Vector2).y - (badge_px(int(hit["kind"])) + px) * 0.45
			if joined:
				continue
			c.y = maxf(c.y, px * 0.5)
			mk["c"] = c
			placed.append(mk)


## Every mark at once, no pops (a skip).
func finish() -> void:
	for mk: Dictionary in marks:
		mk["at"] = -1000.0
	head = 1.0


func _process(delta: float) -> void:
	_clock += delta
	for mk: Dictionary in marks:
		if float(mk["at"]) >= 0.0 and _clock - float(mk["at"]) < POP_TIME + 0.05:
			queue_redraw()
			return


func _pop_reached() -> void:
	for mk: Dictionary in marks:
		if float(mk["at"]) == -1.0 and float(mk["x"]) <= head + 0.0001:
			mk["at"] = _clock
			popped.emit(int(mk["kind"]))


## The plot's rectangle inside the control (the room for the badges above it).
func plot_rect() -> Rect2:
	return Rect2(Vector2(0, TOP_ROOM), Vector2(size.x, maxf(size.y - TOP_ROOM - FOOT_ROOM, 10.0)))


## The line's height (0..1 of the plot) at `x`, between the slices' centres.
func level_at(x: float) -> float:
	var n := slices.size()
	if n == 0:
		return 0.0
	var f := clampf(x, 0.0, 1.0) * float(n) - 0.5
	var k := clampi(int(floor(f)), 0, n - 1)
	var k2 := mini(k + 1, n - 1)
	return lerpf(slices[k], slices[k2], clampf(f - float(k), 0.0, 1.0)) if f >= 0.0 else slices[0]


func _point(r: Rect2, inner: Rect2, x: float) -> Vector2:
	var h := level_at(x)
	return Vector2(inner.position.x + x * inner.size.x, inner.end.y - h * inner.size.y * 0.86)


func _draw() -> void:
	var r := plot_rect()
	draw_rect(r, W.INK)
	var inner := r.grow(-BORDER)
	draw_rect(inner, W.AGED)
	# two faint guides
	for g in [0.33, 0.66]:
		var y: float = inner.end.y - inner.size.y * 0.86 * g
		draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(W.INK, 0.12), 2.0)
	# the area and the line, as far as the head
	if head > 0.0 and slices.size() > 0:
		var pts := PackedVector2Array()
		var steps := maxi(int(ceil(head * 120.0)), 2)
		for k in steps + 1:
			pts.append(_point(r, inner, head * float(k) / float(steps)))
		var poly := PackedVector2Array(pts)
		poly.append(Vector2(pts[pts.size() - 1].x, inner.end.y))
		poly.append(Vector2(inner.position.x, inner.end.y))
		draw_colored_polygon(poly, Color(W.ROCK, 0.85))
		draw_polyline(pts, W.INK, 5.0, true)
	# the stages' starts, over the area, as the line reaches them
	for s in stage_x:
		if float(s[0]) > head:
			continue
		var sx: float = inner.position.x + float(s[0]) * inner.size.x
		_dashed(Vector2(sx, inner.position.y), Vector2(sx, inner.end.y), Color(W.INK, 0.45), 3.0)
		_stage_name(Vector2(sx, r.end.y), "Stage %d" % (int(s[1]) + 1))
	if head > 0.0 and head < 1.0 and slices.size() > 0:
		var tip := _point(r, inner, head)
		draw_line(Vector2(tip.x, inner.position.y), Vector2(tip.x, inner.end.y), Color(W.INK, 0.35), 2.0)
		draw_circle(tip, 8.0, W.INK, true, -1.0, true)
		draw_circle(tip, 4.0, W.PAPER, true, -1.0, true)
	# the marks: graves on the ground first, the kills over the line
	if _laid != size:
		_layout()
	for pass_graves in [true, false]:
		for mk: Dictionary in marks:
			var grave := int(mk["kind"]) == RunTimeline.KIND_DOWN
			if grave != pass_graves or bool(mk["hidden"]) or float(mk["at"]) == -1.0:
				continue
			var s := _pop_scale(float(mk["at"]))
			if s <= 0.0:
				continue
			var c: Vector2 = mk["c"]
			var px := badge_px(int(mk["kind"]))
			var tex := _badge(int(mk["kind"]))
			var side := px * s
			if tex:
				draw_texture_rect(tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
			else:
				draw_circle(c, side * 0.4, W.INK, true, -1.0, true)
			if int(mk["n"]) > 1 and s >= 0.99:
				_chip(c + Vector2(px * 0.22, px * 0.18), "×%d" % int(mk["n"]))


## A mark's size as it pops: 0 before, up past 1 and back over POP_TIME.
func _pop_scale(at: float) -> float:
	if at <= -999.0:
		return 1.0
	var t := (_clock - at) / POP_TIME
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


## A small paper chip with a count, its left edge at `at`.
func _chip(at: Vector2, t: String) -> void:
	var f := W.slab()
	var px := 15
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 10.0
	var rc := Rect2(at - Vector2(0, 11), Vector2(w, 22))
	draw_rect(rc, W.INK)
	draw_rect(rc.grow(-2.0), W.PAPER)
	draw_string(f, Vector2(rc.position.x + 5.0, rc.position.y + 16.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, W.INK)


## A stage's name under the plot, centred on where it began (a tick from the border down to it).
func _stage_name(at: Vector2, t: String) -> void:
	var px := 16
	var f := W.serif(600, false, W.em(px, 0.15))
	var w := f.get_string_size(t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x := clampf(at.x - w * 0.5, 0.0, size.x - w)
	draw_line(at, at + Vector2(0, 7), W.INK, 3.0)
	draw_string(f, Vector2(x, at.y + 7.0 + f.get_ascent(px)), t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px, W.INK_SOFT)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var len := a.distance_to(b)
	var d := (b - a) / maxf(len, 0.001)
	var s := 0.0
	while s < len:
		draw_line(a + d * s, a + d * minf(s + 10.0, len), col, w)
		s += 18.0


func _badge(kind: int) -> Texture2D:
	var name: String = RunTimeline.KIND_NAMES[clampi(kind, 0, RunTimeline.KIND_NAMES.size() - 1)]
	if not _tex.has(name):
		var path := BADGE_PATH % name
		_tex[name] = load(path) if name != "" and ResourceLoader.exists(path) else null
	return _tex[name]
