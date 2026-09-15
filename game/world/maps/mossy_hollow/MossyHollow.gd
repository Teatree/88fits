## Mossy Hollow, the meadow map. Rolling grass hills with a pond, a flat clearing in the middle, a wall of trees,
## groves and giant mushrooms as obstacles, boulders, logs and stumps; three geysers, a bee swarm and fireflies
## instead of the desert's tumbleweeds and dust devil. Every number here is a tunable exported for the editor.
extends MapBase

@export var seed := 41
@export var hill_height := 2.2
@export var pond_center := Vector2(-24, -20)
@export var pond_radius := 11.0
@export var pond_depth := 1.7
@export var flats_radius := 16.0
@export var grass_color := Color(0.38, 0.62, 0.28)
@export var dirt_color := Color(0.36, 0.29, 0.18)
@export var wood_color := Color(0.36, 0.24, 0.14)
@export var leaf_color := Color(0.18, 0.42, 0.16)
@export var geysers := 3

var _static: StaticBody3D
var _noise := FastNoiseLite.new()
var _bark_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _rock_mat: StandardMaterial3D


func _ready() -> void:
	_noise.seed = seed
	_noise.frequency = 0.03
	_noise.fractal_octaves = 3
	flats_center = Vector3(0, 0, 8)
	_build_terrain()
	_build_pond()
	_build_wall()
	_build_props()
	_build_sky()
	_build_hazards()


# ---------------------------------------------------------------- terrain

func _terrain_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _noise.get_noise_2d(x, z) * hill_height + _noise.get_noise_2d(x * 3.0 + 50.0, z * 3.0) * 0.25
	var d_flat := (p - Vector2(flats_center.x, flats_center.z)).length()
	var flat_w: float = clamp((d_flat - flats_radius) / 8.0, 0.0, 1.0)
	h *= flat_w
	var pd := (p - pond_center).length()
	var pw: float = clamp(1.0 - pd / pond_radius, 0.0, 1.0)
	h -= pond_depth * smoothstep(0.0, 1.0, pw)
	return h


func _build_terrain() -> void:
	grid_n = int(size_m * resolution) + 1
	heights.resize(grid_n * grid_n)
	var half := size_m * 0.5
	for iz in range(grid_n):
		for ix in range(grid_n):
			var x := ix / resolution - half
			var z := iz / resolution - half
			heights[iz * grid_n + ix] = _terrain_height(x, z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(grid_n - 1):
		for ix in range(grid_n - 1):
			var x0 := ix / resolution - half
			var z0 := iz / resolution - half
			var x1 := x0 + 1.0 / resolution
			var z1 := z0 + 1.0 / resolution
			var p00 := Vector3(x0, heights[iz * grid_n + ix], z0)
			var p10 := Vector3(x1, heights[iz * grid_n + ix + 1], z0)
			var p01 := Vector3(x0, heights[(iz + 1) * grid_n + ix], z1)
			var p11 := Vector3(x1, heights[(iz + 1) * grid_n + ix + 1], z1)
			var c := _color_at(x0, z0, p00.y)
			# Godot front faces are clockwise: (x0,z0) -> (x1,z0) -> (x0,z1) seen from above
			st.set_color(c); st.add_vertex(p00)
			st.set_color(c); st.add_vertex(p10)
			st.set_color(c); st.add_vertex(p01)
			st.set_color(c); st.add_vertex(p10)
			st.set_color(c); st.add_vertex(p11)
			st.set_color(c); st.add_vertex(p01)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/shaders/terrain_painted.gdshader")
	if ResourceLoader.exists("res://art/env/grass.png") and ResourceLoader.exists("res://art/env/dirt.png"):
		mat.set_shader_parameter("sand_tex", load("res://art/env/grass.png"))
		mat.set_shader_parameter("cracked_tex", load("res://art/env/dirt.png"))
		mat.set_shader_parameter("sand_flat", Vector3(grass_color.r, grass_color.g, grass_color.b))
		mat.set_shader_parameter("cracked_flat", Vector3(dirt_color.r, dirt_color.g, dirt_color.b))
		mat.set_shader_parameter("tiles_per_metre", 0.11)
		mat.set_shader_parameter("calm", 0.45)
		mi.material_override = mat
	else:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = grass_color
		fallback.vertex_color_use_as_albedo = false
		mi.material_override = fallback
	add_child(mi)
	_static = StaticBody3D.new()
	_static.name = "TerrainBody"
	_static.collision_layer = 1
	var shape := HeightMapShape3D.new()
	shape.map_width = grid_n
	shape.map_depth = grid_n
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(1.0 / resolution, 1.0, 1.0 / resolution)
	_static.add_child(cs)
	add_child(_static)


func _color_at(x: float, z: float, h: float) -> Color:
	## r = dirt blend (pond shore, worn paths), g = shade multiplier. The painted terrain shader reads these.
	var pd := (Vector2(x, z) - pond_center).length()
	var shore: float = clamp(1.0 - absf(pd - pond_radius * 0.9) / 4.0, 0.0, 1.0)
	# worn paths: low-frequency noise with a soft edge, so the blend never turns into blocks on the 1 m grid
	var path := _noise.get_noise_2d(x * 0.9 + 300.0, z * 0.9 + 300.0)
	var worn: float = clamp((path - 0.24) * 1.4, 0.0, 0.5)
	var n := _noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0)
	var shade: float = clamp(1.0 - n * 0.3 + h * 0.06, 0.62, 1.15)
	return Color(maxf(shore, worn), shade, 0.0)


func _build_pond() -> void:
	# the water: a flat translucent disc just under the shore line, enemies path around it
	var water := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = pond_radius * 0.82
	cm.bottom_radius = pond_radius * 0.82
	cm.height = 0.1
	cm.radial_segments = 32
	water.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.22, 0.48, 0.62, 0.72)
	mat.roughness = 0.08
	mat.metallic = 0.2
	water.material_override = mat
	water.position = Vector3(pond_center.x, -pond_depth * 0.45, pond_center.y)
	add_child(water)
	# lily pads
	for k in range(9):
		var a := TAU * k / 9.0 + 0.4
		var r := pond_radius * randf_range(0.25, 0.7)
		var pad := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = randf_range(0.5, 0.9)
		pm.bottom_radius = pm.top_radius
		pm.height = 0.06
		pm.radial_segments = 10
		pad.mesh = pm
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.3, 0.6, 0.25)
		pad.material_override = lm
		pad.position = Vector3(pond_center.x + cos(a) * r, -pond_depth * 0.45 + 0.06, pond_center.y + sin(a) * r)
		add_child(pad)


# ---------------------------------------------------------------- materials and helpers

func _bark() -> StandardMaterial3D:
	if _bark_mat == null:
		_bark_mat = StandardMaterial3D.new()
		_bark_mat.albedo_color = wood_color
		_bark_mat.roughness = 1.0
	return _bark_mat


func _leaf() -> StandardMaterial3D:
	if _leaf_mat == null:
		_leaf_mat = StandardMaterial3D.new()
		_leaf_mat.albedo_color = leaf_color
		_leaf_mat.roughness = 1.0
	return _leaf_mat


func _rock() -> StandardMaterial3D:
	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		if ResourceLoader.exists("res://art/env/mossrock.png"):
			_rock_mat.albedo_texture = load("res://art/env/mossrock.png")
			_rock_mat.uv1_triplanar = true
			_rock_mat.uv1_world_triplanar = true
			_rock_mat.uv1_scale = Vector3(0.14, 0.14, 0.14)
		else:
			_rock_mat.albedo_color = Color(0.45, 0.5, 0.42)
		_rock_mat.roughness = 1.0
	return _rock_mat


func _box(p: Vector3, s: Vector3, mat: Material, obstacle_r := 0.0, rot_y := 0.0, visible := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = s
	cs.shape = shape
	body.add_child(cs)
	if visible:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = s
		mi.mesh = m
		mi.material_override = mat
		body.add_child(mi)
	body.position = p
	body.rotation.y = rot_y
	add_child(body)
	if obstacle_r > 0.0:
		obstacles.append(Vector3(p.x, p.z, obstacle_r))
	return body


func _cylinder(p: Vector3, r: float, h: float, mat: Material, obstacle := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	cs.position.y = h * 0.5
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	mi.mesh = m
	mi.position.y = h * 0.5
	mi.material_override = mat
	body.add_child(mi)
	body.position = p
	add_child(body)
	if obstacle:
		obstacles.append(Vector3(p.x, p.z, r + 0.2))
	return body


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## A Blender-built GLB prop from res://art/props/<name>.glb on a static body with a cylinder collider, or the
## `fallback` primitives when the GLB has not been generated yet.
func _prop(name: String, p: Vector3, collider_r: float, collider_h: float, rot_y := 0.0, scale := 1.0, fallback: Callable = Callable(), obstacle := true) -> Node3D:
	var path := "res://art/props/%s.glb" % name
	if not ResourceLoader.exists(path):
		if fallback.is_valid():
			return fallback.call()
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var body := StaticBody3D.new()
	body.collision_layer = 1
	if collider_r > 0.0:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = collider_r * scale
		shape.height = collider_h * scale
		cs.shape = shape
		cs.position.y = collider_h * scale * 0.5
		body.add_child(cs)
	var vis := scene.instantiate()
	vis.scale = Vector3.ONE * scale
	body.add_child(vis)
	body.position = p
	body.rotation.y = rot_y
	add_child(body)
	if obstacle and collider_r > 0.0:
		obstacles.append(Vector3(p.x, p.z, collider_r * scale + 0.2))
	return body


func _tree_fallback(g: Vector3, h: float, pine: bool) -> Node3D:
	var trunk := _cylinder(g, 0.45, h * 0.5, _bark())
	var crown := MeshInstance3D.new()
	if pine:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = h * 0.36
		cm.height = h * 0.8
		crown.mesh = cm
		crown.position.y = h * 0.75
	else:
		var sm := SphereMesh.new()
		sm.radius = h * 0.38
		sm.height = h * 0.7
		sm.radial_segments = 10
		sm.rings = 6
		crown.mesh = sm
		crown.position.y = h * 0.78
	crown.material_override = _leaf()
	trunk.add_child(crown)
	return trunk


# ---------------------------------------------------------------- wall of trees, props

func _build_wall() -> void:
	# a dense ring of tall trees just outside the arena, and an invisible fence a little inside
	var n := 48
	for k in range(n):
		var a := TAU * k / n
		var r := arena_radius + 3.5 + (k % 3) * 1.6
		var g := Vector3(cos(a) * r, 0.0, sin(a) * r)
		g.y = height_at(g.x, g.z)
		var h := 9.0 + (k % 4) * 1.5
		var pine := k % 2 == 0
		_prop("pine_tree" if pine else "oak_tree", g, 0.0, 0.0, randf() * TAU, h / 8.0, func(): return _tree_fallback(g, h, pine), false)
	for k in range(40):
		var a := TAU * k / 40.0
		var r := arena_radius
		var p := Vector3(cos(a) * r, 2.0, sin(a) * r)
		_box(p, Vector3(TAU * r / 40.0 + 1.0, 8.0, 0.5), _bark(), 0.0, -a + PI * 0.5, false)


func _build_props() -> void:
	# groves: clusters of oaks and pines that enemies path around
	var groves := [[Vector2(-44, 22), 5, false], [Vector2(40, -40), 6, true], [Vector2(46, 26), 4, false], [Vector2(-40, -48), 5, true],
		[Vector2(8, 52), 4, false], [Vector2(-8, -54), 4, true], [Vector2(56, -4), 3, false]]
	for gv in groves:
		var c: Vector2 = gv[0]
		var cnt: int = gv[1]
		var pine: bool = gv[2]
		for k in range(cnt):
			var a := TAU * k / cnt + randf() * 0.6
			var r := randf_range(2.5, 6.5)
			var pt := c + Vector2(cos(a), sin(a)) * r
			var g := _ground(pt.x, pt.y)
			var h := randf_range(6.0, 9.0)
			_prop("pine_tree" if pine else "oak_tree", g, 0.55, 3.0, randf() * TAU, h / 8.0, func(): return _tree_fallback(g, h, pine))
	# giant mushrooms in damp spots
	for c in [Vector2(-30, -8), Vector2(-34, -4), Vector2(-27, -2), Vector2(24, 40), Vector2(28, 44), Vector2(-14, 36), Vector2(36, 8)]:
		var g := _ground(c.x, c.y)
		var sc := randf_range(0.8, 1.35)
		_prop("mushroom_big", g, 0.7, 2.2, randf() * TAU, sc, func():
			var stem := _cylinder(g, 0.5 * sc, 1.8 * sc, StandardMaterial3D.new())
			var cap := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 1.3 * sc
			sm.height = 1.2 * sc
			cap.mesh = sm
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(0.8, 0.22, 0.18)
			cap.material_override = cm
			cap.position.y = 1.9 * sc
			stem.add_child(cap)
			return stem)
	# mossy boulders
	var rocks := [["boulder", Vector2(-10, 44)], ["rock_big", Vector2(-6, 47)], ["boulder", Vector2(56, -18)], ["rock_small", Vector2(58, -22)],
		["rock_big", Vector2(-58, 26)], ["rock_big", Vector2(22, -52)], ["boulder", Vector2(-44, -30)], ["rock_small", Vector2(36, 32)], ["rock_big", Vector2(12, -30)]]
	for r in rocks:
		var nm: String = r[0]
		var pt: Vector2 = r[1]
		var rr: float = {"rock_small": 0.9, "rock_big": 1.8, "boulder": 2.8}[nm]
		var g := _ground(pt.x, pt.y)
		var body := _prop(nm, g, rr, rr, randf() * TAU, 1.0, func(): return _cylinder(g, rr, rr * 0.8, _rock()))
		if body:
			for c in body.get_children():
				if c is Node3D and not (c is CollisionShape3D):
					_tint_moss(c)
	# logs and stumps, decoration with a small collider
	for l in [Vector2(-18, 20), Vector2(30, -12), Vector2(-50, 4), Vector2(14, 30)]:
		var g := _ground(l.x, l.y)
		_prop("log", g, 0.0, 0.0, randf() * TAU, 1.0, func():
			var mi := MeshInstance3D.new()
			var m := CylinderMesh.new()
			m.top_radius = 0.4
			m.bottom_radius = 0.45
			m.height = 3.2
			mi.mesh = m
			mi.rotation = Vector3(0, randf() * TAU, PI * 0.5)
			mi.position = g + Vector3(0, 0.4, 0)
			mi.material_override = _bark()
			add_child(mi)
			return mi, false)
	for s in [Vector2(-2, -22), Vector2(40, 14), Vector2(-36, 40)]:
		var g := _ground(s.x, s.y)
		_prop("stump", g, 0.7, 0.8, randf() * TAU, 1.0, func(): return _cylinder(g, 0.7, 0.8, _bark()))
	# a chest spot on the far hill, like the mesa tops in the desert
	spawn_points.append(_ground(44, -44) + Vector3(0, 0.2, 0))
	spawn_points.append(_ground(-46, 20) + Vector3(0, 0.2, 0))


func _tint_moss(n: Node3D) -> void:
	# GLB rocks are grey; a green tint makes them belong to the meadow
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.5, 0.58, 0.42)
			mat.roughness = 1.0
			mi.material_override = mat
		if c is Node3D:
			_tint_moss(c)


# ---------------------------------------------------------------- sky, light, hazards

func _build_sky() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if ResourceLoader.exists("res://art/env/sky_meadow.png"):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load("res://art/env/sky_meadow.png")
		pm.filter = true
		sky.sky_material = pm
	else:
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.32, 0.55, 0.9)
		sm.sky_horizon_color = Color(0.78, 0.86, 0.92)
		sm.ground_bottom_color = Color(0.25, 0.4, 0.2)
		sm.ground_horizon_color = Color(0.55, 0.7, 0.5)
		sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.88, 0.8)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.78, 0.7)
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-55, 120, 0)
	sun.shadow_enabled = false
	add_child(sun)
	# rolling hills outside the wall, dark green silhouettes
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.2, 0.36, 0.2)
	for k in range(12):
		var a := TAU * k / 12.0 + 0.15
		var r := arena_radius + 26.0 + (k % 3) * 9.0
		var hm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 16.0 + (k % 4) * 6.0
		sm.height = 14.0 + (k % 3) * 6.0
		sm.radial_segments = 12
		sm.rings = 6
		hm.mesh = sm
		hm.material_override = hill_mat
		hm.position = Vector3(cos(a) * r, -2.0, sin(a) * r)
		add_child(hm)


func _build_hazards() -> void:
	var spots := [Vector2(14, -6), Vector2(-12, 22), Vector2(22, 24), Vector2(-24, 8)]
	for k in range(mini(geysers, spots.size())):
		var g := Geyser.new()
		var sp: Vector2 = spots[k]
		g.phase = float(k) * 3.0
		add_child(g)
		g.global_position = _ground(sp.x, sp.y)
	var swarm := BeeSwarm.new()
	add_child(swarm)
	swarm.global_position = _ground(30, 30) + Vector3(0, 1.3, 0)
	var ff := Fireflies.new()
	add_child(ff)


func bind_game(game: Node) -> void:
	for c in get_children():
		if c is Geyser or c is BeeSwarm:
			c.game = game
