## Results (Wanted screen 16): the hero and the gold first, the tables last. "★ EXTRACTED ★" (or RUN OVER) over the
## time survived and one line of the run; a panel with the hero's portrait and what was banked, counting up, the purse
## before and after, and a NEW BEST seal hanging off it when the run beat the map's best; damage by weapon as bars with
## the name and number inside the fill; what the run unlocked; PLAY AGAIN, then Upgrade and Main Menu. A death (pass 44)
## shows the gold left in the sand, struck through, and what a Strongbox banked on the way.
extends ScreenBase

var _count: WText
var _banked := 0


func use_header() -> bool:
	return false


func board_top() -> float:
	return 70.0


func board_side() -> float:
	return 60.0


func board_bottom() -> float:
	# PLAY AGAIN (132) and the two buttons under it (91), 22 apart, 80 off the bottom, and a gap
	return 80.0 + 132.0 + 22.0 + 91.0 + 30.0


func build() -> void:
	var s := Run.summary()
	var res: Dictionary = Run.last_result
	Audio.play_music(["mu_results"], 1)
	content.add_theme_constant_override("separation", 0)
	# the head: the star line, the time, one line of the run
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(WStarLine.make("Extracted" if s["extracted"] else "Run over", 30, W.INK))
	head.add_child(W.slab_text(W.mmss(float(s["time"])), 120, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 120.0))
	var bits: Array = ["Endless" if Run.endless else "Stage %d" % int(s["stage"]), W.lv(int(s["level"])), "%s kills" % W.num(int(s["kills"])),
		"%d chest%s" % [int(s["chests"]), "" if int(s["chests"]) == 1 else "s"], "%d evolution%s" % [int(s["evolutions"]), "" if int(s["evolutions"]) == 1 else "s"]]
	var line := W.serif_text(" · ".join(bits), 30, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	line.custom_minimum_size.y = 42
	head.add_child(line)
	content.add_child(head)
	content.add_child(_gap(130))
	# the hero and the gold: banked on an extraction; on a death the purse stays in the sand (pass 44), all but what
	# a Strongbox put away
	var before := int(res.get("gold_before", Save.gold()))
	_banked = int(res.get("banked", s["gold"]))
	var lost := int(res.get("lost", 0))
	var strongbox := int(res.get("strongbox", 0))
	var dead: bool = s["died"] or lost > 0
	var hero := PanelContainer.new()
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(42, 36, 42, 36))
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 30)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(hr)
	if Run.character:
		var p := WPlate.new().for_def(Run.character, 212.0)
		p.border = 6
		p.fill = W.AGED
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hr.add_child(p)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 8)
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gv.add_child(W.serif_text("Left in the sand" if dead else "Banked", 26, W.ROCK if dead else W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 14)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gr.add_child(WCoin.make(64.0, W.AGED if dead else W.BRASS, 4.0))
	_count = W.slab_text("0", 110, W.ROCK if dead else W.BRASS_DARK, HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	_count.strike = dead
	gr.add_child(_count)
	gv.add_child(gr)
	if dead:
		_banked = lost
		var purse := "The purse stays at %s" % W.num(before)
		if strongbox > 0:
			purse = "%s banked by the Strongbox on the way · the purse stays at %s" % [W.num(strongbox), W.num(before)]
		gv.add_child(W.serif_text(purse, 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	else:
		gv.add_child(W.serif_text("%s → %s" % [W.num(before), W.num(before + _banked)], 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	if not Save.hint_seen("results"):
		Save.mark_hint("results")
		gv.add_child(W.serif_text("Only an extraction brings the gold home. Spend it on Upgrades." if dead else "Gold is kept. Spend it on Upgrades.",
			24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	hr.add_child(gv)
	var hero_host := Control.new()
	hero_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prev: Dictionary = res.get("prev_best", {})
	var new_best := not prev.is_empty() and float(s["time"]) > float(prev.get("time", 0.0)) + 0.5
	content.add_child(hero)
	if new_best:
		var seal := WSeal.new()
		seal.side = 162.0
		seal.fill = W.ROCK
		seal.border = 6
		seal.ring = 8
		seal.word = "NEW\nBEST"
		seal.text_size = 20
		seal.rotation = deg_to_rad(12.0)
		seal.pivot_offset = Vector2(81, 81)
		hero.add_child(seal)
		# a free child: the panel lays out the rest (and resets its turn), the seal hangs off its top-right corner
		hero.sort_children.connect(func():
			seal.size = Vector2(162, 162)
			seal.pivot_offset = Vector2(81, 81)
			seal.rotation = deg_to_rad(12.0)
			seal.position = Vector2(hero.size.x - 162.0 + 30.0, -40.0))
	# damage by weapon
	var dmg: Dictionary = s["damage_by_weapon"]
	if not dmg.is_empty():
		content.add_child(_gap(76))
		content.add_child(W.label("Damage by weapon", 22, W.INK_SOFT))
		content.add_child(_gap(16))
		var total := 0.0
		for v in dmg.values():
			total += float(v)
		var keys := dmg.keys()
		keys.sort_custom(func(a, b): return float(dmg[a]) > float(dmg[b]))
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 16)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in keys:
			var def := Registry.weapon(k)
			var frac := float(dmg[k]) / maxf(total, 1.0)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 20)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if def:
				var p2 := WPlate.new().for_def(def, 96.0)
				p2.icon_frac = 0.7
				h.add_child(p2)
			var bar := WBar.make(frac, W.BRASS, 52.0, 4, 0)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.text_px = 26
			# the name and number ride inside the fill when it is wide enough to hold them
			var label := "%s · %s" % [def.display_name if def else k, W.num(int(dmg[k]))]
			if frac > 0.14:
				bar.text = label
			h.add_child(bar)
			var pc := W.slab_text("%d%%" % int(round(frac * 100.0)), 28, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
			pc.custom_minimum_size.x = 90
			pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(pc)
			rows.add_child(h)
		content.add_child(rows)
	# what the run unlocked
	if not QuestTracker.just_completed.is_empty():
		content.add_child(_gap(66))
		for id in QuestTracker.just_completed:
			var q: QuestDef = Registry.quests.get(id)
			if q == null:
				continue
			content.add_child(_unlocked(q))
			content.add_child(_gap(16))
		QuestTracker.just_completed.clear()
	_count_up.call_deferred()
	# the buttons: PLAY AGAIN, then Upgrade and Main Menu
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 60
	col.offset_right = -60
	col.offset_bottom = -80
	col.offset_top = -80 - 132 - 22 - 91
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var again := WButton.make(["PLAY AGAIN"], 72, WButton.PRIMARY, 6, 10, 24.0, 0.0, 72.0)
	again.pressed.connect(func(): go("res://game/Game.tscn"))
	col.add_child(again)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for spec in [["Upgrade", "res://ui/HomesteadScreen.tscn", WButton.PRIMARY], ["Main Menu", TITLE, WButton.SECONDARY]]:
		var b := WButton.make([spec[0]], 30, spec[2], 5, 6, 20.0, 0.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var path: String = spec[1]
		b.pressed.connect(func(): go(path))
		row.add_child(b)
	col.add_child(row)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## One unlock: the item's plate, UNLOCKED in sage, its name, and what earned it on the right.
func _unlocked(q: QuestDef) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 5, 6).pad(31, 25, 31, 25))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var def := _reward(q)
	if def:
		var pl := WPlate.new().for_def(def, 96.0)
		pl.icon_frac = 0.7
		h.add_child(pl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(W.label("Unlocked", 18, W.SAGE))
	v.add_child(W.slab_text(def.display_name if def else q.display_name, 36, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 36.0))
	h.add_child(v)
	var why := W.serif_text(TextGen.quest_text(q), 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, true)
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	why.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(why)
	return p


## What a quest hands over ({"type": "character|weapon|passive|map", "id"}).
func _reward(q: QuestDef) -> ContentDef:
	var id := str(q.unlocks.get("id", ""))
	match str(q.unlocks.get("type", "")):
		"weapon":
			return Registry.weapon(id)
		"passive":
			return Registry.passive(id)
		"character":
			return Registry.character(id)
		"map":
			return Registry.map(id)
	return null


## The banked gold counts up over 900 ms with an ease-out (the lost gold too, struck through).
func _count_up() -> void:
	var tw := create_tween()
	var pre := "−" if _count.strike else "+"
	tw.tween_method(func(v: float): _count.text = pre + W.num(int(round(v))), 0.0, float(_banked), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func on_back() -> void:
	go(TITLE)
