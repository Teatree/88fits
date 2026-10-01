## A western reveal (pass 44): behind a level-up's title or a chest's landed plate, a wanted-poster sunburst of brass rays
## turns slowly and fades while paper scraps and brass sheriff's stars rain down, and a ring of dust snaps out from the
## spot. Drawn, no textures; it frees itself when it is done. `burst(host, at, index)` puts it into `host` at child
## `index` (over the dim, under the cards).
class_name WCelebrate
extends Control

const LIFE := 1.9
const RAYS := 14
const BITS := 42

var _at := Vector2.ZERO
var _t := 0.0
var _bits: Array = []   # [pos, vel, rot, spin, size, colour, star]
var _ray_phase := 0.0


static func burst(host: Control, at: Vector2, index: int = 1) -> WCelebrate:
	var c := WCelebrate.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c._at = at
	host.add_child(c)
	host.move_child(c, clampi(index, 0, host.get_child_count() - 1))
	return c


func _ready() -> void:
	# the UI runs while the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ray_phase = randf() * TAU
	var vp := get_viewport_rect().size
	var cols := [W.PAPER, W.BRASS, W.BRASS, W.ROCK, W.SAGE, W.AGED]
	for k in BITS:
		var x := randf_range(vp.x * 0.1, vp.x * 0.9)
		var star := randf() < 0.35
		_bits.append([Vector2(x, randf_range(-260.0, -40.0)), Vector2(randf_range(-80.0, 80.0), randf_range(380.0, 640.0)),
			randf() * TAU, randf_range(-6.0, 6.0), randf_range(14.0, 26.0) if not star else randf_range(16.0, 24.0),
			cols[randi() % cols.size()], star])


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	for b in _bits:
		b[1].y += 520.0 * delta
		b[1].x += sin(_t * 7.0 + b[2]) * 40.0 * delta
		b[0] += b[1] * delta
		b[2] += b[3] * delta
	queue_redraw()


func _draw() -> void:
	var f := _t / LIFE
	# the sunburst: wide brass rays from the spot, bright at once and gone by the end, turning a little
	var ray_a := 0.22 * (1.0 - f) * (1.0 - f)
	if ray_a > 0.004:
		var rot := _ray_phase + _t * 0.35
		var reach := 1300.0
		for k in RAYS:
			var a := rot + TAU * k / RAYS
			var half := 0.055 + 0.035 * sin(k * 2.1)
			var pts := PackedVector2Array([_at, _at + Vector2.from_angle(a - half) * reach, _at + Vector2.from_angle(a + half) * reach])
			draw_colored_polygon(pts, Color(W.BRASS, ray_a))
	# the dust ring: a paper ring that snaps out and thins
	if _t < 0.55:
		var r := 60.0 + 520.0 * (1.0 - pow(1.0 - _t / 0.55, 2.5))
		draw_arc(_at, r, 0.0, TAU, 64, Color(W.PAPER, 0.5 * (1.0 - _t / 0.55)), 14.0 * (1.0 - _t / 0.55) + 2.0, true)
	# the confetti: paper scraps and brass stars
	var bit_a := clampf((LIFE - _t) / 0.5, 0.0, 1.0)
	for b in _bits:
		var p: Vector2 = b[0]
		if p.y > size.y + 40.0:
			continue
		var col: Color = b[5]
		col.a = bit_a
		draw_set_transform(p, b[2], Vector2.ONE)
		var s: float = b[4]
		if b[6]:
			var star := PackedVector2Array()
			for i in 10:
				var rr := s if i % 2 == 0 else s * 0.45
				star.append(Vector2.from_angle(-PI * 0.5 + TAU * i / 10.0) * rr)
			draw_colored_polygon(star, col)
			draw_polyline(star + PackedVector2Array([star[0]]), Color(W.INK, bit_a), 2.0, true)
		else:
			draw_rect(Rect2(-s * 0.5, -s * 0.3, s, s * 0.6), col)
			draw_rect(Rect2(-s * 0.5, -s * 0.3, s, s * 0.6), Color(W.INK, bit_a), false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
