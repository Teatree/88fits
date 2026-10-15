## Pass 82, lane TOTEM: captures of the Spirit Pole gift screen (design_handoff_88fits_totem, direction 1b) at the phone's
## canvas, windowed and silent:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p82_TOTEM_shots.gd -- out=<dir> [only=world,flat,inset] [seed=11]
## One real run of Red Canyon, the Drifter in god mode:
##   world: the hero stands in a pole's ring until the game opens the screen with its own roll (real_rolled_idle), the
##          same screen given the mock's offer (Le-loo +2%, Chet-woot +6%, Frog +2%; TOTEM 4 OF 11) over the paused run
##          (real_idle), a real finger held on the middle gift (real_pressed), dragged off it (real_cancel), then a real
##          tap: the close mid-way (real_close_a, real_close_b), the toast with the face (real_toast), the grey pole
##          (real_world_after).
##   flat:  the screen over a white backdrop (the mock PNGs' see-through dim as the compare tool shows it), for a pixel compare with screens/01 and 02 (flat_idle,
##          flat_pressed), one gift at its three rolls (flat_rolls, screens/03), the longest texts (flat_longest) and the
##          spirits with no face yet under an unknown total (flat_fallback).
##   inset: the mock's offer under a 200 px camera cutout (flat_inset200: everything 70 px lower).
## Every wait is bounded; a watchdog quits after 240 s. The save is never written (godot.sh keeps the PC's aside too).
extends SceneTree

var _out := "user://p82_totem_shots"
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
		print("p82_totem: watchdog quit")
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
	print("p82_totem: ", n)


## A shot taken at once (the close in motion): one frame, no wait.
func _shot_now(n: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(n + ".png"))
	print("p82_totem: ", n)


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
	if _want("flat"):
		await _flat()
	if _want("inset"):
		st.top_inset = 200
		await _flat_one("flat_inset200", _mock_offer(), 4, 11)
		st.top_inset = 0
	st.top_inset = inset_was
	st.debug_mode = dbg_was
	st.debug_modal_buttons = dbg_btn_was
	st.show_hints = hints_was
	_save.data = keep
	print("p82_totem: done")
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
		print("p82_totem: no pole")
		return
	var pp: Vector3 = pole.global_position
	g.camera.zoom_override = 0.65
	_put_hero(pp + Vector3(0.8, 0.0, 0.15))
	var waited := 0.0
	while waited < 8.0 and not g.totem_screen.visible:
		await _wait(0.1)
		waited += 0.1
	if not g.totem_screen.visible:
		print("p82_totem: the pole did not open its screen")
		return
	await _wait(0.8)
	print("p82_totem: rolled ", g.totem_screen.offer(), " label ", g.totem_screen.label_text())
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
	print("p82_totem: after the drag out the screen is ", "up" if ts.visible else "gone", ", gifts ", _run.totem_boons.size())
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
	print("p82_totem: taken ", _run.totem_boons.back() if not _run.totem_boons.is_empty() else {}, " paused ", g.paused)
	await _wait(1.6)
	g.camera.zoom_override = 0.0
	await _shot("real_world_after")


## The screen over a flat backdrop in the mock PNG's colour, opened by hand (no pick taken here).
func _flat() -> void:
	await _flat_one("flat_idle", _mock_offer(), 4, 11, true)
	var w: Dictionary = _mock_offer()[0]
	var rolls: Array = []
	for v in [0.01, 0.02, 0.03]:
		var b := w.duplicate()
		b["value"] = v
		b["quality"] = _boons.quality(v, 0.01, 0.03)
		rolls.append(b)
	await _flat_one("flat_rolls", rolls, 4, 11)
	await _flat_one("flat_longest", [
		{"id": "serpent", "name": "Se-sook", "animal": "the Two-headed Serpent", "stat": "area", "op": "mul", "value": 0.04, "min": 0.02, "max": 0.04, "quality": 3},
		{"id": "salmon", "name": "Walalee", "animal": "the Salmon", "stat": "regen", "op": "add", "value": 0.1, "min": 0.1, "max": 0.3, "quality": 1},
		{"id": "seal", "name": "Ol-hiyo", "animal": "the Seal", "stat": "magnet", "op": "mul", "value": 0.2, "min": 0.1, "max": 0.2, "quality": 3}], 11, 11)
	await _flat_one("flat_fallback", [
		{"id": "thunderbird", "name": "Thunderbird", "animal": "", "stat": "cooldown", "op": "mul", "value": -0.03, "min": -0.04, "max": -0.02, "quality": 2},
		{"id": "raven", "name": "Raven", "animal": "", "stat": "luck", "op": "add", "value": 0.02, "min": 0.02, "max": 0.06, "quality": 1},
		{"id": "whale", "name": "El-kolie", "animal": "the Whale", "stat": "max_hp", "op": "add", "value": 5.0, "min": 2.0, "max": 6.0, "quality": 3}], 4, 0)


func _flat_one(n: String, offer: Array, index: int, total: int, pressed_too: bool = false) -> void:
	var ts = g.totem_screen
	g.set_paused(true)
	if _backdrop == null:
		_backdrop = ColorRect.new()
		_backdrop.name = "MockBackdrop"
		# the mock PNGs are the dim at .78 over nothing; the compare tool lays them over white
		_backdrop.color = Color.WHITE
		_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _backdrop.get_parent() == null:
		ts.add_child(_backdrop)
	ts.move_child(_backdrop, 0)
	ts.open(offer, _reg.structure("totem_pole"), index, total)
	await _wait(1.2)
	await _shot(n)
	if pressed_too:
		var rows: Array = ts.planks()
		rows[1].show_held(true)
		await _wait(0.25)
		await _shot(n.replace("idle", "pressed"))
		rows[1].show_held(false)
		await _wait(0.2)
	ts.remove_child(_backdrop)
	ts._hide()
	g.set_paused(false)
	await _wait(0.2)
