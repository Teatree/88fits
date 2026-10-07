## The state of the current run, kept in an autoload so every screen (HUD, pause, results) reads one object.
## The Game scene drives it; this holds data and build logic, not nodes.
extends Node

signal level_up(level: int)
signal xp_changed(xp: float, needed: float)
signal xp_gained(amount: float)
signal build_changed
signal gold_changed(run_gold: int)
signal kills_changed(kills: int)
signal stage_changed(stage: int)
signal weapon_evolved(weapon_id: String)
## Gold the run just gained, after greed (pass 47: the HUD's coin pop); only for an amount above 0.
signal gold_gained(amount: int)

var active := false
var character: CharacterDef
var map: MapDef
var elapsed := 0.0
## Seconds the stage clock (`elapsed`) stood still while the run played on (pass 47): a boss fight, a portal wait. The
## buffs count on buff_clock() = elapsed + held_time, so a Barrel Rush boost, Berserk or adrenaline runs out in a boss
## fight too (they lasted until the boss died). WaveDirector adds to it outside the normal phase.
var held_time := 0.0
## 0-based. A new stage refills the skips and banishes (pass 47: they are a stage's), whoever moves it (the director's
## portal, the arena's clock, a test).
var stage := 0:
	set(v):
		var moved := v != stage
		stage = v
		if moved:
			refill_choices()
var endless := false
var level := 1
var xp := 0.0
var run_gold := 0
## gold already sent to the homestead by a Strongbox this run (the results screen says so)
var banked_gold := 0
var kills := 0
var alive := 0
var extracted := false
## What the results screen reads once the run is banked (Game.end_run): gold_before, banked, lost, strongbox, prev_best,
## and hit_log / last_hit (the hero's last 30 s of hits as Player.damage_log_text() and the last entry {by, kind, ...},
## for the debug view; pass 45).
var last_result: Dictionary = {}
var died := false
var revives_used := 0
var thumb_lifted := false
var no_lift_time := 0.0
var max_level_reached := 1
var kills_by_enemy: Dictionary = {}
var kills_by_weapon: Dictionary = {}
var damage_by_weapon: Dictionary = {}
var chests_opened := 0
var evolutions := 0
var bosses_killed := 0

var player_sheet: StatSheet = StatSheet.new()
## Timed buffs from pickups: {"id", "label", "effects", "source", "until"}; re-applied whenever the sheet is rebuilt.
var timed: Array = []
var lifesteal_pool := 0.0
## the most of max HP a second lifesteal may heal, whatever the damage
const LIFESTEAL_CAP := 0.04
var _lifesteal_second := 0.0
var _lifesteal_healed_this_second := 0.0
signal lifesteal_healed(amount: float)
## Buck's momentum: 0..1, applied to the sheet as a speed and might bonus (CharacterDef.momentum in the JSON)
var momentum := 0.0
## Berserk: the hero's weapon speed (1 = normal, 2 = twice as fast), cached off the sheet for the behaviours' own clocks
var haste := 1.0
var momentum_def: Dictionary = {}
## Array of WeaponInstance (see core/systems/WeaponInstance.gd)
var weapons: Array = []
## passive id -> level, in the order they were taken; lines and passive items alike (pass 47: held_lines() are the
## HUD's line slots, five since pass 52, held_passives() the rest); an evolved line sits in its source's place
var passives: Dictionary = {}
## ids banished from this run's pool
var banished: Array = []
## Adrenaline (a passive): kill stacks that lift speed and might, gone ADRENALINE_SECONDS after the last kill
const ADRENALINE_MAX := 20
const ADRENALINE_SECONDS := 4.0
var adrenaline := 0
## Calavera's Crescendo (pass 43): might per kill, up to the perk's cap, until a hit (Game resets it)
var crescendo := 0
var _crescendo_dirty := false
var _crescendo_built := -1.0
var adrenaline_until := 0.0
var _adrenaline_dirty := false
var _adrenaline_built := -1.0
## Desperado (pass 46, a passive): the share of health missing in tenths (note_hp), folded into might as its own source.
## The sheet follows a tenth's change at most every DESPERADO_REBUILD_MS of real time (the run clock stands still in a
## boss fight, when it matters most).
var desperado_bucket := 0
var _desperado_dirty := false
var _desperado_built_ms := -100000
var _desperado_source := ""
const DESPERADO_REBUILD_MS := 250
## Steady Hand (pass 47, a passive: "The longer you stand still, the more damage you do. Max +100% damage"): the Player
## tells the seconds the hero has stood still (note_still, 0 once he moves); the bonus is the passive's `still_might` a
## second, at most STEADY_MAX, folded into attack damage in STEADY_STEP buckets (steady_bucket) so the sheet follows only
## when a bucket changes, at most every DESPERADO_REBUILD_MS of real time like Desperado.
const STEADY_MAX := 1.0
const STEADY_STEP := 0.05
var still_seconds := 0.0
var steady_bucket := 0
var _steady_dirty := false
var _steady_source := ""
## The timed boost a smashed barrel gives a hero holding Barrel Rush (pass 47, barrel_rush()).
const BARREL_RUSH := "barrel_rush"
## The timed boost a landed hit gives a hero holding Skedaddle (pass 48, skedaddle()).
const SKEDADDLE := "skedaddle"
## Hot Streak (pass 48, a passive item; pass 49, Garry: like Megabonk's Demonic Soul, "permanently increases your damage
## per kill for the rest of the run", our own theme, +100% only after a lot of kills): `streak` counts the kills made
## while it is held (add_kill), and nothing takes them away. The bonus is the passive's `kill_might` (attack damage per
## STREAK_PER kills: 5% a level, so +100% at 4,000 kills at level 5, 20,000 at level 1) x the kills, STREAK_CAP at most,
## in whole percents (streak_bucket), folded into attack damage as its own source; the sheet follows only when the
## percent changes, at most every DESPERADO_REBUILD_MS of real time like Desperado.
const STREAK_PER := 1000.0
const STREAK_CAP := 1.0
var streak := 0
var streak_bucket := 0
var _streak_dirty := false
var _streak_source := ""
## Gas Mask (pass 48, a passive item): the damage reduction each poisoned creature alive is worth, up to the passive's
## `gas_mask_cap` (gas_mask_dr).
const GAS_MASK_PER := 0.01
## materials picked up this run (bones from Elites, relics from bosses): banked at the end, half of them on a death
var run_materials: Dictionary = {"bones": 0, "relics": 0}
var harvest: Dictionary = {}          # what the homestead yielded at this run's end (Save.harvest)
## the Stranger's cut: a fraction of max HP given up for his item, for the rest of the run
var stranger_cost := 0.0
## The level-up's choices (pass 47, Garry: "only two skips per Stage, and those skips work for both Level Ups and
## Chests ... the same treatment for Banish, but initially Players only get 1 Banish"): skips and banishes are a stage's,
## refill_choices() puts them back to the sheet's `skips` (2) and `banishes` (1) at the run's start and at every stage,
## the Mirror adding a rank each; rerolls stay the run's. use_skip / use_banish spend one.
var rerolls_left := 0
var skips_left := 0
var banishes_left := 0

## The HUD's strip (pass 47, Garry: "We just give 6 slots for both and keep that static"; pass 52: "Reduce the number of
## Slots for Weapons and Line Items down to 5 instead of 6"): five weapon slots and five line slots, all open from the
## start; passive items take no slot and have no cap.
const MAX_WEAPONS := 5
const MAX_LINES := 5
## The paths (pass 26): a weapon's mutations open at this level, one pick per weapon per stage. A weapon evolves at its
## top level once it carries every mutation of its path (pass 48, Garry: "evolutions only once every mutation is
## collected"; path_progress; it was two of the three).
const MUTATION_FROM_LEVEL := 1
var mutations: Dictionary = {}        # weapon family id -> [mutation ids]
var mutation_stage: Dictionary = {}   # weapon family id -> the stage of its last pick (path or hero)
var mutation_misses: Dictionary = {}  # weapon family id -> offers in a row without one of its open mutations
var perks: Array = []                 # perk ids taken
var perk_gap := 5                     # offers since a perk card was shown (a perk is offered at most once in five)
var path_slot := 0                    # the next path slot of the stage (WaveTimeline.path_times)


## The map's layout roll for this run (Red Canyon reads it): random each run, or `forced_map_seed` when a tool wants
## the same desert every time (the capture tool).
var map_seed := 0
var forced_map_seed := 0
## Poisoned creatures alive right now (pass 48: EnemyManager counts them once a tick; Gas Mask reads it).
var poisoned_alive := 0
## Phoenix Feather (pass 48): its one free revive this run is spent (phoenix_ready / use_phoenix).
var phoenix_used := false


func start(p_character: CharacterDef, p_map: MapDef) -> void:
	active = true
	character = p_character
	map = p_map
	map_seed = forced_map_seed if forced_map_seed != 0 else (randi() % 999983) + 1
	elapsed = 0.0
	held_time = 0.0
	stage = 0
	arena = false
	endless = false
	level = 1
	xp = 0.0
	run_gold = 0
	banked_gold = 0
	kills = 0
	alive = 0
	extracted = false
	died = false
	revives_used = 0
	phoenix_used = false
	poisoned_alive = 0
	thumb_lifted = false
	no_lift_time = 0.0
	max_level_reached = 1
	kills_by_enemy.clear()
	kills_by_weapon.clear()
	damage_by_weapon.clear()
	chests_opened = 0
	evolutions = 0
	bosses_killed = 0
	weapons.clear()
	passives.clear()
	mutations = {}
	mutation_stage = {}
	mutation_misses = {}
	perks = []
	perk_gap = 5
	path_slot = 0
	banished.clear()
	run_materials = {"bones": 0, "relics": 0}
	stranger_cost = 0.0
	adrenaline = 0
	adrenaline_until = 0.0
	crescendo = 0
	_crescendo_dirty = false
	desperado_bucket = 0
	_desperado_dirty = false
	_desperado_source = ""
	still_seconds = 0.0
	steady_bucket = 0
	_steady_dirty = false
	_steady_source = ""
	streak = 0
	streak_bucket = 0
	_streak_dirty = false
	_streak_source = ""
	timed.clear()
	lifesteal_pool = 0.0
	_lifesteal_second = 0.0
	_lifesteal_healed_this_second = 0.0
	momentum = 0.0
	momentum_def = p_character.momentum if p_character else {}
	_build_player_sheet()
	rerolls_left = player_sheet.get_int("rerolls")
	refill_choices()
	Save.note_run_started()
	build_changed.emit()


func end() -> void:
	active = false


## Every hero's 1% crit chance (pass 52, StatSheet.PLAYER_DEFAULTS) is left out under the test runner, so a suite that
## counts a weapon's exact damage never meets a random double; pass52_test turns it back on to check it.
var base_crit := not Array(OS.get_cmdline_args()).any(func(a) -> bool: return str(a).ends_with("GdUnitCmdTool.gd"))


func _build_player_sheet() -> void:
	player_sheet = StatSheet.new()
	player_sheet.scope = "player"
	player_sheet.set_bases(StatSheet.PLAYER_DEFAULTS)
	if not base_crit:
		player_sheet.set_bases({"crit_chance": 0.0})
	if character:
		player_sheet.add_effects(character.trait_effects, character.display_name)
	# the Mirror: the form picked for each talent, as many times as it has ranks
	for tdef: TalentDef in Registry.talents.values():
		var rank := Save.talent_rank(tdef.id)
		if rank > 0:
			var form := Save.talent_form(tdef.id)
			player_sheet.add_effects(tdef.effects_for(form, rank), "%s: %s %d" % [tdef.display_name, tdef.form_name(form), rank])
	for tb in timed:
		player_sheet.add_effects(tb["effects"], tb["source"])
	if momentum > 0.0 and not momentum_def.is_empty():
		var e1 := Effect.new()
		e1.stat = "move_speed"; e1.op = "mul"; e1.value = float(momentum_def.get("speed_bonus", 0.6)) * momentum; e1.target = "player"
		var e2 := Effect.new()
		e2.stat = "might"; e2.op = "mul"; e2.value = float(momentum_def.get("might_bonus", 0.5)) * momentum; e2.target = "player"
		player_sheet.add_effects([e1, e2], "Momentum %d%%" % int(round(momentum * 100.0)))
	if stranger_cost > 0.0:
		var sc := Effect.new()
		sc.stat = "max_hp"; sc.op = "mul"; sc.value = -stranger_cost; sc.target = "player"
		player_sheet.add_effects([sc], "The Stranger's cut")
	_apply_passives_to_sheet()
	# adrenaline reads the per-stack values the passives just put on the sheet, so it goes on last
	if adrenaline > 0:
		var sp: float = player_sheet.get_stat("adrenaline_speed", 0.0) * adrenaline
		var mg: float = player_sheet.get_stat("adrenaline_might", 0.0) * adrenaline
		if sp > 0.0 or mg > 0.0:
			var a1 := Effect.new()
			a1.stat = "move_speed"; a1.op = "mul"; a1.value = sp; a1.target = "player"
			var a2 := Effect.new()
			a2.stat = "might"; a2.op = "mul"; a2.value = mg; a2.target = "player"
			player_sheet.add_effects([a1, a2], "Adrenaline ×%d" % adrenaline)
	if crescendo > 0 and has_perk("crescendo"):
		var c1 := Effect.new()
		c1.stat = "might"; c1.op = "mul"; c1.value = crescendo_might(); c1.target = "player"
		player_sheet.add_effects([c1], "Crescendo +%d%%" % int(round(crescendo_might() * 100.0)))
	haste = player_sheet.get_stat("haste", 1.0)


## What Crescendo adds to might right now (its stacks × the perk's per_kill, capped by its max).
func crescendo_might() -> float:
	return minf(float(crescendo) * perk_param("crescendo", "per_kill", 0.01), perk_param("crescendo", "max", 0.4))


## A hit drops Crescendo to nothing.
func reset_crescendo() -> void:
	if crescendo > 0:
		crescendo = 0
		rebuild_sheets()


## What Hot Streak adds to attack damage right now (the step on the sheet): the passive's `kill_might` per STREAK_PER kills
## x the kills made while it is held, STREAK_CAP at most, in whole percents; 0 without the passive. The HUD's label reads
## it.
func hot_streak_bonus() -> float:
	return float(_streak_percent()) / 100.0


## Hot Streak's bonus in whole percents now (pass 49): what the sheet carries, a step at a time.
func _streak_percent() -> int:
	var km: float = player_sheet.get_stat("kill_might", 0.0) if player_sheet else 0.0
	if km <= 0.0 or streak <= 0:
		return 0
	return floori(minf(float(streak) * km / STREAK_PER, STREAK_CAP) * 100.0 + 0.0001)


## Hot Streak on the sheet as its own source ("Hot Streak +24%": the pause screen's breakdown names it), redone from the
## step.
func _apply_streak() -> void:
	if _streak_source != "":
		player_sheet.remove_source(_streak_source)
		_streak_source = ""
	_streak_dirty = false
	var v := hot_streak_bonus()
	if v <= 0.0:
		return
	_streak_source = "Hot Streak +%d%%" % int(round(v * 100.0))
	player_sheet.add_effects([Effect.make("might", "mul", v, "player")], _streak_source)


## Skedaddle (pass 48, a passive item: "After a hit, run 20% faster for 1.5 s"): a landed hit gives a hero holding it
## (`hurt_speed` above 0) that much more move speed for `hurt_speed_seconds`, a quiet timed boost; another hit starts the
## clock again, at the new speed when a level was taken since. True when it started or refreshed the boost (Game shows
## the red speed effect then). Game._on_player_hit calls it.
func skedaddle() -> bool:
	var sp := player_sheet.get_stat("hurt_speed", 0.0)
	var secs := player_sheet.get_stat("hurt_speed_seconds", 0.0)
	if sp <= 0.0 or secs <= 0.0:
		return false
	_speed_boost(SKEDADDLE, "SKEDADDLE", sp, secs)
	return true


## Seconds left of Skedaddle's boost (pass 48: its red trail, the HUD), 0 when it is not running.
func skedaddle_left() -> float:
	return boost_left(SKEDADDLE)


## Gas Mask (pass 48, a passive item): GAS_MASK_PER damage reduction for every poisoned creature alive (poisoned_alive,
## which EnemyManager counts once a tick), up to the passive's `gas_mask_cap`; 0 without it. Player.take_damage adds it
## to the reduction under the same 80% cap; the HUD's label reads it.
func gas_mask_dr() -> float:
	var cap := player_sheet.get_stat("gas_mask_cap", 0.0)
	if cap <= 0.0 or poisoned_alive <= 0:
		return 0.0
	return minf(cap, GAS_MASK_PER * float(poisoned_alive))


## Phoenix Feather (pass 48): the hero carries a free revive (the player stat `phoenix_revive`) not spent this run.
## Game._on_player_died stands him up with it before the Down! screen.
func phoenix_ready() -> bool:
	return not phoenix_used and player_sheet.get_stat("phoenix_revive", 0.0) > 0.0


## Spends Phoenix Feather's revive (once a run; the run recorder hears it as a "revive" of kind "phoenix", Game._revive).
func use_phoenix() -> void:
	phoenix_used = true


## Whether a passive item held has done its one job this run (pass 48: Phoenix Feather once its revive is spent; the
## item stays held, so it is never offered again), for the UI's SPENT mark.
func item_spent(def: ContentDef) -> bool:
	if def == null or not phoenix_used or not def is PassiveDef:
		return false
	for e in (def as PassiveDef).effects_for_level(1):
		if e is Effect and (e as Effect).stat == "phoenix_revive":
			return true
	return false


## The map's pace knob (pass 48, WaveTimeline.move_pace): the hero, the creatures and their shots move at this fraction,
## and wind-ups and warnings last 1/pace as long. 1 without a map.
func move_pace() -> float:
	if map == null or map.timeline == null:
		return 1.0
	return maxf(map.timeline.move_pace, 0.05)


## The hero's health as it changes (pass 46; Player tells it). Cheap: only the missing share in tenths is kept, and the
## sheet is asked to follow (by tick_timed) only when that tenth changes and the hero holds Desperado.
func note_hp(hp: float, max_hp: float) -> void:
	var b := clampi(int(floor((1.0 - hp / maxf(max_hp, 1.0)) * 10.0)), 0, 10)
	if b == desperado_bucket:
		return
	desperado_bucket = b
	if player_sheet.get_stat("desperado", 0.0) > 0.0:
		_desperado_dirty = true


## What Desperado adds to might right now: the passive's `desperado` × the missing share in tenths (+60% at level 5
## with the hero nearly down).
func desperado_might() -> float:
	return player_sheet.get_stat("desperado", 0.0) * float(desperado_bucket) / 10.0


## Desperado on the sheet as its own source (the pause screen's breakdown names it), redone from the bucket.
func _apply_desperado() -> void:
	if _desperado_source != "":
		player_sheet.remove_source(_desperado_source)
		_desperado_source = ""
	_desperado_dirty = false
	_desperado_built_ms = Time.get_ticks_msec()
	var v := desperado_might()
	if v <= 0.0:
		return
	var e := Effect.new()
	e.stat = "might"; e.op = "mul"; e.value = v; e.target = "player"
	_desperado_source = "Desperado +%d%%" % int(round(v * 100.0))
	player_sheet.add_effects([e], _desperado_source)


func _apply_passives_to_sheet() -> void:
	for pid in passives.keys():
		player_sheet.remove_source("passive:" + pid)
	for pid in passives.keys():
		var def: PassiveDef = Registry.passive(pid)
		if def:
			player_sheet.add_effects(def.effects_for_level(passives[pid]), "passive:" + pid)
	# the hero's favourite passive may bring effects of its own while it is held (CharacterDef.favourite_passive_bonus)
	if character and character.favourite_passive != "":
		var fsrc := "favourite:" + character.favourite_passive
		player_sheet.remove_source(fsrc)
		var fb: Dictionary = character.favourite_passive_bonus
		if passives.has(character.favourite_passive) and str(fb.get("type", "")) == "effects" and fb.get("effects") is Array:
			player_sheet.add_effects(fb["effects"], fsrc)
	# the perks and the mutations that reach the hero (Rattle's slow, Blight's pass-on, Phosphorus's burn)
	for pk in perks:
		player_sheet.remove_source("perk:" + pk)
		var pdef: PerkDef = Registry.perk(pk)
		if pdef:
			player_sheet.add_effects(pdef.effects, "perk:" + pk)
	for fam in mutations.keys():
		for mid in mutations[fam]:
			player_sheet.remove_source("mutation:" + mid)
			var mdef: MutationDef = Registry.mutation(mid)
			if mdef:
				player_sheet.add_effects(mdef.player_effects(), "mutation:" + mid)
	# Desperado reads the `desperado` the passives just put on the sheet (Hot Streak its `kill_might`)
	_apply_desperado()
	_apply_steady()
	streak_bucket = _streak_percent()
	_apply_streak()


## The hero has stood still this long (pass 47; the Player tells it, 0 when he moves). Cheap: only Steady Hand's bucket
## is kept, and the sheet is asked to follow (by tick_timed) only when the bucket changes.
func note_still(seconds: float) -> void:
	still_seconds = maxf(seconds, 0.0)
	var per := player_sheet.get_stat("still_might", 0.0)
	var b := 0
	if per > 0.0 and still_seconds > 0.0:
		b = int(floor(minf(per * still_seconds, STEADY_MAX) / STEADY_STEP + 0.0001))
	if b != steady_bucket:
		steady_bucket = b
		_steady_dirty = true


## What Steady Hand adds to attack damage right now (the bucket on the sheet): 0 .. STEADY_MAX (+100%).
func steady_might() -> float:
	return float(steady_bucket) * STEADY_STEP


## Steady Hand on the sheet as its own source ("Steady Hand +35%", the pause screen's breakdown names it).
func _apply_steady() -> void:
	if _steady_source != "":
		player_sheet.remove_source(_steady_source)
		_steady_source = ""
	_steady_dirty = false
	var v := steady_might()
	if v <= 0.0:
		return
	_steady_source = "Steady Hand +%d%%" % int(round(v * 100.0))
	player_sheet.add_effects([Effect.make("might", "mul", v, "player")], _steady_source)


## The debug arena (pass 33.4): set by the title screen before Game loads (arena_next), held through the session.
var arena := false
var arena_next := false


## How many lines the run may hold (pass 47): five all run since pass 52, whatever the stage; as many as it likes in the
## debug arena.
## Passive items have no cap.
func line_cap() -> int:
	return 99 if arena else MAX_LINES


## How many weapons the run may hold (pass 47): five all run since pass 52, whatever the stage (the arena too).
func weapon_cap() -> int:
	return MAX_WEAPONS


## The lines held (pass 47), in the order they were taken (an evolved one in its source's place): the HUD's line slots.
func held_lines() -> Array:
	var out: Array = []
	for pid in passives.keys():
		var d: PassiveDef = Registry.passive(str(pid))
		if d and d.is_line():
			out.append(pid)
	return out


## The passive items held (pass 47: everything held that is not a line), in the order they were taken.
func held_passives() -> Array:
	var out: Array = []
	for pid in passives.keys():
		var d: PassiveDef = Registry.passive(str(pid))
		if d == null or not d.is_line():
			out.append(pid)
	return out


## Skips and banishes back to the sheet's per-stage numbers (pass 47): the run's start and every new stage.
func refill_choices() -> void:
	skips_left = maxi(player_sheet.get_int("skips"), 0)
	banishes_left = maxi(player_sheet.get_int("banishes"), 0)


## Spends a skip (a level-up's, a path's or a chest's; pass 47). False when the stage has none left.
func use_skip() -> bool:
	if skips_left <= 0:
		return false
	skips_left -= 1
	return true


## Spends a banish (pass 47). False when the stage has none left.
func use_banish() -> bool:
	if banishes_left <= 0:
		return false
	banishes_left -= 1
	return true


## Why an offer card (a level-up's, a chest's roll) may not be banished, "" when it may go (pass 58, Garry: "Banish
## option should not allow Banishing items that Player already has, because this way they can lock themselves out of
## progression for those weapons"):
##   "gold"       a purse of gold, or a card with no item
##   "evolution"  an evolution of something held: a maxed line's evolution card, a chest's weapon evolution
##   "held"       something the hero has: every upgrade card (level_from above 0), a weapon, a line or a passive item held,
##                and a base weapon whose evolution he carries (the family is his)
##   "path"       a mutation on the path of a weapon the hero holds (a boss chest's pick): its evolution needs every one,
##                so it would be locked away for the run (a hero's own mutation is optional and may go)
## A new weapon, line, passive item or perk may go.
func banish_refusal(card: Dictionary) -> String:
	var type := str(card.get("type", ""))
	var id := str(card.get("id", ""))
	var def = card.get("def")
	if type == "gold" or id == "" or def == null:
		return "gold"
	if type == "evolution" or bool(card.get("evolve", false)):
		return "evolution"
	if (def is WeaponDef and (def as WeaponDef).is_evolution) or (def is PassiveDef and (def as PassiveDef).is_evolved()):
		return "evolution"
	if int(card.get("level_from", 0)) > 0 or has_weapon(id) or passives.has(id):
		return "held"
	# the Boomstick while the Blunderbuss is held (pass 58 review: a level-up had offered it again as NEW, banishable)
	if def is WeaponDef and family_instance(id) != null:
		return "held"
	if def is MutationDef and not (def as MutationDef).is_hero() and family_instance((def as MutationDef).weapon) != null:
		return "path"
	return ""


## Whether an offer card may be banished (banish_refusal says why not).
func can_banish_card(card: Dictionary) -> bool:
	return banish_refusal(card) == ""


## A level-up card banished (pass 58): refused (false, nothing spent, nothing struck) when banish_refusal refuses it or
## the stage has no banish left; else one of the stage's banishes spent and its id out of this run's offers, chests and
## the Stranger's.
func banish_card(card: Dictionary) -> bool:
	if not can_banish_card(card) or not use_banish():
		return false
	var id := str(card.get("id", ""))
	if not banished.has(id):
		banished.append(id)
	return true


func mutations_held(family: String) -> Array:
	var v = mutations.get(family, [])
	return v if v is Array else []


func mutation_defs(family: String) -> Array:
	var out: Array = []
	for mid in mutations_held(family):
		var m: MutationDef = Registry.mutation(mid)
		if m:
			out.append(m)
	return out


## The held weapon (base or evolved) on this family, or null.
func family_instance(family: String) -> WeaponInstance:
	for w in weapons:
		if w.family_id() == family:
			return w
	return null


## Whether a weapon may take a path pick now: at the opening level, and no pick on this stage yet.
func can_mutate(w: WeaponInstance) -> bool:
	if w == null or w.level < MUTATION_FROM_LEVEL:
		return false
	return int(mutation_stage.get(w.family_id(), -1)) != stage


## The mutation cards a weapon has open right now: its path and the hero's own option for it, both only while
## the stage's pick is unspent (pass 45: the hero option is that pick, not a free extra). Never a banished one (pass 58:
## a hero's own mutation struck from a boss chest; path_offer drops them too, so a weapon whose only option left is
## banished no longer takes a path slot and puts nothing on the table).
func open_mutations(w: WeaponInstance) -> Array:
	var out: Array = []
	if not can_mutate(w):
		return out
	var fam := w.family_id()
	for m: MutationDef in Registry.mutations_of(fam):
		if not w.has_mutation(m.id) and not banished.has(m.id):
			out.append(m)
	if character:
		for hm: MutationDef in Registry.hero_mutations(character.id):
			if hm.weapon == fam and not w.has_mutation(hm.id) and not banished.has(hm.id):
				out.append(hm)
	return out


## Every pick, the hero's own option included, spends the weapon's pick for the stage. `force` is the Stranger's and
## the boss chest's loophole: a pick past the stage's one (still never the same mutation twice). A hidden mutation
## (pass 48: kept in the content, out of play) only goes on by force (the debug hand).
func add_mutation(id: String, force: bool = false) -> bool:
	var def: MutationDef = Registry.mutation(id)
	if def == null:
		return false
	if def.hidden and not force:
		return false
	var inst := family_instance(def.weapon)
	if inst == null or inst.has_mutation(id):
		return false
	if not force and not can_mutate(inst):
		return false
	var held := mutations_held(def.weapon)
	held.append(id)
	mutations[def.weapon] = held
	_note("mutation", id, 1, {"weapon": def.weapon, "hero": def.is_hero()})
	mutation_stage[def.weapon] = stage
	mutation_misses[def.weapon] = 0
	inst.mutations = mutation_defs(def.weapon)
	_apply_passives_to_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()
	return true


## The level a passive is held at (0 = not held).
func passive_level(id: String) -> int:
	return int(passives.get(id, 0))


## The level a passive arrives at when it is new: 1, or for the hero's favourite passive (pass 46: Ironwood's Cake; pass
## 47: his Brawn at level 2) the level its bonus names ({"type": "max"} = its top level at once, {"type": "level",
## "value": n}).
func first_passive_level(def: PassiveDef) -> int:
	if def == null or character == null or character.favourite_passive != def.id:
		return 1
	var b: Dictionary = character.favourite_passive_bonus
	match str(b.get("type", "")):
		"max":
			return maxi(def.max_level, 1)
		"level":
			return clampi(int(b.get("value", 1)), 1, maxi(def.max_level, 1))
	return 1


## Whether `def` is the run's hero's favourite (a weapon or a passive): the cards say FAVOURITE on it.
func is_favourite(def: ContentDef) -> bool:
	if def == null or character == null:
		return false
	if def is WeaponDef:
		return character.favourite_weapon == def.id
	if def is PassiveDef:
		return character.favourite_passive == def.id
	return false


## A maxed passive becomes its evolution (pass 33.2 on the lines, every passive since pass 46): the source's levels go
## and the evolved passive takes its slot, in its place in the row, at its one level.
func evolve_passive(src_id: String) -> bool:
	var src: PassiveDef = Registry.passive(src_id)
	if src == null or not passives.has(src_id) or src.evolves_into == "":
		return false
	var evo: PassiveDef = Registry.passive(src.evolves_into)
	if evo == null:
		return false
	# rebuilt in order, so the evolution stands where its source stood (the HUD slot, the pause list)
	var held: Dictionary = passives.duplicate()
	passives.clear()
	for pid in held.keys():
		if pid == src_id:
			passives[evo.id] = 1
		elif pid != evo.id:
			passives[pid] = held[pid]
	player_sheet.remove_source("passive:" + src_id)
	_note("passive_evolution", evo.id, 1, {"from": src_id})
	Save.mark_seen("passive", evo.id)
	_apply_passives_to_sheet()
	haste = player_sheet.get_stat("haste", 1.0)
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()
	return true


func add_perk(id: String) -> bool:
	var def: PerkDef = Registry.perk(id)
	if def == null or perks.has(id):
		return false
	perks.append(id)
	_note("perk", id, 1)
	Save.mark_seen("perk", id)
	_apply_passives_to_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()
	return true


func has_perk(id: String) -> bool:
	return perks.has(id)


## A perk's tuning number by the mechanism it names, or the default when the hero has no such perk.
func perk_param(special: String, key: String, default: float) -> float:
	for pk in perks:
		var def: PerkDef = Registry.perk(pk)
		if def and def.special == special:
			return float(def.params.get(key, default))
	return default


## Bookkeeping after an offer was shown: the perk gap.
func note_offer(offer: Array) -> void:
	var shown_perk := false
	for c in offer:
		if c["type"] == "perk":
			shown_perk = true
	perk_gap = 0 if shown_perk else perk_gap + 1


## The path slots: a stage puts a weapon's whole path on the table at set seconds (the map's `path_times`). True once
## per slot, the first frame the stage clock passes it.
func path_due(t_in_stage: float) -> bool:
	if map == null or map.timeline == null:
		return false
	var times: Array = map.timeline.path_times_at(stage)
	if path_slot >= times.size():
		return false
	if t_in_stage < float(times[path_slot]):
		return false
	path_slot += 1
	return true


## The weapon whose path goes on the table at a slot (pass 54, Garry: "picked at random"): one of those with a pick
## still open this stage (path_offer_weapons), drawn at random (randi). Null when every path is spent. Game calls it
## once a slot; the pre-reel spins through path_offer_weapons and lands on it.
func next_path_weapon() -> WeaponInstance:
	var open := path_offer_instances()
	if open.is_empty():
		return null
	return open[randi() % open.size()]


## The weapons whose path may go on the table now (pass 54): those with a pick still open this stage and a mutation
## left to take, in the order they are held.
func path_offer_instances() -> Array:
	var out: Array = []
	for w: WeaponInstance in weapons:
		if can_mutate(w) and not open_mutations(w).is_empty():
			out.append(w)
	return out


## The same weapons as their defs (pass 54): the cells the mutation offer's pre-reel spins through (WWeaponReel).
func path_offer_weapons() -> Array:
	var out: Array = []
	for w: WeaponInstance in path_offer_instances():
		out.append(w.def)
	return out


## A buff for `seconds` of the run clock (a power-up, a structure, a perk); the same id again starts its clock over.
## `quiet` (pass 47, Barrel Rush): it runs out without a "wore off" toast (tick_timed does not return its label).
## Pass 54: the seconds run buff_seconds long on this hero (Solenne's Magic Hour, Long Day), every buff that comes
## through here: power-ups, structures, Pollen, Barrel Rush, Skedaddle.
func add_timed_effects(id: String, label: String, effects: Array, seconds: float, quiet: bool = false) -> void:
	seconds = buff_seconds(seconds)
	var source := "buff:" + id
	for tb in timed:
		if tb["id"] == id:
			tb["until"] = buff_clock() + seconds
			return
	timed.append({"id": id, "label": label, "effects": effects, "source": source, "until": buff_clock() + seconds, "quiet": quiet})
	player_sheet.add_effects(effects, source)
	haste = player_sheet.get_stat("haste", 1.0)
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()


## How long a buff of `seconds` lasts on this hero (pass 54): times the `buff_duration` player stat (1; Solenne's Magic
## Hour 1.25, her hidden Long Day twice that). The shield power-up's seconds go through it too (Game.apply_pickup).
func buff_seconds(seconds: float) -> float:
	return seconds * maxf(player_sheet.get_stat("buff_duration", 1.0), 0.0)


## The buffs' clock (pass 47): the stage clock plus the time it stood still (held_time), so timed effects, adrenaline
## and crescendo keep counting in a boss fight and a portal wait.
func buff_clock() -> float:
	return elapsed + held_time


## Called every frame by the game; returns the labels of buffs that just ran out.
func tick_timed() -> Array:
	var ended: Array = []
	var keep: Array = []
	var gone := false
	for tb in timed:
		if buff_clock() >= float(tb["until"]):
			player_sheet.remove_source(str(tb["source"]))
			if not bool(tb.get("quiet", false)):
				ended.append(str(tb["label"]))
			gone = true
		else:
			keep.append(tb)
	if gone:
		timed = keep
		haste = player_sheet.get_stat("haste", 1.0)
		for w in weapons:
			w.rebuild(player_sheet, weapons)
		build_changed.emit()
	# adrenaline: stacks fall off together when the streak ends; while it runs the sheet follows at most 4× a second
	var now := buff_clock()
	if adrenaline > 0 and now >= adrenaline_until:
		adrenaline = 0
		_adrenaline_dirty = true
	if _adrenaline_dirty and (adrenaline == 0 or now >= _adrenaline_built + 0.25):
		_adrenaline_dirty = false
		_adrenaline_built = now
		rebuild_sheets()
	elif _crescendo_dirty and now >= _crescendo_built + 0.3:
		_crescendo_dirty = false
		_crescendo_built = now
		rebuild_sheets()
	# Desperado: a new tenth of missing health, Steady Hand: a new bucket of standing still, Hot Streak: a new step of the
	# streak, on real time (a rebuild above has already folded them in)
	if (_desperado_dirty or _steady_dirty or _streak_dirty) and Time.get_ticks_msec() >= _desperado_built_ms + DESPERADO_REBUILD_MS:
		rebuild_sheets()
	return ended


## Seconds left of a timed buff by its id (pass 47: Barrel Rush's boost for the HUD), 0 when there is none.
func boost_left(id: String) -> float:
	for tb in timed:
		if tb["id"] == id:
			return maxf(float(tb["until"]) - buff_clock(), 0.0)
	return 0.0


## A barrel was smashed (pass 47, Barrel Rush: "Smacking Barrels Causes Player to get a speed boost, the Upgrades affect
## duration and speed"). With the passive held (`barrel_speed` above 0) the hero runs `barrel_speed` faster for
## `barrel_seconds`; another barrel starts the clock again, at the new speed when a level was taken since. True when it
## gave the boost.
func barrel_rush() -> bool:
	var sp := player_sheet.get_stat("barrel_speed", 0.0)
	var secs := player_sheet.get_stat("barrel_seconds", 0.0)
	if sp <= 0.0 or secs <= 0.0:
		return false
	_speed_boost(BARREL_RUSH, "Barrel Rush", sp, secs)
	return true


## A quiet timed move-speed boost by `id` (Barrel Rush; Skedaddle since pass 48): `sp` faster for `secs` of the buffs'
## clock; the same id again starts its clock over, at the new speed when it changed (a level taken since).
func _speed_boost(id: String, label: String, sp: float, secs: float) -> void:
	for tb in timed:
		if tb["id"] == id and not is_equal_approx(float((tb["effects"][0] as Effect).value), sp):
			# the old speed leaves the sheet; the boost goes on again below at the new one
			player_sheet.remove_source(str(tb["source"]))
			timed.erase(tb)
			break
	add_timed_effects(id, label, [Effect.make("move_speed", "mul", sp, "player")], secs, true)


## The debug arena's hand on the build (pass 33.4): the item `id` of `kind` (weapon, evolution, passive, perk, mutation)
## at level `n`, 0 taking it away, past the rules the cards keep but not past the slots: five weapons, five lines (as many
## as it likes in the arena), passive items without a cap (pass 47). Returns the level it ended at.
func debug_set_item(kind: String, id: String, n: int) -> int:
	match kind:
		"weapon", "evolution":
			var def: WeaponDef = Registry.weapon(id)
			if def == null:
				return 0
			n = clampi(n, 0, def.max_level)
			var w := weapon_instance(id)
			if n == 0:
				if w:
					weapons.erase(w)
			elif w == null:
				if weapons.size() >= MAX_WEAPONS:
					return 0
				w = WeaponInstance.new(def, n)
				w.mutations = mutation_defs(w.family_id())
				weapons.append(w)
			else:
				w.level = n
		"passive":
			var pd: PassiveDef = Registry.passive(id)
			if pd == null:
				return 0
			n = clampi(n, 0, pd.max_level)
			if n == 0:
				passives.erase(id)
			elif passives.has(id) or not pd.is_line() or held_lines().size() < maxi(line_cap(), MAX_LINES):
				passives[id] = n
			else:
				return 0
		"perk":
			if n <= 0:
				perks.erase(id)
			elif not perks.has(id) and Registry.perk(id) != null:
				perks.append(id)
			n = 1 if perks.has(id) else 0
		"mutation":
			var md: MutationDef = Registry.mutation(id)
			if md == null:
				return 0
			var held := mutations_held(md.weapon)
			if n <= 0:
				held.erase(id)
			elif not held.has(id):
				held.append(id)
			mutations[md.weapon] = held
			var inst := family_instance(md.weapon)
			if inst:
				inst.mutations = mutation_defs(md.weapon)
			n = 1 if held.has(id) else 0
	_note("debug_item", id, n, {"kind": kind})
	haste = 1.0
	rebuild_sheets()
	haste = player_sheet.get_stat("haste", 1.0)
	return n


## Every item gone (the arena's clean slate).
func debug_clear_items() -> void:
	weapons.clear()
	passives.clear()
	perks.clear()
	mutations.clear()
	rebuild_sheets()


func rebuild_sheets() -> void:
	_build_player_sheet()
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()


# ---------------------------------------------------------------- xp

## The XP a level needs: the curve, times the map's pace (WaveTimeline.xp_need_mult, pass 46; 1 without a map and in the
## arena, where levels come by the button).
func xp_to_next(l: int = -1) -> float:
	var L := level if l < 0 else l
	return (15.0 + 6.0 * L + 0.5 * L * L) * xp_need_mult()


## The map's pace for levels: its timeline's xp_need_mult, 1 without one or in the arena.
func xp_need_mult() -> float:
	if arena or map == null or map.timeline == null:
		return 1.0
	return maxf(map.timeline.xp_need_mult, 0.01)


func add_xp(n: float) -> void:
	n *= player_sheet.get_stat("xp_gain", 1.0)   # Field Notes
	xp += n
	xp_gained.emit(n)
	xp_changed.emit(xp, xp_to_next())
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_level_reached = max(max_level_reached, level)
		level_up.emit(level)
		xp_changed.emit(xp, xp_to_next())


func spend_gold(n: int) -> bool:
	if run_gold < n:
		return false
	run_gold -= n
	gold_changed.emit(run_gold)
	return true


func add_gold(n: int) -> void:
	var gained := int(round(n * player_sheet.get_stat("greed", 1.0)))
	run_gold += gained
	# all-time gold earned (pass 44: an unlock counts it), whatever becomes of the purse
	if gained > 0 and not arena:
		Save.add_total("gold_earned", gained)
	gold_changed.emit(run_gold)
	if gained > 0:
		gold_gained.emit(gained)


func add_kill(enemy_id: String, weapon_id: String) -> void:
	kills += 1
	if player_sheet.get_stat("adrenaline_speed", 0.0) > 0.0 or player_sheet.get_stat("adrenaline_might", 0.0) > 0.0:
		adrenaline = mini(adrenaline + 1, ADRENALINE_MAX)
		adrenaline_until = buff_clock() + ADRENALINE_SECONDS
		_adrenaline_dirty = true
	if has_perk("crescendo"):
		var cap: int = int(round(perk_param("crescendo", "max", 0.4) / maxf(perk_param("crescendo", "per_kill", 0.01), 0.001)))
		if crescendo < cap:
			crescendo += 1
			_crescendo_dirty = true
	# Hot Streak (pass 49): one more kill while it is held, kept for the rest of the run; the sheet follows when the bonus
	# reaches the next whole percent
	if player_sheet.get_stat("kill_might", 0.0) > 0.0:
		streak += 1
		var b := _streak_percent()
		if b != streak_bucket:
			streak_bucket = b
			_streak_dirty = true
	kills_by_enemy[enemy_id] = int(kills_by_enemy.get(enemy_id, 0)) + 1
	if weapon_id != "":
		kills_by_weapon[weapon_id] = int(kills_by_weapon.get(weapon_id, 0)) + 1
	kills_changed.emit(kills)


## The run recorder's ear (pass 45): an event while RunAnalytics is up (a real run); nothing in the arena or in tests.
func _note(kind: String, id: String, level: int, extra: Dictionary = {}) -> void:
	if RunAnalytics.I:
		RunAnalytics.I.event(kind, id, level, extra)


func add_damage(weapon_id: String, amount: float) -> void:
	damage_by_weapon[weapon_id] = float(damage_by_weapon.get(weapon_id, 0.0)) + amount
	if RunAnalytics.I: RunAnalytics.I.dealt(weapon_id, amount)
	# life steal: a slice of every point of damage comes back as health
	# lifesteal is a trickle, not a tap: at most LIFESTEAL_CAP of max HP a second, however much damage a build pours
	# out (a beam through forty creatures used to refill the bar in one sweep)
	var ls: float = player_sheet.get_stat("lifesteal", 0.0)
	if ls > 0.0:
		# the buffs' clock (pass 47): on the stage clock the cap's second never turned over in a boss fight
		var now: float = buff_clock()
		if now - _lifesteal_second >= 1.0:
			_lifesteal_second = now
			_lifesteal_healed_this_second = 0.0
		var cap: float = player_sheet.get_stat("max_hp", 100.0) * player_sheet.get_stat("lifesteal_cap", LIFESTEAL_CAP)
		var room: float = maxf(cap - _lifesteal_healed_this_second, 0.0)
		if room > 0.0:
			lifesteal_pool += minf(amount * ls, room)
			if lifesteal_pool >= 1.0:
				var heal := floorf(lifesteal_pool)
				lifesteal_pool -= heal
				_lifesteal_healed_this_second += heal
				lifesteal_healed.emit(heal)


# ---------------------------------------------------------------- build

## The element an item carries: its `element` field, else read off its stats (poison_* or fire_*), so a JSON that
## forgets the field is still known for what it is. (Until pass 36 a run held one element only; fire and poison items
## share a run now.)
static func element_of(def: ContentDef) -> String:
	if def == null:
		return ""
	if def.element != "":
		return def.element
	if def is MutationDef or def is PerkDef:
		return ""
	if def is WeaponDef:
		return WeaponInstance.new(def, 1).element()
	if def is PassiveDef:
		for lv in (def as PassiveDef).levels:
			if not lv is Array:
				continue
			for e in lv:
				var st: String = e.stat if e is Effect else str((e as Dictionary).get("stat", "")) if e is Dictionary else ""
				if st.begins_with("fire_"):
					return "fire"
				if st.begins_with("poison_"):
					return "poison"
	return ""


func add_material(kind: String, n: int) -> void:
	run_materials[kind] = int(run_materials.get(kind, 0)) + n


## The Stranger's item: one rare, epic or legendary thing the run can hold, taken far in one stroke. Never common or
## uncommon (pass 47: five tiers), never one its stage has not opened, never rerolled.
func stranger_offer() -> Dictionary:
	var cands: Array = []
	# the loophole: a mutation from a path already spent this stage, the only way past exclusivity, at a higher price
	for w in weapons:
		var fam: String = w.family_id()
		if int(mutation_stage.get(fam, -1)) != stage:
			continue
		for m: MutationDef in Registry.mutations_of(fam):
			if not w.has_mutation(m.id) and not banished.has(m.id):
				cands.append({"type": "mutation", "id": m.id, "def": m, "level_from": 0, "level_to": 1, "is_new": true, "hp_cost": 0.2})
	for w: WeaponDef in CardPool.offer_weapons():
		if w.is_evolution or STRANGER_SKIPS.has(w.rarity) or banished.has(w.id) or not CardPool.stage_open(w):
			continue
		# five weapon levels since pass 48: a new one at level 2, a held one a level up (they were 3 and +2 of eight)
		var inst := weapon_instance(w.id)
		# its evolution held (pass 58 review): the family is the hero's, never a second copy carrying the same path
		if inst == null and family_instance(w.id) != null:
			continue
		if inst == null and weapons.size() < weapon_cap():
			cands.append({"type": "weapon", "id": w.id, "def": w, "level_from": 0, "level_to": mini(2, w.max_level), "is_new": true})
		elif inst and inst.level < w.max_level:
			cands.append({"type": "weapon", "id": w.id, "def": w, "level_from": inst.level, "level_to": mini(inst.level + 1, w.max_level), "is_new": false})
	# base passives only (never an evolved one, nor one whose evolution is held), a new line only into a free line slot
	for p: PassiveDef in CardPool.offer_passives():
		if STRANGER_SKIPS.has(p.rarity) or banished.has(p.id) or (p.evolves_into != "" and passives.has(p.evolves_into)) \
				or not CardPool.stage_open(p):
			continue
		var lv := int(passives.get(p.id, 0))
		if lv == 0 and (not p.is_line() or held_lines().size() < line_cap()):
			var lt := maxi(mini(2, p.max_level), first_passive_level(p))
			cands.append({"type": "passive", "id": p.id, "def": p, "level_from": 0, "level_to": lt, "is_new": true})
		elif lv > 0 and lv < p.max_level:
			cands.append({"type": "passive", "id": p.id, "def": p, "level_from": lv, "level_to": mini(lv + 2, p.max_level), "is_new": false})
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


## The deal: the item to its offered level, and the cut off the hero's max HP.
func stranger_take(offer: Dictionary, hp_cost: float) -> String:
	if offer.is_empty():
		return ""
	var def: ContentDef = offer["def"]
	var to := int(offer.get("level_to", 1))
	if offer["type"] == "mutation":
		add_mutation(def.id, true)
		stranger_cost = minf(stranger_cost + hp_cost, 0.6)
		rebuild_sheets()
		return def.display_name
	if offer["type"] == "weapon":
		if weapon_instance(def.id) == null:
			add_weapon(def, 1)
		while weapon_instance(def.id) and weapon_instance(def.id).level < to:
			level_weapon(def.id)
	else:
		while int(passives.get(def.id, 0)) < to:
			if not add_or_level_passive(def.id):
				break
	stranger_cost = minf(stranger_cost + hp_cost, 0.6)
	rebuild_sheets()
	return "%s Lv %d" % [def.display_name, to]


## The rarities the Stranger never sells.
const STRANGER_SKIPS := ["common", "uncommon"]


func has_weapon(id: String) -> bool:
	for w in weapons:
		if w.def.id == id:
			return true
	return false


func weapon_instance(id: String) -> WeaponInstance:
	for w in weapons:
		if w.def.id == id:
			return w
	return null


## A weapon into the run at `level_override`, never past its max_level (pass 48: five levels, where a tool or an old
## launch file may still ask for eight).
func add_weapon(def: WeaponDef, level_override: int = 1) -> WeaponInstance:
	if weapons.size() >= weapon_cap() and not has_weapon(def.id):
		return null
	var inst := WeaponInstance.new(def, clampi(level_override, 1, maxi(def.max_level, 1)))
	inst.mutations = mutation_defs(inst.family_id())
	weapons.append(inst)
	_note("weapon", def.id, inst.level, {"new": true})
	Save.mark_seen("weapon", def.id)
	inst.rebuild(player_sheet, weapons)
	build_changed.emit()
	return inst


func level_weapon(id: String) -> void:
	var w := weapon_instance(id)
	if w and w.level < w.def.max_level:
		w.level += 1
		_note("weapon", id, w.level, {"new": false})
		w.rebuild(player_sheet, weapons)
		build_changed.emit()


## A passive taken (a card, the shop, the Stranger, a chest): a held one gains a level up to its top; a new line takes
## one of the five line slots while one is free (line_cap), a new passive item needs none (pass 47); a new one arrives at
## first_passive_level (the hero's favourite at its bonus level at once). An evolved passive asked for while its source
## is held is that evolution. False when nothing changed.
func add_or_level_passive(id: String) -> bool:
	var def: PassiveDef = Registry.passive(id)
	if def == null:
		return false
	if passives.has(id):
		if int(passives[id]) >= def.max_level:
			return false
		passives[id] = int(passives[id]) + 1
		_note("passive", id, int(passives[id]), {"new": false})
	else:
		if def.is_evolved() and passives.has(def.evolves_from):
			return evolve_passive(def.evolves_from)
		if def.is_line() and held_lines().size() >= line_cap():
			return false
		var first := first_passive_level(def)
		passives[id] = first
		var extra := {"new": true}
		if first > 1:
			extra["favourite"] = true
		_note("passive", id, first, extra)
		Save.mark_seen("passive", id)
	_apply_passives_to_sheet()
	haste = player_sheet.get_stat("haste", 1.0)
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()
	return true


## How far a weapon is down its path (pass 48): x = the path mutations it carries (Registry.mutations_of its family:
## never a hidden one, never a hero's own), y = how many its path has. The evolution needs all of them.
func path_progress(w: WeaponInstance) -> Vector2i:
	if w == null:
		return Vector2i.ZERO
	var path: Array = Registry.mutations_of(w.family_id())
	var held := mutations_held(w.family_id())
	var n := 0
	for m: MutationDef in path:
		if held.has(m.id):
			n += 1
	return Vector2i(n, path.size())


func evolution_ready(w: WeaponInstance) -> bool:
	if w.def.is_evolution or w.def.evolves_into == "":
		return false
	if w.level < w.def.max_level:
		return false
	# the path leads to the evolution: every mutation of it on the weapon (pass 48; two of the three since pass 26)
	var pp := path_progress(w)
	if pp.y <= 0 or pp.x < pp.y:
		return false
	# banished from a chest (pass 47): this run's weapon stays as it is
	if banished.has(w.def.evolves_into):
		return false
	return Registry.weapons.has(w.def.evolves_into)


func evolution_status(w: WeaponInstance) -> String:
	## One line for the pause screen: what is still missing.
	if w.def.is_evolution:
		return "Evolved form of " + str(Registry.weapon(w.def.evolved_from).display_name if Registry.weapon(w.def.evolved_from) else w.def.evolved_from) + "."
	if w.def.evolves_into == "":
		return "Does not evolve."
	var into: WeaponDef = Registry.weapon(w.def.evolves_into)
	var parts: Array = []
	var pp := path_progress(w)
	parts.append("%d/%d mutations %s" % [pp.x, pp.y, "✓" if pp.y > 0 and pp.x >= pp.y else "✗"])
	parts.append("%s Lv %d/%d %s" % [w.def.display_name, w.level, w.def.max_level, "✓" if w.level >= w.def.max_level else "✗"])
	parts.append("then open a chest")
	return "Evolves into %s · %s" % [into.display_name if into else w.def.evolves_into, " · ".join(parts)]


func evolve(w: WeaponInstance) -> WeaponInstance:
	var into: WeaponDef = Registry.weapon(w.def.evolves_into)
	if into == null:
		return null
	var idx := weapons.find(w)
	var inst := WeaponInstance.new(into, 1)
	inst.kills = w.kills
	inst.damage = w.damage
	inst.mutations = w.mutations   # the path stays on the evolved form
	if idx >= 0:
		weapons[idx] = inst
	else:
		weapons.append(inst)
	_note("evolution", into.id, 1, {"from": w.def.id})
	Save.mark_seen("weapon", into.id)
	inst.rebuild(player_sheet, weapons)
	evolutions += 1
	Save.add_total("evolutions", 1)
	weapon_evolved.emit(into.id)
	build_changed.emit()
	return inst


func any_evolution_ready() -> WeaponInstance:
	for w in weapons:
		if evolution_ready(w):
			return w
	return null


## The paths a boss chest can hold: every mutation still open on a weapon held (not held, not banished) and the hero's
## own option for that weapon (not banished either: pass 58 review, a hero's own mutation is the one a boss chest lets
## the player banish, and it came back on the respin, the reel and later chests). The Stranger's loophole: the stage's
## pick may be spent, the chest still fits one more. The reel (ChestScreen) shows exactly this list (pass 45).
func boss_chest_mutations() -> Array:
	var out: Array = []
	for wi in weapons:
		for m: MutationDef in Registry.mutations_of(wi.family_id()):
			if not wi.has_mutation(m.id) and not banished.has(m.id):
				out.append(m)
		if character:
			for hm: MutationDef in Registry.hero_mutations(character.id):
				if hm.weapon == wi.family_id() and not wi.has_mutation(hm.id) and not banished.has(hm.id):
					out.append(hm)
	return out


## What a chest holds, decided before the reel spins and applied only by chest_take (or left by chest_skip, swapped by
## chest_banish). A card like CardPool's: an evolution when one is ready, else one card of chest_candidates() drawn by
## the level-up's weights (pass 47: CardPool.weight_of, so luck and the level decay count here too), else a purse of
## gold. A boss's chest holds a path pick (boss_chest_mutations) while one is open.
func chest_roll(boss: bool = false) -> Dictionary:
	if boss:
		# the boss's chest holds a path pick: any mutation still open on any weapon held, the Stranger's loophole
		var muts := boss_chest_mutations()
		if not muts.is_empty():
			var m: MutationDef = muts[randi() % muts.size()]
			return {"type": "mutation", "id": m.id, "def": m, "level_from": 0, "level_to": 1, "is_new": true, "boss": true}
	var w := any_evolution_ready()
	if w:
		var into: WeaponDef = Registry.weapon(w.def.evolves_into)
		return {"type": "evolution", "id": into.id, "def": into, "src_id": w.def.id, "level_from": 0, "level_to": 1, "is_new": true}
	var r := CardPool.pick_one(chest_candidates())
	if r.is_empty():
		return {"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false}
	return r


## What an ordinary chest may hold besides an evolution (pass 47): a level of every weapon, line and passive item held
## that can still grow, and every passive item not held yet that the run may find (unlocked, its stage open; never a new
## line, which takes a slot and is a level-up's choice), each weighed as a level-up weighs it; never a banished one.
## A new passive item's weight in a chest, against the upgrades of what the hero holds (the lead's pass 47 call: at
## full weight new items took about three fifths of an early chest, where a chest has always mostly levelled the build;
## at 0.45 they take about two fifths).
const CHEST_NEW_MULT := 0.45


func chest_candidates() -> Array:
	var out: Array = []
	for wi in weapons:
		if wi.def.is_evolution or wi.level >= wi.def.max_level or banished.has(wi.def.id):
			continue
		out.append({"type": "weapon", "id": wi.def.id, "def": wi.def, "level_from": wi.level, "level_to": wi.level + 1,
			"is_new": false, "weight": CardPool.weight_of(wi.def, wi.level)})
	for pid in passives.keys():
		var def: PassiveDef = Registry.passive(str(pid))
		var lv := int(passives[pid])
		if def == null or lv >= def.max_level or banished.has(str(pid)):
			continue
		out.append({"type": "passive", "id": str(pid), "def": def, "level_from": lv, "level_to": lv + 1, "is_new": false,
			"weight": CardPool.weight_of(def, lv)})
	for p: PassiveDef in Registry.unlocked_passives():
		if p.is_line() or passives.has(p.id) or banished.has(p.id) or not CardPool.stage_open(p):
			continue
		if p.evolves_into != "" and passives.has(p.evolves_into):
			continue
		var c := {"type": "passive", "id": p.id, "def": p, "level_from": 0, "level_to": first_passive_level(p),
			"is_new": true, "weight": CardPool.weight_of(p, 0) * CHEST_NEW_MULT}
		if is_favourite(p):
			c["favourite"] = true
		out.append(c)
	return out


## The player took what the chest held. Returns the line for the toast.
func chest_take(r: Dictionary) -> String:
	chests_opened += 1
	_note("chest", str(r.get("id", "")), int(r.get("level_to", 0)), {"roll": str(r.get("type", "")), "take": true, "boss": bool(r.get("boss", false))})
	Save.add_total("chests", 1)
	match str(r.get("type", "")):
		"mutation":
			var md: MutationDef = r.get("def")
			if md and add_mutation(md.id, true):
				return md.display_name
			add_gold(60)
			return "+60 gold"
		"evolution":
			var src := weapon_instance(str(r.get("src_id", "")))
			if src:
				var inst := evolve(src)
				return inst.def.display_name if inst else ""
			return ""
		"weapon":
			# the build can have changed under the reel (an evolution replaced the weapon): then gold instead
			if weapon_instance(r["id"]) == null:
				add_gold(int(r.get("gold", 50)))
				return "+%d gold" % int(r.get("gold", 50))
			level_weapon(r["id"])
			return Registry.weapon(r["id"]).display_name + " Lv " + str(weapon_instance(r["id"]).level)
		"passive":
			# the same: a passive that evolved under the reel is no longer there to level (a new passive item, pass 47,
			# is taken; one that cannot be is gold)
			var pid := str(r["id"])
			if (not bool(r.get("is_new", false)) and not passives.has(pid)) or not add_or_level_passive(pid):
				add_gold(int(r.get("gold", 50)))
				return "+%d gold" % int(r.get("gold", 50))
			return Registry.passive(pid).display_name + " Lv " + str(passives[pid])
		_:
			add_gold(int(r.get("gold", 50)))
			return "+%d gold" % int(r.get("gold", 50))


## The chest left shut (pass 47, Garry: the stage's skips "work for both Level Ups and Chests"): a skip spent, nothing
## gained, the chest counted as opened. "" (and nothing spent or counted) when the stage has no skip left.
func chest_skip(r: Dictionary) -> String:
	if not use_skip():
		return ""
	chests_opened += 1
	_note("chest", str(r.get("id", "")), 0, {"roll": str(r.get("type", "")), "take": false, "skip": true, "left": skips_left, "boss": bool(r.get("boss", false))})
	Save.add_total("chests", 1)
	return "Chest skipped"


## What the chest held, banished (pass 47): a banish spent, its id out of this run (no card, no chest, no Stranger offers
## it again), and a new roll for the reel to spin to. {} (nothing spent) when the stage has no banish left, the roll is
## gold, or (pass 58) banish_refusal refuses it: never an upgrade of what the hero has, an evolution or a path mutation
## of a weapon held.
func chest_banish(r: Dictionary) -> Dictionary:
	var id := str(r.get("id", ""))
	if id == "" or str(r.get("type", "")) == "gold" or banishes_left <= 0:
		return {}
	if not can_banish_card(r):
		return {}
	use_banish()
	if not banished.has(id):
		banished.append(id)
	_note("banish", id, 0, {"where": "chest", "roll": str(r.get("type", ""))})
	return chest_roll(bool(r.get("boss", false)))


## Apply a chest at once (tools and tests): the roll, taken.
func open_chest() -> Dictionary:
	var r := chest_roll()
	r["name"] = chest_take(r)
	return r


func stage_mult() -> float:
	if map == null or map.timeline == null:
		return 1.0
	return map.timeline.stage_mult(stage, endless_seconds())


## Seconds into endless (0 before it).
func endless_seconds() -> float:
	if not endless or map == null or map.timeline == null:
		return 0.0
	return maxf(elapsed - map.timeline.stage_length * map.timeline.stages, 0.0)


## The endless wave the run is in, 1-based (0 outside endless).
func endless_wave() -> int:
	if not endless or map == null or map.timeline == null:
		return 0
	return map.timeline.endless_wave(endless_seconds()) + 1


func summary() -> Dictionary:
	return {
		"time": elapsed, "stage": stage + 1, "level": level, "kills": kills, "gold": run_gold,
		"extracted": extracted, "died": died, "damage_by_weapon": damage_by_weapon.duplicate(),
		"kills_by_weapon": kills_by_weapon.duplicate(), "evolutions": evolutions, "chests": chests_opened,
		"character": character.display_name if character else "", "map": map.display_name if map else "",
	}
