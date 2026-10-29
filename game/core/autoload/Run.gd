## The state of the current run, kept in an autoload so every screen (HUD, pause, results) reads one object.
## The Game scene drives it; this holds data and build logic, not nodes.
extends Node

signal level_up(level: int)
signal xp_changed(xp: float, needed: float)
signal xp_gained(amount: float)
signal build_changed
## the hero's own sheet was rebuilt without the weapons (pass 61: a level's signature stat); Game refreshes the hero's
## health and speed from it at once
signal hero_sheet_changed
signal gold_changed(run_gold: int)
signal kills_changed(kills: int)
signal stage_changed(stage: int)
signal weapon_evolved(weapon_id: String)
## Gold the run just gained, after greed (pass 47: the HUD's coin pop); only for an amount above 0.
signal gold_gained(amount: int)
## pass 79 (lane MUT): a mutation offer fell due or was taken by a level-up (the HUD's mark reads mutlvl_pending)
signal mutation_due_changed

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
## Pass 87 (lane SGAME, stages as their own runs): the stage index (0-based) this run plays, read-only (= stage); the
## stage the next run will play (choose_stage: the Stages menu, the Watch; Game starts it and puts it back to 0); the
## seconds spent in Endless after the stage's portal countdown; whether this run killed its stage's boss.
var stage_index: int:
	get:
		return stage
var stage_next := 0
var endless_time := 0.0
var stage_beaten := false
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
## Pass 113 (lane TASKS, core/systems/TaskTally.gd): the run's tallies for the task types: fire and poison damage the hero's
## side dealt {"fire", "poison"} (EnemyManager.damage's hot and green hits), HP restored by item (an item family's base
## id, split by each item's share of the healing stat) and by source ("pickup:heart", "structure:healing_well"), barrels
## broken, Totem gifts taken; banked into the save once at the run's end (tasks_banked).
var element_damage: Dictionary = {}
var healed_by_item: Dictionary = {}
var healed_by_source: Dictionary = {}
var barrels_broken := 0
var totems_taken := 0
var tasks_banked := false
var chests_opened := 0
var evolutions := 0
var bosses_killed := 0
## The run's story for the Results screen (pass 72, lane RESULTS): the purse, the kills and their kinds, the downs and
## the damage sources second by second (RunTimeline); a new one each start, attached and ticked by Game in a real run.
var timeline: RunTimeline = RunTimeline.new()

var player_sheet: StatSheet = StatSheet.new()
## The hero's numbers as the run began (pass 76, lane UI: the pause Stats tab marks every stat that moved since): stat ->
## value for every stat on the sheet start() built (level 1, the Upgrade board, nothing taken yet), and the hero they were
## taken for (start_stat reads a fresh level-1 sheet when the arena swapped heroes since).
var start_stats: Dictionary = {}
var start_stats_hero := ""
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
## Fadeaway's Heat (pass 67, the basketball's `catch` params): +1 for every caught ball that scored, up to catch.heat_max;
## the ball's damage x (1 + heat x catch.heat_per); 0 again on a hit that reaches his health unless catch.heat_keep.
## Declared and reset here; ProjectileEmitter raises and zeroes it and shows it on the ball (pass 69, `heat_look`: no
## HUD gauge any more), WeaponInstance._shot_dps reads it.
var heat: int = 0
## Buck's Overdrive (pass 67, a perk): the gears counted while his charge is full (Player._tick_momentum: one every
## `every` seconds at full, max / step at most), each `step` more attack damage (overdrive_might); a hit that lands drops
## them all (Player.take_damage).
var overdrive: int = 0
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
## pass 73 (lane STRUCT): the Totem Poles' gifts taken this run (TotemBoons.roll dictionaries), each on the sheet for
## the rest of the run (_apply_totem_boons)
var totem_boons: Array = []
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
## Pass 109: the first-run Dynamite offer (FtueDynamite) has had its card screen this run (once a run at most).
var ftue_dynamite_shown := false
## pass 79 (lane MUT): the mutation offers that fell due on the stage's path_times and wait for a level-up (each makes
## the hero's next level-up a mutation level-up; mutlvl_*), the mutation level-ups whose screen has not opened yet, and
## the level-ups that were mutation offers
var mutlvl_due := 0
var mutlvl_ready := 0
var mutation_levels := 0


## The map's layout roll for this run (Red Canyon reads it): random each run, or `forced_map_seed` when a tool wants
## the same desert every time (the capture tool).
var map_seed := 0
var forced_map_seed := 0
## Pass 77 (lane SIMRUN): a launch set in memory (the run sim's players run side by side and would race on
## user://debug_launch.json): Game._read_debug_launch takes it before the file, empties it and leaves the file alone.
## The file's keys, plus `analytics_memory` (the run recorder keeps its rows in memory and writes no file).
var launch_override: Dictionary = {}
## Pass 77 (lane SIMRUN): the run's dice seed, 0 = random (every run but the run sim's); set by seed_dice.
var rng_seed := 0
## Pass 77 (lane SIMRUN): the Totem Poles' gifts' own dice in a run sim (seed_dice); null in play (TotemBoons.offer rolls
## its own random ones).
var totem_rng: RandomNumberGenerator = null
## Pass 77 (lane SIMRUN): the run sim's fast mode (the launch's `sim_fast`, set by Game._ready for every run): the work
## that only draws or plays is skipped and nothing that moves a number is: the crowd's, the shots' and the pickups'
## drawing (their _process), the ground marks' drawing (Telegraphs keeps ageing them), Fx, sounds, the HUD's and the
## damage numbers' frames; and the sheet's rebuild throttle reads the buffs' clock (_rebuild_clock_ms).
var sim_mode := false
## Pass 77 (lane SIMRUN): a run sim's run, in either of its modes (the launch's `sim_clock`, set by Game._ready for every
## run): the rules that count real time count the run's own clock instead (rule_seconds), as a phone's real time is its
## game time while a headless run goes 2.5 to 4.5 times faster than real time.
var sim_clock := false
## Pass 102 (lane STEADY): the game's own clock in play, seconds: every unpaused frame's delta, which Godot shortens when
## the world falls behind (Game.CATCH_UP_STEPS = 2 while the game plays: a frame runs at most two 60 Hz world steps and
## the frame's delta loses the steps it dropped), so the rules that read rule_seconds() slow down with the world instead
## of running on the wall clock while the crowd crawls. It stops while the tree is paused, like the world.
var play_clock := 0.0
## Poisoned creatures alive right now (pass 48: EnemyManager counts them once a tick; Gas Mask reads it).
var poisoned_alive := 0
## Phoenix Feather (pass 48): its one free revive this run is spent (phoenix_ready / use_phoenix).
var phoenix_used := false
## Counterpunch (pass 69, a passive item): an evade arms the next attack (counter_armed); the first weapon to fire after
## it (counterpunch_fired) deals 1 + `counter_damage` times its damage with every hit until it fires again or
## COUNTER_HIT_WINDOW seconds of the buffs' clock pass (counterpunch_mult).
const COUNTERPUNCH := "counterpunch"
const COUNTER_HIT_WINDOW := 1.0
var counter_armed := false
var counter_weapon := ""
var counter_until := -1.0
## Heavyweight (pass 69): its attack damage on the sheet as its own source (_apply_heavyweight).
var _heavy_source := ""
## Last Stand (pass 69, a passive item): a hit that leaves the hero under LAST_STAND_BELOW of his max HP slows the game to
## LAST_STAND_SCALE for LAST_STAND_SECONDS of real time (ui/LastStandFx.gd keeps the clock) and multiplies his attack
## damage by 1 + `last_stand`; then not again for LAST_STAND_COOLDOWN seconds of the buffs' clock, which nothing shows.
const LAST_STAND_BELOW := 0.3
const LAST_STAND_SCALE := 0.5
const LAST_STAND_SECONDS := 2.0
const LAST_STAND_COOLDOWN := 20.0
var last_stand_active := false
var last_stand_next := 0.0


func start(p_character: CharacterDef, p_map: MapDef) -> void:
	active = true
	character = p_character
	map = p_map
	map_seed = forced_map_seed if forced_map_seed != 0 else (randi() % 999983) + 1
	timeline = RunTimeline.new()
	elapsed = 0.0
	held_time = 0.0
	stage = 0
	arena = false
	endless = false
	# pass 87 (lane SGAME): a run starts outside Endless, its boss not killed (start_stage moves it to its stage)
	endless_time = 0.0
	stage_beaten = false
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
	phoenix_spent = 0
	# pass 69: Counterpunch's armed attack, Last Stand's window and its hidden cooldown start clear
	counter_armed = false
	counter_weapon = ""
	counter_until = -1.0
	last_stand_active = false
	last_stand_next = 0.0
	poisoned_alive = 0
	thumb_lifted = false
	no_lift_time = 0.0
	max_level_reached = 1
	kills_by_enemy.clear()
	kills_by_weapon.clear()
	damage_by_weapon.clear()
	# pass 113 (lane TASKS): the task tallies start empty, not banked
	element_damage.clear()
	healed_by_item.clear()
	healed_by_source.clear()
	barrels_broken = 0
	totems_taken = 0
	tasks_banked = false
	# pass 72 (lane BOSS): the DPS window starts empty
	dps_reset()
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
	ftue_dynamite_shown = false
	path_slot = 0
	mutlvl_due = 0
	mutlvl_ready = 0
	mutation_levels = 0
	banished.clear()
	run_materials = {"bones": 0, "relics": 0}
	stranger_cost = 0.0
	totem_boons = []
	adrenaline = 0
	adrenaline_until = 0.0
	crescendo = 0
	_crescendo_dirty = false
	desperado_bucket = 0
	_desperado_dirty = false
	_desperado_source = ""
	# pass 77 (lane SIMRUN): the throttle's last rebuild "long ago" (the run sim's clock starts at 0 every run)
	_desperado_built_ms = -100000
	still_seconds = 0.0
	steady_bucket = 0
	_steady_dirty = false
	_steady_source = ""
	streak = 0
	streak_bucket = 0
	_streak_dirty = false
	_streak_source = ""
	# pass 70 (lane LINES): Gold Rush counts from nothing
	_gold_rush_reset()
	timed.clear()
	lifesteal_pool = 0.0
	_lifesteal_second = 0.0
	_lifesteal_healed_this_second = 0.0
	momentum = 0.0
	momentum_def = p_character.momentum if p_character else {}
	heat = 0
	overdrive = 0
	_build_player_sheet()
	# pass 76 (lane UI): the stats as the run began, and no unlock of an earlier run (or of the title's quiet check) is
	# this run's
	_take_start_stats()
	QuestTracker.just_completed.clear()
	rerolls_left = player_sheet.get_int("rerolls")
	refill_choices()
	Save.note_run_started()
	build_changed.emit()


func end() -> void:
	active = false


## Pass 77 (lane SIMRUN): the run sim's dice (tools/sim_run.gd calls it before the Game scene loads): `s` seeds the
## global randf()/randi() stream, the level-up offers' and the chests' draws (CardPool.rng, a stream of their own, so
## the build a seed grows stays close when the fight drifts) and the director's (WaveDirector.start reads rng_seed), so
## one simulated player is repeatable on the same content as far as the game allows; 0 puts them back to random.
func seed_dice(s: int) -> void:
	rng_seed = s
	if s == 0:
		CardPool.rng = null
		totem_rng = null
		randomize()
		return
	seed(hash([s, "global"]))
	var r := RandomNumberGenerator.new()
	r.seed = hash([s, "cards"])
	CardPool.rng = r
	totem_rng = RandomNumberGenerator.new()
	totem_rng.seed = hash([s, "totems"])


## Every hero's 1% crit chance (pass 52, StatSheet.PLAYER_DEFAULTS) is left out under the test runner, so a suite that
## counts a weapon's exact damage never meets a random double; pass52_test turns it back on to check it.
var base_crit := not Array(OS.get_cmdline_args()).any(func(a) -> bool: return str(a).ends_with("GdUnitCmdTool.gd"))


func _build_player_sheet() -> void:
	# pass 79 (lane MUT): the trait grows with the card levels (card_level, M5)
	player_sheet = hero_sheet(character, card_level())
	for tb in timed:
		player_sheet.add_effects(tb["effects"], tb["source"])
	if momentum > 0.0 and not momentum_def.is_empty():
		var e1 := Effect.new()
		e1.stat = "move_speed"; e1.op = "mul"; e1.value = float(momentum_def.get("speed_bonus", 0.6)) * momentum; e1.target = "player"
		var e2 := Effect.new()
		e2.stat = "might"; e2.op = "mul"; e2.value = float(momentum_def.get("might_bonus", 0.5)) * momentum; e2.target = "player"
		var mfx: Array = [e1, e2]
		# the charge's third stat (pass 67): evade chance, so the charge guards itself (an evaded hit never touches it)
		var eb := float(momentum_def.get("evade_bonus", 0.0))
		if eb > 0.0:
			var e3 := Effect.new()
			e3.stat = "evade"; e3.op = "add"; e3.value = eb * momentum; e3.target = "player"
			mfx.append(e3)
		player_sheet.add_effects(mfx, "Momentum %d%%" % int(round(momentum * 100.0)), "momentum:" + (character.id if character else ""))
	if stranger_cost > 0.0:
		var sc := Effect.new()
		sc.stat = "max_hp"; sc.op = "mul"; sc.value = -stranger_cost; sc.target = "player"
		player_sheet.add_effects([sc], "The Stranger's cut", "stranger")
	# pass 73 (lane STRUCT): the Totem Poles' gifts, before the passives (Heavyweight reads the max HP they give)
	_apply_totem_boons()
	_apply_passives_to_sheet()
	# pass 95 (lane BREATH): a held weapon's level effects aimed at the hero (the Fire Eater's thorns)
	_apply_weapon_player_effects()
	# adrenaline reads the per-stack values the passives just put on the sheet, so it goes on last
	if adrenaline > 0:
		var sp: float = player_sheet.get_stat("adrenaline_speed", 0.0) * adrenaline
		var mg: float = player_sheet.get_stat("adrenaline_might", 0.0) * adrenaline
		if sp > 0.0 or mg > 0.0:
			var a1 := Effect.new()
			a1.stat = "move_speed"; a1.op = "mul"; a1.value = sp; a1.target = "player"
			var a2 := Effect.new()
			a2.stat = "might"; a2.op = "mul"; a2.value = mg; a2.target = "player"
			player_sheet.add_effects([a1, a2], "Adrenaline ×%d" % adrenaline, _ramp_sid("adrenaline_speed", "adrenaline_might"))
	if crescendo > 0 and has_perk("crescendo"):
		var c1 := Effect.new()
		c1.stat = "might"; c1.op = "mul"; c1.value = crescendo_might(); c1.target = "player"
		player_sheet.add_effects([c1], "Crescendo +%d%%" % int(round(crescendo_might() * 100.0)), _perk_sid("crescendo"))
	# Overdrive (pass 67, Buck's perk): the gears his full charge has counted, each the perk's `step` of attack damage
	var od := overdrive_might()
	if od > 0.0:
		var o1 := Effect.new()
		o1.stat = "might"; o1.op = "mul"; o1.value = od; o1.target = "player"
		player_sheet.add_effects([o1], "Overdrive +%d%%" % int(round(od * 100.0)), _perk_sid("overdrive"))
	# Last Stand (pass 69): while its slowed time runs, its attack damage stays on through any rebuild
	_apply_last_stand()
	haste = player_sheet.get_stat("haste", 1.0)


## A hero's own sheet at a level (pass 61): the defaults, his flat trait (the hidden heroes'), his signature stat at that
## level and the Mirror's ranks; what every run starts from, and what the title's hero sheet (the CV) shows. Nothing in
## the run's state is read or changed.
func hero_sheet(c: CharacterDef, at_level: int = 1) -> StatSheet:
	var sheet := StatSheet.new()
	sheet.scope = "player"
	sheet.set_bases(StatSheet.PLAYER_DEFAULTS)
	if not base_crit:
		sheet.set_bases({"crit_chance": 0.0})
	if c:
		sheet.add_effects(c.trait_effects, c.display_name, "hero:" + c.id)
		# the signature stat (pass 61): one effect per stat worth the level's whole bonus, named with the level; under
		# the test runner the Drifter's crit chance stays out with the base 1% (base_crit), for the same reason
		var lv := c.level_effects(at_level)
		if not base_crit:
			lv = lv.filter(func(e: Effect) -> bool: return e.stat != "crit_chance")
		if not lv.is_empty():
			sheet.add_effects(lv, trait_source(c, at_level), "trait:" + c.id)
	# the Mirror: each talent's ranks by the form chosen for each (pass 63: a rank keeps its form; Padding x2 and Plate x1
	# are two Padding ranks and one Plate rank, each form's ranks counted on their own)
	for tdef: TalentDef in Registry.talents.values():
		for form in range(2):
			var n := Save.talent_count(tdef.id, form)
			if n > 0:
				sheet.add_effects(tdef.effects_for(form, n), "%s: %s %d" % [tdef.display_name, tdef.form_name(form), n], "talent:%s:%d" % [tdef.id, form])
	return sheet


## The name the signature stat goes by on the sheet (the pause screen's breakdown): "Last Dance (Lv 12)".
static func trait_source(c: CharacterDef, at_level: int) -> String:
	var n := c.trait_name if c.trait_name != "" else c.display_name
	return "%s (Lv %d)" % [n, at_level]


# ---------------------------------------------------------------- pass 76 (lane UI): the stats as the run began

## The start's snapshot (start() calls it once the sheet is built): every stat the sheet knows (its bases and every stat
## an effect names), as it stands.
func _take_start_stats() -> void:
	start_stats = {}
	for s in player_sheet.stats():
		var st := str(s)
		start_stats[st] = player_sheet.get_stat(st, float(StatSheet.PLAYER_DEFAULTS.get(st, 0.0)))
	start_stats_hero = character.id if character else ""


## A stat as the run began (the pause Stats tab's mark compares the sheet with it): the snapshot's, or a fresh level-1
## sheet's when there is none or the arena swapped the hero since (hero_sheet: the defaults, his trait, the Upgrade
## board); `default` for a stat neither knows.
func start_stat(stat: String, default: float = 0.0) -> float:
	var hero_id := character.id if character else ""
	if not start_stats.is_empty() and hero_id == start_stats_hero:
		return float(start_stats.get(stat, default))
	return hero_sheet(character, 1).get_stat(stat, default)


## The source id a running bonus goes by on the sheet (Hot Streak's, Desperado's, Adrenaline's...): the id of the item
## that put its stat there (the first entry naming `stat`, else `alt`: "passive:hot_streak"), so the Stats tab shows it
## with that item's name and icon; "" (the bonus's own words) when nothing names it.
func _ramp_sid(stat: String, alt: String = "") -> String:
	for en in player_sheet.entries:
		var s := str((en["effect"] as Effect).stat)
		if s == stat or (alt != "" and s == alt):
			return str(en.get("sid", en["source"]))
	return ""


## The source id of the perk whose `special` a running bonus is (Crescendo, Overdrive): "perk:<id>"; "" with none.
func _perk_sid(special: String) -> String:
	for pk in perks:
		var def: PerkDef = Registry.perk(str(pk))
		if def and def.special == special:
			return "perk:" + str(pk)
	return ""


## Whether the hero's numbers move with his level (pass 61: every hero in play), so a level-up rebuilds the sheets.
func levels_trait() -> bool:
	return character != null and not character.level_trait.is_empty()


## What Crescendo adds to might right now (its stacks × the perk's per_kill, capped by its max).
func crescendo_might() -> float:
	return minf(float(crescendo) * perk_param("crescendo", "per_kill", 0.01), perk_param("crescendo", "max", 0.4))


## A hit drops Crescendo to nothing.
func reset_crescendo() -> void:
	if crescendo > 0:
		crescendo = 0
		rebuild_sheets()


## What Overdrive adds to attack damage right now (pass 67): its gears x the perk's `step`; 0 without the perk.
func overdrive_might() -> float:
	if overdrive <= 0 or not has_perk("overdrive"):
		return 0.0
	return float(overdrive) * perk_param("overdrive", "step", 0.05)


## The most gears Overdrive counts: the perk's `max` over its `step` (5 for +25% in 5% gears).
func overdrive_gears() -> int:
	return int(round(perk_param("overdrive", "max", 0.25) / maxf(perk_param("overdrive", "step", 0.05), 0.001)))


## The `catch` block of the first held weapon whose folded params carry one (the basketball's), or {}.
func catch_params() -> Dictionary:
	for w in weapons:
		var inst: WeaponInstance = w
		var c = inst.params.get("catch") if inst != null else null
		if c is Dictionary:
			return c
	return {}


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
	player_sheet.add_effects([Effect.make("might", "mul", v, "player")], _streak_source, _ramp_sid("kill_might"))


# ---------------------------------------------------------------- pass 70 (lane LINES): Gold Rush
## Gold Rush (pass 70, Gold Tooth's evolution): with the hero's `gold_might` above 0, every GOLD_RUSH_PER gold he gains
## while he holds it (add_gold after greed: coins, purses, chests, everything that pays the purse; its gold_gained signal)
## adds `gold_might` attack damage for the rest of the run, GOLD_RUSH_CAP at most, in whole percents, folded into attack
## damage as its own source ("Gold Rush +12%": the pause screen's breakdown names it). The sheet follows when the percent
## changes. Spending gold takes nothing back.
const GOLD_RUSH_PER := 100.0
const GOLD_RUSH_CAP := 0.5
## Gold gained while Gold Rush was held this run, and the percent the sheet carries.
var gold_rush_gold := 0
var gold_rush_bucket := 0
var _gold_rush_source := ""


## What Gold Rush adds to attack damage right now (the step on the sheet); 0 without it.
func gold_rush_bonus() -> float:
	return float(_gold_rush_percent()) / 100.0


func _gold_rush_percent() -> int:
	var gm: float = player_sheet.get_stat("gold_might", 0.0) if player_sheet else 0.0
	if gm <= 0.0 or gold_rush_gold <= 0:
		return 0
	return floori(minf(floorf(float(gold_rush_gold) / GOLD_RUSH_PER) * gm, GOLD_RUSH_CAP) * 100.0 + 0.0001)


## Gold gained (the gold_gained signal): counted while Gold Rush is held; the sheets are rebuilt when the percent moves.
func _gold_rush_gain(gained: int) -> void:
	if player_sheet == null or player_sheet.get_stat("gold_might", 0.0) <= 0.0:
		return
	gold_rush_gold += maxi(gained, 0)
	var b := _gold_rush_percent()
	if b != gold_rush_bucket:
		gold_rush_bucket = b
		rebuild_sheets()


## Gold Rush on the sheet as its own source, redone from the gold counted (_apply_passives_to_sheet calls it).
func _apply_gold_rush() -> void:
	if _gold_rush_source != "":
		player_sheet.remove_source(_gold_rush_source)
		_gold_rush_source = ""
	gold_rush_bucket = _gold_rush_percent()
	var v := gold_rush_bonus()
	if v <= 0.0:
		return
	# pass 73 (lane CARDS): named by the card's own name (Gold Tooth's evolution is a fortune card now)
	_gold_rush_source = "%s +%d%%" % [PassiveDef.display_name_of("gold_rush", "Gold Rush"), int(round(v * 100.0))]
	player_sheet.add_effects([Effect.make("might", "mul", v, "player")], _gold_rush_source, _ramp_sid("gold_might"))


## A run starts with none counted (start() calls it), and the purse's gold_gained is heard from then on.
func _gold_rush_reset() -> void:
	gold_rush_gold = 0
	gold_rush_bucket = 0
	_gold_rush_source = ""
	if not gold_gained.is_connected(_gold_rush_gain):
		gold_gained.connect(_gold_rush_gain)


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


# ---------------------------------------------------------------- pass 69, the new passive items

## Counterpunch (pass 69, Garry: "After evading, deal 2x Damage next attack, and temporarily increase Attack Speed and
## Movement Speed"): an evade arms the next attack (when the hero holds `counter_damage`) and starts a quiet timed boost
## of `counter_haste` weapon speed and `counter_speed` move speed for `counter_seconds` (another evade starts its clock
## again, at the new numbers when a level was taken since). True when it did anything. Player.take_damage calls it.
func counterpunch_evaded() -> bool:
	var dmg := player_sheet.get_stat("counter_damage", 0.0)
	var secs := player_sheet.get_stat("counter_seconds", 0.0)
	var did := false
	if dmg > 0.0:
		counter_armed = true
		did = true
	var hs := player_sheet.get_stat("counter_haste", 0.0)
	var sp := player_sheet.get_stat("counter_speed", 0.0)
	if secs > 0.0 and (hs > 0.0 or sp > 0.0):
		var effs: Array = []
		if hs > 0.0:
			effs.append(Effect.make("haste", "mul", hs, "player"))
		if sp > 0.0:
			effs.append(Effect.make("move_speed", "mul", sp, "player"))
		for tb in timed:
			if tb["id"] == COUNTERPUNCH and not _same_effects(tb["effects"], effs):
				# the old numbers leave the sheet; the boost goes on again below at the new ones
				player_sheet.remove_source(str(tb["source"]))
				timed.erase(tb)
				break
		add_timed_effects(COUNTERPUNCH, "Counterpunch", effs, secs, true)
		did = true
	return did


## Whether two effect lists say the same (stat, op, value) in the same order (Counterpunch's boost after a level).
static func _same_effects(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for k in range(a.size()):
		var x: Effect = a[k]
		var y: Effect = b[k]
		if x.stat != y.stat or x.op != y.op or not is_equal_approx(x.value, y.value):
			return false
	return true


## A weapon fired (WeaponBehavior._process, every weapon's clock): an armed Counterpunch becomes this weapon's attack,
## its hits doubled for COUNTER_HIT_WINDOW at most; the same weapon firing again ends it (that is its next attack).
func counterpunch_fired(weapon_id: String) -> void:
	if counter_armed:
		counter_armed = false
		counter_weapon = weapon_id
		counter_until = buff_clock() + COUNTER_HIT_WINDOW
	elif weapon_id == counter_weapon:
		counter_weapon = ""


## What a hit by `weapon_id` is multiplied by for Counterpunch (EnemyManager.damage, weapon hits only): 1 +
## `counter_damage` while it is the counter-attack, else 1.
func counterpunch_mult(weapon_id: String) -> float:
	if counter_weapon == "" or weapon_id != counter_weapon:
		return 1.0
	if buff_clock() > counter_until:
		counter_weapon = ""
		return 1.0
	return 1.0 + maxf(player_sheet.get_stat("counter_damage", 0.0), 0.0)


## Heavyweight (pass 69, Garry: "Increases damage by +N% per N max HP"): `heavyweight` attack damage for every whole 10
## max HP the sheet holds, as its own source ("Heavyweight +12%"); redone whenever the passives are (a level, an item, a
## rebuild), so it follows his max HP.
func heavyweight_might() -> float:
	var per := player_sheet.get_stat("heavyweight", 0.0)
	if per <= 0.0:
		return 0.0
	return per * floorf(player_sheet.get_stat("max_hp", 100.0) / 10.0 + 0.0001)


func _apply_heavyweight() -> void:
	if _heavy_source != "":
		player_sheet.remove_source(_heavy_source)
		_heavy_source = ""
	var v := heavyweight_might()
	if v <= 0.0:
		return
	_heavy_source = "Heavyweight +%d%%" % int(round(v * 100.0))
	player_sheet.add_effects([Effect.make("might", "mul", v, "player")], _heavy_source, _ramp_sid("heavyweight"))


## Last Stand (pass 69, Garry: "Upon taking damage below N% Max HP, slow down time and deal Nx damage for like 2
## seconds. Has a cooldown of 20 seconds that's not communicated to the Player anywhere"): a hit that leaves the hero
## alive under LAST_STAND_BELOW of `max_hp`, with `last_stand` held, not already running and off its hidden cooldown,
## starts it (its attack damage on the sheet) and the cooldown. True when it started: the caller (Player.take_damage,
## by its signal Game) slows the clock and shows it; set_last_stand(false) ends it.
func last_stand_check(hp: float, max_hp: float) -> bool:
	if hp <= 0.0 or max_hp <= 0.0 or last_stand_active:
		return false
	if player_sheet.get_stat("last_stand", 0.0) <= 0.0 or buff_clock() < last_stand_next:
		return false
	if hp >= max_hp * LAST_STAND_BELOW:
		return false
	last_stand_next = buff_clock() + LAST_STAND_COOLDOWN
	set_last_stand(true)
	return true


## Last Stand's attack damage on or off the sheet (the weapons rebuilt with it).
func set_last_stand(on: bool) -> void:
	if on == last_stand_active:
		return
	last_stand_active = on
	_apply_last_stand()
	haste = player_sheet.get_stat("haste", 1.0)
	for w in weapons:
		w.rebuild(player_sheet, weapons)
	build_changed.emit()


## What Last Stand multiplies attack damage by while it runs: 1 + `last_stand` (x2, x2.5, x3 by its level).
func last_stand_mult() -> float:
	return 1.0 + maxf(player_sheet.get_stat("last_stand", 0.0), 0.0)


const _LAST_STAND_SOURCE := "Last Stand"


func _apply_last_stand() -> void:
	player_sheet.remove_source(_LAST_STAND_SOURCE)
	if not last_stand_active:
		return
	var v := player_sheet.get_stat("last_stand", 0.0)
	if v > 0.0:
		player_sheet.add_effects([Effect.make("might", "mul", v, "player")], _LAST_STAND_SOURCE, _ramp_sid("last_stand"))


## Phoenix Feather (pass 48): the hero carries a free revive (the player stat `phoenix_revive`) not spent this run.
## Game._on_player_died stands him up with it before the Down! screen.
func phoenix_ready() -> bool:
	return phoenix_spent < phoenix_count()


## Pass 95 (lane PASSIVES): the free revives the feather carries (its `phoenix_revive`: one, two on its Evolved rung)
## and how many this run has spent; `phoenix_used` stays the "all spent" flag the UI and the tests read.
var phoenix_spent := 0


func phoenix_count() -> int:
	return int(round(player_sheet.get_stat("phoenix_revive", 0.0)))


## Spends one of Phoenix Feather's revives (the run recorder hears it as a "revive" of kind "phoenix", Game._revive);
## the item is used up once every one is spent.
func use_phoenix() -> void:
	phoenix_spent += 1
	_refresh_phoenix_used()


## The "all spent" flag follows the lives the feather carries now (a rung that adds a life frees it again).
func _refresh_phoenix_used() -> void:
	phoenix_used = phoenix_spent > 0 and phoenix_spent >= phoenix_count()


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
	_desperado_built_ms = _rebuild_clock_ms()
	var v := desperado_might()
	if v <= 0.0:
		return
	var e := Effect.new()
	e.stat = "might"; e.op = "mul"; e.value = v; e.target = "player"
	_desperado_source = "Desperado +%d%%" % int(round(v * 100.0))
	player_sheet.add_effects([e], _desperado_source, _ramp_sid("desperado"))


## Pass 95 (lane BREATH): a weapon's level effects aimed at "player" (WeaponDef.player_effects: the Fire Eater's thorns
## +8) reach the hero's sheet while the weapon is held, as a mutation's player_effects do; source "weapon:<id>" (the
## pause Stats tab names the weapon). _build_player_sheet calls it; a weapon added, levelled or evolved that carries
## any tells it (_weapon_player_effects_changed), so the sheet follows at once.
func _apply_weapon_player_effects() -> void:
	for w in weapons:
		var src: String = "weapon:" + w.def.id
		player_sheet.remove_source(src)
		var effs: Array = w.def.player_effects(w.level)
		if not effs.is_empty():
			player_sheet.add_effects(effs, src)


## Pass 95 (lane BREATH): `w` was just added, levelled or evolved (from `old`): when either form carries player effects
## the hero's sheet is built again and every weapon rebuilt on it.
func _weapon_player_effects_changed(w: WeaponInstance, old: WeaponDef = null) -> void:
	var any: bool = w != null and not w.def.player_effects(w.level).is_empty()
	if not any and old != null:
		any = not old.player_effects(old.max_level).is_empty()
	if not any:
		return
	_build_player_sheet()
	for x in weapons:
		x.rebuild(player_sheet, weapons)


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
	# Gold Rush (pass 70) reads the `gold_might` the passives just put on the sheet
	_apply_gold_rush()
	# Heavyweight (pass 69) reads the max HP everything above put on the sheet
	_apply_heavyweight()
	# pass 95 (lane PASSIVES): Phoenix Feather's lives follow its rungs
	_refresh_phoenix_used()


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
	player_sheet.add_effects([Effect.make("might", "mul", v, "player")], _steady_source, _ramp_sid("still_might"))


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
##   "mutation"   any mutation (pass 60, Garry: "mutations shouldn't be banishable anywhere"; pass 58 had let a hero's
##                own go): a path's pick is the weapon's progress and a hero's own is his alone, so none is struck
## A new weapon, line, passive item or perk may go.
func banish_refusal(card: Dictionary) -> String:
	var type := str(card.get("type", ""))
	var id := str(card.get("id", ""))
	var def = card.get("def")
	if type == "gold" or id == "" or def == null:
		return "gold"
	if type == "mutation" or def is MutationDef:
		return "mutation"
	if type == "evolution" or bool(card.get("evolve", false)):
		return "evolution"
	if (def is WeaponDef and (def as WeaponDef).is_evolution) or (def is PassiveDef and (def as PassiveDef).is_evolved()):
		return "evolution"
	if int(card.get("level_from", 0)) > 0 or has_weapon(id) or passives.has(id):
		return "held"
	# the Boomstick while the Blunderbuss is held (pass 58 review: a level-up had offered it again as NEW, banishable)
	if def is WeaponDef and family_instance(id) != null:
		return "held"
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


# ---------------------------------------------------------------- pass 79 (lane MUT): mutations come as level-ups

## Pass 79 (Garry: "Mutations are supposed to be level ups, not just random occurrences"; his pick: the offers stay, one
## per weapon per stage, but come as the level-up screen itself in place of the three cards):
##   M1 a mutation offer falls due as before: the stage clock passes one of the map's `path_times` (path_due, Phase
##      NORMAL only). One that falls due while no weapon has a pick open is spent with nothing, as a slot was before.
##   M2 a due offer never opens on its own: it waits (mutlvl_due) for the hero's next level-up, which becomes a mutation
##      level-up (mutlvl_claim, in add_xp): its screen shows the offer (the weapon's reel and its path cards, as before)
##      in place of the three cards. Due offers queue, one a level-up, and stay due across a stage's end.
##   M3 at that level-up a weapon must have a pick open; with none the offer is dropped and the level-up is an ordinary
##      one. The weapon is drawn when the screen opens (mutlvl_take: next_path_weapon among those open then); a level
##      banked meanwhile whose weapons all lost their pick (a chest's mutation) opens as an ordinary one too.
##   M4 the HUD marks the LV plate and the XP rail while the next level-up is a mutation (mutlvl_pending).
##   M5 a mutation level-up counts once it is claimed (mutation_levels; a skipped offer too); card_level() leaves them
##      out for what grows with the hero's level.
## Called by the director every frame of the stage clock: true when an offer fell due now (and was kept).
func mutlvl_tick(t_in_stage: float) -> bool:
	if not path_due(t_in_stage):
		return false
	# the arena levels by its buttons: no offer falls due there (the old slot's present_path_offer did nothing there)
	if arena:
		return false
	if path_offer_instances().is_empty():
		_note("mutation_due", "", level, {"dropped": true, "slot": path_slot, "due": mutlvl_due})
		return false
	mutlvl_due += 1
	_note("mutation_due", "", level, {"slot": path_slot, "due": mutlvl_due})
	mutation_due_changed.emit()
	return true


## Whether the hero's next level-up will be a mutation offer (the HUD's mark): an offer is due and a weapon has a pick
## open now.
func mutlvl_pending() -> bool:
	return mutlvl_due > 0 and not path_offer_instances().is_empty()


## A level-up (add_xp, each level) takes the next due offer (M2, M3): true when it is a mutation level-up. With no weapon
## open the offer is dropped and the level is an ordinary one.
func mutlvl_claim() -> bool:
	if mutlvl_due <= 0:
		return false
	mutlvl_due -= 1
	var open := not path_offer_instances().is_empty()
	if open:
		mutlvl_ready += 1
		mutation_levels += 1
	else:
		_note("mutation_due", "", level, {"dropped": true, "due": mutlvl_due, "at_level_up": true})
	mutation_due_changed.emit()
	return open


## A level-up screen opening (Game._show_next_level_cards): the weapon whose path goes on the table when a claimed
## mutation level-up waits (mutlvl_ready), drawn among those open now; null for an ordinary level-up. A claimed one whose
## weapons all lost their pick meanwhile is an ordinary one after all (mutlvl_unclaim).
func mutlvl_take() -> WeaponInstance:
	if mutlvl_ready <= 0:
		return null
	mutlvl_ready -= 1
	var w := next_path_weapon()
	if w == null:
		mutlvl_unclaim()
	return w


## A claimed mutation level-up that opened as three cards after all: it counts as a card level again (the trait and
## the creatures' level factor follow at once).
func mutlvl_unclaim() -> void:
	mutation_levels = maxi(mutation_levels - 1, 0)
	_note("mutation_due", "", level, {"dropped": true, "due": mutlvl_due, "at_screen": true})
	if levels_trait():
		_build_player_sheet()
		hero_sheet_changed.emit()
		rebuild_sheets()


## The level the numbers that grow with the hero's level read (pass 79, M5): the creatures' level factor
## (WaveDirector), his trait (hero_sheet), Barrel Rush, Ram and Supply Drop. His level less the level-ups that were
## mutation offers (the card levels: about the level the curve before pass 79 gave at the same minute), unless the map's
## `mutation_levels_scale` counts them too. The arena and a run without a map read the level.
func card_level() -> int:
	if map == null or map.timeline == null or map.timeline.mutation_levels_scale:
		return level
	return maxi(level - mutation_levels, 1)


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


## How long a power-up picked up off the ground lasts before buff_seconds (pass 62, the Pocket Watch: x the
## `powerup_duration` player stat, 1 without it, 1.75 at level 5). Game.apply_pickup's timed buffs and the Shield go
## through it; a structure's buff, Pollen and Barrel Rush do not (they call add_timed_effects with their own seconds).
func powerup_seconds(seconds: float) -> float:
	return seconds * maxf(player_sheet.get_stat("powerup_duration", 1.0), 0.0)


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
	if (_desperado_dirty or _steady_dirty or _streak_dirty) and _rebuild_clock_ms() >= _desperado_built_ms + DESPERADO_REBUILD_MS:
		rebuild_sheets()
	return ended


## Pass 77 (lane SIMRUN): the clock the rules that count real time read, in seconds (an Orbiter's hit on the same
## creature, Orbiter._tick; the sheet's rebuild throttle, _rebuild_clock_ms): real time in play (a phone's real time is its
## game time), the buffs' clock in a run sim (sim_clock or sim_mode: a headless run goes 2.5 to 4.5 times faster than real
## time, so on real time an orbiter's saws hit a creature that many times less often, the bonus lags, and how much
## depends on the machine's speed).
## Pass 102 (lane STEADY): in play it is the game's own clock (play_clock: the frames' deltas), no longer the wall clock,
## so when the world slows under load (the capped catch-up) these rules slow with it.
func rule_seconds() -> float:
	return buff_clock() if (sim_clock or sim_mode) else play_clock


## The rebuild throttle's clock (DESPERADO_REBUILD_MS) in milliseconds: rule_seconds' clock.
func _rebuild_clock_ms() -> int:
	return int(buff_clock() * 1000.0) if (sim_clock or sim_mode) else int(play_clock * 1000.0)


## Pass 102 (lane STEADY): play_clock advances by the frame's delta (the autoload pauses with the tree).
func _process(delta: float) -> void:
	play_clock += delta


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


## Pass 106 (lane DRUM): a running timed buff's effects swapped for `effects`, its clock kept (the War Drum's boost
## while a Berserk or a Sprint starts or ends beside it: DrumBoost's stacking rule). False when no buff has that id.
func retune_timed(id: String, effects: Array) -> bool:
	for tb in timed:
		if tb["id"] == id:
			player_sheet.remove_source(str(tb["source"]))
			tb["effects"] = effects
			player_sheet.add_effects(effects, str(tb["source"]))
			haste = player_sheet.get_stat("haste", 1.0)
			for w in weapons:
				w.rebuild(player_sheet, weapons)
			build_changed.emit()
			return true
	return false


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
	# pass 82 (lane XP): the map's growth type (XpCurve; no xp_curve = 15 + 6L + 0.5L^2, the same maths as before)
	return XpCurve.need(xp_curve(), L) * xp_need_mult()


## Pass 82 (lane XP): the map's XP growth type and numbers (WaveTimeline.xp_curve, read by XpCurve); {} (today's curve)
## without a map and in the arena, where levels come by the button.
func xp_curve() -> Dictionary:
	if arena or map == null or map.timeline == null:
		return {}
	return map.timeline.xp_curve


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
	var grew := false
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_level_reached = max(max_level_reached, level)
		# pass 79 (lane MUT): a due mutation offer makes this level-up a mutation level-up (M2; before the trait reads
		# card_level)
		mutlvl_claim()
		# the signature stat grows with the level (pass 61): the hero's own sheet follows before anyone hears of it, so his
		# max HP has risen by the time a level-up heals a share of it; the weapons and the HUD rebuild once after the loop
		# (the review: a credit of many levels at once rebuilt every weapon and plate per level)
		if levels_trait():
			_build_player_sheet()
			hero_sheet_changed.emit()
			grew = true
		level_up.emit(level)
		xp_changed.emit(xp, xp_to_next())
	if grew:
		rebuild_sheets()


## Gold out of the purse. `sink` names where it went (pass 61, Garry: "Coin Gains / Spend ... have all the sources"):
## shop, revive (RunAnalytics.GOLD_SINKS); the run recorder tallies it.
func spend_gold(n: int, sink: String = "other") -> bool:
	if run_gold < n:
		return false
	run_gold -= n
	if n > 0 and RunAnalytics.I: RunAnalytics.I.gold_out(sink, n)
	gold_changed.emit(run_gold)
	return true


## Gold into the purse, scaled by greed. `source` names where it came from (pass 61: coins, elite_purse, chest, ...;
## RunAnalytics.GOLD_SOURCES); the run recorder tallies what was gained, and what greed added to it.
func add_gold(n: int, source: String = "other") -> void:
	var gained := int(round(n * player_sheet.get_stat("greed", 1.0)))
	run_gold += gained
	# all-time gold earned (pass 44: an unlock counts it), whatever becomes of the purse
	if gained > 0 and not arena:
		Save.add_total("gold_earned", gained)
	if gained > 0 and RunAnalytics.I: RunAnalytics.I.gold_in(source, gained, gained - n)
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


## Trick Shot (pass 69, lane FRIS, the Frisbee's motion mutation): what weapon `weapon_id`'s own `params.proc_mult`
## multiplies its life steal (add_damage), its crit, Cold Snap and Vulture chances (EnemyManager.damage) by; 1 for a
## weapon without one, for a weapon he does not hold and for a hit no weapon sent.
func trick_proc_mult(weapon_id: String) -> float:
	if weapon_id == "":
		return 1.0
	var wi := weapon_instance(weapon_id)
	if wi == null:
		return 1.0
	return maxf(float(wi.params.get("proc_mult", 1.0)), 0.0)


func add_damage(weapon_id: String, amount: float, element: String = "") -> void:
	damage_by_weapon[weapon_id] = float(damage_by_weapon.get(weapon_id, 0.0)) + amount
	# pass 113 (lane TASKS): a burn's or a poison's tick (EnemyManager.damage's hot / green hit) counts as fire / poison
	if element != "":
		element_damage[element] = float(element_damage.get(element, 0.0)) + amount
	# pass 72 (lane BOSS): the window the boss HP scaling reads
	dps_note(amount)
	if RunAnalytics.I: RunAnalytics.I.dealt(weapon_id, amount)
	# life steal: a slice of every point of damage comes back as health
	# lifesteal is a trickle, not a tap: at most LIFESTEAL_CAP of max HP a second, however much damage a build pours
	# out (a beam through forty creatures used to refill the bar in one sweep)
	var ls: float = player_sheet.get_stat("lifesteal", 0.0)
	if ls > 0.0:
		# Trick Shot (pass 69): the weapon's own proc_mult
		ls *= trick_proc_mult(weapon_id)
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
			# the hero's favourite comes with its bonus (pass 62: at its bonus level when that is higher)
			cands.append({"type": "weapon", "id": w.id, "def": w, "level_from": 0, "level_to": maxi(mini(2, w.max_level), CardPool.first_weapon_level(w)), "is_new": true})
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
			var fresh := add_weapon(def, 1)
			# the hero's favourite brings its bonus whoever hands it over (pass 62, as a level-up's card does)
			if fresh and character and character.favourite_weapon == def.id:
				CardPool.apply_favourite(fresh)
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


# ---------------------------------------------------------------- the Totem Poles (pass 73, lane STRUCT)

## core/systems/TotemBoons.gd, by path (a new script's class name is unknown until the editor imports it)
const TOTEM_BOONS := preload("res://core/systems/TotemBoons.gd")


## A Totem Pole's gift taken (TotemBoons: a rolled {id, name, animal, stat, op, value, ...}): on the hero for the rest of
## the run, the sheets rebuilt. Returns its words ("+6% move speed").
func take_totem_boon(boon: Dictionary) -> String:
	if boon.is_empty() or str(boon.get("stat", "")) == "":
		return ""
	totem_boons.append(boon.duplicate())
	# pass 113 (lane TASKS): one Totem gift taken (a pole used with nothing taken never reaches here)
	totems_taken += 1
	_note("totem", str(boon.get("id", "")), totem_boons.size(), {"stat": str(boon.get("stat", "")), "value": float(boon.get("value", 0.0))})
	rebuild_sheets()
	return TOTEM_BOONS.text(boon)


## Every gift taken, each its own source on the sheet ("Totem: Le-loo"), so the pause screen's breakdown names it.
func _apply_totem_boons() -> void:
	for b: Dictionary in totem_boons:
		player_sheet.add_effects([TOTEM_BOONS.effect_of(b)], TOTEM_BOONS.source(b), "totem:" + str(b.get("id", b.get("stat", ""))))


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
	_weapon_player_effects_changed(inst)   # pass 95 (lane BREATH)
	build_changed.emit()
	return inst


func level_weapon(id: String) -> void:
	var w := weapon_instance(id)
	if w and w.level < w.def.max_level:
		w.level += 1
		_note("weapon", id, w.level, {"new": false})
		w.rebuild(player_sheet, weapons)
		_weapon_player_effects_changed(w)   # pass 95 (lane BREATH)
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
	_weapon_player_effects_changed(inst, w.def)   # pass 95 (lane BREATH): the Fire Eater's thorns land at once
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
			add_gold(60, "chest")
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
				add_gold(int(r.get("gold", 50)), "chest")
				return "+%d gold" % int(r.get("gold", 50))
			level_weapon(r["id"])
			return Registry.weapon(r["id"]).display_name + " Lv " + str(weapon_instance(r["id"]).level)
		"passive":
			# the same: a passive that evolved under the reel is no longer there to level (a new passive item, pass 47,
			# is taken; one that cannot be is gold)
			var pid := str(r["id"])
			if (not bool(r.get("is_new", false)) and not passives.has(pid)) or not add_or_level_passive(pid):
				add_gold(int(r.get("gold", 50)), "chest")
				return "+%d gold" % int(r.get("gold", 50))
			return Registry.passive(pid).display_name + " Lv " + str(passives[pid])
		_:
			add_gold(int(r.get("gold", 50)), "chest")
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
## gold, or (pass 58) banish_refusal refuses it: never an upgrade of what the hero has, an evolution or (pass 60) any
## mutation.
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


## The stage multiplier of this run's stage (pass 87: Endless no longer grows it; its waves carry their own multipliers,
## WaveTimeline.endless_mults, on the creatures' fixed numbers).
func stage_mult() -> float:
	if map == null or map.timeline == null:
		return 1.0
	return map.timeline.stage_mult(stage)


## Seconds into Endless (0 before it; pass 87: Endless's own clock, endless_time).
func endless_seconds() -> float:
	return endless_time if endless else 0.0


## The Endless wave the run is in, 1-based (0 outside Endless; pass 87: a wave every `endless.every` seconds).
func endless_wave() -> int:
	if not endless or map == null or map.timeline == null:
		return 0
	return map.timeline.endless_wave_at(endless_time, stage)


# ---------------------------------------------------------------- stages as their own runs (pass 87, lane SGAME)

## The stage the next run plays (0-based; the Stages menu, the Watch, a tool). Set it before loading the Game scene: Game
## starts that stage (start_stage) and puts stage_next back to 0, so a Play that skips the menu plays stage 1.
func choose_stage(i: int) -> void:
	stage_next = maxi(i, 0)


## Puts the fresh run (Run.start: level 1, nothing taken) at stage `i`'s window start (Garry: a stage picked from the menu
## "is a fresh run: level 1, the hero's start weapon"): the run clock at the window's start, the stage's index for its
## multipliers, its path slots from the first. Game calls it right after start(); the tests call it directly. The run's
## end is that stage's boss (WaveDirector); it never continues into the next stage.
func start_stage(i: int) -> void:
	var tl: WaveTimeline = map.timeline if map else null
	var k: int = tl.stage_clamp(i) if tl else 0
	stage = k
	elapsed = tl.stage_start(k) if tl else 0.0
	held_time = 0.0
	path_slot = 0
	endless = false
	endless_time = 0.0
	stage_beaten = false
	stage_changed.emit(stage)


## Seconds into this run's stage (the HUD's, the pause screen's and the Down! screen's clock: 0:00 at the stage's start,
## its length at its boss; it stands still through the boss fight, the portal countdown and Endless, as the run clock does).
func stage_clock() -> float:
	if map == null or map.timeline == null:
		return elapsed
	return maxf(elapsed - map.timeline.stage_start(stage), 0.0)


## This run's stage's length in seconds (before its boss).
func stage_length_now() -> float:
	if map == null or map.timeline == null:
		return 0.0
	return map.timeline.stage_len(stage)


## Every second of this run played (unpaused): the stage clock plus the boss fight, the portal countdown and Endless (the
## run clock stands still there and held_time counts on). The "survive N minutes" quests and the best time read it.
func run_time() -> float:
	return stage_clock() + held_time


## How this run ended, or stands (the Results, analytics): "extracted", "died_endless" (fell in Endless),
## "died_after_boss" (fell after the boss, before Endless), "died" (fell before the boss, or quit; a quit is died too).
func outcome() -> String:
	if extracted:
		return "extracted"
	if endless:
		return "died_endless"
	if stage_beaten:
		return "died_after_boss"
	return "died"


func summary() -> Dictionary:
	return {
		# pass 87 (lane SGAME): the time is every second the run was played (run_time; the best time keeps the same), and
		# the stage run's own numbers ride along
		"time": run_time(), "stage_clock": stage_clock(), "stage_name": map.timeline.stage_name(stage) if map and map.timeline else "",
		"outcome": outcome(), "stage_beaten": stage_beaten, "endless_time": endless_time, "endless_wave": endless_wave(),
		"stage": stage + 1, "level": level, "kills": kills, "gold": run_gold,
		"extracted": extracted, "died": died, "damage_by_weapon": damage_by_weapon.duplicate(),
		"kills_by_weapon": kills_by_weapon.duplicate(), "evolutions": evolutions, "chests": chests_opened,
		"character": character.display_name if character else "", "map": map.display_name if map else "",
	}


# ---------------------------------------------------------------- the hero's DPS (pass 72, lane BOSS)

## Garry: "Boss Max HP should scale up the bigger the Player's DPS is in that moment". Every point add_damage records (what
## a hit took off, never past what the creature had left) goes into the bucket of its whole second on buff_clock (the
## clock that runs on through boss fights and portal waits); recent_dps(window) is the sum of the last `window` seconds
## over the seconds the run has had (so the first seconds of a run are not read as a weak hero). The director reads it
## when a boss arrives (WaveDirector.boss_dps_scale).
const DPS_BUCKETS := 240
var _dps_sum := PackedFloat32Array()
var _dps_sec := PackedInt32Array()


func dps_reset() -> void:
	_dps_sum.resize(DPS_BUCKETS)
	_dps_sum.fill(0.0)
	_dps_sec.resize(DPS_BUCKETS)
	_dps_sec.fill(-1)


func dps_note(amount: float) -> void:
	if amount <= 0.0:
		return
	if _dps_sum.size() != DPS_BUCKETS:
		dps_reset()
	var sec := int(floor(buff_clock()))
	var k := posmod(sec, DPS_BUCKETS)
	if _dps_sec[k] != sec:
		_dps_sec[k] = sec
		_dps_sum[k] = 0.0
	_dps_sum[k] += amount


## The hero's damage a second over the last `window` seconds of buff_clock (the second running now counted as far as it
## has gone); 0 before any damage.
func recent_dps(window: float) -> float:
	if _dps_sum.size() != DPS_BUCKETS:
		return 0.0
	var now := buff_clock()
	var w := clampf(window, 1.0, float(DPS_BUCKETS - 1))
	var sec := int(floor(now))
	var first := int(floor(now - w))
	var total := 0.0
	for s in range(maxi(first, 0), sec + 1):
		var k := posmod(s, DPS_BUCKETS)
		if _dps_sec[k] == s:
			total += _dps_sum[k]
	# pass 87 (lane SGAME): the seconds this run has had (run_time: a stage run's clock starts at its window, not 0)
	var span := minf(w, maxf(minf(now, run_time()), 1.0))
	return total / span
