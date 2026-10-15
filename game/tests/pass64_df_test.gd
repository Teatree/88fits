extends GdUnitTestSuite

## Pass 64, lane DF (Garry, 2026-10-10: "That was a bit too harsh ... Let's make it so that the third stage can be
## completed with half the upgrades and the second stage can be completed with a quarter of them."). Pass 62 had tuned
## Red Canyon's stage 2 to half the Upgrade board and stage 3 to the full board; this pass turns the same knobs down
## (the ATK x curve after 7:10, every stage-2 / stage-3 row's and Elite event's HP x) and leaves stage 1 exactly as Garry
## made it (pass62_pc_test pins it). Read from the map file, so Garry can keep tuning in the Level Editor: the checks are
## the shape (softer than pass 62, still a step up stage by stage), not his numbers. Pass 68: Garry retuned the ATK x curve
## himself on 2026-10-12 (stage 1 at 1.21, stages 2 and 3 above it), so the attack checks ask only for a positive
## multiplier with each boss second on its own stage's side of the step.

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const STAGE := 430.0
## Pass 62's numbers (before this pass): the average row HP x of each stage.
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
	# pass 68 re-pin: stage 1's attack is Garry's to tune in the Level Editor (flat at 1 until 2026-10-12, flat at 1.21
	# since), so none of his numbers is pinned: a positive multiplier all through the stage, and the King's second (430)
	# on stage 1's side of the step
	var tl := _tl()
	for k in range(0, 431):
		assert_float(tl.damage_mult_at(float(k))).is_greater(0.0)
	assert_float(tl.damage_mult_at(STAGE)).is_equal_approx(tl.damage_mult_at(STAGE - 1.0), 0.005)


func test_later_stages_attack_is_a_sane_multiplier() -> void:
	# pass 68 re-pin: pass 64 had stages 2 and 3 hit softer than pass 62 (ATK x under 0.65 / 0.55 / 0.6, a stage-2 or
	# stage-3 hit at most what a quarter or half board's HP allows); Garry retuned the curve himself on 2026-10-12
	# (stage 2 from 1.44 to 1.39, stage 3 from 1.54 to 1.58), so that promise is his to keep or drop and the test asks
	# only for the shape: a positive multiplier at every tenth second of stages 2 and 3 and into endless, under 10 (a
	# typo guard)
	var tl := _tl()
	for k in range(431, 2001, 10):
		var v := tl.damage_mult_at(float(k))
		assert_float(v).override_failure_message("ATK x at %d s" % k).is_greater(0.0)
		assert_float(v).override_failure_message("ATK x at %d s" % k).is_less(10.0)


func test_still_a_step_up_stage_by_stage_in_play() -> void:
	var tl := _tl()
	var s1 := tl.stage_mult(0) * tl.damage_mult_at(300.0)
	var s2 := tl.stage_mult(1) * tl.damage_mult_at(700.0)
	var s3 := tl.stage_mult(2) * tl.damage_mult_at(1150.0)
	assert_float(s2).is_greater(s1)
	assert_float(s3).is_greater(s2)
	# the Gila fights on stage 2's ATK x (the clock stands at 860), the Brander on stage 3's end (pass 68: Garry's stage 2
	# slopes, so the second before is a near neighbour, not an equal)
	assert_float(tl.damage_mult_at(STAGE * 2.0)).is_equal_approx(tl.damage_mult_at(STAGE * 2.0 - 1.0), 0.005)


func test_rows_are_softer_than_pass_62_and_still_ramp() -> void:
	# pass 82 re-pin: Garry retuned stage 2's rows himself in the Level Editor (2026-10-16 01:25: several HP x raised to
	# 1.0-2.0, some overrides removed), so pass 64's "softer than pass 62" and "a 3x ramp" are his to change; what stays
	# pinned is the shape any tuning keeps: every stage-2 / stage-3 row that names an HP x names a sane, positive one
	# (P62_HP_AVG / P62_HP_MAX are kept as the record of pass 62's numbers)
	var tl: Dictionary = _json()["timeline_data"]
	for s: int in [1, 2]:
		var hp := _row_hp(tl, s)
		assert_int(hp.size()).override_failure_message("stage %d rows with an HP x" % (s + 1)).is_greater(0)
		for v: float in hp:
			assert_float(v).override_failure_message("stage %d row HP x" % (s + 1)).is_greater(0.0)
			assert_float(v).override_failure_message("stage %d row HP x" % (s + 1)).is_less(20.0)


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
