## One of the Watch's charts (pass 80, lane WATCH): a dark plot drawn in _draw from what the panel hands it once a
## second (points already cut to the window and bucketed to the plot's width): lines on a left and a right axis, a
## lower band with its own axis (HP over Danger), stacked areas (the damage share), the Sim's average as a grey line,
## and vertical marks (the falls, a boss); pass 82: small shaped marks at moments along the plot's foot (the chests,
## power-ups and totems picked up), one lane each, and legend items with those shapes. Nothing here reads the game.
## Tools only.
extends Control

const BG := Color(0.105, 0.115, 0.14)
const EDGE := Color(0.22, 0.24, 0.29)
const GRID := Color(1, 1, 1, 0.06)
const TEXT := Color(0.62, 0.66, 0.74)
const TITLE := Color(0.86, 0.89, 0.94)
const FONT_SIZE := 12
const PAD_L := 46.0
const PAD_R := 46.0
const PAD_T := 22.0
const PAD_B := 16.0
## pass 82: the marks' size (px, half their width) and the step between their lanes
const POINT_R := 3.5
const LANE_H := 9.0
const POINT_EDGE := Color(0.05, 0.05, 0.07, 0.9)

var title := ""
var x0 := 0.0
var x1 := 180.0
## [left, right, lower]: {max, fmt, unit}; max <= 0 = the axis is not drawn
var axes: Array = [{"max": 1.0, "fmt": "%.0f", "unit": ""}, {"max": 0.0, "fmt": "%.0f", "unit": ""}, {"max": 0.0, "fmt": "%.0f", "unit": ""}]
## the lower band's share of the plot's height (0 = no lower band)
var lower := 0.0
## {pts: PackedVector2Array, color, width, axis: 0 left | 1 right | 2 lower, fill: bool (an area to the baseline),
## dashed: bool}
var series: Array = []
## stacked areas on the left axis: {top: PackedVector2Array, bottom: PackedVector2Array (same x), color}
var bands: Array = []
## vertical marks: {x, color}
var marks: Array = []
## pass 82: marks at moments, along the upper plot's foot: {x, lane (0 the lowest), shape: "square" | "circle" |
## "triangle", color}
var points: Array = []
## [[text, color], ...] in the title row; pass 82: [text, color, shape] draws that shape instead of the square
var legend: Array = []
## a line under the title (the window's words, "no data yet")
var note := ""
## the microseconds _draw took since the panel last asked (the Watch's cost)
var draw_us := 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func plot_rect() -> Rect2:
	var r := Rect2(Vector2(PAD_L, PAD_T), size - Vector2(PAD_L + (PAD_R if float(axes[1]["max"]) > 0.0 else 12.0), PAD_T + PAD_B))
	r.size = r.size.max(Vector2(10, 10))
	return r


## The upper plot (the lines on the left and right axes) and the lower band (axis 2).
func _rects() -> Array:
	var r := plot_rect()
	if lower <= 0.0:
		return [r, Rect2()]
	var lh := floorf(r.size.y * lower)
	var up := Rect2(r.position, Vector2(r.size.x, r.size.y - lh - 14.0))
	var lo := Rect2(Vector2(r.position.x, r.end.y - lh), Vector2(r.size.x, lh))
	return [up, lo]


func to_px(p: Vector2, axis: int) -> Vector2:
	var rr := _rects()
	var box: Rect2 = rr[1] if axis == 2 and lower > 0.0 else rr[0]
	var mx := maxf(float(axes[axis]["max"]), 0.000001)
	var fx := (p.x - x0) / maxf(x1 - x0, 0.001)
	var fy := clampf(p.y / mx, 0.0, 1.05)
	return Vector2(box.position.x + fx * box.size.x, box.end.y - fy * box.size.y)


func _draw() -> void:
	var us := Time.get_ticks_usec()
	_draw_all()
	draw_us += Time.get_ticks_usec() - us


func _draw_all() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2.ZERO, size), EDGE, false, 1.0)
	draw_string(font, Vector2(8, 15), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 1, TITLE)
	# the legend, right-aligned in the title row: as many items as fit beside the title, the first ones first
	var room := size.x - 8.0 - (8.0 + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 1).x + 16.0)
	var fit := 0
	var used := 0.0
	for item in legend:
		var need := font.get_string_size(str(item[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 22.0
		if used + need > room:
			break
		used += need
		fit += 1
	var lx := size.x - 8.0
	for i in range(fit - 1, -1, -1):
		var item: Array = legend[i]
		var txt := str(item[0])
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		lx -= w
		draw_string(font, Vector2(lx, 15), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		lx -= 12.0
		if item.size() > 2:
			_shape(Vector2(lx + 4.0, 11.0), str(item[2]), item[1], 4.0)
		else:
			draw_rect(Rect2(lx, 7, 8, 8), item[1])
		lx -= 10.0
	var rr := _rects()
	var up: Rect2 = rr[0]
	# the grid and the axes' numbers
	_grid(font, up, 0, 1)
	if lower > 0.0:
		_grid(font, rr[1], 2, -1)
	# the x axis: the window's ends and middle
	var yb := size.y - 3.0
	draw_string(font, Vector2(up.position.x, yb), _mmss(x0), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
	var mid := _mmss((x0 + x1) * 0.5)
	var mw := font.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x
	draw_string(font, Vector2(up.get_center().x - mw * 0.5, yb), mid, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
	var end := _mmss(x1)
	var ew := font.get_string_size(end, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x
	draw_string(font, Vector2(up.end.x - ew, yb), end, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
	if note != "":
		draw_string(font, Vector2(up.position.x + 6, up.position.y + 14), note, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
	# the stacked areas
	for b in bands:
		_band(b["top"], b["bottom"], b["color"])
	# the marks
	var full := plot_rect()
	for m in marks:
		var x := to_px(Vector2(float(m["x"]), 0.0), 0).x
		if x >= full.position.x and x <= full.end.x:
			draw_line(Vector2(x, full.position.y), Vector2(x, full.end.y), m["color"], 1.0)
	# the lines (areas first, so a line sits on top)
	for s in series:
		if bool(s.get("fill", false)):
			_fill(s["pts"], int(s.get("axis", 0)), s["color"])
	for s in series:
		var pts: PackedVector2Array = s["pts"]
		if pts.size() < 2:
			continue
		var ax := int(s.get("axis", 0))
		var px := PackedVector2Array()
		px.resize(pts.size())
		for i in range(pts.size()):
			px[i] = to_px(pts[i], ax)
		var col: Color = s["color"]
		var w := float(s.get("width", 1.5))
		if bool(s.get("dashed", false)):
			for i in range(0, px.size() - 1, 2):
				draw_line(px[i], px[i + 1], col, w, true)
		else:
			draw_polyline(px, col, w, true)
	_draw_points(up)


## Pass 82: the moments' marks on the upper plot's foot, each kind its lane (`lane` 0 the lowest), drawn last (on top).
func _draw_points(up: Rect2) -> void:
	for p in points:
		var x := to_px(Vector2(float(p["x"]), 0.0), 0).x
		if x < up.position.x - 0.5 or x > up.end.x + 0.5:
			continue
		var y := up.end.y - POINT_R - 2.0 - float(int(p.get("lane", 0))) * LANE_H
		_shape(Vector2(x, y), str(p.get("shape", "circle")), p["color"], POINT_R)


## A mark: a square, a circle or a triangle of half-width `r` at `c`, with a dark rim so it reads over a line or a fill.
func _shape(c: Vector2, shape: String, col: Color, r: float) -> void:
	match shape:
		"square":
			draw_rect(Rect2(c - Vector2(r + 1.0, r + 1.0), Vector2(r + 1.0, r + 1.0) * 2.0), POINT_EDGE)
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col)
		"triangle":
			draw_colored_polygon(triangle(c, r + 1.5), POINT_EDGE)
			draw_colored_polygon(triangle(c, r), col)
		_:
			draw_circle(c, r + 1.0, POINT_EDGE)
			draw_circle(c, r, col)


## A triangle pointing up round `c`, half-width about `r`.
static func triangle(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0.0, -r * 1.2), c + Vector2(r * 1.15, r * 0.9), c + Vector2(-r * 1.15, r * 0.9)])


func _grid(font: Font, box: Rect2, left_axis: int, right_axis: int) -> void:
	var lines := 2 if box.size.y < 70.0 else 4
	for k in range(lines + 1):
		# the upper plot's zero is left unlabelled over a lower band (its top label sits there)
		if k == 0 and left_axis == 0 and lower > 0.0:
			draw_line(Vector2(box.position.x, box.end.y), Vector2(box.end.x, box.end.y), GRID, 1.0)
			continue
		var f := float(k) / float(lines)
		var y := box.end.y - f * box.size.y
		draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), GRID, 1.0)
		var a: Dictionary = axes[left_axis]
		if float(a["max"]) > 0.0:
			var txt := _fmt(a, float(a["max"]) * f)
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x
			draw_string(font, Vector2(box.position.x - tw - 4.0, y + 4.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
		if right_axis >= 0 and float(axes[right_axis]["max"]) > 0.0:
			var b: Dictionary = axes[right_axis]
			draw_string(font, Vector2(box.end.x + 4.0, y + 4.0), _fmt(b, float(b["max"]) * f), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)


func _fmt(a: Dictionary, v: float) -> String:
	var fmt := str(a.get("fmt", "%.0f"))
	var unit := str(a.get("unit", ""))
	if fmt == "k":
		return _k(v) + unit
	# a whole-number axis whose tick falls between two numbers shows one decimal
	if fmt == "%.0f" and absf(v - roundf(v)) > 0.01:
		return ("%.1f" % v) + unit
	return (fmt % v) + unit


static func _k(v: float) -> String:
	if v >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if v >= 10000.0:
		return "%dk" % int(roundf(v / 1000.0))
	if v >= 1000.0:
		return ("%.1fk" % (v / 1000.0)).replace(".0k", "k")
	if absf(v - roundf(v)) > 0.01:
		return "%.1f" % v
	return "%d" % int(roundf(v))


static func _mmss(s: float) -> String:
	var n := int(maxf(s, 0.0))
	return "%d:%02d" % [n / 60, n % 60]


## An area from the line `pts` down to its axis's zero.
func _fill(pts: PackedVector2Array, axis: int, col: Color) -> void:
	if pts.size() < 2:
		return
	var base := PackedVector2Array()
	base.resize(pts.size())
	for i in range(pts.size()):
		base[i] = Vector2(pts[i].x, 0.0)
	_strip(pts, base, axis, Color(col.r, col.g, col.b, col.a * 0.22))


func _band(top: PackedVector2Array, bottom: PackedVector2Array, col: Color) -> void:
	_strip(top, bottom, 0, col)


## The area between two lines of the same times as one triangle list (one draw command).
func _strip(top: PackedVector2Array, bottom: PackedVector2Array, axis: int, col: Color) -> void:
	var n := mini(top.size(), bottom.size())
	if n < 2:
		return
	var pts := PackedVector2Array()
	pts.resize(n * 2)
	for i in range(n):
		pts[i * 2] = to_px(top[i], axis)
		pts[i * 2 + 1] = to_px(bottom[i], axis)
	var idx := PackedInt32Array()
	idx.resize((n - 1) * 6)
	for i in range(n - 1):
		var a := i * 2
		idx[i * 6] = a
		idx[i * 6 + 1] = a + 2
		idx[i * 6 + 2] = a + 1
		idx[i * 6 + 3] = a + 1
		idx[i * 6 + 4] = a + 2
		idx[i * 6 + 5] = a + 3
	var cols := PackedColorArray()
	cols.resize(n * 2)
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
