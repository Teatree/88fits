## Painted 2.5D scenery: one MultiMesh per prop sprite (cacti, rocks, bones), camera-facing quads on their base like
## the creatures, drawn through core/shaders/prop_billboard.gdshader. The map scatters them; colliders and
## obstacle circles stay the map's business. Sprites and their sizes come from art/sprites/props/props.json.
## Pass 83 (lane SCENE; Garry: "add some variation to our environment art"): a manifest entry with `"variant_of": <id>`
## is another painting of that kind (agave_b of the agave). Asked for the kind, add() draws the kind's own painting or
## one of its variants, chosen by the spot (pick_look: a hash of the position, weighted by each entry's `weight`, 1 by
## default), never by the map's roll, so a seed lays out exactly what it did and only the paintings vary; its `placed`
## row keeps the kind's id (`look` names the painting). Asked for a variant by name, it draws that one.
## Pass 83: every placed prop lies on a soft ground shadow (core/shaders/ground_shadow.gdshader), one MultiMesh for the
## whole field, its size from the painting's manifest entry `shadow` {w, d (metres across and deep at scale 1), x, z
## (the foot's offset from the quad's middle, metres; x mirrors with the painting), a (strength)}, measured from the
## painting by tools/prop_shadows.py and tuned by eye, and shifted a little away from the paintings' light
## (SUN_SHIFT). The barrels, the signs and the structures lay theirs in the same MultiMesh (add_shadow), so the whole
## scenery's shadows are one draw.
class_name PropField
extends Node3D

const PER_TYPE := 200
## The shadows' MultiMesh starts this big and doubles when it fills.
const SHADOW_CAP := 512
## The paintings are lit from the upper left (their painted shading, and the cast shadow the renders came with before
## keying): a shadow sits this far right of the foot and this far back, metres per metre of the thing's height, at most
## SUN_SHIFT_MAX metres. Small: a shadow under the thing, leaning the way the light says.
const SUN_SHIFT := Vector2(0.08, -0.02)
const SUN_SHIFT_MAX := 0.3
## A painting with no `shadow` entry: this wide and deep (shares of its quad's height) and this dark.
const SHADOW_DEFAULT := {"w": 0.5, "d": 0.24, "x": 0.0, "z": 0.0, "a": 0.35}

var manifest: Dictionary = {}
var _types: Dictionary = {}   # id -> {"mm", "n", "height", "radius"}
var placed: Array = []        # {"id", "look", "pos", "scale", "flip", "i", "s"} for anyone who needs to find a prop (captures, tests)
var _shader: Shader = preload("res://core/shaders/prop_billboard.gdshader")
## kind -> [[painting id, weight], ...] (the kind's own painting first), for the kinds that have variants
var _variants: Dictionary = {}
## The ground under a point (the map's height_at): the shadows lie on slopes (EnemyManager.drape). Unset: flat at the foot.
var height_fn: Callable
var _shadow_mm: MultiMesh
var _shadow_mmi: MultiMeshInstance3D
var _shadow_n := 0
## each shadow's {a, w, d, tall} and its size now (1 standing, 0 hidden), kept here: a MultiMesh's buffer is not read
## back (the headless renderer keeps none, and on the phone a read waits on the GPU)
var _shadow_c := PackedColorArray()
var _shadow_at := PackedVector3Array()
var _shadow_k := PackedFloat32Array()


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
	_build_variants()
	_build_shadows()


## The kinds' variant tables: every drawable, unhidden entry with `variant_of` naming a drawable kind.
func _build_variants() -> void:
	_variants.clear()
	for id in manifest.keys():
		var row = manifest[id]
		if not row is Dictionary or not _types.has(id) or is_hidden(id):
			continue
		var base := str((row as Dictionary).get("variant_of", ""))
		if base == "" or not _types.has(base):
			continue
		if not _variants.has(base):
			_variants[base] = [[base, _weight(base)]]
		(_variants[base] as Array).append([str(id), _weight(str(id))])


func _weight(id: String) -> float:
	var row = manifest.get(id)
	return maxf(float((row as Dictionary).get("weight", 1.0)), 0.0) if row is Dictionary else 1.0


func _build_shadows() -> void:
	_shadow_mm = MultiMesh.new()
	_shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
	_shadow_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	_shadow_mm.mesh = quad
	_shadow_mm.instance_count = SHADOW_CAP
	_shadow_mm.visible_instance_count = 0
	_shadow_mmi = MultiMeshInstance3D.new()
	_shadow_mmi.name = "GroundShadows"
	_shadow_mmi.multimesh = _shadow_mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/shaders/ground_shadow.gdshader")
	# under the gems and coins like the creatures' (EnemyManager.SHADOW_PRIORITY)
	mat.render_priority = EnemyManager.SHADOW_PRIORITY
	_shadow_mmi.material_override = mat
	_shadow_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(_shadow_mmi)


## Whether a painting is kept out of the scatter (pass 49, Garry: "hide signpost.png and yucca.png"): its manifest entry
## says `"hidden": true`; the painting and its entry stay, so it can come back by deleting the key.
func is_hidden(id: String) -> bool:
	var row = manifest.get(id)
	return row is Dictionary and bool((row as Dictionary).get("hidden", false))


func has(id: String) -> bool:
	return _types.has(id)


func radius_of(id: String) -> float:
	return float(_types[id]["radius"]) if _types.has(id) else 0.0


func height_of(id: String) -> float:
	return float(_types[id]["height"]) if _types.has(id) else 1.0


## The kind a painting belongs to: its `variant_of`, or itself.
func kind_of(id: String) -> String:
	var row = manifest.get(id)
	if row is Dictionary:
		var base := str((row as Dictionary).get("variant_of", ""))
		if base != "":
			return base
	return id


## The paintings of a kind (its own first), [] for a kind without variants.
func looks_of(kind: String) -> Array:
	return (_variants.get(kind, []) as Array).map(func(r) -> String: return str(r[0]))


## The painting drawn for `kind` at `at`: the kind itself or one of its variants, by a hash of the spot (weighted).
func pick_look(kind: String, at: Vector3) -> String:
	var rows: Array = _variants.get(kind, [])
	if rows.size() < 2:
		return kind
	var total := 0.0
	for r in rows:
		total += float(r[1])
	if total <= 0.0:
		return kind
	var h := hash(Vector2i(roundi(at.x * 64.0), roundi(at.z * 64.0)))
	var x := float(h % 100003) / 100003.0 * total
	for r in rows:
		x -= float(r[1])
		if x < 0.0:
			return str(r[0])
	return str(rows[rows.size() - 1][0])


## Places one prop with its base at `at`. `sway` is the wind lean for greenery (0 for rocks and bones). `id` is a kind
## (a painting or one of its variants is drawn, pick_look) or a variant by name; `exact` draws `id` itself even when it
## is a kind (a hand-laid scene, a capture).
func add(id: String, at: Vector3, scale: float = 1.0, flip: bool = false, sway: float = 0.0, exact: bool = false) -> bool:
	if not _types.has(id):
		return false
	var kind := kind_of(id)
	var look := id if exact or id != kind else pick_look(kind, at)
	var t: Dictionary = _types[look]
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
	var s := -1
	var sh := shadow_of(look)
	if float(sh["a"]) > 0.0:
		var x := float(sh["x"]) * h * (-1.0 if flip else 1.0)
		s = add_shadow(at + Vector3(x, 0.0, float(sh["z"]) * h), float(sh["w"]) * h, float(sh["d"]) * h, float(sh["a"]), h)
	placed.append({"id": kind, "look": look, "pos": at, "scale": scale, "flip": flip, "i": n, "s": s})
	return true


## A painting's shadow, as shares of its quad's height (w, d, x, z) and a strength (a): its manifest `shadow` over
## SHADOW_DEFAULT.
func shadow_of(id: String) -> Dictionary:
	var out := SHADOW_DEFAULT.duplicate()
	var row = manifest.get(id)
	if row is Dictionary and (row as Dictionary).get("shadow") is Dictionary:
		var sh: Dictionary = (row as Dictionary)["shadow"]
		for k in out.keys():
			if sh.has(k):
				out[k] = float(sh[k])
	return out


## A ground shadow `w` metres across and `d` deep (before the sun's shift) centred at `at` (its foot), `a` dark, for a
## thing `tall` metres high (SUN_SHIFT). Returns its index (move_shadow, hide_shadow), -1 when the field has no shadows.
func add_shadow(at: Vector3, w: float, d: float, a: float, tall: float = 0.0) -> int:
	if _shadow_mm == null:
		return -1
	if _shadow_n >= _shadow_mm.instance_count:
		_grow_shadows()
	var i := _shadow_n
	_shadow_n += 1
	var c := Color(clampf(a, 0.0, 1.0), w, d, tall)
	_shadow_c.append(c)
	_shadow_k.append(1.0)
	_shadow_at.append(at)
	_shadow_mm.set_instance_custom_data(i, c)
	move_shadow(i, at)
	_shadow_mm.visible_instance_count = _shadow_n
	return i


## Puts shadow `i` under `at` again (a structure coming down on its balloon), `k` times its size (0 hides it).
func move_shadow(i: int, at: Vector3, k: float = 1.0) -> void:
	if _shadow_mm == null or i < 0 or i >= _shadow_n:
		return
	_shadow_k[i] = k
	_shadow_at[i] = at
	_shadow_mm.set_instance_transform(i, shadow_xform(at, _shadow_c[i], k))


func hide_shadow(i: int) -> void:
	move_shadow(i, Vector3.ZERO, 0.0)


func shadow_count() -> int:
	return _shadow_n


## Shadow `i`'s size now: 1 standing, 0 hidden (tests).
func shadow_scale(i: int) -> float:
	return _shadow_k[i] if i >= 0 and i < _shadow_n else 0.0


## Shadow `i`'s strength (custom data r), 0 for none.
func shadow_strength(i: int) -> float:
	return _shadow_c[i].r if i >= 0 and i < _shadow_n else 0.0


## The shadow's transform: the ellipse (custom data g, b = w, d), shifted by the sun for its height (a), draped on the
## ground (height_fn), `k` times its size.
func shadow_xform(at: Vector3, c: Color, k: float = 1.0) -> Transform3D:
	if k <= 0.0:
		return Transform3D(Basis().scaled(Vector3.ZERO), at)
	var shift := SUN_SHIFT * c.a
	if shift.length() > SUN_SHIFT_MAX:
		shift = shift.normalized() * SUN_SHIFT_MAX
	var o := at + Vector3(shift.x, 0.0, -shift.y)
	var xf := Transform3D(Basis(Vector3.RIGHT * (c.g * k), Vector3.UP, Vector3.BACK * (c.b * k)), Vector3(o.x, at.y, o.z))
	if height_fn.is_valid():
		return EnemyManager.drape(xf, height_fn)
	return Transform3D(xf.basis, xf.origin + Vector3(0, EnemyManager.SHADOW_LIFT, 0))


## Twice the room: a MultiMesh's buffer is cleared when its count changes, so every shadow is laid again from what was
## kept of it (_shadow_at, _shadow_c, _shadow_k).
func _grow_shadows() -> void:
	_shadow_mm.instance_count = _shadow_mm.instance_count * 2
	for i in _shadow_n:
		_shadow_mm.set_instance_custom_data(i, _shadow_c[i])
		_shadow_mm.set_instance_transform(i, shadow_xform(_shadow_at[i], _shadow_c[i], _shadow_k[i]))
	_shadow_mm.visible_instance_count = _shadow_n


## Takes every placed prop `keep_out` says to (a Callable on the placed row) off the field, its shadow with it, and out
## of `placed` (the live title clears the hero's view before laying its own scene). Returns how many went.
func remove_where(keep_out: Callable) -> int:
	var gone := 0
	var kept: Array = []
	for row: Dictionary in placed:
		if not bool(keep_out.call(row)):
			kept.append(row)
			continue
		var t: Dictionary = _types.get(str(row.get("look", row["id"])), {})
		if not t.is_empty() and int(row.get("i", -1)) >= 0:
			var at: Vector3 = row["pos"]
			(t["mm"] as MultiMesh).set_instance_transform(int(row["i"]), Transform3D(Basis().scaled(Vector3.ZERO), at))
		hide_shadow(int(row.get("s", -1)))
		gone += 1
	placed = kept
	return gone


func count() -> int:
	var c := 0
	for t in _types.values():
		c += int(t["n"])
	return c
