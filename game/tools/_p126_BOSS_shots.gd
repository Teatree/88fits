## Pass 126 (lane BOSS): captures of Black Sunday in the debug arena under the Dust Bowl's look, windowed, bounded. The boss comes
## `up` metres north of the hero with a crowd round them, then at the given seconds after the attack starts pictures are
## taken. mode=whirl plays his `whirl` row (wind-up, the storm, dazed), mode=blizzard his pattern, mode=stand just stands him
## there (the sprite on the sand), mode=chest shows the chest's pop-up frames in place.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --log-file <abs> \
##        --script res://tools/_p126_BOSS_shots.gd -- mode=whirl stage=3 at=0.7,1.8,3,5,7.2,8,9 out=<dir>
## Arguments: mode, stage=1..4 (3 the Dust Bowl), at=<s,...>, out=<dir>, tag=<name>, up=<m> (6), side=<m> (0), zoom=<x> (1.25),
## hud=1, crowd=<n> (40) straw men (goblins if they are not there), crowd_id=<id>, watchdog=<s> (150), frames=<n> (20000).
## The save in memory goes back as it was. Autoloads and the game's classes are reached through the tree.
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
	print("p126shots: " + s)


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


func _main() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var settings = root.get_node("Settings")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel"]:
		if settings.get(k) != null:
			settings.set(k, false)
	var bdef = reg.enemy("black_sunday")
	run.launch_override = {"arena": true, "analytics": false}
	change_scene_to_file("res://game/Game.tscn")
	for k in range(1200):
		await process_frame
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null and cs.get("enemies") != null:
			g = cs
			break
	if g == null:
		_log("the arena never came up")
		_finish(1)
		return
	await _frames_wait(20)
	var panel = g.arena_panel
	var em = g.enemies
	g.no_random_chests = true
	g.player.god = true
	panel.call("_clear_field")
	var stage := int(A.get("stage", 3)) - 1
	var tl = run.map.timeline if run.map else null
	if stage >= 0 and tl != null:
		panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
		load("res://core/systems/StageLook.gd").call("of", g).show_stage(stage, 0.0)
		if g.map != null and g.map.has_method("set_weather") and tl.get("stage_list") is Array and stage < tl.stage_list.size():
			g.map.set_weather(tl.stage_list[stage].get("weather", {}), 0.0)
	panel.call("set_zoom", float(A.get("zoom", 1.25)))
	panel.call("set_freeze", 0)
	await _frames_wait(4)
	var crowd := int(A.get("crowd", 40))
	if crowd > 0:
		var cid := str(A.get("crowd_id", "straw_man"))
		if reg.enemy(cid) == null:
			cid = "goblin"
		var came: int = panel.call("mass_spawn", [[cid, ""]], crowd, {"layout": "ring", "clear_r": 3.0, "depth": 3.0, "density": 1.4, "rise": false, "specials": false, "regular_only": true})
		_log("crowd %d %s" % [came, cid])
	panel.set("_count", 1)
	panel.call("spawn_enemy", bdef)
	var bi := int(em.boss_index)
	if bi < 0:
		_log("the boss never came")
		_finish(1)
		return
	var hp: Vector3 = g.player.global_position
	var bx := hp.x + float(A.get("side", 0.0))
	var bz := hp.z - float(A.get("up", 6.0))
	em.pos[bi] = Vector3(bx, g.map.height_at(bx, bz), bz)
	var mode := str(A.get("mode", "whirl"))
	var pscript = load("res://core/systems/BossPatterns.gd")
	for k in range(600):
		em.atk_t[bi] = 50.0
		await process_frame
		if em.patterns == null:
			em.patterns = pscript.new(em)
		if em.patterns.is_free(bi):
			break
	var attacks: Array = bdef.boss.get("attacks", [])
	var list: Array = em.custom_resolved(bdef, attacks)
	if mode == "whirl" or mode == "come_here" or mode == "spawn_ring":
		# pass 127: any row of his by its name (mode=come_here, mode=spawn_ring)
		for k in range(list.size()):
			if str((list[k] as Dictionary).get("name", "")) == mode:
				em.atk_i[bi] = k
		em.atk_t[bi] = 0.0
	elif mode == "blizzard":
		var cdef = reg.boss_attack("black_blizzard")
		em.patterns.begin(bi, cdef, {"name": cdef.id}, g.player.global_position)
	if str(A.get("hud", "1")) == "0" and g.get("hud") != null:
		g.hud.visible = false
	var ats: Array = []
	for s in str(A.get("at", "1.0,2.0,4.0")).split(","):
		ats.append(float(s))
	var out := str(A.get("out", "D:/_projects/88fits/tools/dl/p126/BOSS/shots"))
	var tag := str(A.get("tag", mode))
	var t := 0.0
	while not ats.is_empty():
		await process_frame
		t += root.get_process_delta_time()
		if t >= float(ats[0]):
			var when: float = ats.pop_front()
			var ph := -1
			if em.whirls != null:
				ph = em.whirls.phase_of(bi)
			_log("t %.2f whirl phase %d, pattern phase %d, alive %d, lifted now %d, hero %s, boss %s, hp %.0f" % [t, ph, em.patterns.phase_of(bi), em.alive_count(), _lifted(em), str(g.player.global_position), str(em.pos[bi]), em.hp[bi]])
			_log("hero leaps %d airborne %s immune %s cinematic %s shield %s box %s" % [g.player.pull_leaps, str(g.player.airborne), str(g.player.knock_immune()), str(g.player.cinematic), str(g.player.shield_t), str(g.player.box_t)])
			await _shot("%s/%s_%05.2f.png" % [out, tag, when])
	_log("done; whirl %s" % ("started %d lifted %d tosses %d" % [em.whirls.started, em.whirls.lifted, em.whirls.tosses] if em.whirls != null else "none"))
	_finish(0)


func _lifted(em) -> int:
	var n := 0
	for i in range(em.pool_max):
		if em.alive[i] == 1 and em.lift_t[i] > 0.0:
			n += 1
	return n
