## Pass 115, lane META. The game's name on screen (Garry: "Rename the game to Outlaw Survivors, but only in the game
## itself ... we just write 'Outlaw' with big fat text and the 'Drag Dodge Survive' is replaced with simply 'Survivors'"):
## the title's OUTLAW / SURVIVORS, the Settings version line. And Nerve (Garry: "Change the Revive to only affect the
## amount of HP Player gets when they revive ... by default ... 40% of their health ... all at max ... 100% ... skips and
## this new revive thing are not valuable at all, rebalance their ordering in the view as well as their prices"): a
## revive stands him up at 40%, Second Wind adds revive health and no revive; the Phoenix Feather keeps 50%.
## Pass 129: the Upgrade board (and its Nerve talent) is gone. The 40% is the sheet's own default now
## (StatSheet.PLAYER_DEFAULTS), and Second Wind is a Trail upgrade (`second_wind`: revive health, read from
## content/trail/trail.json, never pinned here); Nerve's prices, its place on the board and its refund left with the board.
extends GdUnitTestSuite

const Title := preload("res://ui/TitleScreen.gd")
const Stage := preload("res://ui/TitleStage.gd")
const SettingsScreenScript := preload("res://ui/SettingsScreen.gd")

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"preview": Settings.preview_locked_heroes, "inset": Settings.top_inset,
		"data": Save.data.duplicate(true)}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()
	Trail.refresh()


## Every Second Wind node of the game's Trail bought (the save's `trail`), and what they add to revive health together.
func _buy_second_wind() -> float:
	var ids: Array = []
	var sum := 0.0
	for nd: Dictionary in Trail.nodes():
		var g: Dictionary = nd["gives"]
		if str(g.get("type", "")) == "upgrade" and str(g.get("upgrade", "")) == "second_wind":
			ids.append(str(nd["id"]))
			sum += float(g["value"])
	Save.data["trail"] = {"bought": ids, "spent": 0, "had": []}
	Trail.refresh()
	return sum


func after_test() -> void:
	Run.arena = false
	Run.end()
	Stage.forget()
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Settings.top_inset = int(_keep["inset"])
	Save.data = _keep["data"]
	Save._dirty = false
	Trail.refresh()


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


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
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	var logo: WText = t.find_child("Logo", true, false)
	var tag = t.find_child("Tagline", true, false)
	assert_object(logo).is_not_null()
	assert_object(tag).is_not_null()
	assert_str(logo.text).is_equal("OUTLAW")
	assert_str(tag.text()).is_equal("SURVIVORS")
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
	# pass 129: the sheet's own default (the Nerve talent's base_stats until the board went)
	assert_float(float(StatSheet.PLAYER_DEFAULTS["revive_hp"])).is_equal_approx(0.4, 0.0001)
	# a plain add of revive health reads as a step (a Trail node's line, the pause screen's sources)
	assert_str(TextGen.describe_effect(Effect.make("revive_hp", "add", 0.1, "player"))).is_equal("+10% health on revive")
	_start()
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(0.4, 0.0001)
	var p := _felled()
	p.revive()
	assert_float(p.hp).is_equal_approx(p.max_hp * 0.4, 0.001)


func test_the_trails_second_wind_adds_revive_health_and_no_extra_revive() -> void:
	var more := _buy_second_wind()
	assert_float(more).is_greater(0.0)
	_start()
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(0.4 + more, 0.0001)
	# Second Wind gives no revives: Down! offers its one chance a run, as without it (Game._open_revive's count)
	assert_float(Run.player_sheet.get_stat("revives", 0.0)).is_equal(0.0)
	var chances: int = 1 + Run.player_sheet.get_int("revives", 0) - Run.revives_used
	assert_int(chances).is_equal(1)
	var p := _felled()
	p.revive()
	assert_float(p.hp).is_equal_approx(p.max_hp * minf(0.4 + more, 1.0), 0.001)


func test_the_phoenix_feather_keeps_its_half_health() -> void:
	_start()
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_true()
	# the feather's own floor; the plain revive health stays the default 40%
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(0.4, 0.0001)
	var p := _felled()
	assert_float(p.revive_share(true)).is_equal_approx(0.5, 0.0001)
	assert_float(p.revive_share(false)).is_equal_approx(0.4, 0.0001)
	Run.use_phoenix()
	p.revive(true)
	assert_float(p.hp).is_equal_approx(p.max_hp * 0.5, 0.001)
	# Second Wind still raises a Phoenix revive once it passes the feather's half: the larger of the two
	Run.end()
	var more := _buy_second_wind()
	_start()
	Run.add_or_level_passive("phoenix_feather")
	var q := _felled()
	assert_float(q.revive_share(true)).is_equal_approx(clampf(maxf(0.4 + more, 0.5), 0.0, 1.0), 0.0001)
