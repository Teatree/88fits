## The Stone Golem's boulder (pass 45): a rock on a high arc from the golem to the spot it marked, turning as it flies,
## a shadow growing on the spot under it, and Game.boulder_land where it comes down. It flies on the creatures' clock
## (High Noon slows it) and never reads the hero: the red ring said where it lands.
class_name Boulder
extends Node3D

const STONE := Color(0.5, 0.46, 0.42)
const GLB := "res://art/props/boulder.glb"

static var _rock_mesh: Mesh = null

var game: Node
var from := Vector3.ZERO
var to := Vector3.ZERO
var flight := 1.6
var arc := 9.0
var cfg: Dictionary = {}
var info: Dictionary = {}
var thrower := -1
var _t := 0.0
var _axis := Vector3.RIGHT
var _spin := 7.0
var _pivot: Node3D
var _shadow := -1
var _done := false


func setup(p_game: Node, p_from: Vector3, p_to: Vector3, p_flight: float, p_cfg: Dictionary, p_info: Dictionary, p_thrower: int) -> void:
	game = p_game
	from = p_from
	to = p_to
	flight = maxf(p_flight, 0.2)
	cfg = p_cfg
	info = p_info
	thrower = p_thrower
	arc = float(cfg.get("arc", 9.0))


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh()
	var aabb := mi.mesh.get_aabb()
	var s: float = float(cfg.get("size", 1.7)) / maxf(aabb.size.x, 0.1)   # the GLB is 5.7 m across (rock(2.2) x 1.3)
	mi.scale = Vector3.ONE * s
	mi.position = -aabb.get_center() * s        # spin about the rock's middle, not the GLB's base origin
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STONE
	mat.roughness = 0.95
	mi.material_override = mat                   # one plain lit variant, already warmed by Warmup's `lit` quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(mi)
	_axis = Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3), randf_range(-1.0, 1.0))
	_axis = _axis.normalized() if _axis.length_squared() > 0.001 else Vector3.RIGHT
	global_position = from
	var tg: Node = game.get("telegraphs") if game else null
	if tg:
		_shadow = tg.hold_disc(to, 0.5, Color(0.12, 0.08, 0.05, 0.4))


## The rock's mesh, read once from the prop GLB (a sphere when the prop is missing).
static func _mesh() -> Mesh:
	if _rock_mesh:
		return _rock_mesh
	if ResourceLoader.exists(GLB):
		var packed := load(GLB) as PackedScene
		if packed:
			var scene: Node = packed.instantiate()
			var mis := scene.find_children("*", "MeshInstance3D", true, false)
			if not mis.is_empty():
				_rock_mesh = (mis[0] as MeshInstance3D).mesh
			scene.free()
	if _rock_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 7
		sm.rings = 4
		_rock_mesh = sm
	return _rock_mesh


func _process(delta: float) -> void:
	if _done or game == null or game.paused:
		return
	if bool(game.get("_ended")):
		_done = true
		_drop()
		queue_free()
		return
	var em: Node = game.get("enemies")
	# the creatures' shot clock (pass 48, EnemyManager.hostile_clock: High Noon and the pace knob; its ring lasts as long)
	var dt: float = delta * (float(em.hostile_clock()) if em and em.has_method("hostile_clock") else (float(em.time_scale) if em else 1.0))
	_t += dt
	var u := clampf(_t / flight, 0.0, 1.0)
	global_position = from.lerp(to, u) + Vector3.UP * arc * 4.0 * u * (1.0 - u)
	_pivot.rotate(_axis, _spin * dt)
	if _shadow >= 0:
		var tg: Node = game.get("telegraphs")
		if tg:
			tg.move_held(_shadow, to, 0.5 + 1.3 * u)
	if u >= 1.0:
		_land()


func _land() -> void:
	_done = true
	_drop()
	if game and game.has_method("boulder_land"):
		game.boulder_land(to, cfg, info, thrower)
	queue_free()


func _drop() -> void:
	if _shadow >= 0 and game:
		var tg: Node = game.get("telegraphs")
		if tg:
			tg.release(_shadow)
	_shadow = -1
