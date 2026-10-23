extends GdUnitTestSuite

## Pass 101, lane LOOKS (Garry's item 6: "load only the looks that will appear"): a look's strip is a path in the
## content (.tres and def) and loads the first time something asks for it (LookArt); a run loads and pins, under the
## spawn beam, every creature its stage can bring in the look it brings it in and the hero's played look (RunLooks); the
## arena and a tool's launch load a look when it is picked or spawned; a played look switched in the JSON (the Level
## Editor) is the one the next run loads. The expectations read the map file, not Garry's numbers.

const LAUNCH := "user://debug_launch.json"
const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	if Save.sandboxed():
		Save.end_sandbox()
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	Run.debug_clear_items()
	Run.end()
	if FileAccess.file_exists(LAUNCH):
		DirAccess.remove_absolute(LAUNCH)


func _strip_files(folder: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(folder):
		if f.ends_with(".png") and f.contains("_sprite"):
			out.append(folder + f)
	return out


# ---------------------------------------------------------------- the content holds paths, not strips

func test_no_tres_names_a_strip() -> void:
	var n := 0
	for type: String in ["enemies", "bosses", "characters"]:
		for id: String in DirAccess.get_directories_at("res://content/%s/" % type):
			var tres := "res://content/%s/%s/%s.tres" % [type, id, id]
			if not FileAccess.file_exists(tres):
				continue
			var txt := FileAccess.get_file_as_string(tres)
			for line: String in txt.split("\n"):
				if line.begins_with("[ext_resource") and line.contains("_sprite"):
					fail("%s names a strip: %s" % [tres, line])
			n += 1
	assert_int(n).is_greater(30)


func test_a_fresh_def_holds_no_strip_until_asked() -> void:
	# loaded fresh with its dependencies (nothing from the cache), the def carries the path and no texture
	var d: EnemyDef = ResourceLoader.load("res://content/enemies/dune_scorpion/dune_scorpion.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	assert_object(d).is_not_null()
	assert_object(d._sprite).is_null()
	assert_str(d.sprite_path).starts_with("res://content/enemies/dune_scorpion/")
	assert_bool(ResourceLoader.exists(d.sprite_path)).is_true()
	for code in d.variants.keys():
		var e: Dictionary = d.variants[code]
		assert_bool(e.get("sprite") is String).override_failure_message("%s's %s holds a texture" % [d.id, code]).is_true()
		assert_bool(ResourceLoader.exists(str(e["sprite"]))).is_true()
	# asked once, it loads and is held; the same texture every ask after
	var t := d.sprite
	assert_object(t).is_not_null()
	assert_bool(LookArt.is_held(d.sprite_path)).is_true()
	assert_object(d.sprite).is_same(t)
	# a copy in another look carries that look's path and loads that strip
	for code in d.variant_codes():
		if str(code) != d.variant:
			var v := d.variant_def(str(code))
			assert_str(v.sprite_path).is_equal(str(d.variants[code]["sprite"]))
			assert_str(v.sprite.resource_path).is_equal(v.sprite_path)
			assert_str(d.look_strip_path(str(code))).is_equal(v.sprite_path)
			break


func test_a_hero_def_holds_paths_too() -> void:
	var c: CharacterDef = ResourceLoader.load("res://content/characters/solenne/solenne.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	assert_object(c._sprite).is_null()
	assert_bool(ResourceLoader.exists(c.sprite_path)).is_true()
	for code in c.variant_codes(true):
		assert_bool((c.variants[code] as Dictionary).get("sprite") is String).is_true()
		var v := c.variant_def(str(code))
		assert_str(v.strip_path()).is_equal(c.look_strip_path(str(code)))
		assert_bool(ResourceLoader.exists(v.strip_path())).is_true()


func test_a_texture_entry_still_plays_as_before() -> void:
	# a stand-in look (arena_check's and touch_audit's) hands the texture itself
	var dri: CharacterDef = Registry.character("drifter")
	var c: CharacterDef = Registry.character("solenne").duplicate()
	c.variants = {"A": {"sprite": dri.sprite, "anims": dri.anims}, "B": {"note": "no strip"}}
	c.variant = ""
	assert_object(c.variant_def("A").sprite).is_same(dri.sprite)
	assert_str(c.look_strip_path("A")).is_equal(dri.sprite.resource_path)
	# setting null means no strip
	var e: EnemyDef = Registry.enemy("skeleton").duplicate()
	e.sprite = null
	assert_object(e.sprite).is_null()
	assert_str(e.strip_path()).is_equal("")


# ---------------------------------------------------------------- the cache

func test_lookart_keeps_the_pinned_set_and_lets_old_asks_go() -> void:
	LookArt.clear()
	var strips: Array = []
	for type: String in ["characters"]:
		for id: String in DirAccess.get_directories_at("res://content/%s/" % type):
			strips.append_array(_strip_files("res://content/%s/%s/" % [type, id]))
	assert_int(strips.size()).is_greater(6)
	var pinned: String = strips[0]
	LookArt.pin_only([pinned])
	assert_bool(LookArt.is_pinned(pinned)).is_true()
	# hero strips are 46.5 MB: asking for more than KEEP_MB of them lets the oldest unpinned go, never the pinned one
	for p: String in strips.slice(1):
		LookArt.tex(p)
	assert_bool(LookArt.is_held(pinned)).is_true()
	assert_bool(LookArt.is_held(strips[1])).is_false()
	assert_bool(LookArt.is_held(strips[strips.size() - 1])).is_true()
	# a let-go strip still drawn somewhere comes back the same (Godot's cache), so nothing on screen changes
	var keep: Texture2D = load(strips[1])
	assert_object(LookArt.tex(strips[1])).is_same(keep)
	assert_object(LookArt.tex("")).is_null()
	assert_object(LookArt.tex("res://content/nope_sprite.png")).is_null()
	LookArt.clear()


# ---------------------------------------------------------------- a run's set

func _game(launch: Dictionary) -> Game:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify(launch))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


## The [id, variant] rows of the map file that stage `k`'s window opens (read from the file), the stage's boss and the
## specials whose stage has come.
func _expected_pairs(k: int) -> Array:
	var d: Dictionary = JsonContent.load_json(MAP_JSON)
	var tl: Dictionary = d["timeline_data"]
	var a := 0.0
	var stages: Array = tl.get("stage_list", [])
	for i in range(k):
		a += float(stages[i]["length"])
	var b := a + float(stages[k]["length"])
	var out: Array = [[str(stages[k]["boss"]), ""]]
	for r in tl.get("roster", []):
		var e = r.get("enemy", "")
		if e is Array or str(e) == "roster":
			continue
		var t0 := float(r.get("t", 0.0))
		var until := float(r["until"]) if r.get("until") != null else INF
		if t0 <= b and until > a:
			out.append([str(e), str(r.get("variant", ""))])
	for row in (tl.get("specials", {}) as Dictionary).get("pool", []):
		if int(row.get("stage", 1)) <= k + 1:
			out.append([str(row["enemy"]), ""])
	return out


func test_pairs_for_each_stage_hold_its_rows_its_boss_and_what_the_boss_brings() -> void:
	var map: MapDef = Registry.map("red_canyon")
	for k in range(map.timeline.stage_count()):
		var pairs := RunLooks.pairs_for(Registry, map, k)
		for p: Array in _expected_pairs(k):
			if Registry.enemy(str(p[0])) == null:
				continue
			assert_bool(pairs.any(func(q) -> bool: return q[0] == p[0] and q[1] == p[1])) \
				.override_failure_message("stage %d misses %s %s" % [k + 1, p[0], p[1]]).is_true()
		# the stage's boss brings its brood (a boss attack's `enemy`)
		var boss: EnemyDef = Registry.enemy(map.timeline.stage_boss(k))
		for atk in boss.boss.get("attacks", []):
			if atk is Dictionary and str(atk.get("enemy", "")) != "" and Registry.enemy(str(atk["enemy"])) != null:
				assert_bool(pairs.any(func(q) -> bool: return q[0] == str(atk["enemy"]))).override_failure_message(
					"stage %d misses %s's brood %s" % [k + 1, boss.id, atk["enemy"]]).is_true()
	# a stage leaves out what only a later stage brings: the later stages' bosses (unless the map's own `boss`)
	var s1 := RunLooks.pairs_for(Registry, map, 0)
	for k in range(1, map.timeline.stage_count()):
		var later := map.timeline.stage_boss(k)
		if later != map.boss and later != map.timeline.stage_boss(0):
			assert_bool(s1.any(func(q) -> bool: return q[0] == later)).override_failure_message("stage 1 holds %s" % later).is_false()
	# nobody on no map (the spider, the arena's dummies)
	assert_bool(s1.any(func(q) -> bool: return q[0] == "training_dummy")).is_false()


func test_a_run_pins_its_stage_set_and_the_hero_look_before_the_first_spawn() -> void:
	var g := _game({"character": "solenne", "map": "red_canyon", "map_seed": 5, "analytics": false, "stage": 1})
	assert_bool(Run.arena).is_false()
	for p: Array in RunLooks.last_pairs:
		var d: EnemyDef = Registry.enemy(str(p[0]))
		var path := d.look_strip_path(str(p[1]))
		if path != "":
			assert_bool(LookArt.is_pinned(path)).override_failure_message("%s %s not pinned" % [p[0], p[1]]).is_true()
	for p: Array in _expected_pairs(0):
		var d2: EnemyDef = Registry.enemy(str(p[0]))
		if d2 != null and d2.look_strip_path(str(p[1])) != "":
			assert_bool(LookArt.is_pinned(d2.look_strip_path(str(p[1])))).override_failure_message("%s %s" % [p[0], p[1]]).is_true()
	var look: CharacterDef = Registry.played_look(Registry.character("solenne"))
	assert_bool(LookArt.is_pinned(look.strip_path())).is_true()
	# the hero draws that very texture
	assert_object((g.player.sprite.material_override as ShaderMaterial).get_shader_parameter("sprite")).is_same(look.sprite)
	# a look no row brings and no one plays is not pinned (any creature's unplayed look, here the scorpion's others)
	var sc: EnemyDef = Registry.enemy("dune_scorpion")
	for code in sc.variant_codes(true):
		var path2 := sc.look_strip_path(str(code))
		if str(code) != sc.variant and path2 != sc.strip_path() and not RunLooks.last_pairs.any(func(q) -> bool: return q[0] == sc.id and q[1] == str(code)):
			assert_bool(LookArt.is_pinned(path2)).override_failure_message("unplayed %s pinned" % code).is_false()
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func test_the_arena_pins_its_dummies_and_loads_a_pick_when_picked() -> void:
	var g := _game({"arena": true, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false})
	assert_object(g.arena_panel).is_not_null()
	assert_bool(LookArt.is_pinned(Registry.enemy("training_dummy").strip_path())).is_true()
	# the roster's creatures are not loaded for the arena
	assert_bool(RunLooks.last_pairs.any(func(q) -> bool: return q[0] == "red_goblin")).is_false()
	# a creature in a look: spawned from the panel, its strip loads then and it is drawn
	var sk: EnemyDef = Registry.enemy("skeleton")
	var code := ""
	for c in sk.variant_codes():
		if str(c) != sk.variant:
			code = str(c)
			break
	assert_str(code).is_not_empty()
	var want := sk.look_strip_path(code)
	g.arena_panel.spawn_enemy_n(Registry.enemy_with("skeleton", code), 2)
	assert_bool(LookArt.is_held(want)).is_true()
	var em: EnemyManager = g.enemies
	var t: int = em.type_by_id["skeleton@" + code]
	assert_str((em.types[t]["mat"] as ShaderMaterial).get_shader_parameter("sprite").resource_path).is_equal(want)
	# a hero look shown from the chips loads and is drawn
	var c2: CharacterDef = Registry.character("solenne")
	g.arena_panel.swap_hero("solenne")
	for lc in c2.variant_codes():
		g.arena_panel.show_look(str(lc))
		var lp := c2.look_strip_path(str(lc))
		assert_bool(LookArt.is_held(lp)).is_true()
		assert_str((g.player.sprite.material_override as ShaderMaterial).get_shader_parameter("sprite").resource_path).is_equal(lp)
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func test_a_played_look_switched_in_the_json_is_the_one_the_next_run_loads() -> void:
	# the Level Editor writes the JSON's `variant` and imports it: here the scorpion's JSON built with another look
	var dir := "res://content/enemies/dune_scorpion/"
	var d: Dictionary = JsonContent.load_json(dir + "dune_scorpion.json")
	var was: EnemyDef = Registry.enemies["dune_scorpion"]
	var pick := ""
	for code in was.variant_codes():
		if str(code) != was.variant and was.look_strip_path(str(code)) != was.strip_path():
			pick = str(code)
			break
	assert_str(pick).is_not_empty()
	d["variant"] = pick
	var nd: EnemyDef = JsonContent.build("enemies", d, dir)
	assert_str(nd.variant).is_equal(pick)
	assert_str(nd.strip_path()).is_equal(was.look_strip_path(pick))
	Registry.enemies["dune_scorpion"] = nd
	var g := _game({"character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false, "stage": 1})
	assert_bool(LookArt.is_pinned(nd.strip_path())).is_true()
	Registry.enemies["dune_scorpion"] = was
	# a hero's look kept on the phone (the arena's USE FROM NOW ON) is the one his next run pins
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func test_a_kept_hero_look_is_the_one_the_next_run_pins() -> void:
	var c: CharacterDef = Registry.character("solenne")
	var pick := ""
	for code in c.variant_codes():
		if c.look_strip_path(str(code)) != Registry.played_look(c).strip_path():
			pick = str(code)
			break
	assert_str(pick).is_not_empty()
	Save.set_hero_look("solenne", pick)
	var g := _game({"character": "solenne", "map": "red_canyon", "map_seed": 5, "analytics": false, "stage": 1})
	assert_bool(LookArt.is_pinned(c.look_strip_path(pick))).is_true()
	assert_str(g.player.look_code()).is_equal(pick)
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)
