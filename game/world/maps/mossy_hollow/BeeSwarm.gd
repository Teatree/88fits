## A swarm of bees drifting across the meadow. It wanders, and homes in on the hero when he is near. Standing in it
## stings him a little every half second and stings every enemy inside too, so a pack can be led through it.
class_name BeeSwarm
extends Node3D

@export var radius := 2.3
@export var speed := 1.7
@export var chase_range := 15.0
@export var sting := 3.0
@export var enemy_sting := 4.0
@export var bees := 36
@export var roam_radius := 40.0

var game: Node
var _mm: MultiMesh
var _goal := Vector3.ZERO
var _goal_t := 0.0
var _sting_cd := 0.0
var _t := 0.0
var _seeds := PackedVector3Array()


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.18
	m.radial_segments = 6
	m.rings = 3
	_mm.mesh = m
	_mm.instance_count = bees
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.2)
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
	add_child(mmi)
	for i in range(bees):
		_seeds.append(Vector3(randf() * TAU, randf() * TAU, randf_range(0.6, 1.0)))
	var hum := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = radius
	hm.height = radius * 2.0
	hm.radial_segments = 12
	hm.rings = 6
	hum.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.albedo_color = Color(1.0, 0.85, 0.3, 0.12)
	hum.material_override = hmat
	add_child(hum)
	_pick_goal()


func _pick_goal() -> void:
	var a := randf() * TAU
	var r := randf_range(6.0, roam_radius)
	_goal = Vector3(cos(a) * r, 0, sin(a) * r)
	_goal_t = randf_range(6.0, 12.0)


func _process(delta: float) -> void:
	_t += delta
	_goal_t -= delta
	var pl: Node3D = game.player if game else null
	var goal := _goal
	if pl and not pl.dead:
		var d := pl.global_position - global_position
		d.y = 0.0
		if d.length() < chase_range:
			goal = pl.global_position
	if _goal_t <= 0.0:
		_pick_goal()
	var to := goal - global_position
	to.y = 0.0
	if to.length() > 0.5:
		global_position += to.normalized() * speed * delta
	if game and game.map:
		global_position.y = game.map.height_at(global_position.x, global_position.z) + 1.3
	# the bees orbit the centre on their own little loops
	for i in range(bees):
		var s := _seeds[i]
		var a := s.x + _t * (2.0 + s.z * 1.5)
		var b := s.y + _t * 1.3
		var p := Vector3(cos(a) * radius * 0.8 * s.z, sin(b) * 0.6, sin(a) * radius * 0.8 * s.z)
		_mm.set_instance_transform(i, Transform3D(Basis(), p))
	_sting_cd -= delta
	if _sting_cd > 0.0 or game == null:
		return
	_sting_cd = 0.5
	if pl and not pl.dead:
		var d := pl.global_position - global_position
		d.y = 0.0
		if d.length() < radius:
			pl.take_damage(sting, global_position)
	var em: EnemyManager = game.enemies
	if em:
		em.damage_radius(global_position, radius, enemy_sting, "", 0.0)
