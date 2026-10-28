## The Bounty Board (pass 111, lane WANTED; core/systems/WantedBoard.gd): before a stage run, once the save has finished a
## run, PLAY on the title, a card on the Stages menu and PLAY AGAIN on the Results open it instead of the run
## (WantedBoard.run_scene). Three Wanted posters nailed side by side (ui/wanted/WPoster.gd: the target's still, the task,
## the reward, the difficulty in skulls), the same three every time the board is opened for that stage and hero until a
## choice is made (WantedBoard.board_for); a tap picks one (the brass ring, the card under them says it in full), TAKE IT
## stamps it TAKEN and starts the run with it, "No bounty" starts the run without one. The header: the back square (the
## Stages menu when it opens for the map, else the title), "Bounty Board", the hero's badge on the right.
extends ScreenBase

const POSTER_GAP := 18.0
## The posters' tilt (degrees), left to right, and the chosen one's lift.
const TILTS := [-2.5, 1.5, 3.0]
const PICK_SCALE := 1.04
const TAKE_DELAY := 0.55
const CTA := "Pick a bounty"
const DIFFICULTY_WORDS := ["Easy", "Fair", "Hard", "Tough", "Deadly"]

var map_id := ""
var stage := 0
var hero: CharacterDef
var posters: Array = []
var _cards: Array = []
var _picked := -1
var _detail: VBoxContainer
var _take: WButton
var _none: WButton
var _reroll: WButton
var _row: HBoxContainer
## Tests and tools: what a choice last made ("" none yet, "taken", "none"), and set to keep a choice from leaving.
var chosen := ""
var hold_start := false
## A choice is on its way to the run (a second tap does nothing).
var _leaving := false


func build() -> void:
	set_title("Bounty Board")
	map_id = str(Save.data.get("last_map", "red_canyon"))
	if Registry.map(map_id) == null:
		map_id = "red_canyon"
	stage = Run.stage_next
	hero = Registry.playable_character(str(Save.data.get("last_character", Save.DEFAULT_HERO)))
	if hero and header:
		var hp := WPlate.new().for_def(Registry.played_look(hero), 100.0)
		hp.border = 5
		hp.fill = W.AGED
		hp.name = "Hero"
		header.set_right(hp)
	content.add_theme_constant_override("separation", 26)
	var m := Registry.map(map_id)
	var k: int = m.timeline.stage_clamp(stage) if m and m.timeline else 0
	stage = k
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sname: String = m.timeline.stage_name(k) if m and m.timeline else ""
	head.add_child(W.label("Stage %d · %s · %s" % [k + 1, sname, hero.display_name if hero else ""], 22, W.INK_SOFT))
	var cta := W.slab_text(CTA, 52, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 57.0)
	cta.name = "CallToAction"
	head.add_child(cta)
	head.add_child(W.serif_text("One contract for this run. Done, it pays its gold when the run ends, however it ends.", 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	content.add_child(head)
	posters = WantedBoard.board_for(map_id, k, hero.id if hero else "")
	_row = HBoxContainer.new()
	_row.name = "Posters"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", int(POSTER_GAP))
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(_row)
	_fill_row()
	_detail = VBoxContainer.new()
	_detail.name = "Detail"
	_detail.add_theme_constant_override("separation", 8)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := ScreenBase.board(Vector2(28, 22), 8, 5)
	card.name = "DetailCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_detail)
	content.add_child(card)
	_build_buttons()
	_show_detail()


func board_top() -> float:
	return 196.0


func board_bottom() -> float:
	return 80.0 + 124.0 + 20.0 + 96.0 + 30.0


## The posters nailed in a row, each in a plain holder (a container would reset its tilt), tilted a little.
func _fill_row() -> void:
	for c in _row.get_children():
		c.queue_free()
	_cards.clear()
	_picked = -1
	var room := 984.0
	var n := maxi(posters.size(), 1)
	var w := minf(WPoster.W_PX, (room - POSTER_GAP * float(n - 1)) / float(n))
	for i in posters.size():
		var holder := Control.new()
		holder.name = "Holder%d" % (i + 1)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var p := WPoster.make(posters[i], w)
		p.name = "Poster%d" % (i + 1)
		holder.custom_minimum_size = p.custom_minimum_size + Vector2(0, 24)
		holder.add_child(p)
		p.position = Vector2(0, 8)
		p.pivot_offset = p.size * 0.5
		p.rotation = deg_to_rad(float(TILTS[i % TILTS.size()]))
		p.set_meta("index", i)
		p.pressed.connect(_on_poster.bind(i))
		_row.add_child(holder)
		_cards.append(p)
	UiFx.stagger(_row, 0.07)


func _build_buttons() -> void:
	var col := VBoxContainer.new()
	col.name = "Buttons"
	col.add_theme_constant_override("separation", 20)
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 48
	col.offset_right = -48
	col.offset_bottom = -80
	col.offset_top = -80 - 124 - 20 - 96
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_take = WButton.make(["TAKE IT"], 60, WButton.PRIMARY, 6, 10, 26.0, 0.0, 60.0)
	_take.name = "Take"
	_take.pressed.connect(_on_take)
	col.add_child(_take)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	_none = WButton.make(["No bounty"], 32, WButton.SECONDARY, 5, 6, 22.0, 0.0)
	_none.name = "NoBounty"
	_none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_none.pressed.connect(_on_none)
	row.add_child(_none)
	var left := WantedBoard.rerolls_left(map_id, stage, hero.id if hero else "")
	if left > 0:
		_reroll = WButton.make(["Re-roll"], 32, WButton.SECONDARY, 5, 6, 22.0, 0.0)
		_reroll.name = "Reroll"
		_reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_reroll.pressed.connect(_on_reroll)
		row.add_child(_reroll)
	_take.locked = true


## The card under the posters: the chosen poster in full words, or what to do.
func _show_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _picked < 0 or _picked >= posters.size():
		var hint := W.serif_text("Tap a poster to read it. Harder bounties pay more." if not posters.is_empty() else "No bounty can be posted for this stage yet.",
			26, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
		hint.name = "Hint"
		_detail.add_child(hint)
		if _take:
			_take.locked = true
		return
	var c: Dictionary = posters[_picked]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := W.slab_text(str(c.get("name", "")).to_upper(), 36, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 40.0)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var dw := W.text(difficulty_word(int(c.get("skulls", 1))), W.serif(700, false, W.em(24, 0.04)), 24, _tone(int(c.get("skulls", 1))), HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	dw.name = "Difficulty"
	dw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(dw)
	_detail.add_child(top)
	var task := W.serif_text(str(c.get("text", "")) + ".", 30, W.INK, 600, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	task.name = "Task"
	_detail.add_child(task)
	var pay := HBoxContainer.new()
	pay.add_theme_constant_override("separation", 10)
	pay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pay.add_child(W.serif_text("Pays", 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var coin := WCoin.make(30.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pay.add_child(coin)
	pay.add_child(W.slab_text(W.num(int(c.get("reward", 0))), 32, W.BRASS_DARK, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	pay.add_child(W.serif_text("when the run ends, only if done.", 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	_detail.add_child(pay)
	_detail.add_child(W.serif_text("Its progress shows on the HUD while you play.", 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	if _take:
		_take.locked = false


static func difficulty_word(skulls: int) -> String:
	return DIFFICULTY_WORDS[clampi(skulls - 1, 0, DIFFICULTY_WORDS.size() - 1)]


static func _tone(skulls: int) -> Color:
	return W.SAGE if skulls <= 1 else (W.BRASS_DARK if skulls <= 3 else W.ROCK)


func _on_poster(i: int) -> void:
	if i < 0 or i >= _cards.size():
		return
	_picked = i
	for j in _cards.size():
		var p: WPoster = _cards[j]
		p.selected = j == i
		var tw := p.create_tween()
		tw.tween_property(p, "scale", Vector2.ONE * (PICK_SCALE if j == i else 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "rotation", 0.0 if j == i else deg_to_rad(float(TILTS[j % TILTS.size()])), 0.12)
	_show_detail()


## Which poster is chosen (-1 none): tests and tools.
func picked() -> int:
	return _picked


func cards() -> Array:
	return _cards


func _on_take() -> void:
	if _picked < 0 or _picked >= posters.size() or _leaving:
		Audio.play("ui_locked")
		return
	var p: WPoster = _cards[_picked]
	# on the poster's plain top layer (the poster is a container: a stamp put in it would be stretched over it whole)
	var st := WStamp.make("TAKEN", W.ROCK, 52)
	st.name = "Taken"
	var layer: Control = p.get_node_or_null("Over")
	(layer if layer else p).add_child(st)
	st.position = Vector2(p.size.x * 0.5 - st.size.x * 0.5, p.size.y * 0.3)
	st.rotation = deg_to_rad(-12.0)
	st.slam(0.22)
	W.sfx("ui_stamp")
	_start(posters[_picked], TAKE_DELAY)


func _on_none() -> void:
	_start({}, 0.0)


func _on_reroll() -> void:
	var fresh := WantedBoard.reroll(map_id, stage, hero.id if hero else "")
	if fresh.is_empty():
		Audio.play("ui_locked")
		return
	posters = fresh
	_fill_row()
	_show_detail()
	var left := WantedBoard.rerolls_left(map_id, stage, hero.id if hero else "")
	if _reroll:
		_reroll.visible = left > 0


## The choice made: handed to the run (WantedBoard.choose: every kept board goes) and the run starts, `delay` seconds on
## (the stamp's landing).
func _start(contract: Dictionary, delay: float) -> void:
	if _leaving:
		return
	chosen = "taken" if not contract.is_empty() else "none"
	if hold_start:
		return
	_leaving = true
	WantedBoard.choose(contract)
	Save.request_save()
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	load("res://ui/TitleStage.gd").forget()
	go(WantedBoard.GAME)


## Back: the Stages menu when it opens for the map, else the title.
func on_back() -> void:
	go("res://ui/StagesScreen.tscn" if StagesScreenScript.opens_for(map_id) else TITLE)


const StagesScreenScript := preload("res://ui/StagesScreen.gd")
