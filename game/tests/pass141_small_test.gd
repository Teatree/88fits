## Pass 141, lane SMALL (Garry's "Polish #4"):
##  - the Cake (item 2: "Make the Cake item spawn cakes more rarely, but they heal more. Also, they take x2 as long to
##    despawn"): every level's cake chance about half of pass 140's, a slice heals 2.4x as much and lies twice as long, so a
##    minute's healing (chance x heal) ends a little above pass 140's at every level; the level ladder keeps its shape;
##  - the tutorial hand (item 4: "get a normal looking finger please"): WHighlight draws the painted picture
##    (art/ui/tutorial/hand.png), its fingertip HAND_TIP_PX on an opaque pixel at the picture's top;
##  - the words (items 3.1 and 5): the Trail's owned node reads "Owned" / "OWNED", the Collection's gated weapon
##    "Unlocked with <outlaw>"; the Outlaws screen's "Yours for" and the buy dialog keep theirs (not the Trail).
extends GdUnitTestSuite

## pass 140's cake.json chance per level and cake_slice.json heal and lifetime
const OLD_CHANCE := [0.004, 0.0025, 0.0025, 0.0025, 0.0025, 0.0035]
const OLD_HEAL := 0.06
const OLD_LIFETIME := 30.0
const HL_PATH := "res://ui/wanted/WHighlight.gd"


func _json(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func test_the_cake_drops_rarer_bigger_longer_lived_slices() -> void:
	var cake := _json("res://content/passives/cake/cake.json")
	var slice := _json("res://content/pickups/cake_slice/cake_slice.json")
	var levels: Array = cake.get("levels", [])
	assert_int(levels.size()).is_equal(OLD_CHANCE.size())
	var heal := float(slice.get("value", 0.0))
	assert_float(heal).is_equal_approx(OLD_HEAL * 2.4, 0.0001)
	assert_float(float(slice.get("lifetime", 0.0))).is_equal(OLD_LIFETIME * 2.0)
	var old_sum := 0.0
	var new_sum := 0.0
	for i in levels.size():
		var e: Dictionary = levels[i][0]
		assert_str(str(e["stat"])).is_equal("heal_drop")
		old_sum += float(OLD_CHANCE[i])
		new_sum += float(e["value"])
		# about half the chance at every level ...
		assert_float(new_sum / old_sum).override_failure_message("level %d chance" % (i + 1)).is_between(0.45, 0.55)
		# ... and a minute's healing (chance x heal) a little above pass 140's
		assert_float(new_sum * heal / (old_sum * OLD_HEAL)).override_failure_message("level %d heal" % (i + 1)).is_between(1.1, 1.3)
	# the ladder's shape: the first rung the biggest, four equal rungs, the Evolved rung between them
	var v0 := float(levels[0][0]["value"])
	var vm := float(levels[1][0]["value"])
	var ve := float(levels[5][0]["value"])
	for i in range(1, 5):
		assert_float(float(levels[i][0]["value"])).is_equal_approx(vm, 0.000001)
	assert_bool(v0 > ve and ve > vm).is_true()
	# what the game reads (the .tres), and a slice on the sand lies that long
	var d: PickupDef = Registry.pickup("cake_slice")
	assert_float(d.value).is_equal_approx(heal, 0.0001)
	assert_float(d.lifetime).is_equal(OLD_LIFETIME * 2.0)
	assert_float(float((Registry.passive("cake") as PassiveDef).effects_at_level(1)[0].value)).is_equal_approx(v0, 0.000001)
	var p := Powerup.new()
	p.setup(d)
	assert_float(p.life).is_equal(OLD_LIFETIME * 2.0)
	p.free()


func test_the_tutorial_hand_is_the_painted_picture() -> void:
	var s: GDScript = load(HL_PATH)
	var tex: Texture2D = s.call("hand_texture")
	assert_object(tex).is_not_null()
	assert_str(tex.resource_path).is_equal("res://art/ui/tutorial/hand.png")
	var consts: Dictionary = s.get_script_constant_map()
	assert_str(str(consts["HAND_TEX"])).is_equal("res://art/ui/tutorial/hand.png")
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var tip: Vector2 = consts["HAND_TIP_PX"]
	# the fingertip is on the finger, at the picture's top: opaque there, nothing opaque above it but the outline
	assert_bool(tip.x > 0.0 and tip.x < float(img.get_width()) and tip.y > 0.0).is_true()
	assert_float(img.get_pixelv(Vector2i(tip)).a).is_greater(0.5)
	assert_float(tip.y).is_less(float(img.get_height()) * 0.12)
	for y in range(0, maxi(0, int(tip.y) - 12)):
		for x in img.get_width():
			assert_float(img.get_pixel(x, y).a).override_failure_message("opaque at %d,%d above the tip" % [x, y]).is_less(0.5)
	# the glove drawn in code is gone
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var b := Button.new()
	b.position = Vector2(600, 1500)
	b.size = Vector2(300, 120)
	host.add_child(b)
	var hl: Control = s.call("attach", b, host)
	for k in 3:
		await get_tree().process_frame
	assert_object(host.find_child("TutorHighlight", false, false)).is_same(hl)
	assert_bool(hl.has_method("_hand_shapes")).is_false()
	assert_int(int(hl.call("side"))).is_equal(-1)
	hl.call("stop")


func test_the_trail_says_owned_and_the_collection_unlocked_with() -> void:
	assert_str(Loc.t("ui.trail.state.yours")).is_equal("Owned")
	assert_str(Loc.t("ui.trail.tag.yours")).is_equal("OWNED")
	var j: CharacterDef = Registry.character("buck")
	assert_str(CollectionScreen.comes_with_words(j)).is_equal("Unlocked with " + j.display_name)
	assert_str(CollectionScreen.comes_with_words(null)).is_equal("Unlocked with " + Loc.t("ui.collection.an_outlaw"))
	# no other Trail row says "yours" but the toast of a skin just bought ("<skin> is yours")
	var rows := _json("res://content/strings/en.json")
	for key: String in rows:
		if key.begins_with("ui.trail.") and key != "ui.trail.gift.skin":
			assert_bool(str(rows[key]).to_lower().contains("yours")).override_failure_message(key).is_false()
	# not the Trail: the Outlaws screen's price line and the buy dialog keep theirs
	assert_str(Loc.t("ui.heroes.yours_for", {"price": "9"})).is_equal("Yours for 9.")
	assert_str(Loc.t("ui.buy_outlaw.body", {"price": "9"})).contains("Yours to play")
