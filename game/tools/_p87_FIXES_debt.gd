## Pass 87, lane FIXES, scratch probe: the run's coin debt is set from the map's black barrels (headless, bounded).
##   bash tools/godot.sh --headless --path game --script res://tools/_p87_FIXES_debt.gd
extends SceneTree

var _t0 := 0
var _save
var _keep: Dictionary = {}


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > 60000:
		print("p87_debt: watchdog")
		if _save:
			_save.data = _keep
		quit(3)


func _main() -> void:
	var run = root.get_node("Run")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await create_timer(3.0, true, false, true).timeout
	var g = current_scene
	var bf = g.barrels
	var blacks := 0
	for k in range(bf.pos.size()):
		blacks += bf.light[k]
	print("p87_debt: barrels %d black %d coins_total %d debt %.1f" % [bf.pos.size(), blacks, bf.coins_total(), g.pickups.coin_debt])
	_save.data = _keep
	quit(0)
