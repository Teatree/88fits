## The camera. Two modes, switched live from Settings.camera_mode:
##  0 fixed  north is always up, like Archero and Survivor.io: the world never rotates, the stick maps 1:1 to the
##           screen, and the camera is bolted to the player (no lead, no lag), the way those games do it; only hits shake it.
##  1 follow the chase camera behind the hero, yaw following the facing through a damped spring with a dead zone.
## Both ride the terrain height and shake.
class_name CameraRig
extends Node3D

@export_group("Fixed (north up)")
@export var fixed_pitch_deg := 46.0
@export var fixed_distance := 22.5
@export var fixed_fov := 55.0
@export var fixed_lead := 0.0
## Metres the focus sits north of the hero, so he stands a little below the screen centre and sees more ahead.
@export var fixed_focus_ahead := 3.3
## The camera backs off as the hero moves faster: distance x (1 + log(speed / walk) / log(zoom_at_ratio)), capped at
## zoom_max (x2 at four times the walking speed), eased so a sprint start does not jump.
@export var zoom_max := 2.6
## the build's own pull on the zoom: every hero level past the first adds this much, to `zoom_power_max`
@export var zoom_per_level := 0.02
@export var zoom_power_max := 0.7
@export var zoom_at_ratio := 4.0
@export var walk_speed := 3.6
## how much of that pull-out is kept (pass 33.7: the zoom was too extreme, 30% less of it): the speed's and the level's
## pull both scale by it, and so does the cap (2.6 becomes 1 + 1.6 x 0.7 = 2.12)
@export var zoom_amount := 0.7
var _zoom := 1.0
## a tool's hand on the zoom (the capture's far-zoom frame): > 0 holds it there (pass 110: exported, so the editor's
## Remote inspector can set it while the game runs; 1 = the base distance, below 1 nearer)
@export var zoom_override := 0.0
## Screenshot framing (pass 110, lane ARENA; Garry: "everything above [a caption band] centered around the Player
## hero"): where the hero's middle (FRAME_HERO_MID m above his feet) sits on the screen, as a share of its height from
## the top (0.5 = the centre; 0.35 = the centre of what lies above a 30 % caption band). Below 0 = off: the fixed
## camera's own fixed_focus_ahead (every run). Read every frame, so nothing in the game pulls it back; the debug arena's
## SHOTS tab and its FRAME button set it, and so can the editor's Remote inspector while the game runs.
@export_range(-1.0, 0.95, 0.01) var frame_hero_y := -1.0
const FRAME_HERO_MID := 0.9
@export_group("Follow (chase)")
@export var follow_pitch_deg := 50.0
@export var follow_distance := 21.5
@export var follow_fov := 60.0
@export var follow_lead := 1.5
## Seconds the yaw needs to catch up with a turn. Bigger = lazier camera.
@export var yaw_smooth_time := 0.85
## Turns smaller than this many degrees are ignored, so wobbly steering does not rock the world.
@export var yaw_deadzone_deg := 4.0
@export_group("")
## Seconds the focus point needs to catch up with the player (softens knockback jolts).
@export var focus_smooth_time := 0.16

@onready var camera: Camera3D = $Camera3D

var target: Node3D
var yaw := 0.0
var _yaw_vel := 0.0
var _height := 0.0
var _focus := Vector3.ZERO
var _focus_vel := Vector3.ZERO
var _lead_dir := Vector3.ZERO
var _shake := 0.0
var _shake_vec := Vector3.ZERO
## the rig's transform before the shake (hero_anchor projects through it, so the HUD's bars do not shake)
var _rest_xf := Transform3D()


func _ready() -> void:
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.far = 260.0
	camera.fov = fixed_fov if _mode() == 0 else follow_fov


func _mode() -> int:
	return int(Settings.camera_mode)


func snap_to(t: Node3D) -> void:
	target = t
	yaw = (t.facing if "facing" in t else 0.0) if _mode() == 1 else 0.0
	_yaw_vel = 0.0
	_height = t.global_position.y
	_focus = t.global_position
	_focus_vel = Vector3.ZERO
	_lead_dir = Vector3.ZERO
	_update(1.0)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount * Settings.screen_shake)


## Where the hero's feet sit on the screen with the camera at rest (no shake), in canvas pixels, and how many pixels a
## metre spans there (pass 33.6): the HUD draws his health and shield bars from it. The fixed camera is bolted to him,
## so the spot only moves as the zoom does, and the pixels per metre shrink with the zoom like his sprite does.
func hero_anchor() -> Dictionary:
	var vp := get_viewport().get_visible_rect().size
	var feet: Vector3 = target.global_position if target else _focus
	var local: Vector3 = _rest_xf.affine_inverse() * feet
	var depth := -local.z
	if depth < 0.1 or vp.y <= 0.0:
		return {"pos": Vector2(vp.x * 0.5, vp.y * 0.6), "ppm": 90.0}
	# keep_aspect is KEEP_HEIGHT: the fov spans the canvas's height
	var ppm: float = (vp.y * 0.5) / (depth * tan(deg_to_rad(camera.fov) * 0.5))
	return {"pos": Vector2(vp.x * 0.5 + local.x * ppm, vp.y * 0.5 - local.y * ppm), "ppm": ppm}


## Whether the point `p` shows on the screen, or within `margin_px` canvas pixels of its edge (pass 54: the ranged
## weapons aim only at what is on the screen, EnemyManager.refresh_onscreen). True with no camera (tools, tests).
func on_screen(p: Vector3, margin_px: float = 0.0) -> bool:
	if camera == null:
		return true
	if camera.is_position_behind(p):
		return false
	return get_viewport().get_visible_rect().grow(margin_px).has_point(camera.unproject_position(p))


## How many canvas pixels a metre spans at the hero's feet right now (pass 54: the on-screen test's one-metre margin
## shrinks as the camera pulls out); 90 without a target.
func pixels_per_metre() -> float:
	if target == null or camera == null:
		return 90.0
	return float(hero_anchor().get("ppm", 90.0))


## Yaw the player maps stick directions through (0 in fixed mode: screen up is world -Z).
func current_yaw() -> float:
	return yaw


## How far out the camera is against its base distance (1 = base, up to zoom_max): the creatures' far-zoom marks read it.
func zoom() -> float:
	return _zoom


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	if target == null:
		Perf.add("camera", _t0)
		return
	_update(delta)
	Perf.add("camera", _t0)


## How far north of the hero the fixed camera looks (pass 110): fixed_focus_ahead, or with the screenshot framing on
## (frame_hero_y >= 0) the distance that puts his middle at that share of the screen's height at this `distance` and
## `pitch` (radians) and the camera's fov (keep_height: the fov spans the height). The camera at the focus F plus
## (0, sin p, cos p) x distance, looking at F, sees a point `a` m south of F and `h` m up at the screen's height
## n x tan(fov / 2) (n = 1 - 2 x the share, up positive) when h cos p - a sin p = n t (distance - h sin p - a cos p).
func focus_ahead(distance: float, pitch: float) -> float:
	if frame_hero_y < 0.0 or camera == null:
		return fixed_focus_ahead
	var n := 1.0 - 2.0 * clampf(frame_hero_y, 0.05, 0.95)
	var t := tan(deg_to_rad(camera.fov) * 0.5)
	var sp := sin(pitch)
	var cp := cos(pitch)
	var h := FRAME_HERO_MID
	var den := n * t * cp - sp
	if absf(den) < 0.001:
		return fixed_focus_ahead
	return (n * t * (distance - h * sp) - h * cp) / den


## Critically damped spring towards a target angle (Unity's SmoothDampAngle, wrapped for radians).
func _damp_angle(current: float, to: float, smooth_time: float, delta: float) -> float:
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * delta
	var ex := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := angle_difference(to, current)
	var goal := current - change
	var temp := (_yaw_vel + omega * change) * delta
	_yaw_vel = (_yaw_vel - omega * temp) * ex
	return goal + (change + temp) * ex


func _damp_vec(current: Vector3, to: Vector3, smooth_time: float, delta: float) -> Vector3:
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * delta
	var ex := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - to
	var temp := (_focus_vel + change * omega) * delta
	_focus_vel = (_focus_vel - temp * omega) * ex
	return to + (change + temp) * ex


func _update(delta: float) -> void:
	var fixed := _mode() == 0
	var want_fov := fixed_fov if fixed else follow_fov
	if absf(camera.fov - want_fov) > 0.01:
		camera.fov = lerpf(camera.fov, want_fov, clampf(delta * 6.0, 0.0, 1.0)) if delta < 1.0 else want_fov
	var lead := fixed_lead if fixed else follow_lead
	var pitch := deg_to_rad(fixed_pitch_deg if fixed else follow_pitch_deg)
	var distance := fixed_distance if fixed else follow_distance
	var pv: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
	pv.y = 0.0
	# speed pulls the camera out, and so does the build: a level-30 hero sees a wider field than a level-1 one, because
	# by then the fight around him is wider
	var power := clampf(float(maxi(Run.level - 1, 0)) * zoom_per_level, 0.0, zoom_power_max)
	var pull := power + log(maxf(pv.length(), walk_speed) / walk_speed) / log(zoom_at_ratio)
	var want_zoom := clampf(1.0 + pull * zoom_amount, 1.0, 1.0 + (zoom_max - 1.0) * zoom_amount)
	_zoom = want_zoom if delta >= 1.0 else lerpf(_zoom, want_zoom, clampf(delta * 1.6, 0.0, 1.0))
	if zoom_override > 0.0:
		_zoom = zoom_override
	distance *= _zoom
	if fixed:
		yaw = _damp_angle(yaw, 0.0, 0.35, delta) if delta < 1.0 else 0.0
		# lead towards where the hero is going, eased so it does not flick when he stops
		var vel: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
		vel.y = 0.0
		var want_lead := vel.normalized() if vel.length() > 0.5 else Vector3.ZERO
		_lead_dir = _lead_dir.lerp(want_lead, clampf(delta * 2.5, 0.0, 1.0)) if delta < 1.0 else want_lead
	else:
		var tyaw: float = target.facing if "facing" in target else 0.0
		var diff := angle_difference(yaw, tyaw)
		var dz := deg_to_rad(yaw_deadzone_deg)
		var goal := yaw
		if absf(diff) > dz:
			goal = tyaw - signf(diff) * dz
		yaw = tyaw if delta >= 1.0 else _damp_angle(yaw, goal, yaw_smooth_time, delta)
		_lead_dir = _forward()
	# pass 70: a hero in the air (Hang Time) names the height to ride at (Player.camera_y), so the jump shows on screen
	var ty: float = float(target.call("camera_y")) if target.has_method("camera_y") else target.global_position.y
	_height = lerpf(_height, ty, clampf(delta * 4.0, 0.0, 1.0))
	var want := Vector3(target.global_position.x, _height, target.global_position.z) + _lead_dir * lead
	if fixed:
		# (pass 110: the screenshot framing's own distance when it is on, focus_ahead)
		want += Vector3(0, 0, -focus_ahead(distance, pitch))
	_focus = want if (delta >= 1.0 or fixed) else _damp_vec(_focus, want, focus_smooth_time, delta)
	var back := -_forward() * cos(pitch) * distance
	var up := Vector3(0, sin(pitch) * distance, 0)
	var cam_pos := _focus + back + up
	if _shake > 0.001:
		_shake_vec = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.35
		_shake = lerpf(_shake, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	else:
		_shake_vec = Vector3.ZERO
	_rest_xf = Transform3D(Basis(), cam_pos).looking_at(_focus, Vector3.UP)
	global_position = cam_pos + _shake_vec
	look_at(_focus + _shake_vec * 0.5, Vector3.UP)
