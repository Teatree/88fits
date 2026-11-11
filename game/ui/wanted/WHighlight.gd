## The tutorial's highlight on one button (pass 137, lane TUTOR; Garry: "a big fat highlight of the Upgrade button", "the
## Buy button is highlighted the same way until the first tap"): the button grows to BASE with a small overshoot and
## pulses round it, a warm glow breathes round its edge (drawn under it), a shine crosses its face every SHINE_EVERY
## seconds, and a hand points at it, tapping it with a ripple at the fingertip. The Results' UPGRADE and the
## Trail's BUY wear it. Pass 141 (lane SMALL; Garry: "Tutorial Finger - get a normal looking finger please, this looks
## bad"): the hand is a painted picture (HAND_TEX, tools/gen_tutorial_hand.py: Flux.2 Klein on the style anchor, picked
## by eye) in place of pass 137's white glove drawn in code; the motion is the same. No class_name: load it by path,
##     var hl: Control = load("res://ui/wanted/WHighlight.gd").attach(button, screen)
## `screen` takes the overlay (the shine, the hand) as its last child, a frame later (so the tab bar a screen adds after
## its build() is under it, and a pop-up opened later is over it); the glow goes under the button in its nearest parent
## that is not a Container (a Container would lay it out). `retarget(button)` moves it to another button (the Trail's
## dock rebuilt) without the entrance again; `stop()` ends it for good (the button back to its size, the nodes freed).
## The hand comes from the lower right of a button in the screen's left half and from the lower left of one in its right
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
## The hand: its size (1 = HAND_H px tall on the 1080 canvas), the fingertip's place on the button (fractions of
## its rect, mirrored for a hand from the left), how far it draws back between taps, its angle off upright: HAND_TILT,
## leaning further (up to HAND_TILT_MAX) when the screen's foot is too near for it to stand whole (the Results' row);
## HAND_LEN its length from the fingertip down.
const HAND_SCALE := 1.0
const TIP := Vector2(0.64, 0.55)
const HAND_BACK := 26.0
const HAND_TILT := 0.6
const HAND_TILT_MAX := 1.3
const HAND_LEN := 195.0
## Pass 141: the painted hand (a right hand seen from the back, the index finger pointing straight up; mirrored for a
## hand from the left), drawn HAND_H px tall with its fingertip, HAND_TIP_PX in the picture's pixels, on the button's
## tip point; its shadow the same picture in black at HAND_SHADOW, HAND_SHADOW_AT px down and right. A new picture
## (tools/gen_tutorial_hand.py --pick N) prints its fingertip for HAND_TIP_PX.
const HAND_TEX := "res://art/ui/tutorial/hand.png"
const HAND_TIP_PX := Vector2(76, 9)
const HAND_H := 200.0
const HAND_SHADOW := Color(0, 0, 0, 0.3)
const HAND_SHADOW_AT := Vector2(7, 10)

var target: Control
var glow: Control
## 1: the hand comes from the button's lower right, -1 its lower left; 0 picks by the button's side of the screen.
var hand_side := 0
var _t := 0.0
var _intro := true
var _stopped := false

## The hand's picture, loaded once (hand_texture).
static var _hand_tex: Texture2D


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


## The side the hand comes from: hand_side, else the button's side of the screen.
func side() -> int:
	if hand_side != 0:
		return hand_side
	var r := _rect_in(self)
	return 1 if r.get_center().x < size.x * 0.5 else -1


## The hand: its fingertip on the button, drawn back and in again PULSE_HZ times a second, a ripple at each touch.
func _draw_hand(r: Rect2) -> void:
	var sd := side()
	var tip := r.position + r.size * Vector2(TIP.x if sd > 0 else 1.0 - TIP.x, TIP.y)
	# leaning over when the screen's foot is near: the hand's whole length stays on screen
	var reach := (HAND_LEN + HAND_BACK) * HAND_SCALE
	var room := size.y - tip.y - 12.0
	var tilt := clampf(acos(clampf(room / reach, 0.0, 1.0)), HAND_TILT, HAND_TILT_MAX)
	var ang := -tilt * float(sd)
	# the finger's way out from the button: up the finger is (sin a, -cos a), the hand draws back the other way
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
	var tex := hand_texture()
	if tex == null:
		return
	# the picture HAND_H tall, its fingertip at the origin (mirrored about it for a hand from the left): its shadow, then it
	var k := HAND_H * HAND_SCALE / maxf(1.0, float(tex.get_height()))
	var sc := Vector2(float(sd) * k, k)
	var rc := Rect2(-HAND_TIP_PX, tex.get_size())
	draw_set_transform(at + HAND_SHADOW_AT, ang, sc)
	draw_texture_rect(tex, rc, false, HAND_SHADOW)
	draw_set_transform(at, ang, sc)
	draw_texture_rect(tex, rc, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The hand's picture (HAND_TEX), loaded once; null when it is missing (the hand is then left out).
static func hand_texture() -> Texture2D:
	if _hand_tex == null and ResourceLoader.exists(HAND_TEX):
		_hand_tex = load(HAND_TEX) as Texture2D
	return _hand_tex
