## Title: one big PLAY, the current character and map chip, Shop, Collection, Settings. Gold and best run on top.
extends Control

var _chip: Button


func _ready() -> void:
	UiKit.fullscreen(self)
	_build_backdrop()
	var v := UiKit.vbox(24)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 60
	v.offset_right = -60
	v.offset_top = 70
	v.offset_bottom = -70
	add_child(v)
	var top := UiKit.hbox()
	var gold := UiKit.panel(Color(0, 0, 0, 0.4), 30, Color(0, 0, 0, 0), 0)
	var gh := UiKit.hbox(10)
	var coin := ColorRect.new()
	coin.color = UiKit.ACCENT
	coin.custom_minimum_size = Vector2(28, 28)
	gh.add_child(coin)
	var gl := UiKit.label(str(Save.gold()), 32, UiKit.INK)
	gl.autowrap_mode = TextServer.AUTOWRAP_OFF
	gh.add_child(gl)
	gold.add_child(gh)
	gold.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(gold)
	var best := Save.best_run(str(Save.data.get("last_map", "dry_gulch")))
	var bp := UiKit.panel(Color(0, 0, 0, 0.4), 30, Color(0, 0, 0, 0), 0)
	var bl := UiKit.label("best %s · L%d" % [TextGen.time_mmss(float(best.get("time", 0.0))), int(best.get("level", 0))] if not best.is_empty() else "no runs yet", 26, UiKit.INK2)
	bl.autowrap_mode = TextServer.AUTOWRAP_OFF
	bp.add_child(bl)
	bp.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(bp)
	v.add_child(top)
	v.add_child(UiKit.spacer(140))
	var logo := UiKit.outline(UiKit.label("88fits", 200, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 14, UiKit.ACCENT_INK)
	v.add_child(logo)
	v.add_child(UiKit.outline(UiKit.label("DRAG  ·  DODGE  ·  SURVIVE", 34, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER), 5))
	v.add_child(UiKit.spacer(60))
	var hero := Registry.character(str(Save.data.get("last_character", "astro")))
	if hero:
		var cc := CenterContainer.new()
		cc.add_child(UiKit.icon_view(hero, 220, "character"))
		v.add_child(cc)
	v.add_child(UiKit.spacer(40))
	var play := UiKit.button("PLAY", 72, true, 170)
	play.pressed.connect(_play)
	v.add_child(play)
	_chip = UiKit.button("", 28, false, 76)
	_chip.pressed.connect(func(): UiFx.go(get_tree(), "res://ui/PlaySetup.tscn"))
	v.add_child(_chip)
	_refresh_chip()
	v.add_child(UiKit.spacer(30))
	var row := UiKit.hbox(20)
	for pair in [["Shop", "res://ui/ShopScreen.tscn"], ["Collection", "res://ui/CollectionScreen.tscn"], ["Settings", "res://ui/SettingsScreen.tscn"]]:
		var b := UiKit.button(pair[0], 32, false, 100)
		b.pressed.connect(func(): UiFx.go(get_tree(), pair[1]))
		row.add_child(b)
	v.add_child(row)
	v.add_child(UiKit.spacer(10))
	v.add_child(UiKit.label("v0.4", 22, UiKit.INK3, HORIZONTAL_ALIGNMENT_CENTER))
	UiFx.stagger(v, 0.05, 12)
	Audio.play_music(["mu_title"], 1)


func _build_backdrop() -> void:
	# Cheap golden-hour sky and sand as flat colour bands with a sun.
	var sky := ColorRect.new()
	sky.color = Color(0.14, 0.17, 0.36)
	UiKit.fullscreen(sky)
	add_child(sky)
	var horizon := ColorRect.new()
	horizon.color = Color(0.93, 0.55, 0.30)
	horizon.set_anchors_preset(Control.PRESET_FULL_RECT)
	horizon.offset_top = 700
	horizon.offset_bottom = -720
	add_child(horizon)
	var sun := Panel.new()
	sun.add_theme_stylebox_override("panel", UiKit.stylebox(Color(1.0, 0.82, 0.48), 160))
	sun.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sun.offset_left = 640
	sun.offset_right = 940
	sun.offset_top = 400
	sun.offset_bottom = 700
	add_child(sun)
	var mesa := ColorRect.new()
	mesa.color = Color(0.29, 0.17, 0.27)
	mesa.set_anchors_preset(Control.PRESET_FULL_RECT)
	mesa.offset_top = 1080
	mesa.offset_bottom = -740
	add_child(mesa)
	var sand := ColorRect.new()
	sand.color = Color(0.78, 0.55, 0.33)
	sand.set_anchors_preset(Control.PRESET_FULL_RECT)
	sand.offset_top = 1180
	add_child(sand)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.11, 0.30)
	UiKit.fullscreen(dim)
	add_child(dim)


func _refresh_chip() -> void:
	var c := Registry.character(str(Save.data.get("last_character", "astro")))
	var m := Registry.map(str(Save.data.get("last_map", "dry_gulch")))
	_chip.text = "%s · %s · change ▸" % [c.display_name if c else "?", m.display_name if m else "?"]


func _play() -> void:
	if not Save.first_run_done():
		# first ever run: preselected character and map, straight in
		Save.data["last_character"] = "astro" if Registry.characters.has("astro") else Registry.sorted_characters()[0].id
		Save.data["last_map"] = Registry.sorted_maps()[0].id if not Registry.maps.is_empty() else "dry_gulch"
	UiFx.go(get_tree(), "res://game/Game.tscn")
