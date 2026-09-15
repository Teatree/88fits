## After a run: time, stage, level, kills, gold with the extract bonus shown, damage by weapon, quest ticks.
extends ScreenBase


func build() -> void:
	var s := Run.summary()
	set_title("EXTRACTED" if s["extracted"] else "RUN OVER")
	title_label.add_theme_color_override("font_color", UiKit.GOOD if s["extracted"] else UiKit.DANGER)
	Audio.play_music(["mu_results"], 1)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 8)
	var gold: int = int(s["gold"])
	var bonus := int(round(gold * 1.25)) - gold if s["extracted"] else 0
	var rows := [
		["Time survived", TextGen.time_mmss(float(s["time"]))],
		["Stage reached", ("endless" if Run.endless else str(s["stage"]))],
		["Level", str(s["level"])],
		["Kills", str(s["kills"])],
		["Gold collected", str(gold)],
		["Extract bonus ×1.25", ("+%d" % bonus) if s["extracted"] else "—"],
		["Chests opened", str(s["chests"])],
		["Evolutions", str(s["evolutions"])],
	]
	for r in rows:
		grid.add_child(UiKit.label(r[0], 30, UiKit.INK2))
		grid.add_child(UiKit.label(r[1], 30, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT))
	var p := UiKit.panel()
	p.add_child(grid)
	content.add_child(p)
	if not Save.hint_seen("results"):
		Save.mark_hint("results")
		content.add_child(UiKit.label("Gold is permanent. Spend it in the Shop on upgrades that last forever.", 26, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	# damage by weapon
	var dmg: Dictionary = s["damage_by_weapon"]
	if not dmg.is_empty():
		content.add_child(UiKit.label("Damage by weapon", 30, UiKit.INK3))
		var total := 0.0
		for v in dmg.values():
			total += float(v)
		var keys := dmg.keys()
		keys.sort_custom(func(a, b): return float(dmg[a]) > float(dmg[b]))
		for k in keys:
			var def := Registry.weapon(k)
			var h := UiKit.hbox(14)
			if def:
				h.add_child(UiKit.icon_view(def, 72, "weapon"))
			var bar := ProgressBar.new()
			bar.max_value = max(total, 1.0)
			bar.value = float(dmg[k])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 40)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.add_theme_stylebox_override("background", UiKit.stylebox(UiKit.BG3, 20))
			bar.add_theme_stylebox_override("fill", UiKit.stylebox(UiKit.ACCENT, 20))
			h.add_child(bar)
			var l := UiKit.label("%s  %d (%d%%)" % [def.display_name if def else k, int(dmg[k]), int(100.0 * float(dmg[k]) / max(total, 1.0))], 24, UiKit.INK2, HORIZONTAL_ALIGNMENT_RIGHT)
			l.custom_minimum_size = Vector2(380, 0)
			l.size_flags_horizontal = Control.SIZE_SHRINK_END
			h.add_child(l)
			content.add_child(h)
	# quests completed this run
	if not QuestTracker.just_completed.is_empty():
		content.add_child(UiKit.label("Unlocked this run", 30, UiKit.GOOD))
		for id in QuestTracker.just_completed:
			var q: QuestDef = Registry.quests.get(id)
			if q:
				content.add_child(UiKit.label("✓ %s: %s" % [q.display_name, TextGen.quest_text(q)], 26, UiKit.INK2))
		QuestTracker.just_completed.clear()
	# quest progress
	var pending: Array = []
	for q in Registry.quests.values():
		if not Save.quest_done(q.id):
			var pt := QuestTracker.progress_text(q)
			if pt != "":
				pending.append("%s: %s  (%s)" % [q.display_name, TextGen.quest_text(q), pt])
	if not pending.is_empty():
		content.add_child(UiKit.label("Progress", 30, UiKit.INK3))
		for line in pending:
			content.add_child(UiKit.label(line, 24, UiKit.INK2))
	content.add_child(UiKit.spacer(10))
	var again := UiKit.button("Play again", 44, true, 130)
	again.pressed.connect(func(): go("res://game/Game.tscn"))
	content.add_child(again)
	var row := UiKit.hbox(16)
	var shop := UiKit.button("Shop", 32, false, 100)
	shop.pressed.connect(func(): go("res://ui/ShopScreen.tscn"))
	var hub := UiKit.button("Title", 32, false, 100)
	hub.pressed.connect(func(): go(TITLE))
	row.add_child(shop)
	row.add_child(hub)
	content.add_child(row)


func on_back() -> void:
	go(TITLE)
