## Pass 120, lane REPLAY (Garry: "Replay Watch - Bug: At some point when watching my previous game my guy died and in the
## game I used a Debug Revive and in the Replay I just see the dead body running around not being able to interact with
## objects of any kind."). BALANCING.md 62.REPLAY.
##  1. end to end: a run recorded with the hero going down and getting up on the free (debug) revive and the ad revive
##     (real finger taps on Down!'s buttons, between frames as a player's are) and on the Phoenix Feather (handed over by
##     the level-up's debug hand, a decision the recording now keeps), at an uneven 47 frames a second, replays with every
##     check equal: the same downs and revives at the same clocks, the hero up with the same HP, the run going on after;
##  2. the same recording with one Down! choice taken out (a replay that has parted): the run never ends where the
##     player's went on (Down!'s count waits for the next choice, or the safety net stands him up without spending a
##     chance), and the light says so from that moment;
##  3. the rules one by one: a hero down in a replay is never dragged along a recorded place that walks away; Down!'s
##     count ends the run in a replay only where the recording ends; the debug panel's taps and the debug hand are
##     replayed; an editor recording names its files.
extends GdUnitTestSuite

const DIR := "test_replay120"
## the recording and its three replays (made once in before(): a subprocess each, the suite holds the Godot lock)
static var _rec := {}
static var _rec_events: Array = []
static var _exact := {}
static var _cut_wait := {}
static var _cut_net := {}
static var _cut_kind := ""


func before() -> void:
	var godot := OS.get_executable_path()
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dir := OS.get_user_data_dir().path_join(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var rec := dir.path_join("rec.json")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var out: Array = []
	# Stage 3 with the Upgrade board's Stakes at 6 and a careless bot: he goes down several times in two minutes
	OS.execute(godot, ["--headless", "--fixed-fps", "47", "--path", root, "--script", "res://tools/_p114_REPLAY_proof.gd", "--",
		"mode=record", "out=" + rec, "hero=drifter", "stage=3", "seed=5", "limit=150", "check=0.5", "wall=400",
		"downs=debug,ad,debug,debug", "down_wait=1.0", "down_tap=1", "give=phoenix_feather", "preset=careless", "stakes=6"], out, true)
	if not FileAccess.file_exists(rec):
		return
	_rec = JSON.parse_string(FileAccess.get_file_as_string(rec))
	var ev = JSON.parse_string(FileAccess.get_file_as_string(rec + ".events.json"))
	_rec_events = ev if ev is Array else []
	_exact = _replay(godot, root, rec, dir.path_join("rep.json"), false)
	# the same run with one Down! choice gone (the second debug revive, else the first revive): a replay that parted
	var cut: Dictionary = (_rec as Dictionary).duplicate(true)
	var decs: Array = cut["decisions"]
	var revs: Array = []
	for i in range(decs.size()):
		if str(decs[i]["k"]) == "revive" and str(decs[i].get("kind", "")) != "give_up":
			revs.append(i)
	if revs.is_empty():
		return
	var drop: int = revs[1] if revs.size() > 1 else revs[0]
	_cut_kind = str(decs[drop].get("kind", ""))
	decs.remove_at(drop)
	var cut_path := dir.path_join("cut.json")
	var f := FileAccess.open(cut_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(cut))
	f.close()
	_cut_wait = _replay(godot, root, cut_path, dir.path_join("rep_wait.json"), false)
	_cut_net = _replay(godot, root, cut_path, dir.path_join("rep_net.json"), true)


func after() -> void:
	var dir := OS.get_user_data_dir().path_join(DIR)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func after_test() -> void:
	Lockstep.replaying = false
	Lockstep.driving = false
	Lockstep.input_depth = 0
	Lockstep.clear_timers()
	RunReplay.plan = {}
	RunReplay.I = null


static func _replay(godot: String, root: String, file: String, rep: String, assist: bool) -> Dictionary:
	var out: Array = []
	OS.execute(godot, ["--headless", "--fixed-fps", "64", "--path", root, "--script", "res://tools/_p114_REPLAY_proof.gd", "--",
		"mode=replay", "file=" + file, "out=" + rep, "wall=400", "assist=" + ("1" if assist else "0")], out, true)
	if not FileAccess.file_exists(rep):
		return {}
	var r = JSON.parse_string(FileAccess.get_file_as_string(rep))
	return r if r is Dictionary else {}


## [clock, kind, id] of the downs and the revives in an event log.
static func _downs(events: Array) -> Array:
	var out: Array = []
	for e in events:
		if str(e[1]) == "death" or str(e[1]) == "revive":
			out.append("%.2f %s %s" % [float(e[0]), str(e[1]), str(e[2]) if str(e[1]) == "revive" else ""])
	return out


static func _revives(events: Array, kind: String) -> int:
	var n := 0
	for e in events:
		if str(e[1]) == "revive" and str(e[2]) == kind:
			n += 1
	return n


# ---------------------------------------------------------------- 1. the exact replay

func test_the_recording_went_down_and_got_up_every_way() -> void:
	assert_bool(_rec.is_empty()).is_false()
	# the free revive and the ad as taps between frames (phase 0), the Phoenix Feather by itself after the debug hand's gift
	var tapped := {}
	for d: Dictionary in _rec.get("decisions", []):
		if str(d["k"]) == "revive" and int(d["p"]) == 0:
			tapped[str(d.get("kind", ""))] = true
	assert_bool(tapped.has("debug")).is_true()
	assert_bool(tapped.has("ad")).is_true()
	var gave := false
	for d: Dictionary in _rec.get("decisions", []):
		if str(d["k"]) == "debug_give":
			gave = true
	assert_bool(gave).is_true()
	assert_int(_revives(_rec_events, "debug")).is_greater_equal(2)
	assert_int(_revives(_rec_events, "ad")).is_equal(1)
	assert_int(_revives(_rec_events, "phoenix")).is_equal(1)


func test_debug_ad_and_phoenix_revives_replay_exactly() -> void:
	assert_bool(_exact.is_empty()).is_false()
	assert_int(int(_exact.get("checks_bad", -1))).is_equal(0)
	assert_int(int(_exact.get("drift_frame", 0))).is_equal(-1)
	# every check the recording made (the last, at its end, too)
	assert_int(int(_exact.get("checks_ok", 0))).is_equal((_rec.get("checks", []) as Array).size())
	assert_int((_exact.get("dropped", []) as Array).size()).is_equal(0)
	assert_int(int(_exact.get("late_decisions", -1))).is_equal(0)
	# the same downs and revives at the same moments
	assert_array(_downs(_exact.get("events", []))).is_equal(_downs(_rec_events))
	assert_int(int(_exact.get("corpse_holds", -1))).is_equal(0)
	assert_int(int(_exact.get("down_parts", -1))).is_equal(0)
	assert_int(int(_exact.get("ended_early", 0))).is_equal(-1)
	assert_int(int(_exact.get("frame", 0))).is_equal(int(_rec.get("frames_n", 0)) - 1)


func test_the_hero_stands_up_with_the_same_hp() -> void:
	# after every revive the next check has him up (HP above 0); the replay's check there was equal (the test above)
	var checks: Array = _rec.get("checks", [])
	var n := 0
	for e in _rec_events:
		if str(e[1]) != "revive":
			continue
		for c: Dictionary in checks:
			if float(c["t"]) > float(e[0]):
				assert_float(float(c["hp"])).is_greater(0.0)
				n += 1
				break
	assert_int(n).is_greater_equal(4)


# ---------------------------------------------------------------- 2. a replay that parted

func test_parted_down_waits_for_the_next_choice_without_the_safety_net() -> void:
	assert_bool(_cut_wait.is_empty()).is_false()
	# the run never ends where the player's went on, and the light is red from the moment it parted
	assert_int(int(_cut_wait.get("ended_early", 0))).is_equal(-1)
	assert_int(int(_cut_wait.get("down_parts", 0))).is_greater_equal(1)
	assert_int(int(_cut_wait.get("drift_frame", -1))).is_greater_equal(0)
	assert_int(_revives(_cut_wait.get("events", []), "replay")).is_equal(0)
	var said := false
	for n in _cut_wait.get("notes", []):
		if str(n).begins_with("Down!'s count ran out here"):
			said = true
	assert_bool(said).is_true()
	assert_int(int(_cut_wait.get("frame", 0))).is_equal(int(_rec.get("frames_n", 0)) - 1)


func test_parted_down_the_safety_net_stands_him_up_without_a_chance_spent() -> void:
	assert_bool(_cut_net.is_empty()).is_false()
	assert_int(int(_cut_net.get("ended_early", 0))).is_equal(-1)
	assert_int(_revives(_cut_net.get("events", []), "replay")).is_greater_equal(1)
	# only the ad revives spent a chance
	assert_int(int(_cut_net.get("revives_used", -1))).is_equal(_revives(_cut_net.get("events", []), "ad"))
	assert_int(int(_cut_net.get("frame", 0))).is_equal(int(_rec.get("frames_n", 0)) - 1)


# ---------------------------------------------------------------- 3. the rules

class StubHero:
	extends Node3D
	var dead := false


func test_a_dead_hero_is_never_dragged_along_the_recorded_track() -> void:
	var rr := RunReplay.new()
	rr.mode = RunReplay.REPLAY
	rr.frame = 7
	var p := StubHero.new()
	add_child(p)
	p.global_position = Vector3(1, 0, 1)
	# the recorded places: 4 m away (the player's hero walked on), then 1 cm (the same place in other last bits)
	rr._hero_pos = PackedFloat32Array([5, 0, 1, 1.01, 0, 1, 5, 0, 1])
	p.dead = true
	rr._lock_hero(p)
	assert_vector(p.global_position).is_equal(Vector3(1, 0, 1))
	assert_int(rr.corpse_holds).is_equal(1)
	assert_int(rr.drift_frame).is_equal(7)
	assert_bool(str(rr.notes[0]).contains("his body stays where it fell")).is_true()
	rr._lock_hero(p)
	assert_float(p.global_position.x).is_equal_approx(1.01, 0.0001)
	# up again: the recorded place, wherever it is
	p.dead = false
	rr._lock_hero(p)
	assert_vector(p.global_position).is_equal(Vector3(5, 0, 1))
	p.queue_free()
	rr.free()


class StubDown:
	extends Node
	var took := ""
	func _decide(kind: String) -> void:
		took = kind


func test_downs_count_ends_a_replay_only_where_the_recording_ends() -> void:
	var rs := StubDown.new()
	# outside a replay: as in play
	assert_str(RunReplay.down_ran_out(rs)).is_equal("timeout")
	var rr := RunReplay.new()
	rr.mode = RunReplay.REPLAY
	RunReplay.I = rr
	rr.frames_n = 1000
	rr.frame = 999 - RunReplay.END_SLACK
	# the recording ends within END_SLACK frames: its own count ran out here too
	assert_str(RunReplay.down_ran_out(rs)).is_equal("timeout")
	# anywhere else: the screen waits (no safety net) ...
	rr.frame = 400
	rr.assist = false
	assert_str(RunReplay.down_ran_out(rs)).is_equal("")
	assert_str(rs.took).is_equal("")
	assert_int(rr.down_parts).is_equal(1)
	assert_int(rr.drift_frame).is_equal(400)
	# ... once said (it asks every frame while the count shows 0)
	assert_str(RunReplay.down_ran_out(rs)).is_equal("")
	assert_int(rr.down_parts).is_equal(1)
	# ... or the safety net stands him up (no chance spent: kind "replay")
	rr.assist = true
	assert_str(RunReplay.down_ran_out(rs)).is_equal("")
	assert_str(rs.took).is_equal("replay")
	RunReplay.I = null
	rr.free()
	rs.free()


class StubPanel:
	extends Node
	var ran := ""
	func run_action(what: String) -> bool:
		ran = what
		return what == "Kill all"


class StubGame:
	extends Node
	var debug_panel: Node


func test_a_debug_panel_tap_is_replayed_by_its_words() -> void:
	var rr := RunReplay.new()
	rr.mode = RunReplay.REPLAY
	var g := StubGame.new()
	g.debug_panel = StubPanel.new()
	rr.game = g
	assert_bool(rr._apply({"k": "debug", "what": "Kill all", "f": 3, "p": 0})).is_true()
	assert_str(g.debug_panel.ran).is_equal("Kill all")
	assert_bool(rr.notes.is_empty()).is_true()
	# a button this build does not have: said, and the replay goes on
	assert_bool(rr._apply({"k": "debug", "what": "Old button", "f": 4, "p": 0, "t": 2.0})).is_true()
	assert_bool(str(rr.notes[0]).contains("is not replayed")).is_true()
	g.debug_panel.free()
	g.free()
	rr.free()


func test_the_debug_panel_and_the_debug_hand_note_what_they_do() -> void:
	var rr := RunReplay.new()
	rr.mode = RunReplay.RECORD
	RunReplay.I = rr
	rr.frame = 10
	rr._between = true
	var dp := DebugPanel.new()
	add_child(dp)
	assert_bool(dp.run_action("No such button")).is_false()
	# a tap on a recorded button (its pressed signal): noted by its words
	for b in dp.find_children("*", "Button", true, false):
		if (b as Button).text == "Vacuum":
			(b as Button).pressed.emit()
	var kinds: Array = []
	for d: Dictionary in rr.decisions:
		kinds.append("%s:%s" % [d["k"], d.get("what", "")])
	assert_array(kinds).contains(["debug:Vacuum"])
	# God mode is kept by Game.set_god itself, and Hide only hides the panel: neither is noted here
	for b in dp.find_children("*", "Button", true, false):
		if (b as Button).text == "Hide (F1)":
			(b as Button).pressed.emit()
	assert_int(rr.decisions.size()).is_equal(1)
	dp.queue_free()
	RunReplay.I = null
	rr.free()


class StubGate:
	extends Node
	var visible := true
	var taps := 0
	func tap() -> void:
		taps += 1
		visible = false


class StubRun:
	extends Node
	var _ended := false
	var resume_gate: Node


func test_after_a_drift_the_safety_net_answers_a_screen_the_player_never_did() -> void:
	var rr := RunReplay.new()
	rr.mode = RunReplay.REPLAY
	var g := StubRun.new()
	var gate := StubGate.new()
	g.resume_gate = gate
	rr.game = g
	rr.drift_frame = 0
	# the player's next TAP TO GO is far beyond SCREEN_LOOK: not this gate's
	rr.plan = {"decisions": [{"k": "gate", "f": 2000, "p": 0}]}
	rr.frame = 0
	rr._screen_net()
	rr.frame = RunReplay.SCREEN_WAIT - 1
	rr._screen_net()
	assert_int(gate.taps).is_equal(0)
	rr.frame = RunReplay.SCREEN_WAIT
	rr._screen_net()
	assert_int(gate.taps).is_equal(1)
	assert_int(rr.screens_netted).is_equal(1)
	assert_bool(str(rr.notes[0]).contains("the safety net went on")).is_true()
	# a choice due within SCREEN_LOOK frames: the screen waits for it
	gate.visible = true
	rr.plan = {"decisions": [{"k": "gate", "f": RunReplay.SCREEN_WAIT + 300, "p": 0}]}
	for f in range(RunReplay.SCREEN_WAIT + 1, RunReplay.SCREEN_WAIT * 3):
		rr.frame = f
		rr._screen_net()
	assert_int(gate.taps).is_equal(1)
	gate.free()
	g.free()
	rr.free()


func test_a_held_key_on_tap_to_go_is_a_tap_between_frames() -> void:
	var rr := RunReplay.new()
	rr.mode = RunReplay.RECORD
	RunReplay.I = rr
	rr.frame = 20
	rr._between = true
	var gate := ResumeGate.new()
	add_child(gate)
	var went := [0]
	gate.resumed.connect(func(): went[0] += 1)
	gate.open()
	Input.action_press("move_left")
	# past the guard: the go is sent as an input event, never taken inside _process (a recording would not keep it)
	gate._process(ResumeGate.GUARD + 0.05)
	assert_int(went[0]).is_equal(0)
	gate._process(0.05)
	for _i in range(3):
		await get_tree().process_frame
	Input.action_release("move_left")
	# taken once, between frames: kept as the player's TAP TO GO
	assert_int(went[0]).is_equal(1)
	var kinds: Array = []
	for d: Dictionary in rr.decisions:
		kinds.append(str(d["k"]))
	assert_array(kinds).is_equal(["gate"])
	gate.queue_free()
	RunReplay.I = null
	rr.free()


func test_an_editor_recording_names_its_files() -> void:
	var a := RunReplay.code_print()
	assert_int(a.length()).is_equal(12)
	# read once a process: the same print again
	assert_str(RunReplay.code_print()).is_equal(a)
	if OS.has_feature("editor"):
		assert_str(str(RunReplay.build_info().get("id", ""))).starts_with("editor-")
		# the recording above, made from these very files, carries their print (and the repo's commit)
		var b: Dictionary = _rec.get("build", {})
		assert_str(str(b.get("code", ""))).is_equal(a)
		assert_int(str(b.get("git", "")).length()).is_equal(7)
