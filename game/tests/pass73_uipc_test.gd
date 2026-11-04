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
	_keep = {"preview": Settings.preview_locked_heroes, "inset": Settings.top_inset,
		"data": Save.data.duplicate(true)}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Stage.forget()
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Settings.top_inset = int(_keep["inset"])
	Save.data = _keep["data"]
	Save._dirty = false


func _title(style: String) -> Control:
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





# ---------------------------------------------------------------- everything fits, one set of sizes







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
