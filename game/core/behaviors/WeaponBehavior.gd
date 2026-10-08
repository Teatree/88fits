## Base for reusable weapon behaviour primitives. A WeaponDef names one of these and a visual scene;
## the behaviour reads its numbers from the WeaponInstance StatSheet every frame, so level-ups and
## passives apply instantly.
class_name WeaponBehavior
extends Node3D

var inst: WeaponInstance
var game: Node
var player: Node3D
var visual: Node3D
var cooldown_left := 0.0
var projectile_kind := -1
## The glow every companion and held gun gets (pass 53, Garry: "Add some emit to the materials of 3d objects of items
## that are flying around the Player hero or something, they are quite dim"): emission at this strength in each dim
## material's own colour; `params.glow` sets a weapon's own (0 = none); a material that already emits is left alone.
const GLOW := 0.45


func setup(p_inst: WeaponInstance, p_game: Node) -> void:
	inst = p_inst
	game = p_game
	player = p_game.player
	_load_visual()
	_on_setup()
	# a companion the behaviour itself does not fly (a Lobber after Needle Rain took over the Poison Dart) still
	# circles the hero, instead of staying behind on the map where it was loaded
	if visual and get("_familiar") == null:
		_stray = visual.get_node_or_null("Familiar") as Node3D
		if _stray:
			_stray_orbit = randf() * TAU
			_fly_stray(0.0)
	refresh_marks()


var _stray: Node3D = null
var _stray_orbit := 0.0


## The loose companion's circle: the gun familiars' radius, height, speed and bob (params.familiar), facing along it.
func _fly_stray(delta: float) -> void:
	if _stray == null or player == null:
		return
	var f = inst.params.get("familiar", {})
	var fam: Dictionary = f if f is Dictionary else {}
	var r := float(fam.get("radius", 1.25))
	var h := float(fam.get("height", 1.35))
	_stray_orbit += delta * float(fam.get("speed", 1.4))
	var t := float(Time.get_ticks_msec()) * 0.001
	var want := player.global_position + Vector3(cos(_stray_orbit) * r, h + sin(t * 3.1) * float(fam.get("bob", 0.12)), sin(_stray_orbit) * r)
	_stray.global_position = want if delta <= 0.0 else _stray.global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	_stray.rotation.y = -_stray_orbit


func _load_visual() -> void:
	var scene := inst.visual_scene()
	if scene:
		visual = scene.instantiate()
		# the companion and the held gun glow a little (pass 53), before the merge so parts that share a material still do
		var glow := float(inst.params.get("glow", GLOW))
		if glow > 0.0:
			glow_companions(visual, glow)
		# plain parts that share a material draw as one (pass 33.8); the named ones the behaviours move stay apart
		MeshMerge.merge(visual)
	else:
		visual = Node3D.new()
	add_child(visual)
	var proj := visual.get_node_or_null("Projectile")
	var src := projectile_source(visual)
	if src:
		var mat: Material = src.material_override
		var mesh: Mesh = src.mesh
		var sc: float = src.scale.x
		var basis: Basis = (proj as Node3D).transform.basis
		if src == proj:
			if mat == null and mesh.get_surface_count() == 1:
				mat = mesh.surface_get_material(0)
			# a "Halo" under the Projectile node (pass 60: the Tommy Gun's rounds, the Boomstick's pellets): the shot is
			# drawn as that core inside the halo, one mesh of two surfaces, each with its own material
			var halo := proj.get_node_or_null("Halo") as MeshInstance3D
			if halo and halo.mesh:
				var core_mat: Material = mat if mat else (mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null)
				var halo_mat: Material = halo.material_override if halo.material_override else (halo.mesh.surface_get_material(0) if halo.mesh.get_surface_count() > 0 else null)
				mesh = streak_mesh(mesh, core_mat, halo.mesh, halo_mat, halo.transform)
				mat = null
		else:
			# a model (pass 46, the Spear): every part keeps its own material unless there is only the one, and the shot is
			# drawn at the Projectile node's scale times the part's
			if mat == null and src.mesh.get_surface_count() == 1:
				mat = src.mesh.surface_get_material(0)
			sc *= (proj as Node3D).scale.x
			basis = basis * src.transform.basis
		var pm: Node = game.projectiles
		if pm.get_method_argument_count("register_kind") >= 5:
			# the Projectile node's turn goes with the kind (pass 53, when the ProjectileManager takes one), so a model
			# built along another axis flies point first
			projectile_kind = pm.register_kind(mesh, mat, sc, false, basis.orthonormalized())
		else:
			projectile_kind = pm.register_kind(mesh, mat, sc)
		(proj as Node3D).visible = false
	if projectile_kind < 0 and _uses_projectiles():
		projectile_kind = game.projectiles.register_kind(_default_mesh(), _default_material(), 1.0)
	var held := visual.get_node_or_null("Held")
	if held:
		held.visible = _shows_held()


## Pass 53: every dim StandardMaterial3D on the meshes under `root`'s "Familiar" and "Held" nodes is swapped for a copy
## that emits its own albedo colour (white when it has a texture) at `energy`; a material that already emits (the gold
## guns, the Gravity Gun's core, the strings) is left alone; parts sharing one material share the lit copy, so MeshMerge
## still joins them. Returns how many materials were lit.
static func glow_companions(root: Node, energy: float) -> int:
	if root == null or energy <= 0.0:
		return 0
	var lit := {}
	var n := 0
	for anchor in ["Familiar", "Held"]:
		var a: Node = root.get_node_or_null(anchor)
		if a == null:
			continue
		var meshes: Array = a.find_children("*", "MeshInstance3D", true, false)
		if a is MeshInstance3D:
			meshes.append(a)
		for m: MeshInstance3D in meshes:
			if m.material_override != null:
				var g := _glowing(m.material_override, energy, lit)
				if g != null:
					m.material_override = g
					n += 1
				continue
			if m.mesh == null:
				continue
			for s in range(m.mesh.get_surface_count()):
				var cur: Material = m.get_surface_override_material(s)
				if cur == null:
					cur = m.mesh.surface_get_material(s)
				var g := _glowing(cur, energy, lit)
				if g != null:
					m.set_surface_override_material(s, g)
					n += 1
	return n


## The lit copy of `mat` (made once per material), or null when it is not a plain dim StandardMaterial3D.
static func _glowing(mat: Material, energy: float, lit: Dictionary) -> StandardMaterial3D:
	if not (mat is StandardMaterial3D):
		return null
	var sm := mat as StandardMaterial3D
	var key := sm.get_instance_id()
	if lit.has(key):
		return lit[key]
	if sm.emission_enabled:
		return null
	var g := sm.duplicate() as StandardMaterial3D
	g.emission_enabled = true
	g.emission = Color.WHITE if sm.albedo_texture != null else Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b)
	g.emission_energy_multiplier = energy
	lit[key] = g
	return g


## The mesh a weapon's shots are drawn with: the visual scene's "Projectile" node when it is a mesh, else the first mesh
## under it (pass 46: the Spear's Projectile is its model, an instance of art/props/spear.glb). Null when there is none.
static func projectile_source(vis: Node) -> MeshInstance3D:
	var proj: Node = vis.get_node_or_null("Projectile") if vis else null
	if proj is MeshInstance3D:
		return proj if (proj as MeshInstance3D).mesh else null
	if proj is Node3D:
		for c in proj.find_children("*", "MeshInstance3D", true, false):
			if (c as MeshInstance3D).mesh:
				return c
	return null


## A shot drawn as a hot core inside a soft glow (pass 60, the Tommy Gun's rounds and the Boomstick's pellets, after the
## tracers of Enter the Gungeon and Nuclear Throne: a bright core with a coloured glow round it): one ArrayMesh of two
## surfaces, `core` in `core_mat` and `halo` (moved by `halo_xf`, the "Halo" node's transform under the Projectile
## node) in `halo_mat`, so one MultiMesh draws both and nothing is added per shot.
static func streak_mesh(core: Mesh, core_mat: Material, halo: Mesh, halo_mat: Material, halo_xf: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, core.surface_get_arrays(0))
	if core_mat:
		out.surface_set_material(0, core_mat)
	var arrays: Array = halo.surface_get_arrays(0)
	if not halo_xf.is_equal_approx(Transform3D.IDENTITY):
		var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		for k in range(verts.size()):
			verts[k] = halo_xf * verts[k]
		arrays[Mesh.ARRAY_VERTEX] = verts
		var norms = arrays[Mesh.ARRAY_NORMAL]
		if norms is PackedVector3Array:
			var nn: PackedVector3Array = (norms as PackedVector3Array).duplicate()
			for k in range(nn.size()):
				nn[k] = (halo_xf.basis * nn[k]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = nn
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if halo_mat:
		out.surface_set_material(1, halo_mat)
	return out


## Whether the behaviour fires shots through the ProjectileManager: one that never does (the Guitarra's cone) does not
## take a projectile kind it would never draw.
func _uses_projectiles() -> bool:
	return true


func _default_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.15
	m.height = 0.3
	m.radial_segments = 8
	m.rings = 4
	return m


func _default_material() -> Material:
	var mat := StandardMaterial3D.new()
	var ph: Dictionary = inst.def.placeholder
	mat.albedo_color = Color(str(ph.get("color", "#FFE08A")))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.8
	return mat


func _shows_held() -> bool:
	return false


## Game calls this on every build change (a mutation taken, a level, an evolution; setup too). The emblems that hung over
## a weapon per mutation since pass 28 are gone (pass 60, Garry: "the current halos are stupid and turn into a bit of a
## mess ... remove all the current little halos that appear over weapons after a mutation is applied"): a weapon's path
## shows on the weapon itself or not at all (the Sun Scepter's ring and tint, the pod's heat, Methanol's bottle). This
## frees a "MutationMarks" node still hanging and does nothing else, so the overrides keep their hook (MissilePod wires
## the Pressure Cooker and Pollen's field, Lobber swaps its visual, SunScepter refreshes its looks).
func refresh_marks() -> void:
	var old := get_node_or_null("MutationMarks")
	if old:
		remove_child(old)
		old.queue_free()


func _on_setup() -> void:
	pass


func stat(name: String, default: float = 0.0) -> float:
	return inst.stat(name, default)


## Up to `n` spots within `reach` of the hero to strike, each where a creature has the most others within `r` of it that
## no earlier spot covers (pass 35: the Hammer's heads, the Gravity Gun's throws). Once every creature is covered the
## spots found come round again, so one lone crowd takes every blow. Creatures in `skip` are never counted. A spot is a
## creature on the screen unless `any_screen` (pass 54, EnemyManager.screen_ok).
func crowd_spots(n: int, reach: float, r: float, skip: Dictionary = {}, any_screen: bool = false) -> Array:
	var em: EnemyManager = game.enemies
	var cands := em.indices_in_radius(player.global_position, reach)
	var out: Array = []
	var covered := {}
	var step: int = maxi(1, cands.size() / 40)
	for s in range(n):
		var best := -1
		var best_n := 0
		for k in range(0, cands.size(), step):
			var i := cands[k]
			if skip.has(i) or not em.screen_ok(i, any_screen):
				continue
			var cnt := 0
			for j in em.indices_in_radius(em.pos[i], r):
				if not covered.has(j) and not skip.has(j):
					cnt += 1
			if cnt > best_n:
				best_n = cnt
				best = i
		if best < 0:
			if out.is_empty():
				break
			out.append(out[s % out.size()])
			continue
		out.append(em.pos[best])
		for j in em.indices_in_radius(em.pos[best], r):
			covered[j] = true
	return out


func stat_int(name: String, default: int = 0) -> int:
	return inst.stat_int(name, default)


## The creature a single-target weapon goes for (pass 48): with `"targeting": "priority"` the strong and the close
## (EnemyManager.priority_index: distance over a weight by max HP, big game at the cap), else the nearest. -1 for none.
## Pass 54: only a creature on the screen (Settings.ranged_on_screen) unless `any_screen` (the homing weapons pass it).
func aim_index(from: Vector3, range_m: float, avoid: String = "", any_screen: bool = false) -> int:
	var em: EnemyManager = game.enemies
	if inst.def.targeting == "priority":
		return em.priority_index(from, range_m, avoid, any_screen)
	return em.nearest_index(from, range_m, avoid, any_screen)


func sfx(event: String, at: Vector3 = Vector3.INF) -> void:
	var id := str(inst.def.sfx.get(event, ""))
	if id != "":
		Audio.play(id, at)


## The muzzle's sparks at `at`, turned along `dir` (pass 60: the particle node was only moved, so its sparks flew the
## world's -Z whatever the aim), with a "Flash" sibling (one hot pop at the muzzle, the Tommy Gun's; the Boomstick's
## cone) and a "Smoke" sibling (a grey puff, the Boomstick's) when the visual has them. No `dir`: left turned as it was.
func muzzle_flash(at: Vector3 = Vector3.INF, dir: Vector3 = Vector3.ZERO) -> void:
	if visual == null:
		return
	var p: Vector3 = at if at != Vector3.INF else player.aim_origin(player.forward())
	var d := Vector3(dir.x, 0.0, dir.z)
	for nm: String in ["Muzzle", "Flash", "Smoke"]:
		var m := visual.get_node_or_null(nm)
		if m is CPUParticles3D or m is GPUParticles3D:
			m.global_position = p
			if d.length_squared() > 0.0001 and m.is_inside_tree():
				m.look_at(p + d, Vector3.UP)
			m.restart()
			m.emitting = true


func _process(delta: float) -> void:
	if game == null or player == null or player.dead or game.paused:
		return
	var t0 := Time.get_ticks_usec()
	cooldown_left -= delta
	_fly_stray(delta)
	_tick(delta)
	if cooldown_left <= 0.0:
		if _fire():
			cooldown_left = max(stat("cooldown", 1.0), 0.05)
		else:
			cooldown_left = 0.15
	Perf.add("weapons", t0)


func _tick(_delta: float) -> void:
	pass


## Return true if something happened (starts the cooldown).
func _fire() -> bool:
	return false
