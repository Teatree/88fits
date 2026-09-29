## The coin: a brass disc with an ink ring (paper on a brass button, so it still reads).
class_name WCoin
extends Control

var side := 34.0:
	set(v):
		side = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var fill := W.BRASS
var border := 3.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func make(px: float, f: Color = W.BRASS, b: float = 3.0) -> WCoin:
	var c := WCoin.new()
	c.side = px
	c.fill = f
	c.border = b
	return c


func _draw() -> void:
	var c := Vector2(side, side) * 0.5
	draw_circle(c, side * 0.5, W.INK, true, -1.0, true)
	draw_circle(c, side * 0.5 - border, fill, true, -1.0, true)
