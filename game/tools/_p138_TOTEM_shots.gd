## Pass 138, lane TOTEM: the Spirit Pole's gift cards in their five rarities over a real paused run, windowed and silent:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##       --log-file <abs> --script res://tools/_p138_TOTEM_shots.gd -- out=<abs dir> [only=first,late,tiers,held,faces,rolled]
## first:  "TOTEM 1 OF 10", Le-loo Common, Kuuma Rare, Chet-woot Epic (the store shot's offer);
## late:   "TOTEM 8 OF 11", Rare, Epic, Legendary; tiers: Common, Uncommon, Legendary (with first and late: all five);
## held:   first with its middle gift held; faces: every spirit at least once (faces_0..faces_3), assorted tiers;
## rolled: TotemBoons.offer's own rolls at 0 and 9 gifts taken (seeded).
## Every wait is bounded; a watchdog quits after 200 s. The save is put back as it was.
extends SceneTree

var _out := "user://p138_totem_shots"
var _only: Array = []
var _run
var _save
var _reg
var g
var _boons
var _def


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(200.0, true, false, true).timeout.connect(func() -> void:
		print("p138_totem: watchdog quit")
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
	print("p138_totem: ", n)


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
	var hints_was: bool = st.show_hints
	st.debug_mode = false
	st.show_hints = false
	st.top_inset = 0
	await _start_run()
	_def = _reg.structure("totem_pole")
	if _want("first"):
		await _show("first", [["wolf", 1], ["bullhead", 3], ["bear", 4]], 1, 10)
	if _want("held"):
		await _show("held", [["wolf", 1], ["bullhead", 3], ["bear", 4]], 1, 10, 1)
	if _want("late"):
		await _show("late", [["seal", 3], ["thunderbird", 4], ["whale", 5]], 8, 11)
	if _want("tiers"):
		await _show("tiers", [["frog", 1], ["killer_whale", 2], ["raven", 5]], 5, 11)
	if _want("faces"):
		var sets: Array = [[["wolf", 2], ["whale", 3], ["bear", 1]], [["thunderbird", 5], ["seal", 4], ["salmon", 2]],
			[["frog", 3], ["killer_whale", 1], ["bullhead", 4]], [["raven", 2], ["serpent", 5], ["bullhead", 3]]]
		for k in range(sets.size()):
			await _show("faces_%d" % k, sets[k], k + 2, 11)
	if _want("rolled"):
		for claimed in [0, 9]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 138 + claimed
			var offer: Array = _boons.offer(_def, rng, 0, claimed)
			print("p138_totem: rolled at ", claimed, ": ", offer.map(func(b) -> String: return "%s %s %s" % [b.id, b.rarity, _boons.amount_text(b)]))
			await _open(offer, claimed + 1, 11)
			await _shot("rolled_%d" % claimed)
			g.totem_screen._hide()
	st.top_inset = inset_was
	st.debug_mode = dbg_was
	st.show_hints = hints_was
	_save.data = keep
	print("p138_totem: done")
	quit(0)


func _start_run() -> void:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false})
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
	await _wait(1.0)


## Gifts by [id, tier] from the pole's pool.
func _gifts(spec: Array) -> Array:
	var pool: Array = _boons.pool_of(_def)
	var out: Array = []
	for pair: Array in spec:
		for e: Dictionary in pool:
			if str(e.get("id", "")) == str(pair[0]):
				out.append(_boons.roll(e, RandomNumberGenerator.new(), int(pair[1])))
	return out


func _open(offer: Array, index: int, total: int) -> void:
	if g.hud:
		g.hud.visible = false
	g.set_paused(true)
	g.totem_screen.open(offer, _def, index, total)
	await _wait(1.0)


func _show(n: String, spec: Array, index: int, total: int, held: int = -1) -> void:
	await _open(_gifts(spec), index, total)
	if held >= 0:
		var rows: Array = g.totem_screen.planks()
		rows[held].arrived = true
		rows[held].show_held(true)
		await _wait(0.3)
	await _shot(n)
	g.totem_screen._hide()
	g.set_paused(false)
	await _wait(0.1)
