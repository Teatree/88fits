## Pass 109 (Garry's requests of 2026-10-27):
##  1. The HUD's kill counter under the clock (WKillCount): a jawless skull and the run's kills (Run.kills, the Results'
##     number), a ding on every kill that grows with the kill rate.
##  2. The first-run Dynamite offer (FtueDynamite): the first card screen of level 4 or later holds the Dynamite Stick
##     beside the two lowest-rarity cards, every run until the Dynamite is picked once (the save's once-flag).
extends GdUnitTestSuite


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.arena = false
	Run.banished.clear()
	Run.kills = 0
	Run.end()


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))
	Run.level = FtueDynamite.AT_LEVEL


func _rank(c: Dictionary) -> int:
	return int(FtueDynamite.RARITY_RANK.get((c["def"] as ContentDef).rarity, 2))


# ---------------------------------------------------------------- 2. the first-run Dynamite offer

func test_dynamite_is_the_dynamite_stick() -> void:
	var def: WeaponDef = Registry.weapon(FtueDynamite.WEAPON_ID)
	assert_object(def).is_not_null()
	assert_str(def.display_name).is_equal("Dynamite Stick")


func test_forced_at_level_four_with_the_two_cheapest() -> void:
	_start()
	assert_bool(FtueDynamite.due(3)).is_false()
	assert_bool(FtueDynamite.due(4)).is_true()
	for k in 20:
		Run.ftue_dynamite_shown = false
		var eligible: Array = CardPool.candidates().filter(func(c: Dictionary) -> bool:
			return str(c["id"]) != FtueDynamite.WEAPON_ID and not (str(c["type"]) == "weapon" and bool(c["is_new"])) and FtueDynamite._is_cheap(c))
		var offer := FtueDynamite.offer(3)
		assert_int(offer.size()).is_equal(3)
		var dyn: Array = offer.filter(func(c: Dictionary) -> bool: return str(c["id"]) == FtueDynamite.WEAPON_ID)
		assert_int(dyn.size()).is_equal(1)
		assert_str(str(dyn[0]["type"])).is_equal("weapon")
		assert_bool(bool(dyn[0]["is_new"])).is_true()
		assert_bool(bool(dyn[0].get("ftue", false))).is_true()
		var others: Array = offer.filter(func(c: Dictionary) -> bool: return str(c["id"]) != FtueDynamite.WEAPON_ID)
		assert_int(others.size()).is_equal(2)
		var worst_taken := 0
		for c: Dictionary in others:
			# never a second new weapon, a perk, the favourite or an evolution
			assert_bool(str(c["type"]) == "weapon" and bool(c["is_new"])).is_false()
			assert_str(str(c["type"])).is_not_equal("perk")
			assert_bool(bool(c.get("favourite", false)) or bool(c.get("evolve", false))).is_false()
			assert_bool(eligible.any(func(e: Dictionary) -> bool: return str(e["id"]) == str(c["id"]))).is_true()
			worst_taken = maxi(worst_taken, _rank(c))
		# nothing left out is cheaper than what was taken
		for e: Dictionary in eligible:
			if not others.any(func(c: Dictionary) -> bool: return str(c["id"]) == str(e["id"])):
				assert_int(_rank(e)).is_greater_equal(worst_taken)
	# once a run: the screen after it draws normally
	assert_bool(Run.ftue_dynamite_shown).is_true()
	assert_bool(FtueDynamite.due(5)).is_false()


func test_lowest_rarity_first_from_a_made_list() -> void:
	_start()
	var mk := func(id: String, rarity: String) -> Dictionary:
		var d := PassiveDef.new()
		d.id = id
		d.rarity = rarity
		d.max_level = 5
		return {"type": "passive", "id": id, "def": d, "level_from": 0, "level_to": 1, "is_new": true, "weight": 1.0}
	var cands: Array = [mk.call("e", "epic"), mk.call("c1", "common"), mk.call("r", "rare"), mk.call("u", "uncommon"), mk.call("c2", "common")]
	for k in 10:
		var two := FtueDynamite.worst_cards(cands, 2)
		var ids: Array = two.map(func(c: Dictionary) -> String: return str(c["id"]))
		ids.sort()
		assert_array(ids).is_equal(["c1", "c2"])
	var three := FtueDynamite.worst_cards(cands, 3)
	assert_str(str(three[2]["id"])).is_equal("u")


func test_not_forced_once_taken_and_taken_on_pick() -> void:
	_start()
	assert_bool(FtueDynamite.taken()).is_false()
	var offer := FtueDynamite.offer(3)
	var dyn: Dictionary = offer.filter(func(c: Dictionary) -> bool: return str(c["id"]) == FtueDynamite.WEAPON_ID)[0]
	# a skip or another card leaves it due
	FtueDynamite.note_pick({"skipped": true})
	var other: Dictionary = offer.filter(func(c: Dictionary) -> bool: return str(c["id"]) != FtueDynamite.WEAPON_ID)[0]
	FtueDynamite.note_pick(other)
	assert_bool(FtueDynamite.taken()).is_false()
	# a new run offers it again
	_start()
	assert_bool(FtueDynamite.due(4)).is_true()
	# the pick ends it for good
	FtueDynamite.note_pick(dyn)
	assert_bool(FtueDynamite.taken()).is_true()
	assert_bool(Save.once(FtueDynamite.ONCE_KEY)).is_true()
	assert_bool(FtueDynamite.due(4)).is_false()
	_start()
	assert_bool(FtueDynamite.due(6)).is_false()
	# the developer menu's reset brings it back
	FtueDynamite.reset()
	assert_bool(FtueDynamite.due(4)).is_true()


func test_not_forced_when_held_or_slots_full_or_arena() -> void:
	_start()
	Run.add_weapon(Registry.weapon(FtueDynamite.WEAPON_ID), 1)
	assert_bool(FtueDynamite.due(4)).is_false()
	_start()
	var n := 0
	for w: WeaponDef in Registry.base_weapons():
		if Run.weapons.size() >= Run.weapon_cap():
			break
		if w.id != FtueDynamite.WEAPON_ID and not w.hidden and Run.weapon_instance(w.id) == null:
			Run.add_weapon(w, 1)
			n += 1
	assert_int(Run.weapons.size()).is_equal(Run.weapon_cap())
	assert_bool(FtueDynamite.due(4)).is_false()
	_start()
	Run.arena = true
	assert_bool(FtueDynamite.due(4)).is_false()


# ---------------------------------------------------------------- 1. the kill counter

func test_kill_counter_follows_kills() -> void:
	var kc: WKillCount = auto_free(WKillCount.new())
	add_child(kc)
	assert_str(kc.text()).is_equal("0")
	kc.tick(1.0 / 60.0, 5)
	assert_str(kc.text()).is_equal("5")
	kc.tick(1.0 / 60.0, 1234)
	assert_str(kc.text()).is_equal("1,234")
	# a new run's count is taken at once
	kc.tick(1.0 / 60.0, 0)
	assert_str(kc.text()).is_equal("0")


func test_kill_counter_dings_harder_with_the_kill_rate() -> void:
	# the mapping itself
	assert_float(WKillCount.heat_for(0.0)).is_equal(0.0)
	assert_float(WKillCount.heat_for(1.0)).is_less(WKillCount.heat_for(10.0))
	assert_float(WKillCount.heat_for(WKillCount.RATE_HOT)).is_equal_approx(1.0, 0.001)
	assert_float(WKillCount.heat_for(1000.0)).is_equal(1.0)
	assert_float(WKillCount.pop_amp_for(0.0)).is_equal_approx(WKillCount.POP_MIN, 0.0001)
	assert_float(WKillCount.pop_amp_for(1.0)).is_equal_approx(WKillCount.POP_MAX, 0.0001)
	# one kill a second for 4 s, then 40 a second for 2 s
	var slow: WKillCount = auto_free(WKillCount.new())
	add_child(slow)
	var kills := 0
	for f in 240:
		if f % 60 == 0:
			kills += 1
		slow.tick(1.0 / 60.0, kills)
	var cold := slow.heat
	assert_float(cold).is_greater(0.0)
	assert_float(cold).is_less(0.4)
	var fast: WKillCount = auto_free(WKillCount.new())
	add_child(fast)
	kills = 0
	var peak := 1.0
	for f in 120:
		if f % 3 != 0:
			kills += 1
		fast.tick(1.0 / 60.0, kills)
		peak = maxf(peak, fast.pop_scale())
	assert_float(fast.heat).is_greater(0.9)
	assert_float(fast.heat).is_greater(cold)
	# the punch grows with the heat and stays capped
	assert_float(peak).is_greater(1.0 + WKillCount.pop_amp_for(cold))
	assert_float(peak).is_less_equal(1.0 + WKillCount.POP_MAX + 0.0001)
	# at rest again once the kills stop
	for f in 600:
		fast.tick(1.0 / 60.0, kills)
	assert_float(fast.pop_scale()).is_equal_approx(1.0, 0.0001)
	assert_float(fast.heat).is_less(0.05)


func test_hud_counter_sits_under_the_clock() -> void:
	Run.kills = 0
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	await get_tree().process_frame
	hud._fit_top()
	var kc := hud.kill_counter()
	assert_object(kc).is_not_null()
	var plate: Control = hud._timer_plate
	assert_float(kc.position.y).is_greater_equal(plate.position.y + plate.size.y)
	assert_float(kc.position.x).is_equal_approx(plate.position.x + plate.size.x * 0.5, 0.5)
	# it ends above the foot of the slots' row and fits the room between the weapons and the lines
	assert_float(kc.position.y + kc.row_height()).is_less(HUD.SLOT_Y + 72.0)
	Run.kills = 37
	kc.tick(1.0 / 60.0, Run.kills)
	assert_str(kc.text()).is_equal("37")
