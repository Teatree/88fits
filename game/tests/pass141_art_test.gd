## Pass 141, lane ART (Garry's Polish #4, items 7 and 8): two new skins painted for this pass, Astro's Splashdown (AST-D: a
## V-neck one-piece swimsuit, bare arms, legs and feet, and still her space helmet) and Solenne's Oasis (SOL-I: a triangle
## bikini and high-cut bottoms, barefoot; the most expensive skin of all). Both load with every frame row of a hero strip,
## their badge, sheet still and title cut-out exist, and their skin blocks say what the lead fixed (BALANCING 82.ART).
extends GdUnitTestSuite

const LOOKS := {"astro": "AST-D", "solenne": "SOL-I"}
const NAMES := {"AST-D": "Splashdown", "SOL-I": "Oasis"}
const LETTERS := {"AST-D": "d", "SOL-I": "i"}
## every row a hero strip carries (Player's order), each look of these two as many frames as the outlaw's own strip
const ROWS := ["idle", "run", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd",
	"hit_f", "hit_s", "hit_bd", "hit_fd"]


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func _hero(id: String) -> CharacterDef:
	var c: CharacterDef = Registry.character(id)
	assert_object(c).override_failure_message("no outlaw " + id).is_not_null()
	return c


func test_both_looks_load_with_every_frame_row() -> void:
	for hid: String in LOOKS:
		var c := _hero(hid)
		var code: String = LOOKS[hid]
		var m := "%s %s" % [hid, code]
		assert_bool(c.variants.has(code)).override_failure_message(m + ": no look").is_true()
		assert_bool(c.variant_shelved(code)).override_failure_message(m + ": shelved").is_false()
		var e: Dictionary = c.variants[code]
		# `fresh` is the Level Editor's flag (the JSON's; the game's def does not carry it)
		var src = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/%s/%s.json" % [hid, hid]))
		assert_bool(bool(((src as Dictionary)["variants"] as Dictionary)[code].get("fresh", false))).override_failure_message(m + ": fresh until Garry approves it").is_true()
		var an: Dictionary = e["anims"]
		var total := 0
		for r: String in ROWS:
			assert_int(int(an.get(r, 0))).override_failure_message("%s: row %s" % [m, r]).is_equal(int(c.anims.get(r, 0)))
			assert_int(int(an.get(r, 0))).override_failure_message("%s: row %s empty" % [m, r]).is_greater(0)
			total += int(an.get(r, 0))
		assert_int(total).override_failure_message(m + ": frames").is_equal(166)
		assert_int(int(e["strip_cols"])).override_failure_message(m + ": cols").is_equal(62)
		var strip := c.look_strip_path(code)
		assert_str(strip).override_failure_message(m + ": a strip of its own").is_not_equal(c.strip_path())
		assert_str(strip.get_file()).is_equal("%s_sprite_%s.png" % [hid, LETTERS[code]])
		var tex := load(strip) as Texture2D
		assert_object(tex).override_failure_message(m + ": the strip loads").is_not_null()
		assert_int(tex.get_width()).override_failure_message(m + ": strip width").is_equal(62 * 256)
		assert_int(tex.get_height()).override_failure_message(m + ": strip height").is_equal(3 * 256)
		var worn := c.variant_def(code)
		assert_int(worn.strip_cols).is_equal(62)
		assert_float(float(worn.fps.get("run", 0))).override_failure_message(m + ": run rate").is_greater(0.0)


func test_the_badge_the_sheet_still_and_the_title_exist() -> void:
	for hid: String in LOOKS:
		var c := _hero(hid)
		var code: String = LOOKS[hid]
		var m := "%s %s" % [hid, code]
		var e: Dictionary = c.variants[code]
		var icon := str(e.get("icon", ""))
		assert_str(icon.get_file()).override_failure_message(m + ": badge").is_equal("%s_icon_%s.png" % [hid, LETTERS[code]])
		assert_object(LookArt.icon(e.get("icon"))).override_failure_message(m + ": badge loads").is_not_null()
		assert_str(c.look_still_path(code)).override_failure_message(m + ": sheet still").is_not_empty()
		var worn := c.variant_def(code)
		assert_str(worn.look_title()).override_failure_message(m + ": title").is_equal("hero_%s_%s.png" % [hid, LETTERS[code]])
		assert_bool(ResourceLoader.exists(worn.title_path())).override_failure_message(m + ": title file").is_true()
		assert_str(worn.title_path()).override_failure_message(m + ": a title of its own").is_not_equal(CharacterDef.TITLE_DIR + "hero_" + hid + ".png")


func test_the_skin_blocks() -> void:
	var astro := _hero("astro")
	var solenne := _hero("solenne")
	for hid: String in LOOKS:
		var c := _hero(hid)
		var code: String = LOOKS[hid]
		assert_str(str(c.skin_of(code).get("name", ""))).is_equal(NAMES[code])
		assert_str(c.skin_currency(code)).is_equal("gold")
	# the lead's fixed decisions: Oasis 4,500 gold, the most expensive skin of all; Splashdown (Astro's harder skin) never
	# cheaper than Mission Control (her easier one)
	assert_int(solenne.skin_price("SOL-I")).is_equal(4500)
	assert_int(astro.skin_price("AST-D")).is_greater_equal(astro.skin_price("AST-C"))
	for hid: String in Registry.characters:
		var c: CharacterDef = Registry.characters[hid]
		for code: String in c.variants:
			if hid == "solenne" and code == "SOL-I":
				continue
			if c.skin_of(code).is_empty() or c.variant_shelved(code):
				continue
			assert_int(c.skin_price(code)).override_failure_message("%s %s costs as much as Oasis or more" % [hid, code]).is_less(4500)
