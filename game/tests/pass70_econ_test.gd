## Pass 70, lane ECON (Garry: "Make Coins stay if Player dies. But make the prices for every unlock that we have right
## now considerably more expensive. Make Elites and Bosses give much more Coins. Remove the Balloon Chest thing now." and
## "The new Collection button is wrong: make it the same height as the Hero plaque while maintaining square aspect
## ratio ... It should just be a matrix of squares. The 3x3 was the last one at the bottom, missing."): every end of a
## run banks the purse once (Game.bank_run_end); every talent rank and hero price is x2.5 of pass 69's; an Elite's and a
## boss's gold x5 (Game.ELITE_PURSE / BOSS_PURSE, the bosses' drops.coins, PickupManager.BIG_COIN_MULT); the Strongbox
## (gold_bank) is hidden and never stands on a map; the title's Hero Collections button is a square as tall as the
## plaque with eight squares of a 3 x 3 grid for its glyph.
extends GdUnitTestSuite

const Stage := preload("res://ui/TitleStage.gd")
const Title := preload("res://ui/TitleScreen.gd")

## Pass 69's talent prices, before x2.5 (pass 46's curve: x1, x1.8, x3, x4.5, x6.5, x9 of the first rank).
const TALENTS_69 := {
	"choice": [180, 324, 540, 810, 1170, 1620], "drive": [160, 288, 480, 720, 1040, 1440],
	"fortune": [150, 270, 450, 675, 975, 1350], "grit": [140, 252, 420, 630, 910, 1260],
	"nerve": [220, 396, 660, 990, 1430, 1980], "spite": [200, 360, 600, 900, 1300, 1800],
	"stride": [120, 216, 360, 540, 780, 1080], "study": [170, 306, 510, 765, 1105, 1530]}
## The heroes' prices (INTERFACES: x2.5 of pass 69's, Fadeaway's 50 a stand-in raised to 1,000; Mira stays 9,999).
const HERO_PRICES := {"calavera": 750, "ironwood": 1000, "solenne": 1500, "buck": 1250, "may": 1750, "fadeaway": 1000,
	"mira": 9999}

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"style": Settings.menu_style, "preview": Settings.preview_locked_heroes, "inset": Settings.top_inset}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	Stage.forget()
	Settings.menu_style = str(_keep["style"])
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Settings.top_inset = int(_keep["inset"])
	get_tree().paused = false
	Run.arena = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


## The real game on Red Canyon, the instant start (no beam), no analytics.
func _run_game(seed: int = 11) -> Game:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": seed, "analytics": false})
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


# ---------------------------------------------------------------- 1. the purse comes home, whatever the end

func test_every_end_banks_the_whole_purse() -> void:
	for end in ["death", "abandon", "extract"]:
		Save.data = Save._default()
		Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
		Run.arena = false
		Run.add_gold(300, "coins")
		Run.spend_gold(40, "shop")
		Run.died = end != "extract"
		Run.extracted = end == "extract"
		var before := Save.gold()
		var moved: Array = []
		var cb := func(delta: int, reason: String, _balance: int, _extra: Dictionary) -> void: moved.append([delta, reason])
		Save.gold_moved.connect(cb)
		var banked := Game.bank_run_end("red_canyon")
		Save.gold_moved.disconnect(cb)
		assert_int(banked).override_failure_message(end).is_equal(260)
		assert_int(Save.gold()).override_failure_message(end).is_equal(before + 260)
		# one move into the save, the same reason for every end (run_end's result tells them apart)
		assert_array(moved).override_failure_message(end).is_equal([[260, "run_bank"]])
		var res: Dictionary = Run.last_result
		assert_int(int(res["banked"])).is_equal(260)
		assert_int(int(res["lost"])).is_equal(0)
		assert_int(int(res["gold_before"])).is_equal(before)
		Run.end()


func test_an_empty_purse_moves_nothing() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.died = true
	var before := Save.gold()
	assert_int(Game.bank_run_end("red_canyon")).is_equal(0)
	assert_int(Save.gold()).is_equal(before)


func test_a_second_end_run_banks_nothing() -> void:
	# end_run banks once: past the first, _ended turns every later call away before the gold
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	Run.add_gold(500, "coins")
	Run.died = true
	var g: Game = auto_free(Game.new())
	g._ended = true
	var before := Save.gold()
	g.end_run()
	assert_int(Save.gold()).is_equal(before)
	assert_int(Run.run_gold).is_equal(500)
	# and the source says so: the banking sits after the guard, once
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	var body := src.substr(src.find("func end_run() -> void:"), 1200)
	assert_int(body.find("if _ended:")).is_greater(0)
	assert_int(body.find("bank_run_end(")).is_greater(body.find("_ended = true"))
	assert_int(body.count("bank_run_end(")).is_equal(1)


func test_a_death_counts_as_banked_in_the_analytics() -> void:
	var ra := RunAnalytics.new()
	ra.header = {"gold": 200, "result": "death", "strongbox": 0, "gold_before": 0}
	Run.died = true
	var g := ra.gold_end(200)
	assert_int(int(g["gold_banked"])).is_equal(200)
	assert_int(int(g["gold_lost"])).is_equal(0)
	ra.header["result"] = "abandon"
	assert_int(int(ra.gold_end(200)["gold_lost"])).is_equal(0)
	# a quit (the app gone before end_run) still never brought the purse home
	ra.header["result"] = "quit"
	assert_int(int(ra.gold_end(0)["gold_lost"])).is_equal(200)
	ra.free()


func test_the_results_after_a_death_show_the_gold_banked() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.died = true
	(Save.data["hints_seen"] as Array).append("results")
	Run.last_result = {"gold_before": 100, "banked": 30, "lost": 0, "strongbox": 0, "prev_best": {}}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	await get_tree().process_frame
	var texts := ""
	for n in r.find_children("*", "", true, false):
		if n is WText:
			texts += (n as WText).text + " | "
	assert_str(texts).contains("Banked")
	assert_str(texts).contains("100 → 130")
	assert_str(texts).not_contains("Left in the sand")
	assert_bool(r._count.strike).is_false()
	assert_object(r.find_child("Strongbox", true, false)).is_null()
	r.visible = false


func test_no_text_says_the_gold_stays_in_the_sand() -> void:
	for path in ["res://ui/ResultsScreen.gd", "res://ui/PortalDialog.gd", "res://ui/ReviveScreen.gd", "res://ui/PauseScreen.gd",
			"res://ui/Hints.gd", "res://ui/HomesteadScreen.gd", "res://ui/HUD.gd"]:
		var src := FileAccess.get_file_as_string(path).to_lower()
		for said in ["stays in the sand", "left in the sand", "only an extraction brings", "is lost · asks", "the strongbox keeps"]:
			assert_int(src.find(said)).override_failure_message("%s still says '%s'" % [path, said]).is_equal(-1)


# ---------------------------------------------------------------- 2. prices x2.5

func test_every_talent_rank_costs_two_and_a_half_times_pass_69s() -> void:
	assert_int(Registry.talents_list().size()).is_equal(TALENTS_69.size())
	for td: TalentDef in Registry.talents_list():
		assert_bool(TALENTS_69.has(td.id)).override_failure_message(td.id).is_true()
		var was: Array = TALENTS_69[td.id]
		for k in was.size():
			# x2.5, a half (x4.5 / x6.5 of an odd first rank) to the nearest 5
			var want := int(5 * round(float(was[k]) * 2.5 / 5.0))
			assert_int(td.cost_of_rank(k)).override_failure_message("%s rank %d" % [td.id, k + 1]).is_equal(want)


func test_every_hero_on_sale_costs_his_new_price() -> void:
	# pass 72, lane INTEG (re-pinned): pass 70 set HERO_PRICES (x2.5); Garry prices heroes in the Level Editor since
	# (2026-10-13: Astro on sale at 300, Calavera 300), so the rule is pinned: every hero there, every one on sale at a
	# gold price above 0, the Drifter (the default hero) free
	for id in HERO_PRICES:
		var c: CharacterDef = Registry.character(id)
		assert_object(c).override_failure_message(id).is_not_null()
	for c: CharacterDef in Registry.characters.values():
		if c.availability == "purchase" and not c.hidden:
			assert_int(c.price).override_failure_message(c.id).is_greater(0)
			assert_str(c.currency_type).override_failure_message(c.id).is_equal("gold")
	assert_str(Registry.character("drifter").availability).is_equal("available")
	assert_int(Registry.character("drifter").price).is_equal(0)


# ---------------------------------------------------------------- 3. Elites and bosses x5

func test_elite_and_boss_purses_are_five_times_pass_44s() -> void:
	for s in 4:
		assert_int(Game.elite_purse(s)).is_equal(5 * (90 + 60 * s))
		assert_int(Game.boss_purse(s)).is_equal(5 * (260 + 140 * s))
	assert_int(Game.BOSS_COINS).is_equal(5 * 12)
	# the bosses' coins on the sand: x5 of pass 69's (12 by default, 30, 40)
	assert_int(int(Registry.enemy("tumbleweed_king").drops.get("coins", 0))).is_equal(60)
	assert_int(int(Registry.enemy("gila_grande").drops.get("coins", 0))).is_equal(150)
	assert_int(int(Registry.enemy("brander").drops.get("coins", 0))).is_equal(200)
	# an Elite's or a boss's own coin is worth five creatures' coins; a plain creature's stays
	assert_float(PickupManager.big_coin_mult(Registry.enemy("dune_scorpion"), false)).is_equal(5.0)
	assert_float(PickupManager.big_coin_mult(Registry.enemy("goblin"), true)).is_equal(5.0)
	assert_float(PickupManager.big_coin_mult(Registry.enemy("brander"), false)).is_equal(5.0)
	assert_float(PickupManager.big_coin_mult(Registry.enemy("goblin"), false)).is_equal(1.0)


func test_a_real_elite_and_boss_kill_pay_the_new_gold() -> void:
	var g := _run_game()
	await get_tree().create_timer(0.5).timeout
	g.director.stop()
	g.enemies.kill_all(false)
	var at: Vector3 = g.player.global_position + Vector3(6, 0, 0)
	Run.run_gold = 0
	g._kill_effects(Registry.enemy("dune_scorpion"), at, null, "")
	assert_int(Run.run_gold).is_equal(450)
	# a regular creature in an Elite's modifier pays the same purse
	g._kill_effects(Registry.enemy("goblin"), at, Registry.elites.get("speedy"), "")
	assert_int(Run.run_gold).is_equal(900)
	# the King: his purse at once and sixty coins on the sand
	var coins_before: int = g.pickups.coins
	g._kill_effects(Registry.enemy("tumbleweed_king"), at, null, "")
	assert_int(Run.run_gold).is_equal(900 + 1300)
	assert_int(g.pickups.coins - coins_before).is_equal(60)


# ---------------------------------------------------------------- 4. no Strongbox

func test_the_strongbox_is_retired_but_kept() -> void:
	var d: StructureDef = Registry.structure("gold_bank")
	assert_object(d).is_not_null()
	assert_bool(d.hidden).is_true()
	var all: Array = Registry.structures.values()
	var playing := StructureManager.in_play(all)
	assert_int(playing.size()).is_equal(all.size() - 1)
	assert_bool(playing.has(d)).is_false()
	# a roster naming it still leaves it out
	assert_int(StructureManager.in_play([d, Registry.structure("shop")]).size()).is_equal(1)


func test_no_strongbox_stands_in_a_long_run() -> void:
	var g := _run_game(5)
	await get_tree().create_timer(0.4).timeout
	g.director.stop()
	var sm: StructureManager = g.structures
	var plan: Dictionary = Run.map.timeline.structures
	assert_int(sm.items.size()).is_equal(maxi(int(plan.get("count", 0)), StructureManager.in_play(Registry.structures.values()).size()))
	for s in sm.items:
		assert_str(s.def.id).is_not_equal("gold_bank")
	# half an hour of the structures' own clock (the returns live there): nothing comes down
	for k in 1800:
		sm._process(1.0)
	assert_int(sm.returns).is_equal(0)
	for s in sm.items:
		assert_str(s.def.id).is_not_equal("gold_bank")
	# and ten more scatters of the map's plan: never one
	for k in 10:
		var sm2 := StructureManager.new()
		g.add_child(sm2)
		sm2.setup(g, g.map, plan)
		for s in sm2.items:
			assert_str(s.def.id).is_not_equal("gold_bank")
		sm2.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- 5. the Collection button

func _title(style: String) -> Control:
	Settings.menu_style = style
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	return t


func test_the_hero_button_is_a_square_as_tall_as_the_plaque() -> void:
	for style in ["painted", "live"]:
		var t := await _title(style)
		var btn: Control = t.find_child("HeroesButton", false, false)
		assert_object(btn).is_not_null()
		var plaque: Control = t._plaque
		for i in (t._heroes as Array).size():
			t._index = i
			t._show_hero(0)
			t._place()
			await get_tree().process_frame
			var who := "%s %s" % [style, (t._heroes[i] as CharacterDef).id]
			assert_float(btn.size.x).override_failure_message(who).is_equal_approx(btn.size.y, 0.5)
			assert_float(btn.size.y).override_failure_message(who).is_equal_approx(plaque.size.y, 1.0)
			assert_float(btn.position.y).override_failure_message(who).is_equal_approx(plaque.position.y, 1.0)
			# left of the plaque, the gap between them kept
			assert_float(plaque.position.x - btn.position.x - btn.size.x).is_equal_approx(Title.BOX_GAP, 0.5)
			assert_bool(btn.get_global_rect().end.x <= plaque.get_global_rect().position.x).is_true()
		t.visible = false
		Stage.forget()


func test_the_glyph_is_eight_squares_of_a_three_by_three_grid() -> void:
	for side in [104.0, 180.0, 233.0]:
		var cells: Array = Title.glyph_cells(Vector2(side, side))
		assert_int(cells.size()).is_equal(8)
		var xs := {}
		var ys := {}
		for r: Rect2 in cells:
			# plain squares, whole pixels
			assert_float(r.size.x).is_equal(r.size.y)
			assert_float(r.size.x).is_greater(4.0)
			assert_float(r.position.x).is_equal(roundf(r.position.x))
			assert_float(r.position.y).is_equal(roundf(r.position.y))
			xs[r.position.x] = true
			ys[r.position.y] = true
		assert_int(xs.size()).is_equal(3)
		assert_int(ys.size()).is_equal(3)
		var cx: Array = xs.keys()
		var cy: Array = ys.keys()
		cx.sort()
		cy.sort()
		# the bottom-right one is the one missing
		for r: Rect2 in cells:
			assert_bool(r.position.x == cx[2] and r.position.y == cy[2]).is_false()
		# even steps, inside the button, centred
		assert_float(cx[1] - cx[0]).is_equal(cx[2] - cx[1])
		assert_float(cy[1] - cy[0]).is_equal(cy[2] - cy[1])
		var sq: float = (cells[0] as Rect2).size.x
		var span: float = cx[2] + sq - cx[0]
		assert_float(cx[0]).is_greater(0.0)
		assert_float(absf(cx[0] - (side - (cx[2] + sq)))).is_less_equal(1.0)
		assert_float(span).is_less_equal(side * Title.GLYPH_SPAN + 0.5)
		assert_float(span).is_greater(side * Title.GLYPH_SPAN - 4.0)
