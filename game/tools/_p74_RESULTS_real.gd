## Pass 74 (lane RESULTS): a real run played to its Results, then the show filmed frame by frame (the stepping of
## _p74_RESULTS_shot.gd). The Drifter plays Red Canyon at TIME_SCALE with god mode, a thumb steering him in an S, every
## card, chest, totem and the Stranger answered as smoke_run answers them; at DOWN_AT he goes down once (the story's
## grave) and a debug revive stands him up (the revive's blast joins the sources); the 3:35 Elite is struck down when it
## comes; at BOSS_JUMP_AT the stage clock jumps to the King's arrival, the King falls BOSS_KILL_AFTER later, and the hero
## walks into the portal and extracts. Then: the Results, its story printed (kills against Run.kills, the markers by kind,
## each source's moment) and filmed. Windowed:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p74_RESULTS_real.gd -- out=<dir> [inset=130]
## Every wait is bounded; the watchdog quits after WATCH seconds.
extends "res://tools/_p74_RESULTS_shot.gd"

const WATCH := 900.0
const TIME_SCALE := 4.0
const DOWN_AT := 150.0
const BOSS_JUMP_AT := 240.0
const BOSS_KILL_AFTER := 12.0
## Game seconds the run may take before the tool gives up on it.
const PLAY_MAX := 420.0

var _g
var _run
var _gt := 0.0
var _downed := false
var _jumped := false
var _boss_seen := -1.0
var _elites_struck := 0
var _decided := false


func _watch_secs() -> float:
	return WATCH


func _main() -> void:
	_run = root.get_node("Run")
	if _inset >= 0:
		root.get_node("Settings").top_inset = _inset
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	var deadline := Time.get_ticks_msec() + int(WATCH * 1000.0) - 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var cs = current_scene
		if cs and cs.has_method("part_name"):
			break
		if cs and cs.has_method("open_pause"):
			_g = cs
			_drive(root.get_process_delta_time())
	Engine.time_scale = 1.0
	var rs = current_scene
	if rs == null or not rs.has_method("part_name"):
		printerr("p74_results_real: no Results screen (game time %.0f s)" % _gt)
		quit(3)
		return
	_report()
	rs.set_process(false)
	if rs.get("_chart"):
		rs._chart.set_process(false)
	await _wait(0.45)
	await _film("real" + _suffix())
	quit(0)


## One frame of the run: the hero steered, every screen answered, the run's moments made.
func _drive(dt: float) -> void:
	if _g == null or not is_instance_valid(_g) or _g.player == null:
		return
	if not _g._run_started or _g.spawning:
		return
	if Engine.time_scale != TIME_SCALE and not _decided:
		Engine.time_scale = TIME_SCALE
		_g.player.god = true
	if not _g.paused:
		_gt += dt
	var inp = _g.player.input
	if inp and not _g.paused:
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_gt * 0.5) * 90.0, -110.0)
	if _g.cards and _g.cards.visible and not _g.cards._offer.is_empty() and not _g.cards._picking:
		_g.cards._pick(_g.cards._offer[0])
	if _g.get("chest_screen") and _g.chest_screen.visible and not _g.chest_screen._spinning:
		_g.chest_screen._finish(true)
	if _g.get("resume_gate") and _g.resume_gate.visible:
		_g.resume_gate.tap()
	if _g.get("stranger_screen") and _g.stranger_screen.visible:
		_g.stranger_screen._finish(false)
	if _g.get("structure_shop") and _g.structure_shop.visible:
		_g.structure_shop._finish(false)
	if _g.get("totem_screen") and _g.totem_screen.visible and not _g.totem_screen._done:
		var tp: Array = _g.totem_screen.planks()
		if not tp.is_empty():
			_g.totem_screen._pick(tp[0])
	var em = _g.enemies
	# the down: a grave on the chart, then the revive's blast
	if _gt >= DOWN_AT and not _downed and not _g.paused:
		_downed = true
		_g.player.died.emit()
		_g._revive("debug")
		print("p74_results_real: down and revived at %.0f s" % _gt)
	# the 3:35 Elite, struck down as it comes
	if em and not _g.paused:
		for i in em.MAX:
			if em.alive[i] == 0 or em.state[i] == em.STATE_DYING or em.type_idx[i] < 0:
				continue
			var def = em.types[em.type_idx[i]]["def"]
			if def.archetype == "elite" and i != em.boss_index:
				if em.damage(i, 1000000.0, "revolver"):
					_elites_struck += 1
					print("p74_results_real: Elite %s struck down at %.0f s" % [def.id, _gt])
	# the King: the stage clock jumped to his arrival, his fall a little after
	if _gt >= BOSS_JUMP_AT and not _jumped and not _g.paused and _run.stage == 0:
		_jumped = true
		_run.elapsed = float(_g.director.timeline.stage_length) - 4.0
		print("p74_results_real: stage clock jumped to the King at %.0f s" % _gt)
	if em and em.boss_alive():
		if _boss_seen < 0.0:
			_boss_seen = _gt
		elif _gt - _boss_seen >= BOSS_KILL_AFTER and not _g.paused:
			em.damage(em.boss_index, 1000000.0, "revolver")
			print("p74_results_real: the King falls at %.0f s" % _gt)
	# the portal: walk in, extract
	if _g.portal and is_instance_valid(_g.portal) and _g.portal.armed and not _g.paused:
		_g.player.global_position = _g.portal.global_position + Vector3(0.2, 0.5, 0)
	if _g.portal_dialog and _g.portal_dialog.visible and not _decided:
		_decided = true
		Engine.time_scale = 1.0
		_g.portal_dialog.visible = false
		_g.portal_dialog.decided.emit(true)
		print("p74_results_real: extracted at %.0f s" % _gt)
	if _gt >= PLAY_MAX and not _decided:
		_decided = true
		Engine.time_scale = 1.0
		print("p74_results_real: out of time at %.0f s, the run ends here" % _gt)
		_run.extracted = true
		_g.end_run()


func _report() -> void:
	var tl = _run.timeline
	var sum := 0
	for k in tl.kills:
		sum += int(k)
	var kinds := {}
	for m in tl.markers:
		kinds[int(m[1])] = int(kinds.get(int(m[1]), 0)) + 1
	print("p74_results_real: play %.0f s, kills %d (Run %d), markers %s (1 special, 2 elite, 3 boss, 4 down), stages %s, start %s" % [
		tl.t, sum, _run.kills, str(kinds), str(tl.stages), tl.start_weapon])
	var order: Array = []
	for id in tl.sources:
		var c: PackedFloat32Array = tl.sources[id]["curve"]
		order.append([tl.joined(str(id)), str(id), float(_run.damage_by_weapon.get(id, 0.0)), c.size()])
	order.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for o in order:
		if float(o[2]) > 0.0:
			print("p74_results_real:   %6.1f s  %-18s %9.0f  (%d samples)" % [float(o[0]), str(o[1]), float(o[2]), int(o[3])])
