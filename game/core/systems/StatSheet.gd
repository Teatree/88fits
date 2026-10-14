## A bag of named stats with a base value and a list of Effects, each tagged with its source.
## final = (base + Σ add) × Π (1 + mul), with "set" replacing the base. Keeps sources so the
## pause screen can show every stat's breakdown.
class_name StatSheet
extends RefCounted

## Known player stats with defaults. Weapons use their own keys from WeaponDef.base.
const PLAYER_DEFAULTS := {
	"max_hp": 100.0, "damage_reduction": 0.0, "regen": 0.0, "move_speed": 3.6, "might": 1.0, "cooldown": 1.0,
	"area": 1.0, "projectile_speed": 1.0, "duration": 1.0, "amount": 0.0, "magnet": 1.5, "luck": 0.0, "freeze_chance": 0.0, "crit_heal_chance": 0.0, "gold_on_hit": 0.0,
	"greed": 1.0, "lifesteal": 0.0, "revives": 0.0, "turn_rate": 180.0,
	# the choices (pass 47, Garry: "only two skips per Stage ... initially 1 Banish"): skips and banishes are a stage's,
	# refilled at the run's start and at every stage (Run.refill_choices), the Mirror's Skip and Banish a rank each more;
	# rerolls stay a run's
	"rerolls": 1.0, "skips": 2.0, "banishes": 1.0,
	# passive mechanisms (pass 23): rolled or applied by the systems, never by the sheet itself
	"crit_chance": 0.01, "crit_damage": 2.0, "execute_frac": 0.0, "thorns": 0.0, "adrenaline_speed": 0.0, "adrenaline_might": 0.0,
	"overkill": 0.0, "cooldown_on_kill": 0.0, "xp_gain": 1.0, "ricochet": 0.0, "homing_turn": 1.0,
	# Berserk (pass 33): every weapon's clock runs this much faster (cooldowns divided, blades spin, turrets fire)
	"haste": 1.0,
	# the protective lines and drops (pass 33.2): Evade and Ghost Step, the Energy Shield and Aegis, Second Wind's
	# shorter wait, Bloodthirst's higher lifesteal cap, Cake and Pickpocket
	"evade": 0.0, "evade_invuln": 0.0, "shield_max": 0.0, "shield_delay": 3.0, "shield_rate": 0.5,
	"regen_delay": 3.0, "lifesteal_cap": 0.04, "heal_drop": 0.0, "coin_drop": 0.0,
	# pass 46: the untouchable seconds after a hit, the share of max HP a revive stands up with, and Desperado (up to
	# this much more attack damage as health falls)
	"hit_invuln": 0.5, "revive_hp": 0.5, "desperado": 0.0,
	# pass 47, the new lines and passive items (each read by the system it names): Ducktape's longer burns, poison, slows,
	# marks and pins (a multiplier); Hot Sauce's difficulty (coloured creatures more often, better paid); Siesta's regen
	# and Steady Hand's attack damage a second while the hero stands still (Run.note_still); Barrel Rush's speed and its
	# seconds after a barrel (Run.barrel_rush); Prospector's chance of an extra XP gem a kill; Big Game Hunter's extra
	# damage to Elites and bosses
	"debuff_duration": 1.0, "difficulty": 0.0, "still_regen": 0.0, "still_might": 0.0, "barrel_speed": 0.0,
	"barrel_seconds": 0.0, "xp_drop_chance": 0.0, "elite_damage": 0.0,
	# pass 48, the new passive items (each read by the system it names): Phoenix Feather's free revive (Run.phoenix_ready,
	# Game._on_player_died); Skedaddle's move speed and its seconds after a hit lands (Run.skedaddle); Powder Keg's chance
	# a kill blows up (Game._on_enemy_died); Loose Change's chance a hit knocks a coin out of the hero (Game._on_player_hit);
	# Gas Mask's most damage reduction from poisoned creatures (Run.poisoned_alive); pass 49: Hot Streak's attack damage per
	# 1,000 kills made while it is held (Run.hot_streak_bonus)
	"phoenix_revive": 0.0, "hurt_speed": 0.0, "hurt_speed_seconds": 0.0, "powder_keg_chance": 0.0, "coin_on_hit": 0.0,
	"gas_mask_cap": 0.0, "kill_might": 0.0,
	# pass 54, Solenne: how long every buff on her lasts (Run.buff_seconds: the power-ups, structures, Pollen, Barrel Rush,
	# Skedaddle, the shield power-up), and how big every heal on her is (Player.heal and her regen, Afterglow)
	"buff_duration": 1.0, "heal_mult": 1.0,
	# pass 62, the Pocket Watch: how long a power-up picked up off the ground lasts (Run.powerup_seconds: Berserk, Sprint,
	# the Shield; never a structure's buff, Pollen or Barrel Rush), and a factor on the timeline's per-kill drop chance of
	# a power-up (WaveDirector.drop_pickup_from)
	"powerup_duration": 1.0, "powerup_chance": 1.0,
	# pass 69, the new passive items (each read by the system it names): Counterpunch's next attack after an evade and
	# its timed attack speed and move speed (Run.counterpunch_*); Heavyweight's attack damage per 10 max HP
	# (Run._apply_heavyweight); Snake Oil's overheal as a share of max HP (Player.overheal_cap); Hot Springs' heal pulse
	# (Player._tick_heal_pulse); Last Stand's attack damage in its slowed time (Run.last_stand_check); the Magnet's EXP
	# pulls, their radius and how much more often they come (PickupManager._tick_xp_pulls)
	"counter_damage": 0.0, "counter_haste": 0.0, "counter_speed": 0.0, "counter_seconds": 0.0, "heavyweight": 0.0,
	"overheal": 0.0, "heal_pulse": 0.0, "last_stand": 0.0, "xp_pull_radius": 0.0, "xp_pull_rate": 0.0,
	# pass 70 (lane LINES), the new lines' evolutions (each read by the system it names): Bucking Bronco's chance a
	# knocked-back creature is launched up and away (EnemyManager._bronco_kick); Prairie Fire's jumps of an ending burn or
	# poison (EnemyManager._prairie_jump); Marshal's Star's seconds between its blocks (StarGuard); Mother Lode's seconds
	# between its sweeps of the screen's gems (PickupManager._tick_gem_sweep); Eureka's chance a kill strikes a vein
	# (PickupManager.vein); Gold Rush's attack damage per Run.GOLD_RUSH_PER gold gained while held (Run.gold_rush_bonus)
	"bronco_chance": 0.0, "debuff_jump": 0.0, "star_block_every": 0.0, "gem_sweep_every": 0.0, "vein_chance": 0.0,
	"gold_might": 0.0,
}

## The least a hero's stat can come to, however many sources pull it down (pass 61: Ironwood's regen delay shrinks every
## level, never under half a second). The player scope's get_stat applies it, so the pause screen, the CV and the hero
## all read the same number; TextGen.hero_trait names it.
const STAT_FLOORS := {"regen_delay": 0.5}

## "player" for the hero's own sheet: effects aimed at weapons ("all_weapons", "weapon:<id>", "tag:<tag>") are carried
## for the weapons to pick up but never folded into the hero's numbers; "" folds everything (a weapon's sheet)
var scope := ""
var base: Dictionary = {}
## Array of {"effect": Effect, "source": String, "sid": String}. Pass 76 (lane UI): `sid` is the source's stable id beside
## its words ("talent:grit:0", "totem:wolf", "passive:brawn", "trait:solenne"), what the pause Stats tab groups, names and
## draws a source by; the source's words when none is given (remove_source still goes by the words).
var entries: Array = []


func set_base(stat: String, v: float) -> void:
	base[stat] = v


func set_bases(d: Dictionary) -> void:
	for k in d.keys():
		base[str(k)] = float(d[k])


func add_effect(e: Effect, source: String = "", sid: String = "") -> void:
	if e == null or e.stat == "":
		return
	entries.append({"effect": e, "source": source, "sid": sid if sid != "" else source})


func add_effects(list: Array, source: String = "", sid: String = "") -> void:
	for e in list:
		if e is Effect:
			add_effect(e, source, sid)


## Whether an effect is aimed at weapons ("all_weapons", "weapon:<id>", "tag:<tag>"): carried on the hero's sheet for the
## weapons to pick up, never in the hero's own numbers (get_stat's player scope; pass 76: his breakdown too).
static func aims_at_weapons(e: Effect) -> bool:
	return e.target == "all_weapons" or e.target.begins_with("weapon:") or e.target.begins_with("tag:")


func remove_source(source: String) -> void:
	var keep: Array = []
	for en in entries:
		if en["source"] != source:
			keep.append(en)
	entries = keep


func clear_effects() -> void:
	entries.clear()


func has_stat(stat: String) -> bool:
	if base.has(stat):
		return true
	for en in entries:
		if en["effect"].stat == stat:
			return true
	return false


func get_stat(stat: String, default: float = 0.0) -> float:
	var b: float = float(base.get(stat, default))
	var adds := 0.0
	var mul := 1.0
	for en in entries:
		var e: Effect = en["effect"]
		if e.stat != stat:
			continue
		if scope == "player" and (e.target == "all_weapons" or e.target.begins_with("weapon:") or e.target.begins_with("tag:")):
			continue
		match e.op:
			"add":
				adds += e.value
			"mul":
				mul *= (1.0 + e.value)
			"set":
				b = e.value
	if scope == "player" and STAT_FLOORS.has(stat):
		return maxf((b + adds) * mul, float(STAT_FLOORS[stat]))
	return (b + adds) * mul


func get_int(stat: String, default: int = 0) -> int:
	return int(round(get_stat(stat, float(default))))


func stats() -> Array:
	## Every stat name present, base keys first then any effect-only keys.
	var out: Array = base.keys()
	for en in entries:
		var s: String = en["effect"].stat
		if not out.has(s):
			out.append(s)
	return out


func breakdown(stat: String) -> Array:
	## Rows for the Stats tab: [{"source": "base", "text": "5.0"}, {"source": "Dad", "text": "+20%"}, ...]
	var rows: Array = [{"source": "base", "text": TextGen.format_value(stat, float(base.get(stat, 0.0)))}]
	for en in entries:
		var e: Effect = en["effect"]
		if e.stat == stat:
			# pass 76 (lane UI): an effect aimed at weapons is not in the hero's number, so not among his rows
			if scope == "player" and aims_at_weapons(e):
				continue
			rows.append({"source": en["source"], "text": TextGen.describe_effect(e, false)})
	rows.append({"source": "total", "text": TextGen.format_value(stat, get_stat(stat))})
	return rows


func duplicate_sheet() -> StatSheet:
	var s := StatSheet.new()
	s.base = base.duplicate()
	s.entries = entries.duplicate()
	return s
