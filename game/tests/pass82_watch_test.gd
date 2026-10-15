extends GdUnitTestSuite

## Pass 82, lane WATCH (Garry: "Bot should try to find the Special Enemies when they appear" / "Allow me access to Pause
## button in the game, it also pauses the game, but I can access settings and such" / the Watch "just mark the totals
## somewhere and mark the times that these items were picked up on the chart of Level and XP"): the special goal and its
## option (tools/bot/BotGoals.gd special_candidates, Bot.gd's hunt), the mouse on the phone view turned into the touch the
## phone sends and pushed into a SubViewport onto the game's canvas (Watch.finger_event), the Watch clock's in-game hold,
## and the pickups' totals and marks from the recorder's events (WatchData, WatchPanel.pickup_points; lane STATS' rule).

const BOT := preload("res://tools/bot/Bot.gd")
const GOALS := preload("res://tools/bot/BotGoals.gd")
const SIM := preload("res://tools/sim_run.gd")
const WATCH := preload("res://tools/watch/Watch.gd")
const CLOCK := preload("res://tools/watch/WatchClock.gd")
const DATA := preload("res://tools/watch/WatchData.gd")
const PANEL := preload("res://tools/watch/WatchPanel.gd")
const CHART := preload("res://tools/watch/WatchChart.gd")


func after_test() -> void:
	get_tree().paused = false
	if Save.sandboxed():
		Save.end_sandbox()


# ---------------------------------------------------------------- fakes

class FakeInput:
	extends RefCounted
	var wants_move := false
	var origin := Vector2.ZERO
	var touch_pos := Vector2.ZERO


class FakePlayer:
	extends Node3D
	var input := FakeInput.new()
	var hp := 100.0
	var max_hp := 100.0
	var dead := false


class FakeMap:
	extends RefCounted
	var flats_center := Vector3.ZERO
	var arena_radius := 66.0
	var obstacles: Array = []


class FakeDef:
	extends RefCounted
	var id := "red_goblin"
	var display_name := "Red Goblin"
	var variance := {"special": {}}

	static func special_value(sp: Dictionary, defaults: Dictionary, key: String) -> float:
		if sp.has(key):
			return float(sp[key])
		return float(defaults.get(key, 0.35))


class FakeEnemies:
	extends RefCounted
	const MAX := 8
	const STATE_DYING := 3
	var alive := PackedByteArray()
	var vspecial := PackedByteArray()
	var state := PackedInt32Array()
	var serial := PackedInt32Array()
	var pos := PackedVector3Array()
	var type_idx := PackedInt32Array()
	var onscreen := PackedByteArray()
	var types: Array = []
	var special_defaults := {"chest_chance": 0.35}
	var special_chests := 0
	var boss_index := -1

	func _init() -> void:
		alive.resize(MAX)
		vspecial.resize(MAX)
		state.resize(MAX)
		serial.resize(MAX)
		pos.resize(MAX)
		type_idx.resize(MAX)
		onscreen.resize(MAX)
		onscreen.fill(1)
		types = [{"def": FakeDef.new()}]

	func put(i: int, at: Vector3, special: bool, sr: int = 1) -> void:
		alive[i] = 1
		vspecial[i] = 1 if special else 0
		state[i] = 0
		serial[i] = sr
		pos[i] = at


class FakePickups:
	extends RefCounted
	var specials: Array = []
	var chests: Array = []


class FakeGame:
	extends Node
	var player: FakePlayer
	var map := FakeMap.new()
	var enemies := FakeEnemies.new()
	var pickups := FakePickups.new()
	var paused := false
	var portal = null


func _fake_game() -> FakeGame:
	var g: FakeGame = auto_free(FakeGame.new())
	g.player = FakePlayer.new()
	add_child(g)
	g.add_child(g.player)
	return g


## The planner's view at play second `t` (20 by default: a special first known at 10 has been out of reach 10 s).
func _view(opts: Dictionary, hp: float = 1.0, held: String = "", t: float = 20.0) -> Dictionary:
	return {"me": Vector3.ZERO, "t": t, "hp_frac": hp, "danger": 0.0, "style": "balanced", "opts": BOT.resolve_opts(opts),
		"boss": Vector3.INF, "leash": true, "lure_s": 0.0, "lure_at": Vector3.INF, "held_key": held}


static func _specials(cands: Array) -> Array:
	return cands.filter(func(c: Dictionary) -> bool: return str(c["kind"]) == "special")


# ---------------------------------------------------------------- the specials hunted

func test_the_specials_option_and_the_presets() -> void:
	# every preset names it; pass 77's bot never hunts (it stays pass 77's exactly); the runner's args take it
	for p in BOT.PRESETS:
		assert_bool((BOT.PRESETS[p] as Dictionary).has("specials")).is_true()
	assert_bool(bool(BOT.resolve_opts({"preset": "sim77"})["specials"])).is_false()
	for p in ["explorer", "careless", "expert"]:
		assert_bool(bool(BOT.resolve_opts({"preset": p})["specials"])).override_failure_message(p).is_true()
	assert_bool(bool(BOT.resolve_opts({"preset": "explorer", "specials": "0"})["specials"])).is_false()
	assert_bool(SIM.BOT_ARGS.has("specials")).is_true()
	# the planner runs for the specials alone
	var only := {"preset": "explorer", "explore": 0.0, "totems": false, "barrels": false, "structures": false}
	assert_bool(BOT.planner_on(BOT.resolve_opts(only))).is_true()
	only["specials"] = false
	assert_bool(BOT.planner_on(BOT.resolve_opts(only))).is_false()
	assert_bool(BOT.planner_on(BOT.resolve_opts({"preset": "sim77"}))).is_false()


func test_a_special_is_a_goal_while_he_knows_it() -> void:
	var g := _fake_game()
	var em: FakeEnemies = g.enemies
	em.put(0, Vector3(12, 0, 0), true, 7)
	em.put(1, Vector3(4, 0, 0), false)
	var gl = GOALS.new(3)
	gl.setup_map(g.map)
	# just known: the weapons' for SPECIAL_WAIT s (it may come by itself)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, "", 10.0))).size()).is_equal(0)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, "", 10.0 + GOALS.SPECIAL_WAIT - 0.5))).size()).is_equal(0)
	# known 10 s and still out of reach (12 m): a goal
	var sp := _specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0})))
	assert_int(sp.size()).is_equal(1)
	var c: Dictionary = sp[0]
	assert_str(str(c["key"])).is_equal(GOALS.special_key(0, 7))
	assert_str(str(c["why"])).is_equal("a special: Red Goblin, a 35% chest, out of reach 10 s")
	assert_int(int(c["index"])).is_equal(0)
	assert_float(float(c["fight"])).is_equal(GOALS.SPECIAL_FIGHT_S)
	# no taste or mood: the same value whatever the run's seed, only the jitter and the distance move it
	var gl2 = GOALS.new(99)
	gl2.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, "", 10.0))
	var c2: Dictionary = _specials(gl2.candidates(g, null, _view({"preset": "explorer", "explore": 0.0})))[0]
	assert_float(float(c2["u"]) / gl2.jitter(str(c2["key"]))).is_equal_approx(float(c["u"]) / gl.jitter(str(c["key"])), 0.001)
	assert_float(float(c["u"])).is_equal_approx(GOALS.V_SPECIAL * gl.jitter(str(c["key"])) / (1.0 + 12.0 / GOALS.DIST_SCALE), 0.01)
	# past SPECIAL_SEE: unknown, unless it is the one he hunts (SPECIAL_KEEP)
	em.pos[0] = Vector3(GOALS.SPECIAL_SEE + 5.0, 0, 0)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}))).size()).is_equal(0)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, str(c["key"])))).size()).is_equal(1)
	em.pos[0] = Vector3(GOALS.SPECIAL_KEEP + 5.0, 0, 0)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, str(c["key"])))).size()).is_equal(0)
	# in reach (within IN_REACH and on the screen): the weapons take it, no goal; off the screen it is one; the one he
	# hunts stays his goal in reach too
	em.pos[0] = Vector3(5, 0, 0)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}))).size()).is_equal(0)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, str(c["key"])))).size()).is_equal(1)
	em.onscreen[0] = 0
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}))).size()).is_equal(1)
	em.onscreen[0] = 1
	em.pos[0] = Vector3(12, 0, 0)
	# no hunt while a boss lives (the boss is the fight)
	var vb := _view({"preset": "explorer", "explore": 0.0}, 1.0, str(c["key"]))
	vb["boss"] = Vector3(-20, 0, 0)
	assert_int(_specials(gl.candidates(g, null, vb)).size()).is_equal(0)
	# the option off, hurt, dying, resting after a give-up, another creature in its slot: no goal
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0, "specials": false}))).size()).is_equal(0)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, GOALS.SPECIAL_HP - 0.05))).size()).is_equal(0)
	# the hunt under way goes on below that, down to SPECIAL_HP_HELD (no flip-flop on a health hovering at the line)
	assert_float(GOALS.SPECIAL_HP_HELD).is_less(GOALS.SPECIAL_HP)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, GOALS.SPECIAL_HP - 0.05, str(c["key"])))).size()).is_equal(1)
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, GOALS.SPECIAL_HP_HELD - 0.05, str(c["key"])))).size()).is_equal(0)
	em.state[0] = FakeEnemies.STATE_DYING
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}))).size()).is_equal(0)
	em.state[0] = 0
	gl.resting[str(c["key"])] = 100.0
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}))).size()).is_equal(0)
	gl.resting.clear()
	em.serial[0] = 8
	assert_int(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}))).size()).is_equal(0)
	assert_str(str(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, "", 30.0)))[0]["key"])).is_equal(GOALS.special_key(0, 8))
	# the style's word: greedy wants it more (the chest), safety less
	var u_b := float(_specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, "", 30.0)))[0]["u"])
	var vg := _view({"preset": "explorer", "explore": 0.0}, 1.0, "", 30.0)
	vg["style"] = "greedy"
	var vs := _view({"preset": "explorer", "explore": 0.0}, 1.0, "", 30.0)
	vs["style"] = "safety"
	assert_float(float(_specials(gl.candidates(g, null, vg))[0]["u"])).is_greater(u_b)
	assert_float(float(_specials(gl.candidates(g, null, vs))[0]["u"])).is_less(u_b)


func test_the_real_creatures_say_their_chest() -> void:
	# the real EnemyDef's special_value answers through an instance (the planner calls it so: no game class named there)
	var def: EnemyDef = Registry.enemy("goblin") if Registry.enemy("goblin") != null else Registry.enemies.values()[0]
	var g := _fake_game()
	g.enemies.types = [{"def": def}]
	g.enemies.special_defaults = {"chest_chance": 0.5}
	g.enemies.put(2, Vector3(0, 0, 12), true, 3)
	var gl = GOALS.new(1)
	gl.setup_map(g.map)
	gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0}, 1.0, "", 10.0))
	var sp := _specials(gl.candidates(g, null, _view({"preset": "explorer", "explore": 0.0})))
	assert_int(sp.size()).is_equal(1)
	var want := roundi(EnemyDef.special_value(def.variance.get("special", {}), {"chest_chance": 0.5}, "chest_chance") * 100.0)
	var words := "a special: %s" % def.display_name + ((", a %d%% chest" % want) if want > 0 else "") + ", out of reach 10 s"
	assert_str(str(sp[0]["why"])).is_equal(words)


func test_the_hunt_is_logged_from_its_start_to_its_end() -> void:
	var g := _fake_game()
	var em: FakeEnemies = g.enemies
	em.put(0, Vector3(14, 0, 0), true, 5)
	var bot = BOT.new(g, {"seed": 4, "preset": "explorer"})
	assert_object(bot.planner).is_not_null()
	bot.planner.special_seen[GOALS.special_key(0, 5)] = 0.0
	var cands := _specials(bot.planner.candidates(g, null, _view({"preset": "explorer", "explore": 0.0})))
	bot._commit(cands[0], {})
	var e: Dictionary = bot.decisions[bot.decisions.size() - 1]
	assert_str(str(e["kind"])).is_equal("goal")
	assert_str(str(e["what"])).is_equal("special")
	assert_str(str(e["reason"])).is_equal("a special: Red Goblin, a 35% chest, out of reach 20 s (14 m)")
	assert_str(str(bot.goal["what"])).is_equal("special")
	# its patience: the walk's, and the fight's on top
	assert_float(float(bot._cur["patience"])).is_equal_approx(BOT.PATIENCE_BASE + 14.0 * BOT.PATIENCE_PER_M + GOALS.SPECIAL_FIGHT_S, 0.01)
	# it moves: the hunt follows it frame by frame
	em.pos[0] = Vector3(10, 0, 3)
	assert_vector(bot._special_at(bot._cur)).is_equal(Vector3(10, 0, 3))
	assert_bool(bot._goal_done(bot._cur)).is_false()
	# it falls (and drops a chest): done, and a "special" entry says so
	em.state[0] = FakeEnemies.STATE_DYING
	em.special_chests = 1
	assert_bool(bot._goal_done(bot._cur)).is_true()
	bot._cur["hunt_t"] = 7.4
	bot._goal_finished(bot._cur)
	var d: Dictionary = bot.decisions[bot.decisions.size() - 1]
	assert_str(str(d["kind"])).is_equal("special")
	assert_str(str(d["taken"])).is_equal("red_goblin")
	assert_str(str(d["reason"])).is_equal("the special Red Goblin is down after 7 s of the hunt, a chest dropped")
	assert_int(int(bot.specials_down)).is_equal(1)
	# a new creature in its slot is another one: the old hunt is done
	em.put(0, Vector3(3, 0, 0), true, 6)
	assert_bool(BOT.special_standing(em, 0, 5)).is_false()
	assert_bool(BOT.special_standing(em, 0, 6)).is_true()
	assert_bool(BOT.special_standing(null, 0, 6)).is_false()
	# a hunt of that one: it comes in reach (within HUNT_NEAR and on the screen): found, the hunt ends, the weapons take it
	em.pos[0] = Vector3(14, 0, 0)
	bot.planner.special_seen[GOALS.special_key(0, 6)] = 0.0
	bot._commit(_specials(bot.planner.candidates(g, null, _view({"preset": "explorer", "explore": 0.0})))[0], {})
	assert_bool(bot._goal_done(bot._cur)).is_false()
	em.pos[0] = Vector3(4, 0, 0)
	assert_bool(bot._goal_done(bot._cur)).is_true()
	bot._cur["hunt_t"] = 3.2
	bot._goal_finished(bot._cur)
	var f: Dictionary = bot.decisions[bot.decisions.size() - 1]
	assert_str(str(f["kind"])).is_equal("special")
	assert_str(str(f["reason"])).is_equal("found the special Red Goblin after 3 s: in reach, the weapons take it first")
	assert_int(int(bot.specials_found)).is_equal(1)
	# found: its clock of being out of reach starts again (no re-hunt the next half second when it slips off the screen)
	assert_float(float(bot.planner.special_seen[GOALS.special_key(0, 6)])).is_equal(bot.play_t())
	# the run sim's tallies carry the hunts
	var sm: Dictionary = bot.summary()
	assert_bool(sm.has("specials")).is_true()
	for k in ["came", "killed", "chests", "life_s", "hunted", "found", "hunted_down", "gave_up"]:
		assert_bool((sm["specials"] as Dictionary).has(k)).override_failure_message(k).is_true()
	assert_int(int(sm["specials"]["hunted"])).is_equal(2)
	assert_int(int(sm["specials"]["found"])).is_equal(1)
	assert_int(int(sm["specials"]["hunted_down"])).is_equal(1)


class FakeRA:
	extends Node
	var events: Array = []
	var play_t := 0.0


func test_the_specials_tallies_and_their_time_alive() -> void:
	var g := _fake_game()
	var ra := FakeRA.new()
	ra.name = "RunAnalytics"
	g.add_child(ra)
	# two came at 10 s and 20 s, one fell at 30 s (a chest), the other still stands at 50 s: (30 - 10) + (50 - 20) = 50 s
	ra.events = [{"t": 10.0, "kind": "special", "id": "goblin"}, {"t": 20.0, "kind": "special", "id": "skeleton"},
		{"t": 30.0, "kind": "special_kill", "id": "goblin", "chest": true}, {"t": 31.0, "kind": "pickup", "id": "heart"}]
	ra.play_t = 50.0
	var bot = BOT.new(g, {"seed": 4, "preset": "explorer"})
	var sp: Dictionary = bot.special_tallies()
	assert_int(int(sp["came"])).is_equal(2)
	assert_int(int(sp["killed"])).is_equal(1)
	assert_int(int(sp["chests"])).is_equal(1)
	assert_float(float(sp["life_s"])).is_equal_approx(25.0, 0.01)


func test_in_reach_ends_the_hunt_and_the_kite_still_wins() -> void:
	# in reach: within HUNT_NEAR and on the screen
	var g := _fake_game()
	var em: FakeEnemies = g.enemies
	em.put(0, Vector3(BOT.HUNT_NEAR - 0.5, 0, 0), true, 1)
	assert_bool(BOT.special_in_reach(em, 0, Vector3.ZERO)).is_true()
	em.onscreen[0] = 0
	assert_bool(BOT.special_in_reach(em, 0, Vector3.ZERO)).is_false()
	em.onscreen[0] = 1
	em.pos[0] = Vector3(BOT.HUNT_NEAR + 0.5, 0, 0)
	assert_bool(BOT.special_in_reach(em, 0, Vector3.ZERO)).is_false()
	# inside the weapons' priority reach (10 m, the map's target_priority), and the planner's "in reach"
	assert_float(BOT.HUNT_FAR).is_less_equal(10.0)
	assert_float(BOT.HUNT_FAR).is_equal(GOALS.IN_REACH)
	assert_float(BOT.HUNT_NEAR).is_less_equal(GOALS.IN_REACH)
	# a hunted special is never "grabbed": close to it the hold rule still lets the kite take over
	em.put(0, Vector3(1, 0, 0), true, 1)
	var bot = BOT.new(g, {"seed": 4, "preset": "explorer"})
	bot._cur = {"kind": "special", "key": "sp:0:1", "at": Vector3(1, 0, 0), "index": 0, "serial": 1}
	bot._near_n = BOT.HOLD_CROWD
	bot._update_hold(0.1, 1.0)
	assert_bool(bot._hold).is_true()


# ---------------------------------------------------------------- the mouse on the phone view

func test_the_mouse_becomes_the_phones_finger() -> void:
	var view := Vector2(432, 960)
	var sub := Vector2(432, 960)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(100, 200)
	var f: Dictionary = WATCH.finger_event(press, view, sub, false, Vector2.ZERO)
	assert_bool(f["event"] is InputEventScreenTouch).is_true()
	var t: InputEventScreenTouch = f["event"]
	assert_bool(t.pressed).is_true()
	assert_int(t.index).is_equal(0)
	assert_vector(t.position).is_equal(Vector2(100, 200))
	assert_bool(bool(f["down"])).is_true()
	# a SubViewport twice the view's pixels: the position scales with it
	assert_vector((WATCH.finger_event(press, view, sub * 2.0, false, Vector2.ZERO)["event"] as InputEventScreenTouch).position).is_equal(Vector2(200, 400))
	# the drag while held: a ScreenDrag of finger 0 with its step
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(110, 230)
	var dr: Dictionary = WATCH.finger_event(mv, view, sub, true, Vector2(100, 200))
	assert_bool(dr["event"] is InputEventScreenDrag).is_true()
	assert_vector((dr["event"] as InputEventScreenDrag).relative).is_equal(Vector2(10, 30))
	assert_int((dr["event"] as InputEventScreenDrag).index).is_equal(0)
	# nothing held: a move is no touch; the release lifts the finger
	assert_bool(WATCH.finger_event(mv, view, sub, false, Vector2.ZERO).is_empty()).is_true()
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(110, 230)
	var r: Dictionary = WATCH.finger_event(rel, view, sub, true, Vector2(110, 230))
	assert_bool((r["event"] as InputEventScreenTouch).pressed).is_false()
	assert_bool(bool(r["down"])).is_false()
	# a release with nothing held, another button, the window's own (emulated) touches: nothing
	assert_bool(WATCH.finger_event(rel, view, sub, false, Vector2.ZERO).is_empty()).is_true()
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	assert_bool(WATCH.finger_event(right, view, sub, false, Vector2.ZERO).is_empty()).is_true()
	var emu := InputEventScreenTouch.new()
	emu.pressed = true
	assert_bool(WATCH.finger_event(emu, view, sub, false, Vector2.ZERO).is_empty()).is_true()
	assert_bool(WATCH.finger_event(press, Vector2.ZERO, sub, false, Vector2.ZERO).is_empty()).is_true()


class TouchCatcher:
	extends Control
	var got: Array = []

	func _gui_input(e: InputEvent) -> void:
		got.append(e)


func test_a_click_reaches_the_games_canvas_in_its_subviewport() -> void:
	# the Watch's set-up in small: a SubViewport of the view's pixels whose 2D is the phone's 1080-wide canvas
	var sv := SubViewport.new()
	sv.size = Vector2i(216, 480)
	sv.size_2d_override = Vector2i(1080, 2400)
	sv.size_2d_override_stretch = true
	sv.handle_input_locally = false
	add_child(sv)
	auto_free(sv)
	var layer := CanvasLayer.new()
	sv.add_child(layer)
	var ctl := TouchCatcher.new()
	ctl.position = Vector2(900, 100)
	ctl.size = Vector2(100, 100)
	layer.add_child(ctl)
	await get_tree().process_frame
	# a click on the view at (190, 30) is the canvas's (950, 150): inside the control, at its (50, 50)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(190, 30)
	var f: Dictionary = WATCH.finger_event(press, Vector2(216, 480), Vector2(sv.size), false, Vector2.ZERO)
	sv.push_input(f["event"])
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(190, 30)
	sv.push_input(WATCH.finger_event(rel, Vector2(216, 480), Vector2(sv.size), true, f["at"])["event"])
	var touches: Array = ctl.got.filter(func(e) -> bool: return e is InputEventScreenTouch)
	assert_int(touches.size()).is_equal(2)
	assert_vector((touches[0] as InputEventScreenTouch).position).is_equal_approx(Vector2(50, 50), Vector2(0.01, 0.01))
	assert_bool((touches[0] as InputEventScreenTouch).pressed).is_true()
	assert_bool((touches[1] as InputEventScreenTouch).pressed).is_false()
	# no mouse event reaches the game (the phone sends none: nothing that reads both fires twice)
	assert_int(ctl.got.filter(func(e) -> bool: return e is InputEventMouse).size()).is_equal(0)
	# a click outside it is not its
	ctl.got.clear()
	press.position = Vector2(20, 400)
	sv.push_input(WATCH.finger_event(press, Vector2(216, 480), Vector2(sv.size), false, Vector2.ZERO)["event"])
	assert_int(ctl.got.size()).is_equal(0)


# ---------------------------------------------------------------- the clock while the game's own pause screen is up

func test_the_games_own_pause_runs_the_frames_as_at_1x() -> void:
	var c = CLOCK.new()
	c.set_speed(8.0)
	assert_float(c.running_speed()).is_equal(8.0)
	c.game_hold = true
	assert_float(c.running_speed()).is_equal(1.0)
	# 60 frames a second, every one drawn, the time scale 1 (the screen's tweens move as on the phone)
	assert_int(c.pace(1000000)).is_equal(0)
	assert_int(c.pace(1000000)).is_equal(16666)
	assert_bool(c.draw_due(2000000)).is_true()
	assert_bool(c.draw_due(2001000)).is_true()
	c.game_hold = false
	c.set_speed(0.25)
	assert_float(c.compose(1.0)).is_equal_approx(0.25, 0.0001)
	c.game_hold = true
	assert_float(c.compose(0.25)).is_equal_approx(1.0, 0.0001)
	# the game goes on: the speed asked comes back
	c.game_hold = false
	assert_float(c.running_speed()).is_equal(0.25)
	assert_float(c.compose(1.0)).is_equal_approx(0.25, 0.0001)


# ---------------------------------------------------------------- the totals and the marks

func _events() -> Array:
	return [{"t": 12.0, "clock": 12.0, "kind": "chest", "id": "revolver", "roll": "weapon", "take": true},
		{"t": 30.0, "clock": 30.0, "kind": "pickup", "id": "magnet_pulse", "small": false, "effect": "vacuum"},
		{"t": 31.0, "clock": 31.0, "kind": "pickup", "id": "cake_slice", "small": true, "effect": "heal"},
		{"t": 40.0, "clock": 40.0, "kind": "special", "id": "goblin", "forced": false},
		{"t": 52.0, "clock": 52.0, "kind": "special_kill", "id": "goblin", "chest": true, "weapon": "revolver"},
		{"t": 60.0, "clock": 60.0, "kind": "structure", "id": "totem_pole", "effect": "totem"},
		{"t": 62.0, "clock": 62.0, "kind": "totem", "id": "bear", "level": 1, "stat": "might", "value": 0.06},
		{"t": 70.0, "clock": 70.0, "kind": "chest", "id": "", "roll": "gold", "take": false, "skip": true, "left": 1},
		{"t": 80.0, "clock": 80.0, "kind": "special", "id": "scorpion", "forced": true}]


func test_the_totals_and_the_marks_come_from_the_events() -> void:
	var d = DATA.new()
	var ev := _events()
	assert_int(d.read_events(ev)).is_equal(ev.size())
	# lane STATS' rule: every chest opened (a skipped one too), the power-ups (not the small things), the gifts taken
	assert_dict(d.pickup_totals()).is_equal({"chests": 2, "powerups": 1, "totems": 1})
	assert_dict(d.pickup_totals()).is_equal(SIM.pickup_totals(ev))
	assert_array(d.pickups["chests"]).is_equal([12.0, 70.0])
	assert_array(d.pickups["totems"]).is_equal([62.0])
	assert_int(d.specials_came).is_equal(2)
	assert_int(d.specials_killed).is_equal(1)
	assert_int(d.special_chests).is_equal(1)
	# read once
	assert_int(d.read_events(ev)).is_equal(0)
	assert_dict(d.pickup_totals()).is_equal({"chests": 2, "powerups": 1, "totems": 1})
	# the marks: one a pickup, a lane, a shape and a colour each kind
	var pts: Array = PANEL.pickup_points(d.pickups)
	assert_int(pts.size()).is_equal(4)
	var by := {}
	for p in pts:
		by[str(p["shape"])] = int(by.get(str(p["shape"]), 0)) + 1
	assert_dict(by).is_equal({"square": 2, "circle": 1, "triangle": 1})
	var lanes := {}
	for m in PANEL.PICKUP_MARKS:
		lanes[int(m[4])] = true
	assert_int(lanes.size()).is_equal(3)
	# a hunt's end is no build change: no DPS change is computed for it
	d.add_decision({"t": 20.0, "kind": "special", "taken": "goblin"})
	d.fill_decisions(200.0)
	assert_float(float(d.decisions[0]["real_after"])).is_equal(-1.0)


func test_the_chart_draws_its_marks_and_shaped_legend() -> void:
	var c = CHART.new()
	c.size = Vector2(600, 160)
	c.x0 = 0.0
	c.x1 = 180.0
	c.points = PANEL.pickup_points({"chests": [12.0, 500.0], "powerups": [30.0], "totems": [62.0]})
	c.legend = [["Chests 2", Color.YELLOW, "square"], ["Level", Color.BLUE]]
	add_child(c)
	auto_free(c)
	c.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(int(c.draw_us)).is_greater(0)
	assert_int(CHART.triangle(Vector2(10, 10), 4.0).size()).is_equal(3)
