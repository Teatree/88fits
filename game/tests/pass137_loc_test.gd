extends GdUnitTestSuite

## Pass 137, lane LOCKIT: the string table (core/systems/Loc.gd, content/strings/en.json). Lookup, variables, the
## {n?one:many} selector, literal braces, the warnings a missing key or variable gives (once each), t_first's fallback,
## the shared render cases (tools/level_editor/fixtures/loc_cases.json, also run by the Level Editor's Python and JS), every
## key the code names exists, and the pilot's texts (PortalDialog, StrangerScreen, TextGen's ProjectileEmitter sentences)
## read exactly as the literals they replaced.

const FIXTURE := "res://../tools/level_editor/fixtures/loc_cases.json"


func before_test() -> void:
	Loc.load_table()
	Loc.clear_warnings()


func _fixture() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("tools/level_editor/fixtures/loc_cases.json")
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func test_lookup_and_missing_key() -> void:
	assert_bool(Loc.has("ui.portal.extract")).is_true()
	assert_str(Loc.t("ui.portal.extract")).is_equal("EXTRACT")
	assert_str(Loc.t("no.such.key")).is_equal("no.such.key")
	assert_str(Loc.t("no.such.key")).is_equal("no.such.key")
	var w := Loc.warnings()
	assert_int(w.size()).is_equal(1)   # once, however often it is asked
	assert_str(str(w[0])).contains("no.such.key")


func test_variables_and_selector() -> void:
	assert_str(Loc.render("Fires {amount} {amount?shot:shots}.", {"amount": "1"})).is_equal("Fires 1 shot.")
	assert_str(Loc.render("Fires {amount} {amount?shot:shots}.", {"amount": 2})).is_equal("Fires 2 shots.")
	assert_str(Loc.render("Fires {amount} {amount?shot:shots}.", {"amount": 1})).is_equal("Fires 1 shot.")
	assert_str(Loc.render("{n?one:many}", {"n": 1.0})).is_equal("one")
	assert_str(Loc.render("{{x}}", {})).is_equal("{x}")


func test_missing_variable_warns_once() -> void:
	assert_str(Loc.render("Within {range} m.", {}, "k.test")).is_equal("Within {range} m.")
	assert_str(Loc.render("Within {range} m.", {}, "k.test")).is_equal("Within {range} m.")
	var w := Loc.warnings()
	assert_int(w.size()).is_equal(1)
	assert_str(str(w[0])).contains("{range}")


func test_t_first_falls_back() -> void:
	assert_str(Loc.t_first(["weapon.no_such_weapon.desc", "ui.portal.extract"])).is_equal("EXTRACT")
	assert_str(Loc.t_first(["", "ui.portal.extract"])).is_equal("EXTRACT")
	assert_array(Loc.warnings()).is_empty()   # a missing first choice is not a warning
	assert_str(Loc.t_first(["a.b", "c.d"])).is_equal("c.d")
	assert_int(Loc.warnings().size()).is_equal(1)


func test_shared_cases() -> void:
	var fx := _fixture()
	assert_bool(fx.has("cases")).is_true()
	for c in fx["cases"]:
		assert_str(Loc.render(str(c["t"]), c["v"])).override_failure_message("case %s" % str(c)).is_equal(str(c["out"]))
	for c in fx["variables"]:
		assert_array(Loc.variables(str(c["t"]))).is_equal(c["names"])


func test_table_file_shape() -> void:
	var raw := FileAccess.get_file_as_string("res://content/strings/en.json")
	assert_bool(raw.contains("\r")).is_false()            # LF
	assert_bool(raw.unicode_at(0) == 0xFEFF).is_false()   # no BOM
	var d = JSON.parse_string(raw)
	assert_bool(d is Dictionary).is_true()
	var keys: Array = (d as Dictionary).keys()
	var sorted := keys.duplicate()
	sorted.sort()
	assert_array(keys).is_equal(sorted)
	var key_re := RegEx.create_from_string("^[a-z0-9_]+(\\.[a-z0-9_]+)+$")
	for k in keys:
		assert_bool(key_re.search(str(k)) != null).override_failure_message("key %s" % k).is_true()
		assert_str(str(d[k])).override_failure_message("empty %s" % k).is_not_empty()


## Every Loc.t / Loc.t_first key written as a literal in the game's code has its row (a typo is a test failure, never a
## key on the player's screen).
func test_every_key_in_code_exists() -> void:
	var re := RegEx.create_from_string("Loc\\.(?:t|has)\\(\\s*\"([a-z0-9_.]+)\"")
	var missing: Array = []
	for path in _gd_files("res://", []):
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			var key := m.get_string(1)
			if key.ends_with(".") or key == "no.such.key" or key == "a.b":
				continue
			if not Loc.has(key) and not path.ends_with("pass137_loc_test.gd"):
				missing.append("%s: %s" % [path, key])
	assert_array(missing).is_empty()


func _gd_files(dir: String, out: Array) -> Array:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or sub == "addons" or sub == "android" or sub == "export":
			continue
		_gd_files(dir.path_join(sub), out)
	return out


# ---------------------------------------------------------------- the pilot reads as before

func test_pilot_portal_texts() -> void:
	assert_str(Loc.t("ui.portal.stage_clear", {"stage": "2"})).is_equal("STAGE %d CLEAR" % 2)
	assert_str(Loc.t("ui.portal.line", {"time": "07:10", "kills": "1,234", "level": "Lv 12"})).is_equal(
		"%s · %s kills · %s. Bank it before the horde comes." % ["07:10", "1,234", "Lv 12"])
	assert_str(Loc.t("ui.portal.kills", {"kills": "12"})).is_equal("%s kills" % "12")
	assert_str(Loc.t("ui.portal.endless_line", {"every": "10 s"})).is_equal("A huge wave, then a tougher one every %s, until you fall." % "10 s")
	assert_str(Loc.t("ui.portal.gold_home", {"gold": "450"})).is_equal("The %s gold comes home either way." % "450")
	assert_str(Loc.t("ui.portal.foot")).is_equal("Not ready? Step out, and walk back in before the clock runs out.")
	for pair in [["ui.portal.star", "Boss down"], ["ui.portal.extract_title", "Extract"], ["ui.portal.extract_tag", "Safe · run ends"],
			["ui.portal.gold_banked", "This run's gold, banked"], ["ui.portal.extract", "EXTRACT"], ["ui.portal.not_yet", "NOT YET"],
			["ui.portal.endless_title", "Endless"], ["ui.portal.starts_in", "Starts in"], ["ui.portal.bank_it", "Bank it before the horde comes."]]:
		assert_str(Loc.t(pair[0])).is_equal(pair[1])
	assert_array(Loc.warnings()).is_empty()


func test_pilot_stranger_texts() -> void:
	for pair in [["ui.stranger.star", "No name"], ["ui.stranger.title", "THE STRANGER"],
			["ui.stranger.quote", "“A piece of you, for a piece of the world.”"],
			["ui.stranger.price", "The price · max HP for the rest of the run"],
			["ui.stranger.note", "No reroll. No second offer. He does not haggle."],
			["ui.stranger.walk_away", "WALK AWAY"], ["ui.stranger.deal", "DEAL"]]:
		assert_str(Loc.t(pair[0])).is_equal(pair[1])
	assert_str(Loc.t("ui.stranger.straight_to_level", {"kind": "WEAPON", "level": "3"})).is_equal("%s · STRAIGHT TO LV %d" % ["WEAPON", 3])
	assert_array(Loc.warnings()).is_empty()


## The old ProjectileEmitter sentences, written out as the code had them, against the table at several amounts.
func test_pilot_weapon_sentences() -> void:
	for amount in [1, 2, 5]:
		var a := str(amount)
		var s := "" if amount == 1 else "s"
		assert_str(Loc.t("gen.weapon.shot.forward", {"amount": a, "cone": "30"})).is_equal("Fires %d pellet%s in a %d° cone where you face." % [amount, s, 30])
		assert_str(Loc.t("gen.weapon.shot.random", {"amount": a, "range": "8"})).is_equal("Fires %d shot%s at random enemies within %.0f m." % [amount, s, 8.0])
		assert_str(Loc.t("gen.weapon.shot.flare", {"amount": a, "range": "8"})).is_equal("Fires %d flare%s at the nearest enemy within %.0f m that is not burning yet." % [amount, s, 8.0])
		assert_str(Loc.t("gen.weapon.shot.dart", {"amount": a, "range": "8"})).is_equal("Fires %d dart%s at the nearest enemy within %.0f m that is not poisoned yet." % [amount, s, 8.0])
		assert_str(Loc.t("gen.weapon.shot.priority", {"amount": a, "range": "14", "who": "the strongest enemy nearby"})).is_equal(
			"Fires %d shot%s within %.0f m and aims at %s." % [amount, s, 14.0, "the strongest enemy nearby"])
		assert_str(Loc.t("gen.weapon.shot.nearest", {"amount": a, "range": "8"})).is_equal("Fires %d shot%s at the nearest enemy within %.0f m." % [amount, s, 8.0])
		assert_str(Loc.t("gen.weapon.ricochet", {"count": a, "pct": "50"})).is_equal("Every round ricochets %d time%s at %d%%." % [amount, s, 50])
	assert_str(Loc.t("gen.weapon.blast.lane", {"width": "2.6", "length": "10"})).is_equal(
		"Blasts a %.1f m wide lane %.0f m long where you face: everything in it is hit at once and shoved along it." % [2.6, 10.0])
	assert_str(Loc.t("gen.weapon.blast.cone", {"deg": "75", "depth": "6"})).is_equal("Blasts a %d° cone %.0f m deep where you face: everything in it is hit at once." % [75, 6.0])
	assert_str(Loc.t("gen.weapon.mini_crit", {"pct": "25"})).is_equal("%d%% of rounds are mini crits." % 25)
	assert_str(Loc.t("gen.weapon.hip_shot", {"nth": "5th", "volleys": "3"})).is_equal("Every %s pull fires %d volleys in a row." % ["5th", 3])
	assert_str(Loc.t("gen.weapon.double_every", {"nth": Loc.t("gen.word.nth.3")})).is_equal("Every third shot fires twice in quick succession.")
	assert_str(Loc.t("gen.word.nth.n", {"n": "7"})).is_equal("%dth" % 7)
	assert_str(Loc.t("gen.weapon.who.priority")).is_equal(TextGen.PRIORITY_WHO)


## Each weapon's own row reads, today, exactly as the generic sentence of the shape it comes with (the conversion's
## promise: the table changed no text; Garry's edits come after).
func test_item_rows_match_their_shape() -> void:
	var reg := get_tree().root.get_node("Registry")
	var checked := 0
	for id in reg.weapons:
		var def: WeaponDef = reg.weapons[id]
		var key := ("evolution.%s.desc" if def.is_evolution else "weapon.%s.desc") % id
		if not Loc.has(key):
			continue
		# pass 137 (lane W2-TEXTGEN): every behaviour has its own rows now; the shape it comes with is TextGen.home_shape
		var shape := TextGen.home_shape(def)
		assert_str(shape).override_failure_message(key + ": no home shape").is_not_empty()
		assert_str(Loc.t(key, {})).override_failure_message(key).is_equal(Loc.t("gen.weapon." + shape, {}))
		checked += 1
	assert_int(checked).is_greater(60)
	# the rule items' and the box perk's own rows read as the rule's generic row (lane W2-TEXTGEN)
	var own := {"passive.lightning_in_a_bottle.desc": "gen.passive.rule.arc", "passive.iron_horse.desc": "gen.passive.rule.train",
		"passive.personal_storm.desc": "gen.passive.rule.storm", "perk.invisible_box.desc": "gen.perk.box"}
	for k in own:
		if Loc.has(k):
			assert_str(Loc.t(k, {})).override_failure_message(k).is_equal(Loc.t(str(own[k]), {}))
	Loc.clear_warnings()   # the {variables} left in with no values above warn by design
