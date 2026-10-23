extends GdUnitTestSuite

## Pass 66, lane G (the Level Editor's Enemies, Heroes and Items tabs reach the game): a hero's `availability` folds into
## `hidden` (a "purchase" hero stays out of play until the loop is wired, his `price` and `currency_type` carried and
## shown nowhere); a shelved look (`variants[CODE].shelved`) is out of variant_codes() and so of the arena chips, but
## variant_def still wears it when named; the launch file's `arena`, `look` and `spawn_enemy`/`variant`/`count` keys
## open the debug arena with the hero in that look and that creature near him in that look (the editor's "Test in
## game"), the Save untouched; gen_placeholders.gd takes `only=` as import_json.gd does; the arena's look chips wrap, so
## fifty looks of one creature or hero all get a chip, the Art variants section folds per creature and the per-code
## notes stay with the lit chip.

const GEN := preload("res://tools/gen_placeholders.gd")
const SK := "res://content/enemies/skeleton/"
const SCORP := "res://content/enemies/dune_scorpion/"
const SOL := "res://content/characters/solenne/"
const ASTRO := "res://content/characters/astro/"
const TMP := "user://p66_g_placeholders/"
const LAUNCH := "user://debug_launch.json"

var _keep_debug := false


func before_test() -> void:
	Save.data = Save._default()
	_keep_debug = Settings.debug_mode
	Run.arena_next = false
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	if Save.sandboxed():
		Save.end_sandbox()
	Save.data = Save._default()
	Save._dirty = false
	Settings.debug_mode = _keep_debug
	Run.arena = false
	Run.arena_next = false
	Run.debug_clear_items()
	Run.end()
	if FileAccess.file_exists(LAUNCH):
		DirAccess.remove_absolute(LAUNCH)
	Registry.enemies.erase("p66_fifty")


# ---------------------------------------------------------------- availability

func _hero_from(d: Dictionary) -> CharacterDef:
	return JsonContent.build("characters", d, ASTRO) as CharacterDef


func test_availability_folds_into_hidden() -> void:
	var base: Dictionary = JsonContent.load_json(ASTRO + "astro.json")
	# "purchase": pass 69 (lane UI) wired the loop: shown on the title, locked or on sale (Registry.hero_state), never
	# hidden; the price and the currency carried
	var buy := base.duplicate(true)
	buy["availability"] = "purchase"
	buy["price"] = 500
	var c := _hero_from(buy)
	assert_bool(c.hidden).is_false()
	assert_str(c.availability).is_equal("purchase")
	assert_int(c.price).is_equal(500)
	assert_str(c.currency_type).is_equal("gold")
	# "hidden" alone hides
	var hid := base.duplicate(true)
	hid["availability"] = "hidden"
	assert_bool(_hero_from(hid).hidden).is_true()
	# absent: `hidden` says, and availability is derived from it (pass 72, lane INTEG: astro.json carries Garry's own
	# availability and price since his 2026-10-13 edit, purchase at 300, so the keys are taken out here)
	var bare := base.duplicate(true)
	for k: String in ["availability", "price", "currency_type"]:
		bare.erase(k)
	var plain := _hero_from(bare)
	assert_bool(plain.hidden).is_equal(bool(base.get("hidden", false)))
	assert_str(plain.availability).is_equal("hidden" if bool(base.get("hidden", false)) else "available")
	assert_int(plain.price).is_equal(0)
	assert_str(plain.currency_type).is_equal("gold")
	var h := base.duplicate(true)
	h["hidden"] = true
	# (pass 69: astro.json writes "availability" now; without it, `hidden` says)
	h.erase("availability")
	var hc := _hero_from(h)
	assert_bool(hc.hidden).is_true()
	assert_str(hc.availability).is_equal("hidden")
	# "available" with hidden: true stays hidden (hidden wins; the editor keeps the two in step)
	var both := base.duplicate(true)
	both["hidden"] = true
	both["availability"] = "available"
	var bc := _hero_from(both)
	assert_bool(bc.hidden).is_true()
	assert_str(bc.availability).is_equal("available")
	# "available" on an open hero changes nothing
	var open := base.duplicate(true)
	open["hidden"] = false
	open["availability"] = "available"
	assert_bool(_hero_from(open).hidden).is_false()
	# a negative price is 0; another currency word is carried as written
	var neg := base.duplicate(true)
	neg["price"] = -5
	neg["currency_type"] = "gems"
	var nc := _hero_from(neg)
	assert_int(nc.price).is_equal(0)
	assert_str(nc.currency_type).is_equal("gems")
	# the default of the def itself
	var fresh := CharacterDef.new()
	assert_str(fresh.availability).is_equal("available")
	assert_int(fresh.price).is_equal(0)
	assert_str(fresh.currency_type).is_equal("gold")


func test_every_hero_json_keeps_hidden_and_availability_in_step() -> void:
	for id in DirAccess.get_directories_at("res://content/characters"):
		var dir := "res://content/characters/%s/" % id
		var d: Dictionary = JsonContent.load_json(dir + id + ".json")
		if d.is_empty():
			continue
		var c := JsonContent.build("characters", d, dir) as CharacterDef
		# pass 69 (lane UI): only "hidden" hides; a "purchase" hero is shown (to be unlocked and bought)
		assert_bool(c.hidden).override_failure_message(id).is_equal(c.availability == "hidden")
		assert_bool(["hidden", "available", "purchase"].has(c.availability)).override_failure_message("%s: %s" % [id, c.availability]).is_true()
		assert_int(c.price).is_greater_equal(0)


# ---------------------------------------------------------------- shelved looks

func test_a_shelved_creature_look_is_out_of_the_codes_but_still_worn() -> void:
	var d: Dictionary = JsonContent.load_json(SK + "skeleton.json")
	var all: Array = (d["variants"] as Dictionary).keys()
	all.sort()
	assert_bool(all.has("SK-C")).is_true()
	(d["variants"]["SK-C"] as Dictionary)["shelved"] = true
	var e := JsonContent.build("enemies", d, SK) as EnemyDef
	# the entry is kept, the code is out of the list unless asked for
	assert_bool(e.variants.has("SK-C")).is_true()
	assert_bool(bool((e.variants["SK-C"] as Dictionary).get("shelved", false))).is_true()
	assert_bool(e.variant_shelved("SK-C")).is_true()
	assert_bool(e.variant_shelved("SK-A")).is_false()
	assert_bool(e.variant_shelved("SK-ZZ")).is_false()
	assert_array(e.variant_codes()).not_contains(["SK-C"])
	assert_int(e.variant_codes().size()).is_equal(all.size() - 1)
	assert_array(e.variant_codes(true)).is_equal(all)
	# worn when named: a copy with that strip
	var v := e.variant_def("SK-C")
	assert_object(v).is_not_same(e)
	assert_str(v.variant_code).is_equal("SK-C")
	assert_object(v.sprite).is_not_null()
	assert_str(v.sprite_file).is_equal(str(d["variants"]["SK-C"]["sprite"]))
	assert_str(v.type_key()).is_equal("skeleton@SK-C")
	# not shelved: no key read as shelved, the codes as before
	var plain := JsonContent.build("enemies", JsonContent.load_json(SK + "skeleton.json"), SK) as EnemyDef
	assert_array(plain.variant_codes()).is_equal(all)
	assert_array(plain.variant_codes(true)).is_equal(all)
	for code in all:
		assert_bool(plain.variant_shelved(str(code))).is_false()
		assert_bool(bool((plain.variants[code] as Dictionary).get("shelved", true))).is_false()
	# the base entry (the top-level strip, dune_scorpion's SC-0) carries the flag too
	var sd: Dictionary = JsonContent.load_json(SCORP + "dune_scorpion.json")
	var base_code := str(sd.get("variant_base", ""))
	assert_str(base_code).is_equal("SC-0")
	(sd["variants"][base_code] as Dictionary)["shelved"] = true
	var s := JsonContent.build("enemies", sd, SCORP) as EnemyDef
	assert_bool(s.variants.has(base_code)).is_true()
	assert_bool(s.variant_shelved(base_code)).is_true()
	assert_array(s.variant_codes()).not_contains([base_code])
	assert_array(s.variant_codes(true)).contains([base_code])
	# a creature with every look but one shelved reads as one look (no chips), yet keeps them all
	var one: Dictionary = JsonContent.load_json(SK + "skeleton.json")
	for code in all:
		if str(code) != "SK-A":
			(one["variants"][code] as Dictionary)["shelved"] = true
	var oe := JsonContent.build("enemies", one, SK) as EnemyDef
	assert_array(oe.variant_codes()).is_empty()
	assert_int(oe.variant_codes(true).size()).is_equal(all.size())
	assert_str(oe.variant_def("SK-D").variant_code).is_equal("SK-D")


func test_a_shelved_hero_look_is_out_of_the_codes_but_still_worn() -> void:
	var d: Dictionary = JsonContent.load_json(SOL + "solenne.json")
	var all: Array = (d["variants"] as Dictionary).keys()
	all.sort()
	assert_bool(all.has("SOL-C")).is_true()
	(d["variants"]["SOL-C"] as Dictionary)["shelved"] = true
	var c := JsonContent.build("characters", d, SOL) as CharacterDef
	assert_bool(c.variants.has("SOL-C")).is_true()
	assert_bool(c.variant_shelved("SOL-C")).is_true()
	assert_bool(c.variant_shelved("SOL-B")).is_false()
	assert_array(c.variant_codes()).not_contains(["SOL-C"])
	assert_int(c.variant_codes().size()).is_equal(all.size() - 1)
	assert_array(c.variant_codes(true)).is_equal(all)
	var v := c.variant_def("SOL-C")
	assert_object(v).is_not_same(c)
	assert_str(v.look_code()).is_equal("SOL-C")
	assert_object(v.sprite).is_not_null()
	assert_str(v.sprite_file).is_equal(str(d["variants"]["SOL-C"]["sprite"]))
	# the base look (SOL-A, the top-level strip) shelved: out of the list, worn when named
	var bd: Dictionary = JsonContent.load_json(SOL + "solenne.json")
	var base_code := str(bd.get("variant_base", ""))
	assert_str(base_code).is_equal("SOL-A")
	(bd["variants"][base_code] as Dictionary)["shelved"] = true
	var b := JsonContent.build("characters", bd, SOL) as CharacterDef
	assert_bool(b.variant_shelved(base_code)).is_true()
	assert_array(b.variant_codes()).not_contains([base_code])
	assert_array(b.variant_codes(true)).contains([base_code])
	assert_object(b.variant_def(base_code).sprite).is_not_null()
	# a base entry without a strip of its own (the top-level strip stands for it) carries the flag as well
	var td: Dictionary = JsonContent.load_json(SOL + "solenne.json")
	td["variants"] = {"SOL-A": {"note": "the top strip", "shelved": true},
		"SOL-B": {"note": "a walk", "sprite": str(td["variants"]["SOL-B"]["sprite"])},
		"SOL-C": {"note": "another", "sprite": str(td["variants"]["SOL-C"]["sprite"])}}
	var t := JsonContent.build("characters", td, SOL) as CharacterDef
	assert_bool(t.variant_shelved("SOL-A")).is_true()
	assert_array(t.variant_codes()).is_equal(["SOL-B", "SOL-C"])
	assert_array(t.variant_codes(true)).is_equal(["SOL-A", "SOL-B", "SOL-C"])
	# pass 101 (lane LOOKS): an entry holds its strip's path, the look worn loads it
	assert_str(t.variant_def("SOL-A").strip_path()).is_equal(str(t.variants["SOL-A"]["sprite"]))
	assert_object(t.variant_def("SOL-A").sprite).is_not_null()
	# the content as it is: nothing read as shelved by accident
	var plain := JsonContent.build("characters", JsonContent.load_json(SOL + "solenne.json"), SOL) as CharacterDef
	assert_array(plain.variant_codes()).is_equal(all)
	for code in all:
		assert_bool(plain.variant_shelved(str(code))).is_false()
	assert_bool(ArenaPanel.hero_has_shelved(plain)).is_false()
	assert_bool(ArenaPanel.hero_has_shelved(c)).is_true()
	assert_bool(ArenaPanel.hero_has_shelved(null)).is_false()


func test_every_def_in_the_registry_lists_at_least_its_open_looks() -> void:
	# variant_codes(true) holds every code variant_codes() does, for every creature and hero loaded
	for e: EnemyDef in Registry.enemies.values():
		assert_array(e.variant_codes(true)).override_failure_message(e.id).contains(e.variant_codes())
	for c: CharacterDef in Registry.characters.values():
		assert_array(c.variant_codes(true)).override_failure_message(c.id).contains(c.variant_codes())


# ---------------------------------------------------------------- the launch file

## A real Game (the scene) on a tool's launch file. Game._ready reads the file and, in the arena, spawns at once, so
## a test checks the spawn before any frame runs: the hero's gun fires from the first frame and a skeleton dies to
## one Revolver round (counting the living after a wait was a race in the whole suite).
func _game(launch: Dictionary) -> Game:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify(launch))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func _drawn(p: Player) -> Texture2D:
	return (p.sprite.material_override as ShaderMaterial).get_shader_parameter("sprite")


func test_the_launch_file_opens_the_arena_and_spawns_a_creature_in_a_look() -> void:
	var g := _game({"arena": true, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false,
		"spawn_enemy": "skeleton", "variant": "SK-B", "count": 2})
	# the arena, as the title's ARENA opens it, and the file read once
	assert_bool(Run.arena).is_true()
	assert_bool(Run.arena_next).is_false()
	assert_object(g.arena_panel).is_not_null()
	assert_bool(Save.sandboxed()).is_true()
	assert_bool(FileAccess.file_exists(LAUNCH)).is_false()
	assert_str(Run.character.id).is_equal("drifter")
	# two skeletons wearing SK-B (the game plays SK-A), near the hero
	var em: EnemyManager = g.enemies
	assert_int(em.alive_of("skeleton")).is_equal(2)
	var want: EnemyDef = Registry.enemy("skeleton").variant_def("SK-B")
	assert_str(want.variant_code).is_equal("SK-B")
	var n := 0
	for i in EnemyManager.MAX:
		if em.alive[i] != 1:
			continue
		var def: EnemyDef = em.types[em.type_idx[i]]["def"]
		if def.id != "skeleton":
			continue
		assert_str(def.variant_code).is_equal("SK-B")
		assert_str(def.sprite_file).is_equal(want.sprite_file)
		assert_str(def.type_key()).is_equal("skeleton@SK-B")
		assert_float(Vector2(em.pos[i].x, em.pos[i].z).distance_to(Vector2(g.player.global_position.x, g.player.global_position.z))).is_less(12.0)
		n += 1
	assert_int(n).is_equal(2)
	assert_bool(em.type_by_id.has("skeleton@SK-B")).is_true()
	# the Game outlives Warmup's deferred finish (a freed Game would take its callback) before auto_free takes it
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func test_the_launch_file_spawns_three_by_default_in_the_played_look() -> void:
	var g := _game({"arena": true, "character": "astro", "map": "red_canyon", "map_seed": 5, "analytics": false,
		"spawn_enemy": "goblin"})
	assert_object(g.arena_panel).is_not_null()
	var em: EnemyManager = g.enemies
	assert_int(em.alive_of("goblin")).is_equal(3)
	for i in EnemyManager.MAX:
		if em.alive[i] == 1 and (em.types[em.type_idx[i]]["def"] as EnemyDef).id == "goblin":
			# the def itself: the look the game plays
			assert_str((em.types[em.type_idx[i]]["def"] as EnemyDef).variant_code).is_equal("")
	assert_bool(em.type_by_id.has("goblin")).is_true()
	# the Game outlives Warmup's deferred finish (a freed Game would take its callback) before auto_free takes it
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func test_the_launch_file_shows_a_look_on_the_hero_without_keeping_it() -> void:
	var c: CharacterDef = Registry.character("solenne")
	# a look she does not wear by default (her JSON's `variant`), so the key is what puts it on her
	var worn := c.variant_def(Save.hero_look("solenne")).look_code()
	var pick := ""
	for code in c.variant_codes():
		if str(code) != worn:
			pick = str(code)
			break
	assert_str(pick).is_not_empty()
	var g := _game({"arena": true, "character": "solenne", "map": "red_canyon", "map_seed": 5, "analytics": false, "look": pick})
	assert_object(g.arena_panel).is_not_null()
	assert_str(Run.character.id).is_equal("solenne")
	assert_str(g.player.look_code()).is_equal(pick)
	assert_object(_drawn(g.player)).is_same(c.variant_def(pick).sprite)
	# for this visit only: nothing kept, in the sandbox or behind it
	assert_str(Save.hero_look("solenne")).is_equal("")
	var backup = Save.get("_sandbox_backup")
	if backup is Dictionary:
		assert_str(str((backup as Dictionary).get("hero_look", {}).get("solenne", ""))).is_equal("")
	# a code she has not got leaves her in her own look
	g.player.show_look("SOL-NOPE")
	assert_str(g.player.look_code()).is_equal(worn)
	# the Game outlives Warmup's deferred finish (a freed Game would take its callback) before auto_free takes it
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func test_the_launch_file_without_arena_still_starts_a_run_as_before() -> void:
	var g := _game({"weapon": "boomstick", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false})
	assert_bool(Run.arena).is_false()
	assert_object(g.arena_panel).is_null()
	assert_bool(Save.sandboxed()).is_false()
	assert_str(Run.character.id).is_equal("drifter")
	var w := Run.weapon_instance("boomstick")
	assert_object(w).is_not_null()
	assert_int(w.level).is_equal(2)
	assert_bool(FileAccess.file_exists(LAUNCH)).is_false()
	# the Game outlives Warmup's deferred finish (a freed Game would take its callback) before auto_free takes it
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


func test_spawn_enemy_n_puts_n_near_the_hero_plain() -> void:
	var g := _game({"arena": true, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false})
	var em: EnemyManager = g.enemies
	assert_int(em.alive_of("skeleton")).is_equal(0)
	g.arena_panel.spawn_enemy_n(Registry.enemy("skeleton"), 4)
	assert_int(em.alive_of("skeleton")).is_equal(4)
	# a count below one still spawns one
	g.arena_panel.spawn_enemy_n(Registry.enemy("goblin"), 0)
	assert_int(em.alive_of("goblin")).is_equal(1)
	for i in EnemyManager.MAX:
		if em.alive[i] != 1:
			continue
		var def: EnemyDef = em.types[em.type_idx[i]]["def"]
		if def.id == "skeleton" or def.id == "goblin":
			# no elite modifier, not held, near (4-6.5 m up-screen, up to 3 m aside)
			assert_int(em.elite_idx[i]).is_equal(-1)
			assert_float(em.speed[i]).is_greater(0.0)
			assert_float(Vector2(em.pos[i].x, em.pos[i].z).distance_to(Vector2(g.player.global_position.x, g.player.global_position.z))).is_less(12.0)
	# the Game outlives Warmup's deferred finish (a freed Game would take its callback) before auto_free takes it
	await get_tree().create_timer(0.6).timeout
	g.set_paused(false)


# ---------------------------------------------------------------- gen_placeholders only=

static func _rm_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


static func _pngs(folder: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(folder):
		if str(f).ends_with(".png"):
			out.append(str(f))
	out.sort()
	return out


## A temp copy of a few content JSONs under user://, never the content itself.
func _temp_content() -> void:
	_rm_tree(TMP)
	for pair in [["enemies", "goblin"], ["enemies", "skeleton"], ["passives", "haste"], ["weapons", "boomstick"]]:
		var folder := "%s%s/%s/" % [TMP, pair[0], pair[1]]
		DirAccess.make_dir_recursive_absolute(folder)
		var text := FileAccess.get_file_as_string("res://content/%s/%s/%s.json" % [pair[0], pair[1], pair[1]])
		var f := FileAccess.open(folder + str(pair[1]) + ".json", FileAccess.WRITE)
		f.store_string(text)
		f.close()


func test_gen_placeholders_only_is_read_as_import_json_reads_it() -> void:
	assert_dict(GEN.parse_only(PackedStringArray([]))).is_empty()
	assert_dict(GEN.parse_only(PackedStringArray(["force"]))).is_empty()
	assert_dict(GEN.parse_only(PackedStringArray(["only=enemies/goblin"]))).is_equal({"enemies": ["goblin"]})
	assert_dict(GEN.parse_only(PackedStringArray(["only=enemies/a,enemies/b, passives/ ,mutations"]))).is_equal({"enemies": ["a", "b"], "passives": [], "mutations": []})
	# a bare type beats the ids given for it, whichever comes first
	assert_dict(GEN.parse_only(PackedStringArray(["only=enemies,enemies/a"]))).is_equal({"enemies": []})
	assert_dict(GEN.parse_only(PackedStringArray(["only=enemies/a,enemies"]))).is_equal({"enemies": []})
	assert_dict(GEN.parse_only(PackedStringArray(["force", "only=bosses/brander"]))).is_equal({"bosses": ["brander"]})


func test_gen_placeholders_only_writes_the_named_folders_on_a_copy() -> void:
	_temp_content()
	var only: Dictionary = GEN.parse_only(PackedStringArray(["only=enemies/goblin"]))
	# the goblin's icon and strip, nothing else
	assert_int(GEN.write_for(TMP, only, false)).is_equal(2)
	var gob: Dictionary = JsonContent.load_json(TMP + "enemies/goblin/goblin.json")
	var icon := str(gob.get("icon", "goblin_icon.png"))
	var strip := str(gob.get("sprite", "goblin_sprite.png"))
	assert_array(_pngs(TMP + "enemies/goblin/")).contains_exactly_in_any_order([icon, strip])
	assert_array(_pngs(TMP + "enemies/skeleton/")).is_empty()
	assert_array(_pngs(TMP + "passives/haste/")).is_empty()
	assert_array(_pngs(TMP + "weapons/boomstick/")).is_empty()
	# the icon is the placeholder's size, the strip one row of the creature's frames
	var img := Image.load_from_file(TMP + "enemies/goblin/" + icon)
	assert_object(img).is_not_null()
	assert_int(img.get_width()).is_equal(256)
	var def := JsonContent.build("enemies", gob, TMP + "enemies/goblin/") as EnemyDef
	var simg := Image.load_from_file(TMP + "enemies/goblin/" + strip)
	assert_int(simg.get_height()).is_equal(def.frame_px)
	assert_int(simg.get_width()).is_equal(def.frame_px * def.total_frames())
	# a second run writes nothing (the files are there); force writes them again
	assert_int(GEN.write_for(TMP, only, false)).is_equal(0)
	assert_int(GEN.write_for(TMP, only, true)).is_equal(2)
	# a bare type is every folder of it: the skeleton's two now
	assert_int(GEN.write_for(TMP, GEN.parse_only(PackedStringArray(["only=enemies"])), false)).is_equal(2)
	assert_int(_pngs(TMP + "enemies/skeleton/").size()).is_equal(2)
	# a type with no folder here, and an id that is not there: nothing, quietly
	assert_int(GEN.write_for(TMP, {"bosses": ["brander"]}, false)).is_equal(0)
	assert_int(GEN.write_for(TMP, {"enemies": ["nobody"]}, false)).is_equal(0)
	# no filter: everything that lacks art, an icon each for the passive and the weapon
	assert_int(GEN.write_for(TMP, {}, false)).is_equal(2)
	assert_int(_pngs(TMP + "passives/haste/").size()).is_equal(1)
	assert_int(_pngs(TMP + "weapons/boomstick/").size()).is_equal(1)
	# the content itself untouched: the tool's root is a constant
	assert_str(GEN.ROOT).is_equal("res://content/")
	_rm_tree(TMP)


# ---------------------------------------------------------------- fifty looks in the arena

## A..Z, then AA.. (the codes a look list of fifty takes).
static func _letters(i: int) -> String:
	var s := ""
	var n := i
	while true:
		s = char(65 + n % 26) + s
		n = int(floor(float(n) / 26.0)) - 1
		if n < 0:
			break
	return s


func _hero(def: CharacterDef) -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	p.setup(def)
	add_child(p)
	return p


## A bare Game in the arena round a real hero: what the HERO tab needs (pass55_hv's pattern).
func _arena(def: CharacterDef) -> Game:
	Run.arena = true
	var game: Game = auto_free(Game.new())
	game.player = _hero(def)
	return game


func _panel(game: Game, tab: String) -> ArenaPanel:
	var panel: ArenaPanel = auto_free(ArenaPanel.new())
	panel.game = game
	add_child(panel)
	panel.set_process(false)
	panel._tab = tab
	panel._refresh()
	return panel


## Solenne with fifty looks (and `shelved` more, shelved), every one her own strip.
func _fifty_hero(shelved: int) -> CharacterDef:
	var sol: CharacterDef = Registry.character("solenne")
	var c: CharacterDef = sol.duplicate()
	var vs: Dictionary = {}
	for i in 50 + shelved:
		vs["FL-" + _letters(i)] = {"sprite": sol.sprite, "sprite_file": sol.sprite_file, "anims": sol.anims, "fps": sol.fps,
			"strip_cols": sol.strip_cols, "frame_px": sol.frame_px, "icon": sol.icon, "note": "fake look %d" % i, "shelved": i >= 50}
	c.variants = vs
	c.variant = "FL-A"
	return c


## A creature with fifty looks (and `shelved` more, shelved) built from the skeleton's JSON, every look a real strip.
func _fifty_creature(shelved: int) -> EnemyDef:
	var d: Dictionary = JsonContent.load_json(SK + "skeleton.json")
	var files: Array = []
	for code in (d["variants"] as Dictionary).keys():
		files.append(str(d["variants"][code]["sprite"]))
	d["id"] = "p66_fifty"
	d["name"] = "Fifty Looks"
	var vs: Dictionary = {}
	for i in 50 + shelved:
		vs["FL-" + _letters(i)] = {"sprite": files[i % files.size()], "note": "fake look %d" % i, "shelved": i >= 50}
	d["variants"] = vs
	d["variant_base"] = ""
	d["variant"] = "FL-A"
	return JsonContent.build("enemies", d, SK) as EnemyDef


func _notes(panel: ArenaPanel, prefix: String) -> int:
	var n := 0
	for l in panel._content.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with(prefix) and (l as Label).text.contains("fake look"):
			n += 1
	return n


func test_fifty_hero_looks_all_get_a_chip_in_a_flow() -> void:
	var c := _fifty_hero(3)
	assert_int(c.variant_codes().size()).is_equal(50)
	assert_int(c.variant_codes(true).size()).is_equal(53)
	var game := _arena(c)
	Run.character = c
	var panel := _panel(game, "hero")
	var row: Control = panel._content.find_child("HeroLooks", true, false)
	assert_object(row).is_not_null()
	assert_bool(row is HFlowContainer).is_true()
	var chips: Array = row.get_children().filter(func(n: Node) -> bool: return n is Button and str(n.name).begins_with("Look_"))
	assert_int(chips.size()).is_equal(50)
	for code in c.variant_codes():
		assert_object(panel._content.find_child("Look_" + str(code), true, false)).override_failure_message(str(code)).is_not_null()
	# the shelved ones are not there
	assert_object(panel._content.find_child("Look_FL-AY", true, false)).is_null()
	# more than eight looks: only the lit chip's note shows
	assert_str((panel._content.find_child("Look_FL-A", true, false) as Button).text).is_equal("FL-A ● · RUNS")
	assert_int(_notes(panel, "FL-")).is_equal(1)
	# the Shelved looks choice is there; Show lists them dimmed
	var choice: Control = panel._content.find_child("ShelvedLooksHero", true, false)
	assert_object(choice).is_not_null()
	panel._show_shelved = true
	panel._refresh()
	row = panel._content.find_child("HeroLooks", true, false)
	chips = row.get_children().filter(func(n: Node) -> bool: return n is Button and str(n.name).begins_with("Look_"))
	assert_int(chips.size()).is_equal(53)
	var shelved_chip: Button = panel._content.find_child("Look_FL-AY", true, false)
	assert_object(shelved_chip).is_not_null()
	assert_float(shelved_chip.modulate.a).is_less(1.0)
	assert_float((panel._content.find_child("Look_FL-B", true, false) as Button).modulate.a).is_equal(1.0)
	# a hero with no shelved look gets no choice; with eight or fewer looks every note shows
	var few := _fifty_hero(0)
	var keep: Dictionary = {}
	for code in ["FL-A", "FL-B", "FL-C"]:
		keep[code] = few.variants[code]
	few.variants = keep
	var game2 := _arena(few)
	Run.character = few
	var panel2 := _panel(game2, "hero")
	assert_object(panel2._content.find_child("ShelvedLooksHero", true, false)).is_null()
	assert_int(panel2._content.find_child("HeroLooks", true, false).get_children().size()).is_equal(3)
	assert_int(_notes(panel2, "FL-")).is_equal(3)
	await get_tree().process_frame


func test_fifty_creature_looks_fold_per_creature_and_open_into_a_flow() -> void:
	var fifty := _fifty_creature(2)
	assert_int(fifty.variant_codes().size()).is_equal(50)
	assert_int(fifty.variant_codes(true).size()).is_equal(52)
	Registry.enemies["p66_fifty"] = fifty
	var with_looks: int = Registry.enemies.values().filter(func(d: EnemyDef) -> bool: return not d.variant_codes().is_empty()).size()
	assert_int(with_looks).is_greater(ArenaPanel.LOOKS_FOLD)
	var game := _arena(Registry.character("astro"))
	var panel := _panel(game, "enemy")
	# folded: a header a creature, no chips yet
	var head: Button = panel._content.find_child("LooksHead_p66_fifty", true, false)
	assert_object(head).is_not_null()
	assert_str(head.text).contains("Fifty Looks")
	assert_str(head.text).contains("50 looks")
	assert_object(panel._content.find_child("Variants_p66_fifty", true, false)).is_null()
	assert_object(panel._content.find_child("LooksHead_skeleton", true, false)).is_not_null()
	assert_object(panel._content.find_child("Variants_skeleton", true, false)).is_null()
	# a tap opens one
	head.pressed.emit()
	var flow: Control = panel._content.find_child("Variants_p66_fifty", true, false)
	assert_object(flow).is_not_null()
	assert_bool(flow is HFlowContainer).is_true()
	var chips: Array = flow.get_children().filter(func(n: Node) -> bool: return n is Button and str(n.name).begins_with("Variant_p66_fifty_"))
	assert_int(chips.size()).is_equal(50)
	assert_object(panel._content.find_child("Variants_skeleton", true, false)).is_null()
	# the lit chip and only its note
	assert_str((panel._content.find_child("Variant_p66_fifty_FL-A", true, false) as Button).text).is_equal("FL-A ●")
	assert_str((panel._content.find_child("Variant_p66_fifty_FL-B", true, false) as Button).text).is_equal("FL-B")
	assert_int(_notes(panel, "FL-")).is_equal(1)
	# the Shelved looks choice; Show lists the two more, dimmed
	assert_object(panel._content.find_child("ShelvedLooks", true, false)).is_not_null()
	panel._show_shelved = true
	panel._refresh()
	flow = panel._content.find_child("Variants_p66_fifty", true, false)
	chips = flow.get_children().filter(func(n: Node) -> bool: return n is Button and str(n.name).begins_with("Variant_p66_fifty_"))
	assert_int(chips.size()).is_equal(52)
	assert_float((panel._content.find_child("Variant_p66_fifty_FL-AY", true, false) as Button).modulate.a).is_less(1.0)
	assert_float((panel._content.find_child("Variant_p66_fifty_FL-B", true, false) as Button).modulate.a).is_equal(1.0)
	panel._show_shelved = false
	# the skeleton opened too: five chips and every note (eight or fewer)
	(panel._content.find_child("LooksHead_skeleton", true, false) as Button).pressed.emit()
	var sk: Control = panel._content.find_child("Variants_skeleton", true, false)
	assert_object(sk).is_not_null()
	var skd: EnemyDef = Registry.enemy("skeleton")
	assert_int(sk.get_children().size()).is_equal(skd.variant_codes().size())
	var sk_notes := 0
	for code in skd.variant_codes():
		var b: Button = panel._content.find_child("Variant_skeleton_" + str(code), true, false)
		assert_object(b).override_failure_message(str(code)).is_not_null()
		assert_str(b.text).is_equal(str(code) + (" ●" if str(code) == skd.variant else ""))
		if str((skd.variants[code] as Dictionary).get("note", "")) != "":
			sk_notes += 1
	var shown := 0
	for l in panel._content.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("SK-"):
			shown += 1
	assert_int(shown).is_equal(sk_notes)
	# a second tap closes it again
	(panel._content.find_child("LooksHead_p66_fifty", true, false) as Button).pressed.emit()
	assert_object(panel._content.find_child("Variants_p66_fifty", true, false)).is_null()
	# with few creatures carrying looks the section is not folded: the chips come at once, the name before them
	var keep: Dictionary = Registry.enemies
	Registry.enemies = {"p66_fifty": fifty, "skeleton": keep["skeleton"], "goblin": keep["goblin"]}
	panel._refresh()
	assert_object(panel._content.find_child("LooksHead_p66_fifty", true, false)).is_null()
	flow = panel._content.find_child("Variants_p66_fifty", true, false)
	assert_object(flow).is_not_null()
	assert_bool(flow is HFlowContainer).is_true()
	assert_bool(flow.get_child(0) is Label).is_true()
	assert_str((flow.get_child(0) as Label).text).is_equal("Fifty Looks")
	assert_int(flow.get_children().size()).is_equal(51)
	assert_object(panel._content.find_child("Variants_skeleton", true, false)).is_not_null()
	Registry.enemies = keep
	Registry.enemies.erase("p66_fifty")
	await get_tree().process_frame


func test_no_shelved_look_means_no_choice_and_the_chips_as_before() -> void:
	var game := _arena(Registry.character("astro"))
	var panel := _panel(game, "enemy")
	# the content carries no shelved look today, so the switch is not offered (it appears with the first one)
	var some := false
	for d: EnemyDef in Registry.enemies.values():
		for code in d.variants.keys():
			if d.variant_shelved(str(code)):
				some = true
	assert_bool(panel._content.find_child("ShelvedLooks", true, false) != null).is_equal(some)
	# every creature with looks has a header (folded) or a flow, and tapping a chip spawns that look (the AGAIN label)
	for d: EnemyDef in Registry.enemies.values():
		if d.variant_codes().is_empty():
			continue
		var head: Control = panel._content.find_child("LooksHead_" + d.id, true, false)
		var flow: Control = panel._content.find_child("Variants_" + d.id, true, false)
		assert_bool(head != null or flow != null).override_failure_message(d.id).is_true()
	await get_tree().process_frame
