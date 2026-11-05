## Gusts of dusty wind (pass 44), purely for the look: every nine to sixteen seconds a front of soft sand streaks sweeps
## across the ground around the hero along the wind, with puffs of sand kicked up where it passes and a sigh of wind.
## One MultiMesh of flat quads with a drawn streak texture, laid on the terrain; nothing touches the game.
## Pass 126 (lane STAGE; Garry: "Make the wind visual vfx effect stronger looking on this map only"): a stage's `weather.gust`
## block (set_storm; RedCanyon.set_weather) turns the gusts into a storm: no fronts with calm between, a steady stream of
## longer, faster streaks each on its own clock, swelling and falling together, more puffs of sand, the sigh of wind every
## few seconds. Still the one MultiMesh (instance_count grows to `streaks`). A stage without a block plays the gusts above to
## the number. The block's keys and defaults are STORM_DEFAULTS.
class_name DustGust
extends Node3D

const STORM_SHADER := preload("res://core/shaders/gust_streak.gdshader")
const STORM_DEFAULTS := {"streaks": 56, "life": 2.4, "speed": 21.0, "len": [9.0, 16.0], "wid": [1.3, 2.6], "alpha": 0.62,
	"lanes": 20.0, "turn": 0.45, "swell": 0.35, "puff_every": 0.11, "puff_size": 0.9, "sound_every": [5.0, 9.0], "color": "#EDCF99"}

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
## Pass 126: the storm's numbers ({}: the gusts as ever) and each streak's own clock, line and shape.
var storm: Dictionary = {}
var _s_n := 0
var _s_age := PackedFloat32Array()
var _s_life := PackedFloat32Array()
var _s_org := PackedVector3Array()
var _s_dir := PackedVector3Array()
var _s_y := PackedFloat32Array()
var _s_basis: Array[Basis] = []
var _s_clock := 0.0
var _s_sound := 2.0
var _s_frame := 0
var _mmi: MultiMeshInstance3D
var _plain_mat: Material
var _storm_mat: ShaderMaterial


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
	# pass 87 (lane SLOOK): drawn before the stage's filter (StageLook.PRIORITY), so an evening or a blood moon tints the
	# gust like the sand it blows over (it was 2, after the filter: a pale veil over a dark stage); still over the water
	mat.render_priority = StageLook.PRIORITY - 1
	mmi.material_override = mat
	_mmi = mmi
	_plain_mat = mat
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
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt): the camera and what is on screen follow it
	delta = Lockstep.dt(delta)
	if game == null or map == null:
		return
	if bool(game.get("paused")):
		return
	var pl: Node3D = game.player
	if pl == null:
		return
	if not storm.is_empty():
		_storm_tick(delta, pl.global_position)
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


# ---------------------------------------------------------------- a stage's storm (pass 126, lane STAGE)

## The block whole, every key filled and in range; {} for no block.
static func storm_config(block) -> Dictionary:
	if not (block is Dictionary) or (block as Dictionary).is_empty():
		return {}
	var out: Dictionary = STORM_DEFAULTS.duplicate(true)
	for k in (block as Dictionary):
		out[k] = block[k]
	out["streaks"] = clampi(int(out["streaks"]), 1, 200)
	out["life"] = maxf(float(out["life"]), 0.2)
	out["speed"] = maxf(float(out["speed"]), 0.0)
	out["len"] = BarrelSpawns.range_of(out["len"], Vector2(9.0, 16.0))
	out["wid"] = BarrelSpawns.range_of(out["wid"], Vector2(1.3, 2.6))
	out["sound_every"] = BarrelSpawns.range_of(out["sound_every"], Vector2(5.0, 9.0))
	out["alpha"] = clampf(float(out["alpha"]), 0.0, 1.0)
	out["swell"] = clampf(float(out["swell"]), 0.0, 1.0)
	out["lanes"] = maxf(float(out["lanes"]), 1.0)
	out["turn"] = float(out["turn"])
	out["puff_every"] = float(out["puff_every"])
	out["puff_size"] = float(out["puff_size"])
	out["color"] = WaveTimeline.color_of(out["color"], Color("#EDCF99"))
	return out


## This stage's storm from `block`, or the gusts as ever ({}: back to STREAKS and the fronts).
func set_storm(block) -> void:
	var was_on := not storm.is_empty()
	storm = storm_config(block)
	if _mm == null or (storm.is_empty() and not was_on):
		return
	_t = -1.0
	_next = randf_range(4.0, 9.0)
	_mm.visible_instance_count = 0
	if storm.is_empty():
		_s_n = 0
		if _mm.instance_count != STREAKS:
			_mm.instance_count = STREAKS
			_mm.visible_instance_count = 0
		_mmi.material_override = _plain_mat
		return
	# feathered on every side and laid over the dunes rather than cut by them (core/shaders/gust_streak.gdshader)
	if _storm_mat == null:
		_storm_mat = ShaderMaterial.new()
		_storm_mat.shader = STORM_SHADER
		_storm_mat.render_priority = StageLook.PRIORITY - 1
	_mmi.material_override = _storm_mat
	_s_n = int(storm["streaks"])
	if _mm.instance_count != _s_n:
		_mm.instance_count = _s_n
	_mm.visible_instance_count = 0
	_s_age.resize(_s_n)
	_s_life.resize(_s_n)
	_s_org.resize(_s_n)
	_s_dir.resize(_s_n)
	_s_y.resize(_s_n)
	_s_basis.resize(_s_n)
	_s_clock = 0.0
	_s_sound = 2.0
	# the first of each is already on its way: the storm is blowing when the stage opens
	for k in _s_n:
		_s_life[k] = -1.0


## One streak on a new line: upwind of the hero, in a lane across the wind, the wind's way turned a little by the storm's
## slow swing, `age` seconds along.
func _streak_new(k: int, hero: Vector3, age: float) -> void:
	var swing := sin(_s_clock * 0.17) * float(storm["turn"]) + randf_range(-0.1, 0.1)
	var d := wind.rotated(Vector3.UP, swing).normalized()
	var side := Vector3(-d.z, 0.0, d.x)
	var life := float(storm["life"]) * randf_range(0.8, 1.2)
	var sp := float(storm["speed"])
	_s_dir[k] = d
	_s_life[k] = life
	_s_age[k] = age
	_s_org[k] = hero - d * (sp * life * 0.5 + randf_range(-6.0, 6.0)) + side * randf_range(-float(storm["lanes"]), float(storm["lanes"]))
	var ln: Vector2 = storm["len"]
	var wd: Vector2 = storm["wid"]
	_s_basis[k] = Basis(Vector3.UP, atan2(d.x, d.z)) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis().scaled(Vector3(randf_range(wd.x, wd.y), randf_range(ln.x, ln.y), 1.0))
	_s_y[k] = map.height_at(_s_org[k].x, _s_org[k].z) + 0.35


func _storm_tick(delta: float, hero: Vector3) -> void:
	if Run.sim_mode:
		return
	_s_clock += delta
	_s_frame += 1
	if _mm.visible_instance_count != _s_n:
		_mm.visible_instance_count = _s_n
	var sp := float(storm["speed"])
	var c: Color = storm["color"]
	# the whole storm swells and falls: never calm, never even
	var swell := 1.0 - float(storm["swell"]) * (0.5 + 0.5 * sin(_s_clock * 0.9) * sin(_s_clock * 0.37 + 1.0))
	var base_a := float(storm["alpha"]) * swell
	for k in _s_n:
		if _s_life[k] < 0.0:
			_streak_new(k, hero, randf() * float(storm["life"]))
		_s_age[k] += delta
		if _s_age[k] >= _s_life[k]:
			_streak_new(k, hero, 0.0)
		var p: Vector3 = _s_org[k] + _s_dir[k] * (sp * _s_age[k])
		# the ground under it, a quarter of the streaks a frame (the height a metre on barely moves)
		if (k + _s_frame) % 4 == 0:
			_s_y[k] = map.height_at(p.x, p.z) + 0.35
		p.y = _s_y[k]
		_mm.set_instance_transform(k, Transform3D(_s_basis[k], p))
		var a := sin(PI * _s_age[k] / _s_life[k]) * base_a * (0.82 + 0.18 * sin(float(k) * 1.7))
		_mm.set_instance_color(k, Color(c.r, c.g, c.b, a))
	# sand kicked up along the streaks
	_puff_t -= delta
	var pe := float(storm["puff_every"])
	if pe > 0.0 and _puff_t <= 0.0 and game.fx:
		_puff_t = pe
		var n := randi() % _s_n
		var q: Vector3 = _s_org[n] + _s_dir[n] * (sp * _s_age[n])
		if Vector2(q.x - hero.x, q.z - hero.z).length() < 24.0:
			q.y = _s_y[n] - 0.35
			game.fx.sand(q, float(storm["puff_size"]))
	_s_sound -= delta
	if _s_sound <= 0.0:
		var se: Vector2 = storm["sound_every"]
		_s_sound = randf_range(se.x, se.y)
		Audio.play("wd_gust", hero)
