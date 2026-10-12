## The run recorder (pass 45, the Game Analytics Watch): one sparse row a second of the hero's power against the
## crowd's pressure, every build change and notable moment as an event, written as JSON when the run ends to
## user://analytics/runs/<stamp>.json and, on the PC, mirrored into the repo's analytics/runs/ with latest.js
## (`window.RUN = {...}`) and index.js (`window.RUNS = [...]`) for analytics/dashboard.html, which opens from file://.
## A Game child created only for a real run (`RunAnalytics.create(game)`): the arena never has one, and every hook in
## the game is one line, `if RunAnalytics.I: RunAnalytics.I.<hook>(...)`, so nothing records outside a run.
## Cost: two float adds and a clock read a frame, one dictionary add per hit, kill and spawn, one row a second, one
## JSON.stringify a run.
## Pass 57: the same story goes to PostHog through the Analytics autoload (core/autoload/Analytics.gd): every event as it
## is recorded (an item's once its est_after is known), run_start at the begin, and at the end run_end and run_summary
## (summary(): the rows folded into per-minute series and the run's totals, with the frame clock's fps_avg and
## fps_low). Each settled offer is recorded as an "offer" event (the cards shown, the pick or the skip, the rerolls and
## banishes on the way, how long it took), read off the card screen's own signals; the run's id and the map's Level
## Editor version (map_rev) are in the header.
class_name RunAnalytics
extends Node

static var I: RunAnalytics = null

const SCHEMA := 1
## The player stats a sheet snapshot carries (StatSheet.PLAYER_DEFAULTS minus the bookkeeping ones; pass 47 added the
## new items' stats and the stage's skips and banishes).
const STAT_KEYS := ["max_hp", "damage_reduction", "regen", "move_speed", "might", "cooldown", "area", "projectile_speed",
	"duration", "amount", "magnet", "luck", "greed", "xp_gain", "lifesteal", "evade", "crit_chance", "crit_damage", "thorns",
	"execute_frac", "overkill", "haste", "shield_max", "ricochet", "cooldown_on_kill", "still_regen", "still_might",
	"barrel_speed", "barrel_seconds", "xp_drop_chance", "elite_damage", "debuff_duration", "difficulty", "skips", "banishes",
	"powerup_duration", "powerup_chance"]
## Event kinds that are an item joining or growing in the build: they carry `via` and the estimate before and after.
## (Pass 46: the lines are passives, so "line" and "line_evolution" are "passive" and "passive_evolution" from then on.)
const ITEM_KINDS := ["weapon", "passive", "mutation", "perk", "evolution", "passive_evolution"]
## A dirty sheet (adrenaline, momentum, crescendo rebuild it often) is snapshotted at most this often, unless an item
## was picked since the last snapshot.
const SNAPSHOT_EVERY := 5.0
const INDEX_KEEP := 500
## The frame clock (pass 57): every unpaused frame's wall time in whole-millisecond bins; a gap longer than FRAME_GAP_MS
## is a pause, not a frame.
const FRAME_BINS := 200
const FRAME_GAP_MS := 250.0
## The run summary stays well under PostHog's ~32 KB an event (Analytics.EVENT_MAX): past this it is folded into
## two-minute buckets, then four, ...
const SUMMARY_MAX := 24000
## Where a run's gold comes from (pass 61, Garry: "Coin Gains / Spend (During gameplay and not, have all the sources)"):
## the `source` every Run.add_gold call names. coins = a creature's dropped coin; loose_change, gold_dust, boss_coins,
## loot_cache, blasting_cap = coins of those origins (PickupManager.mark_coin); elite_purse, boss_purse = a kill's
## purse; chest = a chest's gold (its gold roll, or gold when the build changed under the reel); coin_bag = Pickpocket's
## bag; hush_money = a hit's pay; bounty = Bounty Hunter; dice = the dice shrine; empty_offer, stranger_empty,
## shop_empty = something with nothing left to give; debug = the developer buttons (boards leave it out); other = a call
## that named nothing (none should: pass61_an_test).
const GOLD_SOURCES := ["coins", "loose_change", "gold_dust", "boss_coins", "loot_cache", "blasting_cap", "elite_purse",
	"boss_purse", "chest", "coin_bag", "hush_money", "bounty", "dice", "empty_offer", "stranger_empty", "shop_empty",
	"debug", "other"]
## Where a run's gold goes (Run.spend_gold's `sink`): the shop structure, the Down! revive. The Strongbox is not a
## spend: it banks the purse (run_end's gold_banked, the save's gold_meta "strongbox").
const GOLD_SINKS := ["shop", "revive", "other"]
## The saved gold's reasons (Save.add_gold / spend_gold, sent as gold_meta): in from run_bank (the purse an extraction
## brings home), strongbox (banked mid-run), talent_refund (Take it all back); out to talent (an Upgrade rank), hero (pass 69:
## a hero bought on the title, Save.buy_hero) and wipe.
const META_REASONS := ["run_bank", "strongbox", "talent_refund", "talent", "hero", "wipe", "debug", "other"]

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
# the gold of the second (pass 61): {source: gold in}, {sink: gold out}; and the run's totals, which run_end reads
var _gold_in: Dictionary = {}
var _gold_out: Dictionary = {}
var gold_in_total: Dictionary = {}
var gold_out_total: Dictionary = {}
## what greed added on top of the sources' own amounts (part of gold_in_total)
var gold_greed := 0
# the offer on the table (pass 57): when it showed, its rerolls and banishes so far
var _offer_t0 := 0
var _offer_rerolls := 0
var _offer_banished: Array = []
# an item event waiting for its est_after before it goes to PostHog ({} = none)
var _held: Dictionary = {}
# the frame clock
var _frame_hist := PackedInt32Array()
var _frame_n := 0
var _frame_ms := 0.0
var _frame_last_us := 0


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
	# PostHog (pass 57): the run's id goes out on every event of the run and stays in this record, so a local file and its
	# rows in PostHog find each other; map_rev is the Level Editor version of the map the run played
	header["run_id"] = Analytics.uuid7()
	header["map_rev"] = Analytics.map_rev(mapdef)
	# the saved gold as the run began (pass 61: run_end's gold_before; gold_after - gold_before = what the run banked)
	header["gold_before"] = Save.gold()
	Analytics.run_begin(str(header["run_id"]))
	var em = game.get("enemies")
	var dir = game.get("director")
	_connect(em, "enemy_died", _on_enemy_died)
	_connect(em, "boss_died", func(def, _p): event("boss_end", def.id))
	_connect(dir, "boss_started", func(def): event("boss_start", def.id))
	_connect(dir, "stage_started", func(s): event("stage", "", int(s) + 1); _sheet_dirty = true)
	Run.level_up.connect(func(l): event("level", "", int(l)))
	Run.build_changed.connect(_on_build_changed)
	_on_build_changed()
	# the card screen is made after the recorder (Game._ready): its signals are joined once the game is built
	call_deferred("_join_cards")


## The settled offers (pass 57): the card screen's own signals, so the pick screens need no hook of their own.
func _join_cards() -> void:
	if game == null or not is_instance_valid(game):
		return
	var cs = game.get("cards")
	_connect(cs, "visibility_changed", _on_cards_shown)
	_connect(cs, "chosen", _on_offer_chosen)


func _connect(obj, sig: String, cb: Callable) -> void:
	if obj != null and obj is Object and obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)


func _exit_tree() -> void:
	if I == self:
		I = null
	# the game went away without an end (a quit mid-run, a tool that stops early): the record still lands, and PostHog
	# hears the run ended (the queue is on disk before the app is gone; it goes at the next launch)
	if not _finished and not samples.is_empty():
		_finished = true
		_flush_gold()
		header["result"] = "quit"
		_fill_end(false)
		_write(true)
		_send_held()
		Analytics.run_finish(_end_props(0), _summary_props())


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


## Run.add_gold (pass 61): `n` gold came into the purse from `source` (after greed; `greed` of it is greed's share).
func gold_in(source: String, n: int, greed: int = 0) -> void:
	_gold_in[source] = int(_gold_in.get(source, 0)) + n
	gold_in_total[source] = int(gold_in_total.get(source, 0)) + n
	if greed > 0:
		gold_greed += greed


## Run.spend_gold (pass 61): `n` gold went out of the purse to `sink`.
func gold_out(sink: String, n: int) -> void:
	_gold_out[sink] = int(_gold_out.get(sink, 0)) + n
	gold_out_total[sink] = int(gold_out_total.get(sink, 0)) + n


## The run's gold so far (pass 61): earned and spent, every source and sink summed.
func gold_earned() -> int:
	return _sum_ints(gold_in_total)


func gold_spent() -> int:
	return _sum_ints(gold_out_total)


static func _sum_ints(d: Dictionary) -> int:
	var t := 0
	for k in d:
		t += int(d[k])
	return t


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
	_send_held()


## The card screen came up: an offer is on the table (rerolls and banishes keep it up; the pick takes it down).
func _on_cards_shown() -> void:
	var cs = game.get("cards") if game != null and is_instance_valid(game) else null
	if cs != null and bool(cs.get("visible")) and _offer_t0 == 0:
		_offer_t0 = Time.get_ticks_msec()
		_offer_rerolls = 0
		_offer_banished = []


## An offer settled (pass 57, the card screen's `chosen`, heard before Game applies the pick): what was on the table,
## what was taken or that it was skipped, the rerolls and banishes on the way and how long it took. "route" is path
## for a weapon's mutation offer, level_up for the level-up cards.
func _on_offer_chosen(card: Dictionary) -> void:
	var cs = game.get("cards") if game != null and is_instance_valid(game) else null
	var offer: Array = []
	var path := false
	if cs != null:
		var o = cs.get("_offer")
		if o is Array:
			offer = o
		path = bool(cs.get("path_mode"))
	var ids: Array = []
	var kinds: Array = []
	var levels: Array = []
	var weapon := ""
	for c in offer:
		if not (c is Dictionary):
			continue
		ids.append(str(c.get("id", "")))
		kinds.append(str(c.get("type", "")))
		levels.append(int(c.get("level_to", 0)))
		var d = c.get("def")
		if path and weapon == "" and d is MutationDef:
			weapon = (d as MutationDef).weapon
	var skipped := bool(card.get("skipped", false))
	var extra := {"route": "path" if path else "level_up", "cards": ids, "kinds": kinds, "levels": levels, "skipped": skipped,
		"decision_ms": (Time.get_ticks_msec() - _offer_t0) if _offer_t0 > 0 else 0}
	if weapon != "":
		extra["weapon"] = weapon
	if skipped:
		extra["left"] = Run.skips_left
	if _offer_rerolls > 0:
		extra["rerolls"] = _offer_rerolls
	if not _offer_banished.is_empty():
		extra["banished"] = _offer_banished.duplicate()
	_offer_t0 = 0
	_offer_rerolls = 0
	_offer_banished = []
	event("offer", "" if skipped else str(card.get("id", "")), Run.level, extra)


# ---------------------------------------------------------------- events

## A moment in the run: {t, clock, kind, id?, level?} plus `extra`. Pass 47: a skip carries the skips left (no gold any
## more) and a chest let go adds "chest_skip" (Game); a chest's banish is Run's "banish" with "where": "chest". An item kind also records how it arrived (`via`)
## and the build's estimated DPS before it; the next build_changed fills `est_after`.
## Pass 57: the keys every event has (t, clock, kind) are never overwritten by `extra` (the death's hit kind and the
## debug hand's item kind came as "kind" and replaced the event's own: the death was recorded as "melee"); the debug
## hand's is kept as item_kind, the death's is `hit`. The event goes on to PostHog (Analytics.run_event); an item's
## waits for its est_after (the next build_changed) or the next event, whichever comes first.
func event(kind: String, id: String = "", level: int = 0, extra: Dictionary = {}) -> void:
	var e := {"t": snappedf(play_t, 0.1), "clock": snappedf(Run.elapsed, 0.1), "kind": kind}
	if id != "":
		e["id"] = id
	if level != 0:
		e["level"] = level
	for k in extra:
		if k == "kind":
			e["item_kind"] = extra[k]
		elif k != "t" and k != "clock":
			e[k] = extra[k]
	if kind in ITEM_KINDS:
		e["via"] = via
		e["est_before"] = snappedf(_est_now, 0.1)
		_pending_event = events.size()
		_item_since_snapshot = true
	# what the offer on the table went through: its rerolls and its banishes go out with its pick
	if kind == "reroll":
		_offer_rerolls += 1
	elif kind == "banish" and str(extra.get("where", "")) != "chest":
		_offer_banished.append(id)
	_send_held()
	events.append(e)
	if kind in ITEM_KINDS:
		_held = e
	else:
		Analytics.run_event(e)


## The item event waiting for its est_after goes to PostHog now (pass 57).
func _send_held() -> void:
	if _held.is_empty():
		return
	var e := _held
	_held = {}
	Analytics.run_event(e)


## Game._on_player_died: the killer is the last creature whose hit the recorder saw.
func death() -> void:
	event("death", _last_hit_key, 0, {"hit": _last_hit_kind})


# ---------------------------------------------------------------- the clock and the row

## From Game._process, so only unpaused play time counts.
func tick(delta: float) -> void:
	play_t += delta
	_acc_t += delta
	_frame()
	if _acc_t >= 1.0:
		_acc_t -= 1.0
		_sample()


## The frame clock (pass 57): this frame's wall time since the last unpaused one, into its millisecond bin.
func _frame() -> void:
	var now := Time.get_ticks_usec()
	if _frame_last_us > 0:
		var ms := float(now - _frame_last_us) / 1000.0
		if ms < FRAME_GAP_MS:
			if _frame_hist.is_empty():
				_frame_hist.resize(FRAME_BINS)
			var b := mini(int(ms), FRAME_BINS - 1)
			_frame_hist[b] = _frame_hist[b] + 1
			_frame_n += 1
			_frame_ms += ms
	_frame_last_us = now


## {fps_avg, fps_low} from the frame clock ({} before any frame): the mean, and the 1 % low (1000 over the 99th
## percentile frame time, read at the middle of its bin).
func fps_stats() -> Dictionary:
	if _frame_n <= 0 or _frame_ms <= 0.0 or _frame_hist.is_empty():
		return {}
	var need := maxi(int(ceil(float(_frame_n) * 0.01)), 1)
	var seen := 0
	var low_ms := float(FRAME_BINS)
	for b in range(FRAME_BINS - 1, -1, -1):
		seen += _frame_hist[b]
		if seen >= need:
			low_ms = float(b) + 0.5
			break
	return {"fps_avg": snappedf(1000.0 * float(_frame_n) / _frame_ms, 0.1), "fps_low": snappedf(1000.0 / low_ms, 0.1)}


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
	# the second's gold by source and by sink (pass 61)
	_put_map(row, "gold_in", _gold_in, false)
	_put_map(row, "gold_out", _gold_out, false)
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
	for k in _gold_in:
		_gold_in[k] = 0
	for k in _gold_out:
		_gold_out[k] = 0
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
	_flush_gold()
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
	_send_held()
	Analytics.run_finish(_end_props(int(Run.last_result.get("banked", 0))), _summary_props())


## Gold of a second the rows have not taken yet (pass 61: a chest or the shop pays while the game is paused, and the
## last part-second of a run makes no row) goes into the last row, so the rows' gold sums to the run's totals.
func _flush_gold() -> void:
	if _sum_ints(_gold_in) == 0 and _sum_ints(_gold_out) == 0:
		return
	if samples.is_empty():
		_sample()
		return
	var row: Dictionary = samples[-1]
	for pair in [["gold_in", _gold_in], ["gold_out", _gold_out]]:
		var acc: Dictionary = pair[1]
		for k in acc:
			var n: int = acc[k]
			if n == 0:
				continue
			if not (row.get(pair[0]) is Dictionary):
				row[pair[0]] = {}
			row[pair[0]][k] = int(row[pair[0]].get(k, 0)) + n
			acc[k] = 0


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


## What PostHog's run_end carries (pass 57), from the completed header; `banked` is the gold that came home (0 for a
## quit: the run never reached end_run).
func _end_props(banked: int) -> Dictionary:
	var p := {"result": str(header.get("result", "")), "t": header.get("length", 0.0), "clock": header.get("clock", 0.0),
		"stage": header.get("stage", 1), "wave": header.get("endless_wave", 0), "level": header.get("level", 1),
		"kills": header.get("kills", 0), "gold": header.get("gold", 0), "banked": banked,
		"strongbox": header.get("strongbox", 0), "revives": header.get("revives", 0)}
	p.merge(gold_end(banked), true)
	return p


## The run's gold as it ended (pass 61, on run_end): gold_earned (every source, greed in; gold_greed is greed's share,
## gold_debug the developer buttons'), gold_spent (shop, revive), gold_strongbox (banked mid-run), gold_purse (what he
## held at the end), gold_banked (the Strongbox's and the extraction's: all that reached the save), gold_lost (the purse
## of a death, an abandon or a quit, left in the sand), gold_before / gold_after (the saved gold as the run began and
## now). earned - spent = strongbox + purse = banked + lost.
func gold_end(banked: int) -> Dictionary:
	var purse := int(header.get("gold", Run.run_gold))
	var strongbox := int(header.get("strongbox", Run.banked_gold))
	var result := str(header.get("result", ""))
	var lost := purse if (Run.died or result == "quit" or result == "abandon" or result == "death") else 0
	return {"gold_earned": gold_earned(), "gold_spent": gold_spent(), "gold_greed": gold_greed,
		"gold_debug": int(gold_in_total.get("debug", 0)), "gold_strongbox": strongbox, "gold_purse": purse,
		"gold_banked": strongbox + banked, "gold_lost": lost,
		"gold_before": int(header.get("gold_before", Save.gold())), "gold_after": Save.gold()}


## PostHog's run_summary (pass 57): the rows folded (fit_summary) and the frame clock's numbers; pass 60 adds the final
## build (as JSON and as one readable line), the kills each weapon made and the build's final estimated DPS.
func _summary_props() -> Dictionary:
	var s := RunAnalytics.fit_summary(samples)
	s.merge(fps_stats(), true)
	s["kills_by_weapon"] = RunAnalytics._top(Run.kills_by_weapon, 10, 1.0)
	var b := _build()
	s["build"] = b
	s["build_text"] = build_text(b)
	if not samples.is_empty() and samples[-1] is Dictionary:
		s["est_end"] = float((samples[-1] as Dictionary).get("est_total", 0.0))
	# pass 61: what greed added to the run's gold (gold_by_source holds it inside each source's total)
	s["gold_greed"] = gold_greed
	return s


## One line a person can read in a PostHog table: "Revolver 5 +3 · Peashooter 2 | Clover 2 · Brawn 1 | Afterglow".
func build_text(b: Dictionary) -> String:
	var ws: Array = []
	for w in b.get("weapons", []):
		if w is Dictionary:
			var muts: Array = (w as Dictionary).get("mutations", [])
			var mut_s := ""
			if not muts.is_empty():
				mut_s = " +%d" % muts.size()
			ws.append("%s %d%s" % [_name_of(str(w.get("id", ""))), int(w.get("level", 1)), mut_s])
	var ps: Array = []
	var passives: Dictionary = b.get("passives", {})
	for id in passives.keys():
		ps.append("%s %d" % [_name_of(str(id)), int(passives[id])])
	var ks: Array = []
	for id in b.get("perks", []):
		ks.append(_name_of(str(id)))
	var parts: Array = []
	for group in [ws, ps, ks]:
		if not group.is_empty():
			parts.append(" · ".join(PackedStringArray(group)))
	return " | ".join(PackedStringArray(parts))


## The run as PostHog's run_summary carries it (pass 57: Garry's local dashboard in one event). Per bucket of `bucket_s`
## play seconds (a minute; `m_secs` says how many rows it holds, the last one is short): the stage and level at its
## end (m_stage, m_level), the crowd against the cap (m_alive, m_cap: means), what came and went (m_spawned, m_killed:
## sums), the pressure (m_press, m_press_hp, m_press_dmg: means), the build's promise against the damage that landed
## (m_est: mean estimated DPS, m_dmg: damage dealt in the bucket), the hero (m_hp: lowest health fraction, m_took: HP
## lost, m_hits: hits taken, m_low_s: seconds under 30 %, m_gold: the purse at its end); then the run's totals by id,
## the top ten each (dmg_by_weapon, est_by_weapon = the estimate summed over the seconds held, took_by_creature,
## spawned_by_creature, killed_by_creature) and the survivability sums (evaded, shielded, healed). Pass 61: the gold
## that came in and went out in each bucket (m_gold_in, m_gold_out: sums) and the run's gold by source and by sink
## (gold_by_source, gold_spent_by: every one, up to 30).
static func summary(rows: Array, bucket_s: float = 60.0) -> Dictionary:
	var n := 0
	for r in rows:
		if r is Dictionary:
			n = maxi(n, _bucket_of(float((r as Dictionary).get("t", 0.0)), bucket_s) + 1)
	var secs := _zeros(n)
	var stage := _zeros(n)
	var level := _zeros(n)
	var alive := _zeros(n)
	var cap := _zeros(n)
	var press := _zeros(n)
	var press_hp := _zeros(n)
	var press_dmg := _zeros(n)
	var est := _zeros(n)
	var dmg := _zeros(n)
	var took := _zeros(n)
	var hits := _zeros(n)
	var low := _zeros(n)
	var gold := _zeros(n)
	var spawned := _zeros(n)
	var killed := _zeros(n)
	var hp := _zeros(n)
	hp.fill(1.0)
	# pass 60: the rest of the local dashboard's curves (Garry: "Run Curves doesn't seem to contain all of the
	# dashboard.html stuff"): the hero's max HP and shield, the raw damage thrown at him, what he evaded, spent and
	# healed, seconds shielded / invulnerable, the crowd's load against the hard cap, XP into the level, the Strongbox,
	# the kill total, the director's phase, and each weapon's damage minute by minute (the top eight, dmg_by_minute: a map, not an m_ array)
	var hp_max := _zeros(n)
	var shield_pts := _zeros(n)
	var took_raw := _zeros(n)
	var m_evaded := _zeros(n)
	var m_shielded := _zeros(n)
	var m_healed := _zeros(n)
	var shield_s := _zeros(n)
	var invuln_s := _zeros(n)
	var crowd_load := _zeros(n)
	var hard_cap := _zeros(n)
	var xp := _zeros(n)
	var banked := _zeros(n)
	var kills := _zeros(n)
	var phase := _zeros(n)
	# pass 61: gold in and out a bucket, and the run's gold by source and by sink
	var gold_in := _zeros(n)
	var gold_out := _zeros(n)
	var gold_by := {}
	var spent_by := {}
	var dmg_by_min := {}
	var took_kind := {}
	var dmg_by := {}
	var est_by := {}
	var took_by := {}
	var spawned_by := {}
	var killed_by := {}
	var evaded := 0
	var shielded := 0.0
	var healed := 0.0
	for r in rows:
		if not (r is Dictionary):
			continue
		var row: Dictionary = r
		var i := _bucket_of(float(row.get("t", 0.0)), bucket_s)
		secs[i] += 1.0
		stage[i] = maxf(stage[i], float(row.get("stage", 1)))
		level[i] = maxf(level[i], float(row.get("level", 1)))
		alive[i] += float(row.get("alive", 0))
		cap[i] += float(row.get("cap", 0))
		press[i] += float(row.get("press", 0.0))
		press_hp[i] += float(row.get("press_hp", 0.0))
		press_dmg[i] += float(row.get("press_dmg", 0.0))
		est[i] += float(row.get("est_total", 0.0))
		hits[i] += float(row.get("hits", 0))
		# the rows run in time order: the bucket's last row leaves its purse
		gold[i] = float(row.get("gold", 0))
		banked[i] = float(row.get("banked", 0))
		kills[i] = float(row.get("kills", 0))
		phase[i] = float(row.get("phase", 0))
		hp_max[i] = float(row.get("hp_max", 0.0))
		xp[i] = float(row.get("xp", 0.0)) / maxf(float(row.get("xp_next", 1.0)), 1.0)
		shield_pts[i] += float(row.get("shield", 0.0))
		if float(row.get("shield", 0.0)) > 0.0:
			shield_s[i] += 1.0
		if int(row.get("invuln", 0)) > 0:
			invuln_s[i] += 1.0
		crowd_load[i] += float(row.get("load", 0.0))
		hard_cap[i] = maxf(hard_cap[i], float(row.get("hard_cap", 0)))
		took_raw[i] += float(row.get("took_raw", 0.0))
		m_evaded[i] += float(row.get("evaded", 0))
		m_shielded[i] += float(row.get("shielded", 0.0))
		m_healed[i] += float(row.get("healed", 0.0))
		spawned[i] += _add_into(spawned_by, row.get("spawned"))
		killed[i] += _add_into(killed_by, row.get("killed"))
		dmg[i] += _add_into(dmg_by, row.get("dmg"))
		took[i] += _add_into(took_by, row.get("took"))
		_add_into(est_by, row.get("est"))
		_add_into(took_kind, row.get("took_kind"))
		gold_in[i] += _add_into(gold_by, row.get("gold_in"))
		gold_out[i] += _add_into(spent_by, row.get("gold_out"))
		var d: Variant = row.get("dmg")
		if d is Dictionary:
			for w in (d as Dictionary).keys():
				if not dmg_by_min.has(w):
					var a: Array = []
					a.resize(n)
					a.fill(0.0)
					dmg_by_min[w] = a
				dmg_by_min[w][i] = float(dmg_by_min[w][i]) + float(d[w])
		if row.has("hp") and float(row.get("hp_max", 0.0)) > 0.0:
			var f := float(row["hp"]) / float(row["hp_max"])
			hp[i] = minf(hp[i], f)
			if f < 0.3:
				low[i] += 1.0
		evaded += int(row.get("evaded", 0))
		shielded += float(row.get("shielded", 0.0))
		healed += float(row.get("healed", 0.0))
	for i in range(n):
		var k := maxf(secs[i], 1.0)
		alive[i] /= k
		cap[i] /= k
		press[i] /= k
		press_hp[i] /= k
		press_dmg[i] /= k
		est[i] /= k
		shield_pts[i] /= k
		crowd_load[i] /= k
	# each weapon's damage minute by minute, the top eight by their total
	var by_min := {}
	var top_w: Array = _top(dmg_by, 8, 1.0).keys()
	for w in top_w:
		if dmg_by_min.has(w):
			var ints: Array = []
			for v in dmg_by_min[w]:
				ints.append(int(round(float(v))))
			by_min[w] = ints
	return {"bucket_s": int(bucket_s), "minutes": n, "m_secs": _ints(secs), "m_stage": _ints(stage), "m_level": _ints(level),
		"m_alive": _ints(alive), "m_cap": _ints(cap), "m_spawned": _ints(spawned), "m_killed": _ints(killed),
		"m_press": _ints(press), "m_press_hp": _ints(press_hp), "m_press_dmg": _ints(press_dmg), "m_est": _snaps(est, 0.1),
		"m_dmg": _ints(dmg), "m_hp": _snaps(hp, 0.01), "m_took": _snaps(took, 0.1), "m_hits": _ints(hits),
		"m_low_s": _ints(low), "m_gold": _ints(gold),
		"m_hp_max": _ints(hp_max), "m_shield": _snaps(shield_pts, 0.1), "m_took_raw": _snaps(took_raw, 0.1),
		"m_evaded": _ints(m_evaded), "m_shielded": _snaps(m_shielded, 0.1), "m_healed": _snaps(m_healed, 0.1),
		"m_shield_s": _ints(shield_s), "m_invuln_s": _ints(invuln_s), "m_load": _snaps(crowd_load, 0.1),
		"m_hard_cap": _ints(hard_cap), "m_xp": _snaps(xp, 0.01), "m_banked": _ints(banked), "m_kills": _ints(kills),
		"m_phase": _ints(phase), "dmg_by_minute": by_min,
		"m_gold_in": _ints(gold_in), "m_gold_out": _ints(gold_out),
		"gold_by_source": _top(gold_by, 30, 1.0), "gold_spent_by": _top(spent_by, 30, 1.0),
		"dmg_by_weapon": _top(dmg_by, 10, 1.0), "est_by_weapon": _top(est_by, 10, 1.0),
		"took_by_creature": _top(took_by, 10, 0.1), "spawned_by_creature": _top(spawned_by, 10, 1.0),
		"killed_by_creature": _top(killed_by, 10, 1.0), "took_kind": _top(took_kind, 5, 0.1),
		"evaded": evaded, "shielded": snappedf(shielded, 0.1), "healed": snappedf(healed, 0.1)}


## summary() in minute buckets, folded into two-minute ones (then four, ...) while it is bigger than `max_bytes`.
static func fit_summary(rows: Array, max_bytes: int = SUMMARY_MAX) -> Dictionary:
	var b := 60.0
	var s := summary(rows, b)
	while JSON.stringify(s).length() > max_bytes and int(s.get("minutes", 0)) > 1:
		b *= 2.0
		s = summary(rows, b)
	return s


## The bucket a row at play second `t` falls in: (0, b] is the first, so the row stamped 60.0 closes minute one.
static func _bucket_of(t: float, b: float) -> int:
	return maxi(int(ceil(t / b - 0.0001)) - 1, 0)


static func _zeros(n: int) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(n)
	a.fill(0.0)
	return a


static func _ints(a: PackedFloat64Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(round(v)))
	return out


static func _snaps(a: PackedFloat64Array, step: float) -> Array:
	var out: Array = []
	for v in a:
		out.append(snappedf(v, step))
	return out


## Adds every value of `d` (a row's {id: amount} map, or nothing) into `acc`; returns their sum.
static func _add_into(acc: Dictionary, d: Variant) -> float:
	if not (d is Dictionary):
		return 0.0
	var total := 0.0
	for k in (d as Dictionary).keys():
		var v := float(d[k])
		acc[k] = float(acc.get(k, 0.0)) + v
		total += v
	return total


## The `n` biggest of an {id: amount} map, whole numbers when `step` is 1 or more, else snapped to it.
static func _top(d: Dictionary, n: int, step: float) -> Dictionary:
	var ks: Array = d.keys()
	ks.sort_custom(func(a, b) -> bool: return float(d[a]) > float(d[b]))
	var out := {}
	for i in range(mini(n, ks.size())):
		var v := float(d[ks[i]])
		out[str(ks[i])] = int(round(v)) if step >= 1.0 else snappedf(v, step)
	return out


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
