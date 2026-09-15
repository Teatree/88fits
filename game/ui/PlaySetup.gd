## Pick a character, pick a map, GO. Locked ones show their quest text.
extends ScreenBase

var _char_id := ""
var _map_id := ""


func build() -> void:
	set_title("Play")
	_char_id = str(Save.data.get("last_character", "astro"))
	_map_id = str(Save.data.get("last_map", "dry_gulch"))
	_refresh()


func _refresh() -> void:
	clear_content()
	content.add_child(UiKit.label("Character", 34, UiKit.INK3))
	for c in Registry.sorted_characters():
		content.add_child(_char_card(c))
	content.add_child(UiKit.spacer(10))
	content.add_child(UiKit.label("Map", 34, UiKit.INK3))
	for m in Registry.sorted_maps():
		content.add_child(_map_card(m))
	content.add_child(UiKit.spacer(10))
	var go := UiKit.button("GO", 60, true, 150)
	go.pressed.connect(_go)
	content.add_child(go)


func _card_button(selected: bool, locked: bool) -> TapCard:
	return UiKit.card(UiKit.ACCENT if selected else UiKit.LINE, 5 if selected else 2, UiKit.BG2 if not locked else UiKit.BG)


func _fill(b: Control, def: ContentDef, kind: String, lines: Array, locked: bool) -> void:
	var texts: Array = [[def.display_name + (" 🔒" if locked else ""), 40, UiKit.INK if not locked else UiKit.INK3]]
	for line in lines:
		texts.append([line, 26, UiKit.INK2 if not locked else UiKit.INK3])
	UiKit.card_body(b, def, kind, 128, texts)
	if locked:
		b.modulate = Color(0.72, 0.72, 0.78)


func _char_card(c: CharacterDef) -> Control:
	var locked := not Registry.is_unlocked("character", c.id)
	var b := _card_button(_char_id == c.id, locked)
	var lines: Array = []
	var trait_text := TextGen.describe_effects(c.trait_effects)
	if trait_text != "":
		lines.append("Trait: " + trait_text)
	for s in c.specials:
		lines.append({"cannot_stop": "Cannot stop moving.", "auto_magnet": "Wider gem pull."}.get(s, s))
	var fav := Registry.weapon(c.favourite_weapon)
	if fav:
		lines.append("Favourite: %s" % fav.display_name)
	if locked:
		var q := Registry.quest_for("character", c.id)
		lines.append("Unlock: " + (TextGen.quest_text(q) if q else "?"))
	else:
		lines.append(c.flavour)
	_fill(b, c, "character", lines, locked)
	if not locked:
		b.pressed.connect(func(): _char_id = c.id; Audio.play("ui_tap"); _refresh())
	else:
		b.pressed.connect(func(): Audio.play("ui_locked"))
	return b


func _map_card(m: MapDef) -> Control:
	var locked := not Registry.is_unlocked("map", m.id)
	var b := _card_button(_map_id == m.id, locked)
	var lines: Array = [m.flavour]
	var best := Save.best_run(m.id)
	if not best.is_empty():
		lines.append("Best: %s · level %d · stage %d" % [TextGen.time_mmss(float(best.get("time", 0.0))), int(best.get("level", 0)), int(best.get("stage", 0))])
	if locked:
		var q := Registry.quest_for("map", m.id)
		lines.append("Unlock: " + (TextGen.quest_text(q) if q else "?"))
	_fill(b, m, "map", lines, locked)
	if not locked:
		b.pressed.connect(func(): _map_id = m.id; Audio.play("ui_tap"); _refresh())
	else:
		b.pressed.connect(func(): Audio.play("ui_locked"))
	return b


func _go() -> void:
	Save.data["last_character"] = _char_id
	Save.data["last_map"] = _map_id
	Save.request_save()
	go("res://game/Game.tscn")
