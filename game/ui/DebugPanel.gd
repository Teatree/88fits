## Debug panel (F1 on desktop, or enable in Options): spawn waves, level up, god mode, give items, time skip.
class_name DebugPanel
extends Control

var game: Node
var _box: VBoxContainer
var _fps: Label
## pass 120 (lane REPLAY): the buttons' actions by their words, so a recording keeps a tap as a "debug" decision and its
## replay runs the same action (run_action); God mode is kept by Game.set_god itself, Hide is only the panel
var _actions: Dictionary = {}


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
	_btn("God mode", func(): if game: game.set_god(not game.player.god), false)
	_btn("Kill all", func(): if game: game.enemies.kill_all(true))
	_btn("Vacuum", func(): if game: game.pickups.vacuum_all())
	_btn("Chest here", func(): if game: game.pickups.spawn_chest(game.player.global_position + game.player.forward() * 2.0))
	_btn("Skip 60 s", func(): Run.elapsed += 60.0)
	_btn("Give random weapon", _give_weapon)
	_btn("Max all held", _max_all)
	# pass 122 (lane UIKIT_A): the UI theme flipped from inside a run (the pause screen built next wears it; the switch
	# itself is a setting, so a replay already keeps it)
	_btn("UI theme: wanted / royale", func():
		Settings.set_value("ui_theme", "royale" if str(Settings.ui_theme) == "wanted" else "wanted")
		W.theme_changed(), false)
	# pass 122 (lane UIHUD): the Royale HUD's item slots plain or in their level / rarity colours (Settings.hud_slot_rarity;
	# the HUD lays its slots out again on the change)
	_btn("HUD slot rarity: off / on", func():
		Settings.set_value("hud_slot_rarity", not bool(Settings.hud_slot_rarity)), false)
	_btn("Hide (F1)", toggle, false)


func _btn(text: String, cb: Callable, record: bool = true) -> void:
	var b := UiKit.button(text, 22, false, 56)
	if record:
		_actions[text] = cb
		b.pressed.connect(func():
			RunReplay.note("debug", {"what": text})
			cb.call())
	else:
		b.pressed.connect(cb)
	_box.add_child(b)


## A replay's "debug" decision: the action of the button with these words (false: no such button on this build).
func run_action(what: String) -> bool:
	var cb: Callable = _actions.get(what, Callable())
	if not cb.is_valid():
		return false
	cb.call()
	return true


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
	# pass 120 (lane REPLAY): on the rule dice, so its replay hands over the same weapon
	Run.add_weapon(list[Dice.r.randi() % list.size()], 1)


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
