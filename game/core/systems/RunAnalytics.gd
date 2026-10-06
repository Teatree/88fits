## The run recorder (pass 45, the Game Analytics Watch): one sparse row a second of the hero's power against the
## crowd's pressure, every build change and notable moment as an event, written as JSON when the run ends to
## user://analytics/runs/<stamp>.json and, on the PC, mirrored into the repo's analytics/runs/ with latest.js
## (`window.RUN = {...}`) and index.js (`window.RUNS = [...]`) for analytics/dashboard.html, which opens from file://.
## A Game child created only for a real run (`RunAnalytics.create(game)`): the arena never has one, and every hook in
## the game is one line, `if RunAnalytics.I: RunAnalytics.I.<hook>(...)`, so nothing records outside a run.
## Cost: two float adds a frame, one dictionary add per hit, kill and spawn, one row a second, one JSON.stringify a run.
class_name RunAnalytics
extends Node

static var I: RunAnalytics = null

const SCHEMA := 1
## The player stats a sheet snapshot carries (StatSheet.PLAYER_DEFAULTS minus the bookkeeping ones; pass 47 added the
## new items' stats and the stage's skips and banishes).
const STAT_KEYS := ["max_hp", "damage_reduction", "regen", "move_speed", "might", "cooldown", "area", "projectile_speed",
	"duration", "amount", "magnet", "luck", "greed", "xp_gain", "lifesteal", "evade", "crit_chance", "crit_damage", "thorns",
	"execute_frac", "overkill", "haste", "shield_max", "ricochet", "cooldown_on_kill", "still_regen", "still_might",
	"barrel_speed", "barrel_seconds", "xp_drop_chance", "elite_damage", "debuff_duration", "difficulty", "skips", "banishes"]
## Event kinds that are an item joining or growing in the build: they carry `via` and the estimate before and after.
## (Pass 46: the lines are passives, so "line" and "line_evolution" are "passive" and "passive_evolution" from then on.)
const ITEM_KINDS := ["weapon", "passive", "mutation", "perk", "evolution", "passive_evolution"]
## A dirty sheet (adrenaline, momentum, crescendo rebuild it often) is snapshotted at most this often, unless an item
## was picked since the last snapshot.
const SNAPSHOT_EVERY := 5.0
const INDEX_KEEP := 500

var game: Node
var play_t := 0.0            # unpaused play seconds: the x axis (Run.elapsed is the stage clock and freezes in boss and portal phases)
var header: Dictionary = {}
var samples: Array = []
var events: Array = []
var via := "card"            # how the next item arrives: card|path|starter|chest|boss_chest|stranger|shop|debug (set by Game before applying)
var abandoned := false
var mirror := true           # the PC copy beside the repo (tests turn it off)

var _acc_t := 0.0
var _finished := false
var _sheet_dirty := true
var _item_since_snapshot := true
var _last_snapshot_t := -1000.0
var _est_now := 0.0
var _pending_event := -1
var _mults_last: Dictionary = {}
var _last_wave := 0
var _last_hit_key := ""
var _last_hit_kind := ""
# the per-second accumulators: keys kept, values set back to zero after every row (no allocation after the first key)
var _dmg: Dictionary = {}
var _took: Dictionary = {}
var _took_kind: Dictionary = {"melee": 0.0, "ranged": 0.0, "boss": 0.0}
var _took_raw := 0.0
var _hits := 0
var _evaded := 0
var _shielded := 0.0
var _healed := 0.0
var _kills: Dictionary = {}
var _elite_kills := 0
var _spawns: Dictionary = {}


## The one line Game._ready needs: a recorder under the game, begun.
static func create(p_game: Node) -> RunAnalytics:
	var ra := RunAnalytics.new()
	ra.name = "RunAnalytics"
	p_game.add_child(ra)
	ra.begin(p_game)
	return ra


func begin(p_game: Node) -> void:
	I = self
	game = p_game
	var started := Time.get_datetime_string_from_system()
	var hero: CharacterDef = Run.character
	var mapdef: MapDef = Run.map
	header = {
		"schema": SCHEMA,
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"hero": hero.id if hero else "", "hero_name": hero.display_name if hero else "",
		"map": mapdef.id if mapdef else "", "seed": Run.map_seed,
		"started": started, "stamp": started.replace(":", "-"),
		"headless": DisplayServer.get_name() == "headless", "platform": OS.get_name(), "device": OS.get_model_name(),
		"pid": OS.get_process_id(), "result": "in_progress",
	}
	var em = game.get("enemies")
	var dir = game.get("director")
	_connect(em, "enemy_died", _on_enemy_died)
	_connect(em, "boss_died", func(def, _p): event("boss_end", def.id))
	_connect(dir, "boss_started", func(def): event("boss_start", def.id))
	_connect(dir, "stage_started", func(s): event("stage", "", int(s) + 1); _sheet_dirty = true)
	Run.level_up.connect(func(l): event("level", "", int(l)))
	Run.build_changed.connect(_on_build_changed)
	_on_build_changed()


func _connect(obj, sig: String, cb: Callable) -> void:
	if obj != null and obj is Object and obj.has_signal(sig):
		obj.connect(sig, cb)


func _exit_tree() -> void:
	if I == self:
		I = null
	# the game went away without an end (a quit mid-run, a tool that stops early): the record still lands
	if not _finished and not samples.is_empty():
		_finished = true
		header["result"] = "quit"
		_fill_end(false)
		_write(true)


# ---------------------------------------------------------------- hooks (hot: one dictionary op each)

## Run.add_damage: `amount` is the damage dealt (after crit and reduction), so the real-DPS series sums to Run's totals.
func dealt(weapon_id: String, amount: float) -> void:
	_dmg[weapon_id] = float(_dmg.get(weapon_id, 0.0)) + amount


## Player._log_hit: every hit that was not immune (power-up shield, evaded, shield, broke and real hits alike).
func took(info: Dictionary, raw: float, lost: float, shield: float, note: String) -> void:
	var key := str(info.get("id", ""))
	if key == "":
		key = str(info.get("by", "something"))
	_hits += 1
	_took_raw += raw
	_took[key] = float(_took.get(key, 0.0)) + lost
	var kind := str(info.get("kind", "melee"))
	_took_kind[kind] = float(_took_kind.get(kind, 0.0)) + lost
	_shielded += shield
	if note == "evaded":
		_evaded += 1
	_last_hit_key = key
	_last_hit_kind = kind


## EnemyManager.spawn: `def` is the resolved (possibly variant) EnemyDef.
func spawned(def: EnemyDef) -> void:
	_spawns[def.id] = int(_spawns.get(def.id, 0)) + 1
	if def.archetype == "elite":
		event("elite", def.id)


## Player.heal: the health actually restored.
func healed(n: float) -> void:
	_healed += n


func _on_enemy_died(def: EnemyDef, _pos: Vector3, elite: EliteModDef, _weapon_id: String) -> void:
	_kills[def.id] = int(_kills.get(def.id, 0)) + 1
	if elite != null or def.archetype == "elite":
		_elite_kills += 1


func _on_build_changed() -> void:
	_sheet_dirty = true
	var total := 0.0
	for w in Run.weapons:
		total += w.dps_estimate()
	_est_now = total
	if _pending_event >= 0 and _pending_event < events.size():
		events[_pending_event]["est_after"] = snappedf(total, 0.1)
	_pending_event = -1


# ---------------------------------------------------------------- events

## A moment in the run: {t, clock, kind, id?, level?} plus `extra`. Pass 47: a skip carries the skips left (no gold any
## more) and a chest let go adds "chest_skip" (Game); a chest's banish is Run's "banish" with "where": "chest". An item kind also records how it arrived (`via`)
## and the build's estimated DPS before it; the next build_changed fills `est_after`.
func event(kind: String, id: String = "", level: int = 0, extra: Dictionary = {}) -> void:
	var e := {"t": snappedf(play_t, 0.1), "clock": snappedf(Run.elapsed, 0.1), "kind": kind}
	if id != "":
		e["id"] = id
	if level != 0:
		e["level"] = level
	for k in extra:
		e[k] = extra[k]
	if kind in ITEM_KINDS:
		e["via"] = via
		e["est_before"] = snappedf(_est_now, 0.1)
		_pending_event = events.size()
		_item_since_snapshot = true
	events.append(e)


## Game._on_player_died: the killer is the last creature whose hit the recorder saw.
func death() -> void:
	event("death", _last_hit_key, 0, {"kind": _last_hit_kind})


# ---------------------------------------------------------------- the clock and the row

## From Game._process, so only unpaused play time counts.
func tick(delta: float) -> void:
	play_t += delta
	_acc_t += delta
	if _acc_t >= 1.0:
		_acc_t -= 1.0
		_sample()


func _put(row: Dictionary, key: String, v: int) -> void:
	if v != 0:
		row[key] = v


func _putf(row: Dictionary, key: String, v: float, step: float = 0.1) -> void:
	if v != 0.0:
		row[key] = snappedf(v, step)


## A copy of an accumulator with its zero entries left out (empty maps are left off the row).
func _put_map(row: Dictionary, key: String, acc: Dictionary, is_float: bool) -> void:
	var out := {}
	for k in acc:
		if is_float:
			var f: float = acc[k]
			if f != 0.0:
				out[k] = snappedf(f, 0.1)
		else:
			var n: int = acc[k]
			if n != 0:
				out[k] = n
	if not out.is_empty():
		row[key] = out


func _sample() -> void:
	var em = game.get("enemies") if game else null
	var dir = game.get("director") if game else null
	var player = game.get("player") if game else null
	var row := {"t": snappedf(play_t, 0.1), "clock": snappedf(Run.elapsed, 0.1), "stage": Run.stage + 1, "level": Run.level}
	if dir != null:
		_put(row, "phase", int(dir.phase))
	var wave := Run.endless_wave()
	_put(row, "wave", wave)
	if wave != _last_wave:
		if wave > 0:
			event("wave", "", wave)
		_last_wave = wave
	_putf(row, "xp", Run.xp)
	_putf(row, "xp_next", Run.xp_to_next())
	if player != null:
		row["hp"] = snappedf(float(player.hp), 0.1)
		row["hp_max"] = snappedf(float(player.max_hp), 0.1)
		_putf(row, "shield", float(player.shield_pts))
		if float(player.invuln) > 0.0:
			row["invuln"] = 1
	_put(row, "gold", Run.run_gold)
	_put(row, "banked", Run.banked_gold)
	_put(row, "kills", Run.kills)
	_put(row, "adren", Run.adrenaline)
	_put(row, "cresc", Run.crescendo)
	_putf(row, "desp", Run.desperado_might(), 0.01)
	# Steady Hand's bonus right now (pass 47)
	_putf(row, "steady", Run.steady_might(), 0.01)
	# the sheet's promise: each weapon's estimated DPS (what the pause screen prints)
	var est := {}
	var est_total := 0.0
	for w in Run.weapons:
		var e: float = w.dps_estimate()
		est[w.def.id] = snappedf(e, 0.1)
		est_total += e
	if not est.is_empty():
		row["est"] = est
	_putf(row, "est_total", est_total)
	# what the second did
	_put_map(row, "dmg", _dmg, true)
	_put_map(row, "took", _took, true)
	_putf(row, "took_raw", _took_raw)
	_put_map(row, "took_kind", _took_kind, true)
	_put(row, "hits", _hits)
	_put(row, "evaded", _evaded)
	_putf(row, "shielded", _shielded)
	_putf(row, "healed", _healed)
	_put_map(row, "killed", _kills, false)
	_put(row, "elite_kills", _elite_kills)
	_put_map(row, "spawned", _spawns, false)
	# the crowd: count against the cap, and its pressure (Σ max_hp × damage of every creature up)
	if em != null:
		_put(row, "alive", int(em.alive_count()))
		_putf(row, "load", float(em.cap_load()))
		if dir != null:
			_put(row, "cap", int(dir.current_cap()))
			if dir.timeline != null:
				_put(row, "hard_cap", int(dir.timeline.hard_cap))
		var alive: PackedByteArray = em.alive
		var state: PackedInt32Array = em.state
		var hp: PackedFloat32Array = em.hp
		var mx: PackedFloat32Array = em.max_hp
		var dmg: PackedFloat32Array = em.dmg
		var tidx: PackedInt32Array = em.type_idx
		var types: Array = em.types
		var press := 0.0
		var press_hp := 0.0
		var press_dmg := 0.0
		var by := {}
		for i in range(alive.size()):
			if alive[i] == 0 or state[i] == EnemyManager.STATE_DYING:
				continue
			press_hp += hp[i]
			press += mx[i] * dmg[i]
			press_dmg += dmg[i]
			var ti := tidx[i]
			if ti >= 0 and ti < types.size():
				var tid: String = types[ti]["def"].id
				by[tid] = int(by.get(tid, 0)) + 1
		_putf(row, "press", press)
		_putf(row, "press_hp", press_hp)
		_putf(row, "press_dmg", press_dmg)
		if not by.is_empty():
			row["alive_by"] = by
		var bi: int = em.boss_index
		if bi >= 0 and bi < alive.size() and alive[bi] == 1 and mx[bi] > 0.0:
			row["boss_hp"] = snappedf(hp[bi] / mx[bi], 0.01)
		var m := {"stage": snappedf(float(em.stage_mult), 0.01), "hp_t": snappedf(float(em.hp_time_mult), 0.01),
			"lvl_hp": snappedf(float(em.level_hp_mult), 0.01), "lvl_dmg": snappedf(float(em.level_dmg_mult), 0.01),
			"time_scale": snappedf(float(em.time_scale), 0.01)}
		if m != _mults_last:
			row["mults"] = m
			_mults_last = m
	# the build, only when it changed (and not more than once in SNAPSHOT_EVERY unless an item was picked)
	if _sheet_dirty and (_item_since_snapshot or play_t - _last_snapshot_t >= SNAPSHOT_EVERY):
		row["stats"] = _stats_snapshot()
		row["weapons"] = _weapons_snapshot()
		row["passives"] = Run.passives.duplicate()
		row["perks"] = Run.perks.duplicate()
		_sheet_dirty = false
		_item_since_snapshot = false
		_last_snapshot_t = play_t
	samples.append(row)
	# the second is counted: values back to zero, keys kept
	for k in _dmg:
		_dmg[k] = 0.0
	for k in _took:
		_took[k] = 0.0
	for k in _took_kind:
		_took_kind[k] = 0.0
	for k in _kills:
		_kills[k] = 0
	for k in _spawns:
		_spawns[k] = 0
	_took_raw = 0.0
	_hits = 0
	_evaded = 0
	_shielded = 0.0
	_healed = 0.0
	_elite_kills = 0


func _stats_snapshot() -> Dictionary:
	var out := {}
	for k in STAT_KEYS:
		out[k] = snappedf(Run.player_sheet.get_stat(k, 0.0), 0.001)
	return out


func _weapons_snapshot() -> Array:
	var out: Array = []
	for w in Run.weapons:
		var muts: Array = []
		for m in w.mutations:
			muts.append(m.id)
		out.append({"id": w.def.id, "level": w.level, "mut": muts, "dmg": snappedf(w.stat("damage"), 0.1),
			"cd": snappedf(w.stat("cooldown", 1.0), 0.001), "amount": w.stat_int("amount", 1), "pierce": w.stat_int("pierce", 0),
			"area": snappedf(w.stat("area", 1.0), 0.01), "est": snappedf(w.dps_estimate(), 0.1)})
	return out


# ---------------------------------------------------------------- the end and the file

## Game.end_run, after the save: the header is completed and the record written (and indexed on the PC).
func finish() -> void:
	if _finished:
		return
	_finished = true
	if _acc_t > 0.25:
		_sample()
	if Run.extracted:
		header["result"] = "extract"
	elif abandoned:
		header["result"] = "abandon"
	elif Run.died:
		header["result"] = "death"
	else:
		header["result"] = "end"
	_fill_end(true)
	_write(true)


## Game._notification on APPLICATION_PAUSED: the record so far, before Android may drop the process.
func checkpoint() -> void:
	if _finished:
		return
	_fill_end(false)
	_write(false)


func _fill_end(with_log: bool) -> void:
	header["length"] = snappedf(play_t, 0.1)
	header["clock"] = snappedf(Run.elapsed, 0.1)
	header["stage"] = Run.stage + 1
	header["endless_wave"] = Run.endless_wave()
	header["level"] = Run.level
	header["kills"] = Run.kills
	header["gold"] = Run.run_gold
	header["strongbox"] = Run.banked_gold
	header["revives"] = Run.revives_used
	header["build"] = _build()
	header["totals"] = {"damage_by_weapon": Run.damage_by_weapon.duplicate(), "kills_by_weapon": Run.kills_by_weapon.duplicate(),
		"kills_by_enemy": Run.kills_by_enemy.duplicate()}
	header["names"] = _names()
	if with_log and game and is_instance_valid(game):
		var player = game.get("player")
		if player != null and player.get("damage_log") != null:
			header["hit_log"] = (player.damage_log as Array).duplicate(true)


func _build() -> Dictionary:
	var ws: Array = []
	for w in Run.weapons:
		var muts: Array = []
		for m in w.mutations:
			muts.append(m.id)
		ws.append({"id": w.def.id, "level": w.level, "mutations": muts})
	return {"weapons": ws, "passives": Run.passives.duplicate(), "perks": Run.perks.duplicate()}


## id -> display name for everything the record mentions, so the dashboard needs no content folder.
func _names() -> Dictionary:
	var ids := {}
	for k in _dmg:
		ids[k] = true
	for k in _kills:
		ids[k] = true
	for k in _spawns:
		ids[k] = true
	for k in _took:
		ids[k] = true
	for k in Run.damage_by_weapon:
		ids[k] = true
	for k in Run.kills_by_enemy:
		ids[k] = true
	for e in events:
		if e.has("id"):
			ids[str(e["id"])] = true
	for w in Run.weapons:
		ids[w.def.id] = true
		for m in w.mutations:
			ids[m.id] = true
	for k in Run.passives:
		ids[k] = true
	for p in Run.perks:
		ids[str(p)] = true
	var out := {}
	for id in ids:
		var n := _name_of(str(id))
		if n != "":
			out[id] = n
	return out


## The damage sources that are no content folder (pass 48), named for the dashboard: Powder Keg's blast (its passive
## item's own name wins when it has one), the revive's wave, a body going off, a dead rocketeer's loose rocket.
const SOURCE_NAMES := {"powder_keg": "Powder Keg", "revive": "Revive blast", "blast": "Blast", "loose_rocket": "Loose rocket"}


func _name_of(id: String) -> String:
	var d: ContentDef = Registry.weapon(id)
	if d == null:
		d = Registry.passive(id)
	if d == null:
		d = Registry.perk(id)
	if d == null:
		d = Registry.mutation(id)
	if d == null:
		d = Registry.enemy(id)
	if d == null:
		d = Registry.pickup(id)
	if d == null:
		d = Registry.structure(id)
	if d == null:
		return str(SOURCE_NAMES.get(id, ""))
	return d.display_name


## The record as one JSON file under user://, and on the PC a copy beside the repo with latest.js (and the index when
## the run is over). Returns the path written last.
func _write(index: bool) -> String:
	var doc := header.duplicate(true)
	doc["samples"] = samples
	doc["events"] = events
	var json := JSON.stringify(doc)
	var fname := str(header.get("stamp", "run")) + ".json"
	DirAccess.make_dir_recursive_absolute("user://analytics/runs")
	var out := "user://analytics/runs/" + fname
	_store(out, json)
	if mirror and not OS.has_feature("mobile"):
		var dir := _mirror_dir()
		if dir != "":
			out = dir.path_join(fname)
			_store(out, json)
			_store(dir.path_join("latest.js"), "window.RUN = " + json + ";\n")
			if index:
				_update_index(dir)
	print("analytics: %s (%d rows, %d events, %s)" % [out, samples.size(), events.size(), str(header.get("result", ""))])
	return out


## The repo's analytics/runs/ when the game runs from the repo (the editor binary); "" anywhere else.
func _mirror_dir() -> String:
	var repo := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var parent := repo.path_join("analytics")
	if not DirAccess.dir_exists_absolute(parent):
		return ""
	var dir := parent.path_join("runs")
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _update_index(dir: String) -> void:
	var ipath := dir.path_join("index.json")
	var arr: Array = []
	if FileAccess.file_exists(ipath):
		var f := FileAccess.open(ipath, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Array:
				arr = parsed
	var stamp := str(header.get("stamp", ""))
	for i in range(arr.size()):
		if arr[i] is Dictionary and str(arr[i].get("stamp", "")) == stamp:
			arr.remove_at(i)
			break
	arr.append({"file": stamp + ".json", "stamp": stamp, "started": header.get("started", ""), "hero": header.get("hero", ""),
		"hero_name": header.get("hero_name", ""), "map": header.get("map", ""), "result": header.get("result", ""),
		"length": header.get("length", 0.0), "clock": header.get("clock", 0.0), "stage": header.get("stage", 1),
		"level": header.get("level", 1), "kills": header.get("kills", 0), "gold": header.get("gold", 0),
		"version": header.get("version", ""), "headless": header.get("headless", false)})
	while arr.size() > INDEX_KEEP:
		arr.pop_front()
	_store(ipath, JSON.stringify(arr))
	_store(dir.path_join("index.js"), "window.RUNS = " + JSON.stringify(arr) + ";\n")


func _store(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("analytics: could not write " + path)
		return false
	f.store_string(text)
	f.close()
	return true
