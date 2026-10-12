extends GdUnitTestSuite

## Pass 67, lane M (Garry: "Movement Speed Hero: bring back the gazelle guy, do the speed thing but make it more powerful;
## look through the items and see if they still make sense"). Buck is back in play, seventh on the title: his charge
## (CharacterDef.momentum) climbs over 10 s to +80% speed, +60% attack damage and (new) +20% evade (Run._build_player_sheet,
## one "Momentum NN%" source); a hit that lands knocks off `hit_loss` of it (half; Player.take_damage), an evaded one none;
## he grows 1% move speed a level (Full Tilt) beside the flat -15% start; Ram's spikes grow 2 a level from the perk's
## `from` charge; Overdrive counts a gear of +5% attack damage every 5 s at full charge, five at most, gone on a landed
## hit. Pass 69 (lane BB, re-pinned on purpose; Garry: "No UI indicators of any kind"): the HUD's hero gauge and its
## words (MOMENTUM, RAM, OVERDRIVE, HEAT) are gone with Run.hero_gauge(); the charge shows on him, Heat on the ball.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var hud = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
var hits := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3) -> bool:
	return true
func max_speed() -> float:
	return 5.0
"""

const DT := 1.0 / 60.0

var _ram_from = null


func before_test() -> void:
	Save.data = Save._default()
	_ram_from = null


func after_test() -> void:
	# a test that moved Ram's `from` puts the loaded perk back as it was
	if _ram_from != null:
		Registry.perk("ram").params["from"] = _ram_from
	Run.set("heat", 0)
	# no charge left behind for a later suite's HUD (Run.end keeps the hero)
	Run.momentum = 0.0
	Run.momentum_def = {}
	Run.overdrive = 0
	Run.end()


func _start(id: String) -> void:
	Run.start(Registry.character(id), Registry.map("red_canyon"))


## The hero on the sand with his clock stopped: the tests tick his charge by hand.
func _hero(id: String = "buck") -> Player:
	_start(id)
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character(id))
	p.set_physics_process(false)
	p.hp = p.max_hp
	return p


func _tick(p: Player, seconds: float) -> void:
	for k in int(round(seconds / DT)):
		p._tick_momentum(DT)


## A hit that lands for sure: his evade is cancelled on the sheet he reads for that one hit.
func _land(p: Player) -> void:
	p.sheet.add_effects([Effect.make("evade", "add", -5.0, "player")], "test: no evade")
	p.invuln = 0.0
	p.hp = p.max_hp
	p.take_damage(5.0, p.global_position + Vector3(1, 0, 0), {"by": "test", "kind": "melee"})
	p.sheet.remove_source("test: no evade")
	p.refresh_stats()


## A hit he evades: evade far over the 90% cap, tried until the roll comes up (the charge and the gears put back after a
## one-in-ten hit that came through).
func _evade(p: Player) -> void:
	p.sheet.add_effects([Effect.make("evade", "add", 5.0, "player")], "test: evade")
	var keep_t: float = p._momentum_t
	var keep_m: float = Run.momentum
	var keep_o: float = p._over_t
	var keep_g: int = Run.overdrive
	for k in 60:
		p.invuln = 0.0
		p.hp = p.max_hp
		p.take_damage(5.0, p.global_position + Vector3(1, 0, 0), {"by": "test", "kind": "melee"})
		if p.last_outcome == "evaded":
			break
		p._momentum_t = keep_t
		Run.momentum = keep_m
		p._over_t = keep_o
		Run.overdrive = keep_g
	p.sheet.remove_source("test: evade")
	assert_str(p.last_outcome).is_equal("evaded")


func _sources(stat: String) -> Array:
	return Run.player_sheet.breakdown(stat).map(func(r: Dictionary) -> String: return str(r["source"]))


# ---------------------------------------------------------------- the charge

func test_the_charge_at_full_adds_speed_attack_damage_and_evade_under_one_source() -> void:
	_start("buck")
	var base_speed := Run.player_sheet.get_stat("move_speed", 0.0)
	var base_might := Run.player_sheet.get_stat("might", 0.0)
	# level 1: 3.6 x 0.85 (the flat -15%, kept) x 1.01 (Full Tilt's 1% a level); slower than anyone at the start
	assert_float(base_speed).is_equal_approx(3.6 * 0.85 * 1.01, 0.0001)
	assert_float(base_speed).is_less(3.6)
	assert_float(Run.player_sheet.get_stat("evade", 0.0)).is_equal(0.0)
	Run.momentum = 1.0
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(base_speed * 1.8, 0.0001)
	assert_float(Run.player_sheet.get_stat("might", 0.0)).is_equal_approx(base_might * 1.6, 0.0001)
	assert_float(Run.player_sheet.get_stat("evade", 0.0)).is_equal_approx(0.2, 0.0001)
	assert_array(_sources("evade")).contains(["Momentum 100%"])
	# half the charge, half of each, the same source on the pause sheet
	Run.momentum = 0.5
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("evade", 0.0)).is_equal_approx(0.1, 0.0001)
	assert_array(_sources("evade")).contains(["Momentum 50%"])
	assert_array(_sources("move_speed")).contains(["Momentum 50%"])
	# no charge, no source
	Run.momentum = 0.0
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(base_speed, 0.0001)
	assert_int(_sources("evade").filter(func(s: String) -> bool: return s.begins_with("Momentum")).size()).is_equal(0)


func test_a_block_without_evade_bonus_adds_no_evade() -> void:
	_start("astro")
	Run.momentum_def = {"ramp_seconds": 12.0, "speed_bonus": 0.6, "might_bonus": 0.5}
	Run.momentum = 1.0
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("evade", 0.0)).is_equal(0.0)
	assert_int(_sources("evade").filter(func(s: String) -> bool: return s.begins_with("Momentum")).size()).is_equal(0)
	Run.momentum = 0.0
	Run.momentum_def = {}


func test_a_hit_that_lands_takes_half_the_charge_and_an_evaded_one_keeps_it() -> void:
	var p := _hero()
	var ramp := float(Run.momentum_def["ramp_seconds"])
	assert_float(ramp).is_equal(10.0)
	assert_float(float(Run.momentum_def["hit_loss"])).is_equal(0.5)
	p._momentum_t = ramp
	Run.momentum = 1.0
	Run.rebuild_sheets()
	p.refresh_stats()
	_land(p)
	assert_str(p.last_outcome).is_equal("hit")
	assert_float(p._momentum_t).is_equal_approx(ramp * 0.5, 0.0001)
	assert_float(Run.momentum).is_equal_approx(0.5, 0.0001)
	# the sheet follows at once: half the evade
	assert_float(Run.player_sheet.get_stat("evade", 0.0)).is_equal_approx(0.1, 0.0001)
	# two in a row leave a quarter
	_land(p)
	assert_float(Run.momentum).is_equal_approx(0.25, 0.0001)
	# an evaded hit never touches it
	_evade(p)
	assert_float(p._momentum_t).is_equal_approx(ramp * 0.25, 0.0001)
	assert_float(Run.momentum).is_equal_approx(0.25, 0.0001)
	# full again 5 s after a half-loss (10 s ramp)
	p._momentum_t = ramp
	Run.momentum = 1.0
	_land(p)
	# (the sheet follows every quarter second: a little past the 5 s)
	_tick(p, 5.3)
	assert_float(Run.momentum).is_equal(1.0)


func test_hit_loss_1_is_the_old_full_reset() -> void:
	var p := _hero()
	Run.momentum_def = Run.momentum_def.duplicate()
	Run.momentum_def["hit_loss"] = 1.0
	p._momentum_t = 10.0
	Run.momentum = 1.0
	_land(p)
	assert_float(p._momentum_t).is_equal(0.0)
	assert_float(Run.momentum).is_equal(0.0)
	# and a block without the key reads 1.0 too
	Run.momentum_def.erase("hit_loss")
	p._momentum_t = 10.0
	Run.momentum = 1.0
	_land(p)
	assert_float(Run.momentum).is_equal(0.0)


func test_the_charge_always_reaches_exactly_full_on_the_sheet() -> void:
	var p := _hero()
	var ramp := float(Run.momentum_def["ramp_seconds"])
	# the sheet last followed at 0.985 (a half-loss shifts the quarter-second steps): the last step is under the 0.02 the
	# sync waits for, and before pass 67 the charge stayed at 0.985, under Ram's 0.99, for good
	p._momentum_t = ramp * 0.985
	Run.momentum = 0.985
	p._momentum_sync = 0.0
	_tick(p, 1.0)
	assert_float(Run.momentum).is_equal(1.0)
	# pass 69: no words for it under the slots (the hero's own look says it)
	assert_bool(HUD.buff_parts().any(func(s) -> bool: return str(s).begins_with("MOMENTUM"))).is_false()


# ---------------------------------------------------------------- Overdrive

func test_overdrive_counts_a_gear_every_5_s_at_full_folds_them_and_a_landed_hit_drops_them() -> void:
	var p := _hero()
	var ramp := float(Run.momentum_def["ramp_seconds"])
	# without the perk nothing counts
	p._momentum_t = ramp
	Run.momentum = 1.0
	Run.rebuild_sheets()
	_tick(p, 6.0)
	assert_int(Run.overdrive).is_equal(0)
	assert_bool(Run.add_perk("overdrive")).is_true()
	assert_int(Run.overdrive_gears()).is_equal(5)
	_tick(p, 4.9)
	assert_int(Run.overdrive).is_equal(0)
	_tick(p, 0.25)
	assert_int(Run.overdrive).is_equal(1)
	# x1.6 from the charge, x1.05 from one gear
	assert_float(Run.player_sheet.get_stat("might", 0.0)).is_equal_approx(1.6 * 1.05, 0.0001)
	assert_array(_sources("might")).contains(["Overdrive +5%"])
	# five gears at most: x1.6 x 1.25 = x2
	_tick(p, 40.0)
	assert_int(Run.overdrive).is_equal(5)
	assert_float(Run.overdrive_might()).is_equal_approx(0.25, 0.0001)
	assert_float(Run.player_sheet.get_stat("might", 0.0)).is_equal_approx(2.0, 0.0001)
	assert_array(_sources("might")).contains(["Overdrive +25%"])
	# an evaded hit keeps them
	_evade(p)
	assert_int(Run.overdrive).is_equal(5)
	# a hit that lands drops every gear (and half the charge, so counting waits for full again)
	_land(p)
	assert_int(Run.overdrive).is_equal(0)
	assert_float(p._over_t).is_equal(0.0)
	assert_float(Run.player_sheet.get_stat("might", 0.0)).is_equal_approx(1.3, 0.0001)
	assert_int(_sources("might").filter(func(s: String) -> bool: return s.begins_with("Overdrive")).size()).is_equal(0)
	# back to full in 5 s, the first gear 5 s after that
	_tick(p, 5.05)
	assert_int(Run.overdrive).is_equal(0)
	_tick(p, 5.2)
	assert_int(Run.overdrive).is_equal(1)


func test_overdrive_reads_its_numbers_from_the_perk() -> void:
	var od: PerkDef = Registry.perk("overdrive")
	assert_object(od).is_not_null()
	assert_str(od.hero).is_equal("buck")
	assert_str(od.special).is_equal("overdrive")
	assert_float(float(od.params["every"])).is_equal(5.0)
	assert_float(float(od.params["step"])).is_equal(0.05)
	assert_float(float(od.params["max"])).is_equal(0.25)
	assert_object(od.icon).is_not_null()
	_start("buck")
	# a run without the perk folds nothing, whatever the count says
	Run.overdrive = 3
	Run.rebuild_sheets()
	assert_float(Run.overdrive_might()).is_equal(0.0)
	assert_int(_sources("might").filter(func(s: String) -> bool: return s.begins_with("Overdrive")).size()).is_equal(0)
	# a new run starts with none
	_start("buck")
	assert_int(Run.overdrive).is_equal(0)


# ---------------------------------------------------------------- Ram

func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	var gs := GDScript.new()
	gs.source_code = FAKE_GAME
	gs.reload()
	g.set_script(gs)
	add_child(g)
	var hero := Node3D.new()
	var hs := GDScript.new()
	hs.source_code = FAKE_HERO
	hs.reload()
	hero.set_script(hs)
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


## A skeleton at the bite's reach beside him (right, or left with side -1), standing still, too tough to die of the
## spikes, its bite ready.
func _put_beside(em: EnemyManager, side: float = 1.0) -> int:
	var r: float = Registry.enemy("skeleton").radius
	var i := em.spawn("skeleton", Vector3((r + 0.3) * side, 0, 0), null, 1.0, 1.0, "", {})
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.size[i] = Registry.enemy("skeleton").size
	em.radius[i] = r
	em.vel[i] = Vector3.ZERO
	em.kb[i] = Vector3.ZERO
	em.hp[i] = 1000.0
	em.max_hp[i] = 1000.0
	em.contact_cd[i] = 0.0
	return i


func test_rams_spikes_grow_with_his_level() -> void:
	_start("buck")
	assert_bool(Run.add_perk("ram")).is_true()
	assert_float(Run.perk_param("ram", "per_level", 0.0)).is_equal(2.0)
	assert_float(Run.perk_param("ram", "from", 0.0)).is_equal(0.99)
	assert_float(Run.perk_param("ram", "flat", 0.0)).is_equal(12.0)
	assert_float(Run.perk_param("ram", "thorns_mult", 0.0)).is_equal(3.0)
	Run.momentum = 1.0
	Run.level = 10
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node = w["hero"]
	var i := _put_beside(em)
	em._physics_process(DT)
	# he is not touched; the creature takes 12 + 2 x 10 (no thorns held), less its own damage reduction
	assert_int(hero.hits).is_equal(0)
	assert_float(1000.0 - em.hp[i]).is_equal_approx((12.0 + 2.0 * 10.0) * (1.0 - em.dr[i]), 0.01)


func test_ram_starts_at_the_perks_from_charge() -> void:
	_start("buck")
	assert_bool(Run.add_perk("ram")).is_true()
	# under the default 0.99 the bite lands as any other
	Run.momentum = 0.9
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node = w["hero"]
	var i := _put_beside(em)
	em._physics_process(DT)
	assert_int(hero.hits).is_equal(1)
	assert_float(em.hp[i]).is_equal(1000.0)
	# Garry moves `from` to 0.85 in the JSON: the same charge is the wall now
	_ram_from = Registry.perk("ram").params.get("from", 0.99)
	Registry.perk("ram").params["from"] = 0.85
	var j := _put_beside(em, -1.0)
	em.contact_cd[i] = 10.0
	em._physics_process(DT)
	assert_int(hero.hits).is_equal(1)
	assert_float(em.hp[j]).is_less(1000.0)


# ---------------------------------------------------------------- the gauge (gone in pass 69)

func test_the_hud_has_no_hero_gauge_and_no_hero_words_pass69() -> void:
	# pass 69 (Garry: "No UI indicators of any kind please, the VFX effects on the hero himself are good enough"): no
	# gauge under the slots for him or for a ball, and none of his words (MOMENTUM, RAM, OVERDRIVE) or the ball's (HEAT)
	_start("buck")
	Run.momentum = 1.0
	Run.add_perk("ram")
	Run.add_perk("overdrive")
	Run.overdrive = 3
	Run.rebuild_sheets()
	var wd := WeaponDef.new()
	wd.id = "t69_ball"
	wd.max_level = 5
	wd.params = {"catch": {"heat_max": 8, "heat_per": 0.05}}
	Run.weapons.append(WeaponInstance.new(wd, 1))
	Run.set("heat", 4)
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	hud.tick(0.0)
	assert_object(hud.find_child("HeroGauge", true, false)).is_null()
	assert_bool(Run.has_method("hero_gauge")).is_false()
	for s in HUD.buff_parts():
		for w in ["MOMENTUM", "RAM", "OVERDRIVE", "HEAT"]:
			assert_bool(str(s).begins_with(w)).override_failure_message(str(s)).is_false()
	# the column hangs from the slots' foot
	assert_float(hud._buffs.position.y).is_equal_approx(hud._slots_bottom + HUD.BUFF_GAP, 0.5)
	Run.set("heat", 0)
	Run.weapons.clear()


# ---------------------------------------------------------------- the words and the roster

func test_bucks_trait_says_the_level_rule_then_his_charge() -> void:
	var buck: CharacterDef = Registry.character("buck")
	assert_str(buck.trait_name).is_equal("Full Tilt")
	var t := TextGen.hero_trait(buck)
	assert_str(t).starts_with("Gain 1% move speed per level. ")
	assert_str(t).ends_with(buck.trait_text)
	assert_str(buck.trait_text).is_equal("Starts 15% slower. While he is not hit his charge climbs over 10 s to +80% speed, +60% attack damage and +20% evade chance; a hit that lands knocks off half of it.")
	assert_str(TextGen.hero_trait_now(buck, 10)).is_equal("+10% move speed at level 10")
	# a hero with a rule and no special reads the rule alone, as before
	assert_str(TextGen.hero_trait(Registry.character("drifter"))).is_equal("Gain 1% crit chance per level.")
	# the plaque shows what a level gives
	var ts = load("res://ui/TitleScreen.gd").new()
	var rows: Array = ts._stats_of(buck)
	assert_str(str(rows[0][0])).is_equal("+1%")
	assert_str(str(rows[0][1])).is_equal("SPEED / LV")
	ts.free()


func test_buck_is_back_in_play_seventh_and_his_kit_is_whole() -> void:
	var buck: CharacterDef = Registry.character("buck")
	assert_bool(buck.hidden).is_false()
	# pass 69 (lane UI): a hero to buy (survive 15 minutes, then 500 gold), shown on the title, not hidden
	assert_str(buck.availability).is_equal("purchase")
	assert_int(buck.order).is_equal(7)
	assert_bool(Registry.sorted_characters().has(buck)).is_true()
	assert_str(Registry.playable_character("buck").id).is_equal("buck")
	# the flat -15% stays beside the level trait; pass 69 (Jeżyk): he lands with the Frisbee, his favourite is Salt
	assert_float(buck.trait_effects[0].value).is_equal_approx(-0.15, 0.0001)
	assert_int(buck.level_trait.size()).is_equal(1)
	assert_str((buck.level_trait[0] as Effect).stat).is_equal("move_speed")
	assert_float((buck.level_trait[0] as Effect).value).is_equal_approx(0.01, 0.00001)
	assert_str(buck.start_weapon).is_equal("frisbee")
	assert_str(buck.favourite_weapon).is_equal("salt")
	assert_str(Registry.start_weapon_for(buck).id).is_equal("frisbee")
	# the charge's numbers
	assert_float(float(buck.momentum["ramp_seconds"])).is_equal(10.0)
	assert_float(float(buck.momentum["speed_bonus"])).is_equal_approx(0.8, 0.0001)
	assert_float(float(buck.momentum["might_bonus"])).is_equal_approx(0.6, 0.0001)
	assert_float(float(buck.momentum["evade_bonus"])).is_equal_approx(0.2, 0.0001)
	assert_float(float(buck.momentum["hit_loss"])).is_equal_approx(0.5, 0.0001)
	# his two perks and his one hero mutation, on his favourite, offered on his runs
	var perks: Array = Registry.perks_of("buck").map(func(pk: PerkDef) -> String: return pk.id)
	assert_array(perks).contains_exactly_in_any_order(["overdrive", "ram"])
	var own: Array = Registry.hero_mutations("buck")
	assert_int(own.size()).is_equal(1)
	# pass 69: Salt Flats on his Salt; Drum Roll (his Tommy Gun's) is hidden, kept
	assert_str((own[0] as MutationDef).id).is_equal("salt_flats")
	assert_str((own[0] as MutationDef).weapon).is_equal("salt")
	assert_bool(Registry.is_hidden(Registry.perk("ram"))).is_false()
	assert_bool(Registry.is_hidden(Registry.mutation("drum_roll"))).is_true()
	_start("buck")
	var tg := Run.add_weapon(Registry.weapon("salt"), 1)
	assert_object(tg).is_not_null()
	var ids: Array = Run.open_mutations(tg).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(ids.has("salt_flats")).is_true()
