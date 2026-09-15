## A geyser in the meadow. Every `period` seconds it rumbles (a blue ring on the ground for `warn` seconds), then
## erupts: everything inside is thrown up and out, the hero too. It never moves, so it is a tool as much as a
## hazard: lead a pack over it and count.
class_name Geyser
extends Node3D

@export var radius := 2.6
@export var period := 9.0
@export var warn := 1.3
## Seconds into the cycle at start, so several geysers never fire together.
@export var phase := 0.0
@export var enemy_damage := 8.0

var game: Node
var _next := 0.0
var _warned := false
var _spout: MeshInstance3D
var _spout_mat: StandardMaterial3D


func _ready() -> void:
	_next = period - phase
	# the pool: a flat pale disc with a darker rim
	var pool := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = radius * 0.9
	pm.bottom_radius = radius * 0.9
	pm.height = 0.12
	pm.radial_segments = 20
	pool.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.75, 0.82)
	mat.roughness = 0.3
	pool.material_override = mat
	pool.position.y = 0.04
	add_child(pool)
	var rim := MeshInstance3D.new()
	var rmesh := TorusMesh.new()
	rmesh.inner_radius = radius * 0.85
	rmesh.outer_radius = radius * 1.05
	rim.mesh = rmesh
	rim.scale = Vector3(1, 0.4, 1)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.42, 0.40, 0.36)
	rim.material_override = rmat
	rim.position.y = 0.05
	add_child(rim)
	# the spout: a translucent column that shoots up for a moment when it blows
	_spout = MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = radius * 0.75
	sm.bottom_radius = radius * 0.45
	sm.height = 1.0
	sm.radial_segments = 12
	_spout.mesh = sm
	_spout_mat = StandardMaterial3D.new()
	_spout_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spout_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spout_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.0)
	_spout.material_override = _spout_mat
	_spout.position.y = 0.5
	_spout.scale = Vector3(1, 0.01, 1)
	add_child(_spout)


func _process(delta: float) -> void:
	if game == null:
		return
	_next -= delta
	if not _warned and _next <= warn:
		_warned = true
		if game.has_method("telegraph_ring"):
			game.telegraph_ring(global_position, radius, warn, Color(0.5, 0.82, 1.0), true)
	if _next <= 0.0:
		_erupt()
		_next = period
		_warned = false


func _erupt() -> void:
	var em: EnemyManager = game.enemies
	if em:
		em.damage_radius(global_position, radius, enemy_damage, "", 3.0)
		em.lift_radius(global_position, radius, 1.4)
	var pl: Node3D = game.player
	if pl and not pl.dead and pl.has_method("launch"):
		var d := pl.global_position - global_position
		d.y = 0.0
		if d.length() < radius + 0.5:
			var out := d.normalized() if d.length() > 0.2 else Vector3(1, 0, 0)
			pl.launch(Vector3(out.x * 4.5, 9.5, out.z * 4.5))
	if game.has_method("fx_burst"):
		game.fx_burst(global_position + Vector3(0, 1.0, 0), Color(0.75, 0.92, 1.0), 2.2)
	Audio.play("w_lob_boom", global_position)
	# the water column
	_spout.scale = Vector3(1, 0.01, 1)
	_spout_mat.albedo_color.a = 0.55
	var tw := create_tween()
	tw.tween_property(_spout, "scale:y", 7.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_spout, "position:y", 3.5, 0.22)
	tw.tween_property(_spout_mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(func(): _spout.scale = Vector3(1, 0.01, 1); _spout.position.y = 0.5)
