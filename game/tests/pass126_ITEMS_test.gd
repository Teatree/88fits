## Pass 126, lane ITEMS (Garry: "Assayer's Scale - I like this one, make it a Rare Passive Item. Don't make Banish pay
## too", "Canteen - Also like this one, this one can be an Uncommon", "Lifesteal stat - Reduce the Effectiveness ... about
## 25% less effective"; the ideas book's words: "Skipping a card or chest pays 25 coins and 5% of the next level's XP, and
## levels raise both", "Water no longer slows you, and leaving it gives +3 HP a second for 15 s. Evolved: enemies in water
## take +25% damage from you"). The Scale pays through the one place a skip is spent (Run.use_skip -> _pay_skip); the
## Canteen is Player._wade_mult, Player._tick_canteen and EnemyManager.damage; rules in BALANCING 68.ITEMS.
extends GdUnitTestSuite

const LAUNCH := "user://debug_launch.json"
const DT := 1.0 / 60.0

## The Scale's pay at each level: coins, the share of the next level's XP.
const SCALE_PAY := [[25, 0.05], [35, 0.07], [45, 0.09], [90, 0.18]]
## The Canteen at each level: HP a second, seconds.
const CANTEEN_AT := [[3.0, 15.0], [3.5, 16.0], [4.0, 17.0], [4.5, 18.0], [5.0, 20.0]]

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

## A flat world with one lake 4 m round (10, 0), under a holder the hero finds his `map` on.
const WET_MAP := """extends Node
func in_water(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(Vector2(10, 0)) < 4.0
func height_at(_x: float, _z: float) -> float:
	return 0.0
"""
const HOLDER := """extends Node3D
var map = null
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	Run.arena_next = false
	CardPool.rng = null


func after_test() -> void:
	CardPool.rng = null
	Run.arena = false
	Run.arena_next = false
	Run.debug_clear_items()
	Run.end()
	if FileAccess.file_exists(LAUNCH):
		DirAccess.remove_absolute(LAUNCH)


func _start(hero: String = "drifter") -> void:
	var c: CharacterDef = Registry.character(hero)
	Run.start(c, Registry.map("red_canyon"))
	Run.add_weapon(Registry.start_weapon_for(c), 1)


func _level_scale(level: int) -> void:
	while Run.passive_level("assayers_scale") < level:
		assert_bool(Run.add_or_level_passive("assayers_scale")).is_true()


## The purse and the XP a call to `fn` moved: [coins, xp, levels gained].
func _paid_by(fn: Callable) -> Array:
	var gold0: int = Run.run_gold
	var xp0: float = Run.xp
	var lv0: int = Run.level
	fn.call()
	return [Run.run_gold - gold0, Run.xp - xp0, Run.level - lv0]


# ---------------------------------------------------------------- the items are content

func test_the_items_are_there_available_and_on_the_ladder() -> void:
	var scale: PassiveDef = Registry.passive("assayers_scale")
	var can: PassiveDef = Registry.passive("canteen")
	for p: PassiveDef in [scale, can]:
		assert_object(p).is_not_null()
		assert_bool(p.is_item()).is_true()
		assert_bool(p.hidden).is_false()
		assert_bool(p.on_ladder()).is_true()
		assert_bool(Registry.is_unlocked("passive", p.id)).override_failure_message(p.id + " is locked").is_true()
		assert_bool(Registry.unlocked_passives().has(p)).is_true()
		assert_str(p.flavour).is_not_empty()
		assert_str(p.text).is_not_empty()
		assert_object(p.icon).is_not_null()
		assert_object(p.evolved_icon).is_not_null()
		assert_int(p.levels.size()).is_equal(p.max_level)
		assert_float(float(p.weight)).is_greater(0.0)
	assert_str(scale.rarity).is_equal("rare")
	assert_int(scale.max_level).is_equal(4)
	assert_str(can.rarity).is_equal("uncommon")
	assert_int(can.max_level).is_equal(5)
	# the book's numbers are the first level's
	assert_float(scale.levels[0][0].value).is_equal(25.0)
	assert_float(scale.levels[0][1].value).is_equal_approx(0.05, 0.00001)
	assert_bool(scale.text.contains("25 coins") and scale.text.contains("5% of the next level's XP")).is_true()
	assert_bool(can.text.contains("+3 HP a second for 15 s") and can.text.contains("+25%")).is_true()
	# Banish is out of it, in the words too
	assert_bool(scale.text.to_lower().contains("banish")).is_false()


func test_the_words_say_each_level() -> void:
	var scale: PassiveDef = Registry.passive("assayers_scale")
	var can: PassiveDef = Registry.passive("canteen")
	assert_str(TextGen.passive_description(scale, 1)).contains("+25 coins a skip pays")
	assert_str(TextGen.passive_description(scale, 1)).contains("+5% next level's XP a skip pays")
	assert_str(TextGen.passive_description(scale, 3)).contains("+45 coins a skip pays")
	assert_str(TextGen.passive_description(scale, 4)).contains("(Evolved)")
	assert_str(TextGen.passive_description(scale, 4)).contains("+90 coins a skip pays")
	assert_str(TextGen.passive_description(scale, 4)).contains("+18% next level's XP a skip pays")
	assert_str(TextGen.next_level_text(scale, 3)).contains("+45 coins a skip pays")
	assert_str(TextGen.passive_description(can, 1)).contains("+3 HP a second after leaving water")
	assert_str(TextGen.passive_description(can, 1)).contains("+15 s healing after leaving water")
	assert_str(TextGen.passive_description(can, 5)).contains("+5 HP a second after leaving water")
	assert_str(TextGen.passive_description(can, 5)).contains("+25% damage to enemies in water")
	# the rule itself is a word, never a number
	assert_str(TextGen.describe_effects(can.effects_at_level(1))).ends_with("water no longer slows you")
	assert_int(TextGen._sum_effects(can.effects_for_level(1)).size()).is_equal(2)
	# the upgrade card's rows
	var rows := TextGen.passive_changes(can, 4, 5)
	var names: Array = rows.map(func(r: Dictionary) -> String: return str(r["name"]))
	assert_bool(names.has("Damage to enemies in water")).override_failure_message(str(names)).is_true()
	for s in ["skip_coins", "skip_xp", "water_walk", "leave_water_regen", "leave_water_seconds", "water_damage"]:
		assert_bool(StatSheet.PLAYER_DEFAULTS.has(s)).override_failure_message(s).is_true()
		assert_bool(TextGen.STATS.has(s)).override_failure_message(s).is_true()


# ---------------------------------------------------------------- the Scale's pay

func test_a_level_up_skip_and_a_mutation_skip_pay_once_at_each_level() -> void:
	_start()
	var w: WeaponInstance = Run.weapons[0]
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	var closes := [0]
	cs.chosen.connect(func(_c): closes[0] += 1)
	for lv in range(1, 5):
		_level_scale(lv)
		var pay: Array = SCALE_PAY[lv - 1]
		# far from a level, so the share is all the XP moves
		Run.level = 20
		Run.xp = 0.0
		Run.skips_left = 2
		var need: float = Run.xp_to_next()
		var greed: float = Run.player_sheet.get_stat("greed", 1.0)
		# the level-up's SKIP
		cs.show_offer(CardPool.level_up_offer(3), "LEVEL!", false)
		var got := _paid_by(func(): cs._skip())
		assert_int(int(got[0])).override_failure_message("level %d: coins %s" % [lv, str(got)]).is_equal(roundi(float(pay[0]) * greed))
		assert_float(float(got[1])).override_failure_message("level %d: xp %s" % [lv, str(got)]).is_equal_approx(need * float(pay[1]), 0.001)
		assert_int(Run.skips_left).is_equal(1)
		# the mutation offer's SKIP, the same skips (the second skip's share is of the same next level)
		cs.show_offer(CardPool.path_offer(w), "MUTATION", false, true)
		got = _paid_by(func(): cs._skip())
		assert_int(int(got[0])).is_equal(roundi(float(pay[0]) * greed))
		assert_float(float(got[1])).is_equal_approx(need * float(pay[1]), 0.001)
		assert_int(Run.skips_left).is_equal(0)
		# none left: refused, nothing paid
		cs.show_offer(CardPool.level_up_offer(3), "LEVEL!", false)
		got = _paid_by(func(): cs._skip())
		assert_array(got).is_equal([0, 0.0, 0])
		assert_bool(cs.visible).is_true()
		cs.visible = false
	assert_int(closes[0]).is_equal(8)
	# the tables the offers replaced go first
	await get_tree().process_frame


func test_without_the_item_a_skip_pays_nothing() -> void:
	_start()
	Run.skips_left = 2
	var got := _paid_by(func(): assert_bool(Run.use_skip()).is_true())
	assert_array(got).is_equal([0, 0.0, 0])
	got = _paid_by(func(): assert_str(Run.chest_skip(Run.chest_roll())).is_not_empty())
	assert_array(got).is_equal([0, 0.0, 0])


func test_a_chest_skip_pays_once_at_each_level_and_a_chest_it_cannot_skip_pays_nothing() -> void:
	_start()
	for lv in range(1, 5):
		_level_scale(lv)
		var pay: Array = SCALE_PAY[lv - 1]
		Run.level = 20
		Run.xp = 0.0
		Run.skips_left = 1
		var need: float = Run.xp_to_next()
		var greed: float = Run.player_sheet.get_stat("greed", 1.0)
		var got := _paid_by(func(): assert_str(Run.chest_skip(Run.chest_roll())).is_not_empty())
		assert_int(int(got[0])).override_failure_message("level %d" % lv).is_equal(roundi(float(pay[0]) * greed))
		assert_float(float(got[1])).is_equal_approx(need * float(pay[1]), 0.001)
		assert_int(Run.skips_left).is_equal(0)
		# no skip left: it cannot be let go
		got = _paid_by(func(): assert_str(Run.chest_skip(Run.chest_roll())).is_empty())
		assert_array(got).is_equal([0, 0.0, 0])


func test_a_reroll_and_a_banish_pay_nothing_at_every_level() -> void:
	_start()
	Run.level = 20
	Run.xp = 0.0
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	for lv in range(1, 5):
		_level_scale(lv)
		# the reroll
		Run.rerolls_left = 1
		cs.show_offer(CardPool.level_up_offer(3), "LEVEL!", false)
		assert_array(_paid_by(func(): cs._reroll())).is_equal([0, 0.0, 0])
		assert_int(Run.rerolls_left).is_equal(0)
		# the level-up's banish, a whole card struck
		Run.banishes_left = 1
		Run.skips_left = 2
		cs.show_offer(CardPool.level_up_offer(3), "LEVEL!", false)
		cs._toggle_banish()
		var may: Array = CardPool.banishable(cs._offer)
		if not may.is_empty():
			assert_array(_paid_by(func(): cs._pick(may[0]))).is_equal([0, 0.0, 0])
			assert_int(Run.banishes_left).is_equal(0)
		assert_int(Run.skips_left).is_equal(2)
		cs.visible = false
		# the chest's banish
		Run.banishes_left = 1
		var roll := {"type": "passive", "id": "magnet", "def": Registry.passive("magnet"), "level_from": 0, "level_to": 1, "is_new": true}
		assert_array(_paid_by(func(): assert_bool(Run.chest_banish(roll).is_empty()).is_false())).is_equal([0, 0.0, 0])
		Run.banished.erase("magnet")
	await get_tree().process_frame


func test_the_real_screens_pay_through_the_game_once() -> void:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	Run.grind_used = {"id": "boomstick"}
	_level_scale(1)
	Run.level = 20
	Run.xp = 0.0
	Run.skips_left = 3
	var greed: float = Run.player_sheet.get_stat("greed", 1.0)
	var need: float = Run.xp_to_next()
	var heard: Array = []
	var ear := func(c: int, x: float): heard.append([c, x])
	Run.skip_paid.connect(ear)
	# a level-up's SKIP
	g._pending_levels = 1
	g.modal_reset()
	assert_bool(g._show_next_level_cards()).is_true()
	var gold0: int = Run.run_gold
	g.cards._skip()
	assert_int(Run.run_gold - gold0).is_equal(roundi(25.0 * greed))
	assert_int(heard.size()).is_equal(1)
	g.resume_gate.tap()
	# a chest let go: Game hears the screen close once
	g.modal_reset()
	gold0 = Run.run_gold
	var roll := Run.chest_roll(false)
	g.chest_screen.open(roll)
	g._on_chest_closed(false)
	assert_int(Run.run_gold - gold0).is_equal(roundi(25.0 * greed))
	assert_int(heard.size()).is_equal(2)
	assert_float(float(heard[1][1])).is_equal_approx(need * 0.05, 0.001)
	g.chest_screen.visible = false
	g.resume_gate.tap()
	# a chest taken pays nothing of this
	g.modal_reset()
	g.chest_screen.open({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
	g._on_chest_closed(true)
	assert_int(heard.size()).is_equal(2)
	g.chest_screen.visible = false
	g.resume_gate.tap()
	# a table a banish emptied closes on `skipped` (CardScreen._banish_pick) with no skip spent: no pay either
	var left: int = Run.skips_left
	g.modal_reset()
	gold0 = Run.run_gold
	g._on_card_chosen({"skipped": true})
	g.resume_gate.tap()
	g.modal_reset()
	g._on_path_chosen({"skipped": true})
	g.resume_gate.tap()
	assert_int(Run.run_gold).is_equal(gold0)
	assert_int(Run.skips_left).is_equal(left)
	assert_int(heard.size()).is_equal(2)
	Run.skip_paid.disconnect(ear)
	g.modal_reset()
	g.set_paused(false)


## skip -> XP -> level-up -> skip: legal only while skips remain; the banked level's cards come after the screen closes,
## never nested in it.
func test_the_xp_pay_can_level_him_and_the_cards_wait_their_turn() -> void:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	Run.grind_used = {"id": "boomstick"}
	_level_scale(4)
	Run.skips_left = 2
	g.modal_reset()
	# one level open, the bar a hair short of the next
	g._pending_levels = 1
	assert_bool(g._show_next_level_cards()).is_true()
	assert_int(g._pending_levels).is_equal(0)
	Run.xp = Run.xp_to_next() - 0.5
	var lv0: int = Run.level
	g.cards._skip()
	# the skip levelled him: banked, one request waiting, nothing nested on the closing screen
	assert_int(Run.level).is_equal(lv0 + 1)
	assert_int(g._pending_levels).is_equal(1)
	assert_array(g.modal_queue_kinds()).is_equal([Game.Modal.CARDS])
	assert_bool(g.cards.visible).is_false()
	assert_int(Run.skips_left).is_equal(1)
	# the next cards open after the beat, alone
	await get_tree().create_timer(g.MODAL_BEAT + 0.2).timeout
	assert_array(g.visible_modals()).is_equal(["cards"])
	assert_int(g._pending_levels).is_equal(0)
	# the last skip, the bar short again: the next level's cards, and with no skip left the third cannot pay
	Run.xp = Run.xp_to_next() - 0.5
	g.cards._skip()
	assert_int(Run.level).is_equal(lv0 + 2)
	assert_int(Run.skips_left).is_equal(0)
	await get_tree().create_timer(g.MODAL_BEAT + 0.2).timeout
	assert_array(g.visible_modals()).is_equal(["cards"])
	var gold0: int = Run.run_gold
	var xp0: float = Run.xp
	g.cards._skip()
	assert_int(Run.run_gold).is_equal(gold0)
	assert_float(Run.xp).is_equal(xp0)
	assert_array(g.visible_modals()).is_equal(["cards"])
	g.cards.visible = false
	g.modal_reset()
	g.set_paused(false)


func test_the_gold_is_named_for_the_record_and_field_notes_does_not_raise_the_share() -> void:
	assert_bool(RunAnalytics.GOLD_SOURCES.has("skip_pay")).is_true()
	_start()
	_level_scale(1)
	Run.level = 20
	Run.xp = 0.0
	Run.skips_left = 1
	var need: float = Run.xp_to_next()
	Run.player_sheet.add_effect(Effect.make("xp_gain", "mul", 0.5), "p126 test")
	assert_bool(Run.use_skip()).is_true()
	assert_float(Run.xp).is_equal_approx(need * 0.05, 0.001)
	# coins go through coin gain, as all gold
	Run.player_sheet.add_effect(Effect.make("greed", "mul", 1.0), "p126 test")
	Run.skips_left = 1
	var gold0: int = Run.run_gold
	assert_bool(Run.use_skip()).is_true()
	assert_int(Run.run_gold - gold0).is_equal(50)


# ---------------------------------------------------------------- the Canteen on the hero

## A real Player on a fake map: one lake 4 m round (10, 0), the Canteen at `level`, room in his health bar.
func _hero_on_a_lake(level: int) -> Player:
	_start()
	var holder: Node3D = auto_free(Node3D.new())
	holder.set_script(_script(HOLDER))
	add_child(holder)
	var m: Node = Node.new()
	m.set_script(_script(WET_MAP))
	holder.add_child(m)
	holder.set("map", m)
	var pl: Player = (load("res://player/Player.tscn") as PackedScene).instantiate()
	holder.add_child(pl)
	pl.setup(Registry.character("drifter"))
	_level_canteen(level, pl)
	pl.max_hp = 1000.0
	pl.hp = 100.0
	pl.global_position = Vector3(0, 0, 0)
	return pl


func _level_canteen(level: int, pl: Player = null) -> void:
	while Run.passive_level("canteen") < level:
		assert_bool(Run.add_or_level_passive("canteen")).is_true()
	if pl != null:
		pl.refresh_stats()


func test_water_never_slows_the_owner_and_still_slows_without_it() -> void:
	var pl := _hero_on_a_lake(0)
	pl.global_position = Vector3(10, 0, 0)
	assert_float(pl._wade_mult()).is_equal_approx(0.9, 0.0001)
	_level_canteen(1, pl)
	assert_float(pl._wade_mult()).is_equal(1.0)
	assert_float(Run.player_sheet.get_stat("water_walk", 0.0)).is_equal(1.0)
	# every rung holds it
	_level_canteen(5, pl)
	assert_float(pl._wade_mult()).is_equal(1.0)
	assert_float(Run.player_sheet.get_stat("water_walk", 0.0)).is_equal(1.0)


func test_the_owner_changes_nothing_for_a_creature() -> void:
	_start()
	_level_canteen(5)
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_lake(Vector2(12, 0), 4.0)
	em.refresh_player_stats()
	var wet := _creature(em, Vector3(12, 0, 0))
	em._wade_tick()
	assert_float(em._wade_mult(wet)).is_equal_approx(0.9, 0.0001)


func test_leaving_water_heals_for_its_seconds_at_each_level() -> void:
	for lv in range(1, 6):
		var pl := _hero_on_a_lake(lv)
		var at: Array = CANTEEN_AT[lv - 1]
		# Solenne's Buff duration aside, the Drifter's seconds are the item's
		assert_float(Run.buff_seconds(float(at[1]))).is_equal_approx(float(at[1]), 0.0001)
		pl.global_position = Vector3(10, 0, 0)
		pl._tick_canteen(DT)
		assert_float(Run.canteen_left).is_equal(0.0)
		var hp0: float = pl.hp
		# he walks out
		pl.global_position = Vector3(0, 0, 0)
		pl._tick_canteen(DT)
		assert_float(Run.canteen_left).is_equal_approx(float(at[1]) - DT, 0.0001)
		# the whole time, to the last drop
		var t := DT
		while Run.canteen_left > 0.0:
			pl._tick_canteen(DT)
			t += DT
			assert_bool(t < 40.0).is_true()
		assert_float(t).is_equal_approx(float(at[1]), DT * 1.5)
		assert_float(pl.hp - hp0).override_failure_message("level %d: healed %.2f" % [lv, pl.hp - hp0]).is_equal_approx(float(at[0]) * float(at[1]), 0.01)
		# nothing more after it
		var hp1: float = pl.hp
		pl._tick_canteen(1.0)
		assert_float(pl.hp).is_equal(hp1)
		pl.get_parent().queue_free()
		Run.debug_clear_items()
		await get_tree().process_frame


func test_no_heal_in_water_and_coming_out_again_starts_it_anew_never_on_top() -> void:
	var pl := _hero_on_a_lake(1)
	var hp0: float = pl.hp
	# never been in: the dry walk heals nothing
	for k in range(120):
		pl._tick_canteen(DT)
	assert_float(pl.hp).is_equal(hp0)
	assert_float(Run.canteen_left).is_equal(0.0)
	# in the lake: nothing, however long
	pl.global_position = Vector3(10, 0, 0)
	for k in range(600):
		pl._tick_canteen(DT)
	assert_float(pl.hp).is_equal(hp0)
	assert_float(Run.canteen_left).is_equal(0.0)
	# out: it runs
	pl.global_position = Vector3(0, 0, 0)
	for k in range(120):
		pl._tick_canteen(DT)
	assert_float(Run.canteen_left).is_equal_approx(13.0, 0.05)
	assert_float(pl.hp - hp0).is_equal_approx(6.0, 1.0)
	# back in: it stops at once, no heal while he stands there
	pl.global_position = Vector3(10, 0, 0)
	pl._tick_canteen(DT)
	assert_float(Run.canteen_left).is_equal(0.0)
	var hp1: float = pl.hp
	for k in range(120):
		pl._tick_canteen(DT)
	assert_float(pl.hp).is_equal(hp1)
	# out again: the full time again, not 13 + 15
	pl.global_position = Vector3(0, 0, 0)
	pl._tick_canteen(DT)
	assert_float(Run.canteen_left).is_equal_approx(15.0 - DT, 0.001)
	# the HUD's word while it runs
	assert_bool(HUD.buff_parts().has("CANTEEN")).is_true()
	Run.canteen_left = 0.0
	assert_bool(HUD.buff_parts().has("CANTEEN")).is_false()


func test_flying_over_a_lake_is_not_a_wade_and_flying_out_of_one_is_a_leaving() -> void:
	var pl := _hero_on_a_lake(1)
	# over the water, high up, never touched it: not wet, no heal after
	pl.global_position = Vector3(10, 3, 0)
	pl._tick_canteen(DT)
	pl.global_position = Vector3(0, 0, 0)
	pl._tick_canteen(DT)
	assert_float(Run.canteen_left).is_equal(0.0)
	# wet, then thrown up inside the lake's edge: still wet, no time yet; past the edge in the air it starts
	pl.global_position = Vector3(10, 0, 0)
	pl._tick_canteen(DT)
	pl.global_position = Vector3(10, 3, 0)
	pl._tick_canteen(DT)
	assert_float(Run.canteen_left).is_equal(0.0)
	pl.global_position = Vector3(0, 3, 0)
	pl._tick_canteen(DT)
	assert_bool(Run.canteen_left > 14.0).is_true()


func test_the_heal_counts_for_the_item_and_buff_duration_stretches_it() -> void:
	var pl := _hero_on_a_lake(1)
	assert_bool(TaskTally.HEAL_STATS.has("leave_water_regen")).is_true()
	Run.healed_by_item.clear()
	pl.global_position = Vector3(10, 0, 0)
	pl._tick_canteen(DT)
	pl.global_position = Vector3(0, 0, 0)
	for k in range(60):
		pl._tick_canteen(DT)
	assert_float(float(Run.healed_by_item.get("canteen", 0.0))).is_greater_equal(2.0)
	# Solenne's Buff duration, as every timed buff on her
	Run.player_sheet.add_effect(Effect.make("buff_duration", "mul", 1.0), "p126 test")
	pl.global_position = Vector3(10, 0, 0)
	pl._tick_canteen(DT)
	pl.global_position = Vector3(0, 0, 0)
	pl._tick_canteen(DT)
	assert_float(Run.canteen_left).is_equal_approx(30.0 - DT, 0.001)


func test_a_dead_hero_gets_nothing() -> void:
	var pl := _hero_on_a_lake(1)
	pl.dead = true
	pl.hp = 0.0
	pl.heal(5.0, "", "stat:leave_water_regen")
	assert_float(pl.hp).is_equal(0.0)


# ---------------------------------------------------------------- the Evolved rung's damage

func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	hero.global_position = Vector3(0, 0, -40)
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = hero
	add_child(em)
	g.enemies = em
	em.colour_after_kills = 999999
	return {"g": g, "hero": hero, "em": em}


func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em.rise_v[i] = 0.0
	em.dr[i] = 0.0
	em.hp[i] = 100000.0
	em.max_hp[i] = 100000.0
	return i


## What `amount` took off creature `i`, with no crit in it (HIT_NO_CRIT).
func _hit(em: EnemyManager, i: int, amount: float, id := "boomstick", hot := false) -> float:
	var h0: float = em.hp[i]
	em.damage(i, amount, id, Vector3.ZERO, 0.0, false, hot, EnemyManager.HIT_NO_CRIT)
	return h0 - em.hp[i]


func test_the_evolved_rung_hits_harder_only_in_water() -> void:
	_start()
	var w := _world()
	var em: EnemyManager = w["em"]
	em.set_lake(Vector2(12, 0), 4.0)
	var wet := _creature(em, Vector3(12, 0, 0))
	var dry := _creature(em, Vector3(-12, 0, 0))
	# no item, and every rung below Evolved: nothing
	em.refresh_player_stats()
	assert_float(_hit(em, wet, 100.0)).is_equal_approx(100.0, 0.001)
	for lv in range(1, 5):
		_level_canteen(lv)
		em.refresh_player_stats()
		assert_float(em._water_dmg).is_equal(0.0)
		assert_float(_hit(em, wet, 100.0)).override_failure_message("level %d" % lv).is_equal_approx(100.0, 0.001)
	# Evolved
	_level_canteen(5)
	em.refresh_player_stats()
	assert_float(em._water_dmg).is_equal_approx(0.25, 0.00001)
	assert_float(_hit(em, wet, 100.0)).is_equal_approx(125.0, 0.001)
	assert_float(_hit(em, dry, 100.0)).is_equal_approx(100.0, 0.001)
	# his burn too
	assert_float(_hit(em, wet, 100.0, "boomstick", true)).is_equal_approx(125.0, 0.001)
	# not a hit no weapon sent, nor a hostile one, nor the revive's flat tenth
	assert_float(_hit(em, wet, 100.0, "")).is_equal_approx(100.0, 0.001)
	assert_float(_hit(em, wet, 100.0, "blast")).is_equal_approx(100.0, 0.001)
	assert_float(_hit(em, wet, 100.0, "loose_rocket")).is_equal_approx(100.0, 0.001)
	assert_float(_hit(em, wet, 100.0, "revive")).is_equal_approx(100.0, 0.001)
	# nor a creature in the air over the lake
	em.lift_h[wet] = 2.0
	assert_float(_hit(em, wet, 100.0)).is_equal_approx(100.0, 0.001)
	em.lift_h[wet] = 0.0
	# one that walks out of it stops taking it at once
	em.pos[wet] = Vector3(0, 0, 0)
	assert_float(_hit(em, wet, 100.0)).is_equal_approx(100.0, 0.001)


# ---------------------------------------------------------------- life steal, 25% less

func test_life_steal_is_a_quarter_less_and_so_is_its_cap() -> void:
	var thirst: PassiveDef = Registry.passive("thirst")
	assert_float(thirst.levels[0][0].value).is_equal_approx(0.01125, 0.000001)
	# its price is unchanged
	assert_float(thirst.levels[0][1].value).is_equal_approx(-0.06, 0.000001)
	var blood: PassiveDef = Registry.passive("bloodthirst")
	var by := {}
	for e: Effect in blood.levels[0]:
		by[e.stat] = e.value
	assert_float(float(by["lifesteal"])).is_equal_approx(0.06, 0.000001)
	assert_float(float(by["lifesteal_cap"])).is_equal_approx(0.06, 0.000001)
	assert_float(float(by["max_hp"])).is_equal_approx(-0.12, 0.000001)
	assert_float(Run.LIFESTEAL_CAP).is_equal_approx(0.03, 0.000001)
	assert_float(float(StatSheet.PLAYER_DEFAULTS["lifesteal_cap"])).is_equal_approx(0.03, 0.000001)
	# four levels of the card: 4.5%, under a cap of 3% of max HP a second
	_start()
	for k in range(4):
		assert_bool(Run.add_or_level_passive("thirst")).is_true()
	assert_float(Run.player_sheet.get_stat("lifesteal", 0.0)).is_equal_approx(0.045, 0.00001)
	assert_float(Run.player_sheet.get_stat("lifesteal_cap", 0.0)).is_equal_approx(0.03, 0.00001)
	# HeroPower reads the same cap
	var sh := StatSheet.new()
	sh.set_bases({"max_hp": 100.0, "lifesteal": 1.0})
	assert_float(HeroPower.ehp(sh, 1000.0)).is_equal_approx(100.0 + HeroPower.SUSTAIN_SECONDS * 3.0, 0.001)
	# the Trail's upgrade types have none (the Upgrade board had none either, until it went in pass 129)
	for type: Variant in Trail.upgrade_types():
		for e: Dictionary in Trail.upgrade(str(type)).get("effects", []):
			assert_bool(str(e.get("stat", "")) in ["lifesteal", "lifesteal_cap"]).override_failure_message(str(type)).is_false()
