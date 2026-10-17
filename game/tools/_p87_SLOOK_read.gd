## Pass 87, lane SLOOK: the readability check of the stage filters. The debug arena, the hero in god mode with no
## weapon, a set piece round him (plain creatures, a forced special with its rim, an Elite, a creature half behind a
## saguaro and one behind a structure (their outlines), gems of three sizes, coins, a chest, red telegraph rings, a
## filled danger disc, a Brander-orange line, a stage-3 crowd of hellhounds and imps), frozen; then the same frame in
## each look given (StageLook.set_mults + the map's hell), whole and cropped round the set piece. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p87_SLOOK_read.gd -- out=<dir> looks="name,#rrggbb,strength,actors,hell|..."
## A watchdog quits after 150 s whatever happens; every wait is bounded.
extends SceneTree

var _out := "user://p87_slook_read"
var _looks: Array = []
var _zoom := 1.0
var _gust := false
var _run
var _save
var g
var _made: Array = []


func _initialize() -> void:
	var spec := "s1,#ffffff,0,0.35,0|s2,#4a5fa8,0.45,0.35,0|s3,#b02a2a,0.35,0.35,1"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("looks="):
			spec = a.substr(6)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a == "gust=1":
			_gust = true
	for part in spec.split("|", false):
		var f := part.split(",")
		if f.size() < 3:
			continue
		_looks.append({"name": f[0], "color": f[1], "strength": float(f[2]), "actors": float(f[3]) if f.size() > 3 else 0.35, "hell": f.size() > 4 and f[4] == "1"})
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("p87_slook_read: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	for k in range(3):
		_freeze()
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("p87_slook_read: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(600):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _wait(2.0)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(0.4)
	g.enemies.kill_all(false)
	await _wait(0.6)
	_set_piece(g.player.global_position)
	await _wait(0.5)
	# a dust gust across the set piece (it draws before the filter: the stage's tint reaches it)
	var gust = g.map.get_node_or_null("DustGust")
	if gust and _gust:
		gust._start(g.player.global_position + Vector3(0, 0, -3.0))
		await _wait(1.0)
		gust.set_process(false)
	var sl = load("res://core/systems/StageLook.gd").of(g)
	for L: Dictionary in _looks:
		var c := Color.html(str(L["color"]))
		var k := float(L["strength"])
		var a := float(L["actors"])
		sl.set_mults(Color.WHITE.lerp(c, k), Color.WHITE.lerp(c, k * a), 0.0)
		g.map.set_hell(1.0 if L["hell"] else 0.0, 0.01)
		await _wait(0.1)
		await _shot("read_" + str(L["name"]))
	_save.data = keep
	quit(0)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _freeze() -> void:
	var em = g.enemies
	for i: int in _made:
		if i >= 0 and em.alive[i] == 1:
			em.speed[i] = 0.0
			em.cooldown[i] = 9.0
			em.vel[i] = Vector3.ZERO


func _spawn(id: String, at: Vector3, special := false, elite = null, code := "") -> int:
	var em = g.enemies
	em.force_special = special
	var i: int = em.spawn(id, _ground(at), elite, 1.0, 100.0, code)
	em.force_special = false
	_made.append(i)
	return i


## Round the hero (-z is up the screen): the hero stands a little below the middle.
func _set_piece(here: Vector3) -> void:
	var reg = root.get_node("Registry")
	var props = g.map.props
	# plain creatures, left and up
	for k in range(4):
		_spawn("goblin", here + Vector3(-4.6 + 0.9 * k, 0, -2.6 - 0.5 * (k % 2)))
	_spawn("skeleton", here + Vector3(-3.6, 0, -5.4))
	# a special with its rim, right, beside a plain one of its kind
	_spawn("red_goblin", here + Vector3(3.6, 0, -3.0), true, null, "RG-B")
	_spawn("red_goblin", here + Vector3(2.2, 0, -2.4), false, null, "RG-B")
	# an Elite
	var el = reg.elites.get("shielded", null)
	_spawn("bull_beetle", here + Vector3(4.4, 0, -6.8), false, el)
	# a creature half behind a saguaro (outlined where the cactus hides it)
	props.add("saguaro_big", _ground(here + Vector3(-4.6, 0, -8.0)), 1.0)
	_spawn("skeleton", here + Vector3(-4.3, 0, -9.0))
	# a structure with a creature behind it
	var sd = reg.structure("war_drum")
	if sd and g.structures:
		g.structures._spawn(sd, _ground(here + Vector3(1.0, 0, -10.0)))
	_spawn("skeleton", here + Vector3(1.0, 0, -11.2))
	# stage 3's own: hellhounds and an imp, top
	_spawn("hellhound", here + Vector3(-1.4, 0, -13.0))
	_spawn("hellhound", here + Vector3(0.6, 0, -13.6))
	_spawn("imp", here + Vector3(3.2, 0, -13.2))
	# the telegraphs: the boss's red ring (Game.gd hold_ring), a filled danger disc, the Brander's orange line
	var tg = g.telegraphs
	tg.hold_ring(_ground(here + Vector3(-1.2, 0, -6.2)), 1.8, Color(1.0, 0.22, 0.1, 0.9))
	tg.ring(_ground(here + Vector3(2.4, 0, 1.6)), 1.6, 60.0, Color(1.0, 0.22, 0.16), true)
	tg.line(_ground(here + Vector3(-5.5, 0, 4.0)), Vector3(1, 0, 0.15).normalized(), 7.0, 60.0, Color(1.0, 0.45, 0.12, 0.55), 2.2)
	# gems (three sizes) and coins, below-left
	var pk = g.pickups
	for k in range(6):
		pk.spawn(k % 3, _ground(here + Vector3(-3.6 + 0.7 * k, 0, 1.6 + 0.4 * (k % 2))), 1.0)
	for k in range(4):
		pk.spawn(3, _ground(here + Vector3(-3.0 + 0.8 * k, 0, 3.0)), 1.0)
	pk.spawn_chest(_ground(here + Vector3(4.0, 0, 3.6)))
