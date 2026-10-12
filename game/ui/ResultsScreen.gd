## Results (Wanted screen 16): the hero and the gold first, the tables last. "★ EXTRACTED ★" (or RUN OVER) over the
## time survived and one line of the run; a panel with the hero's portrait and what was banked, counting up, the purse
## before and after, and a NEW BEST seal hanging off it when the run beat the map's best; the damage dealt, one row a
## source (pass 47, Garry: "Each row must have both the icon and the text, with the absolute value of damage dealt":
## the plate, the name and the number over a bar of its share, the percent beside it, for every weapon, perk, power-up,
## fire, poison, the revive's blast and explosions, and a "?" plate for anything unknown); what the run unlocked; PLAY
## AGAIN, then Upgrade (turquoise, pass 46: brass is for buying) and Main Menu. A death (pass 44) shows the gold left in the sand, struck through, and what a Strongbox banked on
## the way, by its coin. The hero's last hits are on the Down! screen since pass 46, not here.
extends ScreenBase

## The damage sources' own pictures (pass 47, painted by the lead; until one is there its plate shows a "?").
const SOURCE_ART := "res://art/ui/sources/%s.png"
## Damage ids that are not an item: [picture, name]. A picture is a file in SOURCE_ART, or "passive:<id>" for a
## passive's icon (poison is Venom's, thorns Bristle's, pass 48 the Powder Keg's blast the Powder Keg's; the explosions'
## picture while a passive has no icon or is not in the game). Several ids can be one source ("burn" and "fire").
const SOURCES := {
	"": ["unknown", "Unknown"],
	"revive": ["revive", "Revive blast"],
	"fire": ["fire", "Fire"], "burn": ["fire", "Fire"], "burning": ["fire", "Fire"], "flames": ["fire", "Fire"],
	"poison": ["passive:venom", "Poison"], "toxic": ["passive:venom", "Poison"],
	"blast": ["blast", "Explosions"], "explosion": ["blast", "Explosions"], "loose_rocket": ["blast", "Explosions"],
	"thorns": ["passive:bristle", "Thorns"],
	"powder_keg": ["passive:powder_keg", "Powder Keg"],
	# pass 69: Hot Springs' heal pulses
	"hot_springs": ["passive:hot_springs", "Hot Springs"],
}

var _count: WText
var _banked := 0
## The end-of-run survey (pass 59): PostHog's questions, when Analytics has one due, SURVEY_DELAY after the screen comes in.
const WSurveyScript := preload("res://ui/wanted/WSurvey.gd")
const SURVEY_DELAY := 1.4
var _survey: Control


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
		# his badge in the look he was played in (pass 68, Registry.played_look)
		var p := WPlate.new().for_def(Registry.played_look(Run.character), 212.0)
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
			# what the Strongbox kept is gold the run brought home: its coin goes in front (pass 46)
			var sb := HBoxContainer.new()
			sb.name = "Strongbox"
			sb.add_theme_constant_override("separation", 10)
			sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var coin := WCoin.make(30.0, W.BRASS, 3.0)
			coin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			sb.add_child(coin)
			var said := W.serif_text("%s banked by the Strongbox on the way · the purse stays at %s" % [W.num(strongbox), W.num(before)],
				26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
			said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sb.add_child(said)
			gv.add_child(sb)
		else:
			gv.add_child(W.serif_text(purse, 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	else:
		gv.add_child(W.serif_text("%s → %s" % [W.num(before), W.num(before + _banked)], 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	if not Save.hint_seen("results"):
		Save.mark_hint("results")
		gv.add_child(W.serif_text("Only an extraction brings the gold home. Spend it on Upgrades." if dead else "Gold is kept. Spend it on Upgrades.",
			24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	hr.add_child(gv)
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
	# the damage dealt, by source (pass 47: every row its plate, its name and its number)
	var dmg: Dictionary = s["damage_by_weapon"]
	if not dmg.is_empty():
		content.add_child(_gap(76))
		content.add_child(W.label("Damage dealt", 22, W.INK_SOFT))
		content.add_child(_gap(16))
		content.add_child(damage_rows(dmg))
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
	_offer_survey.call_deferred(float(s["time"]))
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
	for spec in [["Upgrade", "res://ui/HomesteadScreen.tscn", WButton.UPGRADE], ["Main Menu", TITLE, WButton.SECONDARY]]:
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


## What dealt damage under the id Run.add_damage was handed (pass 47): {key, name, def, icon}. A weapon, perk,
## power-up, passive, mutation, creature or structure is its content item (its plate, its icon); fire, poison, the
## revive's blast, explosions and thorns have their own picture (SOURCES); anything else is unknown, a "?" plate named
## after its id ("" is "Unknown"). `key` joins the ids that are one source.
static func damage_source(id: String) -> Dictionary:
	if SOURCES.has(id):
		var spec: Array = SOURCES[id]
		var pic := str(spec[0])
		var icon: Texture2D = null
		if pic.begins_with("passive:"):
			var pd: PassiveDef = Registry.passive(pic.substr(8))
			icon = pd.icon if pd else null
			if icon == null:
				var blast := SOURCE_ART % "blast"
				icon = load(blast) as Texture2D if ResourceLoader.exists(blast) else null
		else:
			var path := SOURCE_ART % pic
			icon = load(path) as Texture2D if ResourceLoader.exists(path) else null
		return {"key": "source:" + str(spec[1]), "name": str(spec[1]), "def": null, "icon": icon}
	var def: ContentDef = Registry.weapon(id)
	if def == null:
		def = Registry.perk(id)
	if def == null:
		def = Registry.pickup(id)
	if def == null:
		def = Registry.passive(id)
	if def == null:
		def = Registry.mutation(id)
	if def == null:
		def = Registry.enemy(id)
	if def == null:
		def = Registry.structure(id)
	if def:
		return {"key": id, "name": def.display_name, "def": def, "icon": def.icon}
	var unknown := SOURCE_ART % "unknown"
	return {"key": "id:" + id, "name": id.replace("_", " ").capitalize(), "def": null,
		"icon": load(unknown) as Texture2D if ResourceLoader.exists(unknown) else null}


## The damage dealt, one row a source, biggest first: the ids that are one source summed into one row.
static func damage_rows(dmg: Dictionary) -> VBoxContainer:
	var by_key: Dictionary = {}
	var total := 0.0
	for id in dmg.keys():
		var amount := float(dmg[id])
		total += amount
		var src := damage_source(str(id))
		var k := str(src["key"])
		if by_key.has(k):
			by_key[k]["amount"] = float(by_key[k]["amount"]) + amount
		else:
			src["amount"] = amount
			by_key[k] = src
	var sources: Array = by_key.values()
	sources.sort_custom(func(a, b): return float(a["amount"]) > float(b["amount"]))
	var rows := VBoxContainer.new()
	rows.name = "DamageRows"
	rows.add_theme_constant_override("separation", 18)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for src in sources:
		rows.add_child(damage_row(src, float(src["amount"]) / maxf(total, 1.0)))
	return rows


## One source: its 96 px plate (the item's in its kind's colour; a paper plate with the source's picture, or a "?"),
## the name and the damage in slab over a bar of its share, and the percent at the end ("<1%" for a sliver).
static func damage_row(src: Dictionary, frac: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Source"
	h.set_meta("source", src)
	h.add_theme_constant_override("separation", 20)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(source_plate(src, 96.0))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := W.slab_text(str(src["name"]), 30, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	nm.name = "Name"
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var num := W.slab_text(W.num(float(src["amount"])), 30, W.BRASS_DARK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	num.name = "Amount"
	top.add_child(num)
	mid.add_child(top)
	var bar := WBar.make(frac, W.BRASS, 26.0, 4, 0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(bar)
	h.add_child(mid)
	var pct := roundf(frac * 100.0)
	var pc := W.slab_text("<1%" if frac > 0.0 and pct < 1.0 else "%d%%" % int(pct), 28, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	pc.name = "Share"
	pc.custom_minimum_size.x = 96
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pc)
	return h


## The level an item ended the run at (pass 48: its plate's colour): a weapon held, its level; one that evolved, the top
## level it evolved from; a passive or a line, its level, a line that evolved its top; 1 for anything else not held.
static func final_level(def: ContentDef) -> int:
	if def is WeaponDef:
		for w in Run.weapons:
			var inst: WeaponInstance = w
			if inst.def == def:
				return inst.level
			if inst.def.is_evolution and inst.def.evolved_from == def.id:
				return (def as WeaponDef).max_level
		return 1
	if def is PassiveDef:
		var pd := def as PassiveDef
		var lv := Run.passive_level(pd.id)
		if lv > 0:
			return lv
		if pd.evolves_into != "" and Run.passive_level(pd.evolves_into) > 0:
			return pd.max_level
		return 1
	return 0


## A source's plate: the item's own (in the colour of the level it ended at, pass 48), else a paper plate with the
## source's picture, else a "?".
static func source_plate(src: Dictionary, px: float) -> WPlate:
	var p := WPlate.new()
	var def: ContentDef = src.get("def")
	if def:
		p.for_def(def, px, false, final_level(def))
	else:
		p.side = px
		p.fill = W.PAPER
		p.tex = src.get("icon")
		if p.tex == null:
			p.glyph = "?"
	p.icon_frac = 0.7
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


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
	# pass 69: a hero to buy is not his yet: on sale, still unknown (his badge black with a "?")
	var on_sale := def is CharacterDef and (def as CharacterDef).availability == "purchase"
	if def:
		var pl := WPlate.new().for_def(def, 96.0)
		pl.icon_frac = 0.7
		pl.mystery = on_sale
		h.add_child(pl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(W.label("For sale" if on_sale else "Unlocked", 18, W.SAGE))
	v.add_child(W.slab_text("A new hero" if on_sale else (def.display_name if def else q.display_name), 36, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 36.0))
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
			# drawn in the look he is played in (pass 68, Registry.played_look)
			return Registry.played_look(Registry.character(id))
		"map":
			return Registry.map(id)
	return null


## The banked gold counts up over 900 ms with an ease-out (the lost gold too, struck through).
func _count_up() -> void:
	var tw := create_tween()
	var pre := "−" if _count.strike else "+"
	tw.tween_method(func(v: float): _count.text = pre + W.num(int(round(v))), 0.0, float(_banked), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func on_back() -> void:
	# the back gesture closes the survey card first ("Not now")
	if is_instance_valid(_survey) and not bool(_survey.call("is_done")):
		_survey.call("dismiss")
		return
	go(TITLE)


## Asks Analytics whether this run brings a survey (pass 59: at most one every few runs of a minute or more, never in a
## run's first minute, never twice a session, never after "Don't ask me again") and opens it after a beat.
func _offer_survey(run_seconds: float) -> void:
	var sv: Dictionary = Analytics.survey_after_run(run_seconds)
	if sv.is_empty():
		return
	await get_tree().create_timer(SURVEY_DELAY).timeout
	if not is_inside_tree():
		return
	_survey = WSurveyScript.open(self, sv)
