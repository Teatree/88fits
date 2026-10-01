## Gusts of dusty wind (pass 44), purely for the look: every nine to sixteen seconds a front of soft sand streaks sweeps
## across the ground around the hero along the wind, with puffs of sand kicked up where it passes and a sigh of wind.
## One MultiMesh of flat quads with a drawn streak texture, laid on the terrain; nothing touches the game.
class_name DustGust
extends Node3D

const STREAKS := 22
const LIFE := 2.6
const SPEED := 13.0
const COLOR := Color(0.93, 0.78, 0.55)

var game: Node
var map: MapBase
var wind := Vector3(1, 0, 0.3).normalized()
var _mm: MultiMesh
var _next := 6.0
var _t := -1.0
var _dir := Vector3.RIGHT
var _side := Vector3.FORWARD
var _origin := Vector3.ZERO
var _lanes: PackedFloat32Array = PackedFloat32Array()
var _stagger: PackedFloat32Array = PackedFloat32Array()
var _len: PackedFloat32Array = PackedFloat32Array()
var _wid: PackedFloat32Array = PackedFloat32Array()
var _puff_t := 0.0


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_mm.mesh = quad
	_mm.instance_count = STREAKS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _streak_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	for k in STREAKS:
		_lanes.append(0.0)
		_stagger.append(0.0)
		_len.append(7.0)
		_wid.append(1.6)


## A soft streak: bright along the middle, feathered at both ends and both sides.
func _streak_texture() -> ImageTexture:
	var w := 128
	var h := 32
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (float(x) + 0.5) / w
			var v := (float(y) + 0.5) / h
			var along := pow(sin(u * PI), 1.4)
			var across := exp(-pow((v - 0.5) * 3.2, 2.0))
			# a few grainy ripples along the streak
			var grain := 0.85 + 0.15 * sin(u * 41.0 + v * 9.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(along * across * grain, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if game == null or map == null:
		return
	if bool(game.get("paused")):
		return
	var pl: Node3D = game.player
	if pl == null:
		return
	if _t < 0.0:
		_next -= delta
		if _next <= 0.0:
			_start(pl.global_position)
		return
	_t += delta
	if _t >= LIFE:
		_t = -1.0
		_mm.visible_instance_count = 0
		_next = randf_range(9.0, 16.0)
		return
	var env := sin(PI * _t / LIFE)
	for k in STREAKS:
		var along := _stagger[k] + SPEED * _t
		var wobble := sin(_t * 3.0 + float(k)) * 0.6
		var p := _origin + _dir * along + _side * (_lanes[k] + wobble)
		p.y = map.height_at(p.x, p.z) + 0.35
		var yaw := atan2(_dir.x, _dir.z)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis().scaled(Vector3(_wid[k], _len[k], 1.0))
		_mm.set_instance_transform(k, Transform3D(b, p))
		var a := env * (0.46 + 0.12 * sin(float(k) * 1.7))
		_mm.set_instance_color(k, Color(COLOR.r, COLOR.g, COLOR.b, a))
	# sand kicked up along the front
	_puff_t -= delta
	if _puff_t <= 0.0 and game.fx and env > 0.3:
		_puff_t = 0.14
		for n in 3:
			var k := randi() % STREAKS
			var p := _origin + _dir * (_stagger[k] + SPEED * _t) + _side * _lanes[k]
			p.y = map.height_at(p.x, p.z)
			game.fx.sand(p, 0.7)


## A front upwind of the hero, wide enough to cross the whole view, turned a little off the map's wind each time.
func _start(hero: Vector3) -> void:
	_t = 0.0
	_dir = wind.rotated(Vector3.UP, randf_range(-0.5, 0.5)).normalized()
	_side = Vector3(-_dir.z, 0, _dir.x)
	_origin = hero - _dir * (SPEED * LIFE * 0.5)
	for k in STREAKS:
		_lanes[k] = randf_range(-15.0, 15.0)
		_stagger[k] = randf_range(-7.0, 3.0)
		_len[k] = randf_range(5.5, 9.5)
		_wid[k] = randf_range(1.3, 2.3)
	_mm.visible_instance_count = STREAKS
	Audio.play("wd_gust", hero)
