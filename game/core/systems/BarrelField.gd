## Wooden barrels (pass 44): forty-odd 3D barrels scattered over the map by the run's seed, each a little apart from the
## next, clear of the flats, the rocks, the water, the structures and the painted scenery (never behind a billboard:
## the camera looks north from above, so a painting covers the ground just north of its foot for about its height).
## Dark barrels are common; light ones are rarer and hold three times the gems. The hero walking up to one breaks it:
## it bursts into splinters and a puff of dust, drops a handful of XP gems, and the camera gives a small kick.
## Drawn as MultiMeshes of art/props/barrel.glb (`Body`, tinted light or dark; `Hoops`, iron).
class_name BarrelField
extends Node3D

const COUNT := 44
const LIGHT_FRAC := 0.22
const MIN_GAP := 6.5
const RADIUS := 0.31
const BREAK_REACH := 1.05
const CAMERA_PITCH_DEG := 46.0
const DARK := Color(0.40, 0.25, 0.13)
const LIGHT := Color(0.80, 0.60, 0.36)

var game: Node
var map: MapBase
var pos: PackedVector3Array = PackedVector3Array()
var light: PackedByteArray = PackedByteArray()
var alive: PackedByteArray = PackedByteArray()
var broken := 0
var _body_dark: MultiMesh
var _body_light: MultiMesh
var _hoops: MultiMesh
var _index_in: PackedInt32Array = PackedInt32Array()   # a barrel's instance index inside its body MultiMesh


func setup(p_game: Node, p_map: MapBase) -> void:
	game = p_game
	map = p_map
	var meshes := _meshes()
	if meshes.is_empty():
		return
	_place()
	var dark_n := 0
	for i in pos.size():
		if light[i] == 0:
			dark_n += 1
	_body_dark = _multimesh(meshes["body"], dark_n, _wood(DARK))
	_body_light = _multimesh(meshes["body"], pos.size() - dark_n, _wood(LIGHT))
	_hoops = _multimesh(meshes["hoops"], pos.size(), null)
	var kd := 0
	var kl := 0
	for i in pos.size():
		var yaw := float(i) * 2.399
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos[i])
		if light[i] == 0:
			_body_dark.set_instance_transform(kd, xf)
			_index_in.append(kd)
			kd += 1
		else:
			_body_light.set_instance_transform(kl, xf)
			_index_in.append(kl)
			kl += 1
		_hoops.set_instance_transform(i, xf)


func _meshes() -> Dictionary:
	if not ResourceLoader.exists("res://art/props/barrel.glb"):
		return {}
	var scene: Node = load("res://art/props/barrel.glb").instantiate()
	var out := {}
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.name.begins_with("Body"):
			out["body"] = mi.mesh
		elif mi.name.begins_with("Hoops"):
			out["hoops"] = mi.mesh
	scene.free()
	return out if out.has("body") and out.has("hoops") else {}


func _wood(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
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
		for c: Vector4 in covers:
			# a painting's foot at (x, z), half its width, and the ground band north of it that it covers on screen
			if absf(p.x - c.x) < c.z + RADIUS and p.y < c.y + 0.7 and p.y > c.y - c.w - RADIUS:
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
	var out: Array = []
	var cot := 1.0 / tan(deg_to_rad(CAMERA_PITCH_DEG))
	var props = map.get("props")
	if props is PropField:
		for row in (props as PropField).placed:
			var id := str(row["id"])
			var h: float = (props as PropField).height_of(id) * float(row["scale"])
			var at: Vector3 = row["pos"]
			out.append(Vector4(at.x, at.z, h * 0.5, h * cot))
	var sm = game.get("structures")
	if sm != null:
		for s in sm.items:
			var n = s.get("node")
			if n is Node3D:
				var at: Vector3 = (n as Node3D).global_position
				out.append(Vector4(at.x, at.z, 1.8, 3.2 * cot))
	return out


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
	else:
		_body_light.set_instance_transform(_index_in[i], gone)
	_hoops.set_instance_transform(i, gone)
	var wood := LIGHT if light[i] == 1 else DARK
	if game.fx:
		# staves, hoop pieces and a cloud of dust, big enough to read from the camera's height
		game.fx.splinters(at, wood, 22 if light[i] == 1 else 18, 0.27)
		game.fx.splinters(at, wood.darkened(0.3), 8, 0.16)
		game.fx.splinters(at, Color(0.22, 0.18, 0.16), 5, 0.15)
		game.fx.sand(at, 2.2)
		game.fx.burst(at + Vector3(0, 0.6, 0), Color(0.86, 0.7, 0.45), 1.3)
	# the gems: a small gem is worth more the deeper the run (a level needs 15 + 6L + L²/2)
	var per := 1.0 + float(Run.level) * 0.15
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


func alive_count() -> int:
	var n := 0
	for i in alive.size():
		n += alive[i]
	return n
