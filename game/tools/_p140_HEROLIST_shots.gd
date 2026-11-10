## Pass 140 (lane HEROLIST): the outlaws' list owned first, locked after, proved by eye. On a sandboxed fresh save that owns
## Drifter, Ironwood and Astro ("before"), then the same plus Solenne ("after": she leaves the locked group for the owned
## one): the Outlaws screen (its picker at the foot) and the title on the picked outlaw, then a step each way along the
## carousel. Prints each list's order (Registry.heroes_in_menu_order) to the log.
## Windowed, bounded (a watchdog quits after 150 s; the save is sandboxed, the PC's file is never written):
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p140_HEROLIST_shots.gd -- out=<abs dir> [only=heroes,title]
extends SceneTree

const BEFORE := ["drifter", "ironwood", "astro"]
const AFTER := ["drifter", "ironwood", "astro", "solenne"]
var _out := "user://p140_herolist_shots"
var _only: Array = []
var _t0 := 0
var _save


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > 150000:
		print("p140_herolist: watchdog")
		_end(2)


func _end(code: int) -> void:
	if _save:
		_save.end_sandbox()
	quit(code)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p140_herolist: shot ", name)


func _settle() -> void:
	# a slow load eats the timer: frames as well, so the slide-ins are over
	await _wait(0.6)
	for k in range(45):
		await process_frame
	await _wait(0.5)


## A fresh save in the sandbox that owns `ids` (heroes_owned: the Trail reads it as their nodes bought), on `pick`.
func _lay_save(ids: Array, pick: String) -> void:
	_save.data = _save._default()
	_save.data["heroes_owned"] = ids.duplicate()
	_save.data["last_character"] = pick
	_save.data["gold"] = 2500
	load("res://core/systems/Trail.gd").refresh()
	var reg = root.get_node("Registry")
	var order: Array = reg.heroes_in_menu_order(false).map(func(c) -> String: return "%s(%s)" % [c.id, reg.hero_state(c)])
	print("p140_herolist: owns %s -> %s" % [str(ids), ", ".join(order)])


func _main() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var st = root.get_node("Settings")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode", "preview_locked_heroes"]:
		st.set(k, false)
	for row: Array in [["before", BEFORE, "astro"], ["after", AFTER, "solenne"]]:
		var tag: String = row[0]
		if _only.is_empty() or _only.has("heroes"):
			_lay_save(row[1], row[2])
			change_scene_to_file("res://ui/HeroesScreen.tscn")
			await _settle()
			var s = current_scene
			if s:
				print("p140_herolist: picker %s: %s, shown %s" % [tag, str(s.heroes.map(func(c) -> String: return c.id)),
					s.shown.id if s.shown else "-"])
			await _shot("heroes_%s" % tag)
		if _only.is_empty() or _only.has("title"):
			_lay_save(row[1], row[2])
			change_scene_to_file("res://ui/TitleScreen.tscn")
			await _settle()
			var t = current_scene
			if t == null or t.get("_heroes") == null:
				continue
			print("p140_herolist: title %s: %s, on %s" % [tag, str(t._heroes.map(func(c) -> String: return c.id)),
				(t._heroes[t._index]).id])
			await _shot("title_%s" % tag)
			for d: int in [1, -1, -1]:
				t._step(d)
				await _wait(0.9)
				await _shot("title_%s_%s" % [tag, (t._heroes[t._index]).id])
	print("p140_herolist: done")
	_end(0)
