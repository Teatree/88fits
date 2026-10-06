## The Content dock: every item by type with its icon, warnings for missing fields, "New <type>" buttons
## that duplicate a template folder, and "Test" that launches the game with the item equipped.
@tool
extends VBoxContainer

const TYPES := ["weapons", "evolutions", "passives", "mutations", "perks", "enemies", "bosses", "elites", "characters", "shop", "quests", "maps"]
const ROOT := "res://content/"

var plugin: EditorPlugin
var _tree: Tree
var _status: Label
var _type_opt: OptionButton


func _ready() -> void:
	custom_minimum_size = Vector2(260, 300)
	var top := HBoxContainer.new()
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(_refresh)
	top.add_child(refresh)
	var reimport := Button.new()
	reimport.text = "JSON → .tres"
	reimport.tooltip_text = "Regenerate every .tres from its .json"
	reimport.pressed.connect(_reimport)
	top.add_child(reimport)
	add_child(top)
	var newrow := HBoxContainer.new()
	_type_opt = OptionButton.new()
	for t: String in TYPES:
		_type_opt.add_item(t)
	newrow.add_child(_type_opt)
	var newbtn := Button.new()
	newbtn.text = "New from template"
	newbtn.pressed.connect(_new_item)
	newrow.add_child(newbtn)
	add_child(newrow)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 60)
	_tree.item_activated.connect(_open_selected)
	_tree.button_clicked.connect(_on_button)
	add_child(_tree)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_refresh()


func _refresh() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var problems := 0
	var total := 0
	for t: String in TYPES:
		var dir := DirAccess.open(ROOT + t + "/")
		if dir == null:
			continue
		var titem := _tree.create_item(root)
		titem.set_text(0, t.capitalize())
		titem.set_selectable(0, false)
		for sub: String in dir.get_directories():
			var folder := ROOT + t + "/" + sub + "/"
			var item := _tree.create_item(titem)
			item.set_text(0, sub)
			item.set_metadata(0, folder)
			total += 1
			var warn := ""
			if not FileAccess.file_exists(folder + sub + ".json"):
				warn += "no json "
			if not ResourceLoader.exists(folder + sub + ".tres"):
				warn += "no tres "
			var icon_ok := ResourceLoader.exists(folder + sub + "_icon.png")
			if not icon_ok:
				warn += "no icon "
			if warn != "":
				problems += 1
				item.set_text(1, "!")
				item.set_tooltip_text(1, warn)
				item.set_custom_color(0, Color(1.0, 0.7, 0.3))
			if t in ["weapons", "evolutions", "enemies", "bosses", "characters"]:
				item.add_button(1, EditorInterface.get_editor_theme().get_icon("Play", "EditorIcons"), 0, false, "Test-launch the game with this item")
			if icon_ok:
				var tex = load(folder + sub + "_icon.png")
				if tex is Texture2D:
					item.set_icon(0, tex)
					item.set_icon_max_width(0, 20)
	_status.text = "%d items, %d with warnings. Double-click opens the .tres." % [total, problems]


func _open_selected() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var folder := str(item.get_metadata(0))
	if folder == "":
		return
	var id := item.get_text(0)
	var tres := folder + id + ".tres"
	if ResourceLoader.exists(tres):
		EditorInterface.edit_resource(load(tres))
	else:
		EditorInterface.get_file_system_dock().navigate_to_path(folder)


func _on_button(item: TreeItem, _column: int, _id: int, _mouse: int) -> void:
	var folder := str(item.get_metadata(0))
	var id := item.get_text(0)
	var type := item.get_parent().get_text(0).to_lower()
	var launch := {}
	match type:
		"weapons", "evolutions":
			launch = {"weapon": id, "level": 4}
		"characters":
			launch = {"character": id, "spawn": true}
		"enemies", "bosses":
			launch = {"weapon": "boomstick", "spawn_enemy": id}
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(launch))
	f.close()
	EditorInterface.play_custom_scene("res://game/Game.tscn")


func _reimport() -> void:
	var script := load("res://tools/import_json.gd")
	# Run the importer in-process: it is a SceneTree script, so call its logic through a helper.
	var count := 0
	for t: String in TYPES:
		var dir := DirAccess.open(ROOT + t + "/")
		if dir == null:
			continue
		for sub: String in dir.get_directories():
			var folder := ROOT + t + "/" + sub + "/"
			var json := folder + sub + ".json"
			if not FileAccess.file_exists(json):
				continue
			var d := JsonContent.load_json(json)
			var res := JsonContent.build(t, d, folder)
			if res:
				ResourceSaver.save(res, folder + sub + ".tres")
				count += 1
	EditorInterface.get_resource_filesystem().scan()
	_status.text = "Regenerated %d .tres files." % count
	_refresh()


func _new_item() -> void:
	var type: String = TYPES[_type_opt.selected]
	var dir := DirAccess.open(ROOT + type + "/")
	if dir == null:
		_status.text = "No folder for " + type
		return
	var subs := dir.get_directories()
	if subs.is_empty():
		_status.text = "No template item in " + type
		return
	var template: String = subs[0]
	var n := 1
	var new_id := "new_%s_%d" % [type.trim_suffix("s"), n]
	while dir.dir_exists(new_id):
		n += 1
		new_id = "new_%s_%d" % [type.trim_suffix("s"), n]
	var src := ROOT + type + "/" + template + "/"
	var dst := ROOT + type + "/" + new_id + "/"
	DirAccess.make_dir_recursive_absolute(dst)
	var d := JsonContent.load_json(src + template + ".json")
	d["id"] = new_id
	d["name"] = new_id.capitalize()
	d["icon"] = new_id + "_icon.png"
	if d.has("visual"):
		d["visual"] = new_id + "_visual.tscn"
	if d.has("sprite"):
		d["sprite"] = new_id + "_sprite.png"
	var f := FileAccess.open(dst + new_id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	for file in ["_visual.tscn", "_icon.png", "_sprite.png"]:
		if FileAccess.file_exists(src + template + file):
			DirAccess.copy_absolute(src + template + file, dst + new_id + file)
	var res := JsonContent.build(type, d, dst)
	if res:
		ResourceSaver.save(res, dst + new_id + ".tres")
	EditorInterface.get_resource_filesystem().scan()
	_status.text = "Created %s. Edit %s.tres in the Inspector." % [new_id, new_id]
	_refresh()
