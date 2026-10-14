extends GdUnitTestSuite

## Pass 64, lane PL (Garry, 2026-10-10: "Coin Extraction needs to be adjusted. It's too harsh. More Balloons - ... the
## balloon structure ... actually returns every 30-60 seconds after it's used. It spawns in a random place ... fly down
## from the sky (basically a reverse of the fly away animation) ... Signs don't suddenly start showing direction towards
## the newly spawned Balloon"; "The start of the run - the hero descending from the sky look janky ... facing us when
## coming down, but then immediately switches back when they land ... a jerky effect ... make it so the hero is facing us
## when we land ... if the player tries to move or press anything while the sequence is happening, it will jerk to the
## end ... let's try to speed up the sequence"; "Rust Mutation 3d object effect looks a bit too gruesome").

const STEP := 1.0 / 60.0


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


## The real game on Red Canyon with the spawn beam, its own clock stopped (the test steps the beam by hand).
func _beam_game() -> Game:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "spawn": true, "analytics": false})
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	g.set_process(false)
	return g


func _press(g: Game, at: Vector2, down: bool = true, index: int = 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = down
	ev.position = at
	g._unhandled_input(ev)


# ---------------------------------------------------------------- the landing

func test_the_hero_faces_us_all_the_way_down_and_lands_softly_on_the_sand() -> void:
	var g := _beam_game()
	# the warm-up's 0.3 s timer done first (it calls into the game: a game freed before it fires errors)
	await get_tree().create_timer(0.35).timeout
	assert_bool(g.spawning).is_true()
	var p: Player = g.player
	var ground: float = g.map.height_at(p.global_position.x, p.global_position.z)
	var last_y := p.global_position.y
	var last_v := 0.0
	var max_dv := 0.0
	var front := true
	var steps := 0
	while g.spawning and steps < 600:
		g._tick_spawn(STEP)
		steps += 1
		var v := (p.global_position.y - last_y) / STEP
		if steps > 1:
			max_dv = maxf(max_dv, absf(v - last_v))
		last_v = v
		last_y = p.global_position.y
		if p.visible and not p.sprite.animation.ends_with("_f"):
			front = false
	assert_bool(g.spawning).is_false()
	assert_bool(front).is_true()
	# on the sand itself, with no speed left (smootherstep), and no jolt between two frames on the way
	assert_float(p.global_position.y).is_equal_approx(ground, 0.02)
	assert_float(absf(last_v)).is_less(0.3)
	assert_float(max_dv).is_less(0.6)
	# and he stays put and facing us once the physics take him (no half-metre drop, no snap to his back)
	for k in 20:
		await get_tree().physics_frame
	assert_float(p.global_position.y).is_equal_approx(ground, 0.06)
	assert_str(p.sprite.animation).ends_with("_f")
	# a soft squash rather than a stretched drop, and no blinking through the landing's safety
	assert_bool(p.quiet_invuln or p.invuln <= 0.0).is_true()
	assert_bool(p.sprite.visible).is_true()


func test_the_landing_squash_starts_from_nothing_and_dies_away() -> void:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	p.land_settle(0.45)
	assert_float(p.land_squash()).is_equal_approx(0.0, 0.001)
	var deepest := 0.0
	var t := 0.0
	while t < 0.45:
		p._land_t = maxf(p._land_t - STEP, 0.0)
		t += STEP
		deepest = maxf(deepest, p.land_squash())
	assert_float(deepest).is_between(0.05, 0.12)
	assert_float(p.land_squash()).is_equal_approx(0.0, 0.001)


func test_the_fall_curve_has_no_speed_at_either_end() -> void:
	assert_float(Game.spawn_ease(0.0)).is_equal(0.0)
	assert_float(Game.spawn_ease(1.0)).is_equal(1.0)
	var d0 := (Game.spawn_ease(0.01) - Game.spawn_ease(0.0)) / 0.01
	var d1 := (Game.spawn_ease(1.0) - Game.spawn_ease(0.99)) / 0.01
	assert_float(d0).is_less(0.01)
	assert_float(d1).is_less(0.01)


func test_a_press_speeds_the_sequence_up_instead_of_skipping_it() -> void:
	var g := _beam_game()
	# the warm-up's 0.3 s timer done first (it calls into the game: a game freed before it fires errors)
	await get_tree().create_timer(0.35).timeout
	# the tap that started the run (in the first SPAWN_HURRY_AFTER) changes nothing
	_press(g, Vector2(540, 1400))
	_press(g, Vector2(540, 1400), false)
	assert_float(g.spawn_rate).is_equal(1.0)
	while g._spawn_t < 1.0:
		g._tick_spawn(STEP)
	# a finger down a second in: still in the air, the rest three times as fast
	_press(g, Vector2(540, 1400))
	assert_bool(g.spawning).is_true()
	assert_float(g.spawn_rate).is_equal(Game.SPAWN_HURRY)
	var before: float = g._spawn_t
	g._tick_spawn(STEP)
	# the speed-up eases in over a few frames (SPAWN_HURRY_RAMP): quicker at once, never a jump
	assert_float(g._spawn_t - before).is_between(STEP * 1.05, STEP * Game.SPAWN_HURRY)
	var steps := 1
	var y_prev: float = g.player.global_position.y
	var v_prev := 0.0
	var max_dv := 0.0
	while g.spawning and steps < 600:
		g._tick_spawn(STEP)
		steps += 1
		var v := (g.player.global_position.y - y_prev) / STEP
		if steps > 2:
			max_dv = maxf(max_dv, absf(v - v_prev))
		v_prev = v
		y_prev = g.player.global_position.y
	# the remaining second of the fall in about a third of the time (the ease-in costs a few frames), never a jump to
	# the end, and the fall's speed never steps by more than a few metres a second between two frames
	var want := (Game.SPAWN_HOLD + Game.SPAWN_FALL - before) / Game.SPAWN_HURRY / STEP
	assert_float(float(steps)).is_between(want - 1.0, want + 5.0)
	assert_float(max_dv).is_less(8.0)
	# the finger still down walks him off at once
	assert_int(g.player.input.active_index).is_equal(0)
	assert_bool(g.player.input.wants_move).is_true()


func test_a_finger_lifted_before_the_landing_does_not_start_the_stick() -> void:
	var g := _beam_game()
	# the warm-up's 0.3 s timer done first (it calls into the game: a game freed before it fires errors)
	await get_tree().create_timer(0.35).timeout
	while g._spawn_t < 1.2:
		g._tick_spawn(STEP)
	_press(g, Vector2(540, 1400))
	_press(g, Vector2(540, 1400), false)
	while g.spawning:
		g._tick_spawn(STEP)
	assert_bool(g.player.input.wants_move).is_false()
	assert_int(g.player.input.active_index).is_equal(-1)


func test_a_drag_hurries_too() -> void:
	var g := _beam_game()
	# the warm-up's 0.3 s timer done first (it calls into the game: a game freed before it fires errors)
	await get_tree().create_timer(0.35).timeout
	while g._spawn_t < 0.6:
		g._tick_spawn(STEP)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(500, 1300)
	g._unhandled_input(drag)
	assert_float(g.spawn_rate).is_equal(Game.SPAWN_HURRY)


func test_a_key_hurries_too() -> void:
	var g2 := _beam_game()
	# the warm-up's 0.3 s timer done first (it calls into the game: a game freed before it fires errors)
	await get_tree().create_timer(0.35).timeout
	while g2._spawn_t < 0.6:
		g2._tick_spawn(STEP)
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	g2._unhandled_input(key)
	assert_float(g2.spawn_rate).is_equal(Game.SPAWN_HURRY)
	assert_bool(g2.spawning).is_true()


# ---------------------------------------------------------------- the Strongbox comes back

## The real game on Red Canyon, the instant start (no beam).
func _run_game() -> Game:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false})
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func _bank(g: Game):
	for s in g.structures.items:
		if s.def.id == "gold_bank":
			return s
	# pass 70 (re-pinned): the Strongbox is retired (hidden: it never spawns, pass70_econ_test), its return primitive
	# (params.respawn) is kept, so the test stands one itself at a fair spot
	var sm: StructureManager = g.structures
	return sm._spawn(Registry.structure("gold_bank"), sm.find_spot())


func test_the_strongbox_has_a_return_window_of_30_to_60_seconds() -> void:
	var def: StructureDef = Registry.structure("gold_bank")
	var rp: Dictionary = def.params.get("respawn", {})
	assert_float(float(rp.get("min", 0))).is_equal(30.0)
	assert_float(float(rp.get("max", 0))).is_equal(60.0)
	assert_str(str(def.params.get("spent", ""))).is_equal("fly_away")


func test_a_used_strongbox_returns_at_a_fresh_spot_and_floats_down() -> void:
	var g := _run_game()
	await get_tree().create_timer(0.3).timeout
	var sm: StructureManager = g.structures
	var first = _bank(g)
	assert_object(first).is_not_null()
	var signs: Node = g.get_node_or_null("Signs")
	var aimed: Array = []
	if signs:
		for rec: Dictionary in signs.arms:
			aimed.append(rec["structure"])
	var count_before := sm.items.size()
	Run.run_gold = 0
	sm._use(first)
	sm._on_flown(first)
	assert_float(sm.return_t).is_between(30.0, 60.0)
	# its clock stands while the run is paused
	var due := sm.return_t
	g.paused = true
	sm._process(1.0)
	assert_float(sm.return_t).is_equal(due)
	g.paused = false
	# a second box flying off meanwhile does not count another return
	sm._on_flown(first)
	assert_float(sm.return_t).is_equal(due)
	sm._process(due + 0.01)
	assert_int(sm.returns).is_equal(1)
	assert_int(sm.items.size()).is_equal(count_before + 1)
	var back = sm.returner
	assert_object(back).is_not_null()
	assert_bool(back != first).is_true()
	assert_bool(back.arriving).is_true()
	assert_bool(back.ring.visible).is_false()
	# a fresh, fair spot: the start's band, clear of the hero, of the water and of every structure still standing
	var at: Vector3 = back.global_position
	var r := Vector2(at.x, at.z).length()
	assert_float(r).is_between(g.map.arena_radius * 0.3 - 0.01, g.map.arena_radius * 0.86 + 0.01)
	var hp: Vector3 = g.player.global_position
	assert_float(Vector2(at.x - hp.x, at.z - hp.z).length()).is_greater_equal(StructureManager.RETURN_HERO_CLEAR)
	assert_bool(g.map.in_water(at)).is_false()
	for s in sm.items:
		if s != back and s != first:
			assert_float(Vector2(at.x - s.global_position.x, at.z - s.global_position.z).length()).is_greater_equal(sm._spacing * 0.5)
	# high up at first, coming down all the way, slowing as it lands; not usable until it stands
	var h0: float = back.visual.position.y - back.rest.y
	assert_float(h0).is_greater(StructureManager.DESCEND_HEIGHT * 0.9)
	g.player.global_position = at
	var last := h0
	var falling := true
	var t := 0.0
	var last_speed := 0.0
	while back.arriving and t < 10.0:
		sm._process(STEP)
		t += STEP
		var h: float = back.visual.position.y - back.rest.y
		if h > last + 0.0001:
			falling = false
		last_speed = (last - h) / STEP
		last = h
		if back.arriving:
			assert_bool(back.used).is_false()
			assert_float(back.progress).is_equal(0.0)
	assert_bool(falling).is_true()
	assert_float(t).is_equal_approx(StructureManager.DESCEND_TIME + StructureManager.SETTLE_TIME, 0.05)
	assert_float(last_speed).is_less(0.3)
	assert_bool(back.arriving).is_false()
	assert_bool(back.ring.visible).is_true()
	assert_vector(back.visual.position).is_equal_approx(back.rest, Vector3(0.001, 0.001, 0.001))
	# and then a Strongbox like any other: standing in it banks
	sm._process(back.def.interact_time + 0.2)
	assert_bool(back.used).is_true()
	# the signs never turn to it: no arm points at the new box, and the one at the first box is blank
	if signs:
		signs.check_used(false)
		for rec: Dictionary in signs.arms:
			assert_bool(rec["structure"] == back).is_false()
			if rec["structure"] == first:
				assert_bool(bool(rec["blank"])).is_true()
		var now: Array = []
		for rec: Dictionary in signs.arms:
			now.append(rec["structure"])
		assert_array(now).is_equal(aimed)


func test_only_one_return_at_a_time() -> void:
	var g := _run_game()
	await get_tree().create_timer(0.3).timeout
	var sm: StructureManager = g.structures
	var first = _bank(g)
	sm._on_flown(first)
	sm._process(sm.return_t + 0.01)
	var back = sm.returner
	assert_object(back).is_not_null()
	# the first box (or any other) flying off while the one that came back stands unused counts nothing
	sm._on_flown(first)
	assert_float(sm.return_t).is_equal(-1.0)
	# once the returned box has been used and has flown, the next one is due
	back.used = true
	sm._on_flown(back)
	assert_float(sm.return_t).is_between(30.0, 60.0)


func test_every_return_spot_keeps_the_rules() -> void:
	var g := _run_game()
	await get_tree().create_timer(0.3).timeout
	var sm: StructureManager = g.structures
	var hp: Vector3 = g.player.global_position
	var standing: Array = []
	# pass 75 (re-pinned): since pass 73 a structure standing its own count (a Totem Pole, `per_map`) is kept at its own
	# spacing (half of it at the most relaxed), not the map's; this test still held them to the map's 22 m and failed now
	# and then, when the search had relaxed and landed 7-11 m from a pole
	var apart: Array = []
	for s in sm.items:
		if StructureManager.per_map_range(s.def) == Vector2i(-1, -1):
			standing.append(s.global_position)
		else:
			apart.append([s.global_position, sm.own_spacing(s.def)])
	var covers: Array = BarrelField.covers_of(g, g.map)
	for k in 40:
		var p := sm.find_spot()
		assert_bool(p != Vector3.INF).is_true()
		assert_float(Vector2(p.x - hp.x, p.z - hp.z).length()).is_greater_equal(StructureManager.RETURN_HERO_CLEAR)
		assert_bool(sm.start_spot_ok(p, standing, sm._spacing, 0.5)).is_true()
		for q: Array in apart:
			var at: Vector3 = q[0]
			assert_float(Vector2(p.x - at.x, p.z - at.z).length()).is_greater_equal(float(q[1]) * 0.5 - 0.001)
		assert_bool(BarrelField.in_cover(covers, Vector2(p.x, p.z), 1.5)).is_false()
		assert_float(p.y).is_equal_approx(g.map.height_at(p.x, p.z), 0.01)


# ---------------------------------------------------------------- Rust, less gruesome

func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


func test_rust_reads_as_old_orange_rust_not_meat() -> void:
	var rp: Dictionary = Registry.mutation("rust").params["rust"]
	var rust := Color(str(rp["rust_color"]))
	var pit := Color(str(rp["pit_color"]))
	# lighter and more orange than pass 61's (#B8551A / #5C2410): green up against red, so less blood-red
	assert_float(_lum(rust)).is_greater(_lum(Color("#B8551A")) + 0.02)
	assert_float(rust.g / rust.r).is_greater(Color("#B8551A").g / Color("#B8551A").r)
	assert_float(_lum(pit)).is_greater(_lum(Color("#5C2410")) + 0.1)
	assert_float(pit.g / pit.r).is_greater(Color("#5C2410").g / Color("#5C2410").r)
	# steel showing (dull, never white marbling), fewer and fainter pits, a thinner rim, fewer and smaller flakes in light
	# colours
	assert_float(float(rp["amount"])).is_less(0.75)
	assert_float(float(rp["steel"])).is_less_equal(0.8)
	assert_float(float(rp["pits"])).is_less_equal(0.35)
	assert_float(float(rp["rim"])).is_less_equal(0.12)
	assert_float(float(rp["flakes"])).is_less_equal(6.0)
	assert_float(float(rp["flake_size"])).is_less(1.0)
	for c in rp["flake_colors"]:
		assert_float(_lum(Color(str(c)))).is_greater(0.45)
	var src := FileAccess.get_file_as_string("res://core/shaders/rust_blade.gdshader")
	assert_str(src).contains("const float PIT_FROM = 0.9;")
	# the Saw Halo's patina goes the same way
	var pat: Dictionary = Registry.weapon("saw_halo").params["rust_patina"]
	assert_float(float(pat["amount"])).is_less_equal(0.3)
	assert_float(float(pat["pits"])).is_less_equal(0.15)
	assert_float(float(pat["rim"])).is_less_equal(0.06)


func test_rust_flakes_take_the_mutations_colours() -> void:
	var rp := {"flake_colors": ["#C9773D"]}
	assert_bool(Orbiter.flake_color(rp).is_equal_approx(Color("#C9773D"))).is_true()
	assert_float(Orbiter.flake_color({}).a).is_equal(0.0)
