## Pass 139, lane POP (tools/dl/p139/POP/brief.md; Garry: "Trials unlocking new items, heroes, etc should be accompanied by
## a quick pop-up that notifies Player of the Unlock and goes away. The whole sequence shouldn't take more than 2
## seconds."): the unlock pop-up (ui/wanted/WUnlockPop.gd) on the Trail screen's fixture (tests/fixtures/trail_screen.json):
## an unlock's buy shows it, an upgrade's does not (its toast stays); it is gone within 2.0 s of its own clock; a tap
## hurries it and taps pass through on its way out; two in a row queue and both play; a level the buy finishes rides in
## the pop-up (no banner); each kind gets its header and its picture.
extends GdUnitTestSuite

const FIX := "res://tests/fixtures/trail_screen.json"
const SCENE := "res://ui/TrailScreen.tscn"
const PopScript := preload("res://ui/wanted/WUnlockPop.gd")


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from(FIX)
	Nav.clear()


func after_test() -> void:
	Nav.clear()
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()


func _have(bought: Array, gold: int) -> void:
	Save.data["trail"] = {"bought": bought.duplicate(), "spent": 0, "had": []}
	Save.data["gold"] = gold
	Trail.refresh()


func _open() -> TrailScreen:
	var s: TrailScreen = auto_free(load(SCENE).instantiate())
	add_child(s)
	for k in 5:
		await get_tree().process_frame
	return s


## Steps the pop-up's clock by hand, `secs` in `dt` steps (the frames between are not awaited: only this clock moves it).
func _run(pop, secs: float, dt: float = 0.05) -> void:
	var n := int(ceil(secs / dt - 0.0001))
	for k in n:
		pop.step(dt)


func _touch(pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.pressed = pressed
	e.position = Vector2(540, 900)
	return e


func test_the_sequence_fits_in_two_seconds() -> void:
	assert_float(PopScript.TOTAL).is_less_equal(2.0)
	assert_float(PopScript.IN + PopScript.HOLD + PopScript.OUT).is_equal_approx(PopScript.TOTAL, 0.0001)
	assert_float(PopScript.OUT_HURRY).is_less(PopScript.OUT)


func test_an_unlock_buy_shows_the_pop_up() -> void:
	_have(["n01", "n02", "n03a", "n04"], 50000)
	var s := await _open()
	s.select("n05")
	assert_bool(s.buy_selected()).is_true()
	var pop = s.unlock_pop()
	assert_bool(pop.is_up()).is_true()
	assert_str(pop.phase()).is_equal("in")
	var e: Dictionary = pop.current()
	assert_str(str(e["kind"])).is_equal("outlaw")
	assert_str(str(e["head"])).is_equal(Loc.t("ui.unlock_pop.head.outlaw"))
	assert_str(str(e["name"])).is_equal("Astro")
	# Astro stands as his full-body cut-out
	assert_str(str(e["frame"])).is_equal("figure")
	assert_object(e["tex"]).is_not_null()
	# on top of the screen, eating taps while it is up
	assert_int(pop.get_index()).is_equal(s.get_child_count() - 1)
	assert_int(pop.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(pop.find_child("Name", true, false)).is_not_null()
	# the pop-up says it: no toast for an unlock
	assert_int(s._toasts._queue.size() + s._toasts._shown.size()).is_equal(0)
	assert_array(Loc.warnings()).is_empty()


func test_an_upgrade_buy_keeps_its_toast_and_shows_no_pop_up() -> void:
	_have([], 50000)
	var s := await _open()
	s.select("n01")
	assert_bool(s.buy_selected()).is_true()
	assert_bool(s.unlock_pop().is_up()).is_false()
	assert_bool(s.unlock_pop().visible).is_false()
	assert_int(s._toasts._queue.size() + s._toasts._shown.size()).is_greater(0)


func test_it_is_gone_within_two_seconds() -> void:
	_have(["n01", "n02", "n03a", "n04"], 50000)
	var s := await _open()
	s.select("n05")
	s.buy_selected()
	var pop = s.unlock_pop()
	pop.frozen = true
	_run(pop, 0.3)
	assert_str(pop.phase()).is_equal("hold")
	_run(pop, 1.4)
	assert_str(pop.phase()).is_equal("out")
	# taps pass through to the screen on its way out
	assert_int(pop.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	_run(pop, 0.3)
	assert_bool(pop.is_up()).is_false()
	assert_bool(pop.visible).is_false()


func test_a_tap_hurries_it_out() -> void:
	var pop = auto_free(PopScript.new())
	add_child(pop)
	pop.frozen = true
	var done := [0]
	pop.done.connect(func() -> void: done[0] += 1)
	pop.play(PopScript.entry_for("weapon", "boomstick", "Boomstick"))
	_run(pop, 0.5)
	assert_str(pop.phase()).is_equal("hold")
	pop._gui_input(_touch(true))
	assert_str(pop.phase()).is_equal("out")
	assert_float(pop.length()).is_less_equal(0.5 + PopScript.OUT_HURRY + 0.0001)
	# a second tap on its way out changes nothing
	pop._gui_input(_touch(true))
	assert_float(pop.length()).is_less_equal(0.5 + PopScript.OUT_HURRY + 0.0001)
	_run(pop, PopScript.OUT_HURRY + 0.01, 0.01)
	assert_bool(pop.is_up()).is_false()
	assert_int(done[0]).is_equal(1)
	# the mouse hurries it too (the PC)
	pop.play(PopScript.entry_for("weapon", "boomstick", "Boomstick"))
	_run(pop, 0.1)
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	pop._gui_input(m)
	assert_str(pop.phase()).is_equal("out")


func test_two_in_a_row_queue_and_both_play() -> void:
	var pop = auto_free(PopScript.new())
	add_child(pop)
	pop.frozen = true
	var done := [0]
	pop.done.connect(func() -> void: done[0] += 1)
	pop.play(PopScript.entry_for("weapon", "boomstick", "Boomstick"))
	pop.play(PopScript.entry_for("structure", "totem_pole", "Totem Pole"))
	assert_int(pop.queued()).is_equal(1)
	assert_str(str(pop.current()["name"])).is_equal("Boomstick")
	_run(pop, PopScript.TOTAL + 0.02, 0.02)
	assert_bool(pop.is_up()).is_true()
	assert_int(pop.started).is_equal(2)
	assert_int(pop.queued()).is_equal(0)
	assert_str(str(pop.current()["name"])).is_equal("Totem Pole")
	assert_int(done[0]).is_equal(0)
	_run(pop, PopScript.TOTAL + 0.02, 0.02)
	assert_bool(pop.is_up()).is_false()
	assert_int(done[0]).is_equal(1)


func test_a_level_it_finishes_rides_in_the_pop_up() -> void:
	# n05 is level 5's only node: buying it finishes the level
	_have(["n01", "n02", "n03a", "n04"], 50000)
	var s := await _open()
	s.select("n05")
	s.buy_selected()
	assert_int(Trail.level()).is_equal(5)
	var e: Dictionary = s.unlock_pop().current()
	assert_str(str(e["foot"])).is_equal(Loc.t("ui.trail.level_banner", {"level": "5"}))
	assert_bool(s._banner.is_up()).is_false()
	assert_object(s.unlock_pop().find_child("Foot", true, false)).is_not_null()


func test_each_kind_has_its_header_and_picture() -> void:
	var w: Dictionary = PopScript.entry_for("weapon", "boomstick", "Boomstick")
	assert_str(str(w["head"])).is_equal(Loc.t("ui.unlock_pop.head.weapon"))
	assert_str(str(w["frame"])).is_equal("plate")
	assert_object(w["def"]).is_not_null()
	var c: Dictionary = PopScript.entry_for("passive", "thirst", "")
	assert_str(str(c["head"])).is_equal(Loc.t("ui.unlock_pop.head.card"))
	assert_str(str(c["name"])).is_not_empty()
	var sk: Dictionary = PopScript.entry_for("skin", "astro:AST-B", "B")
	assert_str(str(sk["head"])).is_equal(Loc.t("ui.unlock_pop.head.skin"))
	assert_str(str(sk["sub"])).is_equal(Loc.t("ui.unlock_pop.skin_for", {"outlaw": Registry.character("astro").display_name}))
	assert_str(str(sk["frame"])).is_equal("figure")
	var st_n := Trail.node("n11")
	var st: Dictionary = TrailScreen.unlock_entry(st_n)
	assert_str(str(st["head"])).is_equal(Loc.t("ui.unlock_pop.head.stage"))
	assert_str(str(st["frame"])).is_equal("picture")
	assert_str(str(st["foot"])).is_equal("")
	var f: Dictionary = TrailScreen.unlock_entry(Trail.node("n16"))
	assert_str(str(f["head"])).is_equal(Loc.t("ui.unlock_pop.head.any"))
	assert_str(str(PopScript.entry_for("powerup", "rage", "Rage")["head"])).is_equal(Loc.t("ui.unlock_pop.head.powerup"))
	assert_str(str(PopScript.entry_for("structure", "totem_pole", "Totem Pole")["head"])).is_equal(Loc.t("ui.unlock_pop.head.structure"))
	assert_array(Loc.warnings()).is_empty()
