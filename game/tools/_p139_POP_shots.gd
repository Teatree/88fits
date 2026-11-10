## Pass 139 (lane POP): the unlock pop-up (ui/wanted/WUnlockPop.gd) proved by eye over the Trail screen, on the 40-level
## fixture (tests/fixtures/trail_screen.json, never the game's file) with a sandboxed save: an outlaw (with the Trail
## level the buy finished), a weapon, a Card, a skin, a stage, a structure, a power-up and the Bounty Board, each at its
## peak (`peak` s into it) and mid-exit, its clock held by hand (WUnlockPop.seek). Also a real buy (`buy`): the pop-up
## right after BUY on Astro's node, as the player sees it. Windowed and bounded (a watchdog quits after 150 s):
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p139_POP_shots.gd -- out=<abs dir> [only=outlaw,weapon,...] [tag=1080]
extends SceneTree

const FIXTURE := "res://tests/fixtures/trail_screen.json"
const TRAIL := "res://ui/TrailScreen.tscn"
var _out := "user://p139_pop_shots"
var _only: Array = []
var _tag := ""
var _t0 := 0
var _save
var _trail


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("tag="):
			_tag = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > 150000:
		print("p139_pop_shots: watchdog")
		_end(2)


func _end(code: int) -> void:
	if _trail:
		_trail.load_from()
	if _save:
		_save.end_sandbox()
	quit(code)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _shot(name: String) -> void:
	await _frames(3)
	var f := name + ("_" + _tag if _tag != "" else "") + ".png"
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(f))
	print("p139_pop_shots: ", f)


func _main() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	_trail = load("res://core/systems/Trail.gd")
	var st = root.get_node("Settings")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		st.set(k, false)
	_trail.load_from(FIXTURE)
	_save.data["trail"] = {"bought": ["n01", "n02", "n03a", "n04"], "spent": 0, "had": []}
	_save.data["gold"] = 50000
	_save.data["heroes_owned"] = []
	_save.data["skins_owned"] = []
	_save.data.erase("board_note")
	if _save.has_method("skip_trail_tutorial"):
		_save.skip_trail_tutorial()
	_trail.refresh()
	change_scene_to_file(TRAIL)
	await _wait(0.5)
	await _frames(30)
	await _wait(0.4)
	var s = current_scene
	var pop = s.unlock_pop()
	var TS = load("res://ui/TrailScreen.gd")
	var P = load("res://ui/wanted/WUnlockPop.gd")
	var cases := [
		["outlaw", TS.unlock_entry(_trail.node("n05"), true)],
		["weapon", TS.unlock_entry(_trail.node("n08"))],
		["card", P.entry_for("passive", "thirst", "")],
		["skin", TS.unlock_entry(_trail.node("n10o"))],
		["stage", TS.unlock_entry(_trail.node("n11"))],
		["structure", TS.unlock_entry(_trail.node("n14"))],
		["powerup", TS.unlock_entry(_trail.node("n15"))],
		["feature", TS.unlock_entry(_trail.node("n16"))],
	]
	var peak: float = 0.6
	var exit_at: float = P.IN + P.HOLD + P.OUT * 0.5
	var k := 0
	for c in cases:
		k += 1
		if not _want(str(c[0])):
			continue
		pop.play(c[1])
		pop.seek(peak)
		await _wait(0.35)
		await _shot("%02d_%s_peak" % [k, c[0]])
		pop.seek(exit_at)
		await _shot("%02d_%s_exit" % [k, c[0]])
		pop.seek(0.0, true)
		pop.step(10.0)
		await _wait(0.1)
	if _want("buy"):
		# a real buy: Astro's node, the pop-up a moment after BUY, then a tap's hurry
		s.select("n05")
		await _wait(0.4)
		s.buy_selected()
		pop.frozen = true
		await _wait(0.25)
		pop.seek(0.25)
		await _shot("20_buy_in")
		pop.seek(0.9)
		await _shot("21_buy_hold")
		pop.hurry()
		pop.seek(0.9 + P.OUT_HURRY * 0.5)
		await _shot("22_buy_hurried")
	_end(0)
