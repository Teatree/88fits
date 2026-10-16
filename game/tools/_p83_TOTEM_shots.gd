## Pass 83, lane TOTEM: the Spirit Pole with its painted segments and crest, over a real paused run, windowed and silent:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game ##       --script res://tools/_p83_TOTEM_shots.gd -- out=<dir> [only=world,all] [seed=11]
## world: the pole's own roll (real_rolled_idle), then the real pick motion as in pass 82 (idle, pressed, close, toast);
## all:   every spirit at least once, three to a screen (all_0..all_3), each idle and with its middle gift pressed.
## Every wait is bounded; a watchdog quits after 240 s. The save is never written (godot.sh keeps the PC's aside too).
extends SceneTree

var _out := "user://p83_totem_shots"
var _only: Array = []
var _seed := 11
var _run
var _save
var _reg
var g
var _boons
var _backdrop: ColorRect


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("p83_totem: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(n + ".png"))
	print("p83_totem: ", n)


## A shot taken at once (the close in motion): one frame, no wait.
func _shot_now(n: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(n + ".png"))
	print("p83_totem: ", n)


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_boons = load("res://core/systems/TotemBoons.gd")
	var keep: Dictionary = _save.data.duplicate(true)
	var st = root.get_node("Settings")
	var inset_was: int = st.top_inset
	var dbg_was: bool = st.debug_mode
	var dbg_btn_was: bool = st.debug_modal_buttons
	var hints_was: bool = st.show_hints
	st.debug_mode = false
	st.debug_modal_buttons = false
	st.show_hints = false
	st.top_inset = 0
	await _start_run()
	if _want("world"):
		await _world()
	if _want("all"):
		await _all()
	st.top_inset = inset_was
	st.debug_mode = dbg_was
	st.debug_modal_buttons = dbg_btn_was
	st.show_hints = hints_was
	_save.data = keep
	print("p83_totem: done")
	quit(0)


func _start_run() -> void:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false})
	_run.arena_next = false
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree() and g.get("director") != null:
			break
	await _wait(2.5)
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	_run.path_slot = 99
	await _wait(1.0)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _put_hero(p: Vector3) -> void:
	g.player.global_position = _ground(p)
	g.player.velocity = Vector3.ZERO
	g.camera.snap_to(g.player)


func _nearest_pole():
	var best = null
	var best_d := INF
	for s in g.structures.items:
		if s.def.id == "totem_pole" and not s.used:
			var d0: float = s.global_position.length()
			if d0 < best_d:
				best_d = d0
				best = s
	return best


## The mock's offer (screens/01): Le-loo +2% (middle third), Chet-woot +6% (top), Frog +2% (bottom).
func _mock_offer() -> Array:
	return [
		{"id": "wolf", "name": "Le-loo", "animal": "the Wolf", "stat": "move_speed", "op": "mul", "value": 0.02, "min": 0.01, "max": 0.03, "quality": 2},
		{"id": "bear", "name": "Chet-woot", "animal": "the Bear", "stat": "might", "op": "mul", "value": 0.06, "min": 0.02, "max": 0.06, "quality": 3},
		{"id": "frog", "name": "Frog", "animal": "", "stat": "xp_gain", "op": "mul", "value": 0.02, "min": 0.02, "max": 0.04, "quality": 1}]


func _tap_down(at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = true
	root.push_input(e, true)


func _tap_up(at: Vector2) -> void:
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = at
	u.pressed = false
	root.push_input(u, true)


func _drag(at: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = at
	d.relative = rel
	root.push_input(d, true)


func _world() -> void:
	var pole = _nearest_pole()
	if pole == null:
		print("p83_totem: no pole")
		return
	var pp: Vector3 = pole.global_position
	g.camera.zoom_override = 0.65
	_put_hero(pp + Vector3(0.8, 0.0, 0.15))
	var waited := 0.0
	while waited < 8.0 and not g.totem_screen.visible:
		await _wait(0.1)
		waited += 0.1
	if not g.totem_screen.visible:
		print("p83_totem: the pole did not open its screen")
		return
	await _wait(0.8)
	print("p83_totem: rolled ", g.totem_screen.offer(), " label ", g.totem_screen.label_text())
	await _shot("real_rolled_idle")
	# the same screen, the mock's offer, over the same paused run (the game's own connections stay: the pick below is
	# taken by the game, toasted and the pole greyed)
	var ts = g.totem_screen
	ts.open(_mock_offer(), _reg.structure("totem_pole"), 4, 11)
	await _wait(0.8)
	await _shot("real_idle")
	var rows: Array = ts.planks()
	var mid: Vector2 = (rows[1].tag as Control).get_global_rect().get_center()
	_tap_down(mid)
	await _wait(0.25)
	await _shot("real_pressed")
	# dragged off the gift: it goes back
	for k in range(1, 9):
		var p := mid.lerp(Vector2(540, 1760), float(k) / 8.0)
		_drag(p, Vector2(0, 60))
		await process_frame
	_tap_up(Vector2(540, 1760))
	await _wait(0.3)
	await _shot("real_cancel")
	print("p83_totem: after the drag out the screen is ", "up" if ts.visible else "gone", ", gifts ", _run.totem_boons.size())
	# a real tap on the middle gift: the close
	_tap_down(mid)
	await _wait(0.12)
	_tap_up(mid)
	await _wait(0.1)
	await _shot_now("real_close_a")
	await _wait(0.1)
	await _shot_now("real_close_b")
	waited = 0.0
	while waited < 2.0 and ts.visible:
		await _wait(0.05)
		waited += 0.05
	await _wait(0.25)
	await _shot("real_toast")
	print("p83_totem: taken ", _run.totem_boons.back() if not _run.totem_boons.is_empty() else {}, " paused ", g.paused)
	await _wait(1.6)
	g.camera.zoom_override = 0.0
	await _shot("real_world_after")


## Every spirit of the pole's pool, three to a screen, over the paused run: idle, then the middle gift held.
func _all() -> void:
	var pool: Array = _boons.pool_of(_reg.structure("totem_pole"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var k := 0
	var i := 0
	while i < pool.size():
		var offer: Array = []
		for j in range(3):
			offer.append(_boons.roll(pool[(i + j) % pool.size()], rng))
		var ts = g.totem_screen
		g.set_paused(true)
		ts.open(offer, _reg.structure("totem_pole"), k + 1, 11)
		await _wait(1.0)
		await _shot("all_%d" % k)
		ts.planks()[1].show_held(true)
		await _wait(0.25)
		await _shot("all_%d_pressed" % k)
		ts.planks()[1].show_held(false)
		await _wait(0.15)
		ts._hide()
		g.set_paused(false)
		await _wait(0.2)
		i += 3
		k += 1
