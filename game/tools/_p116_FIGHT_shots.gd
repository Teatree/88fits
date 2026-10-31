## Pass 116 (lane FIGHT): captures in the debug arena, windowed, bounded (a watchdog and a frame cap):
##   mode=gila: Nightfall, the Gila 10 m north, her burrow forced; pictures `at` seconds after the red warning shows;
##   mode=box: May with the Invisible Box raised: box alone, box + the Shield bubble, a hit on the box.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##        --script res://tools/_p116_FIGHT_shots.gd -- mode=gila out=<dir>
extends SceneTree

const WATCHDOG_S := 150.0
const FRAME_CAP := 20000

var A: Dictionary = {}
var g = null
var _frames := 0
var _frame_cap := FRAME_CAP
var _ended := false
var _save = null
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_frame_cap = int(A.get("frames", FRAME_CAP))
	create_timer(float(A.get("watchdog", WATCHDOG_S)), true, false, true).timeout.connect(_bail.bind("watchdog"))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > _frame_cap:
		_bail("frame cap %d" % _frame_cap)


func _log(s: String) -> void:
	print("p116fight: " + s)


func _bail(why: String) -> void:
	if _ended:
		return
	_log("stopped: " + why)
	_finish(2)


func _finish(code: int) -> void:
	if _ended:
		return
	_ended = true
	paused = false
	Engine.time_scale = 1.0
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	quit(code)


func _frames_wait(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	_log("saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _arena(character: String) -> bool:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel"]:
		if settings.get(k) != null:
			settings.set(k, false)
	run.launch_override = {"arena": true, "analytics": false, "character": character}
	change_scene_to_file("res://game/Game.tscn")
	for k in range(1200):
		await process_frame
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null and cs.get("enemies") != null:
			g = cs
			break
	if g == null:
		return false
	await _frames_wait(20)
	g.no_random_chests = true
	g.player.god = true
	g.arena_panel.call("_clear_field")
	return true


func _main() -> void:
	var mode := str(A.get("mode", "gila"))
	var out := str(A.get("out", "D:/_projects/88fits/tools/dl/p116/FIGHT"))
	if mode == "box":
		await _box(out)
	else:
		await _gila(out)
	_finish(0)


func _gila(out: String) -> void:
	if not await _arena("drifter"):
		_log("no arena")
		return
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var panel = g.arena_panel
	var em = g.enemies
	var tl = run.map.timeline
	panel.call("set_clock", float(tl.stage_start(1)) / 60.0 + 0.05)
	load("res://core/systems/StageLook.gd").call("of", g).show_stage(1, 0.0)
	panel.call("set_zoom", float(A.get("zoom", 1.0)))
	panel.call("set_freeze", 0)
	await _frames_wait(4)
	var bdef = reg.enemy("gila_grande")
	panel.set("_count", 1)
	panel.call("spawn_enemy", bdef)
	var bi := int(em.boss_index)
	if bi < 0:
		_log("no boss")
		return
	var hp: Vector3 = g.player.global_position
	em.pos[bi] = Vector3(hp.x, g.map.height_at(hp.x, hp.z - 10.0), hp.z - 10.0)
	for k in range(240):
		em.atk_t[bi] = 50.0
		await process_frame
		if em.rise_t[bi] >= 1.0:
			break
	var attacks: Array = bdef.boss.get("attacks", [])
	for k in range(attacks.size()):
		if str(attacks[k].get("name", "")) == "burrow":
			em.atk_i[bi] = k
	em.state[bi] = 0
	em.atk_t[bi] = 0.0
	var t0 := -1.0
	var t := 0.0
	var ats: Array = []
	for s in str(A.get("at", "0.2,1.6,3.2")).split(","):
		ats.append(float(s))
	while not ats.is_empty() and t < 20.0:
		await process_frame
		t += root.get_process_delta_time()
		if t0 < 0.0 and int(em.warn_shown) > 0:
			t0 = t
			_log("warning at %.2f s, spot %s, the hero at %s" % [t, str(em.atk_target[bi]), str(g.player.global_position)])
		if t0 >= 0.0 and t - t0 >= float(ats[0]):
			var when: float = ats.pop_front()
			_log("t+%.2f: state %d, hidden %d" % [when, int(em.state[bi]), int(em.hidden[bi])])
			await _shot("%s/gila_warn_t%03.1f.png" % [out, when])
	var t1 := t
	while int(em.eruptions) == 0 and t < 25.0:
		await process_frame
		t += root.get_process_delta_time()
	_log("erupted %.2f s after the warning began" % (t - t0))
	await _frames_wait(3)
	await _shot("%s/gila_erupt.png" % out)


func _box(out: String) -> void:
	if not await _arena("may"):
		_log("no arena")
		return
	var run = root.get_node("Run")
	g.arena_panel.call("set_zoom", float(A.get("zoom", 0.6)))
	g.arena_panel.call("set_freeze", 0)
	run.perks.append("invisible_box")
	g.call("_tick_box", 0.0)
	var box = g.get("mime_box")
	if box == null:
		_log("no box")
		return
	box.set("up_total", 0.0)
	box.call("raise_box")
	box.set("up_t", 600.0)
	box.set("up_total", 600.0)
	await _frames_wait(40)
	await _shot("%s/box_alone.png" % out)
	g.player.shield(600.0)
	await _frames_wait(40)
	await _shot("%s/box_shield.png" % out)
	g.player.shield_t = 0.0
	g.player._shield_node.visible = false
	g.player.sprite.set_tint(Color(1, 1, 1))
	await _frames_wait(30)
	g.player.take_damage(5.0, g.player.global_position + Vector3(3, 0, 1), {"by": "Goblin", "kind": "melee"})
	await _frames_wait(5)
	await _shot("%s/box_hit.png" % out)
	g.player.shield(600.0)
	await _frames_wait(30)
	g.player.take_damage(5.0, g.player.global_position + Vector3(-1, 0, 3), {"by": "Goblin", "kind": "melee"})
	await _frames_wait(4)
	await _shot("%s/box_shield_hit.png" % out)
