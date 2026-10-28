## A headless run through the debug arena (pass 33.4): opens it from the title's flag, checks its field of training
## dummies (pass 48: as many as the developer menu says, in rows north of the hero; undying ones never fall, ones with
## health fall without a drop and stand up again on their spot), goes through every tab of the
## panel, spawns one of every creature, a crowd and a swarm, runs and holds the director, hands over and takes back
## items, drops every power-up, levels the hero, and leaves; the save must come back as it was. Prints ARENA OK or the
## step that failed; SCRIPT ERROR lines point at the code.
## Pass 49: the Elite dummy (a crown) and the Boss dummy (a skull) stand apart from the field; with the patrol on a field
## dummy walks along its row; a melee and a ranged attacker added by the hero turn god mode off, the melee one bites and
## the ranged one winds up its spit; a death in the arena respawns him at once on the start spot with no Down! screen;
## the ITEMS tab draws a weapon's stack open and hands over a weapon's mutations and evolution.
## Pass 55: the HERO tab swaps in every hero in play and back (his trait on the sheet, his strip on the Player), shows
## every look of every hero that has more than one, keeps one (Save.hero_look, past the sandbox) and puts the kept look
## back as it was; a stand-in second look is lent to the first hero when no hero has two yet.
## Pass 110 (lane ARENA): the SHOTS controls: a crowd of 2,000 Lesser Scorpions in a ring (the pool grows past the run's
## 320, nobody inside the clear circle), the freeze (a second later nobody has moved, every one still alive turned to the
## hero, a hit still kills), the speed buttons and keys (Engine.time_scale), the framing (the hero's middle at the share
## asked), hiding the HUD and the controls and the corner that brings them back; the rest of the check runs on the grown
## pool.
##   "$GODOT" --headless --path game --script res://tools/arena_check.gd
extends SceneTree

var _t := 0.0
var _step := 0
var _game: Node
var _save_before := ""
var _errors: Array = []
var _dummy_spot := Vector3.INF   # the spot of the dummy felled in step 10 (pass 48)
var _pickups_before := 0
# pass 49: the patrolling dummy watched in steps 11-12, where it started, the ranged attacker and whether it wound up
var _patroller := -1
var _patrol_from := Vector3.ZERO
var _ranged_i := -1
var _saw_windup := false
var _hp_before := 0.0
var _patrol_along := 0.0
var _patrol_off := 0.0


func _initialize() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var save = root.get_node("Save")
	# pass 69 (lane UI): the arena is entered from the title, whose quiet quest check (QuestTracker.check_all(false))
	# completes the quests the save's totals already meet; leaving the arena opens the title, which runs it again. A quest
	# new to the content that this save already meets (a hero's unlock_<id>: 2,500 kills, the Tumbleweed King killed)
	# completes there, not in the arena: the check runs first, as the title would have before the arena
	load("res://core/systems/QuestTracker.gd").call("check_all", false)
	# the settings as a write would keep them now (pass 49: a setting added since the file was last written is not a change
	# made in the arena; leaving it writes Settings.to_dict() whatever happened)
	var before: Dictionary = (save.data as Dictionary).duplicate(true)
	before["settings"] = root.get_node("Settings").to_dict()
	_save_before = JSON.stringify(before, "", true)
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
				# the run recorder (pass 45) is never created for the arena
				if _game.get_node_or_null("RunAnalytics") != null:
					_fail("the arena has a run recorder")
				_dummy_checks()
				_step = 10
				_t = 0.0
		10:
			# a dummy with health that falls stands up again on its spot five seconds later, and dropped nothing
			if _t > 5.6:
				var back := false
				for i in range(_game.enemies.MAX):
					if _game.enemies.is_alive(i) and _game.enemies.is_dummy(i) and Vector2(_game.enemies.pos[i].x - _dummy_spot.x, _game.enemies.pos[i].z - _dummy_spot.z).length() < 0.6:
						back = true
				if not back:
					_fail("a felled dummy did not stand up again on its spot")
				var now: int = _game.pickups.count + _game.pickups.specials.size()
				if now > _pickups_before:
					_fail("a dummy dropped something (%d pickups, %d before)" % [now, _pickups_before])
				print("arena_check: dummies: a felled one stood up again: %s; standing %d" % [str(back), _game.dummies_standing()])
				# back to the developer menu's field
				var settings = root.get_node("Settings")
				_game.arena_dummies(int(settings.dummy_count), int(settings.dummy_hp))
				_attack_start()
				_step = 11
				_t = 0.0
		11:
			# pass 49: watch the ranged attacker wind up (state 1, STATE_WINDUP) and the patroller walk its row while the
			# attackers do their work: how far it got along the row, and how far off it
			var em11 = _game.enemies
			if _ranged_i >= 0 and em11.is_alive(_ranged_i) and em11.state[_ranged_i] == 1:
				_saw_windup = true
			if _patroller >= 0 and em11.is_alive(_patroller):
				_patrol_along = maxf(_patrol_along, absf(em11.pos[_patroller].x - _patrol_from.x))
				_patrol_off = maxf(_patrol_off, absf(em11.pos[_patroller].z - _patrol_from.z))
			if _t > 4.5:
				_attack_checks()
				_shots_start()
				_step = 20
				_t = 0.0
		20:
			# pass 110: the frozen crowd a second (and a half) later
			if _t > 1.5:
				_shots_checks()
				_step = 1
		1:
			var p = _game.arena_panel
			# a weapon's stack open on ITEMS (pass 49): its mutations and evolution drawn under it (pass 76: the Skull Rain's,
			# the Peashooter is hidden)
			p._open["stack:skull_rain"] = true
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
				# items: every section's first item to max, a weapon's whole stack with it (pass 49: its mutations and
				# evolution sit under it), then everything away
				for s in p3.item_sections():
					var defs: Array = s[2]
					if not defs.is_empty():
						run.debug_set_item(str(s[1]), defs[0].id, 99)
						if str(s[1]) == "weapon":
							for entry in p3.weapon_stack(defs[0]):
								run.debug_set_item(str(entry[0]), entry[1].id, 99)
				print("arena_check: items held ", run.weapons.size(), " weapons, ", run.passives.size(), " passives, ", run.perks.size(), " perks")
				# every item's INFO (pass 51): what a player reads about it builds for everything in the tab, held or not
				var texts := 0
				for s2 in p3.item_sections():
					for d2 in s2[2]:
						var rows2: Array = [[str(s2[1]), d2]]
						if str(s2[1]) == "weapon":
							for entry2 in p3.weapon_stack(d2):
								rows2.append([str(entry2[0]), entry2[1]])
						for r2 in rows2:
							var tx: Array = p3.item_texts(str(r2[0]), r2[1])
							if tx.is_empty() or str((tx[0] as Array)[1]).strip_edges() == "":
								_fail("no INFO for %s %s" % [str(r2[0]), r2[1].id])
							texts += 1
				print("arena_check: INFO built for ", texts, " items")
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
				_hero_checks()
				print("arena_check: level ", root.get_node("Run").level, ", leaving")
				_game.leave_arena()
				_step = 5
				_t = 0.0
		5:
			if _t > 1.5:
				var after := JSON.stringify(root.get_node("Save").data, "", true)
				# the values, not their spelling (a whole number read back from the file is a float); the write's own clock
				# (saved_at, pass 45) moves when the sandbox closes and is no change
				var a: Dictionary = JSON.parse_string(_save_before)
				var b: Dictionary = JSON.parse_string(after)
				a.erase("saved_at")
				b.erase("saved_at")
				if JSON.stringify(a, "", true) != JSON.stringify(b, "", true):
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


## The arena's field of training dummies (pass 48): the developer menu's count (never fewer than ten) in rows of five
## north of the hero; an undying one takes a killing hit and stands; then a field with health, one felled (step 10
## checks it stands up again and dropped nothing). Pass 49: the Elite dummy and the Boss dummy stand apart beside it, so
## the field is told by its role (Game.dummy_role).
func _dummy_checks() -> void:
	var settings = root.get_node("Settings")
	var em = _game.enemies
	var want: int = maxi(int(settings.dummy_count), 10)
	var ids := _field(em)
	print("arena_check: dummies standing %d (the menu says %d, health %d)" % [ids.size(), int(settings.dummy_count), int(settings.dummy_hp)])
	if ids.size() != want or int(_game.dummies_standing()) != want:
		_fail("%d dummies on the field, the menu says %d" % [ids.size(), want])
	var hero: Vector3 = _game.player.global_position
	for i: int in ids:
		if em.pos[i].z > hero.z - 6.0:
			_fail("a dummy stands less than 7 m north of the hero")
			break
	_big_dummy_checks(em, ids)
	_game.arena_dummies(10, 0)
	var undying := _field(em)
	var u: int = undying[0] if not undying.is_empty() else -1
	if u < 0:
		_fail("no undying dummy")
	else:
		em.damage(u, 1000000.0, "arena_check")
		if not em.is_alive(u) or em.hp[u] < em.max_hp[u]:
			_fail("an undying dummy fell or stayed hurt")
	_game.arena_dummies(10, 40)
	_pickups_before = _game.pickups.count + _game.pickups.specials.size()
	for i: int in _field(em):
		_dummy_spot = em.pos[i]
		em.damage(i, 1000.0, "arena_check")
		if em.is_alive(i):
			_fail("a dummy with 40 HP took 1000 and stood")
		break


## The field's dummies standing, by index.
func _field(em) -> Array:
	var out: Array = []
	for i in range(em.MAX):
		if em.is_alive(i) and str(_game.dummy_role(i)) == "field":
			out.append(i)
	return out


## Pass 49: the Elite dummy wears the crown and the Boss dummy the skull, both big game, neither the run's boss, both
## standing apart from the field.
func _big_dummy_checks(em, field: Array) -> void:
	var e: int = _game.dummy_index("elite")
	var s: int = _game.dummy_index("boss")
	if e < 0 or s < 0:
		_fail("the Elite dummy or the Boss dummy is not standing")
		return
	if str(em.badge_of(e)) != "crown" or str(em.badge_of(s)) != "skull":
		_fail("the Elite dummy wears '%s' and the Boss dummy '%s'" % [em.badge_of(e), em.badge_of(s)])
	if not em.is_big_game(e) or not em.is_big_game(s):
		_fail("the Elite or the Boss dummy is not big game")
	if int(em.boss_index) >= 0:
		_fail("a dummy is the run's boss")
	for i: int in field:
		for b: int in [e, s]:
			if Vector2(em.pos[i].x - em.pos[b].x, em.pos[i].z - em.pos[b].z).length() < 2.0:
				_fail("the Elite or the Boss dummy stands in the field")
				return
	print("arena_check: the Elite dummy (%s, %.0f HP) and the Boss dummy (%s, %.0f HP) stand apart" % [em.badge_of(e), em.max_hp[e], em.badge_of(s), em.max_hp[s]])


## Pass 49: the patrol on (a field dummy to watch), god mode on, then a melee and a ranged attacker by the hero; god mode
## has to go off with them.
var _patrol_keep := false


func _attack_start() -> void:
	var settings = root.get_node("Settings")
	var em = _game.enemies
	# his gun away first: a shot's shove (or the Gravity Gun's throw) would knock the patroller off its row and the
	# melee attacker out of reach
	root.get_node("Run").debug_clear_items()
	_patrol_keep = bool(settings.dummy_patrol)
	settings.dummy_patrol = true
	_game.apply_dummy_settings()
	var ids := _field(em)
	if not ids.is_empty():
		_patroller = ids[0]
		_patrol_from = em.pos[_patroller]
	var p = _game.player
	p.god = true
	_hp_before = float(p.hp)
	var m: int = _game.add_attacker("melee")
	_ranged_i = _game.add_attacker("ranged")
	if m < 0 or _ranged_i < 0:
		_fail("an attacker could not be added")
	if p.god:
		_fail("god mode stayed on with attackers on the field")
	if _ranged_i >= 0:
		# its next spit due now
		em.cooldown[_ranged_i] = 0.0
	print("arena_check: attackers %d melee, %d ranged; patrol on" % [_game.attackers_standing("melee"), _game.attackers_standing("ranged")])


## Pass 49, 4.5 s later: the patroller walked along its row, the melee attacker bit (or the hero fell and stood up again),
## the ranged one wound up; then a death respawns him at once on the start spot with no Down! screen; then all put back.
func _attack_checks() -> void:
	var em = _game.enemies
	var p = _game.player
	if _patroller >= 0 and em.is_alive(_patroller):
		if _patrol_along < 1.0 or _patrol_off > 0.4:
			_fail("a patrolling dummy did not walk its row (%.2f along at most, %.2f off)" % [_patrol_along, _patrol_off])
	else:
		_fail("no patrolling dummy to watch")
	var bitten := false
	for row in p.damage_log:
		if str(row.get("id", "")) == "training_dummy_melee":
			bitten = true
	if not bitten and int(_game.arena_respawns) == 0:
		_fail("the melee attacker never bit (%.0f HP, was %.0f)" % [float(p.hp), _hp_before])
	if not _saw_windup:
		_fail("the ranged attacker never wound up a spit")
	# a death in the arena: up again at once, whole, on the start spot, no Down! screen
	var before: int = int(_game.arena_respawns)
	p.god = false
	p.invuln = 0.0
	p.shield_t = 0.0
	p.shield_pts = 0.0
	p.take_damage(float(p.hp) + 99999.0, p.global_position + Vector3(1, 0, 0), {"by": "arena_check", "kind": "melee", "fx": []})
	if p.dead or int(_game.arena_respawns) != before + 1:
		_fail("an arena death did not respawn the hero")
	if float(p.hp) < float(p.max_hp):
		_fail("the hero respawned hurt (%.0f of %.0f)" % [float(p.hp), float(p.max_hp)])
	if _game.revive_screen.visible:
		_fail("an arena death opened Down!")
	var start: Vector3 = _game.map.player_start()
	if Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length() > 0.5:
		_fail("the hero respawned away from the start spot")
	print("arena_check: patrol %.2f m along its row, bitten %s, a spit wound up %s, respawns %d" % [_patrol_along, str(bitten), str(_saw_windup), int(_game.arena_respawns)])
	# put back: no attackers, the patrol as it was, god mode on
	_game.remove_attackers()
	if int(_game.attackers_standing()) != 0:
		_fail("REMOVE ATTACKERS left some")
	root.get_node("Settings").dummy_patrol = _patrol_keep
	_game.apply_dummy_settings()
	p.god = true


## Pass 110 (lane ARENA): the SHOTS tab's crowd and controls through the panel's own calls. A ring of 2,000 Lesser
## Scorpions round the hero with a 4 m clear circle (the pool grows), frozen walking in place; the speed by the panel and
## by the keys; the framing; hiding everything and the corner. _shots_checks reads the crowd a moment later.
var _shots_pos: Dictionary = {}
var _shots_victim := -1


func _shots_start() -> void:
	var p = _game.arena_panel
	var em = _game.enemies
	var hero: Vector3 = _game.player.global_position
	p.set_freeze(1)
	var came: int = p.mass_spawn([["lesser_scorpion", ""]], 2000, {"layout": "ring", "clear_r": 4.0, "seed": 7})
	print("arena_check: SHOTS ring of %d Lesser Scorpions came, alive %d, pool %d (a run's %d)" % [came, em.count_alive, em.pool_max, em.MAX])
	if came < 1900 or em.pool_max < 2000:
		_fail("a ring of 2000 brought %d (pool %d)" % [came, em.pool_max])
	var inside := 0
	for i in range(em.pool_max):
		if em.is_alive(i):
			_shots_pos[i] = em.pos[i]
			if Vector2(em.pos[i].x - hero.x, em.pos[i].z - hero.z).length() < 3.9:
				inside += 1
	if inside > 0:
		_fail("%d creatures inside the ring's clear circle" % inside)
	# the speed: the buttons' call and the keys (1, 2, 4)
	p.set_speed(0.5)
	if not is_equal_approx(Engine.time_scale, 0.5):
		_fail("half speed left the clock at %.2f" % Engine.time_scale)
	for pair in [[KEY_4, 0.25], [KEY_1, 1.0]]:
		var k := InputEventKey.new()
		k.keycode = pair[0]
		k.pressed = true
		p.arena_key(k)
		if not is_equal_approx(Engine.time_scale, float(pair[1])):
			_fail("key %d left the clock at %.2f" % [int(pair[0]), Engine.time_scale])
	# the framing: the hero's middle at the share asked
	p.set_band(0.3)
	p.set_framing(true)
	if absf(float(_game.camera.frame_hero_y) - 0.35) > 0.001:
		_fail("the framing asked for %.3f" % float(_game.camera.frame_hero_y))


func _shots_checks() -> void:
	var p = _game.arena_panel
	var em = _game.enemies
	var hero: Vector3 = _game.player.global_position
	var moved := 0
	var turned := 0
	var asked := 0
	var still := 0
	for i in _shots_pos.keys():
		if not em.is_alive(i) or em.state[i] == 3:
			continue
		still += 1
		if Vector2(em.pos[i].x - (_shots_pos[i] as Vector3).x, em.pos[i].z - (_shots_pos[i] as Vector3).z).length() > 0.02:
			moved += 1
		# facing the hero: one well off to the side mirrors towards him (flip 1 = heading screen-left)
		var dx: float = hero.x - em.pos[i].x
		if absf(dx) > 3.0 and absf(hero.z - em.pos[i].z) < 2.0:
			asked += 1
			if (em.flip[i] == 1) == (dx < 0.0):
				turned += 1
		if _shots_victim < 0 and em.is_dummy(i) == false:
			_shots_victim = i
	print("arena_check: SHOTS frozen: %d standing, %d moved, %d of %d beside the hero face him" % [still, moved, turned, asked])
	if moved > 0:
		_fail("%d frozen creatures moved" % moved)
	if asked > 0 and turned < asked:
		_fail("%d of %d frozen creatures beside the hero do not face him" % [asked - turned, asked])
	if _shots_victim >= 0:
		em.damage(_shots_victim, 1.0e9, "arena_check")
		if em.is_alive(_shots_victim) and em.state[_shots_victim] != 3:
			_fail("a frozen creature took a killing hit and stood")
	# the framing held: the hero's middle at 35 % of the screen's height
	var cam: Camera3D = _game.camera.camera
	var vs: Vector2 = cam.get_viewport().get_visible_rect().size
	var sy: float = cam.unproject_position(hero + Vector3(0, 0.9, 0)).y / maxf(vs.y, 1.0)
	print("arena_check: SHOTS framing: the hero's middle at %.1f%% of the height (35%% asked)" % (sy * 100.0))
	if absf(sy - 0.35) > 0.02:
		_fail("the framed hero's middle sits at %.3f of the height, 0.35 asked" % sy)
	# hiding everything, and the corner bringing it back
	p.set_clean(true)
	if _game.hud.visible or p._col.visible or not p._corner.visible:
		_fail("HIDE left the HUD (%s) or the column (%s) up, or no corner (%s)" % [str(_game.hud.visible), str(p._col.visible), str(p._corner.visible)])
	p._corner.pressed.emit()
	if _game.hud.clean_hidden or not p._col.visible or p._corner.visible:
		_fail("the corner did not bring the controls back")
	var kf := InputEventKey.new()
	kf.keycode = KEY_F
	kf.pressed = true
	p.arena_key(kf)
	if int(em.crowd_freeze) != 0:
		_fail("F did not let the crowd go")
	p.set_framing(false)
	if float(_game.camera.frame_hero_y) >= 0.0:
		_fail("the framing stayed on")
	p.set_freeze(0)
	p._clear_field()


## Pass 55, the HERO tab through the panel's own calls: every hero in play swapped in (the run's hero, the Player's def,
## the strip he is drawn with, his max health off the sheet) and the first one back; every look of a hero that has more
## than one shown on him (the look code and the texture); one kept (Save.hero_look, and in the copy the sandbox puts
## back) and the kept look put back as it was.
func _hero_checks() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var save = root.get_node("Save")
	var panel = _game.arena_panel
	var p = _game.player
	var first = run.character
	var swaps := 0
	for c in reg.sorted_characters() + [first]:
		if run.character == c:
			continue
		panel.swap_hero(c.id)
		var drawn = (p.sprite.material_override as ShaderMaterial).get_shader_parameter("sprite")
		if run.character != c or p.character != c or p.look == null or drawn != p.look.sprite:
			_fail("the HERO tab did not swap in %s" % c.id)
		elif not is_equal_approx(float(p.max_hp), float(run.player_sheet.get_stat("max_hp", 0.0))):
			_fail("%s's max health is %.1f, his sheet says %.1f" % [c.id, float(p.max_hp), float(run.player_sheet.get_stat("max_hp", 0.0))])
		swaps += 1
	if run.character != first:
		_fail("the first hero did not come back")
	# every look of every hero that has more than one, worn on the Player
	var looks := 0
	var lent := false
	var keep_variants: Dictionary = first.variants
	var keep_variant: String = first.variant
	var with_looks: Array = reg.sorted_characters().filter(func(c) -> bool: return not c.variant_codes().is_empty())
	if with_looks.is_empty():
		# none painted yet: a stand-in second look on the first hero, so the keep below has something to keep
		var art := {"sprite": first.sprite, "sprite_file": first.sprite_file, "anims": first.anims, "fps": first.fps,
			"strip_cols": first.strip_cols, "frame_px": first.frame_px, "icon": first.icon, "note": "stand-in (arena_check)"}
		first.variants = {"CHECK-A": art, "CHECK-B": art.duplicate()}
		first.variant = "CHECK-A"
		with_looks = [first]
		lent = true
	var keeper = with_looks[0]
	var kept_raw: String = save.hero_look(keeper.id)
	var last_code := ""
	for c in with_looks:
		if run.character != c:
			panel.swap_hero(c.id)
		for code in c.variant_codes():
			panel.show_look(str(code))
			var want: Texture2D = c.variant_def(str(code)).sprite
			var drawn2 = (p.sprite.material_override as ShaderMaterial).get_shader_parameter("sprite")
			if p.look_code() != str(code) or drawn2 != want:
				_fail("%s's look %s is not on him (%s)" % [c.id, str(code), p.look_code()])
			looks += 1
			last_code = str(code)
		if c == keeper:
			# keep the last one shown, then the kept look as it was
			panel.keep_look()
			var backup = save.get("_sandbox_backup")
			if save.hero_look(c.id) != last_code:
				_fail("USE FROM NOW ON did not keep %s for %s" % [last_code, c.id])
			elif not (backup is Dictionary and str((backup as Dictionary).get("hero_look", {}).get(c.id, "")) == last_code):
				_fail("the kept look %s is not in the copy the sandbox puts back" % last_code)
			save.set_hero_look(c.id, kept_raw)
		p.show_look("")
	if lent:
		first.variants = keep_variants
		first.variant = keep_variant
	if run.character != first:
		panel.swap_hero(first.id)
	p.show_look("")
	if save.hero_look(keeper.id) != kept_raw:
		_fail("the kept look of %s was not put back (%s, was %s)" % [keeper.id, save.hero_look(keeper.id), kept_raw])
	print("arena_check: heroes swapped %d times, %d looks shown%s, one kept and put back" % [swaps, looks, " (a stand-in pair)" if lent else ""])


func _finish() -> void:
	# no run file from this process (its header would carry the pid): the arena does not record
	var dir := "user://analytics/runs"
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".json") or FileAccess.get_modified_time(dir.path_join(f)) < int(Time.get_unix_time_from_system()) - 600:
				continue
			var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
			if fa == null:
				continue
			var doc = JSON.parse_string(fa.get_as_text())
			fa.close()
			if doc is Dictionary and int(doc.get("pid", -1)) == OS.get_process_id():
				_fail("the arena wrote a run file: " + f)
	if _errors.is_empty():
		print("arena_check: ARENA OK")
		quit(0)
	else:
		print("arena_check: ", _errors.size(), " failures")
		quit(1)
