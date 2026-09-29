## A headless run through the debug arena (pass 33.4): opens it from the title's flag, goes through every tab of the
## panel, spawns one of every creature, a crowd and a swarm, runs and holds the director, hands over and takes back
## items, drops every power-up, levels the hero, and leaves; the save must come back as it was. Prints ARENA OK or the
## step that failed; SCRIPT ERROR lines point at the code.
##   "$GODOT" --headless --path game --script res://tools/arena_check.gd
extends SceneTree

var _t := 0.0
var _step := 0
var _game: Node
var _save_before := ""
var _errors: Array = []


func _initialize() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var save = root.get_node("Save")
	_save_before = JSON.stringify(save.data, "", true)
	root.get_node("Run").arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _fail(msg: String) -> void:
	_errors.append(msg)
	print("arena_check: FAIL ", msg)


func _tick() -> void:
	_t += root.get_process_delta_time()
	match _step:
		0:
			if _t > 1.5:
				_game = current_scene
				if _game == null or _game.get("arena_panel") == null:
					_fail("no arena panel")
					_finish()
					return
				if not root.get_node("Run").arena:
					_fail("Run.arena is off")
				if _game.director.running:
					_fail("the director runs in an empty arena")
				_step = 1
		1:
			var p = _game.arena_panel
			for tab in ["enemy", "waves", "items", "hero", "drops", "world"]:
				p.open()
				p._tab = tab
				p._refresh()
			p.close()
			# one of every creature, a boss last
			var bosses: Array = []
			for g in p.enemy_groups():
				for def in g[1]:
					if def.archetype == "boss":
						bosses.append(def)
						continue
					p._count = 1
					p.spawn_enemy(def)
			# every art variant too (pass 34): each spawns under its own type and draws its own sheet
			var nvar := 0
			var reg = root.get_node("Registry")
			for ed in reg.enemies.values():
				for code in ed.variant_codes():
					p._count = 1
					p.spawn_enemy(ed.variant_def(str(code)))
					nvar += 1
			print("arena_check: spawned the whole cast and %d art variants, alive %d, types %d" % [nvar, _game.enemies.count_alive, _game.enemies.types.size()])
			if bosses.size() > 0:
				p.spawn_enemy(bosses[0])
			_step = 2
			_t = 0.0
		2:
			if _t > 1.0:
				var p2 = _game.arena_panel
				p2._clear_field()
				p2.set_clock(8.0)
				p2.crowd(120)
				p2._last_enemy = "goblin"
				p2.swarm(50)
				print("arena_check: crowd and swarm, alive ", _game.enemies.count_alive)
				if _game.enemies.count_alive < 100:
					_fail("the crowd and the swarm brought too few (%d)" % _game.enemies.count_alive)
				p2.run_director()
				_step = 3
				_t = 0.0
		3:
			if _t > 2.0:
				var p3 = _game.arena_panel
				var run = root.get_node("Run")
				if run.elapsed < 8.0 * 60.0 + 1.0:
					_fail("the director did not run its clock (%.1f)" % run.elapsed)
				p3.hold_director()
				# items: every section's first item to max, then everything away
				for s in p3.item_sections():
					var defs: Array = s[2]
					if not defs.is_empty():
						run.debug_set_item(str(s[1]), defs[0].id, 99)
				print("arena_check: items held ", run.weapons.size(), " weapons, ", run.passives.size(), " passives, ", run.lines.size(), " lines")
				p3._levels(10)
				for def in root.get_node("Registry").pickups.values():
					p3._drop_pickup(def)
				p3._act("chest", func() -> void: _game.pickups.spawn_chest(p3._drop_point(3.0)))
				p3._do_again()
				p3._shower(0, 20, 5.0)
				run.debug_clear_items()
				_step = 4
				_t = 0.0
		4:
			if _t > 1.0:
				print("arena_check: level ", root.get_node("Run").level, ", leaving")
				_game.leave_arena()
				_step = 5
				_t = 0.0
		5:
			if _t > 1.5:
				var after := JSON.stringify(root.get_node("Save").data, "", true)
				# the values, not their spelling (a whole number read back from the file is a float)
				if JSON.stringify(JSON.parse_string(after), "", true) != JSON.stringify(JSON.parse_string(_save_before), "", true):
					var a: Dictionary = JSON.parse_string(_save_before)
					var b: Dictionary = JSON.parse_string(after)
					var diff: Array = []
					for k in a.keys():
						if not b.has(k):
							diff.append("%s: removed" % k)
					for k in b.keys():
						if not a.has(k) or JSON.stringify(a[k], "", true) != JSON.stringify(b[k], "", true):
							diff.append("%s: %s -> %s" % [k, JSON.stringify(a.get(k, null)).left(120), JSON.stringify(b[k]).left(120)])
					_fail("the save changed in the arena: " + "; ".join(diff))
				if root.get_node("Run").arena:
					_fail("Run.arena still on after leaving")
				_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("arena_check: ARENA OK")
		quit(0)
	else:
		print("arena_check: ", _errors.size(), " failures")
		quit(1)
