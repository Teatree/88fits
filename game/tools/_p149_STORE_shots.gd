## Pass 149 (lane STORE): the Store's captures (its two sections, the coin offers grown, the questions), the wallets with
## the Store open and shut, and Down! with a paid revive. A sandboxed save (the PC's save is never written), the Settings
## changed in memory only, the store file's revive price set in memory only. Windowed and bounded (a watchdog quits after
## 200 s):
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p149_STORE_shots.gd -- out=<abs dir> [only=store,late,confirm,short,soon,title,trail,shut,down,inset] [tag=<name>]
## store_s0_t0.png the Store on a new save (stage 1, Trail Level 0) with 1,250 gems; store_s3_t40.png at the Blood Moon and
## Trail Level 40 (the coin offers grown); confirm.png a coin offer tapped ("Buy 5,500 coins for 500 gems?"); short.png a
## coin offer tapped short of gems; soon.png a gem pack's price tapped ("Coming soon"); title_open.png / trail_open.png the
## main menu's and the Trail's headers with both wallets; title_shut.png the main menu with the Store shut (no gem
## anywhere); down_paid.png / down_paid_short.png Down! with a paid revive at a test price of 50 gems, with the gems and
## short of them; store_inset130.png the Store under a 130 px camera cutout. `tag` prefixes every file.
extends SceneTree

const STORE := "res://ui/StoreScreen.tscn"
const TITLE := "res://ui/TitleScreen.tscn"
const TRAIL := "res://ui/TrailScreen.tscn"
const PACKS := "res://core/systems/StorePacks.gd"
const TRAIL_ARG := "res://tools/trail_arg.gd"
var _out := "user://p149_store_shots"
var _only: Array = []
var _tag := ""
var _save
var _settings
var _kept: Dictionary = {}
var _fresh: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
		elif a.begins_with("tag="):
			_tag = a.substr(4) + "_"
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(200.0, true, false, true).timeout.connect(func() -> void:
		print("p149_store_shots: watchdog")
		_end(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _end(code: int) -> void:
	if _settings:
		for k: String in _kept:
			_settings.set(k, _kept[k])
	load(PACKS).load_from()
	if _save:
		_save.end_sandbox()
	quit(code)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await _frames(3)
	var p := _out.path_join(_tag + name)
	root.get_viewport().get_texture().get_image().save_png(p)
	print("p149_store_shots: ", p)


## A new save: no stage beaten, no Trail, `gold` coins and `gems` gems.
func _new_save(gold: int, gems: int) -> void:
	_save.data = _fresh.duplicate(true)
	_save.data["gold"] = gold
	_save.data["wallets"] = {"gems": gems}
	_save.data["consent"] = "no"
	_save.skip_trail_tutorial()
	load("res://core/systems/Trail.gd").refresh()


## The furthest stage (every stage before the Blood Moon beaten) and Trail Level `level` (the stage nodes bought too).
func _late_save(level: int) -> void:
	for i in 3:
		_save.mark_stage_beaten("red_canyon", i)
	var ta = load(TRAIL_ARG)
	var tr = load("res://core/systems/Trail.gd")
	var ids: Array = ta.ids_upto(level)
	for n: Dictionary in tr.nodes():
		if str((n["gives"] as Dictionary).get("type", "")) == "stage" and not ids.has(str(n["id"])):
			ids.append(str(n["id"]))
	ta.apply(_save, "", false, ids)


func _tap_price(id: String) -> void:
	var card: Control = current_scene.call("card_of", id)
	var b: Control = card.get_node("Price") if card else null
	if b == null:
		return
	b.call("show_held", true)
	await _frames(4)
	b.call("show_held", false)
	b.emit_signal("pressed")


func _main() -> void:
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_save.begin_sandbox()
	_fresh = _save.call("_default")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode", "store_open", "top_inset"]:
		_kept[k] = _settings.get(k)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		_settings.set(k, false)
	_settings.set("top_inset", 0)
	_settings.set("store_open", true)
	_new_save(1250, 1250)
	if _want("store"):
		change_scene_to_file(STORE)
		await _wait(1.0)
		await _shot("store_s0_t0.png")
	if _want("soon"):
		change_scene_to_file(STORE)
		await _wait(1.0)
		await _tap_price("gems_pouch")
		await _wait(0.7)
		await _shot("soon.png")
	if _want("confirm"):
		change_scene_to_file(STORE)
		await _wait(1.0)
		await _tap_price("coins_medium")
		await _wait(0.7)
		await _shot("confirm.png")
	if _want("short"):
		_new_save(1250, 40)
		change_scene_to_file(STORE)
		await _wait(1.0)
		await _tap_price("coins_large")
		await _wait(0.7)
		await _shot("short.png")
	if _want("late"):
		_new_save(48210, 2600)
		_late_save(40)
		change_scene_to_file(STORE)
		await _wait(1.0)
		await _shot("store_s3_t40.png")
	_new_save(1250, 1250)
	for open in [true, false]:
		_settings.set("store_open", open)
		var word := "open" if open else "shut"
		if _want("title") or (_want("shut") and not open):
			change_scene_to_file(TITLE)
			await _wait(3.0)
			await _shot("title_%s.png" % word)
		if _want("trail") and open:
			change_scene_to_file(TRAIL)
			await _wait(1.2)
			await _shot("trail_%s.png" % word)
	_settings.set("store_open", true)
	if _want("inset"):
		_settings.set("top_inset", 130)
		change_scene_to_file(STORE)
		await _wait(1.0)
		await _shot("store_inset130.png")
		_settings.set("top_inset", 0)
	if _want("down"):
		await _down()
	_end(0)


## Down! in a run (the arena's start, the panel hidden), the store file's revive at a test price of 50 gems (in memory).
func _down() -> void:
	var packs = load(PACKS)
	var d: Dictionary = packs.read_file(packs.DEFAULT)
	d["revive"] = {"price": 50, "currency": "gems", "per_run": 1}
	packs.load_data(d)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	root.get_node("Run").set("arena_next", true)
	change_scene_to_file("res://game/Game.tscn")
	await _wait(3.0)
	var g = current_scene
	if g == null or g.get("revive_screen") == null:
		print("p149_store_shots: no game")
		return
	g.player.god = true
	g.set_paused(false)
	await _wait(2.5)
	if g.get("arena_panel") and g.arena_panel:
		for c in g.arena_panel.get_children():
			c.visible = false
		g.arena_panel.visible = false
	g.hud._banner.visible = false
	var run = root.get_node("Run")
	run.set("kills", 87)
	for gems in [120, 20]:
		_save.data["wallets"] = {"gems": gems}
		g.set_paused(true)
		g.revive_screen.open(0, 0, "", {"by": "The Tumbleweed King", "kind": "boss", "role": "boss"}, [], packs.revive_for(0, 0))
		g.revive_screen._held = true
		await _wait(0.8)
		await _shot("down_paid.png" if gems >= 50 else "down_paid_short.png")
	g.revive_screen._open = false
	g.revive_screen.visible = false
