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
var homing := PackedByteArray()   # missiles: steered by _fly_missile, explode on contact (see launch_missile)
var ret := PackedByteArray()      # the boomerang: 0 plain, 1 on its way out, 2 coming back to the hero
var stuck := PackedInt32Array()   # the sticky grenade: the creature it rides, -1 for none
var stuck_t := PackedFloat32Array()
var psize := PackedFloat32Array()
## the rocketeers' rockets: projectile index -> creature index; a rocket lives while its goblin does (Game asks)
var rocket_of: Dictionary = {}
## diagnostics: missiles launched per weapon id (the smoke run prints it)
var missiles_by_weapon: Dictionary = {}   # a shot's own size against its kind's (params.size_mult): a slug is big, a swarm's hornets small
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
var trail_col := PackedColorArray()   # per dot: spit is green, rocket smoke warm, hornets gold
var trail_size := PackedFloat32Array()   # per dot: rocket smoke puffs are bigger than a spit trail's beads
var trail_next := 0
var trail_count := 0
var _trail_t := PackedFloat32Array()   # per projectile: seconds until its next trail dot
var _trail_mm: MultiMesh
## The rocketeer's rockets draw a faint smoke line all the way back to where they were fired (pass 33), so the hero can
## follow one home to the goblin: the points a rocket has passed, a camera-facing ribbon through them, faded out over a
## second once the rocket is gone. {"pts": PackedVector3Array, "proj": index or -1 once gone, "fade": 1..0}
var _paths: Array = []
var _path_mesh: ImmediateMesh
var _path_drawn := false
## the draw waits for a new physics tick and runs once per shown frame (pass 33.8): ticks run, the last one drawn, and
## the simulated time the trails have to age by
var _ticks := 0
var _drawn := -1
var _draw_dt := 0.0
const PATH_STEP := 0.6
const PATH_MAX := 360
const PATH_WIDTH := 0.22
const PATH_COLOR := Color(1.0, 0.86, 0.8, 0.5)


## The Golden Revolver's lines of energy (pass 35): shots of a weapon with params.trace leave one behind.
var traces: EnergyTraces
## Where bombs just came down (pass 36): {at, t} for LANDED_CLAIM seconds, so the next bomb picks another crowd.
var _landed: Array = []
const LANDED_CLAIM := 2.0


func _ready() -> void:
	traces = EnergyTraces.new()
	add_child(traces)
	pos.resize(MAX); vel.resize(MAX); life.resize(MAX); dmg.resize(MAX); pierce.resize(MAX); kind.resize(MAX)
	radius.resize(MAX); kb.resize(MAX); area.resize(MAX); hostile.resize(MAX); arc.resize(MAX); homing.resize(MAX); alive.resize(MAX); spin.resize(MAX); hover.resize(MAX)
	ret.resize(MAX); stuck.resize(MAX); stuck_t.resize(MAX); psize.resize(MAX)
	for k in range(MAX):
		stuck[k] = -1
		psize[k] = 1.0
	weapon.resize(MAX); memo.resize(MAX); extra.resize(MAX); _trail_t.resize(MAX)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	trail_pos.resize(TRAIL_MAX)
	trail_age.resize(TRAIL_MAX); trail_col.resize(TRAIL_MAX); trail_size.resize(TRAIL_MAX)
	for k in range(TRAIL_MAX):
		trail_age[k] = TRAIL_LIFE
	_build_trail()
	_path_mesh = ImmediateMesh.new()
	var pmi := MeshInstance3D.new()
	pmi.mesh = _path_mesh
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.vertex_color_use_as_albedo = true
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pmi.material_override = pm
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(pmi)


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


func _drop_trail(at: Vector3, col: Color = Color(0.62, 0.95, 0.5, 0.45), size_mult: float = 1.0) -> void:
	# a screen full of shots drops every other bead: the line still reads, the fill rate halves
	if count > 60 and (trail_next & 1) == 0:
		trail_next = (trail_next + 1) % TRAIL_MAX
		return
	trail_pos[trail_next] = at
	trail_age[trail_next] = 0.0
	trail_col[trail_next] = col
	trail_size[trail_next] = size_mult
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
	hostile[i] = 0; arc[i] = 0; alive[i] = 1; spin[i] = randf() * TAU; homing[i] = 0
	ret[i] = 1 if (w and bool(w.params.get("return", false))) else 0
	stuck[i] = -1
	psize[i] = float(w.params.get("size_mult", 1.0)) if w else 1.0
	# a straight shot follows the ground at the height it left the muzzle, so dunes never swallow it or leave it floating
	var g0: float = game.map.height_at(from.x, from.z) if game and game.map else 0.0
	hover[i] = clampf(from.y - g0, 0.35, 1.3)
	weapon[i] = w; memo[i] = {}; extra[i] = {}
	if w and w.params.has("trace"):
		traces.game = game
		extra[i]["trace"] = traces.start(from, w, damage)
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
	# its own copy (a caller may hand in a weapon's params), with where it will come down, for the other throwers
	extra[i] = params.duplicate()
	extra[i]["target"] = target
	lobs_fired += 1
	return i


func hostile_shot(p_kind: int, from: Vector3, velocity: Vector3, damage: float, splash: float, p_life: float = 4.0, arcing := false, params: Dictionary = {}) -> int:
	var i := fire(p_kind, from, velocity, damage, 0, 0.35, p_life, null, 0.0)
	if i >= 0:
		hostile[i] = 1
		arc[i] = 1 if arcing else 0
		area[i] = splash
		extra[i] = params
		_trail_t[i] = 0.0
	return i


func _free(i: int) -> void:
	homing[i] = 0
	if alive[i] == 0:
		return
	# a rocket's smoke line stays behind and fades once the rocket is gone
	if extra[i] is Dictionary and (extra[i] as Dictionary).has("path"):
		extra[i]["path"]["proj"] = -1
	# a Golden Revolver shot's line stays in the air where the shot went
	if extra[i] is Dictionary and (extra[i] as Dictionary).has("trace"):
		traces.seal(extra[i]["trace"])
		(extra[i] as Dictionary).erase("trace")
	if rocket_of.has(i):
		rocket_of.erase(i)
	alive[i] = 0
	weapon[i] = null
	memo[i] = {}
	free_list.append(i)
	count -= 1


func clear_all() -> void:
	for i in range(MAX):
		_free(i)
	traces.clear()
	_landed.clear()


## The spots bombs are headed for or came down on in the last LANDED_CLAIM seconds (pass 36): a bomb thrower picks a
## crowd away from these, so the Molotov, the Skull Rain and the Grenade do not all land on one spot. Bomblets and the
## creatures' own lobs do not count.
func claimed_spots() -> Array:
	var out: Array = []
	for i in range(MAX):
		if alive[i] == 1 and arc[i] == 1 and hostile[i] == 0 and extra[i] is Dictionary:
			var ex: Dictionary = extra[i]
			if ex.has("target") and not ex.has("is_bomblet"):
				out.append(ex["target"])
	for s: Dictionary in _landed:
		out.append(s["at"])
	return out


func _physics_process(delta: float) -> void:
	if game == null:
		return
	var t0 := Time.get_ticks_usec()
	var enemies: EnemyManager = game.enemies
	var player: Node3D = game.player
	var map = game.map
	# a creature's shot keeps the creatures' clock (High Noon slows them in the air too)
	var hostile_dt: float = delta * (enemies.time_scale if enemies else 1.0)
	for k in range(_landed.size() - 1, -1, -1):
		_landed[k]["t"] = float(_landed[k]["t"]) - delta
		if float(_landed[k]["t"]) <= 0.0:
			_landed.remove_at(k)
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var dt: float = hostile_dt if hostile[i] == 1 else delta
		life[i] -= dt
		if stuck[i] >= 0:
			# the sticky grenade rides its creature, then blows where it got to
			var e := stuck[i]
			stuck_t[i] -= delta
			if enemies.alive[e] == 1 and enemies.state[e] != enemies.STATE_DYING:
				pos[i] = enemies.pos[e] + Vector3(0, enemies.size[e] * 0.7, 0)
			if stuck_t[i] <= 0.0 or enemies.alive[e] == 0 or enemies.state[e] == enemies.STATE_DYING:
				_explode(i)
				_free(i)
			continue
		if homing[i] == 1:
			if life[i] <= 0.0:
				_explode(i)
				_free(i)
			else:
				_fly_missile(i, dt, enemies, map)
			continue
		if arc[i] == 1:
			vel[i].y -= 24.0 * dt
		if ret[i] == 2 and player:
			# coming home: steered at the hero, gone when it reaches him
			var home := player.global_position + Vector3(0, hover[i], 0) - pos[i]
			home.y = 0.0
			if home.length() < 0.9:
				_free(i)
				continue
			vel[i] = home.normalized() * maxf(vel[i].length(), 6.0)
		pos[i] += vel[i] * dt
		# a creature's shot holds its line; only the hero's own shots tumble (saws, boomerangs, grenades)
		if hostile[i] == 0:
			spin[i] += delta * 12.0
		if life[i] <= 0.0:
			if ret[i] == 1:
				# the boomerang turns at the end of its run: fresh pierce, fresh memory, twice the damage on the way back
				ret[i] = 2
				life[i] = 6.0
				pierce[i] = 80
				memo[i] = {}
				continue
			_burst_spawn(i)
			_free(i)
			continue
		var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
		if arc[i] == 0:
			pos[i].y = ground + hover[i]
		if arc[i] == 1 and pos[i].y <= ground + 0.15:
			pos[i].y = ground + 0.15
			# Sticky: a creature by the landing spot gets the grenade on its back instead of a blast
			var w0: WeaponInstance = weapon[i]
			if hostile[i] == 0 and w0 and w0.params.has("sticky"):
				var st: Dictionary = w0.params["sticky"]
				var near := enemies.nearest_index(pos[i], float(st.get("reach", 1.4)))
				if near >= 0:
					stuck[i] = near
					stuck_t[i] = float(st.get("seconds", 1.3))
					arc[i] = 0
					vel[i] = Vector3.ZERO
					continue
			_explode(i)
			_free(i)
			continue
		if arc[i] == 1 and hostile[i] == 0:
			# Oil Slick (pass 33): the burning bottle leaks as it flies, a drop every `every` metres of the throw
			if extra[i].has("drip"):
				_drip(i)
			# lobbed shots (skulls, grenades, bomblets) sail over and through the crowd; they only ever explode on landing
			continue
		if hostile[i] == 1:
			_trail_t[i] -= delta
			if _trail_t[i] <= 0.0:
				_trail_t[i] = TRAIL_STEP
				# silk is white; spit is green; a sun shard gold, lead smoke grey; a harpoon trails its rope (Game draws it)
				var shot_kind := str(extra[i].get("shot", ""))
				if extra[i].has("harpoon"):
					pass
				elif extra[i].has("pull"):
					_drop_trail(pos[i], Color(0.96, 0.96, 0.9, 0.7), 0.8)
				elif shot_kind == "shard":
					_drop_trail(pos[i], Color(1.0, 0.84, 0.36, 0.6), 0.9)
				elif shot_kind == "pellet":
					_drop_trail(pos[i], Color(0.42, 0.4, 0.44, 0.45), 0.7)
				else:
					_drop_trail(pos[i])
			if player and not player.dead:
				# a flat distance and a height band as tall as the hero: a shard off a tall creature's staff flies at
				# head height, and the old sphere under a metre across let it pass straight over him
				var d := player.global_position - pos[i]
				var dy: float = pos[i].y - player.global_position.y
				d.y = 0.0
				if d.length() < radius[i] + 0.5 and dy > -0.6 and dy < 2.4:
					var kn: float = float(extra[i].get("knockback", 0.0))
					# who fired it and what it did, for the death log
					var sinfo: Dictionary = (extra[i].get("info", {}) as Dictionary).duplicate(true)
					var sfx: Array = sinfo.get("fx", [])
					if kn > 0.0:
						sfx.append("knocked back")
					if extra[i].has("pull"):
						sfx.append("pulled in")
					if extra[i].has("harpoon"):
						sfx.append("roped")
					sinfo["fx"] = sfx
					player.take_damage(dmg[i], pos[i], sinfo)
					# a shot that carries weight throws him back, once a second however many land
					if kn > 0.0 and player.has_method("shove"):
						var away := player.global_position - pos[i]
						away.y = 0.0
						if away.length_squared() > 0.01:
							player.shove(away.normalized() * kn)
					# a silk line: the hero is yanked towards whoever fired it
					if extra[i].has("pull") and extra[i].has("origin") and player.has_method("apply_knockback"):
						var to: Vector3 = Vector3(extra[i]["origin"]) - player.global_position
						to.y = 0.0
						if to.length_squared() > 0.01:
							player.apply_knockback(to.normalized() * float(extra[i]["pull"]))
					# a harpoon: the rope holds from here on
					if extra[i].has("harpoon") and game and game.has_method("tether_start"):
						game.tether_start(int(extra[i].get("shooter", -1)), extra[i].get("tether", {}))
					_free(i)
			continue
		# friendly: hit enemies
		var w: WeaponInstance = weapon[i]
		var wid := w.def.id if w else ""
		if extra[i].has("trace"):
			traces.follow(extra[i]["trace"], pos[i])
		# a tracer round (params.tracer): a bright short line behind every bullet, so a burst reads as shots fired
		if w and bool(w.params.get("tracer", false)):
			_trail_t[i] -= delta
			if _trail_t[i] <= 0.0:
				_trail_t[i] = 0.022
				_drop_trail(pos[i], Color(1.0, 0.85, 0.35, 0.9), 0.9)
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
				# Ricochet: a killing shot may bounce to the next creature, once, at 60% (never lobs or missiles);
				# a weapon with its own ricochet (Bouncing Peas) bounces at its own odds and damage
				var rc: float = Run.player_sheet.get_stat("ricochet", 0.0)
				var frac := 0.6
				if w and w.stat("ricochet", 0.0) > 0.0:
					rc = maxf(rc, w.stat("ricochet", 0.0))
					frac = w.stat("ricochet_damage", 0.6)
				if rc > 0.0 and arc[i] == 0 and not extra[i].has("bounced") and randf() < rc:
					var nxt := _nearest_other(enemies, pos[i], 7.0, memo[i])
					if nxt >= 0:
						var to: Vector3 = enemies.pos[nxt] - pos[i]
						to.y = 0.0
						var j := fire(kind[i], pos[i], to.normalized() * maxf(vel[i].length(), 8.0), dmg[i] * frac, 0, radius[i], 1.5, w, kb[i])
						if j >= 0:
							extra[j]["bounced"] = true
							memo[j][e] = true
							game.fx_burst(pos[i], Color(1.0, 0.9, 0.5), 0.45)
			if w:
				game.fx_hit(pos[i], w.def)
			pierce[i] -= 1
			if pierce[i] < 0:
				_burst_spawn(i)
				_free(i)
				break
	_tick_paths(delta)
	_ticks += 1
	_draw_dt += delta
	Perf.add("projectiles", t0)


## The shots, their trails and the rockets' lines are drawn once per shown frame, and only after a tick has moved
## them (pass 33.8: inside the physics tick, a phone below 60 fps drew them twice for every frame it showed).
func _process(_delta: float) -> void:
	if game == null or _drawn == _ticks:
		return
	_drawn = _ticks
	var t0 := Time.get_ticks_usec()
	_render()
	_tick_trail(_draw_dt)
	_draw_dt = 0.0
	_draw_paths()
	Perf.add("projectiles.draw", t0)


## The Oil Slick's leak: counts the ground a lobbed bottle has covered and lets a drop of burning oil fall every
## `drip.every` metres after the first `drip.start` (Game.oil_drip makes the spill where it lands).
func _drip(i: int) -> void:
	var p: Dictionary = extra[i]
	var dp: Dictionary = p["drip"]
	if not p.has("drip_from"):
		p["drip_from"] = pos[i]
		p["drip_went"] = 0.0
		p["drip_n"] = 0
		return
	var from: Vector3 = p["drip_from"]
	p["drip_went"] = float(p["drip_went"]) + Vector2(pos[i].x - from.x, pos[i].z - from.z).length()
	p["drip_from"] = pos[i]
	var n: int = int(p["drip_n"])
	if float(p["drip_went"]) >= float(dp.get("start", 1.2)) + float(dp.get("every", 0.9)) * n:
		p["drip_n"] = n + 1
		if game.has_method("oil_drip"):
			game.oil_drip(pos[i], weapon[i], dp)


## Sky Flare and Frag: when a shot ends it spawns others. `burst_spawn` on the weapon's params: kind "ember" lobs
## `count` embers to a ring around the spot, kind "shrapnel" throws `count` straight fragments out; never off a burst.
func _burst_spawn(i: int) -> void:
	var w: WeaponInstance = weapon[i]
	if w == null or hostile[i] == 1 or extra[i].has("is_burst"):
		return
	var bs = w.params.get("burst_spawn")
	if not bs is Dictionary:
		return
	var n := int(bs.get("count", 5))
	var dm := float(bs.get("damage_mult", 0.5))
	if str(bs.get("kind", "shrapnel")) == "ember":
		var ring := float(bs.get("ring", 2.0))
		for k in range(n):
			var a := TAU * float(k) / float(n) + randf_range(-0.2, 0.2)
			var target := pos[i] + Vector3(cos(a), 0, sin(a)) * ring
			var j := lob(kind[i], pos[i] + Vector3(0, 0.6, 0), target, 7.0, dmg[i] * dm, float(bs.get("area", 1.2)), w, kb[i] * 0.5, {"is_burst": true})
			if j >= 0:
				vel[j].y += 5.0
	else:
		var sp := float(bs.get("speed", 14.0))
		for k in range(n):
			var a := TAU * float(k) / float(n) + randf_range(-0.15, 0.15)
			var d := Vector3(cos(a), 0, sin(a))
			var j := fire(kind[i], pos[i] + Vector3(0, 0.3, 0), d * sp, dmg[i] * dm, 0, radius[i] * 0.8, float(bs.get("life", 0.5)), w, kb[i] * 0.5)
			if j >= 0:
				extra[j] = {"is_burst": true}
	game.fx_burst(pos[i], Color(1.0, 0.85, 0.45), 1.0)


## The nearest live creature to `from` within `r` that a shot has not already hit.
func _nearest_other(enemies: EnemyManager, from: Vector3, r: float, seen: Dictionary) -> int:
	var best := -1
	var best_d := r * r
	for e in enemies.indices_in_radius(from, r):
		if seen.has(e) or enemies.state[e] == EnemyManager.STATE_DYING:
			continue
		var d2: float = (enemies.pos[e] - from).length_squared()
		if d2 < best_d:
			best_d = d2
			best = e
	return best


## A homing missile: launched along `dir`, it corkscrews for `wander` seconds, then locks onto the nearest creature and
## turns towards it at `turn` rad/s, diving; it bursts in `p_area` (0 = a single hit) on contact, on the ground or
## when its life runs out. `params.trail` 1 is rocket smoke, 2 a hornet's gold dust.
func launch_missile(p_kind: int, from: Vector3, dir: Vector3, speed: float, damage: float, p_area: float, p_range: float, w: WeaponInstance, params: Dictionary, knockback: float = 0.0) -> int:
	var i := fire(p_kind, from, dir.normalized() * speed * 0.6, damage, 0, 0.3, float(params.get("life", 4.5)), w, knockback)
	if i < 0:
		return -1
	homing[i] = 1
	var wid0: String = w.def.id if w else "?"
	missiles_by_weapon[wid0] = int(missiles_by_weapon.get(wid0, 0)) + 1
	area[i] = p_area
	extra[i] = {"speed": speed, "wander": float(params.get("wander", 0.5)), "turn": float(params.get("turn", 6.0)), "spiral": float(params.get("spiral", 7.0)),
		"age": 0.0, "target": -1, "phase": randf() * TAU, "range": p_range, "trail": int(params.get("trail", 1))}
	_trail_t[i] = 0.0
	return i


## The rocketeer's rocket: slow, bright red, hunts the hero for as long as its goblin lives, and nothing the hero
## carries can touch it (hostile shots are never in the weapons' hit loop). Explodes on the hero, on the ground it
## dives to, or when its goblin dies (Game.kill_rockets_of).
func launch_enemy_rocket(p_kind: int, shooter: int, from: Vector3, dir: Vector3, speed: float, turn: float, damage: float, p_area: float, speed_of_hero: float = 0.0, info: Dictionary = {}, blast: Dictionary = {}) -> int:
	var i := fire(p_kind, from, dir.normalized() * speed, damage, 0, 0.42, 60.0, null, 0.0)
	if i < 0:
		return -1
	hostile[i] = 1
	homing[i] = 1
	area[i] = p_area
	extra[i] = {"speed": speed, "wander": 0.0, "turn": turn, "spiral": 0.0, "age": 0.0, "target": -1, "phase": 0.0, "range": 0.0,
		"trail": 3, "rocket": true, "shooter": shooter, "speed_of_hero": speed_of_hero, "info": info, "blast": blast}
	rocket_of[i] = shooter
	_trail_t[i] = 0.0
	# the smoke line home starts at the goblin's launch tube
	var rec := {"pts": PackedVector3Array([from]), "proj": i, "fade": 1.0}
	_paths.append(rec)
	extra[i]["path"] = rec
	return i


## Whether the creature `shooter` has a rocket of its own in the air (the rocketeer reloads only once it is gone).
func has_rocket_of(shooter: int) -> bool:
	for pi in rocket_of.keys():
		if int(rocket_of[pi]) == shooter and alive[int(pi)] == 1:
			return true
	return false


## The rockets whose thrower was `shooter`: they lose their guidance and go wild, corkscrewing off to die in the
## nearest crowd. A loose rocket cannot touch the hero; it throws creatures about and barely scratches them.
func kill_rockets_of(shooter: int) -> void:
	for pi in rocket_of.keys():
		if int(rocket_of[pi]) == shooter:
			if alive[pi] == 1 and extra[pi].has("rocket"):
				extra[pi]["loose"] = true
				extra[pi]["wild"] = randf() * TAU
				extra[pi]["target"] = -1
				life[pi] = 3.5
				dmg[pi] = 6.0
				game.fx_burst(pos[pi], Color(1.0, 0.7, 0.3), 1.2)
				# nobody to find any more: the line home fades
				if extra[pi].has("path"):
					extra[pi]["path"]["proj"] = -1
			rocket_of.erase(pi)


func _fly_rocket(i: int, delta: float, map) -> void:
	var p: Dictionary = extra[i]
	var player: Node3D = game.player
	var heading: Vector3 = vel[i].normalized() if vel[i].length_squared() > 0.0001 else Vector3.FORWARD
	if bool(p.get("loose", false)):
		# no hand on it any more: it swirls, hunts the nearest creature instead of the hero, and goes off there
		var enemies2: EnemyManager = game.enemies
		var t2: int = int(p.get("target", -1))
		if t2 < 0 or not enemies2.is_alive(t2):
			t2 = enemies2.nearest_index(pos[i], 30.0)
			p["target"] = t2
		p["wild"] = float(p.get("wild", 0.0)) + delta * 9.0
		var swirl := heading.rotated(Vector3.UP, sin(float(p["wild"])) * 5.0 * delta)
		if t2 >= 0:
			var want2: Vector3 = (enemies2.pos[t2] + Vector3(0, 0.5, 0) - pos[i])
			if want2.length_squared() > 0.0001:
				want2 = want2.normalized()
				var ang2 := swirl.angle_to(want2)
				if ang2 > 0.001 and ang2 < PI - 0.02:
					swirl = swirl.slerp(want2, clampf(2.2 * delta / ang2, 0.0, 1.0)).normalized()
			if pos[i].distance_to(enemies2.pos[t2]) < 1.2 or life[i] <= 0.0:
				_explode_loose(i)
				return
		vel[i] = swirl.normalized() * float(p["speed"]) * 1.4
		pos[i] += vel[i] * delta
		var g2: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
		pos[i].y = clampf(pos[i].y, g2 + 0.5, g2 + 4.0)
		_trail_t[i] -= delta
		if _trail_t[i] <= 0.0:
			_trail_t[i] = 0.03
			_drop_trail(pos[i], Color(1.0, 0.5, 0.15, 0.9), 1.4)
		if life[i] <= 0.0:
			_explode_loose(i)
		return
	# the rocket keeps to a fraction of the hero's top speed (pass 33.2: 90%), so it gains on nobody and nobody outruns it
	# for free: a Sprint makes it faster too, a harpoon rope slower
	var soh: float = float(p.get("speed_of_hero", 0.0))
	if soh > 0.0 and player and player.has_method("max_speed"):
		p["speed"] = maxf(player.max_speed() * soh, 1.0)
	if player and not player.dead:
		var want: Vector3 = (player.global_position + Vector3(0, 0.9, 0) - pos[i])
		if want.length_squared() > 0.0001:
			want = want.normalized()
			var ang := heading.angle_to(want)
			if ang > 0.001 and ang < PI - 0.02:
				heading = heading.slerp(want, clampf(float(p["turn"]) * delta / ang, 0.0, 1.0)).normalized()
			elif ang >= PI - 0.02:
				heading = heading.rotated(Vector3.UP, float(p["turn"]) * delta).normalized()
	vel[i] = heading * float(p["speed"])
	pos[i] += vel[i] * delta
	# no tumbling: a rocket points where it is going, and it pulses bigger and smaller twice a second so the eye
	# catches it against the sand
	spin[i] = 0.0
	var age2: float = float(p.get("age2", 0.0)) + delta
	p["age2"] = age2
	psize[i] = 1.0 + 0.28 * sin(age2 * 12.0)
	var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
	pos[i].y = clampf(pos[i].y, ground + 0.5, ground + 4.0)
	# the faint line home: a point every PATH_STEP metres, the oldest half thinned when it gets long
	var rec = p.get("path")
	if rec is Dictionary:
		var pts: PackedVector3Array = rec["pts"]
		if pts.is_empty() or pts[pts.size() - 1].distance_to(pos[i]) >= PATH_STEP:
			pts.append(pos[i])
			if pts.size() > PATH_MAX:
				var thin := PackedVector3Array()
				var half := pts.size() / 2
				for k in range(pts.size()):
					if k >= half or k % 2 == 0:
						thin.append(pts[k])
				pts = thin
			rec["pts"] = pts
	_trail_t[i] -= delta
	if _trail_t[i] <= 0.0:
		# a bright red and white smoke line, thick, so the rocket is seen coming from across the screen
		_trail_t[i] = 0.03
		extra[i]["puff"] = int(extra[i].get("puff", 0)) + 1
		if int(extra[i]["puff"]) % 2 == 0:
			_drop_trail(pos[i], Color(1.0, 0.15, 0.1, 0.9), 1.6)
		else:
			_drop_trail(pos[i], Color(1.0, 0.85, 0.8, 0.85), 1.0)
	if player and not player.dead:
		var d := player.global_position + Vector3(0, 0.9, 0) - pos[i]
		if d.length() < radius[i] + 0.6:
			_explode(i)
			rocket_of.erase(i)
			_free(i)


func _fly_missile(i: int, delta: float, enemies: EnemyManager, map) -> void:
	var p: Dictionary = extra[i]
	if p.has("rocket"):
		_fly_rocket(i, delta, map)
		return
	var age: float = float(p["age"]) + delta
	p["age"] = age
	var spd: float = float(p["speed"])
	var heading: Vector3 = vel[i].normalized() if vel[i].length_squared() > 0.0001 else Vector3.FORWARD
	var wander: float = float(p["wander"])
	if age < wander:
		# the corkscrew: the yaw swings on a sine while the nose eases towards level, at reduced speed
		var ph: float = float(p["phase"]) + age * float(p["spiral"])
		heading = heading.rotated(Vector3.UP, sin(ph) * 6.5 * delta)
		heading.y = lerpf(heading.y, 0.3, clampf(delta * 3.0, 0.0, 1.0))
		heading = heading.normalized()
		spd *= 0.65
	else:
		var t: int = int(p["target"])
		if t < 0 or enemies.alive[t] == 0 or enemies.state[t] == EnemyManager.STATE_DYING or enemies.hidden[t] == 1:
			t = enemies.nearest_index(pos[i], float(p["range"]) + 6.0)
			p["target"] = t
		if t >= 0:
			var want: Vector3 = (enemies.pos[t] + Vector3(0, enemies.size[t] * 0.45, 0) - pos[i]).normalized()
			var ang := heading.angle_to(want)
			if ang > 0.0001 and ang < PI - 0.02:
				heading = heading.slerp(want, clampf(float(p["turn"]) * delta / ang, 0.0, 1.0)).normalized()
			elif ang >= PI - 0.02:
				# straight behind: slerp has no plane to turn in, so yaw
				heading = heading.rotated(Vector3.UP, float(p["turn"]) * delta).normalized()
		else:
			heading.y = lerpf(heading.y, -0.25, clampf(delta * 2.0, 0.0, 1.0))
			heading = heading.normalized()
	vel[i] = heading * spd
	pos[i] += vel[i] * delta
	spin[i] += delta * 20.0
	var ground: float = map.height_at(pos[i].x, pos[i].z) if map else 0.0
	if pos[i].y < ground + 0.25:
		pos[i].y = ground + 0.25
		if age >= wander:
			if area[i] > 0.05:
				_explode(i)
			else:
				# a seeker (no blast) just fizzles in the sand: the zero-radius blast used to spawn a zero-radius cloud
				# whose mesh logged hundreds of warnings each, and every hornet dived at once when a boss died
				game.fx_burst(pos[i], Color(0.9, 0.8, 0.5), 0.35)
			_free(i)
			return
		vel[i].y = absf(vel[i].y)
	pos[i].y = minf(pos[i].y, ground + 7.0)
	_trail_t[i] -= delta
	if _trail_t[i] <= 0.0:
		_trail_t[i] = 0.028
		if int(p["trail"]) == 1:
			# rocket smoke: dark puffs with a hot white core every other drop, so the trail reads on the sand (a warm
			# puff the colour of the ground was invisible)
			extra[i]["puff"] = int(extra[i].get("puff", 0)) + 1
			if int(extra[i]["puff"]) % 2 == 0:
				_drop_trail(pos[i], Color(0.32, 0.31, 0.42, 0.78), 1.5)
			else:
				_drop_trail(pos[i], Color(1.0, 0.96, 0.85, 0.9), 0.75)
		else:
			# a seeker's line: dark, thin
			_drop_trail(pos[i], Color(0.32, 0.2, 0.08, 0.6), 0.8)
	# contact
	var hits := enemies.indices_in_radius(pos[i], radius[i] + 0.4)
	if hits.is_empty():
		return
	if area[i] > 0.01:
		_explode(i)
	else:
		var w: WeaponInstance = weapon[i]
		var wid := w.def.id if w else ""
		var e: int = hits[0]
		# a seeker's sting carries the weapon's element (Ember Hornets)
		if w and w.stat("fire_damage", 0.0) > 0.0:
			enemies.ignite(e, wid, w.stat("fire_damage", 4.0), w.stat("fire_duration", 1.8), w.stat("fire_spread", 0.5))
		if w and w.stat("poison_damage", 0.0) > 0.0:
			enemies.poison(e, wid, w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 10.0))
		var killed := enemies.damage(e, dmg[i], wid, vel[i], kb[i])
		if killed and w:
			w.kills += 1
		if w:
			game.fx_hit(pos[i], w.def)
		# Second Sting: a hornet that kills loops round and dives at the next creature, once
		if killed and w and bool(w.params.get("second_sting", false)) and not extra[i].has("second"):
			extra[i]["second"] = true
			extra[i]["target"] = -1
			extra[i]["age"] = float(extra[i].get("wander", 0.0))
			life[i] = maxf(life[i], 1.5)
			vel[i] = -vel[i] * 0.5 + Vector3(0, 3.0, 0)
			game.fx_burst(pos[i], Color(1.0, 0.85, 0.3), 0.6)
			return
	_free(i)


func _tick_trail(delta: float) -> void:
	var n := 0
	for k in range(TRAIL_MAX):
		if trail_age[k] >= TRAIL_LIFE:
			continue
		trail_age[k] += delta
		var f: float = clampf(trail_age[k] / TRAIL_LIFE, 0.0, 1.0)
		var s: float = (1.0 - f * 0.7) * maxf(trail_size[k], 0.1)
		_trail_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, s, s)), trail_pos[k]))
		var c: Color = trail_col[k]
		_trail_mm.set_instance_color(n, Color(c.r, c.g, c.b, c.a * (1.0 - f)))
		n += 1
	_trail_mm.visible_instance_count = n


## The lines of rockets that are gone fade over a second and a bit, and go (the tick; _draw_paths draws them).
func _tick_paths(delta: float) -> void:
	if _paths.is_empty():
		return
	var keep: Array = []
	for rec in _paths:
		if int(rec["proj"]) < 0:
			rec["fade"] = float(rec["fade"]) - delta / 1.2
			if float(rec["fade"]) <= 0.0:
				continue
		keep.append(rec)
	_paths = keep


## The rockets' lines home, as one ImmediateMesh: a flat ribbon per segment facing the camera, from the launch point to
## the rocket (or to where it ended, fading).
func _draw_paths() -> void:
	if _paths.is_empty():
		if _path_drawn:
			_path_mesh.clear_surfaces()
			_path_drawn = false
		return
	var cam := get_viewport().get_camera_3d()
	var to_cam: Vector3 = cam.global_transform.basis.z if cam else Vector3.UP
	_path_mesh.clear_surfaces()
	var begun := false
	for rec in _paths:
		var pi: int = int(rec["proj"])
		var pts: PackedVector3Array = rec["pts"]
		if pi >= 0 and alive[pi] == 1:
			pts.append(pos[pi])
		if pts.size() < 2:
			continue
		if not begun:
			_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
		var c := Color(PATH_COLOR.r, PATH_COLOR.g, PATH_COLOR.b, PATH_COLOR.a * float(rec["fade"]))
		for k in range(pts.size() - 1):
			var p0 := pts[k]
			var p1 := pts[k + 1]
			var dir := p1 - p0
			if dir.length_squared() < 0.0001:
				continue
			var side := dir.cross(to_cam).normalized() * PATH_WIDTH * 0.5
			for v in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
				_path_mesh.surface_set_color(c)
				_path_mesh.surface_add_vertex(v)
	if begun:
		_path_mesh.surface_end()
	_path_drawn = begun


## A loose rocket goes off: it throws the crowd about and barely hurts it, and the hero is not touched at all.
func _explode_loose(i: int) -> void:
	var enemies: EnemyManager = game.enemies
	enemies.damage_radius(pos[i], maxf(area[i], 2.4), dmg[i], "loose_rocket", 11.0)
	game.fx_burst(pos[i] + Vector3(0, 0.5, 0), Color(1.0, 0.6, 0.2), 3.0)
	if game.has_method("shockwave"):
		game.shockwave(pos[i], maxf(area[i], 2.4))
	Audio.play("w_lob_boom", pos[i])
	rocket_of.erase(i)
	_free(i)


func _explode(i: int) -> void:
	var enemies: EnemyManager = game.enemies
	if hostile[i] == 1:
		if extra[i].has("rocket"):
			# the rocketeer's rocket goes off big (pass 33.3): Game.rocket_blast throws the hero and the crowd
			game.rocket_blast(pos[i], area[i], dmg[i], extra[i].get("info", {}), extra[i].get("blast", {}))
			return
		var player: Node3D = game.player
		if player and not player.dead:
			var d := player.global_position - pos[i]
			d.y = 0.0
			if d.length() <= area[i] + 0.4:
				var einfo: Dictionary = (extra[i].get("info", {}) as Dictionary).duplicate(true)
				(einfo.get("fx", []) as Array).append("rocket blast" if extra[i].has("rocket") else "splash")
				player.take_damage(dmg[i], pos[i], einfo)
		game.fx_burst(pos[i], Color(0.45, 0.75, 0.4), area[i])
		return
	if extra[i] is Dictionary and (extra[i] as Dictionary).has("vortex"):
		# the Singularity: no blast, a black hole that drags and eats and then pops (Vortex); its spot is taken while it lives
		lobs_exploded += 1
		game.spawn_vortex(pos[i], weapon[i], area[i], extra[i]["vortex"], dmg[i])
		_landed.append({"at": pos[i], "t": float((extra[i]["vortex"] as Dictionary).get("seconds", 3.0))})
		return
	var w: WeaponInstance = weapon[i]
	var wid := w.def.id if w else ""
	var before := Run.kills
	lobs_exploded += 1
	if not (extra[i] as Dictionary).has("is_bomblet"):
		_landed.append({"at": pos[i], "t": LANDED_CLAIM})
	enemies.damage_radius(pos[i], area[i], dmg[i], wid, kb[i])
	var element: String = w.element() if w else ""
	if w and element != "":
		# the blast itself carries the element (Thermobaric, Incendiary): everything in it is lit or poisoned at once
		for e in enemies.indices_in_radius(pos[i], area[i]):
			if w.stat("fire_damage", 0.0) > 0.0:
				enemies.ignite(e, wid, w.stat("fire_damage", 4.0), w.stat("fire_duration", 1.8), w.stat("fire_spread", 0.5))
			if w.stat("poison_damage", 0.0) > 0.0:
				enemies.poison(e, wid, w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 10.0))
	if element != "" and area[i] > 0.3:
		# a poison bomb leaves a cloud, a fire bomb a burning pool; both keep working on whoever stands in them
		game.spawn_cloud(pos[i], w, area[i], element, extra[i])
	_burst_spawn(i)
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


## Warm-up: one instance of every kind at `at` (Vector3.INF stops it), so the instanced shader variants compile early.
var _warm_at := Vector3.INF


func warm_draw(at: Vector3) -> void:
	_warm_at = at
	for kd in kinds:
		var mm: MultiMesh = kd["mm"]
		if at == Vector3.INF:
			mm.visible_instance_count = 0
		else:
			mm.set_instance_transform(0, Transform3D(Basis(), at))
			mm.visible_instance_count = 1
	if at != Vector3.INF:
		_drop_trail(at)


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
		basis = basis.rotated(basis.z, spin[i]).scaled(Vector3(s, s, s) * psize[i])
		mm.set_instance_transform(n, Transform3D(basis, pos[i]))
		counters[k] = n + 1
	for k in range(kinds.size()):
		if _warm_at != Vector3.INF:
			kinds[k]["mm"].set_instance_transform(counters[k], Transform3D(Basis(), _warm_at))
			counters[k] += 1
		kinds[k]["mm"].visible_instance_count = counters[k]
