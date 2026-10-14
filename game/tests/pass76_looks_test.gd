extends GdUnitTestSuite

## Pass 76, lane LOOKS (Garry: make the Grenade a Dynamite Stick "as a Look (with several candidates), so I can switch
## back to the grenade if I ever change my mind", and the Molotov "in several different versions"): weapon-family looks.
## A weapon, an evolution or a mutation JSON carries `variants {CODE: entry}` and `variant_base` (its top level's code);
## the weapon's `variant` (or a phone's Save.item_looks) is the code the whole family plays; every member wears its entry
## for that code (name, flavour, text, icon, visual, params one level deep, noun / nouns) or its top level when it has
## none; an entry whose file is missing is left out. Built on a family made here (t76_*), so the dynamite and Molotov
## looks (lanes DYNART, MOLO) can land without moving these tests.

const ItemLooks := preload("res://core/data/ItemLooks.gd")

const GUN := "t76_gun"
const EVO := "t76_gun_evo"
const MUT_A := "t76_mut_a"
const MUT_B := "t76_mut_b"
const MUT_HERO := "t76_mut_hero"
const DIR := "res://content/weapons/lob_grenade/"
const ICON_A := "res://content/weapons/lob_grenade/lob_grenade_icon.png"
const ICON_B := "res://content/weapons/revolver/revolver_icon.png"
const ICON_EVO := "res://content/evolutions/golden_pineapple/golden_pineapple_icon.png"
const ICON_MUT := "res://content/weapons/molotov/molotov_icon.png"
const VIS_A := "res://content/weapons/lob_grenade/lob_grenade_visual.tscn"
const VIS_B := "res://content/evolutions/golden_pineapple/golden_pineapple_visual.tscn"
const MODEL := "res://art/props/golden_grenade.glb"


func after_test() -> void:
	if Registry.weapons.has(GUN):
		Save.set_item_look(GUN, "")
	for id in [GUN, EVO, "t76_fire"]:
		Registry.weapons.erase(id)
	for id in [MUT_A, MUT_B, MUT_HERO]:
		Registry.mutations.erase(id)
	Run.end()


# ---------------------------------------------------------------- the test family

func _gun_json() -> Dictionary:
	return {"id": GUN, "name": "Test Grenade", "flavour": "Plain.", "rarity": "rare", "weight": 7.0, "behavior": "Lobber",
		"targeting": "densest", "base": {"damage": 25.0, "cooldown": 2.2, "amount": 1.0, "area": 2.5, "range": 10.0, "knockback": 7.0, "speed": 9.0},
		"max_level": 5, "levels": [[]], "evolves_into": EVO, "icon": ICON_A, "visual": VIS_A,
		"params": {"model": MODEL, "size_mult": 1.0, "keep": {"x": 1}},
		"variant_base": "A", "variant": "B",
		"variants": {
			"A": {"note": "the grenade"},
			"B": {"name": "Test Stick", "flavour": "Hiss.", "icon": ICON_B, "visual": VIS_B, "noun": "stick", "nouns": "sticks",
				"note": "paper", "fresh": true, "params": {"model_form": "stick", "size_mult": null, "keep": {"y": 2}}},
			"C": {"name": "Lost Look", "icon": "res://content/weapons/lob_grenade/no_such_icon.png"},
			"D": {"name": "Shelved Look", "shelved": true}}}


func _evo_json() -> Dictionary:
	return {"id": EVO, "name": "Test Pineapple", "is_evolution": true, "evolved_from": GUN, "behavior": "Lobber", "max_level": 1,
		"levels": [[]], "base": {"damage": 45.0, "cooldown": 1.8, "amount": 2.0, "area": 3.0}, "icon": ICON_EVO, "visual": VIS_B,
		"params": {"model": MODEL, "final": {"tint": {"albedo": "#FFF2D0"}, "bomblets": 4}},
		"variants": {"B": {"name": "Test Boomtown", "params": {"final": {"tint": null}}}}}


func _mut_json(id: String, kind: String, hero: String, looks: Dictionary) -> Dictionary:
	var d := {"id": id, "name": "Mut " + id, "weapon": GUN, "kind": kind, "hero": hero, "text": "Base text of %s." % id,
		"icon": ICON_A, "effects": [], "params": {"burst_spawn": {"count": 6}}}
	if not looks.is_empty():
		d["variants"] = looks
	return d


## The test family in the Registry, worn as it plays (B, the weapon's JSON `variant`).
func _register() -> void:
	Registry.weapons[GUN] = JsonContent.build("weapons", _gun_json(), DIR)
	Registry.weapons[EVO] = JsonContent.build("evolutions", _evo_json(), DIR)
	Registry.mutations[MUT_A] = JsonContent.build("mutations", _mut_json(MUT_A, "volume", "",
		{"B": {"name": "Coffin Test", "text": "Nails.", "icon": ICON_MUT, "params": {"model_colour": "red"}}}), DIR)
	Registry.mutations[MUT_B] = JsonContent.build("mutations", _mut_json(MUT_B, "motion", "", {}), DIR)
	Registry.mutations[MUT_HERO] = JsonContent.build("mutations", _mut_json(MUT_HERO, "hero", "drifter", {"B": {"icon": ICON_B}}), DIR)
	Registry.apply_item_looks()


## Every text a node and its children show (WText and Label alike).
func _texts(n: Node) -> Array:
	var out: Array = []
	var t = n.get("text")
	if t is String:
		out.append(t)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


# ---------------------------------------------------------------- reading

func test_the_json_looks_are_read_and_an_entry_without_its_file_is_left_out() -> void:
	var w: WeaponDef = JsonContent.build("weapons", _gun_json(), DIR)
	assert_str(w.variant_base).is_equal("A")
	assert_str(w.variant).is_equal("B")
	var keys: Array = w.variants.keys()
	keys.sort()
	# C names an icon that is not on disk: left out, the item wears its base in that look
	assert_array(keys).is_equal(["A", "B", "D"])
	assert_array(w.variant_codes()).is_equal(["A", "B"])
	assert_array(w.variant_codes(true)).is_equal(["A", "B", "D"])
	assert_bool(w.variant_shelved("D")).is_true()
	assert_str(w.variant_note("B")).is_equal("paper")
	var b: Dictionary = w.variants["B"]
	assert_object(b["icon"]).is_same(load(ICON_B))
	assert_object(b["visual"]).is_same(load(VIS_B))
	assert_bool(bool(b["fresh"])).is_true()
	# read, never worn: the def (and so its .tres) holds the top level
	assert_str(w.display_name).is_equal("Test Grenade")
	assert_object(w.icon).is_same(load(ICON_A))
	assert_str(w.look_worn).is_equal("?")
	assert_str(w.look_code()).is_equal("B")
	assert_object(w.look_icon("B")).is_same(load(ICON_B))
	assert_object(w.look_icon("D")).is_same(load(ICON_A))
	assert_str(w.look_name("D")).is_equal("Shelved Look")
	assert_str(w.look_name("A")).is_equal("Test Grenade")
	# a JSON `variant` naming a look it cannot play plays the base
	var d := _gun_json()
	d["variant"] = "C"
	assert_str((JsonContent.build("weapons", d, DIR) as WeaponDef).variant).is_equal("A")
	# no looks: nothing read, nothing to wear
	var plain := _gun_json()
	for k in ["variants", "variant", "variant_base"]:
		plain.erase(k)
	var p: WeaponDef = JsonContent.build("weapons", plain, DIR)
	assert_bool(p.variants.is_empty()).is_true()
	assert_str(p.variant_base).is_equal("")
	assert_str(p.look_code()).is_equal("")
	assert_array(p.variant_codes()).is_empty()


func test_the_looks_survive_the_tres() -> void:
	# import_json writes the .tres from the JSON: the resolved looks (textures and scenes inside the dictionary) load back
	var w: WeaponDef = JsonContent.build("weapons", _gun_json(), DIR)
	var path := "user://t76_gun.tres"
	assert_int(ResourceSaver.save(w, path)).is_equal(OK)
	var back: WeaponDef = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(back).is_not_null()
	assert_str(back.variant).is_equal("B")
	assert_str(back.variant_base).is_equal("A")
	assert_object((back.variants["B"] as Dictionary)["icon"]).is_same(load(ICON_B))
	assert_object((back.variants["B"] as Dictionary)["visual"]).is_same(load(VIS_B))
	assert_str(back.display_name).is_equal("Test Grenade")
	assert_str(back.look_worn).is_equal("?")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_params_overlay_one_level_final_one_deeper_and_null_removes() -> void:
	var base := {"a": 1, "b": {"x": 1, "y": 2}, "final": {"tint": {"albedo": "#fff"}, "bomblets": 4, "sticky": {"seconds": 1.3}}}
	var out: Dictionary = ItemLooks.overlay(base, {"b": {"x": 5}, "c": [1, 2], "a": null, "final": {"tint": null, "sticky": {"reach": 2}}})
	assert_dict(out).is_equal({"b": {"x": 5}, "c": [1, 2], "final": {"bomblets": 4, "sticky": {"reach": 2}}})
	# the base is never written
	assert_dict(base["b"] as Dictionary).is_equal({"x": 1, "y": 2})
	assert_bool((base["final"] as Dictionary).has("tint")).is_true()
	assert_int(int(base["a"])).is_equal(1)


# ---------------------------------------------------------------- the family

func test_the_family_wears_the_look_its_weapon_plays() -> void:
	_register()
	var w := Registry.weapon(GUN)
	var e := Registry.weapon(EVO)
	var ma := Registry.mutation(MUT_A)
	var mb := Registry.mutation(MUT_B)
	var mh := Registry.mutation(MUT_HERO)
	# the family: the weapon, its evolution, its mutations in path order (the hero's own too)
	assert_array(Registry.item_family(GUN)).is_equal([w, e, ma, mb, mh])
	assert_array(Registry.item_family(MUT_HERO)).is_equal([w, e, ma, mb, mh])
	assert_str(Registry.item_family_root(EVO)).is_equal(GUN)
	assert_str(Registry.item_family_root(MUT_A)).is_equal(GUN)
	assert_str(Registry.item_family_root("no_such_thing")).is_equal("")
	assert_array(Registry.item_look_codes(GUN)).is_equal(["A", "B"])
	assert_str(Registry.played_item_look(GUN)).is_equal("B")
	# the weapon in B: its name, words, icon, visual and params
	assert_str(w.display_name).is_equal("Test Stick")
	assert_str(w.flavour).is_equal("Hiss.")
	assert_object(w.icon).is_same(load(ICON_B))
	assert_object(w.visual).is_same(load(VIS_B))
	assert_str(w.look_code()).is_equal("B")
	assert_str(w.nouns).is_equal("sticks")
	# params one level deep: `keep` replaced whole, size_mult dropped by its null, model_form added, the rest kept
	assert_dict(w.params).is_equal({"model": MODEL, "keep": {"y": 2}, "model_form": "stick"})
	assert_dict(w.look_top["params"] as Dictionary).is_equal({"model": MODEL, "size_mult": 1.0, "keep": {"x": 1}})
	# a mutation with a B entry: its name, its text, its icon, its params over its own
	assert_str(ma.display_name).is_equal("Coffin Test")
	assert_str(ma.text).is_equal("Nails.")
	assert_object(ma.icon).is_same(load(ICON_MUT))
	assert_dict(ma.params).is_equal({"burst_spawn": {"count": 6}, "model_colour": "red"})
	# the hero's own: only its icon changes
	assert_object(mh.icon).is_same(load(ICON_B))
	assert_str(mh.display_name).is_equal("Mut " + MUT_HERO)
	# a member without an entry keeps its base
	assert_str(mb.display_name).is_equal("Mut " + MUT_B)
	assert_str(mb.text).is_equal("Base text of %s." % MUT_B)
	assert_object(mb.icon).is_same(load(ICON_A))
	assert_str(mb.look_code()).is_equal("")
	assert_str(mb.look_worn).is_equal("B")
	# the evolution: its name, its `final` one level deeper (the tint gone, the rest kept)
	assert_str(e.display_name).is_equal("Test Boomtown")
	assert_bool((e.params["final"] as Dictionary).has("tint")).is_false()
	assert_int(int((e.params["final"] as Dictionary)["bomblets"])).is_equal(4)
	assert_object(e.icon).is_same(load(ICON_EVO))


func test_a_kept_look_wins_over_the_json_and_json_gives_it_back() -> void:
	_register()
	var w := Registry.weapon(GUN)
	var e := Registry.weapon(EVO)
	var ma := Registry.mutation(MUT_A)
	Save.set_item_look(GUN, "A")
	assert_str(Save.item_look(GUN)).is_equal("A")
	assert_str(Registry.played_item_look(GUN)).is_equal("A")
	assert_str(w.display_name).is_equal("Test Grenade")
	assert_object(w.icon).is_same(load(ICON_A))
	assert_object(w.visual).is_same(load(VIS_A))
	assert_dict(w.params).is_equal({"model": MODEL, "size_mult": 1.0, "keep": {"x": 1}})
	assert_str(w.nouns).is_equal("")
	assert_str(ma.display_name).is_equal("Mut " + MUT_A)
	assert_str(ma.text).is_equal("Base text of %s." % MUT_A)
	assert_dict(ma.params).is_equal({"burst_spawn": {"count": 6}})
	assert_str(e.display_name).is_equal("Test Pineapple")
	assert_bool((e.params["final"] as Dictionary).has("tint")).is_true()
	# "" = the weapon's JSON look again
	Save.set_item_look(GUN, "")
	assert_str(Save.item_look(GUN)).is_equal("")
	assert_str(w.display_name).is_equal("Test Stick")
	assert_str(ma.display_name).is_equal("Coffin Test")
	# a kept look that is shelved, or that the weapon cannot play, gives way to the JSON's
	Save.set_item_look(GUN, "D")
	assert_str(Registry.played_item_look(GUN)).is_equal("B")
	Save.set_item_look(GUN, "C")
	assert_str(Registry.played_item_look(GUN)).is_equal("B")
	assert_str(w.display_name).is_equal("Test Stick")


func test_a_kept_look_survives_the_arena_and_a_wipe_drops_it() -> void:
	_register()
	var w := Registry.weapon(GUN)
	Save.begin_sandbox()
	Save.set_item_look(GUN, "A")
	Save.end_sandbox()
	# a choice about the game, kept past the arena's sandbox (as the card look and a hero's look)
	assert_str(Save.item_look(GUN)).is_equal("A")
	assert_str(w.display_name).is_equal("Test Grenade")
	Save.load_save()
	assert_str(Save.item_look(GUN)).is_equal("A")
	assert_str(w.display_name).is_equal("Test Grenade")
	# a wipe takes it with the progress: the family plays its JSON's look again
	Save.wipe()
	assert_str(Save.item_look(GUN)).is_equal("")
	assert_str(w.display_name).is_equal("Test Stick")


# ---------------------------------------------------------------- what reads it

func test_textgen_names_the_looks_things() -> void:
	_register()
	var w := Registry.weapon(GUN)
	var inst := WeaponInstance.new(w, 1)
	inst.rebuild(StatSheet.new(), [inst])
	assert_str(inst.description()).starts_with("Lobs 1 stick at the densest crowd.")
	assert_str(TextGen.amount_noun(w, inst.sheet, inst.params)).is_equal("sticks")
	assert_array(TextGen.weapon_nouns(w)).is_equal(["stick", "sticks"])
	inst.sheet.add_effect(Effect.make("amount", "add", 1.0), "t76")
	assert_str(TextGen.weapon_description(w, inst.sheet, inst.params)).starts_with("Lobs 2 sticks at the densest crowd.")
	# the evolution names none of its own: its family weapon's words
	assert_array(TextGen.weapon_nouns(Registry.weapon(EVO))).is_equal(["stick", "sticks"])
	# the grenade's own words with no look words
	Save.set_item_look(GUN, "A")
	assert_array(TextGen.weapon_nouns(w)).is_equal(["", ""])
	assert_str(TextGen.weapon_description(w, inst.sheet, {})).starts_with("Lobs 2 grenades at the densest crowd.")
	assert_str(TextGen.amount_noun(w, inst.sheet)).is_equal("grenades")
	# a fire Lobber keeps "of fire" around the look's word; one word given alone makes the other
	var fd := _gun_json()
	fd["id"] = "t76_fire"
	(fd["base"] as Dictionary)["fire_damage"] = 5.0
	(fd["variants"]["B"] as Dictionary).erase("nouns")
	(fd["variants"]["B"] as Dictionary)["noun"] = "jug"
	var fw: WeaponDef = JsonContent.build("weapons", fd, DIR)
	fw.wear_look("B")
	var fi := WeaponInstance.new(fw, 1)
	fi.rebuild(StatSheet.new(), [fi])
	assert_array(TextGen.weapon_nouns(fw)).is_equal(["jug", "jugs"])
	assert_str(fi.description()).starts_with("Lobs 1 jug of fire at the thickest crowd")
	fw.wear_look("A")
	assert_str(TextGen.weapon_description(fw, fi.sheet, {})).starts_with("Lobs 1 bottle of fire at the thickest crowd")


func test_the_cards_show_the_look_and_the_fortune_cards_keep_theirs() -> void:
	_register()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var w := Registry.weapon(GUN)
	var card := {"def": w, "level_from": 0, "level_to": 1}
	assert_str(WItem.effect(card)).starts_with("Lobs 1 stick")
	var c: WCard = auto_free(WCard.make(w, WItem.options(card)))
	add_child(c)
	assert_bool(_texts(c).has("Test Stick")).is_true()
	assert_object(c.plate.tex).is_same(load(ICON_B))
	# the fortune cards (pass 73) keep their own looks whatever a weapon family wears
	var sun := Registry.passive("brawn")
	var sun_icon := sun.icon
	var card_look := Save.card_look()
	Save.set_item_look(GUN, "A")
	assert_object(sun.icon).is_same(sun_icon)
	assert_str(Save.card_look()).is_equal(card_look)
	var c2: WCard = auto_free(WCard.make(w, WItem.options(card)))
	add_child(c2)
	assert_bool(_texts(c2).has("Test Grenade")).is_true()
	assert_object(c2.plate.tex).is_same(load(ICON_A))
	assert_str(WItem.effect(card)).starts_with("Lobs 1 grenade")
	c.queue_free()
	c2.queue_free()


func test_a_held_weapon_follows_the_look() -> void:
	_register()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.debug_set_item("weapon", GUN, 1)
	Run.debug_set_item("mutation", MUT_A, 1)
	var inst := Run.weapon_instance(GUN)
	assert_object(inst).is_not_null()
	# the look's params in the folded params, the mutation's look too
	assert_str(str(inst.params.get("model_form", ""))).is_equal("stick")
	assert_str(str(inst.params.get("model_colour", ""))).is_equal("red")
	assert_object(inst.visual_scene()).is_same(load(VIS_B))
	# a behaviour set up in B is stale once the family wears A (Game._sync_weapons makes it again)
	var b: WeaponBehavior = auto_free(WeaponBehavior.new())
	b.inst = inst
	b.look_seen = str(inst.def.look_worn)
	assert_bool(b.look_stale()).is_false()
	Save.set_item_look(GUN, "A")
	assert_bool(inst.params.has("model_form")).is_false()
	assert_bool(inst.params.has("model_colour")).is_false()
	assert_float(float(inst.params.get("size_mult", 0.0))).is_equal(1.0)
	assert_object(inst.visual_scene()).is_same(load(VIS_A))
	assert_bool(b.look_stale()).is_true()
	# the same look asked again changes nothing (no rebuild)
	b.look_seen = str(inst.def.look_worn)
	Save.set_item_look(GUN, "A")
	assert_bool(b.look_stale()).is_false()


func test_the_arena_offers_the_weapon_looks() -> void:
	_register()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_bool(ArenaPanel.item_look_weapons().has(Registry.weapon(GUN))).is_true()
	var p: ArenaPanel = auto_free(ArenaPanel.new())
	add_child(p)
	p._tab = "items"
	p._refresh()
	await get_tree().process_frame
	var row: Node = p._content.find_child("ItemLooks_" + GUN, true, false)
	assert_object(row).is_not_null()
	var labels: Array = []
	for b in row.get_children():
		if b is Button:
			labels.append((b as Button).text)
	# JSON (the weapon's own), then a chip per look it can play (D is shelved), ● on the one it plays
	assert_array(labels).is_equal(["JSON", "A", "B ●"])
	var chip: Button = row.find_child("ItemLook_%s_A" % GUN, true, false)
	assert_object(chip).is_not_null()
	chip.pressed.emit()
	assert_str(Save.item_look(GUN)).is_equal("A")
	assert_str(Registry.weapon(GUN).display_name).is_equal("Test Grenade")
	await get_tree().process_frame
	row = p._content.find_child("ItemLooks_" + GUN, true, false)
	var back: Button = row.find_child("ItemLook_%s_JSON" % GUN, true, false)
	back.pressed.emit()
	assert_str(Save.item_look(GUN)).is_equal("")
	assert_str(Registry.weapon(GUN).display_name).is_equal("Test Stick")
	# the rows each _refresh took out are queued for deletion: let them go before the test ends (no orphans)
	await get_tree().process_frame
	await get_tree().process_frame


# ---------------------------------------------------------------- the real content

func test_every_real_family_wears_a_look_it_can_play() -> void:
	# the grenade's family (the dynamite looks land on it): its members, whatever looks they carry now
	var fam: Array = Registry.item_family("lob_grenade")
	var ids: Array = fam.map(func(d) -> String: return str(d.id))
	for id in ["lob_grenade", "golden_pineapple", "new_equipment", "frag", "sticky"]:
		assert_bool(ids.has(id)).override_failure_message("%s not in %s" % [id, str(ids)]).is_true()
	assert_str(str(ids[0])).is_equal("lob_grenade")
	for w: WeaponDef in Registry.weapons.values():
		if w.is_evolution:
			continue
		var code := Registry.played_item_look(w.id)
		if w.variants.is_empty():
			assert_str(code).override_failure_message(w.id).is_equal("")
			continue
		assert_bool(code == w.variant_base or w.variants.has(code)).override_failure_message("%s plays %s" % [w.id, code]).is_true()
		for d in Registry.item_family(w.id):
			assert_str(str(d.look_worn)).override_failure_message("%s in %s" % [d.id, w.id]).is_equal(code)
