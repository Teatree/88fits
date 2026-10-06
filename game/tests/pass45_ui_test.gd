## Pass 45, the UI lane: every deed that cannot be undone asks in a pop-up (WConfirm), never by a button changing its
## words; the Upgrade sheet's status line sums the ranks; the title plaque paints a debuff dark red; the Results screen
## showed the hero's last hits under the player's debug mode (pass 46 moved them to Down!, so now it shows none); might,
## area and greed read as attack damage, area of effect and coin gain.
extends GdUnitTestSuite


func _touch(at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	get_tree().root.push_input(e, true)


func _host() -> Control:
	var h: Control = auto_free(Control.new())
	h.size = Vector2(1080, 1920)
	add_child(h)
	return h


# ---------------------------------------------------------------- the pop-up

func test_confirm_runs_the_deed_once_and_closes() -> void:
	var h := _host()
	var n := [0]
	var c := WConfirm.open(h, "Wipe?", "body", "Wipe", "Keep", func(): n[0] += 1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(WConfirm.is_open(h)).is_true()
	assert_bool(c.is_in_group("wanted_modal")).is_true()
	assert_str(c.confirm_btn.label_text()).is_equal("WIPE")
	assert_str(c.cancel_btn.label_text()).is_equal("KEEP")
	c.confirm()
	c.confirm()
	assert_int(n[0]).is_equal(1)
	assert_bool(WConfirm.is_open(h)).is_false()
	assert_bool(c.is_in_group("wanted_modal")).is_false()


func test_cancel_leaves_the_deed_undone() -> void:
	var h := _host()
	var n := [0]
	var k := [0]
	var c := WConfirm.open(h, "Wipe?", "body", "Wipe", "Keep", func(): n[0] += 1, func(): k[0] += 1)
	await get_tree().process_frame
	c.cancel()
	assert_int(n[0]).is_equal(0)
	assert_int(k[0]).is_equal(1)
	assert_bool(WConfirm.dismiss(h)).is_false()


func test_a_finger_on_the_rock_button_confirms_and_on_the_dim_cancels() -> void:
	var h := _host()
	var n := [0]
	var c := WConfirm.open(h, "Stay down?", "body", "Stay down", "Not yet", func(): n[0] += 1)
	await get_tree().create_timer(0.4).timeout
	var at := c.confirm_btn.get_global_rect().get_center()
	_touch(at, true)
	_touch(at, false)
	assert_int(n[0]).is_equal(1)
	await get_tree().create_timer(0.3).timeout
	WConfirm.open(h, "Stay down?", "body", "Stay down", "Not yet", func(): n[0] += 1)
	await get_tree().create_timer(0.4).timeout
	_touch(WConfirm.DIM_TAP, true)
	_touch(WConfirm.DIM_TAP, false)
	assert_int(n[0]).is_equal(1)
	assert_bool(WConfirm.is_open(h)).is_false()


func test_a_new_question_replaces_the_old_and_a_hidden_host_takes_it_with_it() -> void:
	var h := _host()
	var first := WConfirm.open(h, "Abandon?", "body", "Abandon", "Keep", Callable())
	await get_tree().process_frame
	var second := WConfirm.open(h, "Abandon?", "body", "Abandon", "Keep", Callable())
	assert_bool(first._done).is_true()
	assert_object(WConfirm.current(h)).is_same(second)
	h.visible = false
	assert_bool(WConfirm.is_open(h)).is_false()


func test_the_settings_wipe_asks_first() -> void:
	var s: Control = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	var gold := Save.gold()
	s._ask_wipe()
	assert_bool(WConfirm.is_open(s)).is_true()
	assert_int(Save.gold()).is_equal(gold)
	assert_bool(WConfirm.dismiss(s)).is_true()
	assert_bool(WConfirm.is_open(s)).is_false()


# ---------------------------------------------------------------- the Upgrade sheet

func test_the_sheet_sums_the_ranks_for_reading() -> void:
	var def: TalentDef = Registry.talents_list()[0]
	# all the ranks (six since pass 46), each the same step
	var full := def.max_rank()
	assert_int(full).is_equal(6)
	var base: Array = def.effects_for(0, 1)
	assert_int(def.effects_for(0, full).size()).is_equal(base.size() * full)
	var summed: Array = def.summed_effects(0, full)
	assert_int(summed.size()).is_equal(base.size())
	for i in base.size():
		var e: Effect = base[i]
		var s: Effect = summed[i]
		assert_str(s.stat).is_equal(e.stat)
		assert_str(s.op).is_equal(e.op)
		assert_float(s.value).is_equal_approx(e.value * full, 0.0001)
	# one effect reads once: no ", +" between three copies
	var text := TextGen.describe_effects(summed)
	assert_str(text).not_contains(", +")
	assert_int(def.summed_effects(0, 0).size()).is_equal(0)
	assert_int(def.summed_effects(5, 1).size()).is_equal(0)


func test_grit_at_full_reads_as_one_line() -> void:
	var grit := Registry.talent("grit")
	if grit == null:
		return
	assert_str(TextGen.describe_effects(grit.summed_effects(0, 3))).is_equal("+30% max HP")
	assert_str(TextGen.describe_effects(grit.summed_effects(1, 3))).is_equal("+18% damage reduction")
	# and at all six (pass 46)
	assert_str(TextGen.describe_effects(grit.summed_effects(0, 6))).is_equal("+60% max HP")
	assert_str(TextGen.describe_effects(grit.summed_effects(1, 6))).is_equal("+36% damage reduction")


# ---------------------------------------------------------------- the title plaque

func test_a_debuff_on_the_plaque_is_not_good() -> void:
	assert_bool(W.BAD_DARK != W.SAGE).is_true()
	var t = load("res://ui/TitleScreen.gd").new()
	var rows: Array = t._stats_of(Registry.character("calavera"))
	assert_int(rows.size()).is_equal(3)
	assert_bool(bool(rows[0][2])).override_failure_message("+25% might is good").is_true()
	assert_bool(bool(rows[1][2])).override_failure_message("+5% crit is good").is_true()
	assert_bool(bool(rows[2][2])).override_failure_message("−15% max HP is not good").is_false()
	assert_str(str(rows[0][1])).is_equal("ATTACK DAMAGE")
	assert_str(str(rows[2][1])).is_equal("HP")
	# less of a lower-is-better stat is a buff
	var c := CharacterDef.new()
	c.trait_effects = [Effect.make("cooldown", "mul", -0.1, "player"), Effect.make("cooldown", "mul", 0.1, "player")]
	var rows2: Array = t._stats_of(c)
	assert_bool(bool(rows2[0][2])).is_true()
	assert_bool(bool(rows2[1][2])).is_false()
	t.free()


func test_the_short_names_fall_through_to_text_gen() -> void:
	var t = load("res://ui/TitleScreen.gd")
	assert_bool((t.SHORT as Dictionary).has("might")).is_false()
	assert_bool((t.SHORT as Dictionary).has("area")).is_false()
	assert_bool((t.SHORT as Dictionary).has("greed")).is_false()
	assert_str(TextGen.stat_name("might")).is_equal("attack damage")
	assert_str(TextGen.stat_name("area")).is_equal("area of effect")
	assert_str(TextGen.stat_name("greed")).is_equal("coin gain")
	assert_str(TextGen.stat_name("adrenaline_might")).is_equal("attack damage per kill stack")
	# the hand-written content sentences followed
	assert_str(Registry.character("calavera").trait_text).contains("attack damage")
	assert_str(Registry.perk("tough_love").text).contains("area of effect")
	assert_str(Registry.perk("crescendo").text).not_contains("might")


# ---------------------------------------------------------------- the banner

func test_the_banner_sits_in_the_upper_middle() -> void:
	assert_float(HUD.BANNER_FRAC).is_equal_approx(0.38, 0.001)
	var host := _host()
	var b := WBanner.new()
	host.add_child(b)
	b.play("BOSS DOWN", false, null, 730.0)
	assert_bool(b.visible).is_true()
	assert_float(b.position.y).is_equal_approx(670.0, 0.5)
	await get_tree().create_timer(0.45).timeout
	assert_float(b.position.y).is_equal_approx(730.0, 1.0)
	assert_float(b.modulate.a).is_equal_approx(1.0, 0.01)


# ---------------------------------------------------------------- the results screen

func _results_with(debug: bool, log: bool) -> Control:
	Settings.debug_mode = debug
	Settings.hit_log = log
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	return r


## Pass 46: the last hits moved to the Down! screen; the Results screen shows none, whatever the switches say.
func test_the_results_show_no_last_hits_any_more() -> void:
	var was_debug := Settings.debug_mode
	var was_log := Settings.hit_log
	Save.data = Save._default()
	Save._migrate_seen()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.died = true
	# so the screen asks for no save (it marks the "results" hint once)
	(Save.data["hints_seen"] as Array).append("results")
	Run.last_result = {"gold_before": 0, "banked": 0, "lost": 5, "strongbox": 0, "prev_best": {},
		"hit_log": "0:12.0  Goblin  −8 HP, 0 left", "last_hit": {"by": "Goblin", "kind": "melee"}}
	var names: Array = []
	for m in (load("res://ui/ResultsScreen.gd") as Script).get_script_method_list():
		names.append(str(m["name"]))
	assert_bool(names.has("hits_visible") or names.has("_add_hits")).is_false()
	for both in [[true, false], [false, true], [true, true]]:
		var r := _results_with(bool(both[0]), bool(both[1]))
		assert_object(r.find_child("HitLog", true, false)).is_null()
		assert_object(r.find_child("HitLogCopy", true, false)).is_null()
		r.visible = false
	Settings.debug_mode = was_debug
	Settings.hit_log = was_log
	Run.end()
