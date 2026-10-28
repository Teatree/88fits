## Pass 112 (lane ENEMY): the hero's run cycle rate in the game itself (Player.run_rate through _animate): the debug
## arena, the stick held full, a third of the way (a crawl) and full again while roped walking away (the harpoon's 70%),
## each for a second; prints the sprite's rate and his speed at the end of each. Headless is enough:
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/_p112_ENEMY_runrate.gd
## A watchdog quits after 90 s. The PC save is put back as it was.
extends SceneTree

var g


func _initialize() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		print("p112_runrate: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _hold(stick: Vector2, frames: int) -> void:
	for k in range(frames):
		g.player.input.enabled = true
		g.player.input.ui_blocking = false
		g.player.input.wants_move = stick.length() > 0.0
		g.player.input.stick_dir = stick
		await physics_frame


func _main() -> void:
	var run = root.get_node("Run")
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	for k in range(180):
		await process_frame
	g.player.god = true
	g.set_paused(false)
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	var out := {}
	await _hold(Vector2(0, -1), 60)
	out["full"] = [snappedf(g.player.sprite.rate, 0.01), snappedf(g.player._walk_speed, 0.01), snappedf(g.player.max_speed(), 0.01), str(g.player.sprite.animation)]
	await _hold(Vector2(0, -0.18), 60)
	out["crawl"] = [snappedf(g.player.sprite.rate, 0.01), snappedf(g.player._walk_speed, 0.01), snappedf(g.player.max_speed(), 0.01), str(g.player.sprite.animation)]
	g.player.tethered = true
	g.player.tether_from = g.player.global_position + Vector3(0, 0, 8)
	g.player.tether_away = 0.7
	await _hold(Vector2(0, -1), 60)
	out["roped_away"] = [snappedf(g.player.sprite.rate, 0.01), snappedf(g.player._walk_speed, 0.01), snappedf(g.player.max_speed(), 0.01), str(g.player.sprite.animation)]
	g.player.tethered = false
	await _hold(Vector2.ZERO, 30)
	out["stand"] = [snappedf(g.player.sprite.rate, 0.01), str(g.player.sprite.animation)]
	print("p112_runrate: ", JSON.stringify(out))
	save.data = keep
	quit(0)
