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
	_pickup_t = float(pk.get("first", 50.0)) if not pk.is_empty() and not (pk.get("roster", []) as Array).is_empty() else -1.0
	_apply_mults()
	stage_started.emit(Run.stage)


func stop() -> void:
	running = false


func _apply_mults() -> void:
	var em: EnemyManager = game.enemies
	em.stage_mult = Run.stage_mult()
	em.hp_time_mult = timeline.hp_mult_at(Run.elapsed)


func current_cap() -> int:
	var cap := timeline.cap_at(Run.elapsed)
	if phase == Phase.BOSS:
		return int(cap * 0.3)
	if phase == Phase.PORTAL:
		return int(cap * 0.15)
	return cap


func _process(delta: float) -> void:
	if not running or game.paused:
		return
	if phase == Phase.NORMAL:
		Run.elapsed += delta
		_apply_mults()
		_process_events()
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
		if t >= _endless_next_elite:
			_endless_next_elite = t + 45.0
			_spawn_elite("", "")
		if t >= _endless_next_boss and map.boss != "":
			_endless_next_boss = t + 300.0
			_run_event({"type": "boss", "enemy": map.boss})


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


func _start_boss(id: String) -> void:
	var def: EnemyDef = Registry.enemy(id)
	if def == null:
		return
	phase = Phase.BOSS
	var em: EnemyManager = game.enemies
	var mb: MapBase = game.map
	var at: Vector3 = mb.flats_center + Vector3(0, 0, -10)
	em.spawn_boss(id, at)
	boss_started.emit(def)
	game.toast(def.display_name.to_upper(), Color(0.93, 0.29, 0.36))


func _on_boss_died(def: EnemyDef, at: Vector3) -> void:
	phase = Phase.PORTAL
	game.pickups.spawn_chest(at + Vector3(2.0, 0, 0))
	Save.mark_once("boss_%s_%d" % [map.id, Run.stage + 1])
	QuestTracker.check_run_events()
	portal_ready.emit(at)


## Called by the game when the player chooses to continue through the portal.
func continue_to_next_stage() -> void:
	Run.stage += 1
	if Run.stage >= timeline.stages:
		Run.endless = true
		_endless_next_boss = Run.elapsed + 300.0
		_endless_next_elite = Run.elapsed + 45.0
	phase = Phase.NORMAL
	_apply_mults()
	Run.stage_changed.emit(Run.stage)
	stage_started.emit(Run.stage)


func _spawn_burst() -> void:
	var em: EnemyManager = game.enemies
	var cap := current_cap()
	var room := cap - em.alive_count()
	if room <= 0:
		return
	var roster := timeline.roster_at(Run.elapsed)
	if roster.is_empty():
		return
	var burst: int = min(_rng.randi_range(timeline.burst_min, timeline.burst_max), room)
	var total_w := 0.0
	for r in roster:
		total_w += float(r.get("weight", 1.0))
	while burst > 0:
		var pick := _rng.randf() * total_w
		var chosen: Dictionary = roster[0]
		for r in roster:
			pick -= float(r.get("weight", 1.0))
			if pick <= 0.0:
				chosen = r
				break
		var def: EnemyDef = Registry.enemy(str(chosen.get("enemy", "")))
		if def == null:
			return
		var n: int = min(def.pack_size, burst)
		em.spawn_pack(def.id, _spawn_point(), n)
		burst -= n


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


func _spawn_elite(enemy_id: String, mod_id: String) -> void:
	var em: EnemyManager = game.enemies
	if enemy_id == "":
		var roster := timeline.roster_at(Run.elapsed)
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
		game.toast("ELITE: %s %s" % [mod.display_name, Registry.enemy(enemy_id).display_name], mod.outline)


func _cull_behind() -> void:
	var em: EnemyManager = game.enemies
	var player: Node3D = game.player
	var fwd: Vector3 = player.forward()
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 0 or i == em.boss_index:
			continue
		var d := em.pos[i] - player.global_position
		d.y = 0.0
		if d.length() > 30.0 and d.normalized().dot(fwd) < -0.3:
			var p := _spawn_point()
			em.pos[i] = Vector3(p.x, em._height(p.x, p.z), p.z)
