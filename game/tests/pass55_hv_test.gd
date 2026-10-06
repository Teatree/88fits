extends GdUnitTestSuite

## Pass 55, lane HV (Garry: "an option in the hero tab of the Arena Debug menu which allows switching between heroes on
## the fly", "the option to choose between different Art variants, like we do for the enemies" and "to choose which art
## should be used from that point onwards"): a hero carries art variants as the creatures do (CharacterDef.variants,
## variant, variant_def), the look kept for him (Save.hero_look) wins over his JSON's and a code he no longer has falls
## back to it, the arena shows a look for the visit only (Player.show_look), Game.arena_swap_hero swaps the trait and the
## sprite and keeps the items, the kept look outlives the arena's sandbox, the live title draws the kept look, and the
## HERO tab's tiles, chips and USE FROM NOW ON do what they say. The looks are a stub built here (Solenne's own SOL-B..D
## may not be painted yet): look A is her strip, look B the Drifter's, so the two are told apart by their textures.

const Stage := preload("res://ui/TitleStage.gd")

var _keep_debug := false
var _keep_style := ""


func before_test() -> void:
	Save.data = Save._default()
	_keep_debug = Settings.debug_mode
	_keep_style = Settings.menu_style
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	if Save.sandboxed():
		Save.end_sandbox()
	Save.data = Save._default()
	Save._dirty = false
	Settings.debug_mode = _keep_debug
	Settings.menu_style = _keep_style
	Stage.forget()
	Run.arena = false
	Run.debug_clear_items()
	Run.end()


## Solenne with two looks: A her own strip (the JSON's look), B the Drifter's strip with its own frames and speeds.
func _two_looks() -> CharacterDef:
	var sol: CharacterDef = Registry.character("solenne")
	var dri: CharacterDef = Registry.character("drifter")
	var c: CharacterDef = sol.duplicate()
	c.variants = {
		"A": {"sprite": sol.sprite, "sprite_file": sol.sprite_file, "anims": sol.anims, "fps": sol.fps, "strip_cols": sol.strip_cols,
			"frame_px": sol.frame_px, "icon": sol.icon, "note": "her own"},
		"B": {"sprite": dri.sprite, "sprite_file": dri.sprite_file, "anims": dri.anims, "fps": dri.fps, "strip_cols": dri.strip_cols,
			"frame_px": dri.frame_px, "icon": sol.icon, "note": "another strip"},
	}
	c.variant = "A"
	c.sprite = sol.sprite
	c.anims = sol.anims
	c.fps = sol.fps
	c.strip_cols = sol.strip_cols
	return c


func _hero(def: CharacterDef) -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	p.setup(def)
	add_child(p)
	return p


func _drawn(p: Player) -> Texture2D:
	return (p.sprite.material_override as ShaderMaterial).get_shader_parameter("sprite")


## A bare Game in the arena round a real hero: what arena_swap_hero and the HERO tab need.
func _arena(def: CharacterDef) -> Game:
	Run.arena = true
	var game: Game = auto_free(Game.new())
	game.player = _hero(def)
	return game


# ---------------------------------------------------------------- the def

func test_variant_def_swaps_the_art_and_keeps_the_identity() -> void:
	var c := _two_looks()
	var dri: CharacterDef = Registry.character("drifter")
	var b := c.variant_def("B")
	assert_object(b).is_not_same(c)
	assert_object(b.sprite).is_same(dri.sprite)
	assert_dict(b.anims).is_equal(dri.anims)
	assert_dict(b.fps).is_equal(dri.fps)
	assert_int(b.strip_cols).is_equal(dri.strip_cols)
	assert_str(b.look_code()).is_equal("B")
	# everything but the art is hers
	assert_str(b.id).is_equal("solenne")
	assert_str(b.display_name).is_equal(c.display_name)
	assert_str(b.start_weapon).is_equal(c.start_weapon)
	assert_str(b.pronoun).is_equal("she")
	assert_int(b.trait_effects.size()).is_equal(c.trait_effects.size())
	assert_str(b.favourite_passive).is_equal(c.favourite_passive)
	# the look it wears already is itself; the def's own look from the copy is a copy with her strip again
	assert_object(c.variant_def("A")).is_same(c)
	assert_object(b.variant_def("B")).is_same(b)
	assert_object(b.variant_def("A").sprite).is_same(c.sprite)
	assert_array(c.variant_codes()).is_equal(["A", "B"])
	assert_str(c.variant_note("B")).is_equal("another strip")


func test_a_hero_without_variants_is_unchanged() -> void:
	var astro: CharacterDef = Registry.character("astro")
	assert_array(astro.variant_codes()).is_empty()
	assert_object(astro.variant_def("SOL-B")).is_same(astro)
	assert_object(astro.variant_def("")).is_same(astro)
	# and a hero drawn without a kept look is drawn from his own strip, as before
	var p := _hero(astro)
	assert_object(_drawn(p)).is_same(astro.sprite)
	assert_str(p.look_code()).is_equal("")
	# a JSON with no looks builds as it always did
	var d: Dictionary = JsonContent.load_json("res://content/characters/astro/astro.json")
	var built := JsonContent.build("characters", d, "res://content/characters/astro/") as CharacterDef
	assert_dict(built.variants).is_empty()
	assert_str(built.variant).is_equal("")
	assert_str(built.sprite_file).is_equal(astro.sprite_file)


func test_the_json_loads_the_looks_and_drops_one_without_a_strip() -> void:
	var d: Dictionary = JsonContent.load_json("res://content/characters/solenne/solenne.json")
	d["variant_base"] = "SOL-A"
	d["variant"] = "SOL-A"
	d["variants"] = {"SOL-A": {"note": "Walking_sun"},
		"SOL-B": {"note": "a walk", "sprite": "res://content/characters/drifter/drifter_sprite.png", "strip_cols": 7, "fps": {"run": 20}},
		"SOL-C": {"note": "not painted yet", "sprite": "solenne_sprite_c_missing.png"}}
	var c := JsonContent.build("characters", d, "res://content/characters/solenne/") as CharacterDef
	assert_array(c.variant_codes()).is_equal(["SOL-A", "SOL-B"])
	assert_str(c.variant).is_equal("SOL-A")
	assert_str(c.sprite_file).is_equal("solenne_sprite.png")
	assert_str(c.variant_note("SOL-A")).is_equal("Walking_sun")
	var b := c.variant_def("SOL-B")
	assert_object(b.sprite).is_same(Registry.character("drifter").sprite)
	assert_int(b.strip_cols).is_equal(7)
	assert_dict(b.fps).is_equal({"run": 20})
	# the variant entry without anims takes the hero's
	assert_dict(b.anims).is_equal(c.anims)
	# one word in the JSON switches the look the game plays; the base look is a copy with the top-level strip
	d["variant"] = "SOL-B"
	var c2 := JsonContent.build("characters", d, "res://content/characters/solenne/") as CharacterDef
	assert_str(c2.variant).is_equal("SOL-B")
	assert_object(c2.sprite).is_same(Registry.character("drifter").sprite)
	assert_str(c2.variant_def("SOL-A").sprite_file).is_equal("solenne_sprite.png")
	# a look the JSON names but that did not load plays the base one
	d["variant"] = "SOL-C"
	var c3 := JsonContent.build("characters", d, "res://content/characters/solenne/") as CharacterDef
	assert_str(c3.variant).is_equal("SOL-A")


# ---------------------------------------------------------------- the kept look

func test_the_saved_look_wins_over_the_json_and_a_missing_code_falls_back() -> void:
	var c := _two_looks()
	Save.set_hero_look("solenne", "B")
	assert_str(Save.hero_look("solenne")).is_equal("B")
	var p := _hero(c)
	assert_str(p.look_code()).is_equal("B")
	assert_object(_drawn(p)).is_same(Registry.character("drifter").sprite)
	assert_str(p.character.id).is_equal("solenne")
	# a kept code the hero no longer has: his JSON's look
	Save.set_hero_look("solenne", "Z")
	var q := _hero(c)
	assert_str(q.look_code()).is_equal("A")
	assert_object(_drawn(q)).is_same(Registry.character("solenne").sprite)
	# nothing kept: the JSON's
	Save.set_hero_look("solenne", "")
	assert_str(Save.hero_look("solenne")).is_equal("")
	assert_bool((Save.data["hero_look"] as Dictionary).has("solenne")).is_false()


func test_show_look_is_for_this_visit_only() -> void:
	var c := _two_looks()
	var p := _hero(c)
	assert_str(p.look_code()).is_equal("A")
	p.show_look("B")
	assert_str(p.look_code()).is_equal("B")
	assert_object(_drawn(p)).is_same(Registry.character("drifter").sprite)
	assert_str(Save.hero_look("solenne")).is_equal("")
	# the hit pose reads the look's frames: the Drifter's flinch
	assert_dict(p.look.anims).is_equal(Registry.character("drifter").anims)
	# another hero starts on his own kept look
	p.setup(Registry.character("astro"))
	assert_str(p.look_override).is_equal("")
	assert_object(_drawn(p)).is_same(Registry.character("astro").sprite)


func test_a_kept_look_outlives_the_arena_sandbox() -> void:
	Save.data["gold"] = 5
	Save.save_now()
	Save.begin_sandbox()
	Save.add_gold(500)
	Save.set_hero_look("solenne", "SOL-B")
	assert_str(Save.hero_look("solenne")).is_equal("SOL-B")
	# on disk at once, with the gold as it was before the arena
	var on_disk = JSON.parse_string(FileAccess.get_file_as_string(Save.path()))
	assert_str(str((on_disk["hero_look"] as Dictionary).get("solenne", ""))).is_equal("SOL-B")
	assert_int(int(on_disk["gold"])).is_equal(5)
	Save.end_sandbox()
	assert_bool(Save.sandboxed()).is_false()
	assert_str(Save.hero_look("solenne")).is_equal("SOL-B")
	assert_int(Save.gold()).is_equal(5)
	# and a load from the file keeps it
	Save.load_save()
	assert_str(Save.hero_look("solenne")).is_equal("SOL-B")


# ---------------------------------------------------------------- the arena's swap

func test_arena_swap_hero_swaps_the_trait_and_the_sprite_and_keeps_the_items() -> void:
	Run.start(Registry.character("solenne"), Registry.map("red_canyon"))
	var want_hp: float = Run.player_sheet.get_stat("max_hp", 100.0)
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var game := _arena(Registry.character("astro"))
	var p := game.player
	var astro_hp: float = p.max_hp
	assert_float(astro_hp).is_greater(want_hp)
	Run.debug_set_item("weapon", "peashooter", 2)
	Run.add_perk("supply_drop")
	Run.add_perk("high_noon")
	p.god = true
	assert_bool(game.arena_swap_hero("solenne")).is_true()
	assert_str(Run.character.id).is_equal("solenne")
	assert_object(Run.character).is_same(Registry.character("solenne"))
	assert_object(p.character).is_same(Registry.character("solenne"))
	assert_float(p.max_hp).is_equal_approx(want_hp, 0.001)
	assert_float(Run.player_sheet.get_stat("max_hp", 0.0)).is_equal_approx(want_hp, 0.001)
	# her look on him
	var look: CharacterDef = Registry.character("solenne").variant_def(Save.hero_look("solenne"))
	assert_object(_drawn(p)).is_same(look.sprite)
	# the items stay, Astro's perk went, the Drifter's handed over in ITEMS stays, god mode as it was
	assert_int(Run.weapon_instance("peashooter").level).is_equal(2)
	assert_bool(Run.has_perk("supply_drop")).is_false()
	assert_bool(Run.has_perk("high_noon")).is_true()
	assert_bool(p.god).is_true()
	# no start weapon handed over
	assert_object(Run.weapon_instance("sun_scepter")).is_null()


func test_a_swap_to_the_hero_playing_or_outside_the_arena_does_nothing() -> void:
	var game := _arena(Registry.character("astro"))
	assert_bool(game.arena_swap_hero("astro")).is_false()
	assert_bool(game.arena_swap_hero("nobody")).is_false()
	Run.arena = false
	assert_bool(game.arena_swap_hero("drifter")).is_false()
	assert_str(Run.character.id).is_equal("astro")


func test_bucks_momentum_comes_and_goes_with_him() -> void:
	var game := _arena(Registry.character("astro"))
	var buck: CharacterDef = Registry.character("buck")
	assert_bool(game.arena_swap_hero("buck")).is_true()
	assert_dict(Run.momentum_def).is_equal(buck.momentum)
	assert_bool(game.player.momentum).is_true()
	Run.momentum = 0.5
	assert_bool(game.arena_swap_hero("astro")).is_true()
	assert_float(Run.momentum).is_equal(0.0)
	assert_dict(Run.momentum_def).is_empty()
	assert_bool(game.player.momentum).is_false()


# ---------------------------------------------------------------- the title

func test_the_live_title_draws_the_kept_look() -> void:
	Settings.menu_style = "live"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	var stage = t._stage
	var c := _two_looks()
	Save.set_hero_look("solenne", "B")
	stage.show_hero(c, false, 0)
	await get_tree().process_frame
	var mat := stage.hero_sprite().material_override as ShaderMaterial
	assert_object(mat.get_shader_parameter("sprite")).is_same(Registry.character("drifter").sprite)
	Save.set_hero_look("solenne", "")
	stage.show_hero(c, false, 0)
	await get_tree().process_frame
	mat = stage.hero_sprite().material_override as ShaderMaterial
	assert_object(mat.get_shader_parameter("sprite")).is_same(Registry.character("solenne").sprite)


# ---------------------------------------------------------------- the HERO tab

func _panel(game: Game) -> ArenaPanel:
	var panel: ArenaPanel = auto_free(ArenaPanel.new())
	panel.game = game
	add_child(panel)
	# its status line reads the director and the crowd, which a bare game has not got
	panel.set_process(false)
	panel._tab = "hero"
	panel._refresh()
	return panel


func test_the_hero_tab_has_a_tile_per_hero_and_a_tap_swaps() -> void:
	Settings.debug_mode = false
	var game := _arena(Registry.character("astro"))
	var panel := _panel(game)
	for c: CharacterDef in Registry.sorted_characters():
		assert_object(panel._content.find_child("Hero_" + c.id, true, false)).override_failure_message(c.id).is_not_null()
	# the ones out of play only with the debug mode on
	assert_object(panel._content.find_child("Hero_buck", true, false)).is_null()
	Settings.debug_mode = true
	panel._refresh()
	var buck_tile: Control = panel._content.find_child("Hero_buck", true, false)
	assert_object(buck_tile).is_not_null()
	assert_float(buck_tile.modulate.a).is_less(1.0)
	# a tap on the Drifter's tile swaps him in and closes the sheet
	panel._sheet.visible = true
	var tile: Control = panel._content.find_child("Hero_drifter", true, false)
	tile.pressed.emit()
	assert_str(Run.character.id).is_equal("drifter")
	assert_bool(panel.is_open()).is_false()
	await get_tree().process_frame


func test_the_looks_show_for_the_visit_and_use_from_now_on_keeps_one() -> void:
	var c := _two_looks()
	var game := _arena(c)
	Run.character = c
	var panel := _panel(game)
	var a: Button = panel._content.find_child("Look_A", true, false)
	var b: Button = panel._content.find_child("Look_B", true, false)
	assert_object(a).is_not_null()
	assert_object(b).is_not_null()
	assert_str(a.text).is_equal("A ● · RUNS")
	assert_str(b.text).is_equal("B")
	var keep: Button = panel._content.find_child("KeepLook", true, false)
	assert_bool(keep.disabled).is_true()
	# B on him for this visit: nothing kept yet
	b.pressed.emit()
	assert_str(game.player.look_code()).is_equal("B")
	assert_object(_drawn(game.player)).is_same(Registry.character("drifter").sprite)
	assert_str(Save.hero_look("solenne")).is_equal("")
	panel._refresh()
	keep = panel._content.find_child("KeepLook", true, false)
	assert_bool(keep.disabled).is_false()
	assert_str(keep.text).is_equal("USE B FROM NOW ON")
	assert_str((panel._content.find_child("Look_B", true, false) as Button).text).is_equal("B ●")
	keep.pressed.emit()
	assert_str(Save.hero_look("solenne")).is_equal("B")
	assert_str((panel._content.find_child("Look_B", true, false) as Button).text).is_equal("B ● · RUNS")
	assert_str((panel._content.find_child("Look_A", true, false) as Button).text).is_equal("A")
	var said := false
	for l in panel._content.find_children("*", "Label", true, false):
		if (l as Label).text == "Runs use B.":
			said = true
	assert_bool(said).is_true()
	await get_tree().process_frame


func test_a_hero_with_one_look_says_so_and_has_no_chips() -> void:
	var game := _arena(Registry.character("astro"))
	var panel := _panel(game)
	assert_object(panel._content.find_child("HeroLooks", true, false)).is_null()
	assert_object(panel._content.find_child("KeepLook", true, false)).is_null()
	await get_tree().process_frame


func test_the_chip_words() -> void:
	assert_str(ArenaPanel.look_chip_text("SOL-A", "SOL-A", "SOL-B")).is_equal("SOL-A ●")
	assert_str(ArenaPanel.look_chip_text("SOL-B", "SOL-A", "SOL-B")).is_equal("SOL-B · RUNS")
	assert_str(ArenaPanel.look_chip_text("SOL-C", "SOL-C", "SOL-C")).is_equal("SOL-C ● · RUNS")
	assert_str(ArenaPanel.look_chip_text("SOL-D", "SOL-A", "SOL-B")).is_equal("SOL-D")
