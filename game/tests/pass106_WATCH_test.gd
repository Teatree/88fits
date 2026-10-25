extends GdUnitTestSuite

## Pass 106, lane WATCH (Garry: "Add functionality which allows me to take over the play. Nothing changes with the UI, but
## There is now a button next to 'Pause' which lets me control the sequence myself. When it's on, the speed ups work the
## same way as for the bot. I can pause and turn the bot controls back on when I want to."): the "Bot plays" / "You play"
## button beside Pause and T; while you play the bot is never ticked, the hero's own input steers him (WASD through the
## Input map, the mouse in the phone view as the phone's finger on the one-thumb stick) and the cards wait for your
## click; back to the bot, his input muted and the bot ticking again; the stretches in the record (events, header,
## the decision log's rows and its `driver` column) and as the charts' marks.

const DATA := preload("res://tools/watch/WatchData.gd")
const PANEL := preload("res://tools/watch/WatchPanel.gd")
const PLAQUE := preload("res://tools/watch/WatchPlaque.gd")
const WATCH := preload("res://tools/watch/Watch.gd")
const SETUP := preload("res://tools/watch/WatchSetup.gd")


var _scale_mode := 0
var _scale_aspect := 0


func before_test() -> void:
	_scale_mode = get_window().content_scale_mode
	_scale_aspect = get_window().content_scale_aspect


func after_test() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	get_window().content_scale_mode = _scale_mode
	get_window().content_scale_aspect = _scale_aspect
	Run.launch_override = {}
	Run.sim_mode = false
	Run.seed_dice(0)
	Run.forced_map_seed = 0
	get_tree().paused = false
	Engine.time_scale = 1.0
	RenderingServer.render_loop_enabled = true
	AudioServer.set_bus_mute(0, false)
	if Save.sandboxed():
		Save.end_sandbox()
	RunAnalytics.I = null
	Run.end()


# ---------------------------------------------------------------- pure parts

func test_the_stretches_seconds_and_their_marks() -> void:
	assert_float(WATCH.hand_seconds([[10.0, 25.0], [40.0, 41.5]])).is_equal_approx(16.5, 0.001)
	assert_float(WATCH.hand_seconds([])).is_equal(0.0)
	assert_float(WATCH.hand_seconds([[5.0, 3.0], "junk"])).is_equal(0.0)
	# the live stretch has no end mark yet
	var m: Array = PANEL.hand_marks([[10.0, 25.0], [40.0, 41.5]], true)
	assert_int(m.size()).is_equal(3)
	assert_str(str(m[0]["name"])).is_equal("You took over at 0:10")
	assert_str(str(m[1]["name"])).is_equal("The bot again at 0:25, after 0:15 by hand")
	assert_float(float(m[2]["x"])).is_equal(40.0)
	assert_int(PANEL.hand_marks([[10.0, 25.0]], false).size()).is_equal(2)
	assert_int(PANEL.hand_marks([], false).size()).is_equal(0)


func test_the_plaque_says_you_play() -> void:
	assert_str(str(PLAQUE.words_of({"started": true, "hand": true})["text"])).is_equal("You play")
	assert_str(str(PLAQUE.words_of({"started": true, "hand": true})["cap"])).is_equal("YOU")
	assert_str(str(PLAQUE.words_of({"started": true, "intent": "kite"}).get("cap", "BOT"))).is_equal("BOT")
	assert_str(str(PLAQUE.words_of({"started": true, "hand": true, "screens": "cards"})["sub"])).contains("click a card")
	assert_str(str(PLAQUE.words_of({"started": true, "hand": true, "screens": "chest"})["sub"])).contains("click")
	# down, the Watch's question comes first; the bot's words without hand
	assert_str(str(PLAQUE.words_of({"started": true, "hand": true, "down_wait": true})["text"])).is_equal("Down!")
	assert_str(str(PLAQUE.words_of({"started": true, "intent": "breakout"})["text"])).is_equal("Breaking out")


func test_the_csv_says_who_played() -> void:
	var d = DATA.new()
	d.add_decision({"t": 30.0, "clock": 30.0, "kind": "card", "level": 3, "taken": "revolver", "reason": "r", "offered": [], "dps_before": 50.0})
	d.add_decision({"t": 41.0, "clock": 41.0, "kind": "takeover", "level": 3, "taken": "", "reason": "you took over (#1)", "offered": [],
		"dps_before": 0.0, "driver": "hand"})
	d.add_decision({"t": 90.0, "clock": 90.0, "kind": "handback", "level": 5, "taken": "", "reason": "back", "offered": [],
		"dps_before": 0.0, "driver": "bot"})
	assert_str(str(DATA.CSV_COLUMNS[-1])).is_equal("driver")
	var lines := d.decisions_csv().strip_edges().split("\n")
	assert_int(lines.size()).is_equal(4)
	assert_str(lines[0]).ends_with(",driver")
	assert_str(lines[1]).ends_with(",bot")
	assert_str(lines[2]).contains(",takeover,")
	assert_str(lines[2]).ends_with(",hand")
	assert_str(lines[3]).ends_with(",bot")
	# a takeover or a handback changes no build: no DPS change of its own
	d.fill_decisions(1000.0, true)
	assert_float(float(d.decisions[1]["real_before"])).is_equal(-1.0)
	assert_float(float(d.decisions[2]["real_before"])).is_equal(-1.0)


# ---------------------------------------------------------------- a run: you play, then the bot again

func _watch(extra: Dictionary = {}) -> Node:
	var w = WATCH.new()
	var a := {"hero": "drifter", "seed": "11", "talents": "none", "analytics": "memory", "repo": "user://p106_no_such_dir",
		"speed": "1", "bot": "stub", "death": "ask"}
	for k in extra:
		a[k] = extra[k]
	w.set("args", a)
	add_child(w)
	await get_tree().process_frame
	var s := SETUP.defaults_from_args(a)
	w.setup.visible = false
	w._begin_run(s, false)
	var waited := 0
	while not w._attached and waited < 120:
		await get_tree().process_frame
		waited += 1
	return w


## A mouse event on the phone view at canvas point `p` (the game's 1080-wide canvas), handed to the view's input.
func _mouse(w, p: Vector2, kind: String) -> void:
	var cs := Vector2(w.sub.size_2d_override)
	var at: Vector2 = p * w.view.size / cs
	if kind == "move":
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		w._on_view_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = kind == "down"
	mb.position = at
	w._on_view_input(mb)


func _key(w, k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	w._unhandled_input(e)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func test_you_play_then_the_bot_again() -> void:
	var w = await _watch()
	assert_bool(w._attached).is_true()
	assert_bool(w.hand).is_false()
	await _frames(10)
	var game: Node = w.game
	var p = game.player
	var inp = p.input
	# the bot plays: his own input muted
	assert_bool(bool(inp.enabled)).is_false()
	# the button beside Pause: you play
	w.panel.press_hand_button()
	assert_bool(w.hand).is_true()
	assert_bool(bool(inp.enabled)).is_true()
	assert_bool(bool(inp.wants_move)).is_false()
	assert_str(w.driver_now()).is_equal("hand")
	assert_str(w.status_words()).contains("you play")
	w.panel.refresh()
	assert_str(w.panel._hand_btn.text).is_equal("You play")
	assert_bool(w.panel._hand_btn.button_pressed).is_true()
	var bot_t: float = float(w.bot._t)
	await _frames(20)
	# the bot is never ticked
	assert_float(float(w.bot._t)).is_equal(bot_t)
	# WASD: D (through the Input map) steers him right; the Watch leaves D to the stick while you play
	var hurt_tab := bool(w.panel.show_hurt)
	var ev := InputEventKey.new()
	ev.keycode = KEY_D
	ev.physical_keycode = KEY_D
	ev.pressed = true
	Input.parse_input_event(ev)
	w._unhandled_input(ev)
	await _frames(3)
	assert_bool(bool(w.panel.show_hurt)).is_equal(hurt_tab)
	assert_bool(bool(inp.keyboard)).is_true()
	assert_float(float(inp.stick_dir.x)).is_greater(0.9)
	var x0: float = p.global_position.x
	await _frames(30)
	assert_float(p.global_position.distance_to(Vector3(x0, p.global_position.y, p.global_position.z))).is_greater(0.05)
	var up := InputEventKey.new()
	up.keycode = KEY_D
	up.physical_keycode = KEY_D
	up.pressed = false
	Input.parse_input_event(up)
	Input.action_release("move_right")
	await _frames(3)
	assert_bool(bool(inp.keyboard)).is_false()
	# the mouse in the phone view is the phone's finger: the stick under it, a drag to the left steers him left
	_mouse(w, Vector2(540, 1500), "down")
	await _frames(1)
	assert_int(int(inp.active_index)).is_equal(0)
	_mouse(w, Vector2(300, 1500), "move")
	await _frames(2)
	assert_float(float(inp.stick_dir.x)).is_less(-0.9)
	_mouse(w, Vector2(300, 1500), "up")
	await _frames(1)
	assert_int(int(inp.active_index)).is_equal(-1)
	assert_bool(bool(inp.wants_move)).is_false()
	# a level-up: the cards wait for you (the bot would have answered within HOLD_S)
	Run.add_xp(Run.xp_to_next() - Run.xp + 0.01)
	var waited := 0
	while not w.level_cards_up() and waited < 300:
		await get_tree().process_frame
		waited += 1
	assert_bool(w.level_cards_up()).is_true()
	assert_str(str(w.plaque_words()["sub"])).contains("click a card")
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < int((WATCH.HOLD_S + 0.7) * 1000.0) and n < 3000:
		await get_tree().process_frame
		n += 1
	assert_bool(w.level_cards_up()).is_true()
	var level: int = int(Run.level)
	# your click on the first card picks it
	var card: Control = game.cards._cards[0]
	var at: Vector2 = WATCH.canvas_middle(card)
	_mouse(w, at, "down")
	await _frames(2)
	_mouse(w, at, "up")
	waited = 0
	while game.cards.visible and waited < 300:
		await get_tree().process_frame
		waited += 1
	assert_bool(bool(game.cards.visible)).is_false()
	assert_int(int(Run.level)).is_equal(level)
	# no card decision came from the bot
	for d in w.data.decisions:
		assert_str(str(d.get("kind", ""))).is_not_equal("card")
	await _frames(10)
	# T: the bot again, his input muted, the bot ticking
	_key(w, KEY_T)
	assert_bool(w.hand).is_false()
	assert_bool(bool(inp.enabled)).is_false()
	assert_bool(bool(inp.wants_move)).is_false()
	var bt2: float = float(w.bot._t)
	# (a screen still up, the TAP TO GO gate after the pick, is the bot's after HOLD_S of wall time)
	var t1 := Time.get_ticks_msec()
	var n1 := 0
	while (float(w.bot._t) <= bt2 or Time.get_ticks_msec() - t1 < 300) and Time.get_ticks_msec() - t1 < int((WATCH.HOLD_S + 2.0) * 1000.0) and n1 < 5000:
		await get_tree().process_frame
		n1 += 1
	assert_float(float(w.bot._t)).is_greater(bt2)
	# the record: the events, the header's stretch, the decision log and its CSV
	var kinds: Array = []
	for e in w.ra.events:
		if str(e["kind"]) in ["takeover", "handback"]:
			kinds.append(str(e["kind"]))
	assert_array(kinds).is_equal(["takeover", "handback"])
	var hdr: Dictionary = w.ra.header
	var st: Array = hdr["watch"]["hand"]
	assert_int(st.size()).is_equal(1)
	assert_float(float(st[0][1])).is_greater(float(st[0][0]))
	assert_float(float(hdr["watch"]["hand_s"])).is_greater(0.0)
	var csv: String = w.data.decisions_csv()
	assert_int(csv.count(",takeover,")).is_equal(1)
	assert_int(csv.count(",handback,")).is_equal(1)
	assert_bool(csv.contains(",hand\n")).is_true()
	assert_int(PANEL.hand_marks(w.hand_stretches, w.hand).size()).is_equal(2)
	# End run: the words say what you played
	w.end_now()
	waited = 0
	while not w.ended and waited < 120:
		await get_tree().process_frame
		waited += 1
	assert_bool(w.ended).is_true()
	assert_str(w.end_words()).contains("You played")
	w.queue_free()
	await _frames(2)


func test_a_run_can_start_in_your_hands_and_end_there() -> void:
	var w = await _watch({"hand": "1"})
	assert_bool(w.hand).is_true()
	var inp = w.game.player.input
	assert_bool(bool(inp.enabled)).is_true()
	assert_int(w.hand_stretches.size()).is_equal(1)
	var bot_t: float = float(w.bot._t)
	await _frames(60)
	assert_float(float(w.bot._t)).is_equal(bot_t)
	# the live stretch follows the play
	assert_float(float(w.hand_stretches[0][1])).is_equal_approx(snappedf(w.play_t(), 0.1), 0.11)
	# pause and the speeds are the clock's, the same for both
	w.toggle_pause()
	assert_bool(w.clock.paused).is_true()
	w.toggle_pause()
	w.set_speed(4.0)
	assert_float(w.clock.speed).is_equal(4.0)
	w.set_speed(1.0)
	await _frames(20)
	var t_end: float = w.play_t()
	w.end_now()
	var waited := 0
	while not w.ended and waited < 120:
		await get_tree().process_frame
		waited += 1
	assert_bool(w.ended).is_true()
	assert_float(float(w.hand_stretches[0][1])).is_greater(0.0)
	assert_float(float(w.hand_stretches[0][1])).is_less_equal(t_end + 0.2)
	# the choice outlives the run (a Restart starts in the same hands)
	assert_bool(w.hand).is_true()
	w.queue_free()
	await _frames(2)
