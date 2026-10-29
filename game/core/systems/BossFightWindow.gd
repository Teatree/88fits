## Pass 110 (lane BOSS): a stage's boss-fight window as one fight plays it. Garry (2026-10-28): "I'd like some control
## over which enemies spawn during the Boss fight. Just add a 2 minute window in the Timeline where I can set up the cycle
## of enemies that will be spawning ... as long as the Boss Fight is continuing it will be those enemies at that pace that
## will be spawning." The stage entry's `boss_fight` block (WaveTimeline.boss_fight: length, max_count, roster) holds
## spawn rows with the roster's keys, every time on the FIGHT clock. WaveDirector hands the fight to this from the boss's
## arrival (_start_boss -> begin) until it dies (_on_boss_died -> stop); while it is active only these rows spawn (the
## stage's rows, the own-interval rows, the density floor and the specials' clock stand still; the boss's own summons
## still come, never past the hard cap: WaveDirector.summon_room).
##   - The fight clock starts at 0 when the boss arrives (real seconds; a paused game holds it) and loops every `length`
##     seconds: at each new cycle every row starts afresh (a once row comes again, a waves row's schedule restarts from
##     t + offset, what a wave still owed is dropped, chance and t_jitter are rolled again).
##   - Continuous rows (and waves rows that trickle) are drawn at the director's spawn check (spawn_interval), or on their
##     own `interval` clock, by their presence weight at the fight clock: a burst of burst_min..burst_max CREATURES cut to
##     the room under max_count (bodies alive: the boss, its summons and the stage's leftovers count), cut to the drawing
##     rows' share of the weight as the roster's own-interval rows are (pass 83).
##   - Waves and once rows bring `count` a wave (WaveTimeline.row_wave_count), cut to the room under max_count when
##     respect_cap (the default; at least one while there is any room), the rest owed until the row's next wave or its
##     end; respect_cap false = on top of max_count; the hard cap holds unless respect_hard_cap is false. An elite row
##     without a pattern brings coloured-elite arrivals (WaveDirector._spawn_elite, on top of every limit, as on the
##     roster). A row's `channel` is ignored: the window has one limit.
##   - "roster" as a row's creature draws from the window's own open mix rows by their Elite weight.
##   - Numbers (pass 58's rule): each row's creatures are fixed at its first spawn of the run from the run clock at the
##     fight (the stage's end: the HP and ATK curves there) and the hero's level then (WaveDirector.source_for), times
##     the stage multiplier at the spawn and the row's overrides: like a roster row that starts at the stage's end.
class_name BossFightWindow
extends RefCounted

## the WaveDirector that owns this (untyped: it calls the director's own helpers)
var dir = null
## whether a fight plays the window now (begin .. stop)
var active := false
## the stage whose window this is (0-based), one cycle's length (seconds), the most bodies alive (-1 = the hard cap)
var stage := 0
var length := WaveTimeline.BOSS_FIGHT_LENGTH_DEFAULT
var max_count := WaveTimeline.BOSS_FIGHT_MAX_COUNT_DEFAULT
## the window's rows (the timeline's own dictionaries, never changed here)
var rows: Array = []
## seconds since the boss arrived, the cycle in play (0-based), the run second the numbers are fixed from
var clock := 0.0
var cycle := -1
var t0_run := 0.0
## what the fight brought (the tests, the tools): row key -> creatures, the total, cycles begun
var came_by: Dictionary = {}
var came_total := 0
var cycles := 0
## each row's state this cycle (key -> {k, owed, came, waves, next, pick, bannered}), the once / waves rows' roll for the
## cycle (key -> {skip, shift}), the own-interval rows' clocks (key -> seconds to the next draw)
var _st: Dictionary = {}
var _roll: Dictionary = {}
var _draw_left: Dictionary = {}


## The fight of stage `p_stage` begins (the boss has just arrived): true when the stage has a window (it then plays it),
## false (inactive) without one, so the director keeps its old fight.
func begin(d, p_stage: int) -> bool:
	dir = d
	active = false
	_st.clear()
	_roll.clear()
	_draw_left.clear()
	came_by = {}
	came_total = 0
	cycles = 0
	cycle = -1
	clock = 0.0
	if d == null or d.timeline == null:
		return false
	var tl: WaveTimeline = d.timeline
	if not tl.has_boss_fight(p_stage):
		return false
	stage = p_stage
	length = tl.boss_fight_length(stage)
	max_count = tl.boss_fight_max_count(stage)
	rows = tl.boss_fight_rows(stage)
	t0_run = tl.stage_end(stage)
	active = true
	_new_cycle(0)
	return true


## The fight is over (the boss died, the run ended): nothing more comes from the window.
func stop() -> void:
	active = false


## The run's key of window row `r` at index `k` (its fixed numbers, its state): "boss<stage>:<id>#<k>".
func key_of(r: Dictionary, k: int) -> String:
	return "boss%d:%s#%d" % [stage, str(r.get("id", "")), k]


## Seconds into the cycle in play.
func cycle_time() -> float:
	return clock - float(maxi(cycle, 0)) * length


## The cap the director reports while the window plays (WaveDirector.current_cap): max_count, the hard cap for -1.
func cap_value() -> int:
	if dir == null or dir.timeline == null:
		return maxi(max_count, 0)
	return int(dir.timeline.hard_cap) if max_count < 0 else max_count


## Bodies that may still come under max_count now (alive_count: the boss, its summons and the stage's leftovers count).
func room() -> int:
	var alive: int = dir.game.enemies.alive_count()
	if max_count < 0:
		return int(dir.timeline.hard_cap) - alive
	return max_count - alive


## Bodies that may still come under the map's hard cap.
func hard_room() -> int:
	return int(dir.timeline.hard_cap) - int(dir.game.enemies.alive_count())


## The fight's tick (WaveDirector._process in its boss phase): the fight clock, a new cycle when it loops, the waves and
## once rows' schedules and the own-interval rows' clocks.
func tick(delta: float) -> void:
	if not active or length <= 0.0:
		return
	# pass 113 (lane BOSS): the fight clock stands still while the boss plays a bullet-heaven pattern (held)
	if held():
		return
	clock += maxf(delta, 0.0)
	var c := int(floor(clock / length))
	if c != cycle:
		_new_cycle(c)
	var ct := cycle_time()
	_tick_paced(ct)
	_tick_intervals(delta, ct)


## The director's spawn check in a fight with a window: what the waves still owe first, then the continuous draw.
func spawn_check() -> void:
	if not active or held():
		return
	var ct := cycle_time()
	_owed_all(ct)
	_draw(ct, [])


## Pass 113 (lane BOSS; Garry's spec: "the boss-fight window's rows pause for the attack, so the screen is the pattern and
## the player"): true while a bullet-heaven pattern is under way (EnemyManager.pattern_holds: its tell, its bullets and
## the boss's spent seconds). The window's rows bring nothing and its fight clock waits; the creatures already there stay.
func held() -> bool:
	if dir == null or dir.game == null:
		return false
	var em = dir.game.get("enemies")
	return em != null and em.has_method("pattern_holds") and bool(em.pattern_holds())


## A new cycle (the fight's first, or the clock looped): every row starts afresh, the once and waves rows' chance and
## t_jitter rolled again for it (no dice for a row without them).
func _new_cycle(c: int) -> void:
	cycle = c
	cycles = c + 1
	_st.clear()
	_roll.clear()
	_draw_left.clear()
	for k in range(rows.size()):
		var r: Dictionary = rows[k]
		if not WaveTimeline.row_paced(r):
			continue
		var chance := float(r.get("chance", 1.0))
		var jitter := float(r.get("t_jitter", 0.0))
		if chance >= 1.0 and jitter <= 0.0:
			continue
		var roll := {"skip": false, "shift": 0.0}
		if jitter > 0.0:
			roll["shift"] = maxf(dir._rng.randf_range(-jitter, jitter), -float(r.get("t", 0.0)))
		if chance < 1.0 and dir._rng.randf() >= chance:
			roll["skip"] = true
		_roll[key_of(r, k)] = roll


func _state(key: String) -> Dictionary:
	var st = _st.get(key)
	if st is Dictionary:
		return st
	var made := {"k": -1, "owed": 0, "came": 0, "waves": 0}
	_st[key] = made
	return made


## A row's state this cycle as a copy (the tests), {} before it first did anything.
func row_state(k: int) -> Dictionary:
	if k < 0 or k >= rows.size():
		return {}
	var st = _st.get(key_of(rows[k], k))
	return (st as Dictionary).duplicate() if st is Dictionary else {}


## The waves and once rows (pass 81 / 84's rules on the fight clock): wave k falls due at t + offset + k x every while
## the row is open (a timer row, every [min, max] or an elite row, a fresh gap after the wave it fired), a wave due while
## the row weighs 0 does not come; it owes `count` and spawns what fits, the rest as room frees (_owed_all).
func _tick_paced(ct: float) -> void:
	for k in range(rows.size()):
		var r: Dictionary = rows[k]
		if not WaveTimeline.row_paced(r):
			continue
		var key := key_of(r, k)
		var roll: Dictionary = _roll.get(key, {})
		if bool(roll.get("skip", false)):
			continue
		var rt := ct - float(roll.get("shift", 0.0))
		if rt < float(r.get("t", 0.0)) or (r.get("until") != null and rt >= float(r["until"])):
			continue
		var st := _state(key)
		var elite := WaveTimeline.row_elite(r)
		var wave_t := rt
		if WaveTimeline.row_timer(r):
			if not st.has("next"):
				st["next"] = WaveTimeline.row_wave_start(r)
			if rt < float(st["next"]):
				continue
			if elite != "" and not dir.colour_open():
				st["next"] = rt + 1.0
				continue
			st["k"] = int(st["k"]) + 1
			var gap: float = dir._row_every_draw(r)
			var pace: float = dir.elite_pace() if elite != "" else 1.0
			st["next"] = rt + gap / maxf(pace, 0.01) if gap > 0.0 else INF
		else:
			var i := WaveTimeline.row_wave_index(r, rt)
			if i < 0 or i <= int(st["k"]):
				continue
			st["k"] = i
			wave_t = WaveTimeline.row_wave_time(r, i)
		st["owed"] = 0
		st["bannered"] = false
		st.erase("pick")
		if dir._roster_weight(r, wave_t) <= 0.0:
			continue
		st["waves"] = int(st["waves"]) + 1
		if elite != "" and not r.has("pattern"):
			_elite_wave(r, key, st)
			continue
		var pick: Dictionary = {}
		if not _is_roster(r):
			pick = _pick_of(r, key)
			if pick.is_empty():
				continue
		st["pick"] = pick
		var pdef: EnemyDef = _def_of(pick) if not pick.is_empty() else null
		st["owed"] = WaveTimeline.row_wave_count(r, pdef.pack_size if pdef else 1)
		_spawn_owed(r, key, st)


## What the waves still owe, at every spawn check, ahead of the continuous draw; a row that closed drops its rest.
func _owed_all(ct: float) -> void:
	for k in range(rows.size()):
		var r: Dictionary = rows[k]
		if not WaveTimeline.row_paced(r):
			continue
		var key := key_of(r, k)
		var st = _st.get(key)
		if not (st is Dictionary) or int(st["owed"]) <= 0:
			continue
		var rt := ct - float((_roll.get(key, {}) as Dictionary).get("shift", 0.0))
		if r.get("until") != null and rt >= float(r["until"]):
			st["owed"] = 0
			continue
		_spawn_owed(r, key, st)


## A wave's owed creatures now: cut to the hard cap (unless respect_hard_cap is false: the body limit only), the creature's
## max_alive and, with respect_cap, the room under max_count. Returns how many came.
func _spawn_owed(r: Dictionary, key: String, st: Dictionary) -> int:
	var em: EnemyManager = dir.game.enemies
	var n := int(st["owed"])
	if n <= 0:
		return 0
	if bool(r.get("respect_hard_cap", true)):
		n = mini(n, hard_room())
	var pick: Dictionary = st.get("pick", {})
	if not pick.is_empty():
		var def := _def_of(pick)
		if def == null:
			st["owed"] = 0
			return 0
		if def.max_alive > 0:
			n = mini(n, def.max_alive - em.alive_of(def.id))
	if n > 0 and bool(r.get("respect_cap", true)):
		n = mini(n, room())
	if n <= 0:
		return 0
	var came := 0
	if pick.is_empty():
		# the "roster" creature: drawn creature by creature, each group as the row it was drawn from spawns it
		var groups: Array = []
		for _j in range(n):
			var p := _roster_pick(r)
			if p.is_empty():
				break
			var g: Dictionary = {}
			for x: Dictionary in groups:
				if str(x["pick"]["key"]) == str(p["key"]):
					g = x
					break
			if g.is_empty():
				g = {"pick": p, "n": 0}
				groups.append(g)
			g["n"] = int(g["n"]) + 1
		for g: Dictionary in groups:
			came += _spawn(r, key, g["pick"], int(g["n"]))
	else:
		came = _spawn(r, key, pick, n)
	st["owed"] = maxi(int(st["owed"]) - came, 0)
	st["came"] = int(st["came"]) + came
	if came > 0 and not bool(st.get("bannered", false)) and str(r.get("banner", "")) != "":
		st["bannered"] = true
		dir.game.toast(str(r["banner"]), WaveDirector.SWARM_COLOR)
	return came


## An elite row's wave without a pattern: `count` coloured-elite arrivals (WaveDirector._spawn_elite: alone, as its pack
## or a ring by the creature's elite_formats, with its toast; on top of every limit, as the roster's elite rows).
func _elite_wave(r: Dictionary, key: String, st: Dictionary) -> void:
	var em: EnemyManager = dir.game.enemies
	var n := maxi(int(r.get("count", 1)), 1)
	var el := WaveTimeline.row_elite(r)
	var mod_id := "" if el == "random" else el
	var e = r.get("enemy", "")
	var before: int = em.alive_count()
	for _a in range(n):
		var id := ""
		var variant := str(r.get("variant", ""))
		var stats: Dictionary = dir._stats_of(r)
		if e is Array:
			id = dir._pick_id(e, r.get("enemy_weights", []))
		elif str(e) == WaveTimeline.ROW_ENEMY_ROSTER:
			var p := _roster_pick(r)
			if p.is_empty():
				continue
			id = str(p["id"])
			if variant == "":
				variant = str(p["variant"])
			if stats.is_empty():
				stats = p["stats"]
		else:
			id = str(e)
		if id == "" or Registry.enemy(id) == null:
			continue
		dir._spawn_elite(id, mod_id, variant, stats)
	var came := maxi(em.alive_count() - before, 0)
	st["came"] = int(st["came"]) + came
	came_by[key] = int(came_by.get(key, 0)) + came
	came_total += came
	if came > 0 and not bool(st.get("bannered", false)) and str(r.get("banner", "")) != "":
		st["bannered"] = true
		dir.game.toast(str(r["banner"]), WaveDirector.SWARM_COLOR)


## The own-interval rows' clocks (pass 83's rule on the fight clock): an open drawn row with `interval` draws every
## `interval` seconds from the moment it opens (at once the first time), the rows due together.
func _tick_intervals(delta: float, ct: float) -> void:
	var due: Array = []
	for k in range(rows.size()):
		var r: Dictionary = rows[k]
		if not dir.row_has_interval(r) or not WaveTimeline.row_drawn(r):
			continue
		if ct < float(r.get("t", 0.0)) or (r.get("until") != null and ct >= float(r["until"])):
			continue
		var key := key_of(r, k)
		var left: float = float(_draw_left.get(key, 0.0)) - delta
		if left <= 0.0:
			due.append(r)
			left = dir.row_draw_interval(r, dir.timeline.spawn_interval)
		_draw_left[key] = left
	if not due.is_empty():
		_draw(ct, due)


## One continuous draw: the open drawn rows (an elite row once colour is open, a row whose creature is at its max_alive
## left out), the `due` ones (an own-interval draw) or, with `due` empty, those without their own interval; a burst of
## burst_min..burst_max creatures x their share of the weight, cut to the room under max_count and the hard cap, each
## creature group by a row drawn by its weight at the fight clock, its pack (a single row one) at a time.
func _draw(ct: float, due: Array) -> void:
	var em: EnemyManager = dir.game.enemies
	var tl: WaveTimeline = dir.timeline
	var colour: bool = dir.colour_open()
	var open: Array = []
	var open_k: Array = []
	for k in range(rows.size()):
		var r: Dictionary = rows[k]
		if not WaveTimeline.row_drawn(r):
			continue
		if ct < float(r.get("t", 0.0)) or (r.get("until") != null and ct >= float(r["until"])):
			continue
		if not colour and WaveTimeline.row_elite(r) != "":
			continue
		if WaveTimeline.row_single_enemy(r):
			var d0 := _def_of({"id": str(r.get("enemy", "")), "variant": str(r.get("variant", "")), "stats": dir._stats_of(r)})
			if d0 == null or (d0.max_alive > 0 and em.alive_of(d0.id) >= d0.max_alive):
				continue
		open.append(r)
		open_k.append(k)
	if open.is_empty():
		return
	var total := 0.0
	var part := 0.0
	var draw: Array = []
	var draw_k: Array = []
	var ws: Array = []
	for j in range(open.size()):
		var r: Dictionary = open[j]
		var w: float = dir._roster_weight(r, ct)
		total += w
		var mine: bool = due.any(func(x) -> bool: return is_same(x, r)) if not due.is_empty() else not dir.row_has_interval(r)
		if mine:
			draw.append(r)
			draw_k.append(open_k[j])
			ws.append(w)
			part += w
	if draw.is_empty() or part <= 0.0 or total <= 0.0:
		return
	var frac := part / total
	var rm := room()
	var bodies := hard_room()
	if rm <= 0 or bodies <= 0:
		return
	var burst: float = minf(float(dir._rng.randi_range(tl.burst_min, tl.burst_max)) * frac, float(rm))
	var guard := 0
	while burst > 0.0 and bodies > 0 and guard < 64:
		guard += 1
		var pick_w: float = dir._rng.randf() * part
		var ci := 0
		for j in range(draw.size()):
			if float(ws[j]) <= 0.0:
				continue
			ci = j
			pick_w -= float(ws[j])
			if pick_w <= 0.0:
				break
		var chosen: Dictionary = draw[ci]
		var key := key_of(chosen, int(draw_k[ci]))
		var pick := _pick_of(chosen, key)
		if pick.is_empty():
			break
		var def := _def_of(pick)
		if def == null:
			break
		# a cut burst holding less than one creature brings one with that chance (pass 83's rule: the expected count kept)
		if frac < 1.0 and burst < 1.0 and dir._rng.randf() >= burst:
			break
		var pack: int = maxi(int(chosen.get("pack", def.pack_size)), 1)
		var n: int = mini(mini(pack, maxi(int(ceil(burst)), 1)), bodies)
		if str(chosen.get("pattern", "pack")) == "single":
			n = 1
		if def.max_alive > 0:
			n = mini(n, def.max_alive - em.alive_of(def.id))
		if n <= 0:
			break
		_spawn(chosen, key, pick, n)
		burst -= float(n)
		bodies -= n


static func _is_roster(r: Dictionary) -> bool:
	var e = r.get("enemy", "")
	return not (e is Array) and str(e) == WaveTimeline.ROW_ENEMY_ROSTER


## The creature row `r` brings now: {id, variant, stats, key (the fixed numbers' key)}: its own, a list's draw by
## `enemy_weights`, or the "roster" draw (_roster_pick); {} when nothing can come.
func _pick_of(r: Dictionary, key: String) -> Dictionary:
	var e = r.get("enemy", "")
	var variant := str(r.get("variant", ""))
	var stats: Dictionary = dir._stats_of(r)
	if e is Array:
		var lid: String = dir._pick_id(e, r.get("enemy_weights", []))
		if Registry.enemy(lid) == null:
			return {}
		return {"id": lid, "variant": variant, "stats": stats, "key": key + "|" + lid}
	if str(e) == WaveTimeline.ROW_ENEMY_ROSTER:
		return _roster_pick(r)
	if Registry.enemy(str(e)) == null:
		return {}
	return {"id": str(e), "variant": variant, "stats": stats, "key": key}


## The "roster" creature of a window row: one of the window's mix rows open now (one creature, no elite, not special,
## not once; its creature under its max_alive and able to be an Elite) drawn by its Elite weight, coming as that row
## spawns it unless `r` sets its own variant or stats; {} when none is open.
func _roster_pick(r: Dictionary) -> Dictionary:
	var ct := cycle_time()
	var mix: Array = []
	for k in range(rows.size()):
		var x: Dictionary = rows[k]
		if WaveTimeline.row_in_mix(x) and ct >= float(x.get("t", 0.0)) and (x.get("until") == null or ct < float(x["until"])):
			mix.append(x)
	var cands: Array = dir.elite_candidates(dir._roster_open(mix))
	if cands.is_empty():
		return {}
	var drawn: Dictionary = dir._weighted_elite_row(cands)
	var stats: Dictionary = dir._stats_of(r)
	var own := not stats.is_empty()
	var variant := str(r.get("variant", ""))
	var id := str(drawn.get("enemy", ""))
	return {"id": id, "variant": variant if variant != "" else str(drawn.get("variant", "")),
		"stats": stats if own else dir._stats_of(drawn),
		"key": (key_of(r, _index_of(r)) + "|" + id) if own else key_of(drawn, _index_of(drawn))}


## Row `r`'s place in the window's rows (by identity: two rows alike are still two rows), -1 when it is not one of them.
func _index_of(r: Dictionary) -> int:
	for k in range(rows.size()):
		if is_same(rows[k], r):
			return k
	return -1


func _def_of(pick: Dictionary) -> EnemyDef:
	if pick.is_empty():
		return null
	return Registry.enemy_with(str(pick["id"]), str(pick["variant"]), pick["stats"])


## `n` of a pick in row `r`'s way: its numbers fixed from the stage's end at its first spawn (source_for), every one
## wearing the row's `elite` modifier when it has a pattern and colour is open ("random" = any), every one its coloured
## special with `special`; pattern "ring" with a `ring_radius` the classic even ring round the hero, else the row's
## pattern through WaveDirector._spawn_group. Returns how many came.
func _spawn(r: Dictionary, key: String, pick: Dictionary, n: int) -> int:
	var em: EnemyManager = dir.game.enemies
	var id := str(pick["id"])
	var variant := str(pick["variant"])
	var stats: Dictionary = pick["stats"]
	var def: EnemyDef = Registry.enemy_with(id, variant, stats)
	if def == null or n <= 0:
		return 0
	var src: Dictionary = dir.source_for(str(pick["key"]), t0_run, stats)
	var mod: EliteModDef = null
	var el := WaveTimeline.row_elite(r)
	if el != "" and dir.colour_open():
		mod = Registry.elites.get(el) if el != "random" else null
		if mod == null:
			var list: Array = Registry.elites_list()
			if not list.is_empty():
				mod = list[dir._rng.randi() % list.size()]
	var pattern := str(r.get("pattern", "pack"))
	var pack: int = maxi(int(r.get("pack", def.pack_size)), 1)
	em.force_special = bool(r.get("special", false))
	var came := 0
	if pattern == "ring" and r.has("ring_radius"):
		var radius := maxf(float(r.get("ring_radius", WaveDirector.RING_RADIUS)), 1.0)
		if mod == null:
			came = em.spawn_ring(id, n, dir.game.player.global_position, radius, variant, stats, src)
		else:
			came = dir._spawn_elite_ring_at(id, n, mod, variant, stats, src, radius)
	else:
		came = dir._spawn_group(id, n, pattern, pack, mod, variant, stats, Callable(), src)
	em.force_special = false
	if came > 0:
		came_by[key] = int(came_by.get(key, 0)) + came
		came_total += came
		dir._log84("bossfight", id, came)
	return came
