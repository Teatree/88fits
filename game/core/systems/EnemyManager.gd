## Every enemy in the arena lives in these packed arrays. One MultiMeshInstance3D per enemy type draws them
## as Y-billboards. Brains are a few lines of steering. No per-enemy nodes.
class_name EnemyManager
extends Node3D

signal enemy_died(def: EnemyDef, pos: Vector3, elite: EliteModDef, weapon_id: String)
signal boss_spawned(def: EnemyDef)
signal boss_died(def: EnemyDef, pos: Vector3)
signal boss_hp_changed(hp: float, max_hp: float)

const MAX := 320
const CELL := 2.5
const STATE_MOVE := 0
const STATE_WINDUP := 1
const STATE_CHARGE := 2
const STATE_DYING := 3
const STATE_ATTACK := 4
const STATE_SPAWN := 5

var game: Node = null
var player: Node3D = null
var height_fn: Callable = Callable()
var obstacles: Array = []       # Vector3(x, z, radius)
var arena_radius := 66.0
var stage_mult := 1.0
var stage_speed_mult := 1.0
var hp_time_mult := 1.0

# per-enemy data
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var kb := PackedVector3Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var speed := PackedFloat32Array()
var dmg := PackedFloat32Array()
var radius := PackedFloat32Array()
var size := PackedFloat32Array()
var armor := PackedFloat32Array()
var type_idx := PackedInt32Array()
var elite_idx := PackedInt32Array()
var state := PackedInt32Array()
var timer := PackedFloat32Array()
var cooldown := PackedFloat32Array()
var anim_t := PackedFloat32Array()
var flash := PackedFloat32Array()
var squash := PackedFloat32Array()
var flip := PackedByteArray()
var contact_cd := PackedFloat32Array()
var alive := PackedByteArray()
var charge_dir := PackedVector3Array()
var xp_scale := PackedFloat32Array()
var vtint := PackedColorArray()   # per-spawn tint (rgb) and strength (a) from the def's variance block
var away := PackedByteArray()      # 1 while walking away from the camera (back-view frames)
var view := PackedByteArray()      # eight-direction creatures: 0 front, 1 back, 2 side, 3 back-diagonal, 4 front-diagonal
## Poison: per enemy a dictionary of sources, weapon id -> {"stacks", "dmg", "t"}. One tick every POISON_TICK seconds
## deals the sum of stacks x dmg over all sources; a source hit again resets its timer instead of stacking.
var poison_src: Array = []
var poison_tick := PackedFloat32Array()
var flash_green := PackedByteArray()
const POISON_TICK := 2.0
## Fire: per enemy a dictionary of sources, weapon id -> {"dmg", "t", "dur", "spread", "root", "from"}. Hotter and shorter than
## poison (a tick every FIRE_TICK seconds), and every tick it can jump to a creature it is touching; a fire caught
## from another creature spreads at CHILD_SPREAD of the host's chance and never back to the creature it came from.
var fire_src: Array = []
var fire_tick := PackedFloat32Array()
var fire_puff := PackedFloat32Array()   # seconds until the next lick of flame (visual only)
var flash_hot := PackedByteArray()
const FIRE_TICK := 0.6
const CHILD_SPREAD := 0.4
var lift_t := PackedFloat32Array() # seconds left in the air (tornado)
var lift_d := PackedFloat32Array() # total lift duration
var lift_h := PackedFloat32Array() # current height above the ground
var lift_a := PackedFloat32Array() # swirl angle around the tornado
var lift_cd := PackedFloat32Array() # seconds before a tornado may grab this one again

var free_list: Array = []
var count_alive := 0
var boss_index := -1
var boss_attack := 0
var boss_phase_timer := 0.0
var _tick := 0

# types
var types: Array = []          # {def, mm, mmi, frames, shadow}
var type_by_id: Dictionary = {}
var elites: Array = []         # EliteModDef
var _shader: Shader = preload("res://core/shaders/enemy_billboard.gdshader")
var _sil_shader: Shader = preload("res://core/shaders/enemy_silhouette.gdshader")
var _shadow_shader: Shader = preload("res://core/shaders/blob_shadow.gdshader")
var _shadow_mm: MultiMesh
var _shadow_mmi: MultiMeshInstance3D
var _grid: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	pos.resize(MAX); vel.resize(MAX); kb.resize(MAX); hp.resize(MAX); max_hp.resize(MAX)
	speed.resize(MAX); dmg.resize(MAX); radius.resize(MAX); size.resize(MAX); armor.resize(MAX)
	type_idx.resize(MAX); elite_idx.resize(MAX); state.resize(MAX); timer.resize(MAX); cooldown.resize(MAX)
	anim_t.resize(MAX); flash.resize(MAX); squash.resize(MAX); flip.resize(MAX); contact_cd.resize(MAX)
	alive.resize(MAX); charge_dir.resize(MAX); xp_scale.resize(MAX); vtint.resize(MAX)
	away.resize(MAX); view.resize(MAX); poison_tick.resize(MAX); flash_green.resize(MAX)
	poison_src.resize(MAX); fire_src.resize(MAX); fire_tick.resize(MAX); flash_hot.resize(MAX); fire_puff.resize(MAX)
	for i in range(MAX):
		poison_src[i] = {}; fire_src[i] = {}; lift_t.resize(MAX); lift_d.resize(MAX); lift_h.resize(MAX); lift_a.resize(MAX); lift_cd.resize(MAX)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	elites = Registry.elites_list()
	_build_shadows()


func _build_shadows() -> void:
	_shadow_mm = MultiMesh.new()
	_shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	_shadow_mm.mesh = quad
	_shadow_mm.instance_count = MAX
	_shadow_mm.visible_instance_count = 0
	_shadow_mmi = MultiMeshInstance3D.new()
	_shadow_mmi.multimesh = _shadow_mm
	var mat := ShaderMaterial.new()
	mat.shader = _shadow_shader
	_shadow_mmi.material_override = mat
	_shadow_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow_mmi)


func _camera_forward() -> Vector3:
	var yaw: float = game.camera.current_yaw() if game and game.get("camera") and game.camera and game.camera.has_method("current_yaw") else 0.0
	return Vector3(-sin(yaw), 0, -cos(yaw))


## Tornado: every grounded enemy inside the radius is thrown into the air for `duration` seconds.
func lift_radius(center: Vector3, radius: float, duration: float = 1.6) -> int:
	var n := 0
	for i in indices_in_radius(center, radius):
		if lift_t[i] > 0.0 or lift_cd[i] > 0.0 or state[i] == STATE_DYING or i == boss_index:
			continue
		lift_t[i] = duration
		lift_d[i] = duration
		lift_a[i] = atan2(pos[i].z - center.z, pos[i].x - center.x)
		kb[i] = Vector3.ZERO
		n += 1
	return n


## Tornado: airborne enemies near the centre swirl around it and drift with it.
func swirl(center: Vector3, radius: float, delta: float) -> void:
	for i in range(MAX):
		if alive[i] == 0 or lift_t[i] <= 0.0:
			continue
		var d := pos[i] - center
		d.y = 0.0
		if d.length() > radius * 2.5:
			continue
		# spiral outward as the ride goes on, so the drop lands at the rim, not in the funnel
		var f := 1.0 - clampf(lift_t[i] / maxf(lift_d[i], 0.01), 0.0, 1.0)
		var r := clampf(d.length(), 0.6, radius) * (0.7 + 1.4 * f)
		var target := center + Vector3(cos(lift_a[i]), 0, sin(lift_a[i])) * r
		var np := pos[i].lerp(target, clampf(delta * 6.0, 0.0, 1.0))
		np.y = _height(np.x, np.z)
		pos[i] = np


## Register an enemy type so it can be spawned. Safe to call twice.
func register_type(def: EnemyDef) -> int:
	if def == null:
		return -1
	if type_by_id.has(def.id):
		return type_by_id[def.id]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "MM_" + def.id
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	var tex: Texture2D = def.sprite
	if tex == null:
		tex = PlaceholderArt.enemy_strip(def)
	mat.set_shader_parameter("sprite", tex)
	mat.set_shader_parameter("frames", float(def.total_frames()))
	var cols: int = def.strip_cols if def.sprite else 0
	mat.set_shader_parameter("cols", float(cols))
	mat.set_shader_parameter("rows", float(ceili(float(def.total_frames()) / float(cols))) if cols > 0 else 1.0)
	# the occluded pass: a rim where a prop hides the creature (bosses too); same strip uniforms
	var sil := ShaderMaterial.new()
	sil.shader = _sil_shader
	sil.set_shader_parameter("sprite", tex)
	sil.set_shader_parameter("frames", float(def.total_frames()))
	sil.set_shader_parameter("cols", float(cols))
	sil.set_shader_parameter("rows", float(ceili(float(def.total_frames()) / float(cols))) if cols > 0 else 1.0)
	mat.next_pass = sil
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	var t := {"def": def, "mm": mm, "mmi": mmi, "frames": def.total_frames(), "run_fps": float(def.fps.get("run", 0.0)), "eight": def.frames_of("run_s") > 0 and def.anims.has("run_s")}
	types.append(t)
	type_by_id[def.id] = types.size() - 1
	return types.size() - 1


func _height(x: float, z: float) -> float:
	if height_fn.is_valid():
		return height_fn.call(x, z)
	return 0.0


# ---------------------------------------------------------------- spawning

func spawn(def_id: String, at: Vector3, elite: EliteModDef = null, scale_mult := 1.0, hp_mult := 1.0) -> int:
	var def: EnemyDef = Registry.enemy(def_id)
	if def == null or free_list.is_empty():
		return -1
	var t := register_type(def)
	var i: int = free_list.pop_back()
	pos[i] = Vector3(at.x, _height(at.x, at.z), at.z)
	vel[i] = Vector3.ZERO
	kb[i] = Vector3.ZERO
	var ehp := def.hp * stage_mult * hp_time_mult * hp_mult
	var esp := def.speed * stage_speed_mult
	var edm := def.damage * stage_mult
	var ear := 0.0
	var esz := def.size * scale_mult
	var xps := def.xp_mult
	elite_idx[i] = -1
	if elite != null:
		elite_idx[i] = elites.find(elite)
		var sheet := StatSheet.new()
		sheet.set_bases({"hp": ehp, "speed": esp, "damage": edm, "armor": 0.0, "size": esz})
		sheet.add_effects(elite.effects, elite.id)
		ehp = sheet.get_stat("hp"); esp = sheet.get_stat("speed"); edm = sheet.get_stat("damage")
		ear = sheet.get_stat("armor"); esz = sheet.get_stat("size") * elite.scale_mult
		xps *= 4.0
	var vt := Color(1, 1, 1, 0)
	var vsize := 1.0
	if elite == null and not def.variance.is_empty():
		# every spawn is a little different: size, speed, a tint from the palette, and the odd special one
		var vr: Dictionary = def.variance
		vsize = 1.0 + _rng.randf_range(-float(vr.get("size", 0.0)), float(vr.get("size", 0.0)))
		esp *= 1.0 + _rng.randf_range(-float(vr.get("speed", 0.0)), float(vr.get("speed", 0.0)))
		var tints: Array = vr.get("tints", [])
		if not tints.is_empty():
			var c := Color(str(tints[_rng.randi() % tints.size()]))
			vt = Color(c.r, c.g, c.b, float(vr.get("tint_strength", 0.35)))
		if _rng.randf() < float(vr.get("special_chance", 0.0)):
			var sp: Dictionary = vr.get("special", {})
			vsize *= float(sp.get("size", 1.3))
			ehp *= float(sp.get("hp", 1.6))
			edm *= float(sp.get("damage", 1.2))
			xps *= float(sp.get("xp", 2.0))
			if sp.has("tint"):
				var sc := Color(str(sp["tint"]))
				vt = Color(sc.r, sc.g, sc.b, float(sp.get("tint_strength", 0.6)))
		esz *= vsize
	vtint[i] = vt
	hp[i] = ehp; max_hp[i] = ehp; speed[i] = esp; dmg[i] = edm; armor[i] = ear
	radius[i] = def.radius * scale_mult * (elite.scale_mult if elite else 1.0) * vsize
	size[i] = esz
	type_idx[i] = t
	state[i] = STATE_SPAWN
	timer[i] = 0.35
	cooldown[i] = _rng.randf_range(0.5, 2.0)
	anim_t[i] = _rng.randf() * 10.0
	flash[i] = 0.0
	squash[i] = 0.3
	flip[i] = 0
	away[i] = 0
	view[i] = 0
	poison_src[i] = {}
	poison_tick[i] = 0.0
	flash_green[i] = 0
	fire_src[i] = {}
	fire_tick[i] = 0.0
	fire_puff[i] = 0.0
	flash_hot[i] = 0
	lift_t[i] = 0.0
	lift_d[i] = 0.0
	lift_h[i] = 0.0
	lift_cd[i] = 0.0
	contact_cd[i] = 0.0
	charge_dir[i] = Vector3.ZERO
	xp_scale[i] = xps
	alive[i] = 1
	count_alive += 1
	if def.archetype == "boss":
		boss_index = i
		boss_attack = 0
		boss_phase_timer = 2.0
		var extra := pow(float(def.boss.get("hp_mult_per_stage", 1.6)), float(Run.stage))
		hp[i] = def.hp * extra * max(stage_mult, 1.0)
		max_hp[i] = hp[i]
		boss_spawned.emit(def)
		boss_hp_changed.emit(hp[i], max_hp[i])
		Audio.play(str(def.sfx.get("spawn", "en_boss_roar")))
	elif def.archetype == "elite":
		# the mini-boss: scales with the stage like a boss does, but no bar, no intro, no phase change
		var extra := pow(float(def.elite.get("hp_mult_per_stage", 1.8)), float(Run.stage))
		hp[i] = def.hp * extra * max(stage_mult, 1.0)
		max_hp[i] = hp[i]
		Audio.play("en_elite_spawn", pos[i])
	elif elite != null:
		Audio.play("en_elite_spawn", pos[i])
	return i


func spawn_pack(def_id: String, center: Vector3, n: int, elite: EliteModDef = null) -> void:
	var def: EnemyDef = Registry.enemy(def_id)
	if def == null:
		return
	var spread: float = clamp(0.6 * sqrt(float(n)) * def.radius * 2.0, 1.0, 6.0)
	for k in range(n):
		var off := Vector3(_rng.randf_range(-spread, spread), 0, _rng.randf_range(-spread, spread))
		spawn(def_id, _clamp_arena(center + off), elite)


func spawn_ring(def_id: String, count: int, center: Vector3, ring_radius: float) -> void:
	for k in range(count):
		var a := TAU * float(k) / float(maxi(count, 1)) + _rng.randf_range(-0.1, 0.1)
		var p := center + Vector3(cos(a), 0, sin(a)) * ring_radius
		spawn(def_id, _clamp_arena(p))


func spawn_boss(def_id: String, at: Vector3) -> int:
	return spawn(def_id, at)


func _clamp_arena(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > arena_radius - 2.0:
		flat = flat.normalized() * (arena_radius - 2.0)
	return Vector3(flat.x, p.y, flat.y)


func kill_all(reward: bool = false) -> void:
	for i in range(MAX):
		if alive[i] == 1 and state[i] != STATE_DYING:
			if reward:
				_die(i, "")
			else:
				_free(i)


# ---------------------------------------------------------------- damage

func damage(i: int, amount: float, weapon_id: String = "", kb_dir: Vector3 = Vector3.ZERO, kb_force: float = 0.0, green: bool = false, hot: bool = false) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return false
	var dealt: float = max(amount - armor[i], amount * 0.15)
	hp[i] -= dealt
	flash[i] = 1.0
	flash_green[i] = 1 if green else 0
	flash_hot[i] = 1 if hot else 0
	squash[i] = 0.9 if (green or hot) else 0.75
	if weapon_id != "":
		Run.add_damage(weapon_id, dealt)
	if kb_force > 0.0:
		# push away along the hit direction; heavy creatures (size in metres) budge less, the boss barely
		var mass: float = maxf(size[i], 0.8)
		var push: float = kb_force / mass * (0.15 if i == boss_index else 1.0)
		var d := Vector3(kb_dir.x, 0, kb_dir.z)
		if d.length_squared() < 0.0001:
			d = pos[i] - player.global_position if player else Vector3.FORWARD
		kb[i] += Vector3(d.x, 0, d.z).normalized() * push
	if i == boss_index:
		boss_hp_changed.emit(max(hp[i], 0.0), max_hp[i])
	var def: EnemyDef = types[type_idx[i]]["def"]
	if hp[i] <= 0.0:
		_die(i, weapon_id)
		return true
	Audio.play(str(def.sfx.get("hit", "")), pos[i])
	return false


## Poison from one item: a new source, or the same source's timer reset (stacks and damage take the higher value).
func poison(i: int, weapon_id: String, dmg_per_tick: float, stacks: int, duration: float) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return
	var src: Dictionary = poison_src[i]
	var fresh := src.is_empty()
	if src.has(weapon_id):
		var e: Dictionary = src[weapon_id]
		e["t"] = duration
		e["stacks"] = maxi(int(e["stacks"]), stacks)
		e["dmg"] = maxf(float(e["dmg"]), dmg_per_tick)
	else:
		src[weapon_id] = {"stacks": stacks, "dmg": dmg_per_tick, "t": duration}
	if fresh:
		poison_tick[i] = POISON_TICK


func is_poisoned(i: int) -> bool:
	return i >= 0 and i < MAX and not (poison_src[i] as Dictionary).is_empty()


## Fire from one item: a new source, or the same source's timer reset. `from_enemy` is the creature it jumped
## from (-1 when a weapon lit it); `spread` is this fire's own chance to jump on, per tick, per touching creature.
func ignite(i: int, weapon_id: String, dmg_per_tick: float, duration: float, spread: float, from_enemy: int = -1, root_spread: float = -1.0) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return
	var src: Dictionary = fire_src[i]
	var fresh := src.is_empty()
	if src.has(weapon_id):
		var e: Dictionary = src[weapon_id]
		e["t"] = duration
		e["dmg"] = maxf(float(e["dmg"]), dmg_per_tick)
		e["spread"] = maxf(float(e["spread"]), spread)
	else:
		src[weapon_id] = {"dmg": dmg_per_tick, "t": duration, "dur": duration, "spread": spread, "root": root_spread if root_spread >= 0.0 else spread, "from": from_enemy}
	if fresh:
		fire_tick[i] = FIRE_TICK
		if game and game.has_method("fx_ignite"):
			game.fx_ignite(pos[i] + Vector3(0, size[i] * 0.4, 0), size[i])


func is_burning(i: int) -> bool:
	return i >= 0 and i < MAX and not (fire_src[i] as Dictionary).is_empty()


## True when the creature carries the given element ("poison" or "fire"); "" is never carried.
func has_element(i: int, element: String) -> bool:
	match element:
		"poison":
			return is_poisoned(i)
		"fire":
			return is_burning(i)
	return false


## Runs the fire clocks of one enemy: expires sources, every FIRE_TICK seconds deals the sum of their ticks, and
## every source rolls to jump onto each creature this one is touching.
func _tick_fire(i: int, delta: float) -> void:
	var src: Dictionary = fire_src[i]
	if src.is_empty():
		return
	var total := 0.0
	var best_id := ""
	var best := 0.0
	for k in src.keys():
		var e: Dictionary = src[k]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			src.erase(k)
			continue
		var part: float = float(e["dmg"])
		total += part
		if part > best:
			best = part
			best_id = str(k)
	if src.is_empty():
		return
	# flames lick up the whole time it burns, not only on the damage ticks
	fire_puff[i] -= delta
	if fire_puff[i] <= 0.0:
		fire_puff[i] = 0.18
		if game and game.has_method("fx_fire"):
			game.fx_fire(pos[i] + Vector3(0, size[i] * 0.3, 0), size[i])
	fire_tick[i] -= delta
	if fire_tick[i] <= 0.0:
		fire_tick[i] = FIRE_TICK
		# spread first, so a creature that dies of this tick still passes its fire on
		for k in src.keys():
			var e: Dictionary = src[k]
			var chance := float(e["spread"])
			if chance <= 0.0:
				continue
			for j in indices_in_radius(pos[i], radius[i] + 1.2):
				if j == i or j == int(e["from"]) or alive[j] == 0 or state[j] == STATE_DYING or j == boss_index:
					continue
				var touch: float = radius[i] + radius[j] + 0.25
				var d := pos[j] - pos[i]
				d.y = 0.0
				if d.length_squared() > touch * touch:
					continue
				if (fire_src[j] as Dictionary).has(k):
					continue
				if _rng.randf() < chance:
					# every caught fire spreads at a fixed fraction of the original weapon's chance, however far down the chain
					ignite(j, str(k), float(e["dmg"]), float(e["dur"]), float(e["root"]) * CHILD_SPREAD, i, float(e["root"]))
		damage(i, total, best_id, Vector3.ZERO, 0.0, false, true)


## Runs the poison clocks of one enemy: expires sources, and every POISON_TICK seconds deals the sum of their ticks.
func _tick_poison(i: int, delta: float) -> void:
	var src: Dictionary = poison_src[i]
	if src.is_empty():
		return
	var total := 0.0
	var best_id := ""
	var best := 0.0
	for k in src.keys():
		var e: Dictionary = src[k]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			src.erase(k)
			continue
		var part: float = float(e["dmg"]) * int(e["stacks"])
		total += part
		if part > best:
			best = part
			best_id = str(k)
	if src.is_empty():
		return
	poison_tick[i] -= delta
	if poison_tick[i] <= 0.0:
		poison_tick[i] = POISON_TICK
		var was_dead := damage(i, total, best_id, Vector3.ZERO, 0.0, true)
		if game and game.has_method("fx_poison"):
			game.fx_poison(pos[i] + Vector3(0, size[i] * 0.5, 0))
		if was_dead:
			return


func damage_radius(center: Vector3, r: float, amount: float, weapon_id: String = "", kb_force: float = 0.0) -> int:
	var hit := 0
	for i in indices_in_radius(center, r):
		var d := pos[i] - center
		if damage(i, amount, weapon_id, d, kb_force):
			hit += 1
		else:
			hit += 1
	return hit


func _die(i: int, weapon_id: String) -> void:
	var def: EnemyDef = types[type_idx[i]]["def"]
	var elite: EliteModDef = elites[elite_idx[i]] if elite_idx[i] >= 0 else null
	state[i] = STATE_DYING
	timer[i] = 0.4
	vel[i] = Vector3.ZERO
	count_alive -= 1
	Audio.play(str(def.sfx.get("die", "")), pos[i])
	Run.add_kill(def.id, weapon_id)
	Save.add_total("kills", 1)
	Save.add_keyed_total("kills_of_enemy", def.id, 1)
	if weapon_id != "":
		Save.add_keyed_total("kills_with_weapon", weapon_id, 1)
	enemy_died.emit(def, pos[i], elite, weapon_id)
	if elite != null:
		match elite.on_death:
			"split":
				var n := int(elite.params.get("split_count", 3))
				var sc := float(elite.params.get("split_scale", 0.6))
				for k in range(n):
					var a := TAU * k / n
					var p := pos[i] + Vector3(cos(a), 0, sin(a)) * 1.2
					var j := spawn(def.id, p, null, sc, 0.5)
					if j >= 0:
						kb[j] = Vector3(cos(a), 0, sin(a)) * 4.0
			"explode":
				if game and game.has_method("elite_explosion"):
					game.elite_explosion(pos[i], float(elite.params.get("explode_radius", 3.0)), float(elite.params.get("explode_damage", 25.0)), float(elite.params.get("telegraph", 0.5)))
	if i == boss_index:
		boss_index = -1
		Run.bosses_killed += 1
		boss_died.emit(def, pos[i])


func _free(i: int) -> void:
	if alive[i] == 0:
		return
	if state[i] != STATE_DYING:
		count_alive -= 1
	alive[i] = 0
	free_list.append(i)
	if i == boss_index:
		boss_index = -1


# ---------------------------------------------------------------- queries

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func _rebuild_grid() -> void:
	_grid.clear()
	for i in range(MAX):
		if alive[i] == 0 or state[i] == STATE_DYING:
			continue
		var c := _cell(pos[i])
		if _grid.has(c):
			_grid[c].append(i)
		else:
			_grid[c] = [i]


func indices_in_radius(center: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cmin := _cell(center - Vector3(r, 0, r))
	var cmax := _cell(center + Vector3(r, 0, r))
	var r2 := r * r
	for cx in range(cmin.x, cmax.x + 1):
		for cz in range(cmin.y, cmax.y + 1):
			var bucket = _grid.get(Vector2i(cx, cz))
			if bucket == null:
				continue
			for i in bucket:
				var d := pos[i] - center
				d.y = 0.0
				if d.length_squared() <= r2:
					out.append(i)
	return out


func nearest_index(from: Vector3, max_range: float, avoid: String = "") -> int:
	var best := -1
	var best_d := max_range * max_range
	for i in indices_in_radius(from, max_range):
		if avoid != "" and has_element(i, avoid):
			continue
		var d := pos[i] - from
		d.y = 0.0
		var l := d.length_squared()
		if l < best_d:
			best_d = l
			best = i
	return best


func random_in_range(from: Vector3, max_range: float, exclude: Array = [], avoid: String = "") -> int:
	var cands := indices_in_radius(from, max_range)
	var pool: Array = []
	for i in cands:
		if avoid != "" and has_element(i, avoid):
			continue
		if not exclude.has(i):
			pool.append(i)
	if pool.is_empty():
		return -1
	return pool[_rng.randi() % pool.size()]


func densest_point(from: Vector3, max_range: float, avoid: String = "") -> Vector3:
	var cands := indices_in_radius(from, max_range)
	if cands.is_empty():
		return Vector3.INF
	var best := -1
	var best_n := -1
	var step: int = max(1, cands.size() / 40)
	for k in range(0, cands.size(), step):
		var i := cands[k]
		if avoid != "" and has_element(i, avoid):
			continue
		var n := 0
		for j in indices_in_radius(pos[i], 2.5):
			if avoid == "" or not has_element(j, avoid):
				n += 1
		if n > best_n:
			best_n = n
			best = i
	return pos[best] if best >= 0 else Vector3.INF


func indices_in_cone(from: Vector3, dir: Vector3, max_range: float, half_angle_deg: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var d2 := Vector2(dir.x, dir.z).normalized()
	var cos_lim := cos(deg_to_rad(half_angle_deg))
	for i in indices_in_radius(from, max_range):
		var v := Vector2(pos[i].x - from.x, pos[i].z - from.z)
		if v.length() < 0.001:
			out.append(i)
			continue
		if v.normalized().dot(d2) >= cos_lim:
			out.append(i)
	return out


func alive_count() -> int:
	return count_alive


func boss_alive() -> bool:
	return boss_index >= 0


func position_of(i: int) -> Vector3:
	return pos[i]


func is_alive(i: int) -> bool:
	return i >= 0 and i < MAX and alive[i] == 1 and state[i] != STATE_DYING


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var t0 := Time.get_ticks_usec()
	_tick += 1
	var steer := (_tick % 2) == 0
	if steer:
		_rebuild_grid()
	var ppos: Vector3 = player.global_position
	var sdt := delta * 2.0
	for i in range(MAX):
		if alive[i] == 0:
			continue
		if state[i] == STATE_DYING:
			timer[i] -= delta
			squash[i] = lerp(squash[i], 0.6, delta * 8.0)
			if timer[i] <= 0.0:
				_free(i)
			continue
		if lift_t[i] > 0.0:
			# tossed by a tornado: rises, spins, drops, then lands with a thump; no steering meanwhile
			lift_t[i] -= delta
			var f := 1.0 - clampf(lift_t[i] / maxf(lift_d[i], 0.01), 0.0, 1.0)
			lift_h[i] = sin(f * PI) * 3.2 * maxf(size[i], 0.6)
			lift_a[i] += delta * 7.0
			anim_t[i] += delta * 14.0
			flip[i] = 1 if int(lift_a[i] * 1.5) % 2 == 0 else 0
			vel[i] = Vector3.ZERO
			if lift_t[i] <= 0.0:
				# thrown out and away, and immune to the next grab for a while so it cannot get stuck in the funnel
				lift_h[i] = 0.0
				squash[i] = 0.55
				flash[i] = 0.6
				lift_cd[i] = 4.0
				kb[i] = Vector3(cos(lift_a[i]), 0, sin(lift_a[i])) * 12.0
				damage(i, max_hp[i] * 0.08, "", Vector3.ZERO, 0.0)
			continue
		if lift_cd[i] > 0.0:
			lift_cd[i] -= delta
		if state[i] == STATE_SPAWN:
			timer[i] -= delta
			squash[i] = lerp(squash[i], 1.0, delta * 10.0)
			if timer[i] <= 0.0:
				state[i] = STATE_MOVE
			continue
		# decay flash and squash
		flash[i] = max(flash[i] - delta * 6.0, 0.0)
		squash[i] = lerp(squash[i], 1.0, delta * 10.0)
		contact_cd[i] = max(contact_cd[i] - delta, 0.0)
		cooldown[i] = max(cooldown[i] - delta, 0.0)
		if steer:
			_steer(i, ppos, sdt)
		# integrate
		var v := vel[i] + kb[i]
		kb[i] = kb[i].lerp(Vector3.ZERO, delta * 6.0)
		var np := pos[i] + v * delta
		np = _clamp_arena(np)
		np.y = _height(np.x, np.z)
		pos[i] = np
		# the direction the creature faces: where it charges while winding up or charging, else where it moves
		var face := v
		if (state[i] == STATE_WINDUP or state[i] == STATE_CHARGE) and charge_dir[i].length_squared() > 0.01:
			face = charge_dir[i]
		if bool(types[type_idx[i]]["eight"]):
			if face.length_squared() > 0.04:
				var cf := _camera_forward()
				var cr := Vector3(-cf.z, 0, cf.x)   # screen-right
				var fwd := face.dot(cf)
				var right := face.dot(cr)
				var a := absf(atan2(right, fwd))     # 0 = walking away from the camera, PI = towards it
				if a < PI * 0.125:
					view[i] = 1
				elif a < PI * 0.375:
					view[i] = 3
				elif a < PI * 0.625:
					view[i] = 2
				elif a < PI * 0.875:
					view[i] = 4
				else:
					view[i] = 0
				# side and diagonal sets face screen-right; mirror them when heading left
				flip[i] = 1 if right < 0.0 else 0
		else:
			if abs(face.x) > 0.05:
				flip[i] = 1 if face.x < 0.0 else 0
			# walking away from the camera shows the back-view set (the camera forward is world -Z in fixed mode)
			if face.length_squared() > 0.04:
				var cf := _camera_forward()
				away[i] = 1 if face.dot(cf) > face.length() * 0.2 else (0 if face.dot(cf) < -face.length() * 0.2 else away[i])
		_tick_poison(i, delta)
		if alive[i] == 0:
			continue
		_tick_fire(i, delta)
		if alive[i] == 0:
			continue
		# walk cycles cut from video clips carry their own frame rate (EnemyDef.fps); the old six-frame walks run at 10
		var run_fps: float = types[type_idx[i]]["run_fps"]
		anim_t[i] += delta * ((run_fps if run_fps > 0.0 else 10.0) if v.length() > 0.2 else 3.0)
		# contact damage
		var d := ppos - pos[i]
		d.y = 0.0
		var reach := radius[i] + 0.45
		if d.length_squared() < reach * reach and contact_cd[i] <= 0.0:
			contact_cd[i] = 0.6
			var extra := 1.0
			if state[i] == STATE_CHARGE:
				extra = 1.5
			player.take_damage(dmg[i] * extra, pos[i])
	_update_boss(delta, ppos)
	Perf.add("enemies.sim", t0)
	t0 = Time.get_ticks_usec()
	_render()
	Perf.add("enemies.render", t0)


func _steer(i: int, ppos: Vector3, dt: float) -> void:
	var def: EnemyDef = types[type_idx[i]]["def"]
	var to_player := ppos - pos[i]
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player / dist if dist > 0.001 else Vector3.ZERO
	var desired := Vector3.ZERO
	var spd := speed[i]
	match state[i]:
		STATE_WINDUP:
			timer[i] -= dt
			desired = Vector3.ZERO
			if timer[i] <= 0.0:
				if def.brain == "kite" or def.brain == "boss":
					_do_attack(i, def, ppos)
					state[i] = STATE_MOVE
				else:
					# the charge runs along the line that was telegraphed at the start of the wind-up; the hero
					# moving in the meantime is exactly what the telegraph is for
					state[i] = STATE_CHARGE
					timer[i] = float(def.charge.get("duration", 0.7))
					if charge_dir[i].length_squared() < 0.01:
						charge_dir[i] = dir
					Audio.play(str(def.sfx.get("attack", "")), pos[i])
		STATE_CHARGE:
			timer[i] -= dt
			desired = charge_dir[i] * float(def.charge.get("speed", 9.0))
			if timer[i] <= 0.0:
				state[i] = STATE_MOVE
				cooldown[i] = float(def.charge.get("cooldown", 4.0))
		_:
			match def.brain:
				"chase":
					desired = dir * spd
				"flock":
					var wob := Vector3(sin(anim_t[i] * 1.7 + i), 0, cos(anim_t[i] * 1.3 + i * 0.7)) * 0.6
					desired = (dir + wob * 0.5).normalized() * spd
				"kite":
					var keep := float(def.ranged.get("keep_distance", 5.0))
					var rng := float(def.ranged.get("range", 8.0))
					if dist < keep - 0.5:
						desired = -dir * spd
					elif dist > rng:
						desired = dir * spd
					else:
						desired = Vector3.ZERO
						if cooldown[i] <= 0.0:
							state[i] = STATE_WINDUP
							timer[i] = float(def.ranged.get("telegraph", 0.6))
							if game and game.has_method("telegraph_ring"):
								game.telegraph_ring(ppos, float(def.ranged.get("splash", 1.2)), timer[i], Color(0.37, 0.64, 0.35))
				"charge":
					desired = dir * spd
					if cooldown[i] <= 0.0 and dist < float(def.charge.get("trigger_range", 6.0)):
						state[i] = STATE_WINDUP
						timer[i] = float(def.charge.get("windup", 0.8))
						charge_dir[i] = dir
						if game and game.has_method("telegraph_line"):
							game.telegraph_line(pos[i], dir, dist + 4.0, timer[i], Color(0.93, 0.29, 0.36))
				"boss":
					desired = dir * spd if boss_phase_timer > 0.0 else Vector3.ZERO
				_:
					desired = dir * spd
	# separation
	var sep := Vector3.ZERO
	var c := _cell(pos[i])
	var my_r := radius[i]
	for cx in range(c.x - 1, c.x + 2):
		for cz in range(c.y - 1, c.y + 2):
			var bucket = _grid.get(Vector2i(cx, cz))
			if bucket == null:
				continue
			for j in bucket:
				if j == i:
					continue
				var d := pos[i] - pos[j]
				d.y = 0.0
				var min_d := my_r + radius[j]
				var l2 := d.length_squared()
				if l2 < min_d * min_d and l2 > 0.0001:
					var l := sqrt(l2)
					sep += d / l * (min_d - l) / min_d
	# obstacles
	for o: Vector3 in obstacles:
		var d := Vector3(pos[i].x - o.x, 0, pos[i].z - o.y)
		var l2 := d.length_squared()
		var min_d := o.z + my_r
		if l2 < min_d * min_d and l2 > 0.0001:
			var l := sqrt(l2)
			sep += d / l * (min_d - l) * 3.0
	var sep_w := 4.0 if state[i] != STATE_CHARGE else 0.5
	vel[i] = desired + sep * sep_w


func _do_attack(i: int, def: EnemyDef, ppos: Vector3) -> void:
	cooldown[i] = float(def.ranged.get("cooldown", 2.5))
	Audio.play(str(def.sfx.get("attack", "")), pos[i])
	if game and game.has_method("enemy_spit"):
		game.enemy_spit(pos[i] + Vector3(0, size[i] * 0.6, 0), ppos, float(def.ranged.get("projectile_speed", 6.0)), dmg[i], float(def.ranged.get("splash", 1.2)))


func _update_boss(delta: float, ppos: Vector3) -> void:
	if boss_index < 0:
		return
	var i := boss_index
	if alive[i] == 0 or state[i] == STATE_DYING:
		return
	var def: EnemyDef = types[type_idx[i]]["def"]
	var attacks: Array = def.boss.get("attacks", [])
	if attacks.is_empty():
		return
	if state[i] == STATE_MOVE:
		boss_phase_timer -= delta
		if boss_phase_timer <= 0.0:
			var atk: Dictionary = attacks[boss_attack % attacks.size()]
			boss_attack += 1
			state[i] = STATE_ATTACK
			timer[i] = float(atk.get("windup", 1.0))
			var dir := ppos - pos[i]
			dir.y = 0.0
			dir = dir.normalized()
			charge_dir[i] = dir
			match str(atk.get("telegraph", "none")):
				"line":
					if game: game.telegraph_line(pos[i], dir, 22.0, timer[i], Color(0.93, 0.29, 0.36))
				"ring":
					if game: game.telegraph_ring(pos[i], float(atk.get("radius", 6.0)), timer[i], Color(0.93, 0.29, 0.36))
			Audio.play(str(def.sfx.get("attack", "en_boss_attack")), pos[i])
	elif state[i] == STATE_ATTACK:
		timer[i] -= delta
		vel[i] = Vector3.ZERO
		if timer[i] <= 0.0:
			var atk: Dictionary = attacks[(boss_attack - 1) % attacks.size()]
			match str(atk.get("name", "")):
				"roll":
					state[i] = STATE_CHARGE
					timer[i] = float(atk.get("duration", 1.2))
					dmg[i] = float(atk.get("damage", 25)) * stage_mult
				"spawn_ring":
					spawn_ring(str(atk.get("enemy", "coyote")), int(atk.get("count", 10)), pos[i], 5.0)
					state[i] = STATE_MOVE
				"slam":
					var r := float(atk.get("radius", 6.0))
					var d := ppos - pos[i]
					d.y = 0.0
					if d.length() <= r + 0.5:
						player.take_damage(float(atk.get("damage", 30)) * stage_mult, pos[i])
						if player.has_method("apply_knockback"):
							player.apply_knockback(d.normalized() * float(atk.get("knockback", 6.0)))
					if game and game.has_method("shockwave"):
						game.shockwave(pos[i], r)
					state[i] = STATE_MOVE
				_:
					state[i] = STATE_MOVE
			boss_phase_timer = float(def.boss.get("cooldown_between", 2.0))
	elif state[i] == STATE_CHARGE:
		timer[i] -= delta
		vel[i] = charge_dir[i] * float(attacks[(boss_attack - 1) % attacks.size()].get("speed", 12.0))
		if timer[i] <= 0.0:
			state[i] = STATE_MOVE
			dmg[i] = def.damage * stage_mult
			boss_phase_timer = float(def.boss.get("cooldown_between", 2.0))


func _render() -> void:
	# compact instances per type
	var counters := PackedInt32Array()
	counters.resize(types.size())
	var shadow_n := 0
	var cam_x := 0.0
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var t := type_idx[i]
		var td: Dictionary = types[t]
		var def: EnemyDef = td["def"]
		var mm: MultiMesh = td["mm"]
		var k := counters[t]
		var s := size[i]
		var xf := Transform3D(Basis().scaled(Vector3(s, s, s)), pos[i] + Vector3(0, lift_h[i], 0))
		mm.set_instance_transform(k, xf)
		var anim := "run"
		if state[i] == STATE_DYING:
			anim = "die"
		elif state[i] == STATE_WINDUP or state[i] == STATE_ATTACK:
			anim = "attack"
		elif state[i] == STATE_SPAWN:
			anim = "idle"
		elif vel[i].length_squared() < 0.04:
			anim = "idle"
		if flash[i] > 0.6 and def.frames_of("hit") > 0 and state[i] != STATE_DYING:
			anim = "hit"
		if bool(td["eight"]):
			# eight-direction creatures: chargers keep their directional run while charging and hold the idle set while winding up
			if state[i] == STATE_CHARGE:
				anim = "run"
			elif state[i] == STATE_WINDUP and def.charge.size() > 0:
				anim = "idle"
			if anim == "run" or anim == "idle":
				var suffix: String = ["", "_b", "_s", "_bd", "_fd"][view[i]]
				if def.frames_of(anim + suffix) > 0 and def.anims.has(anim + suffix):
					anim += suffix
		elif away[i] == 1 and (anim == "run" or anim == "idle") and def.frames_of(anim + "_b") > 0:
			anim += "_b"
		var n := def.frames_of(anim)
		var frame := def.frame_offset(anim) + (int(anim_t[i]) % maxi(n, 1))
		var sq := squash[i]
		# procedural bob while moving
		if anim == "run":
			sq += sin(anim_t[i] * 1.5) * 0.05
		# the flash: white, green for a poison tick (negative), orange for a fire tick (2 + flash)
		var fl: float = flash[i]
		if flash_green[i] == 1:
			fl = -fl
		elif flash_hot[i] == 1:
			fl = 2.0 + fl
		mm.set_instance_custom_data(k, Color(float(frame), float(flip[i]), fl, sq))
		var tint := vtint[i]
		if elite_idx[i] >= 0:
			var e: EliteModDef = elites[elite_idx[i]]
			tint = Color(e.outline.r, e.outline.g, e.outline.b, 0.7)
		if not (fire_src[i] as Dictionary).is_empty():
			# red-orange that flickers between ember and flame while burning (the shader mixes 65% of the tint's alpha)
			tint = Color(1.0, 0.18 + 0.22 * absf(sin(anim_t[i] * 5.0 + float(i))), 0.02, 1.0)
		elif not (poison_src[i] as Dictionary).is_empty():
			tint = Color(0.45, 1.0, 0.3, 0.8)   # bright green while poisoned
		mm.set_instance_color(k, tint)
		counters[t] = k + 1
		# shadow (stays on the ground and shrinks while the creature is in the air)
		var shs: float = s / (1.0 + lift_h[i] * 0.5)
		var sh := Transform3D(Basis().scaled(Vector3(shs * 0.55, 1, shs * 0.34)), pos[i] + Vector3(0, 0.03, 0))
		_shadow_mm.set_instance_transform(shadow_n, sh)
		shadow_n += 1
	for t in range(types.size()):
		types[t]["mm"].visible_instance_count = counters[t]
	_shadow_mm.visible_instance_count = shadow_n
