## Pass 52, the live Main Menu (lane M): Settings.menu_style ("live", the default since pass 53, or "painted") is saved like the
## other settings and offered in Settings only under the player's debug mode; the painted title is as it was; the live
## title puts the map itself behind its UI (a SubViewport with its own world, laid out from the title's own roll, the
## run's roll put back) with the hero standing in it as a run draws him and his start weapon's companion circling him; a
## locked hero is a dark figure with no weapon and the padlock; Ironwood's Spear does not float; a companion behind the
## hero is drawn past his sprite on the same line of sight; a swap runs the next hero in and the last one off; the built
## world waits out a menu visit and goes when a run starts.
extends GdUnitTestSuite

const Stage := preload("res://ui/TitleStage.gd")

var _keep_style := ""
var _keep_debug := false
var _keep_preview := false
var _keep_last := ""


func before_test() -> void:
	_keep_style = Settings.menu_style
	_keep_debug = Settings.debug_mode
	_keep_preview = Settings.preview_locked_heroes
	_keep_last = str(Save.data.get("last_character", "astro"))


func after_test() -> void:
	Stage.forget()
	Settings.menu_style = _keep_style
	Settings.debug_mode = _keep_debug
	Settings.preview_locked_heroes = _keep_preview
	Save.data["last_character"] = _keep_last


func _title(style: String) -> Control:
	Settings.menu_style = style
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	return t


# ---------------------------------------------------------------- the setting

func test_the_menu_style_is_live_until_chosen_and_saved_like_the_others() -> void:
	var script: GDScript = load("res://core/autoload/Settings.gd")
	var s: Node = auto_free(script.new())
	# pass 53 (Garry: "By default set the Main Menu to be the new one - the one with the live heroes"): live
	assert_str(s.menu_style).is_equal("live")
	assert_str(script.MENU_STYLE_DEFAULT).is_equal("live")
	assert_array(script.MENU_STYLES).contains_exactly(["painted", "live"])
	# a save from before pass 52 has no key: the default
	s.from_dict({})
	assert_str(s.menu_style).is_equal("live")
	s.menu_style = "painted"
	assert_str(str(s.to_dict()["menu_style"])).is_equal("painted")
	var back: Node = auto_free(script.new())
	back.from_dict(s.to_dict())
	assert_str(back.menu_style).is_equal("painted")
	# anything else reads as the default
	back.from_dict({"menu_style": "fancy"})
	assert_str(back.menu_style).is_equal("live")


func test_the_menu_style_reaches_the_save_file() -> void:
	Settings.set_value("menu_style", "live")
	assert_bool(Save.save_now()).is_true()
	var data = JSON.parse_string(FileAccess.get_file_as_string(Save.path()))
	assert_str(str(data["settings"]["menu_style"])).is_equal("live")
	Settings.set_value("menu_style", "painted")
	assert_bool(Save.save_now()).is_true()
	data = JSON.parse_string(FileAccess.get_file_as_string(Save.path()))
	assert_str(str(data["settings"]["menu_style"])).is_equal("painted")


# ---------------------------------------------------------------- the two looks

func test_the_painted_title_is_as_it_was() -> void:
	var t := await _title("painted")
	assert_object(t._stage).is_null()
	assert_object(t._art).is_not_null()
	assert_bool(t._art is WPlaceholder).is_true()
	assert_array(t.find_children("*", "SubViewportContainer", true, false)).is_empty()
	# the still of the desert behind it, first
	assert_bool(t.get_child(0) is ColorRect).is_true()


func test_the_live_title_puts_the_level_behind_the_ui() -> void:
	var seed_before: int = Run.map_seed
	var t := await _title("live")
	var stage = t._stage
	assert_object(stage).is_not_null()
	assert_bool(stage is Stage).is_true()
	# behind everything, never in the way of a finger
	assert_int(stage.get_index()).is_equal(0)
	assert_int(stage.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(stage.viewport.gui_disable_input).is_true()
	# its own world, the map in it (its sky and sun are the map's own), the run's 3D scale
	assert_bool(stage.viewport.own_world_3d).is_true()
	assert_bool(stage.map is MapBase).is_true()
	assert_int(stage.map.get_parent().get_parent().get_instance_id()).is_equal(stage.viewport.get_instance_id())
	assert_array(stage.map.find_children("*", "WorldEnvironment", true, false)).is_not_empty()
	# as many 3D pixels as a run draws: the root's scale, by the screen's pixels per canvas unit
	var root := get_tree().root
	var want := clampf(root.scaling_3d_scale * float(root.size.y) / stage.get_viewport_rect().size.y, 0.25, 2.0)
	assert_float(stage.viewport.scaling_3d_scale).is_equal_approx(want, 0.0001)
	assert_int(stage.viewport.scaling_3d_mode).is_equal(root.scaling_3d_mode)
	assert_bool(stage.camera.current).is_true()
	assert_float(stage.camera.fov).is_equal_approx(Stage.FOV_DEG, 0.001)
	# laid out from the title's roll; the run's own roll is put back
	assert_int(stage.map.run_seed).is_equal(Stage.SEED)
	assert_int(Run.map_seed).is_equal(seed_before)
	# the cut-out is gone: the hero stands on the sand instead
	assert_object(t._art).is_null()
	assert_object(stage.hero_sprite()).is_not_null()


func test_the_live_hero_is_drawn_as_a_run_draws_him_with_his_weapon_circling() -> void:
	var t := await _title("live")
	var stage = t._stage
	var astro: CharacterDef = Registry.character("astro")
	stage.show_hero(astro, false, 0)
	await get_tree().process_frame
	var sp: BillboardSprite = stage.hero_sprite()
	assert_object(sp).is_not_null()
	var mat := sp.material_override as ShaderMaterial
	assert_object(mat.get_shader_parameter("sprite")).is_same(astro.sprite)
	assert_float(float(mat.get_shader_parameter("height"))).is_equal_approx(Stage.HERO_HEIGHT, 0.001)
	# the pass over his speed trails as Player sets it up, and no outline pass (his own companion passing his legs drew
	# his outline across it)
	assert_object(mat.next_pass).is_not_null()
	assert_str((mat.next_pass as ShaderMaterial).shader.resource_path).ends_with("sprite_billboard_over.gdshader")
	assert_bool(sp.outline_when_hidden).is_false()
	# idling, facing the camera
	assert_str(sp.animation).is_equal("idle_f")
	assert_bool(sp.playing).is_true()
	# the Gravity Gun's companion, the only part of the visual shown
	var fam: Node3D = stage.familiar()
	assert_object(fam).is_not_null()
	assert_str(str(fam.name)).is_equal("Familiar")
	assert_bool(fam.visible).is_true()
	for ch in fam.get_parent().get_children():
		if ch is Node3D and ch != fam:
			assert_bool((ch as Node3D).visible).is_false()
	# it circles him: round his feet at its radius, then somewhere else a moment later
	var feet: Vector3 = stage.hero.position
	var p0: Vector3 = stage.hero.fam_pos
	var flat := Vector2(p0.x - feet.x, p0.z - feet.z).length()
	assert_float(flat).is_between(0.8, 1.8)
	assert_float(p0.y - feet.y).is_between(1.0, 2.0)
	await get_tree().create_timer(0.5).timeout
	assert_float(stage.hero.fam_pos.distance_to(p0)).is_greater(0.2)


func test_every_hero_has_his_own_companion_and_the_spear_does_not_float() -> void:
	var t := await _title("live")
	var stage = t._stage
	var want := {"astro": "GravityGun", "drifter": "ProjectileEmitter", "calavera": "ConeWave"}
	for id in want.keys():
		stage.show_hero(Registry.character(id), false, 0)
		assert_object(stage.familiar()).override_failure_message("%s has no companion" % id).is_not_null()
		assert_str(stage.hero.kind).is_equal(str(want[id]))
		assert_object(stage.hero.weapon).is_same(Registry.start_weapon_for(Registry.character(id)))
	# Ironwood lands with the Pike, a blade shown only when it strikes: nothing floats round him
	stage.show_hero(Registry.character("ironwood"), false, 0)
	assert_object(stage.familiar()).is_null()
	assert_object(stage.hero.visual).is_null()
	assert_object(stage.hero_sprite()).is_not_null()


func test_a_locked_hero_is_a_dark_figure_with_no_weapon_and_the_padlock() -> void:
	Settings.preview_locked_heroes = true
	var t := await _title("live")
	var i := -1
	for k in (t._heroes as Array).size():
		if t._is_locked(t._heroes[k]):
			i = k
			break
	assert_int(i).is_greater_equal(0)
	t._index = i
	t._show_hero(0)
	var stage = t._stage
	var tint: Color = (stage.hero_sprite().material_override as ShaderMaterial).get_shader_parameter("tint")
	assert_float(tint.get_luminance()).is_less(0.15)
	assert_object(stage.familiar()).is_null()
	assert_object(t._lock).is_not_null()
	assert_bool(t._play.locked).is_true()
	# an open hero after it: full colour, his weapon back, no padlock
	t._index = 0
	t._show_hero(0)
	var tint2: Color = (stage.hero_sprite().material_override as ShaderMaterial).get_shader_parameter("tint")
	assert_bool(tint2.is_equal_approx(Color(1, 1, 1, 1))).is_true()
	assert_object(t._lock).is_null()
	# the plaque's quest bar and the padlock, taken out of the tree, go on the next frame
	await get_tree().process_frame


func test_the_hero_stands_in_the_hero_box() -> void:
	var t := await _title("live")
	var stage = t._stage
	var hero_size: Vector2 = load("res://ui/TitleScreen.gd").HERO_SIZE
	var box := Rect2(t._hero_row.position + t._art_host.position, hero_size * t._art_host.scale.y)
	var fig: Rect2 = stage.figure_rect()
	assert_bool(box.encloses(fig)).override_failure_message("figure %s outside the box %s" % [fig, box]).is_true()
	# smaller than the painted cut-out, centred in it
	assert_float(fig.size.y).is_less(box.size.y * 0.75)
	assert_float(fig.get_center().x).is_equal_approx(box.get_center().x, 1.0)
	# the camera sees his feet where the figure's soles are framed (the run's lens and pitch)
	var cam: Camera3D = stage.camera
	var vp := Vector2(stage.viewport.size)
	var at: Vector2 = cam.unproject_position(stage.feet())
	var g: Vector2 = stage.ground_px()
	var sc: float = vp.y / float(stage.size.y)
	assert_float(at.x / sc).is_equal_approx(g.x, 2.0)
	assert_float(at.y / sc).is_equal_approx(g.y, 2.0)
	# looking down at the run's pitch, north up
	var pitch := rad_to_deg(asin(cam.global_transform.basis.z.y))
	assert_float(pitch).is_equal_approx(Stage.PITCH_DEG, 0.01)
	assert_float(cam.global_transform.basis.x.distance_to(Vector3.RIGHT)).is_less(0.0001)


func test_a_companion_behind_him_is_drawn_past_his_sprite_and_looks_the_same() -> void:
	var t := await _title("live")
	var stage = t._stage
	stage.show_hero(Registry.character("drifter"), false, 0)
	var h = stage.hero
	var cam: Camera3D = stage.camera
	var fwd := -cam.global_transform.basis.z
	var feet_d: float = (h.position - cam.global_position).dot(fwd)
	# straight behind him (north), at its height: nearer the camera than his sprite as it stands
	h.fam_pos = h.position + Vector3(0.0, 1.4, -1.2)
	assert_float((h.fam_pos - cam.global_position).dot(fwd)).is_less(feet_d)
	h._draw_familiar()
	var fam: Node3D = h.familiar
	assert_float((fam.global_position - cam.global_position).dot(fwd)).is_greater(feet_d)
	# the same place on the screen, the size scaled with the distance
	var a: Vector2 = cam.unproject_position(h.fam_pos)
	var b: Vector2 = cam.unproject_position(fam.global_position)
	assert_float(a.distance_to(b)).is_less(0.5)
	assert_float(fam.scale.x).is_greater(1.0)
	# in front of him (south) it is drawn where it is
	h.fam_pos = h.position + Vector3(0.0, 1.4, 1.2)
	h._draw_familiar()
	assert_float(fam.global_position.distance_to(h.fam_pos)).is_less(0.0001)
	assert_float(fam.scale.x).is_equal_approx(h._base_scale.x, 0.0001)


func test_a_swap_runs_the_next_hero_in_and_the_last_one_off() -> void:
	var t := await _title("live")
	var stage = t._stage
	if (t._heroes as Array).size() < 2:
		return
	var first = stage.hero
	t._step(1)
	var second = stage.hero
	assert_object(second).is_not_same(first)
	assert_bool(second.running()).is_true()
	assert_int((stage.leaving as Array).size()).is_greater_equal(1)
	# the next comes from the right, the last goes left: never on top of each other
	assert_float(second.position.x).is_greater(first.position.x + 3.0)
	await get_tree().create_timer(Stage.SWAP_TIME + 0.1).timeout
	assert_bool(second.running()).is_false()
	assert_float(second.position.distance_to(stage.feet())).is_less(0.01)
	assert_str(second.sprite.animation).is_equal("idle_f")
	await get_tree().create_timer(Stage.LEAVE_TIME).timeout
	assert_bool(is_instance_valid(first)).is_false()


func test_the_world_waits_for_the_way_back_from_a_menu_and_goes_when_a_run_starts() -> void:
	var t := await _title("live")
	var stage = t._stage
	assert_bool(stage.reused).is_false()
	var map_id: int = stage.map.get_instance_id()
	# left for a menu: the heroes go, the viewport with its map waits out of the tree
	stage.keep_on_exit = true
	remove_child(t)
	assert_bool(Stage.has_kept()).is_true()
	assert_object(stage.viewport).is_null()
	t.free()
	# the next title takes it back as it was: the same map, nobody left over from before, a hero of its own
	var t2 := await _title("live")
	var s2 = t2._stage
	assert_bool(s2.reused).is_true()
	assert_float(s2.build_ms).is_equal(0.0)
	assert_int(s2.map.get_instance_id()).is_equal(map_id)
	assert_bool(Stage.has_kept()).is_false()
	var actors := 0
	for n in s2.world.get_children():
		if n.name.begins_with("Hero"):
			actors += 1
	assert_int(actors).is_equal(1)
	assert_object(s2.hero_sprite()).is_not_null()
	assert_bool(s2.camera.current).is_true()
	# a run starting lets it go, and so does the painted look
	s2.keep_on_exit = true
	t2._leave_for_a_run()
	assert_bool(s2.keep_on_exit).is_false()
	remove_child(t2)
	assert_bool(Stage.has_kept()).is_false()
	t2.free()
	var t3 := await _title("live")
	t3._stage.keep_on_exit = true
	remove_child(t3)
	t3.free()
	assert_bool(Stage.has_kept()).is_true()
	var p := await _title("painted")
	assert_bool(Stage.has_kept()).is_false()
	assert_object(p._stage).is_null()


# ---------------------------------------------------------------- Settings

func test_the_look_is_offered_in_settings_only_under_the_debug_mode() -> void:
	Settings.debug_mode = false
	var s: Control = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	assert_object(s.find_child("MenuStyle", true, false)).is_null()
	s.visible = false
	Settings.debug_mode = true
	Settings.menu_style = "painted"
	var s2: Control = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s2)
	await get_tree().process_frame
	var choice = s2.find_child("MenuStyle", true, false)
	assert_object(choice).is_not_null()
	assert_bool(choice is WChoice).is_true()
	assert_int(choice.index).is_equal(0)
	choice.choose(1, true)
	assert_str(Settings.menu_style).is_equal("live")
	choice.choose(0, true)
	assert_str(Settings.menu_style).is_equal("painted")
	# above the wipe
	var panel: Node = s2.find_child("DebugPanel", true, false)
	var wipe_panel: Node = s2._wipe.get_parent().get_parent()
	assert_int(panel.get_index()).is_less(wipe_panel.get_index())
	# the debug mode switched off on this screen takes the panel away at once, and back on brings it back
	Settings.debug_mode = false
	s2._sync_debug_panel()
	await get_tree().process_frame
	assert_object(s2.find_child("MenuStyle", true, false)).is_null()
	Settings.debug_mode = true
	s2._sync_debug_panel()
	assert_object(s2.find_child("MenuStyle", true, false)).is_not_null()
	s2.visible = false
