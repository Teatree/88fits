## A roaming dust devil on the flats. Sucks enemies up into the air and spins them around before dropping them,
## tosses the player, rolls around a loop.
class_name DustDevil
extends Node3D

@export var radius := 2.4
@export var push := 6.0
@export var loop_center := Vector3.ZERO
@export var loop_rx := 18.0
@export var loop_rz := 10.0
@export var speed := 0.25

var game: Node
var _t := 0.0
var _cone: MeshInstance3D
var _player_cd := 0.0


func _ready() -> void:
	_cone = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius * 1.4
	m.bottom_radius = radius * 0.4
	m.height = 6.0
	m.radial_segments = 10
	_cone.mesh = m
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.7, 0.5, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# pass 87 (lane SLOOK): before the stage's filter, so the stage's look tints the column like the sand
	mat.render_priority = StageLook.PRIORITY - 1
	_cone.material_override = mat
	_cone.position.y = 3.0
	add_child(_cone)


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_t += delta * speed
	var p := loop_center + Vector3(cos(_t) * loop_rx, 0, sin(_t * 0.7) * loop_rz)
	if game and game.map:
		p.y = game.map.height_at(p.x, p.z)
	global_position = p
	_cone.rotation.y += delta * 6.0
	if game == null:
		Perf.add("dustdevil", _t0)
		return
	_player_cd = maxf(_player_cd - delta, 0.0)
	var pl: Node3D = game.player
	if pl and not pl.dead:
		var d := pl.global_position - global_position
		d.y = 0.0
		if d.length() < radius + 0.5 and _player_cd <= 0.0 and pl.has_method("launch"):
			# the hero gets tossed up and out, once per pass
			pl.launch(Vector3(d.normalized().x * push * 0.6, 8.0, d.normalized().z * push * 0.6))
			_player_cd = 1.2
	var em: EnemyManager = game.enemies
	if em:
		em.lift_radius(global_position, radius, 1.7)
		em.swirl(global_position, radius, delta)

	Perf.add("dustdevil", _t0)