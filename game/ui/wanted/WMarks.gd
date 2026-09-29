## Level, path and rank marks, drawn (no font here has a star):
##   stars   weapons /8, passives and lines /their max: brass filled up to `held`, the one this pick gives in paper
##           with a 2 px ink stroke, the rest aged with the stroke;
##   rivets  paths /3: brass circles held, aged the rest, 3 px ink;
##   notches ranks /3: 44 x 16 bars, brass owned, aged the rest, 3 px ink.
class_name WMarks
extends Control

var mode := "stars"
var total := 8
var held := 0
## Marks from `held` up to (not including) `upto` are "this pick" marks (paper stars); -1 = none.
var upto := -1
## Star glyph size (the mock's font-size) or the rivet / notch size.
var mark := 28.0
var gap := 8.0
var notch := Vector2(44, 16)
var notch_border := 3.0
var stroke := 2.0
var rivet_fill := W.BRASS
var rivet_empty := W.AGED
## The rivet this pick fills (the path offer's head shows it in solid aged paper).
var next_fill := W.PAPER
var rivet_border := 3.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_mode: String, p_total: int, p_held: int, p_upto: int = -1, p_mark: float = 28.0) -> WMarks:
	mode = p_mode
	total = p_total
	held = p_held
	upto = p_upto
	mark = p_mark
	update_minimum_size()
	queue_redraw()
	return self


func _step() -> float:
	match mode:
		"stars":
			return mark * 0.835
		"rivets":
			return mark + gap
		_:
			return notch.x + gap


func _get_minimum_size() -> Vector2:
	match mode:
		"stars":
			# the mock sets stars as slab text: the line box is the face's own height
			return Vector2(_step() * total, mark * 1.369)
		"rivets":
			return Vector2(_step() * total - gap, mark)
		_:
			return Vector2(_step() * total - gap, notch.y)


func _draw() -> void:
	var h := _get_minimum_size().y
	for i in total:
		var is_held := i < held
		var is_next := not is_held and upto > 0 and i < upto
		match mode:
			"stars":
				var c := Vector2(_step() * (i + 0.5), h * 0.52)
				star(self, c, mark * 0.41, W.BRASS if is_held else (W.PAPER if is_next else W.AGED), 0.0 if is_held else stroke)
			"rivets":
				var c := Vector2(i * _step() + mark * 0.5, h * 0.5)
				draw_circle(c, mark * 0.5, W.INK, true, -1.0, true)
				draw_circle(c, mark * 0.5 - rivet_border, rivet_fill if is_held else (next_fill if is_next else rivet_empty), true, -1.0, true)
			_:
				var r := Rect2(Vector2(i * _step(), 0), notch)
				draw_rect(r, W.INK)
				draw_rect(r.grow(-notch_border), W.BRASS if is_held else W.AGED)


## A five-point star, filled, with an optional ink stroke (the mock's -webkit-text-stroke).
static func star(ci: CanvasItem, c: Vector2, r: float, fill: Color, stroke_px: float = 0.0, ink: Color = W.INK) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * 0.42
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	if stroke_px > 0.0:
		# the stroke straddles the edge: fill slightly larger in ink, then the fill inset
		ci.draw_colored_polygon(_grow(pts, c, stroke_px * 0.5), ink)
		ci.draw_colored_polygon(_grow(pts, c, -stroke_px * 0.5), fill)
	else:
		ci.draw_colored_polygon(pts, fill)


static func _grow(pts: PackedVector2Array, c: Vector2, by: float) -> PackedVector2Array:
	var out := Geometry2D.offset_polygon(pts, by, Geometry2D.JOIN_MITER)
	return out[0] if not out.is_empty() else pts
