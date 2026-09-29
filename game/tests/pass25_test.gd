extends GdUnitTestSuite

## Pass 25: blades, the Stranger, the homestead and its materials, the reworked creatures, the second Elite, Mira.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_blades_are_content_of_the_new_kind() -> void:
	for id in ["sabre", "pike"]:
		var w: WeaponDef = Registry.weapon(id)
		assert_object(w).override_failure_message("missing " + id).is_not_null()
		assert_str(w.behavior).is_equal("Thruster")
		assert_bool(w.tags.has("blade")).is_true()
		assert_bool(w.params.has("thrust")).is_true()
		assert_bool(ResourceLoader.exists("res://content/weapons/%s/%s_visual.tscn" % [id, id])).is_true()
	assert_bool(Registry.weapons.has("zweihander")).is_true()
	assert_bool(Registry.weapons.has("halberd")).is_true()
	for id in ["flurry", "phalanx", "riposte", "pike_sweep"]:
		assert_object(Registry.mutation(id)).override_failure_message("missing " + id).is_not_null()


func test_flurry_touches_only_the_sabre() -> void:
	_start()
	Run.add_weapon(Registry.weapon("sabre"), 3)
	Run.add_weapon(Registry.weapon("peashooter"), 3)
	var before := Run.weapon_instance("sabre").stat_int("amount", 0)
	var pea_before := Run.weapon_instance("peashooter").stat("damage", 0.0)
	Run.add_mutation("flurry")
	assert_int(Run.weapon_instance("sabre").stat_int("amount", 0)).is_equal(before + 2)
	assert_float(Run.weapon_instance("peashooter").stat("damage", 0.0)).is_equal_approx(pea_before, 0.001)


func test_stranger_offers_only_high_value_and_takes_a_cut() -> void:
	_start()
	for k in range(30):
		var o := Run.stranger_offer()
		assert_bool(o.is_empty()).is_false()
		var def: ContentDef = o["def"]
		assert_str(def.rarity).is_not_equal("common")
		assert_int(int(o["level_to"]) - int(o["level_from"])).is_greater_equal(1)
	var hp_before := Run.player_sheet.get_stat("max_hp", 100.0)
	var offer := Run.stranger_offer()
	var line := Run.stranger_take(offer, 0.15)
	assert_str(line).is_not_empty()
	assert_float(Run.player_sheet.get_stat("max_hp", 100.0)).is_less(hp_before)
	if offer["type"] == "weapon":
		assert_int(Run.weapon_instance(offer["id"]).level).is_equal(int(offer["level_to"]))
	else:
		assert_int(int(Run.passives.get(offer["id"], 0))).is_equal(int(offer["level_to"]))


func test_stranger_replaced_the_dice_shrine() -> void:
	assert_bool(Registry.structures.has("hooded_figure")).is_true()
	assert_bool(Registry.structures.has("dice_shrine")).is_false()
	assert_str(Registry.structure("hooded_figure").effect_kind).is_equal("stranger")
	assert_bool(ResourceLoader.exists("res://art/sprites/props/st_hooded_figure.png")).is_true()
	assert_bool(ResourceLoader.exists("res://art/sprites/props/st_hooded_figure_off.png")).is_true()


func test_the_mirror_buys_forms_and_gives_it_all_back() -> void:
	# pass 32: the farm is gone; the meta is eight talents, two forms each, bought with gold and refundable
	Save.wipe()
	assert_int(Registry.talents.size()).is_equal(8)
	var grit: TalentDef = Registry.talent("grit")
	assert_int(grit.forms.size()).is_equal(2)
	assert_int(grit.ranks).is_equal(3)
	Save.add_gold(100000)
	var before := Save.gold()
	assert_bool(Save.buy_talent(grit)).is_true()
	assert_int(Save.talent_rank("grit")).is_equal(1)
	assert_int(Save.gold()).is_equal(before - grit.cost_of_rank(0))
	# the form is a free choice and the ranks stay
	Save.set_talent_form("grit", 1)
	assert_int(Save.talent_form("grit")).is_equal(1)
	assert_int(Save.talent_rank("grit")).is_equal(1)
	# and it folds into the hero's sheet
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	assert_float(Run.player_sheet.get_stat("armor", 0.0)).is_greater_equal(1.0)
	# everything back, to the coin
	var spent := Save.talent_spent()
	var back := Save.talent_refund_all()
	assert_int(back).is_equal(spent)
	assert_int(Save.talent_rank("grit")).is_equal(0)



func test_materials_bank_from_the_run() -> void:
	_start()
	Run.add_material("bones", 2)
	Run.add_material("relics", 1)
	assert_int(int(Run.run_materials["bones"])).is_equal(2)
	assert_int(int(Run.run_materials["relics"])).is_equal(1)


func test_reworked_creatures_and_the_second_elite() -> void:
	var toad: EnemyDef = Registry.enemy("horned_toad")
	assert_bool(toad.death_burst.has("delay")).is_true()
	# pass 28: the harpooner is the straight-shot creature now (the spider is gone)
	var trog: EnemyDef = Registry.enemy("harpoon_troglodyte")
	assert_bool(bool(trog.ranged.get("straight", false))).is_true()
	assert_bool(bool(trog.ranged.get("harpoon", false))).is_true()
	assert_bool(trog.charge.is_empty()).is_true()
	var shaman: EnemyDef = Registry.enemy("dust_shaman")
	assert_float(float(shaman.support.get("heal", 0.0))).is_greater_equal(0.25)
	assert_bool(shaman.support.has("frenzy_seconds")).is_true()
	var slinger: EnemyDef = Registry.enemy("buckshot_dwarf")
	assert_object(slinger).is_not_null()
	assert_bool(bool(slinger.ranged.get("straight", false))).is_true()
	var cent: EnemyDef = Registry.enemy("sun_prophet")
	assert_str(cent.brain).is_equal("caster")
	assert_str(cent.archetype).is_equal("elite")
	var names: Array = []
	for atk in cent.boss.get("attacks", []):
		names.append(str(atk.get("name", "")))
	assert_int(names.size()).is_greater_equal(2)
	assert_bool(names.has("blink")).is_true()
	assert_bool(names.has("slam_at")).is_true()
	# every creature's JSON carries the doc line the bible's table is generated from
	for id in Registry.enemies.keys():
		var def: EnemyDef = Registry.enemies[id]
		var path := def.source_dir.path_join(id + ".json")
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_bool(d is Dictionary and str(d.get("doc", "")) != "").override_failure_message(id + " has no doc line").is_true()


func test_elite_events_pick_between_the_two() -> void:
	var m: MapDef = Registry.map("red_canyon")
	var found := false
	for ev in m.timeline.events:
		if str(ev.get("type", "")) == "elite_boss":
			var e = ev.get("enemy")
			assert_bool(e is Array).is_true()
			assert_bool((e as Array).has("dune_scorpion") and (e as Array).has("sun_prophet")).is_true()
			found = true
	assert_bool(found).is_true()
	var slinger_early := false
	for r in m.timeline.roster_at(140.0):
		if str(r["enemy"]) == "buckshot_dwarf":
			slinger_early = true
	assert_bool(slinger_early).is_true()


func test_mira_is_the_economy_hero() -> void:
	var c: CharacterDef = Registry.character("mira")
	assert_object(c).is_not_null()
	assert_bool(c.specials.has("motherlode")).is_true()
	assert_str(c.trait_name).is_equal("Motherlode")
	assert_str(c.favourite_weapon).is_equal("land_mine")
	var greed := 0.0
	for e in c.trait_effects:
		if e.stat == "greed":
			greed = e.value
	assert_float(greed).is_greater(0.0)


func test_every_structure_kind_lands() -> void:
	var m: MapDef = Registry.map("red_canyon")
	assert_int(int(m.timeline.structures.get("count", 0))).is_greater_equal(Registry.structures.size())
