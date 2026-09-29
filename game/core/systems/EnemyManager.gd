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
## Seconds a body stays: the die frames play at the def's die fps, the body holds, then sinks in the last DIE_SINK.
const DIE_TIME := 1.4
const DIE_SINK := 0.3

var game: Node = null
var player: Node3D = null
var height_fn: Callable = Callable()
var obstacles: Array = []       # Vector3(x, z, radius)
var _splashing := false         # inside an Overkill splash: its kills do not splash again
var hidden := PackedByteArray()   # buried (the ambush brain) or under the sand (a boss burrow): not drawn, not hit, not targeted
var atk_i := PackedInt32Array()        # attack runner (boss and casters): which attack is next
var atk_t := PackedFloat32Array()      # seconds until the next attack
var atk_target := PackedVector3Array() # where a ring_at_hero attack lands
var frenzy_t := PackedFloat32Array()   # seconds of the shaman's drive left (+speed)
var arena_radius := 66.0
var stage_mult := 1.0
## creatures grow with the hero's level (the director sets these from the timeline)
var level_hp_mult := 1.0
var level_dmg_mult := 1.0
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
## Pass 26 statuses: a slow (fraction, seconds), a mark (damage taken multiplier, seconds), the hornets' twister (seconds and
## where it drags the creature to) and a hold (a caster standing still while its rain falls).
var slow_t := PackedFloat32Array()
## the creature holding the hero on a rope (Game sets it): it stands where it threw from and never walks; its outline
## pulses red (the glow level rides on the flip channel, enemy_billboard.gdshader), and while the hero drags it (pass
## 33.10) it shows its wind-up frames for `tether_drag_t` seconds after each pull
var tethered_i := -1
var tether_drag_t := 0.0
## High Noon (the Drifter's perk, pass 34): every creature runs on this fraction of the clock while it lasts
var time_scale := 1.0
## Bounty Hunter (the Drifter's perk, pass 34): the creature wearing the bounty glows warm
var bounty_i := -1
# in a Gravity Gun's grip (pass 35): the gun moves it (pos on the ground under it, lift_h above), nothing hits it, it
# neither steers nor bites, and it is out of the grid; `release` hands it back to the crowd
var held := PackedByteArray()
var _glow_clock := 0.0
## a walking bomb that already went off: its death burst is not fired a second time
var blown := PackedByteArray()
## Rattle's slow, read once a frame in _physics_process instead of per creature
var _poison_slow := 0.0
## how many shadows a crowd may draw: beyond this only the creatures nearest the hero get one (a blend-mode quad
## each, and a phone pays for every overlapping one)
const SHADOW_BUDGET := 70
var slow_f := PackedFloat32Array()
var mark_t := PackedFloat32Array()
var mark_mult := PackedFloat32Array()
var spin_t := PackedFloat32Array()
var spin_to := PackedVector3Array()
var hold_t := PackedFloat32Array()
var _rains: Array = []   # the Djinn's strikes in flight: {left, next, interval, spread, radius, damage, strikes: [{at, t}]}
var lift_d := PackedFloat32Array() # total lift duration
var lift_h := PackedFloat32Array() # current height above the ground
var lift_a := PackedFloat32Array() # swirl angle around the tornado
var lift_cd := PackedFloat32Array() # seconds before a tornado may grab this one again

var free_list: Array = []
var count_alive := 0
var boss_index := -1
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
var _rng := RandomNumberGenerator.new()
## The crowd's grid (pass 33.8): flat arrays instead of a dictionary of arrays. Each cell holds the first creature in it
## (`_g_head`, -1 for none) and each creature the next one in its cell (`_g_next`), rebuilt every tick. Cells are CELL
## metres on the same boundaries as before, and each cell lists its creatures in index order, so every query returns
## what it always did, in the same order.
var _gw := 0
var _g_half := 0.0
var _g_head := PackedInt32Array()
var _g_next := PackedInt32Array()
## The map's obstacles by cell (pass 33.8): a creature checks only the obstacles whose circle, widened by the widest
## creature, reaches its cell. It used to check every obstacle on the map every time it steered.
const OBST_CELL := 4.0
var _obst_cells: Dictionary = {}   # Vector2i -> PackedInt32Array of obstacle indices, in order
var _obst_n := -1
var _obst_margin := 0.0
var _max_r := 0.0
## Per type, read every tick (pass 33.8: a dictionary lookup per creature per tick before): an eight-direction strip,
## its walk and death frame rates, whether it turns to face the hero when it stands (the ranged brains), its MultiMesh,
## its badge, and the frame table (offset and count of each of the 13 strips, and which of them exist).
var _t_eight := PackedByteArray()
var _t_run_fps := PackedFloat32Array()
var _t_die_fps := PackedFloat32Array()
var _t_faces := PackedByteArray()
var _t_mm: Array = []
var _t_badge := PackedStringArray()
var _t_hit_ok := PackedByteArray()
var _t_charge := PackedByteArray()
var _t_off := PackedInt32Array()
var _t_cnt := PackedInt32Array()
var _t_ok := PackedByteArray()     # eight-direction: the strip exists (frames_of > 0 and in the anims)
var _t_okb := PackedByteArray()    # the back strip counts (frames_of > 0, as the old check read it): run_b, idle_b
const ANIM_NAMES := ["run", "idle", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
const N_ANIMS := 13
const A_RUN := 0
const A_IDLE := 1
const A_ATTACK := 2
const A_HIT := 3
const A_DIE := 4
## the strip for run (row 0) or idle (row 1) seen from view 0 front, 1 back, 2 side, 3 back-diagonal, 4 front-diagonal
const VIEW_ANIM := [[0, 5, 7, 9, 11], [1, 6, 8, 10, 12]]
var _cf_tick := Vector3(0, 0, -1)  # the camera's forward, read once a tick
var _ticks := 0                    # physics ticks run: the draw waits for a new one
var _drawn := -1


func _ready() -> void:
	_rng.randomize()
	pos.resize(MAX); vel.resize(MAX); kb.resize(MAX); hp.resize(MAX); max_hp.resize(MAX)
	speed.resize(MAX); dmg.resize(MAX); radius.resize(MAX); size.resize(MAX); armor.resize(MAX); blown.resize(MAX)
	hidden.resize(MAX); held.resize(MAX); atk_i.resize(MAX); atk_t.resize(MAX); atk_target.resize(MAX); frenzy_t.resize(MAX)
	slow_t.resize(MAX); slow_f.resize(MAX); mark_t.resize(MAX); mark_mult.resize(MAX); spin_t.resize(MAX); spin_to.resize(MAX); hold_t.resize(MAX)
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


## Where a creature that fights at range stands so the player sees it: `keep` metres off the hero, on his portrait
## screen. That is up the screen from him (or a little below him when the creature is already well below him), and
## never more than `side` metres to either side: the screen is narrow, and a caster that parked 14 m off to the side
## sat under the HUD strip at the screen's edge, where nobody could find it (pass 33.1).
func _screen_spot(i: int, ppos: Vector3, keep: float, side: float) -> Vector3:
	var cf := _camera_forward()
	var cr := Vector3(-cf.z, 0, cf.x)
	var off := pos[i] - ppos
	off.y = 0.0
	var up := off.dot(cf)
	var along: float = keep if up > -keep * 0.35 else -minf(keep * 0.7, 6.0)
	return ppos + cf * along + cr * clampf(off.dot(cr), -side, side)


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
	# one type per art variant (pass 34): the game's is keyed by the id, another by id@code (EnemyDef.type_key)
	var key := def.type_key()
	if type_by_id.has(key):
		return type_by_id[key]
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
	mmi.name = "MM_" + key.replace("@", "_")
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
	var t := {"def": def, "mm": mm, "mmi": mmi, "mat": mat, "share": def.cap_share, "frames": def.total_frames(), "run_fps": float(def.fps.get("run", 0.0)), "die_fps": float(def.fps.get("die", 6.0)), "eight": def.frames_of("run_s") > 0 and def.anims.has("run_s"),
		"badge": def.badge_for(), "head": def.head}
	types.append(t)
	type_by_id[key] = types.size() - 1
	_t_eight.append(1 if bool(t["eight"]) else 0)
	_t_run_fps.append(float(t["run_fps"]))
	_t_die_fps.append(float(t["die_fps"]))
	_t_faces.append(1 if def.brain in ["caster", "kite", "artillery", "support"] else 0)
	_t_mm.append(mm)
	_t_badge.append(str(t["badge"]))
	_t_hit_ok.append(1 if def.frames_of("hit") > 0 else 0)
	_t_charge.append(1 if def.charge.size() > 0 else 0)
	for a: String in ANIM_NAMES:
		_t_off.append(def.frame_offset(a))
		_t_cnt.append(def.frames_of(a))
		_t_ok.append(1 if def.frames_of(a) > 0 and def.anims.has(a) else 0)
	_t_okb.append(1 if def.frames_of("run_b") > 0 else 0)
	_t_okb.append(1 if def.frames_of("idle_b") > 0 else 0)
	return types.size() - 1


func _height(x: float, z: float) -> float:
	if height_fn.is_valid():
		return height_fn.call(x, z)
	return 0.0


# ---------------------------------------------------------------- spawning

func spawn(def_id: String, at: Vector3, elite: EliteModDef = null, scale_mult := 1.0, hp_mult := 1.0, variant := "") -> int:
	var def: EnemyDef = Registry.enemy(def_id)
	if def == null or free_list.is_empty():
		return -1
	if variant != "":
		# another art variant (the arena's comparison): the same creature, its own strip and type
		def = def.variant_def(variant)
	var t := register_type(def)
	var i: int = free_list.pop_back()
	blown[i] = 0
	held[i] = 0
	pos[i] = Vector3(at.x, _height(at.x, at.z), at.z)
	vel[i] = Vector3.ZERO
	kb[i] = Vector3.ZERO
	var ehp := def.hp * stage_mult * hp_time_mult * hp_mult * level_hp_mult
	var esp := def.speed * stage_speed_mult
	var edm := def.damage * stage_mult * level_dmg_mult
	var ear := def.armor
	var esz := def.size * scale_mult
	var xps := def.xp_mult
	elite_idx[i] = -1
	if elite != null:
		elite_idx[i] = elites.find(elite)
		var sheet := StatSheet.new()
		sheet.set_bases({"hp": ehp, "speed": esp, "damage": edm, "armor": def.armor, "size": esz})
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
	_max_r = maxf(_max_r, radius[i])
	size[i] = esz
	type_idx[i] = t
	state[i] = STATE_SPAWN
	timer[i] = 0.35
	cooldown[i] = _rng.randf_range(0.5, 2.0)
	hidden[i] = 0
	atk_i[i] = 0
	atk_t[i] = 2.0
	frenzy_t[i] = 0.0
	slow_t[i] = 0.0; slow_f[i] = 0.0; mark_t[i] = 0.0; mark_mult[i] = 1.0; spin_t[i] = 0.0; hold_t[i] = 0.0
	if def.brain == "ambush":
		# it waits under the sand for the hero to walk over it
		hidden[i] = 1
		state[i] = STATE_MOVE
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
		atk_i[i] = 0
		atk_t[i] = 2.0
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
	if def.brain == "artillery":
		_stand_off(i, def)
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
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
		return false
	var dealt: float = max(amount - armor[i], amount * 0.15)
	# Cauterize: a marked creature takes more from everything while the mark lasts
	if mark_t[i] > 0.0:
		dealt *= mark_mult[i]
	# a weapon's own statuses: the mark, the twister, the pull (Wide Orbit, Lasso)
	if weapon_id != "" and not green and not hot:
		var wi := Run.weapon_instance(weapon_id)
		if wi:
			var mk: float = wi.stat("mark", 0.0)
			if mk > 0.0:
				mark_t[i] = 3.0
				mark_mult[i] = 1.0 + mk
			var sp: float = wi.stat("spin", 0.0)
			if sp > 0.0 and spin_t[i] <= 0.0 and i != boss_index:
				twist(i, sp, player.global_position if player else pos[i])
			var pl: float = wi.stat("pull", 0.0)
			if pl > 0.0 and player:
				var tow := player.global_position - pos[i]
				tow.y = 0.0
				if tow.length_squared() > 0.01:
					kb[i] += tow.normalized() * pl
	# Deadeye: a weapon hit (never a poison or fire tick) can crit for crit_damage times the damage
	var crit := false
	if weapon_id != "" and not green and not hot:
		var cc: float = Run.player_sheet.get_stat("crit_chance", 0.0)
		if cc > 0.0 and randf() < cc:
			dealt *= Run.player_sheet.get_stat("crit_damage", 2.0)
			crit = true
	hp[i] -= dealt
	flash[i] = 1.0
	flash_green[i] = 1 if green else 0
	flash_hot[i] = 1 if hot else 0
	squash[i] = 0.55 if crit else (0.9 if (green or hot) else 0.75)
	if crit and game:
		game.fx.burst(pos[i] + Vector3(0, size[i] * 0.7, 0), Color(1.0, 0.9, 0.35), 0.6)
	if weapon_id != "":
		Run.add_damage(weapon_id, dealt)
	# Guillotine: a weapon hit finishes anything but a boss that is already below the threshold
	if hp[i] > 0.0 and weapon_id != "" and i != boss_index and str((types[type_idx[i]]["def"] as EnemyDef).archetype) != "boss":
		var ex: float = Run.player_sheet.get_stat("execute_frac", 0.0)
		if ex > 0.0 and hp[i] <= max_hp[i] * ex:
			hp[i] = 0.0
			if game:
				game.fx.burst(pos[i] + Vector3(0, size[i] * 0.5, 0), Color(0.9, 0.15, 0.2), 0.9)
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
		var overflow: float = -hp[i]
		_die(i, weapon_id)
		# Overkill: the damage past the kill splashes onto whatever stood next to it (once, no chains)
		var ok: float = Run.player_sheet.get_stat("overkill", 0.0)
		if ok > 0.0 and overflow > 0.5 and weapon_id != "" and not _splashing:
			_splashing = true
			damage_radius(pos[i], 2.5, overflow * ok, weapon_id, 3.0)
			_splashing = false
			if game:
				game.fx.burst(pos[i] + Vector3(0, 0.5, 0), Color(1.0, 0.6, 0.25), 1.6)
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


## A slow: the stronger of the two when one is already on.
func slow(i: int, frac: float, seconds: float) -> void:
	if i < 0 or i >= MAX or alive[i] == 0:
		return
	slow_f[i] = maxf(slow_f[i] if slow_t[i] > 0.0 else 0.0, frac)
	slow_t[i] = maxf(slow_t[i], seconds)


func slow_radius(center: Vector3, r: float, frac: float, seconds: float) -> void:
	for i in indices_in_radius(center, r):
		slow(i, frac, seconds)


## The hornets' twister: the creature is lifted for `seconds`, cannot walk or bite, and drifts towards `to`.
func twist(i: int, seconds: float, to: Vector3) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return
	spin_t[i] = seconds
	spin_to[i] = to
	if lift_t[i] <= 0.0:
		lift_t[i] = seconds
		lift_d[i] = seconds
		lift_a[i] = atan2(pos[i].z - to.z, pos[i].x - to.x)
	kb[i] = Vector3.ZERO
	if game:
		game.fx_burst(pos[i] + Vector3(0, size[i] * 0.4, 0), Color(0.98, 0.9, 0.6), 1.2)


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
		damage(i, (total) * (1.0 + Run.player_sheet.get_stat("fire_vuln", 0.0)), best_id, Vector3.ZERO, 0.0, false, true)


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


## `weapon_id` "revive" is the hero standing up again: the crowd around him is gone outright, while an Elite or a
## boss takes a tenth of its health instead. "loose_rocket" is a rocket whose thrower died: it throws the crowd and
## barely scratches it.
## A blast throws everything within `r` away from `center` without hurting it (pass 33.3, the rocketeer's rocket): the
## push falls off to half at the rim, heavy creatures budge less and the boss barely, and each lands squashed.
func throw_radius(center: Vector3, r: float, force: float) -> int:
	var n := 0
	for i in indices_in_radius(center, r):
		if hidden[i] == 1 or state[i] == STATE_DYING or lift_t[i] > 0.0:
			continue
		var d := pos[i] - center
		d.y = 0.0
		if d.length_squared() < 0.0001:
			d = Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0))
		var fall_off: float = 1.0 - 0.5 * clampf(d.length() / maxf(r, 0.1), 0.0, 1.0)
		var mass: float = maxf(size[i], 0.8)
		kb[i] += d.normalized() * force * fall_off / mass * (0.15 if i == boss_index else 1.0)
		squash[i] = 0.6
		flash[i] = maxf(flash[i], 0.5)
		n += 1
	return n


func damage_radius(center: Vector3, r: float, amount: float, weapon_id: String = "", kb_force: float = 0.0) -> int:
	var hit := 0
	for i in indices_in_radius(center, r):
		var d := pos[i] - center
		var amt := amount
		if weapon_id == "revive":
			var bdef: EnemyDef = types[type_idx[i]]["def"]
			if i == boss_index or bdef.archetype == "elite" or bdef.archetype == "boss":
				amt = max_hp[i] * 0.1
		if damage(i, amt, weapon_id, d, kb_force):
			hit += 1
		else:
			hit += 1
	return hit


func _die(i: int, weapon_id: String) -> void:
	held[i] = 0
	var def: EnemyDef = types[type_idx[i]]["def"]
	var elite: EliteModDef = elites[elite_idx[i]] if elite_idx[i] >= 0 else null
	# Blight: a creature that dies poisoned passes every source on to the nearest one
	if Run.player_sheet.get_stat("poison_pass", 0.0) > 0.0 and not (poison_src[i] as Dictionary).is_empty():
		var best := -1
		var best_d := 9.0
		for j in indices_in_radius(pos[i], 3.0):
			if j == i or state[j] == STATE_DYING:
				continue
			var dd := pos[j].distance_squared_to(pos[i])
			if dd < best_d:
				best_d = dd
				best = j
		if best >= 0:
			for wid in (poison_src[i] as Dictionary).keys():
				var src: Dictionary = poison_src[i][wid]
				poison(best, str(wid), float(src.get("dmg", 3.0)), int(src.get("stacks", 1)), float(src.get("t", 8.0)))
			if game:
				game.fx_burst(pos[best] + Vector3(0, size[best] * 0.6, 0), Color(0.5, 1.0, 0.4), 0.9)
	state[i] = STATE_DYING
	timer[i] = DIE_TIME
	anim_t[i] = 0.0
	kb[i] = Vector3.ZERO
	poison_src[i] = {}
	fire_src[i] = {}
	vel[i] = Vector3.ZERO
	count_alive -= 1
	Audio.play(str(def.sfx.get("die", "")), pos[i])
	Run.add_kill(def.id, weapon_id)
	Save.add_total("kills", 1)
	Save.add_keyed_total("kills_of_enemy", def.id, 1)
	if weapon_id != "":
		Save.add_keyed_total("kills_with_weapon", weapon_id, 1)
	enemy_died.emit(def, pos[i], elite, weapon_id)
	if game and game.has_method("on_creature_died_index"):
		game.on_creature_died_index(i)
	if not def.death_burst.is_empty() and blown[i] == 0 and game and game.has_method("elite_explosion"):
		# the body goes off after a moment: a red ring on the corpse says so; the crowd around it takes a fifth
		var dbst: Dictionary = def.death_burst
		game.elite_explosion(pos[i], float(dbst.get("radius", 2.4)), float(dbst.get("damage", 12.0)) * stage_mult * level_dmg_mult,
			float(dbst.get("delay", 2.0)), float(dbst.get("knockback", 0.0)), 0.2, hit_info(i, "melee", ["death burst"]))
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
					game.elite_explosion(pos[i], float(elite.params.get("explode_radius", 3.0)), float(elite.params.get("explode_damage", 25.0)), float(elite.params.get("telegraph", 0.5)), 0.0, 0.2, hit_info(i, "melee", ["explosion"]))
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
	held[i] = 0
	free_list.append(i)
	if i == boss_index:
		boss_index = -1


# ---------------------------------------------------------------- queries

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


## A grid column (or row) for a coordinate, clamped to the grid; the grid's edge sits on a CELL boundary, so the cells
## are the old ones.
func _gcol(v: float) -> int:
	return clampi(int(floor((v + _g_half) / CELL)), 0, _gw - 1)


func _rebuild_grid() -> void:
	var half: float = ceilf((arena_radius + 12.0) / CELL) * CELL
	if _gw == 0 or half != _g_half:
		_g_half = half
		_gw = int(half * 2.0 / CELL) + 1
		_g_head.resize(_gw * _gw)
		_g_next.resize(MAX)
	_g_head.fill(-1)
	# backwards, so every cell lists its creatures in index order
	for i in range(MAX - 1, -1, -1):
		if alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
			continue
		var c := _gcol(pos[i].z) * _gw + _gcol(pos[i].x)
		_g_next[i] = _g_head[c]
		_g_head[c] = i


func indices_in_radius(center: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _gw == 0:
		return out
	var x0 := _gcol(center.x - r)
	var x1 := _gcol(center.x + r)
	var z0 := _gcol(center.z - r)
	var z1 := _gcol(center.z + r)
	var r2 := r * r
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var i := _g_head[cz * _gw + cx]
			while i >= 0:
				var dx := pos[i].x - center.x
				var dz := pos[i].z - center.z
				if dx * dx + dz * dz <= r2:
					out.append(i)
				i = _g_next[i]
	return out


## How hard the map's obstacles push creature `i` away: only the ones whose cell list reaches its cell, summed in the
## order of the map's list, as the loop over all of them did (a far obstacle added nothing).
func _obstacle_push(i: int) -> Vector3:
	var push := Vector3.ZERO
	var near_obst = _obst_cells.get(Vector2i(floori(pos[i].x / OBST_CELL), floori(pos[i].z / OBST_CELL)))
	if near_obst == null:
		return push
	var my_r := radius[i]
	for k: int in near_obst:
		var o: Vector3 = obstacles[k]
		var d := Vector3(pos[i].x - o.x, 0, pos[i].z - o.y)
		var l2 := d.length_squared()
		var min_d := o.z + my_r
		if l2 < min_d * min_d and l2 > 0.0001:
			var l := sqrt(l2)
			push += d / l * (min_d - l) * 3.0
	return push


## The obstacle cells, built again whenever the map's obstacles change in number or a wider creature turns up.
func _obstacle_cells() -> void:
	if _obst_n == obstacles.size() and _max_r <= _obst_margin:
		return
	_obst_cells.clear()
	_obst_n = obstacles.size()
	_obst_margin = maxf(_max_r, 1.5)
	for k in range(obstacles.size()):
		var o: Vector3 = obstacles[k]
		var reach: float = o.z + _obst_margin
		for cx in range(floori((o.x - reach) / OBST_CELL), floori((o.x + reach) / OBST_CELL) + 1):
			for cz in range(floori((o.y - reach) / OBST_CELL), floori((o.y + reach) / OBST_CELL) + 1):
				var key := Vector2i(cx, cz)
				var arr: PackedInt32Array = _obst_cells.get(key, PackedInt32Array())
				arr.append(k)
				_obst_cells[key] = arr


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


## The creature in range with the most others within 2.5 m. `avoid` leaves out creatures carrying that element (a fire
## bomb wants the unburnt); `keep_away` leaves out creatures within `keep_r` of those spots, as candidates and in the
## count (pass 36: where other bombs are headed or just landed, so two bomb weapons pick two crowds).
func densest_point(from: Vector3, max_range: float, avoid: String = "", keep_away: Array = [], keep_r: float = 0.0) -> Vector3:
	var cands := indices_in_radius(from, max_range)
	if cands.is_empty():
		return Vector3.INF
	var best := -1
	var best_n := -1
	var step: int = max(1, cands.size() / 40)
	var kr2 := keep_r * keep_r
	for k in range(0, cands.size(), step):
		var i := cands[k]
		if avoid != "" and has_element(i, avoid):
			continue
		if _near_any(pos[i], keep_away, kr2):
			continue
		var n := 0
		for j in indices_in_radius(pos[i], 2.5):
			if (avoid == "" or not has_element(j, avoid)) and not _near_any(pos[j], keep_away, kr2):
				n += 1
		if n > best_n:
			best_n = n
			best = i
	return pos[best] if best >= 0 else Vector3.INF


func _near_any(p: Vector3, spots: Array, r2: float) -> bool:
	for s: Vector3 in spots:
		var dx := p.x - s.x
		var dz := p.z - s.z
		if dx * dx + dz * dz < r2:
			return true
	return false


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


## The crowd against the director's cap: each living creature counts its `cap_share` (the fodder counts half).
func cap_load() -> float:
	var load := 0.0
	for i in range(MAX):
		if alive[i] == 1 and state[i] != STATE_DYING:
			load += float(types[type_idx[i]].get("share", 1.0))
	return load


## Who hit the hero, for his death log (pass 33.2): the creature's name ("Goblin", "Sun Prophet (Elite)"), how it hit
## ("melee", "ranged", or "boss" for anything a boss does) and what came with it ("knocked back", "roped" ...).
func hit_info(i: int, kind: String, fx: Array = []) -> Dictionary:
	var name := "something"
	var boss := false
	if i >= 0 and i < MAX and type_idx[i] >= 0 and type_idx[i] < types.size():
		var def: EnemyDef = types[type_idx[i]]["def"]
		name = def.display_name
		if def.archetype == "elite":
			name += " (Elite)"
		boss = i == boss_index or def.archetype == "boss"
	return {"by": name, "kind": "boss" if boss else kind, "fx": fx}


## How many of one creature are alive right now (the director's `max_alive` rows).
func alive_of(id: String) -> int:
	var ti: int = type_by_id.get(id, -1)
	if ti < 0:
		return 0
	var n := 0
	for i in range(MAX):
		if alive[i] == 1 and type_idx[i] == ti and state[i] != STATE_DYING:
			n += 1
	return n


## The rope: a creature on a tether is pulled to `length` of the hero whenever the rope is taut, so the hero drags it
## along wherever he goes. Returns how far it was dragged this time (0 when the rope is slack), or -1 once it is gone.
func tether_pull(i: int, ppos: Vector3, length: float) -> float:
	if not is_alive(i):
		return -1.0
	var d := ppos - pos[i]
	d.y = 0.0
	var dist := d.length()
	if dist > length and dist > 0.01:
		var moved := dist - length
		pos[i] += d.normalized() * moved
		pos[i].y = _height(pos[i].x, pos[i].z)
		vel[i] = Vector3.ZERO
		if moved > 0.002:
			tether_drag_t = 0.18
		return moved
	return 0.0


## How strongly the roped creature's outline glows right now: a slow red pulse, 0.35 to 1 about every 1.4 s.
## Whether the Gravity Gun may take creature `i` (pass 35): an ordinary creature on its feet; never a boss, an Elite,
## an elite-modded one, a special (EnemyDef.can_be_grabbed false: the rocketeer, the harpooner) or one already held.
func grabbable(i: int) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
		return false
	if lift_t[i] > 0.0 or i == boss_index or elite_idx[i] >= 0 or i == tethered_i:
		return false
	var def: EnemyDef = types[type_idx[i]]["def"]
	return def.archetype != "boss" and def.archetype != "elite" and def.can_be_grabbed


## Into the grip: out of the crowd until `release`.
func grab(i: int) -> void:
	held[i] = 1
	vel[i] = Vector3.ZERO
	kb[i] = Vector3.ZERO
	charge_dir[i] = Vector3.ZERO
	state[i] = STATE_MOVE
	timer[i] = 0.0
	flash[i] = 0.8


## Where a held creature is (the Gravity Gun moves it through here: a write to `pos` from outside copies the array):
## `at` is where it floats, pos stays on the ground under it and lift_h carries the height. `wriggle` > 0 squashes it.
func place_held(i: int, at: Vector3, wriggle: float = -1.0, turn: bool = false) -> void:
	var gy := _height(at.x, at.z)
	pos[i] = Vector3(at.x, gy, at.z)
	lift_h[i] = maxf(at.y - gy, 0.0)
	if wriggle > 0.0:
		squash[i] = wriggle
	if turn:
		flip[i] = 1 - flip[i]


## The Singularity's drag (pass 35): everything within `r` of `center` moves up to `speed_mps` towards it this frame,
## harder near the middle; bosses and Elites at a fifth. A held or buried creature is out of the grid and stays put.
func drag_radius(center: Vector3, r: float, speed_mps: float, delta: float) -> void:
	for e in indices_in_radius(center, r):
		if state[e] == STATE_DYING or lift_t[e] > 0.0:
			continue
		var d := center - pos[e]
		d.y = 0.0
		var dist := d.length()
		if dist < 0.25:
			continue
		var strength: float = speed_mps * (0.45 + 0.55 * (1.0 - dist / maxf(r, 0.1)))
		var def: EnemyDef = types[type_idx[e]]["def"]
		if e == boss_index or def.archetype == "boss" or def.archetype == "elite":
			strength *= 0.2
		var np := pos[e] + d / dist * minf(strength * delta, dist - 0.2)
		np.y = _height(np.x, np.z)
		pos[e] = np


## Out of the grip, on the ground where the gun left it (pos), a little squashed from the landing.
func release(i: int) -> void:
	if i < 0 or i >= MAX:
		return
	held[i] = 0
	lift_h[i] = 0.0
	if alive[i] == 1 and state[i] != STATE_DYING:
		pos[i].y = _height(pos[i].x, pos[i].z)
		vel[i] = Vector3.ZERO
		kb[i] = Vector3.ZERO
		squash[i] = 0.5
		cooldown[i] = maxf(cooldown[i], 0.6)


func tether_glow() -> float:
	return 0.35 + 0.65 * (0.5 + 0.5 * sin(_glow_clock * 4.5))


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
	# every creature steers every other tick, as before, but half of the crowd on each tick (pass 33.8: all of them on
	# the even ticks made every other frame three times the cost of the one between)
	var parity := _tick & 1
	_rebuild_grid()
	_obstacle_cells()
	_cf_tick = _camera_forward()
	# High Noon slows the whole crowd's clock: steering, attacks, animations
	delta *= time_scale
	var ppos: Vector3 = player.global_position
	var sdt := delta * 2.0
	tether_drag_t = maxf(tether_drag_t - delta, 0.0)
	_glow_clock += delta
	# one sheet lookup a frame instead of one per creature (Rattle's slow, read 150 times a frame at the new caps)
	_poison_slow = Run.player_sheet.get_stat("poison_slow", 0.0)
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var ti := type_idx[i]
		if state[i] == STATE_DYING:
			# the death plays through its frames (the fall, then the painted body), holds, and sinks away at the end
			timer[i] -= delta
			anim_t[i] += delta * _t_die_fps[ti]
			flash[i] = max(flash[i] - delta * 6.0, 0.0)
			if timer[i] < DIE_SINK:
				squash[i] = maxf(timer[i] / DIE_SINK, 0.02)
			if timer[i] <= 0.0:
				_free(i)
			continue
		if held[i] == 1:
			# in the Gravity Gun's grip: its legs go, nothing else (the gun places it)
			anim_t[i] += delta * 20.0
			flash[i] = max(flash[i] - delta * 3.0, 0.0)
			squash[i] = lerp(squash[i], 1.0, delta * 6.0)
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
		if (i & 1) == parity:
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
		elif face.length_squared() <= 0.04 and player:
			# standing still: a creature that fights at range turns to face the hero (the centipede's eight views)
			if _t_faces[ti] == 1:
				var tf := player.global_position - pos[i]
				tf.y = 0.0
				face = tf
		if _t_eight[ti] == 1:
			if face.length_squared() > 0.04:
				var cf := _cf_tick
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
				var cf := _cf_tick
				away[i] = 1 if face.dot(cf) > face.length() * 0.2 else (0 if face.dot(cf) < -face.length() * 0.2 else away[i])
		_tick_poison(i, delta)
		if alive[i] == 0:
			continue
		_tick_fire(i, delta)
		if alive[i] == 0:
			continue
		# walk cycles cut from video clips carry their own frame rate (EnemyDef.fps); the old six-frame walks run at 10
		var run_fps: float = _t_run_fps[ti]
		anim_t[i] += delta * ((run_fps if run_fps > 0.0 else 10.0) if v.length() > 0.2 else 3.0)
		# contact damage
		var d := ppos - pos[i]
		d.y = 0.0
		var reach := radius[i] + 0.45
		if d.length_squared() < reach * reach and contact_cd[i] <= 0.0 and hidden[i] == 0:
			contact_cd[i] = 0.6
			var extra := 1.0
			var cfx: Array = []
			if state[i] == STATE_CHARGE:
				extra = 1.5
				cfx.append("charge")
				# a charge that connects throws him aside (once a second, whatever else is landing)
				var kn := float((types[type_idx[i]]["def"] as EnemyDef).charge.get("knockback", 0.0))
				if kn > 0.0:
					cfx.append("knocked back")
				if kn > 0.0 and player and player.has_method("shove"):
					var away2 := ppos - pos[i]
					away2.y = 0.0
					if away2.length_squared() > 0.01:
						player.shove(away2.normalized() * kn)
			# Ram: at full momentum Buck is the wall; the creature is shoved and spiked, he is not touched
			if Run.has_perk("ram") and Run.momentum >= 0.99 and state[i] != STATE_CHARGE and i != boss_index:
				var away := pos[i] - ppos
				away.y = 0.0
				kb[i] += (away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD) * Run.perk_param("ram", "shove", 9.0)
				var th: float = Run.player_sheet.get_stat("thorns", 0.0) * Run.perk_param("ram", "thorns_mult", 3.0) + Run.perk_param("ram", "flat", 12.0)
				damage(i, th, "", away, 0.0)
				if game:
					game.fx_burst(pos[i] + Vector3(0, size[i] * 0.5, 0), Color(0.95, 0.75, 0.4), 1.0)
				continue
			player.take_damage(dmg[i] * extra, pos[i], hit_info(i, "melee", cfx))
	_update_boss(delta, ppos)
	_ticks += 1
	Perf.add("enemies.sim", t0)


## The draw runs once per shown frame, and only when a tick has moved something since the last one (pass 33.8: it ran
## inside the physics tick, so a phone below 60 fps drew the crowd twice for every frame it showed).
func _process(_delta: float) -> void:
	if player == null or _drawn == _ticks:
		return
	_drawn = _ticks
	var t0 := Time.get_ticks_usec()
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
	if frenzy_t[i] > 0.0:
		frenzy_t[i] -= dt
		spd *= 1.3
	if slow_t[i] > 0.0:
		slow_t[i] -= dt
		spd *= 1.0 - clampf(slow_f[i], 0.0, 0.9)
		# a slowed creature kicks up dust at its feet
		if game and int(slow_t[i] * 3.0) != int((slow_t[i] + dt) * 3.0):
			game.fx_burst(pos[i] + Vector3(0, 0.15, 0), Color(0.85, 0.72, 0.5), 0.45)
	if mark_t[i] > 0.0:
		mark_t[i] -= dt
		# the brand glows while the mark lasts
		flash[i] = maxf(flash[i], 0.35)
		flash_hot[i] = 1
	# Rattle: poisoned creatures drag their feet
	var pslow: float = _poison_slow
	if pslow > 0.0 and not (poison_src[i] as Dictionary).is_empty():
		spd *= 1.0 - clampf(pslow, 0.0, 0.9)
	if spin_t[i] > 0.0:
		# the twister: no walking, no biting, a slow drag towards where the sting came from
		spin_t[i] -= dt
		var tow := spin_to[i] - pos[i]
		tow.y = 0.0
		if tow.length() > 0.3:
			pos[i] += tow.normalized() * 0.6 * dt
		vel[i] = Vector3.ZERO
		if game and int(spin_t[i] * 8.0) != int((spin_t[i] + dt) * 8.0):
			game.fx_burst(pos[i] + Vector3(0, size[i] * 0.3, 0), Color(0.95, 0.85, 0.55), 0.7)
		return
	match state[i]:
		STATE_WINDUP:
			timer[i] -= dt
			desired = Vector3.ZERO
			if timer[i] <= 0.0:
				if def.brain == "artillery":
					_fire_artillery(i, def, ppos)
					state[i] = STATE_MOVE
				elif def.brain == "kite" or def.brain == "boss" or def.brain == "ambush" or def.brain == "support":
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
		STATE_ATTACK:
			desired = Vector3.ZERO
		STATE_CHARGE:
			timer[i] -= dt
			desired = charge_dir[i] * float(def.charge.get("speed", 9.0))
			if timer[i] <= 0.0:
				state[i] = STATE_MOVE
				cooldown[i] = float(def.charge.get("cooldown", 4.0))
		_:
			match def.brain:
				"kamikaze":
					# the mines blink: a slow red pulse while it walks, fast once it is winding up to go off
					# the mine's lamp: a hard red blink, on for a beat and off for a beat, not a gentle glow
					var blink: float = 1.0 if fmod(anim_t[i] * 0.6 + float(i), 2.0) < 0.85 else 0.0
					flash[i] = maxf(flash[i], blink * 0.75)
					flash_hot[i] = 1
					# a walking bomb: it runs at the hero and goes off when it gets there (a beat of warning first);
					# it keeps the swarmer's wobble so a pack still fans out instead of filing in
					var kwob := Vector3(sin(anim_t[i] * 1.7 + i), 0, cos(anim_t[i] * 1.3 + i * 0.7)) * 0.6
					desired = (dir + kwob * 0.45).normalized() * spd
					if timer[i] > 0.0:
						desired = Vector3.ZERO
						timer[i] -= dt
						flash[i] = 1.0
						flash_hot[i] = 1
						if timer[i] <= 0.0:
							_blow_up(i, def)
					elif dist < float(def.kamikaze.get("trigger", 1.1)) + size[i] * 0.4:
						timer[i] = float(def.kamikaze.get("windup", 0.35))
						if game:
							game.telegraph_ring(pos[i], float(def.kamikaze.get("radius", 2.6)), timer[i], Color(0.93, 0.29, 0.36), true)
				"chase":
					desired = dir * spd
				"flock":
					var wob := Vector3(sin(anim_t[i] * 1.7 + i), 0, cos(anim_t[i] * 1.3 + i * 0.7)) * 0.6
					desired = (dir + wob * 0.5).normalized() * spd
				"artillery":
					# far off and still: a wind-up, a rocket, and it sits and watches while the rocket hunts; the
					# moment its rocket is gone (it hit, or burnt out) it reloads and winds up again, so there is always
					# one of his in the air (pass 33.3: it used to fire once and never again). Placed at its stand-off
					# when it spawns (_stand_off).
					desired = Vector3.ZERO
					# and he is lit: a slow warm pulse, so the one thing on the far side of the screen that matters
					# is not a speck among the crowd
					flash[i] = maxf(flash[i], 0.3 + 0.22 * sin(anim_t[i] * 2.2))
					flash_hot[i] = 1
					if atk_i[i] == 2 and not (game and game.has_method("rocket_out") and game.rocket_out(i)):
						atk_i[i] = 0
						cooldown[i] = float(def.artillery.get("reload", 2.5))
					if atk_i[i] == 0 and cooldown[i] <= 0.0:
						atk_i[i] = 1
						state[i] = STATE_WINDUP
						timer[i] = float(def.artillery.get("windup", 1.4))
						charge_dir[i] = dir
						if game and game.has_method("telegraph_line"):
							game.telegraph_line(pos[i], dir, 5.0, timer[i], Color(0.93, 0.29, 0.36))
						Audio.play(str(def.sfx.get("attack", "")), pos[i])
				"kite":
					var keep := float(def.ranged.get("keep_distance", 5.0))
					var rng := float(def.ranged.get("range", 8.0))
					if tethered_i == i:
						# hauling on the rope: it braces where it stands (the hero drags it, it never walks)
						desired = Vector3.ZERO
					elif dist < keep - 0.5:
						desired = -dir * spd
					elif dist > rng:
						desired = dir * spd
					else:
						desired = Vector3.ZERO
						if cooldown[i] <= 0.0:
							state[i] = STATE_WINDUP
							timer[i] = float(def.ranged.get("telegraph", 0.6))
							_telegraph_shot(i, def, ppos, dir, dist)
				"charge":
					desired = dir * spd
					if cooldown[i] <= 0.0 and dist < float(def.charge.get("trigger_range", 6.0)):
						state[i] = STATE_WINDUP
						timer[i] = float(def.charge.get("windup", 0.8))
						charge_dir[i] = dir
						if game and game.has_method("telegraph_line"):
							game.telegraph_line(pos[i], dir, dist + 4.0, timer[i], Color(0.93, 0.29, 0.36))
				"boss":
					desired = dir * spd if atk_t[i] > 0.0 else Vector3.ZERO
				"ambush":
					# under the sand until the hero is close, then out and straight at him; a chaser after that, and
					# back under when it loses him
					var am: Dictionary = def.ambush
					if hidden[i] == 1:
						desired = Vector3.ZERO
						if game and _rng.randf() < dt * 0.6:
							game.fx_burst(pos[i] + Vector3(0, 0.1, 0), Color(0.86, 0.72, 0.5), 0.4)
						if dist < float(am.get("trigger", 5.0)):
							# up out of the sand, and straight into a silk line at the hero
							hidden[i] = 0
							state[i] = STATE_WINDUP
							timer[i] = float(def.ranged.get("telegraph", 0.45))
							if game:
								game.fx_burst(pos[i] + Vector3(0, 0.3, 0), Color(0.9, 0.75, 0.5), 1.8)
								game.hint_once("spider", "TRAPDOOR SPIDER: its silk pulls you in. Step off the red line.")
							_telegraph_shot(i, def, ppos, dir, dist)
							Audio.play(str(def.sfx.get("attack", "")), pos[i])
					else:
						desired = dir * spd
						if cooldown[i] <= 0.0 and dist > float(am.get("rehide_distance", 12.0)):
							hidden[i] = 1
							cooldown[i] = float(am.get("rehide_after", 6.0))
							if game:
								game.fx_burst(pos[i] + Vector3(0, 0.2, 0), Color(0.86, 0.72, 0.5), 1.2)
						elif cooldown[i] <= 0.0 and dist > 2.5 and dist < float(def.ranged.get("range", 9.0)):
							state[i] = STATE_WINDUP
							timer[i] = float(def.ranged.get("telegraph", 0.45))
							_telegraph_shot(i, def, ppos, dir, dist)
				"caster":
					# the ranged Elite walks to a spot keep_distance off the hero ON his portrait screen (see
					# _screen_spot), so the player can see who is casting; the tricks are its attack list, run below
					# like a boss's
					var cs: Dictionary = def.caster
					var spot := _screen_spot(i, ppos, float(cs.get("keep_distance", 7.0)), float(cs.get("side", 4.5)))
					var to_spot := spot - pos[i]
					to_spot.y = 0.0
					var sd := to_spot.length()
					desired = to_spot / sd * spd * clampf(sd / 1.5, 0.3, 1.0) if sd > 0.6 else Vector3.ZERO
				"support":
					# keeps its distance and, every few seconds, mends whatever stands around it
					var su: Dictionary = def.support
					var keep := float(su.get("keep_distance", 7.0))
					var far := float(su.get("range", 10.0))
					if dist < keep - 0.5:
						desired = -dir * spd
					elif dist > far:
						desired = dir * spd
					else:
						desired = Vector3.ZERO
					if cooldown[i] <= 0.0:
						cooldown[i] = float(su.get("interval", 4.0))
						_support_pulse(i, float(su.get("radius", 5.0)), float(su.get("heal", 0.25)), float(su.get("frenzy_seconds", 3.0)))
						Audio.play(str(def.sfx.get("attack", "")), pos[i])
				_:
					desired = dir * spd
	# separation: the creatures in this cell and the eight around it
	var sep := Vector3.ZERO
	var my_r := radius[i]
	var gx := _gcol(pos[i].x)
	var gz := _gcol(pos[i].z)
	for cx in range(maxi(gx - 1, 0), mini(gx + 2, _gw)):
		for cz in range(maxi(gz - 1, 0), mini(gz + 2, _gw)):
			var j := _g_head[cz * _gw + cx]
			while j >= 0:
				if j != i:
					var d := pos[i] - pos[j]
					d.y = 0.0
					var min_d := my_r + radius[j]
					var l2 := d.length_squared()
					if l2 < min_d * min_d and l2 > 0.0001:
						var l := sqrt(l2)
						sep += d / l * (min_d - l) / min_d
				j = _g_next[j]
	sep += _obstacle_push(i)
	var sep_w := 4.0 if state[i] != STATE_CHARGE else 0.5
	vel[i] = desired + sep * sep_w


func _do_attack(i: int, def: EnemyDef, ppos: Vector3) -> void:
	cooldown[i] = float(def.ranged.get("cooldown", 2.5))
	Audio.play(str(def.sfx.get("attack", "")), pos[i])
	if game == null:
		return
	var from := pos[i] + Vector3(0, size[i] * 0.6, 0)
	if def.ranged.has("cone_deg"):
		# a cone of pellets across the wedge, each its own short straight shot
		var n := maxi(int(def.ranged.get("count", 5)), 1)
		var cone := deg_to_rad(float(def.ranged.get("cone_deg", 50.0)))
		for k in range(n):
			var a := -cone * 0.5 + cone * (float(k) + 0.5) / float(n)
			var target := pos[i] + charge_dir[i].rotated(Vector3.UP, a) * 12.0
			game.enemy_shot_straight(from, target, float(def.ranged.get("projectile_speed", 16.0)), dmg[i], float(def.ranged.get("splash", 0.45)), {"life": float(def.ranged.get("life", 0.45)), "shot": str(def.ranged.get("shot", "")), "knockback": float(def.ranged.get("knockback", 0.0)), "info": hit_info(i, "ranged", ["buckshot"])})
		if game.has_method("fx_burst"):
			game.fx_burst(from + charge_dir[i] * 0.8, Color(1.0, 0.8, 0.4), 1.3)
		return
	if bool(def.ranged.get("straight", false)):
		# along the telegraphed line, where the hero stood when the wind-up started
		var target := pos[i] + charge_dir[i] * 12.0
		var params := {"life": float(def.ranged.get("life", 1.4)), "shot": str(def.ranged.get("shot", "")),
			"knockback": float(def.ranged.get("knockback", 0.0)), "info": hit_info(i, "ranged", [])}
		if def.ranged.has("pull"):
			params["pull"] = float(def.ranged["pull"])
		if bool(def.ranged.get("harpoon", false)):
			# a harpoon on a rope: the hit tethers the hero to whoever threw it (Game.tether_start)
			params["harpoon"] = true
			params["shooter"] = i
			params["tether"] = def.ranged.get("tether", {})
		game.enemy_shot_straight(from, target, float(def.ranged.get("projectile_speed", 12.0)), dmg[i], float(def.ranged.get("splash", 0.8)), params)
	elif game.has_method("enemy_spit"):
		game.enemy_spit(from, ppos, float(def.ranged.get("projectile_speed", 6.0)), dmg[i], float(def.ranged.get("splash", 1.2)), hit_info(i, "ranged", ["spit"]))


## The rocketeer's shot: a slow red rocket that hunts the hero and goes loose only when he dies (Game.enemy_missile).
func _fire_artillery(i: int, def: EnemyDef, ppos: Vector3) -> void:
	var ms: Dictionary = def.artillery.get("missile", {})
	if game and game.has_method("enemy_missile"):
		game.enemy_missile(i, pos[i] + Vector3(0, size[i] * 0.8, 0), float(ms.get("speed", 4.0)), float(ms.get("turn", 1.3)),
			float(ms.get("damage", 22.0)) * stage_mult * level_dmg_mult, float(ms.get("area", 1.6)),
			float(ms.get("speed_of_hero", 0.0)), hit_info(i, "ranged", ["rocket"]), ms)
	atk_i[i] = 2
	Audio.play(str(def.sfx.get("attack", "")), pos[i])


## An artillery creature spawns at its stand-off from the hero, never closer, inside the wall.
func _stand_off(i: int, def: EnemyDef) -> void:
	if player == null:
		return
	var so := float(def.artillery.get("stand_off", 28.0))
	var pp: Vector3 = player.global_position
	var d := pos[i] - pp
	d.y = 0.0
	if d.length_squared() < 0.01:
		d = Vector3.FORWARD
	if d.length() < so:
		var np: Vector3 = pp + d.normalized() * so
		if game and game.map and game.map.has_method("clamp_to_arena"):
			np = game.map.clamp_to_arena(np)
		pos[i] = Vector3(np.x, _height(np.x, np.z), np.z)
	atk_i[i] = 0
	cooldown[i] = 0.6


## A walking bomb goes off: the blast (Game.elite_explosion also hurts the crowd), then it dies without its death burst
## firing a second time.
func _blow_up(i: int, def: EnemyDef) -> void:
	var km: Dictionary = def.kamikaze
	if game and game.has_method("elite_explosion"):
		game.elite_explosion(pos[i], float(km.get("radius", 2.6)), float(km.get("damage", 26.0)) * stage_mult * level_dmg_mult,
			0.0, float(km.get("knockback", 9.0)), 0.2, hit_info(i, "melee", ["mine"]))
	blown[i] = 1
	_die(i, "")


## A shaman's mend: every creature within `r` of it (not itself, never a boss) heals `frac` of its max HP and flashes.
func _support_pulse(i: int, r: float, frac: float, frenzy_seconds: float) -> void:
	var n := 0
	for j in indices_in_radius(pos[i], r):
		if j == i or j == boss_index:
			continue
		hp[j] = minf(hp[j] + max_hp[j] * frac, max_hp[j])
		frenzy_t[j] = frenzy_seconds
		flash[j] = 0.7
		flash_green[j] = 1
		n += 1
		if game:
			game.fx_burst(pos[j] + Vector3(0, size[j] * 0.7, 0), Color(0.5, 1.0, 0.55), 0.7)
	if game:
		game.telegraph_ring(pos[i], r, 0.6, Color(0.45, 0.9, 0.55), true)
		game.fx_burst(pos[i] + Vector3(0, size[i] * 0.9, 0), Color(0.5, 1.0, 0.6), 1.6)
		if n > 0:
			game.hint_once("shaman", "DUST SHAMAN: it mends and drives its pack (green ring). Kill it first.")


## The wind-up mark for a ranged creature: a red line along a straight shot, a red ring where a lob will land.
func _telegraph_shot(i: int, def: EnemyDef, ppos: Vector3, dir: Vector3, dist: float) -> void:
	if game == null:
		return
	if def.ranged.has("cone_deg"):
		# the dwarf's wedge: everything inside it is about to be peppered
		charge_dir[i] = dir
		game.telegraph_sector(pos[i], dir, float(def.ranged.get("range", 5.0)) + 1.5, float(def.ranged.get("cone_deg", 50.0)), timer[i], Color(0.93, 0.29, 0.36))
	elif bool(def.ranged.get("straight", false)):
		var aim := dir
		if bool(def.ranged.get("lead", false)) and player:
			# the harpooner leads its throw: where the hero will be when the harpoon gets there, at his current pace
			var v: Vector3 = player.velocity
			v.y = 0.0
			var flight: float = (dist + 1.0) / maxf(float(def.ranged.get("projectile_speed", 12.0)), 1.0) + timer[i] * 0.5
			var at := ppos + v * flight
			var to := at - pos[i]
			to.y = 0.0
			if to.length_squared() > 0.01:
				aim = to.normalized()
		charge_dir[i] = aim
		game.telegraph_line(pos[i], aim, minf(dist + 4.0, float(def.ranged.get("range", 9.0)) + 4.0), timer[i], Color(0.93, 0.29, 0.36))
	else:
		game.telegraph_ring(ppos, float(def.ranged.get("splash", 1.2)), timer[i], Color(0.93, 0.29, 0.36))


## The Djinn's rain: every `interval` a strike is placed (the first on the hero, the rest scattered around where he
## is right then) with a red ring, and lands `warn` later: damage in the ring, a bolt and a burst.
func _tick_rains(delta: float, ppos: Vector3) -> void:
	if _rains.is_empty():
		return
	var keep: Array = []
	for r in _rains:
		r["next"] -= delta
		if r["next"] <= 0.0 and int(r["left"]) > 0:
			r["next"] = float(r["interval"])
			r["left"] = int(r["left"]) - 1
			var at := ppos
			if not bool(r["first"]):
				var sp: float = float(r["spread"])
				at = ppos + Vector3(randf_range(-sp, sp), 0, randf_range(-sp, sp))
			r["first"] = false
			at.y = _height(at.x, at.z)
			if game:
				game.telegraph_ring(at, float(r["radius"]), float(r["warn"]), Color(0.93, 0.29, 0.36))
				if bool(r.get("pillar", false)) and game.has_method("light_pillar"):
					game.light_pillar(at, float(r["radius"]), float(r["warn"]))
				elif game.has_method("erupt_mound"):
					game.erupt_mound(at, float(r["radius"]), float(r["warn"]))
			(r["strikes"] as Array).append({"at": at, "t": float(r["warn"])})
		var left_strikes: Array = []
		for s in r["strikes"]:
			s["t"] = float(s["t"]) - delta
			if float(s["t"]) > 0.0:
				left_strikes.append(s)
				continue
			var at: Vector3 = s["at"]
			var d := ppos - at
			d.y = 0.0
			if player and not player.dead and d.length() <= float(r["radius"]) + 0.35:
				var rinfo: Dictionary = (r.get("info", {}) as Dictionary).duplicate(true)
				if float(r.get("knockback", 0.0)) > 0.0:
					(rinfo.get("fx", []) as Array).append("knocked back")
				player.take_damage(float(r["damage"]), at, rinfo)
				if float(r.get("knockback", 0.0)) > 0.0 and player.has_method("shove") and d.length_squared() > 0.01:
					player.shove(d.normalized() * float(r.get("knockback", 0.0)))
			var sp_id: String = str(r.get("spawn", ""))
			if sp_id != "":
				# the sand bursts and something comes up through it, thrown a little towards the hero
				var j := spawn(sp_id, at)
				if j >= 0:
					var tow := ppos - at
					tow.y = 0.0
					kb[j] = (tow.normalized() if tow.length_squared() > 0.01 else Vector3.ZERO) * 3.0
					state[j] = STATE_MOVE
				if game:
					# sand thrown up where it breaks the surface (a burst that size was a pale cloud over the whole ring)
					game.fx_sand(at + Vector3(0, 0.2, 0), float(r["radius"]) * 0.9)
					if game.has_method("shockwave"):
						game.shockwave(at, float(r["radius"]))
					Audio.play("en_boss_attack", at)
			elif bool(r.get("pillar", false)) and game:
				# the Sun Idol's column lands: a flash of gold and a shock, no sand
				game.fx_burst(at + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.35), float(r["radius"]) * 1.6)
				if game.has_method("shockwave"):
					game.shockwave(at, float(r["radius"]))
				Audio.play("en_boss_attack", at)
			elif game:
				var jit := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
				game.fx_lightning([at + Vector3(0, 11.0, 0) + jit * 2.0, at + Vector3(0, 6.0, 0) + jit, at + Vector3(0, 0.2, 0)])
				game.fx_burst(at + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.45), float(r["radius"]) * 1.1)
				if game.has_method("shockwave"):
					game.shockwave(at, float(r["radius"]))
				Audio.play("en_boss_attack", at)
		r["strikes"] = left_strikes
		if int(r["left"]) > 0 or not left_strikes.is_empty():
			keep.append(r)
	_rains = keep


func _update_boss(delta: float, ppos: Vector3) -> void:
	_tick_rains(delta, ppos)
	if boss_index >= 0:
		_update_attacks(boss_index, delta, ppos)
	for i in range(MAX):
		if alive[i] == 1 and i != boss_index:
			var adef: EnemyDef = types[type_idx[i]]["def"]
			# casters live by their script; any other Elite with one runs it between whatever its brain does. The script
			# owns STATE_ATTACK, so it keeps running through the attack it started (pass 33.6: it only ran in STATE_MOVE,
			# so an attack never finished: the Dune Scorpion went under the sand for its burrow and never came up)
			if adef.brain == "caster" or (adef.archetype == "elite" and not (adef.boss.get("attacks", []) as Array).is_empty()):
				if state[i] == STATE_MOVE or state[i] == STATE_ATTACK or adef.brain == "caster":
					_update_attacks(i, delta, ppos)
				# and whatever happens, a scripted creature is never left buried outside its own attack
				if hidden[i] == 1 and state[i] != STATE_ATTACK and adef.brain != "ambush":
					hidden[i] = 0


## The attack runner: a creature with a `boss.attacks` list (the bosses, the casters) cycles through them, each with a
## wind-up and a telegraph, then the effect. State lives per creature, so a caster and the boss can run at once.
func _update_attacks(i: int, delta: float, ppos: Vector3) -> void:
	if alive[i] == 0 or state[i] == STATE_DYING:
		return
	var def: EnemyDef = types[type_idx[i]]["def"]
	var attacks: Array = def.boss.get("attacks", [])
	if attacks.is_empty():
		return
	if state[i] == STATE_MOVE:
		if hold_t[i] > 0.0:
			# standing and casting (the rain falls): no walking, nothing new
			hold_t[i] -= delta
			vel[i] = Vector3.ZERO
			return
		atk_t[i] -= delta
		if atk_t[i] <= 0.0:
			# a caster saves its script for when the hero can see it: nothing new starts from past `attack_range`
			if def.brain == "caster" and def.caster.has("attack_range"):
				var reach := ppos - pos[i]
				reach.y = 0.0
				if reach.length() > float(def.caster["attack_range"]):
					atk_t[i] = 0.25
					return
			var atk: Dictionary = attacks[atk_i[i] % attacks.size()]
			# an attack with a minimum range is skipped while the hero is inside it (the rain never falls on his head)
			var tries := 0
			while atk.has("min_range") and (ppos - pos[i]).length() < float(atk["min_range"]) and tries < attacks.size():
				atk_i[i] += 1
				atk = attacks[atk_i[i] % attacks.size()]
				tries += 1
			atk_i[i] += 1
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
				"ring_at_hero":
					atk_target[i] = ppos
					if game: game.telegraph_ring(ppos, float(atk.get("radius", 5.0)), timer[i], Color(0.93, 0.29, 0.36))
				"fan":
					if game:
						var fn := int(atk.get("count", 7))
						var fspread := deg_to_rad(float(atk.get("spread_deg", 90.0)))
						for k in range(fn):
							game.telegraph_line(pos[i], dir.rotated(Vector3.UP, -fspread * 0.5 + fspread * float(k) / float(maxi(fn - 1, 1))), 14.0, timer[i], Color(0.93, 0.29, 0.36))
			if str(atk.get("name", "")) == "burrow":
				# under the sand for the wind-up; the ring on the hero says where it comes up
				hidden[i] = 1
				if game: game.fx_burst(pos[i] + Vector3(0, 0.5, 0), Color(0.85, 0.7, 0.5), 4.0)
			Audio.play(str(def.sfx.get("attack", "en_boss_attack")), pos[i])
	elif state[i] == STATE_ATTACK:
		timer[i] -= delta
		vel[i] = Vector3.ZERO
		if timer[i] <= 0.0:
			var atk: Dictionary = attacks[(atk_i[i] - 1) % attacks.size()]
			match str(atk.get("name", "")):
				"roll":
					state[i] = STATE_CHARGE
					timer[i] = float(atk.get("duration", 1.2))
					dmg[i] = float(atk.get("damage", 25)) * stage_mult
				"spawn_ring":
					spawn_ring(str(atk.get("enemy", "coyote")), int(atk.get("count", 10)), pos[i], 5.0)
					state[i] = STATE_MOVE
				"slam_at":
					# a rock on the marked spot: damage there, the caster stays where it is
					var rs := float(atk.get("radius", 2.6))
					var ds := ppos - atk_target[i]
					ds.y = 0.0
					if ds.length() <= rs + 0.4:
						player.take_damage(float(atk.get("damage", 18)) * stage_mult, atk_target[i], hit_info(i, "ranged", ["rock slam", "knocked back"]))
						if player.has_method("shove") and ds.length_squared() > 0.01:
							player.shove(ds.normalized() * float(atk.get("knockback", 6.0)))
					if game:
						if game.has_method("shockwave"):
							game.shockwave(atk_target[i], rs)
						game.fx_burst(atk_target[i] + Vector3(0, 0.4, 0), Color(0.85, 0.7, 0.5), 3.0)
					state[i] = STATE_MOVE
				"blink":
					var dest: Vector3
					if str(atk.get("to", "")) == "screen":
						# a fresh spot on the hero's screen, across from where it stood: the ranged Elite repositions,
						# it never blinks off the screen (it used to jump 8 m further off every cycle)
						var bf := _camera_forward()
						var br := Vector3(-bf.z, 0, bf.x)
						var bkeep := float(def.caster.get("keep_distance", 7.0))
						var bside := float(def.caster.get("side", 4.5))
						var across := (pos[i] - ppos).dot(br)
						var sgn: float = -signf(across) if absf(across) > 1.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
						dest = ppos + bf * bkeep * _rng.randf_range(0.85, 1.05) + br * sgn * _rng.randf_range(1.5, bside)
					else:
						# away from the hero in a puff of sand, inside the arena
						var away := pos[i] - ppos
						away.y = 0.0
						if away.length_squared() < 0.01:
							away = Vector3.FORWARD
						dest = pos[i] + away.normalized() * float(atk.get("distance", 8.0))
					var lim: float = (game.map.arena_radius - 3.0) if game and game.map else 60.0
					if Vector2(dest.x, dest.z).length() > lim:
						var flat := Vector2(dest.x, dest.z).normalized() * lim
						dest = Vector3(flat.x, dest.y, flat.y)
					dest.y = _height(dest.x, dest.z)
					if game:
						game.fx_burst(pos[i] + Vector3(0, size[i] * 0.5, 0), Color(0.9, 0.78, 0.55), 2.2)
					pos[i] = dest
					if game:
						game.fx_burst(pos[i] + Vector3(0, size[i] * 0.5, 0), Color(0.9, 0.78, 0.55), 2.2)
					state[i] = STATE_MOVE
				"burrow":
					hidden[i] = 0
					pos[i] = atk_target[i]
					var rb := float(atk.get("radius", 5.0))
					var db := ppos - pos[i]
					db.y = 0.0
					if db.length() <= rb + 0.5:
						player.take_damage(float(atk.get("damage", 28)) * stage_mult, pos[i], hit_info(i, "melee", ["burst up from the sand", "knocked back"]))
						if player.has_method("shove"):
							player.shove(db.normalized() * float(atk.get("knockback", 8.0)))
					if game:
						if game.has_method("shockwave"):
							game.shockwave(pos[i], rb)
						game.fx_burst(pos[i] + Vector3(0, 0.5, 0), Color(0.85, 0.7, 0.5), 5.0)
					state[i] = STATE_MOVE
				"rain", "erupt":
					# a sequence of small strikes around the hero, each a red ring first: a dodge that lasts a few seconds;
					# "erupt" also brings a creature up through the sand at every ring (the Dune Centipede's young)
					_rains.append({"left": int(atk.get("count", 10)), "next": 0.0, "interval": float(atk.get("interval", 0.3)),
						"spread": float(atk.get("spread", 5.0)), "radius": float(atk.get("radius", 1.6)), "damage": float(atk.get("damage", 14)) * stage_mult,
						"warn": float(atk.get("warn", 0.55)), "strikes": [], "first": true, "spawn": str(atk.get("spawn", "")),
						"pillar": bool(atk.get("pillar", false)), "knockback": float(atk.get("knockback", 0.0)),
						"info": hit_info(i, "ranged", ["pillar of light" if bool(atk.get("pillar", false)) else "eruption"])})
					hold_t[i] = float(atk.get("count", 10)) * float(atk.get("interval", 0.3)) + float(atk.get("warn", 0.55)) + 0.3
					state[i] = STATE_MOVE
				"spit_volley":
					var vn := int(atk.get("count", 7))
					var vspread := deg_to_rad(float(atk.get("spread_deg", 90.0)))
					for k in range(vn):
						var va := -vspread * 0.5 + vspread * float(k) / float(maxi(vn - 1, 1))
						var target: Vector3 = pos[i] + charge_dir[i].rotated(Vector3.UP, va) * 12.0
						var vfrom: Vector3 = pos[i] + Vector3(0, size[i] * 0.6, 0)
						if bool(atk.get("straight", false)) and game and game.has_method("enemy_shot_straight"):
							# the fan on the ground is a set of lines: the shots fly down them, not over them
							game.enemy_shot_straight(vfrom, target, float(atk.get("speed", 14.0)), float(atk.get("damage", 12)) * stage_mult * level_dmg_mult,
								float(atk.get("splash", 0.5)), {"life": float(atk.get("life", 1.0)), "shot": str(atk.get("shot", "")),
								"knockback": float(atk.get("knockback", 0.0)), "info": hit_info(i, "ranged", [str(atk.get("shot", "volley"))])})
						elif game and game.has_method("enemy_spit"):
							game.enemy_spit(vfrom, target, float(atk.get("speed", 7.0)), float(atk.get("damage", 12)) * stage_mult, float(atk.get("splash", 1.4)), hit_info(i, "ranged", ["volley"]))
					state[i] = STATE_MOVE
				"slam":
					var r := float(atk.get("radius", 6.0))
					var d := ppos - pos[i]
					d.y = 0.0
					if d.length() <= r + 0.5:
						player.take_damage(float(atk.get("damage", 30)) * stage_mult, pos[i], hit_info(i, "melee", ["slam", "knocked back"]))
						if player.has_method("apply_knockback"):
							player.apply_knockback(d.normalized() * float(atk.get("knockback", 6.0)))
					if game and game.has_method("shockwave"):
						game.shockwave(pos[i], r)
					state[i] = STATE_MOVE
				_:
					state[i] = STATE_MOVE
			atk_t[i] = float(def.boss.get("cooldown_between", 2.0))
	elif state[i] == STATE_CHARGE and str(def.brain) == "boss":
		timer[i] -= delta
		vel[i] = charge_dir[i] * float(attacks[(atk_i[i] - 1) % attacks.size()].get("speed", 12.0))
		if timer[i] <= 0.0:
			state[i] = STATE_MOVE
			dmg[i] = def.damage * stage_mult
			atk_t[i] = float(def.boss.get("cooldown_between", 2.0))


## Warm-up: every type draws one instance at `at` (Vector3.INF stops it) so its shader variants compile behind the
## starter pick. The render loop keeps that extra instance while the warm-up is on.
var _warm_at := Vector3.INF


func warm_draw(at: Vector3) -> void:
	_warm_at = at
	if at != Vector3.INF:
		for kind in ["crown", "skull", "gear"]:
			_badge_mm(kind)
	for t in types:
		var mm: MultiMesh = t["mm"]
		if at == Vector3.INF:
			mm.visible_instance_count = 0
		else:
			mm.set_instance_transform(0, Transform3D(Basis(), at))
			mm.set_instance_custom_data(0, Color(0, 0, 0.5, 1))
			mm.set_instance_color(0, Color(1, 1, 1, 0))
			mm.visible_instance_count = 1


# ---------------------------------------------------------------- badges

## Badges (pass 33.3): a crown floats over the two Elites (and nothing else), a skull over a boss, a gear over the specials (the harpooner,
## the rocketeer; their JSON `badge`). One MultiMesh per badge drawn by core/shaders/badge.gdshader, built the first
## time a creature wears it; `BADGE_SIZE` metres at the base zoom, growing a little as the camera pulls out.
const BADGE_SIZE := 0.72
const BADGE_MAX := 24
var _badges: Dictionary = {}   # badge -> MultiMesh (null when its painting is missing)
var _badge_scale := 1.0
var _badge_shader: Shader = preload("res://core/shaders/badge.gdshader")


func _badge_mm(kind: String) -> MultiMesh:
	if _badges.has(kind):
		return _badges[kind]
	var mm: MultiMesh = null
	var path := "res://art/ui/badges/%s.png" % kind
	if ResourceLoader.exists(path):
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		mm.mesh = quad
		mm.instance_count = BADGE_MAX
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Badge_" + kind
		var mat := ShaderMaterial.new()
		mat.shader = _badge_shader
		mat.set_shader_parameter("tex", load(path))
		mat.render_priority = 10
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		add_child(mmi)
	_badges[kind] = mm
	return mm


## The badge a creature wears right now ("" for none): its type's (an elite modifier never adds one).
func badge_of(i: int) -> String:
	if i < 0 or i >= MAX or alive[i] == 0:
		return ""
	return str(types[type_idx[i]]["badge"])


var _mark := -1.0
## Far zoom (pass 33.2): past twice the camera's base distance every creature gets a thicker dark-red rim and a faint
## warm tint, fading in to full by 2.4x, so a crowd of specks stays readable around a small hero.
func _update_mark() -> void:
	var z: float = game.camera.zoom() if game and game.get("camera") and game.camera and game.camera.has_method("zoom") else 1.0
	# the badges grow a little as the camera pulls out, so a crown stays a crown when the crowd is specks
	_badge_scale = pow(maxf(z, 1.0), 0.6)
	var m: float = snappedf(clampf((z - 2.0) / 0.4, 0.0, 1.0), 0.05)
	if m == _mark:
		return
	_mark = m
	for t in types:
		(t["mat"] as ShaderMaterial).set_shader_parameter("mark", m)


## Which of the 13 strips (ANIM_NAMES) creature `i` of type `t` shows right now: the same choice as ever, read from the
## type's frame table (pass 33.8: the strip's name was built and looked up as a string, and frame_offset walked the
## list of strips, for every creature every tick).
func _strip_of(i: int, t: int) -> int:
	var st := state[i]
	var a := A_RUN
	if st == STATE_DYING:
		a = A_DIE
	elif st == STATE_WINDUP or st == STATE_ATTACK:
		a = A_ATTACK
	elif st == STATE_SPAWN:
		a = A_IDLE
	elif vel[i].length_squared() < 0.04:
		a = A_IDLE
	if held[i] == 1 and st != STATE_DYING:
		# kicking its legs in the air
		a = A_RUN
	if i == tethered_i and tether_drag_t > 0.0 and st != STATE_DYING:
		# dragged on the rope: it digs in with the frames it shows before a throw
		a = A_ATTACK
	if flash[i] > 0.6 and _t_hit_ok[t] == 1 and st != STATE_DYING:
		a = A_HIT
	if _t_eight[t] == 1:
		# eight-direction creatures: chargers keep their directional run while charging and hold the idle set while winding up
		if st == STATE_CHARGE:
			a = A_RUN
		elif st == STATE_WINDUP and _t_charge[t] == 1:
			a = A_IDLE
		if a == A_RUN or a == A_IDLE:
			var cand: int = VIEW_ANIM[a][view[i]]
			if _t_ok[t * N_ANIMS + cand] == 1:
				return cand
		return a
	if away[i] == 1 and (a == A_RUN or a == A_IDLE) and _t_okb[t * 2 + a] == 1:
		return 5 if a == A_RUN else 6
	return a


## The first frame of strip `strip` in type `t`'s sheet, and how many frames it has.
func strip_frames(t: int, strip: int) -> Vector2i:
	return Vector2i(_t_off[t * N_ANIMS + strip], _t_cnt[t * N_ANIMS + strip])


func _render() -> void:
	_update_mark()
	# compact instances per type
	var counters := PackedInt32Array()
	counters.resize(types.size())
	var shadow_n := 0
	# with a big crowd only the creatures around the hero cast a shadow: the far ones are a metre of dark quad each
	# and they overlap into a wall of blending on a phone
	var shadow_all: bool = count_alive <= SHADOW_BUDGET
	var shadow_r2 := 100.0
	var badge_n: Dictionary = {}
	var ppos2: Vector3 = player.global_position if player else Vector3.ZERO
	var cam_x := 0.0
	for i in range(MAX):
		if alive[i] == 0 or hidden[i] == 1:
			continue
		var t := type_idx[i]
		var mm: MultiMesh = _t_mm[t]
		var k := counters[t]
		var s := size[i]
		var xf := Transform3D(Basis().scaled(Vector3(s, s, s)), pos[i] + Vector3(0, lift_h[i], 0))
		mm.set_instance_transform(k, xf)
		var st := state[i]
		var strip := _strip_of(i, t)
		var n := _t_cnt[t * N_ANIMS + strip]
		var frame := _t_off[t * N_ANIMS + strip] + (mini(int(anim_t[i]), n - 1) if strip == A_DIE else (int(anim_t[i]) % maxi(n, 1)))
		var sq := squash[i]
		# procedural bob while moving
		if strip == A_RUN:
			sq += sin(anim_t[i] * 1.5) * 0.05
		# the flash: white, green for a poison tick (negative), orange for a fire tick (2 + flash)
		var fl: float = flash[i]
		if i == bounty_i and fl < 0.4:
			# the bounty: a strong warm pulse, brighter than the rocketeer's, so it stands out of a crowd
			fl = 0.4 + 0.25 * sin(_glow_clock * 3.0)
			flash_hot[i] = 1
		if flash_green[i] == 1:
			fl = -fl
		elif flash_hot[i] == 1:
			fl = 2.0 + fl
		var fy := float(flip[i])
		if i == tethered_i and st != STATE_DYING:
			# the red outline of the creature holding the rope (levels 0..16 on top of the flip bit)
			fy += 2.0 * roundf(tether_glow() * 16.0)
		mm.set_instance_custom_data(k, Color(float(frame), fy, fl, sq))
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
		# the badge over its head: from the feet up the screen past the top of the figure, then half the badge
		var bk: String = _t_badge[t]
		if bk != "" and st != STATE_DYING:
			var bmm := _badge_mm(bk)
			if bmm:
				var bn: int = int(badge_n.get(bk, 0))
				if bn < BADGE_MAX:
					var td: Dictionary = types[t]
					var def: EnemyDef = td["def"]
					var bs: float = BADGE_SIZE * _badge_scale * (1.3 if i == boss_index or def.archetype == "boss" else 1.0)
					bmm.set_instance_transform(bn, Transform3D(Basis(), pos[i] + Vector3(0, lift_h[i], 0)))
					bmm.set_instance_custom_data(bn, Color(s * float(td["head"]) * maxf(sq, 0.2) + 0.12 + bs * 0.5, bs, float(i) * 1.7, 0.0))
					badge_n[bk] = bn + 1
		# shadow (stays on the ground and shrinks while the creature is in the air)
		if shadow_all or shadow_n < SHADOW_BUDGET:
			var d2: float = pos[i].distance_squared_to(ppos2)
			if shadow_all or d2 < shadow_r2:
				var shs: float = s / (1.0 + lift_h[i] * 0.5)
				var sh := Transform3D(Basis().scaled(Vector3(shs * 0.55, 1, shs * 0.34)), pos[i] + Vector3(0, 0.03, 0))
				_shadow_mm.set_instance_transform(shadow_n, sh)
				shadow_n += 1
	for t in range(types.size()):
		if _warm_at != Vector3.INF:
			var mm: MultiMesh = types[t]["mm"]
			mm.set_instance_transform(counters[t], Transform3D(Basis(), _warm_at))
			mm.set_instance_custom_data(counters[t], Color(0, 0, 0.5, 1))
			mm.set_instance_color(counters[t], Color(1, 1, 1, 0))
			counters[t] += 1
		types[t]["mm"].visible_instance_count = counters[t]
	_shadow_mm.visible_instance_count = shadow_n
	for bk in _badges.keys():
		var bmm2: MultiMesh = _badges[bk]
		if bmm2:
			var bn2: int = int(badge_n.get(bk, 0))
			if _warm_at != Vector3.INF and bn2 < BADGE_MAX:
				bmm2.set_instance_transform(bn2, Transform3D(Basis(), _warm_at))
				bmm2.set_instance_custom_data(bn2, Color(1.0, 0.3, 0.0, 0.0))
				bn2 += 1
			bmm2.visible_instance_count = bn2
