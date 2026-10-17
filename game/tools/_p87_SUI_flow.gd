## Pass 87 lane SUI scratch: the portal countdown to Endless end to end in a real stage run (not the arena): the boss's
## death opens the portal, NOT YET leaves the count on the HUD, the dialog's own count runs out into Endless (it closes,
## the run goes on, the ENDLESS banner and WAVE 1), the next wave's tag, then a fall in Endless and the Results' head.
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p87_SUI_flow.gd -- out=<dir>
extends SceneTree

var _out := "user://p87_sui_flow"
var _lines: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	# the watchdog: whatever happens, the lock goes back within 90 s
	create_timer(90.0, true, false, true).timeout.connect(func():
		_say("WATCHDOG: gave up")
		_finish())
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _say(t: String) -> void:
	_lines.append(t)
	print("flow: ", t)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	_say("shot " + name)


func _finish() -> void:
	var f := FileAccess.open(_out.path_join("flow.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
		f.close()
	quit()


func _go() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "map": "red_canyon", "map_seed": 7, "stage": 1, "analytics": false}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(3.5)
	var g = current_scene
	var run = root.get_node("Run")
	g.player.god = true
	var d = g.director
	# the boss falls: the portal opens with its countdown
	d.call("_on_boss_died", null, g.player.global_position + Vector3(5, 0, 0))
	await _wait(0.3)
	_say("phase %d, countdown %.1f, hud mode '%s' tag '%s'" % [int(d.phase), float(g.portal_seconds_left()), g.hud.clock_mode(), g.hud.stage_tag_text()])
	d.set("_portal_left", 20.0)
	g._on_portal_entered()
	await _wait(1.0)
	_say("dialog up %s, paused %s, count %s" % [g.portal_dialog.visible, g.paused, (g.portal_dialog.get("_count") as Control).get("text")])
	await _shot("a-dialog")
	# NOT YET: the count goes on under the clock
	g.portal_dialog.decline()
	await _wait(1.5)
	_say("after NOT YET: dialog %s, paused %s, hud '%s' %s tag '%s'" % [g.portal_dialog.visible, g.paused, g.hud.clock_mode(), (g.hud.get("_timer") as Control).get("text"), g.hud.stage_tag_text()])
	await _shot("b-hud-countdown")
	# back in with three seconds left: the dialog's own count runs out into Endless
	d.set("_portal_left", 3.0)
	g._on_portal_entered()
	await _wait(0.6)
	_say("dialog again %s, count %s" % [g.portal_dialog.visible, (g.portal_dialog.get("_count") as Control).get("text")])
	await _shot("c-dialog-last-seconds")
	var w := 0.0
	while w < 6.0 and not run.endless:
		await _wait(0.1)
		w += 0.1
	await _wait(0.4)
	_say("endless %s after %.1f s: dialog %s, paused %s, banner '%s', hud '%s' tag '%s'" % [run.endless, w, g.portal_dialog.visible, g.paused, g.hud.banner_text(), g.hud.clock_mode(), g.hud.stage_tag_text()])
	await _shot("d-endless")
	w = 0.0
	while w < 14.0 and run.endless_wave() < 2:
		await _wait(0.2)
		w += 0.2
	await _wait(0.3)
	_say("wave %d: tag '%s', clock %s" % [run.endless_wave(), g.hud.stage_tag_text(), (g.hud.get("_timer") as Control).get("text")])
	await _shot("e-endless-wave2")
	# a fall in Endless: the Results' head
	run.died = true
	g.end_run()
	w = 0.0
	while w < 6.0 and not (current_scene and current_scene.name.to_lower().contains("result")):
		await _wait(0.1)
		w += 0.1
	await _wait(0.5)
	if current_scene and current_scene.has_method("skip_all"):
		current_scene.skip_all()
		await _wait(1.5)
		current_scene.scroll.scroll_vertical = 0
		await _wait(0.3)
		var hl: Node = current_scene.find_child("StageLine", true, false)
		_say("results: stage line '%s'" % (hl.get("text") if hl else "?"))
		await _shot("f-results-endless")
	_finish()
