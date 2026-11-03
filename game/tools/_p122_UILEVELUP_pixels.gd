## Pass 122 (lane UILEVELUP): the Wanted level-up drawn by the pass 121 CardScreen (OLD_PATH, regenerated on demand: below)
## and by the edited one, the same table, over a flat ground, with everything that moves
## held still (the shine hidden, the reveal's confetti dropped, the rail at t 0 and its process off, the upgrade's star
## pulse off), captured for a pixel-by-pixel comparison (0 differing pixels = the Wanted drawing untouched; the capture
## tool's fresh-seeded world made that proof statistical). Four states each: the cards settled, the second card held, banish
## mode on, the mutation offer landed. Windowed, silent:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --script res://tools/_p122_UILEVELUP_pixels.gd -- out=<dir> [theme=wanted|royale] [twice=1]
## Writes <dir>/old_<state>.png and <dir>/new_<state>.png (twice=1: new2_<state>.png, a second take of the new script, the
## capture's own noise). Every wait is bounded and a watchdog quits after WATCHDOG seconds. The autoloads are reached by
## name at run time (a --script compiles before they exist), the two screens loaded by path.
## The pass 121 CardScreen is not kept in the repo (the lane's review: a frozen copy under res://tools would be parse-checked
## by every ship and read stale once CardScreen.gd changed). It is regenerated on demand into game/tools/_scratch/, a folder
## git ignores by its own .gitignore and Godot by its .gdignore (check_scripts and the editor skip it: no .uid is made,
## nothing is committed), from the last commit before pass 122:
##   mkdir -p game/tools/_scratch && printf '*\n' > game/tools/_scratch/.gitignore && : > game/tools/_scratch/.gdignore
##   git show 2ea06b3:game/ui/CardScreen.gd | sed 's/^class_name CardScreen$/## the pass 121 CardScreen, class_name stripped/' \
##     > game/tools/_scratch/_p122_UILEVELUP_old.gd
## Without it the tool says so and quits 1.
extends SceneTree

const WATCHDOG := 150.0
const OLD_PATH := "res://tools/_scratch/_p122_UILEVELUP_old.gd"
const NEW_PATH := "res://ui/CardScreen.gd"
const GROUND := Color("8a7a5a")

var _out := "user://p122_pixels"
var _theme := "wanted"
var _twice := false
var _started := 0
var _run
var _reg
var _save


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("theme="):
			_theme = a.substr(6)
		elif a == "twice=1":
			_twice = true
	DirAccess.make_dir_recursive_absolute(_out)
	_started = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_watch)


func _watch() -> void:
	if Time.get_ticks_msec() - _started > WATCHDOG * 1000.0:
		print("p122_pixels: watchdog, quitting")
		quit(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _card(type: String, def, from: int, to: int) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


func _main() -> void:
	var old: GDScript = load(OLD_PATH) if FileAccess.file_exists(OLD_PATH) else null
	if old == null or not old.can_instantiate():
		printerr("p122_pixels: no pass 121 CardScreen at ", OLD_PATH, ": regenerate it (this file's header), then run again")
		quit(1)
		return
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	root.get_node("Settings").set("ui_theme", _theme)
	await _frames(2)
	print("p122_pixels: theme ", root.get_node("Settings").get("ui_theme"))
	_run.start(_reg.character("astro"), _reg.map("red_canyon"))
	_run.add_weapon(_reg.weapon("boomstick"), 3)
	var ms: Array = _reg.mutations_of("boomstick")
	if not ms.is_empty():
		_run.debug_set_item("mutation", ms[0].id, 1)
	_run.rerolls_left = 1
	_run.skips_left = 2
	_run.banishes_left = 1
	var takes: Array = [["old", OLD_PATH], ["new", NEW_PATH]]
	if _twice:
		takes.append(["new2", NEW_PATH])
	for t in takes:
		await _take(str(t[0]), str(t[1]))
	quit()


## One script's four states, each captured once settled.
func _take(tag: String, path: String) -> void:
	# the "banish" hint as every take finds it: unseen (banish mode's first line is the longer one, Save.mark_hint)
	var seen: Array = _save.data.get("hints_seen", [])
	seen.erase("banish")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ground := ColorRect.new()
	ground.color = GROUND
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(ground)
	root.add_child(host)
	var script: GDScript = load(path)
	var cs = script.new()
	host.add_child(cs)
	await _frames(2)
	var table := [_card("passive", _reg.passive("bristle"), 0, 1), _card("passive", _reg.passive("desperado"), 0, 1),
		_card("weapon", _reg.weapon("boomstick"), 3, 4)]
	# the cards settled
	cs.show_offer(table, "LEVEL 3!", false)
	await _still(cs)
	await _shot(tag + "_levelup")
	# the second card held
	cs._cards[1].show_held(true)
	await _still(cs)
	await _shot(tag + "_held")
	cs._cards[1].show_held(false)
	# banish mode
	cs._toggle_banish()
	await _still(cs)
	await _shot(tag + "_banish")
	cs._set_banish(false)
	# the mutation offer landed
	var w = _run.weapon_instance("boomstick")
	var offer: Array = load("res://core/systems/CardPool.gd").path_offer(w)
	cs.show_offer(offer, "MUTATION", false, true)
	cs.skip_reel()
	var n := 0
	while (cs.reel_running() or (cs._cards as Array).is_empty()) and n < 240:
		await process_frame
		n += 1
	await _still(cs)
	await _shot(tag + "_path")
	cs.visible = false
	host.queue_free()
	await _frames(3)


## Everything that moves held still, the tweens given their time (the dim's fade, the header's drop, the title's stamp,
## the cards' drops): the shine hidden, the confetti dropped, the stars' pulse off, the rail at t 0 with its process off.
func _still(cs) -> void:
	await _wait(1.2)
	cs.shine().visible = false
	for c in cs.get_children():
		var sc: Script = c.get_script()
		if sc and str(sc.get_global_name()) == "WCelebrate":
			c.queue_free()
	for card in cs._cards:
		if is_instance_valid(card) and card.marks:
			card.marks.pulse = false
			card.marks.queue_redraw()
	cs.set_process(false)
	cs._rail_t = 0.0
	cs._rail.queue_redraw()
	await _frames(3)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p122_pixels: ", name)
