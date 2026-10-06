## A western reveal (pass 44): behind a level-up's title or a chest's landed plate, a wanted-poster sunburst of brass rays
## turns slowly and fades while paper scraps and brass sheriff's stars rain down, and a ring of dust snaps out from the
## spot. Drawn, no textures; it frees itself when it is done. `burst(host, at, index)` puts it into `host` at child
## `index` (over the dim, under the cards). Pass 54 (Garry: more celebration on a level-up): `strength` 2 is a bigger
## one (18 rays and 64 scraps for the 14 and 42 of 1), the rays can take another colour (the boss's chest: purple), and
## `sunburst` is a brass badge of a sun that pops up behind the LEVEL N title for SUN_LIFE seconds; `level_up` plays
## the lot: the badge, a strong burst and a second one BURST_GAP later, all done inside LIFE (under 2 s).
class_name WCelebrate
extends Control

const LIFE := 1.9
const RAYS := 14
const BITS := 42
## A strength-2 burst's rays and scraps (pass 54).
const RAYS_STRONG := 18
const BITS_STRONG := 64
## The second burst of a level-up, this long after the first.
const BURST_GAP := 0.15
## The sun badge's life and points.
const SUN_LIFE := 0.6
const SUN_POINTS := 28

var _at := Vector2.ZERO
var _t := 0.0
var _bits: Array = []   # [pos, vel, rot, spin, size, colour, star]
var _ray_phase := 0.0
var _rays := RAYS
var _bits_n := BITS
var _ray_color := W.BRASS
var _ray_k := 1.0
var _life := LIFE
## The sun badge (sunburst): its radius; 0 for a burst.
var _sun_r := 0.0


static func burst(host: Control, at: Vector2, index: int = 1, strength: float = 1.0, ray_color: Color = W.BRASS) -> WCelebrate:
	var c := WCelebrate.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c._at = at
	var k := clampf(strength - 1.0, 0.0, 1.0)
	c._rays = int(round(lerpf(RAYS, RAYS_STRONG, k)))
	c._bits_n = int(round(lerpf(BITS, BITS_STRONG, k)))
	c._ray_color = ray_color
	host.add_child(c)
	host.move_child(c, clampi(index, 0, host.get_child_count() - 1))
	return c


## A brass sun badge behind a title (pass 54, the level-up's LEVEL N): a disc of SUN_POINTS sharp points that pops up,
## turns a little and fades over SUN_LIFE seconds, an ink ring inside it.
static func sunburst(host: Control, at: Vector2, index: int = 1, radius: float = 280.0, color: Color = W.BRASS) -> WCelebrate:
	var c := WCelebrate.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c._at = at
	c._sun_r = radius
	c._life = SUN_LIFE
	c._bits_n = 0
	c._ray_color = color
	host.add_child(c)
	host.move_child(c, clampi(index, 0, host.get_child_count() - 1))
	return c


## The level-up's reveal (pass 54): the sun badge behind the title at `at`, a strong burst there and a second, plainer
## one BURST_GAP later; returns the first burst (tests count its rays).
static func level_up(host: Control, at: Vector2, index: int = 1) -> WCelebrate:
	sunburst(host, at, index)
	var first := burst(host, at, index, 2.0)
	var tw := host.create_tween()
	tw.tween_interval(BURST_GAP)
	tw.tween_callback(func():
		if is_instance_valid(host) and host.is_inside_tree():
			var second := burst(host, at + Vector2(0, 30), index, 1.0)
			second._ray_k = 0.5)
	return first


func rays() -> int:
	return _rays


func bits() -> int:
	return _bits_n


func _ready() -> void:
	# the UI runs while the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ray_phase = randf() * TAU
	var vp := get_viewport_rect().size
	var cols := [W.PAPER, W.BRASS, W.BRASS, W.ROCK, W.SAGE, W.AGED]
	for k in _bits_n:
		var x := randf_range(vp.x * 0.1, vp.x * 0.9)
		var star := randf() < 0.35
		_bits.append([Vector2(x, randf_range(-260.0, -40.0)), Vector2(randf_range(-80.0, 80.0), randf_range(380.0, 640.0)),
			randf() * TAU, randf_range(-6.0, 6.0), randf_range(14.0, 26.0) if not star else randf_range(16.0, 24.0),
			cols[randi() % cols.size()], star])


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	for b in _bits:
		b[1].y += 520.0 * delta
		b[1].x += sin(_t * 7.0 + b[2]) * 40.0 * delta
		b[0] += b[1] * delta
		b[2] += b[3] * delta
	queue_redraw()


func _draw() -> void:
	if _sun_r > 0.0:
		_draw_sun()
		return
	var f := _t / LIFE
	# the sunburst: wide brass rays from the spot, bright at once and gone by the end, turning a little
	var ray_a := 0.22 * _ray_k * (1.0 - f) * (1.0 - f)
	if ray_a > 0.004:
		var rot := _ray_phase + _t * 0.35
		var reach := 1300.0
		for k in _rays:
			var a := rot + TAU * k / _rays
			var half := 0.055 + 0.035 * sin(k * 2.1)
			var pts := PackedVector2Array([_at, _at + Vector2.from_angle(a - half) * reach, _at + Vector2.from_angle(a + half) * reach])
			draw_colored_polygon(pts, Color(_ray_color, ray_a))
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


## The sun badge: pops up over its first 0.18 s with a little overshoot, holds, fades over the second half of its life.
func _draw_sun() -> void:
	var k := clampf(_t / _life, 0.0, 1.0)
	var u := clampf(_t / 0.18, 0.0, 1.0)
	var grow := 1.0 + 0.12 * sin(u * PI) if u < 1.0 else 1.0
	var s := (1.0 - pow(1.0 - u, 3.0)) * grow
	var a := 0.7 * (1.0 - smoothstep(0.45, 1.0, k))
	if a <= 0.004 or s <= 0.01:
		return
	var rot := _ray_phase + _t * 0.5
	var pts := PackedVector2Array()
	for i in SUN_POINTS * 2:
		var rr := _sun_r * s * (1.0 if i % 2 == 0 else 0.8)
		pts.append(_at + Vector2.from_angle(rot + PI * float(i) / SUN_POINTS) * rr)
	draw_colored_polygon(pts, Color(_ray_color, a))
	draw_arc(_at, _sun_r * s * 0.72, 0.0, TAU, 72, Color(W.INK, a * 0.55), 6.0, true)
	draw_arc(_at, _sun_r * s * 0.64, 0.0, TAU, 72, Color(W.PAPER, a * 0.5), 3.0, true)
