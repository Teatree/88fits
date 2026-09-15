## A cloud of green smoke where a poison bomb landed: a draped disc on the ground and a few billowing puffs.
## Every creature inside is poisoned (the poison itself lives in EnemyManager). Fades in its last second.
class_name PoisonCloud
extends Node3D

var game: Node
var weapon: WeaponInstance
var radius := 2.2
var life := 4.0
var dmg := 3.0
var stacks := 1
var duration := 10.0
var _t := 0.0
var _total := 4.0
var _check := 0.0
var _disc: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _puffs: Array = []
var _puff_mats: Array = []


func setup(p_game: Node, w: WeaponInstance, r: float, cloud_seconds: float, p_dmg: float, p_stacks: int, p_duration: float) -> void:
	game = p_game
	weapon = w
	radius = r
	life = cloud_seconds
	_total = cloud_seconds
	dmg = p_dmg
	stacks = p_stacks
	duration = p_duration


func _ready() -> void:
	var tg: Telegraphs = game.telegraphs
	_disc = MeshInstance3D.new()
	_disc.mesh = tg.draped_sector(global_position, radius, 1.0)
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.albedo_color = Color(0.35, 0.95, 0.3, 0.38)
	_disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc.material_override = _disc_mat
	_disc.top_level = true
	add_child(_disc)
	for k in range(6):
		var p := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius * randf_range(0.28, 0.42)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		p.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.4, 0.95, 0.35, 0.42)
		p.material_override = m
		var a := TAU * k / 6.0 + randf() * 0.6
		p.position = Vector3(cos(a) * radius * 0.5, 0.4 + randf() * 0.4, sin(a) * radius * 0.5)
		p.scale = Vector3.ONE * 0.2
		add_child(p)
		_puffs.append(p)
		_puff_mats.append(m)


func _process(delta: float) -> void:
	if game == null or game.paused:
		return
	_t += delta
	life -= delta
	var fade: float = clampf(life / 1.0, 0.0, 1.0)
	var grow: float = clampf(_t / 0.35, 0.0, 1.0)
	_disc_mat.albedo_color.a = 0.38 * fade
	for k in range(_puffs.size()):
		var p: MeshInstance3D = _puffs[k]
		var s: float = grow * (0.85 + 0.25 * sin(_t * 2.0 + k))
		p.scale = Vector3.ONE * s
		p.position.y += delta * 0.12
		p.rotation.y += delta * 0.6
		_puff_mats[k].albedo_color.a = 0.42 * fade * (0.8 + 0.2 * sin(_t * 3.0 + k * 1.3))
	_check -= delta
	if _check <= 0.0:
		_check = 0.3
		var em: EnemyManager = game.enemies
		var wid: String = weapon.def.id if weapon else ""
		for e in em.indices_in_radius(global_position, radius):
			em.poison(e, wid, dmg, stacks, duration)
	if life <= 0.0:
		queue_free()
