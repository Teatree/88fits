## A rubber stamp (pass 72, the Results' unlocks): a word in slab inside a double frame, in one ink colour a little
## see-through, as a sheriff's office would stamp a poster. Turned by whoever hangs it (a free child, like the NEW BEST
## seal). `slam(t)` is its landing: from STAMP_FROM times its size and see-through down to its place over `t` seconds.
class_name WStamp
extends Control

const STAMP_FROM := 2.4

var word := "UNLOCKED"
var color := W.SAGE
var text_px := 30


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func make(t: String, col: Color, px: int = 30) -> WStamp:
	var s := WStamp.new()
	s.word = t
	s.color = col
	s.text_px = px
	s.size = s.stamp_size()
	s.custom_minimum_size = s.size
	s.pivot_offset = s.size * 0.5
	return s


## The stamp's size from its word: the slab word plus the frames' room.
func stamp_size() -> Vector2:
	var f := W.slab()
	var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px).x
	return Vector2(ceilf(w) + 52.0, float(text_px) + 40.0)


## Its landing over `t` seconds (0: at once): big and faint to its size and full ink, an ease-in.
func slam(t: float) -> void:
	if t <= 0.0:
		scale = Vector2.ONE
		modulate.a = 1.0
		return
	scale = Vector2.ONE * STAMP_FROM
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 1.0, t * 0.6)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var ink := Color(color, 0.9)
	draw_rect(r, ink, false, 6.0)
	draw_rect(r.grow(-11.0), ink, false, 3.0)
	var f := W.slab()
	var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px).x
	var base := (size.y - f.get_height(text_px)) * 0.5 + f.get_ascent(text_px)
	draw_string(f, Vector2((size.x - w) * 0.5, base), word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px, ink)
