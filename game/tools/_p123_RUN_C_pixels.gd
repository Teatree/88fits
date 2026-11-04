## Pass 123 (lane RUN_C): the War Drum's moment and the Grindstone's show drawn by the pass 122 scripts (OLD_*, regenerated
## on demand: below) and by the edited ones, frozen on the same beats over a flat ground, with their dice fixed (the drum's
## shake), for a pixel-by-pixel comparison under Wanted (0 differing pixels = the Wanted drawing untouched; wanted_shots'
## run world behind them made that proof statistical). Five states: the drum's first slap and its big slap with the words,
## the grind with its sparks, a level stamped, an evolution burst. theme=royale draws the edited scripts alone under the
## Royale theme (the same frozen beats, for a clean look at the kit's type). Windowed, silent:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --script res://tools/_p123_RUN_C_pixels.gd -- out=<dir> [theme=wanted|royale] [twice=1]
## Writes <dir>/old_<state>.png and <dir>/new_<state>.png (theme=royale: new_ only; twice=1: new2_, a second take). Every
## wait is bounded and a watchdog quits after WATCHDOG seconds; the save is sandboxed; autoloads are reached by name at
## run time and the scripts loaded by path.
## The pass 122 scripts live only in game/tools/_scratch/ (git-ignored by its .gitignore, skipped by Godot by its
## .gdignore), made from the last commit before pass 123's edits:
##   git show 434ffab:game/ui/DrumMoment.gd | sed 's/^class_name DrumMoment$/## the pass 122 DrumMoment, class_name stripped/' \
##     > game/tools/_scratch/_p123_DrumMoment_old.gd
##   git show 434ffab:game/ui/GrindMoment.gd | sed 's/^class_name GrindMoment$/## the pass 122 GrindMoment, class_name stripped/' \
##     > game/tools/_scratch/_p123_GrindMoment_old.gd
extends SceneTree

const WATCHDOG := 150.0
const OLD_DRUM := "res://tools/_scratch/_p123_DrumMoment_old.gd"
const OLD_GRIND := "res://tools/_scratch/_p123_GrindMoment_old.gd"
const NEW_DRUM := "res://ui/DrumMoment.gd"
const NEW_GRIND := "res://ui/GrindMoment.gd"
const GROUND := Color("8a7a5a")
const DRUM_AT := [[0.4, "drum_slap"], [1.7, "drum_words"]]
const GRIND_LEVEL_AT := [[0.75, "grind_sparks"], [2.3, "grind_level"]]
const GRIND_EVOLVE_AT := [[2.75, "grind_evolved"]]

var _out := "user://p123_runc_pixels"
var _theme := "wanted"
var _twice := false
var _started := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("theme="):
			_theme = a.substr(6)
		elif a == "twice=1":
			_twice = true
	DirAccess.make_dir_recursive_absolute(_out)
	_started = Time.get_ticks_msec()
	process_frame.connect(_watchdog)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watchdog() -> void:
	if Time.get_ticks_msec() - _started > int(WATCHDOG * 1000.0):
		printerr("p123_runc_pixels: watchdog, quitting")
		quit(2)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p123_runc_pixels: ", name)


func _main() -> void:
	var save = root.get_node("Save")
	save.begin_sandbox()
	var settings = root.get_node("Settings")
	settings.set("ui_theme", _theme)
	if _theme == "wanted" and not (ResourceLoader.exists(OLD_DRUM) and ResourceLoader.exists(OLD_GRIND)):
		printerr("p123_runc_pixels: no pass 122 scripts at %s / %s: regenerate them (this file's header), then run again" % [OLD_DRUM, OLD_GRIND])
		save.end_sandbox()
		quit(1)
		return
	root.get_node("Run").start(root.get_node("Registry").character("drifter"), root.get_node("Registry").map("red_canyon"))
	var ground := ColorRect.new()
	ground.color = GROUND
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ground)
	await process_frame
	var takes: Array = []
	if _theme == "wanted":
		takes.append(["old", OLD_DRUM, OLD_GRIND])
	takes.append(["new", NEW_DRUM, NEW_GRIND])
	if _twice:
		takes.append(["new2", NEW_DRUM, NEW_GRIND])
	for tk in takes:
		await _drum(str(tk[0]), load(str(tk[1])) as GDScript)
		await _grind(str(tk[0]), load(str(tk[2])) as GDScript, false)
		await _grind(str(tk[0]), load(str(tk[2])) as GDScript, true)
	ground.queue_free()
	root.get_node("Run").end()
	save.end_sandbox()
	quit(0)


## The drum's moment frozen on DRUM_AT, its clock stepped at 60 fps and its dice fixed after open (which randomizes them).
func _drum(tag: String, sc: GDScript) -> void:
	var dm: Control = sc.new()
	root.add_child(dm)
	await process_frame
	dm.call("open", root.get_node("Registry").structure("war_drum"), "x2 damage · x2 attack speed · knockback · +15% speed · 15 seconds")
	dm.set_process(false)
	(dm.get("_rng") as RandomNumberGenerator).seed = 7
	for pair in DRUM_AT:
		var n := 0
		while bool(dm.get("playing")) and float(dm.get("t")) < float(pair[0]) and n < 600:
			dm.call("_process", 1.0 / 60.0)
			n += 1
		dm.queue_redraw()
		await _shot("%s_%s" % [tag, str(pair[1])])
	dm.call("skip")
	dm.queue_free()
	await process_frame


## The Grindstone's show frozen with seek (its own dice are seeded by the weapons' ids): a level (the Boomstick 2 -> 3) or
## an evolution (the Revolver into the Golden Revolver).
func _grind(tag: String, sc: GDScript, evolve: bool) -> void:
	var gm: Control = sc.new()
	root.add_child(gm)
	await process_frame
	if evolve:
		gm.call("open", {"id": "golden_revolver", "from": "revolver", "level_from": 5, "level_to": 5, "evolved": true})
	else:
		gm.call("open", {"id": "boomstick", "from": "boomstick", "level_from": 2, "level_to": 3, "evolved": false})
	gm.set_process(false)
	for pair in (GRIND_EVOLVE_AT if evolve else GRIND_LEVEL_AT):
		gm.call("seek", float(pair[0]))
		await _shot("%s_%s" % [tag, str(pair[1])])
	gm.call("skip")
	gm.queue_free()
	await process_frame
