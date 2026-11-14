## Pass 148 (lane ROCKS): the four rock paintings laid in a row on clean sand in the debug arena, seen by the game's real
## camera, under several foot settings and with the old or the current paintings, in the stages named; close and at play
## zoom. Windowed:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --log-file <abs> --script res://tools/_p148_ROCKS_shots.gd -- out=<dir> [stages=1,4] [cfgs=off,dither,tone]
##     [art=before|now] [tag=<name>] [zooms=0.35,1.0] [ids=rock_small,rock_big,boulder,boulder_b (four props, left to right)]
## A cfg is a name below (CFGS) or "data" (the paintings' own props.json foot, as the game lays them). art=before lays the
## paintings kept in tools/dl/p148/ROCKS/before/. Frame cap and watchdog bound it; the save in memory goes back as it was.
extends SceneTree

const ROCKS := ["rock_small", "rock_big", "boulder", "boulder_b"]
const BEFORE := "D:/_projects/88fits/tools/dl/p148/ROCKS/before/"
const SAND := [0.99, 0.85, 0.58]
const SAND_HELL := [1.0, 0.86, 0.72]
## foot settings tried (props.json `foot` keys)
const CFGS := {
	"off": {},
	"sink": {"sink": 0.1},
	"dither": {"sink": 0.1, "band": 0.1, "fade": 1.0, "dark": 0.2, "noise": 0.35},
	"tone": {"sink": 0.1, "band": 0.1, "tone": 0.7, "dark": 0.1, "noise": 0.35},
	"dark": {"sink": 0.1, "band": 0.12, "dark": 0.45, "noise": 0.3},
	"both": {"sink": 0.1, "band": 0.1, "fade": 0.7, "tone": 0.5, "dark": 0.15, "noise": 0.35},
	"dither2": {"sink": 0.08, "band": 0.07, "fade": 1.0, "dark": 0.3, "noise": 0.4},
	"tone2": {"sink": 0.08, "band": 0.08, "tone": 0.85, "dark": 0.0, "noise": 0.4},
	"mix2": {"sink": 0.08, "band": 0.08, "fade": 0.6, "tone": 0.6, "dark": 0.2, "noise": 0.4},
	"dark2": {"sink": 0.08, "band": 0.1, "dark": 0.35, "noise": 0.4},
	"shade": {"sink": 0.08, "band": 0.08, "tone": 0.8, "color": [0.6, 0.49, 0.35], "color_hell": [0.54, 0.45, 0.38], "noise": 0.4},
	"shade_lo": {"sink": 0.03, "band": 0.07, "tone": 0.75, "color": [0.6, 0.49, 0.35], "color_hell": [0.54, 0.45, 0.38], "noise": 0.4},
	"mid_lo": {"sink": 0.03, "band": 0.07, "tone": 0.8, "color": [0.78, 0.65, 0.46], "color_hell": [0.72, 0.6, 0.5], "noise": 0.4},
}

var A: Dictionary = {}
var g = null
var _frames := 0
var _ended := false
var _save = null
var _keep: Dictionary = {}
var _out := ""
var _ids: Array = ROCKS


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if A.has("ids"):
		_ids = Array(str(A["ids"]).split(","))
	_out = str(A.get("out", "D:/_projects/88fits/tools/dl/p148/ROCKS/shots"))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(float(A.get("watchdog", 220.0)), true, false, true).timeout.connect(_finish.bind(2))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > 400000:
		_finish(2)


func _finish(code: int) -> void:
	if _ended:
		return
	_ended = true
	print("rocks_shots: finish ", code)
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	quit(code)


func _wait(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("rocks_shots: ", path)


func _go(x: float, z: float) -> void:
	g.player.global_position = Vector3(x, g.map.height_at(x, z) + 0.5, z)
	g.camera.snap_to(g.player)
	await _wait(6)


func _apply(props, cfg: Dictionary, hell: bool) -> void:
	for id: String in _ids:
		var mmi = props.get_node_or_null("Prop_" + id)
		if mmi == null:
			continue
		var mat: ShaderMaterial = mmi.material_override
		var f: Dictionary = cfg if cfg.get("data") == null else props.foot_of(id)
		mat.set_shader_parameter("foot_sink", float(f.get("sink", 0.0)))
		mat.set_shader_parameter("foot_band", float(f.get("band", 0.0)))
		mat.set_shader_parameter("foot_fade", float(f.get("fade", 0.0)))
		mat.set_shader_parameter("foot_dark", float(f.get("dark", 0.0)))
		mat.set_shader_parameter("foot_noise", float(f.get("noise", 0.0)))
		var col: Array = f.get("color_hell", SAND_HELL) if hell else f.get("color", SAND)
		mat.set_shader_parameter("foot_color", Color(float(col[0]), float(col[1]), float(col[2]), float(f.get("tone", 0.0))))


func _main() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel"]:
		if settings.get(k) != null:
			settings.set(k, false)
	run.forced_map_seed = int(A.get("seed", 7))
	run.launch_override = {"arena": true, "analytics": false}
	change_scene_to_file("res://game/Game.tscn")
	for k in range(1200):
		await process_frame
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null and cs.get("enemies") != null:
			g = cs
			break
	if g == null:
		print("rocks_shots: the arena never came up")
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
	var props = g.map.get("props")
	# the spot: clean sand ahead of the start, every prop within 10 m taken away, the four rocks in a row
	var p0: Vector3 = g.player.global_position
	var cx := p0.x + float(A.get("dx", 0.0))
	var cz := p0.z - 4.0 + float(A.get("dz", 0.0))
	props.remove_where(func(r: Dictionary) -> bool: return Vector2((r["pos"] as Vector3).x - cx, (r["pos"] as Vector3).z - cz).length() < 10.0)
	var xs := [-3.7, -2.2, 0.2, 3.0]
	for k in mini(_ids.size(), xs.size()):
		var x: float = cx + float(xs[k])
		props.add(str(_ids[k]), Vector3(x, g.map.height_at(x, cz), cz), 1.0, false, 0.0, true)
	if str(A.get("art", "now")) == "before":
		for id: String in ROCKS:
			var img := Image.load_from_file(BEFORE + id + ".png")
			img.generate_mipmaps()
			var mmi = props.get_node_or_null("Prop_" + id)
			if mmi:
				(mmi.material_override as ShaderMaterial).set_shader_parameter("sprite", ImageTexture.create_from_image(img))
	var tl = run.map.timeline if run.map else null
	var stage_look = load("res://core/systems/StageLook.gd").call("of", g)
	var tag := str(A.get("tag", A.get("art", "now")))
	var zooms: PackedStringArray = str(A.get("zooms", "0.55,1.0")).split(",")
	for s_txt in str(A.get("stages", "1,4")).split(","):
		var stage := int(s_txt) - 1
		if tl != null and stage < tl.stage_list.size():
			panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
			stage_look.show_stage(stage, 0.0)
			panel.call("_clear_field")
		await _wait(30)
		var hell: bool = stage >= 3
		for c_name in str(A.get("cfgs", "off,dither,tone")).split(","):
			var cfg: Dictionary = {"data": true} if c_name == "data" else CFGS.get(c_name, {})
			_apply(props, cfg, hell)
			for z_txt in zooms:
				var zoom := float(z_txt)
				g.camera.zoom_override = zoom
				if zoom < 0.8:
					# close: the small pair, then the boulders
					await _go(cx - 2.9, cz + 2.6)
					await _shot("st%d_%s_%s_close_a" % [stage + 1, tag, c_name])
					await _go(cx + 1.6, cz + 3.2)
					await _shot("st%d_%s_%s_close_b" % [stage + 1, tag, c_name])
				else:
					await _go(cx, cz + 3.6)
					await _shot("st%d_%s_%s_play" % [stage + 1, tag, c_name])
	_finish(0)
