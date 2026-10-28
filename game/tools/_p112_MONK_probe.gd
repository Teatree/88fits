## Pass 112 (lane MONK): a headless probe of the Monk in the real game (the debug arena, the real map with its rocks and
## the director's continuous draw): the hero stands in god mode with the Revolver; the director brings a Monk row's squads
## (WaveDirector._burst_from) and the probe prints, every 5 s, the squads, their sizes, the volleys, the spheres and
## the hero's hits.
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/_p112_MONK_probe.gd [-- seconds=40 draws=3]
## A watchdog quits after 200 s; the PC save is put back as it was.
extends SceneTree

var _seconds := 40.0
var _draws := 3
var _weapons := true
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			_seconds = float(a.substr(8))
		elif a.begins_with("draws="):
			_draws = int(a.substr(6))
		elif a == "weapons=0":
			_weapons = false
	seed(112)
	create_timer(200.0, true, false, true).timeout.connect(func() -> void:
		print("p112_probe: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _main() -> void:
	var run = root.get_node("Run")
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	await _frames(120)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if not _weapons:
		run.debug_clear_items()
		run.build_changed.emit()
	g.enemies.kill_all(false)
	await _frames(10)
	var em = g.enemies
	var d = g.director
	var hits0 := int(g.player.get("hits_taken")) if g.player.get("hits_taken") != null else 0
	for k in range(_draws):
		d._burst_from([{"t": 0, "enemy": "monk", "weight": 1}], 200.0, 300)
	var t := 0.0
	var next := 0.0
	var min_nn := INF
	while t < _seconds:
		await _frames(1)
		t += 1.0 / 60.0
		if t >= next:
			next += 5.0
			var sq = em.squads
			var sizes: Array = []
			var dist: Array = []
			for s in sq.list.values():
				sizes.append((s["members"] as PackedInt32Array).size())
				var a: Vector3 = s["anchor"]
				var p: Vector3 = g.player.global_position
				dist.append(snappedf(Vector2(a.x - p.x, a.z - p.z).length() - float(s["radius"]), 0.1))
			var o = sq.orbs
			print("p112_probe: t=%4.1f squads %s edge %s alive %d volleys %d/%d spheres fired %d in the air %d hit %d spent %d kills %d" % [t,
				sizes, dist, em.alive_count(), sq.volleys_started, sq.volleys_fired, o.fired if o else 0, o.count if o else 0,
				o.hits if o else 0, o.spent if o else 0, int(run.kills)])
			for s in sq.list.values():
				var m0: PackedInt32Array = s["members"]
				var mean := Vector3.ZERO
				var rising := 0
				var spd := 0.0
				for i in m0:
					mean += em.pos[i]
					spd += em.speed[i]
					if em.rise_t[i] < 1.0 or em.state[i] == 5:
						rising += 1
				mean /= float(m0.size())
				var a3: Vector3 = s["anchor"]
				print("p112_probe:   squad %d vel %.2f mean speed %.2f rising %d anchor-mean %.2f atk %.2f cd %.2f" % [int(s["id"]),
					(s["vel"] as Vector3).length(), spd / float(m0.size()), rising, Vector2(a3.x - mean.x, a3.z - mean.z).length(),
					float(s["atk"]), float(s["cd"])])
			# the tightest neighbour distance inside a squad that stands
			for s in sq.list.values():
				if (s["vel"] as Vector3).length() < 0.05:
					var m: PackedInt32Array = s["members"]
					for a2 in m:
						for b2 in m:
							if a2 < b2:
								min_nn = minf(min_nn, Vector2(em.pos[a2].x - em.pos[b2].x, em.pos[a2].z - em.pos[b2].z).length())
	print("p112_probe: closest two monks of a standing squad %.2f m" % min_nn)
	save.data = keep
	quit(0)
