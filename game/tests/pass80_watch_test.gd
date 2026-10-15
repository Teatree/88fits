extends GdUnitTestSuite

## Pass 80, lane WATCH (Garry: "For the 'Watch' tool, proceed with implementation of it"): the pure parts of the Watch
## (game/tools/watch/): the speed steps and the engine's numbers for each (WatchClock: the clock slows up to 1x, more
## frames a second above it with the step unchanged, the composition with the game's own time scale, step one second,
## run to the next level-up, the drawing gate, the measured speed), the ring buffer, the charts' scaling and bucketing,
## the derived numbers (Danger, Keeping up), the real DPS change 30 s after a decision, the decision log as CSV, the
## board's talents from the command line and the Sim's average read from a result.json.

const CLOCK := preload("res://tools/watch/WatchClock.gd")
const DATA := preload("res://tools/watch/WatchData.gd")
const RING := preload("res://tools/watch/WatchRing.gd")
const WATCH := preload("res://tools/watch/Watch.gd")
const STRIP := preload("res://tools/watch/WatchStrip.gd")


# ---------------------------------------------------------------- the speeds

func test_speed_steps() -> void:
	assert_array(CLOCK.SPEEDS).is_equal([0.25, 0.5, 1.0, 2.0, 4.0, 8.0])
	assert_float(CLOCK.faster(1.0)).is_equal(2.0)
	assert_float(CLOCK.faster(8.0)).is_equal(8.0)
	assert_float(CLOCK.slower(1.0)).is_equal(0.5)
	assert_float(CLOCK.slower(0.25)).is_equal(0.25)
	assert_float(CLOCK.nearest(3.0)).is_equal(2.0)
	assert_float(CLOCK.nearest(5.0)).is_equal(4.0)
	assert_float(CLOCK.nearest(100.0)).is_equal(8.0)
	assert_str(CLOCK.label(0.25)).is_equal("0.25x")
	assert_str(CLOCK.label(0.5)).is_equal("0.5x")
	assert_str(CLOCK.label(8.0)).is_equal("8x")


func test_up_to_1x_the_clock_slows_above_it_more_frames() -> void:
	# up to 1x: the time scale is the speed and 60 frames a second; above it the step stays 1/60 s and the frames grow
	assert_float(CLOCK.nominal_scale(0.25)).is_equal(0.25)
	assert_float(CLOCK.nominal_scale(1.0)).is_equal(1.0)
	assert_float(CLOCK.nominal_scale(8.0)).is_equal(1.0)
	assert_int(CLOCK.frames_per_second(0.25)).is_equal(60)
	assert_int(CLOCK.frames_per_second(1.0)).is_equal(60)
	assert_int(CLOCK.frames_per_second(4.0)).is_equal(240)
	assert_int(CLOCK.frames_per_second(8.0)).is_equal(480)


func test_time_scale_composes_with_the_games_own() -> void:
	var c = CLOCK.new()
	c.set_speed(0.25)
	assert_float(c.compose(1.0)).is_equal_approx(0.25, 0.0001)
	# unchanged since the Watch wrote it
	assert_float(c.compose(0.25)).is_equal_approx(0.25, 0.0001)
	# the hit-stop's 0.08: the game's own share, times the Watch's
	assert_float(c.compose(0.08)).is_equal_approx(0.02, 0.0001)
	assert_float(c.game_scale).is_equal_approx(0.08, 0.0001)
	# the hit-stop's end (1.0) gives the clock back
	assert_float(c.compose(1.0)).is_equal_approx(0.25, 0.0001)
	# Last Stand's slow clock, then its restore of the clock it found (the Watch's 0.25): back to the Watch's alone
	assert_float(c.compose(0.3)).is_equal_approx(0.075, 0.0001)
	assert_float(c.compose(0.3)).is_equal_approx(0.075, 0.0001)
	assert_float(c.compose(0.25)).is_equal_approx(0.25, 0.0001)
	# above 1x the Watch asks for 1: only the game's own slow remains
	c.set_speed(4.0)
	assert_float(c.compose(0.25)).is_equal_approx(1.0, 0.0001)
	assert_float(c.compose(0.08)).is_equal_approx(0.08, 0.0001)


func test_step_one_second_and_next_level_up() -> void:
	var c = CLOCK.new()
	c.set_speed(4.0)
	c.toggle_pause()
	assert_bool(c.paused).is_true()
	# from a pause the second plays at 1x, then it pauses
	c.step(10.0)
	assert_bool(c.paused).is_false()
	assert_float(c.running_speed()).is_equal(1.0)
	assert_bool(c.reached_end(10.5, false)).is_false()
	assert_bool(c.reached_end(11.0, false)).is_true()
	assert_bool(c.paused).is_true()
	assert_str(c.mode).is_equal("")
	# while running it steps at the speed asked
	c.set_speed(2.0)
	c.step(20.0)
	assert_float(c.running_speed()).is_equal(2.0)
	# to the next level-up: the fastest until the cards are up (a mutation offer does not count: the Watch says)
	c.to_level(7)
	assert_float(c.running_speed()).is_equal(8.0)
	assert_bool(c.reached_end(30.0, false)).is_false()
	assert_bool(c.reached_end(31.0, true)).is_true()
	assert_bool(c.paused).is_true()
	# after it, the speed asked before
	c.toggle_pause()
	assert_float(c.running_speed()).is_equal(2.0)


func test_frame_pacing() -> void:
	var c = CLOCK.new()
	c.set_speed(4.0)
	# the first frame plays at once; the next waits for its 1/240 s
	assert_int(c.pace(1000000)).is_equal(0)
	assert_int(c.pace(1000000)).is_equal(4166)
	# a frame that came late waits less, then none while it is behind
	assert_int(c.pace(1010000)).is_equal(0)
	# at 1x a sixtieth of a second a frame
	c.set_speed(1.0)
	var t := 2000000
	assert_int(c.pace(t)).is_equal(0)
	assert_int(c.pace(t)).is_equal(16666)
	# paused: 60 frames a second too
	c.set_speed(8.0)
	c.toggle_pause()
	assert_int(c.pace(3000000)).is_equal(0)
	assert_int(c.pace(3000000)).is_equal(16666)
	# idle (no run up, or the run over): 60 a second whatever the speed
	c.toggle_pause()
	assert_int(c.pace(4000000, true)).is_equal(0)
	assert_int(c.pace(4000000, true)).is_equal(16666)
	# running again at 8x: the frame after that one waits its 1/480 s
	assert_int(c.pace(4033332)).is_equal(0)
	assert_int(c.pace(4033332)).is_equal(2083)


func test_drawing_gate_above_1x() -> void:
	var c = CLOCK.new()
	c.set_speed(1.0)
	assert_bool(c.draw_due(0)).is_true()
	assert_bool(c.draw_due(1000)).is_true()
	c.set_speed(2.0)
	assert_bool(c.draw_due(100000)).is_true()
	# 4 ms later (a frame at 120 a second): not drawn; a sixtieth of a second later: drawn
	assert_bool(c.draw_due(104166)).is_false()
	assert_bool(c.draw_due(110000)).is_false()
	assert_bool(c.draw_due(116700)).is_true()
	# from 4x on, 30 frames a second are drawn
	c.set_speed(8.0)
	assert_bool(c.draw_due(200000)).is_true()
	assert_bool(c.draw_due(216700)).is_false()
	assert_bool(c.draw_due(233400)).is_true()
	# paused: always drawn
	c.toggle_pause()
	assert_bool(c.draw_due(117000)).is_true()


func test_measured_speed() -> void:
	var c = CLOCK.new()
	c.set_speed(4.0)
	# 240 frames of 1/240 s wall each playing 1/60 s: 4x
	for i in range(240):
		c.measure(1.0 / 240.0, 1.0 / 60.0)
	assert_float(c.reached).is_equal_approx(4.0, 0.01)
	assert_bool(c.short()).is_false()
	# frames that played nothing (a screen up) are left out
	for i in range(100):
		c.measure(0.01, 0.0)
	assert_float(c.reached).is_equal_approx(4.0, 0.01)
	# slower frames: 2.5x is short of 4x (under 90 %)
	for i in range(400):
		c.measure(1.0 / 150.0, 1.0 / 60.0)
	assert_float(c.reached).is_equal_approx(2.5, 0.05)
	assert_bool(c.short()).is_true()
	# short: the drawing steps down to 30 frames a second, tried again at the full rate after 20 s of play
	assert_bool(c.low_draw).is_true()
	var n := 0
	while c.low_draw and n < 2000:
		c.measure(1.0 / 60.0, 1.0 / 60.0)
		n += 1
	assert_bool(c.low_draw).is_false()
	assert_int(n).is_between(900, 1300)
	c.low_draw = true
	c.reset_measure()
	assert_float(c.reached).is_equal(0.0)
	assert_bool(c.low_draw).is_false()
	# at 1x, short: one frame in each thirtieth of a second drawn
	c.set_speed(1.0)
	c.low_draw = true
	assert_bool(c.draw_due(500000)).is_true()
	assert_bool(c.draw_due(517000)).is_false()
	assert_bool(c.draw_due(534000)).is_true()


# ---------------------------------------------------------------- the ring buffer

func test_ring_buffer() -> void:
	var r = RING.new(3)
	assert_bool(r.is_empty()).is_true()
	assert_float(r.mean()).is_equal(0.0)
	r.push(1.0)
	r.push(2.0)
	assert_int(r.size()).is_equal(2)
	assert_float(r.sum()).is_equal(3.0)
	r.push(3.0)
	r.push(4.0)
	assert_int(r.size()).is_equal(3)
	assert_float(r.sum()).is_equal(9.0)
	assert_float(r.mean()).is_equal(3.0)
	assert_float(r.at(0)).is_equal(2.0)
	assert_float(r.at(2)).is_equal(4.0)
	assert_float(r.last()).is_equal(4.0)
	assert_float(r.at(5)).is_equal(0.0)
	assert_float(r.sum_newest(2)).is_equal(7.0)
	r.clear()
	assert_int(r.size()).is_equal(0)
	assert_float(r.sum()).is_equal(0.0)


# ---------------------------------------------------------------- the charts

func test_nice_max() -> void:
	assert_float(DATA.nice_max(0.0)).is_equal(1.0)
	assert_float(DATA.nice_max(-5.0)).is_equal(1.0)
	assert_float(DATA.nice_max(0.7)).is_equal_approx(0.8, 0.0001)
	assert_float(DATA.nice_max(1.0)).is_equal_approx(1.0, 0.0001)
	assert_float(DATA.nice_max(1.3)).is_equal_approx(1.6, 0.0001)
	assert_float(DATA.nice_max(2.2)).is_equal_approx(2.4, 0.0001)
	assert_float(DATA.nice_max(3.0)).is_equal_approx(3.2, 0.0001)
	assert_float(DATA.nice_max(7.0)).is_equal_approx(8.0, 0.0001)
	assert_float(DATA.nice_max(41.0)).is_equal_approx(60.0, 0.001)
	assert_float(DATA.nice_max(180.0)).is_equal_approx(200.0, 0.001)
	assert_float(DATA.nice_max(4321.0)).is_equal_approx(6000.0, 0.01)
	# every top's quarter is a round tick
	for m in DATA.NICE:
		var q := float(m) * 1000.0 / 4.0
		assert_float(q - roundf(q / 50.0) * 50.0).is_equal_approx(0.0, 0.001)


func test_bucket_keeps_the_window_and_averages_past_the_cap() -> void:
	var ts := PackedFloat32Array()
	var vs := PackedFloat32Array()
	for i in range(1, 601):
		ts.append(float(i))
		vs.append(float(i % 10))
	# the window 0..180 of a 600 s run: 180 points, none past it
	var pts: PackedVector2Array = DATA.bucket(ts, vs, 420.0, 600.0, 360)
	assert_int(pts.size()).is_equal(181)
	assert_float(pts[0].x).is_equal(420.0)
	# the whole run into 100 buckets of 6 s: each the mean of its times and values
	var all: PackedVector2Array = DATA.bucket(ts, vs, 0.0, 600.0, 100)
	assert_int(all.size()).is_equal(100)
	assert_float(all[0].x).is_equal_approx(3.5, 0.001)
	assert_float(all[0].y).is_equal_approx(3.5, 0.001)
	# NAN left out
	var ts2 := PackedFloat32Array([1.0, 2.0, 3.0])
	var vs2 := PackedFloat32Array([1.0, NAN, 3.0])
	assert_int(DATA.bucket(ts2, vs2, 0.0, 10.0, 360).size()).is_equal(2)
	assert_int(DATA.bucket(PackedFloat32Array(), PackedFloat32Array(), 0.0, 10.0, 10).size()).is_equal(0)


func test_mmss() -> void:
	assert_str(DATA.mmss(0.0)).is_equal("0:00")
	assert_str(DATA.mmss(65.4)).is_equal("1:05")
	assert_str(DATA.mmss(3725.0)).is_equal("1:02:05")


# ---------------------------------------------------------------- the rows, Danger, Keeping up

func _rows(n: int, dmg_per_s: float, took_per_s: float = 0.0) -> Array:
	var rows: Array = []
	for i in range(1, n + 1):
		var r := {"t": float(i), "clock": float(i), "stage": 1, "level": 1 + int(i / 30.0), "hp": 100.0, "hp_max": 200.0,
			"xp": 5.0, "xp_next": 20.0, "est_total": 50.0, "press_hp": 1000.0, "near3": 1, "near6": 4, "alive": 30}
		if dmg_per_s > 0.0:
			r["dmg"] = {"revolver": dmg_per_s * 0.75, "tommy_gun": dmg_per_s * 0.25}
		if took_per_s > 0.0:
			r["took"] = {"goblin": took_per_s}
			r["hits_by"] = {"goblin": 2}
		rows.append(r)
	return rows


func test_rows_read_once_with_the_derived_numbers() -> void:
	var d = DATA.new()
	var rows := _rows(10, 40.0, 4.0)
	assert_int(d.read_rows(rows)).is_equal(10)
	assert_int(d.read_rows(rows)).is_equal(0)
	assert_int(d.size()).is_equal(10)
	assert_float(d.dps[9]).is_equal_approx(40.0, 0.001)
	assert_float(d.dps5[9]).is_equal_approx(40.0, 0.001)
	# Danger: 4 HP of 200 a second = 2 % (the Sim tab's)
	assert_float(d.danger[9]).is_equal_approx(2.0, 0.001)
	# Keeping up: 1000 HP of crowd at 40 DPS = 25 s
	assert_float(d.keep_up[9]).is_equal_approx(25.0, 0.001)
	assert_float(d.xp_frac[0]).is_equal_approx(0.25, 0.001)
	assert_float(float(d.dmg_total["revolver"])).is_equal_approx(300.0, 0.01)
	# the share: three quarters the revolver's
	var sh: Array = d.shares(0, 9, 6)
	assert_str(str(sh[0][0])).is_equal("revolver")
	assert_float(float(sh[0][1])).is_equal_approx(0.75, 0.001)
	# a second without damage: no ratio
	assert_float(DATA.keep_up_s(1000.0, 0.0, 0.5)).is_equal(-1.0)
	# the boss's HP is left out of the crowd's
	assert_float(DATA.keep_up_s(1000.0, 600.0, 40.0)).is_equal_approx(10.0, 0.001)
	assert_float(DATA.tail_mean(PackedFloat32Array([1.0, 2.0, 3.0, 4.0]), 2)).is_equal_approx(3.5, 0.001)


func test_threat_of_the_last_ten_seconds() -> void:
	var d = DATA.new()
	var rows := _rows(30, 10.0, 0.0)
	for i in range(25, 30):
		rows[i]["took"] = {"goblin": 3.0, "bull_beetle": 10.0}
		rows[i]["hits_by"] = {"goblin": 1, "bull_beetle": 1}
	rows[5]["took"] = {"scorpion": 99.0}
	d.read_rows(rows)
	var th: Array = d.threat(10)
	assert_int(th.size()).is_equal(2)
	assert_str(str(th[0]["id"])).is_equal("bull_beetle")
	assert_float(float(th[0]["lost"])).is_equal_approx(50.0, 0.001)
	assert_int(int(th[1]["hits"])).is_equal(5)


func test_events_bring_arrivals_and_falls() -> void:
	var d = DATA.new()
	var ev: Array = [{"t": 1.0, "clock": 1.0, "kind": "weapon", "id": "revolver", "level": 1, "via": "starter"},
		{"t": 30.0, "clock": 30.0, "kind": "passive", "id": "tower", "level": 1, "line": true},
		{"t": 31.0, "clock": 31.0, "kind": "level", "level": 3},
		{"t": 90.0, "clock": 90.0, "kind": "death", "id": "goblin", "hit": "melee"}]
	var hits: Array = [{"by": "Goblin", "dealt": 5.0}, {"by": "Goblin", "dealt": 7.0, "fatal": true}]
	assert_int(d.read_events(ev, hits)).is_equal(4)
	assert_int(d.arrivals.size()).is_equal(2)
	assert_int(STRIP.lane_of(d.arrivals[0])).is_equal(0)
	assert_int(STRIP.lane_of(d.arrivals[1])).is_equal(2)
	assert_int(d.falls.size()).is_equal(1)
	assert_str(str(d.falls[0]["killer"])).is_equal("goblin")
	# the last hits newest first
	assert_float(float(d.falls[0]["last"][0]["dealt"])).is_equal(7.0)
	assert_int(d.read_events(ev, hits)).is_equal(0)


# ---------------------------------------------------------------- the real DPS change 30 s after a decision

func test_real_dps_change_fills_after_thirty_seconds() -> void:
	var d = DATA.new()
	# 60 s at 100 DPS, then 60 s at 150
	var rows := _rows(60, 100.0)
	var later := _rows(60, 150.0)
	for r in later:
		r["t"] = float(r["t"]) + 60.0
	d.read_rows(rows)
	d.add_decision({"t": 60.0, "clock": 60.0, "kind": "card", "taken": "tommy_gun", "offered": [], "reason": "x", "level": 3})
	# 30 s have not passed: nothing filled
	assert_int(d.fill_decisions(60.0)).is_equal(0)
	assert_bool(bool(d.decisions[0]["filled"])).is_false()
	d.read_rows(rows + later)
	assert_int(d.fill_decisions(90.0)).is_equal(1)
	var e: Dictionary = d.decisions[0]
	assert_float(float(e["real_before"])).is_equal_approx(100.0, 0.001)
	assert_float(float(e["real_after"])).is_equal_approx(150.0, 0.001)
	assert_float(float(e["real_change"])).is_equal_approx(50.0, 0.001)
	# filled once
	assert_int(d.fill_decisions(200.0)).is_equal(0)
	# the run's end fills what there is
	d.add_decision({"t": 110.0, "kind": "card", "taken": "x"})
	assert_int(d.fill_decisions(115.0, true)).is_equal(1)
	assert_float(float(d.decisions[1]["real_after"])).is_equal_approx(150.0, 0.001)
	# a walking goal changes no build: no DPS change of its own
	d.add_decision({"t": 20.0, "kind": "goal", "taken": "cell:3"})
	d.fill_decisions(200.0)
	assert_float(float(d.decisions[2]["real_after"])).is_equal(-1.0)
	assert_bool(bool(d.decisions[2]["filled"])).is_true()
	# nothing before it: no percentage
	assert_bool(is_nan(DATA.change_pct(0.0, 50.0))).is_true()
	assert_bool(is_nan(DATA.change_pct(-1.0, 50.0))).is_true()
	assert_float(DATA.change_pct(100.0, 80.0)).is_equal_approx(-20.0, 0.001)
	assert_float(DATA.mean_between(PackedFloat32Array([1.0, 2.0, 3.0]), PackedFloat32Array([10.0, 20.0, 30.0]), 1.0, 3.0)).is_equal_approx(25.0, 0.001)
	assert_float(DATA.mean_between(PackedFloat32Array([1.0]), PackedFloat32Array([10.0]), 5.0, 9.0)).is_equal(-1.0)


# ---------------------------------------------------------------- the CSV

func test_decision_log_csv() -> void:
	assert_str(DATA.csv_field("plain")).is_equal("plain")
	assert_str(DATA.csv_field("a, b")).is_equal("\"a, b\"")
	assert_str(DATA.csv_field("say \"hi\"")).is_equal("\"say \"\"hi\"\"\"")
	assert_str(DATA.csv_field("two\nlines")).is_equal("\"two\nlines\"")
	var d = DATA.new()
	d.add_decision({"t": 61.0, "clock": 61.0, "kind": "card", "level": 4, "taken": "tommy_gun",
		"reason": "+18% DPS: Tommy Gun to Lv 4, the favourite",
		"offered": [{"id": "tommy_gun", "score": 1.32}, {"id": "snake_oil", "score": 0.9}], "dps_before": 120.0})
	var csv: String = d.decisions_csv({"tommy_gun": "Tommy Gun"})
	var lines := csv.strip_edges().split("\n")
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[0]).is_equal(",".join(PackedStringArray(DATA.CSV_COLUMNS)))
	assert_str(lines[1]).is_equal("61.0,61.0,4,card,tommy_gun,Tommy Gun,\"+18% DPS: Tommy Gun to Lv 4, the favourite\",tommy_gun=1.3 | snake_oil=0.9,120.0,,,")


# ---------------------------------------------------------------- the command line

func test_talents_from_the_command_line() -> void:
	var known := ["grit", "drive", "study"]
	var t: Dictionary = WATCH.talents_from("grit:AAB,drive:A", known)
	assert_array(t["grit"]["picks"]).is_equal([0, 0, 1])
	assert_int(int(t["grit"]["rank"])).is_equal(3)
	assert_int(int(t["grit"]["form"])).is_equal(1)
	assert_int(int(t["drive"]["rank"])).is_equal(1)
	assert_bool(WATCH.talents_from("none", known).is_empty()).is_true()
	assert_bool(WATCH.talents_from("", known).is_empty()).is_true()
	assert_bool(WATCH.talents_from("nope:A", known).has("error")).is_true()
	assert_bool(WATCH.talents_from("grit:AAAAAAA", known).has("error")).is_true()
	assert_bool(WATCH.talents_from("grit:AXB", known).has("error")).is_true()
	assert_that(WATCH.typed_value("0.6")).is_equal(0.6)
	assert_that(WATCH.typed_value("3")).is_equal(3)
	assert_that(WATCH.typed_value("off")).is_equal(false)
	assert_that(WATCH.typed_value("greedy")).is_equal("greedy")


func test_the_sims_average_from_a_result() -> void:
	var doc := {"t": [0, 1, 2], "series": {"dps": {"mean": [0.0, 10.0, null]}, "hp": {"mean": [100, 90, 80]},
		"level": {"median": [1, 1, 2]}}, "summary": {"ok": 10}}
	var r: Dictionary = WATCH.ref_from(doc)
	assert_int((r["t"] as PackedFloat32Array).size()).is_equal(3)
	assert_float((r["dps"] as PackedFloat32Array)[1]).is_equal(10.0)
	assert_bool(is_nan((r["dps"] as PackedFloat32Array)[2])).is_true()
	assert_float((r["hp"] as PackedFloat32Array)[2]).is_equal(80.0)
	# a series without a mean is left out
	assert_bool(r.has("level")).is_false()
	assert_int(int(r["players"])).is_equal(10)
	assert_bool(WATCH.ref_from({"nothing": 1}).is_empty()).is_true()
	assert_bool(WATCH.ref_from({"t": [0], "series": {}}).is_empty()).is_true()
