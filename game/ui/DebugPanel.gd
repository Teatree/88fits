## Debug panel (F1 on desktop, or enable in Options): spawn waves, level up, god mode, give items, time skip.
class_name DebugPanel
extends Control

var game: Node
var _box: VBoxContainer
var _fps: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 20
	offset_bottom = -20
	offset_top = -900
	offset_right = 520
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = Settings.debug_panel
	var p := UiKit.panel(Color(0, 0, 0, 0.7), 20, UiKit.INFO, 2)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(p)
	_box = UiKit.vbox(6)
	p.add_child(_box)
	_fps = UiKit.label("", 22, UiKit.INFO)
	_box.add_child(_fps)
	_btn("Spawn 50 walkers", func(): _spawn("walker", 50))
	_btn("Spawn 100 swarmers", func(): _spawn("swarmer", 100))
	_btn("Spawn elite", func(): if game: game.director._spawn_elite("", ""))
	_btn("Spawn boss", func(): if game and Run.map: game.director._start_boss(Run.map.boss))
	_btn("Level up", func(): Run.add_xp(Run.xp_to_next() - Run.xp + 0.1))
	_btn("+500 gold", func(): Run.add_gold(500, "debug"))
	_btn("God mode", func(): if game: game.set_god(not game.player.god))
	_btn("Kill all", func(): if game: game.enemies.kill_all(true))
	_btn("Vacuum", func(): if game: game.pickups.vacuum_all())
	_btn("Chest here", func(): if game: game.pickups.spawn_chest(game.player.global_position + game.player.forward() * 2.0))
	_btn("Skip 60 s", func(): Run.elapsed += 60.0)
	_btn("Give random weapon", _give_weapon)
	_btn("Max all held", _max_all)
	_btn("Hide (F1)", toggle)


func _btn(text: String, cb: Callable) -> void:
	var b := UiKit.button(text, 22, false, 56)
	b.pressed.connect(cb)
	_box.add_child(b)


func toggle() -> void:
	visible = not visible


func _spawn(archetype: String, n: int) -> void:
	if game == null or Run.map == null:
		return
	var id: String = str(Run.map.skins.get(archetype, ""))
	if id == "":
		return
	game.enemies.spawn_pack(id, game.player.global_position + game.player.forward() * 12.0, n)


func _give_weapon() -> void:
	var list := Registry.base_weapons().filter(func(w): return not Run.has_weapon(w.id))
	if list.is_empty():
		return
	Run.add_weapon(list[randi() % list.size()], 1)


func _max_all() -> void:
	for w in Run.weapons:
		w.level = w.def.max_level
		w.rebuild(Run.player_sheet, Run.weapons)
	for pid in Run.passives.keys():
		var d := Registry.passive(pid)
		if d:
			Run.passives[pid] = d.max_level
	Run.rebuild_sheets()


func _process(_delta: float) -> void:
	if visible:
		_fps.text = "fps %d · alive %d · proj %d · gems %d" % [Engine.get_frames_per_second(), Run.alive, game.projectiles.count if game else 0, game.pickups.count if game else 0]
