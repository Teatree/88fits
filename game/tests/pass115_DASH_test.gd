## Pass 115, lane DASH (Garry: "Hero Level ... Hero Items Count as well", "Individual Weapon Real DPS ... For each item that
## was affected by other items we list those as icons as well", "Just show Current HP instead with bars ... per 5
## seconds", "There should be info about what level of Mirror Upgrade Player was when they played", "I need to know
## Player Mirror Upgrades while watching the replay"): the run record's schema 5 (core/systems/RunAnalytics.gd): a row's
## `hp_min` (the lowest health inside its second, only when below the row's hp), the header's `board` (the whole Upgrade
## board: every talent, its ranks' forms, what they cost), `weapon_sources` (what shaped each held weapon, in words, with
## its icon), `weapon_family` (an evolution's base weapon), `icons` (every id's icon file) and the index row's board
## numbers; RunAnalytics.board reading another save's talents (the replay viewer's). The dashboard's cards themselves are
## checked from the lane with Node and a browser (tools/level_editor/selftest_DASH115.py, tools/dl/p115/DASH/).
extends GdUnitTestSuite

const FAKE_GAME := """extends Node
var enemies = null
var director = null
var player = null
"""

const FAKE_PLAYER := """extends Node
var hp := 80.0
var max_hp := 100.0
var shield_pts := 0.0
var invuln := 0.0
var damage_log: Array = []
"""

var _stamps: Array = []


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	RunAnalytics.I = null
	_stamps = []


func after_test() -> void:
	RunAnalytics.I = null
	for s in _stamps:
		DirAccess.remove_absolute("user://analytics/runs/%s.json" % s)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A game with only a hero (80 of 100): the rows' crowd parts stay out.
func _fake_game() -> Node:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var p := Node.new()
	p.set_script(_script(FAKE_PLAYER))
	g.add_child(p)
	g.player = p
	return g


func _recorder(g: Node) -> RunAnalytics:
	var ra := RunAnalytics.new()
	ra.mirror = false
	g.add_child(ra)
	ra.begin(g)
	var stamp := "test-p115-%d" % Time.get_ticks_usec()
	ra.header["stamp"] = stamp
	_stamps.append(stamp)
	return ra


func test_schema_5() -> void:
	var ra := _recorder(_fake_game())
	assert_int(RunAnalytics.SCHEMA).is_equal(5)
	assert_int(int(ra.header["schema"])).is_equal(5)
	ra.finish()


func test_a_row_keeps_the_lowest_health_inside_its_second() -> void:
	var g := _fake_game()
	var ra := _recorder(g)
	var p: Node = g.player
	ra.tick(0.3)
	# a hit takes him to 30, a heal brings him back to 70 before the row: the row says 70 and the dip to 30
	p.hp = 30.0
	ra.took({"by": "Goblin", "id": "goblin", "kind": "melee"}, 50.0, 50.0, 0.0, "")
	p.hp = 70.0
	ra.tick(0.8)
	var row: Dictionary = ra.samples[0]
	assert_float(float(row["hp"])).is_equal(70.0)
	assert_float(float(row["hp_min"])).is_equal(30.0)
	# a second with no dip below the row's hp has none
	ra.tick(1.0)
	assert_bool((ra.samples[1] as Dictionary).has("hp_min")).is_false()
	# a frame's reading counts too (a dip no hit reported: the Stranger's cut, a fall), and never below 0
	p.hp = -5.0
	ra.tick(0.5)
	p.hp = 60.0
	ra.tick(0.5)
	assert_float(float((ra.samples[2] as Dictionary)["hp_min"])).is_equal(0.0)
	ra.finish()


func test_the_board_names_every_talent_its_ranks_forms_and_price() -> void:
	var save_talents := {"grit": {"picks": [0, 1, 0]}, "drive": {"form": 1, "rank": 2}, "nobody": {"picks": [1]}}
	var b := RunAnalytics.board(save_talents, 1234)
	var rows: Array = b["talents"]
	var list: Array = Registry.talents_list()
	assert_int(rows.size()).is_equal(list.size())
	var most := 0
	for i in list.size():
		var d: TalentDef = list[i]
		var r: Dictionary = rows[i]
		# in the board's order, each with its most ranks and both forms' names and lines
		assert_str(str(r["id"])).is_equal(d.id)
		assert_str(str(r["name"])).is_equal(d.display_name)
		assert_int(int(r["max"])).is_equal(d.max_rank())
		assert_array(r["forms"]).is_equal([d.form_name(0), d.form_name(1)])
		assert_array(r["texts"]).is_equal([d.form_text(0), d.form_text(1)])
		most += d.max_rank()
	var by := {}
	for r in rows:
		by[str(r["id"])] = r
	assert_array(by["grit"]["picks"]).is_equal([0, 1, 0])
	# an old {form, rank} save reads as that form rank times (Save.talent_picks' rule)
	assert_array(by["drive"]["picks"]).is_equal([1, 1])
	var gd: TalentDef = Registry.talent("grit")
	assert_int(int(by["grit"]["gold"])).is_equal(gd.cost_of_rank(0) + gd.cost_of_rank(1) + gd.cost_of_rank(2))
	assert_int(int(b["ranks"])).is_equal(5)
	assert_int(int(b["max"])).is_equal(most)
	var gold := 0
	for r in rows:
		gold += int(r["gold"])
	assert_int(int(b["gold"])).is_equal(gold)
	assert_int(int(b["spent"])).is_equal(1234)
	# an empty save: every talent at 0
	var none := RunAnalytics.board({})
	assert_int(int(none["ranks"])).is_equal(0)
	assert_int(int(none["gold"])).is_equal(0)
	# the recorder's header carries this phone's own board
	var ra := _recorder(_fake_game())
	assert_bool(ra.header["board"] is Dictionary).is_true()
	assert_int((ra.header["board"]["talents"] as Array).size()).is_equal(list.size())
	assert_int(int(ra.header["board"]["spent"])).is_equal(Save.talent_spent())
	ra.finish()


func test_weapon_sources_name_what_changed_each_weapon() -> void:
	var w: WeaponInstance = Run.add_weapon(Registry.weapon("revolver"), 1)
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("haste")
	var list := RunAnalytics.weapon_sources_of(w, Run.player_sheet)
	var by := {}
	for x in list:
		assert_dict(x).contains_keys(["s", "n", "k", "w", "i"])
		assert_str(str(x["w"])).is_not_empty()
		by[str(x["s"])] = x
	# The Sun: +10% attack damage on every weapon; The Tower: -8% cooldown
	assert_bool(by.has("passive:brawn")).is_true()
	assert_str(str(by["passive:brawn"]["w"])).contains(TextGen.stat_name("might"))
	assert_str(str(by["passive:brawn"]["k"])).is_equal("passive")
	assert_bool(by.has("passive:haste")).is_true()
	assert_str(str(by["passive:haste"]["w"])).contains(TextGen.stat_name("cooldown"))
	# its icon is a file of the game's (a res:// path without the prefix)
	var ip := str(by["passive:brawn"]["i"])
	assert_bool(ip.begins_with("content/")).is_true()
	assert_bool(ResourceLoader.exists("res://" + ip)).is_true()
	# a stat no weapon reads (move speed alone) shapes no weapon: never a source
	for x in list:
		assert_str(str(x["w"])).not_contains(TextGen.stat_name("move_speed"))
	# its own level is the weapon itself: never a source
	assert_bool(by.has("level")).is_false()


func test_the_end_header_carries_sources_families_icons_and_the_index_its_board() -> void:
	var g := _fake_game()
	var ra := _recorder(g)
	Run.add_weapon(Registry.weapon("revolver"), 1)
	Run.add_or_level_passive("brawn")
	Run.add_damage(Run.weapons[0].def.id, 10.0)
	Run.damage_by_weapon["golden_revolver"] = 5.0
	ra.tick(1.0)
	ra.finish()
	var h: Dictionary = ra.header
	var wid: String = Run.weapons[0].def.id
	assert_bool((h["weapon_sources"] as Dictionary).has(wid)).is_true()
	if Registry.weapon("golden_revolver") != null:
		assert_str(str(h["weapon_family"].get("golden_revolver", ""))).is_equal("revolver")
	assert_bool((h["weapon_family"] as Dictionary).has(wid)).is_false()
	var icons: Dictionary = h["icons"]
	assert_bool(icons.has(wid)).is_true()
	assert_bool(icons.has("brawn")).is_true()
	assert_bool(icons.has("hero:astro")).is_true()
	for k in icons:
		assert_bool(ResourceLoader.exists("res://" + str(icons[k]))).override_failure_message(str(k) + " " + str(icons[k])).is_true()
	# a talent's form icon by "talent:<id>:<form>" where the form has one
	for t in Registry.talents_list():
		var td: TalentDef = t
		if td.form_icon(0) != null and td.form_icon(0).resource_path.begins_with("res://"):
			assert_bool(icons.has("talent:%s:0" % td.id)).is_true()
	# the index row: the board's most and its gold beside the ranks, the big blocks left out
	var row := ra.index_row()
	assert_int(int(row["board_max"])).is_equal(int(h["board"]["max"]))
	assert_int(int(row["board_gold"])).is_equal(int(h["board"]["gold"]))
	for k in ["board", "weapon_sources", "weapon_family", "icons"]:
		assert_bool(row.has(k)).override_failure_message("index row has " + k).is_false()
		for rk in row:
			assert_bool(str(rk).begins_with(k + ".")).override_failure_message("index row has " + str(rk)).is_false()
	Run.damage_by_weapon.erase("golden_revolver")


func test_the_replay_viewer_shows_the_board() -> void:
	var src := FileAccess.get_file_as_string("res://replay/ReplayViewer.gd")
	assert_str(src).contains("RunAnalytics.board(")
	assert_str(src).contains("KEY_B")
	assert_str(src).contains("plan.get(\"look\"")
