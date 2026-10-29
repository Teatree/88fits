## The Singularity's black hole (pass 35): it lands where it was thrown and for `seconds` drags every creature within
## `radius` towards its middle (bosses and Elites a little, the rest hard) and eats `dps` into them; then it collapses
## with a pop (`pop` times the shot's damage, thrown outwards). A black sphere with a violet rim over a flat turning
## spiral, and dust drawn in from the rim. The numbers come from the weapon's params.gravity.black_hole block.
## Pass 48: Repulsor carried on the Singularity sends `knock_mult` and `throw_mult` in that block: the pop throws that
## much harder over that much wider a ring.
class_name Vortex
extends Node3D

const SPHERE_SHADER := preload("res://core/shaders/black_hole.gdshader")
const SWIRL_SHADER := preload("res://core/shaders/swirl.gdshader")

var game: Node
var weapon: WeaponInstance
var radius := 3.2
var life := 3.0
var dps := 10.0
var pull := 5.5
var pop := 1.0
var damage := 12.0
var tick := 0.25
var knock_mult := 1.0
var throw_mult := 1.0
var _t := 0.0
var _total := 3.0
var _next := 0.0
var _mote_t := 0.0
var _sphere: MeshInstance3D
var _disc: MeshInstance3D
var _swirl_mat: ShaderMaterial


func setup(p_game: Node, w: WeaponInstance, r: float, cfg: Dictionary, shot_damage: float) -> void:
	game = p_game
	weapon = w
	radius = r
	life = float(cfg.get("seconds", 3.0))
	_total = life
	dps = shot_damage * float(cfg.get("dps_frac", 0.8))
	pull = float(cfg.get("pull", 5.5))
	pop = float(cfg.get("pop", 1.0))
	tick = maxf(float(cfg.get("tick", 0.25)), 0.1)
	knock_mult = maxf(float(cfg.get("knock_mult", 1.0)), 0.0)
	throw_mult = maxf(float(cfg.get("throw_mult", 1.0)), 0.1)
	damage = shot_damage


func _ready() -> void:
	_sphere = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 20
	sm.rings = 10
	_sphere.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = SPHERE_SHADER
	_sphere.material_override = mat
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sphere.position = Vector3(0, 0.9, 0)
	_sphere.scale = Vector3.ONE * 0.05
	add_child(_sphere)
	_disc = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.2, radius * 2.2)
	_disc.mesh = pm
	_swirl_mat = ShaderMaterial.new()
	_swirl_mat.shader = SWIRL_SHADER
	_swirl_mat.set_shader_parameter("color_a", Color(0.1, 0.02, 0.18, 0.75))
	_swirl_mat.set_shader_parameter("color_b", Color(0.62, 0.25, 0.95, 0.9))
	_swirl_mat.set_shader_parameter("color_eye", Color(0.0, 0.0, 0.0, 0.95))
	_swirl_mat.set_shader_parameter("speed", 5.0)
	_swirl_mat.set_shader_parameter("twist", 1.6)
	_swirl_mat.set_shader_parameter("eye", 0.16)
	_disc.material_override = _swirl_mat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.position = Vector3(0, 0.08, 0)
	# on the slope it lands on (pass 52), not level through it
	if game and game.get("map") and game.map.has_method("normal_at"):
		var n: Vector3 = game.map.normal_at(position.x, position.z, radius * 0.6)
		_disc.basis = MapBase.ground_basis(n)
		_disc.position = n * 0.08
	add_child(_disc)
	if game:
		game.telegraphs.flash_ring(global_position, radius, Color(0.7, 0.35, 1.0), 0.4)
		Audio.play("w_blackhole", global_position)


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	if game == null or game.paused:
		return
	_t += delta
	life -= delta
	# it swells in, throbs, and shrinks to nothing in the last fifth of a second before the pop
	var grow := clampf(_t / 0.25, 0.0, 1.0)
	var shrink := clampf(life / 0.2, 0.0, 1.0)
	var s := 0.9 * grow * shrink * (1.0 + 0.08 * sin(_t * 18.0))
	_sphere.scale = Vector3.ONE * maxf(s, 0.01)
	_swirl_mat.set_shader_parameter("alpha", grow * clampf(life / 0.35, 0.0, 1.0))
	_disc.rotation.y += delta * 1.5
	var em: EnemyManager = game.enemies
	var c := global_position
	# the drag: straight at the middle, harder near it
	em.drag_radius(c, radius, pull, delta)
	_next -= delta
	if _next <= 0.0:
		_next = tick
		var before := Run.kills
		em.damage_radius(c, radius, dps * tick, weapon.def.id if weapon else "", 0.0)
		if weapon:
			weapon.kills += Run.kills - before
	# dust drawn in from the rim
	_mote_t -= delta
	if _mote_t <= 0.0:
		_mote_t = 0.06
		var a := randf() * TAU
		var p := c + Vector3(cos(a), 0.0, sin(a)) * radius * randf_range(0.7, 1.0)
		p.y = (game.map.height_at(p.x, p.z) if game.map else c.y) + 0.25
		var to := (c + Vector3(0, 0.6, 0)) - p
		game.fx.mote(p, to / 0.45, 0.45, 0.35, Color(0.72, 0.45, 1.0, 0.8))
	if life <= 0.0:
		_collapse()


func _collapse() -> void:
	var em: EnemyManager = game.enemies
	var before := Run.kills
	var pop_r := radius * 0.7 * throw_mult
	em.damage_radius(global_position, pop_r, damage * pop, weapon.def.id if weapon else "", 9.0 * knock_mult)
	if weapon:
		weapon.kills += Run.kills - before
	game.fx.burst(global_position + Vector3(0, 0.8, 0), Color(0.75, 0.4, 1.0), pop_r)
	game.telegraphs.flash_ring(global_position, pop_r, Color(0.8, 0.45, 1.0), 0.35)
	game.camera.shake(0.35)
	Audio.play("w_lob_boom", global_position)
	queue_free()
