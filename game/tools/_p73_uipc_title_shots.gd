## Pass 73 (lane UIPC): the title with every hero of the carousel, in each state a hero can be in, for checking the
## plaque by eye and by numbers (Garry: "the size of the hero plaque keeps changing depending on which hero you're
## looking at"). Windowed at the phone's canvas:
## bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p73_uipc_title_shots.gd -- out=<dir> [inset=130] [looks=painted,live] [states=owned,buyable,locked,preview]
## Writes <look>_<state>_<nn>_<hero>.png per hero and geometry.json: the plaque's, the Collections button's, PLAY's,
## the hero row's and the Requirement card's rects per shot, so "nothing moves when swiping" can be read as numbers.
## The save is sandboxed (Save.begin_sandbox): nothing is written; godot.sh keeps the PC save aside as well.
extends SceneTree

var _out := "user://p73_title"
var _inset := -1
var _looks: Array = ["painted", "live"]
var _states: Array = ["owned", "buyable", "locked", "preview"]
var _geo: Array = []
var _save
var _reg
var _settings
var _deadline := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
		elif a.begins_with("looks="):
			_looks = Array(a.substr(6).split(","))
		elif a.begins_with("states="):
			_states = Array(a.substr(7).split(","))
	DirAccess.make_dir_recursive_absolute(_out)
	# a watchdog: a capture never holds the Godot lock for long (pass 69's lesson)
	_deadline = Time.get_ticks_msec() / 1000.0 + 420.0
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() / 1000.0 > _deadline:
		push_error("_p73_uipc_title_shots: watchdog, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p73_title: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_settings = root.get_node("Settings")
	_save.begin_sandbox()
	if _inset >= 0:
		_settings.top_inset = _inset
	_save.data["gold"] = 1200
	if not (_save.data.get("best_runs") is Dictionary):
		_save.data["best_runs"] = {}
	_save.data["best_runs"]["red_canyon"] = {"time": 600.0, "level": 47, "stage": 2}
	# the quests that unlock heroes, and every hero on sale
	var hero_quests: Array = []
	for q in _reg.quests.values():
		if str(q.unlocks.get("type", "")) == "character":
			hero_quests.append(str(q.id))
	var on_sale: Array = []
	for c in _reg.characters.values():
		if not c.hidden and str(c.availability) == "purchase":
			on_sale.append(str(c.id))
	var kept_totals: Dictionary = (_save.data.get("totals", {}) as Dictionary).duplicate(true)
	for look in _looks:
		_settings.menu_style = look
		for st in _states:
			var done: Array = (_save.data["quests_done"] as Array).filter(func(id): return not hero_quests.has(str(id)))
			_save.data["totals"] = kept_totals.duplicate(true)
			_settings.preview_locked_heroes = st == "preview"
			match st:
				"owned":
					done.append_array(hero_quests)
					_save.data["heroes_owned"] = on_sale.duplicate()
				"buyable":
					done.append_array(hero_quests)
					_save.data["heroes_owned"] = []
				_:
					# no quest done (and no totals that would finish one on the title's QuestTracker.check_all)
					_save.data["totals"] = {}
					_save.data["heroes_owned"] = []
			_save.data["quests_done"] = done
			change_scene_to_file("res://ui/TitleScreen.tscn")
			await _wait(1.3 if look == "live" else 0.9)
			var t = current_scene
			var heroes: Array = t._heroes
			for i in heroes.size():
				var c = heroes[i]
				if st == "preview" and not c.hidden:
					continue
				t._index = i
				t._show_hero(1)
				t._place()
				await _wait(0.9 if look == "live" else 0.45)
				var name := "%s_%s_%02d_%s" % [look, st, i, c.id]
				await _shot(name)
				_geo.append(_rects(t, name, c))
	var f := FileAccess.open(_out.path_join("geometry.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_geo, "\t"))
	f.close()
	_save.end_sandbox()
	quit()


func _rect(c: Control) -> Array:
	if c == null or not c.is_visible_in_tree():
		return []
	var r: Rect2 = c.get_global_rect()
	return [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]


func _rects(t, name: String, c) -> Dictionary:
	var out := {"shot": name, "hero": str(c.id), "state": str(t._state(c))}
	out["plaque"] = _rect(t._plaque)
	out["button"] = _rect(t._drawer_btn)
	out["play"] = _rect(t._play)
	out["hero_row"] = _rect(t._hero_row)
	out["req"] = _rect(t._req)
	out["buy"] = _rect(t._buy_col)
	# every text on the plaque: its rect and whether its words fit inside it and inside the plaque
	var texts: Array = []
	# the room inside the border and the padding (pass 73: the plaque's Body clips what does not fit)
	var body: Control = t._plaque.get_node("Body")
	var pr: Rect2 = body.get_global_rect()
	out["body"] = _rect(body)
	for n in t._plaque.find_children("*", "WText", true, false):
		var w := n as WText
		if not w.is_visible_in_tree() or w.text == "":
			continue
		var r := w.get_global_rect()
		texts.append({"text": w.text, "px": w.font_size, "rect": _rect(w), "needs": snappedf(w.text_width(), 0.1),
			"inside": pr.grow(0.5).encloses(r)})
	out["texts"] = texts
	return out
