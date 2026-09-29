extends GdUnitTestSuite

## Pass 34: art variants to compare in the arena, four weapons and the sand lizard hidden (and the collection keeping
## the hidden apart), Wide Orbit breathing and batting creatures aside, Quickdraw as projectile speed only, more lines
## on stage 1, four new hero perks, the Big Mouth as a 3D model, the Stranger's offer with its name.


func after_test() -> void:
	Run.arena = false


# ---------------------------------------------------------------- hidden

func test_hidden_weapons_are_never_offered() -> void:
	var offered: Array = Registry.unlocked_weapons().map(func(w): return w.id)
	for id in ["branding_iron", "flare_gun", "poison_dart", "rattlesnake"]:
		var w: WeaponDef = Registry.weapon(id)
		assert_object(w).override_failure_message(id + " is gone from the content").is_not_null()
		assert_bool(w.hidden).override_failure_message(id + " is not hidden").is_true()
		assert_bool(offered.has(id)).override_failure_message(id + " is still offered").is_false()
		assert_bool(Registry.is_hidden(w)).is_true()
		# what only it brings is out of play too: its evolution and its paths
		if w.evolves_into != "":
			assert_bool(Registry.is_hidden(Registry.weapon(w.evolves_into))).override_failure_message(w.evolves_into + " is not hidden").is_true()
		for m: MutationDef in Registry.mutations_of(id):
			assert_bool(Registry.is_hidden(m)).is_true()
	# what is in play stays in play
	assert_bool(Registry.is_hidden(Registry.weapon("boomstick"))).is_false()
	assert_bool(Registry.is_hidden(Registry.weapon("tommy_gun"))).is_false()


func test_the_sand_lizard_is_out_of_the_waves() -> void:
	var lz: EnemyDef = Registry.enemy("sand_lizard")
	assert_bool(lz.hidden).is_true()
	assert_bool(Registry.is_hidden(lz)).is_true()
	var m: MapDef = Registry.map("red_canyon")
	for r in m.timeline.roster:
		assert_str(str(r["enemy"])).is_not_equal("sand_lizard")
	for ev in m.timeline.events:
		assert_str(str(ev.get("enemy", ""))).is_not_equal("sand_lizard")
	assert_str(str(m.skins.get("runner", ""))).is_not_equal("sand_lizard")
	# retired creatures count as hidden for the book
	assert_bool(Registry.is_hidden(Registry.enemy("skeleton"))).is_true()
	assert_bool(Registry.is_hidden(Registry.enemy("goblin"))).is_false()


# ---------------------------------------------------------------- items

func test_quickdraw_is_projectile_speed_only() -> void:
	var q: PassiveDef = Registry.passive("quickdraw")
	var stats: Array = []
	for lv in q.levels:
		for e: Effect in lv:
			stats.append(e.stat)
	assert_bool(stats.has("cooldown")).is_false()
	assert_bool(stats.has("projectile_speed")).is_true()


func test_wide_orbit_breathes_and_bats_aside() -> void:
	var m: MutationDef = Registry.mutation("wide_orbit")
	assert_object(m).is_not_null()
	var b: Dictionary = m.params.get("breathe", {})
	assert_float(float(b.get("min", 0.0))).is_equal_approx(0.9, 0.001)
	assert_float(float(b.get("max", 0.0))).is_equal_approx(1.6, 0.001)
	var s: Dictionary = m.params.get("side_knock", {})
	assert_float(float(s.get("every", 0.0))).is_equal_approx(1.0, 0.001)
	# no pull towards the hero any more
	for e: Effect in m.effects:
		assert_str(e.stat).is_not_equal("pull")


func test_more_lines_on_stage_one() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	assert_int(Run.line_cap()).is_greater(2)
	var opened := 0
	for l: LineDef in Registry.sorted_lines():
		if Run.add_or_rank_line(l.id):
			opened += 1
		if opened >= 3:
			break
	assert_int(Run.lines.size()).is_equal(3)


# ---------------------------------------------------------------- perks

func test_each_hero_has_two_new_perks() -> void:
	for pair in [["astro", "supply_drop"], ["astro", "thruster_burst"], ["drifter", "high_noon"], ["drifter", "bounty_hunter"]]:
		var pk: PerkDef = Registry.perks.get(pair[1])
		assert_object(pk).override_failure_message(pair[1] + " missing").is_not_null()
		assert_str(pk.hero).is_equal(pair[0])
		assert_str(pk.special).is_equal(pair[1])
		assert_bool(Registry.perks_of(pair[0]).has(pk)).is_true()
	assert_float(float(Registry.perks["high_noon"].params.get("slow", 1.0))).is_less(1.0)


func test_high_noon_slows_the_crowd_clock() -> void:
	var em := EnemyManager.new()
	assert_float(em.time_scale).is_equal_approx(1.0, 0.0001)
	em.free()


# ---------------------------------------------------------------- art variants

func test_goblins_carry_art_variants() -> void:
	for id in ["goblin", "goblin_runt"]:
		var d: EnemyDef = Registry.enemy(id)
		assert_str(d.variant).is_not_empty()
		assert_bool(d.variants.has(d.variant)).is_true()
		# the game's own art is the variant in use: its copy is the def itself
		assert_object(d.variant_def(d.variant)).is_same(d)
		assert_str(d.type_key()).is_equal(id)


func test_a_variant_is_its_own_type() -> void:
	var d: EnemyDef = Registry.enemy("goblin")
	var codes: Array = d.variant_codes()
	if codes.size() < 2:
		return
	var other := ""
	for c in codes:
		if str(c) != d.variant:
			other = str(c)
			break
	var v: EnemyDef = d.variant_def(other)
	assert_object(v).is_not_same(d)
	assert_str(v.type_key()).is_equal("goblin@" + other)
	assert_object(v.sprite).is_not_null()
	assert_object(v.sprite).is_not_same(d.sprite)
	var em := EnemyManager.new()
	add_child(em)
	var a := em.register_type(d)
	var b := em.register_type(v)
	assert_int(b).is_not_equal(a)
	assert_int(em.register_type(d.variant_def(other))).is_equal(b)
	em.queue_free()


# ---------------------------------------------------------------- the Big Mouth

func test_the_big_mouth_is_a_model_with_a_jaw() -> void:
	var s: PackedScene = load("res://content/weapons/big_mouth/big_mouth_visual.tscn")
	var n: Node = s.instantiate()
	var mouth: Node = n.get_node_or_null("Familiar/Mouth")
	assert_object(mouth).override_failure_message("no 3D mouth under the Familiar").is_not_null()
	assert_object(mouth.find_child("Jaw", true, false)).is_not_null()
	n.free()


func test_a_variant_brings_its_own_icon() -> void:
	var d: EnemyDef = Registry.enemy("goblin")
	for code in d.variant_codes():
		var e: Dictionary = d.variants[code]
		assert_object(e.get("icon")).override_failure_message(str(code) + " has no icon").is_not_null()
	var other := ""
	for code in d.variant_codes():
		if str(code) != d.variant:
			other = str(code)
			break
	if other != "":
		assert_object(d.variant_def(other).icon).is_same(d.variants[other]["icon"])


func test_content_images_import_lossy() -> void:
	# every PNG in a content folder imports lossy (tools/lossy_imports.py, run by ship.sh): a lossless strip adds a
	# megabyte or more to the APK
	var bad: Array = []
	_walk_imports("res://content", bad)
	assert_array(bad).override_failure_message("lossless imports: " + str(bad)).is_empty()


func _walk_imports(path: String, bad: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_walk_imports(path.path_join(sub), bad)
	for f in dir.get_files():
		if f.ends_with(".png.import"):
			var t := FileAccess.get_file_as_string(path.path_join(f))
			if t.contains("compress/mode=0"):
				bad.append(f)
