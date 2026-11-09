## Pass 137 (lane ENV; Garry: "Slight colour differences on the environment art ... subtle but noticeable when two stand
## next to each other"): the scenery's tints seen by the game's real camera in the debug arena, for one map seed. The tool
## finds the spots where several props of one painting stand together (the most same-looking neighbours within 5 m, one
## spot a group: rocks, bushes, dead wood, cacti, trees, bones; at least 18 m apart), then captures each spot in the stages
## named (the stage's filter and weather over the arena's map: the arena stands in Sundown, so its paintings are Sundown's),
## the wind held still and the outlaw hidden, so a "before" and an "after" run of the same seed frame the same props.
## Windowed:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --log-file <abs> --script res://tools/_p137_ENV_shots.gd -- out=<dir> tag=before|after [seed=7] [stages=1,2,3]
##     [spots=6] [zoom=0.55] [plain=1]
## plain=1 also captures each spot with every painting's tint off (the paintings as painted). Writes <out>/<tag>_spots.txt
## (each spot's props, painting, place and tint code). Frame cap and watchdog bound it; the save in memory goes back as it
## was (the arena's sandbox keeps it off the disk).
extends SceneTree

const GROUPS := {
	"rocks": ["rock_small", "rock_big", "boulder"],
	"bushes": ["desert_bush", "creosote_bush", "brittlebush", "dead_shrub"],
	"deadwood": ["dead_tree"],
	"cacti": ["saguaro_big", "saguaro_small", "barrel_cactus", "agave", "ocotillo"],
	"trees": ["mesquite_tree", "palo_verde", "joshua_tree", "fan_palm"],
	"bones": ["skull", "skull_small", "bones"],
}
const NEAR := 5.0

var A: Dictionary = {}
var g = null
var _frames := 0
var _ended := false
var _save = null
var _keep: Dictionary = {}
var _out := ""
var _tag := "shot"
var _seed := 7


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = str(A.get("out", "D:/_projects/88fits/tools/dl/p137/ENV/shots"))
	_tag = str(A.get("tag", "shot"))
	_seed = int(A.get("seed", 7))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(float(A.get("watchdog", 280.0)), true, false, true).timeout.connect(_finish.bind(2))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > 30000:
		_finish(2)


func _finish(code: int) -> void:
	if _ended:
		return
	_ended = true
	print("env_shots: finish ", code)
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	quit(code)


func _wait(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := _out.path_join("%s_s%d_%s.png" % [_tag, _seed, name])
	root.get_texture().get_image().save_png(path)
	print("env_shots: ", path)


func _go(x: float, z: float) -> void:
	g.player.global_position = Vector3(x, g.map.height_at(x, z) + 0.5, z)
	g.camera.snap_to(g.player)
	await _wait(6)


func _group_of(kind: String) -> String:
	for gname: String in GROUPS.keys():
		if (GROUPS[gname] as Array).has(kind):
			return gname
	return ""


## The spots: per group, the prop with the most same-painting neighbours within NEAR (ties: the nearer neighbours), its
## cluster's middle; groups by their best count, at most `n`, each at least 18 m from the others.
func _spots(props, n: int) -> Array:
	var rows: Array = props.placed
	var best := {}
	for k in rows.size():
		var r: Dictionary = rows[k]
		var gname := _group_of(str(r["id"]))
		if gname == "":
			continue
		var at: Vector3 = r["pos"]
		var near: Array = [at]
		for j in rows.size():
			if j == k or str(rows[j]["look"]) != str(r["look"]):
				continue
			var p: Vector3 = rows[j]["pos"]
			if Vector2(p.x - at.x, p.z - at.z).length() < NEAR:
				near.append(p)
		var c := Vector3.ZERO
		for p: Vector3 in near:
			c += p
		c /= float(near.size())
		var score := float(near.size())
		if near.size() < 2:
			continue
		var cand := {"group": gname, "look": str(r["look"]), "score": score, "center": c, "count": near.size()}
		if not best.has(gname):
			best[gname] = []
		(best[gname] as Array).append(cand)
	# the best of each group first, then the next best of any group, each at least 14 m from the others
	var firsts: Array = []
	var rest: Array = []
	for gname: String in best.keys():
		var l: Array = best[gname]
		l.sort_custom(func(a, b) -> bool: return float(a["score"]) > float(b["score"]))
		firsts.append(l[0])
		rest.append_array(l.slice(1))
	firsts.sort_custom(func(a, b) -> bool: return float(a["score"]) > float(b["score"]))
	rest.sort_custom(func(a, b) -> bool: return float(a["score"]) > float(b["score"]))
	var out: Array = []
	for s: Dictionary in firsts + rest:
		var ok := true
		for o: Dictionary in out:
			if Vector2((s["center"] as Vector3).x - (o["center"] as Vector3).x, (s["center"] as Vector3).z - (o["center"] as Vector3).z).length() < 14.0:
				ok = false
		if ok:
			s["group"] = "%s%d" % [s["group"], out.filter(func(o) -> bool: return str(o["group"]).begins_with(str(s["group"]))).size()]
			out.append(s)
		if out.size() >= n:
			break
	return out


func _main() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel"]:
		if settings.get(k) != null:
			settings.set(k, false)
	run.forced_map_seed = _seed
	run.launch_override = {"arena": true, "analytics": false}
	change_scene_to_file("res://game/Game.tscn")
	for k in range(1200):
		await process_frame
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null and cs.get("enemies") != null:
			g = cs
			break
	if g == null:
		print("env_shots: the arena never came up")
		_finish(1)
		return
	await _wait(20)
	var panel = g.arena_panel
	g.no_random_chests = true
	g.player.god = true
	panel.call("_clear_field")
	g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	var bn = g.hud.get("_banner") if g.hud else null
	if bn:
		bn.visible = false
	panel.set("_hide_hud", true)
	panel.call("set_clean", true)
	panel.get("_hint").visible = false
	g.player.visible = false
	panel.call("set_zoom", float(A.get("zoom", 0.55)))
	var props = g.map.get("props")
	var spots := _spots(props, int(A.get("spots", 6)))
	# the spots' props, for the record (the same seed lays the same props before and after)
	var lines: PackedStringArray = []
	for s: Dictionary in spots:
		lines.append("spot %s: %s x%d at (%.1f, %.1f)" % [s["group"], s["look"], s["count"], (s["center"] as Vector3).x, (s["center"] as Vector3).z])
		for r: Dictionary in props.placed:
			var p: Vector3 = r["pos"]
			if Vector2(p.x - (s["center"] as Vector3).x, p.z - (s["center"] as Vector3).z).length() < 9.0:
				var code = r.get("tint", props.call("tint_code", p))
				lines.append("    %-16s (%.2f, %.2f) tint %s" % [r["look"], p.x, p.z, str(code)])
	var f := FileAccess.open(_out.path_join("%s_s%d_spots.txt" % [_tag, _seed]), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("env_shots: spots ", spots.size(), " placed ", props.placed.size())
	# pass 137: the map's tints by the cluster rule (settling again changes nothing: the counts of what the map laid)
	if props.has_method("settle_tints"):
		var st: Dictionary = props.call("settle_tints")
		var tinted_n := 0
		var total_n := 0
		print("env_shots: tints ", st)
		for r: Dictionary in props.placed:
			if props.call("tint_rules", str(r["look"])).is_empty():
				continue
			total_n += 1
			if int(props.call("tint_level", float(r["tint"]))) > 0:
				tinted_n += 1
		print("env_shots: tinted props %d of %d" % [tinted_n, total_n])
	var tl = run.map.timeline if run.map else null
	var stage_look = load("res://core/systems/StageLook.gd").call("of", g)
	var stages: PackedStringArray = str(A.get("stages", "1,2,3")).split(",")
	for s_txt in stages:
		var stage := int(s_txt) - 1
		if tl != null and stage < tl.stage_list.size():
			panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
			stage_look.show_stage(stage, 0.0)
			panel.call("_clear_field")
			if str(tl.stage_list[stage].get("weather", "")) != "" and g.map.has_method("set_weather"):
				g.map.call("set_weather", tl.stage_list[stage].get("weather", {}), 0.01)
		await _wait(6)
		# still plants, so a before and an after differ only by their colours
		props.set_wind(0.0, 0.0, 0.0)
		g.player.visible = false
		for s: Dictionary in spots:
			var c: Vector3 = s["center"]
			await _go(c.x, c.z + 3.0)
			await _shot("st%d_%s" % [stage + 1, s["group"]])
			if A.has("plain"):
				var keep := {}
				for ch in props.get_children():
					if ch is MultiMeshInstance3D and (ch as Node).name.begins_with("Prop_"):
						var m := (ch as MultiMeshInstance3D).material_override as ShaderMaterial
						keep[m] = m.get_shader_parameter("tint_v_0")
						m.set_shader_parameter("tint_v_0", Vector4(1, 1, 0.5, 0))
				await _wait(2)
				await _shot("st%d_%s_plain" % [stage + 1, s["group"]])
				for m: ShaderMaterial in keep.keys():
					m.set_shader_parameter("tint_v_0", keep[m])
	_finish(0)
