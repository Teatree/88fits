## A stationary turret dropped by Spawner. Shoots the nearest enemy; expires after `lifetime`.
class_name Turret
extends Node3D

var owner_behavior: WeaponBehavior
var life := 12.0
var fire_rate := 0.35
var _fire_t := 0.0
var _head: MeshInstance3D
var _magnet := false
var _expiring := false


func setup(b: WeaponBehavior, mesh: Mesh, mat: Material) -> void:
	owner_behavior = b
	life = b.stat("lifetime", 12.0)
	fire_rate = float(b.inst.def.params.get("turret_fire_rate", 0.35))
	_magnet = bool(b.inst.def.params.get("magnet", false))
	var base := MeshInstance3D.new()
	base.mesh = mesh
	if mat:
		base.material_override = mat
	base.position.y = 0.35
	add_child(base)
	_head = MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.25, 0.25, 0.7)
	_head.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.25, 0.25, 0.3)
	_head.material_override = hmat
	_head.position.y = 0.85
	add_child(_head)
	scale = Vector3(0.1, 0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func expire() -> void:
	if _expiring:
		return
	_expiring = true
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.3)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	if owner_behavior == null or owner_behavior.game == null or owner_behavior.game.paused:
		return
	if _expiring:
		return
	life -= delta
	if life <= 0.0:
		expire()
		return
	var game = owner_behavior.game
	if _magnet:
		game.pickups.add_attractor(global_position, 4.0)
	_fire_t -= delta
	if _fire_t > 0.0:
		return
	var enemies: EnemyManager = game.enemies
	var rng := owner_behavior.stat("range", 8.0)
	var t := enemies.nearest_index(global_position, rng)
	if t < 0:
		_fire_t = 0.1
		return
	_fire_t = fire_rate
	var from := global_position + Vector3(0, 0.85, 0)
	var dir := enemies.pos[t] + Vector3(0, 0.4, 0) - from
	dir = dir.normalized()
	_head.look_at(from + dir, Vector3.UP)
	var speed := owner_behavior.stat("speed", 16.0)
	game.projectiles.fire(owner_behavior.projectile_kind, from, dir * speed, owner_behavior.stat("damage", 4.0), 0, 0.2, rng / speed, owner_behavior.inst, 0.3)
	owner_behavior.sfx("fire", from)
