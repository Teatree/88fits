extends GdUnitTestSuite

## Pass 140, lane DIFF (Garry, 2026-11-10: "Try to achieve the enemy power increase without changing the quantity of them
## too much (as I like the amount right now). But more with ATK and HP"): the creature strength by stage of the progression
## plan v2 (docs/progression/progression_plan.html section 6) read from the map file. Each stage's HP and bite (its stage
## multiplier x the HP / ATK curve) at its edges near the plan's targets and rising inside the stage, every stage opening
## above the one before, Sundown's opening bite under the old flat 1.21, the opening scorpions softer, the Brander 65 s of
## full DPS, a row on a later stage's first second reading that stage's step (WaveTimeline.curve_t), and the crowd's
## numbers (counts, packs, Max alive, the cap and the boss fights) exactly as Garry left them before this pass
## (tests/fixtures/pass140_counts.json, taken from the file before the pass). Re-pin the targets when Garry retunes the
## curves in the Level Editor; the counts fixture only when he changes the rows.

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const COUNTS := "res://tests/fixtures/pass140_counts.json"
## [HP start, HP end, bite start, bite end] per stage (x the creature's base, before creature_hp_mult and a row's own mult)
const TARGET := [[1.00, 2.30, 0.95, 1.45], [4.50, 9.45, 0.79, 2.60], [9.30, 15.8, 0.98, 2.55], [17.0, 32.3, 1.21, 2.645]]


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## The map's timeline built from its JSON (the file Garry edits), not the imported .tres.
func _tl() -> WaveTimeline:
	return JsonContent.timeline_from_dict(_json(MAP_JSON)["timeline_data"])


func _hp(tl: WaveTimeline, k: int, t: float) -> float:
	return tl.stage_mult(k) * tl.hp_mult_at(tl.curve_t(t, k))


func _bite(tl: WaveTimeline, k: int, t: float) -> float:
	return tl.stage_mult(k) * tl.damage_mult_at(tl.curve_t(t, k))


func test_each_stage_meets_the_plan_at_its_edges() -> void:
	var tl := _tl()
	assert_int(tl.stage_count()).is_equal(4)
	for k in range(4):
		var a := tl.stage_start(k)
		var b := tl.stage_end(k)
		var want: Array = TARGET[k]
		var got := [_hp(tl, k, a), _hp(tl, k, b), _bite(tl, k, a), _bite(tl, k, b)]
		for j in range(4):
			assert_float(float(got[j])).override_failure_message("stage %d edge %d: x%.3f, the plan x%.3f" % [k, j, float(got[j]), float(want[j])]) \
				.is_equal_approx(float(want[j]), float(want[j]) * 0.03)


func test_hp_and_bite_rise_inside_every_stage() -> void:
	var tl := _tl()
	for k in range(4):
		var a := tl.stage_start(k)
		var b := tl.stage_end(k)
		var prev := _hp(tl, k, a)
		var t := a + 10.0
		while t <= b:
			var v := _hp(tl, k, t)
			assert_float(v).override_failure_message("stage %d HP falls at %.0f" % [k, t]).is_greater_equal(prev - 0.0001)
			prev = v
			t += 10.0
		assert_float(_hp(tl, k, b)).is_greater(_hp(tl, k, a) * 1.6)
		# the bite climbs to the stage's last stretch (the Blood Moon eases off in its last 135 s, Garry's shape, still
		# well above its opening)
		var top := a + (b - a) * 0.85
		prev = _bite(tl, k, a)
		t = a + 10.0
		while t <= top:
			var v := _bite(tl, k, t)
			assert_float(v).override_failure_message("stage %d bite falls at %.0f" % [k, t]).is_greater_equal(prev - 0.0001)
			prev = v
			t += 10.0
		assert_float(_bite(tl, k, b)).is_greater(_bite(tl, k, a) * 1.5)


func test_every_stage_opens_above_the_one_before() -> void:
	var tl := _tl()
	for k in range(1, 4):
		assert_float(_hp(tl, k, tl.stage_start(k))).is_greater(_hp(tl, k - 1, tl.stage_start(k - 1)) * 1.5)
		# and about where the stage before ended (the plan opens the Dust Bowl a hair under Nightfall's end)
		assert_float(_hp(tl, k, tl.stage_start(k))).is_greater(_hp(tl, k - 1, tl.stage_end(k - 1)) * 0.95)
	# the Dust Bowl's +20% and the Blood Moon's +30% at their start, over what the old curve gave them there
	assert_float(_hp(tl, 2, tl.stage_start(2))).is_greater(2.05 * pow(1.0 + 0.0977 * 1030.0 / 60.0, 1.35) * 1.15)
	assert_float(_hp(tl, 3, tl.stage_start(3))).is_greater(2.05 * pow(1.0 + 0.0977 * 1810.0 / 60.0, 1.35) * 1.25)


func test_sundown_opens_softer() -> void:
	var tl := _tl()
	# the bite under the old flat 1.21 for its first three minutes, x1.0 by 3:00, then up to the King
	for t in [0.0, 60.0, 120.0, 180.0]:
		assert_float(_bite(tl, 0, t)).is_less(1.21)
	assert_float(_bite(tl, 0, 0.0)).is_equal_approx(0.95, 0.01)
	assert_float(_bite(tl, 0, 180.0)).is_equal_approx(1.0, 0.01)
	# the King fights on Sundown's last step (the boss second reads the stage it closes)
	assert_float(tl.damage_mult_at(430.0)).is_equal_approx(tl.damage_mult_at(429.0), 0.005)
	# the opening scorpion horde x0.8 of its old 1.2
	var d := _json(MAP_JSON)
	var seen := 0
	for r in d["timeline_data"]["roster"]:
		if str(r.get("id", "")) in ["r3", "r5"]:
			assert_str(str(r["enemy"])).is_equal("lesser_scorpion")
			assert_float(float(r["stats"]["hp_mult"])).is_equal_approx(0.96, 0.0001)
			seen += 1
	assert_int(seen).is_equal(2)


func test_the_brander_takes_65_seconds() -> void:
	var tl := _tl()
	assert_str(tl.boss_hp_mode()).is_equal("seconds")
	assert_float(tl.boss_seconds("brander")).is_equal(65.0)
	assert_float(tl.boss_seconds("tumbleweed_king")).is_equal(40.0)
	assert_float(tl.boss_seconds("gila_grande")).is_equal(60.0)
	assert_float(tl.boss_seconds("black_sunday")).is_equal(70.0)


func test_a_row_on_a_stages_first_second_reads_that_stage() -> void:
	var tl := _tl()
	# a later stage's first second, fixed in that stage's own run: a hair inside its window
	assert_float(tl.curve_t(1030.0, 2)).is_equal_approx(1030.01, 0.0001)
	assert_float(tl.curve_t(1810.0, 3)).is_equal_approx(1810.01, 0.0001)
	# the boss second fixed in the run of the stage it closes (its boss fight's rows) keeps that stage's end
	assert_float(tl.curve_t(1030.0, 1)).is_equal(1030.0)
	assert_float(tl.curve_t(430.0, 0)).is_equal(430.0)
	# Sundown's first second and any other second are as they were
	assert_float(tl.curve_t(0.0, 0)).is_equal(0.0)
	assert_float(tl.curve_t(1040.0, 2)).is_equal(1040.0)
	# so the Dust Bowl's opening bunnies (da1 at 13:00 of the clock) bite at the Dust Bowl's opening, not at Nightfall's end
	assert_float(_bite(tl, 2, 1030.0)).is_less(1.1)
	assert_float(tl.stage_mult(1) * tl.damage_mult_at(tl.curve_t(1030.0, 1))).is_greater(2.4)


func test_the_crowd_is_as_garry_left_it() -> void:
	var was_file := _json(COUNTS)
	var td: Dictionary = _json(MAP_JSON)["timeline_data"]
	var keys := ["t", "until", "pace", "count", "pack", "every", "interval", "offset", "pattern", "respect_cap", "channel", "enemy"]
	var rows: Dictionary = was_file["rows"]
	var now := {}
	for r in td["roster"]:
		now[str(r["id"])] = r
	assert_int(now.size()).is_equal(rows.size())
	for id: String in rows:
		assert_bool(now.has(id)).override_failure_message("row %s is gone" % id).is_true()
		if not now.has(id):
			continue
		var was: Dictionary = rows[id]
		var r: Dictionary = now[id]
		for k: String in keys:
			assert_str(JSON.stringify(r.get(k))).override_failure_message("row %s %s" % [id, k]).is_equal(JSON.stringify(was.get(k)))
		var ma = (r.get("stats", {}) as Dictionary).get("max_alive")
		assert_str(JSON.stringify(ma)).override_failure_message("row %s max_alive" % id).is_equal(JSON.stringify(was.get("max_alive")))
	for k: String in ["cap_curve", "cap_max", "hard_cap", "hell_cap"]:
		assert_str(JSON.stringify(td.get(k))).override_failure_message(k).is_equal(JSON.stringify(was_file[k]))
	assert_str(JSON.stringify(td.get("floor_curve", []))).is_equal(JSON.stringify(was_file["floor_curve"]))
	for s in td["stage_list"]:
		var bf: Dictionary = was_file["boss_fights"].get(str(s["id"]), {})
		var f: Dictionary = s.get("boss_fight", {})
		assert_str(JSON.stringify(f.get("max_count"))).is_equal(JSON.stringify(bf.get("max_count")))
		var frows: Dictionary = bf.get("rows", {})
		for r in f.get("roster", []):
			var was: Dictionary = frows.get(str(r["id"]), {})
			for k: String in ["count", "pack", "every", "interval", "pace"]:
				assert_str(JSON.stringify(r.get(k))).override_failure_message("fight row %s %s" % [r["id"], k]).is_equal(JSON.stringify(was.get(k)))
