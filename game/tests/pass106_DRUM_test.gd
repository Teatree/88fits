extends GdUnitTestSuite

## Pass 106, lane DRUM (Garry: the War Drum "should be more powerful and longer lasting than the Rage Power-up. It's only
## one time thing and it should be a big deal"): the moment (time stops: the run clock, the creatures, the music; every
## touch swallowed; ~2 s; then everything goes on from where it stood), the boost (15 s of attack damage and weapon speed
## at least the Berserk's, knockback on every weapon, a little move speed), the stacking rule with a Berserk and a Sprint
## (the drum's part x1.5 in place of x2), the HUD's plate, one use per drum.

const DRUM := "war_drum"


func _drum() -> StructureDef:
	return Registry.structure(DRUM)


func _eff(list: Array, stat: String, op: String = "mul") -> Effect:
	for e in list:
		if e is Effect and (e as Effect).stat == stat and (e as Effect).op == op:
			return e
	return null


# ---------------------------------------------------------------- the data

func test_the_drum_is_stronger_and_longer_than_the_berserk() -> void:
	var d := _drum()
	var rage: PickupDef = Registry.pickup("rage")
	assert_str(d.effect_kind).is_equal("buff")
	assert_float(float(d.params.get("seconds", 0.0))).is_equal(15.0)
	for stat: String in ["might", "haste"]:
		var mine := _eff(d.effects, stat)
		var theirs := _eff(rage.effects, stat)
		assert_object(mine).override_failure_message(stat).is_not_null()
		assert_float(mine.value).override_failure_message(stat).is_greater_equal(theirs.value)
	assert_float(_eff(d.effects, "move_speed").value).is_greater(0.0)
	var kb_add := _eff(d.effects, "knockback", "add")
	assert_float(kb_add.value).is_greater(0.0)
	assert_str(kb_add.target).is_equal("all_weapons")
	assert_bool(bool(d.params.get("plate", false))).is_true()
	var m: Dictionary = d.params["moment"]
	assert_float(float(m["seconds"])).is_between(1.5, 2.6)
	assert_int((m["hits"] as Array).size()).is_greater_equal(5)
	assert_bool(ResourceLoader.exists(str(m["picture"]))).is_true()
	assert_bool(Registry.soundmap.entry(str(m["sound"])).get("stream") != null).is_true()
	assert_object(d.icon).is_not_null()


func test_the_stacking_rule() -> void:
	var d := _drum()
	var rules := DrumBoost.stack_rules(d)
	var alone := DrumBoost.stacked_effects(d.effects, rules, {"rage": false, "sprint": false})
	assert_float(_eff(alone, "might").value).is_equal_approx(1.0, 0.0001)
	assert_float(_eff(alone, "haste").value).is_equal_approx(1.0, 0.0001)
	# beside a Berserk: x1.5 in place of x2 on damage and weapon speed, the rest untouched
	var rage := DrumBoost.stacked_effects(d.effects, rules, {"rage": true, "sprint": false})
	assert_float(1.0 + _eff(rage, "might").value).is_equal_approx(1.5, 0.0001)
	assert_float(1.0 + _eff(rage, "haste").value).is_equal_approx(1.5, 0.0001)
	assert_float(_eff(rage, "move_speed").value).is_equal_approx(_eff(alone, "move_speed").value, 0.0001)
	assert_float(_eff(rage, "knockback", "add").value).is_equal_approx(_eff(alone, "knockback", "add").value, 0.0001)
	# beside a Sprint: half the move speed's bonus
	var sprint := DrumBoost.stacked_effects(d.effects, rules, {"rage": false, "sprint": true})
	assert_float(_eff(sprint, "move_speed").value).is_equal_approx(_eff(alone, "move_speed").value * 0.5, 0.0001)
	assert_float(_eff(sprint, "might").value).is_equal_approx(1.0, 0.0001)
	# the def's own effects are never changed
	assert_float(_eff(d.effects, "might").value).is_equal_approx(1.0, 0.0001)
	assert_str(DrumBoost.summary(alone, 15.0)).is_equal("×2 DAMAGE · ×2 ATTACK SPEED · KNOCKBACK · +15% SPEED · 15 SECONDS")
	assert_str(DrumBoost.summary(rage, 15.0)).contains("×1.5 DAMAGE")


func test_the_plate_is_the_drums() -> void:
	assert_str(HUD.plate_key("structure:" + DRUM)).is_equal("structure:" + DRUM)
	assert_object(HUD.plate_def("structure:" + DRUM)).is_equal(_drum())
	# a structure's buff without params.plate has none
	assert_str(HUD.plate_key("structure:healing_well")).is_equal("")


# ---------------------------------------------------------------- in a run

func _game() -> Game:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 9, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func _until(cond: Callable, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		if cond.call():
			return true
		await get_tree().create_timer(0.05, true).timeout
		waited += 0.05
	return bool(cond.call())


func test_time_stops_for_the_moment_and_goes_on_after() -> void:
	var g := _game()
	await get_tree().create_timer(0.4).timeout
	g.player.god = true
	var here: Vector3 = g.player.global_position
	var e: int = g.enemies.spawn("skeleton", here + Vector3(7, 0, 0))
	await get_tree().create_timer(0.5).timeout
	var w: WeaponInstance = Run.weapon_instance("revolver")
	var dmg0 := w.stat("damage")
	var kb0 := w.stat("knockback")
	var cd0 := w.stat("cooldown")
	var ms0 := Run.player_sheet.get_stat("move_speed", 5.0)
	# the drum, used as the hero would: a structure beside him, filled
	var sm: StructureManager = g.structures
	var at := here + Vector3(4, 0, 0)
	at.y = g.map.height_at(at.x, at.z)
	var s: StructureManager.Structure = sm._spawn(_drum(), at)
	sm._use(s)
	assert_bool(g.paused).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(g.drum_moment.visible).is_true()
	assert_bool(g.drum_moment.playing).is_true()
	assert_int(g.current_modal()).is_equal(Game.Modal.DRUM)
	# no boost yet: it starts as time does
	assert_float(Run.boost_left("structure:" + DRUM)).is_equal(0.0)
	var clock0 := Run.elapsed
	var buff0 := Run.buff_clock()
	var epos: Vector3 = g.enemies.pos[e]
	var mus0 := Audio.music_position()
	# a finger on the screen, and on the pause disc, while it plays: swallowed, nothing opens
	var eaten0: int = g.drum_moment.touches_eaten
	for spot in [Vector2(540, 1500), Vector2(1000, 120)]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = spot
		t.pressed = true
		Input.parse_input_event(t)
		await get_tree().process_frame
		var u := InputEventScreenTouch.new()
		u.index = 0
		u.position = spot
		u.pressed = false
		Input.parse_input_event(u)
		await get_tree().process_frame
	await get_tree().create_timer(0.8, true).timeout
	assert_int(g.drum_moment.touches_eaten).is_greater(eaten0)
	assert_bool(g.pause_screen.visible).is_false()
	assert_bool(g.drum_moment.playing).is_true()
	assert_int(g.drum_moment.hits_played).is_greater(0)
	# everything stood still: the run's clock, the buffs' clock, the creature, the music
	assert_float(Run.elapsed).is_equal(clock0)
	assert_float(Run.buff_clock()).is_equal(buff0)
	assert_vector(g.enemies.pos[e]).is_equal(epos)
	if mus0 >= 0.0:
		assert_float(Audio.music_position()).is_equal_approx(mus0, 0.05)
	# it ends by itself after about two seconds and the run goes on
	var done: bool = await _until(func() -> bool: return not g.paused, 3.0)
	assert_bool(done).is_true()
	assert_bool(g.drum_moment.visible).is_false()
	assert_int(g.drum_moment.hits_played).is_equal((_drum().params["moment"]["hits"] as Array).size())
	assert_float(Run.boost_left("structure:" + DRUM)).is_between(14.0, 15.0)
	if mus0 >= 0.0:
		assert_float(Audio.music_position()).is_greater_equal(mus0 - 0.01)
		assert_float(Audio.music_position()).is_less(mus0 + 1.0)
	# the boost: x2 damage, x2 weapon speed, knockback on the gun, +15% move speed
	assert_float(w.stat("damage")).is_equal_approx(dmg0 * 2.0, 0.01)
	assert_float(w.stat("cooldown")).is_equal_approx(cd0 * 0.5, 0.01)
	assert_float(w.stat("knockback")).is_equal_approx((kb0 + 3.0) * 1.5, 0.01)
	assert_float(Run.player_sheet.get_stat("move_speed", 5.0)).is_equal_approx(ms0 * 1.15, 0.01)
	# the clock runs again, and the music with it
	var mus1 := Audio.music_position()
	await get_tree().create_timer(0.3).timeout
	assert_float(Run.elapsed).is_greater(clock0)
	# (headless the run's track plays on the dummy driver: it held at mus0 through the moment and went on from there)
	if mus0 >= 0.0:
		assert_float(mus1 - mus0).is_between(0.0, 0.1)
		assert_float(Audio.music_position()).is_greater(mus1 + 0.1)
	# the HUD's plate: the drum's icon with its seconds
	var plate: WPlate = null
	for c in g.hud._buffs.get_children():
		if str(c.get_meta("buff", "")) == "structure:" + DRUM:
			plate = c
	assert_object(plate).is_not_null()
	assert_int(int(plate.level_text)).is_between(13, 15)
	# the look: the ring under him and the beats
	assert_int(g.drum_boost.beats).is_greater(0)
	assert_int(g.drum_boost._ring).is_greater_equal(0)
	# one use: the drum stays spent with the hero standing in it
	assert_bool(s.used).is_true()
	var left0 := Run.boost_left("structure:" + DRUM)
	g.player.global_position = at
	await get_tree().create_timer(0.6).timeout
	assert_bool(g.drum_moment.playing).is_false()
	assert_float(Run.boost_left("structure:" + DRUM)).is_less(left0)
	# the boost ends: everything back
	for tb: Dictionary in Run.timed:
		if str(tb["id"]) == "structure:" + DRUM:
			tb["until"] = Run.buff_clock() - 0.01
	await get_tree().create_timer(0.2).timeout
	assert_float(w.stat("damage")).is_equal_approx(dmg0, 0.01)
	assert_float(w.stat("knockback")).is_equal_approx(kb0, 0.01)
	assert_float(Run.haste).is_equal_approx(1.0, 0.001)
	assert_int(g.drum_boost._ring).is_equal(-1)


func test_with_a_berserk_and_a_sprint_the_drum_gives_half() -> void:
	var g := _game()
	await get_tree().create_timer(0.4).timeout
	g.director.stop()
	g.player.god = true
	var w: WeaponInstance = Run.weapon_instance("revolver")
	var dmg0 := w.stat("damage")
	var ms0 := Run.player_sheet.get_stat("move_speed", 5.0)
	var here: Vector3 = g.player.global_position
	g.apply_pickup(Registry.pickup("rage"), here)
	g.apply_pickup(Registry.pickup("sprint"), here)
	var sprint_ms := Run.player_sheet.get_stat("move_speed", 5.0)
	g.use_structure(_drum(), here)
	assert_bool(g.drum_moment.playing).is_true()
	g.drum_moment.skip()
	await get_tree().process_frame
	# Berserk x1.5 damage, x2 weapon speed; the drum beside it x1.5 and x1.5
	assert_float(w.stat("damage")).is_equal_approx(dmg0 * 1.5 * 1.5, 0.01)
	assert_float(Run.haste).is_equal_approx(2.0 * 1.5, 0.001)
	assert_float(Run.player_sheet.get_stat("move_speed", 5.0)).is_equal_approx(sprint_ms * 1.075, 0.01)
	# the Berserk and the Sprint run out: the drum gives its whole part again
	for tb: Dictionary in Run.timed:
		if str(tb["id"]) == "rage" or str(tb["id"]) == "sprint":
			tb["until"] = Run.buff_clock() - 0.01
	await get_tree().create_timer(0.2).timeout
	assert_float(w.stat("damage")).is_equal_approx(dmg0 * 2.0, 0.01)
	assert_float(Run.haste).is_equal_approx(2.0, 0.001)
	assert_float(Run.player_sheet.get_stat("move_speed", 5.0)).is_equal_approx(ms0 * 1.15, 0.01)
	assert_str(g.drum_boost.applied_key).is_equal("rage=0,sprint=0")
	# a Berserk picked up while the drum runs: x1.5 again
	g.apply_pickup(Registry.pickup("rage"), here)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(Run.haste).is_equal_approx(2.0 * 1.5, 0.001)
