## Pass 122, lane S3APPLY (Garry, 2026-11-03: "Creating coloured variants for enemies that don't have a white / or yellow
## (or any other coloured) version. You'd need to specifically [pick] ones that actually look visible on red"): the two
## S3LOOKS lanes' row-to-look mapping written into the map's stage-3 rows (the roster's s3* rows and the Blood Moon's
## boss-fight rows bf3-*), their `variant` key only. The rule pinned here, read from the map file: every stage-3 row's
## look, when set, is one of its creature's looks with a strip on disk, so the game (WaveDirector._look_of,
## EnemyDef.variant_def, Registry.enemy_with) plays that look and never falls back to the creature's own; and the map's
## .tres carries the same codes as the JSON (import_json ran after the edit). No row's code is pinned: which look a row
## plays is Garry's to change in the Level Editor.
extends GdUnitTestSuite

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const ENEMIES := "res://content/enemies/"


func _map() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON))


## The stage-3 rows as the file has them, id -> row: the roster's s3* rows and stage_list[2].boss_fight.roster's bf3-*.
func _stage3_rows(d: Dictionary) -> Dictionary:
	var out := {}
	var td: Dictionary = d["timeline_data"]
	for r in td.get("roster", []):
		if r is Dictionary and str((r as Dictionary).get("id", "")).begins_with("s3"):
			out[str(r["id"])] = r
	var sl: Array = td.get("stage_list", [])
	if sl.size() > 2 and sl[2] is Dictionary:
		var bf = (sl[2] as Dictionary).get("boss_fight", {})
		if bf is Dictionary:
			for r in (bf as Dictionary).get("roster", []):
				if r is Dictionary and str((r as Dictionary).get("id", "")).begins_with("bf3-"):
					out[str(r["id"])] = r
	return out


## id -> code for the stage-3 rows that set a look.
func _set_looks(rows: Dictionary) -> Dictionary:
	var out := {}
	for id in rows:
		var code: String = str((rows[id] as Dictionary).get("variant", ""))
		if code != "":
			out[id] = code
	return out


func test_the_map_has_stage3_rows_and_some_set_a_look() -> void:
	var rows := _stage3_rows(_map())
	var roster_rows := 0
	var fight_rows := 0
	for id in rows:
		if str(id).begins_with("bf3-"):
			fight_rows += 1
		else:
			roster_rows += 1
	assert_int(roster_rows).override_failure_message("stage-3 roster rows (ids s3*)").is_greater(0)
	assert_int(fight_rows).override_failure_message("Blood Moon boss-fight rows (ids bf3-*)").is_greater(0)
	# the pass wrote looks into the rows: some of them name one (which ones is the file's business)
	assert_int(_set_looks(rows).size()).is_greater(0)
	for id in rows:
		var r: Dictionary = rows[id]
		assert_bool(Registry.enemy(str(r.get("enemy", ""))) != null).override_failure_message("row %s names an unknown creature '%s'" % [id, str(r.get("enemy", ""))]).is_true()


func test_every_set_look_exists_on_its_creature_with_a_strip_on_disk() -> void:
	var rows := _stage3_rows(_map())
	var looks := _set_looks(rows)
	for id in looks:
		var code: String = looks[id]
		var cid: String = str((rows[id] as Dictionary)["enemy"])
		var def: EnemyDef = Registry.enemy(cid)
		assert_bool(def != null).override_failure_message("row %s: no creature %s" % [id, cid]).is_true()
		if def == null:
			continue
		# its own code is allowed (the row then plays what the creature plays); any other must be one of its looks
		if code != def.variant:
			assert_bool(def.variants.has(code)).override_failure_message("row %s: %s has no look %s (it has %s)" % [id, cid, code, str(def.variants.keys())]).is_true()
			assert_bool(def.variant_shelved(code)).override_failure_message("row %s: %s's look %s is shelved" % [id, cid, code]).is_false()
		var strip := def.look_strip_path(code)
		assert_str(strip).override_failure_message("row %s: %s@%s has no strip path" % [id, cid, code]).is_not_empty()
		assert_bool(FileAccess.file_exists(strip)).override_failure_message("row %s: %s@%s strip missing on disk: %s" % [id, cid, code, strip]).is_true()
		# the JSON's own entry points at a file in the creature's folder
		var raw := JSON.parse_string(FileAccess.get_file_as_string(ENEMIES + cid + "/" + cid + ".json")) as Dictionary
		if code != str(raw.get("variant", "")):
			var e: Dictionary = (raw.get("variants", {}) as Dictionary).get(code, {})
			assert_bool(e.has("sprite")).override_failure_message("row %s: %s's entry %s names no sprite" % [id, cid, code]).is_true()
			assert_bool(FileAccess.file_exists(ENEMIES + cid + "/" + str(e.get("sprite", "")))).override_failure_message("row %s: %s/%s not on disk" % [id, cid, str(e.get("sprite", ""))]).is_true()


func test_the_game_plays_the_rows_look_and_never_the_fallback() -> void:
	var rows := _stage3_rows(_map())
	var looks := _set_looks(rows)
	for id in looks:
		var code: String = looks[id]
		var cid: String = str((rows[id] as Dictionary)["enemy"])
		var def: EnemyDef = Registry.enemy(cid)
		if def == null:
			continue
		if code == def.variant:
			# the creature's own look: WaveDirector asks for "" and the def itself plays
			assert_str(WaveDirector._look_of(cid, code)).is_equal("")
			assert_bool(def.variant_def(code) == def).is_true()
			continue
		# another of its looks: the director keeps the code, the def is a copy wearing it, typed id@CODE in the manager
		assert_str(WaveDirector._look_of(cid, code)).override_failure_message("row %s: the director drops %s@%s" % [id, cid, code]).is_equal(code)
		var vd: EnemyDef = def.variant_def(code)
		assert_bool(vd != def).override_failure_message("row %s: variant_def(%s) fell back to %s itself" % [id, code, cid]).is_true()
		assert_str(vd.variant_code).is_equal(code)
		assert_str(vd.strip_path()).override_failure_message("row %s: %s@%s draws the creature's own strip" % [id, cid, code]).is_not_equal(def.strip_path())
		assert_str(vd.strip_path()).is_equal(def.look_strip_path(code))
		var with: EnemyDef = Registry.enemy_with(cid, code)
		assert_bool(with != null).is_true()
		assert_str(with.type_key()).override_failure_message("row %s" % id).is_equal(cid + "@" + code)
		assert_str(with.strip_path()).is_equal(vd.strip_path())


func test_the_tres_carries_the_files_codes() -> void:
	# import_json ran after the rows were written: the timeline the game loads names the same look for every stage-3 row
	var rows := _stage3_rows(_map())
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var seen := {}
	for r in tl.roster:
		if r is Dictionary and str((r as Dictionary).get("id", "")).begins_with("s3"):
			seen[str(r["id"])] = str((r as Dictionary).get("variant", ""))
	for r in tl.boss_fight_rows(2):
		if r is Dictionary and str((r as Dictionary).get("id", "")).begins_with("bf3-"):
			seen[str(r["id"])] = str((r as Dictionary).get("variant", ""))
	assert_array(seen.keys()).override_failure_message("the .tres and the JSON hold different stage-3 rows").contains_exactly_in_any_order(rows.keys())
	for id in rows:
		assert_str(str(seen.get(id, "<absent>"))).override_failure_message("row %s: the .tres plays '%s', the JSON '%s'" % [id, str(seen.get(id, "<absent>")), str((rows[id] as Dictionary).get("variant", ""))]).is_equal(str((rows[id] as Dictionary).get("variant", "")))


func test_the_rows_creatures_each_read_as_one_kind_on_the_blood_moon() -> void:
	# a shape rule for the crowd, not a colour pin: two different creatures standing in the same stage-3 window never
	# share a strip (a row that named another creature's look would draw two kinds alike)
	var rows := _stage3_rows(_map())
	var strips := {}
	for id in rows:
		var r: Dictionary = rows[id]
		var cid: String = str(r.get("enemy", ""))
		var def: EnemyDef = Registry.enemy(cid)
		if def == null:
			continue
		var strip := def.look_strip_path(str(r.get("variant", "")))
		if strips.has(strip):
			assert_str(str(strips[strip])).override_failure_message("rows %s and %s draw one strip for two creatures: %s" % [id, str(strips[strip]), strip]).is_equal(cid)
		else:
			strips[strip] = cid
