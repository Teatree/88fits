extends GdUnitTestSuite

## Pass 81, lane PROD (Garry: "It's time to make a production build version ... no debug options, no extra art (unless
## it's used in the Level timeline)"): the production switch (Settings.is_prod, forced here as the prod presets'
## feature `prod` would) hides every developer surface and keeps it hidden; the reachability the pruner works from
## (tools/prod_reach.gd) keeps every hero in play, every creature, boss and summon the map brings, every item in play
## with its path and evolution, and the looks the game plays or the timeline names, and drops the hidden rest; the
## Python pruner's own fixture check passes.

const REACH := preload("res://tools/prod_reach.gd")

var _plan: Dictionary = {}
var _saved_settings: Dictionary = {}


func before_test() -> void:
	_saved_settings = Settings.to_dict()


func after_test() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_saved_settings)
	Run.launch_override = {}
	Run.arena_next = false
	if FileAccess.file_exists("user://debug_launch.json"):
		DirAccess.remove_absolute("user://debug_launch.json")
	get_tree().paused = false


func _p() -> Dictionary:
	if _plan.is_empty():
		_plan = REACH.plan(Registry)
	return _plan


func _kept(def) -> bool:
	return (_p()["keep"] as Dictionary).has(REACH.folder_of(def))


const DEBUG_ON := {"debug_mode": true, "debug_panel": true, "debug_modal_buttons": true, "free_revive_button": true,
	"hit_log": true, "preview_locked_heroes": true, "menu_style": "painted", "ranged_on_screen": false, "pierce_falloff": false}


# ---------------------------------------------------------------- the switch

func test_the_dev_build_is_not_prod_and_keeps_its_switches() -> void:
	assert_bool(Settings.is_prod()).is_false()
	assert_str(Settings.build_flavour()).is_equal("dev")
	Settings.from_dict(DEBUG_ON)
	assert_bool(Settings.debug_mode).is_true()
	assert_bool(Settings.hit_log).is_true()
	assert_str(Settings.menu_style).is_equal("painted")


func test_prod_locks_every_developer_switch_at_the_players_default() -> void:
	Settings.from_dict(DEBUG_ON)
	Settings.force_prod(true)
	assert_bool(Settings.is_prod()).is_true()
	assert_str(Settings.build_flavour()).is_equal("prod")
	for k: String in Settings.PROD_LOCKED:
		assert_that(Settings.get(k)).override_failure_message("%s after force_prod" % k).is_equal(Settings.PROD_LOCKED[k])
	# a save written by a dev build with everything on reads back locked
	Settings.from_dict(DEBUG_ON)
	for k: String in Settings.PROD_LOCKED:
		assert_that(Settings.get(k)).override_failure_message("%s after from_dict" % k).is_equal(Settings.PROD_LOCKED[k])
	# and nothing sets them again; the player's own settings still do
	for k: String in DEBUG_ON:
		Settings.set_value(k, DEBUG_ON[k])
		assert_that(Settings.get(k)).override_failure_message("%s after set_value" % k).is_equal(Settings.PROD_LOCKED[k])
	var vol := Settings.sfx_volume
	Settings.set_value("sfx_volume", 0.25)
	assert_float(Settings.sfx_volume).is_equal(0.25)
	Settings.sfx_volume = vol
	# back to the dev build
	Settings.force_prod(false)
	assert_bool(Settings.is_prod()).is_false()
	Settings.set_value("debug_panel", true)
	assert_bool(Settings.debug_panel).is_true()


func test_analytics_tags_every_event_with_the_build_flavour() -> void:
	var p: Dictionary = Analytics.super_properties()
	assert_str(str(p.get("build"))).is_equal("dev")
	Settings.force_prod(true)
	assert_str(str(Analytics.super_properties().get("build"))).is_equal("prod")


func test_prod_ignores_a_tools_launch_file_and_leaves_it() -> void:
	var g: Node = auto_free(load("res://game/Game.gd").new())
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"arena": true, "character": "dad"}))
	f.close()
	Run.launch_override = {"sim_fast": true}
	Settings.force_prod(true)
	assert_dict(g._read_debug_launch()).is_empty()
	assert_dict(Run.launch_override).is_empty()
	assert_bool(FileAccess.file_exists("user://debug_launch.json")).is_true()
	# the dev build reads it (and removes it)
	Settings.force_prod(false)
	var d: Dictionary = g._read_debug_launch()
	assert_bool(bool(d.get("arena", false))).is_true()
	assert_bool(FileAccess.file_exists("user://debug_launch.json")).is_false()


func test_prod_settings_screen_has_no_debug_taps_no_hold_and_no_debug_panel() -> void:
	Settings.force_prod(true)
	var s: Control = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	for i in 12:
		s._count_hint_tap()
	assert_bool(Settings.debug_mode).is_false()
	assert_object(s.find_child("DebugPanel", true, false)).is_null()
	var down := InputEventScreenTouch.new()
	down.pressed = true
	s._on_version_input(down)
	assert_bool(s._holding).is_false()
	s.visible = false


func test_the_dev_settings_screen_still_has_its_ten_taps_and_its_hold() -> void:
	var was := Settings.debug_mode
	var s: Control = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	var down := InputEventScreenTouch.new()
	down.pressed = true
	s._on_version_input(down)
	assert_bool(s._holding).is_true()
	s._holding = false
	for i in 10:
		s._count_hint_tap()
	assert_bool(Settings.debug_mode).is_not_equal(was)
	Settings.debug_mode = was
	s.visible = false


func test_prod_developer_menu_builds_nothing_and_goes_back() -> void:
	Settings.force_prod(true)
	var m: Control = auto_free(load("res://ui/DevMenu.tscn").instantiate())
	add_child(m)
	await get_tree().process_frame
	assert_object(m.get("_list")).is_null()
	assert_int(m.get_child_count()).is_equal(0)
	# the fade it started back to Settings (freed at once here: its tween would change the test runner's scene)
	var fades := get_tree().root.get_children().filter(func(n: Node) -> bool: return n is CanvasLayer and n.layer == 100)
	assert_bool(fades.is_empty()).is_false()
	for n: Node in fades:
		n.free()


func test_prod_title_never_shows_the_arena() -> void:
	Settings.force_prod(true)
	Settings.debug_mode = true   # as if a save had slipped it through: the title asks is_prod itself too
	Settings.menu_style = "painted"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	var b: Control = t.find_child("ArenaButton", true, false)
	assert_object(b).is_not_null()
	assert_bool(b.visible).is_false()
	t.visible = false


# ---------------------------------------------------------------- the reachability

func test_every_hero_in_play_and_what_he_brings_is_kept_and_the_hidden_ones_go() -> void:
	for c: CharacterDef in Registry.characters.values():
		if c.hidden:
			assert_bool(_kept(c)).override_failure_message("hidden hero %s kept" % c.id).is_false()
			continue
		assert_bool(_kept(c)).override_failure_message("hero %s dropped" % c.id).is_true()
		assert_bool(_kept(Registry.start_weapon_for(c))).override_failure_message("%s's start weapon" % c.id).is_true()
		if c.favourite_weapon != "":
			assert_bool(_kept(Registry.weapon(c.favourite_weapon))).is_true()
		if c.favourite_passive != "":
			assert_bool(_kept(Registry.passive(c.favourite_passive))).is_true()
		for p in Registry.perks_of(c.id):
			assert_bool(_kept(p)).override_failure_message("%s's perk %s" % [c.id, p.id]).is_true()
		for m in Registry.hero_mutations(c.id):
			assert_bool(_kept(m)).override_failure_message("%s's hero mutation %s" % [c.id, m.id]).is_true()


func test_every_item_in_play_with_its_path_and_evolution_is_kept() -> void:
	for w: WeaponDef in Registry.base_weapons():
		if w.hidden:
			continue
		assert_bool(_kept(w)).override_failure_message("weapon %s" % w.id).is_true()
		if w.evolves_into != "":
			assert_bool(_kept(Registry.weapon(w.evolves_into))).override_failure_message("%s's evolution" % w.id).is_true()
		for m in Registry.mutations_of(w.id):
			assert_bool(_kept(m)).override_failure_message("%s's path %s" % [w.id, m.id]).is_true()
	for p: PassiveDef in Registry.base_passives():
		assert_bool(_kept(p)).override_failure_message("passive %s" % p.id).is_true()
		if p.evolves_into != "":
			assert_bool(_kept(Registry.passive(p.evolves_into))).override_failure_message("%s's evolution" % p.id).is_true()
	for dict_name in ["talents", "elites", "pickups", "structures"]:
		for d in (Registry.get(dict_name) as Dictionary).values():
			if not d.hidden:
				assert_bool(_kept(d)).override_failure_message("%s %s" % [dict_name, d.id]).is_true()


## Every string a JSON holds (the test's own walk, independent of the reach's).
func _strings(x, out: Dictionary) -> Dictionary:
	if x is Dictionary:
		for k in x:
			_strings(x[k], out)
	elif x is Array:
		for v in x:
			_strings(v, out)
	elif x is String:
		out[x] = true
	return out


func test_every_creature_boss_and_summon_the_map_brings_is_kept_with_the_looks_it_names() -> void:
	var map: MapDef = Registry.map("red_canyon")
	var raw: Dictionary = REACH.raw_json(map)
	var named := _strings(raw, {})
	var n := 0
	for id: String in named:
		var e: EnemyDef = Registry.enemy(id)
		if e != null:
			n += 1
			assert_bool(_kept(e)).override_failure_message("map names %s" % id).is_true()
	assert_int(n).is_greater(10)
	for arch in map.skins:
		assert_bool(_kept(Registry.enemy(str(map.skins[arch])))).is_true()
	for boss_id in ["tumbleweed_king", "gila_grande", "brander"]:
		var b: EnemyDef = Registry.enemy(boss_id)
		assert_bool(_kept(b)).override_failure_message("boss %s" % boss_id).is_true()
		# his summons (the Gila's sand lizards are hidden creatures, yet they come)
		for s: String in _strings(REACH.raw_json(b), {}):
			var e: EnemyDef = Registry.enemy(s)
			if e != null:
				assert_bool(_kept(e)).override_failure_message("%s summons %s" % [boss_id, s]).is_true()
	assert_bool(_kept(Registry.enemy("sand_lizard"))).is_true()
	# every look a roster row or an event names, and each creature's own
	var looks: Dictionary = _p()["looks"]
	for row in (raw["timeline_data"]["roster"] as Array) + (raw["timeline_data"]["events"] as Array):
		if row is Dictionary and row.get("variant") is String and row.get("enemy") is String:
			var key := REACH.folder_of(Registry.enemy(str(row["enemy"])))
			assert_bool(looks.has(key)).override_failure_message("%s has no looks entry" % key).is_true()
			assert_array(looks[key]["keep"]).override_failure_message("%s %s" % [key, row["variant"]]).contains([str(row["variant"])])
	# the codes each creature's rows name (pass 115, the lead: look codes are per creature: Garry's spit_cactus row naming
	# SC-B must not count for the dune scorpion's own SC-B, which the plan rightly drops)
	var named_by: Dictionary = {}
	for row in (raw["timeline_data"]["roster"] as Array) + (raw["timeline_data"]["events"] as Array):
		if row is Dictionary and row.get("variant") is String and row.get("enemy") is String and Registry.enemy(str(row["enemy"])) != null:
			var fk := REACH.folder_of(Registry.enemy(str(row["enemy"])))
			if not named_by.has(fk):
				named_by[fk] = {}
			(named_by[fk] as Dictionary)[str(row["variant"])] = true
	for key: String in looks:
		var lk: Dictionary = looks[key]
		assert_array(lk["keep"]).contains([str(lk["play"])])
		for code in lk["drop"]:
			var mine: bool = named_by.has(key) and (named_by[key] as Dictionary).has(str(code))
			assert_bool(mine and lk["kind"] == "creature").override_failure_message("%s drops %s, which the map names" % [key, code]).is_false()


func test_heroes_and_cards_keep_only_the_look_they_play() -> void:
	var looks: Dictionary = _p()["looks"]
	for c: CharacterDef in Registry.sorted_characters():
		var key := REACH.folder_of(c)
		if not looks.has(key):
			continue
		# pass 111 (lane SKINS): and every look sold as a skin, after it
		var want: Array = [c.variant]
		for code in c.variants.keys():
			if c.sells_skin(str(code)):
				want.append(str(code))
		assert_array(looks[key]["keep"]).contains_exactly_in_any_order(want)
		assert_str(str(looks[key]["keep"][0])).is_equal(c.variant)
		assert_bool(bool(looks[key]["promote"])).is_equal(c.variant != str(REACH.raw_json(c).get("variant_base", "")))
	for p: PassiveDef in Registry.base_passives():
		var key := REACH.folder_of(p)
		if looks.has(key):
			assert_array(looks[key]["keep"]).is_equal([p.variant])


func test_nothing_hidden_is_kept_unless_something_brings_it() -> void:
	var keep: Dictionary = _p()["keep"]
	for key: String in keep:
		var why := str(keep[key])
		var type := key.get_slice("/", 0)
		var id := key.get_slice("/", 1)
		var d = null
		match type:
			"weapons", "evolutions":
				d = Registry.weapon(id)
			"passives":
				d = Registry.passive(id)
			"mutations":
				d = Registry.mutation(id)
			"perks":
				d = Registry.perk(id)
			"enemies", "bosses":
				d = Registry.enemy(id)
			"characters":
				d = Registry.character(id)
			"pickups":
				d = Registry.pickup(id)
			"structures":
				d = Registry.structure(id)
		if d == null or not Registry.is_hidden(d):
			continue
		# a hidden thing stays only when the map, a creature, a boss or the code names it
		assert_bool(why.begins_with("named by")).override_failure_message("hidden %s kept: %s" % [key, why]).is_true()
	var drop: Dictionary = _p()["drop"]
	for key in ["characters/dad", "enemies/training_dummy", "enemies/training_dummy_boss", "structures/gold_bank"]:
		if DirAccess.dir_exists_absolute("res://content/" + key):
			assert_bool(drop.has(key)).override_failure_message("%s not dropped" % key).is_true()
	# a quest stays only for what is kept
	for q: QuestDef in Registry.quests.values():
		var what = Registry.unlocked_by(q)
		if keep.has(REACH.folder_of(q)) and what != null:
			assert_bool(keep.has(REACH.folder_of(what))).override_failure_message("quest %s for a dropped item" % q.id).is_true()


func test_the_code_pins_skip_the_debug_scripts() -> void:
	for pin: Array in REACH.code_pins(Registry):
		assert_bool(["ArenaPanel.gd", "DebugPanel.gd", "DebugHand.gd", "DevMenu.gd"].has(str(pin[2]))).is_false()


func test_the_python_pruner_passes_its_fixture() -> void:
	var out: Array = []
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var code := OS.execute("python", [root.path_join("tools/prod_prune.py"), "--selftest"], out, true)
	assert_int(code).override_failure_message("prod_prune.py --selftest: %s" % "\n".join(out)).is_equal(0)
