## The tutorial's highlight on one button (pass 137, lane TUTOR; Garry: "a big fat highlight of the Upgrade button", "the
## Buy button is highlighted the same way until the first tap"): the button grows to BASE with a small overshoot and
## pulses round it, a warm glow breathes round its edge (drawn under it), a shine crosses its face every SHINE_EVERY
## seconds, and a white glove points at it, tapping it with a ripple at the fingertip. The Results' UPGRADE and the
## Trail's BUY wear it. No class_name: load it by path,
##     var hl: Control = load("res://ui/wanted/WHighlight.gd").attach(button, screen)
## `screen` takes the overlay (the shine, the glove) as its last child, a frame later (so the tab bar a screen adds after
## its build() is under it, and a pop-up opened later is over it); the glow goes under the button in its nearest parent
## that is not a Container (a Container would lay it out). `retarget(button)` moves it to another button (the Trail's
## dock rebuilt) without the entrance again; `stop()` ends it for good (the button back to its size, the nodes freed).
## The glove comes from the lower right of a button in the screen's left half and from the lower left of one in its right
## half. Looks only: it runs on the frame's delta and never rolls a die. Nodes for tools: the overlay "TutorHighlight",
## the glow "TutorGlow"; the button carries the meta "highlight" while it is on.
extends Control

const SELF_PATH := "res://ui/wanted/WHighlight.gd"
## The button's size at rest in the pulse, the pulse's swing either side and its rate; the entrance's length.
const BASE := 1.09
const SWING := 0.035
const PULSE_HZ := 1.25
const INTRO_S := 0.42
## The glow round the button: GLOW_LAYERS soft rings out to GLOW_REACH px (under the button), and a crisp rim RIM px wide
## RIM_OUT px out (over everything, so a neighbouring button never hides it).
const GLOW := Color("ffd34d")
const GLOW_LAYERS := 7
const GLOW_REACH := 52.0
const GLOW_ALPHA := 0.2
const RIM := 6.0
const RIM_OUT := 9.0
## The shine: a slanted band SHINE_W of the button's width crossing it in SHINE_S, once every SHINE_EVERY.
const SHINE_EVERY := 1.7
const SHINE_S := 0.55
const SHINE_W := 0.26
## The glove: its size (1 = about 84 x 156 px on the 1080 canvas), the fingertip's place on the button (fractions of
## its rect, mirrored for a glove from the left), how far it draws back between taps, its angle off upright: HAND_TILT,
## leaning further (up to HAND_TILT_MAX) when the screen's foot is too near for it to stand whole (the Results' row).
const HAND_SCALE := 1.0
const TIP := Vector2(0.64, 0.55)
const HAND_BACK := 26.0
const HAND_TILT := 0.6
const HAND_TILT_MAX := 1.3
const HAND_LEN := 170.0
const HAND_INK := Color("0e1f4a")
const HAND_SHADE := Color("dfe5f2")
const HAND_OUTLINE := 6.0

var target: Control
var glow: Control
## 1: the glove comes from the button's lower right, -1 its lower left; 0 picks by the button's side of the screen.
var hand_side := 0
var _t := 0.0
var _intro := true
var _stopped := false

## The glove's shapes (fingertip at the origin, finger up), built once.
static var _shapes: Dictionary = {}


## The highlight on `button`, its overlay in `screen` (see the head).
static func attach(button: Control, screen: Control) -> Control:
	var s: GDScript = load(SELF_PATH)
	var h: Control = s.new()
	h.name = "TutorHighlight"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.call("retarget", button)
	h.set("_intro", true)
	screen.add_child.call_deferred(h)
	return h


## Moves the highlight to `button` (null: it waits hidden for one); the glow follows it, the entrance does not replay.
func retarget(button: Control) -> void:
	if target and is_instance_valid(target) and target != button:
		_release(target)
	if glow and is_instance_valid(glow):
		glow.queue_free()
	glow = null
	target = button
	_intro = false
	if button == null or _stopped:
		return
	button.set_meta("highlight", true)
	glow = Control.new()
	glow.name = "TutorGlow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.draw.connect(_draw_glow)
	# under the button, in the nearest parent that lays nothing out
	var child: Node = button
	var host: Node = button.get_parent()
	while host is Container and host.get_parent() != null:
		child = host
		host = host.get_parent()
	if host is Control:
		host.add_child(glow)
		host.move_child(glow, child.get_index())
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.top_level = false


## The highlight off for good: the button back to its size, the glow and the overlay freed.
func stop() -> void:
	if _stopped:
		return
	_stopped = true
	if target and is_instance_valid(target):
		_release(target)
	target = null
	if glow and is_instance_valid(glow):
		glow.queue_free()
	glow = null
	queue_free()


## Whether the highlight shows (a button to show it on, not stopped).
func is_on() -> bool:
	return not _stopped and target != null and is_instance_valid(target) and target.is_visible_in_tree()


func _release(b: Control) -> void:
	b.scale = Vector2.ONE
	if b.has_meta("highlight"):
		b.remove_meta("highlight")


func _process(delta: float) -> void:
	if _stopped:
		return
	_t += delta
	if target == null or not is_instance_valid(target):
		target = null
		visible = false
		return
	visible = target.is_visible_in_tree()
	# the button's size: the entrance's overshoot, then the pulse (set every frame: a Container resets it when it sorts)
	var s := BASE + SWING * sin(TAU * PULSE_HZ * _t)
	if _intro and _t < INTRO_S:
		s = 1.0 + (BASE - 1.0) * _back_out(_t / INTRO_S)
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2(s, s)
	queue_redraw()
	if glow and is_instance_valid(glow):
		glow.queue_redraw()


static func _back_out(f: float) -> float:
	var c1 := 2.4
	var c3 := c1 + 1.0
	var x := f - 1.0
	return 1.0 + c3 * x * x * x + c1 * x * x


## The button's rect as `on` sees it (its scale and pivot counted).
func _rect_in(on: CanvasItem) -> Rect2:
	var xf := on.get_global_transform().affine_inverse() * target.get_global_transform()
	return xf * Rect2(Vector2.ZERO, target.size)


## The breath of the glow (0..1), in step with the pulse.
func _breath() -> float:
	return 0.5 + 0.5 * sin(TAU * PULSE_HZ * _t)


func _draw_glow() -> void:
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	var r := _rect_in(glow)
	var b := _breath()
	var k := clampf(_t / INTRO_S, 0.0, 1.0) if _intro else 1.0
	for i in GLOW_LAYERS:
		var f := float(i + 1) / float(GLOW_LAYERS)
		var grow := GLOW_REACH * f * (0.8 + 0.2 * b)
		var a := GLOW_ALPHA * (1.0 - f * 0.85) * (0.7 + 0.3 * b) * k
		_round_rect(glow, r.grow(grow), 12.0 + grow, Color(GLOW, a))


## The crisp rim round the button, breathing with the pulse.
func _draw_rim(r: Rect2) -> void:
	var b := _breath()
	var k := clampf(_t / INTRO_S, 0.0, 1.0) if _intro else 1.0
	var rim := r.grow(RIM_OUT + 3.0 * b)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(int(RIM))
	sb.border_color = Color(GLOW.lightened(0.3), (0.6 + 0.4 * b) * k)
	sb.set_corner_radius_all(int(10.0 + RIM_OUT))
	sb.anti_aliasing = true
	sb.draw(get_canvas_item(), rim)


static func _round_rect(on: CanvasItem, r: Rect2, radius: float, c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	sb.draw(on.get_canvas_item(), r)


func _draw() -> void:
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	var r := _rect_in(self)
	_draw_rim(r)
	_draw_shine(r)
	_draw_hand(r)


## The shine: a slanted band of light crossing the face left to right, cut to the face.
func _draw_shine(r: Rect2) -> void:
	var ph := fmod(_t, SHINE_EVERY)
	if ph > SHINE_S:
		return
	var k := ph / SHINE_S
	var face := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var bw := r.size.x * SHINE_W
	var slant := r.size.y * 0.55
	var x := lerpf(r.position.x - bw - slant, r.end.x + slant, k)
	for band: Array in [[1.0, 0.2], [0.42, 0.38]]:
		var w := bw * float(band[0])
		var x0 := x + (bw - w) * 0.5
		var poly := PackedVector2Array([Vector2(x0 + slant, r.position.y), Vector2(x0 + slant + w, r.position.y),
			Vector2(x0 + w, r.end.y), Vector2(x0, r.end.y)])
		for p: PackedVector2Array in Geometry2D.intersect_polygons(poly, face):
			draw_colored_polygon(p, Color(1, 1, 1, float(band[1])))


## The side the glove comes from: hand_side, else the button's side of the screen.
func side() -> int:
	if hand_side != 0:
		return hand_side
	var r := _rect_in(self)
	return 1 if r.get_center().x < size.x * 0.5 else -1


## The glove: its fingertip on the button, drawn back and in again PULSE_HZ times a second, a ripple at each touch.
func _draw_hand(r: Rect2) -> void:
	var sd := side()
	var tip := r.position + r.size * Vector2(TIP.x if sd > 0 else 1.0 - TIP.x, TIP.y)
	# leaning over when the screen's foot is near: the glove's whole length stays on screen
	var reach := (HAND_LEN + HAND_BACK) * HAND_SCALE
	var room := size.y - tip.y - 12.0
	var tilt := clampf(acos(clampf(room / reach, 0.0, 1.0)), HAND_TILT, HAND_TILT_MAX)
	var ang := -tilt * float(sd)
	# the finger's way out from the button: up the finger is (sin a, -cos a), the glove draws back the other way
	var up := Vector2(sin(ang), -cos(ang))
	var ph := fmod(_t * PULSE_HZ, 1.0)
	var back := HAND_BACK * (0.5 - 0.5 * cos(TAU * ph))
	if _intro and _t < INTRO_S:
		back += 120.0 * pow(1.0 - _t / INTRO_S, 2.0)
	var at := tip - up * back
	# the ripple: a ring growing from the fingertip after each touch
	if ph < 0.6:
		var q := ph / 0.6
		draw_arc(tip, 12.0 + 54.0 * q, 0.0, TAU, 40, Color(1, 1, 1, 0.7 * (1.0 - q)), 5.0 * (1.0 - q) + 1.5, true)
	var sh := _hand_shapes()
	var sc := Vector2(float(sd) * HAND_SCALE, HAND_SCALE)
	# its shadow, its ink, its white
	draw_set_transform(at + Vector2(7, 10), ang, sc)
	for p: PackedVector2Array in sh["outline"]:
		draw_colored_polygon(p, Color(0, 0, 0, 0.3))
	draw_set_transform(at, ang, sc)
	for p: PackedVector2Array in sh["outline"]:
		draw_colored_polygon(p, HAND_INK)
	for key: String in ["finger", "fist", "cuff"]:
		draw_colored_polygon(sh[key], Color.WHITE)
	# the shade down the far side of the fist, the thumb over it, the creases of the curled fingers, the cuff's seam
	draw_colored_polygon(sh["shade"], HAND_SHADE)
	draw_colored_polygon(sh["thumb_ink"], HAND_INK)
	draw_colored_polygon(sh["thumb"], Color.WHITE)
	for y: float in [86.0, 106.0]:
		draw_line(Vector2(14.0, y), Vector2(40.0, y), HAND_INK, 4.0, true)
	draw_line(Vector2(-24.0, 132.0), Vector2(48.0, 132.0), HAND_INK, 4.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The glove's polygons, fingertip at (0, 0), the finger pointing up (-y): the finger, the fist, the cuff, their joined
## outline, the shade, the thumb and its ink.
static func _hand_shapes() -> Dictionary:
	if not _shapes.is_empty():
		return _shapes
	var finger := _capsule(Vector2(0.0, 15.0), Vector2(0.0, 80.0), 15.0)
	var fist := _rounded(Rect2(-24.0, 58.0, 72.0, 76.0), 22.0)
	var cuff := _rounded(Rect2(-22.0, 130.0, 68.0, 26.0), 6.0)
	var whole := finger
	for p: PackedVector2Array in [fist, cuff]:
		var m := Geometry2D.merge_polygons(whole, p)
		whole = m[0] if not m.is_empty() else whole
	_shapes["outline"] = Geometry2D.offset_polygon(whole, HAND_OUTLINE, Geometry2D.JOIN_ROUND)
	_shapes["finger"] = finger
	_shapes["fist"] = fist
	_shapes["cuff"] = cuff
	var shade := Geometry2D.intersect_polygons(fist, _rounded(Rect2(30.0, 58.0, 30.0, 76.0), 4.0))
	_shapes["shade"] = shade[0] if not shade.is_empty() else PackedVector2Array()
	var thumb := _capsule(Vector2(-26.0, 112.0), Vector2(-6.0, 80.0), 12.0)
	_shapes["thumb"] = thumb
	var ti := Geometry2D.offset_polygon(thumb, HAND_OUTLINE * 0.75, Geometry2D.JOIN_ROUND)
	_shapes["thumb_ink"] = ti[0] if not ti.is_empty() else thumb
	return _shapes


## A capsule from `a` to `b`, `r` round.
static func _capsule(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var out := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		var t := PI * float(i) / float(steps)
		out.append(b + (n * cos(t) + d * sin(t)) * r)
	for i in steps + 1:
		var t := PI * float(i) / float(steps)
		out.append(a + (-n * cos(t) - d * sin(t)) * r)
	return out


## A rectangle with its corners `rad` round.
static func _rounded(rc: Rect2, rad: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cs := [[rc.end.x - rad, rc.position.y + rad, -PI * 0.5], [rc.end.x - rad, rc.end.y - rad, 0.0],
		[rc.position.x + rad, rc.end.y - rad, PI * 0.5], [rc.position.x + rad, rc.position.y + rad, PI]]
	for c: Array in cs:
		for i in 7:
			var t := float(c[2]) + PI * 0.5 * float(i) / 6.0
			out.append(Vector2(float(c[0]), float(c[1])) + Vector2(cos(t), sin(t)) * rad)
	return out
