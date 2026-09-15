## Every weapon, evolution, passive, enemy, boss, and character. Locked items show their quest.
## Tap an item for its full generated description.
extends ScreenBase

var _expanded := ""


func build() -> void:
	set_title("Collection")
	_refresh()


func _refresh() -> void:
	clear_content()
	_section("Weapons", Registry.base_weapons(), "weapon")
	var evos: Array = Registry.weapons.values().filter(func(w): return w.is_evolution)
	evos.sort_custom(func(a, b): return a.id < b.id)
	_section("Evolutions", evos, "evolution")
	var passives: Array = Registry.passives.values()
	passives.sort_custom(func(a, b): return a.id < b.id)
	_section("Passives", passives, "passive")
	_section("Characters", Registry.sorted_characters(), "character")
	var enemies: Array = Registry.enemies.values()
	enemies.sort_custom(func(a, b): return a.id < b.id)
	_section("Enemies", enemies, "enemy")
	var quests_done := 0
	for q in Registry.quests.values():
		if Save.quest_done(q.id):
			quests_done += 1
	content.add_child(UiKit.label("%d / %d unlocks done · %d kills all time" % [quests_done, Registry.quests.size(), Save.total("kills")], 24, UiKit.INK3, HORIZONTAL_ALIGNMENT_CENTER))


func _section(title: String, items: Array, kind: String) -> void:
	content.add_child(UiKit.label(title, 34, UiKit.INK3))
	for def in items:
		content.add_child(_row(def, kind))


func _locked(def: ContentDef, kind: String) -> bool:
	match kind:
		"weapon", "passive", "character":
			return not Registry.is_unlocked(kind, def.id)
		"evolution":
			return Save.keyed_total("kills_with_weapon", def.id) == 0 and Save.total("evolutions") == 0
		"enemy":
			return Save.keyed_total("kills_of_enemy", def.id) == 0
	return false


func _row(def: ContentDef, kind: String) -> Control:
	var locked := _locked(def, kind)
	var expanded := _expanded == def.id
	var p := UiKit.panel(UiKit.BG2 if not locked else UiKit.BG, 22, UiKit.ACCENT if expanded else UiKit.LINE, 3 if expanded else 2)
	var v := UiKit.vbox(8)
	p.add_child(v)
	var b := TapCard.new()
	b.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	b.pressed.connect(func(): _expanded = "" if expanded else def.id; Audio.play("ui_tap"); _refresh())
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_top", 4)
	hm.add_theme_constant_override("margin_bottom", 4)
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hm)
	var h := UiKit.hbox(20)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hm.add_child(h)
	var ic := UiKit.icon_view(def, 100, kind)
	if locked:
		ic.modulate = Color(0.35, 0.35, 0.4)
	h.add_child(ic)
	var nv := UiKit.vbox(2)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := UiKit.label(("???" if locked and kind == "enemy" else def.display_name), 34, UiKit.INK if not locked else UiKit.INK3)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.add_child(nl)
	var sub := ""
	if locked:
		var q := Registry.quest_for(kind, def.id)
		if q:
			sub = "Unlock: " + TextGen.quest_text(q) + ("  (%s)" % QuestTracker.progress_text(q) if QuestTracker.progress_text(q) != "" else "")
		elif kind == "evolution":
			var from := Registry.weapon(def.evolved_from)
			sub = "Evolve %s with %s at a chest." % [from.display_name if from else def.evolved_from, Registry.passive(from.evolves_with).display_name if from and Registry.passive(from.evolves_with) else "its passive"]
		elif kind == "enemy":
			sub = "Not met yet."
	else:
		sub = def.flavour
	var sl := UiKit.label(sub, 22, UiKit.INK3)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.add_child(sl)
	h.add_child(nv)
	v.add_child(b)
	if expanded and not locked:
		v.add_child(UiKit.label(_describe(def, kind), 26, UiKit.INK2))
	return p


func _describe(def: ContentDef, kind: String) -> String:
	if def is WeaponDef:
		var tmp := WeaponInstance.new(def, 1)
		tmp.rebuild(StatSheet.new(), [])
		var s := tmp.description()
		if not def.is_evolution and def.evolves_into != "":
			var into := Registry.weapon(def.evolves_into)
			var with_p := Registry.passive(def.evolves_with)
			s += " Evolves into %s with %s." % [into.display_name if into else def.evolves_into, with_p.display_name if with_p else def.evolves_with]
		return s
	if def is PassiveDef:
		return TextGen.passive_description(def, 1) + (" Pairs with %s." % Registry.weapon(def.pairs_with).display_name if Registry.weapon(def.pairs_with) else "")
	if def is CharacterDef:
		return "Trait: %s. Favourite weapon: %s." % [TextGen.describe_effects(def.trait_effects), Registry.weapon(def.favourite_weapon).display_name if Registry.weapon(def.favourite_weapon) else "?"]
	if def is EnemyDef:
		return "%s. HP %d, speed %.1f, damage %d. Killed %d times." % [def.archetype.capitalize(), int(def.hp), def.speed, int(def.damage), Save.keyed_total("kills_of_enemy", def.id)]
	return def.flavour
