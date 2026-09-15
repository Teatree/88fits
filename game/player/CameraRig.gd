## The camera. Two modes, switched live from Settings.camera_mode:
##  0 fixed  north is always up, like Archero and Survivor.io: the world never rotates, the stick maps 1:1 to the
##           screen, and the camera is bolted to the player (no lead, no lag), the way those games do it; only hits shake it.
##  1 follow the chase camera behind the hero, yaw following the facing through a damped spring with a dead zone.
## Both ride the terrain height and shake.
class_name CameraRig
extends Node3D

@export_group("Fixed (north up)")
@export var fixed_pitch_deg := 46.0
@export var fixed_distance := 20.5
@export var fixed_fov := 55.0
@export var fixed_lead := 0.0
## Metres the focus sits north of the hero, so he stands a little below the screen centre and sees more ahead.
@export var fixed_focus_ahead := 3.0
@export_group("Follow (chase)")
@export var follow_pitch_deg := 50.0
@export var follow_distance := 19.5
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


## Yaw the player maps stick directions through (0 in fixed mode: screen up is world -Z).
func current_yaw() -> float:
	return yaw


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _process(delta: float) -> void:
	if target == null:
		return
	_update(delta)


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
	_height = lerpf(_height, target.global_position.y, clampf(delta * 4.0, 0.0, 1.0))
	var want := Vector3(target.global_position.x, _height, target.global_position.z) + _lead_dir * lead
	if fixed:
		want += Vector3(0, 0, -fixed_focus_ahead)
	_focus = want if (delta >= 1.0 or fixed) else _damp_vec(_focus, want, focus_smooth_time, delta)
	var back := -_forward() * cos(pitch) * distance
	var up := Vector3(0, sin(pitch) * distance, 0)
	var cam_pos := _focus + back + up
	if _shake > 0.001:
		_shake_vec = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.35
		_shake = lerpf(_shake, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	else:
		_shake_vec = Vector3.ZERO
	global_position = cam_pos + _shake_vec
	look_at(_focus + _shake_vec * 0.5, Vector3.UP)
