extends GdUnitTestSuite

## Pass 26: the paths. A weapon cap that grows with the stage (six on every stage since pass 47), three mutations a
## weapon (one pick a stage, exclusive within it), lines (two a run; passives under a stage cap in pass 46; six line
## slots and uncapped passive items since pass 47), hero perks, the evolution rule, the card pool's limits and the
## Buckshot Dwarf.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _give(id: String, level: int) -> WeaponInstance:
	var inst := Run.add_weapon(Registry.weapon(id), level)
	return inst


func test_content_is_there() -> void:
	# pass 66: the counts this test pinned (113 mutations with 28 hidden, 15 evolving lines and 15 evolved, 18 perks, 61
	# passives) and the loop over every hero's perks and mutation are shape rules now (pass66_shape_test.gd: every weapon
	# in play has its three path mutations and its evolution, every line evolves, every hero in play has a perk and one
	# hero mutation): the Level Editor adds content, and a hidden hero made from a template has no perks yet
	for w in Registry.base_weapons():
		# a hidden weapon's template mutations are hidden with it (pass 66), so the path is the weapons in play's
		if w.hidden:
			continue
		var path: Array = Registry.mutations_of(w.id)
		assert_int(path.size()).override_failure_message("%s has %d path mutations" % [w.id, path.size()]).is_greater_equal(3)
		var kinds: Array = []
		for m in path:
			kinds.append(m.mutation_kind)
		# an element, a volume and a motion pick on every path; a weapon may carry more (the turret's stances)
		assert_bool(kinds.slice(0, 3) == ["element", "volume", "motion"]).override_failure_message(w.id + " path kinds " + str(kinds)).is_true()
		assert_str(w.evolves_with).is_equal("")
	# pass 69: "snake_oil" is a new passive item again (Snake Oil's overheal, lane PAS), so it left this list
	for pid in ["might", "spurs", "sombrero", "leech", "cactus_coat", "guidance_fins", "payload", "whetstone", "long_arm", "conductor"]:
		assert_bool(Registry.passives.has(pid)).override_failure_message(pid + " should be retired").is_false()


func test_weapon_cap_grows_with_the_stage() -> void:
	# pass 47 (Garry: "We just give 6 slots for both and keep that static"): six on every stage from the start
	_start()
	assert_int(Run.weapon_cap()).is_equal(5)   # pass 52: five slots
	var ids := ["peashooter", "boomstick", "tommy_gun", "hornet_nest", "orbit_saws", "zap_beam", "sabre"]
	for id in ids:
		Run.add_weapon(Registry.weapon(id), 1)
	assert_int(Run.weapons.size()).is_equal(5)
	# the pool offers no new weapon at the cap
	for k in range(12):
		for c in CardPool.level_up_offer(3):
			if c["type"] == "weapon":
				assert_bool(bool(c["is_new"])).override_failure_message("a new weapon was offered at the cap").is_false()
	for s in [1, 2, 5]:
		Run.stage = s
		assert_int(Run.weapon_cap()).is_equal(5)   # pass 52: five slots


func test_mutations_open_at_level_three_one_a_stage() -> void:
	_start()
	# pass 27: a path opens from level 1 (the stage's slots decide when it goes on the table)
	var w := _give("hornet_nest", 1)
	assert_int(Run.open_mutations(w).size()).is_equal(3)
	Run.level_weapon("hornet_nest")
	Run.level_weapon("hornet_nest")
	assert_int(w.level).is_equal(3)
	assert_int(Run.open_mutations(w).size()).is_equal(3)
	# pass 29: Second Sting took the twister's place (a param the seekers read)
	assert_bool(Run.add_mutation("second_sting")).is_true()
	assert_bool(w.has_mutation("second_sting")).is_true()
	assert_bool(bool(w.params.get("second_sting", false))).is_true()
	# the other two are closed for the rest of the stage
	assert_bool(Run.can_mutate(w)).is_false()
	assert_int(Run.open_mutations(w).size()).is_equal(0)
	Run.stage = 1
	assert_bool(Run.can_mutate(w)).is_true()
	assert_int(Run.open_mutations(w).size()).is_equal(2)
	# pass 48: the Tarantula Hawk and Pollen took Swarm's and Ember Hornets' slots (both hidden, kept)
	assert_bool(Run.add_mutation("tarantula_hawk")).is_true()
	assert_bool(w.params.has("hawk")).is_true()
	assert_bool(Run.add_mutation("pollen")).override_failure_message("a third pick on the same stage").is_false()
	# a mutation cannot be taken twice, and its params merged into the instance
	assert_bool(Run.add_mutation("tarantula_hawk")).is_false()
	assert_int(Run.mutations_held("hornet_nest").size()).is_equal(2)


func test_element_mutations_of_both_elements_share_a_run() -> void:
	_start()
	var w := _give("peashooter", 3)
	var w2 := _give("boomstick", 3)
	assert_bool(Run.add_mutation("toxic_peas")).is_true()
	assert_str(w.element()).is_equal("poison")
	# pass 36: the boomstick's fire pick stays on its path next to the poison peas
	var ids: Array = []
	for m in Run.open_mutations(w2):
		ids.append(m.id)
	assert_bool(ids.has("dragons_breath")).is_true()
	# pass 48: the new Birdshot (a lane) under its own id, the old one hidden
	assert_bool(ids.has("birdshot_lane")).is_true()
	assert_bool(ids.has("birdshot")).is_false()
	assert_bool(Run.add_mutation("dragons_breath")).is_true()
	assert_str(w2.element()).is_equal("fire")


func test_behaviour_and_visual_swaps() -> void:
	_start()
	var w := _give("poison_dart", 3)
	assert_str(w.behavior()).is_equal("ProjectileEmitter")
	assert_bool(Run.add_mutation("needle_rain")).is_true()
	assert_str(w.behavior()).is_equal("Lobber")
	assert_float(w.stat("area", 0.0)).is_greater(1.0)
	# pass 29: the turret keeps its Spawner; its stances are params the Turret node builds its shape from (pass 47: the
	# Watchtower is gone, the Bunker is the one stance left)
	var t := _give("turret_buddy", 3)
	var dmg := t.stat("damage", 0.0)
	assert_bool(Run.add_mutation("bunker")).is_true()
	assert_str(t.behavior()).is_equal("Spawner")
	assert_str(str((t.params.get("turret", {}) as Dictionary).get("style", ""))).is_equal("bunker")
	assert_float(t.stat("damage", 0.0)).is_greater(dmg)


func test_player_side_mutation_effects_reach_the_sheet() -> void:
	_start()
	_give("rattlesnake", 3)
	assert_bool(Run.add_mutation("rattle")).is_true()
	assert_float(Run.player_sheet.get_stat("poison_slow", 0.0)).is_equal_approx(0.3, 0.001)
	_give("flare_gun", 3)
	assert_bool(Run.add_mutation("white_phosphorus")).is_true()
	assert_float(Run.player_sheet.get_stat("fire_vuln", 0.0)).is_equal_approx(0.5, 0.001)


func test_passives_capped_by_the_stage_with_levels() -> void:
	_start()
	assert_bool(Run.add_or_level_passive("vigour")).is_true()
	var hp1 := Run.player_sheet.get_stat("max_hp", 100.0)
	var dr1 := Run.player_sheet.get_stat("damage_reduction", 0.0)
	assert_bool(Run.add_or_level_passive("vigour")).is_true()
	assert_float(Run.player_sheet.get_stat("max_hp", 100.0)).is_greater(hp1)
	assert_float(Run.player_sheet.get_stat("damage_reduction", 0.0)).is_equal_approx(dr1 + 0.05, 0.001)
	# pass 47: Brawn no longer slows (Garry: "Simplify Brawn, so it doesn't have the debuffs")
	var speed := Run.player_sheet.get_stat("move_speed", 3.6)
	assert_bool(Run.add_or_level_passive("brawn")).is_true()
	assert_float(Run.player_sheet.get_stat("move_speed", 3.6)).is_equal_approx(speed, 0.0001)
	# pass 47: six line slots on every stage, the passive items take none; five since pass 52
	for id in ["stride", "mend", "thirst"]:
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id + " found no line slot on stage 1").is_true()
	assert_bool(Run.add_or_level_passive("magnet")).override_failure_message("a passive item was capped").is_true()
	assert_bool(Run.add_or_level_passive("bristle")).override_failure_message("a sixth line opened").is_false()
	# the pool now offers no new line: a line card is a level of one of the five held
	var held := ["vigour", "brawn", "stride", "mend", "thirst"]
	for k in range(10):
		for c in CardPool.level_up_offer(3):
			if c["type"] == "passive" and (c["def"] as PassiveDef).is_line() and not bool(c.get("evolve", false)):
				assert_bool(held.has(str(c["id"]))).override_failure_message("offered " + str(c["id"])).is_true()
	for s in [1, 2]:
		Run.stage = s
		assert_bool(Run.add_or_level_passive("bristle")).override_failure_message("stage %d opened a sixth line" % (s + 1)).is_false()
	for k in range(2):
		Run.add_or_level_passive("vigour")
	assert_int(Run.passive_level("vigour")).is_equal(4)
	assert_bool(Run.add_or_level_passive("vigour")).is_false()


func test_perks_are_the_heros_own() -> void:
	_start("dad")
	assert_bool(Run.add_perk("tough_love")).is_true()
	assert_bool(Run.add_perk("tough_love")).is_false()
	assert_float(Run.perk_param("tough_love", "might", 0.0)).is_equal_approx(0.15, 0.001)
	assert_float(Run.perk_param("ram", "shove", 0.0)).is_equal(0.0)
	_start("buck")
	Run.perk_gap = 5
	var seen_other := false
	var seen_own := false
	for k in range(40):
		for c in CardPool.level_up_offer(3):
			if c["type"] == "perk":
				# pass 67: Ram and Overdrive are both his
				if str(c["id"]) in ["ram", "overdrive"]:
					seen_own = true
				else:
					seen_other = true
	assert_bool(seen_other).is_false()
	assert_bool(seen_own).is_true()
	# Buck is back in play (pass 67): his own mutation is offered on his favourite (pass 46 had it out of play with him);
	# pass 69: he is Jeżyk, his favourite the Salt and his own Salt Flats
	_give("salt", 3)
	var ids: Array = []
	for m in Run.open_mutations(Run.weapon_instance("salt")):
		ids.append(m.id)
	assert_bool(ids.has("salt_flats")).is_true()
	# pass 69 (lane UI): Mira is back, a hero to buy (in play: locked or on sale on the title), so her own is offered
	# to her: the Blasting Cap on her Land Mine (a hidden hero's own staying out: pass66_shape_test's rule, Dad has none).
	# Garry hid her again on 2026-10-13: her own is offered exactly while she is in play
	var mira_in_play: bool = not Registry.character("mira").hidden
	_start("mira")
	_give("land_mine", 3)
	ids.clear()
	for m in Run.open_mutations(Run.weapon_instance("land_mine")):
		ids.append(m.id)
	assert_bool(ids.has("blasting_cap")).is_equal(mira_in_play)
	# the hero mutation shows for the favourite weapon only: the Drifter's Fan the Hammer on the Peashooter
	_start("drifter")
	_give("peashooter", 3)
	_give("boomstick", 3)
	ids.clear()
	for m in Run.open_mutations(Run.weapon_instance("peashooter")):
		ids.append(m.id)
	assert_bool(ids.has("fan_the_hammer")).is_true()
	for m in Run.open_mutations(Run.weapon_instance("boomstick")):
		assert_bool((m as MutationDef).is_hero()).is_false()
	assert_bool(Run.add_mutation("fan_the_hammer")).is_true()
	# a hero mutation is the stage's pick for that weapon (pass 45; it was a free extra before)
	assert_bool(Run.can_mutate(Run.weapon_instance("peashooter"))).is_false()


## Pass 48: every mutation of the path (it was two of the three since pass 26).
func test_evolution_needs_every_mutation() -> void:
	_start()
	var w := _give("sabre", 5)
	assert_bool(Run.evolution_ready(w)).is_false()
	Run.add_mutation("flurry")
	assert_bool(Run.evolution_ready(w)).is_false()
	Run.stage = 1
	# pass 53 (lane W2): Critical Thinking is the Sabre's element pick (Flame Blade hidden), the Whirlwind its evolution
	Run.add_mutation("critical_thinking")
	assert_bool(Run.evolution_ready(w)).is_false()
	Run.stage = 2
	Run.add_mutation("riposte")
	assert_bool(Run.evolution_ready(w)).is_true()
	var evo := Run.evolve(w)
	assert_str(evo.def.id).is_equal("whirlwind")
	assert_int(evo.mutations.size()).is_equal(3)
	assert_str(evo.family_id()).is_equal("sabre")
	assert_float(float(evo.params.get("crit_refund", 0.0))).is_equal_approx(0.2, 0.0001)


func test_offer_limits_and_forcing() -> void:
	_start()
	_give("hornet_nest", 3)
	# pass 27: mutations never sit in a level-up; the path has its own table
	for k in range(12):
		for c in CardPool.level_up_offer(3):
			assert_bool(str(c["type"]) == "mutation").override_failure_message("a mutation card in a level-up").is_false()
	# never two new weapons or two perks in one offer
	for k in range(30):
		Run.perk_gap = 5
		var o := CardPool.level_up_offer(3)
		var new_w := 0
		var pk := 0
		for c in o:
			if c["type"] == "weapon" and bool(c["is_new"]):
				new_w += 1
			if c["type"] == "perk":
				pk += 1
		assert_int(new_w).is_less_equal(1)
		assert_int(pk).is_less_equal(1)
	# applying each kind of card
	var m := Registry.mutation("tarantula_hawk")
	assert_str(CardPool.apply({"type": "mutation", "id": "tarantula_hawk", "def": m, "level_from": 0, "level_to": 1, "is_new": true})).is_equal("Tarantula Hawk")
	assert_str(CardPool.apply({"type": "passive", "id": "mend", "def": Registry.passive("mend"), "level_from": 0, "level_to": 1, "is_new": true})).is_equal("Mend Lv 1")


func test_stranger_sells_a_closed_mutation() -> void:
	_start()
	_give("sabre", 3)
	Run.add_mutation("flurry")
	var found := false
	for k in range(60):
		var o := Run.stranger_offer()
		if not o.is_empty() and o["type"] == "mutation":
			assert_str((o["def"] as MutationDef).weapon).is_equal("sabre")
			assert_float(float(o["hp_cost"])).is_equal_approx(0.2, 0.001)
			var line := Run.stranger_take(o, float(o["hp_cost"]))
			assert_str(line).is_not_empty()
			assert_int(Run.mutations_held("sabre").size()).is_equal(2)
			found = true
			break
	assert_bool(found).is_true()


func test_the_dwarf_replaces_the_slinger() -> void:
	assert_bool(Registry.enemies.has("goblin_slinger")).is_false()
	var d: EnemyDef = Registry.enemy("buckshot_dwarf")
	assert_object(d).is_not_null()
	assert_int(int(d.ranged.get("cone_deg", 0))).is_greater(0)
	assert_int(int(d.ranged.get("count", 0))).is_greater_equal(3)
	var cactus: EnemyDef = Registry.enemy("spit_cactus")
	assert_float(float(d.ranged.get("range", 0.0))).is_less(float(cactus.ranged.get("range", 0.0)))
	assert_float(d.hp).is_greater(cactus.hp * 1.5)
	var m: MapDef = Registry.map("red_canyon")
	# 2:20 before the clocks were stretched by 430/300 (pass 46): the dwarf came at 3:06; pass 54: Garry's placement in
	# the Level Editor (2026-10-06) has no dwarf row, so this only holds while one is there
	var rows: Array = m.timeline.roster.filter(func(r): return str(r.get("enemy", "")) == "buckshot_dwarf")
	# pass 56 (re-pinned): Garry's placement (2026-10-07) brings the dwarf at 9:54; whatever he picks, the row plays
	for row in rows:
		var on := false
		for r in m.timeline.roster_at(float(row.get("t", 0.0)) + 1.0):
			if str(r["enemy"]) == "buckshot_dwarf":
				on = true
		assert_bool(on).is_true()
	# pass 47: six from the start
	assert_int(m.timeline.weapon_cap_at(0)).is_equal(5)
	assert_int(m.timeline.weapon_cap_at(9)).is_equal(5)


func test_the_idol_erupts_in_light() -> void:
	# pass 32: the Sun Idol took the ranged Elite's place, and its rings are pillars of light
	assert_bool(Registry.enemies.has("dune_centipede")).is_false()
	assert_bool(Registry.enemies.has("mirage_djinn")).is_false()
	var idol: EnemyDef = Registry.enemy("sun_prophet")
	assert_object(idol).is_not_null()
	var names: Array = []
	var erupt: Dictionary = {}
	for atk in idol.boss.get("attacks", []):
		names.append(str(atk.get("name", "")))
		if str(atk.get("name", "")) == "erupt":
			erupt = atk
	assert_bool(names.has("erupt")).is_true()
	assert_bool(bool(erupt.get("pillar", false))).is_true()
	assert_float(float(erupt.get("min_range", 0.0))).is_greater(0.0)
	assert_float(float(erupt.get("warn", 0.0))).is_greater_equal(0.8)


