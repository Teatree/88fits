## Dry Gulch, greybox. Builds the heightmap terrain (dunes, sunken riverbed, flat centre), the mesa ring wall,
## two mesas with ramps and auto-jump gaps, desert props as obstacles, jump pads, a dust devil, tumbleweeds,
## and the golden-hour sky. Every number here is a tunable exported for the editor.
extends MapBase

@export var seed := 88
@export var dune_height := 1.5
@export var river_depth := 2.0
@export var river_width := 6.0
@export var flats_radius := 16.0
@export var mesa_height := 3.0
@export var sand_color := Color(0.85, 0.66, 0.39)
@export var river_color := Color(0.70, 0.46, 0.26)
@export var wall_color := Color(0.56, 0.31, 0.17)
@export var tumbleweeds := 6

const RIVER := [Vector2(-60, -40), Vector2(-30, -55), Vector2(0, -20), Vector2(25, -30), Vector2(48, 0), Vector2(60, 30)]
const WEST_MESA := [Rect2(-46, 4, 14, 10), Rect2(-28, 2, 11, 9)]
const EAST_MESA := [Rect2(18, 20, 14, 10), Rect2(36, 18, 10, 9)]

var _static: StaticBody3D
var _noise := FastNoiseLite.new()


func _ready() -> void:
	_noise.seed = seed
	_noise.frequency = 0.045
	_noise.fractal_octaves = 3
	flats_center = Vector3(0, 0, 8)
	_build_terrain()
	_build_wall()
	_build_mesas()
	_build_props()
	_build_sky()
	_build_movers()


# ---------------------------------------------------------------- terrain

## The heightmap stops at the mesa foot; on a mesa the ground is its top, so gems, pickups, markings and the
## tumbleweeds that get up there sit on the plateau instead of sinking into the block.
func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	for r in WEST_MESA + EAST_MESA:
		if r.has_point(p):
			return mesa_height
	return super.height_at(x, z)


func _river_dist(p: Vector2) -> float:
	var best := 1e9
	for k in range(RIVER.size() - 1):
		var a: Vector2 = RIVER[k]
		var b: Vector2 = RIVER[k + 1]
		var ab := b - a
		var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = min(best, (a + ab * t - p).length())
	return best


func _in_mesa(p: Vector2) -> bool:
	for r in WEST_MESA + EAST_MESA:
		if r.grow(1.0).has_point(p):
			return true
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
	if _in_mesa(p):
		h = 0.0
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
	## r = riverbed blend, g = shade multiplier, b unused. The painted terrain shader reads these.
	var rd := _river_dist(Vector2(x, z))
	var t: float = clamp(1.0 - rd / (river_width * 0.9), 0.0, 1.0)
	var n := _noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0)
	var shade: float = clamp(1.0 - n * 0.35 + h * 0.05, 0.6, 1.15)
	return Color(t, shade, 0.0)


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


# ---------------------------------------------------------------- wall, mesas, jump pads

func _build_wall() -> void:
	var n := 40
	for k in range(n):
		var a := TAU * k / n
		var r := arena_radius + 3.0
		var p := Vector3(cos(a) * r, 2.5, sin(a) * r)
		var w := TAU * r / n + 1.0
		_box(p, Vector3(w, 7.0 + (k % 3) * 1.5, 6.0), wall_color, 0.0, -a + PI * 0.5)
	# invisible fence a little inside so the player never wedges into the blocks
	for k in range(n):
		var a := TAU * k / n
		var r := arena_radius
		var p := Vector3(cos(a) * r, 2.0, sin(a) * r)
		var body := _box(p, Vector3(TAU * r / n + 1.0, 8.0, 0.5), wall_color, 0.0, -a + PI * 0.5)
		for c in body.get_children():
			if c is MeshInstance3D:
				c.visible = false


func _build_mesas() -> void:
	var mesa_color := Color(0.72, 0.42, 0.24)
	var ramp_color := Color(0.83, 0.63, 0.42)
	for group in [WEST_MESA, EAST_MESA]:
		for r: Rect2 in group:
			var c := r.get_center()
			_box(Vector3(c.x, mesa_height * 0.5, c.y), Vector3(r.size.x, mesa_height, r.size.y), mesa_color)
			# enemies path around the plateau
			obstacles.append(Vector3(c.x, c.y, max(r.size.x, r.size.y) * 0.55))
			# chest on top
			var chest_pos := Vector3(c.x, mesa_height, c.y)
			spawn_points.append(chest_pos)
		# ramp on the first block's south side, sloping up northwards
		var first: Rect2 = group[0]
		var rc := first.get_center()
		var ramp_len := 7.0
		var ramp_pos := Vector3(rc.x, mesa_height * 0.5 - 0.2, first.end.y + ramp_len * 0.5 - 0.3)
		var ramp := _box(ramp_pos, Vector3(5.0, 0.5, ramp_len * 1.08), ramp_color)
		ramp.rotation.x = -atan2(mesa_height, ramp_len)
		# gap between block 0 and 1 gets a jump pad each side
		var second: Rect2 = group[1]
		var gap_mid_x := (first.end.x + second.position.x) * 0.5
		var gap_z := (rc.y + second.get_center().y) * 0.5
		_jump_pad(Vector3(first.end.x - 1.0, mesa_height + 0.6, gap_z), Vector3(1, 0, 0), 4.0, second.position.x - first.end.x + 3.0)
		_jump_pad(Vector3(second.position.x + 1.0, mesa_height + 0.6, gap_z), Vector3(-1, 0, 0), 4.0, second.position.x - first.end.x + 3.0)
		# rock arch marker at the gap for readability
		_box(Vector3(gap_mid_x, mesa_height + 4.5, gap_z - first.size.y * 0.5), Vector3(second.position.x - first.end.x + 2.0, 0.6, 0.6), mesa_color)


func _jump_pad(p: Vector3, dir: Vector3, up: float, gap: float) -> void:
	var pad := JumpPad.new()
	pad.direction = dir
	pad.up_speed = 7.5
	pad.forward_speed = max(gap * 1.1, 6.0)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 2.0, 8.0)
	cs.shape = shape
	pad.add_child(cs)
	pad.position = p
	add_child(pad)
	jump_pads.append(pad)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(1.0, 0.1, 8.0)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.94, 0.91, 0.84, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = Vector3(0, -0.55, 0)
	pad.add_child(mi)


# ---------------------------------------------------------------- props

## Places a Blender-built GLB prop from res://art/props/<name>.glb on a static body with a cylinder collider.
## Falls back to `fallback` (a Callable building primitives) when the GLB has not been generated yet.
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


func _build_props() -> void:
	var cactus := Color(0.31, 0.56, 0.30)
	var rock := Color(0.61, 0.54, 0.48)
	var rust := Color(0.48, 0.29, 0.23)
	var bone := Color(0.95, 0.91, 0.84)
	# saguaro clusters
	for c in [Vector2(-50, -20), Vector2(-46, -14), Vector2(-54, -12), Vector2(44, -44), Vector2(48, -38), Vector2(40, -36), Vector2(8, 48), Vector2(12, 52), Vector2(-16, -58), Vector2(-12, -54), Vector2(26, -8), Vector2(-30, 40), Vector2(-34, 44)]:
		var h := randf_range(0.8, 1.25)
		var g := _ground(c.x, c.y)
		_prop("saguaro", g, 0.55, 3.0, randf() * TAU, h, func(): _saguaro(g, 2.6 * h, cactus); return null)
	# barrel cacti between them
	for c in [Vector2(-48, -8), Vector2(52, -42), Vector2(16, 46), Vector2(-20, -50), Vector2(30, -4), Vector2(-36, 36), Vector2(2, -40)]:
		_prop("barrel_cactus", _ground(c.x, c.y), 0.6, 1.0, randf() * TAU, randf_range(0.9, 1.3), func(): _cylinder(_ground(c.x, c.y), 0.5, 0.9, cactus); return null)
	# rocks
	var rocks := [["rock_big", Vector2(-8, 40)], ["rock_small", Vector2(-6, 43)], ["boulder", Vector2(58, -10)], ["rock_small", Vector2(60, -14)], ["rock_big", Vector2(-58, 26)], ["rock_big", Vector2(20, -50)], ["boulder", Vector2(-40, -34)], ["rock_small", Vector2(34, 30)]]
	for r in rocks:
		var nm: String = r[0]
		var pt: Vector2 = r[1]
		var rr: float = {"rock_small": 0.9, "rock_big": 1.8, "boulder": 2.8}[nm]
		var g := _ground(pt.x, pt.y)
		_prop(nm, g, rr, rr, randf() * TAU, 1.0, func(): _cylinder(g, rr, rr * 0.8, rock); return null)
	# wrecked pickup
	var wg := _ground(-24, -26)
	_prop("pickup_wreck", wg, 0.0, 0.0, deg_to_rad(-15), 1.0, func():
		var wreck := _box(wg + Vector3(0, 0.9, 0), Vector3(5.0, 1.8, 2.4), rust, 3.2, deg_to_rad(-15))
		return wreck)
	_box(wg + Vector3(0, 0.9, 0), Vector3(5.2, 1.8, 2.6), rust, 3.4, deg_to_rad(-15)).visible = false
	# gas station
	var gg := _ground(40, -56)
	_prop("gas_station", gg, 0.0, 0.0, 0.0, 1.0, func():
		_box(gg + Vector3(0, 2.0, 0), Vector3(9.0, 4.0, 5.0), Color(0.54, 0.42, 0.29), 5.5)
		_box(gg + Vector3(0, 5.2, 0), Vector3(6.0, 1.2, 0.4), Color(0.85, 0.26, 0.23), 0.0)
		return null)
	_box(gg + Vector3(0, 2.0, 0), Vector3(9.2, 4.0, 5.2), Color(0.54, 0.42, 0.29), 5.6).visible = false
	# water tower and wind pump
	var tg := _ground(58, -44)
	_prop("water_tower", tg, 1.6, 9.0, 0.0, 1.0, func(): _cylinder(tg, 2.0, 8.0, Color(0.43, 0.29, 0.17)); return null)
	var pg := _ground(-52, 14)
	_prop("wind_pump", pg, 1.0, 7.0, 0.0, 1.0, func(): _cylinder(pg, 0.6, 7.0, Color(0.3, 0.2, 0.12)); return null)
	# bones and skulls, decoration only
	for b in [Vector2(-16, 14), Vector2(30, 36), Vector2(-52, 8), Vector2(12, -34)]:
		var bg := _ground(b.x, b.y)
		_prop("bone", bg, 0.0, 0.0, randf() * TAU, 1.0, func():
			var mi := MeshInstance3D.new()
			var m := CapsuleMesh.new()
			m.radius = 0.18
			m.height = 2.2
			mi.mesh = m
			mi.position = bg + Vector3(0, 0.2, 0)
			mi.rotation = Vector3(PI * 0.5, randf() * TAU, 0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = bone
			mi.material_override = mat
			add_child(mi)
			return mi)
	for sk in [Vector2(-14, 16), Vector2(28, 38)]:
		_prop("skull", _ground(sk.x, sk.y), 0.0, 0.0, randf() * TAU, 1.0, Callable(), false)
	# signpost and campfire
	var sg := _ground(-4, -30)
	_prop("signpost", sg, 0.25, 3.0, deg_to_rad(20), 1.0, func():
		_cylinder(sg, 0.2, 3.0, Color(0.35, 0.22, 0.12), false)
		return _box(sg + Vector3(0, 3.0, 0), Vector3(2.6, 0.7, 0.15), Color(0.85, 0.75, 0.55)))
	var cg := _ground(6, 24)
	var fire := _prop("campfire", cg, 0.9, 0.6, 0.0, 1.0, Callable(), true)
	if fire:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.25)
		light.omni_range = 9.0
		light.light_energy = 1.6
		light.position = Vector3(0, 1.0, 0)
		fire.add_child(light)


func _saguaro(p: Vector3, h: float, color: Color) -> void:
	var body := _cylinder(p, 0.5, h, color)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var am := CylinderMesh.new()
		am.top_radius = 0.28
		am.bottom_radius = 0.28
		am.height = h * 0.5
		arm.mesh = am
		arm.position = Vector3(side * 0.9, h * 0.62, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		arm.material_override = mat
		body.add_child(arm)
		var joint := MeshInstance3D.new()
		var jm := CylinderMesh.new()
		jm.top_radius = 0.26
		jm.bottom_radius = 0.26
		jm.height = 1.0
		joint.mesh = jm
		joint.position = Vector3(side * 0.5, h * 0.42, 0)
		joint.rotation.z = PI * 0.5
		joint.material_override = mat
		body.add_child(joint)


# ---------------------------------------------------------------- sky, light, movers

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
	# distant mesa silhouettes outside the wall
	for k in range(14):
		var a := TAU * k / 14.0 + 0.2
		var r := arena_radius + 22.0 + (k % 3) * 8.0
		_box(Vector3(cos(a) * r, 5.0, sin(a) * r), Vector3(14.0 + (k % 4) * 6.0, 10.0 + (k % 3) * 5.0, 8.0), Color(0.42, 0.24, 0.22), 0.0, -a + PI * 0.5)


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
