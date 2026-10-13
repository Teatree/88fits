## Pass 72, lane BOSS, scratch captures: the Gila Grande's red cactus rain in the debug arena, frame by frame from the
## run camera: the wind-up (the outline of the area), the spikes thrown up and out, the red circles on the landing spots
## with the gaps between them, the spikes landing, the sand after. Then the same with the spit look (to compare by eye).
## A watchdog quits after WATCHDOG seconds whatever happens. Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path game --script res://tools/_p72_boss_rain_shot.gd -- out=<dir> [zoom=1.5] [looks=spike,spit]
extends SceneTree

const WATCHDOG := 120.0
var _out := "user://p72_boss"
var _zoom := 1.5
var _looks: PackedStringArray = ["spike", "spit"]
var _run
var _reg
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("looks="):
			_looks = a.substr(6).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	# the watchdog: a hang never holds the Godot lock for long
	var wd := create_timer(WATCHDOG, true, false, true)
	wd.timeout.connect(func():
		printerr("p72_boss: WATCHDOG fired after %d s" % int(WATCHDOG))
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_png(_out.path_join(name + ".png"))
	print("p72_boss: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(3.0)
	var rain = _reg.boss_attack("cactus_rain")
	var look0: String = str(rain.projectile.get("look", "spike"))
	for look in _looks:
		rain.projectile["look"] = look
		await _rain(look)
	rain.projectile["look"] = look0
	_save.data = keep
	print("p72_boss: done in %d s" % int((Time.get_ticks_msec() - _t0) / 1000))
	quit(0)


## The Gila 4 m up the screen from the hero, its next attack the cactus rain; frames from its wind-up to the last landing.
func _rain(tag: String) -> void:
	var em = g.enemies
	em.kill_all(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(0.6)
	var here: Vector3 = g.player.global_position
	var i: int = em.spawn("gila_grande", here + Vector3(0, 0, -4.0))
	if i < 0:
		printerr("p72_boss: no Gila")
		return
	var atks: Array = em.types[em.type_idx[i]]["def"].boss.get("attacks", [])
	var k := 0
	for j in range(atks.size()):
		if str((atks[j] as Dictionary).get("name", "")) == "cactus_rain":
			k = j
	em.atk_i[i] = k
	em.atk_t[i] = 0.2
	# its wind-up begins (the runner puts it in STATE_ATTACK)
	var waited := 0.0
	while em.state[i] != 4 and waited < 5.0:
		await process_frame
		waited += 1.0 / 60.0
	var wind: float = em.timer[i]
	print("p72_boss: %s wind-up %.2f s (pace %.2f)" % [tag, wind, em.pace])
	await _wait(0.35)
	_shot("%s_a_windup" % tag)
	await _wait(maxf(wind - 0.35 + 0.25, 0.05))
	_shot("%s_b_thrown" % tag)
	print("p72_boss: %s spots %d" % [tag, int(em.custom_last.get("spots", 0))])
	for s in [0.35, 0.7, 1.05, 1.4, 1.8, 2.3]:
		await _wait(0.35 if s < 1.5 else 0.45)
		_shot("%s_c_%03d" % [tag, int(s * 100)])
	await _wait(0.8)
	_shot("%s_d_after" % tag)
	print("p72_boss: %s landed %d, the hero hit %d" % [tag, em.custom_landed, em.custom_hits])
	em.kill_all(false)
