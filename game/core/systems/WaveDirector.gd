## Reads the map's WaveTimeline and keeps the arena full: a growing live cap, a roster that changes
## over time, scripted elites, swarm rings, and bosses. Owns the stage clock and the portal flow. The cap follows the
## timeline's `cap_curve` (pass 45), the boss fight keeps `boss_cap_frac` of it, and the portal wait keeps `portal_cap`
## load for `portal_spawn_seconds` (-1 / -1 = the stage-end cap for as long as the hero stays out) unless the timeline has
## a `portal_wave` (pass 48: one small wave round the hero as the portal opens, then nothing). Pass 46 stretched Red
## Canyon's clock by 430/300 (stages of 7:10), so every clock here reads the timeline (`stage_length`) instead of a fixed
## number of seconds, and the elite modifiers wait for the run's `colour_after_kills`-th kill.
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
var _portal_t := 0.0   # seconds the portal has waited (the run clock is frozen then; pass 45)
var _endless_next_boss := 0.0
var _endless_next_elite := 0.0
var _endless_next_elite_boss := 0.0
var _endless_wave := 0
var _endless_boss_i := 0   # the endless loop's bosses come in the timeline's order (pass 43)
## Elite-modifier spawns asked for before colour came in (pass 46): {enemy, mod}, released one a second once it has
var _elite_held: Array = []
var _elite_retry := 0.0    # the run clock at which the held ones are asked about again
var elite_index := -1            # the mini-boss while it lives (the HUD points at it)
var _rng := RandomNumberGenerator.new()
var _pickup_t := -1.0          # seconds until the next pickup; negative = none scheduled
var running := false
## The creatures the last portal wave brought (pass 48: tools and tests read it).
var portal_wave_spawned := 0
## The timeline's waves as this run plays them (pass 53, docs/waves_schema.md), one entry per wave in the timeline's
## order: {id, alt (the alternative rolled for this run), spawned, next_t (the run clock of the next burst), toasted,
## done}. Rolled at start() (_roll_waves) with the fresh _rng, never from the map seed (Garry: the alternatives "run
## fresh every run"); a director that never started rolls on its first tick (_ensure_rolled).
var _waves: Array = []
## The events as this run plays them (pass 53): a copy of the timeline's events, each with its effective `t` (its own
## +- `t_jitter`, rolled at start), `_i` its place in the timeline and `_skip` when its `chance` failed, sorted by t then
## _i; _process_events walks it with _event_i. Without jitter or chance it is the timeline's list in the timeline's
## order, so a tool that sets _event_i from the timeline (smoke_run, hell_check, the arena) still lands right.
var _run_events: Array = []
## Bursts one wave may fire in one tick (pass 53): at 60 fps a wave never owes more than one, so more means the clock
## jumped (a tool); past this many the rhythm starts again from now instead of replaying every burst since.
const WAVE_BURSTS_PER_TICK := 8
const SWARM_COLOR := Color(0.94, 0.63, 0.35)


func start(p_map: MapDef) -> void:
	map = p_map
	timeline = p_map.timeline if p_map.timeline else WaveTimeline.new()
	phase = Phase.NORMAL
	_event_i = 0
	_elite_timers.clear()
	_elite_held.clear()
	_elite_retry = 0.0
	_portal_t = 0.0
	_rng.randomize()
	# pass 53: the events' jitter and chance and the waves' alternatives, rolled once for this run
	_roll_events()
	_roll_waves()
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
	# pass 46: beefier creatures (never a boss), colour only after the run's first kills (the arena shows it from the
	# first spawn: it is there to look at the art), and a cap on what one touch takes
	em.creature_hp_mult = timeline.creature_hp_mult
	em.colour_after_kills = 0 if Run.arena else timeline.colour_after_kills
	em.contact_cap = timeline.contact_cap
	# pass 54: every hostile damage times the timeline's creature_damage_mult (1.25 on Red Canyon) and the damage
	# curve's value now (1 without one); the arena plays creatures at their data's damage. EnemyManager carries the two
	# (lane C); set() is a quiet no-op on a manager that has not got them yet
	em.set("creature_damage_mult", 1.0 if Run.arena else timeline.creature_damage_mult)
	em.set("damage_time_mult", timeline.damage_mult_at(Run.elapsed))


## Whether colour may come yet (pass 46): the run has made its first `colour_after_kills` kills (the arena always may).
## An elite modifier is colour, so its spawns wait for this; the crowd's tints and specials wait in EnemyManager.spawn.
func colour_open() -> bool:
	return Run.arena or timeline == null or Run.kills >= timeline.colour_after_kills


## How often endless sends an elite-modded creature: 0.15 of a stage (45 s of a 300 s stage, 64.5 s of Red Canyon's 430
## since pass 46 stretched it; the endless clocks follow the stage instead of fixed seconds), sooner with Hot Sauce.
func _endless_elite_every() -> float:
	return timeline.stage_length * 0.15 / elite_pace()


## Hot Sauce (pass 47, Garry: "how likely Player is to get coloured enemies"): the coloured Elites' clocks (the
## timeline's elite_every timers and endless's) run 1 + 0.5 x the hero's `difficulty` times as fast.
func elite_pace() -> float:
	var d: float = Run.player_sheet.get_stat("difficulty", 0.0) if Run.player_sheet else 0.0
	return 1.0 + 0.5 * maxf(d, 0.0)


## When an elite_every timer that fired at `t` fires next: its `interval` later, shortened by Hot Sauce (pass 47).
func next_elite_at(t: float, interval: float) -> float:
	return t + interval / elite_pace()


func current_cap() -> int:
	var cap := timeline.cap_at(Run.elapsed, Run.stage)
	if phase == Phase.BOSS:
		return int(cap * timeline.boss_cap_frac)
	if phase == Phase.PORTAL:
		# pass 48 (Garry: "after the boss dies we spawn a small wave and that's it"): a timeline with a portal wave sent it
		# as the portal opened (spawn_portal_wave), and nothing comes after it until the hero walks through
		if has_portal_wave():
			return 0
		# between stages (pass 45): `portal_cap` load for `portal_spawn_seconds`, then nothing until the hero walks
		# through; -1 / -1 keeps the stage-end cap up for as long as the portal waits (the hero keeps killing and earning)
		if timeline.portal_spawn_seconds >= 0.0 and _portal_t >= timeline.portal_spawn_seconds:
			return 0
		return cap if timeline.portal_cap < 0 else timeline.portal_cap
	return cap


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	if not running or game.paused:
		# the debug arena holds the director, and with it the stage clock: the buffs' clock runs on regardless (pass 49,
		# Garry: "Pollen should only last 5 seconds, not forever": in the arena no timed buff ever ran out)
		if not running and Run.arena and not game.paused:
			Run.held_time += delta
		Perf.add("director", _t0)
		return
	if phase == Phase.NORMAL:
		Run.elapsed += delta
		_apply_mults()
		_process_events()
		if phase == Phase.NORMAL:
			# the timeline's waves (pass 53) run in the normal phase only: an event above may just have started a boss
			_tick_waves()
		# the path slots: a stage puts a weapon's whole path on the table at set seconds into it
		if Run.path_due(Run.elapsed - float(Run.stage) * timeline.stage_length) and game.has_method("present_path_offer"):
			game.present_path_offer()
	elif phase == Phase.PORTAL:
		_portal_t += delta
	if phase != Phase.NORMAL:
		# the stage clock stands still; the buffs' clock does not (Run.buff_clock, pass 47)
		Run.held_time += delta
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
	_ensure_rolled()
	while _event_i < _run_events.size():
		var ev: Dictionary = _run_events[_event_i]
		if float(ev.get("t", 0.0)) > t:
			break
		_event_i += 1
		if bool(ev.get("_skip", false)):
			# its `chance` failed this run (pass 53)
			continue
		_run_event(ev)
		if phase != Phase.NORMAL:
			return
	for et in _elite_timers:
		if t >= float(et["next"]):
			if not colour_open():
				# colour comes after the run's first kills (pass 46): the timer keeps its Elite and asks again in a second
				et["next"] = t + 1.0
				continue
			# a fresh interval every firing when the event gave [min, max] (pass 53)
			et["next"] = next_elite_at(t, _interval_of(et["interval"]))
			_spawn_elite(_pick_id(et.get("enemy", ""), et.get("weights", [])), str(et.get("mod", "")), str(et.get("variant", "")), _stats_of(et))
	if not _elite_held.is_empty() and t >= _elite_retry:
		# an elite spawn asked for before colour came in goes out now, one a second
		_elite_retry = t + 1.0
		if colour_open():
			var h: Dictionary = _elite_held.pop_front()
			_spawn_elite(str(h.get("enemy", "")), str(h.get("mod", "")), str(h.get("variant", "")), _stats_of(h))
	if Run.endless:
		# every wave (the timeline's endless_wave_seconds: 86 s on Red Canyon since pass 46) the crowd gets
		# endless_wave_mult tougher, compounding (pass 43); the multipliers follow through _apply_mults, this is the
		# announcement
		var wave := Run.endless_wave()
		if wave != _endless_wave:
			_endless_wave = wave
			if wave > 1:
				game.toast("WAVE %d · ×%.2f" % [wave, Run.stage_mult()], Color(0.93, 0.29, 0.36))
		if t >= _endless_next_elite:
			if colour_open():
				_endless_next_elite = t + _endless_elite_every()
				_spawn_elite("", "")
			else:
				# held a second at a time while colour waits (never, in practice, this late in a run)
				_endless_next_elite = t + 1.0
		if t >= _endless_next_boss and map.boss != "":
			# a boss a stage, a mini-boss half way between (pass 46: from the stage length; it was 300 and 150 s)
			_endless_next_boss = t + timeline.stage_length
			_endless_next_elite_boss = t + timeline.stage_length * 0.5
			_run_event({"type": "boss", "enemy": _endless_boss_id()})
		if _endless_next_elite_boss > 0.0 and t >= _endless_next_elite_boss and _endless_elite_id() != "":
			_endless_next_elite_boss = 0.0
			_run_event({"type": "elite_boss", "enemy": _endless_elite_id()})


## Seconds until the next boss event, or -1 when none is scheduled. The HUD counts it down. Pass 53: it reads the run's
## own copy of the events when there is one (a boss with `t_jitter` comes at its rolled time and the count says so; one
## whose `chance` failed is not counted down to), the timeline's list before a run has rolled.
func next_boss_in() -> float:
	if timeline == null:
		return -1.0
	var t: float = Run.elapsed
	if Run.endless:
		return _endless_next_boss - t
	var best := -1.0
	var list: Array = _run_events if _run_events.size() == timeline.events.size() else timeline.events
	for ev in list:
		if str(ev.get("type", "")) == "boss" and not bool(ev.get("_skip", false)):
			var et := float(ev.get("t", 0.0))
			if et > t and (best < 0.0 or et - t < best):
				best = et - t
	return best


func _run_event(ev: Dictionary) -> void:
	# pass 53: every type may carry an art `variant` and `stats` overrides for what it spawns, and `enemy` may be a list
	# with `weights`
	var variant := str(ev.get("variant", ""))
	var stats := _stats_of(ev)
	match str(ev.get("type", "")):
		"elite":
			_spawn_elite(_pick_id(ev.get("enemy", ""), ev.get("weights", [])), str(ev.get("mod", "")), variant, stats)
		"elite_every":
			# `interval` may be [min, max] (pass 53): a fresh draw every firing (_interval_of)
			_elite_timers.append({"next": Run.elapsed, "interval": ev.get("interval", 90.0), "enemy": ev.get("enemy", ""),
				"weights": ev.get("weights", []), "mod": str(ev.get("mod", "")), "variant": variant, "stats": stats})
		"swarm":
			var em: EnemyManager = game.enemies
			var id := _pick_id(ev.get("enemy", ""), ev.get("weights", []))
			if id == "" and not map.skins.is_empty():
				id = map.skins.values()[0]
			var count := int(ev.get("count", 40))
			match str(ev.get("pattern", "ring")):
				"pack", "scatter":
					# through the spawn points instead of the ring (pass 53), still on top of the cap like the ring
					_spawn_group(id, count, str(ev["pattern"]), int(ev.get("pack", 0)), null, variant, stats)
				_:
					em.spawn_ring(id, count, game.player.global_position, 16.0, variant, stats)
			game.toast("SWARM!", SWARM_COLOR)
		"boss":
			_start_boss(_pick_id(ev.get("enemy", map.boss), ev.get("weights", [])), Vector3.INF, variant, stats)
		"elite_boss":
			# `enemy` may be a list: one of them, at random (the scorpion or the djinn), by `weights` when given
			_spawn_elite_boss(_pick_id(ev.get("enemy", ""), ev.get("weights", [])), variant, stats)


func _start_boss(id: String, where: Vector3 = Vector3.INF, variant := "", stats := {}) -> void:
	var def: EnemyDef = Registry.enemy(id)
	if def == null:
		return
	phase = Phase.BOSS
	var em: EnemyManager = game.enemies
	var mb: MapBase = game.map
	# the arena may name the spot; the timeline's boss comes up on the flats
	var at: Vector3 = mb.flats_center + Vector3(0, 0, -10) if where == Vector3.INF else where
	em.spawn_boss(id, at, variant, stats)
	boss_started.emit(def)
	game.toast(def.display_name.to_upper(), Color(0.93, 0.29, 0.36))


## The mini-boss: one big creature near the hero, a toast and nothing else. Its chest comes from its drops.
func _spawn_elite_boss(id: String, variant := "", stats := {}) -> void:
	var def: EnemyDef = Registry.enemy(id)
	if def == null:
		return
	var em: EnemyManager = game.enemies
	# where the hero is headed, as before the spawn sides (pass 54: the schema keeps the Elite bosses on the old rule)
	var i := em.spawn(id, _facing_point(), null, 1.0, 1.0, variant, stats)
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


## One id from `v`: a string as it is; from a list one at random, by the parallel `weights` list when one is given (pass
## 53; an entry past the end of the weights weighs 1), else evenly.
func _pick_id(v, weights = []) -> String:
	if v is Array and not (v as Array).is_empty():
		var ids: Array = v
		if weights is Array and not (weights as Array).is_empty():
			var ws: Array = weights
			var total := 0.0
			for k in range(ids.size()):
				total += maxf(float(ws[k]) if k < ws.size() else 1.0, 0.0)
			if total > 0.0:
				var pick := _rng.randf() * total
				var last := ""
				for k in range(ids.size()):
					var wk := maxf(float(ws[k]) if k < ws.size() else 1.0, 0.0)
					if wk <= 0.0:
						# a weight of 0 is never drawn (randf() may return exactly 0)
						continue
					last = str(ids[k])
					pick -= wk
					if pick <= 0.0:
						return last
				return last
		return str(ids[_rng.randi() % ids.size()])
	return str(v)


## An elite_every timer's interval for this firing (pass 53): a number as it is, [min, max] a fresh draw inside it.
func _interval_of(v) -> float:
	if v is Array and not (v as Array).is_empty():
		var iv: Array = v
		return _rng.randf_range(float(iv[0]), float(iv[iv.size() - 1]))
	return float(v) if v != null else 90.0


## The `stats` overrides a row, an alt or an event carries (pass 53), {} when none.
static func _stats_of(d: Dictionary) -> Dictionary:
	var s = d.get("stats", {})
	return s if s is Dictionary else {}


## A roster row's creature as it spawns (pass 53): with the row's art `variant` and `stats` on it (Registry caches the
## copies), null for an unknown creature.
static func _row_def(r: Dictionary) -> EnemyDef:
	return Registry.enemy_with(str(r.get("enemy", "")), str(r.get("variant", "")), _stats_of(r))


## `n` creatures of `id` through the spawn points (pass 53, the roster's and the waves' `pattern`): "pack" puts them at
## one point (`pack` or more of them in several packs, each at its own point; pack 0 = all together), "scatter" and
## "single" each at a point of its own. `point` picks the points (`_spawn_point` when not given; the portal wave hands
## `_around_point`). Returns how many came.
func _spawn_group(id: String, n: int, pattern: String, pack: int, mod: EliteModDef, variant: String, stats: Dictionary, point: Callable = Callable()) -> int:
	var em: EnemyManager = game.enemies
	if not point.is_valid():
		point = _spawn_point
	var came := 0
	if pattern == "scatter" or pattern == "single":
		for k in range(n):
			if em.spawn(id, point.call(), mod, 1.0, 1.0, variant, stats) >= 0:
				came += 1
		return came
	var left := n
	var chunk: int = pack if pack > 0 else n
	while left > 0:
		var m: int = mini(chunk, left)
		came += em.spawn_pack(id, point.call(), m, mod, variant, stats)
		left -= m
	return came


## Position of the living mini-boss, or Vector3.INF when none.
func elite_position() -> Vector3:
	var em: EnemyManager = game.enemies
	if elite_index >= 0 and em.is_alive(elite_index) and (em.types[em.type_idx[elite_index]]["def"] as EnemyDef).archetype == "elite":
		return em.pos[elite_index]
	elite_index = -1
	return Vector3.INF


func _on_boss_died(def: EnemyDef, at: Vector3) -> void:
	phase = Phase.PORTAL
	_portal_t = 0.0
	# the boss's own chest: it holds a mutation, and opening it is what calls every gem, coin and chest in (pass 30)
	game.pickups.spawn_chest(at + Vector3(2.0, 0, 0), true)
	Save.mark_once("boss_%s_%d" % [map.id, Run.stage + 1])
	QuestTracker.check_run_events()
	portal_ready.emit(at)
	spawn_portal_wave()


## Whether the timeline sends one wave as the portal opens instead of keeping the crowd up (pass 48, `portal_wave`).
func has_portal_wave() -> bool:
	return timeline != null and int(timeline.portal_wave.get("count", 0)) > 0


## The portal's one wave (pass 48, the timeline's `portal_wave` {count}): `count` creatures of the roster as it stood at
## the stage's end (the regular rows; the frozen clock sits a hair past the boundary, so it is read a second early as
## the bursts read it) come in packs from all round the hero, and current_cap keeps everything else away until he steps
## through. Held, like every spawn, while the director is (the arena). Returns how many came.
func spawn_portal_wave() -> int:
	portal_wave_spawned = 0
	if not running or not has_portal_wave() or game == null or game.player == null:
		return 0
	var em: EnemyManager = game.enemies
	var rows: Array = _roster_open(timeline.roster_at(Run.elapsed - 1.0).filter(func(r: Dictionary) -> bool: return str(r.get("channel", "")) != "hell"))
	if rows.is_empty():
		return 0
	var left: int = mini(int(timeline.portal_wave.get("count", 0)), timeline.hard_cap - em.alive_count())
	var before: int = em.alive_count()
	var guard := 0
	while left > 0 and guard < 64:
		guard += 1
		# the row's pack, pattern, variant and overrides (pass 53), round the hero instead of ahead of him
		var row: Dictionary = _weighted_row(rows)
		var def: EnemyDef = _row_def(row)
		if def == null:
			break
		var pack: int = maxi(int(row.get("pack", def.pack_size)), 1)
		var pattern := str(row.get("pattern", "pack"))
		var n: int = mini(pack, left) if pattern != "single" else 1
		_spawn_group(def.id, n, pattern, pack, null, str(row.get("variant", "")), _stats_of(row), _around_point)
		left -= n
	portal_wave_spawned = maxi(em.alive_count() - before, 0)
	return portal_wave_spawned


## One roster row drawn by its weight now (_roster_weight); a row at weight 0 is never drawn (pass 54: a presence
## keyframe at 0 is a row that is not there yet), {} when every row is at 0.
func _weighted_row(rows: Array) -> Dictionary:
	var total := 0.0
	for r in rows:
		total += _roster_weight(r, Run.elapsed)
	if total <= 0.0:
		return {}
	var pick := _rng.randf() * total
	var last: Dictionary = {}
	for r in rows:
		var w := _roster_weight(r, Run.elapsed)
		if w <= 0.0:
			continue
		last = r
		pick -= w
		if pick <= 0.0:
			return r
	return last


## A spot all round the hero, just off his screen (the portal wave comes from every side, not mostly ahead).
func _around_point() -> Vector3:
	var player: Node3D = game.player
	var mb: MapBase = game.map
	var a := _rng.randf() * TAU
	var p: Vector3 = player.global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(15.0, 20.0)
	return mb.clamp_to_arena(p) if mb else p


## Called by the game when the player chooses to continue through the portal.
func continue_to_next_stage() -> void:
	Run.stage += 1
	Run.path_slot = 0
	if Run.stage >= timeline.stages:
		Run.endless = true
		_endless_wave = 1
		_endless_boss_i = 0
		_endless_next_boss = Run.elapsed + timeline.stage_length
		_endless_next_elite = Run.elapsed + _endless_elite_every()
		_endless_next_elite_boss = Run.elapsed + timeline.stage_length * 0.5
	phase = Phase.NORMAL
	_apply_mults()
	Run.stage_changed.emit(Run.stage)
	stage_started.emit(Run.stage)


func _spawn_burst() -> void:
	var em: EnemyManager = game.enemies
	var cap := current_cap()
	if cap <= 0:
		return
	# the frozen clock sits a hair past the stage boundary through the boss fight and the portal wait, so the rows dated
	# exactly on it (the mummy at 430, the shaman at 860 on Red Canyon since pass 46) wait for their stage (pass 45)
	var all := timeline.roster_at(Run.elapsed if phase == Phase.NORMAL else Run.elapsed - 1.0)
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
	if roster.is_empty():
		return bodies
	var burst: float = minf(float(_rng.randi_range(timeline.burst_min, timeline.burst_max)), room)
	var total_w := 0.0
	var ws: Array = []
	for r in roster:
		ws.append(_roster_weight(r, Run.elapsed))
		total_w += ws[ws.size() - 1]
	if total_w <= 0.0:
		# every open row is at weight 0 now (pass 54: a presence keyframe at 0 is a row that is not there yet)
		return bodies
	while burst > 0.0 and bodies > 0:
		var pick := _rng.randf() * total_w
		var chosen: Dictionary = roster[0]
		for k in range(roster.size()):
			if float(ws[k]) <= 0.0:
				# a row at weight 0 is never drawn (randf() may return exactly 0)
				continue
			chosen = roster[k]
			pick -= float(ws[k])
			if pick <= 0.0:
				break
		# the row's creature with its overrides (pass 53): its cap_share, pack and numbers may be the row's own
		var def: EnemyDef = _row_def(chosen)
		if def == null:
			return bodies
		var share: float = maxf(def.cap_share, 0.05)
		# the row's `pack` and `pattern` (pass 53): a pack at one point, a scatter each at its own, a single one a draw
		var pattern := str(chosen.get("pattern", "pack"))
		var pack: int = maxi(int(chosen.get("pack", def.pack_size)), 1)
		var n: int = mini(mini(pack, maxi(int(ceil(burst / share)), 1)), bodies)
		if pattern == "single":
			n = 1
		_spawn_group(def.id, n, pattern, pack, null, str(chosen.get("variant", "")), _stats_of(chosen))
		burst -= float(n) * share
		bodies -= n
	return bodies


## The hell channel's living creatures against its cap (each its cap_share), from its roster rows and, pass 53, from the
## hell waves open now (a creature id is hell while any hell row or hell wave of the moment brings it; every one of that
## id counts, whatever brought it, as the rows always did). Each creature counts its own type's share (EnemyManager.load_of:
## an overridden copy may carry its own cap_share).
func _hell_load(rows: Array) -> float:
	var em: EnemyManager = game.enemies
	var load := 0.0
	var seen: Dictionary = {}
	for r in rows:
		seen[str(r.get("enemy", ""))] = true
	for id: String in _hell_wave_ids():
		seen[id] = true
	for id: String in seen.keys():
		if Registry.enemy(id):
			load += em.load_of(id)
	return load


## The creature ids the hell waves bring right now (pass 53): the rolled alt of every wave on the hell channel whose
## window is open (t reached, until not, not spent).
func _hell_wave_ids() -> Array:
	var out: Array = []
	if timeline == null or timeline.waves.is_empty():
		return out
	_ensure_rolled()
	var t := Run.elapsed
	for k in range(_waves.size()):
		var ws: Dictionary = _waves[k]
		var w: Dictionary = timeline.waves[k] if timeline.waves[k] is Dictionary else {}
		if str(w.get("channel", "regular")) != "hell" or bool(ws.get("done", false)):
			continue
		if t < float(w.get("t", 0.0)) or (w.has("until") and t >= float(w["until"])):
			continue
		var id := str((ws["alt"] as Dictionary).get("enemy", ""))
		if id != "" and not out.has(id):
			out.append(id)
	return out


## The hell channel's rows in the roster now (the arena's WAVES tab and the tests).
func hell_rows() -> Array:
	return timeline.roster_at(Run.elapsed).filter(func(r: Dictionary) -> bool: return str(r.get("channel", "")) == "hell")


# ---------------------------------------------------------------- the waves and the run's roll (pass 53)

## The run's copies of the events and the waves exist (a director that never ran start(): the tests, a tool) and match
## the timeline's lists; rolled here when not.
func _ensure_rolled() -> void:
	if _run_events.size() != timeline.events.size():
		_roll_events()
	if _waves.size() != timeline.waves.size():
		_roll_waves()


## This run's events (pass 53): each timeline event copied with its effective `t` (its own plus a draw inside
## +- `t_jitter`, never below 0), `_i` its place in the timeline and `_skip` when its `chance` (0..1, default 1) failed,
## in order of t then _i. A skipped event stays in the list so the indices keep to the timeline's where nothing is jittered.
func _roll_events() -> void:
	_run_events.clear()
	for k in range(timeline.events.size()):
		var src = timeline.events[k]
		var e: Dictionary = (src as Dictionary).duplicate() if src is Dictionary else {}
		e["_i"] = k
		var jitter := float(e.get("t_jitter", 0.0))
		if jitter > 0.0:
			e["t"] = maxf(float(e.get("t", 0.0)) + _rng.randf_range(-jitter, jitter), 0.0)
		var chance := float(e.get("chance", 1.0))
		if chance < 1.0 and _rng.randf() >= chance:
			e["_skip"] = true
		_run_events.append(e)
	_run_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a.get("t", 0.0))
		var tb := float(b.get("t", 0.0))
		return ta < tb if ta != tb else int(a.get("_i", 0)) < int(b.get("_i", 0)))


## Steps _event_i past every event of this run dated before `t` (pass 53): the tools that jump the clock (smoke_run,
## hell_check, perf_late, the arena's WAVES tab) can use this instead of counting the timeline's events themselves.
func skip_events_before(t: float) -> void:
	_ensure_rolled()
	_event_i = 0
	while _event_i < _run_events.size() and float(_run_events[_event_i].get("t", 0.0)) < t:
		_event_i += 1


## This run's waves (pass 53): one state per timeline wave, in order, with the alternative rolled for it by `chance`
## (the chances are normalised; a wave without `alts` is its own one alternative: its enemy / variant / pack / stats).
func _roll_waves() -> void:
	_waves.clear()
	for k in range(timeline.waves.size()):
		var src = timeline.waves[k]
		if not (src is Dictionary):
			_waves.append({"id": "w%d" % k, "alt": {}, "spawned": 0, "next_t": 0.0, "toasted": false, "done": true})
			continue
		var w: Dictionary = src
		var alt: Dictionary = {}
		var alts: Array = w.get("alts", []) if w.get("alts") is Array else []
		alts = alts.filter(func(a) -> bool: return a is Dictionary)
		if alts.is_empty():
			for key: String in ["enemy", "variant", "pack", "stats"]:
				if w.has(key):
					alt[key] = w[key]
		else:
			var total := 0.0
			for a: Dictionary in alts:
				total += maxf(float(a.get("chance", 1.0)), 0.0)
			alt = alts[0]
			if total > 0.0:
				var pick := _rng.randf() * total
				for a: Dictionary in alts:
					var c := maxf(float(a.get("chance", 1.0)), 0.0)
					if c <= 0.0:
						# a chance of 0 never comes up (randf() may return exactly 0)
						continue
					alt = a
					pick -= c
					if pick <= 0.0:
						break
		_waves.append({"id": str(w.get("id", "w%d" % k)), "alt": alt, "spawned": 0, "next_t": float(w.get("t", 0.0)), "toasted": false, "done": false})


## The run's state of the wave called `id` (pass 53; the tests and the arena): {id, alt, spawned, next_t, toasted, done}
## as a copy, {} for an unknown wave.
func wave_state(id: String) -> Dictionary:
	if timeline == null:
		return {}
	_ensure_rolled()
	for ws: Dictionary in _waves:
		if str(ws.get("id", "")) == id:
			return ws.duplicate(true)
	return {}


## The waves' tick (pass 53, from _process in the normal phase): every wave whose `t` the run clock has reached, whose
## `until` it has not, and whose `count` is not full fires a burst each time the clock passes its next_t, then waits
## `every` (`every` <= 0: one burst, and the wave is spent once it has come). A burst that found no room (the cap, the
## hard cap, no creature) leaves next_t where the rhythm says (or, for a one-burst wave, a spawn interval on), so it
## tries again then. A clock that jumped (a tool) fires at most WAVE_BURSTS_PER_TICK and starts the rhythm again from now.
func _tick_waves() -> void:
	if timeline == null or timeline.waves.is_empty() or game == null or game.player == null:
		return
	_ensure_rolled()
	var t := Run.elapsed
	for k in range(_waves.size()):
		var ws: Dictionary = _waves[k]
		if bool(ws.get("done", false)) or not (timeline.waves[k] is Dictionary):
			continue
		var w: Dictionary = timeline.waves[k]
		if t < float(w.get("t", 0.0)):
			continue
		if w.has("until") and t >= float(w["until"]):
			ws["done"] = true
			continue
		var count := int(w.get("count", 0))
		if count > 0 and int(ws["spawned"]) >= count:
			ws["done"] = true
			continue
		var every := float(w.get("every", 0.0))
		var fired := 0
		while t >= float(ws["next_t"]) and fired < WAVE_BURSTS_PER_TICK:
			fired += 1
			var came := _wave_burst(w, ws)
			if every <= 0.0:
				if came > 0:
					ws["done"] = true
				else:
					ws["next_t"] = t + timeline.spawn_interval
				break
			ws["next_t"] = float(ws["next_t"]) + every
			if count > 0 and int(ws["spawned"]) >= count:
				ws["done"] = true
				break
		if not bool(ws["done"]) and fired >= WAVE_BURSTS_PER_TICK and t >= float(ws["next_t"]):
			ws["next_t"] = t


## One burst of wave `w` in state `ws` (pass 53): `burst` creatures of the rolled alt, cut to what `count` still owes,
## to the hard cap's room and, when `respect_cap` (the default), to the free room of the wave's `channel` ("regular" |
## "hell") in load units as _spawn_burst reckons it; by the wave's `pattern` through the spawn points (packs of the alt's
## `pack`); every one wearing the wave's `elite` modifier ("random" = any) once colour is open (plain before, like the
## elite events); the `toast` once, at the first burst that brought anything. Returns how many came.
func _wave_burst(w: Dictionary, ws: Dictionary) -> int:
	var alt: Dictionary = ws["alt"]
	var id := str(alt.get("enemy", ""))
	var variant := str(alt.get("variant", ""))
	var stats := _stats_of(alt)
	var def: EnemyDef = Registry.enemy_with(id, variant, stats)
	if def == null:
		ws["done"] = true
		return 0
	var em: EnemyManager = game.enemies
	var n: int = maxi(int(w.get("burst", 5)), 1)
	var count := int(w.get("count", 0))
	if count > 0:
		n = mini(n, count - int(ws["spawned"]))
	n = mini(n, timeline.hard_cap - em.alive_count())
	if bool(w.get("respect_cap", true)):
		var room := _channel_room(str(w.get("channel", "regular")))
		if room <= 0.0:
			return 0
		n = mini(n, maxi(int(ceil(room / maxf(def.cap_share, 0.05))), 1))
	if n <= 0:
		return 0
	var mod: EliteModDef = null
	var el := str(w.get("elite", ""))
	if el != "" and colour_open():
		if el == "random":
			var list := Registry.elites_list()
			if not list.is_empty():
				mod = list[_rng.randi() % list.size()]
		else:
			mod = Registry.elites.get(el)
	var came := _spawn_group(id, n, str(w.get("pattern", "pack")), int(alt.get("pack", def.pack_size)), mod, variant, stats)
	if came > 0:
		ws["spawned"] = int(ws["spawned"]) + came
		if not bool(ws["toasted"]) and str(w.get("toast", "")) != "":
			ws["toasted"] = true
			game.toast(str(w["toast"]), SWARM_COLOR)
	return came


## The free room of a spawn channel right now in load units (pass 53), as _spawn_burst reckons it: the regular cap less
## the regular load (everything that is not hell), or the hell channel's share of the cap less the hell load.
func _channel_room(channel: String) -> float:
	var em: EnemyManager = game.enemies
	var cap := current_cap()
	var hell_load := _hell_load(hell_rows())
	if channel == "hell":
		return timeline.hell_cap_at(Run.stage) * float(cap) - hell_load
	return float(cap) - (em.cap_load() - hell_load)


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
	if Run.stage == 0 and Run.elapsed < float(sp.get("from", timeline.stage_length * 0.5)):
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


## The roster without the rows whose creature is at its live limit (`max_alive`: the harpooner is never more than one).
func _roster_open(rows: Array) -> Array:
	var em: EnemyManager = game.enemies
	var out: Array = []
	for r in rows:
		# the row's own max_alive when its stats set one (pass 53); alive_of counts every type of the creature
		var def: EnemyDef = _row_def(r)
		if def and def.max_alive > 0 and em.alive_of(def.id) >= def.max_alive:
			continue
		out.append(r)
	return out


## A roster row's weight at time `t`: its `weights` presence keyframes when it has them (pass 54, [[t, w], ...]: linear
## between the points, flat before the first and after the last, WaveTimeline.sample_points), else the old slide:
## `weight` when it arrives, sliding to `weight_late` (when the row has one) by the timeline's `weight_late_t` (the end
## of stage 2: 860 s on Red Canyon since pass 46), so the fodder thins out as the harder creatures take over.
func _roster_weight(r: Dictionary, t: float) -> float:
	var ws = r.get("weights")
	if ws is Array and not (ws as Array).is_empty():
		return maxf(WaveTimeline.sample_points(ws, t), 0.0)
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
	# pass 53 (the wave schema): the creature's own roster of power-ups when it has one ({id: weight}, no hard bias),
	# and its own factor on the per-kill chance
	if not def.pickup_weights.is_empty():
		roster = []
		for id in def.pickup_weights.keys():
			roster.append({"id": str(id), "weight": float(def.pickup_weights[id])})
	var per_kill := float(pk.get("per_kill", 0.0)) * def.pickup_chance_mult
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


## The four screen sides a spawn may come from (pass 54) and the turn of each side's axis from the camera's forward in
## the hero's yaw convention (0 = -Z; screen right is the camera's right, -PI/2 of it; left +PI/2; bottom PI).
const SIDES := ["top", "bottom", "left", "right"]
const SIDE_TURN := {"top": 0.0, "bottom": PI, "left": PI * 0.5, "right": -PI * 0.5}
## Half the arc round a side's axis a spawn point may land in (45 degrees: the four arcs tile the circle).
const SIDE_HALF_ARC := PI * 0.25


## A spawn point for the roster's bursts, the waves, the specials, a random Elite and a creature moved up from far
## behind (_cull_behind): 19-24 m from the hero, clamped to the arena, in the direction the timeline's `spawn_sides`
## picks (pass 54, Garry: 55 / 15 / 15 / 15 top / bottom / left / right). "sides" mode draws a screen side by its weight
## (in camera space: top is up the screen, north under the fixed camera), then an angle within 45 degrees of that side's
## axis; "facing" mode, a timeline without the block and a sides block whose weights are all zero play the old rule
## (_facing_angle). The Elite bosses keep the old rule whatever the block says (_facing_point).
func _spawn_point() -> Vector3:
	return _point_at(_spawn_angle())


## The old rule's point (pass 54: the Elite bosses are placed as before, docs/waves_schema.md).
func _facing_point() -> Vector3:
	return _point_at(_facing_angle(timeline.spawn_sides if timeline else {}))


## A point 19-24 m from the hero towards the yaw `a` (the hero's `facing` convention: 0 = -Z), clamped to the arena.
func _point_at(a: float) -> Vector3:
	var player: Node3D = game.player
	var mb: MapBase = game.map
	var r := _rng.randf_range(19.0, 24.0)
	var dir := Vector3(-sin(a), 0, -cos(a))
	var p: Vector3 = player.global_position + dir * r
	return mb.clamp_to_arena(p)


## The yaw of the next spawn point (_spawn_point): 0 = -Z, the hero's `facing` convention.
func _spawn_angle() -> float:
	var ss: Dictionary = timeline.spawn_sides if timeline else {}
	if str(ss.get("mode", "facing")) == "sides":
		var side := _pick_side(ss)
		if side != "":
			# the camera's yaw (0 under the fixed camera: screen up is north), so follow mode keeps its sides too
			var yaw: float = game.camera.current_yaw() if game.get("camera") and game.camera and game.camera.has_method("current_yaw") else 0.0
			return yaw + float(SIDE_TURN[side]) + _rng.randf_range(-SIDE_HALF_ARC, SIDE_HALF_ARC)
	return _facing_angle(ss)


## The old rule's yaw: `facing_share` (0.7) of the points within `facing_spread_deg` (60) of where the hero faces, the
## rest anywhere round him (the block's numbers when `ss` names them).
func _facing_angle(ss: Dictionary) -> float:
	var player: Node3D = game.player
	if _rng.randf() < float(ss.get("facing_share", 0.7)):
		var spread := deg_to_rad(float(ss.get("facing_spread_deg", 60.0)))
		return float(player.facing) + _rng.randf_range(-spread, spread)
	return _rng.randf() * TAU


## One of the four sides by the block's weights (a missing side weighs 0, a weight of 0 never comes up), "" when they
## are all zero or missing.
func _pick_side(ss: Dictionary) -> String:
	var total := 0.0
	for s: String in SIDES:
		total += maxf(float(ss.get(s, 0.0)), 0.0)
	if total <= 0.0:
		return ""
	var pick := _rng.randf() * total
	var last := ""
	for s: String in SIDES:
		var w := maxf(float(ss.get(s, 0.0)), 0.0)
		if w <= 0.0:
			continue
		last = s
		pick -= w
		if pick <= 0.0:
			return s
	return last


## The roster rows an elite modifier may land on: only a creature that can be an Elite (a cactus cannot, nor a special),
## from a row whose `elite_weight` is not 0 (pass 54: the row's own "never").
static func elite_candidates(rows: Array) -> Array:
	return rows.filter(func(r: Dictionary) -> bool:
		var d: EnemyDef = _row_def(r)
		return d != null and d.can_be_elite and d.elite_weight > 0.0)


## One Elite candidate row drawn by its `elite_weight` (pass 54: every row weighs 1 unless its stats say; it was an
## even draw).
func _weighted_elite_row(rows: Array) -> Dictionary:
	var total := 0.0
	var ws: Array = []
	for r in rows:
		var d: EnemyDef = _row_def(r)
		var w: float = maxf(d.elite_weight, 0.0) if d else 0.0
		ws.append(w)
		total += w
	if total <= 0.0:
		return rows[_rng.randi() % rows.size()]
	var pick := _rng.randf() * total
	var last: Dictionary = rows[rows.size() - 1]
	for k in range(rows.size()):
		if float(ws[k]) <= 0.0:
			continue
		last = rows[k]
		pick -= float(ws[k])
		if pick <= 0.0:
			return rows[k]
	return last


## The ways an elite-modified creature may arrive (pass 54) and the ring's radius round the hero.
const ELITE_FORMATS := ["single", "pack", "ring"]
const ELITE_RING_RADIUS := 12.0


## How an elite-modified creature of `def` arrives (pass 54): one of its row's `elite_formats` {single, pack, ring} by
## their chances (normalised; a chance of 0 never comes up), "single" for a creature whose row says nothing.
func _elite_format(def: EnemyDef) -> String:
	var ef: Dictionary = def.elite_formats
	var total := 0.0
	for f: String in ELITE_FORMATS:
		total += maxf(float(ef.get(f, 0.0)), 0.0)
	if total <= 0.0:
		return "single"
	var pick := _rng.randf() * total
	var last := "single"
	for f: String in ELITE_FORMATS:
		var c := maxf(float(ef.get(f, 0.0)), 0.0)
		if c <= 0.0:
			continue
		last = f
		pick -= c
		if pick <= 0.0:
			return f
	return last


## `n` of a creature, every one wearing `mod`, on a ring of ELITE_RING_RADIUS round the hero (pass 54, the "ring"
## elite format; EnemyManager.spawn_ring takes no modifier). Returns how many came.
func _spawn_elite_ring(id: String, n: int, mod: EliteModDef, variant: String, stats: Dictionary) -> int:
	var em: EnemyManager = game.enemies
	var mb: MapBase = game.map
	var center: Vector3 = game.player.global_position
	var came := 0
	var turn := _rng.randf() * TAU
	for k in range(n):
		var a := turn + TAU * float(k) / float(maxi(n, 1)) + _rng.randf_range(-0.1, 0.1)
		var p := center + Vector3(cos(a), 0, sin(a)) * ELITE_RING_RADIUS
		if em.spawn(id, mb.clamp_to_arena(p) if mb else p, mod, 1.0, 1.0, variant, stats) >= 0:
			came += 1
	return came


## Creatures wearing an elite modifier: a roster creature drawn by its row's `elite_weight` (pass 54; it was an even
## draw) and a random modifier unless named, arriving as the row's `elite_formats` say: alone (the default), as its
## whole pack every one wearing the modifier, or as a ring of `pack` of them round the hero; one toast whichever way.
## Before the run's `colour_after_kills`-th kill it is held, not dropped (pass 46): _process_events lets it out once
## colour is open.
func _spawn_elite(enemy_id: String, mod_id: String, variant := "", stats := {}) -> void:
	if not colour_open():
		_elite_held.append({"enemy": enemy_id, "mod": mod_id, "variant": variant, "stats": stats})
		return
	var em: EnemyManager = game.enemies
	var row: Dictionary = {}
	if enemy_id == "":
		var roster := elite_candidates(_roster_open(timeline.roster_at(Run.elapsed)))
		if roster.is_empty():
			return
		# a roster creature comes as its row spawns it (pass 53: the row's variant and overrides)
		row = _weighted_elite_row(roster)
		enemy_id = str(row.get("enemy", ""))
		if variant == "":
			variant = str(row.get("variant", ""))
		if stats.is_empty():
			stats = _stats_of(row)
	var mod: EliteModDef = Registry.elites.get(mod_id)
	if mod == null:
		var list := Registry.elites_list()
		if list.is_empty():
			return
		mod = list[_rng.randi() % list.size()]
	var def: EnemyDef = Registry.enemy_with(enemy_id, variant, stats)
	if def == null:
		return
	var pack: int = maxi(int(row.get("pack", def.pack_size)), 1)
	var came := 0
	match _elite_format(def):
		"pack":
			came = em.spawn_pack(enemy_id, _spawn_point(), pack, mod, variant, stats)
		"ring":
			came = _spawn_elite_ring(enemy_id, pack, mod, variant, stats)
		_:
			came = 1 if em.spawn(enemy_id, _spawn_point(), mod, 1.0, 1.0, variant, stats) >= 0 else 0
	if came > 0:
		var title := ("%s %s" % [mod.display_name, def.display_name]).to_upper()
		game.toast(title if came == 1 else "%s ×%d" % [title, came], mod.outline)


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
