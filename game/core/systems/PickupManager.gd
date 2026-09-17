## XP gems and coins as 3D meshes in MultiMeshes. Magnet pull, merge when crowded, vacuum, chests.
class_name PickupManager
extends Node3D

const MAX := 600
const KIND_GEM_S := 0
const KIND_GEM_M := 1
const KIND_GEM_L := 2
const KIND_COIN := 3
const KIND_VACUUM := 4
const MERGE_AT := 300

var game: Node
var pos := PackedVector3Array()
var kind := PackedInt32Array()
var value := PackedFloat32Array()
var vel := PackedVector3Array()
var flying := PackedByteArray()
var alive := PackedByteArray()
var born := PackedFloat32Array()
var free_list: Array = []
var count := 0
var _time := 0.0
var _mms: Array = []
var _attractors: Array = []   # {pos, r} set each frame by turrets
var chests: Array = []
var specials: Array = []       # Powerup nodes waiting on the ground


func _ready() -> void:
	pos.resize(MAX); kind.resize(MAX); value.resize(MAX); vel.resize(MAX); flying.resize(MAX); alive.resize(MAX); born.resize(MAX)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	_mms.append(_make_mm(_gem_mesh(0.22), Color(0.62, 0.48, 1.0)))
	_mms.append(_make_mm(_gem_mesh(0.32), Color(0.45, 0.85, 1.0)))
	_mms.append(_make_mm(_gem_mesh(0.45), Color(1.0, 0.55, 0.85)))
	_mms.append(_make_mm(_coin_mesh(), Color(1.0, 0.72, 0.25)))
	_mms.append(_make_mm(_gem_mesh(0.5), Color(1.0, 1.0, 1.0)))


func _gem_mesh(r: float) -> Mesh:
	var m := PrismMesh.new()
	m.size = Vector3(r * 2.0, r * 2.4, r * 2.0)
	return m


func _coin_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.28
	m.bottom_radius = 0.28
	m.height = 0.08
	m.radial_segments = 12
	return m


func _make_mm(mesh: Mesh, color: Color) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	return mm


func spawn(p_kind: int, at: Vector3, v: float) -> int:
	if free_list.is_empty():
		_merge(120)
		if free_list.is_empty():
			return -1
	var i: int = free_list.pop_back()
	pos[i] = at + Vector3(randf_range(-0.4, 0.4), 0.4, randf_range(-0.4, 0.4))
	kind[i] = p_kind
	value[i] = v
	vel[i] = Vector3(randf_range(-1.5, 1.5), 3.0, randf_range(-1.5, 1.5))
	flying[i] = 0
	alive[i] = 1
	born[i] = _time
	count += 1
	if count > MERGE_AT:
		_merge(100)
	return i


func drop_from(def: EnemyDef, at: Vector3, xp_scale: float, is_elite: bool) -> void:
	var d := def.drops
	var luck: float = Run.player_sheet.get_stat("luck", 0.0)
	if randf() < float(d.get("small", 0.0)):
		spawn(KIND_GEM_S, at, 1.0 * xp_scale)
	if randf() < float(d.get("medium", 0.0)) + luck * 0.1:
		spawn(KIND_GEM_M, at, 5.0 * xp_scale)
	if randf() < float(d.get("large", 0.0)):
		spawn(KIND_GEM_L, at, 25.0 * xp_scale)
	if randf() < float(d.get("gold", 0.0)) * (1.0 + luck):
		spawn(KIND_COIN, at, float(1 + randi() % 3))
	if is_elite and randf() < 0.05 + luck * 0.1:
		spawn(KIND_VACUUM, at, 0.0)


func vacuum_all(coins_too: bool = false) -> void:
	for i in range(MAX):
		if alive[i] == 1 and (coins_too or kind[i] != KIND_COIN):
			flying[i] = 1
	Audio.play("pk_vacuum")


func add_attractor(p: Vector3, r: float) -> void:
	_attractors.append({"pos": p, "r": r})


func _merge(n: int) -> void:
	# merge the n oldest gems into one large gem at their centroid
	var idx: Array = []
	for i in range(MAX):
		if alive[i] == 1 and kind[i] <= KIND_GEM_L and flying[i] == 0:
			idx.append(i)
	if idx.size() < n:
		return
	idx.sort_custom(func(a, b): return born[a] < born[b])
	var total := 0.0
	var centroid := Vector3.ZERO
	for k in range(n):
		var i: int = idx[k]
		total += value[i]
		centroid += pos[i]
		_free(i)
	centroid /= float(n)
	var j := spawn(KIND_GEM_L, centroid, total)
	if j >= 0:
		vel[j] = Vector3.ZERO


func _free(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	free_list.append(i)
	count -= 1


func clear_all() -> void:
	for i in range(MAX):
		_free(i)


func _physics_process(delta: float) -> void:
	_time += delta
	if game == null or game.player == null:
		return
	var t0 := Time.get_ticks_usec()
	var player: Node3D = game.player
	var ppos: Vector3 = player.global_position + Vector3(0, 0.5, 0)
	var magnet: float = Run.player_sheet.get_stat("magnet", 1.5)
	if player.character and player.character.specials.has("auto_magnet"):
		magnet *= 1.6
	var m2 := magnet * magnet
	var map = game.map
	for i in range(MAX):
		if alive[i] == 0:
			continue
		if flying[i] == 1:
			var d := ppos - pos[i]
			var l := d.length()
			var sp: float = clamp(8.0 + (magnet * 6.0), 8.0, 40.0)
			pos[i] += d.normalized() * min(sp * delta, l)
			if l < 0.6:
				_collect(i)
			continue
		# settle
		vel[i].y -= 20.0 * delta
		pos[i] += vel[i] * delta
		var ground: float = (map.height_at(pos[i].x, pos[i].z) if map else 0.0) + 0.35
		if pos[i].y < ground:
			pos[i].y = ground
			vel[i] = Vector3.ZERO
		var dd := ppos - pos[i]
		dd.y = 0.0
		if dd.length_squared() < m2:
			flying[i] = 1
		else:
			for a in _attractors:
				var da: Vector3 = a["pos"] - pos[i]
				da.y = 0.0
				if da.length() < a["r"]:
					flying[i] = 1
					break
	_attractors.clear()
	_check_chests(player)
	_check_specials(player)
	_render()
	Perf.add("pickups", t0)


func _collect(i: int) -> void:
	match kind[i]:
		KIND_COIN:
			Run.add_gold(int(value[i]) * max(int(round(Run.stage_mult())), 1))
			Audio.play("pk_coin")
		KIND_VACUUM:
			vacuum_all()
		KIND_GEM_L:
			Run.add_xp(value[i])
			Audio.play("pk_gem_l")
		KIND_GEM_M:
			Run.add_xp(value[i])
			Audio.play("pk_gem_m")
		_:
			Run.add_xp(value[i])
			Audio.play("pk_gem_s")
	_free(i)


func spawn_chest(at: Vector3) -> void:
	var c := Chest.new()
	add_child(c)
	c.global_position = at
	chests.append(c)


func spawn_special(def: PickupDef, at: Vector3) -> void:
	var p := Powerup.new()
	p.setup(def)
	add_child(p)
	p.global_position = at
	specials.append(p)
	Audio.play("pk_chest_open", at)


func _check_specials(player: Node3D) -> void:
	var keep: Array = []
	for p in specials:
		if not is_instance_valid(p) or p.taken:
			continue
		var d: Vector3 = player.global_position - p.global_position
		d.y = 0.0
		if d.length() < 1.25:
			p.collect_anim()
			game.apply_pickup(p.def, p.global_position)
		else:
			keep.append(p)
	specials = keep


func _check_chests(player: Node3D) -> void:
	var keep: Array = []
	for c in chests:
		if not is_instance_valid(c):
			continue
		var d: Vector3 = player.global_position - c.global_position
		d.y = 0.0
		if d.length() < 1.3 and not c.opened:
			c.opened = true
			game.open_chest(c.global_position)
			c.open_anim()
		else:
			keep.append(c)
	chests = keep


func _render() -> void:
	var counters := PackedInt32Array()
	counters.resize(_mms.size())
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var k := kind[i]
		var mm: MultiMesh = _mms[k]
		var n := counters[k]
		var b := Basis().rotated(Vector3.UP, _time * 2.0 + float(i))
		if k == KIND_COIN:
			b = Basis().rotated(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, _time * 3.0 + float(i))
		var bob := 0.06 + sin(_time * 2.4 + float(i) * 0.9) * 0.13
		mm.set_instance_transform(n, Transform3D(b, pos[i] + Vector3(0, bob, 0)))
		counters[k] = n + 1
	for k in range(_mms.size()):
		_mms[k].visible_instance_count = counters[k]
