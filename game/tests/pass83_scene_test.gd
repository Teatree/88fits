extends GdUnitTestSuite

## Pass 83, lane SCENE (Garry: "Main Menu background scene, looks barren. Can you place the cactuses and other environment
## art that we have in a way that present a nicely composed scene to look at. Furthermore, add some variation to our
## environment art - a variant of agave.png, barrel_cactus.png, ocotillo.png, boulder.png, desert_bush.png, dead_shrub,
## (2 more joshua_tree.png) and another small bushlike thing - add a simple shadow underneath the environment 2.5d
## things. Make sure that they make sense visually. - barrels, signs, and structures too."): the variants and the new
## brittlebush registered and mixed in by the spot, every painting with a ground shadow, the barrels, signs and
## structures on theirs, the title's composed scene.

const MANIFEST := "res://art/sprites/props/props.json"
const STAGE := preload("res://ui/TitleStage.gd")
const RED_CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")
const VARIANTS := {"agave_b": "agave", "barrel_cactus_b": "barrel_cactus", "ocotillo_b": "ocotillo", "boulder_b": "boulder",
	"desert_bush_b": "desert_bush", "dead_shrub_b": "dead_shrub", "joshua_tree_b": "joshua_tree", "joshua_tree_c": "joshua_tree"}

var _keep_style := ""


func before_test() -> void:
	_keep_style = Settings.menu_style


func after_test() -> void:
	STAGE.forget()
	Settings.menu_style = _keep_style
	Run.forced_map_seed = 0
	Run.end()


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))


func _field() -> PropField:
	var pf: PropField = auto_free(PropField.new())
	pf.setup()
	return pf


func _canyon(ms: int) -> MapBase:
	Run.forced_map_seed = ms
	Run.end()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var m: MapBase = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	return m


# ---------------------------------------------------------------- the variants

func test_every_variant_is_painted_and_registered_with_its_kind() -> void:
	var man := _manifest()
	var pf := _field()
	for id: String in VARIANTS.keys():
		var base: String = VARIANTS[id]
		assert_bool(man.has(id)).override_failure_message("no manifest entry for " + id).is_true()
		assert_str(str(man[id].get("variant_of", ""))).is_equal(base)
		assert_bool(ResourceLoader.exists("res://art/sprites/props/%s.png" % id)).override_failure_message(id).is_true()
		assert_bool(pf.has(id)).is_true()
		assert_str(pf.kind_of(id)).is_equal(base)
		assert_array(pf.looks_of(base)).contains([base, id])
		# a variant walks like its kind: a bush or an agave is walked through, a rock is not
		assert_bool(float(man[id]["radius"]) == 0.0).is_equal(float(man[base]["radius"]) == 0.0)
	# two more joshua trees (pass 85, re-pinned: and a third, joshua_tree_d)
	assert_array(pf.looks_of("joshua_tree")).has_size(4)


func test_the_brittlebush_is_a_new_bush_in_the_patches() -> void:
	var man := _manifest()
	assert_bool(man.has("brittlebush")).is_true()
	assert_bool(man["brittlebush"].has("variant_of")).is_false()
	assert_float(float(man["brittlebush"]["radius"])).is_equal(0.0)
	assert_bool(ResourceLoader.exists("res://art/sprites/props/brittlebush.png")).is_true()
	var ids: Array = RED_CANYON.BUSH_IDS.map(func(r) -> String: return str(r[0]))
	assert_array(ids).contains(["brittlebush"])
	# on the sand of a real map
	var n := 0
	for ms in [5, 7, 11]:
		var m := _canyon(ms)
		for row: Dictionary in (m.get("props") as PropField).placed:
			if str(row["id"]) == "brittlebush":
				n += 1
		m.queue_free()
		await get_tree().process_frame
	assert_int(n).is_greater(0)


func test_a_kind_draws_its_looks_by_the_spot_and_the_layout_keeps_its_kinds() -> void:
	var pf := _field()
	# the same spot always draws the same look; over many spots every look shows
	var seen := {}
	for i in 400:
		var at := Vector3(float(i % 20) * 1.7, 0.0, float(i / 20) * 2.3)
		var look := pf.pick_look("agave", at)
		assert_str(pf.pick_look("agave", at)).is_equal(look)
		seen[look] = true
	assert_bool(seen.has("agave") and seen.has("agave_b")).is_true()
	# a kind with no variant is itself
	assert_str(pf.pick_look("saguaro_big", Vector3(3, 0, 4))).is_equal("saguaro_big")
	# on the map: every row keeps its kind's id, its look is that kind's, and some looks are variants
	var m := _canyon(7)
	var variants := 0
	for row: Dictionary in (m.get("props") as PropField).placed:
		var look := str(row["look"])
		assert_str(str(row["id"])).is_equal((m.get("props") as PropField).kind_of(look))
		assert_bool(VARIANTS.has(str(row["id"]))).is_false()
		if look != str(row["id"]):
			variants += 1
	assert_int(variants).is_greater(5)


func test_a_variant_asked_by_name_is_drawn_as_itself() -> void:
	var pf := _field()
	add_child(pf)
	assert_bool(pf.add("boulder_b", Vector3(1, 0, 1))).is_true()
	var row: Dictionary = pf.placed[pf.placed.size() - 1]
	assert_str(str(row["id"])).is_equal("boulder")
	assert_str(str(row["look"])).is_equal("boulder_b")
	# a kind's own painting asked for exactly (a hand-laid scene) is never swapped for a variant
	for i in 20:
		assert_bool(pf.add("agave", Vector3(float(i) * 1.3, 0, 2), 1.0, false, 0.0, true)).is_true()
		assert_str(str(pf.placed[pf.placed.size() - 1]["look"])).is_equal("agave")


# ---------------------------------------------------------------- the shadows

func test_every_painting_has_a_measured_shadow() -> void:
	var man := _manifest()
	var pf := _field()
	for id: String in man.keys():
		if not pf.has(id):
			continue
		assert_bool((man[id] as Dictionary).get("shadow") is Dictionary).override_failure_message("no shadow for " + id).is_true()
		var sh := pf.shadow_of(id)
		assert_float(float(sh["w"])).override_failure_message(id).is_greater(0.1)
		assert_float(float(sh["d"])).override_failure_message(id).is_greater(0.05)
		assert_float(float(sh["a"])).override_failure_message(id).is_between(0.15, 0.7)
		# under the painted foot: not off to the side, and behind the quad's foot (it stands a little up its quad)
		assert_float(absf(float(sh["x"]))).override_failure_message(id).is_less(0.12)
		assert_float(float(sh["z"])).override_failure_message(id).is_between(-0.15, 0.0)


func test_every_placed_prop_lies_on_one_shadow_on_the_ground() -> void:
	var m := _canyon(7)
	var pf: PropField = m.get("props")
	assert_int(pf.placed.size()).is_greater(60)
	var used := {}
	for row: Dictionary in pf.placed:
		var s := int(row["s"])
		assert_int(s).is_greater_equal(0)
		# one each, never two props on one shadow
		assert_bool(used.has(s)).is_false()
		used[s] = true
	assert_int(pf.shadow_count()).is_greater_equal(pf.placed.size())
	# a shadow lies on the sand under its foot: draped a hair above the ground, near the foot, flat-ish
	var row0: Dictionary = pf.placed[0]
	var xf := pf.shadow_xform(row0["pos"], Color(0.4, 1.0, 0.7, 2.0))
	var at: Vector3 = row0["pos"]
	assert_float(xf.origin.distance_to(Vector3(at.x, xf.origin.y, at.z))).is_less(PropField.SUN_SHIFT_MAX + 0.01)
	assert_float(xf.origin.y - m.height_at(xf.origin.x, xf.origin.z)).is_between(0.0, 0.3)
	# drawn see-through at the creatures' shadow priority (under the gems and coins)
	var mmi: MultiMeshInstance3D = pf.get_node("GroundShadows")
	assert_int(mmi.material_override.render_priority).is_equal(EnemyManager.SHADOW_PRIORITY)
	assert_int(EnemyManager.SHADOW_PRIORITY).is_less(PickupManager.PICKUP_PRIORITY)


func test_the_shadows_grow_past_their_first_buffer() -> void:
	var pf := _field()
	add_child(pf)
	for i in PropField.SHADOW_CAP + 40:
		pf.add_shadow(Vector3(float(i % 30), 0.0, float(i / 30)), 1.0, 0.6, 0.4)
	assert_int(pf.shadow_count()).is_equal(PropField.SHADOW_CAP + 40)
	assert_int(pf.get_node("GroundShadows").multimesh.instance_count).is_greater_equal(PropField.SHADOW_CAP + 40)


func test_barrels_signs_and_structures_stand_on_shadows() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.3).timeout
	var pf: PropField = g.map.get("props")
	# a barrel each, gone when it breaks
	assert_int(g.barrels.shadows.size()).is_equal(g.barrels.pos.size())
	for s in g.barrels.shadows:
		assert_int(s).is_greater_equal(0)
	var s0: int = g.barrels.shadows[0]
	assert_float(pf.shadow_scale(s0)).is_equal(1.0)
	assert_float(pf.shadow_strength(s0)).is_equal_approx(BarrelField.SHADOW_A, 0.001)
	g.barrels._break(0)
	assert_float(pf.shadow_scale(s0)).is_equal(0.0)
	# a post each
	var signs = g.get_node_or_null("Signs")
	assert_object(signs).is_not_null()
	assert_int(signs.shadows.size()).is_equal(signs.spots.size())
	# every structure
	assert_int(g.structures.items.size()).is_greater(5)
	for s in g.structures.items:
		assert_int(s.shadow).is_greater_equal(0)
	var st = g.structures.items[0]
	g.structures.shadow_k(st, 0.0)
	assert_float(pf.shadow_scale(st.shadow)).is_equal(0.0)
	g.structures.shadow_k(st, 1.0)
	assert_float(pf.shadow_scale(st.shadow)).is_equal(1.0)


# ---------------------------------------------------------------- the title

func test_the_title_scene_is_composed_round_the_hero() -> void:
	Settings.menu_style = "live"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	var stage = t._stage
	assert_object(stage).is_not_null()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STAGE.SCENE_FILE))
	var sc: Dictionary = data["red_canyon"]
	# every painting of the vignette laid (a variant by name too), each on its shadow (pass 85, re-pinned: the vignette
	# is one of the map's presets, drawn at random each visit)
	var laid_props: Array = STAGE.presets_of(sc)[stage.preset_index]["props"]
	assert_int(stage.composed.size()).is_equal(laid_props.size())
	var pf: PropField = stage.map.get("props")
	var feet: Vector3 = stage.feet()
	var bx: Array = sc["clear"]["x"]
	var bz: Array = sc["clear"]["z"]
	var laid := 0
	for row: Dictionary in pf.placed:
		var p: Vector3 = row["pos"]
		var inside: bool = p.x - feet.x >= float(bx[0]) and p.x - feet.x <= float(bx[1]) and p.z - feet.z >= float(bz[0]) and p.z - feet.z <= float(bz[1])
		if inside:
			laid += 1
			assert_int(int(row["s"])).is_greater_equal(0)
	# inside the box only the vignette stands (the map's own scatter there is gone)
	assert_int(laid).is_equal(stage.composed.size())
	# the hero's spot is clear: nothing within 1.3 m of his feet
	for pr: Dictionary in STAGE.presets_of(sc):
		for e: Dictionary in pr["props"]:
			assert_float(Vector2(float(e["x"]), float(e["z"])).length()).is_greater(1.3)
