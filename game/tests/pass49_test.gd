extends GdUnitTestSuite

## Pass 49 (Garry's seventh list), the lead's parts: the arena's buffs run out (Pollen lasted forever there), a weapon's
## plate draws a dot only for a mutation held, the camera cutout's ink band over every screen, the hero's speed trails
## under his painting, the Blunderbuss's bell open at the muzzle, the signpost and the yucca kept out of the desert, and
## bigger skeletons. (Hot Streak's new rules are in pass48_items_test, the HUD's solid slots in pass48_ui_test.)

const FAKE_GAME := """extends Node
var paused := false
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _start() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.arena = false
	Settings.top_inset = -1
	Run.forced_map_seed = 0


# ---------------------------------------------------------------- the arena's buffs run out

func test_a_buff_runs_out_in_the_arena_where_the_director_holds_the_clock() -> void:
	_start()
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = g
	d.map = Registry.map("red_canyon")
	d.timeline = d.map.timeline
	d.running = false
	Run.add_timed_effects("pollen:hornet_nest", "Pollen", [], 5.0, true)
	assert_float(Run.boost_left("pollen:hornet_nest")).is_equal_approx(5.0, 0.001)
	# out of the arena a held director stops every clock (the run is over, or not begun)
	d._process(2.0)
	assert_float(Run.boost_left("pollen:hornet_nest")).is_equal_approx(5.0, 0.001)
	# in the arena the stage clock holds and the buffs' clock runs on
	Run.arena = true
	d._process(2.0)
	assert_float(Run.elapsed).is_equal(0.0)
	assert_float(Run.boost_left("pollen:hornet_nest")).is_equal_approx(3.0, 0.001)
	d._process(3.5)
	Run.tick_timed()
	assert_float(Run.boost_left("pollen:hornet_nest")).is_equal(0.0)
	assert_bool(Run.timed.any(func(tb) -> bool: return str(tb["id"]) == "pollen:hornet_nest")).is_false()
	# a paused arena holds it too
	Run.add_timed_effects("rage", "Berserk", [], 5.0)
	g.paused = true
	d._process(2.0)
	assert_float(Run.boost_left("rage")).is_equal_approx(5.0, 0.001)
	Run.end()


# ---------------------------------------------------------------- dots only for what is held

func test_a_plate_draws_a_dot_for_each_mutation_held_and_none_for_the_open_ones() -> void:
	var p: WPlate = auto_free(WPlate.new().for_def(Registry.weapon("peashooter"), 72.0, false, 2))
	add_child(p)
	# none held: nothing drawn, though the path is three long
	p.set_dots(Vector2i(0, 3))
	assert_object(p.dots).is_equal(Vector2i(0, 3))
	# one held: one dot, in the middle of the top edge
	p.set_dots(Vector2i(1, 3))
	assert_float(p.held_center(0).x).is_equal_approx(36.0, 0.01)
	assert_float(p.held_center(0).y).is_equal_approx(p.border * 0.5, 0.01)
	# two held: a pair centred on the plate
	p.set_dots(Vector2i(2, 3))
	assert_float(p.held_center(0).x + p.held_center(1).x).is_equal_approx(72.0, 0.01)
	assert_float(p.held_center(1).x - p.held_center(0).x).is_equal_approx(p.dot_size() + maxf(roundf(p.dot_size() * 0.2), 2.0), 0.01)
	# all three: the row the path would make
	p.set_dots(Vector2i(3, 3), true)
	for i in 3:
		assert_float(p.held_center(i).x).is_equal_approx(p.dot_center(i).x, 0.01)
	await get_tree().process_frame


# ---------------------------------------------------------------- the cutout's band on every screen

func test_the_cutout_band_paints_every_screen_above_everything() -> void:
	var band := get_tree().root.get_node_or_null("CutoutBand")
	assert_object(band).is_not_null()
	assert_bool(band is CanvasLayer).is_true()
	# above the game's UI and the scene fade
	assert_int((band as CanvasLayer).layer).is_greater(100)
	var rect := band.get_node("Band") as ColorRect
	assert_int(rect.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(rect.color.is_equal_approx(W.INK)).is_true()
	# as tall as the cutout, and gone without one
	Settings.top_inset = 130
	band.call("_fit")
	assert_float(rect.offset_bottom).is_equal(130.0)
	assert_bool(rect.visible).is_true()
	assert_float(float(band.call("height"))).is_equal(130.0)
	Settings.top_inset = 0
	band.call("_fit")
	assert_bool(rect.visible).is_false()
	assert_float(float(band.call("height"))).is_equal(0.0)


# ---------------------------------------------------------------- speed trails under the hero

func test_the_speed_trails_draw_before_the_heros_second_pass_and_every_other_effect_after() -> void:
	assert_int(Fx.speed_ribbon_material().render_priority).is_equal(Fx.SPEED_TRAIL_PRIORITY)
	assert_int(Fx.SPEED_TRAIL_PRIORITY).is_less(BillboardSprite.OVER_PRIORITY)
	assert_int(BillboardSprite.OVER_PRIORITY).is_less(0)
	# the other swept trails keep their place
	assert_int(Fx.glow_ribbon_material().render_priority).is_equal(0)
	# the trails and the wind wear it
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	fx.speed_trail("blue", Vector3.ZERO, 0.05, true)
	fx.speed_trail("blue", Vector3(0, 0, -1), 0.05, true)
	var tr := fx.get_node("Trail_blue") as MeshInstance3D
	assert_object(tr.material_override).is_same(Fx.speed_ribbon_material())
	# the hero's painting has its pass over them, in the see-through queue, the same frame as the first
	var s: BillboardSprite = auto_free(BillboardSprite.new())
	s.enable_outline()
	s.enable_over_trails()
	add_child(s)
	var over: ShaderMaterial = s._over
	assert_object(over).is_not_null()
	assert_int(over.render_priority).is_equal(BillboardSprite.OVER_PRIORITY)
	assert_object((s.material_override as ShaderMaterial).next_pass).is_same(s._sil)
	assert_object(s._sil.next_pass).is_same(over)
	s.set_flip(true)
	s.set_tint(Color(0.5, 0.6, 0.7))
	assert_float(float(over.get_shader_parameter("flip"))).is_equal(1.0)
	assert_bool((over.get_shader_parameter("tint") as Color).is_equal_approx(Color(0.5, 0.6, 0.7))).is_true()
	# the hero's own sprite gets it
	var src := FileAccess.get_file_as_string("res://player/Player.gd")
	assert_bool(src.contains("sprite.enable_over_trails()")).is_true()


# ---------------------------------------------------------------- the Blunderbuss's bell

func test_the_blunderbuss_bell_flares_out_at_the_muzzle_with_a_dark_mouth() -> void:
	var v: Node3D = auto_free((load("res://content/evolutions/blunderbuss/blunderbuss_visual.tscn") as PackedScene).instantiate())
	var bell := v.get_node("Held/Bell") as MeshInstance3D
	var cm := bell.mesh as CylinderMesh
	# the cylinder's top (local +Y) points down the barrel (-Z): the wide end is the muzzle
	var top_dir := bell.transform.basis.y.normalized()
	assert_float(top_dir.z).is_less(-0.99)
	assert_float(cm.top_radius).is_greater(cm.bottom_radius * 1.8)
	# the narrow end takes both barrels in
	assert_float(cm.bottom_radius).is_greater_equal(0.085)
	var mouth := v.get_node("Held/BellMouth") as MeshInstance3D
	assert_object(mouth).is_not_null()
	# just in front of the bell's wide face, a little narrower so a gold rim shows
	assert_float(mouth.position.z).is_less(bell.position.z - cm.height * 0.5)
	assert_float((mouth.mesh as CylinderMesh).top_radius).is_less(cm.top_radius)
	assert_float(((mouth.material_override as StandardMaterial3D).albedo_color).v).is_less(0.15)


# ---------------------------------------------------------------- no signposts, no yuccas

func test_the_signpost_and_the_yucca_stay_out_of_the_desert() -> void:
	var pf: PropField = auto_free(PropField.new())
	pf.setup()
	for id in ["signpost", "yucca"]:
		assert_bool(pf.has(id)).override_failure_message(id).is_true()
		assert_bool(pf.is_hidden(id)).override_failure_message(id).is_true()
	assert_bool(pf.is_hidden("ocotillo")).is_false()
	# three deserts, not one of either
	for seed in [5, 6, 7]:
		Run.forced_map_seed = seed
		_start()
		var m: MapBase = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
		add_child(m)
		var props: PropField = m.get("props")
		assert_int(props.placed.size()).is_greater(60)
		for row: Dictionary in props.placed:
			assert_bool(str(row["id"]) in ["signpost", "yucca"]).override_failure_message("seed %d placed %s" % [seed, row["id"]]).is_false()
		m.queue_free()
		await get_tree().process_frame
	Run.end()


# ---------------------------------------------------------------- bigger skeletons

func test_the_skeletons_stand_near_the_heros_height() -> void:
	var sk: EnemyDef = Registry.enemy("skeleton")
	var kn: EnemyDef = Registry.enemy("skeleton_knight")
	assert_float(sk.size).is_equal(1.75)
	assert_float(kn.size).is_equal(1.85)
	assert_float(kn.size).is_greater(sk.size)
	# wider with it, so they are as easy to hit and keep their room in a crowd
	assert_float(sk.radius).is_equal(0.52)
	assert_float(kn.radius).is_equal(0.54)


# ---------------------------------------------------------------- the pause screen names a buff

func test_the_stats_breakdown_names_a_timed_buff_by_its_label() -> void:
	_start()
	Run.add_timed_effects("pollen:hornet_nest", "Pollen", [Effect.make("amount", "mul", 3.0, "weapon:hornet_nest")], 5.0, true)
	Run.add_timed_effects("rage", "Berserk", [Effect.make("haste", "mul", 1.0, "player")], 5.0)
	var ps: PauseScreen = auto_free(PauseScreen.new())
	assert_str(ps._source_name("buff:pollen:hornet_nest")).is_equal("Pollen")
	assert_str(ps._source_name("buff:rage")).is_equal("Berserk")
	# gone from the clock, a pickup's buff still says the pickup's name
	Run.timed.clear()
	assert_str(ps._source_name("buff:rage")).is_equal(Registry.pickup("rage").display_name)
	assert_str(ps._source_name("passive:brawn")).is_equal(Registry.passive("brawn").display_name)
	Run.end()
