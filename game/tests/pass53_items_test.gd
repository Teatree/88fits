## Pass 53, lane P (Garry's tenth list: items, perks and polish): the common plate is a light grey (every level-1 weapon
## and line wears it), the HUD's weapon group sits against the row's left edge and the line group against its right edge
## with no brass divider between them (a narrow row splits into a left-aligned weapon row and a right-aligned line row),
## the live main menu is the default and a pass 52 save steps to it once (Save version 5), a clean save opens on the
## Drifter and no once-flag moves him, the barrel's lid is round and its hoops stand where the model puts them, three
## perks are hidden but kept (Suit Seals, Serenade, Bounty Hunter), and Supply Drop's pod leaves only a heart or a
## magnet pulse over a halved blast.
extends GdUnitTestSuite

const DIR := "user://test_saves/pass53"
var _dir_before := ""
var _settings_before: Dictionary = {}
var _last_before := ""


func before() -> void:
	Save.flush()
	_dir_before = Save.dir
	_settings_before = Settings.to_dict()
	_last_before = str(Save.data.get("last_character", Save.DEFAULT_HERO))
	Save.dir = DIR


func after() -> void:
	_clear()
	Save.dir = _dir_before
	Save.data = Save._default()
	Save.data["last_character"] = _last_before
	Save._dirty = false
	Settings.from_dict(_settings_before)


func before_test() -> void:
	_clear()
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Run.arena = false
	Run.end()
	Settings.from_dict(_settings_before)


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _clear() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))


func _write(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _repo_file(rel: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("..").path_join(rel))


# ---------------------------------------------------------------- the common plate

func test_the_common_plate_is_a_light_grey() -> void:
	# Garry: "Change the White of Common item bg to a light gray. (For Weapons and Line Items as well)"
	var c: Color = W.RARITY_PLATE["common"]
	assert_str(c.to_html(false)).is_equal("d2cfc7")
	# grey: the channels within a few hundredths of each other; darker than the paper it sits on, still light
	assert_float(maxf(maxf(c.r, c.g), c.b) - minf(minf(c.r, c.g), c.b)).is_less(0.05)
	assert_float(c.get_luminance()).is_less(W.PAPER.get_luminance())
	assert_float(c.get_luminance()).is_greater(0.6)
	# every level-1 weapon and line wears it, and a common passive item
	assert_bool(W.level_fill(1).is_equal_approx(c)).is_true()
	assert_bool(W.level_fill(0).is_equal_approx(c)).is_true()
	assert_bool(W.plate_fill(Registry.weapon("peashooter"), 1).is_equal_approx(c)).is_true()
	assert_bool(W.plate_fill(Registry.passive("brawn"), 1).is_equal_approx(c)).is_true()
	var common_item: PassiveDef = null
	for p: PassiveDef in Registry.sorted_passives_only():
		if W.rarity_of(p) == "common":
			common_item = p
			break
	assert_object(common_item).is_not_null()
	assert_bool(W.plate_fill(common_item, 3).is_equal_approx(c)).is_true()
	var plate: WPlate = auto_free(WPlate.new().for_def(Registry.weapon("peashooter"), 72.0, false, 1))
	assert_bool(plate.fill.is_equal_approx(c)).is_true()
	# the other tiers as they were
	assert_str(W.RARITY_PLATE["uncommon"].to_html(false)).is_equal("8cc97a")
	assert_str(W.RARITY_PLATE["legendary"].to_html(false)).is_equal("e0a060")
	# the bible's fallback names the same grey (it reads W.gd when it can)
	var bible := _repo_file("tools/make_bible.py")
	assert_bool(bible.contains("\"common\": \"#D2CFC7\"")).is_true()


# ---------------------------------------------------------------- the HUD's slot groups

func test_the_hud_s_weapons_sit_left_and_its_lines_right_with_nothing_between() -> void:
	# Garry: "Don't center the 2 Slot groups, make the stick to their sides, Lines on the right weapons on the left"
	_start()
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	Run.add_weapon(Registry.weapon("peashooter"), 5)
	Run.add_or_level_passive("brawn")
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	await get_tree().process_frame
	var plates: Array = hud._slots.get_children()
	assert_int(plates.size()).is_equal(10)
	var avail := hud.get_viewport_rect().size.x - 72.0
	# one row: the first weapon plate at its left edge, the last line plate's right edge at avail
	assert_float((plates[0] as WPlate).position.x).is_equal(0.0)
	assert_float((plates[9] as WPlate).position.x + (plates[9] as WPlate).side).is_equal_approx(avail, 0.01)
	for p: WPlate in plates:
		assert_float(p.position.y).is_equal(0.0)
		assert_float(p.side).is_equal(72.0)
	# 8 px inside each group; between the groups whatever the row has left (224 px at 1080), more than the old 48
	for i in range(1, 10):
		var gap: float = (plates[i] as WPlate).position.x - ((plates[i - 1] as WPlate).position.x + 72.0)
		assert_float(gap).override_failure_message("gap %d" % i).is_equal_approx(avail - 784.0 if i == 5 else 8.0, 0.01)
	assert_float(avail - 784.0).is_greater(HUD.GROUP_GAP)
	# the row starts at the 36 px margin, so both groups are 36 px off the screen's edges
	assert_float(hud._slots.position.x).is_equal(36.0)
	# no divider: neither the node nor its constants
	assert_object(hud.get("_divider")).is_null()
	assert_object(hud.find_child("SlotDivider", true, false)).is_null()
	var src := FileAccess.get_file_as_string("res://ui/HUD.gd")
	assert_bool(src.contains("DIVIDER_W")).is_false()
	assert_bool(src.contains("_divider")).is_false()
	# the weapons first, then the lines, the held plates solid and in their level's colour
	assert_bool(bool(hud._slot_nodes.has("boomstick")) and bool(hud._slot_nodes.has("brawn"))).is_true()
	assert_int(plates.find(hud._slot_nodes["boomstick"])).is_less(5)
	assert_int(plates.find(hud._slot_nodes["brawn"])).is_greater_equal(5)
	assert_float((hud._slot_nodes["boomstick"] as WPlate).plate_alpha).is_equal(1.0)
	assert_bool((hud._slot_nodes["brawn"] as WPlate).fill.is_equal_approx(W.RARITY_PLATE["common"])).is_true()
	# a row's least width is unchanged: five and five need 832 px before they squeeze or split
	assert_float(HUD._row_width(HUD.slot_specs([], 5, [], [], 5, []))).is_equal(832.0)


func test_a_narrow_row_splits_into_a_left_weapon_row_and_a_right_line_row() -> void:
	_start()
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("boomstick"), 1)
	Run.add_or_level_passive("brawn")
	# a 700 px wide view: 832 x 0.85 = 707 is more than its 628 between the margins, so each group takes a row
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(700, 1400)
	add_child(vp)
	var hud := HUD.new()
	vp.add_child(hud)
	await get_tree().process_frame
	assert_float(hud.get_viewport_rect().size.x).is_equal(700.0)
	var avail := 700.0 - 72.0
	var plates: Array = hud._slots.get_children()
	assert_int(plates.size()).is_equal(10)
	var weapons: Array = plates.slice(0, 5)
	var lines: Array = plates.slice(5, 10)
	# the weapons' row on top, from the left edge, full size (392 px fits in 628)
	assert_float((weapons[0] as WPlate).position.x).is_equal(0.0)
	for p: WPlate in weapons:
		assert_float(p.position.y).is_equal(0.0)
		assert_float(p.side).is_equal(72.0)
	assert_float((weapons[4] as WPlate).position.x + 72.0).is_equal_approx(392.0, 0.01)
	# the lines' row under it, ending at the right edge
	var y2: float = (lines[0] as WPlate).position.y
	assert_float(y2).is_equal_approx(72.0 + HUD.ROW_GAP, 0.01)
	for p: WPlate in lines:
		assert_float(p.position.y).is_equal_approx(y2, 0.01)
		assert_float(p.side).is_equal(72.0)
	assert_float((lines[0] as WPlate).position.x).is_equal_approx(avail - 392.0, 0.01)
	assert_float((lines[4] as WPlate).position.x + 72.0).is_equal_approx(avail, 0.01)
	# the strip reaches under both rows
	assert_float(hud._slots_bottom).is_greater(HUD.SLOT_Y + 72.0 + HUD.ROW_GAP + 72.0)
	assert_float(HUD.band_h).is_greater_equal(hud._slots_bottom + 14.0)


# ---------------------------------------------------------------- the live menu

func test_the_live_menu_is_the_default_and_a_pass_52_save_steps_to_it_once() -> void:
	# Garry: "By default set the Main Menu to be the new one - the one with the live heroes"
	var script: GDScript = load("res://core/autoload/Settings.gd")
	var s: Node = auto_free(script.new())
	assert_str(s.menu_style).is_equal("live")
	assert_str(Settings.MENU_STYLE_DEFAULT).is_equal("live")
	s.from_dict({})
	assert_str(s.menu_style).is_equal("live")
	s.from_dict({"menu_style": "painted"})
	assert_str(s.menu_style).is_equal("painted")
	s.from_dict({"menu_style": "fancy"})
	assert_str(s.menu_style).is_equal("live")
	# a save written under pass 52 (version 4) carries "painted": version 5 sets it to live, once
	assert_int(Save.VERSION).is_equal(5)
	# (pass 69, lane UI: Calavera is a hero to buy; this save bought him, so he stays its last hero)
	_write(Save.path(), JSON.stringify({"version": 4, "gold": 12, "once": ["seen_migrated", "hero_astro"], "last_character": "calavera",
		"heroes_owned": ["calavera"], "settings": {"menu_style": "painted", "damage_numbers": true, "music_volume": 0.4}}))
	Save.load_save()
	assert_str(Save.loaded_from).is_equal("save")
	assert_int(int(Save.data["version"])).is_equal(5)
	assert_str(str(Save.data["settings"]["menu_style"])).is_equal("live")
	assert_str(Settings.menu_style).is_equal("live")
	# the other settings and the rest of the save as they were, and the stepped-up file asked onto the disk
	assert_float(Settings.music_volume).is_equal_approx(0.4, 0.0001)
	assert_int(Save.gold()).is_equal(12)
	assert_str(str(Save.data["last_character"])).is_equal("calavera")
	assert_bool(Save._dirty).is_true()
	# a save from before the setting existed steps the same way
	_write(Save.path(), JSON.stringify({"version": 3, "once": ["seen_migrated"], "settings": {"music_volume": 0.2}}))
	Save.load_save()
	assert_str(str(Save.data["settings"]["menu_style"])).is_equal("live")
	assert_bool(bool(Save.data["settings"]["damage_numbers"])).is_true()
	assert_str(Settings.menu_style).is_equal("live")
	# from here on the developer menu's pick sticks: a version-5 file with painted stays painted
	_write(Save.path(), JSON.stringify({"version": 5, "once": ["seen_migrated"], "settings": {"menu_style": "painted"}}))
	Save.load_save()
	assert_str(str(Save.data["settings"]["menu_style"])).is_equal("painted")
	assert_str(Settings.menu_style).is_equal("painted")


# ---------------------------------------------------------------- the Drifter

func test_a_clean_save_opens_on_the_drifter_and_nothing_moves_him() -> void:
	# Garry: "By Default Drifter hero is selected (on a clean save I mean)"
	assert_str(Save.DEFAULT_HERO).is_equal("drifter")
	assert_str(str(Save._default()["last_character"])).is_equal("drifter")
	assert_bool(Registry.is_unlocked("character", "drifter")).is_true()
	assert_bool(Registry.characters.has("drifter") and not Registry.character("drifter").hidden).is_true()
	# no file at all: a clean boot
	Save.load_save()
	assert_str(Save.loaded_from).is_equal("new")
	assert_str(str(Save.data["last_character"])).is_equal("drifter")
	assert_bool((Save.data["once"] as Array).has("hero_astro")).is_false()
	var src := FileAccess.get_file_as_string("res://core/autoload/Save.gd")
	assert_bool(src.contains("\"hero_astro\"")).is_false()
	# an existing save keeps the hero it last played, whether or not it carries the old flag
	_write(Save.path(), JSON.stringify({"version": 5, "once": ["hero_astro"], "last_character": "astro"}))
	Save.load_save()
	assert_str(str(Save.data["last_character"])).is_equal("astro")
	_write(Save.path(), JSON.stringify({"version": 5, "once": [], "last_character": "calavera", "heroes_owned": ["calavera"]}))
	Save.load_save()
	assert_str(str(Save.data["last_character"])).is_equal("calavera")
	# pass 69 (lane UI): a last hero the save does not own (to be bought now) falls to the Drifter
	_write(Save.path(), JSON.stringify({"version": 5, "once": [], "last_character": "calavera"}))
	Save.load_save()
	assert_str(str(Save.data["last_character"])).is_equal("drifter")
	# a save without the key, or naming a hero that is gone, falls to the Drifter
	_write(Save.path(), JSON.stringify({"version": 5, "once": []}))
	Save.load_save()
	assert_str(str(Save.data["last_character"])).is_equal("drifter")
	_write(Save.path(), JSON.stringify({"version": 5, "once": [], "last_character": "nobody"}))
	Save.load_save()
	assert_str(str(Save.data["last_character"])).is_equal("drifter")
	# the title's carousel opens on him
	Save.data = Save._default()
	Settings.menu_style = "painted"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str((t._heroes[t._index] as CharacterDef).id).is_equal("drifter")
	assert_str(str(Save.data["last_character"])).is_equal("drifter")
	t.visible = false
	await get_tree().process_frame


# ---------------------------------------------------------------- the barrel

func test_the_barrel_s_lid_is_round_and_its_hoops_stand_at_their_height() -> void:
	# Garry: "the barrels have a square top for some reason even though they're cylindrical. Give them a round top please".
	# The GLB itself, read fresh (the import cache may be older than the file)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	assert_int(doc.append_from_file("res://art/props/barrel.glb", st)).is_equal(OK)
	var root: Node = doc.generate_scene(st)
	assert_object(root).is_not_null()
	var body: MeshInstance3D = null
	var hoops: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if str(n.name).begins_with("Body"):
			body = n
		elif str(n.name).begins_with("Hoops"):
			hoops = n
	assert_object(body).is_not_null()
	assert_object(hoops).is_not_null()
	# every vertex above the lid (the planks) lies within the lid's 0.245 m disc: the top's silhouette is round (the old
	# planks were full boxes reaching 0.28 m out at their corners)
	var above := 0
	var reach := 0.0
	for s in body.mesh.get_surface_count():
		var verts: PackedVector3Array = body.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y > 0.9 + 0.001:
				above += 1
				var r := Vector2(v.x, v.z).length()
				reach = maxf(reach, r)
				assert_float(r).override_failure_message("plank vertex at %s" % str(v)).is_less_equal(0.245 + 0.002)
	assert_int(above).is_greater_equal(3 * 14)
	assert_float(reach).is_greater(0.2)
	# the hoops' node stands where Blender's join left its origin, the lowest hoop's height
	var hxf: Transform3D = BarrelField.part_transform(root, hoops)
	assert_float(hxf.origin.y).is_greater_equal(0.09)
	root.free()
	# BarrelField applies it (it took the mesh alone and drew every hoop 12.6 cm too low)
	_start()
	var bf: BarrelField = auto_free(BarrelField.new())
	var meshes := bf._meshes()
	assert_bool(meshes.has("hoops_xf") and meshes.has("body_xf")).is_true()
	var hy: float = (meshes["hoops_xf"] as Transform3D).origin.y
	assert_float(hy).is_greater_equal(0.09)
	assert_float((meshes["body_xf"] as Transform3D).origin.y).is_equal_approx(0.0, 0.001)
	# a field on a flat map: every hoop instance sits that high over its barrel's spot, every body on the ground (the
	# headless renderer keeps no MultiMesh instance transforms, so the transforms setup writes are read off the function
	# that makes them)
	var ms := GDScript.new()
	ms.source_code = "extends MapBase\nvar flats_radius := 16.0\n"
	ms.reload()
	var map: Node3D = auto_free(Node3D.new())
	map.set_script(ms)
	add_child(map)
	var game: Node = auto_free(Node.new())
	add_child(game)
	var field: BarrelField = auto_free(BarrelField.new())
	add_child(field)
	field.setup(game, map)
	assert_int(field.pos.size()).is_equal(BarrelField.COUNT)
	assert_float((field._part_xf["hoops"] as Transform3D).origin.y).is_equal_approx(hy, 0.0001)
	for k in field.pos.size():
		var hoop_xf := field.instance_transform(k, "hoops")
		var body_xf := field.instance_transform(k, "body")
		assert_float(hoop_xf.origin.y - field.pos[k].y).override_failure_message("barrel %d" % k).is_equal_approx(hy, 0.001)
		assert_float(body_xf.origin.y - field.pos[k].y).is_equal_approx(0.0, 0.001)
		# on the barrel's spot, turned as the barrel is
		assert_bool(body_xf.origin.is_equal_approx(field.pos[k])).is_true()
		assert_bool(hoop_xf.basis.is_equal_approx(field.barrel_transform(k).basis)).is_true()
		assert_bool(Vector2(hoop_xf.origin.x, hoop_xf.origin.z).is_equal_approx(Vector2(field.pos[k].x, field.pos[k].z))).is_true()
	# a field built by hand, no model: the part transforms fall back to identity
	var bare: BarrelField = auto_free(BarrelField.new())
	bare.pos.append(Vector3(3, 1, 2))
	assert_bool(bare.instance_transform(0, "hoops").origin.is_equal_approx(Vector3(3, 1, 2))).is_true()
	# the model's script says so too
	var py := _repo_file("tools/blender_barrel.py")
	assert_bool(py.contains("plank_ring(")).is_true()
	assert_bool(py.contains("LID_R = 0.245")).is_true()


# ---------------------------------------------------------------- perks

func test_three_perks_are_hidden_but_kept() -> void:
	# Garry: "Hide (make it so it's hidden, but I can bring it back if I want to)"
	for pair in [["suit_seals", "astro"], ["serenade", "calavera"], ["bounty_hunter", "drifter"]]:
		var id: String = pair[0]
		var pk: PerkDef = Registry.perks.get(id)
		assert_object(pk).override_failure_message(id).is_not_null()
		assert_bool(pk.hidden).override_failure_message(id + " not hidden").is_true()
		assert_bool(Registry.is_hidden(pk)).is_true()
		assert_str(pk.hero).is_equal(pair[1])
		assert_bool(Registry.perks_of(pair[1]).has(pk)).is_false()
		# the way back is written in the JSON (a JSON has no comments)
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://content/perks/%s/%s.json" % [id, id]))
		assert_bool(bool(j.get("hidden", false))).is_true()
		assert_str(str(j.get("note", ""))).contains("remove hidden")
	# the heroes keep their perks in play (pass 54: eighteen in the content, Solenne's Afterglow and Sunburn in play, her
	# Lingering Light and Long Day hidden); pass 66: the rule in place of the counts (the Level Editor adds perks and
	# heroes): every perk names a hero that is there and every hero in play has at least one
	for pk: PerkDef in Registry.perks.values():
		assert_object(Registry.character(pk.hero)).override_failure_message(pk.id + " names no hero").is_not_null()
	for c: CharacterDef in Registry.sorted_characters():
		assert_int(Registry.perks_of(c.id).size()).override_failure_message(c.id).is_greater_equal(1)
	# the Collection's Perks tab leaves them out
	var cs: Control = auto_free(load("res://ui/CollectionScreen.tscn").instantiate())
	var tab: Array = cs._items(3)
	for d: ContentDef in tab:
		assert_bool(["suit_seals", "serenade", "bounty_hunter"].has(d.id)).override_failure_message(d.id).is_false()
	assert_bool(tab.any(func(d: ContentDef) -> bool: return d.id == "supply_drop")).is_true()


func test_supply_drop_leaves_a_heart_or_a_magnet_pulse_over_a_halved_blast() -> void:
	# Garry: "Supply Drop is insanely powerful, nerf it" and "It feels op, power-ups feel powerful"
	var pk: PerkDef = Registry.perk("supply_drop")
	assert_bool(pk.hidden).is_false()
	assert_float(float(pk.params["damage"])).is_equal(15.0)
	assert_float(float(pk.params["damage_per_level"])).is_equal(2.0)
	assert_float(float(pk.params["heart_below"])).is_equal_approx(0.6, 0.0001)
	assert_array(pk.params["drops"]).contains_exactly(["magnet_pulse"])
	for id in ["rage", "shield", "sprint"]:
		assert_bool((pk.params["drops"] as Array).has(id)).is_false()
	assert_str(pk.text).contains("magnet pulse")
	assert_str(pk.text).contains("heart")
	assert_str(pk.text).not_contains("power-up")
	# without the perk the helper still answers with the pulse (the default)
	_start()
	assert_str(Game.supply_drop_pick(100.0, 100.0)).is_equal("magnet_pulse")
	assert_bool(Run.add_perk("supply_drop")).is_true()
	assert_float(Run.perk_param("supply_drop", "damage", 30.0)).is_equal(15.0)
	assert_float(Run.perk_param("supply_drop", "damage_per_level", 4.0)).is_equal(2.0)
	# fifty pods over a healthy hero: the magnet pulse every time, never Berserk, Shield or Sprint
	for k in 50:
		assert_str(Game.supply_drop_pick(100.0, 100.0)).is_equal("magnet_pulse")
	assert_str(Game.supply_drop_pick(60.0, 100.0)).is_equal("magnet_pulse")
	# hurt: the heart
	assert_str(Game.supply_drop_pick(59.0, 100.0)).is_equal("heart")
	assert_str(Game.supply_drop_pick(10.0, 100.0)).is_equal("heart")
	# the ids it hands out are pickups that exist
	for id in ["heart", "magnet_pulse"]:
		assert_object(Registry.pickup(id)).is_not_null()
	# the old roll is gone from the landing, which asks the helper
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(src.contains("[\"magnet_pulse\", \"rage\", \"shield\", \"sprint\"]")).is_false()
	assert_bool(src.contains("supply_drop_pick(")).is_true()
