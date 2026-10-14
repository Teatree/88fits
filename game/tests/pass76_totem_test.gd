extends GdUnitTestSuite

## Pass 76, lane TOTEM (Garry: "also some of the upgrades are very powerful, can you reassess them please"): the Totem
## Pole's gifts follow one rule. A gift's average is about 0.4 of one level of the line item for its stat (a mul stat in
## multiplier space, since mul effects compound: 0.4 of a level of +m is (1 + m)^0.4 - 1; the Whale's max HP against the
## Giant's +8% of the base 100 HP), so a map's 10-12 gifts come to about one maxed line (4 levels) in all. A range is
## whole steps of what the screen shows (TextGen says a mul in whole percents), its smallest roll at least a third of its
## biggest (pass 73), and its span never a multiple of three steps, so the feathers (which third of the range a roll fell
## in) never hang on a rounding error and 1, 2 and 3 feathers all come up. The rule's table: tools/dl/p76/balancing_TOTEM.md.

const BOONS := preload("res://core/systems/TotemBoons.gd")

## The line item each gift's stat is measured against (the Reach is a passive item: no line raises the area).
const LINE_OF := {"move_speed": "stride", "max_hp": "vigour", "might": "brawn", "cooldown": "haste", "magnet": "lodestone",
	"regen": "mend", "xp_gain": "field_notes", "crit_chance": "deadeye", "damage_reduction": "tin_star", "luck": "clover",
	"area": "reach"}


func _pole() -> StructureDef:
	return Registry.structure("totem_pole")


## One level of the line item for `stat`: its first level's effect on that stat.
func _line_effect(stat: String) -> Effect:
	var p := Registry.passive(str(LINE_OF.get(stat, "")))
	if p == null:
		return null
	for e in p.effects_at_level(1):
		if e is Effect and (e as Effect).stat == stat:
			return e
	return null


## How many levels of its line one gift of `value` is.
func _levels(stat: String, op: String, value: float) -> float:
	var le := _line_effect(stat)
	if le == null or absf(le.value) < 0.000001:
		return -1.0
	if le.op == "mul" and op == "mul":
		return log(1.0 + value) / log(1.0 + le.value)
	if le.op == "mul" and op == "add":
		return value / (float(StatSheet.PLAYER_DEFAULTS.get(stat, 100.0)) * le.value)
	return value / le.value


## Every value a gift can roll: min to max in whole steps, snapped and clamped as TotemBoons.roll does.
func _values(e: Dictionary) -> Array:
	var lo := float(e["min"])
	var hi := float(e["max"])
	var step := float(e["step"])
	var n := int(round(absf(hi - lo) / step))
	var out: Array = []
	for k in range(n + 1):
		var v := snappedf(lerpf(lo, hi, float(k) / float(maxi(n, 1))), step)
		out.append(clampf(v, minf(lo, hi), maxf(lo, hi)))
	return out


func test_every_gift_is_about_four_tenths_of_a_level_of_its_line() -> void:
	var pool := BOONS.pool_of(_pole())
	assert_int(pool.size()).is_greater_equal(10)
	for e: Dictionary in pool:
		var stat := str(e["stat"])
		assert_bool(LINE_OF.has(stat)).override_failure_message("no line named for the gift of " + stat).is_true()
		assert_object(_line_effect(stat)).override_failure_message("%s has no %s" % [LINE_OF.get(stat), stat]).is_not_null()
		var avg := (float(e["min"]) + float(e["max"])) / 2.0
		var lv := _levels(stat, str(e["op"]), avg)
		assert_float(lv).override_failure_message("%s averages %.2f levels of %s" % [e["id"], lv, LINE_OF[stat]]).is_between(0.3, 0.55)
		# a mul gift and its line pull the same way (the Thunderbird's cooldown down with the Tower's)
		assert_bool(signf(float(e["min"])) == signf(_line_effect(stat).value)).override_failure_message(str(e["id"])).is_true()


func test_a_maps_gifts_come_to_about_one_maxed_line() -> void:
	# the average gift as the poles offer them (drawn by weight, three at a time), in levels of its line
	var d := _pole()
	var rng := RandomNumberGenerator.new()
	rng.seed = 76
	var total := 0.0
	var n := 0
	for k in range(3000):
		for b: Dictionary in BOONS.offer(d, rng):
			total += _levels(str(b["stat"]), str(b["op"]), float(b["value"]))
			n += 1
	var mean := total / float(n)
	assert_float(mean).is_between(0.33, 0.47)
	# ten to twelve poles a map: about four levels in all, one maxed line (it was about 7-8 before pass 76)
	var per_map := StructureManager.per_map_range(d)
	assert_float(mean * per_map.x).is_greater(3.0)
	assert_float(mean * per_map.y).is_less(5.8)


func test_every_roll_reads_as_the_amount_it_gives() -> void:
	for e: Dictionary in BOONS.pool_of(_pole()):
		for v: float in _values(e):
			var boon := {"stat": str(e["stat"]), "op": str(e["op"]), "value": v}
			if str(e["op"]) == "mul":
				# TextGen says a mul in whole percents: a roll is a whole percent, so the screen tells the truth
				assert_float(absf(v * 100.0 - round(v * 100.0))).override_failure_message("%s %f" % [e["id"], v]).is_less(0.000001)
			var words := BOONS.amount_text(boon)
			assert_str(words).is_not_empty()
			assert_bool(words.begins_with("+") or words.begins_with("−")).override_failure_message(words).is_true()


func test_every_gift_hangs_one_two_or_three_feathers_by_its_third() -> void:
	for e: Dictionary in BOONS.pool_of(_pole()):
		var vals := _values(e)
		var n := vals.size() - 1
		assert_int(n).override_failure_message("%s rolls one number" % e["id"]).is_greater_equal(2)
		# never a multiple of three steps: no roll sits on a third, where a rounding error would pick the feathers
		assert_int(n % 3).override_failure_message("%s spans %d steps" % [e["id"], n]).is_not_equal(0)
		var small := minf(absf(float(e["min"])), absf(float(e["max"])))
		var seen := {}
		for v: float in vals:
			var q := BOONS.quality(v, float(e["min"]), float(e["max"]))
			# the third of the range its size falls in, counted in whole steps from the smallest roll
			var k := int(round((absf(v) - small) / float(e["step"])))
			assert_int(q).override_failure_message("%s rolls %f" % [e["id"], v]).is_equal(mini(int(3.0 * k / float(n)) + 1, 3))
			seen[q] = true
		assert_bool(seen.has(1) and seen.has(2) and seen.has(3)).override_failure_message(str(e["id"])).is_true()
		# small but not nothing (pass 73): the smallest roll is at least a third of the biggest
		assert_float(absf(float(e["min"]))).is_greater_equal(absf(float(e["max"])) / 3.0 - 0.0001)


func test_the_weights_and_the_feathers_rule_are_kept() -> void:
	# pass 73's weights: the commonest stats three, the rarest one
	var w := {}
	for e: Dictionary in BOONS.pool_of(_pole()):
		w[str(e["id"])] = float(e["weight"])
	assert_float(float(w.get("wolf", 0.0))).is_greater(float(w.get("raven", 0.0)))
	assert_float(float(w.get("whale", 0.0))).is_greater(float(w.get("killer_whale", 0.0)))
	assert_float(float(w.get("bear", 0.0))).is_greater(float(w.get("serpent", 0.0)))
	# the feathers: the third of its range the amount fell in
	assert_int(BOONS.quality(0.01, 0.01, 0.03)).is_equal(1)
	assert_int(BOONS.quality(0.02, 0.01, 0.03)).is_equal(2)
	assert_int(BOONS.quality(0.03, 0.01, 0.03)).is_equal(3)
	assert_int(BOONS.quality(-0.04, -0.04, -0.02)).is_equal(3)
	# a damage reduction gift never brings the cap near: twelve of the best roll stay under half of it
	for e: Dictionary in BOONS.pool_of(_pole()):
		if str(e["stat"]) == "damage_reduction":
			assert_float(12.0 * maxf(absf(float(e["min"])), absf(float(e["max"])))).is_less(0.4)
