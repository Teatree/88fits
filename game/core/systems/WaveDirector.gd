## Reads the map's WaveTimeline and keeps the arena full: a growing live cap, a roster that changes
## over time, scripted elites, swarm rings, and bosses. Owns the stage clock and the portal flow.
class_name WaveDirector
extends Node

signal boss_started(def: EnemyDef)
signal portal_ready(pos: Vector3)
signal stage_started(stage: int)

enum Phase { NORMAL, BOSS, PORTAL }

var game: Node
var timeline: WaveTimeline
var map: MapDef
var phase := Phase.NORMAL
var _spawn_t := 0.0
var _event_i := 0
var _elite_timers: Array = []     # {next, interval}
var _cull_t := 0.0
var _endless_next_boss := 0.0
var _endless_next_elite := 0.0
var _endless_next_elite_boss := 0.0
var _endless_wave := 0
var _endless_boss_i := 0   # the endless loop's bosses come in the timeline's order (pass 43)
var elite_index := -1            # the mini-boss while it lives (the HUD points at it)
var _rng := RandomNumberGenerator.new()
var _pickup_t := -1.0          # seconds until the next pickup; negative = none scheduled
var running := false


func start(p_map: MapDef) -> void:
	map = p_map
	timeline = p_map.timeline if p_map.timeline else WaveTimeline.new()
	phase = Phase.NORMAL
	_event_i = 0
	_elite_timers.clear()
	_rng.randomize()
	running = true
	var em: EnemyManager = game.enemies
	for a in map.skins.keys():
		em.register_type(Registry.enemy(map.skins[a]))
	if map.boss != "":
		em.register_type(Registry.enemy(map.boss))
	em.boss_died.connect(_on_boss_died)
	var pk: Dictionary = timeline.pickups
	# a timeline may still schedule pickups on a clock ("first"/"interval"); the desert drops them from kills instead
	_pickup_t = float(pk.get("first", 50.0)) if pk.has("interval") and not (pk.get("roster", []) as Array).is_empty() else -1.0
	_apply_mults()
	stage_started.emit(Run.stage)


func stop() -> void:
	running = false
	elite_index = -1


func _apply_mults() -> void:
	var em: EnemyManager = game.enemies
	em.stage_mult = Run.stage_mult()
	em.stage_speed_mult = timeline.speed_mult(Run.stage)
	em.hp_time_mult = timeline.hp_mult_at(Run.elapsed)
	var lv := float(maxi(Run.level - 1, 0))
	em.level_hp_mult = 1.0 + timeline.level_hp_per_level * lv
	em.level_dmg_mult = 1.0 + timeline.level_damage_per_level * lv


func current_cap() -> int:
	var cap := timeline.cap_at(Run.elapsed, Run.stage)
	if phase == Phase.BOSS:
		return int(cap * 0.3)
	if phase == Phase.PORTAL:
		return int(cap * 0.15)
	return cap


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	if not running or game.paused:
		Perf.add("director", _t0)
		return
	if phase == Phase.NORMAL:
		Run.elapsed += delta
		_apply_mults()
		_process_events()
		# the path slots: a stage puts a weapon's whole path on the table at set seconds into it
		if Run.path_due(Run.elapsed - float(Run.stage) * timeline.stage_length) and game.has_method("present_path_offer"):
			game.present_path_offer()
	if phase != Phase.PORTAL:
		_tick_specials(delta)
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = timeline.spawn_interval
		_spawn_burst()
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = 0.5
		_cull_behind()
	if _pickup_t > 0.0:
		_pickup_t -= delta
		if _pickup_t <= 0.0:
			_spawn_pickup()
	Perf.add("director", _t0)


func _process_events() -> void:
	var t := Run.elapsed
	while _event_i < timeline.events.size():
		var ev: Dictionary = timeline.events[_event_i]
		if float(ev.get("t", 0.0)) > t:
			break
		_event_i += 1
		_run_event(ev)
		if phase != Phase.NORMAL:
			return
	for et in _elite_timers:
		if t >= float(et["next"]):
			et["next"] = t + float(et["interval"])
			_spawn_elite("", "")
	if Run.endless:
		# every wave (a minute) the crowd gets endless_wave_mult tougher, compounding (pass 43); the multipliers follow
		# through _apply_mults, this is the announcement
		var wave := Run.endless_wave()
		if wave != _endless_wave:
			_endless_wave = wave
			if wave > 1:
				game.toast("WAVE %d · ×%.2f" % [wave, Run.stage_mult()], Color(0.93, 0.29, 0.36))
		if t >= _endless_next_elite:
			_endless_next_elite = t + 45.0
			_spawn_elite("", "")
		if t >= _endless_next_boss and map.boss != "":
			_endless_next_boss = t + 300.0
			_endless_next_elite_boss = t + 150.0
			_run_event({"type": "boss", "enemy": _endless_boss_id()})
		if _endless_next_elite_boss > 0.0 and t >= _endless_next_elite_boss and _endless_elite_id() != "":
			_endless_next_elite_boss = 0.0
			_run_event({"type": "elite_boss", "enemy": _endless_elite_id()})


## Seconds until the next boss event, or -1 when none is scheduled. The HUD counts it down.
func next_boss_in() -> float:
	if timeline == null:
		return -1.0
	var t: float = Run.elapsed
	if Run.endless:
		return _endless_next_boss - t
	var best := -1.0
	for ev in timeline.events:
		if str(ev.get("type", "")) == "boss":
			var et := float(ev.get("t", 0.0))
			if et > t and (best < 0.0 or et - t < best):
				best = et - t
	return best


func _run_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"elite":
			_spawn_elite(str(ev.get("enemy", "")), str(ev.get("mod", "")))
		"elite_every":
			_elite_timers.append({"next": Run.elapsed, "interval": float(ev.get("interval", 90.0))})
		"swarm":
			var em: EnemyManager = game.enemies
			var id := str(ev.get("enemy", ""))
			if id == "" and not map.skins.is_empty():
				id = map.skins.values()[0]
			em.spawn_ring(id, int(ev.get("count", 40)), game.player.global_position, 16.0)
			game.toast("SWARM!", Color(0.94, 0.63, 0.35))
		"boss":
			_start_boss(str(ev.get("enemy", map.boss)))
		"elite_boss":
			# `enemy` may be a list: one of them, at random (the scorpion or the djinn)
			_spawn_elite_boss(_pick_id(ev.get("enemy", "")))


func _start_boss(id: String, where: Vector3 = Vector3.INF) -> void:
	var def: EnemyDef = Registry.enemy(id)
	if def == null:
		return
	phase = Phase.BOSS
	var em: EnemyManager = game.enemies
	var mb: MapBase = game.map
	# the arena may name the spot; the timeline's boss comes up on the flats
	var at: Vector3 = mb.flats_center + Vector3(0, 0, -10) if where == Vector3.INF else where
	em.spawn_boss(id, at)
	boss_started.emit(def)
	game.toast(def.display_name.to_upper(), Color(0.93, 0.29, 0.36))


## The mini-boss: one big creature near the hero, a toast and nothing else. Its chest comes from its drops.
func _spawn_elite_boss(id: String) -> void:
	var def: EnemyDef = Registry.enemy(id)
	if def == null:
		return
	var em: EnemyManager = game.enemies
	em.register_type(def)
	var i := em.spawn(id, _spawn_point())
	if i >= 0:
		elite_index = i
		game.toast(def.display_name.to_upper(), Color(0.98, 0.62, 0.25))


## The boss the endless loop brings next: the timeline's boss events in order, round and round (the King, the Gila, the
## Brander, the King...), the map's boss when it has none.
func _endless_boss_id() -> String:
	var ids: Array = []
	for ev in timeline.events:
		if str(ev.get("type", "")) == "boss" and Registry.enemy(str(ev.get("enemy", ""))) != null:
			ids.append(str(ev.get("enemy", "")))
	if ids.is_empty():
		return map.boss
	var id: String = ids[_endless_boss_i % ids.size()]
	_endless_boss_i += 1
	return id


## The mini-boss the endless loop repeats: the last elite_boss event in the timeline (one of its ids when it lists several).
func _endless_elite_id() -> String:
	for k in range(timeline.events.size() - 1, -1, -1):
		var ev: Dictionary = timeline.events[k]
		if str(ev.get("type", "")) == "elite_boss":
			return _pick_id(ev.get("enemy", ""))
	return ""


func _pick_id(v) -> String:
	if v is Array and not v.is_empty():
		return str(v[_rng.randi() % v.size()])
	return str(v)


## Position of the living mini-boss, or Vector3.INF when none.
func elite_position() -> Vector3:
	var em: EnemyManager = game.enemies
	if elite_index >= 0 and em.is_alive(elite_index) and (em.types[em.type_idx[elite_index]]["def"] as EnemyDef).archetype == "elite":
		return em.pos[elite_index]
	elite_index = -1
	return Vector3.INF


func _on_boss_died(def: EnemyDef, at: Vector3) -> void:
	phase = Phase.PORTAL
	# the boss's own chest: it holds a mutation, and opening it is what calls every gem, coin and chest in (pass 30)
	game.pickups.spawn_chest(at + Vector3(2.0, 0, 0), true)
	Save.mark_once("boss_%s_%d" % [map.id, Run.stage + 1])
	QuestTracker.check_run_events()
	portal_ready.emit(at)


## Called by the game when the player chooses to continue through the portal.
func continue_to_next_stage() -> void:
	Run.stage += 1
	Run.path_slot = 0
	if Run.stage >= timeline.stages:
		Run.endless = true
		_endless_wave = 1
		_endless_boss_i = 0
		_endless_next_boss = Run.elapsed + 300.0
		_endless_next_elite = Run.elapsed + 45.0
		_endless_next_elite_boss = Run.elapsed + 150.0
	phase = Phase.NORMAL
	_apply_mults()
	Run.stage_changed.emit(Run.stage)
	stage_started.emit(Run.stage)


func _spawn_burst() -> void:
	var em: EnemyManager = game.enemies
	var cap := current_cap()
	var all := timeline.roster_at(Run.elapsed)
	# the hell channel (pass 43): its rows spawn against their own cap, a fraction of the regular one, so the regular
	# roster keeps its mix and its count exactly; the hell crowd is bodies on top
	var hell_rows: Array = all.filter(func(r: Dictionary) -> bool: return str(r.get("channel", "")) == "hell")
	var hell_load := _hell_load(hell_rows)
	# the cap counts each creature's share (the fodder counts half), and the map's hard cap is a count of bodies
	var room: float = float(cap) - (em.cap_load() - hell_load)
	var bodies: int = timeline.hard_cap - em.alive_count()
	if bodies <= 0:
		return
	var regular: Array = all.filter(func(r: Dictionary) -> bool: return str(r.get("channel", "")) != "hell")
	if room > 0.0:
		bodies = _burst_from(_roster_open(regular), room, bodies)
	var hell_room: float = timeline.hell_cap_at(Run.stage) * float(cap) - hell_load
	if hell_room > 0.0 and bodies > 0 and not hell_rows.is_empty():
		_burst_from(_roster_open(hell_rows), hell_room, bodies)


## One burst from `roster` (weighted rows) into `room` of cap and `bodies` of the hard cap; returns the bodies left.
func _burst_from(roster: Array, room: float, bodies: int) -> int:
	var em: EnemyManager = game.enemies
	if roster.is_empty():
		return bodies
	var burst: float = minf(float(_rng.randi_range(timeline.burst_min, timeline.burst_max)), room)
	var total_w := 0.0
	var ws: Array = []
	for r in roster:
		ws.append(_roster_weight(r, Run.elapsed))
		total_w += ws[ws.size() - 1]
	while burst > 0.0 and bodies > 0:
		var pick := _rng.randf() * total_w
		var chosen: Dictionary = roster[0]
		for k in range(roster.size()):
			pick -= float(ws[k])
			if pick <= 0.0:
				chosen = roster[k]
				break
		var def: EnemyDef = Registry.enemy(str(chosen.get("enemy", "")))
		if def == null:
			return bodies
		var share: float = maxf(def.cap_share, 0.05)
		var n: int = mini(mini(def.pack_size, maxi(int(ceil(burst / share)), 1)), bodies)
		em.spawn_pack(def.id, _spawn_point(), n)
		burst -= float(n) * share
		bodies -= n
	return bodies


## The hell channel's living creatures against its cap (each its cap_share), from its roster rows.
func _hell_load(rows: Array) -> float:
	var em: EnemyManager = game.enemies
	var load := 0.0
	var seen: Dictionary = {}
	for r in rows:
		var id := str(r.get("enemy", ""))
		if seen.has(id):
			continue
		seen[id] = true
		var def: EnemyDef = Registry.enemy(id)
		if def:
			load += float(em.alive_of(id)) * def.cap_share
	return load


## The hell channel's rows in the roster now (the arena's WAVES tab and the tests).
func hell_rows() -> Array:
	return timeline.roster_at(Run.elapsed).filter(func(r: Dictionary) -> bool: return str(r.get("channel", "")) == "hell")


## The roster without the rows whose creature is at its live limit (`max_alive`: the harpooner is never more than one).
# ---------------------------------------------------------------- the specials

## seconds until the next special; below zero while one is alive (the clock only starts once it is dead)
var special_t := -1.0


## The specials' clock (pass 33.4). From the timeline's `specials.from` in stage 1 (and all through every later stage),
## while fewer than `max_alive` specials live, a countdown of `interval` seconds runs, and at its end one creature from
## the pool comes in (a pool row with a `stage` waits for that stage: the harpooner is a stage 2 creature).
func _tick_specials(delta: float) -> void:
	var sp: Dictionary = timeline.specials
	if sp.is_empty():
		return
	if Run.stage == 0 and Run.elapsed < float(sp.get("from", 150.0)):
		return
	var pool := specials_pool()
	if pool.is_empty():
		return
	if specials_alive() >= int(sp.get("max_alive", 1)):
		special_t = -1.0
		return
	if special_t < 0.0:
		var iv: Array = sp.get("interval", [20.0, 40.0])
		special_t = _rng.randf_range(float(iv[0]), float(iv[iv.size() - 1]))
	special_t -= delta
	if special_t > 0.0:
		return
	special_t = -1.0
	var id: String = pool[_rng.randi() % pool.size()]
	var em: EnemyManager = game.enemies
	em.register_type(Registry.enemy(id))
	em.spawn(id, _spawn_point())


## The special ids that may come now: the pool rows whose stage has come.
func specials_pool() -> Array:
	var out: Array = []
	for row in timeline.specials.get("pool", []):
		var id := str(row.get("enemy", "")) if row is Dictionary else str(row)
		var st := int(row.get("stage", 1)) if row is Dictionary else 1
		if Registry.enemy(id) != null and Run.stage + 1 >= st:
			out.append(id)
	return out


## How many specials are alive right now (any of the pool, whatever the stage).
func specials_alive() -> int:
	var em: EnemyManager = game.enemies
	var n := 0
	for row in timeline.specials.get("pool", []):
		n += em.alive_of(str(row.get("enemy", "")) if row is Dictionary else str(row))
	return n


func _roster_open(rows: Array) -> Array:
	var em: EnemyManager = game.enemies
	var out: Array = []
	for r in rows:
		var def: EnemyDef = Registry.enemy(str(r.get("enemy", "")))
		if def and def.max_alive > 0 and em.alive_of(def.id) >= def.max_alive:
			continue
		out.append(r)
	return out


## A roster row's weight at time `t`: `weight` when it arrives, sliding to `weight_late` (when the row has one) by the
## timeline's `weight_late_t` (600 s, the end of stage 2), so the goblins thin out as the harder creatures take over.
func _roster_weight(r: Dictionary, t: float) -> float:
	var w := float(r.get("weight", 1.0))
	if not r.has("weight_late"):
		return w
	var start := float(r.get("t", 0.0))
	var late_t := float(timeline.weight_late_t)
	var f := clampf((t - start) / maxf(late_t - start, 1.0), 0.0, 1.0)
	return lerpf(w, float(r.get("weight_late", w)), f)


## Power-ups drop from kills: a per-kill chance scaled by how hard the creature was (its xp_mult; elite variants count
## double), and the rarer power-ups weigh more the harder the creature (hard_bias per roster row).
func drop_pickup_from(def: EnemyDef, at: Vector3, elite: bool) -> void:
	var pk: Dictionary = timeline.pickups
	var roster: Array = pk.get("roster", [])
	var per_kill := float(pk.get("per_kill", 0.0))
	if roster.is_empty() or per_kill <= 0.0:
		return
	var hardness: float = def.xp_mult * (2.0 if elite else 1.0)
	if _rng.randf() >= per_kill * hardness:
		return
	var total := 0.0
	var weights: Array = []
	for r in roster:
		var w: float = float(r.get("weight", 1.0)) * (1.0 + float(r.get("hard_bias", 0.0)) * hardness / 3.0)
		weights.append(w)
		total += w
	var pick := _rng.randf() * total
	var chosen: Dictionary = roster[0]
	for k in range(roster.size()):
		pick -= float(weights[k])
		if pick <= 0.0:
			chosen = roster[k]
			break
	var pdef: PickupDef = Registry.pickup(str(chosen.get("id", "")))
	if pdef == null:
		return
	var p := at + Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.8, 0.8))
	p.y = (game.map as MapBase).height_at(p.x, p.z)
	game.pickups.spawn_special(pdef, p)


## One pickup from the map's roster, a short run away from the hero, then the next one is scheduled.
func _spawn_pickup() -> void:
	var pk: Dictionary = timeline.pickups
	var roster: Array = pk.get("roster", [])
	var interval := float(pk.get("interval", 75.0))
	var jitter := float(pk.get("jitter", 0.0))
	_pickup_t = maxf(interval + _rng.randf_range(-jitter, jitter), 10.0)
	if roster.is_empty():
		return
	var total := 0.0
	for r in roster:
		total += float(r.get("weight", 1.0))
	var pick := _rng.randf() * total
	var chosen: Dictionary = roster[0]
	for r in roster:
		pick -= float(r.get("weight", 1.0))
		if pick <= 0.0:
			chosen = r
			break
	var def: PickupDef = Registry.pickup(str(chosen.get("id", "")))
	if def == null:
		return
	var player: Node3D = game.player
	var mb: MapBase = game.map
	var a := _rng.randf() * TAU
	var p: Vector3 = player.global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(7.0, 11.0)
	p = mb.clamp_to_arena(p)
	p.y = mb.height_at(p.x, p.z)
	game.pickups.spawn_special(def, p)
	game.toast("%s nearby" % def.display_name, def.color)


func _spawn_point() -> Vector3:
	var player: Node3D = game.player
	var mb: MapBase = game.map
	var ahead := _rng.randf() < 0.7
	var yaw: float = player.facing
	var a: float
	if ahead:
		a = yaw + _rng.randf_range(-1.05, 1.05)
	else:
		a = _rng.randf() * TAU
	var r := _rng.randf_range(19.0, 24.0)
	var dir := Vector3(-sin(a), 0, -cos(a))
	var p: Vector3 = player.global_position + dir * r
	return mb.clamp_to_arena(p)


## The roster rows an elite modifier may land on: only a creature that can be an Elite (a cactus cannot, nor a special).
static func elite_candidates(rows: Array) -> Array:
	return rows.filter(func(r: Dictionary) -> bool:
		var d: EnemyDef = Registry.enemy(str(r.get("enemy", "")))
		return d != null and d.can_be_elite)


func _spawn_elite(enemy_id: String, mod_id: String) -> void:
	var em: EnemyManager = game.enemies
	if enemy_id == "":
		var roster := elite_candidates(_roster_open(timeline.roster_at(Run.elapsed)))
		if roster.is_empty():
			return
		enemy_id = str(roster[_rng.randi() % roster.size()].get("enemy", ""))
	var mod: EliteModDef = Registry.elites.get(mod_id)
	if mod == null:
		var list := Registry.elites_list()
		if list.is_empty():
			return
		mod = list[_rng.randi() % list.size()]
	var i := em.spawn(enemy_id, _spawn_point(), mod)
	if i >= 0:
		game.toast(("%s %s" % [mod.display_name, Registry.enemy(enemy_id).display_name]).to_upper(), mod.outline)


func _cull_behind() -> void:
	var em: EnemyManager = game.enemies
	var player: Node3D = game.player
	var fwd: Vector3 = player.forward()
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 0 or i == em.boss_index or i == elite_index:
			continue
		if (em.types[em.type_idx[i]]["def"] as EnemyDef).brain == "artillery":
			continue
		var d := em.pos[i] - player.global_position
		d.y = 0.0
		if d.length() > 30.0 and d.normalized().dot(fwd) < -0.3:
			var p := _spawn_point()
			em.pos[i] = Vector3(p.x, em._height(p.x, p.z), p.z)
