## Pass 88, lane STAGEMENU (Garry 2026-10-18, "Stages"): simpler stage words naming no creature or boss, "Choose a
## Stage" under the header, "Difficulty: Easy / Medium / Hard / Extremely Hard", and the boss hidden (the Collection's
## silhouette, "Boss not encountered yet") until the player has met him once (Save.enemy_met: on the sand in a run, or
## killed); a locked stage asks to "Beat Stage k" until the boss before it has been met.
extends GdUnitTestSuite

const StagesScreenScript := preload("res://ui/StagesScreen.gd")

var _keep_save: Dictionary = {}


func before_test() -> void:
	_keep_save = Save.data.duplicate(true)
	Save.data = Save._default()
	Save.data["last_character"] = "drifter"
	Save.data["last_map"] = "red_canyon"


func after_test() -> void:
	Save.data = _keep_save


func _frames(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			var t := n as WText
			s += t.text + " "
			for r in t.runs:
				s += str(r[0]) + " "
	return s


func _menu() -> Control:
	var sub := SubViewport.new()
	sub.size = Vector2i(1080, 1920)
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sub)
	auto_free(sub)
	var m: Control = load("res://ui/StagesScreen.tscn").instantiate()
	sub.add_child(m)
	await _frames(3)
	return m


func _list() -> Array:
	return StagesScreenScript.entries(Registry.map("red_canyon"))


# ---------------------------------------------------------------- the words

func test_the_difficulty_line_is_one_word_by_level() -> void:
	assert_str(StagesScreenScript.difficulty_text({}, 0)).is_equal("Difficulty: Easy")
	assert_str(StagesScreenScript.difficulty_word({}, 1)).is_equal("Medium")
	assert_str(StagesScreenScript.difficulty_word({}, 2)).is_equal("Hard")
	# Garry: "Extremely Hard if we ever get a 4th stage", and every stage after it
	assert_str(StagesScreenScript.difficulty_word({}, 3)).is_equal("Extremely Hard")
	assert_str(StagesScreenScript.difficulty_word({}, 6)).is_equal("Extremely Hard")
	# the entry's own word wins; a number is a level; a written "Difficulty:" is not doubled
	assert_str(StagesScreenScript.difficulty_word({"difficulty": "Hard"}, 0)).is_equal("Hard")
	assert_str(StagesScreenScript.difficulty_word({"difficulty": "4"}, 0)).is_equal("Extremely Hard")
	assert_str(StagesScreenScript.difficulty_text({"difficulty": "Difficulty: Medium"}, 0)).is_equal("Difficulty: Medium")


func test_red_canyon_reads_easy_medium_hard() -> void:
	var list := _list()
	assert_int(list.size()).is_greater_equal(3)
	var want := ["Easy", "Medium", "Hard"]
	for i in range(3):
		assert_str(StagesScreenScript.difficulty_text(list[i], i)).is_equal("Difficulty: " + want[i])


func test_the_descriptions_name_no_creature_or_boss() -> void:
	for e: Dictionary in _list():
		var d := str(e.get("description", "")).to_lower()
		assert_str(d).is_not_empty()
		assert_bool(d.contains("boss")).override_failure_message("'%s' says boss" % d).is_false()
		for en: EnemyDef in Registry.enemies.values():
			var nm := en.display_name.to_lower().trim_prefix("the ")
			if nm.length() < 4:
				continue
			assert_bool(d.contains(nm)).override_failure_message("'%s' names %s" % [d, en.display_name]).is_false()


# ---------------------------------------------------------------- met

func test_a_boss_is_met_once_on_the_sand_or_killed() -> void:
	assert_bool(Save.enemy_met("gila_grande")).is_false()
	assert_bool(StagesScreenScript.boss_met("gila_grande")).is_false()
	Save.mark_seen("enemy", "gila_grande")
	assert_bool(Save.enemy_met("gila_grande")).is_true()
	Save.add_keyed_total("kills_of_enemy", "brander", 1)
	assert_bool(Save.enemy_met("brander")).is_true()
	assert_bool(Save.enemy_met("")).is_false()


func test_a_locked_stage_names_its_boss_only_once_met() -> void:
	var m := Registry.map("red_canyon")
	var list := _list()
	assert_str(StagesScreenScript.requirement(m, list, 1)).is_equal("Beat Stage 1")
	assert_str(StagesScreenScript.requirement(m, list, 2)).is_equal("Beat Stage 2")
	Save.mark_seen("enemy", str(list[0]["boss"]))
	var king: EnemyDef = Registry.enemy(str(list[0]["boss"]))
	assert_str(StagesScreenScript.requirement(m, list, 1).to_lower()).contains(king.display_name.to_lower().trim_prefix("the "))


# ---------------------------------------------------------------- the menu

func test_the_menu_asks_to_choose_a_stage() -> void:
	Save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	var m := await _menu()
	var cta: Node = m.find_child("CallToAction", true, false)
	assert_object(cta).is_not_null()
	assert_str((cta as WText).text).is_equal("Choose a Stage")


func test_the_boss_is_hidden_until_met() -> void:
	Save.data["stages_beaten"] = {"red_canyon": [true, true, false]}
	var list := _list()
	var m := await _menu()
	for c: WTap in m.call("cards"):
		var e: Dictionary = list[int(c.get_meta("stage"))]
		var bd: EnemyDef = Registry.enemy(str(e["boss"]))
		var plate: WPlate = c.find_child("BossPlate", true, false)
		assert_object(plate).is_not_null()
		assert_bool(plate.locked).override_failure_message("%s's plate shows him" % bd.id).is_true()
		var said := _texts(c)
		assert_str(said).contains("Boss not encountered yet")
		assert_bool(said.contains(bd.display_name)).override_failure_message("%s named" % bd.id).is_false()
		assert_str(said).contains("Difficulty: ")
	# the King met (on the sand once): his card shows him, the others still do not
	Save.mark_seen("enemy", str(list[0]["boss"]))
	var m2 := await _menu()
	var cards: Array = m2.call("cards")
	var king: EnemyDef = Registry.enemy(str(list[0]["boss"]))
	var p0: WPlate = (cards[0] as Node).find_child("BossPlate", true, false)
	assert_bool(p0.locked).is_false()
	assert_str(_texts(cards[0])).contains(king.display_name)
	assert_str(_texts(cards[0])).not_contains("Boss not encountered yet")
	var p1: WPlate = (cards[1] as Node).find_child("BossPlate", true, false)
	assert_bool(p1.locked).is_true()
