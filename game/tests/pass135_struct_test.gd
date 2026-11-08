## Pass 135 (Garry: "Barrels aren't clear, make them glint occasionally"; "All Structures that can be interacted with, can be
## interacted with in 3 seconds ... Make the teleport smaller, make the animation be much more noticeable as Player is
## activating it ... place 4 to 6 more of them all around the edges on opposite ends of the map ... not colliding with the
## walls"; "Increase all pierce of Revolver by 1 (damage still drops though)").
extends GdUnitTestSuite


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	get_tree().paused = false
	Run.forced_map_seed = 0
	Run.arena = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _run_game(seed_: int) -> Game:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": seed_, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


# ---------------------------------------------------------------- 3 seconds for every structure

func test_every_structure_you_stand_in_takes_three_seconds() -> void:
	var n := 0
	for d: StructureDef in Registry.structures.values():
		if d.hidden:
			continue
		n += 1
		assert_float(d.interact_time).override_failure_message(d.id + " is not 3 s").is_equal_approx(3.0, 0.001)
	assert_int(n).is_greater_equal(8)


# ---------------------------------------------------------------- the Revolver's pierce

func test_the_revolver_pierces_one_more_at_every_level_and_its_evolution_too() -> void:
	var before := [1, 1, 2, 2, 2]   # pass 134's pierce at levels 1-5
	for lv in range(1, 6):
		var inst := WeaponInstance.new(Registry.weapon("revolver"), lv)
		inst.rebuild(Run.player_sheet, [inst])
		assert_int(inst.stat_int("pierce", 0)).is_equal(before[lv - 1] + 1)
	var gold := WeaponInstance.new(Registry.weapon("golden_revolver"), 1)
	gold.rebuild(Run.player_sheet, [gold])
	assert_int(gold.stat_int("pierce", 0)).is_equal(3)
	# the drop-off still plays: the second in the row takes less than the first
	var pf: Dictionary = Registry.weapon("revolver").params["pierce_falloff"]
	assert_float(ProjectileManager.falloff_factor(pf, 2)).is_less(ProjectileManager.falloff_factor(pf, 1))


# ---------------------------------------------------------------- the Teleport: smaller, its charge, the rim's

func test_the_teleport_is_smaller_and_has_a_charge_and_a_rim_set() -> void:
	var t: StructureDef = Registry.structure("teleport")
	assert_float(t.height).is_equal_approx(2.0, 0.001)
	assert_float(t.radius).is_equal_approx(1.4, 0.001)
	assert_bool(t.params.get("charge") is Dictionary).is_true()
	var e: Dictionary = t.params["edge"]
	assert_int(int(e["min"])).is_equal(4)
	assert_int(int(e["max"])).is_equal(6)
	assert_object(StructureManager._pair([1, 2], Vector2.ZERO)).is_equal(Vector2(1, 2))
	assert_object(StructureManager._pair(3, Vector2.ZERO)).is_equal(Vector2(3, 3))
	assert_object(StructureManager._pair(null, Vector2(5, 6))).is_equal(Vector2(5, 6))


func test_four_to_six_teleports_stand_on_the_rim_spread_round_it_clear_of_the_wall() -> void:
	var g := _run_game(11)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	var t: StructureDef = Registry.structure("teleport")
	var e: Dictionary = t.params["edge"]
	var plan: Dictionary = Run.map.timeline.structures
	var arena: float = g.map.arena_radius
	var seen := {}
	# a seed left by another suite would place every trial alike (StructureManager.setup seeds from Run.rng_seed)
	var keep_seed: int = Run.rng_seed
	Run.rng_seed = 0
	for trial in range(8):
		var sm: StructureManager = g.structures
		if trial > 0:
			sm = StructureManager.new()
			g.add_child(sm)
			sm.setup(g, g.map, plan)
		var edges := sm.edge_spots()
		assert_int(edges.size()).is_between(4, 6)
		seen[edges.size()] = true
		var all := sm.teleport_spots()
		var mean := Vector2.ZERO
		for p: Vector3 in edges:
			var r := Vector2(p.x, p.z).length()
			# on the rim: inset in from the wall, never more than EDGE_IN further in
			assert_float(r).is_less_equal(arena - float(e["inset"]) + 0.01)
			assert_float(r).is_greater_equal(arena - float(e["inset"]) - StructureManager.EDGE_IN - 0.01)
			# the whole ring is where the outlaw can stand (he stops 1.5 m from the wall)
			assert_float(r + t.radius).is_less(arena - 1.5)
			assert_bool(g.map.in_water(p)).is_false()
			for o: Vector3 in g.map.obstacles:
				assert_float(Vector2(p.x - o.x, p.z - o.y).length()).is_greater_equal(o.z)
			var others := all.filter(func(q: Vector3) -> bool: return q != p)
			assert_float(StructureManager.nearest_distance(p, others)).is_greater_equal(float(e["clear"]) - 0.01)
			mean += Vector2(p.x, p.z).normalized()
		# spread round the circle: they face each other, so their directions nearly cancel
		assert_float(mean.length() / float(edges.size())).is_less(0.45)
		if trial > 0:
			sm.queue_free()
			await get_tree().process_frame
	Run.rng_seed = keep_seed
	assert_int(seen.size()).is_greater_equal(2)


func test_charging_a_teleport_grows_its_swirl_opens_the_vortex_and_turns_smoothly() -> void:
	var g := _run_game(11)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	var s: StructureManager.Structure = null
	for st: StructureManager.Structure in g.structures.items:
		if st.def.effect_kind == "teleport" and st.portal_mat != null:
			s = st
			break
	assert_object(s).is_not_null()
	assert_object(s.vortex).is_not_null()
	assert_bool(s.vortex.visible).is_false()
	var size0 := s.portal_size
	var spin0 := s.spin
	s.progress = 0.9
	g.structures._tick_portal(s, 0.05, true, 100.0)
	assert_bool(s.vortex.visible).is_true()
	assert_float(float(s.portal_mat.get_shader_parameter("size"))).is_greater(size0 * 1.3)
	assert_float(float(s.portal_mat.get_shader_parameter("speed"))).is_equal(0.0)
	# the turn is the script's: a frame moves it by speed x delta, never a jump
	var turned := fposmod(s.spin - spin0, TAU)
	assert_float(turned).is_between(0.05 * 2.2, 0.05 * 20.0 + 0.001)
	s.progress = 0.0
	g.structures._tick_portal(s, 0.05, false, 100.0)
	assert_bool(s.vortex.visible).is_false()


# ---------------------------------------------------------------- the barrels' glint

func test_the_glint_block_fills_and_clamps() -> void:
	var d := BarrelSpawns.glint_of({})
	assert_float(float(d["strength"])).is_equal_approx(0.85, 0.001)
	assert_float(float(d["every"])).is_equal_approx(6.0, 0.001)
	var o := BarrelSpawns.glint_of({"glint": {"strength": 3, "every": 0.1, "length": 9, "width": 0}})
	assert_float(float(o["strength"])).is_equal(1.0)
	assert_float(float(o["every"])).is_equal(0.5)
	assert_float(float(o["length"])).is_equal(0.5)
	assert_float(float(o["width"])).is_equal(0.01)
	assert_float(float(BarrelSpawns.glint_of({"glint": {"strength": 0}})["strength"])).is_equal(0.0)


func test_every_barrel_material_glints_and_the_props_do_not() -> void:
	var g := _run_game(11)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	var mats: Array = g.barrels.materials()
	assert_int(mats.size()).is_greater(0)
	for m: ShaderMaterial in mats:
		assert_float(float(m.get_shader_parameter("glint"))).is_equal_approx(0.85, 0.001)
	# the shader's own default is off, so every other prop is as before
	var sh: Shader = load("res://core/shaders/prop_billboard.gdshader")
	assert_float(float(RenderingServer.shader_get_parameter_default(sh.get_rid(), "glint"))).is_equal(0.0)
