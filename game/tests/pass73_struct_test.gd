## Pass 73, lane STRUCT (Garry: "(Bug) Structure - The Guy who you sacrifice Max HP to in order to get an item art cuts
## off weirdly, should be seamless" and "New Structure type - Totem Poles ... a smaller area that Player has to stand in
## to interact with them, but it takes just as much time to activate them ... a menu pops up offering Players a choice
## between 3 small stats improvements for that run ... always between 10-12 of them on the map. Signs show to them as
## well ... a bit smaller than other Structures ... When used they turn gray as well, but they don't get 'destroyed'").
## The Stranger's two pictures have no seam (the world painting's keyed glow bubble gone, the screen cut-out fading out
## at its foot); content/structures/totem_pole (its gifts as data); StructureManager's per-map structures apart from the
## draw; TotemBoons' offers; Run's run-long gifts; the menu (ui/TotemScreen.gd); a used pole grey and standing; the
## signs' per-kind cap.
extends GdUnitTestSuite

const SIGNS := preload("res://core/systems/SignField.gd")
const BOONS := preload("res://core/systems/TotemBoons.gd")
const SCREEN := preload("res://ui/TotemScreen.gd")
const REF_WORDS := ["Le-loo", "Chet-woot", "Skana", "Walalee", "Ol-hiyo", "El-kolie", "Kuuma", "Thunderbird", "Raven",
	"Frog", "Se-sook"]

const FLAT_MAP := """extends MapBase
var flats_radius := 16.0
"""

const FAKE_GAME := """extends Node
var structures = null
var player = null
var paused := false
"""

const FAKE_SM := """extends Node3D
var items: Array = []
"""

var _keep_inset := -1


func before_test() -> void:
	_keep_inset = Settings.top_inset
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	Settings.top_inset = _keep_inset
	get_tree().paused = false
	Run.forced_map_seed = 0
	Run.arena = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _pole() -> StructureDef:
	return Registry.structure("totem_pole")


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _run_game(seed: int = 11) -> Game:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": seed, "analytics": false})
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func _png(rel: String) -> Image:
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(rel))).is_equal(OK)
	img.convert(Image.FORMAT_RGBA8)
	return img


# ---------------------------------------------------------------- 1. the Stranger without a seam

func test_the_strangers_screen_cut_out_fades_out_at_its_foot() -> void:
	# the cut-out ran off its picture's bottom edge (alpha 255 on the last row): a hard line over the dim on the screen
	var img := _png("res://art/ui/wanted/stranger.png")
	var h := img.get_height()
	var last := 0.0
	var mid := 0.0
	for x in range(img.get_width()):
		last = maxf(last, img.get_pixel(x, h - 1).a)
		mid = maxf(mid, img.get_pixel(x, int(h * 0.5)).a)
	assert_float(last).is_less(0.02)
	# the figure itself is whole above the fade (his hands, the glow)
	assert_float(mid).is_greater(0.99)
	# and it fades smoothly: a row near the foot is fainter than one where the fade starts
	var near_foot := 0.0
	var at_start := 0.0
	for x in range(img.get_width()):
		near_foot = maxf(near_foot, img.get_pixel(x, int(h * 0.94)).a)
		at_start = maxf(at_start, img.get_pixel(x, int(h * 0.76)).a)
	assert_float(near_foot).is_less(at_start)


func test_the_strangers_painting_has_no_glow_bubble_round_the_hood() -> void:
	# the keyed "faint violet glow from inside the hood" had stayed as an opaque pale green-white bubble round the hood
	var img := _png("res://art/sprites/props/st_hooded_figure.png")
	var bubble := 0
	for y in range(0, 84):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var greenish := c.h * 360.0 >= 60.0 and c.h * 360.0 <= 215.0 and c.v >= 0.45 and c.s >= 0.06
			var washed := c.v >= 0.7 and c.s <= 0.2
			if greenish or washed:
				bubble += 1
	assert_int(bubble).is_less(6)
	# the hood is still there: its black inside and its violet cloth
	var black := 0
	var violet := 0
	for y in range(10, 70):
		for x in range(100, 160):
			var c := img.get_pixel(x, y)
			if c.a < 0.9:
				continue
			if c.v < 0.12:
				black += 1
			elif c.h * 360.0 >= 255.0 and c.h * 360.0 <= 335.0 and c.s > 0.15:
				violet += 1
	assert_int(black).is_greater(300)
	assert_int(violet).is_greater(300)


# ---------------------------------------------------------------- 2. the Totem Pole as content

func test_the_totem_pole_is_content() -> void:
	var d := _pole()
	assert_object(d).is_not_null()
	assert_str(d.effect_kind).is_equal("totem")
	assert_bool(d.hidden).is_false()
	# a smaller circle (Garry: "a smaller area that Player has to stand in"), the usual interact time
	assert_float(d.radius).is_equal_approx(1.2, 0.001)
	assert_float(d.radius).is_less(Registry.structure("healing_well").radius)
	assert_float(d.interact_time).is_equal_approx(Registry.structure("healing_well").interact_time, 0.001)
	# a bit smaller than the other structures: about 75% of their typical height
	var hs: Array = []
	for o: StructureDef in StructureManager.drawn(StructureManager.in_play(Registry.structures.values())):
		hs.append(o.height)
	hs.sort()
	var median: float = hs[int(hs.size() / 2.0)]
	assert_float(d.height / median).is_between(0.65, 0.85)
	# 10-12 a map, apart from the draw
	assert_bool(StructureManager.per_map_range(d) == Vector2i(10, 12)).is_true()
	# its painting, and its prompt for the art queue
	assert_bool(ResourceLoader.exists("res://art/sprites/props/st_totem_pole.png")).is_true()
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://content/structures/totem_pole/totem_pole.json"))
	assert_bool(raw is Dictionary).is_true()
	assert_str(str((raw as Dictionary).get("art_prompt", ""))).contains("totem pole")


func test_the_gifts_are_data_titled_with_the_references_words() -> void:
	var pool := BOONS.pool_of(_pole())
	assert_int(pool.size()).is_greater_equal(10)
	var names: Array = []
	var stats: Array = []
	for e: Dictionary in pool:
		names.append(str(e["name"]))
		for k in ["id", "name", "animal", "stat", "op", "min", "max", "step", "weight"]:
			assert_bool(e.has(k)).override_failure_message("%s lacks %s" % [e.get("id"), k]).is_true()
		var stat := str(e["stat"])
		# a stat the hero's sheet knows, and the words TextGen has for it
		assert_bool(StatSheet.PLAYER_DEFAULTS.has(stat)).override_failure_message(stat).is_true()
		assert_bool(TextGen.STATS.has(stat)).override_failure_message(stat).is_true()
		assert_bool(stats.has(stat)).override_failure_message("two gifts of " + stat).is_false()
		stats.append(stat)
		# small but not nothing: never under a third of its top, never zero
		assert_float(absf(float(e["min"]))).is_greater(0.0)
		assert_float(absf(float(e["min"]))).is_greater_equal(absf(float(e["max"])) / 3.0 - 0.0001)
	for w in REF_WORDS:
		assert_bool(names.has(w)).override_failure_message("no gift named " + w).is_true()
	# the commonest stats weigh more than the rarest
	var weight_of := func(stat: String) -> float:
		for e: Dictionary in pool:
			if str(e["stat"]) == stat:
				return float(e["weight"])
		return 0.0
	assert_float(weight_of.call("move_speed")).is_greater(weight_of.call("luck"))
	assert_float(weight_of.call("max_hp")).is_greater(weight_of.call("crit_chance"))


# ---------------------------------------------------------------- 3. the offers

func test_an_offer_is_three_different_stats_each_rolled_in_its_range() -> void:
	var d := _pole()
	var rng := RandomNumberGenerator.new()
	for k in range(300):
		rng.seed = k + 1
		var offer := BOONS.offer(d, rng)
		assert_int(offer.size()).is_equal(3)
		var stats: Array = []
		for b: Dictionary in offer:
			assert_bool(stats.has(str(b["stat"]))).is_false()
			stats.append(str(b["stat"]))
			var lo := minf(float(b["min"]), float(b["max"]))
			var hi := maxf(float(b["min"]), float(b["max"]))
			assert_float(float(b["value"])).is_between(lo - 0.00001, hi + 0.00001)
			assert_int(int(b["quality"])).is_between(1, 3)
	# the amounts range over the whole span: over many offers the smallest and the biggest both come up
	# (pass 76, lane TOTEM, re-pinned on purpose: the Whale's range is read from the pool, 2-6 since pass 76, was 6-14)
	var whale := {}
	for e: Dictionary in BOONS.pool_of(d):
		if str(e["stat"]) == "max_hp":
			whale = e
	var seen := {}
	for k in range(600):
		rng.seed = 1000 + k
		for b: Dictionary in BOONS.offer(d, rng):
			if str(b["stat"]) == "max_hp":
				seen[int(round(float(b["value"])))] = true
	assert_bool(seen.has(int(round(float(whale["min"]))))).is_true()
	assert_bool(seen.has(int(round(float(whale["max"]))))).is_true()


func test_common_stats_are_offered_more_often() -> void:
	var d := _pole()
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var count := {}
	for k in range(2000):
		for b: Dictionary in BOONS.offer(d, rng):
			count[str(b["stat"])] = int(count.get(str(b["stat"]), 0)) + 1
	assert_int(int(count.get("move_speed", 0))).is_greater(int(count.get("luck", 0)) * 3 / 2)
	assert_int(int(count.get("might", 0))).is_greater(int(count.get("area", 0)) * 3 / 2)
	# every gift comes up
	for e: Dictionary in BOONS.pool_of(d):
		assert_int(int(count.get(str(e["stat"]), 0))).override_failure_message(str(e["stat"])).is_greater(0)


func test_the_gift_reads_as_a_plain_number() -> void:
	assert_str(BOONS.text({"stat": "move_speed", "op": "mul", "value": 0.06})).is_equal("+6% move speed")
	assert_str(BOONS.text({"stat": "max_hp", "op": "add", "value": 10.0})).is_equal("+10 max HP")
	assert_str(BOONS.text({"stat": "cooldown", "op": "mul", "value": -0.03})).is_equal("−3% cooldown")
	assert_str(BOONS.text({"stat": "regen", "op": "add", "value": 0.3})).is_equal("+0.3 regen per second")
	assert_str(BOONS.text({"stat": "crit_chance", "op": "add", "value": 0.02})).is_equal("+2% crit chance")
	assert_str(BOONS.amount_text({"stat": "magnet", "op": "mul", "value": 0.12})).is_equal("+12%")
	assert_str(BOONS.title({"name": "Le-loo", "animal": "the Wolf"})).is_equal("Le-loo, the Wolf")
	assert_str(BOONS.title({"name": "Raven", "animal": ""})).is_equal("Raven")
	# the feathers: the third of its range the amount fell in
	assert_int(BOONS.quality(0.03, 0.03, 0.07)).is_equal(1)
	assert_int(BOONS.quality(0.05, 0.03, 0.07)).is_equal(2)
	assert_int(BOONS.quality(0.07, 0.03, 0.07)).is_equal(3)
	assert_int(BOONS.quality(-0.05, -0.05, -0.02)).is_equal(3)


# ---------------------------------------------------------------- 4. a gift stays for the run

func test_a_gift_stays_on_the_hero_for_the_run() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var speed0 := Run.player_sheet.get_stat("move_speed")
	var hp0 := Run.player_sheet.get_stat("max_hp")
	var words := Run.take_totem_boon({"id": "wolf", "name": "Le-loo", "animal": "the Wolf", "stat": "move_speed", "op": "mul", "value": 0.05})
	assert_str(words).is_equal("+5% move speed")
	assert_float(Run.player_sheet.get_stat("move_speed")).is_equal_approx(speed0 * 1.05, 0.0001)
	var _w := Run.take_totem_boon({"id": "whale", "name": "El-kolie", "animal": "the Whale", "stat": "max_hp", "op": "add", "value": 10.0})
	assert_float(Run.player_sheet.get_stat("max_hp")).is_equal_approx(hp0 + 10.0, 0.0001)
	# named on the sheet (the pause screen's breakdown)
	var sources: Array = []
	for row: Dictionary in Run.player_sheet.breakdown("move_speed"):
		sources.append(str(row["source"]))
	assert_bool(sources.has("Totem: Le-loo")).is_true()
	# a rebuild (a level, a passive) keeps them
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("move_speed")).is_equal_approx(speed0 * 1.05, 0.0001)
	assert_int(Run.totem_boons.size()).is_equal(2)
	# a new run starts without them
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_int(Run.totem_boons.size()).is_equal(0)
	assert_float(Run.player_sheet.get_stat("move_speed")).is_equal_approx(speed0, 0.0001)
	# nothing to take: nothing changes
	assert_str(Run.take_totem_boon({})).is_equal("")
	assert_int(Run.totem_boons.size()).is_equal(0)


# ---------------------------------------------------------------- 5. on the map

func test_a_map_stands_ten_to_twelve_poles_spread_out_beside_the_draw() -> void:
	var g := _run_game(7)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	var plan: Dictionary = Run.map.timeline.structures
	var drawn_kinds := StructureManager.drawn(StructureManager.in_play(Registry.structures.values()))
	for trial in range(6):
		var sm: StructureManager = g.structures
		if trial > 0:
			sm = StructureManager.new()
			g.add_child(sm)
			sm.setup(g, g.map, plan)
		var poles: Array = []
		var others := 0
		for s in sm.items:
			if s.def.id == "totem_pole":
				poles.append(s.global_position)
			elif StructureManager.per_map_range(s.def) == Vector2i(-1, -1):
				# pass 85 (re-pinned): the Teleports stand their own count too (params.per_map), beside the draw
				others += 1
		# the draw as before, the poles on top
		assert_int(others).is_equal(maxi(int(plan.get("count", 0)), drawn_kinds.size()))
		assert_int(poles.size()).is_between(10, 12)
		var river: Array = g.map.call("river_points")
		var half: float = float(g.map.get("river_width")) * 0.5
		for p: Vector3 in poles:
			# off the dry river's bed, out of the water, inside the arena, clear of the start
			assert_float(StructureManager.river_distance(Vector2(p.x, p.z), river)).is_greater_equal(half + StructureManager.RIVER_CLEAR - 0.001)
			assert_bool(g.map.in_water(p)).is_false()
			assert_float(Vector2(p.x, p.z).length()).is_less(g.map.arena_radius * StructureManager.PER_MAP_BAND.y + 0.01)
			var fc: Vector3 = g.map.flats_center
			assert_float(Vector2(p.x - fc.x, p.z - fc.z).length()).is_greater_equal(9.0)
		# spread out: never closer than the relaxed spacing, and far apart on the whole
		var sum := 0.0
		for p: Vector3 in poles:
			var others_p := poles.filter(func(q: Vector3) -> bool: return q != p)
			var nn := StructureManager.nearest_distance(p, others_p)
			assert_float(nn).is_greater_equal(7.0)
			sum += nn
		assert_float(sum / float(poles.size())).is_greater(14.0)
		if trial > 0:
			sm.queue_free()


func test_signs_point_at_one_pole_at_most_each() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.map_seed = 73
	var map: Node3D = auto_free(Node3D.new())
	map.set_script(_script(FLAT_MAP))
	add_child(map)
	var game: Node = auto_free(Node.new())
	game.set_script(_script(FAKE_GAME))
	add_child(game)
	var sm: Node3D = Node3D.new()
	sm.set_script(_script(FAKE_SM))
	game.add_child(sm)
	game.structures = sm
	# six poles close round a spot and two structures farther out
	var at := Vector3(30, 0, 0)
	var defs: Array = []
	for k in range(6):
		defs.append([_pole(), at + Vector3(cos(k * 1.05) * (4.0 + k), 0, sin(k * 1.05) * (4.0 + k))])
	defs.append([Registry.structure("shop"), at + Vector3(0, 0, 20)])
	defs.append([Registry.structure("hooded_figure"), at + Vector3(-20, 0, 0)])
	for pair in defs:
		var s := StructureManager.Structure.new()
		s.def = pair[0]
		sm.add_child(s)
		s.position = pair[1]
		sm.items.append(s)
	var f: Node3D = auto_free(SIGNS.new())
	add_child(f)
	f.game = game
	f.map = map
	var near: Array = f.nearest_unused(at, 4, 0.0)
	var poles := near.filter(func(s) -> bool: return s.def.id == "totem_pole")
	assert_int(poles.size()).is_equal(1)
	# the rest of the arms go to the other structures
	assert_int(near.size()).is_equal(3)
	assert_int(SIGNS.per_sign_cap(poles[0])).is_equal(1)
	assert_str(SIGNS.SHORT.get("totem_pole", "")).is_equal("TOTEM")


func test_a_used_pole_stands_grey_and_is_not_used_again() -> void:
	var g := _run_game(9)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	var sm: StructureManager = g.structures
	var here: Vector3 = g.player.global_position + Vector3(6, 0, 0)
	here.y = g.map.height_at(here.x, here.z)
	var s: StructureManager.Structure = sm._spawn(_pole(), here)
	assert_bool(s.visual is BillboardSprite).is_true()
	assert_object(s.glow).is_null()
	var n := sm.items.size()
	sm._use(s)
	await get_tree().create_timer(0.1).timeout
	# (pass 82, lane TOTEM, re-pinned on purpose: the Spirit Pole screen's motion: the pole keeps its paint and its ring
	# while its gift screen is up and greys once the gift is taken; the end state below is pass 73's)
	assert_bool(s.used).is_true()
	assert_bool(s.ring.visible).is_true()
	# the menu it opened, closed by a pick
	assert_bool(g.totem_screen.visible).is_true()
	g.totem_screen._pick(g.totem_screen.planks()[0])
	await get_tree().create_timer(0.8).timeout
	# still standing, grey, its ring gone
	assert_bool(is_instance_valid(s) and s.is_inside_tree()).is_true()
	assert_int(sm.items.size()).is_equal(n)
	assert_bool(s.used).is_true()
	assert_bool(s.visual.visible).is_true()
	assert_bool(s.ring.visible).is_false()
	var mat := (s.visual as BillboardSprite).material_override as ShaderMaterial
	var tint: Color = mat.get_shader_parameter("tint")
	assert_bool(tint.is_equal_approx(Color(1, 1, 1, 1))).is_false()
	var grey := StructureManager.grey_painting(_pole())
	if grey != null:
		# the painting's own grey copy: no colour left in it
		var img := grey.get_image()
		var coloured := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var c := img.get_pixel(x, y)
				if c.a > 0.5 and c.s > 0.08:
					coloured += 1
		assert_int(coloured).is_equal(0)
		assert_object(mat.get_shader_parameter("sprite")).is_same(grey)
	# standing in it again does nothing
	g.player.global_position = here
	for k in range(40):
		sm._process(0.1)
	assert_bool(g.totem_screen.visible).is_false()
	assert_int(Run.totem_boons.size()).is_equal(1)


# ---------------------------------------------------------------- 6. the menu

func test_the_game_opens_the_menu_and_the_pick_stays() -> void:
	var g := _run_game(5)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	var speed0 := Run.player_sheet.get_stat("move_speed")
	g.use_structure(_pole(), g.player.global_position)
	await get_tree().create_timer(0.1).timeout
	assert_bool(g.totem_screen.visible).is_true()
	assert_int(g.current_modal()).is_equal(Game.Modal.TOTEM)
	assert_bool(g.paused).is_true()
	assert_array(g.visible_modals()).is_equal(["totem"])
	var planks: Array = g.totem_screen.planks()
	assert_int(planks.size()).is_equal(3)
	var offer: Array = g.totem_screen.offer()
	# (pass 82, lane TOTEM, re-pinned on purpose: the Spirit Pole's tags: the amount and the stat, the spirit "Word, the
	# Animal" (the word alone without an animal), the roll gauge with its third filled; pass82_totem_test has the rest)
	for k in range(3):
		var p = planks[k]
		var b: Dictionary = offer[k]
		assert_str(p.amount.text).is_equal(BOONS.amount_text(b))
		assert_str(p.stat.text).is_equal(BOONS.stat_text(b))
		assert_str(p.spirit.text).is_equal(BOONS.title(b))
		assert_bool(p.spirit.text.contains(",")).is_equal(str(b["animal"]) != "")
		assert_int(p.gauge.filled).is_equal(int(b["quality"]))
		assert_int(p.feathers).is_equal(int(b["quality"]))
	# a press on the second plank takes its gift; the run goes on
	planks[1].pressed.emit()
	await get_tree().create_timer(0.5).timeout
	assert_bool(g.totem_screen.visible).is_false()
	assert_int(g.current_modal()).is_equal(Game.Modal.NONE)
	assert_bool(g.paused).is_false()
	assert_int(Run.totem_boons.size()).is_equal(1)
	assert_str(str(Run.totem_boons[0]["id"])).is_equal(str(offer[1]["id"]))
	if str(offer[1]["stat"]) == "move_speed":
		assert_float(Run.player_sheet.get_stat("move_speed")).is_greater(speed0)
	# a second tap on the closed screen takes nothing more
	planks[0].pressed.emit()
	await get_tree().create_timer(0.3).timeout
	assert_int(Run.totem_boons.size()).is_equal(1)


func test_the_menu_fits_the_screen_with_and_without_a_cutout() -> void:
	# (pass 82, lane TOTEM, re-pinned on purpose: the Spirit Pole screen is top-anchored, its label at y 300 under a cutout
	# of up to 130 px and moved down by the rest of a deeper one; its rows inside the screen, one under another, the words
	# inside their tags)
	for inset in [0, 130, 200]:
		Settings.top_inset = inset
		var scr = auto_free(SCREEN.new())
		add_child(scr)
		var rng := RandomNumberGenerator.new()
		rng.seed = inset + 3
		scr.open(BOONS.offer(_pole(), rng), _pole())
		await get_tree().create_timer(0.6).timeout
		var vp: Vector2 = scr.get_viewport_rect().size
		var label: Rect2 = (scr.get_node("Label") as Control).get_global_rect()
		assert_float(label.position.y).is_greater_equal(float(inset))
		assert_float(label.position.y).is_equal(300.0 + maxf(float(inset) - 130.0, 0.0))
		var planks: Array = scr.planks()
		assert_int(planks.size()).is_equal(3)
		var prev_bottom: float = label.end.y
		for p in planks:
			var r: Rect2 = (p as Control).get_global_rect()
			assert_float(r.position.y).is_greater_equal(prev_bottom)
			assert_float(r.position.x).is_greater_equal(0.0)
			assert_float(r.end.x).is_less_equal(vp.x)
			assert_float(r.end.y).is_less_equal(vp.y)
			prev_bottom = r.end.y
			# the words fit the tag
			var tag: Rect2 = (p.tag as Control).get_global_rect()
			for t in [p.stat, p.spirit, p.gauge]:
				assert_float((t as Control).get_global_rect().end.x).is_less_equal(tag.end.x)
		scr.visible = false
