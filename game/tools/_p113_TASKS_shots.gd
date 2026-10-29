## Pass 113, lane TASKS: captures of the new task types (windowed, bounded by a watchdog; the PC's save goes back as it was):
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p113_TASKS_shots.gd -- out=<dir>
##  posters_a.png  Deal N damage with a weapon, Restore N HP with an item, Restore N HP with the Heart
##  posters_b.png  Get an item to level N, Break N barrels, Take N Totem gifts
##  posters_c.png  Deal N fire damage, Deal N poison damage, Restore N HP with the Healing Well
##  collection_*.png  the Collection's locked box with a goal's picture beside its words
##  hero_sheet_*.png  the hero sheet's "To unlock" box with the picture
## Only the in-memory quests are changed for the captures (never a file); the save is restored at the end.
extends SceneTree

const LIMIT_MS := 150000
var _out := "user://p113_tasks"
var _deadline := 0
var _reg
var _save
var WP
var WB


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	_deadline = Time.get_ticks_msec() + LIMIT_MS
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		print("_p113_TASKS_shots: watchdog, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("_p113_TASKS_shots: ", name)


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## The first contract of `type` (seeds 0..400) whose target passes `want`.
func _contract(cfg: Dictionary, ctx: Dictionary, type: String, want: Callable) -> Dictionary:
	for s in 400:
		var c: Dictionary = WB.make_contract(cfg, type, ctx, _rng(s * 7 + 1))
		if not c.is_empty() and bool(want.call(c)):
			return c
	return {}


func _board(name: String, list: Array) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color("5b3d2a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	h.position = Vector2(30, 420)
	layer.add_child(h)
	for c in list:
		if (c as Dictionary).is_empty():
			continue
		h.add_child(WP.make(c, 316.0))
	await _wait(0.4)
	await _shot(name)
	for c in list:
		print("  ", str((c as Dictionary).get("type", "")), " -> ", str((c as Dictionary).get("target", "")), " n ", (c as Dictionary).get("n", 0),
			" d ", (c as Dictionary).get("d", 0), " reward ", (c as Dictionary).get("reward", 0), " | ", (c as Dictionary).get("name", ""), " | ", (c as Dictionary).get("text", ""))
	layer.queue_free()
	await process_frame


func _main() -> void:
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	WP = load("res://ui/wanted/WPoster.gd")
	WB = load("res://core/systems/WantedBoard.gd")
	var kept := FileAccess.get_file_as_string("user://save.json")
	_save.begin_sandbox()
	for id in _reg.enemies.keys():
		_save.mark_seen("enemy", str(id))
	for id in _reg.weapons.keys():
		_save.mark_seen("weapon", str(id))
	for id in _reg.passives.keys():
		_save.mark_seen("passive", str(id))
	_save.add_total("runs", 1)
	var cfg: Dictionary = WB.config(true)
	var ctx: Dictionary = WB.context("red_canyon", 0, "drifter")
	await _board("posters_a", [
		_contract(cfg, ctx, "damage_weapon", func(c): return str(c["target"]) == "revolver"),
		_contract(cfg, ctx, "heal_item", func(c): return str(c["target"]) == "mend"),
		_contract(cfg, ctx, "heal_source", func(c): return str(c["target"]) == "heart")])
	await _board("posters_b", [
		_contract(cfg, ctx, "item_level", func(c): return str(c["target_kind"]) == "passive"),
		_contract(cfg, ctx, "barrels", func(_c): return true),
		_contract(cfg, ctx, "totems", func(_c): return true)])
	await _board("posters_c", [
		_contract(cfg, ctx, "element_damage", func(c): return str(c["target"]) == "fire"),
		_contract(cfg, ctx, "element_damage", func(c): return str(c["target"]) == "poison"),
		_contract(cfg, ctx, "heal_source", func(c): return str(c["target"]) == "healing_well")])
	# the Collection's locked box: one quest as it is (the Sabre: the Orbit Saws to level 5), two in the new types
	_save.data["quests_done"] = []
	var thirst = _reg.quests.get("unlock_thirst")
	var land = _reg.quests.get("unlock_land_mine")
	var keep_t: Dictionary = thirst.condition.duplicate() if thirst else {}
	var keep_l: Dictionary = land.condition.duplicate() if land else {}
	if thirst:
		thirst.condition = {"type": "heal_with_item", "item": "mend", "count": 500}
	if land:
		land.condition = {"type": "element_damage", "element": "poison", "count": 20000, "in_one_run": true}
	_save.add_keyed_total("heal_with_item", "mend", 180)
	change_scene_to_file("res://ui/CollectionScreen.tscn")
	await _wait(1.0)
	current_scene._open_locked(_reg.weapon("sabre"))
	await _wait(0.5)
	await _shot("collection_sabre")
	current_scene._open_locked(_reg.passive("thirst"))
	await _wait(0.5)
	await _shot("collection_thirst_heal_item")
	current_scene._open_locked(_reg.weapon("land_mine"))
	await _wait(0.5)
	await _shot("collection_land_mine_poison")
	# the hero sheet's "To unlock": Fadeaway as he is (level 12 with the Drifter), then with a barrel goal
	var fad = _reg.character("fadeaway")
	var fq = _reg.quest_for("character", "fadeaway")
	var keep_f: Dictionary = fq.condition.duplicate() if fq else {}
	if fad:
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		current_scene.add_child(host)
		var s1: Control = load("res://ui/wanted/WHeroSheet.gd").open(host, fad, true)
		await _wait(0.8)
		await _scroll_to(s1, "QuestWords")
		await _shot("hero_sheet_fadeaway")
		s1.queue_free()
		if fq:
			fq.condition = {"type": "barrels_total", "count": 40}
			_save.add_total("barrels", 12)
		var s2: Control = load("res://ui/wanted/WHeroSheet.gd").open(host, fad, true)
		await _wait(0.8)
		await _scroll_to(s2, "QuestWords")
		await _shot("hero_sheet_fadeaway_barrels")
		s2.queue_free()
	if thirst:
		thirst.condition = keep_t
	if land:
		land.condition = keep_l
	if fq:
		fq.condition = keep_f
	_save.end_sandbox()
	if kept != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(kept)
		f.close()
	quit()


## Scrolls the sheet's own ScrollContainer so the node named `name` shows (it sits low on the sheet).
func _scroll_to(sheet: Control, name: String) -> void:
	var n: Control = sheet.find_child(name, true, false)
	if n == null:
		print("_p113_TASKS_shots: no ", name, " on the sheet")
		return
	var p := n.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p is ScrollContainer:
		(p as ScrollContainer).ensure_control_visible(n)
		await _wait(0.3)
