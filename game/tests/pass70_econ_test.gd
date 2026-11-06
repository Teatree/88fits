## Pass 70, lane ECON (Garry: "Make Coins stay if Player dies. But make the prices for every unlock that we have right
## now considerably more expensive. Make Elites and Bosses give much more Coins. Remove the Balloon Chest thing now." and
## "The new Collection button is wrong: make it the same height as the Hero plaque while maintaining square aspect
## ratio ... It should just be a matrix of squares. The 3x3 was the last one at the bottom, missing."): every end of a
## run banks the purse once (Game.bank_run_end); every hero price is x2.5 of pass 69's (the Upgrade board's ranks too, until the board left in pass 129); an Elite's and a
## boss's gold x5 (Game.ELITE_PURSE / BOSS_PURSE, the bosses' drops.coins, PickupManager.BIG_COIN_MULT); the Strongbox
## (gold_bank) is hidden and never stands on a map; the title's Hero Collections button is a square as tall as the
## plaque with eight squares of a 3 x 3 grid for its glyph.
extends GdUnitTestSuite

const Stage := preload("res://ui/TitleStage.gd")
const Title := preload("res://ui/TitleScreen.gd")

## The heroes' prices (INTERFACES: x2.5 of pass 69's, Fadeaway's 50 a stand-in raised to 1,000; Mira stays 9,999).
const HERO_PRICES := {"calavera": 750, "ironwood": 1000, "solenne": 1500, "buck": 1250, "may": 1750, "fadeaway": 1000,
	"mira": 9999}

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"preview": Settings.preview_locked_heroes, "inset": Settings.top_inset}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	Stage.forget()
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
	assert_str(texts).contains("BANKED")
	assert_str(texts).contains("100 → 130")
	assert_str(texts).not_contains("Left in the sand")
	assert_bool(r._count.strike).is_false()
	assert_object(r.find_child("Strongbox", true, false)).is_null()
	r.visible = false


func test_no_text_says_the_gold_stays_in_the_sand() -> void:
	for path in ["res://ui/ResultsScreen.gd", "res://ui/PortalDialog.gd", "res://ui/ReviveScreen.gd", "res://ui/PauseScreen.gd",
			"res://ui/Hints.gd", "res://ui/TrailScreen.gd", "res://ui/HUD.gd"]:
		var src := FileAccess.get_file_as_string(path).to_lower()
		for said in ["stays in the sand", "left in the sand", "only an extraction brings", "is lost · asks", "the strongbox keeps"]:
			assert_int(src.find(said)).override_failure_message("%s still says '%s'" % [path, said]).is_equal(-1)


# ---------------------------------------------------------------- 2. prices x2.5

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
	# (pass 110, lane ECON, re-pinned: Garry's "Reduce the coins gain from Boss, Elite and Specials. By 50%": x5 of pass
	# 44's, then halved: x2.5; pass 111, lane WANTED: halved again, x1.25, the purse's half coin dropped)
	for s in 4:
		assert_int(Game.elite_purse(s)).is_equal(int(1.25 * (90 + 60 * s)))
		assert_int(Game.boss_purse(s)).is_equal(int(1.25 * (260 + 140 * s)))
	assert_int(Game.BOSS_COINS).is_equal(15)
	# the bosses' coins on the sand: x5 of pass 69's (12 by default, 30, 40), halved in pass 110 and again in pass 111
	assert_int(int(Registry.enemy("tumbleweed_king").drops.get("coins", 0))).is_equal(15)
	assert_int(int(Registry.enemy("gila_grande").drops.get("coins", 0))).is_equal(37)
	assert_int(int(Registry.enemy("brander").drops.get("coins", 0))).is_equal(50)
	# an Elite's or a boss's own coin is worth 1.25 creatures' coins (5 until pass 110, 2.5 until pass 111); a plain
	# creature's stays
	assert_float(PickupManager.big_coin_mult(Registry.enemy("dune_scorpion"), false)).is_equal(1.25)
	assert_float(PickupManager.big_coin_mult(Registry.enemy("goblin"), true)).is_equal(1.25)
	assert_float(PickupManager.big_coin_mult(Registry.enemy("brander"), false)).is_equal(1.25)
	assert_float(PickupManager.big_coin_mult(Registry.enemy("goblin"), false)).is_equal(1.0)


func test_a_real_elite_and_boss_kill_pay_the_new_gold() -> void:
	var g := _run_game()
	await get_tree().create_timer(0.5).timeout
	g.director.stop()
	g.enemies.kill_all(false)
	var at: Vector3 = g.player.global_position + Vector3(6, 0, 0)
	Run.run_gold = 0
	g._kill_effects(Registry.enemy("dune_scorpion"), at, null, "")
	# (pass 110, lane ECON, re-pinned: the purses halved; pass 111, lane WANTED: halved again)
	assert_int(Run.run_gold).is_equal(112)
	# a regular creature in an Elite's modifier pays the same purse
	g._kill_effects(Registry.enemy("goblin"), at, Registry.elites.get("speedy"), "")
	assert_int(Run.run_gold).is_equal(224)
	# the King: his purse at once and fifteen coins on the sand (sixty until pass 110, thirty until pass 111)
	var coins_before: int = g.pickups.coins
	g._kill_effects(Registry.enemy("tumbleweed_king"), at, null, "")
	assert_int(Run.run_gold).is_equal(224 + 325)
	assert_int(g.pickups.coins - coins_before).is_equal(15)


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
	# pass 73: the draw's structures; the Totem Poles (params.per_map) stand their own count beside them
	var drawn_items: Array = sm.items.filter(func(s) -> bool: return StructureManager.per_map_range(s.def) == Vector2i(-1, -1))
	assert_int(drawn_items.size()).is_equal(maxi(int(plan.get("count", 0)), StructureManager.drawn(StructureManager.in_play(Registry.structures.values())).size()))
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
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	return t
