extends GdUnitTestSuite

## Pass 66, lane G (Garry: count-pinning tests become shape rules the Level Editor can also check on Save): the rules the
## content must keep whatever Garry adds in the editor, each over the Registry, in place of the counts pass26, pass334,
## pass61_hr, pass333, pass47_ui and pass53_items pinned (113 mutations, 61 passives, 18 perks, exactly five heroes,
## exactly four crowns...). A new hero, creature, weapon, line or passive item made from a template passes these when it
## is whole; the editor's Items and Heroes tabs say the same rules in words.

const PATH_KINDS := ["element", "volume", "motion"]
const ITEM_RARITIES := ["common", "uncommon", "rare", "epic"]


func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


# ---------------------------------------------------------------- the registry

func test_the_registry_loads_clean() -> void:
	assert_array(Registry.problems).is_empty()
	assert_bool(Registry.weapons.is_empty()).is_false()
	assert_bool(Registry.passives.is_empty()).is_false()
	assert_bool(Registry.enemies.is_empty()).is_false()
	assert_bool(Registry.characters.is_empty()).is_false()
	assert_bool(Registry.mutations.is_empty()).is_false()
	assert_bool(Registry.perks.is_empty()).is_false()


# ---------------------------------------------------------------- weapons

func test_every_weapon_in_play_has_one_element_volume_and_motion_and_an_evolution_of_its_own() -> void:
	var seen := 0
	for w: WeaponDef in Registry.base_weapons():
		if w.hidden:
			continue
		seen += 1
		# the path: exactly three mutations in play, one of each kind, none a hero's (mutations_of leaves hero and hidden
		# ones out), in element, volume, motion order
		var path: Array = Registry.mutations_of(w.id)
		var kinds: Array = path.map(func(m: MutationDef) -> String: return m.mutation_kind)
		assert_array(kinds).override_failure_message("%s path kinds %s" % [w.id, str(kinds)]).is_equal(PATH_KINDS)
		for m: MutationDef in path:
			assert_bool(m.is_hero()).override_failure_message(m.id).is_false()
			assert_bool(m.hidden).override_failure_message(m.id).is_false()
			assert_str(m.weapon).is_equal(w.id)
		# the evolution: an evolution of this weapon, in play, naming it back
		assert_str(w.evolves_into).override_failure_message(w.id + " has no evolves_into").is_not_empty()
		var ev: WeaponDef = Registry.weapon(w.evolves_into)
		assert_object(ev).override_failure_message("%s evolves into %s, which is not there" % [w.id, w.evolves_into]).is_not_null()
		if ev == null:
			continue
		assert_bool(ev.is_evolution).override_failure_message(ev.id + " is not an evolution").is_true()
		assert_str(ev.evolved_from).override_failure_message("%s evolved_from %s, not %s" % [ev.id, ev.evolved_from, w.id]).is_equal(w.id)
		assert_bool(ev.hidden).override_failure_message(ev.id + " is hidden under a weapon in play").is_false()
		# no passive key (pass 26: the path leads to the evolution)
		assert_str(w.evolves_with).is_equal("")
	assert_int(seen).is_greater(0)


func test_every_evolution_names_a_base_weapon_that_is_there() -> void:
	for w: WeaponDef in Registry.weapons.values():
		if not w.is_evolution:
			continue
		assert_str(w.evolved_from).override_failure_message(w.id + " has no evolved_from").is_not_empty()
		var src: WeaponDef = Registry.weapon(w.evolved_from)
		assert_object(src).override_failure_message("%s evolved from %s, which is not there" % [w.id, w.evolved_from]).is_not_null()
		if src:
			assert_bool(src.is_evolution).override_failure_message(w.id + " evolved from an evolution").is_false()


func test_every_mutation_names_a_weapon_that_is_there_and_a_kind_it_can_be() -> void:
	for m: MutationDef in Registry.mutations.values():
		assert_object(Registry.weapon(m.weapon)).override_failure_message("%s is on %s, which is not there" % [m.id, m.weapon]).is_not_null()
		assert_bool(["element", "volume", "motion", "stance", "hero"].has(m.mutation_kind)).override_failure_message("%s kind %s" % [m.id, m.mutation_kind]).is_true()
		if m.hero != "":
			assert_object(Registry.character(m.hero)).override_failure_message("%s is %s's, who is not there" % [m.id, m.hero]).is_not_null()
			assert_bool(m.is_hero()).override_failure_message(m.id + " names a hero but is not of the hero kind").is_true()


# ---------------------------------------------------------------- lines and passive items

func test_every_line_has_an_evolution_and_every_evolved_passive_a_source() -> void:
	var lines := 0
	for p: PassiveDef in Registry.sorted_lines():
		lines += 1
		assert_str(p.evolves_into).override_failure_message(p.id + " has no evolution").is_not_empty()
		var ev: PassiveDef = Registry.passive(p.evolves_into)
		assert_object(ev).override_failure_message("%s evolves into %s, which is not there" % [p.id, p.evolves_into]).is_not_null()
		if ev == null:
			continue
		assert_bool(ev.is_evolved()).override_failure_message(ev.id).is_true()
		assert_str(ev.evolves_from).is_equal(p.id)
		assert_bool(ev.is_line()).override_failure_message(ev.id + " is not a line like its source").is_true()
	assert_int(lines).is_greater(0)
	for p: PassiveDef in Registry.passives.values():
		if not p.is_evolved():
			continue
		var src: PassiveDef = Registry.passive(p.evolves_from)
		assert_object(src).override_failure_message("%s evolved from %s, which is not there" % [p.id, p.evolves_from]).is_not_null()
		if src:
			assert_str(src.evolves_into).override_failure_message("%s does not evolve into %s" % [src.id, p.id]).is_equal(p.id)
			assert_bool(src.is_line()).is_equal(p.is_line())


func test_passive_items_span_common_to_epic_and_none_is_legendary() -> void:
	var rarities: Dictionary = {}
	for p: PassiveDef in Registry.sorted_passives_only():
		assert_bool(ITEM_RARITIES.has(p.rarity)).override_failure_message("%s is %s" % [p.id, p.rarity]).is_true()
		# W.rarity_of knows it (the plate colour follows), and it is never the legendary plate
		assert_str(W.rarity_of(p)).is_equal(p.rarity)
		assert_str(p.rarity).is_not_equal("legendary")
		rarities[p.rarity] = true
	assert_int(rarities.size()).is_between(1, ITEM_RARITIES.size())
	assert_bool(rarities.has("common")).is_true()
	# every rarity any item names has a plate
	for p: PassiveDef in Registry.passives.values():
		assert_bool(W.RARITY_PLATE.has(p.rarity)).override_failure_message("%s: %s" % [p.id, p.rarity]).is_true()
	for w: WeaponDef in Registry.weapons.values():
		assert_bool(W.RARITY_PLATE.has(w.rarity)).override_failure_message("%s: %s" % [w.id, w.rarity]).is_true()


# ---------------------------------------------------------------- heroes

func test_the_title_shows_the_heroes_in_play_in_order_with_distinct_orders() -> void:
	var played: Array = Registry.sorted_characters()
	assert_bool(played.is_empty()).is_false()
	var want: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return not c.hidden)
	want.sort_custom(func(a: CharacterDef, b: CharacterDef) -> bool: return a.id < b.id if a.order == b.order else a.order < b.order)
	assert_array(played.map(func(c: CharacterDef) -> String: return c.id)).is_equal(want.map(func(c: CharacterDef) -> String: return c.id))
	var orders: Dictionary = {}
	for c: CharacterDef in played:
		assert_bool(c.hidden).is_false()
		assert_bool(orders.has(c.order)).override_failure_message("%s shares order %d with %s" % [c.id, c.order, str(orders.get(c.order, ""))]).is_false()
		orders[c.order] = c.id
		assert_str(c.availability).is_equal("available")
	for c: CharacterDef in Registry.characters.values():
		if c.hidden:
			assert_bool(played.has(c)).override_failure_message(c.id + " is hidden yet played").is_false()


func test_every_hero_in_play_is_whole() -> void:
	for c: CharacterDef in Registry.sorted_characters():
		# a gun to land with, a name, a trait in words
		assert_object(Registry.start_weapon_for(c)).override_failure_message(c.id + " has no start weapon").is_not_null()
		assert_str(c.display_name).override_failure_message(c.id).is_not_empty()
		assert_str(c.trait_text).override_failure_message(c.id + " has no trait text").is_not_empty()
		assert_bool(["he", "she", "they"].has(c.pronoun)).override_failure_message("%s: %s" % [c.id, c.pronoun]).is_true()
		if c.favourite_weapon != "":
			assert_object(Registry.weapon(c.favourite_weapon)).override_failure_message("%s's favourite %s is not there" % [c.id, c.favourite_weapon]).is_not_null()
		if c.favourite_passive != "":
			assert_object(Registry.passive(c.favourite_passive)).override_failure_message("%s's favourite %s is not there" % [c.id, c.favourite_passive]).is_not_null()
		# at least one perk in play
		assert_int(Registry.perks_of(c.id).size()).override_failure_message(c.id + " has no perk").is_greater_equal(1)
		# exactly one hero mutation, on his favourite weapon (on the weapon he starts with when his favourite is a passive:
		# Ironwood's Heartseeker on the Spear)
		var own: Array = Registry.hero_mutations(c.id)
		assert_int(own.size()).override_failure_message("%s has %d hero mutations" % [c.id, own.size()]).is_equal(1)
		if own.size() != 1:
			continue
		var m: MutationDef = own[0]
		var home := c.favourite_weapon if c.favourite_weapon != "" else Registry.start_weapon_for(c).id
		assert_str(m.weapon).override_failure_message("%s's %s sits on %s, not %s" % [c.id, m.id, m.weapon, home]).is_equal(home)
		assert_str(m.hero).is_equal(c.id)
		assert_bool(m.is_hero()).is_true()


func test_a_hidden_hero_has_no_mutation_in_play_and_his_perks_count_as_hidden() -> void:
	var hidden := 0
	for c: CharacterDef in Registry.characters.values():
		if not c.hidden:
			continue
		hidden += 1
		assert_array(Registry.hero_mutations(c.id)).override_failure_message(c.id).is_empty()
		for pk: PerkDef in Registry.perks.values():
			if pk.hero == c.id:
				assert_bool(Registry.is_hidden(pk)).override_failure_message(pk.id).is_true()
		for m: MutationDef in Registry.mutations.values():
			if m.hero == c.id:
				assert_bool(Registry.is_hidden(m)).override_failure_message(m.id).is_true()
	# the hidden heroes of the content are still there (Dad, Mira; pass 67 brought Buck back), kept for later
	assert_int(hidden).is_greater_equal(1)


func test_every_perk_names_a_hero_that_is_there() -> void:
	for pk: PerkDef in Registry.perks.values():
		assert_str(pk.hero).override_failure_message(pk.id + " names no hero").is_not_empty()
		assert_object(Registry.character(pk.hero)).override_failure_message("%s is %s's, who is not there" % [pk.id, pk.hero]).is_not_null()


# ---------------------------------------------------------------- creatures

func test_only_elites_wear_the_crown_and_every_plain_elite_does() -> void:
	var crowned: Array = []
	for d: EnemyDef in Registry.enemies.values():
		var crown := d.badge_for() == "crown"
		if crown:
			crowned.append(d.id)
		# a crown is an Elite's alone; an Elite wears one unless its JSON names another badge (the Boss dummy's skull)
		assert_bool(crown).override_failure_message("%s: archetype %s, badge '%s', wears %s" % [d.id, d.archetype, d.badge, d.badge_for()]).is_equal(d.archetype == "elite" and (d.badge == "" or d.badge == "crown"))
		assert_bool(["", "crown", "skull", "gear", "none"].has(d.badge)).override_failure_message("%s badge %s" % [d.id, d.badge]).is_true()
		# a boss wears the skull unless told otherwise
		if d.archetype == "boss" and d.badge == "":
			assert_str(d.badge_for()).is_equal("skull")
	# the Elites of the content, and the debug arena's Elite dummy (an Elite by its archetype so the items that care see one)
	assert_array(crowned).contains(["dune_scorpion", "sun_prophet", "stone_golem", "training_dummy_elite"])


func test_every_creature_carries_its_knockback_blood_and_doc() -> void:
	var n := 0
	for kind in ["enemies", "bosses"]:
		for id in DirAccess.get_directories_at("res://content/" + kind):
			var path := "res://content/%s/%s/%s.json" % [kind, id, id]
			if not FileAccess.file_exists(path):
				continue
			var j := _json(path)
			var def: EnemyDef = Registry.enemy(id)
			assert_object(def).override_failure_message(id + " did not load").is_not_null()
			if def == null:
				continue
			assert_str(def.id).is_equal(id)
			# the doc line the bible's creature table and the Collection read
			assert_str(str(j.get("doc", ""))).override_failure_message(id + " has no doc line").is_not_empty()
			assert_str(def.doc).override_failure_message(id).is_not_empty()
			# its own shove (pass 54; the dummies excepted: they never bite)
			if not id.begins_with("training_dummy"):
				assert_float(def.knockback).override_failure_message(id + " has no knockback of its own").is_greater(0.0)
				assert_float(float(j.get("knockback", 0.0))).override_failure_message(id).is_greater(0.0)
			# a blood colour that reaches the def (pass 58)
			var hex := str(j.get("blood", ""))
			assert_bool(hex.length() == 7 and hex.begins_with("#") and Color.html_is_valid(hex)).override_failure_message("%s blood '%s'" % [id, hex]).is_true()
			if Color.html_is_valid(hex):
				assert_bool(def.blood.is_equal_approx(Color.html(hex))).override_failure_message(id).is_true()
			# a body
			assert_float(def.hp).override_failure_message(id).is_greater(0.0)
			assert_float(def.size).override_failure_message(id).is_greater(0.0)
			assert_float(def.radius).override_failure_message(id).is_greater(0.0)
			assert_int(def.pack_size).override_failure_message(id).is_greater_equal(1)
			n += 1
	assert_int(n).is_equal(Registry.enemies.size())


func test_every_look_a_creature_names_resolves_and_the_played_one_is_among_them() -> void:
	for d: EnemyDef in Registry.enemies.values():
		if d.variants.is_empty():
			assert_str(d.variant).override_failure_message(d.id).is_equal("")
			continue
		assert_bool(d.variants.has(d.variant)).override_failure_message("%s plays %s, which it has not got" % [d.id, d.variant]).is_true()
		for code in d.variants.keys():
			var e: Dictionary = d.variants[code]
			assert_object(e.get("sprite")).override_failure_message("%s's look %s has no strip" % [d.id, str(code)]).is_not_null()
		# the played look is never shelved (the editor refuses it)
		assert_bool(d.variant_shelved(d.variant)).override_failure_message("%s plays a shelved look" % d.id).is_false()
	for c: CharacterDef in Registry.characters.values():
		if c.variants.is_empty():
			continue
		assert_bool(c.variants.has(c.variant)).override_failure_message("%s wears %s, which he has not got" % [c.id, c.variant]).is_true()
		assert_bool(c.variant_shelved(c.variant)).override_failure_message("%s wears a shelved look" % c.id).is_false()
		for code in c.variants.keys():
			assert_object((c.variants[code] as Dictionary).get("sprite")).override_failure_message("%s's look %s has no strip" % [c.id, str(code)]).is_not_null()


# ---------------------------------------------------------------- the map

func test_every_roster_row_plays_a_creature_in_play_in_a_look_it_has() -> void:
	for m: MapDef in Registry.maps.values():
		var tl: WaveTimeline = m.timeline
		if tl == null:
			continue
		for r in tl.roster:
			var id := str(r.get("enemy", ""))
			var d: EnemyDef = Registry.enemy(id)
			assert_object(d).override_failure_message("%s: unknown creature %s" % [m.id, id]).is_not_null()
			if d == null:
				continue
			assert_bool(d.retired or d.hidden).override_failure_message("%s: %s is retired or hidden" % [m.id, d.id]).is_false()
			var v := str(r.get("variant", ""))
			if v != "":
				assert_bool(d.variants.has(v)).override_failure_message("%s: %s has no look %s" % [m.id, d.id, v]).is_true()
		for ev in tl.events:
			var e = ev.get("enemy", "")
			for id in (e if e is Array else [e]):
				if str(id) != "":
					assert_object(Registry.enemy(str(id))).override_failure_message("%s: an event names %s" % [m.id, str(id)]).is_not_null()
		assert_object(Registry.enemy(m.boss)).override_failure_message("%s: boss %s" % [m.id, m.boss]).is_not_null()
