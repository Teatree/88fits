extends GdUnitTestSuite

## Pass 64, lane DF (Garry, 2026-10-10: "That was a bit too harsh ... Let's make it so that the third stage can be
## completed with half the upgrades and the second stage can be completed with a quarter of them."). Pass 62 had tuned
## Red Canyon's stage 2 to half the Upgrade board and stage 3 to the full board; this pass turns the same knobs down
## (the ATK x curve after 7:10, every stage-2 / stage-3 row's and Elite event's HP x) and leaves stage 1 exactly as Garry
## made it (pass62_pc_test pins it). Read from the map file, so Garry can keep tuning in the Level Editor: the checks are
## the shape (softer than pass 62, still a step up stage by stage), not his numbers.

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const STAGE := 430.0
## Pass 62's numbers (before this pass): the ATK x points after 7:10 and the average row HP x of each stage.
const P62_DMG := [[431.0, 0.65], [860.0, 0.65], [861.0, 0.55], [1290.0, 0.6]]
const P62_HP_AVG := [1.1653, 1.2862]
const P62_HP_MAX := 2.03


func _json() -> Dictionary:
	var f := FileAccess.open(MAP_JSON, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _tl() -> WaveTimeline:
	return Registry.map("red_canyon").timeline


func _row_hp(tl: Dictionary, s: int) -> Array:
	var a := STAGE * s
	var b := STAGE * (s + 1) if s < 2 else INF
	var out: Array = []
	for r in tl["roster"]:
		var t := float(r.get("t", 0.0))
		var st = r.get("stats", {})
		if t > a and t < b and st is Dictionary and (st as Dictionary).has("hp_mult"):
			out.append(float(st["hp_mult"]))
	return out


func test_stage_one_attack_is_untouched() -> void:
	var tl := _tl()
	for k in range(0, 431):
		assert_float(tl.damage_mult_at(float(k))).is_equal_approx(1.0, 0.000001)


func test_later_stages_hit_softer_than_pass_62() -> void:
	var tl := _tl()
	for p in P62_DMG:
		var t := float(p[0])
		assert_float(tl.damage_mult_at(t)).override_failure_message("ATK x at %d s" % int(t)).is_less(float(p[1]))
	# the big-hit rule: a stage-2 hit at most what a quarter board's HP allows (x 1.15 / 1.3 of pass 62's), a stage-3 hit
	# at most what half the board allows (x 1.3 / 1.6)
	assert_float(tl.damage_mult_at(700.0)).is_less_equal(0.65 * 1.15 / 1.3 + 0.001)
	assert_float(tl.damage_mult_at(1150.0)).is_less_equal(0.5837 * 1.3 / 1.6 + 0.001)


func test_still_a_step_up_stage_by_stage_in_play() -> void:
	var tl := _tl()
	var s1 := tl.stage_mult(0) * tl.damage_mult_at(300.0)
	var s2 := tl.stage_mult(1) * tl.damage_mult_at(700.0)
	var s3 := tl.stage_mult(2) * tl.damage_mult_at(1150.0)
	assert_float(s2).is_greater(s1)
	assert_float(s3).is_greater(s2)
	# the Gila fights on stage 2's ATK x (the clock stands at 860), the Brander on stage 3's end
	assert_float(tl.damage_mult_at(STAGE * 2.0)).is_equal_approx(tl.damage_mult_at(STAGE * 2.0 - 1.0), 0.000001)


func test_rows_are_softer_than_pass_62_and_still_ramp() -> void:
	var tl: Dictionary = _json()["timeline_data"]
	for s: int in [1, 2]:
		var hp := _row_hp(tl, s)
		assert_int(hp.size()).is_greater(10)
		var sum := 0.0
		var most := 0.0
		for v: float in hp:
			sum += v
			most = maxf(most, v)
		assert_float(sum / hp.size()).override_failure_message("stage %d average HP x" % (s + 1)).is_less(float(P62_HP_AVG[s - 1]))
		assert_float(most).is_less(P62_HP_MAX)
		# the ramp: a stage's first rows start softer than its last ones
		var early := INF
		var late := 0.0
		for r in tl["roster"]:
			var t := float(r.get("t", 0.0))
			var st = r.get("stats", {})
			if not (st is Dictionary and (st as Dictionary).has("hp_mult")):
				continue
			if t > STAGE * s and t < STAGE * s + 60.0:
				early = minf(early, float(st["hp_mult"]))
			if t > STAGE * s + 280.0 and t < STAGE * (s + 1) + 1.0:
				late = maxf(late, float(st["hp_mult"]))
		assert_float(late).is_greater(early * 3.0)


func test_the_elite_events_are_softer_than_pass_62() -> void:
	var tl: Dictionary = _json()["timeline_data"]
	var want := {645: 1.3, 1075: 1.9}
	for e in tl["events"]:
		var t := int(float(e.get("t", 0.0)))
		if str(e.get("type", "")) == "elite_boss" and want.has(t):
			var st: Dictionary = e.get("stats", {})
			assert_float(float(st.get("hp_mult", 1.0))).is_less(float(want[t]))
			assert_float(float(st.get("hp_mult", 1.0))).is_greater(0.5)


func test_the_probe_plays_a_quarter_board() -> void:
	var probe = load("res://tools/difficulty_probe.gd")
	var total := 0
	for k in range(8):
		total += int(probe.rank_for(1.5, k))
	assert_int(total).is_equal(12)
	assert_int(int(probe.rank_for(1.5, 0))).is_equal(2)
	assert_int(int(probe.rank_for(1.5, 1))).is_equal(1)
	assert_int(int(probe.rank_for(3.0, 5))).is_equal(3)
	assert_int(int(probe.rank_for(0.0, 0))).is_equal(0)
	assert_int(int(probe.rank_for(6.0, 7))).is_equal(6)
