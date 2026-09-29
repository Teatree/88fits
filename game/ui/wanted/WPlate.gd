## The one plate every item lives on: a rounded square in its kind's colour with an ink border, the painted icon
## centred on it, an optional level tag (paper chip, 3 px ink, slab number) overlapping the bottom-right corner by
## 10 px, optional path rivets (brass circles) over the top-left corner, and a locked look (aged plate, the icon a
## 30 % ink silhouette). Portraits are round (`round_plate`). Drawn in one pass, so a HUD row of twelve stays cheap.
class_name WPlate
extends Control

var side := 96.0:
	set(v):
		side = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var fill := W.BRASS
var border := 4
var border_color := W.INK
var radius := 10
var round_plate := false
var tex: Texture2D
var icon_frac := 0.81
var level_text := ""
var level_size := 22
var level_fill := W.PAPER
var level_border_color := W.INK
var rivets := 0
## Outside size of a path rivet (14 px inside a 2 px ink ring in the HUD).
var rivet_size := 18.0
var rivet_ring := 2.0
var locked := false
var shadow := 0
## A second, inner outline: the brass ring of an evolved item.
var ring := 0
var ring_color := W.BRASS
## The ring the plate has of its own (an evolved item's), for whoever borrows the ring and gives it back.
var base_ring := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)


## Set the plate up for a content item: its kind's colour, its icon, locked if it is not found yet.
func for_def(def: ContentDef, px: float, is_locked: bool = false) -> WPlate:
	side = px
	var k := W.kind_of(def)
	var evolved := W.is_evolved(def)
	fill = W.EVOLVED_FILL if evolved else W.KIND.get(k, W.BRASS)
	round_plate = k == "character"
	tex = def.icon if def else null
	locked = is_locked
	radius = 10 if px < 140 else (12 if px < 190 else (14 if px < 240 else (18 if px < 400 else 24)))
	border = 4 if px < 140 else 5
	# an evolution: the dark plate in a brass ring (about 4 px on a HUD slot)
	ring = maxi(3, int(round(px * 0.04))) if evolved and not is_locked else 0
	ring_color = W.EVOLVED_RING
	base_ring = ring
	queue_redraw()
	return self


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(side, side))
	var f := W.AGED if locked else fill
	if shadow > 0:
		_shape(Rect2(r.position + Vector2(shadow, shadow), r.size), W.INK, 0, W.INK)
	_shape(r, f, border, border_color)
	if ring > 0:
		var rr := r.grow(-border)
		if round_plate:
			draw_arc(rr.get_center(), rr.size.x * 0.5 - ring * 0.5, 0.0, TAU, 64, ring_color, ring, true)
		else:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_corner_radius_all(maxi(radius - border, 2))
			sb.set_border_width_all(ring)
			sb.border_color = ring_color
			sb.anti_aliasing = true
			draw_style_box(sb, rr)
	if tex:
		var inner := side * icon_frac
		var ts := tex.get_size()
		var k := inner / maxf(ts.x, ts.y)
		var sz := ts * k
		var at := (Vector2(side, side) - sz) * 0.5
		if round_plate:
			# a portrait fills its disc
			at = Vector2(border, border)
			sz = Vector2(side - border * 2, side - border * 2)
		draw_texture_rect(tex, Rect2(at, sz), false, Color(0.14, 0.106, 0.078, 0.3) if locked else Color.WHITE)
	if rivets > 0:
		# left:-6 / top:-10 on the padding box, 3 px apart
		var gap := 3.0
		for i in rivets:
			var c := Vector2(border - 6.0 + rivet_size * 0.5 + i * (rivet_size + gap), border - 10.0 + rivet_size * 0.5)
			draw_circle(c, rivet_size * 0.5, W.INK, true, -1.0, true)
			draw_circle(c, rivet_size * 0.5 - rivet_ring, W.BRASS, true, -1.0, true)
	if level_text != "":
		var fnt := W.slab()
		var tw := fnt.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, level_size).x
		var padx := 8.0 if level_size >= 22 else 7.0
		var h := W.normal_height(fnt, level_size) + 6.0
		var w := tw + padx * 2.0 + 6.0
		# right:-10 / bottom:-10 on the padding box: 10 px past the inner edge of the border
		var tag := Rect2(Vector2(side - border + 10.0 - w, side - border + 10.0 - h), Vector2(w, h))
		draw_rect(tag, level_border_color)
		draw_rect(tag.grow(-3.0), level_fill)
		var base := tag.position.y + 3.0 + (h - 6.0 - fnt.get_height(level_size)) * 0.5 + fnt.get_ascent(level_size)
		draw_string(fnt, Vector2(tag.position.x + 3.0 + padx, base), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, level_size, W.INK)


func _shape(r: Rect2, f: Color, b: int, bc: Color) -> void:
	if round_plate:
		var c := r.get_center()
		var rad := r.size.x * 0.5
		if b > 0:
			draw_circle(c, rad, bc, true, -1.0, true)
			draw_circle(c, rad - b, f, true, -1.0, true)
		else:
			draw_circle(c, rad, f, true, -1.0, true)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = f
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(b)
	sb.border_color = bc
	sb.anti_aliasing = true
	draw_style_box(sb, r)
