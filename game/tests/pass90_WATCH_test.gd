extends GdUnitTestSuite

## Pass 90, lane WATCH (Garry: "add a tab in the HP, and Danger beneath which would show a breakdown of where the damage
## comes from"; "add a highlight to the Charts. One that shows a hint when you hover over the charts"; "allow me to
## manually revive the Bot when he dies. Like, as many times as I like ... it will continue the run like nothing
## happened"): the Damage taken breakdown summed from the hero's damage log (read as it is trimmed, heals left out, the
## shield's and the evaded parts apart, the window), its table and hint; the charts' hover (the nearest sample, the
## named lines, bands and marks, nothing off the plot); the revive: a fall holds the run (no Down!, no end), Revive
## stands him up at full health with the run going on, as often as wanted, counted in the record; End run while down
## ends it as a death; "auto" stands him up by itself.

const DATA := preload("res://tools/watch/WatchData.gd")
const CHART := preload("res://tools/watch/WatchChart.gd")
const HURT := preload("res://tools/watch/WatchHurt.gd")
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


static func _hit(by: String, kind: String, fx: Array, raw: float, dealt: float, shield: float = 0.0, note: String = "", role: String = "") -> Dictionary:
	return {"t": 0.0, "by": by, "id": by.to_lower(), "kind": kind, "role": role, "colour": "", "fx": fx, "raw": raw, "dealt": dealt,
		"shield": shield, "note": note, "hp": 50.0, "fatal": false}


# ---------------------------------------------------------------- the damage taken

func test_the_breakdown_sums_from_a_damage_log() -> void:
	var d = DATA.new()
	var dlog: Array = [_hit("Goblin", "melee", [], 10.0, 8.0), _hit("Goblin", "melee", ["knocked back"], 10.0, 0.0, 0.0, "evaded"),
		{"t": 0.0, "by": "Cake", "kind": "heal", "dealt": 0.0, "raw": 0.0, "fx": []},
		_hit("Vulture Raider", "ranged", ["rocket"], 30.0, 0.0, 20.0, "shield", "special")]
	assert_int(d.read_hurt(dlog, 10.0)).is_equal(3)
	# read again: nothing new
	assert_int(d.read_hurt(dlog, 11.0)).is_equal(0)
	# the log is trimmed at its head and grows at its tail: only the new ones come
	dlog.pop_front()
	dlog.append(_hit("Goblin", "melee", ["charge", "knocked back"], 20.0, 16.0))
	dlog.append(_hit("Gila Grande", "boss", ["volley"], 40.0, 0.0, 0.0, "power-up", "boss"))
	assert_int(d.read_hurt(dlog, 40.0)).is_equal(2)
	var rows: Array = d.hurt_rows()
	# Goblin's bite, Goblin's charge, the Raider's rocket, the Gila's volley: by HP lost, then the shield's part, then hits
	assert_int(rows.size()).is_equal(4)
	assert_str(str(rows[0]["key"])).is_equal("Goblin|charge")
	assert_float(float(rows[0]["lost"])).is_equal(16.0)
	assert_str(str(rows[1]["key"])).is_equal("Goblin|bite")
	assert_float(float(rows[1]["lost"])).is_equal(8.0)
	assert_int(int(rows[1]["hits"])).is_equal(2)
	assert_int(int(rows[1]["evaded"])).is_equal(1)
	assert_float(float(rows[1]["evaded_raw"])).is_equal(10.0)
	assert_str(str(rows[2]["attack"])).is_equal("rocket")
	assert_float(float(rows[2]["shield"])).is_equal(20.0)
	assert_str(str(rows[3]["attack"])).is_equal("volley")
	assert_int(int(rows[3]["blocked"])).is_equal(1)
	# the totals: HP lost and the shield's part apart
	var tot: Dictionary = DATA.hurt_totals(rows)
	assert_float(float(tot["lost"])).is_equal(24.0)
	assert_float(float(tot["shield"])).is_equal(20.0)
	assert_int(int(tot["hits"])).is_equal(5)
	assert_int(int(tot["evaded"])).is_equal(1)
	# the window: only what came at or after play second 30
	var win: Array = d.hurt_rows(30.0)
	assert_int(win.size()).is_equal(2)
	assert_float(float(DATA.hurt_totals(win)["lost"])).is_equal(16.0)
	# the kind's word when the words name no attack
	assert_str(DATA.attack_of("melee", ["knocked back"])).is_equal("bite")
	assert_str(DATA.attack_of("ranged", [])).is_equal("shot")
	assert_str(DATA.attack_of("boss", ["ground rumble", "thrown"])).is_equal("ground rumble")
	# the table: the run's share and the window's beside it, sortable
	var tab: Array = HURT.table(rows, win, "run")
	assert_str(str(tab[0]["key"])).is_equal("Goblin|charge")
	assert_float(float(tab[0]["share"])).is_equal_approx(16.0 / 24.0, 0.0001)
	assert_float(float(tab[0]["w_share"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(tab[1]["w_lost"])).is_equal(0.0)
	var by_hits: Array = HURT.table(rows, win, "hits")
	assert_str(str(by_hits[0]["key"])).is_equal("Goblin|bite")
	var by_shield: Array = HURT.table(rows, win, "shield")
	assert_str(str(by_shield[0]["key"])).is_equal("Vulture Raider|rocket")
	# the hint tells a row's whole story
	var lines: PackedStringArray = HURT.hint_lines(tab[1], 30, 40.0)
	assert_str(lines[0]).is_equal("Goblin · bite")
	assert_str(lines[1]).contains("2 hits")
	assert_str(lines[1]).contains("8 HP lost (33%")
	assert_str("\n".join(lines)).contains("1 evaded (10)")
	assert_str(HURT.hint_lines(tab[2], 30, 40.0)[0]).is_equal("Vulture Raider · rocket (special)")
	assert_bool(HURT.dot_colour({"role": "boss"}) == HURT.BAD).is_true()


func test_the_table_draws_and_answers_its_clicks() -> void:
	var h = HURT.new()
	h.size = Vector2(720, 180)
	add_child(h)
	var rows: Array = DATA.sum_hurt([DATA.hit_of(_hit("Goblin", "melee", [], 10.0, 8.0), 5.0),
		DATA.hit_of(_hit("Scorpion", "melee", [], 10.0, 4.0), 25.0)])
	h.set_rows(rows, DATA.sum_hurt([DATA.hit_of(_hit("Scorpion", "melee", [], 10.0, 4.0), 25.0)]), 30.0)
	await get_tree().process_frame
	h.click("sort:win")
	assert_str(h.sort_by).is_equal("win")
	assert_str(str(h._table[0]["by"])).is_equal("Scorpion")
	# the same head again: back to the run's HP lost
	h.click("sort:win")
	assert_str(h.sort_by).is_equal("run")
	var got := [0]
	h.window_changed.connect(func(s: int) -> void: got[0] = s)
	h.click("win:60")
	assert_int(h.window_s).is_equal(60)
	assert_int(got[0]).is_equal(60)
	h.queue_free()


# ---------------------------------------------------------------- the charts' hover

func test_the_hovers_nearest_sample() -> void:
	var pts := PackedVector2Array([Vector2(0, 10), Vector2(50, 20), Vector2(100, 30)])
	assert_int(CHART.nearest_index(pts, 48.0)).is_equal(1)
	assert_int(CHART.nearest_index(pts, 76.0)).is_equal(2)
	assert_int(CHART.nearest_index(pts, -5.0)).is_equal(0)
	assert_int(CHART.nearest_index(PackedVector2Array(), 3.0)).is_equal(-1)
	var c = CHART.new()
	c.size = Vector2(400, 200)
	c.x0 = 0.0
	c.x1 = 100.0
	c.axes = [{"max": 40.0, "fmt": "%.0f", "unit": ""}, {"max": 0.0}, {"max": 0.0}]
	c.series = [{"pts": pts, "name": "HP", "color": Color.GREEN, "axis": 0}, {"pts": PackedVector2Array([Vector2(90, 5), Vector2(100, 6)]),
		"name": "Late", "color": Color.RED, "axis": 0}, {"pts": pts, "color": Color.BLUE, "axis": 0}]
	c.marks = [{"x": 50.0, "color": Color.RED, "name": "Fell to Goblin at 0:50"}]
	var r: Rect2 = c.plot_rect()
	var px := r.position.x + 0.5 * r.size.x
	var info: Dictionary = c.hover_info(Vector2(px, r.get_center().y))
	assert_float(float(info["t"])).is_equal_approx(50.0, 0.01)
	# the named line with its value; a line that starts later has none here; an unnamed one is left out
	assert_int((info["rows"] as Array).size()).is_equal(1)
	assert_str(str(info["rows"][0][0])).is_equal("HP  20")
	assert_str(str(info["marks"][0][0])).is_equal("Fell to Goblin at 0:50")
	# off the plot: nothing
	assert_bool(c.hover_info(Vector2(2, 2)).is_empty()).is_true()
	c.free()


func test_the_falls_are_named_marks_and_a_revive_marks_its_fall() -> void:
	var d = DATA.new()
	d.read_events([{"t": 90.0, "clock": 95.0, "kind": "death", "id": "goblin", "hit": "melee"},
		{"t": 90.0, "clock": 95.0, "kind": "revive", "id": "watch", "n": 1, "blast": false},
		{"t": 120.0, "clock": 125.0, "kind": "death", "id": "", "hit": "ranged"}])
	assert_int(d.watch_revives()).is_equal(1)
	assert_str(str(d.falls[0]["revived"])).is_equal("watch")
	var m: Array = PANEL.fall_marks(d.falls, null)
	assert_str(str(m[0]["name"])).is_equal("Fell to goblin (melee) at 1:35 · revived")
	assert_bool(m[0].has("tip")).is_true()
	assert_bool(m[1].has("tip")).is_false()
	# the down and revive lines change no build: never filled with a DPS change
	d.add_decision({"t": 90.0, "kind": "down"})
	d.fill_decisions(500.0)
	assert_float(float(d.decisions[0]["real_before"])).is_equal(-1.0)
	assert_str(str(PLAQUE.words_of({"started": true, "down_wait": true})["text"])).is_equal("Down!")
	# lane BOT's push out of a ring has its words, and changes no build either
	assert_str(str(PLAQUE.words_of({"started": true, "intent": "breakout"})["text"])).is_equal("Breaking out")
	d.add_decision({"t": 95.0, "kind": "breakout"})
	d.fill_decisions(500.0)
	assert_float(float(d.decisions[1]["real_before"])).is_equal(-1.0)


# ---------------------------------------------------------------- the revive

func _watch(death: String) -> Node:
	var w = WATCH.new()
	w.set("args", {"hero": "drifter", "seed": "11", "talents": "none", "analytics": "memory", "repo": "user://p90_no_such_dir",
		"speed": "1", "bot": "stub", "death": death})
	add_child(w)
	await get_tree().process_frame
	var s := SETUP.defaults_from_args({"hero": "drifter", "seed": "11", "talents": "none", "bot": "stub", "death": death})
	w.setup.visible = false
	w._begin_run(s, false)
	var waited := 0
	while not w._attached and waited < 120:
		await get_tree().process_frame
		waited += 1
	return w


func test_the_revive_keeps_the_run_going_as_often_as_wanted() -> void:
	var w = await _watch("ask")
	assert_bool(w._attached).is_true()
	assert_str(w.death).is_equal("ask")
	for i in range(20):
		await get_tree().process_frame
	var game: Node = w.game
	var p = game.player
	w.check_fell()
	assert_bool(bool(p.dead)).is_true()
	for i in range(3):
		await get_tree().process_frame
	# the run waits: paused, no Down!, not over, the box up
	assert_bool(w.down_wait).is_true()
	assert_bool(w.clock.paused).is_true()
	assert_bool(get_tree().paused).is_true()
	for i in range(100):
		await get_tree().process_frame
	assert_bool(game.revive_screen.visible).is_false()
	assert_bool(bool(game._ended)).is_false()
	assert_str(w.badge_words()).contains("R revive")
	assert_str(w.down_words()).contains("the Watch's check")
	# Space does not let the run go on while he lies there
	w.toggle_pause()
	assert_bool(w.clock.paused).is_true()
	# Revive: up at full health, blinking, the run going on
	assert_bool(w.watch_revive(false)).is_true()
	assert_bool(bool(p.dead)).is_false()
	assert_float(float(p.hp)).is_equal(float(p.max_hp))
	assert_float(float(p.invuln)).is_greater(1.5)
	assert_bool(w.down_wait).is_false()
	assert_int(w.revive_count).is_equal(1)
	var t0: float = w.play_t()
	for i in range(40):
		await get_tree().process_frame
	assert_bool(get_tree().paused).is_false()
	assert_float(w.play_t()).is_greater(t0 + 0.3)
	assert_bool(bool(game._ended)).is_false()
	assert_int(w.data.revives.size()).is_equal(1)
	assert_int(w.data.watch_revives()).is_equal(1)
	assert_str(str(w.data.falls[0].get("revived", ""))).is_equal("watch")
	# again, with the blast
	p.invuln = 0.0
	w.check_fell()
	for i in range(3):
		await get_tree().process_frame
	assert_bool(w.down_wait).is_true()
	assert_bool(w.watch_revive(true)).is_true()
	assert_int(w.revive_count).is_equal(2)
	var hdr: Dictionary = w.ra.header
	assert_int(int(hdr["watch_revives"])).is_equal(2)
	assert_int(int(hdr["watch"]["revives"])).is_equal(2)
	assert_int((hdr["watch"]["revive_t"] as Array).size()).is_equal(2)
	var kinds: Array = []
	for e in w.ra.events:
		if str(e["kind"]) in ["death", "revive"]:
			kinds.append(str(e["kind"]) + (":" + str(e.get("id", "")) if str(e["kind"]) == "revive" else ""))
	assert_array(kinds).is_equal(["death", "revive:watch", "death", "revive:watch"])
	# the decision log (and its CSV) has the falls and the revives with their times
	var csv: String = w.data.decisions_csv()
	assert_int(csv.count(",down,")).is_equal(2)
	assert_int(csv.count(",revive,")).is_equal(2)
	# a third fall, and End run: over as a death, the revives in the record
	for i in range(130):
		await get_tree().process_frame
	p.invuln = 0.0
	w.check_fell()
	for i in range(3):
		await get_tree().process_frame
	assert_bool(w.down_wait).is_true()
	w.end_down()
	var waited := 0
	while not w.ended and waited < 60:
		await get_tree().process_frame
		waited += 1
	assert_bool(w.ended).is_true()
	assert_str(str(w.end_info["result"])).is_equal("death")
	assert_str(w.end_words()).contains("Revived 2×")
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func test_auto_stands_him_up_by_itself() -> void:
	var w = await _watch("auto")
	for i in range(20):
		await get_tree().process_frame
	var p = w.game.player
	w.check_fell()
	var waited := 0
	while bool(p.dead) and waited < 120:
		await get_tree().process_frame
		waited += 1
	assert_bool(bool(p.dead)).is_false()
	assert_bool(w.down_wait).is_false()
	assert_int(w.revive_count).is_equal(1)
	assert_bool(w.game.revive_screen.visible).is_false()
	assert_bool(bool(w.game._ended)).is_false()
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func test_a_check_that_closes_itself_is_not_asked() -> void:
	var w = WATCH.new()
	w.death = "ask"
	w.autoquit = true
	assert_bool(w.watch_handles_death()).is_false()
	w.autoquit = false
	assert_bool(w.watch_handles_death()).is_true()
	w.death = "end"
	assert_bool(w.watch_handles_death()).is_false()
	w.free()
	assert_str(str(SETUP.defaults_from_args({})["death"])).is_equal("ask")
	assert_str(str(SETUP.DEATHS[0][0])).is_equal("ask")
