## Reads the map's WaveTimeline and keeps the arena full: a growing live cap, a roster that changes
## over time, scripted elites, swarm rings, and bosses. Owns the stage clock and the portal flow. The cap follows the
## timeline's `cap_curve` (pass 45), the boss fight keeps `boss_cap_frac` of it, and the portal wait keeps `portal_cap`
## load for `portal_spawn_seconds` (-1 / -1 = the stage-end cap for as long as the hero stays out) unless the timeline has
## a `portal_wave` (pass 48: one small wave round the hero as the portal opens, then nothing). Pass 46 stretched Red
## Canyon's clock by 430/300 (stages of 7:10), so every clock here reads the timeline (`stage_length`) instead of a fixed
## number of seconds, and the elite modifiers wait for the run's `colour_after_kills`-th kill. Pass 57: a roster row's or a
## wave's `pattern` may be "ring" (the whole spawn evenly round the hero at RING_RADIUS) or "in_front" (from the top of
## the screen whatever the timeline's `spawn_sides` says); a swarm event takes "in_front" too. Pass 58: every roster row
## and wave fixes its creatures' numbers at its first spawn (the time curves at its start, the hero's level then:
## source_for; afresh at each endless wave), an event and a special the moment they come (fixed_numbers) unless a row or
## wave brings the same creature then (event_numbers: the row's), the portal wave the row it drew, and EnemyManager.spawn
## plays them for each creature's life; a row's `stats.size` may be a range and `stats.tint` a colour range, rolled per
## creature.
class_name WaveDirector
extends Node

signal boss_started(def: EnemyDef)
signal portal_ready(pos: Vector3)
signal stage_started(stage: int)
## Pass 87 (lane SGAME): the run's stage boss died (Save marked the stage beaten), its portal's countdown to Endless
## began; Endless began (the countdown ran out: the portal closes); an Endless wave came (1-based).
signal stage_cleared(stage: int)
signal endless_started
signal endless_wave_started(wave: int)

## Pass 87: ENDLESS after the portal's countdown (the run clock stands still; Endless keeps its own, Run.endless_time).
enum Phase { NORMAL, BOSS, PORTAL, ENDLESS }

var game: Node
var timeline: WaveTimeline
var map: MapDef
var phase := Phase.NORMAL
var _spawn_t := 0.0
var _event_i := 0
var _elite_timers: Array = []     # {next, interval}
var _cull_t := 0.0
var _portal_t := 0.0   # seconds the portal has waited (the run clock is frozen then; pass 45)
## pass 87 (lane SGAME): the portal's countdown to Endless (seconds left; -1 = none runs), the Endless wave that came last
## (0 = none yet), the late roster Endless draws from ({row, w}), and Endless's creatures' speed factor now
var _portal_left := -1.0
var _endless_wave := 0
var _endless_pool: Array = []
var _endless_speed := 1.0
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
## fresh every run"); a director that never started rolls on its first tick (_ensure_rolled). Pass 58: `k` is the wave's
## place in the timeline (its key in the fixed numbers, "wave#k").
var _waves: Array = []
## Pass 58 (R1): each roster row's and wave's numbers as the run fixed them at its first spawn, key -> {t0, hp_time,
## dmg_time, lv_hp, lv_dmg} (source_for, fixed_numbers; in endless one per endless wave); cleared when a run starts.
var _src: Dictionary = {}
## The events as this run plays them (pass 53): a copy of the timeline's events, each with its effective `t` (its own
## +- `t_jitter`, rolled at start), `_i` its place in the timeline and `_skip` when its `chance` failed, sorted by t then
## _i; _process_events walks it with _event_i. Without jitter or chance it is the timeline's list in the timeline's
## order, so a tool that sets _event_i from the timeline (smoke_run, hell_check, the arena) still lands right.
var _run_events: Array = []
## Bursts one wave may fire in one tick (pass 53): at 60 fps a wave never owes more than one, so more means the clock
## jumped (a tool); past this many the rhythm starts again from now instead of replaying every burst since.
const WAVE_BURSTS_PER_TICK := 8
const SWARM_COLOR := Color(0.94, 0.63, 0.35)
## Pass 110 (lane BOSS): the stage's boss-fight window as this fight plays it (BossFightWindow; active from the boss's
## arrival to its death when the stage has one: then only its rows spawn, under its own max_count; boss_window_on).
var boss_window := BossFightWindow.new()


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
	# pass 77 (lane SIMRUN): the run sim's seed (Run.seed_dice) makes the director's dice repeatable
	if Run.rng_seed != 0:
		_rng.seed = hash([Run.rng_seed, "director"])
	# pass 58: every row and wave fixes its numbers afresh at its first spawn of this run
	forget_sources()
	# pass 53: the events' jitter and chance and the waves' alternatives, rolled once for this run
	_roll_events()
	_roll_waves()
	# pass 81 (lane PACE): the waves rows' schedule starts afresh
	_row_waves.clear()
	# pass 83 (lane TIMELINE): the own-interval rows' clocks start afresh
	_row_draw_left.clear()
	# pass 84 (lane SPAWN): the once and waves rows' chance and t_jitter, rolled once for this run (no dice without them)
	_roll_rows()
	_starve84.clear()
	# pass 110 (lane BOSS): no boss-fight window plays until this run's boss arrives
	boss_window.stop()
	# pass 87 (lane SGAME): no countdown, no Endless yet; a stage run starts at its window (what came before it never comes)
	_portal_left = -1.0
	_endless_wave = 0
	_endless_pool = []
	_endless_speed = 1.0
	if game.get("pickups") and game.pickups:
		game.pickups.set("endless_coin_chance", 1.0)
	_enter_stage_window()
	running = true
	var em: EnemyManager = game.enemies
	# pass 106 (lane ENDLESS): no Endless speed on a fresh run's creatures
	em.set_endless_speed(_endless_speed)
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
	boss_window.stop()


## Pass 110 (lane BOSS): whether the boss fight in play spawns from its stage's window (BossFightWindow) instead of the
## stage's rows.
func boss_window_on() -> bool:
	return phase == Phase.BOSS and boss_window.active


## Pass 113 (lane BOSS): whether a boss's bullet-heaven pattern is under way (EnemyManager.pattern_holds): the fight's
## spawns wait for it.
func boss_pattern_holds() -> bool:
	if game == null or game.get("enemies") == null:
		return false
	var em = game.enemies
	return em.has_method("pattern_holds") and bool(em.pattern_holds())


## Pass 110 (lane BOSS; the lead: "boss summons keep their own rules but must not push past the hard cap"): how many of
## `want` summons a boss's spawn_ring may bring now: all of them while the map's hard cap (bodies) has room, else what is
## left of it. EnemyManager.summon_count asks it; without a timeline, all of them.
func summon_room(want: int) -> int:
	if timeline == null or game == null or game.get("enemies") == null:
		return want
	return clampi(want, 0, maxi(timeline.hard_cap - int(game.enemies.alive_count()), 0))


func _apply_mults() -> void:
	var em: EnemyManager = game.enemies
	em.stage_mult = Run.stage_mult()
	em.stage_speed_mult = timeline.speed_mult(Run.stage)
	em.hp_time_mult = timeline.hp_mult_at(Run.elapsed)
	# pass 79 (lane MUT): the card levels (Run.card_level, M5)
	var lv := float(maxi(Run.card_level() - 1, 0))
	# pass 83 (lane SCALE): times the HP factor of the hero's power (power_hp_mult; 1 at the map's default scaling 1)
	em.level_hp_mult = (1.0 + timeline.level_hp_per_level * lv) * power_hp_mult()
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
	# pass 60: every creature's pace times the timeline's creature_speed_mult (0.9 on Red Canyon), the arena included (it
	# is where the walks are looked at, and they should go as they do in a run); the hero keeps his move_pace
	em.creature_speed_mult = timeline.creature_speed_mult
	# pass 69 (lane EN): the map's fallbacks for a variance special's numbers (EnemyDef.special_value)
	em.special_defaults = timeline.special_defaults
	# pass 73 (lane SNIPER): the weapons' target priority (EnemyManager.priority_target)
	em.set_target_priority(timeline.target_priority)
	# pass 73 (lane GROUND): every spawn grows out of the ground (EnemyManager.set_spawn_rise), the arena included
	em.set_spawn_rise(timeline.spawn_rise_value("seconds"), timeline.spawn_rise_value("big_seconds"), timeline.spawn_rise_value("targetable"), timeline.spawn_rise_value("dust"))
	# pass 95 (lane WORLD): regular creatures far from the hero and off the screen despawn (EnemyManager.set_despawn,
	# the map's timeline_data.despawn); never in the arena, where creatures are spawned to be looked at
	em.set_despawn({} if Run.arena else timeline.despawn_cfg())
	# pass 111 (lane ENEMY): regular creatures and bosses far from the hero walk faster (EnemyManager.set_far_speed, the
	# map's timeline_data.far_speed), the arena included (it is where the walks are looked at, as creature_speed_mult)
	if em.has_method("set_far_speed"):
		em.set_far_speed(timeline.far_speed_cfg())
	# pass 87 (lane SGAME): in Endless every creature that comes walks at the wave's speed factor (a little faster each
	# wave, WaveTimeline.endless_mults; fixed per creature at its spawn as the stage's is)
	if phase == Phase.ENDLESS:
		em.stage_speed_mult = timeline.speed_mult(Run.stage) * _endless_speed


## Whether colour may come yet (pass 46): the run has made its first `colour_after_kills` kills (the arena always may).
## An elite modifier is colour, so its spawns wait for this; the crowd's tints and specials wait in EnemyManager.spawn.
func colour_open() -> bool:
	return Run.arena or timeline == null or Run.kills >= timeline.colour_after_kills


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
		# pass 110 (lane BOSS): a fight that plays its stage's window keeps the window's own max_count (bodies)
		if boss_window.active:
			return boss_window.cap_value()
		return int(cap * timeline.boss_cap_frac)
	if phase == Phase.ENDLESS:
		# pass 87 (lane SGAME): the crowd Endless keeps up between its waves, x the stage-end cap (the frozen clock's)
		return int(float(cap) * maxf(timeline.endless_value("cap", Run.stage), 0.0))
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
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	var _t0 := Time.get_ticks_usec()
	if not running or game.paused:
		# the debug arena holds the director, and with it the stage clock: the buffs' clock runs on regardless (pass 49,
		# Garry: "Pollen should only last 5 seconds, not forever": in the arena no timed buff ever ran out)
		if not running and Run.arena and not game.paused:
			Run.held_time += delta
		Perf.add("director", _t0)
		return
	if phase == Phase.NORMAL:
		# pass 87 (lane SGAME): the run clock stays inside this run's stage window (it is never pulled back: a tool may have
		# set it past); the window's end brings the stage's boss
		var end: float = timeline.stage_end(Run.stage)
		Run.elapsed = minf(Run.elapsed + delta, end) if Run.elapsed < end else Run.elapsed
		_apply_mults()
		_process_events()
		if phase == Phase.NORMAL:
			# the timeline's waves (pass 53) run in the normal phase only: an event above may just have started a boss
			_tick_waves()
			# pass 81 (lane PACE): the roster rows paced as waves
			_tick_row_waves()
		# the path slots: a stage puts a weapon's whole path on the table at set seconds into it; pass 79 (lane MUT): the
		# offer falls due there and waits for the hero's next level-up (Run.mutlvl_tick, M1-M2), never opening on its own
		# (pass 87: seconds into the stage's own window)
		Run.mutlvl_tick(Run.elapsed - timeline.stage_start(Run.stage))
		if phase == Phase.NORMAL and Run.elapsed >= end:
			_stage_end_reached()
	elif phase == Phase.PORTAL:
		_portal_t += delta
		# pass 87: the portal's countdown to Endless, on the run's clock (it stands still behind every screen but the
		# portal dialog, which ticks it through Game.tick_portal_countdown)
		tick_portal_countdown(delta)
	elif phase == Phase.ENDLESS:
		_tick_endless(delta)
	elif boss_window_on():
		# pass 110 (lane BOSS): the fight clock of the stage's boss-fight window, its waves and its own-interval rows
		boss_window.tick(delta)
	if phase != Phase.NORMAL:
		# the stage clock stands still; the buffs' clock does not (Run.buff_clock, pass 47)
		Run.held_time += delta
	# the specials' clock in the stage and its boss fight (pass 87: not in the portal wait nor in Endless; pass 110: nor
	# in a fight that plays its window, where only the window's rows spawn)
	# pass 113 (lane BOSS): a boss fight without a window holds its spawns too while his bullet-heaven pattern runs (the
	# window holds its own rows: BossFightWindow.held)
	var pat_hold: bool = phase == Phase.BOSS and not boss_window.active and boss_pattern_holds()
	if phase == Phase.NORMAL or (phase == Phase.BOSS and not boss_window.active and not pat_hold):
		_tick_specials(delta)
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = timeline.spawn_interval
		# pass 87: Endless keeps its crowd up from the stage's late roster (_endless_fill) instead of the roster's draw
		if phase == Phase.ENDLESS:
			_endless_fill()
		elif boss_window_on():
			boss_window.spawn_check()
		elif not pat_hold:
			_spawn_burst()
	if phase != Phase.ENDLESS and not boss_window_on() and not pat_hold:
		# pass 83 (lane TIMELINE): the continuous rows with their own `interval` draw on their own clocks
		_tick_row_intervals(delta)
		# pass 84 (lane SPAWN): the density floor (floor_curve; nothing without one)
		_floor_fill()
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


## Seconds until the next boss event, or -1 when none is scheduled. The HUD counts it down. Pass 53: it reads the run's
## own copy of the events when there is one (a boss with `t_jitter` comes at its rolled time and the count says so; one
## whose `chance` failed is not counted down to), the timeline's list before a run has rolled. Pass 87 (lane SGAME): only
## in the stage's normal phase and only inside its window (a later stage's boss is never this run's): the stage's own
## boss at the window's end when no boss event comes sooner (_stage_end_reached); -1 in a boss fight, the portal's
## countdown and Endless.
func next_boss_in() -> float:
	if timeline == null or phase != Phase.NORMAL:
		return -1.0
	var t: float = Run.elapsed
	var end: float = timeline.stage_end(Run.stage)
	var best := -1.0
	var list: Array = _run_events if _run_events.size() == timeline.events.size() else timeline.events
	for ev in list:
		if str(ev.get("type", "")) == "boss" and not bool(ev.get("_skip", false)):
			var et := float(ev.get("t", 0.0))
			if et > t and et <= end and (best < 0.0 or et - t < best):
				best = et - t
	if best < 0.0 and end > t and timeline.stage_boss_named(Run.stage) != "":
		best = end - t
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
			# an event's numbers are the moment it fires (pass 58, R1), or the row's that brings the same creature then
			# (the fix round: a fire-ant swarm beside the fire-ant row had 1.6 times their HP)
			var en := event_numbers(id, variant, stats)
			var est: Dictionary = en["stats"]
			var src: Dictionary = en["src"]
			# pass 69 (lane EN, Garry: "a single 'Special' regular Goblin appears at the end of the first wave"):
			# "special": true brings every one of it as its variance special (EnemyManager.force_special: whatever its
			# chance, before colour_after_kills), with no SWARM! banner
			var forced := bool(ev.get("special", false))
			em.force_special = forced
			match str(ev.get("pattern", "ring")):
				"pack", "scatter", "in_front":
					# through the spawn points instead of the ring (pass 53), still on top of the cap like the ring;
					# "in_front" (pass 57) from the top of the screen whatever spawn_sides says
					_spawn_group(id, count, str(ev["pattern"]), int(ev.get("pack", 0)), null, variant, est, Callable(), src)
				_:
					# the swarm's own ring, 16 m round the hero as it always was (the rows' and waves' "ring" is
					# RING_RADIUS, pass 57)
					em.spawn_ring(id, count, game.player.global_position, 16.0, variant, est, src)
			em.force_special = false
			if not forced:
				game.toast("SWARM!", SWARM_COLOR)
			_log84("swarm", id, count)
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
	# pass 110 (lane BOSS): the stage's boss-fight window, when it has one, plays from now until the boss dies
	boss_window.begin(self, Run.stage)
	var em: EnemyManager = game.enemies
	var mb: MapBase = game.map
	# the arena may name the spot; the timeline's boss comes up on the flats. A boss keeps its own rules (pass 58: the
	# fixed numbers reach only a regular creature a boss event might name)
	var at: Vector3 = mb.flats_center + Vector3(0, 0, -10) if where == Vector3.INF else where
	var en := event_numbers(id, variant, stats)
	# pass 72 (lane BOSS): its HP pegged to the hero's DPS (boss_dps_scale), held around the spawn only
	em.set("boss_hp_scale", boss_dps_scale(id))
	# pass 83 (lane SCALE): the seconds mode's floor on its HP (boss_seconds_target; 0 = none), held around the spawn too
	em.set("boss_hp_target", boss_seconds_target(id, variant, en["stats"]))
	em.spawn_boss(id, at, variant, en["stats"], en["src"])
	em.set("boss_hp_scale", 1.0)
	em.set("boss_hp_target", 0.0)
	if not last_boss_scale.is_empty() and em.boss_index >= 0:
		last_boss_scale["hp"] = float(em.max_hp[em.boss_index])
	boss_started.emit(def)
	game.toast(def.display_name.to_upper(), Color(0.93, 0.29, 0.36))


## Boss HP pegged to the hero's DPS (pass 72, lane BOSS; Garry: "Boss Max HP should scale up the bigger the Player's DPS is
## in that moment. It shouldn't be 1 to 1"): the multiplier boss `id` spawns with now, from the hero's damage a second
## over the map's window (Run.recent_dps) against the boss's ref_dps (WaveTimeline.boss_hp_mult). In endless a returning
## boss's reference grows as its own HP has grown since its stage (hp_mult_per_stage^stage x the stage multiplier), so a
## build that kept up with the clock is not tripled on top. 1 in the debug arena (its bosses keep their data HP), with
## scaling off or without a reference. What it read is kept in last_boss_scale (the probe, the debug panel, the tests).
var last_boss_scale: Dictionary = {}


func boss_dps_scale(id: String) -> float:
	last_boss_scale = {}
	# (pass 72, lane INTEG: an empty block plays WaveTimeline's defaults, on; enabled false turns it off)
	if Run.arena or timeline == null or not bool(timeline.boss_hp_scaling.get("enabled", WaveTimeline.BOSS_HP_SCALING_DEFAULTS["enabled"])):
		return 1.0
	# pass 83 (lane SCALE): the seconds mode (the game's default) sets a floor on the HP instead (boss_seconds_target)
	if timeline.boss_hp_mode() == "seconds":
		return 1.0
	var ref: float = timeline.boss_ref_dps(id)
	if ref <= 0.0:
		return 1.0
	var def: EnemyDef = Registry.enemy(id)
	var s0 := boss_stage_of(id)
	var grow := 1.0
	if def != null and s0 >= 0 and Run.stage > s0:
		var hpm := float(def.boss.get("hp_mult_per_stage", 1.6))
		var now_f := pow(hpm, float(Run.stage)) * maxf(Run.stage_mult(), 1.0)
		var own_f := pow(hpm, float(s0)) * maxf(timeline.stage_mult(s0), 1.0)
		grow = now_f / maxf(own_f, 0.0001)
	var window: float = timeline.boss_dps_window()
	var dps: float = Run.recent_dps(window)
	var mult: float = WaveTimeline.boss_hp_mult(timeline.boss_hp_scaling, dps, ref * grow)
	last_boss_scale = {"id": id, "dps": dps, "ref": ref * grow, "mult": mult, "window": window, "stage": Run.stage}
	print("boss hp scaling: %s dps %.0f over %.0f s, ref %.0f -> HP x%.2f" % [id, dps, window, ref * grow, mult])
	return mult


## The stage (0-based) the timeline's first boss event for `id` ends: the event at the stage's last second (7:10 = 430 s
## on Red Canyon) belongs to the stage it closes. -1 when no boss event names it.
func boss_stage_of(id: String) -> int:
	if timeline == null:
		return -1
	for ev in timeline.events:
		if str(ev.get("type", "")) == "boss" and str(ev.get("enemy", "")) == id:
			# pass 87 (lane SGAME): the stage whose window the event closes (a hair back: its end second is the next's)
			return timeline.stage_at(float(ev.get("t", 0.0)) - 0.5)
	return -1


## Pass 83 (lane SCALE; Garry: "at least 25 seconds of Player's FULL DPS on Tumbleweed king ... 40s for the next and a
## full minute to the last one"): in boss_hp_scaling's "seconds" mode (WaveTimeline.boss_hp_mode, the game's default)
## the HP boss `id` must at least come with: the hero's full DPS on it now (HeroPower.full_dps, boss = true) x its
## seconds (WaveTimeline.boss_seconds) x (1 - its damage reduction); EnemyManager takes max(its data HP, this). 0 = no
## floor: the debug arena, scaling off, the "dps" mode, a boss without seconds. Fills last_boss_scale.
func boss_seconds_target(id: String, variant := "", stats := {}) -> float:
	if Run.arena or timeline == null or not bool(timeline.boss_hp_scaling.get("enabled", WaveTimeline.BOSS_HP_SCALING_DEFAULTS["enabled"])):
		return 0.0
	if timeline.boss_hp_mode() != "seconds":
		return 0.0
	var secs: float = timeline.boss_seconds(id)
	var def: EnemyDef = Registry.enemy_with(id, variant, stats)
	if secs <= 0.0 or def == null:
		return 0.0
	var dps: float = HeroPower.boss_dps_now()
	var base: float = def.hp * pow(float(def.boss.get("hp_mult_per_stage", 1.6)), float(Run.stage)) * maxf(Run.stage_mult(), 1.0)
	var target: float = WaveTimeline.boss_seconds_hp(0.0, dps, secs, def.damage_reduction)
	last_boss_scale = {"id": id, "mode": "seconds", "full_dps": dps, "seconds": secs, "base": base, "target": target,
		"mult": maxf(target, base) / maxf(base, 0.0001), "dps": dps, "stage": Run.stage}
	print("boss hp seconds: %s full dps %.0f x %.0f s = %.0f, data hp %.0f -> HP %.0f" % [id, dps, secs, target, base, maxf(target, base)])
	return target


## Pass 83 (lane SCALE): every ordinary creature's HP factor from the hero's power now (WaveTimeline.power_hp_factor of
## the map's power_hp_scaling and power_hp_max, HeroPower.current); 1 in the arena, without a timeline or at scaling 1
## (the power is not even worked out then). Folded into the hero-level factor (lv_hp) where a row fixes its numbers.
func power_hp_mult() -> float:
	if Run.arena or timeline == null or absf(timeline.power_hp_scaling - 1.0) < 0.000001:
		return 1.0
	return WaveTimeline.power_hp_factor(timeline.power_hp_scaling, timeline.power_hp_max, HeroPower.current())


## The mini-boss: one big creature near the hero, a toast and nothing else. Its chest comes from its drops.
func _spawn_elite_boss(id: String, variant := "", stats := {}) -> void:
	var def: EnemyDef = Registry.enemy(id)
	if def == null:
		return
	var em: EnemyManager = game.enemies
	# where the hero is headed, as before the spawn sides (pass 54: the schema keeps the Elite bosses on the old rule); an
	# Elite by its kind keeps its own numbers (pass 58), the event's fixed ones reach only a regular creature it names
	var en := event_numbers(id, variant, stats)
	# pass 107 (fix): an Elite boss comes like the stage's boss, a slot made when the pool is full (EnemyManager._room_for_boss)
	if em.free_list.is_empty():
		em._room_for_boss()
	var i := em.spawn(id, _facing_point(), null, 1.0, 1.0, variant, en["stats"], en["src"])
	if i >= 0:
		elite_index = i
		game.toast(def.display_name.to_upper(), Color(0.98, 0.62, 0.25))


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


# ---------------------------------------------------------------- a source's numbers fixed from its start (pass 58)

## The fixed numbers of a spawn source that starts at `t0` with `stats` overrides, read now (pass 58, R1 of the pass's
## rules, docs/waves_schema.md "Pass 58"; Garry: "While I want the HP of enemies to increase over time, I don't actually
## want it to change for the same 'wave' of enemies on the fly"): the HP and damage curves at t0, 1 for a number the stats
## set themselves (Garry: "the multiplier will inform what the HP should be for enemy rows whose stats weren't
## overridden"), and the hero-level factors at the hero's level now. EnemyManager.spawn takes it as `src`: the creature
## plays these instead of the live curve and level, times the stage multiplier at its spawn, and keeps them for its hits.
func fixed_numbers(t0: float, stats: Dictionary = {}) -> Dictionary:
	var tl: WaveTimeline = timeline if timeline else WaveTimeline.new()
	var lv := float(maxi(Run.card_level() - 1, 0))
	return {"t0": t0,
		"hp_time": 1.0 if stats.has("hp") else tl.hp_mult_at(t0),
		"dmg_time": 1.0 if stats.has("damage") else tl.damage_mult_at(t0),
		# pass 83 (lane SCALE): times the hero-power HP factor, fixed with the row like the level (power_hp_mult)
		"lv_hp": (1.0 + tl.level_hp_per_level * lv) * power_hp_mult(),
		"lv_dmg": 1.0 + tl.level_damage_per_level * lv}


## A roster row's or a wave's fixed numbers (pass 58): made at its first spawn of the run (the hero's level then) and kept
## for every later creature of it. Events, specials and a boss's brood take theirs the moment they come instead
## (fixed_numbers), or a row's that brings the same creature then (event_numbers). The fix round (the review: Red
## Canyon's hell rows have no end, so stage 3 and the whole of endless kept 14:20's curve and hero level, and only the
## x1.12 a wave was left of endless's growth): in endless every row and wave fixes its numbers afresh at each endless
## wave, from the wave's start (or its own `t`, if later) and the hero's level at its first spawn in that wave; the step
## comes with the WAVE toast, like the stage multiplier's, so nothing changes in the middle of a wave. Pass 87 (lane
## SGAME): Endless follows the stage, its run clock frozen at the window's end, so the numbers are fixed from the row's
## own start as in the stage, then times the Endless wave's multipliers (WaveTimeline.endless_mults: hp on the HP, atk on
## the damage), afresh at each Endless wave.
func source_for(key: String, t0: float, stats: Dictionary) -> Dictionary:
	var ew := endless_wave_now()
	if ew > 0:
		key += "@w%d" % ew
	var s = _src.get(key)
	if s is Dictionary:
		return s
	var made := fixed_numbers(t0, stats)
	if ew > 0 and timeline != null:
		var m: Dictionary = timeline.endless_mults(ew, Run.stage)
		made["hp_time"] = float(made["hp_time"]) * float(m["hp"])
		made["dmg_time"] = float(made["dmg_time"]) * float(m["atk"])
		made["endless_wave"] = ew
	_src[key] = made
	return made


## The Endless wave the run is in (pass 58 fix round; pass 87: Run.endless_wave(), a wave every `endless.every` seconds of
## Endless), 1-based, 0 outside Endless.
func endless_wave_now() -> int:
	if not Run.endless or timeline == null:
		return 0
	return Run.endless_wave()


## The second of Endless at which Endless wave `w` (1-based) starts (pass 87: Endless's own clock, Run.endless_time).
func endless_wave_start(w: int) -> float:
	return float(maxi(w - 1, 0)) * maxf(timeline.endless_value("every", Run.stage), 1.0)


## Forgets every row's and wave's fixed numbers (pass 58): the next spawn of each fixes them again, from the hero's level
## then. A run starts this way (start()); the debug arena's "Run from the clock" may call it, since the hero's level and
## the clock there are whatever was set since the director last ran.
func forget_sources() -> void:
	_src.clear()


## The run's fixed numbers of the source called `key` ("row:<id>#<index>", "row#<index>", "wave#<index>", and in endless
## "@w<wave>" on the end), {} before its first spawn (the tests, a tool).
func source_state(key: String) -> Dictionary:
	var s = _src.get(key)
	return (s as Dictionary).duplicate() if s is Dictionary else {}


## A roster row's key in the fixed numbers (pass 58): its `id` and its place in the timeline's roster ("row:<id>#<index>";
## the fix round: two rows of a hand-made JSON that share an id kept one snapshot), "row#<index>" for a row without an id,
## else (a row built by hand: the tests) "row:<id>" or its creature and start.
func row_key(r: Dictionary) -> String:
	var id := str(r.get("id", ""))
	if timeline:
		for k in range(timeline.roster.size()):
			if is_same(timeline.roster[k], r):
				return ("row:%s#%d" % [id, k]) if id != "" else "row#%d" % k
	if id != "":
		return "row:" + id
	return "row?%s@%s" % [str(r.get("enemy", "")), str(r.get("t", 0.0))]


## A roster row's fixed numbers (pass 58): from its `t` (0 when it has none) and its own stats.
func _row_src(r: Dictionary) -> Dictionary:
	return source_for(row_key(r), float(r.get("t", 0.0)), _stats_of(r))


## The numbers an event's creatures play (pass 58; this rule is the fix round's, docs/waves_schema.md "Pass 58"): the
## moment's (fixed_numbers), except that while a roster row or a wave brings the same creature in the same look
## (open_source_of), each half the event's own stats leave alone (HP: `hp`, `hp_mult`; ATK: `damage`, `damage_mult`) is
## that row's: its overrides and its fixed numbers. The review had a fire-ant swarm at 9:19 come with 520 HP beside the
## 7:10 row's 322-HP ants, the very "shooting the same enemy with the same weapon suddenly doesn't kill it" Garry wanted
## gone. {stats (the event's, with the row's numbers in), src, joined (the row's key, "" for none)}. A boss and an Elite by
## their kind never join (their own rules). EnemyManager.brood_numbers asks it for a boss's brood too.
func event_numbers(id: String, variant: String, stats: Dictionary) -> Dictionary:
	var src := fixed_numbers(Run.elapsed, stats)
	var out := {"stats": stats, "src": src, "joined": ""}
	var base: EnemyDef = Registry.enemy(id)
	if base == null or base.archetype == "boss" or base.archetype == "elite" or timeline == null:
		return out
	var hp_own := stats.has("hp") or stats.has("hp_mult")
	var dmg_own := stats.has("damage") or stats.has("damage_mult")
	if hp_own and dmg_own:
		return out
	var row := open_source_of(id, variant)
	if row.is_empty():
		return out
	var rstats: Dictionary = row["stats"]
	var rs := source_for(str(row["key"]), float(row["t0"]), rstats)
	var merged: Dictionary = stats.duplicate(true)
	if not hp_own:
		src["hp_time"] = rs["hp_time"]
		src["lv_hp"] = rs["lv_hp"]
		for k: String in ["hp", "hp_mult"]:
			if rstats.has(k):
				merged[k] = rstats[k]
	if not dmg_own:
		src["dmg_time"] = rs["dmg_time"]
		src["lv_dmg"] = rs["lv_dmg"]
		for k: String in ["damage", "damage_mult"]:
			if rstats.has(k):
				merged[k] = rstats[k]
	return {"stats": merged, "src": src, "joined": str(row["key"])}


## The roster row, else the wave, bringing creature `id` in the look `variant` right now (pass 58 fix round): a row of
## either channel open now at a weight above 0 (the heaviest when several are), else a wave inside its window and not
## spent whose rolled alternative brings it; {key, t0, stats} as source_for takes them, {} when none. "Now" is the clock a
## hair back outside the normal phase, as the bursts read it (the frozen clock sits on the stage boundary).
func open_source_of(id: String, variant: String) -> Dictionary:
	if timeline == null:
		return {}
	var t := Run.elapsed if phase == Phase.NORMAL else Run.elapsed - 1.0
	var look := _look_of(id, variant)
	var best: Dictionary = {}
	var best_w := 0.0
	# pass 84 (lane SPAWN): the mix rows only (a once row, a list or "roster" row, an elite or special row is an event)
	for r in WaveTimeline.mix_rows(timeline.roster_at(t)):
		if not (r is Dictionary) or str(r.get("enemy", "")) != id or _look_of(id, str(r.get("variant", ""))) != look:
			continue
		var w := _roster_weight(r, t)
		if w > best_w:
			best_w = w
			best = {"key": row_key(r), "t0": float(r.get("t", 0.0)), "stats": _stats_of(r)}
	if not best.is_empty() or timeline.waves.is_empty():
		return best
	_ensure_rolled()
	for k in range(_waves.size()):
		var ws: Dictionary = _waves[k]
		var wv: Dictionary = timeline.waves[k] if timeline.waves[k] is Dictionary else {}
		if wv.is_empty() or bool(ws.get("done", false)) or t < float(wv.get("t", 0.0)) or (wv.has("until") and t >= float(wv["until"])):
			continue
		var alt: Dictionary = ws["alt"]
		if str(alt.get("enemy", "")) != id or _look_of(id, str(alt.get("variant", ""))) != look:
			continue
		return {"key": "wave#%d" % k, "t0": float(wv.get("t", 0.0)), "stats": _stats_of(alt)}
	return {}


## The art variant creature `id` plays with `variant` asked for (pass 58 fix round): the code itself when it is one of the
## creature's other looks, "" for its own (an empty code, its default or an unknown one: EnemyDef.variant_def's rule).
static func _look_of(id: String, variant: String) -> String:
	var base: EnemyDef = Registry.enemy(id)
	if base == null or variant == "" or variant == base.variant or not base.variants.has(variant):
		return ""
	return variant


## `n` creatures of `id` through the spawn points (pass 53, the roster's and the waves' `pattern`): "pack" puts them at
## one point (`pack` or more of them in several packs, each at its own point; pack 0 = all together), "scatter" and
## "single" each at a point of its own. `point` picks the points (`_spawn_point` when not given; the portal wave hands
## `_around_point`). Pass 57: "ring" puts all `n` evenly round the hero (_spawn_ring_group: a row's pack, a wave's
## burst, whatever `pack` says), and "in_front" puts each of the `n` at its own point at the top of the screen
## (_in_front_point) whatever `point` and the timeline's spawn_sides say: a loose band across the top, which read as
## "they come from above" better than packs sharing a top point did (both were captured in the arena). Any other
## pattern is "pack", as it always was. Returns how many came. Pass 58: `src` is the source's fixed numbers
## (source_for / fixed_numbers), handed to every creature; {} = the live numbers.
func _spawn_group(id: String, n: int, pattern: String, pack: int, mod: EliteModDef, variant: String, stats: Dictionary, point: Callable = Callable(), src: Dictionary = {}) -> int:
	var em: EnemyManager = game.enemies
	# pass 112 (lane MONK): a squad creature always comes as a pack, the whole call one squad (never more than its largest
	# size a squad), whatever the row's pattern and pack: the callers that know squads hand one squad (squad_take)
	var sqdef: EnemyDef = Registry.enemy(id)
	if sqdef != null and sqdef.is_squad():
		pattern = "pack"
		pack = mini(maxi(n, 1), sqdef.squad_max())
	if pattern == "ring":
		return _spawn_ring_group(id, n, mod, variant, stats, src)
	if pattern == "in_front":
		# Garry: "an override to the Spawning part in the Settings"
		point = _in_front_point
		pattern = "scatter"
	if not point.is_valid():
		point = _spawn_point
	var came := 0
	if pattern == "scatter" or pattern == "single":
		for k in range(n):
			if em.spawn(id, point.call(), mod, 1.0, 1.0, variant, stats, src) >= 0:
				came += 1
		return came
	var left := n
	var chunk: int = pack if pack > 0 else n
	while left > 0:
		var m: int = mini(chunk, left)
		came += em.spawn_pack(id, point.call(), m, mod, variant, stats, src)
		left -= m
	return came


## The "ring" pattern's radius round the hero (pass 57, Garry: "spawn in a Ring around the Player (kind of like what we
## have in the debug option in the Arena), but about 30% further from the Player"): the arena's ring (ArenaPanel
## _place_point "ring", 9 m) times 1.3. The swarm event's own ring stays 16 m, and the elite "ring" format 12 m.
const RING_RADIUS := 9.0 * 1.3
## How far a ring point may stray in or out (pass 57): a full ring reads as a thick band, not a drawn line.
const RING_JITTER := 0.6
## How far a ring point may slide round the circle, as a share of the even spacing (pass 57): small enough that no two
## come closer than half the spacing.
const RING_SLIDE := 0.2


## `n` creatures of `id` on a ring round the hero (pass 57, the "ring" pattern; ring_points places them). Each may wear
## `mod` (a wave's elite modifier) and carry the source's fixed numbers `src` (pass 58). Returns how many came.
func _spawn_ring_group(id: String, n: int, mod: EliteModDef, variant: String, stats: Dictionary, src: Dictionary = {}) -> int:
	var em: EnemyManager = game.enemies
	var came := 0
	for p: Vector3 in ring_points(n):
		if em.spawn(id, p, mod, 1.0, 1.0, variant, stats, src) >= 0:
			came += 1
	return came


## Where a ring of `n` stands (pass 57): evenly round the hero at RING_RADIUS from a random start angle, each point slid
## up to RING_SLIDE of the spacing round the circle and RING_JITTER in or out. The editor's hint says how many make "a
## thick ring with few gaps" (Garry): about 1.5 times the circle over a body's width. Pass 58 (the review of pass 57: by
## the wall the ring's outer part was clamped onto the wall right beside the hero, 7 of a 105-ring within 2 m of him): a
## ring that would cross the wall spreads all `n` evenly over the arc of it inside the arena, and a point on a rock's
## painting or in the lake steps a little round the ring or in and out (EnemyManager.ring_spots); every point stays a
## ring's width from the hero.
func ring_points(n: int) -> Array:
	var out: Array = []
	if n <= 0 or game == null or game.player == null:
		return out
	var center: Vector3 = game.player.global_position
	var mb: MapBase = game.map
	var turn := _rng.randf() * TAU
	for p: Vector3 in EnemyManager.ring_spots(center, RING_RADIUS, n, _spawn_lim(), _rng, turn, RING_SLIDE, RING_JITTER, mb):
		out.append(mb.clamp_to_arena(p) if mb else p)
	return out


## The usable radius of the arena for a spawn point (pass 58): MapBase.clamp_to_arena's own limit, so a point placed inside
## it is never moved by the clamp.
func _spawn_lim() -> float:
	var mb: MapBase = game.map if game else null
	return mb.arena_radius - 1.5 if mb else INF


## A point for the "in_front" pattern (pass 57, Garry: "makes the enemies spawn above the Player, basically an override to
## the Spawning part in the Settings"): the usual 19-24 m from the hero, clamped to the arena, within 45 degrees either
## side of straight up the screen (the side spawn_sides calls top; the follow camera's yaw turns it with the screen),
## whatever the timeline's spawn_sides says, mode sides or facing. Pass 58: by the north wall it turns round inside the
## arena instead of piling onto the wall beside him (_point_at), and it steps off a rock's painting or the lake (it can be
## on the screen when the camera has pulled out).
func _in_front_point() -> Vector3:
	return _point_at(_camera_yaw() + _rng.randf_range(-SIDE_HALF_ARC, SIDE_HALF_ARC), true)


## The camera's yaw in the hero's convention (0 = -Z, straight up the screen under the fixed camera, which never turns);
## the follow camera's own yaw when it has one (pass 54's spawn sides, pass 57's in_front).
func _camera_yaw() -> float:
	return game.camera.current_yaw() if game.get("camera") and game.camera and game.camera.has_method("current_yaw") else 0.0


## Position of the living mini-boss, or Vector3.INF when none.
func elite_position() -> Vector3:
	var em: EnemyManager = game.enemies
	if elite_index >= 0 and em.is_alive(elite_index) and (em.types[em.type_idx[elite_index]]["def"] as EnemyDef).archetype == "elite":
		return em.pos[elite_index]
	elite_index = -1
	return Vector3.INF


func _on_boss_died(_def: EnemyDef, at: Vector3) -> void:
	# pass 87 (lane SGAME): a boss that falls in Endless (the arena, a tool) changes nothing
	if phase == Phase.ENDLESS:
		return
	phase = Phase.PORTAL
	# pass 110 (lane BOSS): the fight is over, so is its window
	boss_window.stop()
	_portal_t = 0.0
	# the boss's own chest: it holds a mutation, and opening it is what calls every gem, coin and chest in (pass 30)
	game.pickups.spawn_chest(at + Vector3(2.0, 0, 0), true)
	Save.mark_once("boss_%s_%d" % [map.id, Run.stage + 1])
	# pass 87: the stage is beaten (the next one unlocks: Save.stage_unlocked), and the portal's countdown to Endless begins
	Run.stage_beaten = true
	if not Run.arena:
		Save.mark_stage_beaten(map.id, Run.stage)
	_portal_left = timeline.portal_seconds(Run.stage)
	# pass 113 (Garry: a skin's goal reached in a run gets "a notification, similar to the other unlocks"): the quests a
	# fallen boss completes (beat_stage: a look's goal) are checked through the game, which shows each one's banner; this
	# check used to mark them done quietly, so the game's own check never saw them
	if game and game.has_method("check_quests_now"):
		game.check_quests_now()
	else:
		QuestTracker.check_run_events()
	portal_ready.emit(at)
	spawn_portal_wave()
	stage_cleared.emit(Run.stage)


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
	# pass 84 (lane SPAWN): the mix rows only (WaveTimeline.row_in_mix)
	var rows: Array = _roster_open(WaveTimeline.mix_rows(timeline.roster_at(Run.elapsed - 1.0)).filter(func(r: Dictionary) -> bool: return str(r.get("channel", "")) != "hell"))
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
		# the row's own numbers (pass 58 fix round: it is that row's creature, beside the ones the hero was just shooting)
		_spawn_group(def.id, n, pattern, pack, null, str(row.get("variant", "")), _stats_of(row), _around_point, _row_src(row))
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


## A spot all round the hero, just off his screen (the portal wave comes from every side, not mostly ahead). Pass 58: a
## spot past the wall turns round inside the arena at the same distance (EnemyManager.point_inside) instead of being
## clamped onto the wall beside him.
func _around_point() -> Vector3:
	var player: Node3D = game.player
	var mb: MapBase = game.map
	var a := _rng.randf() * TAU
	var p := EnemyManager.point_inside(player.global_position, a, _rng.randf_range(15.0, 20.0), _spawn_lim())
	return mb.clamp_to_arena(p) if mb else p


# ---------------------------------------------------------------- a stage run's window, its end, Endless (pass 87, lane SGAME)

## Garry (2026-10-17): "Player kills the boss and the Portal that appears shows a 1 minute timer before the Endless Mode
## will activate. There is only an Extract button now in the Portal." A run plays one stage (Run.start_stage): its clock
## starts at the window's start (start() -> _enter_stage_window), stops at the window's end, where the stage's boss comes
## (its boss event, or _stage_end_reached); the boss's death opens the portal and its countdown (portal_seconds, run
## clock); the hero extracts through it (Game), or the countdown runs out and Endless starts (start_endless). There is no
## going on to the next stage any more (continue_to_next_stage is gone).

## What the timeline dated before this run's stage window never comes (start(), after the run's roll): every event before
## the window's start is skipped, and a boss event on the start itself too (it is the stage before's); an elite_every
## event before it still sets its timer, on its own rhythm from its second; a wave of the timeline's `waves` that began
## before keeps its rhythm from the window's start (a one-burst wave, or one closed by then, is spent). The roster rows
## need nothing: a once row past its second is dropped as stale, a waves row fires only its latest wave due, a continuous
## row is open by its own t/until (pass 81/84's rules for a clock that jumped). A run of stage 1 (start 0) changes nothing.
func _enter_stage_window() -> void:
	if timeline == null:
		return
	var w0: float = timeline.stage_start(Run.stage)
	if w0 <= 0.0:
		return
	for e: Dictionary in _run_events:
		var t := float(e.get("t", 0.0))
		var kind := str(e.get("type", ""))
		if t > w0 or (t == w0 and kind != "boss"):
			continue
		if kind == "elite_every" and not bool(e.get("_skip", false)):
			var iv := maxf(_interval_of(e.get("interval", 90.0)), 1.0)
			_elite_timers.append({"next": t + ceilf((w0 - t) / iv) * iv, "interval": e.get("interval", 90.0),
				"enemy": e.get("enemy", ""), "weights": e.get("weights", []), "mod": str(e.get("mod", "")),
				"variant": str(e.get("variant", "")), "stats": _stats_of(e)})
		e["_skip"] = true
	for k in range(_waves.size()):
		var ws: Dictionary = _waves[k]
		var w = timeline.waves[k]
		if not (w is Dictionary) or bool(ws.get("done", false)) or float(w.get("t", 0.0)) >= w0:
			continue
		var every := float(w.get("every", 0.0))
		if every <= 0.0 or ((w as Dictionary).has("until") and float(w["until"]) <= w0):
			ws["done"] = true
			continue
		var t0 := float(w.get("t", 0.0))
		ws["next_t"] = t0 + ceilf((w0 - t0) / every) * every


## The window's end came with no boss fight begun (no boss event at its end, or one whose jitter moved it past): the boss
## the stage's entry names, else the boss event's at the window's end unless this run skipped it (its `chance` failed:
## no boss this run, as before), or, for a stage without one, its portal where the hero stands.
func _stage_end_reached() -> void:
	var id: String = timeline.stage_boss_named(Run.stage)
	if id == "":
		id = timeline.stage_boss(Run.stage)
		for e: Dictionary in _run_events:
			if str(e.get("type", "")) == "boss" and str(e.get("enemy", "")) == id and bool(e.get("_skip", false)):
				id = ""
	if id != "" and Registry.enemy(id) != null:
		_start_boss(id)
		if phase == Phase.BOSS:
			return
	_on_boss_died(null, game.player.global_position if game and game.player else Vector3.ZERO)


## Seconds left on the portal's countdown to Endless, -1 when none runs (the HUD, the portal dialog; Game.portal_seconds_left).
func portal_seconds_left() -> float:
	return maxf(_portal_left, 0.0) if phase == Phase.PORTAL and _portal_left >= 0.0 else -1.0


## The countdown's tick (from _process in the portal phase; Game.tick_portal_countdown while the portal dialog is up).
func tick_portal_countdown(delta: float) -> void:
	if _portal_left < 0.0 or phase != Phase.PORTAL:
		return
	_portal_left -= delta
	if _portal_left <= 0.0:
		start_endless()


## Endless begins (the portal's countdown ran out; tools and tests may call it): the portal closes (Game hears
## endless_started), the run clock stays frozen at the window's end while Endless keeps its own (Run.endless_time), its
## first wave comes at once. Garry: "Enemies still drop EXP, but modest amounts and drop coins very very rarely" (Game's
## xp share, PickupManager.endless_coin_chance); "The goal of this mode is to kill the Player": it runs until he falls (a
## death banks everything, pass 70).
func start_endless() -> void:
	if phase == Phase.ENDLESS or timeline == null:
		return
	phase = Phase.ENDLESS
	_portal_left = -1.0
	Run.endless = true
	Run.endless_time = 0.0
	_endless_wave = 0
	_endless_pool = endless_rows()
	if game.get("pickups") and game.pickups:
		game.pickups.set("endless_coin_chance", clampf(timeline.endless_value("coin_chance", Run.stage), 0.0, 1.0))
	endless_started.emit()
	_tick_endless(0.0)


## Endless's clock (from _process): every `every` seconds the next wave, its numbers that much tougher (source_for), its
## creatures that little faster (_apply_mults), the wave's creatures round the hero.
func _tick_endless(delta: float) -> void:
	Run.endless_time += delta
	var w: int = timeline.endless_wave_at(Run.endless_time, Run.stage)
	if w <= _endless_wave:
		return
	_endless_wave = w
	_endless_speed = float(timeline.endless_mults(w, Run.stage)["speed"])
	_apply_mults()
	# pass 106 (lane ENDLESS): the wave's speed reaches every creature already on the sand too, not only the new ones
	game.enemies.set_endless_speed(_endless_speed)
	spawn_endless_wave(w)
	endless_wave_started.emit(w)


## The late roster Endless draws from: the mix rows (WaveTimeline.row_in_mix: one creature, no elite, not a special, not a
## once row; either channel, any pace) open at some second of the stage's last `roster_window` seconds, each weighing its
## weight at its last open second there; [{row, w}]. The map's skins when no row is open there.
func endless_rows() -> Array:
	var out: Array = []
	if timeline == null:
		return out
	var end: float = timeline.stage_end(Run.stage)
	var win := maxf(timeline.endless_value("roster_window", Run.stage), 1.0)
	for r in timeline.roster:
		if not (r is Dictionary) or not WaveTimeline.row_in_mix(r):
			continue
		var t0 := float(r.get("t", 0.0))
		var until := float(r["until"]) if r.get("until") != null else INF
		if t0 >= end or until <= end - win:
			continue
		var w := _roster_weight(r, maxf(minf(until, end) - 0.5, t0))
		if w <= 0.0 or _row_def(r) == null:
			continue
		out.append({"row": r, "w": w})
	if out.is_empty() and map != null:
		for id in map.skins.values():
			if Registry.enemy(str(id)) != null:
				out.append({"row": {"enemy": str(id), "t": 0.0}, "w": 1.0})
	return out


## One row of the Endless pool by weight ({} when the pool is empty or every row's creature is at its live limit).
## Pass 87 (the lead; lane TUNE found hammer giants, bull beetles and spit cacti piling up in Endless): a row whose
## creature is at its `max_alive` (the row's own when its stats set one) is left out of the draw, as in the roster's
## (_roster_open); the waves and the fill take only what is left of that limit (_endless_room).
func _endless_pick() -> Dictionary:
	var em: EnemyManager = game.enemies if game != null else null
	var open: Array = []
	var total := 0.0
	for p: Dictionary in _endless_pool:
		var def: EnemyDef = _row_def(p["row"])
		if em != null and def != null and def.max_alive > 0 and em.alive_of(def.id) >= def.max_alive:
			continue
		open.append(p)
		total += float(p["w"])
	if total <= 0.0:
		return {}
	var pick := _rng.randf() * total
	for p: Dictionary in open:
		pick -= float(p["w"])
		if pick <= 0.0:
			return p["row"]
	return (open[open.size() - 1] as Dictionary)["row"]


## How many more of `def` Endless may bring now: what is left of its max_alive (no limit: `want`).
func _endless_room(def: EnemyDef, want: int) -> int:
	if def == null or def.max_alive <= 0 or game == null:
		return want
	return mini(want, maxi(def.max_alive - game.enemies.alive_of(def.id), 0))


## Endless wave `w`: endless_wave_size(w) creatures of the pool in packs (the row's pack, 1..12) from all round the hero,
## past the live cap (the hard cap still holds), with the wave's numbers. Returns how many came.
func spawn_endless_wave(w: int) -> int:
	if game == null or game.player == null or _endless_pool.is_empty():
		return 0
	var em: EnemyManager = game.enemies
	var left: int = mini(timeline.endless_wave_size(w, Run.stage), timeline.hard_cap - em.alive_count())
	var before: int = em.alive_count()
	var guard := 0
	while left > 0 and guard < 256:
		guard += 1
		var row := _endless_pick()
		var def: EnemyDef = _row_def(row)
		if def == null:
			break
		var n: int = _endless_room(def, mini(clampi(int(row.get("pack", def.pack_size)), 1, 12), left))
		if n <= 0:
			continue
		_spawn_group(def.id, n, "pack", n, null, str(row.get("variant", "")), _stats_of(row), _around_point, _row_src(row))
		left -= n
	return maxi(em.alive_count() - before, 0)


## Between the waves (the spawn check, every spawn_interval): the crowd kept up to Endless's cap (current_cap) from the
## pool, a burst at a time through the spawn points, with the wave's numbers.
func _endless_fill() -> void:
	if game == null or game.player == null or _endless_pool.is_empty():
		return
	var em: EnemyManager = game.enemies
	var room: float = float(current_cap()) - em.cap_load()
	var bodies: int = timeline.hard_cap - em.alive_count()
	if room <= 0.0 or bodies <= 0:
		return
	var burst: float = minf(float(_rng.randi_range(timeline.burst_min, timeline.burst_max)), room)
	var guard := 0
	while burst > 0.0 and bodies > 0 and guard < 32:
		guard += 1
		var row := _endless_pick()
		var def: EnemyDef = _row_def(row)
		if def == null:
			return
		var share: float = maxf(def.cap_share, 0.05)
		var n: int = _endless_room(def, mini(mini(clampi(int(row.get("pack", def.pack_size)), 1, 12), maxi(int(ceil(burst / share)), 1)), bodies))
		if n <= 0:
			continue
		_spawn_group(def.id, n, "pack", n, null, str(row.get("variant", "")), _stats_of(row), Callable(), _row_src(row))
		burst -= float(n) * share
		bodies -= n


## A kill's XP share now (Game's drop): Endless's `xp_share`, 1 outside Endless.
func xp_share() -> float:
	if phase != Phase.ENDLESS or timeline == null:
		return 1.0
	return maxf(timeline.endless_value("xp_share", Run.stage), 0.0)


## Pass 107 (lane XPT): the stage's own XP multiplier on a kill's XP (Game's drop; its stage_list entry's `xp_mult`,
## 1 without one or without a timeline). It holds through the stage's boss, its portal and its Endless (times xp_share).
func stage_xp_mult() -> float:
	if timeline == null:
		return 1.0
	return timeline.stage_xp_mult(Run.stage)


func _spawn_burst(due: Array = []) -> void:
	# pass 81 (lane PACE): what a waves row's last wave still owes takes the room first (pass 83: at the spawn check, not
	# at an own-interval row's draw, `due`)
	if due.is_empty():
		_row_waves_owed()
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
		bodies = _burst_from(_roster_open(regular), room, bodies, due)
	var hell_room: float = timeline.hell_cap_at(Run.stage) * float(cap) - hell_load
	if hell_room > 0.0 and bodies > 0 and not hell_rows.is_empty():
		_burst_from(_roster_open(hell_rows), hell_room, bodies, due)


## One burst from `roster` (weighted rows) into `room` of cap and `bodies` of the hard cap; returns the bodies left.
func _burst_from(roster: Array, room: float, bodies: int, due: Array = []) -> int:
	# pass 81 (lane PACE): a row paced as waves is not in the continuous draw unless it trickles
	roster = roster.filter(func(r) -> bool: return not (r is Dictionary) or WaveTimeline.row_drawn(r))
	# pass 84 (lane SPAWN): a continuous elite row waits for colour (colour_after_kills), as every coloured Elite does
	if not colour_open():
		roster = roster.filter(func(r) -> bool: return not (r is Dictionary) or WaveTimeline.row_elite(r) == "")
	# pass 83 (lane TIMELINE): a row with its own `interval` draws on its own clock (`due`), the others at the spawn check;
	# either way the burst is cut to the drawing rows' share of the channel's weight (_interval_part)
	var frac := 1.0
	if not due.is_empty() or roster.any(func(r) -> bool: return row_has_interval(r)):
		var part := _interval_part(roster, due)
		roster = part[0]
		frac = float(part[1])
	if roster.is_empty():
		return bodies
	var burst: float = minf(float(_rng.randi_range(timeline.burst_min, timeline.burst_max)) * frac, room)
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
		var ci := 0
		for k in range(roster.size()):
			if float(ws[k]) <= 0.0:
				# a row at weight 0 is never drawn (randf() may return exactly 0)
				continue
			chosen = roster[k]
			ci = k
			pick -= float(ws[k])
			if pick <= 0.0:
				break
		# the row's creature with its overrides (pass 53): its cap_share, pack and numbers may be the row's own; pass 84
		# (lane SPAWN): a list or "roster" row's creature is drawn here (_row_pick84, kept in _pick84 for the spawn)
		var def: EnemyDef = _row_def(chosen) if WaveTimeline.row_single_enemy(chosen) else _row_pick_def84(chosen)
		if def == null:
			return bodies
		var share: float = maxf(def.cap_share, 0.05)
		# pass 83 (lane TIMELINE): a cut burst holding less than one creature brings one with that chance (the expected
		# count kept: a light row on its own clock is not rounded up to a creature at every draw)
		if frac < 1.0 and burst < share and _rng.randf() * share >= burst:
			break
		# the row's `pack` and `pattern` (pass 53): a pack at one point, a scatter each at its own, a single one a draw;
		# a ring (pass 57) is the pack round the hero and in_front the pack from the top of the screen, counted as a pack
		var pattern := str(chosen.get("pattern", "pack"))
		var pack: int = maxi(int(chosen.get("pack", def.pack_size)), 1)
		var n: int = mini(mini(pack, maxi(int(ceil(burst / share)), 1)), bodies)
		if pattern == "single":
			n = 1
		# pass 110 (lane BOSS): a creature's max_alive holds inside one burst too (_roster_open checks it once, before the
		# burst, and a burst of several packs went past it: Nightfall's cacti, max alive 4, stood 14 strong); a row whose
		# creature is at its limit leaves the rest of this burst
		if def.max_alive > 0:
			n = mini(n, def.max_alive - (game.enemies as EnemyManager).alive_of(def.id))
			if n <= 0:
				total_w -= float(ws[ci])
				ws[ci] = 0.0
				if total_w <= 0.000001:
					break
				continue
		# pass 112 (lane MONK): a squad creature comes as one whole squad, never cut by the burst; a squad that does not fit
		# waits, and the row sits out the rest of this burst (squad_take)
		var sq_n := squad_take(def, chosen, 0, mini(bodies, int(floor(room / share))))
		if sq_n == 0:
			total_w -= float(ws[ci])
			ws[ci] = 0.0
			if total_w <= 0.000001:
				break
			continue
		if sq_n > 0:
			n = sq_n
		# the row's numbers as its first spawn of the run fixed them (pass 58, R1); pass 84: a row with the new keys
		# spawns through _spawn_drawn84 (its pick, elite, special, ring_radius, banner)
		if _row_new84(chosen, -1):
			_spawn_drawn84(chosen, def, n)
		else:
			_spawn_group(def.id, n, pattern, pack, null, str(chosen.get("variant", "")), _stats_of(chosen), Callable(), _row_src(chosen))
		burst -= float(n) * share
		bodies -= n
		# pass 112 (lane MONK): a squad is a draw of its own: it takes the rest of this burst
		if sq_n > 0:
			break
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
			_waves.append({"id": "w%d" % k, "k": k, "alt": {}, "spawned": 0, "next_t": 0.0, "toasted": false, "done": true})
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
		_waves.append({"id": str(w.get("id", "w%d" % k)), "k": k, "alt": alt, "spawned": 0, "next_t": float(w.get("t", 0.0)), "toasted": false, "done": false})


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
	# the wave's numbers as its first burst of the run fixed them, from its `t` and the rolled alt's stats (pass 58, R1)
	var key: String = "wave#%d" % int(ws["k"]) if ws.has("k") else "wave:" + str(ws.get("id", ""))
	var src := source_for(key, float(w.get("t", 0.0)), stats)
	var came := _spawn_group(id, n, str(w.get("pattern", "pack")), int(alt.get("pack", def.pack_size)), mod, variant, stats, Callable(), src)
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


# ---------------------------------------------------------------- a continuous row's own interval (pass 83, lane TIMELINE)

## Garry (2026-10-16): "for Continuous spawning, I would still like to control the interval of continuous spawning, the
## 0.7s can be a default." A roster row in the continuous draw (a continuous row, or a waves row that trickles) may carry
## `interval` (seconds): it is then drawn on its own clock, every `interval` real seconds from the frame it opens (through
## boss fights and the portal wait, like the spawn check), instead of at the director's spawn check (`spawn_interval`).
## Every draw (the spawn check for the rows without the key, a row's own clock for a row with it) takes
## randi(burst_min..burst_max) load units x the drawing rows' weight / the weight of every open drawn row of the channel,
## so a row's expected rate is a burst x (its weight / the channel's) / its interval: the map's spawn_interval draws as
## often as today, half of it twice as often, at the same size. A map where no open row has the key plays exactly as
## before (the same dice). Below ROW_INTERVAL_MIN counts as it.
const ROW_INTERVAL_MIN := 0.1

## Seconds until each own-interval row's next draw (pass 83; key: _row_key_at), on the real clock; a row seen open for
## the first time draws at once. Cleared when a run starts.
var _row_draw_left: Dictionary = {}


## Whether roster row `r` carries its own continuous interval (`interval`, a number above 0).
static func row_has_interval(r) -> bool:
	if not (r is Dictionary) or not (r as Dictionary).has("interval"):
		return false
	var v = r["interval"]
	return (v is float or v is int) and float(v) > 0.0


## Seconds between roster row `r`'s continuous draws: its `interval` (at least ROW_INTERVAL_MIN), else `spawn_interval`.
static func row_draw_interval(r: Dictionary, spawn_interval: float) -> float:
	if row_has_interval(r):
		return maxf(float(r["interval"]), ROW_INTERVAL_MIN)
	return spawn_interval


## The own-interval rows' clocks (pass 83), every frame after the spawn check: the open drawn rows with `interval` whose
## clock ran out draw together (_spawn_burst with them as `due`), each clock then set to its interval again.
func _tick_row_intervals(delta: float) -> void:
	if timeline == null or game == null or game.player == null:
		return
	# the rows open as the spawn check reckons them (the frozen clock a second back, _spawn_burst)
	var tr := Run.elapsed if phase == Phase.NORMAL else Run.elapsed - 1.0
	var due: Array = []
	for k in range(timeline.roster.size()):
		var r = timeline.roster[k]
		if not row_has_interval(r) or not WaveTimeline.row_drawn(r):
			continue
		if tr < float(r.get("t", 0.0)) or tr >= float(r.get("until", 1e9)):
			continue
		var key := _row_key_at(r, k)
		var left: float = float(_row_draw_left.get(key, 0.0)) - delta
		if left <= 0.0:
			due.append(r)
			left = row_draw_interval(r, timeline.spawn_interval)
		_row_draw_left[key] = left
	if not due.is_empty():
		_spawn_burst(due)


## The rows of `roster` that draw now and their share of its weight (pass 83): the `due` ones (an own-interval draw), or
## with `due` empty the ones without their own interval (the spawn check). [rows, frac].
func _interval_part(roster: Array, due: Array) -> Array:
	var total := 0.0
	var part := 0.0
	var rows: Array = []
	for r in roster:
		var w := _roster_weight(r, Run.elapsed)
		total += w
		var mine := due.any(func(d) -> bool: return is_same(d, r)) if not due.is_empty() else not row_has_interval(r)
		if mine:
			rows.append(r)
			part += w
	return [rows, part / total if total > 0.0 else 0.0]


# ---------------------------------------------------------------- a roster row paced as waves (pass 81, lane PACE)

## Each waves row's state this run (pass 81), keyed like its fixed numbers (row_key: "row:<id>#<index>"): {k (the last
## wave index that fell due, -1 before the first), owed (what its last wave still owes), came (every creature its waves
## brought), waves (the waves that fell due while it weighed above 0)}. Cleared when a run starts.
var _row_waves: Dictionary = {}


## The roster rows paced as waves (pass 81, lane PACE; Garry: "Add the ability to control the pacing of the waves. I mean
## the frequency at which enemy waves come"), from _process in the normal phase: a row with `pace` "waves" open now
## (t <= clock < until) sends wave k as the clock passes t + offset + k x every (WaveTimeline.row_wave_index), `count`
## creatures in its pattern (_row_wave_spawn), when the row weighs above 0 at that wave's second (its presence keyframes
## gate the waves; the weight's size scales nothing). A new wave drops what the last one still owed. A clock that jumped
## (a tool) fires only the latest wave due, never a backlog. Such a row is not in the continuous draw unless it has
## `trickle` (_burst_from).
func _tick_row_waves() -> void:
	if timeline == null or game == null or game.player == null:
		return
	var t := Run.elapsed
	for k in range(timeline.roster.size()):
		var r = timeline.roster[k]
		if not (r is Dictionary) or not WaveTimeline.row_paced(r):
			continue
		# pass 84 (lane SPAWN): a row with the new keys (once, a timer, a list or "roster" creature, elite, special,
		# banner, ring_radius, chance, t_jitter) runs its own schedule; a plain waves row plays pass 81's below, unchanged
		if _row_new84(r, k):
			_tick_row84(r, k, t)
			continue
		if t < float(r.get("t", 0.0)) or (r.get("until") != null and t >= float(r["until"])):
			continue
		var i := WaveTimeline.row_wave_index(r, t)
		if i < 0:
			continue
		var key := _row_key_at(r, k)
		var st: Dictionary = _row_waves.get(key, {"k": -1, "owed": 0, "came": 0, "waves": 0})
		_row_waves[key] = st
		if i <= int(st["k"]):
			continue
		st["k"] = i
		st["owed"] = 0
		if _roster_weight(r, WaveTimeline.row_wave_time(r, i)) <= 0.0:
			continue
		var def: EnemyDef = _row_def(r)
		if def == null:
			continue
		st["waves"] = int(st["waves"]) + 1
		# (pass 112, lane MONK: a squad creature's wave owes one squad's size drawn, squad_pack)
		st["owed"] = WaveTimeline.row_wave_count(r, squad_pack(def))
		_row_wave_spawn(r, st, def)


## What a waves row's wave still owes (`st.owed`), now (pass 81): cut to the hard cap's room and the creature's max_alive
## and, with `respect_cap` (the default), to the free room of the row's channel (at least one while there is any: the
## waves' rule, _wave_burst); in the row's pattern and pack, with its variant, its overrides and its fixed numbers
## (_row_src: the same as its trickle's). Whatever does not fit stays owed (_row_waves_owed). Returns how many came.
func _row_wave_spawn(r: Dictionary, st: Dictionary, def: EnemyDef) -> int:
	var em: EnemyManager = game.enemies
	# pass 112 (lane MONK): a squad creature's wave comes one whole squad a call (squad_take); what does not fit waits
	if def.is_squad():
		var sq_n := squad_take(def, r, int(st["owed"]), _squad_fit(def, r))
		if sq_n <= 0:
			return 0
		var sc := _spawn_group(def.id, sq_n, "pack", sq_n, null, str(r.get("variant", "")), _stats_of(r), Callable(), _row_src(r))
		st["owed"] = maxi(int(st["owed"]) - sc, 0)
		st["came"] = int(st["came"]) + sc
		return sc
	var n := int(st["owed"])
	# pass 84 (lane SPAWN): respect_hard_cap false = only the body limit (EnemyManager.MAX), as a swarm event was
	if bool(r.get("respect_hard_cap", true)):
		n = mini(n, timeline.hard_cap - em.alive_count())
	if def.max_alive > 0:
		n = mini(n, def.max_alive - em.alive_of(def.id))
	if n > 0 and bool(r.get("respect_cap", true)):
		var room := _channel_room(str(r.get("channel", "regular")))
		if room <= 0.0:
			return 0
		n = mini(n, maxi(int(ceil(room / maxf(def.cap_share, 0.05))), 1))
	if n <= 0:
		return 0
	var pack: int = maxi(int(r.get("pack", def.pack_size)), 1)
	var came := _spawn_group(def.id, n, str(r.get("pattern", "pack")), pack, null, str(r.get("variant", "")), _stats_of(r), Callable(), _row_src(r))
	st["owed"] = maxi(int(st["owed"]) - came, 0)
	st["came"] = int(st["came"]) + came
	return came


## The waves rows' leftovers (pass 81), first thing at every spawn check of the normal phase: a wave the cap cut comes in
## as the room frees, ahead of the continuous draw, until the row's next wave falls due (which drops the rest,
## _tick_row_waves) or the row closes. A boss fight and the portal wait hold it, as they hold the clock.
func _row_waves_owed() -> void:
	if _row_waves.is_empty() or phase != Phase.NORMAL or timeline == null or game == null or game.player == null:
		return
	var t := Run.elapsed
	for k in range(timeline.roster.size()):
		var r = timeline.roster[k]
		if not (r is Dictionary) or not WaveTimeline.row_paced(r):
			continue
		# pass 84 (lane SPAWN): the new rows' leftovers (_row_owed84)
		if _row_new84(r, k):
			_row_owed84(r, k)
			continue
		var st = _row_waves.get(_row_key_at(r, k))
		if not (st is Dictionary) or int(st["owed"]) <= 0:
			continue
		var def: EnemyDef = _row_def(r)
		if def == null or (r.get("until") != null and t >= float(r["until"])):
			st["owed"] = 0
			continue
		_row_wave_spawn(r, st, def)


## A roster row's key (row_key's form) from its place `k` in the timeline's roster, without row_key's search (pass 81).
static func _row_key_at(r: Dictionary, k: int) -> String:
	var id := str(r.get("id", ""))
	return ("row:%s#%d" % [id, k]) if id != "" else "row#%d" % k


## A waves row's state this run (pass 81; the tests, a tool): {k, owed, came, waves} as a copy for the roster row at
## index `k`, {} before its first wave fell due or for a row that is not paced.
func row_wave_state(k: int) -> Dictionary:
	if timeline == null or k < 0 or k >= timeline.roster.size() or not (timeline.roster[k] is Dictionary):
		return {}
	var s = _row_waves.get(_row_key_at(timeline.roster[k], k))
	return (s as Dictionary).duplicate() if s is Dictionary else {}


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
	# a special's numbers are the moment it comes (pass 58, R1), or a row's that brings it then (event_numbers)
	var en := event_numbers(id, "", {})
	em.spawn(id, _spawn_point(), null, 1.0, 1.0, "", en["stats"], en["src"])


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
## Pass 69 (lane SALT): `luck` multiplies the per-kill chance (Thing About Luck's x3 for a creature killed in the salt).
func drop_pickup_from(def: EnemyDef, at: Vector3, elite: bool, luck: float = 1.0) -> void:
	var pk: Dictionary = timeline.pickups
	var roster: Array = pk.get("roster", [])
	# pass 53 (the wave schema): the creature's own roster of power-ups when it has one ({id: weight}, no hard bias),
	# and its own factor on the per-kill chance
	if not def.pickup_weights.is_empty():
		roster = []
		for id in def.pickup_weights.keys():
			roster.append({"id": str(id), "weight": float(def.pickup_weights[id])})
	# pass 62: the Pocket Watch's powerup_chance on the hero's sheet (x1.12 at level 5)
	var per_kill := float(pk.get("per_kill", 0.0)) * def.pickup_chance_mult * powerup_chance_mult() * maxf(luck, 0.0)
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


## The factor the hero's sheet puts on how often power-ups appear (pass 62, the Pocket Watch's `powerup_chance`: 1
## without it, 1.12 at level 5): the per-kill chance is multiplied by it, a timed roster's interval divided.
func powerup_chance_mult() -> float:
	if Run.player_sheet == null:
		return 1.0
	return maxf(Run.player_sheet.get_stat("powerup_chance", 1.0), 0.0)


## One pickup from the map's roster, a short run away from the hero, then the next one is scheduled.
func _spawn_pickup() -> void:
	var pk: Dictionary = timeline.pickups
	var roster: Array = pk.get("roster", [])
	# pass 62: the Pocket Watch brings a timed roster's power-ups round sooner (a map with an `interval`; none on Red Canyon)
	var interval := float(pk.get("interval", 75.0)) / maxf(powerup_chance_mult(), 0.01)
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
## Pass 58 (the review of pass 57: by the wall, points past it were clamped onto the wall beside the hero): a point past
## the wall turns round the least way that keeps it inside, at the same distance (EnemyManager.point_inside), so it is
## never nearer him than 19 m. `avoid` (the in_front pattern's points) also steps it a few degrees or a metre or two off a
## rock's painting or the lake.
func _point_at(a: float, avoid := false) -> Vector3:
	var player: Node3D = game.player
	var mb: MapBase = game.map
	var r := _rng.randf_range(19.0, 24.0)
	var from: Vector3 = player.global_position
	var lim := _spawn_lim()
	var p := EnemyManager.point_inside(from, a, r, lim)
	if avoid and mb and not EnemyManager.spawn_clear(mb, p):
		# past the lake first when the point is in it (the fix round: the steps reach 12 degrees, and the oasis spans some
		# 40 degrees 20 m off), round the yaw that clears it the least way, then the other way; else the steps round `a`
		var turns: Array = EnemyManager.lake_turns(mb, from, a, r)
		var bases: Array = turns if not turns.is_empty() else [a]
		var done := false
		for b: float in bases:
			for t: Vector2 in AVOID_STEPS:
				var q := EnemyManager.point_inside(from, b + deg_to_rad(t.x), r + t.y, lim)
				if EnemyManager.spawn_clear(mb, q):
					p = q
					done = true
					break
			if done:
				break
	return mb.clamp_to_arena(p) if mb else p


## The steps (degrees round, metres out) _point_at tries for a point on a rock's painting or in the lake (pass 58), the
## point itself first.
const AVOID_STEPS := [Vector2(0, 0), Vector2(4, 0), Vector2(-4, 0), Vector2(0, 1.5), Vector2(0, -1.5), Vector2(8, 0),
	Vector2(-8, 0), Vector2(4, 1.5), Vector2(-4, 1.5), Vector2(12, 0), Vector2(-12, 0), Vector2(8, -1.5), Vector2(-8, -1.5)]


## The yaw of the next spawn point (_spawn_point): 0 = -Z, the hero's `facing` convention.
func _spawn_angle() -> float:
	var ss: Dictionary = timeline.spawn_sides if timeline else {}
	if str(ss.get("mode", "facing")) == "sides":
		var side := _pick_side(ss)
		if side != "":
			# the camera's yaw (0 under the fixed camera: screen up is north), so follow mode keeps its sides too
			return _camera_yaw() + float(SIDE_TURN[side]) + _rng.randf_range(-SIDE_HALF_ARC, SIDE_HALF_ARC)
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
## elite format; EnemyManager.spawn_ring takes no modifier), on the event's fixed numbers `src` (pass 58). Returns how many
## came.
func _spawn_elite_ring(id: String, n: int, mod: EliteModDef, variant: String, stats: Dictionary, src: Dictionary = {}) -> int:
	var em: EnemyManager = game.enemies
	var mb: MapBase = game.map
	var center: Vector3 = game.player.global_position
	var came := 0
	var turn := _rng.randf() * TAU
	# +-0.1 radians round the ring as before; by the wall the ring keeps to the arc inside it (pass 58, ring_spots)
	var slide := 0.1 / (TAU / float(maxi(n, 1)))
	for p: Vector3 in EnemyManager.ring_spots(center, ELITE_RING_RADIUS, n, _spawn_lim(), _rng, turn, slide, 0.0, mb):
		if em.spawn(id, mb.clamp_to_arena(p) if mb else p, mod, 1.0, 1.0, variant, stats, src) >= 0:
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
	var row_stats := false
	if enemy_id == "":
		# pass 84 (lane SPAWN): drawn from the mix rows only (WaveTimeline.row_in_mix)
		var roster := elite_candidates(_roster_open(WaveTimeline.mix_rows(timeline.roster_at(Run.elapsed))))
		if roster.is_empty():
			return
		# a roster creature comes as its row spawns it (pass 53: the row's variant and overrides)
		row = _weighted_elite_row(roster)
		enemy_id = str(row.get("enemy", ""))
		if variant == "":
			variant = str(row.get("variant", ""))
		if stats.is_empty():
			stats = _stats_of(row)
			row_stats = true
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
	# an elite event's numbers are the moment it comes (pass 58, R1), or, the fix round, a row's that brings the same
	# creature then (event_numbers); one drawn from a row with the row's own stats comes on that row's numbers
	var src: Dictionary
	if row_stats:
		src = _row_src(row)
	else:
		var en := event_numbers(enemy_id, variant, stats)
		stats = en["stats"]
		src = en["src"]
		def = Registry.enemy_with(enemy_id, variant, stats)
		if def == null:
			return
	var came := 0
	match _elite_format(def):
		"pack":
			came = em.spawn_pack(enemy_id, _spawn_point(), pack, mod, variant, stats, src)
		"ring":
			came = _spawn_elite_ring(enemy_id, pack, mod, variant, stats, src)
		_:
			came = 1 if em.spawn(enemy_id, _spawn_point(), mod, 1.0, 1.0, variant, stats, src) >= 0 else 0
	if came > 0:
		var title := ("%s %s" % [mod.display_name, def.display_name]).to_upper()
		game.toast(title if came == 1 else "%s ×%d" % [title, came], mod.outline)
		_log84("elite", enemy_id, came)


func _cull_behind() -> void:
	var em: EnemyManager = game.enemies
	var player: Node3D = game.player
	var fwd: Vector3 = player.forward()
	for i in range(em.pool_max):
		if em.alive[i] == 0 or i == em.boss_index or i == elite_index:
			continue
		if (em.types[em.type_idx[i]]["def"] as EnemyDef).brain == "artillery":
			continue
		# pass 95 (lane WORLD): with the map's despawn rule on, a regular creature left behind despawns out of view
		# (EnemyManager._tick_despawn) instead of being moved up ahead of him; the ones that rule never takes (a special,
		# an Elite, a coloured special, a boss's summon, one held, in the air or rising) are moved up as before
		if em.despawn_enabled() and em.despawn_kind(i):
			continue
		var d := em.pos[i] - player.global_position
		d.y = 0.0
		if d.length() > 30.0 and d.normalized().dot(fwd) < -0.3:
			var p := _spawn_point()
			em.pos[i] = Vector3(p.x, em._height(p.x, p.z), p.z)


# ---------------------------------------------------------------- one spawning language (pass 84, lane SPAWN)

## Garry (2026-10-16): "spawning options are important to me ... But I do agree that there are too many ways of spawning
## an enemy right now". Every spawn a map makes is a roster row now (WaveTimeline "Pass 84" keys, docs/waves_schema.md):
## a swarm is a "once" row (respect_cap false, pattern ring with ring_radius 16, its count, banner "SWARM!"), a coloured
## elite a "once" row with `elite`, Elites-every a waves row of the "roster" creature, count 1, elite "random", `every`
## its interval. An old map's swarm / elite / elite_every events and waves[] still play through their own code above.
## Rows that use none of the new keys play exactly as before (the same functions, the same dice).

## Each once / waves row's roll for this run (key _row_key_at): {skip: its `chance` failed, shift: its draw inside
## +- `t_jitter` (the whole row moves by it)}. Only rows that carry either key are here (no dice for the others).
var _row_roll: Dictionary = {}
## The creature a list or "roster" row drew for the continuous draw in hand (_row_pick_def84 -> _spawn_drawn84).
var _pick84: Dictionary = {}
## A "once" row's wave found more than this many seconds past its second is dropped (the clock jumped: smoke_run,
## hell_check, the arena's clock); in a run the rows tick every frame of the normal phase, so it never is.
const ROW_STALE_S := 2.0
## The rows that wanted to spawn and could not (the cap or the hard cap full), key -> the run clock it last happened
## (lane SIMVIEW's starving series may read it; the tests).
var _starve84: Dictionary = {}


## The once and waves rows' chance and t_jitter for this run (start()), in the roster's order, a row's jitter before its
## chance (the events' order, _roll_events). A shift never moves a row before the run's start.
func _roll_rows() -> void:
	_row_roll.clear()
	if timeline == null:
		return
	for k in range(timeline.roster.size()):
		var r = timeline.roster[k]
		if not (r is Dictionary) or not WaveTimeline.row_paced(r):
			continue
		var chance := float(r.get("chance", 1.0))
		var jitter := float(r.get("t_jitter", 0.0))
		if chance >= 1.0 and jitter <= 0.0:
			continue
		var roll := {"skip": false, "shift": 0.0}
		if jitter > 0.0:
			roll["shift"] = maxf(_rng.randf_range(-jitter, jitter), -float(r.get("t", 0.0)))
		if chance < 1.0 and _rng.randf() >= chance:
			roll["skip"] = true
		_row_roll[_row_key_at(r, k)] = roll


## A row's roll this run (_roll_rows), {} when it has none (the tests, the arena).
func row_roll(k: int) -> Dictionary:
	if timeline == null or k < 0 or k >= timeline.roster.size() or not (timeline.roster[k] is Dictionary):
		return {}
	var v = _row_roll.get(_row_key_at(timeline.roster[k], k))
	return (v as Dictionary).duplicate() if v is Dictionary else {}


## Whether row `r` (at roster index `k`, -1 = unknown) uses the pass 84 path: outside the mix (once, a list or "roster"
## creature, elite, special), a timer (every [min, max], an elite row), a ring_radius or a banner, or a roll this run.
func _row_new84(r: Dictionary, k: int) -> bool:
	if not WaveTimeline.row_in_mix(r) or WaveTimeline.row_timer(r) or r.has("ring_radius") or r.has("banner"):
		return true
	return k >= 0 and _row_roll.has(_row_key_at(r, k))


## A waves row's gap to its next wave (pass 84): `every` [min, max] a fresh draw inside it, a number as it is; 0 or less
## (and a once row) = no next wave.
func _row_every_draw(r: Dictionary) -> float:
	if str(r.get("pace", "")) == "once":
		return 0.0
	var v = r.get("every", WaveTimeline.ROW_WAVE_EVERY_DEFAULT)
	if v is Array and not (v as Array).is_empty():
		return _interval_of(v)
	return WaveTimeline.row_wave_every(r)


## One pass 84 paced row's tick (from _tick_row_waves, the normal phase): on its own clock (the run clock less its
## t_jitter shift), inside its window (t <= clock < until), its next wave falls due on the fixed rhythm (t + offset +
## k x every, pass 81's rule) or, for a timer row (every [min, max], an elite row), a gap after the wave it last fired (a
## fresh draw; an elite row's gap shortened by Hot Sauce, elite_pace, as elite_every's was; while colour is closed an
## elite wave waits, asking again a second later). A wave due while the row weighs 0 does not come (pass 81). An elite
## row without a `pattern` brings `count` arrivals through the coloured-elite spawn (_row_elite_wave); every other row
## owes `count` creatures (default its pack, else the creature's pack size) and spawns what fits (_row_spawn84), the
## rest as room frees until its next wave or its end (_row_owed84).
func _tick_row84(r: Dictionary, k: int, t: float) -> void:
	var key := _row_key_at(r, k)
	var roll: Dictionary = _row_roll.get(key, {})
	if bool(roll.get("skip", false)):
		return
	var rt := t - float(roll.get("shift", 0.0))
	if rt < float(r.get("t", 0.0)) or (r.get("until") != null and rt >= float(r["until"])):
		return
	var st: Dictionary = _row_waves.get(key, {"k": -1, "owed": 0, "came": 0, "waves": 0})
	_row_waves[key] = st
	var elite := WaveTimeline.row_elite(r)
	var wave_t := rt
	if WaveTimeline.row_timer(r):
		if not st.has("next"):
			st["next"] = WaveTimeline.row_wave_start(r)
		if rt < float(st["next"]):
			return
		if elite != "" and not colour_open():
			st["next"] = rt + 1.0
			return
		st["k"] = int(st["k"]) + 1
		var gap := _row_every_draw(r)
		st["next"] = rt + gap / (elite_pace() if elite != "" else 1.0) if gap > 0.0 else INF
	else:
		var i := WaveTimeline.row_wave_index(r, rt)
		if i < 0 or i <= int(st["k"]):
			return
		st["k"] = i
		wave_t = WaveTimeline.row_wave_time(r, i)
		if str(r.get("pace", "")) == "once" and rt - wave_t > ROW_STALE_S:
			# the clock jumped past it (a tool, the arena): dropped, as a skipped event was
			return
	st["owed"] = 0
	st["bannered"] = false
	if _roster_weight(r, wave_t) <= 0.0:
		return
	st["waves"] = int(st["waves"]) + 1
	if elite != "" and not r.has("pattern"):
		_row_elite_wave(r, st)
		return
	var pick: Dictionary = {}
	if str(r.get("enemy", "")) != WaveTimeline.ROW_ENEMY_ROSTER or r.get("enemy") is Array:
		pick = _row_pick84(r)
		if pick.is_empty():
			return
	st["pick"] = pick
	var pdef: EnemyDef = null
	if not pick.is_empty():
		pdef = Registry.enemy_with(str(pick["id"]), str(pick["variant"]), pick["stats"])
	# (pass 112, lane MONK: a squad creature's wave owes one squad's size drawn, squad_pack)
	st["owed"] = WaveTimeline.row_wave_count(r, squad_pack(pdef) if pdef else 1)
	_row_spawn84(r, k, st)


## A pass 84 row's leftovers (from _row_waves_owed: first thing at every spawn check of the normal phase).
func _row_owed84(r: Dictionary, k: int) -> void:
	var key := _row_key_at(r, k)
	var st = _row_waves.get(key)
	if not (st is Dictionary) or int(st["owed"]) <= 0:
		return
	var roll: Dictionary = _row_roll.get(key, {})
	var rt := Run.elapsed - float(roll.get("shift", 0.0))
	if r.get("until") != null and rt >= float(r["until"]):
		st["owed"] = 0
		return
	_row_spawn84(r, k, st)


## An elite row's wave (pass 84; the coloured-elite events' way): `count` arrivals (default 1), each through _spawn_elite
## with the row's creature (a list drawn by enemy_weights; "roster" = the mix rows' elite_weight draw), its modifier
## ("random" = any), variant and stats: alone, as its pack or a ring by the creature's elite_formats, with its toast. Like
## the events it ignores the cap and the hard cap (respect_cap is not read); the row's banner shows once a wave.
func _row_elite_wave(r: Dictionary, st: Dictionary) -> void:
	var n := maxi(int(r.get("count", 1)), 1)
	var el := WaveTimeline.row_elite(r)
	var mod_id := "" if el == "random" else el
	var e = r.get("enemy", "")
	for a in range(n):
		var id := ""
		if e is Array:
			id = _pick_id(e, r.get("enemy_weights", []))
		elif str(e) != WaveTimeline.ROW_ENEMY_ROSTER:
			id = str(e)
		_spawn_elite(id, mod_id, str(r.get("variant", "")), _stats_of(r))
	st["came"] = int(st["came"]) + n
	_row_banner84(r, st)


## The creature a row brings now (pass 84): {id, variant, stats, row (the row whose numbers it takes)} for its own
## creature, a list's draw by `enemy_weights` (an entry past their end weighs 1, a 0 never comes), or the "roster"
## creature: a mix row open now drawn by its elite_weight (elite_candidates), coming as that row spawns it unless this row
## sets its own variant or stats; {} when nothing can come.
func _row_pick84(r: Dictionary) -> Dictionary:
	var e = r.get("enemy", "")
	var variant := str(r.get("variant", ""))
	var stats := _stats_of(r)
	if e is Array:
		var lid := _pick_id(e, r.get("enemy_weights", []))
		return {} if Registry.enemy(lid) == null else {"id": lid, "variant": variant, "stats": stats, "row": r}
	if str(e) == WaveTimeline.ROW_ENEMY_ROSTER:
		var t := Run.elapsed if phase == Phase.NORMAL else Run.elapsed - 1.0
		var cands := elite_candidates(_roster_open(WaveTimeline.mix_rows(timeline.roster_at(t))))
		if cands.is_empty():
			return {}
		var drawn := _weighted_elite_row(cands)
		var own := not stats.is_empty()
		return {"id": str(drawn.get("enemy", "")), "variant": variant if variant != "" else str(drawn.get("variant", "")),
			"stats": stats if own else _stats_of(drawn), "row": r if own else drawn}
	return {} if Registry.enemy(str(e)) == null else {"id": str(e), "variant": variant, "stats": stats, "row": r}


## The fixed numbers a pass 84 pick plays (pass 58's R1 kept): a "once" row's are the moment's, or a mix row's that brings
## the same creature and look then (event_numbers, a swarm's rule: {stats, src}); a drawn mix row's are that row's; a
## row's own creature (one, or each of a list's) is fixed from the row's start.
func _pick_numbers84(r: Dictionary, pick: Dictionary) -> Dictionary:
	var id := str(pick["id"])
	var variant := str(pick["variant"])
	var stats: Dictionary = pick["stats"]
	if str(r.get("pace", "")) == "once":
		return event_numbers(id, variant, stats)
	var row: Dictionary = pick["row"]
	if not is_same(row, r):
		return {"stats": stats, "src": _row_src(row)}
	if WaveTimeline.row_single_enemy(r):
		return {"stats": stats, "src": _row_src(r)}
	return {"stats": stats, "src": source_for(row_key(r) + "|" + id, float(r.get("t", 0.0)), stats)}


## What a pass 84 row's wave still owes, now: cut to the hard cap's room (unless respect_hard_cap is false: the body limit
## only, the swarm events' rule), the creature's max_alive and, with respect_cap
## (the default), its channel's room (at least one while there is any: pass 81's rule); a "roster" row draws each
## creature (grouped by the row drawn). The rest stays owed. Returns how many came.
func _row_spawn84(r: Dictionary, k: int, st: Dictionary) -> int:
	var em: EnemyManager = game.enemies
	var key := _row_key_at(r, k) if k >= 0 else row_key(r)
	var n := int(st["owed"])
	# respect_hard_cap false: only the body limit (EnemyManager.MAX: em.spawn stops there), as the swarm events were
	if bool(r.get("respect_hard_cap", true)):
		n = mini(n, timeline.hard_cap - em.alive_count())
	var pick: Dictionary = st.get("pick", {})
	var def: EnemyDef = null
	if not pick.is_empty():
		def = Registry.enemy_with(str(pick["id"]), str(pick["variant"]), pick["stats"])
		if def == null:
			st["owed"] = 0
			return 0
		if def.max_alive > 0:
			n = mini(n, def.max_alive - em.alive_of(def.id))
	if n > 0 and bool(r.get("respect_cap", true)):
		var room := _channel_room(str(r.get("channel", "regular")))
		if room <= 0.0:
			_starve84[key] = Run.elapsed
			return 0
		n = mini(n, maxi(int(ceil(room / maxf(def.cap_share if def else 1.0, 0.05))), 1))
	# pass 112 (lane MONK): a squad creature's wave comes one whole squad a call (squad_take); what does not fit waits
	if def != null and def.is_squad():
		n = squad_take(def, r, int(st["owed"]), _squad_fit(def, r))
	if n <= 0:
		if int(st["owed"]) > 0:
			_starve84[key] = Run.elapsed
		return 0
	var came := 0
	if pick.is_empty():
		# the "roster" creature, drawn creature by creature, each group as its row spawns it
		var groups: Array = []
		for j in range(n):
			var p := _row_pick84(r)
			if p.is_empty():
				break
			var g: Dictionary = {}
			for x: Dictionary in groups:
				if is_same(x["pick"]["row"], p["row"]) and str(x["pick"]["id"]) == str(p["id"]):
					g = x
					break
			if g.is_empty():
				g = {"pick": p, "n": 0}
				groups.append(g)
			g["n"] = int(g["n"]) + 1
		for g: Dictionary in groups:
			came += _spawn_pick84(r, g["pick"], int(g["n"]))
	else:
		came = _spawn_pick84(r, pick, n)
	st["owed"] = maxi(int(st["owed"]) - came, 0)
	st["came"] = int(st["came"]) + came
	if came > 0:
		_row_banner84(r, st)
	return came


## `n` of a pick in row `r`'s pattern (pass 84): its numbers (_pick_numbers84), every one wearing the row's `elite`
## modifier when it has a pattern and colour is open ("random" = any), every one its coloured special with `special`;
## pattern "ring" with a `ring_radius` is the classic even ring of that radius round the hero (the swarm's, 16 m on the
## converted swarms; EnemyManager.spawn_ring, or the elite ring with a modifier), else the row's pattern as always
## (_spawn_group: the rows' ring is RING_RADIUS). Returns how many came.
func _spawn_pick84(r: Dictionary, pick: Dictionary, n: int) -> int:
	var em: EnemyManager = game.enemies
	var id := str(pick["id"])
	var variant := str(pick["variant"])
	var en := _pick_numbers84(r, pick)
	var stats: Dictionary = en["stats"]
	var src: Dictionary = en["src"]
	var def: EnemyDef = Registry.enemy_with(id, variant, stats)
	if def == null or n <= 0:
		return 0
	var mod: EliteModDef = null
	var el := WaveTimeline.row_elite(r)
	if el != "" and colour_open():
		mod = Registry.elites.get(el) if el != "random" else null
		if mod == null:
			var list := Registry.elites_list()
			if not list.is_empty():
				mod = list[_rng.randi() % list.size()]
	var pattern := str(r.get("pattern", "pack"))
	var pack: int = maxi(int(r.get("pack", def.pack_size)), 1)
	em.force_special = bool(r.get("special", false))
	var came := 0
	if pattern == "ring" and r.has("ring_radius"):
		var radius := maxf(float(r.get("ring_radius", RING_RADIUS)), 1.0)
		if mod == null:
			came = em.spawn_ring(id, n, game.player.global_position, radius, variant, stats, src)
		else:
			came = _spawn_elite_ring_at(id, n, mod, variant, stats, src, radius)
	else:
		came = _spawn_group(id, n, pattern, pack, mod, variant, stats, Callable(), src)
	em.force_special = false
	_log84("row", id, came)
	return came


## The elite ring (_spawn_elite_ring) at `radius` (pass 84: an elite row with pattern ring and a ring_radius).
func _spawn_elite_ring_at(id: String, n: int, mod: EliteModDef, variant: String, stats: Dictionary, src: Dictionary, radius: float) -> int:
	var em: EnemyManager = game.enemies
	var mb: MapBase = game.map
	var came := 0
	var turn := _rng.randf() * TAU
	var slide := 0.1 / (TAU / float(maxi(n, 1)))
	for p: Vector3 in EnemyManager.ring_spots(game.player.global_position, radius, n, _spawn_lim(), _rng, turn, slide, 0.0, mb):
		if em.spawn(id, mb.clamp_to_arena(p) if mb else p, mod, 1.0, 1.0, variant, stats, src) >= 0:
			came += 1
	return came


## The row's `banner` as a toast, once a wave (the first time it brings anything).
func _row_banner84(r: Dictionary, st: Dictionary) -> void:
	var b := str(r.get("banner", ""))
	if b == "" or bool(st.get("bannered", false)):
		return
	st["bannered"] = true
	game.toast(b, SWARM_COLOR)


## The continuous draw's creature for a list or "roster" row (pass 84): drawn now (_row_pick84) and kept in _pick84 for
## _spawn_drawn84; null when nothing can come.
func _row_pick_def84(r: Dictionary) -> EnemyDef:
	_pick84 = _row_pick84(r)
	if _pick84.is_empty():
		return null
	return Registry.enemy_with(str(_pick84["id"]), str(_pick84["variant"]), _pick84["stats"])


## `n` of a continuous pass 84 row's draw (from _burst_from and the floor): its own creature or the pick in hand.
func _spawn_drawn84(r: Dictionary, def: EnemyDef, n: int) -> void:
	var pick: Dictionary = _pick84
	if WaveTimeline.row_single_enemy(r):
		pick = {"id": def.id, "variant": str(r.get("variant", "")), "stats": _stats_of(r), "row": r}
	if pick.is_empty():
		return
	_spawn_pick84(r, pick, n)
	_pick84 = {}


## The rows that could not spawn since run second `since` (_starve84 keys; the cap or the hard cap was full).
func starving_since(since: float) -> Array:
	var out: Array = []
	for key: String in _starve84.keys():
		if float(_starve84[key]) >= since:
			out.append(key)
	return out


# ---------------------------------------------------------------- the density floor (pass 84, lane SPAWN)

## The most creatures one frame's floor fill brings (a limit on a floor typed far above the cap).
const FLOOR_FILL_MAX := 64


## The lead's design ("a density floor (minimum alive) beside the cap"): while fewer creatures than `floor_curve` says
## are alive on the regular channel (everything the hell channel does not bring), the director draws the regular
## continuous rows at once, every frame, instead of waiting for the spawn check: a row by its weight now, its pack (a
## single row one) at a time, each cut to what the floor still lacks, the cap's room (load units) and the hard cap, until
## the floor is met, the room is gone or FLOOR_FILL_MAX came. Through a boss fight and the portal wait too, never past
## the cap (0 in the portal wait after a portal wave). No floor_curve: nothing (today's play).
func _floor_fill() -> void:
	if timeline == null or timeline.floor_curve.is_empty() or game == null or game.player == null:
		return
	var em: EnemyManager = game.enemies
	var floor_n := int(floor(timeline.floor_at(Run.elapsed)))
	if floor_n <= 0:
		return
	var tr := Run.elapsed if phase == Phase.NORMAL else Run.elapsed - 1.0
	var all := timeline.roster_at(tr)
	var hell: Array = all.filter(func(r: Dictionary) -> bool: return str(r.get("channel", "")) == "hell")
	var hell_n := 0
	var seen: Dictionary = {}
	for r: Dictionary in hell:
		var hid := str(r.get("enemy", ""))
		if not seen.has(hid):
			seen[hid] = true
			hell_n += em.alive_of(hid)
	var lack := floor_n - (em.alive_count() - hell_n)
	if lack <= 0:
		return
	var cap := current_cap()
	var room: float = float(cap) - (em.cap_load() - _hell_load(hell))
	var bodies: int = timeline.hard_cap - em.alive_count()
	var rows: Array = _roster_open(all.filter(func(r: Dictionary) -> bool: return str(r.get("channel", "")) != "hell" and WaveTimeline.row_drawn(r) and (WaveTimeline.row_elite(r) == "" or colour_open())))
	var guard := 0
	var brought := 0
	while lack > 0 and room > 0.0 and bodies > 0 and brought < FLOOR_FILL_MAX and guard < 32 and not rows.is_empty():
		guard += 1
		var row := _weighted_row(rows)
		if row.is_empty():
			break
		var def: EnemyDef = _row_def(row) if WaveTimeline.row_single_enemy(row) else _row_pick_def84(row)
		if def == null:
			break
		var share: float = maxf(def.cap_share, 0.05)
		var pack: int = maxi(int(row.get("pack", def.pack_size)), 1)
		var n: int = mini(mini(mini(pack, lack), bodies), maxi(int(ceil(room / share)), 1))
		if str(row.get("pattern", "pack")) == "single":
			n = 1
		# pass 110 (lane BOSS): the creature's max_alive holds inside one fill too (_burst_from's rule)
		if def.max_alive > 0:
			n = mini(n, def.max_alive - em.alive_of(def.id))
			if n <= 0:
				rows = rows.filter(func(x) -> bool: return not is_same(x, row))
				continue
		# pass 112 (lane MONK): one whole squad (squad_take); a squad that does not fit leaves the row out of this fill
		var sq_n := squad_take(def, row, 0, mini(bodies, int(floor(room / share))))
		if sq_n == 0:
			rows = rows.filter(func(x) -> bool: return not is_same(x, row))
			continue
		if sq_n > 0:
			n = sq_n
		var before := em.alive_count()
		if _row_new84(row, -1):
			_spawn_drawn84(row, def, n)
		else:
			_spawn_group(def.id, n, str(row.get("pattern", "pack")), pack, null, str(row.get("variant", "")), _stats_of(row), Callable(), _row_src(row))
		var came := maxi(em.alive_count() - before, 0)
		if came <= 0:
			break
		lack -= came
		room -= float(came) * share
		bodies -= came
		brought += came


# ---------------------------------------------------------------- one creature's shown numbers (pass 84, lane SPAWN)

## The HP and ATK a creature of roster row `r` plays at run second `t` with the hero at `level` (the Level Editor's one
## shown difficulty number, model.js creatureDifficulty / creatureAt, the same rule): a regular creature's row numbers
## fixed from the row's start (its `stats.hp` / `damage`, else the creature's JSON number x the HP / damage curve at the
## row's `t`; x hp_mult / damage_mult), x the stage multiplier at t, x the hero-level factor (1 + level_*_per_level x
## (level - 1)), x creature_hp_mult / creature_damage_mult, x the hero-power factor at power 1 (= 1); an Elite by its
## kind: elite.hp_mult_per_stage^stage x the stage x creature_hp_mult; a boss: boss.hp_mult_per_stage^stage x the stage
## (their ATK the live damage curve at t). {hp, atk, stage, stage_mult, hp_time, dmg_time, lv_hp, lv_dmg}; {} for an
## unknown creature or a row that names none.
static func shown_numbers(tl: WaveTimeline, r: Dictionary, t: float, level: int) -> Dictionary:
	if tl == null or not WaveTimeline.row_single_enemy(r):
		return {}
	var stats := _stats_of(r)
	var def: EnemyDef = Registry.enemy_with(str(r.get("enemy", "")), "", stats)
	if def == null:
		return {}
	# pass 87 (lane SGAME): the stage whose window holds t (Endless no longer grows the stage multiplier)
	var s: int = tl.stage_at(t)
	var sm := tl.stage_mult(s)
	var lv := float(maxi(level - 1, 0))
	var lv_hp := 1.0 + tl.level_hp_per_level * lv
	var lv_dmg := 1.0 + tl.level_damage_per_level * lv
	var t0 := maxf(float(r.get("t", t)), 0.0)
	var out := {"stage": s, "stage_mult": sm, "lv_hp": lv_hp, "lv_dmg": lv_dmg, "hp_time": 1.0, "dmg_time": 1.0}
	if def.archetype == "boss" or def.archetype == "elite":
		var per := float(def.boss.get("hp_mult_per_stage", 1.6)) if def.archetype == "boss" else float(def.elite.get("hp_mult_per_stage", 1.8))
		out["hp"] = def.hp * pow(per, float(s)) * maxf(sm, 1.0) * (1.0 if def.archetype == "boss" else tl.creature_hp_mult)
		out["dmg_time"] = tl.damage_mult_at(t)
		out["atk"] = def.damage * sm * lv_dmg * tl.creature_damage_mult * float(out["dmg_time"])
		return out
	var hp_time := 1.0 if stats.has("hp") else tl.hp_mult_at(t0)
	var dmg_time := 1.0 if stats.has("damage") else tl.damage_mult_at(t0)
	out["hp_time"] = hp_time
	out["dmg_time"] = dmg_time
	out["hp"] = def.hp * hp_time * sm * lv_hp * tl.creature_hp_mult
	out["atk"] = def.damage * dmg_time * sm * lv_dmg * tl.creature_damage_mult
	return out


## A line in a headless run's log for each swarm, coloured elite and pass 84 row spawn (lane SPAWN's sims count them):
## "spawn84 <kind> <id> <n> <clock>". Never on a phone (only a headless display prints it).
func _log84(kind: String, id: String, n: int) -> void:
	if n <= 0 or DisplayServer.get_name() != "headless":
		return
	print("spawn84 %s %s %d %.1f" % [kind, id, n, Run.elapsed])


# ---------------------------------------------------------------- pass 112 (lane MONK): squads

## How many of squad creature `def` one draw of row `row` brings (EnemyDef.squad; -1 for any other creature: the caller's
## own rule then): the row's `pack` when it names one, else `want` when the caller owes that many (a waves row: its count,
## or one squad's size drawn, squad_pack; a want past the creature's largest size comes as several squads, one a call),
## else a size drawn from the creature's `squad.sizes` by its `weights`. It comes whole when `fit` (what the cap and the
## hard cap still take, the pool's free slots and the creature's max_alive) holds it; else as the largest of its sizes
## that fits (a row's own pack never shrinks); else 0: the squad waits (never a partial squad).
func squad_take(def: EnemyDef, row: Dictionary, want: int, fit: int) -> int:
	if def == null or not def.is_squad():
		return -1
	var em: EnemyManager = game.enemies
	fit = mini(fit, em.free_list.size())
	if def.max_alive > 0:
		fit = mini(fit, def.max_alive - em.alive_of(def.id))
	var own := int(row.get("pack", 0)) if row.get("pack") != null else 0
	var s := own
	if s <= 0:
		s = mini(want, def.squad_max()) if want > 0 else def.squad_roll(_rng.randf())
	elif want > 0:
		s = mini(s, want)
	if s <= fit:
		return maxi(s, 0)
	if own > 0:
		return 0
	var best := 0
	for z: int in def.squad_sizes():
		if z <= fit and z <= s:
			best = maxi(best, z)
	return best


## What a waves row `r` may still bring of `def` now (squad_take's `fit`): the hard cap's room (unless respect_hard_cap is
## false) and, with respect_cap (the default), its channel's room counted in bodies of `def`.
func _squad_fit(def: EnemyDef, r: Dictionary) -> int:
	var em: EnemyManager = game.enemies
	var fit := em.pool_max
	if bool(r.get("respect_hard_cap", true)):
		fit = mini(fit, timeline.hard_cap - em.alive_count())
	if bool(r.get("respect_cap", true)):
		fit = mini(fit, int(floor(_channel_room(str(r.get("channel", "regular"))) / maxf(def.cap_share, 0.05))))
	return fit


## A waves row's count for `def` when the row names neither `count` nor `pack` (WaveTimeline.row_wave_count's fallback):
## one squad's size drawn by its weights for a squad creature, its pack size for any other.
func squad_pack(def: EnemyDef) -> int:
	if def == null:
		return 1
	return def.squad_roll(_rng.randf()) if def.is_squad() else def.pack_size
