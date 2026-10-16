## Pass 83 lane META scratch probe: the Drifter stands still in the crowd from the run's start (no steering: the
## face-tank a Thorns board invites), the Upgrade board's Spite at `ranks` ranks of Thorns (form 0) and nothing else;
## his HP is refilled below 40 % so the window plays out. Reports thorns damage against the weapons' over `secs` of play.
##   bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/_p83_META_thorns.gd -- ranks=6 secs=240
extends SceneTree

var _ranks := 6
var _secs := 240.0
var _seed := 11
var _game: Node
var _run: Node
var _t := 0.0
var _refills := 0
var _hits := 0
var _marks: Array = [60.0, 120.0, 180.0, 240.0, 300.0, 420.0]
var _wall := 0.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"ranks": _ranks = int(kv[1])
			"secs": _secs = float(kv[1])
			"seed": _seed = int(kv[1])
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var save := root.get_node_or_null("Save")
	_run = root.get_node_or_null("Run")
	if save == null or _run == null:
		quit(2)
		return
	save.begin_sandbox()
	save.data["runs_started"] = 1
	var talents := {}
	if _ranks > 0:
		var picks: Array = []
		for _r in range(_ranks):
			picks.append(0)
		talents["spite"] = {"picks": picks, "rank": _ranks, "form": 0}
	save.data["talents"] = talents
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false, "sim_clock": true}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	_wall += root.get_process_delta_time()
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null:
			return
		_game = g
		_game.player.hit.connect(func(): _hits += 1)
		print("probe: thorns stat %.1f" % _run.player_sheet.get_stat("thorns", 0.0))
	_screens()
	var p = _game.player
	if p.dead:
		p.revive()
		p.hp = p.max_hp
		_refills += 1
	elif p.hp < p.max_hp * 0.4:
		p.hp = p.max_hp
		_refills += 1
	var t: float = _run.elapsed
	if not _marks.is_empty() and t >= float(_marks[0]):
		_marks.pop_front()
		_line(t)
	if t >= _secs or _wall > 1500.0:
		_line(t)
		quit(0)


func _line(t: float) -> void:
	var th := float(_run.damage_by_weapon.get("thorns", 0.0))
	var all := 0.0
	for k in _run.damage_by_weapon.keys():
		all += float(_run.damage_by_weapon[k])
	print("probe: RANKS %d t %.0f | thorns %.0f of %.0f = %.1f%% | revolver %.0f | kills %d | hits %d refills %d level %d" % [_ranks, t, th, all,
		100.0 * th / maxf(all, 1.0), float(_run.damage_by_weapon.get("revolver", 0.0)), int(_run.kills), _hits, _refills, int(_run.level)])


func _screens() -> void:
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		_game.chest_screen._finish(true)
	if _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible:
		_game.resume_gate.tap()
	if _game.get("stranger_screen") and _game.stranger_screen and _game.stranger_screen.visible:
		_game.stranger_screen._finish(false)
	if _game.get("structure_shop") and _game.structure_shop and _game.structure_shop.visible:
		_game.structure_shop._finish(false)
	if _game.get("totem_screen") and _game.totem_screen and _game.totem_screen.visible and not _game.totem_screen._done:
		var tp: Array = _game.totem_screen.planks()
		if not tp.is_empty():
			_game.totem_screen._pick(tp[0])
	if _game.portal_dialog and _game.portal_dialog.visible:
		_game.portal_dialog.visible = false
		_game.portal_dialog.decided.emit(false)
