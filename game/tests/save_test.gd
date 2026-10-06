## Pass 45: the save survives. Atomic writes with a backup, a corrupt file falls back and is kept aside, a newer or odd
## file is never reset, an old one migrates forward, the arena sandbox never reaches the disk, the debounce holds then
## flushes, and a wipe leaves no backup to come back from. Runs in its own folder, never the developer's save.
extends GdUnitTestSuite

const DIR := "user://test_saves/save_test"
var _dir_before := ""


func before() -> void:
	Save.flush()
	_dir_before = Save.dir
	Save.dir = DIR
	_clear()


func after() -> void:
	_clear()
	Save.dir = _dir_before
	Save.data = Save._default()
	Save._dirty = false


func before_test() -> void:
	_clear()
	Save.data = Save._default()
	Save._dirty = false
	Save.last_error = ""
	if Save.sandboxed():
		Save.end_sandbox()


func _clear() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))


func _on_disk(p: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


func _write(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_the_suite_runs_in_its_own_folder() -> void:
	# Save._ready moved every gdUnit run to user://test_saves; this suite goes one deeper
	assert_str(_dir_before).is_equal("user://test_saves")
	assert_str(Save.path()).is_equal(DIR + "/save.json")


func test_a_write_is_whole_and_keeps_the_last_one_as_backup() -> void:
	Save.data["gold"] = 11
	assert_bool(Save.save_now()).is_true()
	assert_bool(FileAccess.file_exists(Save.path())).is_true()
	assert_bool(FileAccess.file_exists(Save.tmp_path())).is_false()
	assert_int(Save.last_saved_unix).is_greater(0)
	Save.data["gold"] = 22
	Save.save_now()
	assert_int(int(_on_disk(Save.path())["gold"])).is_equal(22)
	assert_int(int(_on_disk(Save.bak_path())["gold"])).is_equal(11)
	assert_int(int(_on_disk(Save.path())["version"])).is_equal(Save.VERSION)


func test_a_corrupt_file_falls_back_to_the_backup_and_is_kept_aside() -> void:
	Save.data["gold"] = 33
	Save.save_now()
	Save.data["gold"] = 44
	Save.save_now()
	_write(Save.path(), "{\"gold\": 44, \"tot")   # the write died halfway
	Save.load_save()
	assert_int(Save.gold()).is_equal(33)
	assert_str(Save.loaded_from).is_equal("backup")
	assert_bool(Array(DirAccess.get_files_at(DIR)).any(func(n) -> bool: return str(n).begins_with("save.json.corrupt-"))).is_true()
	# the recovered data is put back in place by the next flush, and nothing is lost after it
	Save.flush()
	assert_int(int(_on_disk(Save.path())["gold"])).is_equal(33)


func test_both_files_broken_still_keeps_them_aside() -> void:
	_write(Save.path(), "not json")
	_write(Save.bak_path(), "[1, 2")
	Save.load_save()
	assert_str(Save.loaded_from).is_equal("new")
	assert_int(Array(DirAccess.get_files_at(DIR)).filter(func(n) -> bool: return str(n).find(".corrupt-") >= 0).size()).is_equal(2)


func test_a_newer_or_odd_file_is_never_reset() -> void:
	_write(Save.path(), JSON.stringify({"version": 99, "gold": 7, "future_key": [1, 2], "totals": {"kills": 5}, "quests_done": "oops"}))
	Save.load_save()
	assert_int(Save.gold()).is_equal(7)
	assert_int(int(Save.data["version"])).is_equal(99)
	assert_bool(Save.data.has("future_key")).is_true()
	assert_int(Save.total("kills")).is_equal(5)
	assert_int(Save.total("pickups")).is_equal(0)
	assert_bool(Save.data["quests_done"] is Array).is_true()
	Save.save_now()
	assert_int(int(_on_disk(Save.path())["version"])).is_equal(99)
	assert_bool(_on_disk(Save.path()).has("future_key")).is_true()


func test_an_old_version_migrates_forward() -> void:
	_write(Save.path(), JSON.stringify({"version": 1, "gold": 3, "once": [], "totals": {"kills_of_enemy": {"goblin": 2}}}))
	Save.load_save()
	assert_int(int(Save.data["version"])).is_equal(Save.VERSION)
	assert_bool(Save.seen("enemy", "goblin")).is_true()
	assert_int(Save.gold()).is_equal(3)
	assert_bool(Save.once("seen_migrated")).is_true()
	# the stepped-up file is asked onto the disk
	assert_bool(Save._dirty).is_true()


func test_version_2_folds_the_lines_into_the_passives() -> void:
	# pass 46: what was met as a line was met as a passive (never listed twice), and Cheese is Cake wherever it was seen
	_write(Save.path(), JSON.stringify({"version": 2, "gold": 4, "once": ["seen_migrated"],
		"seen": {"line": ["brawn", "mend"], "passive": ["magnet", "mend", "cheese"], "pickup": ["cheese_bite"], "enemy": ["goblin"]}}))
	Save.load_save()
	# stepped on to this build's version (pass 47: 4, the damage numbers switched on once; pass 53: 5, the live menu once)
	assert_int(int(Save.data["version"])).is_equal(Save.VERSION)
	assert_bool((Save.data["seen"] as Dictionary).has("line")).is_false()
	assert_array(Save.data["seen"]["passive"]).contains_exactly_in_any_order(["magnet", "mend", "cake", "brawn"])
	assert_bool(Save.seen("passive", "brawn")).is_true()
	assert_bool(Save.seen("passive", "cheese")).is_false()
	assert_bool(Save.seen("pickup", "cake_slice")).is_true()
	assert_bool(Save.seen("enemy", "goblin")).is_true()
	assert_int(Save.gold()).is_equal(4)
	assert_bool(Save._dirty).is_true()
	# forward only: a file already at 3 is not renamed again (only 3 -> 4 runs, which renames nothing)
	_write(Save.path(), JSON.stringify({"version": 3, "seen": {"passive": ["cheese"]}}))
	Save.load_save()
	assert_bool(Save.seen("passive", "cheese")).is_true()
	assert_bool(Save.seen("passive", "cake")).is_false()


func test_the_arena_sandbox_never_reaches_the_disk() -> void:
	Save.data["gold"] = 5
	Save.save_now()
	Save.begin_sandbox()
	Save.add_gold(500)
	Save.mark_seen("enemy", "imp")
	Save.note_run_started()
	Save.flush()
	assert_int(int(_on_disk(Save.path())["gold"])).is_equal(5)
	Save.end_sandbox()
	assert_int(Save.gold()).is_equal(5)
	assert_bool(Save.seen("enemy", "imp")).is_false()
	assert_int(int(Save.data["runs_started"])).is_equal(0)
	assert_int(int(_on_disk(Save.path())["gold"])).is_equal(5)
	assert_bool(Save.sandboxed()).is_false()


func test_tallies_wait_and_a_menu_change_pulls_the_write_forward() -> void:
	Save.save_now()
	Save.add_total("kills", 1)
	assert_bool(Save._dirty).is_true()
	assert_int(Save._due_ms - Time.get_ticks_msec()).is_greater(Save.DEBOUNCE_MS)
	assert_int(int(_on_disk(Save.path())["totals"].get("kills", 0))).is_equal(0)
	Save.add_gold(1)
	assert_int(Save._due_ms - Time.get_ticks_msec()).is_less_equal(Save.DEBOUNCE_MS)
	Save.flush()
	assert_bool(Save._dirty).is_false()
	assert_int(int(_on_disk(Save.path())["totals"]["kills"])).is_equal(1)
	assert_int(int(_on_disk(Save.path())["gold"])).is_equal(1)


func test_the_background_notification_flushes() -> void:
	Save.save_now()
	Save.mark_once("boss_red_canyon_1")
	Save.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_bool(Save._dirty).is_false()
	assert_bool((_on_disk(Save.path())["once"] as Array).has("boss_red_canyon_1")).is_true()


func test_a_wipe_leaves_no_backup_to_come_back_from() -> void:
	Save.data["gold"] = 9
	Save.save_now()
	Save.save_now()
	assert_bool(FileAccess.file_exists(Save.bak_path())).is_true()
	Save.wipe()
	assert_int(Save.gold()).is_equal(0)
	assert_bool(FileAccess.file_exists(Save.bak_path())).is_false()
	Save.load_save()
	assert_int(Save.gold()).is_equal(0)
