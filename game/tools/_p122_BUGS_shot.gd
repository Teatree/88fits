## Pass 122 lane BUGS capture (Garry: "There doesn't seem to be an exploding effect to the Exploding enemies"): the debug
## arena in a stage's look (3 = hell's red ground by default), one creature wearing the Explosive elite modifier (or, with
## mode=burst, a Horned Toad: its death_burst two seconds after it dies) standing up the screen from the hero, killed by
## one hit of the tool's own (the hero's gun holds its fire), then frames: it standing, the warning ring as it opens and
## halfway through, the boom the frame it goes off and 0.25, 0.5, 0.8 and 1.5 s on (the flash, the fireball, the smoke,
## the scorch). Prints where the body fell, how far its follow-through slid it by the boom, and Fx's blast count.
## Windowed, --fixed-fps 60 (a PNG save stalls the clock, not the game), bounded (WATCHDOG_S, FRAME_CAP), the save kept
## in memory and put back (tools/godot.sh keeps the PC's file aside too).
## Run: GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game
##        --script res://tools/_p122_BUGS_shot.gd -- out=<dir> [stage=1|2|3] [mode=elite|burst] [creature=<id>] [zoom=<x>] [up=<m>] [clean=0]
## Pictures: <mode>_s<stage>_stand, _ring_000, _ring_half, _boom_0000 .. _boom_1500 (ms after the boom) in `out`.
## Autoloads and the game's classes are reached through the tree (SceneTree scripts compile before the autoloads exist).
extends SceneTree

const WATCHDOG_S := 200.0
const FRAME_CAP := 30000
const DEFAULT_OUT := "D:/_projects/88fits/tools/dl/p122/BUGS/shots"
## frames after the boom the pictures are taken at (60 a second)
const BOOM_FRAMES := [0, 15, 30, 48, 90]

var A: Dictionary = {}
var _out := DEFAULT_OUT
var _frames := 0
var _ended := false
var _save = null
var _keep: Dictionary = {}
var g = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = str(A.get("out", DEFAULT_OUT))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(_bail.bind("watchdog"))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > FRAME_CAP:
		_bail("frame cap %d" % FRAME_CAP)


func _log(s: String) -> void:
	print("p122_bugs: " + s)


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


## Runs the game on to process frame `target` (Engine.get_process_frames), at most `cap` frames.
func _until_frame(target: int, cap: int = 2000) -> void:
	var guard := 0
	while Engine.get_process_frames() < target and guard < cap:
		await process_frame
		guard += 1


## The frame now drawn, as the player sees it, saved as <name>.png (no game frame passes: the draw of this frame).
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(_out.path_join(name + ".png"))
	_log("saved %s.png (%dx%d, error %d)" % [name, img.get_width(), img.get_height(), err])


func _main() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var settings = root.get_node("Settings")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	# no debug surfaces in the picture (in memory only)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel"]:
		if settings.get(k) != null:
			settings.set(k, false)
	_log("window %s, args %s" % [str(DisplayServer.window_get_size()), str(A)])
	run.launch_override = {"arena": true, "analytics": false, "character": str(A.get("hero", "drifter"))}
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
	var EM = load("res://core/systems/EnemyManager.gd")
	g.no_random_chests = true
	g.player.god = true
	panel.call("_clear_field")
	# the stage's look (hell's red ground on 3) and the arena clock at its window's start
	var stage := int(A.get("stage", 3)) - 1
	var tl = run.map.timeline if run.map else null
	if stage >= 0 and tl != null:
		panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
		load("res://core/systems/StageLook.gd").call("of", g).show_stage(stage, 0.0)
	# the hero's gun holds its fire: the kill below is the tool's own, on its frame
	g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	if A.has("zoom"):
		panel.call("set_zoom", float(A["zoom"]))
	# the arena's own controls go; with clean=1 (the default) the HUD, the damage numbers and the Elite's chest go too, so
	# the ring, the blast and the scorch show on their own; clean=0 keeps the HUD and the chest (what Garry sees)
	var clean := str(A.get("clean", "1")) in ["1", "true", "yes", "on"]
	panel.set("_hide_hud", clean)
	panel.set("_numbers", not clean)
	panel.call("set_clean", true)
	panel.get("_hint").visible = false
	# the arena's DEBUG ARENA banner never shows in a picture
	var bn = g.hud.get("_banner") if g.hud else null
	if bn:
		bn.visible = false
	await _frames_wait(30)
	# the creature, standing still facing him, up the screen
	var mode := str(A.get("mode", "elite"))
	var cid := str(A.get("creature", "skeleton" if mode == "elite" else "horned_toad"))
	var mod = reg.elites.get("explosive") if mode == "elite" else null
	var def = reg.enemy(cid)
	if def == null:
		_log("no creature '%s'" % cid)
		_finish(1)
		return
	var yaw: float = g.camera.current_yaw()
	var up := Vector3(-sin(yaw), 0, -cos(yaw))
	var hp: Vector3 = g.player.global_position
	var at: Vector3 = hp + up * float(A.get("up", 5.5))
	at.y = g.map.height_at(at.x, at.z)
	em.spawn_rise_s = 0.0
	em.spawn_rise_big_s = 0.0
	var i: int = em.spawn(cid, at, mod)
	if i < 0:
		_log("the creature never came")
		_finish(1)
		return
	if em.state[i] == EM.STATE_SPAWN:
		em.state[i] = EM.STATE_MOVE
		em.timer[i] = 0.0
		em.squash[i] = 1.0
	em.speed[i] = 0.0
	em._face_toward(i, em.type_idx[i], hp - em.pos[i])
	em._rebuild_grid()
	var tag := "%s_s%d" % [mode, stage + 1]
	_log("%s: %s at %s, elite_idx %d, pace %.2f, hero at %s" % [tag, cid, str(em.pos[i]), em.elite_idx[i], em.pace, str(hp)])
	await _frames_wait(45)
	await _shot(tag + "_stand")
	# the kill: one hit along the screen's up, as a round of the hero's would land
	var where: Vector3 = em.pos[i]
	var serial: int = em.serial[i]
	var n0: int = g.fx.blasts
	var f0: int = Engine.get_process_frames()
	var hit: bool = em.damage(i, 1.0e9, "revolver", up, 4.0)
	_log("killed: hit %s, dying %s, fell at %s" % [str(hit), str(em.state[i] == EM.STATE_DYING), str(where)])
	if clean and g.pickups:
		# the Elite's chest (its beam and sunburst stand on the very spot) out of the picture
		var n_ch: int = g.pickups.chests.size()
		for c in g.pickups.chests:
			if is_instance_valid(c):
				c.queue_free()
		g.pickups.chests.clear()
		_log("chests cleared: %d" % n_ch)
	var delay: float = (float(mod.params.get("telegraph", 0.5)) if mod else float(def.death_burst.get("delay", 2.0))) / maxf(float(em.pace), 0.01)
	var dframes := int(round(delay * 60.0))
	_log("warning %.2f s = %d frames" % [delay, dframes])
	await _shot(tag + "_ring_000")
	await _until_frame(f0 + maxi(int(dframes / 2), 1))
	await _shot(tag + "_ring_half")
	_body(em, i, serial, where, "halfway")
	# the boom: the first frame the blast is drawn
	var guard := 0
	while g.fx.blasts == n0 and guard < dframes + 20:
		await process_frame
		guard += 1
	if g.fx.blasts == n0:
		_log("no blast came within %d frames" % (dframes + 20))
		_finish(1)
		return
	var fb: int = Engine.get_process_frames()
	_log("boom on frame %d after the kill (expected about %d); blasts %d -> %d; last_blast %s" % [fb - f0, dframes, n0, g.fx.blasts, str(g.fx.last_blast)])
	_body(em, i, serial, where, "at the boom")
	for n: int in BOOM_FRAMES:
		await _until_frame(fb + n)
		await _shot("%s_boom_%04d" % [tag, int(round(n * 1000.0 / 60.0))])
	_body(em, i, serial, where, "1.5 s on")
	_log("done in %.1f s" % (Time.get_ticks_msec() / 1000.0))
	_finish(0)


## Where the body lies now against where it fell (the corpse's follow-through, pass 82), while its slot is still its own.
func _body(em, i: int, serial: int, where: Vector3, when: String) -> void:
	if em.alive[i] == 1 and em.serial[i] == serial:
		var p: Vector3 = em.pos[i]
		_log("body %s: %s, %.2f m from where it fell" % [when, str(p), Vector2(p.x - where.x, p.z - where.z).length()])
	else:
		_log("body %s: gone (its slot freed)" % when)
