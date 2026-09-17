## Pooled projectiles in packed arrays, one MultiMesh per visual kind. Straight shots, gravity arcs that
## fly through enemies and explode on landing, and hostile shots that hit the player. Hit checks use the enemy spatial grid.
class_name ProjectileManager
extends Node3D

const MAX := 400

var game: Node
var kinds: Array = []   # {mm, mmi, scale}

var pos := PackedVector3Array()
var vel := PackedVector3Array()
var life := PackedFloat32Array()
var dmg := PackedFloat32Array()
var pierce := PackedInt32Array()
var kind := PackedInt32Array()
var radius := PackedFloat32Array()
var kb := PackedFloat32Array()
var area := PackedFloat32Array()
var hostile := PackedByteArray()
var arc := PackedByteArray()
var alive := PackedByteArray()
var spin := PackedFloat32Array()
var hover := PackedFloat32Array()   # straight shots: height above the ground they keep, sampled where they were fired
var weapon: Array = []
var memo: Array = []
var extra: Array = []
var free_list: Array = []
var count := 0
## Counters for the smoke run: lobbed shots fired, and how many of them exploded on landing (the rest timed out).
var lobs_fired := 0
var lobs_exploded := 0
## Hostile shots leave a faint trail of fading dots, so a spit can be followed back to whoever threw it.
const TRAIL_MAX := 800
const TRAIL_LIFE := 1.4
const TRAIL_STEP := 0.055
var trail_pos := PackedVector3Array()
var trail_age := PackedFloat32Array()
var trail_next := 0
var trail_count := 0
var _trail_t := PackedFloat32Array()   # per projectile: seconds until its next trail dot
var _trail_mm: MultiMesh


func _ready() -> void:
	pos.resize(MAX); vel.resize(MAX); life.resize(MAX); dmg.resize(MAX); pierce.resize(MAX); kind.resize(MAX)
	radius.resize(MAX); kb.resize(MAX); area.resize(MAX); hostile.resize(MAX); arc.resize(MAX); alive.resize(MAX); spin.resize(MAX); hover.resize(MAX)
	weapon.resize(MAX); memo.resize(MAX); extra.resize(MAX); _trail_t.resize(MAX)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	trail_pos.resize(TRAIL_MAX)
	trail_age.resize(TRAIL_MAX)
	for k in range(TRAIL_MAX):
		trail_age[k] = TRAIL_LIFE
	_build_trail()


func _build_trail() -> void:
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 6
	sm.rings = 3
	_trail_mm.mesh = sm
	_trail_mm.instance_count = TRAIL_MAX
	_trail_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _trail_mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)


func _drop_trail(at: Vector3) -> void:
	trail_pos[trail_next] = at
	trail_age[trail_next] = 0.0
	trail_next = (trail_next + 1) % TRAIL_MAX


## Every projectile is drawn a third bigger than its mesh says: small things read as nothing on a phone.
const CHUNK := 1.35


func register_kind(mesh: Mesh, material: Material, scale: float = 1.0) -> int:
	scale *= CHUNK
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if material:
		mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	kinds.append({"mm": mm, "mmi": mmi, "scale": scale})
	return kinds.size() - 1


func fire(p_kind: int, from: Vector3, velocity: Vector3, damage: float, p_pierce: int, p_radius: float, p_life: float, w: WeaponInstance, knockback: float = 0.0) -> int:
	if free_list.is_empty():
		return -1
	var i: int = free_list.pop_back()
	pos[i] = from; vel[i] = velocity; life[i] = p_life; dmg[i] = damage; pierce[i] = p_pierce
	kind[i] = p_kind; radius[i] = p_radius; kb[i] = knockback; area[i] = 0.0
	hostile[i] = 0; arc[i] = 0; alive[i] = 1; spin[i] = randf() * TAU
	# a straight shot follows the ground at the height it left the muzzle, so dunes never swallow it or leave it floating
	var g0: float = game.map.height_at(from.x, from.z) if game and game.map else 0.0
	hover[i] = clampf(from.y - g0, 0.35, 1.3)
	weapon[i] = w; memo[i] = {}; extra[i] = {}
	count += 1
	return i


func lob(p_kind: int, from: Vector3, target: Vector3, speed: float, damage: float, p_area: float, w: WeaponInstance, knockback: float, params: Dictionary = {}) -> int:
	var i := fire(p_kind, from, Vector3.ZERO, damage, 0, 0.3, 6.0, w, knockback)
	if i < 0:
		return -1
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var dist: float = max(flat.length(), 0.5)
	var t: float = clamp(dist / max(speed, 1.0), 0.35, 2.5)
	var g := 24.0
	var vy := ((target.y - from.y) + 0.5 * g * t * t) / t
	vel[i] = flat / t + Vector3(0, vy, 0)
	arc[i] = 1
	area[i] = p_area
	extra[i] = params
	lobs_fired += 1
	return i


func hostile_shot(p_kind: int, from: Vector3, velocity: Vector3, damage: float, splash: float, p_life: float = 4.0, arcing := false) -> int:
	var i := fire(p_kind, from, velocity, damage, 0, 0.35, p_life, null, 0.0)
	if i >= 0:
		hostile[i] = 1
		arc[i] = 1 if arcing else 0
		area[i] = splash
		_trail_t[i] = 0.0
	return i


func _free(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	weapon[i] = null
	memo[i] = {}
	free_list.append(i)
	count -= 1


func clear_all() -> void:
	for i in range(MAX):
		_free(i)


func _physics_process(delta: float) -> void:
	if game == null:
		return
	var t0 := Time.get_ticks_usec()
	var enemies: EnemyManager = game.enemies
	var player: Node3D = game.player
	var map = game.map
	for i in range(MAX):
		if alive[i] == 0:
			continue
		life[i] -= delta
		if arc[i] == 1:
			vel[i].y -= 24.0 * delta
		pos[i] += vel[i] * delta
		spin[i] += delta * 12.0
		if life[i] <= 0.0:
			_free(i)
			continue
		var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
		if arc[i] == 0:
			pos[i].y = ground + hover[i]
		if arc[i] == 1 and pos[i].y <= ground + 0.15:
			pos[i].y = ground + 0.15
			_explode(i)
			_free(i)
			continue
		if arc[i] == 1 and hostile[i] == 0:
			# lobbed shots (skulls, grenades, bomblets) sail over and through the crowd; they only ever explode on landing
			continue
		if hostile[i] == 1:
			_trail_t[i] -= delta
			if _trail_t[i] <= 0.0:
				_trail_t[i] = TRAIL_STEP
				_drop_trail(pos[i])
			if player and not player.dead:
				var d := player.global_position - pos[i]
				if d.length() < radius[i] + 0.5:
					player.take_damage(dmg[i], pos[i])
					_free(i)
			continue
		# friendly: hit enemies
		var w: WeaponInstance = weapon[i]
		var wid := w.def.id if w else ""
		var hits := enemies.indices_in_radius(pos[i], radius[i] + 0.35)
		for e in hits:
			if memo[i].has(e):
				continue
			memo[i][e] = true
			var dir := vel[i]
			if w and w.stat("poison_damage", 0.0) > 0.0:
				enemies.poison(e, wid, w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 10.0))
			if w and w.stat("fire_damage", 0.0) > 0.0:
				enemies.ignite(e, wid, w.stat("fire_damage", 4.0), w.stat("fire_duration", 1.8), w.stat("fire_spread", 0.5))
			if enemies.damage(e, dmg[i], wid, dir, kb[i]):
				if w:
					w.kills += 1
			if w:
				game.fx_hit(pos[i], w.def)
			pierce[i] -= 1
			if pierce[i] < 0:
				_free(i)
				break
	_render()
	_tick_trail(delta)
	Perf.add("projectiles", t0)


func _tick_trail(delta: float) -> void:
	var n := 0
	for k in range(TRAIL_MAX):
		if trail_age[k] >= TRAIL_LIFE:
			continue
		trail_age[k] += delta
		var f: float = clampf(trail_age[k] / TRAIL_LIFE, 0.0, 1.0)
		var s: float = 1.0 - f * 0.7
		_trail_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, s, s)), trail_pos[k]))
		_trail_mm.set_instance_color(n, Color(0.62, 0.95, 0.5, 0.45 * (1.0 - f)))
		n += 1
	_trail_mm.visible_instance_count = n


func _explode(i: int) -> void:
	var enemies: EnemyManager = game.enemies
	if hostile[i] == 1:
		var player: Node3D = game.player
		if player and not player.dead:
			var d := player.global_position - pos[i]
			d.y = 0.0
			if d.length() <= area[i] + 0.4:
				player.take_damage(dmg[i], pos[i])
		game.fx_burst(pos[i], Color(0.45, 0.75, 0.4), area[i])
		return
	var w: WeaponInstance = weapon[i]
	var wid := w.def.id if w else ""
	var before := Run.kills
	lobs_exploded += 1
	enemies.damage_radius(pos[i], area[i], dmg[i], wid, kb[i])
	var element: String = w.element() if w else ""
	if element != "":
		# a poison bomb leaves a cloud, a fire bomb a burning pool; both keep working on whoever stands in them
		game.spawn_cloud(pos[i], w, area[i], element)
	if w:
		w.kills += Run.kills - before
		Audio.play(str(w.def.sfx.get("hit", "w_lob_boom")), pos[i])
	game.fx_burst(pos[i], {"poison": Color(0.45, 0.95, 0.35), "fire": Color(1.0, 0.45, 0.15)}.get(element, Color(1.0, 0.7, 0.3)), area[i])
	game.camera.shake(0.5)
	var params: Dictionary = extra[i]
	var bomblets := int(params.get("bomblets", 0))
	if bomblets > 0 and not params.has("is_bomblet"):
		for k in range(bomblets):
			var a := TAU * k / bomblets
			var target := pos[i] + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 3.5)
			var j := lob(kind[i], pos[i] + Vector3(0, 0.5, 0), target, 6.0, dmg[i] * float(params.get("bomblet_damage_mult", 0.5)), float(params.get("bomblet_area", 1.4)), w, kb[i] * 0.5, {"is_bomblet": true})
			if j >= 0:
				vel[j].y += 4.0


func _render() -> void:
	var counters := PackedInt32Array()
	counters.resize(kinds.size())
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var k := kind[i]
		if k < 0 or k >= kinds.size():
			continue
		var kd: Dictionary = kinds[k]
		var mm: MultiMesh = kd["mm"]
		var n: int = counters[k]
		var s: float = kd["scale"]
		var basis := Basis()
		var v := vel[i]
		if v.length_squared() > 0.01:
			var fwd := v.normalized()
			var up := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			basis = Basis.looking_at(fwd, up)
		basis = basis.rotated(basis.z, spin[i]).scaled(Vector3(s, s, s))
		mm.set_instance_transform(n, Transform3D(basis, pos[i]))
		counters[k] = n + 1
	for k in range(kinds.size()):
		kinds[k]["mm"].visible_instance_count = counters[k]
