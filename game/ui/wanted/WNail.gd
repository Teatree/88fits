## A brass nail head (pass 82, lane TOTEM; design_handoff_88fits_totem, direction 1b): a 32 px brass disc in a 4 px ink
## ring, the thing a paper tag hangs from. Set `size` to its diameter; it draws a circle filling its box.
class_name WNail
extends Control

const SIDE := 32.0
const RING := 4.0

var fill := W.BRASS
var ring_color := W.INK


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(SIDE, SIDE)
	custom_minimum_size = Vector2(SIDE, SIDE)


## A nail centred on `c` (in its parent's coordinates).
static func at_center(c: Vector2, side: float = SIDE) -> WNail:
	var n := WNail.new()
	n.size = Vector2(side, side)
	n.position = c - n.size * 0.5
	return n


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, ring_color, true, -1.0, true)
	draw_circle(c, r - RING, fill, true, -1.0, true)
