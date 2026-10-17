## The Watch's panel (pass 80, lane WATCH; REQUEST.md's seven parts): 1 the header (hero, board, seed, the bot, the
## clock and stage, the speed controls), 2 the live numbers, 3 the charts (the last 3 minutes scrolling, or the whole
## run; DPS against the crowd, HP over Danger, level and XP, the damage share; a grey line for the Sim's average of the
## same hero and board), 4 the decision log (the bot's, with the real DPS change 30 s after a pick), 5 the build and the
## strip of when each item came, 6 the threat (what hurt the hero in the last 10 s, the falls and their last hits, the
## bot's intent), 7 after the run, where the record and the decision log were saved. Plain Godot controls in a dark
## tool style (the Level Editor's), refreshed once a second by Watch.gd; the charts when new rows came (at most twice a
## wall second). Pass 82: the Live tiles "Chests", "Power-ups", "Totems" (the run's totals so far, lane STATS' meaning;
## each value in its mark's colour) and "Specials" (killed / came), and on the Level and XP chart a mark at each pickup's
## moment, a shape and colour per kind, with the totals in its legend. Tools only.
extends PanelContainer

const CHART := preload("res://tools/watch/WatchChart.gd")
const STRIP := preload("res://tools/watch/WatchStrip.gd")
const DATA := preload("res://tools/watch/WatchData.gd")
const CLOCK := preload("res://tools/watch/WatchClock.gd")

const BG := Color(0.082, 0.09, 0.11)
const CARD := Color(0.105, 0.115, 0.14)
const EDGE := Color(0.2, 0.22, 0.27)
const TEXT := Color(0.86, 0.89, 0.94)
const DIM := Color(0.56, 0.6, 0.68)
const ACCENT := Color(0.93, 0.66, 0.26)
const GOOD := Color(0.47, 0.83, 0.5)
const BAD := Color(0.95, 0.42, 0.36)
const BLUE := Color(0.43, 0.71, 1.0)
const PURPLE := Color(0.72, 0.55, 0.96)
const GREY := Color(0.62, 0.64, 0.68, 0.85)
## the damage share's colours, biggest source first; "other" last
const SHARE_COLS := [Color(0.98, 0.62, 0.3), Color(0.43, 0.71, 1.0), Color(0.47, 0.83, 0.5), Color(0.86, 0.5, 0.93),
	Color(0.98, 0.85, 0.35), Color(0.4, 0.85, 0.85), Color(0.5, 0.52, 0.58)]
## the window the charts scroll over, seconds of play
const WINDOW_S := 180.0
## pass 82: the pickups' marks on the Level and XP chart: [kind, word, colour, shape, lane]
const PICKUP_MARKS := [["chests", "Chests", Color(0.98, 0.8, 0.3), "square", 2], ["powerups", "Power-ups", Color(0.42, 0.88, 0.62), "circle", 1],
	["totems", "Totems", Color(0.95, 0.55, 0.8), "triangle", 0]]
## the decision log shows at most this many entries, newest first
const LOG_MAX := 60

var watch: Node
var whole_run := false
## pass 83 (lane SCALE): the first chart shows the hero's power instead of the DPS (Watch.toggle_power, P)
var show_power := false
var _power_btn: Button
var show_goals := true

var _title: Label
var _sub: Label
var _speed_btns: Dictionary = {}
var _pause_btn: Button
var _window_btn: Button
var _sound_btn: Button
var _goals_btn: Button
var _end_btn: Button
var _status: Label
var _tiles: Dictionary = {}
var _charts: Array = []
var _log: RichTextLabel
## pass 85 (lane TOOLS): the build as chips with the game's icons (weapons and their mutations, evolutions, cards, items,
## perks), wrapping in rows
var _build_box: VBoxContainer
var _restart_btn: Button
var _strip
var _threat: RichTextLabel
var _end_box: PanelContainer
var _end_text: RichTextLabel
var _log_key := ""
var _build_key := ""
var _share_cols: Dictionary = {}


func build(w: Node) -> void:
	watch = w
	theme = _theme()
	add_theme_stylebox_override("panel", _box(BG, 0, 0))
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	m.add_child(col)
	col.add_child(_header())
	_end_box = PanelContainer.new()
	_end_box.add_theme_stylebox_override("panel", _box(Color(0.16, 0.13, 0.08), 6, 8, ACCENT))
	_end_text = _rich(15)
	_end_text.fit_content = true
	_end_text.meta_clicked.connect(_on_meta)
	_end_box.add_child(_end_text)
	_end_box.visible = false
	col.add_child(_end_box)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var a := VBoxContainer.new()
	a.add_theme_constant_override("separation", 6)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.size_flags_stretch_ratio = 1.12
	body.add_child(a)
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 6)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = 0.88
	body.add_child(b)
	# 2: the live numbers
	a.add_child(_section("Live"))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	a.add_child(grid)
	for spec in [["dps", "Real DPS"], ["est", "Estimated DPS"], ["hp", "HP"], ["danger", "Danger"], ["keep", "Keeping up"],
			["close", "Creatures close"], ["kills", "Kills"], ["level", "Level"], ["gold", "Gold"], ["crowd", "Crowd"],
			["chests", "Chests"], ["powerups", "Power-ups"], ["totems", "Totems"], ["specials", "Specials"], ["power", "Power"]]:
		grid.add_child(_tile(str(spec[0]), str(spec[1])))
	# 3: the charts
	var ch_head := HBoxContainer.new()
	ch_head.add_child(_section("Charts"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch_head.add_child(sp)
	_window_btn = _button("Whole run", "show the whole run instead of the last 3 minutes (G)", func() -> void: watch.toggle_window())
	ch_head.add_child(_window_btn)
	_power_btn = _button("Power", "the first chart: the DPS, or the hero's power level (P): sqrt((full DPS / 20.4) x (effective HP / 100)), a fresh level-1 Drifter = 1", func() -> void: watch.toggle_power())
	ch_head.add_child(_power_btn)
	a.add_child(ch_head)
	for t in ["DPS against the crowd", "HP, and Danger beneath", "Level and XP", "Damage share by source"]:
		var c = CHART.new()
		c.title = t
		c.custom_minimum_size = Vector2(0, 72)
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		a.add_child(c)
		_charts.append(c)
	# 4: the decision log
	var lg_head := HBoxContainer.new()
	lg_head.add_child(_section("Decisions"))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lg_head.add_child(sp2)
	_goals_btn = _button("Goals shown", "the bot's walking goals in the log, or only its picks", func() -> void:
		show_goals = not show_goals
		_log_key = ""
		refresh())
	lg_head.add_child(_goals_btn)
	b.add_child(lg_head)
	_log = _rich(13)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.size_flags_stretch_ratio = 2.2
	b.add_child(_card(_log, true))
	# 5: the build (pass 85: icons and names, wrapping)
	b.add_child(_section("Build"))
	var bsc := ScrollContainer.new()
	bsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bsc.size_flags_stretch_ratio = 0.9
	_build_box = VBoxContainer.new()
	_build_box.add_theme_constant_override("separation", 4)
	_build_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bsc.add_child(_build_box)
	b.add_child(_card(bsc, true))
	_strip = STRIP.new()
	_strip.custom_minimum_size = Vector2(0, 80)
	b.add_child(_strip)
	# 6: the threat
	b.add_child(_section("Threat"))
	_threat = _rich(13)
	_threat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_threat.size_flags_stretch_ratio = 1.0
	b.add_child(_card(_threat, true))


# ---------------------------------------------------------------- the pieces

func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14
	th.set_color("font_color", "Label", TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	th.set_color("font_disabled_color", "Button", DIM)
	th.set_stylebox("normal", "Button", _box(Color(0.15, 0.165, 0.2), 4, 6, EDGE))
	th.set_stylebox("hover", "Button", _box(Color(0.2, 0.22, 0.27), 4, 6, Color(0.35, 0.38, 0.45)))
	th.set_stylebox("pressed", "Button", _box(ACCENT, 4, 6, ACCENT))
	th.set_stylebox("disabled", "Button", _box(Color(0.12, 0.13, 0.16), 4, 6, EDGE))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return th


func _box(col: Color, radius: int, pad: int, edge: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(pad - 2, 0)
	s.content_margin_bottom = maxi(pad - 2, 0)
	if edge.a > 0.0:
		s.border_color = edge
		s.set_border_width_all(1)
	return s


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_font_size_override("font_size", 12)
	return l


func _rich(fs: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = true
	r.selection_enabled = false
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_size_override("bold_font_size", fs)
	r.focus_mode = Control.FOCUS_NONE
	return r


func _card(inner: Control, expand: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(CARD, 6, 8, EDGE))
	p.add_child(inner)
	if expand:
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.size_flags_stretch_ratio = inner.size_flags_stretch_ratio
	return p


func _button(text: String, tip: String, cb: Callable) -> Button:
	var bt := Button.new()
	bt.text = text
	bt.tooltip_text = tip
	bt.focus_mode = Control.FOCUS_NONE
	bt.pressed.connect(cb)
	return bt


func _tile(key: String, label: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(CARD, 6, 8, EDGE))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 12)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(l)
	var val := Label.new()
	val.text = "-"
	val.add_theme_font_size_override("font_size", 22)
	v.add_child(val)
	var sub := Label.new()
	sub.text = " "
	sub.add_theme_color_override("font_color", DIM)
	sub.add_theme_font_size_override("font_size", 11)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	_tiles[key] = [val, sub]
	return p


func _header() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 19)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_color_override("font_color", DIM)
	_sub.add_theme_font_size_override("font_size", 13)
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	_pause_btn = _button("Pause", "pause or go on (Space)", func() -> void: watch.toggle_pause())
	_pause_btn.custom_minimum_size = Vector2(76, 0)
	row.add_child(_pause_btn)
	var keys := ["1", "2", "3", "4", "5", "6"]
	for i in range(CLOCK.SPEEDS.size()):
		var s := float(CLOCK.SPEEDS[i])
		var bt := _button(CLOCK.label(s), "run at %s (key %s)" % [CLOCK.label(s), keys[i]], func() -> void: watch.set_speed(s))
		bt.toggle_mode = true
		bt.custom_minimum_size = Vector2(52, 0)
		row.add_child(bt)
		_speed_btns[s] = bt
	row.add_child(_button("Step 1 s", "play one second, then pause (.)", func() -> void: watch.step_second()))
	row.add_child(_button("Next level-up", "run at 8x until the next level-up's cards, then pause before the bot picks (L)",
		func() -> void: watch.run_to_level()))
	_sound_btn = _button("Sound", "sound on or off (M); above 1x it is always off", func() -> void: watch.toggle_sound())
	row.add_child(_sound_btn)
	# the status takes the room left and trims itself (a narrow window keeps the buttons whole)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size = Vector2(40, 0)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_status)
	_end_btn = _button("End run", "end the run now: the record and the decision log are saved", func() -> void: watch.end_now())
	row.add_child(_end_btn)
	# pass 85: the Hero Settings pop-up again (the run ends when the new one starts) (R)
	_restart_btn = _button("Restart run", "choose the next run's settings (hero, look, board, seed, bot ...): Start Run ends this run (recorded) and starts that one down the spawn beam (R)",
		func() -> void: watch.open_setup(true))
	row.add_child(_restart_btn)
	return v


func _on_meta(meta) -> void:
	watch.open_meta(str(meta))


## The charts' and the strip's drawing time since the last call (microseconds), set back to 0.
func take_draw_us() -> int:
	var us := 0
	for c in _charts:
		us += int(c.draw_us)
		c.draw_us = 0
	if _strip:
		us += int(_strip.draw_us)
		_strip.draw_us = 0
	return us


## Pass 85: a new run in this window: the per-run memory goes (the log's and the build's keys, the share chart's colours,
## the build's chips).
func reset_run() -> void:
	_log_key = ""
	_build_key = ""
	_share_cols = {}
	if _build_box != null:
		for c in _build_box.get_children():
			_build_box.remove_child(c)
			c.queue_free()
	if _strip != null:
		_strip.arrivals = []


# ---------------------------------------------------------------- once a second

func refresh() -> void:
	if watch == null:
		return
	var w := watch
	var clk = w.clock
	var data = w.data
	var run: Node = w.run_node()
	var game: Node = w.game if w.game != null and is_instance_valid(w.game) else null
	# 1: the header
	var stage_txt := ""
	if run:
		var ph := ""
		if game and game.get("director") != null:
			# pass 87 (lane STOOLS): the portal's countdown and Endless (phase 3) with its wave
			ph = ["", " · boss", " · portal", " · Endless"][clampi(int(game.director.phase), 0, 3)] if int(game.director.phase) <= 3 else " · phase %d" % int(game.director.phase)
			if int(game.director.phase) == 2 and game.director.has_method("portal_seconds_left") and float(game.director.portal_seconds_left()) >= 0.0:
				ph += " %s" % DATA.mmss(float(game.director.portal_seconds_left()))
			if int(game.director.phase) == 3 and run.has_method("endless_wave"):
				ph += " wave %d" % int(run.endless_wave())
		# pass 87: the stage's name and its own clock (a stage run's clock starts at its window)
		var st_name := ""
		if run.get("map") != null and run.map.timeline != null and run.map.timeline.has_method("stage_name"):
			st_name = " " + str(run.map.timeline.stage_name(int(run.stage)))
		var st_clock: float = float(run.stage_clock()) if run.has_method("stage_clock") else float(run.elapsed)
		stage_txt = "stage %d%s%s · clock %s · played %s" % [int(run.stage) + 1, st_name, ph, DATA.mmss(st_clock), DATA.mmss(w.play_t())]
	_title.text = "%s  ·  %s" % [w.hero_name(), stage_txt if stage_txt != "" else ("Hero Settings: choose the run, then Start Run" if w.setup_open() and game == null else "starting…")]
	_sub.text = w.header_words()
	_pause_btn.text = "Go on" if clk.paused else "Pause"
	for s in _speed_btns:
		var bt: Button = _speed_btns[s]
		bt.set_pressed_no_signal(not clk.paused and clk.mode == "" and absf(float(s) - clk.speed) < 0.001)
	_window_btn.text = "Last 3 min" if whole_run else "Whole run"
	_power_btn.text = "DPS" if show_power else "Power"
	_goals_btn.text = "Goals shown" if show_goals else "Goals hidden"
	_sound_btn.text = "Sound on" if w.sound_on else "Sound off"
	_end_btn.disabled = w.ended or game == null
	_restart_btn.disabled = w.setup_open()
	_status.text = w.status_words()
	_status.tooltip_text = _status.text
	_status.add_theme_color_override("font_color", BAD if clk.short() else DIM)
	# 7: after the run
	_end_box.visible = w.ended
	if w.ended:
		var txt: String = w.end_words()
		if _end_text.text != txt:
			_end_text.text = txt
	# 2: the live numbers
	_live(w, data, run, game)
	# 4, 5, 6
	_decisions(w, data)
	_build_text(w, data, run)
	_threat_text(w, data, game)


func _set_tile(key: String, val: String, sub: String = " ", col: Color = TEXT) -> void:
	var t: Array = _tiles[key]
	(t[0] as Label).text = val
	(t[0] as Label).add_theme_color_override("font_color", col)
	(t[1] as Label).text = sub if sub != "" else " "


func _live(w: Node, data, run: Node, game: Node) -> void:
	var n: int = data.size()
	var i := n - 1
	var player = game.get("player") if game else null
	if i < 0:
		for k in _tiles:
			_set_tile(k, "-")
		return
	_set_tile("dps", _num(data.dps5[i]), "%s this second · 5 s mean" % _num(data.dps[i]), ACCENT)
	# pass 83 (lane SCALE): the hero's power level (HeroPower)
	_set_tile("power", "%.2f" % data.power[i] if data.power[i] > 0.0 else "-", "fresh Drifter = 1")
	var est: float = data.est[i]
	var ratio := "%d%% of it real" % int(roundf(100.0 * data.dps5[i] / est)) if est >= 1.0 else ""
	_set_tile("est", _num(est), ratio)
	var hp := float(player.hp) if player else float(data.hp[i])
	var mx := float(player.max_hp) if player else float(data.hp_max[i])
	var hp_col := GOOD if hp >= 0.6 * mx else (ACCENT if hp >= 0.3 * mx else BAD)
	_set_tile("hp", "%d / %d" % [int(ceil(hp)), int(roundf(mx))], "%d%%" % int(roundf(100.0 * hp / maxf(mx, 1.0))), hp_col)
	var dg: float = data.danger[i]
	_set_tile("danger", "%.1f%%" % dg, "max HP lost a second (5 s)", BAD if dg >= 3.0 else (ACCENT if dg >= 1.0 else TEXT))
	var ku: float = data.keep_up[i]
	_set_tile("keep", "-" if ku < 0.0 else "%.1f s" % ku, "to clear the crowd at this DPS", BAD if ku > 30.0 else TEXT)
	_set_tile("close", "%d · %d" % [data.near3[i], data.near6[i]], "within 3 m · 6 m", BAD if data.near3[i] >= 4 else TEXT)
	var kills := int(run.kills) if run else int(data.kills[i])
	_set_tile("kills", "%d" % kills, "%.1f a second (10 s)" % _rate(data.kills, 10))
	if run:
		var xn := float(run.xp_to_next())
		_set_tile("level", "%d" % int(run.level), "%d / %d XP · %d to go" % [int(run.xp), int(xn), int(maxf(xn - float(run.xp), 0.0))], BLUE)
		_set_tile("gold", "%d" % int(run.run_gold), "this run's purse")
	else:
		_set_tile("level", "%d" % data.level[i])
		_set_tile("gold", "%d" % data.gold[i])
	var cap := 0
	if game and game.get("director") != null:
		cap = int(game.director.current_cap())
	_set_tile("crowd", ("%d / %d" % [data.alive[i], cap]) if cap > 0 else "%d" % data.alive[i], "%s HP alive%s" % [_num(data.crowd[i]),
		" · the cap now" if cap > 0 else ""], PURPLE)
	_pickup_tiles(data)


## Pass 82: the run's chests, power-ups and totems so far (each in its mark's colour), and the specials killed of those
## that came.
func _pickup_tiles(data) -> void:
	var tot: Dictionary = data.pickup_totals()
	var subs := {"chests": "opened, skips too", "powerups": "taken, not the small", "totems": "gifts taken"}
	for m in PICKUP_MARKS:
		var k := str(m[0])
		_set_tile(k, "%d" % int(tot[k]), str(subs[k]), m[2])
	var sc := int(data.special_chests)
	_set_tile("specials", "%d / %d" % [int(data.specials_killed), int(data.specials_came)], "killed / came%s" % (
		(" · %d chest%s" % [sc, "" if sc == 1 else "s"]) if sc > 0 else ""), Color(0.95, 0.55, 0.8) if int(data.specials_came) > int(data.specials_killed) else TEXT)


## The per-second rate of a running count over its newest `secs` rows.
static func _rate(a: PackedInt32Array, secs: int) -> float:
	var n := a.size()
	if n < 2:
		return 0.0
	var k := mini(secs, n - 1)
	return float(a[n - 1] - a[n - 1 - k]) / float(k)


static func _num(v: float) -> String:
	if v >= 100000.0:
		return "%dk" % int(roundf(v / 1000.0))
	if v >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	return "%d" % int(roundf(v))


static func _hex(c: Color) -> String:
	return c.to_html(false)


func _decisions(w: Node, data) -> void:
	var list: Array = data.decisions
	var key := "%d|%d|%s" % [list.size(), _filled(list), str(show_goals)]
	if key == _log_key:
		return
	_log_key = key
	var out := PackedStringArray()
	var shown := 0
	var goals_in_row := 0
	for j in range(list.size() - 1, -1, -1):
		if shown >= LOG_MAX:
			break
		var d: Dictionary = list[j]
		var kind := str(d.get("kind", ""))
		if kind == "goal":
			if not show_goals:
				continue
			goals_in_row += 1
			if goals_in_row > 6:
				continue
			out.append("[color=#%s]%s · goal: %s[/color]" % [_hex(DIM), DATA.mmss(float(d.get("clock", 0.0))), _esc(str(d.get("reason", d.get("taken", ""))))])
			shown += 1
			continue
		goals_in_row = 0
		shown += 1
		out.append(_entry(w, d))
	if out.is_empty():
		out.append("[color=#%s]No decisions yet: the bot's level-up picks, mutation offers, chests, totems, the Stranger, the shop and its goals land here.[/color]" % _hex(DIM))
	_log.text = "\n".join(out)


static func _filled(list: Array) -> int:
	var n := 0
	for d in list:
		if bool(d.get("filled", false)):
			n += 1
	return n


func _entry(w: Node, d: Dictionary) -> String:
	var kind := str(d.get("kind", ""))
	var lines := PackedStringArray()
	var head := "[color=#%s]%s · Lv %d · %s[/color]" % [_hex(DIM), DATA.mmss(float(d.get("clock", 0.0))), int(d.get("level", 0)), kind]
	lines.append(head)
	var taken := str(d.get("taken", ""))
	for o in d.get("offered", []):
		if not (o is Dictionary):
			continue
		var id := str(o.get("id", ""))
		var nm: String = str(o.get("name", "")) if str(o.get("name", "")) != "" else str(w.name_of(id))
		var parts := ""
		var pd = o.get("parts", {})
		if pd is Dictionary and not (pd as Dictionary).is_empty():
			var ps := PackedStringArray()
			for k in pd:
				var v = pd[k]
				ps.append("%s %s" % [str(k), ("%.2f" % float(v)) if (v is float or v is int) else str(v)])
			parts = "  [color=#%s](%s)[/color]" % [_hex(DIM), _esc(" · ".join(ps))]
		var score = o.get("score", null)
		var sc := ("%.2f" % float(score)) if (score is float or score is int) else ""
		if id == taken and taken != "":
			lines.append("  [color=#%s]✓ %s[/color]  %s%s" % [_hex(ACCENT), _esc(nm), sc, parts])
		else:
			lines.append("    %s  %s%s" % [_esc(nm), sc, parts])
	if (d.get("offered", []) as Array).is_empty() and taken != "":
		lines.append("  [color=#%s]✓ %s[/color]" % [_hex(ACCENT), _esc(w.name_of(taken))])
	var why := str(d.get("reason", ""))
	if why != "":
		lines.append("  [i]%s[/i]" % _esc(why))
	if kind in ["card", "mutation", "chest", "stranger", "shop", "totem"]:
		if bool(d.get("filled", false)):
			var b := float(d.get("real_before", -1.0))
			var a := float(d.get("real_after", -1.0))
			var c := float(d.get("real_change", NAN))
			var col := GOOD if (not is_nan(c) and c >= 0.0) else BAD
			var pct := ("%+d%%" % int(roundf(c))) if not is_nan(c) else "n/a"
			lines.append("  real DPS, 30 s before and after: %s → %s  [color=#%s]%s[/color]" % [_num(maxf(b, 0.0)), _num(maxf(a, 0.0)), _hex(col), pct])
		else:
			lines.append("  [color=#%s]real DPS after it: in %d s[/color]" % [_hex(DIM), int(ceil(maxf(float(d.get("t", 0.0)) + DATA.AFTER_S - w.play_t(), 0.0)))])
	return "\n".join(lines) + "\n"


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _build_text(w: Node, data, run: Node) -> void:
	if run == null:
		return
	var key := build_key(run)
	if key != _build_key:
		_build_key = key
		_build_chips(w, run)
	_strip.arrivals = data.arrivals
	_strip.now = maxf(w.play_t(), 60.0)
	for a in data.arrivals:
		w.name_of(str(a["id"]))
	_strip.names = w.names
	_strip.queue_redraw()


## What the build holds, as a key (the chips are made again only when it changes): each weapon, its level and
## mutations, each card and item and its level, each perk.
static func build_key(run) -> String:
	var parts := PackedStringArray()
	for wi in run.weapons:
		var ms := PackedStringArray()
		for m in wi.mutations:
			ms.append(str(m.id))
		parts.append("%s:%d:%s" % [str(wi.def.id), int(wi.level), ",".join(ms)])
	for id in run.passives:
		parts.append("%s=%d" % [str(id), int(run.passives[id])])
	for p in run.perks:
		parts.append("perk:" + str(p))
	return "|".join(parts)


## The build as rows of chips, one row a kind (Weapons, Evolutions, Cards, Items, Perks): each chip the game's icon, the
## name and the level; a weapon's mutations follow it as smaller chips edged in purple. [[icon, name, level, mutation]]
## a group (a weapon and its mutations), the groups a row: build_rows (pure).
func _build_chips(w: Node, run: Node) -> void:
	for c in _build_box.get_children():
		_build_box.remove_child(c)
		c.queue_free()
	for r in build_rows(w, run):
		var list: Array = r[1]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		_build_box.add_child(line)
		var l := Label.new()
		l.text = str(r[0])
		l.custom_minimum_size = Vector2(74, 28)
		l.add_theme_color_override("font_color", DIM)
		l.add_theme_font_size_override("font_size", 12)
		l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(l)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(flow)
		if list.is_empty():
			var none := Label.new()
			none.text = "-"
			none.custom_minimum_size = Vector2(0, 28)
			none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			none.add_theme_color_override("font_color", DIM)
			flow.add_child(none)
			continue
		for group in list:
			for c in group:
				flow.add_child(_chip(c[0], str(c[1]), int(c[2]), bool(c[3])))


## The build's rows: [[word, [group, ...]], ...] for Weapons, Evolutions (when any), Cards, Items, Perks (when any); a
## group [[icon, name, level, mutation?], ...] (a weapon first, then its mutations, level -1).
static func build_rows(w: Node, run) -> Array:
	var weapons: Array = []
	var evos: Array = []
	for wi in run.weapons:
		var group: Array = [[wi.def.icon, str(wi.def.display_name), int(wi.level), false]]
		for m in wi.mutations:
			group.append([m.icon, str(m.display_name), -1, true])
		if bool(wi.def.is_evolution):
			evos.append(group)
		else:
			weapons.append(group)
	var cards: Array = []
	var items: Array = []
	for id in run.passives:
		var pd = w.passive_def(str(id))
		var chip: Array = [[pd.icon if pd != null else null, w.name_of(str(id)), int(run.passives[id]), false]]
		if pd != null and pd.has_method("is_line") and bool(pd.is_line()):
			cards.append(chip)
		else:
			items.append(chip)
	var perks: Array = []
	var reg: Node = w.get_node_or_null("/root/Registry")
	for p in run.perks:
		var pk = reg.perk(str(p)) if reg != null else null
		perks.append([[pk.icon if pk != null else null, w.name_of(str(p)), -1, false]])
	var rows: Array = [["Weapons", weapons]]
	if not evos.is_empty():
		rows.append(["Evolutions", evos])
	rows.append(["Cards", cards])
	rows.append(["Items", items])
	if not perks.is_empty():
		rows.append(["Perks", perks])
	return rows


## One chip: the icon (or the name's first letter), the name and the level (-1: none); `mut` a mutation's smaller chip.
func _chip(icon, nm_text: String, level: int, mut: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.13, 0.14, 0.17) if not mut else Color(0.14, 0.12, 0.19), 5, 4, PURPLE if mut else EDGE))
	p.tooltip_text = nm_text + ((" · level %d" % level) if level >= 0 else (" (mutation)" if mut else ""))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var px := 18 if mut else 24
	if icon is Texture2D:
		var t := TextureRect.new()
		t.texture = icon
		t.custom_minimum_size = Vector2(px, px)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
	else:
		var ph := Label.new()
		ph.text = nm_text.substr(0, 1)
		ph.custom_minimum_size = Vector2(px, px)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.add_theme_color_override("font_color", DIM)
		h.add_child(ph)
	var nm := Label.new()
	nm.text = nm_text
	nm.add_theme_font_size_override("font_size", 11 if mut else 13)
	nm.add_theme_color_override("font_color", Color(0.85, 0.8, 0.95) if mut else TEXT)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nm)
	if level >= 0:
		var lv := Label.new()
		lv.text = str(level)
		lv.add_theme_font_size_override("font_size", 13)
		lv.add_theme_color_override("font_color", ACCENT)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(lv)
	return p


func _threat_text(w: Node, data, game: Node) -> void:
	var lines := PackedStringArray()
	var bot = w.bot
	var intent := str(bot.get("intent")) if bot != null else "-"
	var goal = bot.get("goal") if bot != null else {}
	var gtxt := ""
	if goal is Dictionary and not (goal as Dictionary).is_empty():
		gtxt = str(goal.get("what", ""))
		var why := str(goal.get("why", ""))
		if why != "":
			# (pass 82: a special's why already says so: "a special: Red Goblin")
			gtxt = why if why.begins_with("a %s" % gtxt) else gtxt + ": " + why
	lines.append("[color=#%s]Intent[/color]  [color=#%s]%s[/color]%s" % [_hex(DIM), _hex(ACCENT), _esc(intent), ("   [color=#%s]goal[/color] %s" % [_hex(DIM), _esc(gtxt)]) if gtxt != "" else ""])
	var th: Array = data.threat(DATA.THREAT_S)
	if th.is_empty():
		lines.append("[color=#%s]Last 10 s[/color]  nothing hurt him" % _hex(DIM))
	else:
		var ps := PackedStringArray()
		for k in range(mini(th.size(), 6)):
			var e: Dictionary = th[k]
			var lost := float(e["lost"])
			var lost_txt := ("[color=#%s]-%d HP[/color]" % [_hex(BAD), int(roundf(lost))]) if lost >= 0.5 else "no HP lost"
			ps.append("%s %s (%d hit%s)" % [_esc(w.name_of(str(e["id"]))), lost_txt, int(e["hits"]), "" if int(e["hits"]) == 1 else "s"])
		lines.append("[color=#%s]Last 10 s[/color]  %s" % [_hex(DIM), " · ".join(ps)])
	if game and game.get("player") != null and game.player.dead:
		lines.append("[color=#%s]DOWN[/color]" % _hex(BAD))
	if data.falls.is_empty():
		lines.append("[color=#%s]Falls[/color]  none" % _hex(DIM))
	elif data.falls.size() > 3:
		lines.append("[color=#%s]Falls[/color]  %d, the newest first" % [_hex(DIM), data.falls.size()])
	# the newest falls first, at most three
	for k in range(data.falls.size() - 1, maxi(data.falls.size() - 4, -1), -1):
		var f: Dictionary = data.falls[k]
		var last := PackedStringArray()
		for h in f.get("last", []):
			if h is Dictionary:
				var dealt := float(h.get("dealt", 0.0))
				var note := str(h.get("note", ""))
				# a hit that took nothing and says nothing (an item's own touch) is left out
				if dealt < 0.5 and note == "":
					continue
				var amount := ("%d" % int(roundf(dealt))) if dealt >= 0.5 or note == "" else note
				last.append("%s %s%s" % [_esc(str(h.get("by", "?"))), amount, " (fatal)" if bool(h.get("fatal", false)) else ""])
		lines.append("[color=#%s]Fell[/color] at %s to %s%s%s" % [_hex(BAD), DATA.mmss(float(f["clock"])), _esc(w.name_of(str(f["killer"]))),
			(" (%s)" % str(f["hit"])) if str(f["hit"]) != "" else "", ("; last hits: " + ", ".join(last)) if not last.is_empty() else ""])
	_threat.text = "\n".join(lines)


# ---------------------------------------------------------------- the charts

func update_charts() -> void:
	if watch == null:
		return
	var data = watch.data
	var n: int = data.size()
	var last_t: float = data.t[n - 1] if n > 0 else 0.0
	var x1 := maxf(last_t, WINDOW_S) if not whole_run else maxf(last_t, 60.0)
	var x0 := 0.0 if whole_run else maxf(x1 - WINDOW_S, 0.0)
	var cols := 360
	var ref: Dictionary = watch.ref
	var marks: Array = []
	for f in data.falls:
		marks.append({"x": float(f["t"]), "color": Color(BAD.r, BAD.g, BAD.b, 0.8)})
	for c in _charts:
		c.x0 = x0
		c.x1 = x1
		c.marks = marks
		c.note = "" if n > 0 else "no rows yet"
	# 1: DPS against the crowd
	var c1 = _charts[0]
	var dps_pts: PackedVector2Array = DATA.bucket(data.t, data.dps5, x0, x1, cols)
	var est_pts: PackedVector2Array = DATA.bucket(data.t, data.est, x0, x1, cols)
	var crowd_pts: PackedVector2Array = DATA.bucket(data.t, data.crowd, x0, x1, cols)
	var ref_dps := _ref_pts(ref, "dps", x0, x1, cols)
	c1.series = [{"pts": crowd_pts, "color": PURPLE, "width": 1.2, "axis": 1, "fill": true}]
	if not ref_dps.is_empty():
		c1.series.append({"pts": ref_dps, "color": GREY, "width": 1.5, "axis": 0})
	c1.series.append({"pts": est_pts, "color": Color(0.98, 0.85, 0.35, 0.8), "width": 1.2, "axis": 0, "dashed": true})
	c1.series.append({"pts": dps_pts, "color": ACCENT, "width": 2.0, "axis": 0})
	c1.axes = [{"max": DATA.nice_max(maxf(maxf(_max_y(dps_pts), _max_y(est_pts)), _max_y(ref_dps))), "fmt": "k", "unit": ""},
		{"max": DATA.nice_max(_max_y(crowd_pts)), "fmt": "k", "unit": ""}, {"max": 0.0}]
	c1.legend = [["Real DPS (5 s)", ACCENT], ["Estimate", Color(0.98, 0.85, 0.35)], ["Crowd HP (right)", PURPLE]]
	if not ref_dps.is_empty():
		c1.legend.append(["Sim avg", GREY])
	c1.title = "DPS against the crowd"
	if show_power:
		# pass 83 (lane SCALE): the hero's power level in its place (the P key, the Power button)
		c1.title = "Hero power (fresh Drifter = 1)"
		var pw_pts: PackedVector2Array = DATA.bucket(data.t, data.power, x0, x1, cols)
		var ref_pw := _ref_pts(ref, "power", x0, x1, cols)
		c1.series = []
		if not ref_pw.is_empty():
			c1.series.append({"pts": ref_pw, "color": GREY, "width": 1.5, "axis": 0})
		c1.series.append({"pts": pw_pts, "color": Color(0.55, 0.8, 1.0), "width": 2.0, "axis": 0, "fill": true})
		c1.axes = [{"max": DATA.nice_max(maxf(maxf(_max_y(pw_pts), _max_y(ref_pw)), 1.0)), "fmt": "%.1f", "unit": ""}, {"max": 0.0}, {"max": 0.0}]
		c1.legend = [["Power: sqrt(full DPS / 20.4 x eff. HP / 100)", Color(0.55, 0.8, 1.0)]]
		if not ref_pw.is_empty():
			c1.legend.append(["Sim avg", GREY])
	# 2: HP, Danger beneath
	var c2 = _charts[1]
	var hp_pts: PackedVector2Array = DATA.bucket(data.t, data.hp, x0, x1, cols)
	var mx_pts: PackedVector2Array = DATA.bucket(data.t, data.hp_max, x0, x1, cols)
	var dg_pts: PackedVector2Array = DATA.bucket(data.t, data.danger, x0, x1, cols)
	var ref_hp := _ref_pts(ref, "hp", x0, x1, cols)
	c2.lower = 0.34
	c2.series = [{"pts": mx_pts, "color": Color(GOOD.r, GOOD.g, GOOD.b, 0.35), "width": 1.0, "axis": 0},
		{"pts": hp_pts, "color": GOOD, "width": 2.0, "axis": 0, "fill": true},
		{"pts": dg_pts, "color": BAD, "width": 1.4, "axis": 2, "fill": true}]
	if not ref_hp.is_empty():
		c2.series.insert(1, {"pts": ref_hp, "color": GREY, "width": 1.5, "axis": 0})
	c2.axes = [{"max": DATA.nice_max(maxf(_max_y(mx_pts), _max_y(ref_hp))), "fmt": "%.0f", "unit": ""}, {"max": 0.0},
		{"max": DATA.nice_max(maxf(_max_y(dg_pts), 2.0)), "fmt": "%.0f", "unit": "%"}]
	c2.legend = [["HP", GOOD], ["Max HP", Color(GOOD.r, GOOD.g, GOOD.b, 0.45)], ["Danger (below)", BAD]]
	if not ref_hp.is_empty():
		c2.legend.append(["Sim avg", GREY])
	# 3: level and XP
	var c3 = _charts[2]
	var lv := PackedFloat32Array()
	lv.resize(n)
	var xp := PackedFloat32Array()
	xp.resize(n)
	for i in range(n):
		lv[i] = float(data.level[i])
		xp[i] = 100.0 * data.xp_frac[i]
	var lv_pts: PackedVector2Array = DATA.bucket(data.t, lv, x0, x1, cols)
	var xp_pts: PackedVector2Array = DATA.bucket(data.t, xp, x0, x1, cols)
	var ref_lv := _ref_pts(ref, "level", x0, x1, cols)
	c3.series = [{"pts": xp_pts, "color": Color(BLUE.r, BLUE.g, BLUE.b, 0.5), "width": 1.0, "axis": 1, "fill": true}]
	if not ref_lv.is_empty():
		c3.series.append({"pts": ref_lv, "color": GREY, "width": 1.5, "axis": 0})
	c3.series.append({"pts": lv_pts, "color": BLUE, "width": 2.0, "axis": 0})
	c3.axes = [{"max": DATA.nice_max(maxf(maxf(_max_y(lv_pts), _max_y(ref_lv)), 8.0)), "fmt": "%.0f", "unit": ""},
		{"max": 100.0, "fmt": "%.0f", "unit": "%"}, {"max": 0.0}]
	c3.legend = [["Level", BLUE], ["XP to next (right)", Color(BLUE.r, BLUE.g, BLUE.b, 0.6)]]
	if not ref_lv.is_empty():
		c3.legend.append(["Sim avg", GREY])
	_pickup_marks(c3, data)
	# 4: the damage share, stacked, over columns of the window
	_share_chart(_charts[3], data, x0, x1, mini(cols, 240))
	for c in _charts:
		c.queue_redraw()


## Pass 82: a mark at each chest, power-up and totem gift picked up (PICKUP_MARKS: one lane, shape and colour a kind) on
## the Level and XP chart, the totals first in its legend.
func _pickup_marks(c, data) -> void:
	c.points = pickup_points(data.pickups)
	var tot: Dictionary = data.pickup_totals()
	var items: Array = []
	for m in PICKUP_MARKS:
		items.append(["%s %d" % [str(m[1]), int(tot[str(m[0])])], m[2], str(m[3])])
	c.legend = items + c.legend


## The marks of `pickups` ({kind: [play seconds]}): [{x, lane, shape, color}] (pure; tested).
static func pickup_points(pickups: Dictionary) -> Array:
	var out: Array = []
	for m in PICKUP_MARKS:
		for t in pickups.get(str(m[0]), []):
			out.append({"x": float(t), "lane": int(m[4]), "shape": str(m[3]), "color": m[2]})
	return out


func _share_chart(c, data, x0: float, x1: float, ncols: int) -> void:
	var n: int = data.size()
	var i0 := 0
	while i0 < n and data.t[i0] < x0:
		i0 += 1
	var count := n - i0
	c.series = []
	c.bands = []
	c.axes = [{"max": 100.0, "fmt": "%.0f", "unit": "%"}, {"max": 0.0}, {"max": 0.0}]
	if count <= 0:
		c.legend = []
		return
	# the window's biggest sources name the bands
	var order: Array = data.shares(i0, n - 1, 6)
	var ids: Array = []
	for o in order:
		ids.append(str(o[0]))
	var ncol := mini(ncols, count)
	var per := float(count) / float(ncol)
	# each column's x and the bands' running sums (bottom of band j = sums[j], top = sums[j + 1])
	var xs := PackedFloat32Array()
	var sums: Array = []
	for b in range(ncol):
		# each column: its rows and the 4 s before them (a smoother share)
		var r0 := i0 + int(floor(float(b) * per))
		var r1 := mini(i0 + int(floor(float(b + 1) * per)), n) - 1
		r1 = maxi(r1, r0)
		var sh: Array = data.shares(maxi(r0 - 4, 0), r1, 6)
		var by := {}
		for s in sh:
			by[str(s[0])] = float(s[1])
		# a source not among the window's top six counts as "other" here
		var other := 0.0
		for k in by:
			if not ids.has(k):
				other += float(by[k])
		xs.append((data.t[r0] + data.t[r1]) * 0.5)
		var acc := PackedFloat32Array([0.0])
		for j in range(ids.size()):
			var v := float(by.get(ids[j], 0.0))
			if ids[j] == "other":
				v += other
			acc.append(acc[acc.size() - 1] + v * 100.0)
		sums.append(acc)
	var tops: Array = []
	var bottoms: Array = []
	for j in range(ids.size()):
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		top.resize(xs.size())
		bot.resize(xs.size())
		for b in range(xs.size()):
			var acc: PackedFloat32Array = sums[b]
			bot[b] = Vector2(xs[b], acc[j])
			top[b] = Vector2(xs[b], acc[j + 1])
		tops.append(top)
		bottoms.append(bot)
	var legend: Array = []
	for j in range(ids.size()):
		var col: Color = _share_colour(str(ids[j]))
		c.bands.append({"top": tops[j], "bottom": bottoms[j], "color": Color(col.r, col.g, col.b, 0.75)})
		var nm: String = "Other" if ids[j] == "other" else watch.name_of(ids[j])
		legend.append(["%s %d%%" % [nm, int(roundf(100.0 * float(order[j][1])))], col])
	c.legend = legend


## A damage source's colour in the share chart, kept for the whole run (the first source seen takes the first colour,
## and so on round the palette; "other" grey), so a source keeps its colour when the ranking changes.
func _share_colour(id: String) -> Color:
	if id == "other":
		return SHARE_COLS[SHARE_COLS.size() - 1]
	if not _share_cols.has(id):
		_share_cols[id] = SHARE_COLS[_share_cols.size() % (SHARE_COLS.size() - 1)]
	return _share_cols[id]


static func _max_y(pts: PackedVector2Array) -> float:
	var m := 0.0
	for p in pts:
		m = maxf(m, p.y)
	return m


## The Sim's average of series `key` (the result.json's series[key].mean, one value a second of play) within the
## window, bucketed; empty without a reference.
func _ref_pts(ref: Dictionary, key: String, x0: float, x1: float, cols: int) -> PackedVector2Array:
	if ref.is_empty() or not ref.has(key):
		return PackedVector2Array()
	var ts: PackedFloat32Array = ref["t"]
	var vs: PackedFloat32Array = ref[key]
	var lim := ts.size()
	var out := PackedVector2Array()
	var cut_t := PackedFloat32Array()
	var cut_v := PackedFloat32Array()
	for i in range(lim):
		if ts[i] < x0 or ts[i] > x1:
			continue
		cut_t.append(ts[i])
		cut_v.append(vs[i])
	out = DATA.bucket(cut_t, cut_v, x0, x1, cols)
	return out
