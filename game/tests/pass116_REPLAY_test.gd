## Pass 116, lane REPLAY (Garry: "the Replay watch tool still randomizes the Elites ... I got a different Elite while
## playing from the one that I saw when watching the replay"; BALANCING.md 59.REPLAY):
##  1. a random Elite modifier is drawn from a list in id order (never the folder scan's order);
##  2. every run gets its own seed (the first run's seed no longer sticks for the rest of the sitting); a tool's seed holds;
##  3. the director's Elites, specials and per-kill drops have their own dice: kills never move the Elites' draws;
##  4. end to end: a run recorded past its first Elite (God mode, the bot driving), replayed from the file alone: every
##     check equal (now with the events' digest `ev` and the director's dice `wd`) and the same events in the same order.
extends GdUnitTestSuite


func after_test() -> void:
	Lockstep.replaying = false
	Lockstep.driving = false
	RunReplay.plan = {}


func test_elite_mods_in_id_order() -> void:
	var list := Registry.elites_list()
	assert_int(list.size()).is_greater(1)
	for i in range(1, list.size()):
		assert_bool(str(list[i - 1].id) < str(list[i].id)).is_true()


func test_every_run_its_own_seed() -> void:
	Run.seed_dice(0)
	var a := Run.begin_run_seed({})
	var b := Run.begin_run_seed({})
	assert_int(a).is_not_equal(b)
	# a tool's seed (the run sim, the Watch) is kept for every run it starts
	Run.seed_dice(77)
	assert_int(Run.begin_run_seed({})).is_equal(77)
	assert_int(Run.begin_run_seed({})).is_equal(77)
	Run.seed_dice(0)


func test_director_streams_apart() -> void:
	Run.seed_dice(31)
	var wd := WaveDirector.new()
	Dice.seed_rng(wd._elite_rng, "director_elites")
	Dice.seed_rng(wd._drop_rng, "director_drops")
	var first := wd._elite_rng.randi()
	Dice.seed_rng(wd._elite_rng, "director_elites")
	for i in range(500):
		wd._drop_rng.randf()   # five hundred kills' power-up rolls
		wd._rng.randf()
	assert_int(wd._elite_rng.randi()).is_equal(first)
	wd.free()
	Run.seed_dice(0)


## ~5.5 minutes of Stage 1 at a fixed 60 frames a second (the first Elite row is at 5:01), then its replay at 64.
func test_record_then_replay_same_elites_and_events() -> void:
	var godot := OS.get_executable_path()
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dir := OS.get_user_data_dir().path_join("test_replay116")
	DirAccess.make_dir_recursive_absolute(dir)
	var rec := dir.path_join("rec.json")
	var rep := dir.path_join("rep.json")
	for f in [rec, rep, rec + ".events.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var out: Array = []
	OS.execute(godot, ["--headless", "--fixed-fps", "60", "--path", root, "--script", "res://tools/_p114_REPLAY_proof.gd", "--",
		"mode=record", "out=" + rec, "hero=drifter", "stage=1", "seed=11", "limit=320", "god=1", "check=1", "wall=850"], out, true)
	assert_bool(FileAccess.file_exists(rec + ".events.json")).is_true()
	if not FileAccess.file_exists(rec + ".events.json"):
		return
	out.clear()
	OS.execute(godot, ["--headless", "--fixed-fps", "64", "--path", root, "--script", "res://tools/_p114_REPLAY_proof.gd", "--",
		"mode=replay", "file=" + rec, "out=" + rep, "wall=850"], out, true)
	assert_bool(FileAccess.file_exists(rep)).is_true()
	if not FileAccess.file_exists(rep):
		return
	var recorded = JSON.parse_string(FileAccess.get_file_as_string(rec + ".events.json"))
	var r = JSON.parse_string(FileAccess.get_file_as_string(rep))
	assert_bool(recorded is Array and r is Dictionary).is_true()
	var kinds := {}
	for e in recorded:
		kinds[str(e[1])] = true
		if str(e[1]) == "elite_mod":
			assert_str(str(e[3])).is_not_empty()   # the modifier's id rides with the event
	# it met an Elite with its modifier and at least one special
	assert_bool(kinds.has("elite") and kinds.has("elite_mod")).is_true()
	assert_bool(kinds.has("special")).is_true()
	assert_int(int(r.get("checks_bad", -1))).is_equal(0)
	assert_int(int(r.get("checks_ok", 0))).is_greater(250)
	var played: Array = r.get("events", [])
	assert_int(played.size()).is_equal((recorded as Array).size())
	for i in range(mini(played.size(), (recorded as Array).size())):
		assert_str("%s:%s:%s" % [played[i][1], played[i][2], played[i][3]]).is_equal("%s:%s:%s" % [recorded[i][1], recorded[i][2], recorded[i][3]])
	for f in [rec, rep, rec + ".events.json"]:
		DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(dir)
