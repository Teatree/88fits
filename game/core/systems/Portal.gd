## The portal that appears where a boss dies. Walking in asks: extract or continue.
class_name Portal
extends Node3D

signal entered

var _ring: MeshInstance3D
var _t := 0.0
var armed := true
var _light: OmniLight3D


func _ready() -> void:
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.4
	t.outer_radius = 1.8
	_ring.mesh = t
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.83, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.27, 0.83, 0.6)
	mat.emission_energy_multiplier = 1.5
	_ring.material_override = mat
	_ring.position.y = 2.0
	_ring.rotation.x = PI * 0.5
	add_child(_ring)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 1.4
	cyl.height = 0.05
	disc.mesh = cyl
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.27, 0.83, 0.6, 0.35)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dmat
	disc.position.y = 0.05
	add_child(disc)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.3, 0.9, 0.6)
	_light.omni_range = 8.0
	_light.light_energy = 2.0
	_light.position.y = 2.0
	add_child(_light)
	scale = Vector3(0.05, 0.05, 0.05)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play("wd_portal_open", global_position)


func _process(delta: float) -> void:
	_t += delta
	_ring.rotation.z += delta * 1.2
	_ring.position.y = 2.0 + sin(_t * 2.0) * 0.15


func check_player(p: Node3D) -> void:
	if not armed:
		return
	var d := p.global_position - global_position
	d.y = 0.0
	if d.length() < 1.5:
		armed = false
		entered.emit()
