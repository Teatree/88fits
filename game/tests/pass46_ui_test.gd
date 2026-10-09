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


## Pass 47: a skip pays nothing any more (two a stage, Garry), so SKIP carries no coin; the Strongbox line still does.
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
	# the results after a death with a Strongbox on the way
	Run.died = true
	(Save.data["hints_seen"] as Array).append("results")
	Run.last_result = {"gold_before": 100, "banked": 0, "lost": 30, "strongbox": 12, "prev_best": {}}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	var line: Node = r.find_child("Strongbox", true, false)
	assert_object(line).is_not_null()
	assert_int(_coins(line).size()).is_equal(1)
	assert_str(_texts(line)).contains("banked by the Strongbox")
	r.visible = false
	Run.end()
	await get_tree().process_frame


# ---------------------------------------------------------------- brass is for buying

func test_the_choice_marks_its_pick_in_ink() -> void:
	var c: WChoice = auto_free(WChoice.make([["Fixed", "north stays up"], ["Follow", "behind the hero"]], 0))
	var on: HardBox = (c._halves[0] as WTap).box
	var off: HardBox = (c._halves[1] as WTap).box
	assert_bool(on.fill == W.INK).is_true()
	assert_bool(off.fill == W.PAPER).is_true()
	for t in c._texts[0]:
		if t:
			assert_bool((t as WText).color == W.PAPER).is_true()
	for t in c._texts[1]:
		if t:
			assert_bool((t as WText).color == W.INK_SOFT).is_true()
	c.choose(1)
	assert_bool(((c._halves[1] as WTap).box as HardBox).fill == W.INK).is_true()
	assert_bool(((c._halves[0] as WTap).box as HardBox).fill == W.PAPER).is_true()
	# never brass, either half
	for h in c._halves:
		assert_bool(((h as WTap).box as HardBox).fill == W.BRASS).is_false()


func test_upgrade_buttons_are_turquoise_and_buy_stays_brass() -> void:
	var b: WButton = auto_free(WButton.make(["Upgrade"], 30, WButton.UPGRADE, 5, 6, 20.0, 0.0))
	assert_bool((b.box as HardBox).fill == W.TURQUOISE).is_true()
	assert_bool((b.box_down as HardBox).fill == WButton.UPGRADE_DOWN).is_true()
	var label: WText = null
	for n in b._row.get_children():
		if n is WText:
			label = n
	assert_object(label).is_not_null()
	assert_bool(label.color == W.PAPER).is_true()
	# it locks like any button: aged, faded, still pressable
	b.locked = true
	assert_bool((b.get_theme_stylebox("panel") as HardBox).fill == b.locked_fill).is_true()
	assert_float(b.modulate.a).is_equal_approx(b.locked_alpha, 0.001)
	var buy: WButton = auto_free(WButton.make(["RANK 1", {"coin": 40, "fill": W.PAPER}, ["140", null, 40]], 48, WButton.PRIMARY))
	assert_bool((buy.box as HardBox).fill == W.BRASS).is_true()
	assert_bool((buy.box_down as HardBox).fill == W.BRASS_DARK).is_true()


func test_the_title_and_the_results_send_to_upgrade_in_turquoise() -> void:
	_fresh_save()
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	assert_str(t._upgrade_btn.variant).is_equal(WButton.UPGRADE)
	assert_bool(load("res://ui/TitleScreen.gd").GLOW == W.TURQUOISE).is_true()
	t.visible = false
	_start()
	Run.died = true
	(Save.data["hints_seen"] as Array).append("results")
	Run.last_result = {"gold_before": 0, "banked": 0, "lost": 5, "strongbox": 0, "prev_best": {}}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	var found := false
	for n in r.find_children("*", "", true, false):
		if n is WButton and (n as WButton).label_text() == "Upgrade":
			found = true
			assert_str((n as WButton).variant).is_equal(WButton.UPGRADE)
		if n is WButton and (n as WButton).label_text() == "PLAY AGAIN":
			assert_str((n as WButton).variant).is_equal(WButton.PRIMARY)
	assert_bool(found).is_true()
	r.visible = false
	Run.end()
	await get_tree().process_frame


func test_the_upgrade_tiles_price_on_paper_and_six_notches_fit() -> void:
	_fresh_save()
	Save.add_gold(100000)
	var h: Control = auto_free(load("res://ui/HomesteadScreen.tscn").instantiate())
	add_child(h)
	await get_tree().process_frame
	await get_tree().process_frame
	var prices: Array = h.find_children("Price", "", true, false)
	assert_int(prices.size()).is_greater(0)
	for p in prices:
		var box: HardBox = (p as PanelContainer).get_theme_stylebox("panel")
		assert_bool(box.fill == W.PAPER).is_true()
		var coins := _coins(p)
		assert_int(coins.size()).is_equal(1)
		assert_bool((coins[0] as WCoin).fill == W.BRASS).is_true()
	# the board fits its column: six notches beside the longest name
	var grid: GridContainer = h._grid
	assert_float(grid.size.x).is_less_equal(h.content.size.x + 0.5)
	for tile in grid.get_children():
		assert_float((tile as Control).size.x).is_less_equal((h.content.size.x - 24.0) * 0.5 + 0.5)
	# the sheet too
	h._open(Registry.talent("fortune"))
	await get_tree().process_frame
	await get_tree().process_frame
	var sheet: Control = h._sheet_root.find_child("Sheet", true, false)
	assert_float(sheet.get_combined_minimum_size().x).is_less_equal(sheet.size.x + 0.5)
	# pass 63: the next rank is a choice, one button a form (its name and price), under "Rank 1: choose one."
	assert_str(_texts(sheet)).contains("Rank 1: choose one")
	h._close(false)
	# short of gold: aged tags, aged coins
	Save.data["gold"] = 0
	h._refresh()
	await get_tree().process_frame
	for p in h.find_children("Price", "", true, false):
		if not (p as Node).is_queued_for_deletion():
			assert_bool(((p as PanelContainer).get_theme_stylebox("panel") as HardBox).fill == W.AGED).is_true()
			assert_bool((_coins(p)[0] as WCoin).fill == W.AGED).is_true()
	h.visible = false


func test_a_full_talent_reads_its_six_ranks() -> void:
	_fresh_save()
	Save.data["talents"] = {"grit": {"form": 0, "rank": 6}}
	var h: Control = auto_free(load("res://ui/HomesteadScreen.tscn").instantiate())
	add_child(h)
	await get_tree().process_frame
	h._open(Registry.talent("grit"))
	await get_tree().process_frame
	var sheet: Control = h._sheet_root.find_child("Sheet", true, false)
	var said := _texts(sheet)
	assert_str(said).contains("Rank 6 of 6 owned")
	assert_str(said).contains("+60% max HP")
	var buy: WButton = sheet.find_child("Buy", true, false)
	assert_str(buy.label_text()).is_equal("FULL")
	assert_bool(buy.locked).is_true()
	h._close(false)
	h.visible = false
	Save.data["talents"] = {}
	await get_tree().process_frame


# ---------------------------------------------------------------- six ranks

func test_every_talent_has_six_ranks_on_the_steepening_curve() -> void:
	var mult := [1.0, 1.8, 3.0, 4.5, 6.5, 9.0]
	assert_int(Registry.talents_list().size()).is_equal(8)
	for td: TalentDef in Registry.talents_list():
		assert_int(td.ranks).override_failure_message(td.id).is_equal(6)
		assert_int(td.max_rank()).is_equal(6)
		assert_int(td.cost.size()).override_failure_message(td.id + " prices").is_equal(6)
		var first := int(td.cost[0])
		for k in range(6):
			# today's first three kept, then x4.5, x6.5 and x9 of the first, to the nearest 5
			if k >= 3:
				assert_int(int(td.cost[k])).override_failure_message("%s rank %d" % [td.id, k + 1]).is_equal(int(5 * round(first * float(mult[k]) / 5.0)))
			if k > 0:
				assert_int(int(td.cost[k])).is_greater(int(td.cost[k - 1]))
		assert_int(td.cost_of_rank(5)).is_equal(int(td.cost[5]))
		assert_int(td.cost_of_rank(6)).is_equal(-1)


func test_second_wind_alternates_a_revive_and_revive_health() -> void:
	var nerve: TalentDef = Registry.talent("nerve")
	var form := -1
	for f in nerve.forms.size():
		if nerve.form_name(f) == "Second Wind":
			form = f
	assert_int(form).is_greater_equal(0)
	assert_int(((nerve.forms[form] as Dictionary).get("rank_effects", []) as Array).size()).is_equal(6)
	for r in range(1, 7):
		var revives := 0.0
		var hp := 0.0
		for e in nerve.effects_for(form, r):
			if e.stat == "revives":
				revives += e.value
			elif e.stat == "revive_hp":
				hp += e.value
		# ranks 1, 3, 5 a revive; 2, 4, 6 +15% health on getting up
		assert_float(revives).override_failure_message("rank %d" % r).is_equal_approx(float(ceili(r / 2.0)), 0.0001)
		assert_float(hp).override_failure_message("rank %d" % r).is_equal_approx(0.15 * float(floori(r / 2.0)), 0.0001)
	assert_str(TextGen.describe_effects(nerve.summed_effects(form, 4))).is_equal("+2 revives, +30% health on revive")
	# and it reaches the hero's sheet
	_fresh_save()
	_start()
	var r0 := Run.player_sheet.get_stat("revives", 0.0)
	var h0 := Run.player_sheet.get_stat("revive_hp", 0.5)
	Save.data["talents"] = {"nerve": {"form": form, "rank": 4}}
	_start()
	assert_float(Run.player_sheet.get_stat("revives", 0.0)).is_equal_approx(r0 + 2.0, 0.0001)
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(h0 + 0.3, 0.0001)
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
	assert_int(dn.count()).is_equal(DamageNumbers.CAP)
	assert_int(DamageNumbers.CAP).is_equal(60)
	assert_int((dn.live()[0] as DamageNumbers.Num).who).is_equal(110)
	assert_int((dn.live()[59] as DamageNumbers.Num).who).is_equal(169)


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

func test_the_plaque_shows_a_favourite_passive_when_there_is_no_favourite_weapon() -> void:
	_fresh_save()
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	var pid: String = ""
	for id in Registry.passives.keys():
		if not Registry.is_hidden(Registry.passives[id]):
			pid = str(id)
			break
	var c := CharacterDef.new()
	c.id = "t46_hero"
	c.display_name = "Tester"
	c.favourite_weapon = ""
	c.favourite_passive = pid
	assert_object(t._favourite_of(c)).is_same(Registry.passive(pid))
	t._heroes = [c]
	t._index = 0
	t._show_hero(0)
	var fav: Node = t._stats.find_child("Favourite", false, false)
	assert_object(fav).is_not_null()
	assert_object(fav.get_meta("def")).is_same(Registry.passive(pid))
	assert_str(_texts(fav)).contains("FAVOURITE")
	# a favourite weapon still comes first
	c.favourite_weapon = "boomstick"
	assert_object(t._favourite_of(c)).is_same(Registry.weapon("boomstick"))
	t.visible = false
	Save.data["last_character"] = "astro"
	await get_tree().process_frame


func test_the_plaque_reads_regen_and_its_delay() -> void:
	var t = load("res://ui/TitleScreen.gd").new()
	var c := CharacterDef.new()
	c.trait_effects = [Effect.make("regen", "add", 1.2, "player"), Effect.make("regen_delay", "add", -1.5, "player")]
	var rows: Array = t._stats_of(c)
	assert_str(str(rows[0][0])).is_equal("+1.2/s")
	assert_str(str(rows[0][1])).is_equal("REGEN")
	assert_bool(bool(rows[0][2])).is_true()
	assert_str(str(rows[1][0])).is_equal("−1.5 s")
	assert_str(str(rows[1][1])).is_equal("REGEN DELAY")
	# a shorter wait is better
	assert_bool(bool(rows[1][2])).is_true()
	# Ironwood, when he is in the content: his Cake on the plaque (once it is a passive)
	var iw: CharacterDef = Registry.character("ironwood")
	if iw and Registry.passive(iw.favourite_passive):
		assert_object(t._favourite_of(iw)).is_same(Registry.passive(iw.favourite_passive))
	t.free()


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
