## A chest on the ground. Walking into it calls Game.open_chest: the game pauses and the reel decides what it held.
class_name Chest
extends Node3D

var opened := false
var _lid: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.7, 0.8)
	body.mesh = bm
	body.position.y = 0.35
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.33, 0.15)
	body.material_override = mat
	add_child(body)
	_lid = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.15, 0.25, 0.85)
	_lid.mesh = lm
	_lid.position.y = 0.82
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1.0, 0.72, 0.25)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.72, 0.25)
	lmat.emission_energy_multiplier = 0.4
	_lid.material_override = lmat
	add_child(_lid)
	if Fx.want_lights():
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.8, 0.4)
		light.omni_range = 4.0
		light.light_energy = 1.2
		light.position.y = 1.2
		add_child(light)


func _process(delta: float) -> void:
	_t += delta
	if not opened:
		_lid.position.y = 0.82 + sin(_t * 4.0) * 0.04
		rotation.y += delta * 0.6


func open_anim() -> void:
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.4, 0.25)
	tw.parallel().tween_property(self, "scale", Vector3(1.2, 1.2, 1.2), 0.25)
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tw.tween_callback(queue_free)
