## Pass 46, the UI lane: the painted coin everywhere (the drawn disc until it is painted), brass kept for buying (the
## choice's pick in ink, the Upgrade buttons turquoise, the Upgrade tiles' prices on paper), six ranks a talent with
## Second Wind's ranks alternating, the floating damage numbers, the chest that opens before its reel, the hero's
## favourite passive on the title plaque, and the mutation offer's words.
extends GdUnitTestSuite

const WChestScript := preload("res://ui/wanted/WChest.gd")


## A stand-in for the game the damage numbers read: its pause and (no) camera rig.
class FakeGame extends Node:
	var paused := false
	var camera = null


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _fresh_save() -> void:
	Save.data = Save._default()
	Save._migrate_seen()


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			var t := n as WText
			s += t.text + " "
			for r in t.runs:
				s += str(r[0]) + " "
	return s


func _coins(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "", true, false):
		if n is WCoin:
			out.append(n)
	return out


# ---------------------------------------------------------------- the coin

func test_the_coin_is_the_painting_when_there_is_one_and_the_disc_until_then() -> void:
	# no painting: the drawn disc
	WCoin.set_art(null)
	assert_object(WCoin.art()).is_null()
	var c: WCoin = auto_free(WCoin.make(40.0))
	add_child(c)
	await get_tree().process_frame
	# a painting handed in: every coin draws it
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.6, 0.2))
	var tex := ImageTexture.create_from_image(img)
	WCoin.set_art(tex)
	assert_object(WCoin.art()).is_same(tex)
	c.queue_redraw()
	var aged: WCoin = auto_free(WCoin.make(40.0, W.AGED))
	add_child(aged)
	await get_tree().process_frame
	# and back to whatever the disk holds
	WCoin.set_art(null, true)
	assert_bool(WCoin.art() != null).is_equal(ResourceLoader.exists(WCoin.ART))


## Pass 47: a skip pays nothing any more (two a stage, Garry), so SKIP carries no coin. Re-pinned in pass 70: the
## Strongbox is retired and a death banks the purse, so the results show no Strongbox line, only the banked gold.
func test_a_skip_carries_no_coin_and_the_strongbox_line_does() -> void:
	_fresh_save()
	_start()
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs._refresh_buttons()
	await get_tree().process_frame
	assert_int(_coins(cs._skip_btn).size()).is_equal(0)
	cs.show_offer([], "LEVEL 2", false, true)
	await get_tree().process_frame
	assert_int(_coins(cs._path_skip).size()).is_equal(0)
	cs.visible = false
	# the results after a death (an old record's Strongbox is not mentioned any more): the purse banked, by its coin
	Run.died = true
	(Save.data["hints_seen"] as Array).append("results")
	Run.last_result = {"gold_before": 100, "banked": 30, "lost": 0, "strongbox": 12, "prev_best": {}}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	assert_object(r.find_child("Strongbox", true, false)).is_null()
	assert_str(_texts(r)).contains("BANKED")
	assert_str(_texts(r)).contains("100 → 130")
	r.visible = false
	Run.end()
	await get_tree().process_frame


# ---------------------------------------------------------------- brass is for buying

func test_the_choice_marks_its_pick() -> void:
	var c: WChoice = auto_free(WChoice.make([["Fixed", "north stays up"], ["Follow", "behind the hero"]], 0))
	assert_str(((c._halves[0] as WTap).box as HardBox).role).is_equal("gold")
	assert_str(((c._halves[1] as WTap).box as HardBox).role).is_equal("slate")
	c.choose(1)
	assert_str(((c._halves[1] as WTap).box as HardBox).role).is_equal("gold")
	assert_str(((c._halves[0] as WTap).box as HardBox).role).is_equal("slate")








func test_a_full_talent_reads_its_seven_ranks() -> void:
	_fresh_save()
	Save.data["talents"] = {"grit": {"form": 0, "rank": 7}}
	var h: Control = auto_free(load("res://ui/HomesteadScreen.tscn").instantiate())
	add_child(h)
	await get_tree().process_frame
	h._open(Registry.talent("grit"))
	await get_tree().process_frame
	var sheet: Control = h._sheet_root.find_child("Sheet", true, false)
	var said := _texts(sheet)
	assert_str(said).contains("Rank 7 of 7 owned")
	# six ranks of +10% and the seventh's +15% (pass 123)
	assert_str(said).contains("+75% max HP")
	assert_object(sheet.find_child("Buy0", true, false)).is_null()
	h._close(false)
	h.visible = false
	Save.data["talents"] = {}
	await get_tree().process_frame


# ---------------------------------------------------------------- six ranks

func test_every_talent_has_seven_ranks_on_the_steepening_curve() -> void:
	# (pass 110, lane ECON, re-pinned: Garry's "Mirror costs should be more exponential (Polynomial) ... Starting point
	# prices should stay the same": rank k costs k x k times the first, was x1.8, x3, x4.5, x6.5, x9)
	# (pass 123: "Add 1 more upgrade slot to all ... the extra slot, higher cost and higher increase": 49 x the first)
	var mult := [1.0, 4.0, 9.0, 16.0, 25.0, 36.0, 49.0]
	assert_int(Registry.talents_list().size()).is_equal(8)
	for td: TalentDef in Registry.talents_list():
		assert_int(td.ranks).override_failure_message(td.id).is_equal(7)
		assert_int(td.max_rank()).is_equal(7)
		assert_int(td.cost.size()).override_failure_message(td.id + " prices").is_equal(7)
		var first := int(td.cost[0])
		for k in range(7):
			# every rank k x k times the first (pass 110; the first rank's price is pass 88's)
			assert_int(int(td.cost[k])).override_failure_message("%s rank %d" % [td.id, k + 1]).is_equal(int(round(first * float(mult[k]))))
			if k > 0:
				assert_int(int(td.cost[k])).is_greater(int(td.cost[k - 1]))
		assert_int(td.cost_of_rank(6)).is_equal(int(td.cost[6]))
		assert_int(td.cost_of_rank(7)).is_equal(-1)


func test_second_wind_is_revive_health_a_rank() -> void:
	# pass 115 (lane META, re-pinned): Second Wind alternated a revive and +15% revive health until pass 115; Garry: "Change
	# the Revive to only affect the amount of HP Player gets when they revive": +10% revive health every rank, no revives
	var nerve: TalentDef = Registry.talent("nerve")
	var form := -1
	for f in nerve.forms.size():
		if nerve.form_name(f) == "Second Wind":
			form = f
	assert_int(form).is_greater_equal(0)
	for r in range(1, 7):
		var revives := 0.0
		var hp := 0.0
		for e in nerve.effects_for(form, r):
			if e.stat == "revives":
				revives += e.value
			elif e.stat == "revive_hp":
				hp += e.value
		assert_float(revives).override_failure_message("rank %d" % r).is_equal(0.0)
		assert_float(hp).override_failure_message("rank %d" % r).is_equal_approx(0.1 * float(r), 0.0001)
	assert_str(TextGen.describe_effects(nerve.summed_effects(form, 4))).is_equal("+40% health on revive")
	# and it reaches the hero's sheet
	_fresh_save()
	_start()
	var r0 := Run.player_sheet.get_stat("revives", 0.0)
	var h0 := Run.player_sheet.get_stat("revive_hp", 0.5)
	Save.data["talents"] = {"nerve": {"form": form, "rank": 4}}
	_start()
	assert_float(Run.player_sheet.get_stat("revives", 0.0)).is_equal_approx(r0, 0.0001)
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(h0 + 0.4, 0.0001)
	Save.data["talents"] = {}
	Run.end()


# ---------------------------------------------------------------- the damage numbers

## The numbers on the tree, with a camera over the origin so the hits there are on the screen.
func _numbers() -> DamageNumbers:
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.position = Vector3(0, 12, 12)
	cam.look_at(Vector3.ZERO)
	cam.make_current()
	var dn: DamageNumbers = auto_free(DamageNumbers.new())
	add_child(dn)
	return dn


func test_damage_numbers_merge_a_creature_s_hits_within_the_window() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	assert_object(DamageNumbers.I).is_same(dn)
	dn.add(3, Vector3.ZERO, 10.0)
	dn.add(3, Vector3.ZERO, 5.0)
	assert_int(dn.count()).is_equal(1)
	assert_float((dn.live()[0] as DamageNumbers.Num).amount).is_equal_approx(15.0, 0.001)
	# another creature, and a fire tick on the same one, are numbers of their own
	dn.add(4, Vector3.ZERO, 2.0)
	dn.add(3, Vector3.ZERO, 1.0, false, false, true)
	assert_int(dn.count()).is_equal(3)
	# past the window a new hit starts a new number
	dn.step(DamageNumbers.MERGE + 0.01)
	dn.add(3, Vector3.ZERO, 4.0)
	assert_int(dn.count()).is_equal(4)
	# a crit joining a plain hit turns it a crit (yellow since pass 48)
	dn.add(3, Vector3.ZERO, 6.0, true)
	var last: DamageNumbers.Num = dn.live()[3]
	assert_float(last.amount).is_equal_approx(10.0, 0.001)
	assert_bool(last.crit).is_true()
	# everything is gone after its life
	dn.step(DamageNumbers.LIFE)
	assert_int(dn.count()).is_equal(0)
	# a hit behind the camera gets none
	dn.add(9, Vector3(0, 30, 40), 5.0)
	assert_int(dn.count()).is_equal(0)


func test_damage_numbers_keep_the_newest_sixty() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	for k in range(70):
		dn.add(100 + k, Vector3.ZERO, 3.0)
	# pass 102 (lane HITS, re-pinned on purpose): a full screen (DamageNumbers.CROWD, 40) holds that many creature
	# numbers, the newest pushing the oldest out; CAP (60) is still the most there can be
	assert_int(dn.count()).is_equal(DamageNumbers.CROWD)
	assert_int(DamageNumbers.CAP).is_equal(60)
	assert_int((dn.live()[0] as DamageNumbers.Num).who).is_equal(130)
	assert_int((dn.live()[DamageNumbers.CROWD - 1] as DamageNumbers.Num).who).is_equal(169)


func test_damage_numbers_colour_and_size_by_kind() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	dn.add(1, Vector3.ZERO, 5.0)
	dn.add(2, Vector3.ZERO, 5.0, true)
	dn.add(3, Vector3.ZERO, 5.0, false, false, true)
	dn.add(4, Vector3.ZERO, 5.0, false, true, false)
	var n: Array = dn.live()
	assert_bool(DamageNumbers.colour_of(n[0]) == DamageNumbers.WHITE).is_true()
	assert_bool(DamageNumbers.colour_of(n[1]) == DamageNumbers.CRIT).is_true()
	assert_bool(DamageNumbers.colour_of(n[2]) == DamageNumbers.HOT).is_true()
	assert_bool(DamageNumbers.colour_of(n[3]) == DamageNumbers.POISON).is_true()
	assert_int(DamageNumbers.size_of(n[1])).is_greater(DamageNumbers.size_of(n[0]))
	assert_int(DamageNumbers.size_of(n[2])).is_less(DamageNumbers.size_of(n[0]))
	# whole numbers, never under one
	assert_str(DamageNumbers.text_of(0.3)).is_equal("1")
	assert_str(DamageNumbers.text_of(12.6)).is_equal("13")
	assert_str(DamageNumbers.text_of(1234.0)).is_equal("1,234")
	await get_tree().process_frame


func test_damage_numbers_are_off_with_the_setting_and_frozen_in_a_pause() -> void:
	var was := Settings.damage_numbers
	Settings.damage_numbers = true
	var dn := _numbers()
	var g: FakeGame = auto_free(FakeGame.new())
	dn.game = g
	dn.add(1, Vector3.ZERO, 5.0)
	# the run paused: the numbers hold still
	g.paused = true
	dn._process(0.5)
	assert_int(dn.count()).is_equal(1)
	assert_float((dn.live()[0] as DamageNumbers.Num).age).is_equal_approx(0.0, 0.0001)
	g.paused = false
	dn._process(0.2)
	assert_float((dn.live()[0] as DamageNumbers.Num).age).is_equal_approx(0.2, 0.0001)
	# switched off: none added, and those up go
	Settings.damage_numbers = false
	dn.add(2, Vector3.ZERO, 5.0)
	assert_int(dn.count()).is_equal(1)
	dn._process(0.016)
	assert_int(dn.count()).is_equal(0)
	Settings.damage_numbers = true
	dn.add(2, Vector3.ZERO, 5.0)
	assert_int(dn.count()).is_equal(1)
	# the setting is saved like the other switches
	assert_bool(Settings.to_dict().has("damage_numbers")).is_true()
	Settings.from_dict({"damage_numbers": false})
	assert_bool(Settings.damage_numbers).is_false()
	Settings.from_dict({"damage_numbers": true})
	assert_bool(Settings.damage_numbers).is_true()
	Settings.damage_numbers = was


func test_damage_numbers_step_aside_for_a_modal_and_let_go_of_i() -> void:
	Settings.damage_numbers = true
	var dn := _numbers()
	var m: WModal = auto_free(WModal.new())
	add_child(m)
	m.visible = true
	dn._process(0.016)
	assert_bool(dn.visible).is_false()
	m.visible = false
	dn._process(0.016)
	# (unless some other modal is still up on the tree)
	var others: Array = get_tree().get_nodes_in_group("wanted_modal").filter(func(x): return (x as CanvasItem).visible)
	assert_bool(dn.visible).is_equal(others.is_empty())
	remove_child(dn)
	assert_object(DamageNumbers.I).is_null()
	add_child(dn)
	assert_object(DamageNumbers.I).is_same(dn)


func test_the_settings_screen_switches_the_damage_numbers() -> void:
	var was := Settings.damage_numbers
	var s: Control = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	var sw: WSwitch = s.find_child("DamageNumbers", true, false)
	assert_object(sw).is_not_null()
	assert_bool(sw.on).is_equal(Settings.damage_numbers)
	sw.toggled.emit(false)
	assert_bool(Settings.damage_numbers).is_false()
	sw.toggled.emit(true)
	assert_bool(Settings.damage_numbers).is_true()
	Settings.damage_numbers = was
	s.visible = false


# ---------------------------------------------------------------- the chest opening

func test_the_chest_knocks_cracks_opens_and_sinks() -> void:
	var ch = auto_free(WChestScript.new())
	add_child(ch)
	ch.setup(false, Vector2(540, 678), 420.0)
	assert_bool(ch.painted()).is_equal(ResourceLoader.exists("res://art/ui/wanted/chest_closed.png")
		and ResourceLoader.exists("res://art/ui/wanted/chest_cracked.png") and ResourceLoader.exists("res://art/ui/wanted/chest_open.png"))
	# dropping in: above its spot, fading in
	ch.at(0.05)
	assert_float(ch._y).is_less(0.0)
	# the first knock leans it
	ch.at(float(WChestScript.KNOCKS[0]) + WChestScript.KNOCK_LEN * 0.5)
	assert_int(ch.frame).is_equal(WChestScript.CLOSED)
	assert_float(absf(ch._rot)).is_greater(0.01)
	ch.at(WChestScript.CRACK + 0.02)
	assert_int(ch.frame).is_equal(WChestScript.CRACKED)
	assert_float(ch.light).is_equal(0.0)
	ch.at(WChestScript.OPEN + 0.04)
	assert_int(ch.frame).is_equal(WChestScript.OPENED)
	assert_float(ch.light).is_greater(0.0)
	assert_bool(ch.before_spin()).is_true()
	ch.at(WChestScript.SPIN_AT + 0.15)
	assert_float(ch.modulate.a).is_less(1.0)
	assert_float(ch._y).is_greater(0.0)
	ch.at(WChestScript.LIFE)
	assert_bool(ch.visible).is_false()
	# the boss's chest is its own (violet) one
	ch.setup(true, Vector2(540, 678), 420.0)
	assert_bool(ch.boss).is_true()
	assert_bool(ch.visible).is_true()
	ch.queue_redraw()
	await get_tree().process_frame


func test_the_chest_screen_opens_the_chest_before_the_reel_and_a_skip_goes_to_the_spin() -> void:
	_fresh_save()
	_start()
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	cs.open({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
	assert_bool(cs.intro_playing()).is_true()
	assert_bool(cs._chest.visible).is_true()
	assert_float(cs._reel.modulate.a).is_equal(0.0)
	assert_bool(cs._chest.boss).is_false()
	# it plays by itself: half a second in the chest is still closed, knocking
	await get_tree().create_timer(0.45).timeout
	assert_bool(cs.intro_playing()).is_true()
	assert_float(cs._chest.t).is_greater(0.2)
	assert_int(cs._chest.frame).is_equal(WChestScript.CLOSED)
	# a skip: straight to the spin, the lid open, the reel coming in
	cs.skip_intro()
	assert_bool(cs.intro_playing()).is_false()
	assert_bool(cs._spinning).is_true()
	assert_int(cs._chest.frame).is_equal(WChestScript.OPENED)
	assert_float(cs._tw.get_total_elapsed_time()).is_greater_equal(WChestScript.SPIN_AT - 0.001)
	# and the reel still lands, the buttons up
	cs._tw.set_speed_scale(40.0)
	await get_tree().create_timer(0.5).timeout
	assert_bool(cs._spinning).is_false()
	assert_bool(cs.buttons.visible).is_true()
	assert_bool(cs._chest.visible).is_false()
	# the boss's chest: violet
	Run.add_weapon(Registry.weapon("hornet_nest"), 3)
	var r := Run.chest_roll(true)
	if str(r.get("type", "")) == "mutation":
		cs.open(r)
		assert_bool(cs._chest.boss).is_true()
		cs._tw.set_speed_scale(40.0)
		await get_tree().create_timer(0.5).timeout
	cs.visible = false
	Run.end()


func test_a_tap_while_the_chest_opens_skips_to_the_spin() -> void:
	_fresh_save()
	_start()
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	cs.open({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
	await get_tree().process_frame
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = Vector2(540, 960)
	e.pressed = true
	cs._input(e)
	assert_bool(cs.intro_playing()).is_false()
	assert_bool(cs._spinning).is_true()
	# a second tap now hurries the spin
	cs._input(e)
	await get_tree().create_timer(1.2).timeout
	assert_bool(cs._spinning).is_false()
	cs.visible = false
	Run.end()


# ---------------------------------------------------------------- the title plaque





# ---------------------------------------------------------------- the mutation offer

func test_the_mutation_offer_says_mutation_and_the_others_come_back() -> void:
	assert_str(CardScreen.leave_line(3)).is_equal("· the others come back next stage")
	assert_str(CardScreen.leave_line(4)).is_equal("· the others come back next stage")
	assert_str(CardScreen.leave_line(2)).is_equal("· the other comes back next stage")
	assert_str(CardScreen.leave_line(1)).is_equal("")
	_fresh_save()
	_start()
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs._fill_path_head(Registry.weapon("boomstick"), 1, 4)
	var said := _texts(cs._path_head)
	assert_str(said).contains("PICK A MUTATION")
	assert_str(said).contains("Mutation")
	assert_str(said).contains("the others come back")
	assert_str(said.to_lower()).not_contains("path")
	assert_str(said.to_lower()).not_contains("road forks")
	cs.visible = false
	Run.end()
	await get_tree().process_frame
