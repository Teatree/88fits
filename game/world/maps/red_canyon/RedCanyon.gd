## Red Canyon. Nothing here is a 3D prop: the ground (dunes, one sunken dry river, one oasis lake, a flat centre, a
## red-rock rim), a rugged mountain wall around the arena with ranges beyond it, and painted 2.5D scenery, structures,
## tumbleweeds and a dust devil on top. The layout rolls per run (Run.map_seed): the river's course, the lake's place,
## the dunes and where the scenery stands; the wall, the flats and the rim never move. Every number here is a tunable
## exported for the editor.
extends MapBase

@export var seed := 88
@export var dune_height := 1.5
@export var river_depth := 2.0
@export var river_width := 6.0
@export var flats_radius := 16.0
@export var sand_color := Color(0.85, 0.66, 0.39)
@export var river_color := Color(0.70, 0.46, 0.26)
@export var wall_color := Color(0.56, 0.31, 0.17)
@export var tumbleweeds := 6
@export var lake_depth := 0.45

## the run's roll: the river's waypoints, the lake's centre, radius, water level and floor
var _river: Array = []
var _lake_c := Vector2(30, -20)
var _lake_r := 6.5
var _lake_y := 0.0
var _lake_floor := -1.4
var _rng := RandomNumberGenerator.new()
var run_seed := 0
## the rim: the ground rises into red rock towards the wall, from this radius out
@export var rim_start := 44.0
@export var rim_height := 2.2

var _static: StaticBody3D
var _noise := FastNoiseLite.new()
var props: PropField


func _ready() -> void:
	run_seed = seed
	if Run.map_seed != 0:
		run_seed = Run.map_seed
	_rng.seed = run_seed
	_noise.seed = run_seed
	_noise.frequency = 0.045
	_noise.fractal_octaves = 3
	flats_center = Vector3(0, 0, 8)
	_roll_layout()
	_build_terrain()
	_build_wall()
	_build_lake()
	_build_props()
	_build_sky()
	_build_movers()


# ---------------------------------------------------------------- the roll

## The run's layout: one dry river from rim to rim with a wandering middle that bends around the flats, and one oasis
## lake off the river and the flats, well inside the wall.
func _roll_layout() -> void:
	var fc := Vector2(flats_center.x, flats_center.z)
	var a0 := _rng.randf() * TAU
	var a1 := a0 + PI + _rng.randf_range(-0.7, 0.7)
	var rr := arena_radius + 6.0
	var p0 := Vector2(cos(a0), sin(a0)) * rr
	var p1 := Vector2(cos(a1), sin(a1)) * rr
	var perp := (p1 - p0).normalized().rotated(PI * 0.5)
	var n := 6
	_river.clear()
	for k in range(n + 1):
		var f := float(k) / float(n)
		var pt := p0.lerp(p1, f)
		if k > 0 and k < n:
			pt += perp * _rng.randf_range(-14.0, 14.0)
			var d := pt - fc
			var keep := flats_radius + river_width + 4.0
			if d.length() < keep:
				pt = fc + (d.normalized() if d.length() > 0.01 else Vector2(1, 0)) * keep
		_river.append(pt)
	_lake_r = _rng.randf_range(5.5, 7.5)
	_lake_c = Vector2(0, -34)
	for tries in range(200):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(24.0, arena_radius - 18.0)
		var c := Vector2(cos(a) * r, sin(a) * r)
		if (c - fc).length() < flats_radius + _lake_r + 8.0:
			continue
		if _river_dist(c) < river_width * 0.5 + _lake_r + 5.0:
			continue
		_lake_c = c
		break
	var base := _noise.get_noise_2d(_lake_c.x, _lake_c.y) * dune_height
	# a wading pool: the floor is knee-deep under a surface level with the shore, and anyone can walk in
	_lake_y = base - 0.04
	_lake_floor = base - lake_depth


func river_points() -> Array:
	return _river


func lake_center() -> Vector2:
	return _lake_c


func lake_radius() -> float:
	return _lake_r


# ---------------------------------------------------------------- terrain

func _river_dist(p: Vector2) -> float:
	var best := 1e9
	for k in range(_river.size() - 1):
		var a: Vector2 = _river[k]
		var b: Vector2 = _river[k + 1]
		var ab := b - a
		var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = min(best, (a + ab * t - p).length())
	return best


func _lake_dist(p: Vector2) -> float:
	return (p - _lake_c).length()


## How far into the red-rock rim a point is, 0 on the sand to 1 at the wall.
func _rim(p: Vector2) -> float:
	return clampf((p.length() - rim_start) / maxf(arena_radius - rim_start, 1.0), 0.0, 1.0)


func _in_mesa(_p: Vector2) -> bool:
	return false


func _terrain_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _noise.get_noise_2d(x, z) * dune_height
	var d_flat := (p - Vector2(flats_center.x, flats_center.z)).length()
	var flat_w: float = clamp((d_flat - flats_radius) / 8.0, 0.0, 1.0)
	h *= flat_w
	var rd := _river_dist(p)
	var rw: float = clamp(1.0 - rd / river_width, 0.0, 1.0)
	h -= river_depth * smoothstep(0.0, 1.0, rw) * flat_w
	# the rim climbs into broken red rock towards the wall
	var rim := _rim(p)
	h += rim_height * rim * rim + _noise.get_noise_2d(x * 2.5 + 40.0, z * 2.5) * rim * 1.2
	# the oasis: a shallow dish with a flat floor under the water
	var dl := _lake_dist(p)
	if dl < _lake_r * 1.6:
		var w := 1.0 - smoothstep(_lake_r * 0.7, _lake_r * 1.6, dl)
		h = lerpf(h, _lake_floor, w)
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
	# mesh
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
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/shaders/terrain_painted.gdshader")
	if ResourceLoader.exists("res://art/env/sand.png") and ResourceLoader.exists("res://art/env/cracked.png"):
		mat.set_shader_parameter("sand_tex", load("res://art/env/sand.png"))
		mat.set_shader_parameter("cracked_tex", load("res://art/env/cracked.png"))
		if ResourceLoader.exists("res://art/env/redrock.png"):
			mat.set_shader_parameter("rock_tex", load("res://art/env/redrock.png"))
	else:
		var fallback := StandardMaterial3D.new()
		fallback.vertex_color_use_as_albedo = true
		mi.material_override = fallback
	if mi.material_override == null:
		mi.material_override = mat
	add_child(mi)
	# collision
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
	## r = riverbed blend, g = shade multiplier, b = red-rock blend. The painted terrain shader reads these.
	var rd := _river_dist(Vector2(x, z))
	var t: float = clamp(1.0 - rd / (river_width * 0.9), 0.0, 1.0)
	# a damp ring around the water, but never under it: the dark cracked earth showing through a half-transparent
	# disc turned the blue to grey mud
	var dl2 := _lake_dist(Vector2(x, z))
	var shore := smoothstep(_lake_r * 0.75, _lake_r * 1.05, dl2) * (1.0 - smoothstep(_lake_r * 1.15, _lake_r * 1.9, dl2))
	t = maxf(t, shore * 0.35)
	var n := _noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0)
	var shade: float = clamp(1.0 - n * 0.35 + h * 0.05, 0.6, 1.15)
	var rock: float = clampf(_rim(Vector2(x, z)) * 1.6 + n * 0.3, 0.0, 1.0)
	return Color(t, shade, rock)


# ---------------------------------------------------------------- geometry helpers

var _stone_mat: StandardMaterial3D


func _stone() -> StandardMaterial3D:
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		if ResourceLoader.exists("res://art/env/sandstone.png"):
			_stone_mat.albedo_texture = load("res://art/env/sandstone.png")
			_stone_mat.uv1_triplanar = true
			_stone_mat.uv1_world_triplanar = true
			_stone_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
		else:
			_stone_mat.albedo_color = wall_color
		_stone_mat.roughness = 1.0
	return _stone_mat


func _box(p: Vector3, s: Vector3, color: Color, obstacle_r := 0.0, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = s
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = s
	mi.mesh = m
	if color == wall_color or color == Color(0.72, 0.42, 0.24) or color == Color(0.83, 0.63, 0.42):
		mi.material_override = _stone()
		if color != wall_color:
			mi.material_override = _stone().duplicate()
			mi.material_override.albedo_color = color.lightened(0.15)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 1.0
		mi.material_override = mat
	body.add_child(mi)
	body.position = p
	body.rotation.y = rot_y
	add_child(body)
	if obstacle_r > 0.0:
		obstacles.append(Vector3(p.x, p.z, obstacle_r))
	return body


func _cylinder(p: Vector3, r: float, h: float, color: Color, obstacle := true) -> StaticBody3D:
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)
	body.position = p
	add_child(body)
	if obstacle:
		obstacles.append(Vector3(p.x, p.z, r + 0.2))
	return body


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


# ---------------------------------------------------------------- the wall

func _build_wall() -> void:
	# the mountain wall: a ring of cliff faces whose height wanders, one mesh, stone-textured; the ranges beyond are
	# the same ring twice more, bigger and darker, so the horizon has depth without a single box
	var near := _stone().duplicate()
	near.albedo_color = Color(0.78, 0.6, 0.5)   # a shade darker than the ground so the cliffs read as cliffs
	add_child(_ridge(arena_radius + 4.0, 9.0, 6.0, 96, near, 1.0))
	var far := _stone().duplicate()
	far.albedo_color = Color(0.62, 0.42, 0.36)
	add_child(_ridge(arena_radius + 26.0, 16.0, 9.0, 72, far, 2.3))
	var farther := _stone().duplicate()
	farther.albedo_color = Color(0.46, 0.30, 0.30)
	add_child(_ridge(arena_radius + 52.0, 24.0, 12.0, 60, farther, 5.1))
	# the boundary itself: a low stacked-stone wall right on the arena's edge, with posts and skulls, so the line the
	# hero cannot cross is a thing in the world and not a place where he stops for no reason
	add_child(_boundary_wall(arena_radius, 120))
	# invisible fence a little inside so the player never wedges into the cliffs
	var n := 40
	for k2 in range(n):
		var a := TAU * k2 / n
		var r := arena_radius - 1.1   # the wall's inner face, so the hero stops at the stone and not inside it
		var p := Vector3(cos(a) * r, 2.0, sin(a) * r)
		var body := _box(p, Vector3(TAU * r / n + 1.0, 8.0, 0.5), wall_color, 0.0, -a + PI * 0.5)
		for c in body.get_children():
			if c is MeshInstance3D:
				c.visible = false


## The stacked-stone boundary: a ring wall 1.7 m thick and about 3 m tall with battlements (every other block stands a
## step higher), a dark cap, both faces and the cap as one mesh, vertex-coloured (sRGB, so the stone stays as dark as
## authored) so the courses read; boulders along the cap in one MultiMesh, tall wooden posts every ten degrees and a
## skull on every fourth post.
func _boundary_wall(r: float, segs: int) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var thick := 1.7
	var base_h := 2.7
	var tops: Array = []
	for k2 in range(segs):
		var a := TAU * (float(k2) + 0.5) / segs
		var nh := _noise.get_noise_2d(cos(a) * 80.0 + 700.0, sin(a) * 80.0)
		tops.append(base_h + 0.35 * nh + (0.5 if k2 % 2 == 0 else 0.0) + 0.1 * sin(a * 41.0))
	var stone := Color(0.60, 0.40, 0.30)
	var light := Color(0.68, 0.47, 0.35)
	var cap := Color(0.40, 0.26, 0.21)
	var riser := Color(0.34, 0.22, 0.18)
	var ri := r - thick * 0.5
	var ro := r + thick * 0.5
	for k2 in range(segs):
		var a0 := TAU * k2 / segs
		var a1 := TAU * (k2 + 1) / segs
		var g0 := height_at(cos(a0) * (r - 1.0), sin(a0) * (r - 1.0)) - 0.8
		var g1 := height_at(cos(a1) * (r - 1.0), sin(a1) * (r - 1.0)) - 0.8
		var h: float = tops[k2]
		var bi0 := Vector3(cos(a0) * ri, g0, sin(a0) * ri)
		var bi1 := Vector3(cos(a1) * ri, g1, sin(a1) * ri)
		var bo0 := Vector3(cos(a0) * ro, g0, sin(a0) * ro)
		var bo1 := Vector3(cos(a1) * ro, g1, sin(a1) * ro)
		var ti0 := bi0 + Vector3(0, h, 0)
		var ti1 := bi1 + Vector3(0, h, 0)
		var to0 := bo0 + Vector3(0, h, 0)
		var to1 := bo1 + Vector3(0, h, 0)
		# alternate blocks a shade apart so the courses read as stone
		var c := stone if k2 % 2 == 0 else light
		# inner face (towards the arena), wound so it faces inward
		_quad(st, bi1, bi0, ti0, ti1, c)
		# outer face
		_quad(st, bo0, bo1, to1, to0, c.darkened(0.25))
		# the cap
		_quad(st, ti0, to0, to1, ti1, cap)
		# the step up or down to the previous block, across the thickness
		var hp: float = tops[(k2 - 1 + segs) % segs]
		var pi0 := bi0 + Vector3(0, hp, 0)
		var po0 := bo0 + Vector3(0, hp, 0)
		_quad(st, pi0, po0, to0, ti0, riser)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)
	# boulders along the cap: one multimesh of rough blocks, every other one on the low blocks
	var bm := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 0.75, 0.9)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.5, 0.33, 0.26)
	bmat.roughness = 1.0
	box.material = bmat
	mm.mesh = box
	var bn := segs / 3
	mm.instance_count = bn
	for k2 in range(bn):
		var a := TAU * (float(k2 * 3) + 1.5) / segs + 0.3 * _noise.get_noise_1d(float(k2) * 9.0)
		var px := cos(a) * (r + 0.15 * _noise.get_noise_1d(float(k2) * 3.0))
		var pz := sin(a) * (r + 0.15 * _noise.get_noise_1d(float(k2) * 3.0))
		var seg := int(floor(a / TAU * segs)) % segs
		var gy := height_at(cos(a) * (r - 1.0), sin(a) * (r - 1.0)) - 0.8 + float(tops[seg]) + 0.25
		var sc := 0.8 + 0.5 * absf(_noise.get_noise_1d(float(k2) * 5.0 + 40.0))
		var t := Transform3D(Basis.from_euler(Vector3(0.12 * _noise.get_noise_1d(float(k2) + 3.0), -a + 0.4 * _noise.get_noise_1d(float(k2) * 2.0), 0)).scaled(Vector3(sc, sc, sc)), Vector3(px, gy, pz))
		mm.set_instance_transform(k2, t)
	bm.multimesh = mm
	root.add_child(bm)
	# posts and skulls: the posts are one MultiMesh (pass 33.8: 36 meshes with a material each, a draw call apiece)
	var post_n := 36
	var skull_scene: PackedScene = load("res://art/props/skull.glb") if ResourceLoader.exists("res://art/props/skull.glb") else null
	var cm := CylinderMesh.new()
	cm.top_radius = 0.11
	cm.bottom_radius = 0.15
	cm.height = 4.0
	cm.radial_segments = 6
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = cm
	pmm.instance_count = post_n
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.36, 0.25, 0.16)
	pm.roughness = 1.0
	var posts := MultiMeshInstance3D.new()
	posts.name = "Posts"
	posts.multimesh = pmm
	posts.material_override = pm
	root.add_child(posts)
	for k2 in range(post_n):
		var a := TAU * k2 / post_n + 0.04
		var px := cos(a) * (r - 1.3)
		var pz := sin(a) * (r - 1.3)
		var gy := height_at(px, pz)
		pmm.set_instance_transform(k2, Transform3D(Basis.from_euler(Vector3(0, 0, 0.05 * sin(a * 5.0))), Vector3(px, gy + 1.6, pz)))
		if k2 % 4 == 0 and skull_scene:
			var sk: Node3D = skull_scene.instantiate()
			sk.position = Vector3(px, gy + 3.7, pz)
			sk.rotation.y = -a + PI * 0.5
			sk.scale = Vector3.ONE * 0.9
			root.add_child(sk)
	return root


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color) -> void:
	for v in [p0, p1, p2, p0, p2, p3]:
		st.set_color(c)
		st.add_vertex(v)


## A ring of cliffs: an inner face that leans outward, a jagged top, height wandering with noise around the ring.
func _ridge(r: float, h: float, h_var: float, segs: int, mat: Material, noise_off: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops: Array = []
	for k2 in range(segs + 1):
		var a := TAU * float(k2 % segs) / segs
		var nh := _noise.get_noise_2d(cos(a) * 30.0 + noise_off * 100.0, sin(a) * 30.0)
		tops.append(h + h_var * nh + h_var * 0.35 * sin(a * 7.0 + noise_off))
	for k2 in range(segs):
		var a0 := TAU * k2 / segs
		var a1 := TAU * (k2 + 1) / segs
		var g0 := height_at(cos(a0) * minf(r, arena_radius - 1.0), sin(a0) * minf(r, arena_radius - 1.0)) - 3.0
		var g1 := height_at(cos(a1) * minf(r, arena_radius - 1.0), sin(a1) * minf(r, arena_radius - 1.0)) - 3.0
		var b0 := Vector3(cos(a0) * r, g0, sin(a0) * r)
		var b1 := Vector3(cos(a1) * r, g1, sin(a1) * r)
		var t0 := Vector3(cos(a0) * (r + 4.0), float(tops[k2]), sin(a0) * (r + 4.0))
		var t1 := Vector3(cos(a1) * (r + 4.0), float(tops[k2 + 1]), sin(a1) * (r + 4.0))
		var back0 := t0 + Vector3(cos(a0), 0, sin(a0)) * 12.0 - Vector3(0, 2.0, 0)
		var back1 := t1 + Vector3(cos(a1), 0, sin(a1)) * 12.0 - Vector3(0, 2.0, 0)
		# inner face (seen from the arena: clockwise), then the sloping top
		for tri in [[b0, t0, b1], [t0, t1, b1], [t0, back0, t1], [back0, back1, t1]]:
			for p in tri:
				st.add_vertex(p)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	# both windings are used around the ring (the faces run either way past the arena's axis), so no culling here
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The oasis: a rippling water disc in the dish (core/shaders/oasis_water.gdshader), a collider and an obstacle
## circle so nobody walks into it.
func _build_lake() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Oasis"
	var cm := CylinderMesh.new()
	cm.top_radius = _lake_r * 1.06
	cm.bottom_radius = _lake_r * 1.06
	cm.height = 0.08
	cm.radial_segments = 40
	cm.rings = 1
	mi.mesh = cm
	# the simplest water there is: one flat half-transparent colour, unshaded, no texture, no ripple, no shore fade
	# (a shader with waves in it read as a patterned disc lying on the sand)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.07, 0.42, 0.64, 0.82)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	# under the ground marks (their pools draw at priority -5..-1, pass 33.8), so a red ring on the lake bed always reads
	mat.render_priority = -10
	mi.material_override = mat
	mi.position = Vector3(_lake_c.x, _lake_y, _lake_c.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Standing in the water? (the hero's ripples, Game)
func in_water(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(_lake_c) < _lake_r * 1.02


func _build_props() -> void:
	# painted scenery only: cacti, trees, bushes, rocks, bones and signposts, placed by region from the run's roll
	_scatter_sprites()


func _build_sky() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if ResourceLoader.exists("res://art/env/sky_panorama.png"):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load("res://art/env/sky_panorama.png")
		pm.filter = true
		sky.sky_material = pm
	else:
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.21, 0.14, 0.31)
		sm.sky_horizon_color = Color(0.89, 0.53, 0.30)
		sm.ground_bottom_color = Color(0.55, 0.36, 0.20)
		sm.ground_horizon_color = Color(0.80, 0.50, 0.28)
		sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.80, 0.66)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.93, 0.66, 0.42)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.85, 0.65)
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-42, 140, 0)
	sun.shadow_enabled = false
	add_child(sun)


func _build_movers() -> void:
	var dd := DustDevil.new()
	dd.loop_center = flats_center + Vector3(6, 0, 4)
	add_child(dd)
	for k in range(tumbleweeds):
		var tw := Tumbleweed.new()
		add_child(tw)
		tw.setup(self, Vector3(1, 0, 0.3), randf_range(0.5, 0.9))
		tw.global_position = Vector3(randf_range(-50, 50), 0, randf_range(-50, 50))


func bind_game(game: Node) -> void:
	for c in get_children():
		if c is DustDevil:
			c.game = game


# ---------------------------------------------------------------- painted scenery

## A PropField of painted sprites laid down by region, so like stands with like: the oasis (palms and green around
## the water), three green stands (a cactus stand or a tree stand with the low greenery around it), dead trees and
## shrubs on the dry river's banks with bones in its bed, rock fields near the rim with skulls among them, and a few
## lone things. Anything with a collider radius gets a cylinder body and an obstacle circle; bushes have none.
func _scatter_sprites() -> void:
	props = PropField.new()
	props.name = "Props"
	add_child(props)
	props.setup()
	if not props.has("saguaro_big"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7 + 3
	var taken: Array = []   # Vector3(x, z, keep-out radius)
	var fc := Vector2(flats_center.x, flats_center.z)

	var free := func(pt: Vector2, keep: float, in_bed := false) -> bool:
		if (pt - fc).length() < flats_radius + 3.0:
			return false
		if pt.length() > arena_radius - 5.0:
			return false
		if not in_bed and _river_dist(pt) < river_width * 0.5 + 1.0:
			return false
		if _lake_dist(pt) < _lake_r + 1.2:
			return false
		for t: Vector3 in taken:
			if (pt - Vector2(t.x, t.y)).length() < t.z + keep:
				return false
		return true

	var place := func(id: String, pt: Vector2, scale: float, sway: float) -> void:
		if not props.has(id):
			return
		var g := _ground(pt.x, pt.y)
		props.add(id, g, scale, rng.randf() < 0.5, sway)
		var r := props.radius_of(id) * scale
		if r > 0.0:
			_sprite_collider(g, r, props.height_of(id) * scale)
		taken.append(Vector3(pt.x, pt.y, maxf(r, 0.6)))

	var around := func(centre: Vector2, rmin: float, rmax: float, keep: float) -> Vector2:
		for k in range(30):
			var a := rng.randf() * TAU
			var r := rng.randf_range(rmin, rmax)
			var pt := centre + Vector2(cos(a) * r, sin(a) * r)
			if free.call(pt, keep):
				return pt
		return Vector2.INF

	var spot := func(keep: float, rmin: float, rmax: float, away: Array, away_r: float) -> Vector2:
		for k in range(80):
			var a := rng.randf() * TAU
			var r := rng.randf_range(rmin, rmax)
			var pt := Vector2(cos(a) * r, sin(a) * r)
			if not free.call(pt, keep):
				continue
			var ok := true
			for c: Vector2 in away:
				if (pt - c).length() < away_r:
					ok = false
			if ok:
				return pt
		return Vector2.INF

	var pick := func(table: Array) -> String:
		# [[id, weight], ...]
		var total := 0.0
		for row in table:
			total += float(row[1])
		var x := rng.randf() * total
		for row in table:
			x -= float(row[1])
			if x <= 0.0:
				return str(row[0])
		return str(table[0][0])

	# --- the oasis: palms right at the shore, green a little further out, a rock or two at the water
	var greens: Array = [_lake_c]
	for k in range(rng.randi_range(8, 10)):
		var pt: Vector2 = around.call(_lake_c, _lake_r + 1.4, _lake_r + 5.0, 1.2)
		if pt != Vector2.INF:
			place.call("fan_palm", pt, rng.randf_range(0.9, 1.15), 0.05)
	var oasis_low: Array = [["desert_bush", 3], ["creosote_bush", 2], ["agave", 2], ["prickly_pear", 2], ["yucca", 2], ["ocotillo", 1], ["mesquite_tree", 1], ["rock_small", 1]]
	for k in range(rng.randi_range(22, 28)):
		var pt: Vector2 = around.call(_lake_c, _lake_r + 1.0, _lake_r + 11.0, 0.6)
		if pt != Vector2.INF:
			var id: String = pick.call(oasis_low)
			place.call(id, pt, rng.randf_range(0.8, 1.2), 0.0 if id == "rock_small" else 0.06)
	# --- three green stands: cactus or trees, with the low greenery around
	for c in range(3):
		var centre: Vector2 = spot.call(3.0, 22.0, arena_radius - 12.0, greens, 22.0)
		if centre == Vector2.INF:
			continue
		greens.append(centre)
		if rng.randf() < 0.5:
			for k in range(rng.randi_range(2, 3)):
				var pt: Vector2 = around.call(centre, 0.0, 5.0, 1.5)
				if pt != Vector2.INF:
					place.call("saguaro_big", pt, rng.randf_range(0.9, 1.15), 0.05)
			for k in range(rng.randi_range(3, 5)):
				var pt: Vector2 = around.call(centre, 1.0, 7.0, 0.8)
				if pt != Vector2.INF:
					place.call("saguaro_small", pt, rng.randf_range(0.85, 1.1), 0.06)
			var low: Array = [["barrel_cactus", 3], ["prickly_pear", 3], ["agave", 2], ["yucca", 2], ["ocotillo", 1.5], ["desert_bush", 2], ["dead_shrub", 1]]
			for k in range(rng.randi_range(8, 12)):
				var pt: Vector2 = around.call(centre, 1.0, 9.0, 0.6)
				if pt != Vector2.INF:
					var id: String = pick.call(low)
					place.call(id, pt, rng.randf_range(0.8, 1.2), 0.04)
		else:
			var trees: Array = [["mesquite_tree", 3], ["palo_verde", 2], ["joshua_tree", 2]]
			for k in range(rng.randi_range(3, 4)):
				var pt: Vector2 = around.call(centre, 0.0, 6.0, 2.0)
				if pt != Vector2.INF:
					place.call(pick.call(trees), pt, rng.randf_range(0.85, 1.15), 0.03)
			var under: Array = [["desert_bush", 3], ["creosote_bush", 3], ["yucca", 1.5], ["ocotillo", 1], ["agave", 1]]
			for k in range(rng.randi_range(7, 10)):
				var pt: Vector2 = around.call(centre, 1.0, 9.0, 0.6)
				if pt != Vector2.INF:
					var id: String = pick.call(under)
					place.call(id, pt, rng.randf_range(0.8, 1.2), 0.08)
	# --- the dry river: dead trees and shrubs on its banks, bones in the bed
	if _river.size() >= 2:
		for k in range(rng.randi_range(7, 10)):
			var seg := rng.randi() % (_river.size() - 1)
			var a: Vector2 = _river[seg]
			var b: Vector2 = _river[seg + 1]
			var along := a.lerp(b, rng.randf())
			var side := (b - a).normalized().rotated(PI * 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
			var pt := along + side * rng.randf_range(river_width * 0.5 + 1.5, river_width * 0.5 + 5.5)
			if free.call(pt, 1.0):
				place.call("dead_tree" if rng.randf() < 0.45 else "dead_shrub", pt, rng.randf_range(0.8, 1.15), 0.06)
		for k in range(rng.randi_range(6, 9)):
			var seg := rng.randi() % (_river.size() - 1)
			var a: Vector2 = _river[seg]
			var b: Vector2 = _river[seg + 1]
			var along := a.lerp(b, rng.randf())
			var side := (b - a).normalized().rotated(PI * 0.5)
			var pt := along + side * rng.randf_range(-river_width * 0.4, river_width * 0.4)
			if free.call(pt, 0.8, true):
				var bone := rng.randf()
				place.call("skull" if bone < 0.35 else ("bones" if bone < 0.7 else "skull_small"), pt, rng.randf_range(0.8, 1.2), 0.0)
	# --- rock fields near the rim, skulls among the stones
	var rocks: Array = []
	for c in range(rng.randi_range(3, 4)):
		var centre: Vector2 = spot.call(3.0, 36.0, arena_radius - 7.0, greens + rocks, 16.0)
		if centre == Vector2.INF:
			continue
		rocks.append(centre)
		for k in range(rng.randi_range(1, 2)):
			var pt: Vector2 = around.call(centre, 0.0, 4.0, 1.5)
			if pt != Vector2.INF:
				place.call("boulder", pt, rng.randf_range(0.85, 1.15), 0.0)
		for k in range(rng.randi_range(3, 4)):
			var pt: Vector2 = around.call(centre, 1.0, 7.0, 0.8)
			if pt != Vector2.INF:
				place.call("rock_big", pt, rng.randf_range(0.85, 1.15), 0.0)
		for k in range(rng.randi_range(6, 9)):
			var pt: Vector2 = around.call(centre, 1.0, 9.0, 0.4)
			if pt != Vector2.INF:
				place.call("rock_small", pt, rng.randf_range(0.7, 1.2), 0.0)
		for k in range(rng.randi_range(2, 3)):
			var pt: Vector2 = around.call(centre, 2.0, 9.0, 0.5)
			if pt != Vector2.INF:
				place.call("skull" if rng.randf() < 0.5 else "bones", pt, rng.randf_range(0.8, 1.2), 0.0)
	# --- a few lone things: bushes and shrubs in the open, three signposts near the flats
	for k in range(6):
		var pt: Vector2 = spot.call(1.5, 16.0, arena_radius - 8.0, [], 0.0)
		if pt != Vector2.INF:
			place.call(["desert_bush", "creosote_bush", "dead_shrub"][rng.randi() % 3], pt, rng.randf_range(0.8, 1.2), 0.08)
	for k in range(3):
		var pt: Vector2 = spot.call(3.0, 18.0, 34.0, [], 0.0)
		if pt != Vector2.INF:
			place.call("signpost", pt, 1.0, 0.0)


func _sprite_collider(g: Vector3, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = maxf(h, 1.0)
	cs.shape = shape
	cs.position.y = maxf(h, 1.0) * 0.5
	body.add_child(cs)
	body.position = g
	add_child(body)
	# creatures steer around the painting's foot, not around a halo of it
	obstacles.append(Vector3(g.x, g.z, r + 0.08))
