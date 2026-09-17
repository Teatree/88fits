## Painted 2.5D scenery: one MultiMesh per prop sprite (cacti, rocks, bones), camera-facing quads on their base like
## the creatures, drawn through core/shaders/prop_billboard.gdshader. The map scatters them; colliders and
## obstacle circles stay the map's business. Sprites and their sizes come from art/sprites/props/props.json.
class_name PropField
extends Node3D

const PER_TYPE := 200

var manifest: Dictionary = {}
var _types: Dictionary = {}   # id -> {"mm", "n", "height"}
var placed: Array = []        # {"id", "pos", "scale"} for anyone who needs to find a prop (captures, tests)
var _shader: Shader = preload("res://core/shaders/prop_billboard.gdshader")


func setup(manifest_path: String = "res://art/sprites/props/props.json") -> void:
	if not FileAccess.file_exists(manifest_path):
		return
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		manifest = parsed
	var dir := manifest_path.get_base_dir()
	for id in manifest.keys():
		var row: Dictionary = manifest[id]
		var path: String = dir.path_join(str(row.get("file", id + ".png")))
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		mm.mesh = quad
		mm.instance_count = PER_TYPE
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Prop_" + str(id)
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("sprite", tex)
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		add_child(mmi)
		_types[id] = {"mm": mm, "n": 0, "height": float(row.get("height", 1.0)), "radius": float(row.get("radius", 0.0))}


func has(id: String) -> bool:
	return _types.has(id)


func radius_of(id: String) -> float:
	return float(_types[id]["radius"]) if _types.has(id) else 0.0


func height_of(id: String) -> float:
	return float(_types[id]["height"]) if _types.has(id) else 1.0


## Places one prop with its base at `at`. `sway` is the wind lean for greenery (0 for rocks and bones).
func add(id: String, at: Vector3, scale: float = 1.0, flip: bool = false, sway: float = 0.0) -> bool:
	if not _types.has(id):
		return false
	var t: Dictionary = _types[id]
	var n: int = t["n"]
	if n >= PER_TYPE:
		return false
	var mm: MultiMesh = t["mm"]
	var h: float = float(t["height"]) * scale
	# a hair above the ground so the base never sinks into a slope
	mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(h, h, h)), at + Vector3(0, 0.06, 0)))
	mm.set_instance_custom_data(n, Color(1.0 if flip else 0.0, sway, randf() * TAU, 0.0))
	t["n"] = n + 1
	mm.visible_instance_count = n + 1
	placed.append({"id": id, "pos": at, "scale": scale})
	return true


func count() -> int:
	var c := 0
	for t in _types.values():
		c += int(t["n"])
	return c
