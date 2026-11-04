## Pass 123 (lane BACKDROP): captures of the Royale menu backdrop (ui/wanted/RoyaleBackdrop.gd). Windowed:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##     --script res://tools/_p123_BACKDROP_shots.gd -- out=D:/_projects/88fits/tools/dl/p123/BACKDROP/shots [only=title,menu,tall]
## title: the "title" kind with a hero's idle frame (the Drifter, 300 px tall, as the main menu will stand him) on the
##   disc, a tumbleweed sent across at once, a frame every 0.5 s for 4 s (title_00..08.png);
## menu: the "menu" kind at set_dim(0.4) under a slate panel (menu_dim.png) and undimmed (menu_plain.png);
## tall: the title kind in a 1080 x 2400 view (a 20:9 phone) and a 1440 x 1920 one (a wide screen), drawn in a
##   SubViewport (tall_2400.png, wide_1440.png).
## No autoload is touched; a watchdog quits after 120 s.
extends SceneTree

const BD := "res://ui/wanted/RoyaleBackdrop.gd"
var _out := "D:/_projects/88fits/tools/dl/p123/BACKDROP/shots"
var _only := ["title", "menu", "tall"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(","))
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		push_error("_p123_BACKDROP_shots: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, vp: Viewport = null) -> void:
	var v := vp if vp != null else root.get_viewport()
	var img := v.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(_out.path_join(name + ".png"))
	print("_p123_BACKDROP_shots: ", name)


func _clear() -> void:
	for c in root.get_children():
		if c.has_meta("p123_shot"):
			c.queue_free()
	await _frames(2)


## The Drifter's first idle_f frame (column 38: idle 4, run 24, hit 4, die 5, cheer 1 before it), its figure `figure_px` tall, its soles on `feet`.
func _hero(parent: Node, feet: Vector2, figure_px: float) -> Sprite2D:
	var tex: Texture2D = load("res://content/characters/drifter/drifter_sprite.png")
	var s := Sprite2D.new()
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2(38 * 256, 0, 256, 256)
	s.centered = false
	# the figure fills 0.08..0.953 of the frame (TitleStage.FIGURE_TOP / FIGURE_FEET)
	var k := figure_px / ((0.953 - 0.08) * 256.0)
	s.scale = Vector2(k, k)
	s.offset = Vector2(-128, -0.953 * 256.0)
	s.position = feet
	parent.add_child(s)
	return s


func _main() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var script: GDScript = load(BD)
	script.set("force_live", true)
	if "title" in _only:
		var host := Control.new()
		host.set_meta("p123_shot", true)
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(host)
		var bd: Control = script.call("make", "title")
		host.add_child(bd)
		await _frames(3)
		var c: Vector2 = bd.call("disc_center")
		_hero(host, c - Vector2(0, 30), 300.0)
		bd.call("force_tumbleweed")
		await _frames(2)
		for i in 9:
			_shot("title_%02d" % i)
			await _wait(0.5)
		await _clear()
	if "menu" in _only:
		var host := Control.new()
		host.set_meta("p123_shot", true)
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(host)
		var bd: Control = script.call("make", "menu")
		host.add_child(bd)
		await _frames(3)
		_shot("menu_plain")
		bd.call("set_dim", 0.4)
		var panel := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("27314a")
		sb.border_color = Color("0e1f4a")
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(18)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 8
		panel.add_theme_stylebox_override("panel", sb)
		panel.position = Vector2(48, 320)
		panel.size = Vector2(984, 1200)
		host.add_child(panel)
		var title := Label.new()
		title.text = "SETTINGS"
		title.add_theme_font_size_override("font_size", 72)
		title.add_theme_color_override("font_color", Color("fff6dc"))
		title.position = Vector2(60, 150)
		host.add_child(title)
		await _frames(3)
		_shot("menu_dim")
		await _clear()
	if "tall" in _only:
		for spec in [["tall_2400", Vector2i(1080, 2400)], ["wide_1440", Vector2i(1440, 1920)]]:
			var svc := SubViewportContainer.new()
			svc.set_meta("p123_shot", true)
			svc.stretch = false
			root.add_child(svc)
			var vp := SubViewport.new()
			vp.size = spec[1]
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			vp.transparent_bg = false
			svc.add_child(vp)
			var host := Control.new()
			host.size = Vector2(spec[1])
			vp.add_child(host)
			var bd: Control = script.call("make", "title")
			bd.set_anchors_preset(Control.PRESET_TOP_LEFT)
			bd.size = Vector2(spec[1])
			host.add_child(bd)
			await _frames(3)
			bd.size = Vector2(spec[1])
			await _frames(2)
			var c: Vector2 = bd.call("disc_center")
			_hero(host, c - Vector2(0, 30), 300.0)
			await _frames(3)
			_shot(spec[0], vp)
			await _clear()
	quit(0)
