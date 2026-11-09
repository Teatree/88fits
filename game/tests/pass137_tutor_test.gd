## Pass 137, lane TUTOR (Garry: "Tutorialize the Trail"): the Trail's first steps.
##  - a new save has the Trail closed: its tab locked like STORE (grey, its padlock, refused), Nav.to_trail refused;
##  - the first run counted (Save.record_run) opens it; an old save (a run started or counted, a node bought) skips every
##    step, once (_migrate_tutorial); a save without the block counts every step done;
##  - the Results' Trail button reads UPGRADE, is grey and inert through the show while the step is open, highlighted
##    once the show is over (a skip too), and its first tap ends the highlight for good;
##  - the Trail's BUY highlighted the same way until the first tap the purse can pay (a short tap leaves it on);
##  - the tab's unlock plays once, on the first bar after the Trail opened that is not the Trail's own.
extends GdUnitTestSuite

const FIX := "res://tests/fixtures/trail_screen.json"
const TRAIL_SCENE := "res://ui/TrailScreen.tscn"
const TabBarScript := preload("res://ui/wanted/WTabBar.gd")
const QT := preload("res://core/systems/QuestTracker.gd")

var _keep: Dictionary = {}
var _asked: Array = []


func before_test() -> void:
	_keep = {"save": Save.data.duplicate(true), "inset": Settings.top_inset}
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._migrate_seen()
	Save._dirty = false
	Run.arena = false
	QT.just_completed.clear()
	Nav.clear()
	_asked = []
	Nav.navigate = func(p: String) -> void: _asked.append(p)


func after_test() -> void:
	Nav.navigate = Callable()
	Nav.clear()
	# a Nav.to_trail that went through leaves the Trail's next build on its node: forget it
	TrailScreen.open_on("", "")
	QT.just_completed.clear()
	Settings.top_inset = int(_keep["inset"])
	Save.data = _keep["save"]
	Save._dirty = false
	Trail.load_from()
	Run.end()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _fresh() -> void:
	Save.data["tutorial"] = Save.tutorial_fresh()


func _bar(active: String) -> Control:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var bar: Control = TabBarScript.make(active)
	bar.set("navigate", func(p: String) -> void: _asked.append(p))
	host.add_child(bar)
	return bar


# ---------------------------------------------------------------- the state

func test_a_save_without_the_block_has_every_step_done() -> void:
	assert_bool(Save._default().has("tutorial")).is_false()
	for st: String in Save.TUTORIAL_STEPS:
		assert_bool(Save.tutorial_done(st)).is_true()
	assert_bool(Save.trail_open()).is_true()
	_fresh()
	for st: String in Save.TUTORIAL_STEPS:
		assert_bool(Save.tutorial_done(st)).is_false()
	assert_bool(Save.trail_open()).is_false()
	Save.mark_tutorial("buy_tapped")
	assert_bool(Save.tutorial_done("buy_tapped")).is_true()
	assert_bool(Save.tutorial_done("upgrade_tapped")).is_false()
	Save.skip_trail_tutorial()
	for st: String in Save.TUTORIAL_STEPS:
		assert_bool(Save.tutorial_done(st)).is_true()
	Save.reset_trail_tutorial()
	assert_bool(Save.trail_open()).is_false()


func test_a_new_save_meets_the_steps_and_an_old_one_skips_them_once() -> void:
	# a save that never started a run, bought nothing: every step to come
	Save._migrate_tutorial()
	assert_bool(Save.trail_open()).is_false()
	assert_bool(Save.once(Save.TUTORIAL_ONCE)).is_true()
	# a run started before this build
	Save.data = Save._default()
	Save.data["runs_started"] = 1
	Save._migrate_tutorial()
	for st: String in Save.TUTORIAL_STEPS:
		assert_bool(Save.tutorial_done(st)).is_true()
	# a run counted
	Save.data = Save._default()
	Save.data["totals"]["runs"] = 3
	Save._migrate_tutorial()
	assert_bool(Save.tutorial_done("tab_unlock_shown")).is_true()
	# a node bought
	Save.data = Save._default()
	Save.data["trail"] = {"bought": ["n01"], "spent": 10, "had": []}
	Save._migrate_tutorial()
	assert_bool(Save.tutorial_done("upgrade_tapped")).is_true()
	# once: a new save that has since played keeps its steps to come
	Save.data = Save._default()
	Save._migrate_tutorial()
	Save.data["runs_started"] = 4
	Save._migrate_tutorial()
	assert_bool(Save.trail_open()).is_false()
	# a wipe meets them again
	Save.skip_trail_tutorial()
	var keep_dir := Save.dir
	Save.dir = "user://test_saves/pass137_tutor"
	DirAccess.make_dir_recursive_absolute(Save.dir)
	Save.wipe()
	assert_bool(Save.trail_open()).is_false()
	assert_bool(Save.tutorial_done("buy_tapped")).is_false()
	for f: String in ["save.json", "save.json.bak", "save.json.tmp"]:
		if FileAccess.file_exists(Save.dir.path_join(f)):
			DirAccess.remove_absolute(Save.dir.path_join(f))
	Save.dir = keep_dir


func test_the_first_run_counted_opens_the_trail() -> void:
	_fresh()
	assert_bool(Save.trail_open()).is_false()
	Save.record_run("red_canyon", 30.0, 2, 1, 5)
	assert_bool(Save.trail_open()).is_true()
	assert_bool(Save.tutorial_done("upgrade_tapped")).is_false()
	assert_bool(Save.tutorial_done("tab_unlock_shown")).is_false()


# ---------------------------------------------------------------- the tab and the other ways in

func test_a_new_save_has_the_trail_tab_locked_like_the_store() -> void:
	_fresh()
	var bar := _bar("battle")
	await _frames(2)
	assert_bool(TabBarScript.opens("upgrade")).is_false()
	assert_bool(bar.call("is_locked", "upgrade")).is_true()
	var up: WTap = bar.call("tab", "upgrade")
	assert_bool(up.locked).is_true()
	assert_bool(bool(up.get_meta("locked"))).is_true()
	assert_bool((bar.get_node("UpgradeLock") as Control).visible).is_true()
	assert_bool((bar.get_node("LockBadge") as Control).visible).is_true()
	# a finger on it: refused (no screen asked for), and no unlock to play
	bar.call("press", "upgrade")
	assert_array(_asked).is_empty()
	assert_bool(bar.call("unlock_pending")).is_false()
	# no crumb on a locked tab, whatever the purse
	Save.data["gold"] = 999999
	bar.call("refresh")
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_false()
	# the "Reach Trail Level N" links open nothing
	var from: Control = auto_free(Control.new())
	assert_bool(Nav.to_trail("outlaw", "calavera", from)).is_false()
	assert_int(Nav.depth()).is_equal(0)
	# opened: the same links work
	Save.mark_tutorial("trail_open")
	Save.mark_tutorial("tab_unlock_shown")
	assert_bool(TabBarScript.opens("upgrade")).is_true()
	assert_bool(Nav.to_trail("outlaw", "calavera", from)).is_true()
	assert_array(_asked).contains_exactly([Nav.TRAIL])


func test_the_tab_unlock_plays_once_and_never_on_the_trail_itself() -> void:
	_fresh()
	Save.mark_tutorial("trail_open")
	# the Trail's own bar: its tab is the open one, nothing to play, the step waits
	var own := _bar("upgrade")
	assert_bool(own.call("unlock_pending")).is_false()
	assert_bool(Save.tutorial_done("tab_unlock_shown")).is_false()
	# the title's bar: the tab looks locked (padlock, grey) but is open to a finger
	var bar := _bar("battle")
	await _frames(1)
	assert_bool(bar.call("unlock_pending")).is_true()
	assert_bool(bar.call("is_locked", "upgrade")).is_false()
	assert_bool(bar.call("looks_locked", "upgrade")).is_true()
	assert_bool((bar.call("tab", "upgrade") as WTap).locked).is_true()
	assert_bool((bar.get_node("UpgradeLock") as Control).visible).is_true()
	# it plays by itself after UNLOCK_DELAY
	await get_tree().create_timer(TabBarScript.UNLOCK_DELAY + 0.15).timeout
	assert_bool(bar.call("unlock_pending")).is_false()
	assert_bool(Save.tutorial_done("tab_unlock_shown")).is_true()
	assert_bool((bar.get_node("UpgradeLock") as Control).visible).is_false()
	assert_bool((bar.call("tab", "upgrade") as WTap).locked).is_false()
	assert_object(bar.get_node_or_null("UpgradeLockFall")).is_not_null()
	assert_object(bar.get_node_or_null("UnlockShine")).is_not_null()
	# the padlock falls away and the drain lets go
	await get_tree().create_timer(TabBarScript.BADGE_POP_S + TabBarScript.BADGE_FALL_S + 0.2).timeout
	assert_object(bar.get_node_or_null("UpgradeLockFall")).is_null()
	assert_object((bar.call("tab", "upgrade") as WTap).material).is_null()
	assert_float((bar.call("tab", "upgrade") as WTap).modulate.a).is_equal_approx(1.0, 0.01)
	# a finger on it goes to the Trail
	bar.call("press", "upgrade")
	assert_array(_asked).contains_exactly([TabBarScript.TRAIL_SCENE])
	# the next bar: plain
	var next := _bar("collections")
	assert_bool(next.call("unlock_pending")).is_false()
	assert_bool((next.call("tab", "upgrade") as WTap).locked).is_false()


# ---------------------------------------------------------------- the Results' UPGRADE

func _results() -> Control:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.kills = 40
	Run.damage_by_weapon = {"revolver": 900.0}
	Run.last_result = {"gold_before": 100, "banked": 50}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	return r


## The Results' buttons by their words.
func _words(r: Control) -> Dictionary:
	var out := {}
	for b in r.find_children("*", "WButton", true, false):
		out[(b as WButton).label_text()] = b
	return out


func test_the_results_upgrade_is_grey_through_the_show_then_highlighted_until_its_first_tap() -> void:
	_fresh()
	Save.mark_tutorial("trail_open")
	var r := _results()
	await _frames(2)
	var words := _words(r)
	assert_bool(words.has("UPGRADE")).is_true()
	assert_bool(words.has("TRAIL")).is_false()
	var up: WButton = words["UPGRADE"]
	assert_str(String(up.name)).is_equal("Upgrade")
	# through the show: grey, inert, no highlight
	assert_int(int(r.call("sequence"))).is_equal(1)
	assert_bool(up.locked).is_true()
	r.call("_on_upgrade")
	assert_bool(Save.tutorial_done("upgrade_tapped")).is_false()
	assert_bool(r.call("upgrade_highlighted")).is_false()
	# the show over (a skip ends it too): awake and highlighted
	r.call("skip_all")
	await _frames(3)
	assert_bool(up.locked).is_false()
	assert_bool(r.call("upgrade_highlighted")).is_true()
	var hl: Control = r.find_child("TutorHighlight", false, false)
	assert_object(hl).is_not_null()
	assert_object(r.find_child("TutorGlow", true, false)).is_not_null()
	# past its entrance the button stands bigger, pulsing round BASE
	hl.set("_t", 1.0)
	await _frames(1)
	assert_float(up.scale.x).is_greater(1.04)
	# the first tap: the step done, the highlight gone for good (UiFx.go held by a curtain: the test stays here)
	var curtain: Node = auto_free(Node.new())
	curtain.add_to_group(UiFx.CURTAIN_GROUP)
	add_child(curtain)
	r.call("_on_upgrade")
	assert_bool(Save.tutorial_done("upgrade_tapped")).is_true()
	await _frames(2)
	assert_bool(r.call("upgrade_highlighted")).is_false()
	assert_object(r.find_child("TutorHighlight", false, false)).is_null()
	assert_float(up.scale.x).is_equal(1.0)
	# the next Results: UPGRADE awake from the start, never highlighted
	r.queue_free()
	await _frames(2)
	var r2 := _results()
	await _frames(2)
	var up2: WButton = _words(r2)["UPGRADE"]
	assert_bool(up2.locked).is_false()
	r2.call("skip_all")
	await _frames(3)
	assert_bool(r2.call("upgrade_highlighted")).is_false()


func test_the_highlight_plays_on_every_results_until_the_tap() -> void:
	_fresh()
	Save.mark_tutorial("trail_open")
	for k in 2:
		var r := _results()
		await _frames(2)
		assert_bool((_words(r)["UPGRADE"] as WButton).locked).is_true()
		r.call("skip_all")
		await _frames(3)
		assert_bool(r.call("upgrade_highlighted")).is_true()
		r.queue_free()
		await _frames(2)
	assert_bool(Save.tutorial_done("upgrade_tapped")).is_false()


func test_an_old_save_sees_upgrade_awake_and_plain() -> void:
	var r := _results()
	await _frames(2)
	var up: WButton = _words(r)["UPGRADE"]
	assert_bool(up.locked).is_false()
	r.call("skip_all")
	await _frames(3)
	assert_bool(r.call("upgrade_highlighted")).is_false()


# ---------------------------------------------------------------- the Trail's BUY

func _trail(bought: Array, gold: int) -> TrailScreen:
	Trail.load_from(FIX)
	Save.data["trail"] = {"bought": bought.duplicate(), "spent": 0, "had": []}
	Save.data["gold"] = gold
	Trail.refresh()
	var s: TrailScreen = auto_free(load(TRAIL_SCENE).instantiate())
	add_child(s)
	await _frames(6)
	return s


func test_buy_is_highlighted_until_its_first_paid_tap() -> void:
	_fresh()
	Save.mark_tutorial("trail_open")
	Save.mark_tutorial("upgrade_tapped")
	Save.mark_tutorial("tab_unlock_shown")
	# a short purse: highlighted all the same, and a refused tap leaves it on
	var s := await _trail([], 0)
	assert_bool(s.buy_highlighted()).is_true()
	assert_object(s.find_child("TutorHighlight", false, false)).is_not_null()
	s.press_buy()
	assert_bool(Save.tutorial_done("buy_tapped")).is_false()
	await _frames(2)
	assert_bool(s.buy_highlighted()).is_true()
	s.queue_free()
	await _frames(2)
	# the purse can pay: the first tap buys and ends it for good
	var s2 := await _trail([], 5000)
	assert_bool(s2.buy_highlighted()).is_true()
	var first := s2.selected
	s2.press_buy()
	assert_bool(Save.tutorial_done("buy_tapped")).is_true()
	assert_bool(Trail.state(first) == "bought").is_true()
	await _frames(2)
	assert_bool(s2.buy_highlighted()).is_false()
	assert_object(s2.find_child("TutorHighlight", false, false)).is_null()
	s2.queue_free()
	await _frames(2)
	var s3 := await _trail(Save.trail_bought(), 5000)
	assert_bool(s3.buy_highlighted()).is_false()


func test_the_highlight_follows_buy_as_the_dock_is_rebuilt() -> void:
	_fresh()
	Save.mark_tutorial("trail_open")
	var s := await _trail([], 5000)
	assert_bool(s.buy_highlighted()).is_true()
	var hl: Control = s.buy_highlight
	# a node that is not open: no BUY, the highlight waits hidden
	var locked_id := ""
	for n: Dictionary in Trail.nodes_on(5):
		locked_id = str(n["id"])
		break
	s.select(locked_id)
	await _frames(2)
	assert_object(s._dock.get_node_or_null("Buy")).is_null()
	assert_bool(s.buy_highlighted()).is_false()
	# back to an open one: the same highlight on the new BUY
	s.select(s._next_open())
	await _frames(2)
	assert_bool(s.buy_highlighted()).is_true()
	assert_object(s.buy_highlight).is_same(hl)
	assert_bool((s._dock.get_node("Buy") as Control).has_meta("highlight")).is_true()


func test_an_old_save_has_no_buy_highlight() -> void:
	var s := await _trail([], 5000)
	assert_bool(s.buy_highlighted()).is_false()
	assert_object(s.find_child("TutorHighlight", false, false)).is_null()


# ---------------------------------------------------------------- the developer menu

func test_the_developer_menu_resets_the_tutorial() -> void:
	var src := FileAccess.get_file_as_string("res://ui/DevMenu.gd")
	assert_str(src).contains("The Trail · reset the tutorial")
	assert_str(src).contains("Save.reset_trail_tutorial()")
