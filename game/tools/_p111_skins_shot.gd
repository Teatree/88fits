## Pass 111, lane SKINS: captures of the hero sheet's Looks in every state (locked, buy, short of gold, the buy question,
## owned, worn) and the title with the hero in the look he wears. The save is a sandbox (Save.begin_sandbox: nothing
## reaches the disk). Windowed at the phone's canvas, a watchdog quits a hung run:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p111_skins_shot.gd -- out=<dir> [hero=may]
extends SceneTree

const WATCHDOG := 150.0

var _out := "user://p111_skins"
var _hero_id := ""
var _save
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("hero="):
			_hero_id = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG, true, false, true).timeout.connect(func():
		print("p111_skins: WATCHDOG fired, quitting")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p111_skins: ", name)


## The save for a state: the hero owned, his look's goal done or not, the gold, the look bought and worn or not.
func _state(hero, code: String, goal_done: bool, gold: int, bought: bool, worn: bool) -> void:
	var d: Dictionary = _save.data
	d["hero_look"] = {}
	if not (d["heroes_owned"] as Array).has(hero.id):
		(d["heroes_owned"] as Array).append(hero.id)
	var q = _reg.skin_quest(hero, code)
	if q:
		(d["quests_done"] as Array).erase(q.id)
		if goal_done:
			(d["quests_done"] as Array).append(q.id)
	d["gold"] = gold
	d["skins_owned"] = [_reg.skin_key(hero.id, code)] if bought else []
	d["skin_worn"] = {hero.id: code} if worn else {}
	d["last_character"] = hero.id


func _title_with(hero) -> Node:
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.6)
	var t = current_scene
	t._index = maxi((t._heroes as Array).find(hero), 0)
	t._show_hero(0)
	t._place()
	await _wait(1.0)
	return t


func _sheet(t) -> Control:
	t.open_sheet()
	await _wait(0.8)
	var s: Control = t.find_child("HeroSheet", false, false)
	var grid: Control = s.find_child("LookGrid", true, false) if s else null
	if grid:
		(s.get("scroll") as ScrollContainer).ensure_control_visible(grid)
		await _wait(0.3)
	return s


func _main() -> void:
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
	var hero = null
	var code := ""
	for c in _reg.sorted_characters():
		if _hero_id != "" and c.id != _hero_id:
			continue
		for k in c.variants.keys():
			if c.sells_skin(str(k)):
				hero = c
				code = str(k)
				break
		if hero:
			break
	if hero == null:
		print("p111_skins: no look sold")
		quit(1)
		return
	var price: int = hero.skin_price(code)
	var states := [["locked", false, price + 400, false, false], ["buy", true, price + 400, false, false],
		["short", true, maxi(price - 350, 0), false, false], ["owned", true, 400, true, false], ["worn", true, 400, true, true]]
	for st in states:
		_state(hero, code, bool(st[1]), int(st[2]), bool(st[3]), bool(st[4]))
		var t = await _title_with(hero)
		if str(st[0]) == "worn" or str(st[0]) == "locked":
			await _shot("%s_title_%s" % [hero.id, st[0]])
		var s := await _sheet(t)
		await _shot("%s_sheet_%s" % [hero.id, st[0]])
		if str(st[0]) == "buy":
			s.call("ask_buy_look", code)
			await _wait(0.6)
			await _shot("%s_sheet_buy_confirm" % hero.id)
	print("p111_skins: done")
	quit(0)
