## Pass 67, lane A (sounds). The gem tune: Audio.chain_pitch plays a row's `ladder` of semitone offsets step by step,
## rows of one `chain_group` share the counter, plays within `chain_min_ms` of a step repeat its note, `chain_end` holds
## the top or wraps; the three gem rows carry a pentatonic each, rooted in their own ding, all in C major; rows without
## a ladder keep the pass-65 slide. The chest's chill: ui_jackpot and ui_slot_stop re-levelled, the landing plays the
## jackpot for every kind (the mega-win has one owner, Game._on_evolved), the lid's crack is silent, TAKE plays
## ui_chest_take and not the purchases' ka-ching. Five placeholder ids for the basketball and the jump-away item.
extends GdUnitTestSuite

const SOUNDS := "res://content/sounds/"
const GEMS := ["pk_gem_s", "pk_gem_m", "pk_gem_l"]
## each ding's root as a pitch class (tools/synth_sfx.py: s = G6, m = E6, l = C6) and C major's pitch classes
const ROOTS := {"pk_gem_s": 7, "pk_gem_m": 4, "pk_gem_l": 0}
const C_MAJOR := [0, 2, 4, 5, 7, 9, 11]
const NEW_IDS := ["w_ball_throw", "w_ball_bounce", "w_ball_catch", "pk_timeout", "ui_buzzer"]


func _row(id: String) -> Dictionary:
	return Registry.soundmap.entry(id)


func _semi(n: float) -> float:
	return pow(2.0, n / 12.0)


## Audio with the chain counter `key` forgotten.
func _fresh(key: String) -> Node:
	var a: Node = Audio
	a._chain.erase(key)
	return a


# ---------------------------------------------------------------- the ladder maths

func test_a_ladder_climbs_its_notes_then_holds_the_top() -> void:
	var row := {"ladder": [0, 7, 12], "chain_window": 0.3}
	var a := _fresh("t67h")
	assert_float(a.chain_pitch("t67h", row, 1000)).is_equal_approx(1.0, 0.0001)
	assert_float(a.chain_pitch("t67h", row, 1100)).is_equal_approx(_semi(7), 0.0001)
	assert_float(a.chain_pitch("t67h", row, 1200)).is_equal_approx(2.0, 0.0001)
	assert_float(a.chain_pitch("t67h", row, 1300)).is_equal_approx(2.0, 0.0001)
	assert_float(a.chain_pitch("t67h", row, 1400)).is_equal_approx(2.0, 0.0001)
	# a pause longer than the window starts the tune again
	assert_float(a.chain_pitch("t67h", row, 3000)).is_equal_approx(1.0, 0.0001)
	# "hold" is the default: the same with it spelt out
	var held := {"ladder": [0, 7, 12], "chain_window": 0.3, "chain_end": "hold"}
	_fresh("t67h2")
	for t: int in [1000, 1100, 1200, 1300]:
		a.chain_pitch("t67h2", held, t)
	assert_float(a.chain_pitch("t67h2", held, 1400)).is_equal_approx(2.0, 0.0001)


func test_wrap_drops_back_to_the_first_note() -> void:
	var row := {"ladder": [0, 7, 12], "chain_window": 0.3, "chain_end": "wrap"}
	var a := _fresh("t67w")
	assert_float(a.chain_pitch("t67w", row, 1000)).is_equal_approx(1.0, 0.0001)
	assert_float(a.chain_pitch("t67w", row, 1100)).is_equal_approx(_semi(7), 0.0001)
	assert_float(a.chain_pitch("t67w", row, 1200)).is_equal_approx(2.0, 0.0001)
	assert_float(a.chain_pitch("t67w", row, 1300)).is_equal_approx(1.0, 0.0001)
	assert_float(a.chain_pitch("t67w", row, 1400)).is_equal_approx(_semi(7), 0.0001)


func test_chain_max_can_shorten_a_ladder() -> void:
	var row := {"ladder": [0, 2, 4, 7, 9], "chain_window": 0.3, "chain_max": 2}
	var a := _fresh("t67x")
	for t: int in [1000, 1100, 1200, 1300]:
		a.chain_pitch("t67x", row, t)
	assert_float(a.chain_pitch("t67x", row, 1400)).is_equal_approx(_semi(4), 0.0001)


func test_a_chain_group_shares_one_counter_between_ids() -> void:
	var small := {"ladder": [0, 7, 12], "chain_group": "g67", "chain_window": 0.3}
	var large := {"ladder": [0, 4, 7], "chain_group": "g67", "chain_window": 0.3}
	var a := _fresh("g67")
	_fresh("t67c")
	assert_float(a.chain_pitch("a67", small, 1000)).is_equal_approx(1.0, 0.0001)
	# the other id takes the next step of the same tune, through its own ladder
	assert_float(a.chain_pitch("b67", large, 1100)).is_equal_approx(_semi(4), 0.0001)
	assert_float(a.chain_pitch("a67", small, 1200)).is_equal_approx(2.0, 0.0001)
	# a row without a group keeps its own counter
	assert_float(a.chain_pitch("t67c", {"ladder": [0, 7, 12]}, 1250)).is_equal_approx(1.0, 0.0001)
	assert_bool(a._chain.has("g67")).is_true()
	assert_bool(a._chain.has("a67")).is_false()


func test_plays_within_chain_min_ms_repeat_the_step() -> void:
	var row := {"ladder": [0, 7, 12], "chain_window": 0.3, "chain_min_ms": 70}
	var a := _fresh("t67m")
	assert_float(a.chain_pitch("t67m", row, 1000)).is_equal_approx(1.0, 0.0001)
	assert_float(a.chain_pitch("t67m", row, 1030)).is_equal_approx(1.0, 0.0001)
	assert_float(a.chain_pitch("t67m", row, 1060)).is_equal_approx(1.0, 0.0001)
	# 80 ms after the step's first play: the next note, though only 20 ms passed since the last play
	assert_float(a.chain_pitch("t67m", row, 1080)).is_equal_approx(_semi(7), 0.0001)
	assert_float(a.chain_pitch("t67m", row, 1100)).is_equal_approx(_semi(7), 0.0001)
	assert_float(a.chain_pitch("t67m", row, 1200)).is_equal_approx(2.0, 0.0001)
	# a flood of plays every 20 ms climbs one step per 70 ms, not one per play: 15 plays over 280 ms reach the top (3 steps)
	_fresh("t67f")
	var pitch := 0.0
	var notes: Array = []
	for k: int in range(15):
		pitch = a.chain_pitch("t67f", row, 2000 + k * 20)
		if notes.is_empty() or not is_equal_approx(float(notes[-1]), pitch):
			notes.append(pitch)
	assert_float(pitch).is_equal_approx(2.0, 0.0001)
	assert_int(notes.size()).is_equal(3)


func test_rows_without_a_ladder_keep_the_pass_65_slide() -> void:
	var row := {"chain_step": 1.0, "chain_window": 0.3, "chain_max": 3.0}
	var a := _fresh("t67l")
	assert_float(a.chain_pitch("t67l", row, 1000)).is_equal_approx(1.0, 0.0001)
	assert_float(a.chain_pitch("t67l", row, 1100)).is_equal_approx(_semi(1), 0.0001)
	a.chain_pitch("t67l", row, 1200)
	a.chain_pitch("t67l", row, 1300)
	assert_float(a.chain_pitch("t67l", row, 1400)).is_equal_approx(_semi(3), 0.0001)
	assert_float(a.chain_pitch("t67l", {}, 1500)).is_equal(1.0)


# ---------------------------------------------------------------- the gem rows

func test_the_gem_rows_carry_one_tune_in_c_major() -> void:
	for id in GEMS:
		var row := _row(id)
		var ladder = row.get("ladder")
		assert_bool(ladder is Array).override_failure_message(id + " has no ladder").is_true()
		assert_int((ladder as Array).size()).is_greater_equal(5)
		assert_str(str(row.get("chain_group", ""))).is_equal("gems")
		assert_float(float(row.get("pitch_spread", 1.0))).is_less_equal(0.01)
		assert_float(float(row.get("chain_step", 0.0))).is_greater(0.0)   # pass 65's rows keep their step
		assert_float(float(row.get("chain_window", 0.0))).is_greater_equal(0.5)
		assert_float(float(row.get("chain_min_ms", 0.0))).is_greater(0.0)
		assert_bool(str(row.get("chain_end", "hold")) in ["hold", "wrap"]).is_true()
		# the offsets start on the ding's own note, climb, and never leave C major (the dings are C6, E6 and G6)
		assert_float(float(ladder[0])).is_equal(0.0)
		var last := -1.0
		for o in ladder:
			assert_float(float(o)).is_greater(last)
			last = float(o)
			var pc := posmod(int(ROOTS[id]) + int(o), 12)
			assert_bool(pc in C_MAJOR).override_failure_message("%s: offset %s leaves C major" % [id, o]).is_true()


func test_two_gems_in_one_tick_play_one_note() -> void:
	var a: Node = Audio
	a._chain.erase("gems")
	for id in GEMS:
		a._last_played.erase(id)
		a._last_any.erase(id)
	a.play("pk_gem_s")
	a.play("pk_gem_m")
	assert_bool(a._chain.has("gems")).is_true()
	assert_int(int((a._chain["gems"] as Array)[1])).is_equal(0)
	a._chain.erase("gems")


func test_soundmap_from_dict_keeps_the_tune_keys() -> void:
	var d := {"sounds": {"x67": {"category": "pickup", "ladder": [0, 7, 12], "chain_group": "g", "chain_end": "wrap",
		"chain_min_ms": 70, "chain_step": 0.5, "file": "real/pk_gem_s.wav"}, "y67": {"category": "ui"}}}
	var sm := JsonContent.soundmap_from_dict(d, SOUNDS)
	var x: Dictionary = sm.entry("x67")
	assert_array(x["ladder"]).is_equal([0.0, 7.0, 12.0])
	assert_str(str(x["chain_group"])).is_equal("g")
	assert_str(str(x["chain_end"])).is_equal("wrap")
	assert_float(float(x["chain_min_ms"])).is_equal(70.0)
	assert_float(float(x["chain_step"])).is_equal(0.5)
	assert_bool(x.get("stream") is AudioStream).is_true()
	var y: Dictionary = sm.entry("y67")
	for k in ["ladder", "chain_group", "chain_end", "chain_min_ms"]:
		assert_bool(y.has(k)).override_failure_message(k + " should be absent").is_false()


# ---------------------------------------------------------------- the chest

func test_the_chest_is_chilled() -> void:
	# the landing: the slot's clunk and the jackpot, both lower than before (-6 / -3 dB in pass 65)
	assert_float(float(_row("ui_slot_stop")["volume_db"])).is_less_equal(-10.0)
	assert_float(float(_row("ui_jackpot")["volume_db"])).is_less_equal(-9.0)
	# TAKE: the poker chip's clack (the card pick's file) at -6 dB; purchases keep ui_buy and its level
	var take := _row("ui_chest_take")
	assert_bool(take.is_empty()).is_false()
	assert_str(str(take.get("file", ""))).is_equal("real/ui_card_pick.wav")
	assert_bool(take.get("stream") is AudioStream).is_true()
	assert_float(float(take.get("volume_db", 0.0))).is_less_equal(-6.0)
	assert_float(float(_row("ui_buy")["volume_db"])).is_greater(float(take["volume_db"]))
	assert_str(str(_row("ui_buy").get("file", ""))).is_equal("real/ui_buy.wav")
	# the doubles are gone: the landing plays the jackpot for every kind and the mega-win has one owner (Game._on_evolved;
	# High Noon plays it positionally), the lid's crack is silent (pk_chest_open plays once, at the touch), TAKE plays
	# ui_chest_take and not the ka-ching
	var chest := FileAccess.get_file_as_string("res://ui/ChestScreen.gd")
	assert_str(chest).not_contains("w_evo_reveal")
	assert_str(chest).contains("Audio.play(\"ui_jackpot\")")
	var wchest := FileAccess.get_file_as_string("res://ui/wanted/WChest.gd")
	assert_str(wchest).not_contains("\"pk_chest_open\"")
	assert_str(wchest).contains("W.sfx(knock_sound())")
	var game := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(game).contains("Audio.play(\"ui_chest_take\")")
	assert_int(game.count("Audio.play(\"w_evo_reveal\")")).is_equal(1)
	assert_int(game.count("Audio.play(\"pk_chest_open\", at)")).is_equal(2)   # the touch and a structure's use
	var closed := game.find("func _on_chest_closed(")
	assert_int(closed).is_greater(0)
	var next_func := game.find("\nfunc ", closed + 1)
	assert_str(game.substr(closed, next_func - closed)).not_contains("Audio.play(\"ui_buy\")")


# ---------------------------------------------------------------- the placeholder ids

func test_the_five_new_ids_exist_and_load() -> void:
	for id in NEW_IDS:
		var row := _row(id)
		assert_bool(row.is_empty()).override_failure_message("no row " + id).is_false()
		var file := str(row.get("file", ""))
		assert_str(file).is_equal("placeholder/%s.wav" % id)
		assert_bool(FileAccess.file_exists(SOUNDS + file)).override_failure_message("no file " + file).is_true()
		assert_bool(row.get("stream") is AudioStream).override_failure_message("no stream " + id).is_true()
	for id in ["w_ball_throw", "w_ball_bounce", "w_ball_catch"]:
		assert_str(str(_row(id).get("category", ""))).is_equal("weapon")
	assert_str(str(_row("pk_timeout").get("category", ""))).is_equal("pickup")
	assert_str(str(_row("ui_buzzer").get("category", ""))).is_equal("ui")
