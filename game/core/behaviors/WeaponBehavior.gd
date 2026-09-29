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
# the mutation marks (pass 28): one emblem per pick, hung over the weapon's companion, its held gun, or the hero's shoulder
var _marks: Node3D
var _mark_key := ""


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
		# plain parts that share a material draw as one (pass 33.8); the named ones the behaviours move stay apart
		MeshMerge.merge(visual)
	else:
		visual = Node3D.new()
	add_child(visual)
	var proj := visual.get_node_or_null("Projectile")
	if proj is MeshInstance3D and proj.mesh:
		var mat: Material = proj.material_override
		if mat == null and proj.mesh.get_surface_count() > 0:
			mat = proj.mesh.surface_get_material(0)
		projectile_kind = game.projectiles.register_kind(proj.mesh, mat, proj.scale.x)
		proj.visible = false
	if projectile_kind < 0:
		projectile_kind = game.projectiles.register_kind(_default_mesh(), _default_material(), 1.0)
	var held := visual.get_node_or_null("Held")
	if held:
		held.visible = _shows_held()


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


## The emblems for the mutations this weapon carries, rebuilt when the set changes (Game calls this on every build change).
func refresh_marks() -> void:
	var key := ""
	if inst:
		for m in inst.mutations:
			key += str(m.id) + ","
	if key == _mark_key and (_marks != null or key == ""):
		return
	_mark_key = key
	if _marks:
		_marks.queue_free()
		_marks = null
	if key == "":
		return
	_marks = Node3D.new()
	_marks.name = "MutationMarks"
	_marks.top_level = true
	add_child(_marks)
	var k := 0
	for m in inst.mutations:
		var e := _mark_for(m)
		# an emblem's pieces share one material: one mesh, one draw call (pass 33.8)
		MeshMerge.merge(e)
		e.position = Vector3(0, 0.26 * k, 0)
		_marks.add_child(e)
		k += 1


func _mark_colour(m: MutationDef) -> Color:
	match m.mutation_kind:
		"element":
			var el = m.get("element")
			var els := str(el) if el != null else ""
			if els == "":
				for ef in m.effects:
					if ef is Effect and str(ef.stat).begins_with("fire"):
						els = "fire"
					elif ef is Effect and str(ef.stat).begins_with("poison"):
						els = "poison"
			return Color(1.0, 0.5, 0.15) if els == "fire" else Color(0.45, 1.0, 0.35)
		"volume":
			return Color(1.0, 0.82, 0.3)
		"motion":
			return Color(0.35, 0.9, 1.0)
		"stance":
			return Color(0.85, 0.7, 0.45)
	return Color(1.0, 1.0, 1.0)


func _mark_for(m: MutationDef) -> Node3D:
	var root := Node3D.new()
	var col := _mark_colour(m)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	match m.mutation_kind:
		"volume":
			# three orbs in a ring: more of everything
			for j in range(3):
				var s := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.06
				sm.height = 0.12
				sm.radial_segments = 8
				sm.rings = 4
				s.mesh = sm
				s.material_override = mat
				var a := TAU * float(j) / 3.0
				s.position = Vector3(cos(a) * 0.14, 0, sin(a) * 0.14)
				root.add_child(s)
		_:
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.13
			tm.outer_radius = 0.19
			tm.rings = 16
			tm.ring_segments = 6
			t.mesh = tm
			t.material_override = mat
			root.add_child(t)
			if m.mutation_kind == "motion":
				# a blade through the ring: it spins
				var b := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.34, 0.025, 0.05)
				b.mesh = bm
				b.material_override = mat
				root.add_child(b)
			elif m.mutation_kind == "element":
				# a flame or a drop in the ring
				var c := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = 0.06
				cm.height = 0.16
				cm.radial_segments = 6
				cm.rings = 1
				c.mesh = cm
				c.material_override = mat
				c.rotation.x = PI if col.g > col.r else 0.0
				root.add_child(c)
			elif m.mutation_kind == "hero":
				var t2 := MeshInstance3D.new()
				t2.mesh = tm
				t2.material_override = mat
				t2.rotation.x = PI * 0.5
				root.add_child(t2)
	root.set_meta("spin", 2.2 if m.mutation_kind == "motion" else 0.8)
	return root


## The marks ride over the companion, the held gun, or the hero's shoulder (a slot apart for weapons with neither).
func _tick_marks(delta: float) -> void:
	if _marks == null:
		return
	var anchor: Node3D = visual.get_node_or_null("Familiar") if visual else null
	var lift := 0.55
	if anchor == null:
		var held := visual.get_node_or_null("Held") if visual else null
		if held is Node3D and (held as Node3D).visible:
			anchor = held
			lift = 0.45
	var at: Vector3
	if anchor:
		at = anchor.global_position + Vector3(0, lift, 0)
	else:
		var slot := 0
		for k in range(Run.weapons.size()):
			if Run.weapons[k] == inst:
				slot = k
		at = player.global_position + Vector3((float(slot) - 1.5) * 0.4, 2.15, 0.0)
	var t := float(Time.get_ticks_msec()) * 0.001
	_marks.global_position = at + Vector3(0, 0.04 * sin(t * 2.5), 0)
	for c in _marks.get_children():
		if c is Node3D:
			c.rotation.y += delta * float(c.get_meta("spin", 0.8))


func _on_setup() -> void:
	pass


func stat(name: String, default: float = 0.0) -> float:
	return inst.stat(name, default)


## Up to `n` spots within `reach` of the hero to strike, each where a creature has the most others within `r` of it that
## no earlier spot covers (pass 35: the Hammer's heads, the Gravity Gun's throws). Once every creature is covered the
## spots found come round again, so one lone crowd takes every blow. Creatures in `skip` are never counted.
func crowd_spots(n: int, reach: float, r: float, skip: Dictionary = {}) -> Array:
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
			if skip.has(i):
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


func sfx(event: String, at: Vector3 = Vector3.INF) -> void:
	var id := str(inst.def.sfx.get(event, ""))
	if id != "":
		Audio.play(id, at)


func muzzle_flash(at: Vector3 = Vector3.INF) -> void:
	var m := visual.get_node_or_null("Muzzle")
	if m is CPUParticles3D or m is GPUParticles3D:
		m.global_position = at if at != Vector3.INF else player.aim_origin(player.forward())
		m.restart()
		m.emitting = true


func _process(delta: float) -> void:
	if game == null or player == null or player.dead or game.paused:
		return
	var t0 := Time.get_ticks_usec()
	cooldown_left -= delta
	_fly_stray(delta)
	_tick_marks(delta)
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
