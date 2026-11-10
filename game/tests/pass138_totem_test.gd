extends GdUnitTestSuite

## Pass 138, lane TOTEM (Garry: "Let's make it so there are 5 rarities now (Common, Uncommon, Rare, Epic, Legendary) ...
## Legendary is a bit stronger than the strongest right now, Common is a bit weaker than the weakest right now ...
## offered stat increases are the same [rarity] more rarely (but it still happens sometimes); the more totems Player
## claims the better the rarity chances"; "remove the stars, center the text; border should now have the rarity
## indicator; remove the little dot on the left").

const BOONS := preload("res://core/systems/TotemBoons.gd")

## The pole's ranges before pass 138 (min, max), so the five tiers can be held against them.
const OLD := {"wolf": [0.01, 0.03], "whale": [2.0, 6.0], "bear": [0.02, 0.06], "thunderbird": [-0.04, -0.02],
	"seal": [0.1, 0.2], "salmon": [0.1, 0.3], "frog": [0.02, 0.04], "killer_whale": [0.02, 0.04],
	"bullhead": [0.01, 0.03], "raven": [0.02, 0.06], "serpent": [0.02, 0.04]}


func _pole() -> StructureDef:
	return Registry.structure("totem_pole")


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func test_every_gift_names_five_rising_amounts_in_its_json() -> void:
	var pool := BOONS.pool_of(_pole())
	assert_int(pool.size()).is_equal(11)
	for e: Dictionary in pool:
		var id := str(e["id"])
		# explicit in the JSON, by rarity name
		assert_bool(e.get("tiers") is Dictionary).override_failure_message(id).is_true()
		for name: String in BOONS.TIERS:
			assert_bool((e["tiers"] as Dictionary).has(name)).override_failure_message("%s has no %s" % [id, name]).is_true()
		var t := BOONS.tier_amounts(e)
		assert_int(t.size()).is_equal(5)
		for k in range(1, 5):
			# strictly rising in size, one sign (the Thunderbird's cooldown all negative)
			assert_float(absf(float(t[k]))).override_failure_message("%s tier %d" % [id, k]).is_greater(absf(float(t[k - 1])))
			assert_bool(signf(float(t[k])) == signf(float(t[0]))).is_true()
		# against the old range: Legendary > old max > old min > Common; Legendary a bit stronger (1.2..1.4 x the max)
		var lo := absf(float(OLD[id][0]))
		var hi := absf(float(OLD[id][1]))
		if lo > hi:
			var sw := lo
			lo = hi
			hi = sw
		assert_float(absf(float(t[4]))).override_failure_message(id).is_greater(hi)
		assert_float(absf(float(t[4])) / hi).override_failure_message(id).is_between(1.2, 1.4)
		assert_float(absf(float(t[0]))).override_failure_message(id).is_less(lo)
		# whole-number stats keep whole numbers
		if str(e["stat"]) == "max_hp":
			for v in t:
				assert_float(float(v)).is_equal(roundf(float(v)))


func test_an_old_entry_with_only_min_and_max_still_reads() -> void:
	var e := {"id": "x", "stat": "might", "op": "mul", "min": 0.02, "max": 0.06, "step": 0.01, "weight": 1}
	var t := BOONS.tier_amounts(e)
	assert_int(t.size()).is_equal(5)
	assert_float(float(t[1])).is_equal_approx(0.02, 0.0001)
	assert_float(float(t[2])).is_equal_approx(0.04, 0.0001)
	assert_float(float(t[3])).is_equal_approx(0.06, 0.0001)
	assert_float(float(t[0])).is_less(0.02)
	assert_float(float(t[4])).is_greater(0.06)
	# a list of five reads too
	assert_array(BOONS.tier_amounts({"tiers": [1, 2, 3, 4, 5]})).is_equal([1.0, 2.0, 3.0, 4.0, 5.0])


func test_a_roll_at_a_tier_gives_that_tiers_amount_and_says_its_rarity() -> void:
	var pool := BOONS.pool_of(_pole())
	var rng := RandomNumberGenerator.new()
	for e: Dictionary in pool:
		var t := BOONS.tier_amounts(e)
		for tier in range(1, 6):
			var b := BOONS.roll(e, rng, tier)
			assert_float(float(b["value"])).is_equal_approx(float(t[tier - 1]), 0.000001)
			assert_int(int(b["tier"])).is_equal(tier)
			assert_int(int(b["quality"])).is_equal(tier)
			assert_str(str(b["rarity"])).is_equal(BOONS.TIERS[tier - 1])
			assert_int(BOONS.tier_of(b)).is_equal(tier)
			assert_float(float(b["min"])).is_equal_approx(float(t[0]), 0.000001)
			assert_float(float(b["max"])).is_equal_approx(float(t[4]), 0.000001)
	assert_str(BOONS.rarity_name(1)).is_equal("Common")
	assert_str(BOONS.rarity_name(5)).is_equal("Legendary")


func test_a_half_percent_reads_as_one() -> void:
	var wolf := {"id": "wolf", "name": "Le-loo", "animal": "the Wolf", "stat": "move_speed", "op": "mul", "value": 0.005}
	assert_str(BOONS.amount_text(wolf)).is_equal("+0.5%")
	assert_str(BOONS.text(wolf)).is_equal("+0.5% " + TextGen.stat_name("move_speed"))
	var tb := {"stat": "cooldown", "op": "mul", "value": -0.015}
	assert_str(BOONS.amount_text(tb)).is_equal("−1.5%")
	# a whole percent reads as TextGen says it
	var bear := {"stat": "might", "op": "mul", "value": 0.04}
	assert_str(BOONS.amount_text(bear)).is_equal(TextGen.describe_effect(BOONS.effect_of(bear), false))
	# every tier of every gift reads as a signed amount, two tiers of one gift never read alike
	for e: Dictionary in BOONS.pool_of(_pole()):
		var seen := {}
		for tier in range(1, 6):
			var words := BOONS.amount_text(BOONS.roll(e, RandomNumberGenerator.new(), tier))
			assert_bool(words.begins_with("+") or words.begins_with("−")).override_failure_message(words).is_true()
			assert_bool(seen.has(words)).override_failure_message("%s: %s twice" % [e["id"], words]).is_false()
			seen[words] = true


## The tier mix of `n` offers at `claimed` gifts taken, with the shares of all-same and two-same offers.
func _measure(def: StructureDef, claimed: int, n: int, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cnt := [0, 0, 0, 0, 0]
	var all_same := 0
	var two_same := 0
	var gifts := 0
	for k in range(n):
		var tiers := {}
		var offer := BOONS.offer(def, rng, 0, claimed)
		for b: Dictionary in offer:
			cnt[int(b["tier"]) - 1] += 1
			tiers[int(b["tier"])] = true
			gifts += 1
		if tiers.size() == 1:
			all_same += 1
		elif tiers.size() == 2:
			two_same += 1
	var mean := 0.0
	for t in range(5):
		mean += float(t + 1) * cnt[t]
	return {"mix": cnt, "gifts": gifts, "all": float(all_same) / n, "two": float(two_same) / n, "mean": mean / gifts}


func test_the_odds_improve_with_every_gift_taken() -> void:
	var d := _pole()
	var first := _measure(d, 0, 3000, 1)
	var later := _measure(d, 5, 3000, 2)
	var last := _measure(d, 11, 3000, 3)
	assert_float(float(later["mean"])).is_greater(float(first["mean"]))
	assert_float(float(last["mean"])).is_greater(float(later["mean"]))
	# the first totem: no Legendary, Common the most common, an Epic now and then
	var m: Array = first["mix"]
	assert_int(int(m[4])).is_equal(0)
	assert_int(int(m[0])).is_greater(int(m[1]))
	assert_int(int(m[0])).is_greater(int(m[3]))
	assert_int(int(m[3])).is_greater(0)
	# late: Legendary is reachable and still the rarest (by weight in every row; as measured, below the middle three)
	var ml: Array = last["mix"]
	assert_int(int(ml[4])).is_greater(0)
	for t in range(1, 4):
		assert_int(int(ml[4])).is_less(int(ml[t]))
	for c in range(BOONS.rarity_weights(d).size()):
		var wr := BOONS.weights_for(BOONS.rarity_weights(d), c)
		for t in range(4):
			assert_float(float(wr[4])).override_failure_message("row %d" % c).is_less(float(wr[t]))
	# the table's rows each improve on the one before (the mean tier rises claim by claim, by the weights alone)
	var rows := BOONS.rarity_weights(d)
	var prev := -1.0
	for c in range(rows.size()):
		var w := BOONS.weights_for(rows, c)
		var tot := 0.0
		var sum := 0.0
		for t in range(5):
			tot += float(w[t])
			sum += float(t + 1) * float(w[t])
		assert_float(sum / tot).override_failure_message("row %d" % c).is_greater(prev)
		prev = sum / tot
	# past the table's end the last row holds
	assert_array(BOONS.weights_for(rows, 40)).is_equal(BOONS.weights_for(rows, rows.size() - 1))


func test_one_rarity_twice_in_an_offer_is_rarer_than_by_independent_rolls() -> void:
	var d := _pole()
	var indep: StructureDef = d.duplicate(true)
	var p: Dictionary = d.params.duplicate(true)
	var r: Dictionary = (p["rarity"] as Dictionary).duplicate(true)
	r["same_tier"] = 1.0
	p["rarity"] = r
	indep.params = p
	assert_float(BOONS.same_tier_of(d)).is_less(1.0)
	for c in [0, 5, 11]:
		var dep := _measure(d, c, 3000, 10 + c)
		var ind := _measure(indep, c, 3000, 10 + c)
		assert_float(float(dep["all"])).is_less(float(ind["all"]))
		assert_float(float(dep["all"]) + float(dep["two"])).is_less(float(ind["all"]) + float(ind["two"]))
	# but it still happens sometimes
	var many := _measure(d, 0, 6000, 99)
	assert_float(float(many["all"]) + float(many["two"])).is_greater(0.1)
	assert_float(float(many["all"])).is_greater(0.0)


func test_the_offer_is_the_same_for_the_same_seed_and_keeps_one_stat_once() -> void:
	var d := _pole()
	for c in [0, 3, 9]:
		var a := RandomNumberGenerator.new()
		a.seed = 4242 + c
		var b := RandomNumberGenerator.new()
		b.seed = 4242 + c
		for k in range(50):
			var oa := BOONS.offer(d, a, 0, c)
			var ob := BOONS.offer(d, b, 0, c)
			assert_int(oa.size()).is_equal(3)
			assert_str(str(oa)).is_equal(str(ob))
			var stats := {}
			for g: Dictionary in oa:
				assert_bool(stats.has(str(g["stat"]))).is_false()
				stats[str(g["stat"])] = true
	# two draws a gift: the stream after an offer is where six draws leave it
	var x := RandomNumberGenerator.new()
	x.seed = 7
	BOONS.offer(d, x, 0, 0)
	var y := RandomNumberGenerator.new()
	y.seed = 7
	for k in range(6):
		y.randf()
	assert_float(x.randf()).is_equal(y.randf())


func test_the_record_keeps_the_tier_as_quality() -> void:
	var d := _pole()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for k in range(400):
		for b: Dictionary in BOONS.offer(d, rng, 0, 11):
			assert_int(int(b["quality"])).is_between(1, 5)
			seen[int(b["quality"])] = true
	assert_int(seen.size()).is_equal(5)


func test_the_card_wears_its_rarity_on_the_border_without_stars_or_nail() -> void:
	var d := _pole()
	var pool := BOONS.pool_of(d)
	var ts := TotemScreen.new()
	add_child(ts)
	await _frames(1)
	var offer: Array = [BOONS.roll(pool[0], RandomNumberGenerator.new(), 1), BOONS.roll(pool[1], RandomNumberGenerator.new(), 4),
		BOONS.roll(pool[2], RandomNumberGenerator.new(), 5)]
	ts.open(offer, d, 1, 10)
	await get_tree().create_timer(0.7, true, false, true).timeout
	await _frames(2)
	var rows: Array = ts.planks()
	assert_int(rows.size()).is_equal(3)
	var want := [1, 4, 5]
	for k in range(3):
		var row: TotemScreen.GiftRow = rows[k]
		assert_int(row.feathers).is_equal(want[k])
		# no stars, no nail, no gauge
		assert_object(row.tag.find_child("Gauge", true, false)).is_null()
		assert_object(row.tag.find_child("Nail", true, false)).is_null()
		# the rim and the tab with the rarity's word, centred on the card's top edge
		assert_object(row.rarity).is_not_null()
		assert_str(row.rarity_word.text).is_equal(BOONS.rarity_name(want[k]).to_upper())
		var tab: Rect2 = row.rarity_tab.get_rect()
		assert_float(tab.get_center().x).is_equal_approx(row.tag.size.x * 0.5, 1.0)
		assert_float(tab.get_center().y).is_equal_approx(0.0, 1.0)
		# the text centred across the card
		var a: Rect2 = row.amount.get_rect()
		var s: Rect2 = row.stat.get_rect()
		var line_mid := (a.position.x + s.position.x + row.stat.text_width()) * 0.5
		assert_float(line_mid).is_equal_approx(row.tag.size.x * 0.5, 2.0)
		var sp: Rect2 = row.spirit.get_rect()
		assert_float(sp.position.x + row.spirit.text_width() * 0.5).is_equal_approx(row.tag.size.x * 0.5, 2.0)
		assert_float(a.position.x).is_greater(0.0)
		assert_float(s.position.x + row.stat.text_width()).is_less(row.tag.size.x)
		# Epic and Legendary glow
		assert_bool(row.has_meta("tag_glow")).is_equal(want[k] >= 4)
		# a finger on the tab is the gift's
		assert_bool(row._has_point(row.tag_at + Vector2(row.tag.size.x * 0.5, -TotemScreen.TAB_H * 0.4))).is_true()
	ts.queue_free()
