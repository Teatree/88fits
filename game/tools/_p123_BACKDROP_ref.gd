## Pass 123 (lane BACKDROP): the composition reference for the Royale menu backdrop's sunset painting. The live title's
## world (TitleStage: Red Canyon on its title roll, one of art/ui/title_scene.json's presets laid round the hero's spot)
## seen from a lower camera that shows the horizon and the sky, the hero hidden (hero=1 keeps him, a size check) and no
## UI. tools/gen_royale_backdrop.py hands the picture to Flux.2 Klein as the reference it repaints at sunset.
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --script res://tools/_p123_BACKDROP_ref.gd -- out=<png> [preset=0] [horizon=760] [feet=1150] [hero_px=300]
##     [yaw=0] [hero=0] [spot=x,z]
## The PC's window keeps 9:16, so a taller phone's canvas (tall=2400: 1080 x 2400, 20:9) is made with a wider lens and
## the middle 864 px of the 1080 cut out: the picture is that canvas at 0.8 (864 x 1920, the painting's own size).
## horizon / feet: the tall canvas's y of the horizon and of the hero's soles; hero_px: his 1.9 m figure's height there (it
## sets how far off the camera stands, the title's lens: FOV 55 over 1920 px); yaw: degrees the view turns (+ to the
## left). Every position in <out>_props.json is in the tall canvas's px. The save is sandboxed; a watchdog quits after
## 90 s.
extends SceneTree

var _out := "D:/_projects/88fits/tools/dl/p123/BACKDROP/ref/ref.png"
var _preset := 0
var _horizon := 760.0
var _feet_y := 1150.0
var _hero_px := 300.0
var _yaw := 0.0
var _hero := false
var _spot := Vector2.INF
var _tall := 2400.0
## the picture's scale (1920 / tall) and the lens that gives it
var _k := 0.8
var _f := 1475.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"out": _out = kv[1]
			"preset": _preset = int(kv[1])
			"horizon": _horizon = float(kv[1])
			"feet": _feet_y = float(kv[1])
			"hero_px": _hero_px = float(kv[1])
			"yaw": _yaw = float(kv[1])
			"hero": _hero = kv[1] == "1"
			"tall": _tall = float(kv[1])
			"spot":
				var p := kv[1].split(",")
				if p.size() == 2:
					_spot = Vector2(float(p[0]), float(p[1]))
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		push_error("_p123_BACKDROP_ref: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	var save = root.get_node("Save")
	save.begin_sandbox()
	root.get_node("Settings").menu_style = "live"
	var stage_script = load("res://ui/TitleStage.gd")
	stage_script.force_preset = _preset
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.6)
	var t = current_scene
	for c in t.get_children():
		if c is CanvasItem and c.name != "TitleStage":
			(c as CanvasItem).visible = false
	var stage = t.get_node_or_null("TitleStage")
	if stage == null or stage.hero == null:
		push_error("_p123_BACKDROP_ref: no live title")
		save.end_sandbox()
		quit(2)
		return
	if _spot != Vector2.INF:
		stage.spot = _spot
	stage.hero.visible = _hero
	var fam = stage.familiar()
	if fam != null:
		(fam as Node3D).visible = false
	var feet: Vector3 = stage.feet()
	var cam: Camera3D = stage.camera
	cam.far = 400.0
	_k = 1920.0 / _tall
	_f = 1920.0 * 0.5 / tan(deg_to_rad(55.0) * 0.5) * _k
	cam.fov = rad_to_deg(2.0 * atan(960.0 / _f))
	for i in 6:
		_place(cam, feet, stage.size)
		await process_frame
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	_shot(_out)
	# the preset's paintings as quads on the screen (the backdrop lays the game's own paintings there as cut-outs), then
	# the same view without them: the plate the painting is made from
	var map = stage.map
	var pf = map.get("props")
	var rows: Array = []
	if pf != null and map.has_meta("title_mark"):
		var m: Dictionary = map.get_meta("title_mark")
		var from := int(m.get("placed", 0))
		var sc: Dictionary = stage_script.scene_of(stage.map_id)
		var presets: Array = stage_script.presets_of(sc)
		var spec: Array = presets[stage.preset_index].get("props", []) if stage.preset_index >= 0 else []
		var placed: Array = pf.placed
		for i in range(from, placed.size()):
			var row: Dictionary = placed[i]
			var k := i - from
			var d: Dictionary = spec[k] if k < spec.size() else {}
			rows.append(_quad(cam, pf, row, d))
		pf.truncate(m)
		for i in 4:
			_place(cam, feet, stage.size)
			await process_frame
		_shot(_out.get_basename() + "_plate.png")
	var info := {"preset": stage.preset_name, "preset_index": stage.preset_index, "feet": [feet.x, feet.y, feet.z],
		"view": [1080.0, _tall], "picture_scale": _k, "horizon": _horizon, "feet_y": _feet_y, "hero_px": _hero_px, "yaw": _yaw,
		"feet_px": _px(cam, feet), "props": rows}
	var f := FileAccess.open(_out.get_basename() + "_props.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  "))
	f.close()
	print("_p123_BACKDROP_ref: -> ", _out, " preset ", stage.preset_name, " feet ", feet, " props ", rows.size())
	save.end_sandbox()
	quit(0)


func _shot(path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	# the middle of the 1080: the tall canvas at _k (the window's pixels may be fewer than the canvas's)
	var w := float(img.get_width())
	var sx := w / 1080.0
	var cw := int(round(1080.0 * _k * sx))
	img = img.get_region(Rect2i(int((img.get_width() - cw) / 2), 0, cw, img.get_height()))
	img.resize(int(round(1080.0 * _k)), 1920, Image.INTERPOLATE_LANCZOS)
	img.save_png(path)


func _px(cam: Camera3D, p: Vector3) -> Array:
	var v := cam.unproject_position(p)
	# the 1080 x 1920 viewport's px -> the tall canvas's
	return [snappedf(540.0 + (v.x - 540.0) / _k, 0.1), snappedf(_tall * 0.5 + (v.y - 960.0) / _k, 0.1)]


## A placed painting's quad on the screen (prop_billboard.gdshader: a camera-facing square of the painting's height x
## scale, pivoting on its base 6 cm above the ground), its depth, and the preset's own entry (sway, flip, scale).
func _quad(cam: Camera3D, pf, row: Dictionary, spec: Dictionary) -> Dictionary:
	var look := str(row.get("look", ""))
	var h: float = float(pf.height_of(look)) * float(row.get("scale", 1.0))
	var base: Vector3 = row["pos"] + Vector3(0, 0.06, 0)
	var b := cam.global_transform.basis
	var up: Vector3 = b.y.normalized()
	var right: Vector3 = b.x.normalized()
	var depth := -(cam.global_transform.affine_inverse() * base).z
	return {"id": str(row.get("id", "")), "look": look, "flip": bool(row.get("flip", false)),
		"sway": float(spec.get("sway", 0.0)), "scale": float(row.get("scale", 1.0)), "height_m": h, "depth": depth,
		"base": _px(cam, base), "top": _px(cam, base + up * h), "left": _px(cam, base - right * h * 0.5),
		"right": _px(cam, base + right * h * 0.5), "shadow": pf.shadow_of(look)}


## The camera at the title's lens (FOV 55, keep height), pitched so the horizon sits at `_horizon` and the soles at
## `_feet_y`, as far off as `_hero_px` asks for a 1.9 m figure.
func _place(cam: Camera3D, feet: Vector3, _view: Vector2) -> void:
	# in the 1080 x 1920 viewport's px: the tall canvas's y and sizes times _k about the middle
	var f := _f
	var ppm := _hero_px * _k / 1.9
	var zc := f / ppm
	var hz := 960.0 + (_horizon - _tall * 0.5) * _k
	var fy := 960.0 + (_feet_y - _tall * 0.5) * _k
	var p := atan((960.0 - hz) / f)
	var yaw := deg_to_rad(_yaw)
	var fwd := Vector3(0.0, -sin(p), -cos(p)).rotated(Vector3.UP, yaw)
	var up := Vector3(0.0, cos(p), -sin(p)).rotated(Vector3.UP, yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var pos := feet - fwd * zc + up * ((fy - 960.0) / f * zc)
	cam.global_transform = Transform3D(Basis(right, up, -fwd), pos)
