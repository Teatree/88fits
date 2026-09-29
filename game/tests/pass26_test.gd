extends GdUnitTestSuite

## Pass 26: the paths. A weapon cap that grows with the stage, three mutations a weapon (one pick a stage, exclusive
## within it), lines (two a run), hero perks, the evolution rule, the card pool's limits and the Buckshot Dwarf.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _give(id: String, level: int) -> WeaponInstance:
	var inst := Run.add_weapon(Registry.weapon(id), level)
	return inst


func test_content_is_there() -> void:
	assert_int(Registry.mutations.size()).is_equal(75)   # pass 29: a fourth turret stance; pass 30: the laser's three; pass 35: nine for three weapons
	# pass 33.2: eight lines a level-up can offer, each with an evolution
	assert_int(Registry.sorted_lines().size()).is_equal(8)
	assert_int(Registry.lines.size()).is_equal(16)
	# pass 34: two more perks each for the two heroes in play (Supply Drop, Thruster Burst; High Noon, Bounty Hunter)
	assert_int(Registry.perks.size()).is_equal(9)
	for w in Registry.base_weapons():
		var path: Array = Registry.mutations_of(w.id)
		assert_int(path.size()).override_failure_message("%s has %d path mutations" % [w.id, path.size()]).is_greater_equal(3)
		var kinds: Array = []
		for m in path:
			kinds.append(m.mutation_kind)
		# an element, a volume and a motion pick on every path; a weapon may carry more (the turret's stances)
		assert_bool(kinds.slice(0, 3) == ["element", "volume", "motion"]).override_failure_message(w.id + " path kinds " + str(kinds)).is_true()
		assert_str(w.evolves_with).is_equal("")
	for c in Registry.characters.values():
		var want := 3 if ["astro", "drifter"].has(c.id) else 1
		assert_int(Registry.perks_of(c.id).size()).override_failure_message("%s has %d perks, not %d" % [c.id, Registry.perks_of(c.id).size(), want]).is_equal(want)
		assert_int(Registry.hero_mutations(c.id).size()).override_failure_message(c.id + " has no hero mutation").is_equal(1)
		assert_str((Registry.hero_mutations(c.id)[0] as MutationDef).weapon).is_equal(c.favourite_weapon)
	for pid in ["might", "spurs", "sombrero", "snake_oil", "leech", "cactus_coat", "guidance_fins", "payload", "whetstone", "long_arm", "conductor"]:
		assert_bool(Registry.passives.has(pid)).override_failure_message(pid + " should be retired").is_false()
	# pass 33.2: Beef Jerky and Pickpocket
	assert_int(Registry.passives.size()).is_equal(15)


func test_weapon_cap_grows_with_the_stage() -> void:
	_start()
	assert_int(Run.weapon_cap()).is_equal(4)
	var ids := ["peashooter", "boomstick", "tommy_gun", "hornet_nest", "orbit_saws", "zap_beam"]
	for id in ids:
		Run.add_weapon(Registry.weapon(id), 1)
	assert_int(Run.weapons.size()).is_equal(4)
	# the pool offers no new weapon at the cap
	for k in range(12):
		for c in CardPool.level_up_offer(3):
			if c["type"] == "weapon":
				assert_bool(bool(c["is_new"])).override_failure_message("a new weapon was offered at the cap").is_false()
	# stage 2 opens two slots (pass 33.7; one before)
	Run.stage = 1
	assert_int(Run.weapon_cap()).is_equal(6)
	Run.add_weapon(Registry.weapon("orbit_saws"), 1)
	Run.add_weapon(Registry.weapon("zap_beam"), 1)
	assert_int(Run.weapons.size()).is_equal(6)
	Run.stage = 2
	assert_int(Run.weapon_cap()).is_equal(6)
	Run.stage = 5
	assert_int(Run.weapon_cap()).is_equal(6)


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
	assert_bool(Run.add_mutation("swarm")).is_true()
	assert_int(w.stat_int("amount", 0)).is_greater_equal(8)
	assert_bool(Run.add_mutation("ember_hornets")).override_failure_message("a third pick on the same stage").is_false()
	# a mutation cannot be taken twice, and its params merged into the instance
	assert_bool(Run.add_mutation("swarm")).is_false()
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
	assert_bool(ids.has("birdshot")).is_true()
	assert_bool(Run.add_mutation("dragons_breath")).is_true()
	assert_str(w2.element()).is_equal("fire")


func test_behaviour_and_visual_swaps() -> void:
	_start()
	var w := _give("poison_dart", 3)
	assert_str(w.behavior()).is_equal("ProjectileEmitter")
	assert_bool(Run.add_mutation("needle_rain")).is_true()
	assert_str(w.behavior()).is_equal("Lobber")
	assert_float(w.stat("area", 0.0)).is_greater(1.0)
	# pass 29: the turret keeps its Spawner; its stances are params the Turret node builds its shape from
	var t := _give("turret_buddy", 3)
	assert_bool(Run.add_mutation("watchtower")).is_true()
	assert_str(t.behavior()).is_equal("Spawner")
	assert_str(str((t.params.get("turret", {}) as Dictionary).get("style", ""))).is_equal("tower")
	assert_float(t.stat("range", 0.0)).is_greater(Registry.weapon("turret_buddy").base.get("range", 8.0))


func test_player_side_mutation_effects_reach_the_sheet() -> void:
	_start()
	_give("rattlesnake", 3)
	assert_bool(Run.add_mutation("rattle")).is_true()
	assert_float(Run.player_sheet.get_stat("poison_slow", 0.0)).is_equal_approx(0.3, 0.001)
	_give("flare_gun", 3)
	assert_bool(Run.add_mutation("white_phosphorus")).is_true()
	assert_float(Run.player_sheet.get_stat("fire_vuln", 0.0)).is_equal_approx(0.5, 0.001)


func test_lines_capped_by_the_stage_with_ranks() -> void:
	_start()
	assert_bool(Run.add_or_rank_line("vigour")).is_true()
	var hp1 := Run.player_sheet.get_stat("max_hp", 100.0)
	var armor1 := Run.player_sheet.get_stat("armor", 0.0)
	assert_bool(Run.add_or_rank_line("vigour")).is_true()
	assert_float(Run.player_sheet.get_stat("max_hp", 100.0)).is_greater(hp1)
	assert_float(Run.player_sheet.get_stat("armor", 0.0)).is_equal_approx(armor1 + 1.0, 0.001)
	assert_bool(Run.add_or_rank_line("brawn")).is_true()
	assert_float(Run.player_sheet.get_stat("move_speed", 3.6)).is_less(3.6)
	# pass 34: stage 1 opens three lines (the map's line_cap, 3 / 4 / 4), not two for the whole run
	assert_bool(Run.add_or_rank_line("stride")).override_failure_message("a third line did not open on stage 1").is_true()
	assert_bool(Run.add_or_rank_line("mend")).override_failure_message("a fourth line opened on stage 1").is_false()
	# the pool now offers only ranks of the three open lines
	for k in range(10):
		for c in CardPool.level_up_offer(3):
			if c["type"] == "line":
				assert_bool(["vigour", "brawn", "stride"].has(str(c["id"]))).is_true()
	for k in range(2):
		Run.add_or_rank_line("vigour")
	assert_int(Run.line_rank("vigour")).is_equal(4)
	assert_bool(Run.add_or_rank_line("vigour")).is_false()


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
				if str(c["id"]) == "ram":
					seen_own = true
				else:
					seen_other = true
	assert_bool(seen_other).is_false()
	assert_bool(seen_own).is_true()
	# the hero mutation shows for the favourite weapon only
	_give("tommy_gun", 3)
	var ids: Array = []
	for m in Run.open_mutations(Run.weapon_instance("tommy_gun")):
		ids.append(m.id)
	assert_bool(ids.has("drum_roll")).is_true()
	assert_bool(Run.add_mutation("drum_roll")).is_true()
	# a hero mutation does not spend the stage's pick
	assert_bool(Run.can_mutate(Run.weapon_instance("tommy_gun"))).is_true()


func test_evolution_needs_two_mutations() -> void:
	_start()
	var w := _give("sabre", 8)
	assert_bool(Run.evolution_ready(w)).is_false()
	Run.add_mutation("flurry")
	assert_bool(Run.evolution_ready(w)).is_false()
	Run.stage = 1
	Run.add_mutation("flame_blade")
	assert_bool(Run.evolution_ready(w)).is_true()
	var evo := Run.evolve(w)
	assert_str(evo.def.id).is_equal("zweihander")
	assert_int(evo.mutations.size()).is_equal(2)
	assert_str(evo.family_id()).is_equal("sabre")
	assert_float(evo.stat("fire_damage", 0.0)).is_greater(0.0)


func test_offer_limits_and_forcing() -> void:
	_start()
	_give("hornet_nest", 3)
	# pass 27: mutations never sit in a level-up; the path has its own table
	for k in range(12):
		for c in CardPool.level_up_offer(3):
			assert_bool(str(c["type"]) == "mutation").override_failure_message("a mutation card in a level-up").is_false()
	# never two new weapons, two lines or two perks in one offer
	for k in range(30):
		var o := CardPool.level_up_offer(3)
		var new_w := 0
		var ln := 0
		for c in o:
			if c["type"] == "weapon" and bool(c["is_new"]):
				new_w += 1
			if c["type"] == "line":
				ln += 1
		assert_int(new_w).is_less_equal(1)
		assert_int(ln).is_less_equal(1)
	# applying each kind of card
	var m := Registry.mutation("swarm")
	assert_str(CardPool.apply({"type": "mutation", "id": "swarm", "def": m, "level_from": 0, "level_to": 1, "is_new": true})).is_equal("Swarm")
	assert_str(CardPool.apply({"type": "line", "id": "mend", "def": Registry.line("mend"), "level_from": 0, "level_to": 1, "is_new": true})).is_equal("Mend rank 1")


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
	var early := false
	for r in m.timeline.roster_at(140.0):
		if str(r["enemy"]) == "buckshot_dwarf":
			early = true
	assert_bool(early).is_true()
	assert_int(m.timeline.weapon_cap_at(0)).is_equal(4)
	assert_int(m.timeline.weapon_cap_at(9)).is_equal(6)


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


