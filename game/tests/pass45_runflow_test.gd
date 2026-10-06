## Pass 45, the run flow lane: a hero's own mutation is the stage's path pick for that weapon (item 11: Calavera taking
## Danza Macabra must not get Skull Rain's path straight back, nor at the stage's next slot), the boss chest's reel holds
## only the paths it can land on (item 13), and every hero lands with his own weapon, no starter pick (item 26).
extends GdUnitTestSuite


func after_test() -> void:
	Run.end()


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _calavera_with_skull_rain() -> WeaponInstance:
	_start("calavera")
	return Run.add_weapon(Registry.weapon("skull_rain"), 2)


# ---------------------------------------------------------------- item 11: the hero mutation is the stage's pick

func test_the_hero_mutation_spends_the_stages_pick() -> void:
	var w := _calavera_with_skull_rain()
	assert_object(Run.next_path_weapon()).is_same(w)
	var offer := CardPool.path_offer(w)
	# Plague, Bone Storm, Homing Skulls, then Calavera's own Danza Macabra
	assert_int(offer.size()).is_equal(4)
	var hero_card: Dictionary = offer[3]
	assert_str(str(hero_card["id"])).is_equal("danza_macabra")
	assert_bool((hero_card["def"] as MutationDef).is_hero()).is_true()
	CardPool.apply(hero_card)
	assert_bool(w.has_mutation("danza_macabra")).is_true()
	# the bug: Game re-opened the path whenever these held after a hero pick
	assert_bool(Run.can_mutate(w)).override_failure_message("the hero pick left the stage's path open").is_false()
	assert_int(Run.open_mutations(w).size()).is_equal(0)
	assert_object(Run.next_path_weapon()).override_failure_message("Skull Rain's path went on the table again").is_null()
	assert_bool(Run.add_mutation("plague")).override_failure_message("a path pick on top of the hero pick in one stage").is_false()
	assert_int(Run.mutations_held("skull_rain").size()).is_equal(1)
	# the next stage: the three path picks, the hero option already held
	Run.stage = 1
	assert_bool(Run.can_mutate(w)).is_true()
	var o2 := CardPool.path_offer(w)
	assert_int(o2.size()).is_equal(3)
	for c in o2:
		assert_bool((c["def"] as MutationDef).is_hero()).is_false()


func test_a_path_pick_closes_the_hero_option_for_the_stage() -> void:
	var w := _calavera_with_skull_rain()
	CardPool.apply(CardPool.path_offer(w)[0])
	assert_int(Run.open_mutations(w).size()).is_equal(0)
	assert_bool(Run.add_mutation("danza_macabra")).is_false()
	# the boss chest and the Stranger still hand it over past the stage's pick
	assert_bool(Run.add_mutation("danza_macabra", true)).is_true()
	assert_int(Run.mutations_held("skull_rain").size()).is_equal(2)


# ---------------------------------------------------------------- item 13: the boss reel shows the open paths only

func test_the_boss_reel_pool_is_only_open_paths() -> void:
	_start()
	assert_array(Run.boss_chest_mutations()).is_empty()
	Run.add_weapon(Registry.weapon("hornet_nest"), 3)
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	var pool := Run.boss_chest_mutations()
	assert_int(pool.size()).is_greater_equal(6)
	for m in pool:
		assert_bool(m is MutationDef).is_true()
		assert_bool((m as MutationDef).weapon in ["hornet_nest", "boomstick"]).override_failure_message((m as MutationDef).id).is_true()
	# a path taken leaves the list, a banished one too, and the roll comes out of what is left
	var taken: MutationDef = pool[0]
	var banned: MutationDef = pool[1]
	assert_bool(Run.add_mutation(taken.id, true)).is_true()
	Run.banished.append(banned.id)
	var left := Run.boss_chest_mutations()
	assert_bool(left.has(taken)).is_false()
	assert_bool(left.has(banned)).is_false()
	assert_int(left.size()).is_equal(pool.size() - 2)
	var r := Run.chest_roll(true)
	assert_str(str(r.get("type", ""))).is_equal("mutation")
	assert_bool(left.has(r.get("def"))).is_true()


func test_a_boss_chest_with_no_open_path_rolls_like_any_chest() -> void:
	_start()
	# pass 47: any chest may hold a new passive item, so with nothing held the roll is one of those
	var r := Run.chest_roll(true)
	assert_str(str(r.get("type", ""))).is_equal("passive")
	assert_bool(bool(r.get("is_new", false))).is_true()
	assert_bool((r["def"] as PassiveDef).is_line()).is_false()
	# and gold when nothing at all is left
	for p: PassiveDef in Registry.passives.values():
		Run.banished.append(p.id)
	assert_str(str(Run.chest_roll(true).get("type", ""))).is_equal("gold")
	Run.banished.clear()


func test_the_reel_strip_lands_on_the_roll_and_never_repeats_it_beside_itself() -> void:
	_start()
	Run.add_weapon(Registry.weapon("hornet_nest"), 3)
	var pool := Run.boss_chest_mutations()
	var def: MutationDef = pool[0]
	var cs: ChestScreen = auto_free(ChestScreen.new())
	cs._fill_strip([def, pool[1]], def)
	assert_int(cs._defs.size()).is_equal(ChestScreen.CELLS + ChestScreen.TAIL)
	assert_object(cs._defs[ChestScreen.CELLS - 1]).is_same(def)
	assert_object(cs._defs[ChestScreen.CELLS - 2]).is_not_same(def)
	assert_object(cs._defs[ChestScreen.CELLS]).is_not_same(def)
	# every plate is one the chest could stop on
	for d in cs._defs:
		assert_bool(d is MutationDef).is_true()
	# an empty pool gives blank plates round the roll, as before
	cs._fill_strip([], def)
	assert_object(cs._defs[ChestScreen.CELLS - 1]).is_same(def)
	assert_object(cs._defs[0]).is_null()


# ---------------------------------------------------------------- item 26: the hero lands with his own weapon

func test_every_hero_lands_with_his_own_weapon() -> void:
	var want := {"astro": "gravity_gun", "drifter": "revolver", "calavera": "guitarra", "buck": "tommy_gun", "dad": "boomstick", "mira": "land_mine"}
	for hid in want.keys():
		var c: CharacterDef = Registry.character(hid)
		assert_object(c).override_failure_message(str(hid)).is_not_null()
		var w := Registry.start_weapon_for(c)
		assert_object(w).override_failure_message(str(hid)).is_not_null()
		assert_str(w.id).override_failure_message(str(hid)).is_equal(str(want[hid]))
		assert_bool(w.is_evolution).is_false()
		Run.start(c, Registry.map("red_canyon"))
		assert_bool(Registry.hero_may_use(w)).override_failure_message(str(hid)).is_true()
		Run.end()
	# the key is data (JsonContent reads start_weapon) and the fallbacks hold without it
	assert_str(Registry.character("astro").start_weapon).is_equal("gravity_gun")
	assert_str(Registry.character("buck").start_weapon).is_equal("")
	assert_str(Registry.start_weapon_for(null).id).is_equal("peashooter")


func test_the_start_weapon_takes_the_favourite_bonus_only_when_it_is_the_favourite() -> void:
	_start("drifter")
	var rev := Run.add_weapon(Registry.start_weapon_for(Run.character), 1)
	assert_str(rev.def.id).is_equal("revolver")
	assert_int(rev.level).is_equal(1)
	assert_bool(rev.bonus_effects.is_empty()).is_true()
	# a launch file naming the favourite gets the bonus the pick gave: the Drifter's Peashooter at level 2 (pass 48: of five,
	# it was 3 of eight)
	var pea := Run.add_weapon(Registry.weapon("peashooter"), 1)
	CardPool.apply_favourite(pea)
	assert_int(pea.level).is_equal(2)


func test_the_starter_pick_is_gone() -> void:
	assert_bool(CardPool.new().has_method("starter_offer")).is_false()
	assert_bool(CardPool.new().has_method("apply_favourite")).is_true()


func test_the_cinematic_hero_keeps_his_height() -> void:
	_start()
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	p.setup(Run.character)
	add_child(p)
	p.cinematic = true
	p.global_position = Vector3(0, 12.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(p.global_position.y).is_equal_approx(12.0, 0.01)
	# off the beam he is a body again: gravity takes him
	p.cinematic = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(p.global_position.y).is_less(12.0)
	remove_child(p)


func test_the_spawn_sounds_are_bound() -> void:
	assert_bool(Registry.soundmap.entries.has("pl_spawn_beam")).is_true()
	assert_bool(Registry.soundmap.entries.has("pl_spawn_land")).is_true()
