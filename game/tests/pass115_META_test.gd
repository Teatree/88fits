## Pass 115, lane META. The game's name on screen (Garry: "Rename the game to Outlaw Survivors, but only in the game
## itself ... we just write 'Outlaw' with big fat text and the 'Drag Dodge Survive' is replaced with simply 'Survivors'"):
## the title's OUTLAW / SURVIVORS, the Settings version line. And Nerve (Garry: "Change the Revive to only affect the
## amount of HP Player gets when they revive ... by default ... 40% of their health ... all at max ... 100% ... skips and
## this new revive thing are not valuable at all, rebalance their ordering in the view as well as their prices"): a
## revive stands him up at 40% with no rank, +10% a Second Wind rank to 100% at six, no revives from Nerve, Nerve
## the second cheapest talent on the board, an older save's overpaid ranks paid back once; the Phoenix Feather keeps 50%.
extends GdUnitTestSuite

const Title := preload("res://ui/TitleScreen.gd")
const Stage := preload("res://ui/TitleStage.gd")
const HS := preload("res://ui/HomesteadScreen.gd")
const SettingsScreenScript := preload("res://ui/SettingsScreen.gd")

## Nerve's new prices, rank by rank (rank k = k x k x 150, the board's pass 110 ladder).
const NERVE_COST := [150, 600, 1350, 2400, 3750, 5400]
## The board top to bottom: by the first rank's price, `order` the same.
const BOARD := ["spite", "nerve", "fortune", "choice", "drive", "study", "stride", "grit"]

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"style": Settings.menu_style, "preview": Settings.preview_locked_heroes, "inset": Settings.top_inset,
		"data": Save.data.duplicate(true)}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Run.arena = false
	Run.end()
	Stage.forget()
	Settings.menu_style = str(_keep["style"])
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Settings.top_inset = int(_keep["inset"])
	Save.data = _keep["data"]
	Save._dirty = false


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _nerve() -> TalentDef:
	return Registry.talent("nerve")


## A hero on the field, felled, as Game._on_player_died finds him.
func _felled() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Run.character)
	p.hp = p.max_hp
	p.take_damage(99999.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_bool(p.dead).is_true()
	return p


# ---------------------------------------------------------------- 1. the name

func test_the_title_reads_outlaw_and_survivors() -> void:
	assert_str(W.GAME_NAME).is_equal("Outlaw Survivors")
	Settings.menu_style = "painted"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	var logo: WText = t.find_child("Logo", true, false)
	var tag: WText = t.find_child("Tagline", true, false)
	assert_object(logo).is_not_null()
	assert_object(tag).is_not_null()
	assert_str(logo.text).is_equal("OUTLAW")
	assert_str(tag.text).is_equal("SURVIVORS")
	# no "88fits" or "Drag · Dodge · Survive" left on the title
	for n in t.find_children("*", "WText", true, false):
		var s := str((n as WText).text)
		assert_str(s).override_failure_message(s).not_contains("88fits")
		assert_str(s.to_lower()).override_failure_message(s).not_contains("dodge")
	# the big word fits the 1080 px canvas with its shadow and a 16 px gutter each side
	var w := W.slab().get_string_size("OUTLAW", HORIZONTAL_ALIGNMENT_LEFT, -1, Title.LOGO_PX).x + float(logo.shadow)
	assert_float(w).is_less_equal(1080.0 - 32.0)
	# and it stays big: wider than "88fits" was at 210
	assert_float(w).is_greater(W.slab().get_string_size("88fits", HORIZONTAL_ALIGNMENT_LEFT, -1, 210).x)


func test_the_settings_line_names_the_game() -> void:
	var line: String = SettingsScreenScript.version_line()
	assert_str(line).starts_with("Outlaw Survivors v")
	assert_str(line).contains(Save.player_name())


# ---------------------------------------------------------------- 2. Second Wind: revive health only

func test_a_revive_stands_him_up_at_forty_percent_with_no_rank() -> void:
	assert_float(_nerve().base_of("revive_hp", -1.0)).is_equal_approx(0.4, 0.0001)
	_start()
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(0.4, 0.0001)
	var p := _felled()
	p.revive()
	assert_float(p.hp).is_equal_approx(p.max_hp * 0.4, 0.001)


func test_six_second_wind_ranks_give_a_whole_revive_and_no_extra_one() -> void:
	Save.data["talents"] = {"nerve": {"picks": [1, 1, 1, 1, 1, 1]}}
	_start()
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(1.0, 0.0001)
	# Nerve gives no revives: Down! offers its one chance a run, as without it (Game._open_revive's count)
	assert_float(Run.player_sheet.get_stat("revives", 0.0)).is_equal(0.0)
	var chances: int = 1 + Run.player_sheet.get_int("revives", 0) - Run.revives_used
	assert_int(chances).is_equal(1)
	var p := _felled()
	p.revive()
	assert_float(p.hp).is_equal_approx(p.max_hp, 0.001)


func test_every_second_wind_rank_is_ten_points_of_revive_health_and_nothing_else() -> void:
	var nerve := _nerve()
	assert_str(nerve.form_name(1)).is_equal("Second Wind")
	for r in range(1, 7):
		var revive_hp := 0.0
		for e: Effect in nerve.effects_for(1, r):
			assert_str(e.stat).override_failure_message("rank %d: %s" % [r, e.stat]).is_equal("revive_hp")
			assert_str(e.op).is_equal("add")
			revive_hp += e.value
		assert_float(revive_hp).override_failure_message("rank %d" % r).is_equal_approx(0.1 * r, 0.0001)
		assert_float(nerve.base_of("revive_hp", 0.0) + revive_hp).is_less_equal(1.0 + 0.0001)
	# Skip is as it was: +1 skip a stage, a rank
	assert_str(nerve.form_name(0)).is_equal("Skip")
	assert_str((nerve.effects_for(0, 1)[0] as Effect).stat).is_equal("skips")
	assert_float((nerve.effects_for(0, 1)[0] as Effect).value).is_equal(1.0)
	# no form of any talent gives revives now
	for td: TalentDef in Registry.talents.values():
		for f in range(td.forms.size()):
			for e: Effect in td.effects_for(f, td.max_rank()):
				assert_str(e.stat).override_failure_message(td.id).is_not_equal("revives")


func test_the_board_says_the_revive_health_in_plain_words() -> void:
	var nerve := _nerve()
	Save.data["talents"] = {"nerve": {"picks": [1]}}
	assert_str(HS.held_line(nerve)).is_equal("Revive with 50% health")
	Save.data["talents"] = {"nerve": {"picks": [1, 1]}}
	assert_str(HS.held_line(nerve)).is_equal("Revive with 60% health")
	Save.data["talents"] = {"nerve": {"picks": [0, 0, 1]}}
	assert_str(HS.held_line(nerve)).is_equal("+2 skips, revive with 50% health")
	Save.data["talents"] = {"nerve": {"picks": [1, 1, 1, 1, 1, 1]}}
	assert_str(HS.held_line(nerve)).is_equal("Revive with 100% health")
	# a plain add of revive health still reads as a step (an item's card, the pause screen's sources)
	assert_str(TextGen.describe_effect(Effect.make("revive_hp", "add", 0.1, "player"))).is_equal("+10% health on revive")
	assert_str(TextGen.describe_effect(Effect.make("revive_hp", "set", 0.7, "player"))).is_equal("revive with 70% health")


func test_the_phoenix_feather_keeps_its_half_health() -> void:
	_start()
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_true()
	# the feather's own floor; the plain revive health stays Nerve's 40%
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(0.4, 0.0001)
	var p := _felled()
	assert_float(p.revive_share(true)).is_equal_approx(0.5, 0.0001)
	assert_float(p.revive_share(false)).is_equal_approx(0.4, 0.0001)
	Run.use_phoenix()
	p.revive(true)
	assert_float(p.hp).is_equal_approx(p.max_hp * 0.5, 0.001)
	# Second Wind still raises a Phoenix revive once it passes the feather's half: three ranks, 70%
	Run.end()
	Save.data["talents"] = {"nerve": {"picks": [1, 1, 1]}}
	_start()
	Run.add_or_level_passive("phoenix_feather")
	var q := _felled()
	assert_float(q.revive_share(true)).is_equal_approx(0.7, 0.0001)


# ---------------------------------------------------------------- 3. the price and the place on the board

func test_nerve_costs_a_k_squared_ladder_from_150() -> void:
	var nerve := _nerve()
	assert_int(nerve.cost.size()).is_equal(6)
	for k in range(6):
		assert_int(int(nerve.cost[k])).is_equal(int(NERVE_COST[k]))
		assert_int(int(nerve.cost[k])).is_equal((k + 1) * (k + 1) * 150)
	# under every talent but the Stakes (the gold-and-challenge one)
	for td: TalentDef in Registry.talents.values():
		if td.id == "nerve":
			continue
		if td.id == "spite":
			assert_int(td.first_price()).is_less(nerve.first_price())
		else:
			assert_int(td.first_price()).override_failure_message(td.id).is_greater(nerve.first_price())


func test_the_board_lists_nerve_second() -> void:
	var list := Registry.talents_list()
	var ids: Array = []
	for td: TalentDef in list:
		ids.append(td.id)
	assert_array(ids).is_equal(BOARD)
	for k in range(list.size()):
		assert_int((list[k] as TalentDef).order).override_failure_message((list[k] as TalentDef).id).is_equal(k + 1)


# ---------------------------------------------------------------- 4. an older save's Nerve ranks

func test_an_older_saves_nerve_ranks_stay_and_the_overpaid_gold_comes_back_once() -> void:
	Save.data["gold"] = 100
	Save.data["talents"] = {"nerve": {"picks": [1, 0, 1]}, "grit": {"picks": [0]}}
	Save.data["talent_spent"] = 500 + 900 + 1500 + 450
	var back: int = Save._migrate_nerve()
	# counted at pass 88's prices against the new ones: (500-150) + (900-600) + (1500-1350)
	assert_int(back).is_equal(350 + 300 + 150)
	assert_int(Save.gold()).is_equal(100 + 800)
	assert_int(Save.talent_spent()).is_equal(500 + 900 + 1500 + 450 - 800)
	# the ranks stay, in the forms they were bought
	assert_array(Save.talent_picks("nerve")).is_equal([1, 0, 1])
	assert_int(Save.talent_rank("grit")).is_equal(1)
	assert_str(str(Save.nerve_note().get("kind", ""))).is_equal("nerve_refund")
	assert_array(HS.nerve_words(Save.nerve_note())).is_equal(["NERVE COSTS LESS NOW", "+800 GOLD BACK FOR 3 RANKS",
		"SECOND WIND: REVIVE HEALTH"])
	# once
	assert_int(Save._migrate_nerve()).is_equal(0)
	assert_int(Save.gold()).is_equal(900)
	Save.clear_nerve_note()
	assert_bool(Save.nerve_note().is_empty()).is_true()


func test_a_refund_never_passes_what_the_board_cost() -> void:
	# a board a tool set (nothing spent): the ranks stay, nothing comes back, Second Wind's change is still said
	Save.data["gold"] = 0
	Save.data["talents"] = {"nerve": {"picks": [1, 1]}}
	Save.data["talent_spent"] = 0
	assert_int(Save._migrate_nerve()).is_equal(0)
	assert_int(Save.gold()).is_equal(0)
	assert_array(HS.nerve_words(Save.nerve_note())).is_equal(["SECOND WIND: REVIVE HEALTH"])
	# ranks 4-6 cost more now than at pass 88's prices: they bring nothing back, never a negative
	Save.data = Save._default()
	Save.data["talents"] = {"nerve": {"picks": [0, 0, 0, 0, 0, 0]}}
	Save.data["talent_spent"] = 100000
	assert_int(Save._migrate_nerve()).is_equal(350 + 300 + 150)
	assert_array(HS.nerve_words(Save.nerve_note())).is_equal(["NERVE COSTS LESS NOW", "+800 GOLD BACK FOR 6 RANKS"])


func test_a_new_save_and_a_nerve_rank_bought_now_are_never_paid_back() -> void:
	assert_int(Save._migrate_nerve()).is_equal(0)
	assert_bool(Save.once(Save.NERVE_ONCE)).is_true()
	assert_bool(Save.nerve_note().is_empty()).is_true()
	# a save wiped since its load: buying a Nerve rank marks it, so the next load keeps the rank and its price
	Save.data = Save._default()
	Save.add_gold(100000)
	assert_bool(Save.buy_talent(_nerve(), 1)).is_true()
	assert_int(Save.talent_spent()).is_equal(150)
	assert_bool(Save.once(Save.NERVE_ONCE)).is_true()
	assert_int(Save._migrate_nerve()).is_equal(0)
	assert_int(Save.talent_rank("nerve")).is_equal(1)
