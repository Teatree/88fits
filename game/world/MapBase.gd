## Base for arena scenes. Provides terrain height, obstacle circles for the enemy steering,
## the flats centre for bosses, and spawn helpers. Concrete maps build their geometry in _ready.
class_name MapBase
extends Node3D

@export var arena_radius := 66.0
@export var size_m := 140.0
## Points per metre of the heightmap.
@export var resolution := 1.0

var heights := PackedFloat32Array()
var grid_n := 0
var obstacles: Array = []       # Vector3(x, z, r)
var flats_center := Vector3.ZERO
var spawn_points: Array = []    # player start candidates
var jump_pads: Array = []


## Hell (pass 43): how red the ground is, 0 to 1, tweened in over `seconds`. Maps with painted terrain override it.
func set_hell(_f: float, _seconds: float = 3.0) -> void:
	pass


func height_at(x: float, z: float) -> float:
	if grid_n == 0:
		return 0.0
	var half := size_m * 0.5
	var fx: float = clamp((x + half) * resolution, 0.0, float(grid_n - 1) - 0.001)
	var fz: float = clamp((z + half) * resolution, 0.0, float(grid_n - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := heights[iz * grid_n + ix]
	var h10 := heights[iz * grid_n + ix + 1]
	var h01 := heights[(iz + 1) * grid_n + ix]
	var h11 := heights[(iz + 1) * grid_n + ix + 1]
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)


func random_point_on_ring(center: Vector3, r: float) -> Vector3:
	var a := randf() * TAU
	return Vector3(center.x + cos(a) * r, 0, center.z + sin(a) * r)


func clamp_to_arena(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > arena_radius - 1.5:
		flat = flat.normalized() * (arena_radius - 1.5)
	return Vector3(flat.x, p.y, flat.y)


func player_start() -> Vector3:
	var p := flats_center
	return Vector3(p.x, height_at(p.x, p.z) + 0.5, p.z)
