extends GdUnitTestSuite

## Pass 117, lane WATCHDPS (Garry: "Add Individual Weapon Real DPS to the local Dashboard, and make a version of that for
## the Watch tool ... For each item that was affected by other items we list those as icons as well (with a highlight
## hint to show what they did)"): the Watch's Weapon DPS tab's pure parts: an evolution folded into its weapon's family,
## the lines (weapon families, a big other source its own line, the small ones "__other"), the rolling mean, the marks
## under the chart (weapons, the items that shape a weapon now, Totem gifts of a weapon stat, the Stranger, power-ups
## but the small ones, the War Drum), a source's pick times, the icons' lanes; WatchData keeps every event; the panel
## builds the tab and switches it.

const WDPS := preload("res://tools/watch/WatchWeaponDps.gd")
const DATA := preload("res://tools/watch/WatchData.gd")
const PANEL := preload("res://tools/watch/WatchPanel.gd")


func test_family_follows_evolutions() -> void:
	var fam := {"golden_revolver": "revolver", "platinum": "golden_revolver"}
	assert_str(WDPS.family_of("golden_revolver", fam)).is_equal("revolver")
	assert_str(WDPS.family_of("platinum", fam)).is_equal("revolver")
	assert_str(WDPS.family_of("boomstick", fam)).is_equal("boomstick")
	# a loop never hangs
	assert_str(WDPS.family_of("a", {"a": "b", "b": "a"})).is_not_empty()


func test_fold_sums_a_family_and_splits_the_others() -> void:
	var rows: Array = [
		{"revolver": 10.0, "boomstick": 5.0, "powder_keg": 30.0, "thorns": 1.0},
		{"golden_revolver": 20.0, "boomstick": 5.0},
		{},
		{"golden_revolver": 40.0, "blast": 0.5}]
	var f: Dictionary = WDPS.fold(rows, ["golden_revolver", "boomstick", "dynamite"], {"golden_revolver": "revolver"})
	assert_array(f["fams"]).is_equal(["revolver", "boomstick", "dynamite"])
	assert_array(f["own"]).is_equal(["powder_keg"])
	assert_array(f["folded"]).is_equal(["thorns", "blast"])
	assert_array(f["keys"]).is_equal(["revolver", "boomstick", "dynamite", "powder_keg", "__other"])
	var rev: PackedFloat32Array = f["raw"]["revolver"]
	assert_array(Array(rev)).is_equal([10.0, 20.0, 0.0, 40.0])
	assert_float(float(f["totals"]["revolver"])).is_equal(70.0)
	assert_float(float(f["totals"]["dynamite"])).is_equal(0.0)
	assert_float(float(f["totals"]["__other"])).is_equal(1.5)
	assert_float(float(f["total"])).is_equal(111.5)
	assert_bool((f["members"]["revolver"] as Array).has("revolver")).is_true()


func test_roll_is_the_dashboards_rolling_mean() -> void:
	var r := WDPS.roll(PackedFloat32Array([10.0, 20.0, 30.0, 0.0]), 2)
	assert_array(Array(r)).is_equal([10.0, 15.0, 25.0, 15.0])
	assert_int(WDPS.roll(PackedFloat32Array(), 10).size()).is_equal(0)


func test_marks_by_row() -> void:
	var events: Array = [
		{"t": 0.0, "kind": "weapon", "id": "revolver", "level": 1, "new": true, "via": "starter"},
		{"t": 20.0, "kind": "passive", "id": "whetstone", "level": 1, "via": "card", "est_before": 30.0, "est_after": 36.0},
		{"t": 25.0, "kind": "passive", "id": "boots", "level": 1, "via": "card"},
		{"t": 30.0, "kind": "mutation", "id": "fan", "weapon": "revolver", "via": "path"},
		{"t": 40.0, "kind": "pickup", "id": "rage", "small": false, "effect": "buff"},
		{"t": 41.0, "kind": "pickup", "id": "gem", "small": true},
		{"t": 50.0, "kind": "structure", "id": "war_drum"},
		{"t": 51.0, "kind": "structure", "id": "shop", "effect": "shop"},
		{"t": 60.0, "kind": "totem", "id": "raven", "stat": "might", "value": 0.1},
		{"t": 61.0, "kind": "totem", "id": "bear", "stat": "max_hp", "value": 10.0},
		{"t": 70.0, "kind": "stranger", "id": "boomstick", "type": "weapon", "level": 2, "cost": 0.2},
		{"t": 80.0, "kind": "evolution", "id": "golden_revolver", "from": "revolver"},
		{"t": 90.0, "kind": "perk", "id": "quickdraw"}]
	var by_sid: Dictionary = WDPS.sources_by_sid({
		"revolver": [{"s": "passive:whetstone", "n": "Whetstone", "k": "passive", "w": "+10% attack damage", "i": ""},
			{"s": "mutation:fan", "n": "Fan", "k": "mutation", "w": "+1 projectile", "i": ""},
			{"s": "totem:raven", "n": "Raven", "k": "totem", "w": "+10% attack damage", "i": ""}],
		"boomstick": [{"s": "passive:whetstone", "n": "Whetstone", "k": "passive", "w": "+10% attack damage", "i": ""}]})
	var names := {"revolver": "Revolver", "whetstone": "Whetstone", "golden_revolver": "Golden Revolver", "boomstick": "Boomstick",
		"rage": "Rage", "war_drum": "War Drum", "raven": "Raven", "fan": "Fan", "stat:might": "attack damage"}
	var marks: Array = WDPS.dps_marks(events, by_sid, names)
	var kinds: Array = []
	for m in marks:
		kinds.append("%s:%s:%s" % [m["row"], m["kind"], m["key"]])
	# boots and the perk shape no weapon; the small gem, the shop and a Totem gift of max HP are no mark
	assert_array(kinds).is_equal(["weapons:weapon:revolver", "items:passive:whetstone", "weapons:mutation:fan", "boosts:pickup:rage",
		"boosts:structure:war_drum", "items:totem:raven", "items:weapon:boomstick", "weapons:evolution:golden_revolver"])
	var whet: Array = marks[1]["lines"]
	assert_str(str(whet[0])).is_equal("0:20 · Whetstone (passive item) (a level-up card)")
	assert_str(str(whet[1])).contains("30 → 36")
	# the same to every weapon it shapes: one line
	assert_str(str(whet[2])).is_equal("every weapon held now: +10% attack damage")
	assert_str(str(marks[0]["lines"][0])).contains("joined at level 1 (the starting weapon)")
	assert_str(str(marks[5]["lines"][1])).is_equal("attack damage +0.1")
	assert_str(str(marks[6]["lines"][1])).is_equal("for 20% of max HP")
	assert_str(str(marks[7]["lines"][0])).contains("Revolver evolved into Golden Revolver")


func test_source_times() -> void:
	var events: Array = [{"t": 5.0, "kind": "passive", "id": "whetstone"}, {"t": 9.0, "kind": "passive", "id": "whetstone"},
		{"t": 12.0, "kind": "perk", "id": "quickdraw"}, {"t": 20.0, "kind": "stranger", "id": "x"}, {"t": 21.0, "kind": "totem", "id": "raven"}]
	assert_array(WDPS.source_times(events, "passive:whetstone")).is_equal([5.0, 9.0])
	assert_array(WDPS.source_times(events, "perk:quickdraw")).is_equal([12.0])
	assert_array(WDPS.source_times(events, "stranger:3")).is_equal([20.0])
	assert_array(WDPS.source_times(events, "totem:raven")).is_equal([21.0])
	assert_array(WDPS.source_times(events, "talent:grit:0")).is_empty()


func test_lanes_keep_icons_apart() -> void:
	# two close icons share no lane; a third far right goes back to lane 0; a crowd past the lanes reuses the freest
	assert_array(WDPS.lanes([10.0, 15.0, 60.0], 16.0, 2)).is_equal([0, 1, 0])
	assert_array(WDPS.lanes([10.0, 12.0, 14.0], 16.0, 2)).is_equal([0, 1, 0])


func test_data_keeps_every_event() -> void:
	var d = DATA.new()
	var ev: Array = [{"t": 1.0, "kind": "pickup", "id": "rage"}, {"t": 2.0, "kind": "weapon", "id": "revolver"}, "junk"]
	d.read_events(ev)
	assert_int(d.events.size()).is_equal(2)
	# the same dictionary: an est_after the recorder adds later shows
	(ev[1] as Dictionary)["est_after"] = 12.0
	assert_float(float(d.events[1]["est_after"])).is_equal(12.0)


func test_view_draws_a_model() -> void:
	var v = auto_free(WDPS.new())
	v.size = Vector2(800, 330)
	add_child(v)
	var f: Dictionary = WDPS.fold([{"revolver": 10.0}, {"revolver": 30.0}], ["revolver"], {})
	v.set_model({"t": PackedFloat32Array([1.0, 2.0]), "keys": f["keys"], "raw": f["raw"], "total": f["total"],
		"info": {"revolver": {"name": "Revolver", "sub": "Lv 1", "color": Color.ORANGE, "weapon": true, "icon": null,
			"sources": [{"icon": null, "name": "Whetstone", "lines": ["Whetstone", "passive item: +10%"], "times": [1.0]}]}},
		"marks": [{"t": 1.0, "row": "weapons", "key": "revolver", "kind": "weapon", "label": "Revolver", "lines": ["0:01 · Revolver"]}],
		"x0": 0.0, "x1": 180.0, "base_marks": []})
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(v.chart.series.size()).is_equal(1)
	# a mark, a row and a shaped-by icon drawn; the pointer on the source lights its time on the chart
	assert_vector(v.point_for("m0")).is_not_equal(Vector2(-1, -1))
	assert_vector(v.point_for("r0")).is_not_equal(Vector2(-1, -1))
	var p: Vector2 = v.point_for("s0")
	assert_vector(p).is_not_equal(Vector2(-1, -1))
	v.set_hover(p)
	assert_int(v.chart.marks.size()).is_equal(1)
	v.set_hover(Vector2(-1, -1))
	assert_int(v.chart.marks.size()).is_equal(0)
	# a click on the row hides its line
	v.toggle_line("revolver")
	assert_int(v.chart.series.size()).is_equal(0)
	v.set_window(30)
	assert_str(v.chart.title).contains("30 s")
