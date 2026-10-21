## The hero's power level and his full DPS (pass 83, lane SCALE; Garry: "You will write how you calculate the hero
## power level ... The idea is that the higher the Player power level the higher the HP" and "I want it to take at least
## 25 seconds of Player's FULL DPS on Tumbleweed king to kill it").
##
## FULL DPS (full_dps): the damage a second the hero's weapons deal to ONE target that every shot hits, all bonuses in:
##   each weapon's estimate (WeaponInstance.dps_estimate: the pause screen's "dps", might, cooldown, amount, levels and
##   mutations folded in) with its crowd guess taken out (a smash, a cone wave, a gravity blast counted 3 creatures a
##   blow there, a mine or a laser 2, a sun pillar 1.6, a frisbee 2.57, a chained beam 1 + chains, a gun's blast its
##   catch: a boss is one body), plus its burn or poison kept up on that target
##   (fire_damage every 0.6 s, poison_damage x stacks every 2 s), the whole times the average crit
##   (1 + crit_chance x (crit_damage - 1)). On a boss (boss = true) Big Game Hunter's elite_damage is in too.
##   Left out: perks' own hits, thorns, Powder Keg, Overkill splashes, marks (they are small or need a crowd).
## EFFECTIVE HP (ehp): the damage creatures must deal to bring him down over a SUSTAIN_SECONDS fight:
##   (max HP + shield + SUSTAIN_SECONDS x (regen a second + lifesteal a second, the lifesteal held under its cap))
##   / ((1 - damage reduction) x (1 - evade)).
## POWER (power): sqrt((full DPS / BASE_DPS) x (effective HP / BASE_EHP)): the geometric mean of how hard he hits and how
##   much he takes, each against a fresh level-1 Drifter with the Revolver on a clean save (power 1.0). Twice the DPS
##   alone = 1.41, twice both = 2.0; a fight's length against him grows with his DPS x his HP, so the square root keeps
##   the number readable (measured on difficulty_probe's tuned builds: 3 to 5 at the King, 6 to 24 at the Gila, 14 to 50
##   at the Brander; game/tools/_p83_SCALE_boss_probe.gd).
## No autoload is named here (tools compile this before they exist): the run is read through the tree.
class_name HeroPower
extends RefCounted

## A fresh level-1 Drifter's full DPS (the Revolver at level 1, no talents) and effective HP (100 max HP): power 1.0.
## Measured with game/tools/_p83_SCALE_boss_probe.gd mode=base (pass 83).
const BASE_DPS := 20.4
const BASE_EHP := 100.0
## The fight the effective HP counts healing over (seconds).
const SUSTAIN_SECONDS := 30.0
## Fire and poison ticks (EnemyManager.FIRE_TICK, POISON_TICK).
const FIRE_TICK := 0.6
const POISON_TICK := 2.0

static var _cache_key := -1
static var _cache: Dictionary = {}


## The crowd a weapon's estimate counts (what full_dps divides out): 1 for a weapon that hits one target a shot.
static func crowd_of(w: WeaponInstance) -> float:
	match w.behavior():
		"Smasher", "GravityGun", "ConeWave":
			return 3.0
		"MineLayer", "LaserBeam":
			return 2.0
		"SunScepter":
			return WeaponInstance.SUN_CATCH
		"Frisbee":
			return maxf(w.frisbee_catch(), 1.0)
		"Beam":
			return 1.0 + float(maxi(w.stat_int("chains", 0), 0))
		"Orbiter", "Spawner", "Lobber", "MissilePod", "SaltShaker":
			return 1.0
		"FireBreath":
			# pass 95 (lane BREATH): the cone, about BREATH_CATCH creatures in it
			return WeaponInstance.BREATH_CATCH
	# a gun (ProjectileEmitter): its blast's catch (a ricochet is left in: measured on a lone boss, the Golden Revolver
	# lands its whole estimate)
	var bl := w.blast()
	if not bl.is_empty():
		return maxf(WeaponInstance.blast_catch(bl), 1.0)
	return 1.0


## A weapon's burn or poison a second on one target that it keeps alight (0 for a weapon without an element).
static func element_dps(w: WeaponInstance) -> float:
	match w.element():
		"fire":
			return w.stat("fire_damage", 4.0) / FIRE_TICK
		"poison":
			return w.stat("poison_damage", 3.0) * float(maxi(w.stat_int("poison_stacks", 1), 1)) / POISON_TICK
	return 0.0


## One weapon's damage a second on one target every shot hits (before crits).
static func weapon_dps(w: WeaponInstance) -> float:
	if w == null or w.def == null:
		return 0.0
	return maxf(w.dps_estimate(), 0.0) / crowd_of(w) + element_dps(w) * element_uptime(w)


## Pass 95 (lane BREATH): the share of the time a weapon's burn is on its target. 1 for every weapon as before; the
## Dragon's Breath lights it only while it breathes and the burn after (breath_seconds + fire_duration over its long
## cooldown), so its burn is counted for that share and a boss's HP is not pegged to a fire that is out most of the time.
static func element_uptime(w: WeaponInstance) -> float:
	if w == null or w.behavior() != "FireBreath":
		return 1.0
	var cd: float = maxf(w.stat("cooldown", 10.0), 0.05)
	return clampf((w.breath_seconds() + w.stat("fire_duration", 1.8)) / cd, 0.0, 1.0)


## The average crit's factor: 1 + crit_chance x (crit_damage - 1).
static func crit_factor(sheet: StatSheet) -> float:
	if sheet == null:
		return 1.0
	return 1.0 + clampf(sheet.get_stat("crit_chance", 0.0), 0.0, 1.0) * maxf(sheet.get_stat("crit_damage", 2.0) - 1.0, 0.0)


## FULL DPS (see the head of the file): `weapons` the run's WeaponInstances, `sheet` the hero's; boss = true adds Big
## Game Hunter.
static func full_dps(weapons: Array, sheet: StatSheet, boss := false) -> float:
	var s := 0.0
	for w in weapons:
		if w is WeaponInstance:
			s += weapon_dps(w)
	s *= crit_factor(sheet)
	if boss and sheet != null:
		s *= 1.0 + maxf(sheet.get_stat("elite_damage", 0.0), 0.0)
	return s


## EFFECTIVE HP (see the head of the file); `dps` feeds the lifesteal.
static func ehp(sheet: StatSheet, dps: float) -> float:
	if sheet == null:
		return BASE_EHP
	var mh := sheet.get_stat("max_hp", 100.0)
	var hp := mh + maxf(sheet.get_stat("shield_max", 0.0), 0.0)
	var regen := maxf(sheet.get_stat("regen", 0.0), 0.0)
	var ls := minf(maxf(sheet.get_stat("lifesteal", 0.0), 0.0) * maxf(dps, 0.0), mh * sheet.get_stat("lifesteal_cap", 0.04))
	var dr := clampf(sheet.get_stat("damage_reduction", 0.0), 0.0, 0.8)
	var ev := clampf(sheet.get_stat("evade", 0.0), 0.0, 0.9)
	return (hp + SUSTAIN_SECONDS * (regen + ls)) / ((1.0 - dr) * (1.0 - ev))


## POWER from a full DPS and an effective HP.
static func power_from(dps: float, eff_hp: float) -> float:
	return sqrt(maxf(dps, 0.0) / BASE_DPS * maxf(eff_hp, 0.0) / BASE_EHP)


## Everything at once for a build: {dps, ehp, power}.
static func measure(weapons: Array, sheet: StatSheet) -> Dictionary:
	var d := full_dps(weapons, sheet)
	var e := ehp(sheet, d)
	return {"dps": d, "ehp": e, "power": power_from(d, e)}


## The run's hero now ({dps, ehp, power}; power 1 without a run), worked out at most once a frame.
static func now() -> Dictionary:
	var f := Engine.get_process_frames()
	if f == _cache_key and not _cache.is_empty():
		return _cache
	var ml := Engine.get_main_loop()
	var run: Node = (ml as SceneTree).root.get_node_or_null("Run") if ml is SceneTree else null
	if run == null:
		return {"dps": BASE_DPS, "ehp": BASE_EHP, "power": 1.0}
	_cache = measure(run.get("weapons"), run.get("player_sheet"))
	_cache_key = f
	return _cache


## The run's hero's power now (1 without a run).
static func current() -> float:
	return float(now()["power"])


## The run's full DPS on a boss now (Big Game Hunter in).
static func boss_dps_now() -> float:
	var ml := Engine.get_main_loop()
	var run: Node = (ml as SceneTree).root.get_node_or_null("Run") if ml is SceneTree else null
	if run == null:
		return 0.0
	return full_dps(run.get("weapons"), run.get("player_sheet"), true)


## Forget the frame's cache (a test that changes the build in one frame).
static func forget() -> void:
	_cache_key = -1
	_cache = {}
