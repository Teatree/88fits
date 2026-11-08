## The Skull Rain's skulls on the sand (pass 136, lane PLACED; Garry: "Let's make it so the 'stink' of the Skull that
## stays on is actually around a skull 3d object sitting on the ground, which disappears once the effect is off").
## A poison cloud of a weapon carrying `params.ground_skull` (Skull Rain, Grave Hail: every bounce's cloud) holds one
## 3D skull at its centre for the cloud's life (ElementCloud._ready calls place_for): it pops up out of the sand in POP
## seconds, sits with its face turned up towards the camera, and sinks back into the sand over the cloud's last `sink`
## seconds, gone as the cloud goes. A cloud a skull's own (a ricochet's puff, a death pool: `pool_seconds`) has none.
## params.ground_skull {model (a GLB, its first mesh in its own vertex colours; MODEL by default), size (x the model,
## grown with the cloud's radius: sqrt(radius / REF_RADIUS) within 0.8..1.4), tint (a colour multiplied over the
## vertex colours: the weapon's look), sink (seconds), tilt (radians the face is turned up)}.
## Pooled: one MultiMesh a model and tint for every skull on the map (one draw call), the slots reused; looks only, so
## its yaw and wobble roll on the global stream (never the run's dice).
class_name GroundSkulls
extends Node3D

const MODEL := "res://art/props/skull_rain_skull.glb"
const NODE_NAME := "GroundSkulls"
## seconds the skull takes to pop up out of the sand, and how far under it starts
const POP := 0.2
const POP_DEPTH := 0.5
## the default sink (seconds) and tilt (radians, the face turned up towards the high camera)
const SINK := 0.5
const TILT := 0.55
## a cloud this wide holds a skull of `size`; wider ones grow it (sqrt), within SIZE_MIN..SIZE_MAX of it
const REF_RADIUS := 2.2
const SIZE_MIN := 0.8
const SIZE_MAX := 1.4
## slots a MultiMesh starts with (doubled when full)
const START_CAP := 16

static var _meshes: Dictionary = {}

## key -> {mm: MultiMesh, node: MultiMeshInstance3D, free: Array of slots}
var _sets: Dictionary = {}
## the skulls standing: {key, slot, at, yaw, scale, tilt, life, total, sink, t}
var _items: Array = []
var game: Node
## skulls placed so far (tests, captures)
var placed := 0


## The pool of `p_game` (made the first time).
static func of(p_game: Node) -> GroundSkulls:
	if p_game == null:
		return null
	var n := p_game.get_node_or_null(NODE_NAME)
	if n is GroundSkulls:
		return n
	var g := GroundSkulls.new()
	g.name = NODE_NAME
	g.game = p_game
	p_game.add_child(g)
	return g


## The weapon's ground_skull block, {} without one.
static func cfg(w: WeaponInstance) -> Dictionary:
	if w == null:
		return {}
	var c = w.params.get("ground_skull")
	return c if c is Dictionary else {}


## A skull for a cloud of `w` at `at` (on the ground), `radius` wide, lasting `life` seconds; -1 when the weapon has
## no ground_skull block (or the model is missing). Returns the skull's index among those standing now.
static func place_for(p_game: Node, w: WeaponInstance, at: Vector3, radius: float, life: float) -> int:
	var c := cfg(w)
	if c.is_empty() or life <= 0.0:
		return -1
	var g := of(p_game)
	return g.place(at, radius, life, c) if g else -1


## The skulls standing now (tests).
func count() -> int:
	return _items.size()


## A skull's height over the sand now as a share of its full height (1 sitting, 0 gone; tests).
func rise_of(k: int) -> float:
	if k < 0 or k >= _items.size():
		return 0.0
	return _rise(_items[k])


func place(at: Vector3, radius: float, life: float, c: Dictionary) -> int:
	var path := str(c.get("model", MODEL))
	var tint := Color(str(c.get("tint", "#FFFFFF")))
	var key := "%s|%s" % [path, tint.to_html()]
	if not _sets.has(key):
		var mesh := _mesh(path)
		if mesh == null:
			return -1
		_sets[key] = _make_set(mesh, tint)
	var st: Dictionary = _sets[key]
	if (st["free"] as Array).is_empty():
		_grow(st)
	var slot: int = (st["free"] as Array).pop_back()
	var sc := float(c.get("size", 1.5)) * clampf(sqrt(maxf(radius, 0.1) / REF_RADIUS), SIZE_MIN, SIZE_MAX)
	var it := {"key": key, "slot": slot, "at": at, "yaw": randf_range(-0.45, 0.45), "roll": randf_range(-0.12, 0.12),
			"scale": sc, "tilt": float(c.get("tilt", TILT)), "life": life, "total": life,
			"sink": minf(float(c.get("sink", SINK)), life * 0.5), "t": 0.0}
	_items.append(it)
	placed += 1
	_draw(it)
	return _items.size() - 1


func _process(delta: float) -> void:
	delta = Lockstep.dt(delta)
	if _items.is_empty():
		return
	if game != null and bool(game.get("paused")):
		return
	for k in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[k]
		it["t"] = float(it["t"]) + delta
		it["life"] = float(it["life"]) - delta
		if float(it["life"]) <= 0.0:
			var st: Dictionary = _sets[it["key"]]
			(st["mm"] as MultiMesh).set_instance_transform(int(it["slot"]), Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			(st["free"] as Array).append(int(it["slot"]))
			_items.remove_at(k)
			continue
		_draw(it)


## How far up the skull stands (0..1): popping up, sitting, sinking away over its last `sink` seconds.
func _rise(it: Dictionary) -> float:
	var up := clampf(float(it["t"]) / POP, 0.0, 1.0)
	# a little overshoot as it pops up
	up = 1.0 - pow(1.0 - up, 3.0) + 0.12 * sin(up * PI)
	var s := float(it["sink"])
	var down := clampf(float(it["life"]) / maxf(s, 0.01), 0.0, 1.0)
	return minf(up, down * down * (3.0 - 2.0 * down))


func _draw(it: Dictionary) -> void:
	var st: Dictionary = _sets[it["key"]]
	var r := _rise(it)
	var sc := float(it["scale"])
	# the face (the model's +Z) turned up towards the camera, a small yaw and roll of its own; it sinks straight down,
	# a little smaller as it goes
	var b := Basis(Vector3.UP, float(it["yaw"])) * Basis(Vector3.RIGHT, -float(it["tilt"])) * Basis(Vector3.BACK, float(it["roll"]))
	var k := lerpf(0.7, 1.0, r)
	var at: Vector3 = it["at"]
	var y := at.y - (1.0 - r) * POP_DEPTH * sc - 0.04 * sc
	(st["mm"] as MultiMesh).set_instance_transform(int(it["slot"]), Transform3D(b.scaled(Vector3.ONE * sc * k), Vector3(at.x, y, at.z)))


func _make_set(mesh: Mesh, tint: Color) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# (Compatibility: instance colours on, all white, so the vertex colours are not multiplied by stray data)
	mm.use_colors = true
	mm.mesh = mesh
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.top_level = true
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	mat.set_shader_parameter("tint", tint)
	node.material_override = mat
	# never culled by its first skull's bounds: the skulls stand all over the map
	node.custom_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 400, 4000))
	add_child(node)
	var st := {"mm": mm, "node": node, "free": []}
	_resize(st, START_CAP)
	return st


func _grow(st: Dictionary) -> void:
	_resize(st, maxi((st["mm"] as MultiMesh).instance_count * 2, START_CAP))


## A new capacity (the MultiMesh's data resets): the standing skulls drawn again, the new slots free.
func _resize(st: Dictionary, cap: int) -> void:
	var mm: MultiMesh = st["mm"]
	var old := mm.instance_count
	mm.instance_count = cap
	for s in range(cap):
		mm.set_instance_transform(s, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		mm.set_instance_color(s, Color.WHITE)
	for s in range(cap - 1, old - 1, -1):
		(st["free"] as Array).append(s)
	for it: Dictionary in _items:
		if is_same(_sets.get(it["key"]), st):
			_draw(it)


## The skull's paint: its vertex colours x the tint, lit, a little lift so the bone reads white on the sand, and the
## toxic green of the eye sockets and nose glowing (where green stands well over red and blue).
const SHADER_CODE := """shader_type spatial;
render_mode cull_back;
uniform vec4 tint : source_color = vec4(1.0);
uniform float lift = 0.22;
uniform float eye_glow = 1.4;
void fragment() {
	vec3 c = COLOR.rgb * tint.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.85;
	float g = clamp((COLOR.g - max(COLOR.r, COLOR.b)) * 2.5, 0.0, 1.0);
	EMISSION = c * lift + vec3(0.3, 1.0, 0.22) * g * eye_glow * COLOR.g;
}
"""
static var _shader_res: Shader = null


static func _shader() -> Shader:
	if _shader_res == null:
		_shader_res = Shader.new()
		_shader_res.code = SHADER_CODE
	return _shader_res


## The model's first mesh (cached by path); null when the file is missing.
static func _mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var mesh: Mesh = null
	if ResourceLoader.exists(path):
		var scn = load(path)
		if scn is PackedScene:
			var root: Node = (scn as PackedScene).instantiate()
			for m in root.find_children("*", "MeshInstance3D", true, false):
				if (m as MeshInstance3D).mesh:
					mesh = (m as MeshInstance3D).mesh
					break
			root.free()
	_meshes[path] = mesh
	return mesh
