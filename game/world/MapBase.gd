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


## The height of the water's surface (pass 54): a map with no water answers far below any ground, so a check against
## it is never true; Red Canyon returns its lake's level. Pairs with `in_water` on maps that have one.
func water_level() -> float:
	return -1000.0


## The ground's up at (x, z) (pass 52: a flat thing laid on the sand, a power-up's ring, a black hole's disc, a chest's
## pool of light, tilts to it, so a slope no longer swallows half of it): from height_at `span` metres either side, so a
## ring `span` wide sits on the plane of the sand it covers rather than on one bump.
func normal_at(x: float, z: float, span: float = 0.5) -> Vector3:
	var e := maxf(span, 0.05)
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx / (2.0 * e), 1.0, -dz / (2.0 * e)).normalized()


## The ground's rise per metre at (x, z) along x and along z (pass 52: the chest's pool of light, which its shader lays
## out itself), over the same span as normal_at.
func slope_at(x: float, z: float, span: float = 0.5) -> Vector2:
	var e := maxf(span, 0.05)
	return Vector2((height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e), (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e))


## A basis whose up is `n` (pass 52): the shortest turn from straight up to the ground's normal.
static func ground_basis(n: Vector3) -> Basis:
	var up := n.normalized() if n.length_squared() > 0.0001 else Vector3.UP
	if up.is_equal_approx(Vector3.UP):
		return Basis()
	return Basis(Quaternion(Vector3.UP, up))


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
	var a := Dice.r.randf() * TAU
	return Vector3(center.x + cos(a) * r, 0, center.z + sin(a) * r)


func clamp_to_arena(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > arena_radius - 1.5:
		flat = flat.normalized() * (arena_radius - 1.5)
	return Vector3(flat.x, p.y, flat.y)


func player_start() -> Vector3:
	var p := flats_center
	return Vector3(p.x, height_at(p.x, p.z) + 0.5, p.z)
