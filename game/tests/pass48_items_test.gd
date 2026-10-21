## Pass 48, the items lane (Garry's sixth list): six new passive items with their data and their mechanisms on the Run,
## the Player and the pickups (Phoenix Feather's one free revive, never offered again; Skedaddle's quiet boost after a
## hit; Hot Streak's kills since the last hit, in steps of a twentieth; Gas Mask's point of damage reduction a poisoned
## creature, capped; Loose Change's coin that lands a few steps away and lies out of the magnet's reach a second; Powder
## Keg's chance and its own source), Desperado's card text, every passive item at most five levels and every line four,
## and the weapons' five levels wherever a level is offered.
extends GdUnitTestSuite

const NEW := ["phoenix_feather", "skedaddle", "powder_keg", "loose_change", "gas_mask", "hot_streak"]
## id -> [rarity, weight, max_level, {stat: its value at the top level}]
const DATA := {
	# re-pinned in pass 95 (lane PASSIVES): the items climb the rarity ladder (uncommon 5 levels, rare 4, epic 3) and
	# their numbers were redistributed (tools/passive_ladder.py); Phoenix Feather climbs to a second life
	"phoenix_feather": ["uncommon", 6.0, 5, {"phoenix_revive": 2.0}],
	"skedaddle": ["rare", 7.0, 4, {"hurt_speed": 0.36, "hurt_speed_seconds": 3.1}],
	"powder_keg": ["uncommon", 8.0, 5, {"powder_keg_chance": 0.155}],
	"loose_change": ["uncommon", 8.0, 5, {"coin_on_hit": 0.68}],
	"gas_mask": ["epic", 5.0, 3, {"gas_mask_cap": 0.3}],
	"hot_streak": ["rare", 6.0, 4, {"kill_might": 0.21}],
}
## the player-facing line of each, word for word (Garry's brief)
const TEXT := {
	# (pass 95: the lines name the ladder's numbers)
	"phoenix_feather": "Two seconds after you fall, you get back up with the revive's blast, once a run. Each rung raises the health you rise with; Evolved: a second life.",
	"skedaddle": "After a hit, run 25% faster for 2 s (+3% and +0.3 s a rung, Evolved +5% and +0.5 s).",
	"powder_keg": "A kill has a 6.5% chance to blow up (+2% a rung, Evolved +3%): a quarter of its max health to everything within 2.4 m, and a shove. Kills from the blast never blow.",
	"loose_change": "A hit has a 32% chance to knock a coin worth 10 gold out of you (+8% a rung, Evolved +12%). It lands a few steps away: go and get it.",
	"gas_mask": "1% damage reduction for every poisoned enemy, up to 12% (20% at level 2, 30% once Evolved).",
	"hot_streak": "Kills make you stronger for the rest of the run: +7% attack damage per 1,000 kills (more each rung), up to +100%.",
}
const DESPERADO_TEXT := "The more you are hurt, the harder you hit: +1.6% attack damage for every 10% of health you are missing at level 1 (+16% near death), up to +51% once Evolved."

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	# nothing unlocked, no Mirror ranks: the base numbers
	Save.data = Save._default()


func after_test() -> void:
	Run.player_sheet.remove_source("test")
	Run.banished.clear()
	Run.arena = false
	Run.poisoned_alive = 0
	Run.end()


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _ids(list: Array) -> Array:
	return list.map(func(d: ContentDef) -> String: return d.id)


## A fake game with a fake hero at the origin and a real PickupManager (no map: the sand is flat at 0).
func _pickups() -> Dictionary:
	_start()
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var pm: PickupManager = auto_free(PickupManager.new())
	pm.game = g
	add_child(pm)
	g.pickups = pm
	return {"g": g, "hero": hero, "pm": pm}


## The real hero (Astro) at full health, on the run's sheet.
func _hero() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.hp = p.max_hp
	return p


## The rebuild Desperado, Steady Hand and Hot Streak wait for (on real time), now.
func _follow() -> void:
	Run._desperado_built_ms = -100000
	Run.tick_timed()


# ---------------------------------------------------------------- the six items

func test_six_new_passive_items_with_their_numbers_and_words() -> void:
	assert_array(Registry.problems).is_empty()
	for id: String in NEW:
		var p: PassiveDef = Registry.passive(id)
		assert_object(p).override_failure_message(id + " is missing").is_not_null()
		var want: Array = DATA[id]
		assert_str(p.rarity).override_failure_message(id + " rarity").is_equal(str(want[0]))
		assert_float(p.weight).override_failure_message(id + " weight").is_equal(float(want[1]))
		assert_int(p.max_level).override_failure_message(id + " levels").is_equal(int(want[2]))
		# a passive item: no line, no evolution, no quest, offered from stage 1
		assert_bool(p.is_line()).is_false()
		assert_str(p.evolves_into).is_empty()
		assert_bool(p.hidden).is_false()
		assert_int(p.from_stage).is_less_equal(1)
		assert_object(Registry.quest_for("passive", id)).override_failure_message(id + " is locked").is_null()
		assert_bool(Registry.unlocked_passives().has(p)).is_true()
		assert_bool(_ids(Registry.sorted_passives_only()).has(id)).is_true()
		# the card's line, the flavour, the placeholder and the painter's prompt
		assert_str(p.text).is_equal(str(TEXT[id]))
		assert_str(p.flavour).is_not_empty()
		assert_str(str(p.placeholder.get("color", ""))).is_not_empty()
		assert_str(str(p.placeholder.get("glyph", ""))).is_not_empty()
		var d := JsonContent.load_json("res://content/passives/%s/%s.json" % [id, id])
		assert_str(str(d.get("art_prompt", ""))).override_failure_message(id + " has no art prompt").is_not_empty()
		assert_bool(bool(d.get("repeat_last_level", false))).is_true()
		# the top level's numbers on the sheet, and not a level past it
		_start()
		for k in range(p.max_level):
			assert_bool(Run.add_or_level_passive(id)).override_failure_message("%s level %d" % [id, k + 1]).is_true()
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id + " past its top").is_false()
		var top: Dictionary = want[3]
		for stat: String in top.keys():
			assert_float(Run.player_sheet.get_stat(stat, 0.0)).override_failure_message("%s %s" % [id, stat]).is_equal_approx(float(top[stat]), 0.0001)
		Run.end()
	# the first levels (pass 95: higher than the brief's, the ladder's first rung: Skedaddle +25% for 2 s, Powder Keg 6.5%,
	# Loose Change 32%), then the step
	_start()
	var at := {"skedaddle": ["hurt_speed", 0.25], "powder_keg": ["powder_keg_chance", 0.065], "loose_change": ["coin_on_hit", 0.32],
		"gas_mask": ["gas_mask_cap", 0.12], "hot_streak": ["kill_might", 0.07], "phoenix_feather": ["phoenix_revive", 1.0]}
	for id: String in at.keys():
		Run.add_or_level_passive(id)
		assert_float(Run.player_sheet.get_stat(str(at[id][0]), 0.0)).override_failure_message(id).is_equal_approx(float(at[id][1]), 0.0001)
	assert_float(Run.player_sheet.get_stat("hurt_speed_seconds", 0.0)).is_equal_approx(2.0, 0.0001)
	Run.add_or_level_passive("skedaddle")
	assert_float(Run.player_sheet.get_stat("hurt_speed", 0.0)).is_equal_approx(0.28, 0.0001)
	assert_float(Run.player_sheet.get_stat("hurt_speed_seconds", 0.0)).is_equal_approx(2.3, 0.0001)
	Run.add_or_level_passive("powder_keg")
	assert_float(Run.player_sheet.get_stat("powder_keg_chance", 0.0)).is_equal_approx(0.085, 0.0001)
	Run.add_or_level_passive("loose_change")
	assert_float(Run.player_sheet.get_stat("coin_on_hit", 0.0)).is_equal_approx(0.40, 0.0001)


func test_the_new_items_read_well_on_cards_pause_and_collection() -> void:
	for id: String in NEW:
		var p: PassiveDef = Registry.passive(id)
		var lines: Array = [p.text, TextGen.passive_description(p, 1), TextGen.passive_description(p, p.max_level),
			TextGen.next_level_text(p, 1), TextGen.next_level_text(p, p.max_level)]
		print("pass48 text  %-16s | %s" % [p.display_name, " | ".join(lines)])
		for s: String in lines:
			assert_bool(s.contains("_")).override_failure_message(id + " shows a raw stat: " + s).is_false()
			assert_bool(s.to_lower().contains("rank")).override_failure_message(id + " says rank: " + s).is_false()
			# each starts a sentence: a capital, a digit or a sign
			var c0 := s.substr(0, 1)
			assert_bool(c0 == c0.to_upper()).override_failure_message(id + " starts small: " + s).is_true()
	# (pass 95: the first level reads plainly, a higher one names its rung, the next level its rung)
	assert_str(TextGen.passive_description(Registry.passive("phoenix_feather"), 1)).is_equal("+1 free revive.")
	assert_str(TextGen.next_level_text(Registry.passive("phoenix_feather"), 1)).is_equal("Next level (Rare): +15% health on revive")
	assert_str(TextGen.next_level_text(Registry.passive("phoenix_feather"), 5)).is_equal("Maxed.")
	assert_str(TextGen.passive_description(Registry.passive("skedaddle"), 1)).is_equal(
		"+25% move speed after a hit, +2 s boost after a hit.")
	assert_str(TextGen.passive_description(Registry.passive("skedaddle"), 4)).is_equal(
		"Level 4 (Evolved): +36% move speed after a hit, +3.1 s boost after a hit total.")
	assert_str(TextGen.passive_description(Registry.passive("powder_keg"), 5)).is_equal("Level 5 (Evolved): +15.5% chance a kill blows up total.")
	assert_str(TextGen.passive_description(Registry.passive("loose_change"), 5)).is_equal("Level 5 (Evolved): +68% chance a hit knocks a coin out total.")
	assert_str(TextGen.passive_description(Registry.passive("hot_streak"), 2)).is_equal(
		"Level 2 (Epic): +11% attack damage per 1,000 kills total.")
	# a ceiling says "up to", and the line still starts with a capital
	assert_str(TextGen.passive_description(Registry.passive("gas_mask"), 1)).is_equal("Up to +12% damage reduction from poisoned enemies.")
	assert_str(TextGen.passive_description(Registry.passive("gas_mask"), 3)).is_equal(
		"Level 3 (Evolved): up to +30% damage reduction from poisoned enemies total.")
	assert_str(TextGen.describe_effect(Effect.make("gas_mask_cap", "add", 0.08, "player"))).is_equal("up to +8% damage reduction from poisoned enemies")
	assert_str(TextGen.describe_effect(Effect.make("coin_on_hit", "add", 0.1, "player"))).is_equal("+10% chance a hit knocks a coin out")
	assert_str(TextGen.describe_effect(Effect.make("phoenix_revive", "add", 1.0, "player"))).is_equal("+1 free revive")
	# one level and no more for what has no levels (a mutation, a perk): no eight-level default left
	assert_str(TextGen.next_level_text(Registry.mutation("dragons_breath"), 1)).is_equal("Maxed.")


func test_desperado_says_what_it_does() -> void:
	var d: PassiveDef = Registry.passive("desperado")
	assert_str(d.text).is_equal(DESPERADO_TEXT)
	# the numbers it promises (pass 95): +1.6% a tenth at level 1, +51% near death once Evolved (level 4)
	assert_float(float((d.effects_at_level(1)[0] as Effect).value)).is_equal_approx(0.16, 0.0001)
	_start()
	for k in range(4):
		Run.add_or_level_passive("desperado")
	Run.note_hp(0.0, 100.0)
	assert_float(Run.desperado_might()).is_equal_approx(0.51, 0.0001)
	assert_str(TextGen.passive_description(d, 1)).starts_with("Up to +16% attack damage as health falls")
	# the comment beside TextGen.PREFIX no longer says +30%
	var src := FileAccess.get_file_as_string("res://core/systems/TextGen.gd")
	assert_bool(src.contains("up to +30% attack damage")).is_false()


# ---------------------------------------------------------------- the levels

func test_passive_items_top_out_at_five_and_lines_at_four() -> void:
	for p: PassiveDef in Registry.passives.values():
		if p.is_evolved():
			assert_int(p.max_level).override_failure_message(p.id + " (evolved)").is_equal(1)
		elif p.is_line():
			assert_int(p.max_level).override_failure_message(p.id + " (line)").is_equal(4)
		else:
			# Garry's item 13: a pick-up and four upgrades at most; pass 95: the rarity ladder (common 6 .. epic 3)
			assert_int(p.max_level).override_failure_message(p.id + " (passive item)").is_equal(PassiveDef.ladder_levels(p.rarity))
	_start()
	for k in range(5):
		assert_bool(Run.add_or_level_passive("loose_change")).is_true()
	assert_bool(Run.add_or_level_passive("loose_change")).is_false()
	assert_int(Run.passive_level("loose_change")).is_equal(5)
	for c: Dictionary in Run.chest_candidates():
		assert_str(str(c["id"])).is_not_equal("loose_change")


func test_weapon_levels_stop_at_five_wherever_they_are_offered() -> void:
	for w: WeaponDef in Registry.weapons.values():
		if not w.is_evolution:
			assert_int(w.max_level).override_failure_message(w.id).is_equal(5)
	_start()
	var pea: WeaponDef = Registry.weapon("peashooter")
	Run.add_weapon(pea, 4)
	var seen := false
	for k in range(300):
		for c in CardPool.level_up_offer(4):
			if str(c["id"]) == "peashooter":
				seen = true
				assert_int(int(c["level_from"])).is_equal(4)
				assert_int(int(c["level_to"])).is_equal(5)
		if seen:
			break
	assert_bool(seen).override_failure_message("a level-4 Peashooter was never offered its fifth").is_true()
	Run.level_weapon("peashooter")
	Run.level_weapon("peashooter")
	assert_int(Run.weapon_instance("peashooter").level).is_equal(5)
	for k in range(60):
		for c in CardPool.level_up_offer(4):
			assert_str(str(c["id"])).override_failure_message("a maxed weapon offered").is_not_equal("peashooter")
	for c: Dictionary in Run.chest_candidates():
		assert_str(str(c["id"])).is_not_equal("peashooter")
	# the debug hand and a tool's launch level: never past five
	assert_int(Run.debug_set_item("weapon", "boomstick", 8)).is_equal(5)
	assert_int(Run.weapon_instance("boomstick").level).is_equal(5)
	assert_int(Run.add_weapon(Registry.weapon("tommy_gun"), 8).level).is_equal(5)
	assert_int(Run.add_weapon(Registry.weapon("molotov"), 0).level).is_equal(1)
	# the Stranger: a new weapon at level 2, a held one a level up, never past five
	for k in range(300):
		var o := Run.stranger_offer()
		if o.is_empty() or str(o["type"]) != "weapon":
			continue
		var wd: WeaponDef = o["def"]
		assert_int(int(o["level_to"])).is_less_equal(wd.max_level)
		if bool(o["is_new"]):
			assert_int(int(o["level_to"])).is_equal(2)
		else:
			assert_int(int(o["level_to"])).is_equal(int(o["level_from"]) + 1)


# ---------------------------------------------------------------- Phoenix Feather

func test_phoenix_feather_is_one_revive_and_never_offered_again() -> void:
	# re-pinned in pass 95 (lane PASSIVES): the feather climbs the ladder like every item (its rungs raise the health he
	# rises with, Evolved is a second life: pass95_PASSIVES_test), so a held one is offered as an upgrade; a spent one at
	# its top is never offered again
	_start()
	var ph: PassiveDef = Registry.passive("phoenix_feather")
	assert_bool(Run.phoenix_ready()).is_false()
	# not held yet: a chest may hold it, new
	var in_chest := false
	for c: Dictionary in Run.chest_candidates():
		if str(c["id"]) == "phoenix_feather":
			in_chest = true
			assert_bool(bool(c["is_new"])).is_true()
	assert_bool(in_chest).is_true()
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_true()
	assert_int(Run.passive_level("phoenix_feather")).is_equal(1)
	assert_bool(Run.phoenix_ready()).is_true()
	assert_bool(Run.item_spent(ph)).is_false()
	# held: its next rungs are on the table as upgrades, never as a new item
	for c: Dictionary in Run.chest_candidates():
		if str(c["id"]) == "phoenix_feather":
			assert_bool(bool(c["is_new"])).is_false()
			assert_int(int(c["level_from"])).is_equal(1)
	# spent: once a run at level 1, kept in the build (the UI says SPENT)
	Run.use_phoenix()
	assert_bool(Run.phoenix_used).is_true()
	assert_bool(Run.phoenix_ready()).is_false()
	assert_bool(Run.item_spent(ph)).is_true()
	assert_bool(Run.item_spent(Registry.passive("magnet"))).is_false()
	assert_bool(Run.held_passives().has("phoenix_feather")).is_true()
	# at its top and spent: no card, no chest, no Stranger (he sells rare and up)
	Run.debug_set_item("passive", "phoenix_feather", ph.max_level)
	Run.use_phoenix()
	assert_bool(Run.phoenix_used).is_true()
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_false()
	for k in range(100):
		for c in CardPool.level_up_offer(4):
			assert_str(str(c["id"])).is_not_equal("phoenix_feather")
	for c: Dictionary in Run.chest_candidates():
		assert_str(str(c["id"])).is_not_equal("phoenix_feather")
	for k in range(100):
		var o := Run.stranger_offer()
		if not o.is_empty():
			assert_str(str(o["id"])).is_not_equal("phoenix_feather")
	# a rebuild keeps it spent
	Run.rebuild_sheets()
	assert_bool(Run.phoenix_ready()).is_false()
	# a new run has it fresh
	_start()
	assert_bool(Run.phoenix_used).is_false()
	assert_bool(Run.item_spent(ph)).is_false()


# ---------------------------------------------------------------- Skedaddle

func test_skedaddle_runs_after_a_hit_quietly_and_a_new_hit_refreshes_it() -> void:
	_start()
	var speed := Run.player_sheet.get_stat("move_speed", 0.0)
	assert_bool(Run.skedaddle()).is_false()
	assert_float(Run.skedaddle_left()).is_equal(0.0)
	assert_bool(Run.timed.is_empty()).is_true()
	Run.add_or_level_passive("skedaddle")
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed, 0.0001)
	# a hit: 25% faster for 2 s (pass 95's first rung), a quiet boost
	assert_bool(Run.skedaddle()).is_true()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.25, 0.0001)
	assert_float(Run.skedaddle_left()).is_equal_approx(2.0, 0.0001)
	var mine: Array = Run.timed.filter(func(t: Dictionary) -> bool: return t["id"] == Run.SKEDADDLE)
	assert_int(mine.size()).is_equal(1)
	assert_bool(bool(mine[0]["quiet"])).is_true()
	assert_str(str(mine[0]["label"])).is_equal("SKEDADDLE")
	# a second later another hit: the clock starts again, the speed is not stacked
	Run.elapsed += 1.0
	assert_float(Run.skedaddle_left()).is_equal_approx(1.0, 0.0001)
	assert_bool(Run.skedaddle()).is_true()
	assert_float(Run.skedaddle_left()).is_equal_approx(2.0, 0.0001)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.25, 0.0001)
	assert_int(Run.timed.filter(func(t: Dictionary) -> bool: return t["id"] == Run.SKEDADDLE).size()).is_equal(1)
	# two rungs later the next hit runs faster and longer (+3% and +0.3 s a rung)
	Run.add_or_level_passive("skedaddle")
	Run.add_or_level_passive("skedaddle")
	assert_bool(Run.skedaddle()).is_true()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.31, 0.0001)
	assert_float(Run.skedaddle_left()).is_equal_approx(2.6, 0.0001)
	assert_int(Run.timed.filter(func(t: Dictionary) -> bool: return t["id"] == Run.SKEDADDLE).size()).is_equal(1)
	# the buffs' clock: a boss fight (held_time) counts too
	Run.held_time += 1.0
	assert_float(Run.skedaddle_left()).is_equal_approx(1.6, 0.0001)
	# it runs out without a "wore off" toast, and the speed is back
	Run.elapsed += 2.0
	assert_array(Run.tick_timed()).is_empty()
	assert_float(Run.skedaddle_left()).is_equal(0.0)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed, 0.0001)
	# Barrel Rush (the same kind of boost) runs beside it on its own clock
	Run.add_or_level_passive("barrel_rush")
	assert_bool(Run.barrel_rush()).is_true()
	assert_bool(Run.skedaddle()).is_true()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.3 * 1.31, 0.0001)
	assert_float(Run.boost_left(Run.BARREL_RUSH)).is_equal_approx(4.0, 0.0001)
	assert_float(Run.skedaddle_left()).is_equal_approx(2.6, 0.0001)


# ---------------------------------------------------------------- Gas Mask

func test_gas_mask_turns_poisoned_creatures_into_damage_reduction() -> void:
	_start()
	Run.poisoned_alive = 30
	assert_float(Run.gas_mask_dr()).is_equal(0.0)
	Run.add_or_level_passive("gas_mask")
	# a point a poisoned creature, up to 12% at level 1 (pass 95), 30% once Evolved (level 3)
	for pair in [[0, 0.0], [1, 0.01], [3, 0.03], [12, 0.12], [30, 0.12]]:
		Run.poisoned_alive = int(pair[0])
		assert_float(Run.gas_mask_dr()).override_failure_message("%d poisoned" % int(pair[0])).is_equal_approx(float(pair[1]), 0.00001)
	for k in range(2):
		Run.add_or_level_passive("gas_mask")
	Run.poisoned_alive = 25
	assert_float(Run.gas_mask_dr()).is_equal_approx(0.25, 0.00001)
	Run.poisoned_alive = 55
	assert_float(Run.gas_mask_dr()).is_equal_approx(0.3, 0.00001)
	# the hero takes it off every hit, on top of his own reduction
	var p := _hero()
	var own := Run.player_sheet.get_stat("damage_reduction", 0.0)
	Run.poisoned_alive = 12
	p.take_damage(50.0, Vector3(3, 0, 0))
	assert_float(p.max_hp - p.hp).is_equal_approx(50.0 * (1.0 - own - 0.12), 0.001)
	# none poisoned: his own only
	Run.poisoned_alive = 0
	p.hp = p.max_hp
	p.invuln = 0.0
	p.take_damage(50.0, Vector3(3, 0, 0))
	assert_float(p.max_hp - p.hp).is_equal_approx(50.0 * (1.0 - own), 0.001)
	# never past the 80% cap
	Run.player_sheet.add_effects([Effect.make("damage_reduction", "add", 0.7, "player")], "test")
	Run.poisoned_alive = 55
	p.hp = p.max_hp
	p.invuln = 0.0
	p.take_damage(50.0, Vector3(3, 0, 0))
	assert_float(p.max_hp - p.hp).is_equal_approx(50.0 * 0.2, 0.001)


# ---------------------------------------------------------------- Hot Streak

func test_hot_streak_keeps_every_kill_made_while_held_for_the_rest_of_the_run() -> void:
	# pass 49 (Garry: like Megabonk's Demonic Soul, +100% only after a lot of kills): +5% attack damage per 1,000 kills
	# a level, in whole percents, never taken away by a hit, +100% at most
	_start()
	var base := Run.player_sheet.get_stat("might", 1.0)
	# kills before it is held count for nothing
	for k in range(150):
		Run.add_kill("goblin", "peashooter")
	assert_int(Run.streak).is_equal(0)
	assert_float(Run.hot_streak_bonus()).is_equal(0.0)
	Run.add_or_level_passive("hot_streak")
	assert_float(Run.player_sheet.get_stat("kill_might", 0.0)).is_equal_approx(0.07, 0.00001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base, 0.0001)
	# level 1 (pass 95: +7% per 1,000): a percent every 143 kills; 142 kills are still nothing
	for k in range(142):
		Run.add_kill("goblin", "peashooter")
	assert_int(Run.streak).is_equal(142)
	assert_int(Run.streak_bucket).is_equal(0)
	assert_bool(Run._streak_dirty).is_false()
	Run.add_kill("goblin", "peashooter")
	assert_int(Run.streak_bucket).is_equal(1)
	assert_bool(Run._streak_dirty).is_true()
	_follow()
	assert_bool(Run._streak_dirty).is_false()
	assert_float(Run.hot_streak_bonus()).is_equal_approx(0.01, 0.00001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 1.01, 0.0001)
	# within a percent nothing asks for a rebuild
	Run.add_kill("goblin", "peashooter")
	assert_bool(Run._streak_dirty).is_false()
	# a hit takes nothing away: there is nothing that ends it (Game._on_player_hit ends only Crescendo)
	assert_bool(Run.has_method("reset_hot_streak")).is_false()
	Run.reset_crescendo()
	assert_int(Run.streak).is_equal(144)
	# 1,000 kills at level 1: +7%, named on the sheet
	for k in range(856):
		Run.add_kill("goblin", "peashooter")
	_follow()
	assert_float(Run.hot_streak_bonus()).is_equal_approx(0.07, 0.00001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 1.07, 0.0001)
	var named := false
	for r in Run.player_sheet.breakdown("might"):
		if str(r["source"]) == "Hot Streak +7%":
			named = true
	assert_bool(named).is_true()
	# a rebuild for any other reason keeps it; a level more counts every kill again at the new rate at once
	Run.add_or_level_passive("magnet")
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 1.07, 0.0001)
	for k in range(3):
		Run.add_or_level_passive("hot_streak")
	assert_float(Run.player_sheet.get_stat("kill_might", 0.0)).is_equal_approx(0.21, 0.00001)
	assert_float(Run.hot_streak_bonus()).is_equal_approx(0.21, 0.00001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 1.21, 0.0001)
	# Evolved (level 4): +100% at 4,762 kills, and no further
	for k in range(3800):
		Run.add_kill("goblin", "peashooter")
	_follow()
	assert_int(Run.streak).is_equal(4800)
	assert_float(Run.hot_streak_bonus()).is_equal_approx(1.0, 0.00001)
	for k in range(500):
		Run.add_kill("goblin", "peashooter")
	_follow()
	assert_float(Run.hot_streak_bonus()).is_equal_approx(Run.STREAK_CAP, 0.00001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 2.0, 0.0001)
	# a new run starts with none
	_start()
	assert_int(Run.streak).is_equal(0)
	assert_int(Run.streak_bucket).is_equal(0)
	assert_float(Run.hot_streak_bonus()).is_equal(0.0)


# ---------------------------------------------------------------- Powder Keg

func test_powder_keg_rolls_on_its_own_stat_and_records_as_itself() -> void:
	_start()
	assert_float(Run.player_sheet.get_stat("powder_keg_chance", 0.0)).is_equal(0.0)
	Run.add_or_level_passive("powder_keg")
	assert_float(Run.player_sheet.get_stat("powder_keg_chance", 0.0)).is_equal_approx(0.065, 0.0001)
	for k in range(4):
		Run.add_or_level_passive("powder_keg")
	assert_float(Run.player_sheet.get_stat("powder_keg_chance", 0.0)).is_equal_approx(0.155, 0.0001)
	# the blast is the item's own source (Results names it by the item): a quarter of the body's health within 2.4 m (Game's
	# constants read off its script, so this suite compiles without the whole game)
	var consts: Dictionary = (load("res://game/Game.gd") as GDScript).get_script_constant_map()
	assert_str(str(consts["POWDER_KEG"])).is_equal("powder_keg")
	assert_object(Registry.passive(str(consts["POWDER_KEG"]))).is_not_null()
	assert_float(float(consts["KEG_RADIUS"])).is_equal_approx(2.4, 0.0001)
	assert_float(float(consts["KEG_FRAC"])).is_equal_approx(0.25, 0.0001)
	# Game reads the stats these items give by their names
	var game_src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(game_src.contains("get_stat(\"powder_keg_chance\"")).is_true()
	assert_bool(game_src.contains("get_stat(\"coin_on_hit\"")).is_true()


# ---------------------------------------------------------------- Loose Change

func test_a_tossed_coin_lands_a_few_steps_away_and_waits_a_second() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	# a magnet that would reach it where it lands
	Run.player_sheet.add_effects([Effect.make("magnet", "add", 5.0, "player")], "test")
	var g0: int = Run.run_gold
	var i := pm.toss_coin(hero.global_position)
	assert_int(i).is_greater_equal(0)
	assert_int(pm.kind[i]).is_equal(PickupManager.KIND_COIN)
	assert_float(pm.value[i]).is_equal(10.0)
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_TOSS)
	var top := 0.0
	var t := 0.0
	while pm.phase[i] == PickupManager.PHASE_TOSS and t < 2.0:
		pm._physics_process(DT)
		t += DT
		top = maxf(top, pm.pos[i].y)
		assert_int(pm.flying[i]).override_failure_message("called while in the air").is_equal(0)
	# an arc, down after its flight, 2 to 3.5 m from him
	assert_float(t).is_between(PickupManager.TOSS_TIME - 0.001, PickupManager.TOSS_TIME + DT + 0.001)
	assert_float(top).is_greater(PickupManager.TOSS_FROM + 0.3)
	var d := _flat(pm.pos[i] - hero.global_position)
	assert_float(d).is_between(PickupManager.TOSS_MIN - 0.001, PickupManager.TOSS_MAX + 0.001)
	assert_float(pm.hold[i]).is_equal_approx(PickupManager.TOSS_HOLD, 0.0001)
	# a second well inside the magnet's reach and nothing calls it
	var held := 0.0
	while held < PickupManager.TOSS_HOLD - 2.0 * DT:
		pm._physics_process(DT)
		held += DT
		assert_int(pm.flying[i]).override_failure_message("pulled %.2f s after it landed" % held).is_equal(0)
		assert_int(Run.run_gold).is_equal(g0)
	# then it is a coin like any other: the magnet takes it, and it pays on arrival
	var t2 := 0.0
	while pm.alive[i] == 1 and t2 < 3.0:
		pm._physics_process(DT)
		t2 += DT
	assert_int(pm.alive[i]).is_equal(0)
	assert_float(t2).is_less(1.5)
	var pay: int = 10 * maxi(int(round(Run.stage_mult())), 1)
	assert_int(Run.run_gold - g0).is_equal(int(round(pay * Run.player_sheet.get_stat("greed", 1.0))))


func test_a_tossed_coin_is_his_when_he_walks_onto_it_or_a_vacuum_calls() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var hero: Node3D = w["hero"]
	var i := pm.toss_coin(hero.global_position)
	for k in range(int(ceil(PickupManager.TOSS_TIME / DT)) + 1):
		pm._physics_process(DT)
	assert_int(pm.phase[i]).is_equal(PickupManager.PHASE_GROUND)
	assert_float(pm.hold[i]).is_greater(0.5)
	# the turrets' pull is kept off it as well
	pm.add_attractor(pm.pos[i], 4.0)
	pm._physics_process(DT)
	assert_int(pm.flying[i]).is_equal(0)
	# his own feet are no magnet: he walks onto it and it is his
	hero.global_position = Vector3(pm.pos[i].x, 0.0, pm.pos[i].z)
	pm._physics_process(DT)
	assert_int(pm.flying[i]).is_equal(1)
	# a vacuum calls a held coin like everything else
	hero.global_position = Vector3.ZERO
	var j := pm.toss_coin(hero.global_position)
	for k in range(int(ceil(PickupManager.TOSS_TIME / DT)) + 1):
		pm._physics_process(DT)
	assert_float(pm.hold[j]).is_greater(0.5)
	pm.vacuum_all(true)
	assert_int(pm.flying[j]).is_equal(1)


func test_a_tossed_coin_lands_inside_the_arena_and_off_the_rocks() -> void:
	var pm: PickupManager = auto_free(PickupManager.new())
	var m: MapBase = auto_free(MapBase.new())
	m.arena_radius = 10.0
	m.obstacles = [Vector3(8.0, 2.5, 1.0)]
	var at := Vector3(7.5, 0.0, 0.0)
	var rim: float = m.arena_radius - PickupManager.TOSS_EDGE
	for k in range(300):
		var p := pm.toss_spot(at, m)
		var d := _flat(p - at)
		assert_float(d).is_between(PickupManager.TOSS_MIN - 0.001, PickupManager.TOSS_MAX + 0.001)
		assert_float(_flat(p)).override_failure_message("out past the rim at %s" % str(p)).is_less_equal(rim + 0.001)
		assert_float(Vector2(p.x - 8.0, p.z - 2.5).length()).override_failure_message("on the rock at %s" % str(p)).is_greater_equal(1.0 + PickupManager.TOSS_CLEAR - 0.001)
	# nowhere clear: TOSS_MIN towards the middle
	m.arena_radius = 100.0
	m.obstacles = [Vector3(5.0, 0.0, 10.0)]
	var p2 := pm.toss_spot(Vector3(5.0, 0.0, 0.0), m)
	assert_float(p2.x).is_equal_approx(5.0 - PickupManager.TOSS_MIN, 0.001)
	assert_float(p2.z).is_equal_approx(0.0, 0.001)
	# without a map anywhere on the ring
	for k in range(50):
		var p3 := pm.toss_spot(Vector3(1.0, 0.0, 1.0))
		assert_float(_flat(p3 - Vector3(1.0, 0.0, 1.0))).is_between(PickupManager.TOSS_MIN - 0.001, PickupManager.TOSS_MAX + 0.001)
