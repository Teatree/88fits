## Fireflies: a hundred glowing dots that drift and twinkle over the meadow. Decoration only.
class_name Fireflies
extends Node3D

@export var count := 100
@export var spread := 60.0

var _mm: MultiMesh
var _base := PackedVector3Array()
var _seeds := PackedVector3Array()
var _t := 0.0


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var m := SphereMesh.new()
	m.radius = 0.07
	m.height = 0.14
	m.radial_segments = 5
	m.rings = 3
	_mm.mesh = m
	_mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 1.0, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 1.0, 0.3)
	mat.emission_energy_multiplier = 2.0
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-spread - 5, -5, -spread - 5), Vector3(spread * 2 + 10, 20, spread * 2 + 10))
	add_child(mmi)
	for i in range(count):
		_base.append(Vector3(randf_range(-spread, spread), randf_range(0.8, 2.6), randf_range(-spread, spread)))
		_seeds.append(Vector3(randf() * TAU, randf() * TAU, randf_range(0.5, 1.5)))


func _process(delta: float) -> void:
	_t += delta
	for i in range(count):
		var s := _seeds[i]
		var p := _base[i] + Vector3(sin(_t * 0.4 * s.z + s.x) * 1.5, sin(_t * 0.9 + s.y) * 0.4, cos(_t * 0.35 * s.z + s.y) * 1.5)
		var tw := 0.5 + 0.5 * sin(_t * 3.0 * s.z + s.x)
		var sc := 0.3 + tw * 0.9
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), p))
