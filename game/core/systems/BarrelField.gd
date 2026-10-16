## Wooden barrels (pass 44): thirty-three 3D barrels (COUNT; forty-four until pass 45) scattered over the map by the run's
## seed, each a little apart from the next, clear of the flats, the rocks, the water, the structures and the painted
## scenery (never behind a billboard: the camera looks north from above, so a painting covers the ground just north of
## its foot for about its height).
## Dark barrels are common; the rare ones (`light`, they hold three times the gems) are matte black with brass hoops since
## pass 48 (Garry: black), so the good barrel still reads as the good one. The hero walking up to one breaks it:
## it bursts into splinters and a puff of dust, drops a handful of XP gems, and the camera gives a small kick.
## Drawn as MultiMeshes of art/props/barrel.glb (`Body`, tinted dark or black; `Hoops`, iron on the common ones and brass
## on the rare ones, a MultiMesh each).
## Barrel Rush (pass 47, a passive): every barrel he smashes starts or refreshes a speed boost (Run.barrel_rush) and the
## game shows it on him (Game.barrel_rush_fx).
class_name BarrelField
extends Node3D

const COUNT := 33
const LIGHT_FRAC := 0.22
const MIN_GAP := 6.5
const RADIUS := 0.31
const BREAK_REACH := 1.05
const CAMERA_PITCH_DEG := 46.0
## a structure's painting is about this wide either side of its foot (the cover band's half width, pass 54)
const STRUCTURE_HALF_W := 1.8
## and a barrel stands at least this far outside a structure's ring (pass 54)
const RING_CLEAR := 0.5
const DARK := Color(0.40, 0.25, 0.13)
## the rare barrel's body (pass 48: matte black; it was a light wood, Color(0.80, 0.60, 0.36)) and its hoops
const LIGHT := Color(0.05, 0.05, 0.06)
const BRASS := Color(0.85, 0.62, 0.22)

var game: Node
var map: MapBase
var pos: PackedVector3Array = PackedVector3Array()
var light: PackedByteArray = PackedByteArray()
var alive: PackedByteArray = PackedByteArray()
var broken := 0
var _body_dark: MultiMesh
var _body_light: MultiMesh
var _hoops: MultiMesh          # the common barrels' iron hoops
var _hoops_light: MultiMesh    # the rare barrels' brass hoops (pass 48)
var _index_in: PackedInt32Array = PackedInt32Array()   # a barrel's instance index inside its body (and hoop) MultiMesh
## Pass 83 (lane SCENE; Garry: "barrels, signs, and structures too. Want them to feel like they are part of the world"):
## each barrel stands on a ground shadow in the scenery's shadow MultiMesh (PropField.add_shadow, the map's props), this
## wide and deep (metres), this dark, shifted by the sun for a thing SHADOW_TALL high; gone when the barrel breaks.
const SHADOW_W := 0.95
const SHADOW_D := 0.66
const SHADOW_A := 0.5
const SHADOW_TALL := 0.9
var shadows: PackedInt32Array = PackedInt32Array()
var _part_xf: Dictionary = {}   # "body" / "hoops" -> Transform3D: where each part stands inside the model (pass 53)


func setup(p_game: Node, p_map: MapBase) -> void:
	game = p_game
	map = p_map
	var meshes := _meshes()
	if meshes.is_empty():
		return
	# each part's place inside the model (pass 53: the hoops' node stands 0.126 m up; dropped, every hoop drew 12.6 cm
	# too low and the bottom one sat half in the sand)
	_part_xf = {"body": meshes.get("body_xf", Transform3D.IDENTITY), "hoops": meshes.get("hoops_xf", Transform3D.IDENTITY)}
	_place()
	var dark_n := 0
	for i in pos.size():
		if light[i] == 0:
			dark_n += 1
	_body_dark = _multimesh(meshes["body"], dark_n, _wood(DARK))
	_body_light = _multimesh(meshes["body"], pos.size() - dark_n, _black())
	_hoops = _multimesh(meshes["hoops"], dark_n, null)
	_hoops_light = _multimesh(meshes["hoops"], pos.size() - dark_n, _brass())
	var kd := 0
	var kl := 0
	for i in pos.size():
		if light[i] == 0:
			_body_dark.set_instance_transform(kd, instance_transform(i, "body"))
			_hoops.set_instance_transform(kd, instance_transform(i, "hoops"))
			_index_in.append(kd)
			kd += 1
		else:
			_body_light.set_instance_transform(kl, instance_transform(i, "body"))
			_hoops_light.set_instance_transform(kl, instance_transform(i, "hoops"))
			_index_in.append(kl)
			kl += 1
	_add_shadows()


## The barrels' ground shadows (pass 83), one each in the map's scenery shadows; none on a map without props.
func _add_shadows() -> void:
	shadows.clear()
	var props = map.get("props") if map else null
	for i in pos.size():
		shadows.append(props.add_shadow(pos[i], SHADOW_W, SHADOW_D, SHADOW_A, SHADOW_TALL) if props is PropField else -1)


## A barrel's own place on the map: turned by its index (no two face the same way), standing on its spot.
func barrel_transform(i: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(i) * 2.399), pos[i])


## Where a part ("body" or "hoops") of barrel `i` is drawn: the barrel's place with the part's own place inside the model
## (pass 53: the hoops 0.126 m up). The headless renderer keeps no instance transforms, so the tests read this.
func instance_transform(i: int, part: String) -> Transform3D:
	return barrel_transform(i) * (_part_xf.get(part, Transform3D.IDENTITY) as Transform3D)


## The model's two parts: `body` and `hoops` are the meshes, `body_xf` and `hoops_xf` where each part stands inside the
## GLB (pass 53: the `Hoops` node keeps the origin Blender's join gave it, the lowest hoop's at y 0.126; the mesh alone
## put that hoop's middle on the ground). Empty when the model is missing a part.
func _meshes() -> Dictionary:
	if not ResourceLoader.exists("res://art/props/barrel.glb"):
		return {}
	var scene: Node = load("res://art/props/barrel.glb").instantiate()
	var out := {}
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var key := ""
		if mi.name.begins_with("Body"):
			key = "body"
		elif mi.name.begins_with("Hoops"):
			key = "hoops"
		if key != "":
			out[key] = mi.mesh
			out[key + "_xf"] = part_transform(scene, mi)
	scene.free()
	return out if out.has("body") and out.has("hoops") else {}


## Where `node` stands inside the model whose root is `root`: its own transform under every Node3D above it, the root's
## included (the scene is not in a tree, so no global transform is asked for).
static func part_transform(root: Node, node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		if p == root:
			break
		p = p.get_parent()
	return xf


func _wood(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


## The rare barrel's paint (pass 48): matte black, no shine.
func _black() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = LIGHT
	m.roughness = 0.95
	m.metallic = 0.0
	return m


## The rare barrel's hoops (pass 48): brass, a little metal so they catch the light against the black.
func _brass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = BRASS
	m.metallic = 0.4
	m.roughness = 0.45
	return m


func _multimesh(mesh: Mesh, n: int, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = maxi(n, 1)
	mm.visible_instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	# pass 72: scenery (a creature a barrel hides is outlined, SceneryStencil)
	SceneryStencil.mark_tree(mmi)
	add_child(mmi)
	return mm


## Spots at least MIN_GAP apart, clear of everything that would hide or crowd a barrel; the gap relaxes when the map
## fights back, so there are always COUNT of them.
func _place() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Run.map_seed * 13 + 7
	var fc := Vector2(map.flats_center.x, map.flats_center.z)
	var start := map.player_start()
	var covers: Array = _covers()
	var rings: Array = structure_rings(game)
	var tries := 0
	var limit := COUNT * 400
	while pos.size() < COUNT and tries < limit:
		tries += 1
		var relax := 1.0 - 0.6 * clampf(float(tries) / float(limit), 0.0, 1.0)
		var a := rng.randf() * TAU
		var r := rng.randf_range(map.arena_radius * 0.12, map.arena_radius * 0.92)
		var p := Vector2(cos(a) * r, sin(a) * r)
		if (p - fc).length() < map.flats_radius * 0.5:
			continue
		if p.distance_to(Vector2(start.x, start.z)) < 5.0:
			continue
		if map.has_method("in_water") and map.in_water(Vector3(p.x, 0, p.y)):
			continue
		var ok := true
		for o: Vector3 in map.obstacles:
			if p.distance_to(Vector2(o.x, o.y)) < o.z + RADIUS + 0.9:
				ok = false
				break
		if not ok:
			continue
		if in_cover(covers, p, RADIUS):
			continue
		# never inside a structure's ring either (pass 54: its cover band only reaches 0.7 m south of the foot)
		for g: Vector3 in rings:
			if p.distance_to(Vector2(g.x, g.y)) < g.z + RADIUS + RING_CLEAR:
				ok = false
				break
		if not ok:
			continue
		for q in pos:
			if p.distance_to(Vector2(q.x, q.z)) < MIN_GAP * relax:
				ok = false
				break
		if not ok:
			continue
		pos.append(Vector3(p.x, map.height_at(p.x, p.y), p.y))
		light.append(1 if rng.randf() < LIGHT_FRAC else 0)
		alive.append(1)


## Every billboard on the map as (x, z, half width, cover length north): the painted scenery and the structures.
func _covers() -> Array:
	return covers_of(game, map)


## The cover bands of `map`'s painted scenery and of `game`'s structures, as (x, z, half width, cover length north)
## (pass 54: shared with SignField). A structure is its own Node3D (StructureManager.items); the band used to be read off
## a `node` field no Structure has, so it never counted and barrels landed behind the paintings.
static func covers_of(p_game: Node, p_map: Node) -> Array:
	var out: Array = []
	var cot := 1.0 / tan(deg_to_rad(CAMERA_PITCH_DEG))
	var props = p_map.get("props") if p_map != null else null
	if props is PropField:
		for row in (props as PropField).placed:
			var id := str(row["id"])
			var h: float = (props as PropField).height_of(id) * float(row["scale"])
			var at: Vector3 = row["pos"]
			out.append(Vector4(at.x, at.z, h * 0.5, h * cot))
	for s in structures_of(p_game):
		var at := structure_position(s)
		var d = s.get("def")
		var tall: float = float(d.height) if d != null else 3.2
		out.append(Vector4(at.x, at.z, STRUCTURE_HALF_W, tall * cot))
	return out


## Inside any cover band, for something `r` metres round standing at `p` (x, z)? A band runs from 0.7 m south of the
## painting's foot to its cover length north of it (the camera looks north from above), its half width either side.
static func in_cover(covers: Array, p: Vector2, r: float) -> bool:
	for c: Vector4 in covers:
		if absf(p.x - c.x) < c.z + r and p.y < c.y + 0.7 and p.y > c.y - c.w - r:
			return true
	return false


## Every structure's ring as (x, z, radius) (pass 54).
static func structure_rings(p_game: Node) -> Array:
	var out: Array = []
	for s in structures_of(p_game):
		var at := structure_position(s)
		var d = s.get("def")
		out.append(Vector3(at.x, at.z, float(d.radius) if d != null else 2.2))
	return out


## The game's structures (StructureManager.items, Structure nodes), none when it has none.
static func structures_of(p_game: Node) -> Array:
	var out: Array = []
	var sm = p_game.get("structures") if p_game != null else null
	if not (sm is Object) or not is_instance_valid(sm):
		return out
	var items = sm.get("items")
	if not (items is Array):
		return out
	for s in items:
		if s is Node3D and is_instance_valid(s):
			out.append(s)
	return out


## Where a structure stands: its global position once it is in the tree (Game._ready), its own position before.
static func structure_position(s: Node3D) -> Vector3:
	return s.global_position if s.is_inside_tree() else s.position


func _physics_process(_delta: float) -> void:
	if game == null or pos.is_empty() or bool(game.get("paused")) or game.player == null or game.player.dead:
		return
	var pp: Vector3 = game.player.global_position
	for i in pos.size():
		if alive[i] == 0:
			continue
		var d := Vector2(pp.x - pos[i].x, pp.z - pos[i].z).length()
		if d < RADIUS + BREAK_REACH:
			_break(i)


## The barrel bursts: splinters in its own wood, dust, gems (three times as many from a light one), a crack and a kick.
func _break(i: int) -> void:
	alive[i] = 0
	broken += 1
	var at := pos[i]
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), at)
	if light[i] == 0:
		_body_dark.set_instance_transform(_index_in[i], gone)
		if _hoops:
			_hoops.set_instance_transform(_index_in[i], gone)
	else:
		_body_light.set_instance_transform(_index_in[i], gone)
		if _hoops_light:
			_hoops_light.set_instance_transform(_index_in[i], gone)
	if i < shadows.size() and shadows[i] >= 0 and map and map.get("props") is PropField:
		(map.get("props") as PropField).hide_shadow(shadows[i])
	var wood := LIGHT if light[i] == 1 else DARK
	if game.fx:
		# staves, hoop pieces and a cloud of dust, big enough to read from the camera's height (a rare one's are black
		# with brass)
		game.fx.splinters(at, wood, 22 if light[i] == 1 else 18, 0.27)
		game.fx.splinters(at, wood.lightened(0.15) if light[i] == 1 else wood.darkened(0.3), 8, 0.16)
		game.fx.splinters(at, BRASS if light[i] == 1 else Color(0.22, 0.18, 0.16), 5, 0.15)
		game.fx.sand(at, 2.2)
		game.fx.burst(at + Vector3(0, 0.6, 0), Color(0.86, 0.7, 0.45), 1.3)
	# the gems: a small gem is worth more the deeper the run (a level needs 15 + 6L + L²/2)
	# pass 79 (lane MUT): the card levels (Run.card_level), so a barrel pays at a minute what it paid before
	var per := 1.0 + float(Run.card_level()) * 0.15
	var pk = game.pickups
	if pk:
		var n_small := 8 if light[i] == 0 else 10
		for k in n_small:
			pk.spawn(pk.KIND_GEM_S, at + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5)), per)
		if light[i] == 1:
			for k in 4:
				pk.spawn(pk.KIND_GEM_M, at + Vector3(randf_range(-0.6, 0.6), 0.5, randf_range(-0.6, 0.6)), per * 4.0)
	Audio.play("st_barrel_break", at)
	if game.camera:
		game.camera.shake(0.45 if light[i] == 1 else 0.3)
	if game.hud and light[i] == 1:
		game.hud.toast("A GOOD BARREL", Color(1.0, 0.85, 0.4))
	_rush()


## Barrel Rush (pass 47, Garry: "Smacking Barrels Causes Player to get a speed boost"): Run starts or refreshes the boost
## when the hero holds it; the game bursts gold round him (`fresh` when none was running). True when it did.
func _rush() -> bool:
	var fresh := Run.boost_left(Run.BARREL_RUSH) <= 0.0
	if not Run.barrel_rush():
		return false
	if game != null and game.has_method("barrel_rush_fx"):
		game.barrel_rush_fx(fresh)
	return true


func alive_count() -> int:
	var n := 0
	for i in alive.size():
		n += alive[i]
	return n
