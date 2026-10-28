## Pass 112, lane WANTED: the Wanted posters float over the run (Garry: "this should appear at the beginning of a run
## right after the descend sequence. And make it so it's not a full screen, but more like floating posters instead.
## Similar logic though."). ui/BountyPosters.gd, Game._offer_bounty / Modal.BOUNTY; BALANCING.md 55.WANTED.
##  1. after the spawn beam's landing the posters come over the paused run (a finished run behind the save), never for a
##     first-time player, never when a tool's launch names its own `bounty`;
##  2. a poster taken starts its contract and its HUD plate, the board is forgotten, the run goes on;
##  3. "No bounty" leaves no contract and the run goes on;
##  4. the one-screen rule: a level-up while the posters are up waits for them, never two screens at once; BOUNTY sits
##     after the level cards and before a path offer;
##  5. the title, the Stages menu and PLAY AGAIN go straight into the run again (pass 111's board screen is gone).
extends GdUnitTestSuite

const MAP := "red_canyon"


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	WantedBoard.set_config({})


func after_test() -> void:
	WantedRun.current = null
	get_tree().paused = false
	Run.arena = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _game(extra: Dictionary = {}) -> Game:
	var d := {"weapon": "revolver", "level": 1, "character": "drifter", "map": MAP, "map_seed": 11, "analytics": false}
	d.merge(extra, true)
	_launch(d)
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func _meet_everything() -> void:
	for id in Registry.enemies.keys():
		Save.mark_seen("enemy", str(id))
	for id in Registry.weapons.keys():
		Save.mark_seen("weapon", str(id))


## Waits (real seconds, at most `limit`) until `cond` holds.
func _until(cond: Callable, limit: float = 6.0) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call():
			return true
		await get_tree().create_timer(0.1, true, false, true).timeout
		t += 0.1
	return bool(cond.call())


# ---------------------------------------------------------------- 1. after the landing, not for a first-time player

func test_the_posters_float_in_after_the_landing() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var g := _game({"spawn": true})
	await get_tree().process_frame
	assert_bool(g.spawning).is_true()
	assert_bool(g.bounty_posters.visible).is_false()
	g.spawn_rate = Game.SPAWN_HURRY
	var landed: bool = await _until(func() -> bool: return not g.spawning)
	assert_bool(landed).is_true()
	# not at the landing itself: the dust settles first
	assert_bool(g.bounty_posters.visible).is_false()
	var up: bool = await _until(func() -> bool: return g.bounty_posters.visible, 3.0)
	assert_bool(up).is_true()
	assert_bool(g.paused).is_true()
	assert_int(g.current_modal()).is_equal(Game.Modal.BOUNTY)
	assert_array(g.visible_modals()).is_equal(["bounty"])
	assert_int((g.bounty_posters.cards() as Array).size()).is_equal(3)
	# not a full-screen board: a light dim over the run, and the HUD steps aside while they hang
	assert_float(g.bounty_posters.dim.color.a).is_less(0.5)
	await get_tree().create_timer(0.3, true, false, true).timeout
	assert_bool(g.hud.visible).is_false()


func test_a_first_time_player_lands_without_posters() -> void:
	assert_int(Save.total("runs")).is_equal(0)
	var g := _game({"spawn": true})
	await get_tree().process_frame
	g.spawn_rate = Game.SPAWN_HURRY
	await _until(func() -> bool: return not g.spawning)
	await get_tree().create_timer(Game.BOUNTY_AFTER_LAND + 0.6, true, false, true).timeout
	assert_bool(g.bounty_posters.visible).is_false()
	assert_bool(g.paused).is_false()
	assert_object(WantedRun.current).is_null()


func test_a_tools_own_bounty_keeps_the_posters_away() -> void:
	Save.add_total("runs", 1)
	var g := _game({"bounty_board": true, "bounty": "none"})
	await get_tree().create_timer(0.4, true, false, true).timeout
	assert_bool(g.bounty_posters.visible).is_false()
	assert_bool(g.paused).is_false()


# ---------------------------------------------------------------- 2. and 3. taken, or blown away

func test_a_poster_taken_starts_its_contract_and_plate() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var g := _game({"bounty_board": true})
	var up: bool = await _until(func() -> bool: return g.bounty_posters.visible, 3.0)
	assert_bool(up).is_true()
	var posters: Array = g.bounty_posters.posters
	assert_bool((WantedBoard.store()["boards"] as Dictionary).is_empty()).is_false()
	g.bounty_posters.choose(1)
	assert_str(str(g.bounty_posters.chosen)).is_equal("taken")
	# a second tap does nothing
	g.bounty_posters.choose(0)
	assert_str(str(g.bounty_posters.chosen)).is_equal("taken")
	# the contract is on at once, its plate unseen until the poster has flown into it
	assert_object(WantedRun.current).is_not_null()
	assert_str(str(WantedRun.current.contract["type"])).is_equal(str(posters[1]["type"]))
	assert_float(WantedRun.current.plate().modulate.a).is_less(0.1)
	var gone: bool = await _until(func() -> bool: return not g.bounty_posters.visible and not g.paused, 3.0)
	assert_bool(gone).is_true()
	await get_tree().create_timer(0.4, true, false, true).timeout
	assert_float(WantedRun.current.plate().modulate.a).is_greater(0.9)
	assert_bool(WantedRun.current.plate().get_parent() == g.hud).is_true()
	assert_int(g.current_modal()).is_equal(Game.Modal.NONE)
	assert_bool((WantedBoard.store()["boards"] as Dictionary).is_empty()).is_true()
	assert_int(int(WantedBoard.store()["taken"])).is_equal(1)


func test_no_bounty_blows_them_away() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var g := _game({"bounty_board": true})
	var up: bool = await _until(func() -> bool: return g.bounty_posters.visible, 3.0)
	assert_bool(up).is_true()
	g.bounty_posters.choose(-1)
	assert_str(str(g.bounty_posters.chosen)).is_equal("none")
	var gone: bool = await _until(func() -> bool: return not g.bounty_posters.visible and not g.paused, 3.0)
	assert_bool(gone).is_true()
	assert_object(WantedRun.current).is_null()
	assert_object(g.get_node_or_null("WantedRun")).is_null()
	assert_bool((WantedBoard.store()["boards"] as Dictionary).is_empty()).is_true()
	assert_int(int(WantedBoard.store().get("taken", 0))).is_equal(0)


# ---------------------------------------------------------------- 4. the one-screen rule

func test_a_level_up_waits_for_the_posters() -> void:
	assert_int(int(Game.MODAL_PRIORITY[Game.Modal.BOUNTY])).is_less(int(Game.MODAL_PRIORITY[Game.Modal.CARDS]))
	assert_int(int(Game.MODAL_PRIORITY[Game.Modal.BOUNTY])).is_greater(int(Game.MODAL_PRIORITY[Game.Modal.PATH]))
	Save.add_total("runs", 1)
	_meet_everything()
	var g := _game({"bounty_board": true})
	var up: bool = await _until(func() -> bool: return g.bounty_posters.visible, 3.0)
	assert_bool(up).is_true()
	# a level reached while they hang (XP collected at the landing): the cards wait their turn
	Run.add_xp(Run.xp_to_next() + 1.0)
	assert_array(g.visible_modals()).is_equal(["bounty"])
	assert_bool(g.modal_queue_kinds().has(Game.Modal.CARDS)).is_true()
	g.bounty_posters.choose(-1)
	var two := [false]
	var cards_up: bool = await _until(func() -> bool:
		if g.visible_modals().size() > 1:
			two[0] = true
		return g.cards.visible, 4.0)
	assert_bool(cards_up).is_true()
	assert_bool(two[0]).is_false()
	assert_array(g.visible_modals()).is_equal(["cards"])


# ---------------------------------------------------------------- 5. the menus go straight into the run

func test_the_menus_go_straight_into_the_run() -> void:
	assert_bool(ResourceLoader.exists("res://ui/WantedBoardScreen.tscn")).is_false()
	for path in ["res://ui/TitleScreen.gd", "res://ui/StagesScreen.gd", "res://ui/ResultsScreen.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_bool(src.contains("run_scene")).override_failure_message(path).is_false()
		assert_bool(src.contains("res://game/Game.tscn")).override_failure_message(path).is_true()


func test_a_reroll_when_the_config_gives_one() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var cfg := WantedBoard.config().duplicate(true)
	cfg["rerolls"] = 1
	WantedBoard.set_config(cfg)
	var g := _game({"bounty_board": true})
	var up: bool = await _until(func() -> bool: return g.bounty_posters.visible, 3.0)
	assert_bool(up).is_true()
	var rr: Control = g.bounty_posters.find_child("Reroll", true, false)
	assert_bool(rr.visible).is_true()
	g.bounty_posters._on_reroll()
	await get_tree().process_frame
	assert_int((g.bounty_posters.cards() as Array).size()).is_equal(3)
	assert_bool(rr.visible).is_false()
	assert_bool(g.bounty_posters.visible).is_true()
	# by default there is none
	WantedBoard.set_config({})
	assert_int(int(WantedBoard.config()["rerolls"])).is_equal(0)
