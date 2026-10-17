## The Stages menu's pictures (pass 87, lane SLOOK; Garry: "Each of the Stage Buttons will feature a screenshot from the
## map itself (at a nice angle) ... The screenshots in the Stages menu should reflect the look"). Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/stage_shots.gd -- [map=red_canyon] [stages=1,2,3] [out=<dir>] [preview=<dir>] [seed=88]
##       [hero=drifter] [w=1248] [h=480] [ss=2] [spot=x,z] [dist=34] [height=15] [fov=34] [yaw=0]
##       [look<k>=#rrggbb,strength,hell] [boss=0|1] [count=1]
## For each stage of the map (its timeline_data.stage_list, else `stages` x stage_length): the debug arena on the map's
## layout roll `seed`, nothing else alive; the hero at the spot; the stage's own creatures (the roster rows that play in
## its window, the hell channel too, most weighted first, each row's own look) coming at him from up the map; the
## stage's look (StageLook: its filter and its hell) at once; then a camera higher and wider than play, looking
## up the map (north, as the run's camera does, so every painting shows the side it shows in play) over the hero and the
## crowd to the props, the oasis, the fort wall and the cliffs. Drawn by a SubViewport of w x ss by h x ss pixels that
## shares the run's world (the filter's quads cover any camera's view), scaled down to w x h (smooth edges), written as
## <out>/<map>_s<k>.jpg (default out res://art/ui/stages; the menu's card box is 936 x 360, drawn covered) and, with
## `preview`, a PNG of each there too. Run `--import` after it so the game loads the new pictures.
## The arena keeps nothing (Save.begin_sandbox); a watchdog quits after 240 s whatever happens; every wait is bounded.
extends SceneTree

const SPOTS := {
	# picked by eye on the title's roll (88; tools/dl/p87/SLOOK/frame_*_sheet.png): the crowd on the south shore of the
	# east oasis (its lake at (42, 4)), the palms round it, the fort wall, the cliffs and a sliver of sky behind, the hero
	# in front with his back to the camera. `spot` the crowd's middle on the ground (x, z), the camera `dist` m south of
	# it and `height` m over it aiming `look_up` m over it, `fov` degrees tall; the hero `hero_dx`, `hero_dz` m off the
	# spot; the crowd `band` m wide
	"red_canyon": {"spot": Vector2(46.0, 15.0), "dist": 13.0, "height": 4.5, "fov": 36.0, "yaw": 0.0, "look_up": 2.2, "hero_dx": -1.2, "hero_dz": 2.4, "band": 11.0},
}
## Creatures a stage's picture shows: this many rows, this many of each.
const ROWS := 3
const PER_ROW := 4

var _map := "red_canyon"
var _out := "res://art/ui/stages"
var _preview := ""
var _stages: Array = []
var _seed := 88
var _hero := "drifter"
var _w := 1248
var _h := 480
var _ss := 2
var _cam: Dictionary = {}
var _looks: Dictionary = {}
var _boss := false
var _count := 1
## overview=<png>: the layout from straight above instead (choosing a spot), its lakes, structures and signs printed
var _overview := ""
var _run
var _save
var _reg
var g
var _made: Array = []
var _vp: SubViewport
var _camera: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		var k: String = kv[0]
		var v: String = kv[1]
		match k:
			"map": _map = v
			"out": _out = v
			"preview": _preview = v
			"stages":
				for s in v.split(",", false):
					_stages.append(int(s))
			"seed": _seed = int(v)
			"hero": _hero = v
			"w": _w = int(v)
			"h": _h = int(v)
			"ss": _ss = maxi(int(v), 1)
			"spot":
				var p := v.split(",")
				_cam["spot"] = Vector2(float(p[0]), float(p[1]))
			"dist", "height", "fov", "yaw", "look_up", "hero_dx", "hero_dz", "band":
				_cam[k] = float(v)
			"boss": _boss = v == "1"
			"overview": _overview = v
			"count": _count = maxi(int(v), 1)
			_:
				if k.begins_with("look"):
					var f := v.split(",")
					_looks[int(k.substr(4))] = {"filter": {"color": f[0], "strength": float(f[1]) if f.size() > 1 else 0.0}, "hell": f.size() > 2 and f[2] == "1"}
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("stage_shots: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": _hero, "map": _map, "map_seed": _seed}))
	f.close()
	_run.arena_next = true
	# the run's dice fixed (Run.seed_dice, as the sim does): the structures land where they landed last time
	_run.seed_dice(8701)
	change_scene_to_file("res://game/Game.tscn")
	for k in range(600):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	if g == null or g.get("player") == null:
		printerr("stage_shots: the game did not start")
		quit(2)
		return
	await _wait(2.0)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	var tl = _run.map.timeline if _run.map else null
	var list: Array = load("res://core/systems/StageLook.gd").stage_list_of(tl)
	if _stages.is_empty():
		var n: int = list.size() if not list.is_empty() else (int(tl.stages) if tl else 3)
		for k in range(n):
			_stages.append(k + 1)
	var cfg: Dictionary = SPOTS.get(_map, {"spot": Vector2(0, 0), "dist": 13.0, "height": 4.5, "fov": 36.0, "yaw": 0.0, "look_up": 2.2}).duplicate()
	cfg.merge(_cam, true)
	_build_view(cfg)
	_clear_view(cfg)
	var out_abs := ProjectSettings.globalize_path(_out) if _out.begins_with("res://") or _out.begins_with("user://") else _out
	DirAccess.make_dir_recursive_absolute(out_abs)
	if _preview != "":
		DirAccess.make_dir_recursive_absolute(_preview)
	if _overview != "":
		await _overview_shot()
		_save.data = keep
		quit(0)
		return
	for s: int in _stages:
		await _stage_shot(s, tl, list, cfg, out_abs)
	_run.seed_dice(0)
	_save.data = keep
	quit(0)


## The picture's camera: a SubViewport sharing the run's world, its camera `dist` metres back from the spot (south, or
## turned by `yaw` degrees) and `height` up, looking at the spot, `fov` degrees tall.
func _build_view(cfg: Dictionary) -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(_w * _ss, _h * _ss)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.transparent_bg = false
	g.add_child(_vp)
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = float(cfg["fov"])
	_camera.far = 400.0
	_vp.add_child(_camera)
	_camera.current = true
	var spot: Vector2 = cfg["spot"]
	var at := _ground(Vector3(spot.x, 0, spot.y)) + Vector3(0, 1.0, 0)
	var aim := at + Vector3(0, float(cfg.get("look_up", 0.0)), 0)
	var back := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(float(cfg["yaw"])))
	_camera.global_position = at + back * float(cfg["dist"]) + Vector3(0, float(cfg["height"]), 0)
	_camera.look_at(aim, Vector3.UP)


## Nothing between the camera and the crowd, and nothing standing in the crowd: the props there are taken off the field
## and the structures there hidden (with their rings, lights and shadows), so the crowd and the hero are seen whole.
func _clear_view(cfg: Dictionary) -> void:
	var spot: Vector2 = cfg["spot"]
	var band := float(cfg.get("band", 11.0))
	var cam_z := spot.y + float(cfg["dist"])
	var inside := func(p: Vector3) -> bool:
		var dz := p.z - spot.y
		if dz < -4.5 or p.z > cam_z + 2.0:
			return false
		var half := band * 0.5 + 1.5 + maxf(dz, 0.0) * 0.45
		return absf(p.x - spot.x) < half
	var gone: int = g.map.props.remove_where(func(row: Dictionary) -> bool: return inside.call(row["pos"]))
	var hid := 0
	for st in g.structures.items:
		if is_instance_valid(st) and inside.call(st.global_position):
			st.visible = false
			for part in [st.ring, st.pie, st.portal, st.glow]:
				if part:
					part.visible = false
			if int(st.get("shadow")) >= 0:
				g.map.props.hide_shadow(int(st.shadow))
			hid += 1
	print("stage_shots: cleared %d props, %d structures from the view" % [gone, hid])


func _stage_shot(s: int, tl, list: Array, cfg: Dictionary, out_abs: String) -> void:
	var em = g.enemies
	em.kill_all(false)
	g.projectiles.clear_all()
	_made.clear()
	await _wait(0.8)
	em.kill_all(false)
	await _wait(0.3)
	var spot: Vector2 = cfg["spot"]
	var here := _ground(Vector3(spot.x, 0, spot.y))
	var hero_at := here + Vector3(float(cfg.get("hero_dx", -1.2)), 0.0, float(cfg.get("hero_dz", 5.0)))
	g.player.global_position = _ground(hero_at) + Vector3(0, 0.05, 0)
	# the stage's creatures in a band across the spot, facing the hero
	var window := _window(tl, list, s - 1)
	var ids := _stage_creatures(tl, window, s - 1)
	print("stage_shots: stage %d window %s creatures %s" % [s, str(window), str(ids.map(func(r): return str(r.get("enemy", ""))))])
	var rng := RandomNumberGenerator.new()
	rng.seed = 87 + s
	var band := float(cfg.get("band", 11.0))
	for r in range(ids.size()):
		var row: Dictionary = ids[r]
		var cx := -band * 0.5 + band * (float(r) + 0.5) / float(ids.size())
		for k in range(PER_ROW * _count):
			var p := here + Vector3(cx + rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-3.8, -0.6))
			var st = row.get("stats", {})
			var i: int = em.spawn(str(row["enemy"]), _ground(p), null, 1.0, 1.0, str(row.get("variant", "")), st if st is Dictionary else {}, {})
			_made.append(i)
	if _boss:
		var e: Dictionary = list[s - 1] if s - 1 < list.size() else {}
		var bid := str(e.get("boss", ""))
		if bid != "":
			_made.append(em.spawn(bid, _ground(here + Vector3(1.0, 0, -6.0)), null, 1.0, 1.0))
	# the look
	var entry: Dictionary = _looks.get(s, {})
	var sl = load("res://core/systems/StageLook.gd").of(g)
	if entry.is_empty():
		sl.show_stage(s - 1, 0.0)
	else:
		var m: Array = sl.filter_mults(entry)
		sl.set_mults(m[0], m[1], 0.0)
		g.map.set_hell(1.0 if bool(entry.get("hell", false)) else 0.0, 0.01)
	# held where they stand while they rise out of the sand (the map's spawn_rise) and turn to the hero
	for k in range(110):
		_freeze()
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _vp.get_texture().get_image()
	if _ss > 1:
		img.resize(_w, _h, Image.INTERPOLATE_LANCZOS)
	var name := "%s_s%d" % [_map, s]
	var path := out_abs.path_join(name + ".jpg")
	var err := img.save_jpg(path, 0.88)
	print("stage_shots: ", path, " ", err)
	if _preview != "":
		img.save_png(_preview.path_join(name + ".png"))


## The roll from straight above (x right, z down the picture, 150 m across), for choosing a spot; the lakes, the
## structures and the signs printed in metres.
func _overview_shot() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 150.0
	_vp.size = Vector2i(1500, 1500)
	_camera.global_position = Vector3(0, 120, 0)
	_camera.look_at(Vector3(0, 0, 0.001), Vector3(0, 0, -1))
	for c: Dictionary in g.map.lakes():
		print("stage_shots: lake ", c)
	for s in g.structures.items:
		if is_instance_valid(s):
			print("stage_shots: structure %s at (%.1f, %.1f)" % [str(s.def.id) if s.get("def") else s.name, s.global_position.x, s.global_position.z])
	print("stage_shots: hero start ", g.map.player_start(), " flats ", g.map.flats_center, " radius ", g.map.arena_radius)
	for k in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png(_overview)
	print("stage_shots: overview ", _overview)


## Stage index `i`'s window on the run clock [start, end]: the stage list's lengths, else stage_length each.
func _window(tl, list: Array, i: int) -> Vector2:
	if not list.is_empty():
		var t0 := 0.0
		for k in range(mini(i, list.size())):
			t0 += float((list[k] as Dictionary).get("length", 430.0))
		var e: Dictionary = list[mini(i, list.size() - 1)]
		return Vector2(t0, t0 + float(e.get("length", 430.0)))
	var L: float = float(tl.stage_length) if tl else 430.0
	return Vector2(L * i, L * (i + 1))


## The creature rows that play in the window's later half (the stage's own crowd), most weighted first, one per creature,
## at most ROWS; a hell stage's hell-channel rows first.
func _stage_creatures(tl, w: Vector2, _i: int) -> Array:
	var out: Array = []
	if tl == null:
		return out
	var mid := w.x + (w.y - w.x) * 0.55
	var scored: Array = []
	for r in tl.roster:
		if not (r is Dictionary):
			continue
		var d: Dictionary = r
		var id := str(d.get("enemy", ""))
		if id == "" or _reg.enemy(id) == null:
			continue
		var t0 := float(d.get("t", 0.0))
		var t1 := float(d.get("until", 1e9))
		if t1 < mid or t0 >= w.y:
			continue
		var wt := 0.0
		for p in d.get("weights", []):
			if p is Array and (p as Array).size() >= 2:
				wt = maxf(wt, float(p[1]))
		if str(d.get("channel", "")) == "hell":
			wt += 100.0
		scored.append({"row": d, "w": wt})
	scored.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
	var seen := {}
	for sc in scored:
		var row: Dictionary = sc["row"]
		var id := str(row["enemy"])
		if seen.has(id):
			continue
		seen[id] = true
		out.append(row)
		if out.size() >= ROWS:
			break
	return out


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _freeze() -> void:
	var em = g.enemies
	for i: int in _made:
		if i >= 0 and em.alive[i] == 1:
			em.speed[i] = 0.0
			em.cooldown[i] = 9.0
			em.vel[i] = Vector3.ZERO
