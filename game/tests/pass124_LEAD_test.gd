extends GdUnitTestSuite

## Pass 124, Garry's adjustments: the Results' damage panel waits for its turn; the Upgrade board keeps no room for chips nobody holds,
## its short price is grey with the amount in red, its pop-up's pips are bigger; the title's hero runs in and out on a diagonal with his
## own shadow, DETAILS stands in one place; the backdrop's props stand on their shadows; the revive button shows in debug mode; the
## loading screen is dark with the new logo; and the old design is gone: no theme to choose.

var _keep: Dictionary = {}


func before() -> void:
	_keep = Settings.to_dict()


func after() -> void:
	Settings.from_dict(_keep)


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Settings.from_dict(_keep)
	Save.data = Save._default()
	Save._dirty = false


func _title() -> Control:
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	return t


# ---------------------------------------------------------------- the old design is gone

func test_there_is_no_theme_to_choose() -> void:
	assert_bool("ui_theme" in Settings).is_false()
	assert_bool("menu_style" in Settings).is_false()
	assert_bool(Settings.to_dict().has("ui_theme")).is_false()
	# an old save that holds the keys loads without them
	Settings.from_dict({"ui_theme": "wanted", "menu_style": "live"})
	assert_bool(Settings.to_dict().has("ui_theme")).is_false()
	var names: Array = (load("res://ui/wanted/W.gd") as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	assert_bool(names.has("royale")).is_false()
	# the switches are out of the developer menu and the debug panel
	var dm: Control = auto_free(load("res://ui/DevMenu.gd").new())
	add_child(dm)
	await get_tree().process_frame
	assert_object(dm.find_child("UiThemeRow", true, false)).is_null()


func test_prod_shows_the_slot_rarity() -> void:
	var script: GDScript = load("res://core/autoload/Settings.gd")
	assert_bool(bool(script.PROD_LOCKED["hud_slot_rarity"])).is_true()
	assert_bool(script.PROD_LOCKED.has("ui_theme")).is_false()


# ---------------------------------------------------------------- the Results

func test_the_damage_panel_waits_for_its_turn() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.kills = 120
	Run.damage_by_weapon = {"revolver": 900.0}
	Run.last_result = {"gold_before": 100, "banked": 50}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	await get_tree().process_frame
	var panel := r.find_child("DamagePanel", true, false) as Control
	assert_object(panel).is_not_null()
	# not while the count runs, and in with the chart: nothing empty shows first
	assert_float(panel.modulate.a).is_equal(0.0)
	r._part_pop(0.0, false)
	assert_float(panel.modulate.a).is_equal(0.0)
	r._part_pop(1.0, false)
	assert_float(panel.modulate.a).is_equal(1.0)
	r.visible = false
	Run.end()


# ---------------------------------------------------------------- the Upgrade board

func test_the_short_price_is_grey_with_the_amount_in_red() -> void:
	var short: WButton = auto_free(WButton.price(500, "BUY", WButton.GREEN, R.PRICE_PX, 120))
	add_child(short)
	assert_str(short.role).is_equal(WButton.LOCKED)
	assert_bool(short.locked).is_true()
	assert_bool(short.ink_override.is_equal_approx(R.SHORT_INK)).is_true()
	assert_bool(R.SHORT_INK.r > R.SHORT_INK.g * 1.5).is_true()
	var enough: WButton = auto_free(WButton.price(500, "BUY", WButton.GREEN, R.PRICE_PX, 0))
	assert_float(enough.ink_override.a).is_equal(0.0)


func test_the_board_keeps_no_empty_room_and_says_no_shortfall() -> void:
	Save.data["gold"] = 1
	var h: Control = auto_free(load("res://ui/HomesteadScreen.tscn").instantiate())
	add_child(h)
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Control = h.find_child("HoldRow", true, false)
	var board: Control = h.find_child("Board", true, false)
	# the board starts right under the row: no room kept for chips nobody has
	assert_float(row.get_combined_minimum_size().y).is_less(140.0)
	assert_float(board.global_position.y - (row.global_position.y + row.size.y)).is_less_equal(20.0)
	assert_object(h.find_child("Short", true, false)).is_null()
	h._open(Registry.talent("grit"))
	await get_tree().process_frame
	assert_object(h._choice.find_child("Short", true, false)).is_null()
	var track: Control = h._choice.find_child("RankBar", true, false)
	assert_float(track.pip.x).is_greater(R_POP_MIN)
	h._close_choice()


const R_POP_MIN := 80.0


# ---------------------------------------------------------------- the title's hero

func test_details_stays_in_one_place_for_every_hero() -> void:
	Save.data["heroes_owned"] = ["drifter", "astro", "ironwood"]
	var t := await _title()
	# the lower block's entrance is over
	await get_tree().create_timer(0.35).timeout
	var at: Vector2 = t._details_btn.global_position
	# under the trait, not beside it
	assert_float(at.y).is_greater(t._trait_row.global_position.y + t._trait_row.size.y - 1.0)
	assert_float(at.x + t._details_btn.size.x * 0.5).is_equal_approx(t.size.x * 0.5, 1.0)
	for k in (t._heroes as Array).size():
		t._step(1)
		await get_tree().process_frame
		t._place()
		await get_tree().process_frame
		assert_vector(t._details_btn.global_position).is_equal_approx(at, Vector2(0.5, 0.5))


func test_a_swap_runs_one_in_and_one_out_on_a_diagonal() -> void:
	Save.data["heroes_owned"] = ["drifter", "astro"]
	var t := await _title()
	var old = t._figure
	t._step(1)
	await get_tree().process_frame
	var fresh = t._figure
	assert_object(fresh).is_not_same(old)
	assert_bool(fresh.flip).is_true()
	# he starts up the sand on the right, smaller, in his three-quarter run
	assert_float(fresh.position.x).is_greater(100.0)
	assert_float(fresh.position.y).is_less(0.0)
	assert_float(fresh.scale.x).is_less(1.0)
	var run: Array = fresh.offsets.get("run_fd", fresh.offsets.get("run_s", fresh.offsets.get("run", [0, 1])))
	assert_int(fresh.first).is_equal(int(run[0]))
	# the one standing is on his way out, and goes
	assert_bool(is_instance_valid(old)).is_true()
	await get_tree().create_timer(float(t.RY_RUN_IN) + float(t.RY_TURN_BEAT) + 0.25).timeout
	assert_bool(is_instance_valid(old)).is_false()
	# the new one stands on the spot facing us
	assert_vector(fresh.position).is_equal_approx(Vector2.ZERO, Vector2(0.5, 0.5))
	assert_bool(fresh.flip).is_false()
	var idle: Array = fresh.offsets.get("idle_f", fresh.offsets.get("idle_fd", fresh.offsets.get("idle", [0, 1])))
	assert_int(fresh.first).is_equal(int(idle[0]))


func test_the_hero_casts_his_own_shadow() -> void:
	var t := await _title()
	t._figure.refresh_shadow()
	var s: Control = t._figure.find_child("FigureShadow", true, false)
	assert_object(s).is_not_null()
	assert_bool(s.material is ShaderMaterial).is_true()
	assert_float(s.axis.y).is_greater(0.0)


# ---------------------------------------------------------------- the backdrop

func test_a_prop_stands_on_its_shadow() -> void:
	var t := await _title()
	var bd: Control = t.find_child("RoyaleBackdrop", true, false)
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://art/ui/royale/backdrop.json"))
	var props: Array = bd.get("props")
	var shadows: Array = bd.get("shadows")
	assert_int(props.size()).is_equal((m["props"] as Array).size())
	assert_int(shadows.size()).is_equal(props.size())
	for d in m["props"]:
		var p: Sprite2D = bd.find_child("Prop_" + str(d["look"]), true, false)
		var s: Sprite2D = bd.find_child("Shadow_" + str(d["look"]), true, false)
		assert_object(p).is_not_null()
		assert_object(s).is_not_null()
		assert_object(s.texture).is_same(p.texture)
		assert_bool((s.material as ShaderMaterial).shader.resource_path.ends_with("ui_backdrop_shadow.gdshader")).is_true()
		# the painted foot lands on `base`, and the shadow's picture starts from there
		var base := Vector2(float(d["base"][0]), float(d["base"][1]))
		var h := float(p.texture.get_height())
		var foot_in_picture := Vector2(0.0, -h * float(d["foot_up"]))
		assert_vector(p.transform * foot_in_picture).is_equal_approx(base, Vector2(0.5, 0.5))
		assert_vector(s.transform * foot_in_picture).is_equal_approx(base, Vector2(0.5, 0.5))
		# and runs away from the sun, towards the viewer
		assert_float(s.transform.y.y).is_less(0.0)


func test_the_composition_has_depth() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://art/ui/royale/backdrop.json"))
	var hs: Array = []
	for d in m["props"]:
		hs.append(float(d["height_px"]))
		# the hero's lane stays clear
		var x := float(d["base"][0])
		assert_bool(x < 330.0 or x > 900.0).override_failure_message(str(d["look"])).is_true()
	hs.sort()
	assert_float(float(hs[-1]) / float(hs[0])).is_greater(4.0)


# ---------------------------------------------------------------- the Down screen

func test_the_revive_shows_in_debug_mode_under_the_cutout() -> void:
	Settings.debug_mode = true
	var r: ReviveScreen = auto_free(ReviveScreen.new())
	add_child(r)
	await get_tree().process_frame
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	r.open(10, 0)
	await get_tree().process_frame
	var b: WButton = r.find_child("DebugRevive", true, false)
	assert_object(b).is_not_null()
	assert_bool(b.is_visible_in_tree()).is_true()
	assert_str(b.label_text()).is_equal("REVIVE")
	assert_str(b.role).is_equal(WButton.GREEN)
	assert_float(b.modulate.a).is_equal(1.0)
	assert_float(b.offset_top).is_greater_equal(W.safe_top())
	r.visible = false
	Run.end()


# ---------------------------------------------------------------- the loading screen

func test_the_loading_screen_is_dark_everywhere_it_shows() -> void:
	var boot: GDScript = load("res://ui/Boot.gd")
	assert_float(boot.palette("paper").v).is_less(0.2)
	assert_float(boot.palette("ground_a").v).is_less(0.3)
	# the print stands a little lighter than its ground
	assert_float(boot.palette("motif_color").v).is_greater(boot.palette("ground_b").v)
	var dark: Color = boot.DARK
	assert_bool(boot.palette("paper").is_equal_approx(dark)).is_true()
	var splash: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	assert_bool(splash.is_equal_approx(dark)).override_failure_message("the engine's splash").is_true()
	# the plate is the wordmark on nothing: its corners are clear
	var im: Image = (load("res://art/ui/loading/title_plate.png") as Texture2D).get_image()
	assert_float(im.get_pixel(1, 1).a).is_equal(0.0)
