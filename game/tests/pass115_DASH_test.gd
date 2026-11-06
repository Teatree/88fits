## Pass 115, lane DASH (Garry: "Hero Level ... Hero Items Count as well", "Individual Weapon Real DPS ... For each item that
## was affected by other items we list those as icons as well", "Just show Current HP instead with bars ... per 5
## seconds", "There should be info about what level of Mirror Upgrade Player was when they played", "I need to know
## Player Mirror Upgrades while watching the replay"): the run record's schema 5 (core/systems/RunAnalytics.gd): a row's
## `hp_min` (the lowest health inside its second, only when below the row's hp), `weapon_sources` (what shaped each held
## weapon, in words, with its icon), `weapon_family` (an evolution's base weapon), `icons` (every id's icon file).
## Pass 129 (schema 6): the header's `board` (the whole Upgrade board) is gone with the board; the header's `trail`
## (RunAnalytics.trail_block: the Trail's level, nodes, cost, upgrade totals with their words), the index row's trail
## numbers, and trail_block reading another save (the replay viewer's) take its place. The dashboard's cards themselves are
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
	assert_int(RunAnalytics.SCHEMA).is_equal(6)   # pass 129: schema 6 (the Upgrade board gone), re-pinned on purpose
	assert_int(int(ra.header["schema"])).is_equal(6)   # pass 129: schema 6 (the Upgrade board gone), re-pinned on purpose
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


func test_the_end_header_carries_sources_families_icons_and_the_index_its_trail() -> void:
	# two upgrade nodes of the game's Trail bought: the record names them and their icons
	Trail.load_from()
	var ups: Array = []
	for nd: Dictionary in Trail.nodes():
		if ups.size() < 2 and str((nd["gives"] as Dictionary).get("type", "")) == "upgrade" and str(nd["kind"]) == "node":
			ups.append(str(nd["id"]))
	Save.data["trail"] = {"bought": ups, "spent": 80, "had": []}
	Trail.refresh()
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
	# schema 6: no Upgrade board; the Trail's block whole, a bought upgrade type's icon by "trail:<type>"
	assert_int(int(h["schema"])).is_equal(6)
	for gone: String in ["board", "talents", "talent_forms"]:
		assert_bool(h.has(gone)).override_failure_message("the header still has " + gone).is_false()
	var tr: Dictionary = h["trail"]
	assert_int((tr["bought"] as Array).size()).is_equal(2)
	assert_int(int(tr["spent"])).is_equal(80)
	assert_int(int(tr["levels"])).is_equal(Trail.levels())
	assert_int(int(tr["nodes"])).is_equal(Trail.nodes().size())
	assert_bool((tr["upgrades"] as Dictionary).is_empty()).is_false()
	for type: Variant in (tr["upgrades"] as Dictionary).keys():
		var info: Dictionary = (tr["types"] as Dictionary)[type]
		assert_str(str(info["name"])).is_equal(str(Trail.upgrade(str(type))["name"]))
		assert_str(str(info["kind"])).is_equal(str(Trail.upgrade(str(type))["kind"]))
		if Trail.icon(str(type)) != null:
			assert_bool(icons.has("trail:" + str(type))).override_failure_message("no icon for trail:" + str(type)).is_true()
	# the index row: the Trail's level, nodes and cost, the big blocks left out
	var row := ra.index_row()
	assert_int(int(row["trail_level"])).is_equal(int(tr["level"]))
	assert_int(int(row["trail_bought"])).is_equal(2)
	assert_int(int(row["trail_spent"])).is_equal(80)
	for gone: String in ["talents", "board_max", "board_gold"]:
		assert_bool(row.has(gone)).override_failure_message("index row has " + gone).is_false()
	for k in ["trail", "weapon_sources", "weapon_family", "icons"]:
		assert_bool(row.has(k)).override_failure_message("index row has " + k).is_false()
		for rk in row:
			assert_bool(str(rk).begins_with(k + ".")).override_failure_message("index row has " + str(rk)).is_false()
	Run.damage_by_weapon.erase("golden_revolver")
	Save.data["trail"] = {"bought": [], "spent": 0, "had": []}
	Trail.refresh()


func test_the_trail_block_reads_another_save_and_leaves_this_one_alone() -> void:
	Trail.load_from()
	Save.data["trail"] = {"bought": [], "spent": 0, "had": []}
	Trail.refresh()
	var mine := Save.data
	var first := str(Trail.nodes()[0]["id"])
	var other := {"gold": 5, "trail": {"bought": [first], "spent": 10, "had": []}}
	var b := RunAnalytics.trail_block(other)
	assert_array(b["bought"]).is_equal([first])
	assert_int(int(b["level"])).is_equal(1)
	assert_int(int(b["spent"])).is_equal(10)
	assert_int(int(b["paid"])).is_equal(1)
	# this save is as it was, and the Trail answers for it again
	assert_bool(Save.data == mine).is_true()
	assert_int(Trail.level()).is_equal(0)
	assert_array(RunAnalytics.trail_block()["bought"]).is_empty()


func test_the_replay_viewer_shows_the_trail() -> void:
	var src := FileAccess.get_file_as_string("res://replay/ReplayViewer.gd")
	assert_str(src).contains("RunAnalytics.trail_block(")
	var words: String = load("res://replay/ReplayViewer.gd").trail_text({"level": 3, "levels": 70, "nodes": 100, "bought": ["a", "b", "c"],
		"spent": 1234, "upgrades": {"might": 0.06}, "types": {"might": {"name": "Might", "kind": "percent", "text": "Attack damage"}}}, true)
	assert_str(words).contains("level 3 of 70")
	assert_str(words).contains("3 of 100 nodes")
	assert_str(words).contains("1,234 gold")
	assert_str(words).contains("Might")
	assert_str(words).contains("+6%")
	assert_str(src).contains("KEY_B")
	assert_str(src).contains("plan.get(\"look\"")
