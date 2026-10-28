## Pass 110 (lane ARENA): does the shaders' TIME follow Engine.time_scale in this Godot? A full-screen rect paints
## fract(TIME / 8) into its red; the red is read a wall-clock second apart at time_scale 1 and 0.25. Windowed, bounded.
##   bash tools/godot.sh --audio-driver Dummy --resolution 64x64 --path game --script res://tools/_p110_ARENA_time_probe.gd
extends SceneTree

var _rect: ColorRect


func _initialize() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func(): print("time_probe: watchdog"); quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _red() -> float:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	return img.get_pixel(img.get_width() / 2, img.get_height() / 2).r


func _main() -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(fract(TIME / 8.0), 0.0, 0.0, 1.0); }\n"
	var m := ShaderMaterial.new()
	m.shader = sh
	_rect.material = m
	root.add_child(_rect)
	for k in range(5):
		await process_frame
	for sc: float in [1.0, 0.25]:
		Engine.time_scale = sc
		await process_frame
		var a: float = await _red()
		var t0 := Time.get_ticks_msec()
		await create_timer(1.0, true, false, true).timeout
		var b: float = await _red()
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		print("time_probe: time_scale %.2f: shader TIME moved %.3f s in %.3f wall s" % [sc, (b - a) * 8.0, secs])
	Engine.time_scale = 1.0
	quit(0)
