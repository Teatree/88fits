extends GdUnitTestSuite

## Pass 145 (Garry: "War Drum: the text is a bit too hard to see right now, cz it goes away so fast. Make the text much
## simpler and make it linger for just a bit longer. Let's add a small knockback after Player picks up the War Drum ...
## it deals very little damage, but it's there the first time, and there is some VFX that plays right after"):
## the moment says two short lines that stay after the drum, and the boost starts with one small push round the Outlaw.

const DRUM := "war_drum"


func _drum() -> StructureDef:
	return Registry.structure(DRUM)


func test_the_words_are_two_short_lines() -> void:
	var d := _drum()
	assert_str(DrumBoost.headline(d.effects, 15.0)).is_equal("×2 ATTACK ×2 SPEED · FOR 15 SECONDS")
	var rules := DrumBoost.stack_rules(d)
	var under_rage := DrumBoost.stacked_effects(d.effects, rules, {"rage": true, "sprint": false})
	assert_str(DrumBoost.headline(under_rage, 15.0)).is_equal("×1.5 ATTACK ×1.5 SPEED · FOR 15 SECONDS")


func test_the_words_linger_after_the_drum() -> void:
	var m := DrumMoment.new()
	add_child(m)
	m.open(_drum(), DrumBoost.headline(_drum().effects, 15.0))
	var mo: Dictionary = _drum().params["moment"]
	var big_t := 0.0
	for h: Dictionary in mo["hits"]:
		if bool(h.get("big", false)):
			big_t = float(h["t"])
	assert_float(m.total_seconds()).is_equal_approx(big_t + float(mo["words_hold"]) + float(mo["words_fade"]), 0.001)
	assert_float(m.total_seconds()).is_greater(float(mo["seconds"]))
	# fully shown a second after the big slap, though the drum is fading or gone by then
	m.t = big_t
	m._process(0.0)
	m._words_t = big_t
	assert_float(m.words_alpha_at(big_t + 0.8)).is_equal(1.0)
	assert_float(m.alpha_at(big_t + 0.8)).is_less(0.5)
	assert_float(m.words_alpha_at(m.total_seconds())).is_equal(0.0)
	m.skip()
	m.free()


func test_the_boost_starts_with_a_small_push() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 9, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.4).timeout
	g.player.god = true
	var here: Vector3 = g.player.global_position
	var near: int = g.enemies.spawn("skeleton", here + Vector3(2, 0, 0))
	var far: int = g.enemies.spawn("skeleton", here + Vector3(9, 0, 0))
	# the Revolver must not kill them while they rise
	for i: int in [near, far]:
		g.enemies.max_hp[i] = 1.0e5
		g.enemies.hp[i] = 1.0e5
	# out of the ground first (a rising creature stands where it is)
	await get_tree().create_timer(1.5).timeout
	here = g.player.global_position
	var hp_near: float = g.enemies.hp[near]
	var hp_far: float = g.enemies.hp[far]
	var b: Dictionary = _drum().params["burst"]
	assert_float(float(b["damage"])).is_less_equal(10.0)
	g._drum_burst(_drum())
	# the near one is hurt a little and pushed out; the far one is untouched
	assert_float(g.enemies.hp[near]).is_less(hp_near)
	assert_float(hp_near - float(g.enemies.hp[near])).is_less_equal(float(b["damage"]) * 3.0)
	assert_float(g.enemies.hp[far]).is_equal(hp_far)
	# pushed away by a small distance (about a metre or more for a skeleton), not a throw across the screen
	var p0: Vector3 = g.enemies.pos[near]
	var d0 := Vector2(p0.x - here.x, p0.z - here.z).length()
	await get_tree().create_timer(0.3).timeout
	var p1: Vector3 = g.enemies.pos[near]
	var d1 := Vector2(p1.x - here.x, p1.z - here.z).length()
	print("drum push: ", d0, " -> ", d1)
	assert_float(d1 - d0).is_between(1.0, 4.0)
