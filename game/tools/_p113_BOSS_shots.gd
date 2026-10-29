## Pass 113 (lane BOSS): captures of a boss's bullet-heaven pattern in the debug arena, windowed, bounded. The arena opens
## in the stage's look, the boss comes as the arena brings one (his bar, his attacks) `up` metres north of the hero, his
## own cycle held back, and once he is free his pattern is started; pictures are taken at the given seconds after the
## tell began (so 1.0 = mid-tell with the default 2 s tell; 6.5 = the bullets' peak). The pattern's own cost is
## measured every frame of its bullets (BossPatterns.last_us: the CPU of its tick) with the bullets in the air.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##        --script res://tools/_p113_BOSS_shots.gd -- boss=tumbleweed_king stage=1 at=1.0,6.5,11.0 out=<dir>
## Arguments: boss=<id> (tumbleweed_king), attack=<id> (the boss's pattern), stage=1|2|3, at=<s,...>, out=<dir>
## (D:/_projects/88fits/tools/dl/p113/BOSS), tag=<name> (the boss's id), up=<m> (9), side=<m> (0), zoom=<x> (1.25),
## hud=0 (the HUD shown by default: the banner and the grey bar are part of the tell), crowd=<n> creatures (goblins) round
## the hero first (0), watchdog=<s> (150), frames=<n> (20000).
## The save in memory goes back as it was (the arena's sandbox keeps it off the disk; tools/godot.sh puts the PC save
## file back too). Autoloads and the game's classes are reached through the tree.
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
	print("p113shots: " + s)


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
	var boss_id := str(A.get("boss", "tumbleweed_king"))
	var bdef = reg.enemy(boss_id)
	if bdef == null:
		_log("no boss " + boss_id)
		_finish(1)
		return
	var attack_id := str(A.get("attack", ""))
	if attack_id == "":
		for e in bdef.boss.get("attacks", []):
			var c = reg.boss_attack(str((e as Dictionary).get("name", ""))) if e is Dictionary else null
			if c != null and c.attack_kind == "pattern":
				attack_id = c.id
	var cdef = reg.boss_attack(attack_id)
	if cdef == null:
		_log("no pattern for " + boss_id)
		_finish(1)
		return
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
	var stage := int(A.get("stage", 1)) - 1
	var tl = run.map.timeline if run.map else null
	if stage >= 0 and tl != null:
		panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
		load("res://core/systems/StageLook.gd").call("of", g).show_stage(stage, 0.0)
	panel.call("set_zoom", float(A.get("zoom", 1.25)))
	panel.call("set_freeze", 0)
	await _frames_wait(4)
	var crowd := int(A.get("crowd", 0))
	if crowd > 0:
		var came: int = panel.call("mass_spawn", [["goblin", ""]], crowd, {"layout": "ring", "clear_r": 6.0, "depth": 0.0, "density": 1.2, "rise": false, "specials": false, "replace": true, "seed": 3})
		_log("crowd %d" % came)
	panel.set("_count", 1)
	panel.call("spawn_enemy", bdef)
	var bi := int(em.boss_index)
	if bi < 0:
		_log("the boss never came")
		_finish(1)
		return
	var hp: Vector3 = g.player.global_position
	var bx := hp.x + float(A.get("side", 0.0))
	var bz := hp.z - float(A.get("up", 9.0))
	em.pos[bi] = Vector3(bx, g.map.height_at(bx, bz), bz)
	# his own cycle held back while he rises; then the pattern as soon as he is free
	var pscript = load("res://core/systems/BossPatterns.gd")
	for k in range(600):
		em.atk_t[bi] = 50.0
		await process_frame
		if em.patterns == null:
			em.patterns = pscript.new(em)
		if em.patterns.is_free(bi):
			break
	em.patterns.begin(bi, cdef, {"name": cdef.id}, g.player.global_position)
	# what the pattern's look made, and every mesh under it with its material (a look check)
	var fxn = em.patterns.runs[bi]["fxn"]
	if fxn != null:
		_log("look: made %s" % str(fxn.made))
		for c in fxn.find_children("*", "GeometryInstance3D", true, false):
			var mat = c.get("material_override")
			_log("  %s: %s %s, scale %s, global scale %s" % [c.name, c.get_class(), (mat.shader.resource_path if mat is ShaderMaterial and mat.shader else str(mat)),
				str(c.scale), str(c.global_transform.basis.get_scale())])
		if str(A.get("hide", "")) == "Pillar":
			# (a look check: the pillar taken away)
			var pn = fxn.get("_pillar")
			fxn.set("_pillar", null)
			fxn.set("_pillar_mat", null)
			if pn != null:
				pn.queue_free()
	_log("pattern %s on %s (stage %d): tell %.1f s, bullets %.1f s, spent %.1f s" % [cdef.id, boss_id, stage + 1, cdef.tell_seconds(), cdef.pattern_duration(), cdef.num("spent", "seconds")])
	var ats: Array = []
	for s in str(A.get("at", "1.0,6.5")).split(","):
		ats.append(float(s))
	var out := str(A.get("out", "D:/_projects/88fits/tools/dl/p113/BOSS"))
	var tag := str(A.get("tag", boss_id))
	var t := 0.0
	var us_sum := 0.0
	var us_n := 0
	var us_max := 0
	var at_peak := 0
	var frame_sum := 0.0
	var frame_n := 0
	var last := Time.get_ticks_usec()
	while not ats.is_empty():
		await process_frame
		var now := Time.get_ticks_usec()
		var dt: float = root.get_process_delta_time()
		t += dt
		var p = em.patterns
		if p != null and p.phase_of(bi) == 1:
			us_sum += float(p.last_us)
			us_n += 1
			us_max = maxi(us_max, int(p.last_us))
			at_peak = maxi(at_peak, p.bullet_count())
			frame_sum += (now - last) / 1000.0
			frame_n += 1
		last = now
		if t >= float(ats[0]):
			var when: float = ats.pop_front()
			var ph: int = p.phase_of(bi) if p != null else -1
			var fading := 0
			if p != null and p.runs.has(bi):
				var rb: PackedFloat32Array = p.runs[bi]["b"]
				for k in range(int(p.runs[bi]["n"])):
					if rb[k * p.B + p.BFADE] > 0.0:
						fading += 1
			_log("t %.2f: phase %d, %d bullets in the air (%d burning out), boss guard x%s, pattern clock %.2f" % [when, ph, p.bullet_count() if p != null else 0, fading,
				str(p.mult.get(bi, 1.0)) if p != null else "-", float(p.runs[bi]["t"]) if p != null and p.runs.has(bi) else -1.0])
			await _shot("%s/%s_%s_t%04.1f.png" % [out, tag, "s%d" % (stage + 1), when])
	_log("pattern cost: %.0f us a tick on average over %d ticks of bullets, %d at most; %d bullets at most; frames %.1f ms on average meanwhile"
		% [us_sum / maxf(float(us_n), 1.0), us_n, us_max, at_peak, frame_sum / maxf(float(frame_n), 1.0)])
	_finish(0)
