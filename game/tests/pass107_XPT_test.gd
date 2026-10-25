extends GdUnitTestSuite

## Pass 107, lane XPT (Garry, 2026-10-25): "EXP drop is too high. Ridiculous increase. Make it so it follows a slightly
## faster level up progression than Stage 1, but not by much." and "Tumbleweed projectiles are not visible on stage 2,
## make em a different colour in stage 2 or something." A stage's own XP multiplier (stage_list entry `xp_mult`,
## WaveTimeline.stage_xp_mult, WaveDirector.stage_xp_mult, applied in Game._drop_from_kill); the Tumbleweed's and the
## Dust Devil's `night_tint` worn while the stage look shows a filter (ProjectileEmitter.night_look_on).


func after_test() -> void:
	Run.launch_override = {}


func _tl(list: Array) -> WaveTimeline:
	return JsonContent.timeline_from_dict({"stage_list": list})


# ---------------------------------------------------------------- the key

func test_the_stage_xp_key_is_read_with_its_default() -> void:
	var tl := _tl([{"id": "a", "length": 100}, {"id": "b", "length": 100, "xp_mult": 0.4}, {"id": "c", "length": 100, "xp_mult": -2}])
	assert_float(tl.stage_xp_mult(0)).is_equal(1.0)
	assert_float(tl.stage_xp_mult(1)).is_equal_approx(0.4, 1e-6)
	# never below 0; past the last stage, the last's
	assert_float(tl.stage_xp_mult(2)).is_equal(0.0)
	assert_float(tl.stage_xp_mult(9)).is_equal(0.0)
	assert_float(float(tl.stage_entry(1)["xp_mult"])).is_equal_approx(0.4, 1e-6)
	# a map without a stage list: 1 everywhere
	var old := JsonContent.timeline_from_dict({})
	assert_float(old.stage_xp_mult(0)).is_equal(1.0)
	assert_float(old.stage_xp_mult(2)).is_equal(1.0)


func test_red_canyon_slows_only_nightfall() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	# Sundown and Blood Moon untouched (1); Nightfall's XP cut (the value comes from the run sim, see the lane's report)
	assert_float(tl.stage_xp_mult(0)).is_equal(1.0)
	assert_float(tl.stage_xp_mult(2)).is_equal(1.0)
	var s2 := tl.stage_xp_mult(1)
	assert_float(s2).is_greater(0.0)
	assert_float(s2).is_less(1.0)


func test_the_director_hands_the_stage_xp_on() -> void:
	var d: WaveDirector = auto_free(WaveDirector.new())
	assert_float(d.stage_xp_mult()).is_equal(1.0)
	d.timeline = _tl([{"id": "a", "length": 100}, {"id": "b", "length": 100, "xp_mult": 0.5}])
	var keep := Run.stage
	Run.stage = 0
	assert_float(d.stage_xp_mult()).is_equal(1.0)
	Run.stage = 1
	assert_float(d.stage_xp_mult()).is_equal_approx(0.5, 1e-6)
	Run.stage = keep


# ---------------------------------------------------------------- a kill's XP in a real game

## A real Game at stage `s1` (1-based), its landing hurried until the run starts.
func _game_at(s1: int) -> Game:
	Run.launch_override = {"spawn": true, "stage": s1, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	g.spawn_rate = Game.SPAWN_HURRY
	var frames := 0
	while not g._run_started and frames < 900:
		await get_tree().process_frame
		frames += 1
	return g


func _gem_total(pk: PickupManager) -> float:
	var s := 0.0
	for i in range(pk.alive.size()):
		if pk.alive[i] == 1 and pk.kind[i] in [PickupManager.KIND_GEM_S, PickupManager.KIND_GEM_M, PickupManager.KIND_GEM_L]:
			s += pk.value[i]
	return s


## The XP a plain kill drops in the game: one small gem (drops small 1) of a creature whose xp_mult is 2.
func _kill_xp(g: Game) -> float:
	var def := EnemyDef.new()
	def.id = "xpt_probe"
	def.xp_mult = 2.0
	def.drops = {"small": 1.0, "medium": -1.0, "large": 0.0, "gold": 0.0}  # medium -1: no luck-made medium gem
	g.enemies.died_xp_scale = 0.0
	var before := _gem_total(g.pickups)
	g._drop_from_kill(def, g.player.global_position + Vector3(4, 0, 0), null)
	return _gem_total(g.pickups) - before


func test_a_kill_drops_the_stage_share_of_its_xp() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var g1 := await _game_at(1)
	assert_int(Run.stage).is_equal(0)
	# Stage 1 unchanged: the creature's own XP to the bit
	assert_float(_kill_xp(g1)).is_equal_approx(2.0, 1e-4)
	g1.queue_free()
	await get_tree().process_frame
	var g2 := await _game_at(2)
	assert_int(Run.stage).is_equal(1)
	assert_float(_kill_xp(g2)).is_equal_approx(2.0 * tl.stage_xp_mult(1), 1e-4)
	g2.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- the Tumbleweed at night

func _inst(id: String) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), 1)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


## The colour the emitter's shot kind is drawn in.
func _shot_albedo(g: Game, id: String) -> Color:
	var b := ProjectileEmitter.new()
	g.add_child(b)
	b.setup(_inst(id), g)
	var k := b._kind()
	var kd: Dictionary = g.projectiles.kinds[k]
	var m: Material = (kd["mmi"] as MultiMeshInstance3D).material_override
	if m == null:
		var mesh: Mesh = (kd["mm"] as MultiMesh).mesh
		m = mesh.surface_get_material(0)
	return (m as StandardMaterial3D).albedo_color


func test_the_tumbleweed_wears_its_night_colours_only_under_a_filter() -> void:
	for id: String in ["tumbleweed", "dust_devil"]:
		assert_bool(Registry.weapon(id).params.get("night_tint") is Dictionary).override_failure_message(id + " has no night_tint").is_true()
	var g1 := await _game_at(1)
	assert_bool(ProjectileEmitter.stage_filter_on(g1)).is_false()
	# Sundown: the day's dark brown ball and the black Dust Devil, as before
	assert_float(_shot_albedo(g1, "tumbleweed").v).is_less(0.4)
	assert_float(_shot_albedo(g1, "dust_devil").v).is_less(0.08)
	g1.queue_free()
	await get_tree().process_frame
	var g2 := await _game_at(2)
	assert_bool(ProjectileEmitter.stage_filter_on(g2)).is_true()
	var want := Color(str((Registry.weapon("tumbleweed").params["night_tint"] as Dictionary)["albedo"]))
	var got := _shot_albedo(g2, "tumbleweed")
	assert_bool(Color(got.r, got.g, got.b).is_equal_approx(Color(want.r, want.g, want.b))).override_failure_message("night weed %s" % got).is_true()
	assert_float(got.v).is_greater(0.8)
	assert_float(_shot_albedo(g2, "dust_devil").v).is_greater(0.7)
	g2.queue_free()
	await get_tree().process_frame
	var g3 := await _game_at(3)
	assert_bool(ProjectileEmitter.stage_filter_on(g3)).is_true()
	assert_float(_shot_albedo(g3, "tumbleweed").v).is_greater(0.8)
	g3.queue_free()
	await get_tree().process_frame


func test_a_world_without_a_stage_look_plays_the_day() -> void:
	var n: Node = auto_free(Node.new())
	assert_bool(ProjectileEmitter.stage_filter_on(n)).is_false()
	assert_bool(ProjectileEmitter.stage_filter_on(null)).is_false()
