## Pass 126 (lane STAGE; Garry: The Dust Bowl, "Add a brown fog effect (without damping the view distance too much or killing
## performance) to imitate a dust storm"): the rolling haze of a stage's `weather.haze` block, one full-screen quad
## (core/shaders/dust_haze.gdshader: one draw call, two samples of one small noise). Made by the map with nothing in it: the
## quad is built the first time a stage asks for it and is hidden, its _process off, on any stage without one, so the
## other stages draw nothing and pay nothing. Only the look: nothing reads it.
##
## The block (`DEFAULTS` fill what it leaves out; numbers in the map's JSON, RedCanyon.set_weather hands it here):
##   color        the dust's colour
##   strength     the layer's alpha at the thick of a band (0 = off)
##   floor        the share of `strength` left between the bands
##   wind         [x, z] the way the bands slide (made unit)
##   speed        m/s the broad band slides; the fine one at 2.1 x
##   tile         [along, across] the wind, metres of ground one tile of the broad band covers
##   hero_clear   the share of the layer left where the hero stands
##   clear_near, clear_far   metres from him where it starts to come back and where it is whole
class_name DustHaze
extends Node3D

const SHADER := preload("res://core/shaders/dust_haze.gdshader")
const NOISE := preload("res://art/fx/fire_noise.png")
## Before the stage's filter (-7) and the gusts and the tornado (-8), after the water (-10).
const PRIORITY := StageLook.PRIORITY - 2
const DEFAULTS := {"color": "#A87C4A", "strength": 0.3, "floor": 0.35, "wind": [1.0, 0.3], "speed": 6.0, "tile": [110.0, 42.0],
	"hero_clear": 0.45, "clear_near": 5.0, "clear_far": 16.0}

var game: Node
var quad: MeshInstance3D
var clock := 0.0
var _mat: ShaderMaterial
var _amount := 0.0
var _tween: Tween


func _ready() -> void:
	set_process(false)


## The block whole, every key filled and in range ({} or strength 0: `on` false).
static func config_of(block) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if block is Dictionary:
		for k in (block as Dictionary):
			out[k] = block[k]
	out["strength"] = clampf(_num(out["strength"], 0.3), 0.0, 1.0)
	out["floor"] = clampf(_num(out["floor"], 0.35), 0.0, 1.0)
	out["speed"] = _num(out["speed"], 6.0)
	out["hero_clear"] = clampf(_num(out["hero_clear"], 0.45), 0.0, 1.0)
	out["clear_near"] = maxf(_num(out["clear_near"], 5.0), 0.0)
	out["clear_far"] = maxf(_num(out["clear_far"], 16.0), float(out["clear_near"]) + 0.01)
	out["wind"] = _vec2(out["wind"], Vector2(1.0, 0.3)).normalized()
	var t := _vec2(out["tile"], Vector2(110.0, 42.0))
	out["tile"] = Vector2(maxf(t.x, 1.0), maxf(t.y, 1.0))
	out["color"] = WaveTimeline.color_of(out["color"], Color("#A87C4A"))
	out["on"] = block is Dictionary and not (block as Dictionary).is_empty() and float(out["strength"]) > 0.0
	return out


## This stage's haze: on over `seconds` from `block`, off (hidden, no _process) when it says nothing.
func apply(block, seconds: float = 0.0) -> void:
	var c := config_of(block)
	if _tween:
		_tween.kill()
		_tween = null
	if not bool(c["on"]):
		if quad == null or not quad.visible:
			return
		if seconds <= 0.0 or not is_inside_tree():
			_off()
			return
		_tween = create_tween()
		_tween.tween_method(_set_amount, _amount, 0.0, seconds)
		_tween.tween_callback(_off)
		return
	if quad == null:
		_build()
	_mat.set_shader_parameter("color", c["color"])
	_mat.set_shader_parameter("strength", c["strength"])
	_mat.set_shader_parameter("floor_share", c["floor"])
	_mat.set_shader_parameter("wind", c["wind"])
	_mat.set_shader_parameter("speed", c["speed"])
	_mat.set_shader_parameter("tile", c["tile"])
	_mat.set_shader_parameter("hero_clear", c["hero_clear"])
	_mat.set_shader_parameter("clear_r", Vector2(float(c["clear_near"]), float(c["clear_far"])))
	quad.visible = true
	set_process(true)
	if seconds <= 0.0 or not is_inside_tree():
		_set_amount(1.0)
		return
	_tween = create_tween()
	_tween.tween_method(_set_amount, _amount, 1.0, seconds)


## Whether it draws now.
func showing() -> bool:
	return quad != null and quad.visible


func _off() -> void:
	_set_amount(0.0)
	if quad:
		quad.visible = false
	set_process(false)


func _set_amount(f: float) -> void:
	_amount = f
	if _mat:
		_mat.set_shader_parameter("amount", f)


func _build() -> void:
	quad = MeshInstance3D.new()
	quad.name = "HazeQuad"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	quad.mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = PRIORITY
	_mat.set_shader_parameter("noise_tex", NOISE)
	quad.material_override = _mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 16384.0
	quad.ignore_occlusion_culling = true
	quad.visible = false
	add_child(quad)


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt); it stops with the game's pause
	delta = Lockstep.dt(delta)
	if game != null and bool(game.get("paused")):
		return
	clock += delta
	_mat.set_shader_parameter("clock", clock)
	var pl = game.get("player") if game != null else null
	if pl is Node3D:
		var p: Vector3 = (pl as Node3D).global_position
		_mat.set_shader_parameter("hero_xz", Vector2(p.x, p.z))


static func _num(v, fallback: float) -> float:
	return float(v) if (v is float or v is int) else fallback


static func _vec2(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback
