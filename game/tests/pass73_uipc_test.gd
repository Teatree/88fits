## Pass 73, lane UIPC. The title's hero plaque at one size (Garry: "The size of the hero plaque in the main menu keeps
## changing depending on which hero you're looking at ... Make it so that it stays static no matter what hero plaque
## it's displaying. Adjust the size of the fonts so that every single hero fits well inside the static block and each
## of the elements is readable. The font size should be consistent for all the heroes."): the plaque, the Hero
## Collections button, the hero above them and PLAY sit in the same place for every hero in every state (owned, on
## sale, locked, a hidden one previewed), every word on the plaque fits inside it at one set of sizes, the flavour in
## at most LINE_MAX lines. And the PC build (Garry: "Can you make an icon for the PC build"): game/icon.ico holds every
## size Windows asks for, the Windows preset embeds it and takes the game's version.
extends GdUnitTestSuite

const Title := preload("res://ui/TitleScreen.gd")
const Stage := preload("res://ui/TitleStage.gd")

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"style": Settings.menu_style, "preview": Settings.preview_locked_heroes, "inset": Settings.top_inset,
		"data": Save.data.duplicate(true)}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Stage.forget()
	Settings.menu_style = str(_keep["style"])
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Settings.top_inset = int(_keep["inset"])
	Save.data = _keep["data"]
	Save._dirty = false


func _title(style: String) -> Control:
	Settings.menu_style = style
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	# the lower block's entrance (TitleScreen._enter: up 40 px over 0.25 s) is over before anything is measured
	await get_tree().create_timer(0.4).timeout
	return t


## The save in one of the states a hero can be in: "owned" (every quest done, every hero bought), "buyable" (the quests
## done, nobody bought), "locked" (no quest done). Returns how the carousel will be filled.
func _state(which: String) -> void:
	Save.data = Save._default()
	var done: Array = []
	for q in Registry.quests.values():
		if str(q.unlocks.get("type", "")) == "character" and which != "locked":
			done.append(str(q.id))
	Save.data["quests_done"] = done
	var owned: Array = []
	if which == "owned":
		for c: CharacterDef in Registry.characters.values():
			if not c.hidden and c.availability == "purchase":
				owned.append(c.id)
	Save.data["heroes_owned"] = owned
	Save._dirty = false


func _rect(c: Control) -> Rect2:
	return c.get_global_rect()


## Every WText under `n` that shows words.
func _texts(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "", true, false):
		if c is WText and (c as WText).is_visible_in_tree() and (c as WText).text != "":
			out.append(c)
	return out


func _show(t: Control, i: int) -> void:
	t._index = i
	t._show_hero(0)
	t._place()


# ---------------------------------------------------------------- one size, nothing moves

func test_the_plaque_is_one_size_for_every_hero_in_every_state() -> void:
	for style in ["painted", "live"]:
		for which in ["owned", "buyable", "locked", "preview"]:
			_state("locked" if which == "preview" else which)
			Settings.preview_locked_heroes = which == "preview"
			var t := await _title(style)
			var vp: Vector2 = t.get_viewport_rect().size
			var want_size := Vector2(vp.x - 60.0 - (Title.BOX_LEFT + Title.PLAQUE_H + Title.BOX_GAP), Title.PLAQUE_H)
			var first := {}
			for i in (t._heroes as Array).size():
				_show(t, i)
				await get_tree().process_frame
				var who := "%s %s %s" % [style, which, (t._heroes[i] as CharacterDef).id]
				assert_vector(t._plaque.size).override_failure_message(who).is_equal_approx(want_size, Vector2(0.5, 0.5))
				var now := {"plaque": _rect(t._plaque), "button": _rect(t._drawer_btn), "play": _rect(t._play),
					"hero": Rect2(t._hero_row.position, t._hero_row.size), "dots": _rect(t._dots), "map": _rect(t._map_tap)}
				if first.is_empty():
					first = now
					continue
				for k: String in now:
					var a: Rect2 = now[k]
					var b: Rect2 = first[k]
					assert_bool(a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)) \
						.override_failure_message("%s: the %s moved: %s -> %s" % [who, k, b, a]).is_true()
			t.visible = false
			Stage.forget()


func test_swiping_through_every_hero_moves_nothing() -> void:
	_state("buyable")
	var t := await _title("painted")
	var was := [_rect(t._plaque), _rect(t._drawer_btn), _rect(t._play), Rect2(t._hero_row.position, t._hero_row.size)]
	for k in (t._heroes as Array).size():
		t._step(1)
		await get_tree().process_frame
		var now := [_rect(t._plaque), _rect(t._drawer_btn), _rect(t._play), Rect2(t._hero_row.position, t._hero_row.size)]
		for j in now.size():
			assert_bool((now[j] as Rect2).is_equal_approx(was[j] as Rect2)) \
				.override_failure_message("swipe %d: %s -> %s" % [k, was[j], now[j]]).is_true()


# ---------------------------------------------------------------- everything fits, one set of sizes

func test_every_heros_words_fit_inside_the_plaque_at_one_set_of_sizes() -> void:
	for which in ["owned", "buyable", "locked", "preview"]:
		_state("locked" if which == "preview" else which)
		Settings.preview_locked_heroes = which == "preview"
		var t := await _title("painted")
		var body: Control = t._plaque.get_node("Body")
		for i in (t._heroes as Array).size():
			_show(t, i)
			await get_tree().process_frame
			var c: CharacterDef = t._heroes[i]
			var who := "%s %s" % [which, c.id]
			var room := _rect(body).grow(0.5)
			# the insides never ask for more than the room inside the border and the padding
			var cols: Control = body.get_node("Columns")
			var need := cols.get_combined_minimum_size()
			assert_bool(need.x <= body.size.x + 0.5 and need.y <= body.size.y + 0.5) \
				.override_failure_message("%s needs %s in %s" % [who, need, body.size]).is_true()
			for w: WText in _texts(body):
				assert_bool(room.encloses(_rect(w))).override_failure_message("%s: '%s' at %s is outside %s" % [who, w.text, _rect(w), room]).is_true()
				# one line unless it is the flavour; nothing wider than its box
				if not w.wrap:
					assert_float(w.text_width()).override_failure_message("%s: '%s'" % [who, w.text]).is_less_equal(w.size.x + 0.5)
			# the flavour in at most LINE_MAX lines, none cut
			if t._line.is_visible_in_tree():
				t._line._shape()
				assert_int(t._line._para.get_line_count()).override_failure_message("%s: the flavour wraps to more than %d lines" % [who, Title.LINE_MAX]).is_less_equal(Title.LINE_MAX)
			# the sizes are the plaque's, whoever he is
			assert_int(t._name.font_size).is_equal(Title.NAME_PX)
			assert_int(t._line.font_size).is_equal(Title.LINE_PX)
			for s in t._trait.get_children():
				assert_int((s.get_node("Value") as WText).font_size).override_failure_message(who).is_equal(Title.VALUE_PX)
				assert_int((s.get_node("Label") as WText).font_size).override_failure_message(who).is_equal(Title.LABEL_PX)
			for col in t._stats.get_children():
				for w: WText in _texts(col):
					assert_int(w.font_size).override_failure_message(who).is_equal(Title.LABEL_PX)
			assert_int((t._plaque.find_child("Details", true, false) as WText).font_size).is_equal(Title.LABEL_PX)
			# at most two plates (START, FAVOURITE): the sheet lists the rest
			assert_int(t._stats.get_child_count()).is_less_equal(Title.PLATES_MAX)
		t.visible = false


func test_the_labels_are_bigger_than_before_and_the_numbers_sit_on_their_baseline() -> void:
	# pass 73: the labels under the plates and beside the numbers were 14 px; one size of 18 now
	assert_int(Title.LABEL_PX).is_greater_equal(18)
	assert_int(Title.LINE_PX).is_greater_equal(24)
	_state("owned")
	var t := await _title("painted")
	for i in (t._heroes as Array).size():
		if (t._heroes[i] as CharacterDef).id == "ironwood":
			_show(t, i)
	await get_tree().process_frame
	# Ironwood's two numbers: a row each, each label on its number's line
	var stats: Array = t._trait.get_children()
	assert_int(stats.size()).is_greater_equal(1)
	for s: Control in stats:
		var v: WText = s.get_node("Value")
		var l: WText = s.get_node("Label")
		assert_float(l.size.y).is_equal_approx(v.size.y, 0.5)
		assert_int(l.valign).is_equal(VERTICAL_ALIGNMENT_BOTTOM)
	t.visible = false


func test_the_hero_keeps_clear_of_the_title_words_under_a_camera_cutout() -> void:
	Settings.top_inset = 130
	_state("owned")
	var t := await _title("painted")
	# the title's words end 440 px down on a 1920 screen, plus the inset
	assert_float(t._hero_row.position.y).is_greater_equal(440.0 + 130.0 - 0.5)
	assert_float(t._hero_row.position.y + t._hero_row.size.y).is_less_equal(t._plaque.position.y - 38.0 + 0.5)
	t.visible = false


# ---------------------------------------------------------------- the PC build

func test_the_windows_icon_holds_every_size_and_the_preset_embeds_it() -> void:
	var f := FileAccess.open("res://icon.ico", FileAccess.READ)
	assert_object(f).override_failure_message("res://icon.ico is missing (python tools/make_win_icon.py)").is_not_null()
	assert_int(f.get_16()).is_equal(0)
	assert_int(f.get_16()).is_equal(1)
	var count := f.get_16()
	var sizes: Array = []
	for i in count:
		var w := f.get_8()
		var h := f.get_8()
		f.get_8()
		f.get_8()
		f.get_16()
		assert_int(f.get_16()).is_equal(32)
		f.get_32()
		f.get_32()
		assert_int(w).is_equal(h)
		sizes.append(256 if w == 0 else w)
	# Godot keeps 16, 32, 48, 64, 128 and 256 in the exe; the others serve the running window at other scales
	for s in [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]:
		assert_bool(sizes.has(s)).override_failure_message("no %d px icon" % s).is_true()
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var win := ""
	for sec in cfg.get_sections():
		if str(cfg.get_value(sec, "name", "")) == "Windows Desktop":
			win = sec
	assert_str(win).is_not_empty()
	var opts := win + ".options"
	assert_str(str(cfg.get_value(opts, "application/icon", ""))).is_equal("res://icon.ico")
	assert_bool(bool(cfg.get_value(opts, "application/modify_resources", false))).is_true()
	# empty: the exe's version is application/config/version (EditorExportPreset.get_version), kept in step by itself
	assert_str(str(cfg.get_value(opts, "application/file_version", "x"))).is_empty()
	assert_str(str(cfg.get_value(opts, "application/product_version", "x"))).is_empty()
	for k in ["application/company_name", "application/product_name", "application/file_description"]:
		assert_str(str(cfg.get_value(opts, k, ""))).override_failure_message(k).is_not_empty()
	# signing stays off in the preset: ship.sh signs only when tools/keys/codesign.env exists
	assert_bool(bool(cfg.get_value(opts, "codesign/enable", true))).is_false()
	# the .ico travels in the pack (the running window's icon reads it from res://)
	assert_str(str(cfg.get_value(win, "include_filter", ""))).contains("*.ico")
