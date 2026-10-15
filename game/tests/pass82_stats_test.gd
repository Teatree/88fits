extends GdUnitTestSuite

## Pass 82, lane STATS (Garry: "In the Sim add a chart for Chests Picked up, Power-ups and Totems though a run"): what
## counts as a chest, a power-up and a totem (game/tools/sim_run.gd pickup_kind, the GDScript twin of
## tools/level_editor/sim_model.js pickupKind and tools/analytics_csv.py pickup_kind) and the run sim's counts so far at
## each row (sim_run.gd series(): `chests`, `powerups`, `totems`), both pinned to the fixture the page and the Python
## are checked against (tools/level_editor/testdata/stats82_pickups.json, selftest_STATS82); and the pickups the game
## records: a power-up is a pickup without `params.small` (Game.apply_pickup's own count).

const SIM := preload("res://tools/sim_run.gd")
const FIXTURE := preload("res://tools/series_fixture.gd")


## The fixture ({record, kinds, expect}), or {} off the repo.
func _fixture() -> Dictionary:
	var path := FIXTURE.fixture_dir().path_join("stats82_pickups.json")
	if not FileAccess.file_exists(path):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		return {}
	return j.data


func _ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out


func test_pickup_kind_is_the_fixtures() -> void:
	var fx := _fixture()
	if fx.is_empty():
		push_warning("pass82: the fixture is not beside the project: skipped")
		return
	var events: Array = fx["record"]["events"]
	var kinds: Array = fx["kinds"]
	assert_int(events.size()).is_equal(kinds.size())
	for i in range(events.size()):
		assert_str(SIM.pickup_kind(events[i])).override_failure_message("event %d %s" % [i, str(events[i])]).is_equal(str(kinds[i]))


func test_pickup_kind_rule() -> void:
	assert_str(SIM.pickup_kind({"kind": "chest", "skip": true})).is_equal("chests")
	assert_str(SIM.pickup_kind({"kind": "chest", "boss": true})).is_equal("chests")
	assert_str(SIM.pickup_kind({"kind": "pickup", "id": "heart", "small": false})).is_equal("powerups")
	assert_str(SIM.pickup_kind({"kind": "pickup", "id": "nuke"})).is_equal("powerups")
	assert_str(SIM.pickup_kind({"kind": "pickup", "id": "cake_slice", "small": true})).is_equal("")
	assert_str(SIM.pickup_kind({"kind": "totem", "id": "wolf"})).is_equal("totems")
	assert_str(SIM.pickup_kind({"kind": "structure", "id": "totem_pole", "effect": "totem"})).is_equal("")
	assert_str(SIM.pickup_kind({"kind": "totem_offer", "id": "wolf"})).is_equal("")
	assert_str(SIM.pickup_kind(42)).is_equal("")


func test_series_counts_are_the_fixtures() -> void:
	var fx := _fixture()
	if fx.is_empty():
		push_warning("pass82: the fixture is not beside the project: skipped")
		return
	var rec: Dictionary = fx["record"]
	var out: Dictionary = SIM.series(rec["samples"], rec["events"], [], {}, {})
	var want: Dictionary = fx["expect"]
	for k in SIM.PICKUP_KEYS:
		assert_array(_ints(out[k])).override_failure_message("%s: %s" % [k, str(out[k])]).is_equal(_ints(want[k]))
		assert_int((out[k] as Array).size()).is_equal((out["t"] as Array).size())
	var tot: Dictionary = SIM.pickup_totals(rec["events"])
	for k in SIM.PICKUP_KEYS:
		assert_int(int(tot[k])).is_equal(int(want["totals"][k]))


func test_times_are_sorted_and_counted_like_the_deaths() -> void:
	var ev := [{"t": 9.0, "kind": "chest"}, {"t": 2.0, "kind": "chest"}, {"t": 5.0, "kind": "pickup", "small": 0}]
	var times: Dictionary = SIM.pickup_times(ev)
	assert_array(times["chests"]).is_equal([2.0, 9.0])
	var rows := [{"t": 1.0}, {"t": 2.0}, {"t": 4.5}, {"t": 9.0}, {"t": 10.0}]
	var out: Dictionary = SIM.series(rows, ev, [], {}, {})
	assert_array(_ints(out["chests"])).is_equal([0, 1, 1, 2, 2])
	assert_array(_ints(out["powerups"])).is_equal([0, 0, 0, 1, 1])
	assert_array(_ints(out["totems"])).is_equal([0, 0, 0, 0, 0])


## The event Game.apply_pickup records for each pickup in the content counts as a power-up exactly when the pickup is
## not one of the small things underfoot (params.small), as the game's own `pickups` total does.
func test_every_pickup_in_the_content() -> void:
	var powerups := 0
	var small := 0
	for id in Registry.pickups.keys():
		var def: PickupDef = Registry.pickups[id]
		var is_small := bool(def.params.get("small", false))
		var ev := {"t": 1.0, "kind": "pickup", "id": def.id, "small": is_small, "effect": def.effect_kind}
		assert_str(SIM.pickup_kind(ev)).override_failure_message(def.id).is_equal("" if is_small else "powerups")
		if is_small:
			small += 1
		else:
			powerups += 1
	assert_int(powerups).is_greater(0)
	assert_int(small).is_greater(0)
