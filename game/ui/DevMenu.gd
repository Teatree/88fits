## The developer menu (Wanted 17): everything that used to leak into the player's screens, in one place, reached by
## holding the version line in Settings for 2 s. Ink, JetBrains Mono. The arena, the in-run debug panel, the debug
## buttons on the pick screens, the free revive and the hit log on Down! (and Results), the last run's last second, the recent system
## pauses, the hidden items (the Collection in its hidden mode) and where the save file lives. Switches save at once.
## Pass 48: the arena's training dummies, their health (UNDYING or 100 .. 10000 HP, Settings.dummy_hp) and how many
## stand in the field (10 .. 30, Settings.dummy_count), each a row that steps on a tap. Pass 49: whether the field patrols
## (Settings.dummy_patrol), the attacking dummies' health (Settings.attacker_dummy_hp), and the Elite dummy's and the Boss
## dummy's health and behaviour (stand, patrol, melee, ranged), stepped the same way. Pass 57: the PostHog client's
## readout (core/autoload/Analytics.gd: whether the key file has a key, never the key itself, whether anything is sent and
## why not, the queue, the events sent this session, the last send) and a Send now row that pushes the queue out with a
## dev_ping, so PostHog's live view shows something at once.
## Pass 62 (Garry: "I'd like an option to reset the Survey. Basically some way to test it for sure. Like in the developer
## options that Player can access"): a Surveys block, the readout (Analytics.survey_lines: the surveys fetched with their
## run tags, the counted runs, the session, armed, answered and dismissed ids) and five rows that work in a release
## build: Reset surveys (asks first, WConfirm), Fetch surveys now, Show a survey now (the real card over this menu, its
## real events), Next run asks (arms the next counted run) and Counted runs (+1 a tap, to reach a [run N] survey's run).
## And (Garry: "those developer options get cut off on mobile"): every row's words wrap and its value stays whole at the
## right edge; nothing in the list may be wider than the screen.
extends Control

const SETTINGS := "res://ui/SettingsScreen.tscn"
const WSurveyScript := preload("res://ui/wanted/WSurvey.gd")

var _list: VBoxContainer
var _scroll: ScrollContainer
var _touch: TouchScroll
var _open := ""
var _refresh_due := false
## The survey card a "Show a survey now" opened (pass 62), and the block's last word (why nothing showed, what a tap did).
var _survey: Control
var _survey_note := ""


func _ready() -> void:
	get_tree().paused = false
	# pass 81 (lane PROD): the production build has no developer menu; anything that lands here goes back to Settings
	if Settings.is_prod():
		var tree := get_tree()
		(func(): UiFx.go(tree, SETTINGS)).call_deferred()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = W.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var header := WMenuHeader.make("")
	header.back.connect(_back)
	# on ink the back square keeps its paper face and loses its shadow
	var bb := W.box(W.PAPER, 5, 0)
	header.back_button.box = bb
	header.back_button.box_down = bb
	header.title.font = W.mono(500)
	header.title.font_size = 44
	header.title.line_height = 0.0
	header.title.color = W.PAPER
	header.title.valign = VERTICAL_ALIGNMENT_CENTER
	header.title.position.y = 0
	header.title.size = Vector2(860, 114)
	header.title.text = "developer · v%s" % str(ProjectSettings.get_setting("application/config/version", "0.28"))
	add_child(header)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 200 + W.safe_top()
	_scroll.offset_bottom = -40
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 48)
	m.add_theme_constant_override("margin_right", 48)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(m)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 18)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(_list)
	_touch = TouchScroll.new(_scroll)
	# a send that finishes while the menu is up puts its status in the readout
	Analytics.sent.connect(_on_analytics_sent)
	# a survey fetch, an answer or a reset likewise (pass 62)
	Analytics.surveys_changed.connect(_refresh_soon)
	_refresh()


func _on_analytics_sent(_ok: bool) -> void:
	_refresh_soon()


func _refresh_soon() -> void:
	if _refresh_due:
		return
	_refresh_due = true
	call_deferred("_refresh_now")


func _refresh_now() -> void:
	_refresh_due = false
	if is_inside_tree():
		_refresh()


func _refresh() -> void:
	# out of the list at once (pass 48): a row only queued keeps its name, and the new one took a made-up one
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list.add_child(_row("Arena", "›", func():
		Run.arena_next = true
		UiFx.go(get_tree(), "res://game/Game.tscn")))
	_list.add_child(_switch("Debug mode (the player's: 10 taps on the hints switch)", "debug_mode"))
	_list.add_child(_switch("Debug panel in run", "debug_panel"))
	_list.add_child(_switch("Debug buttons on modals", "debug_modal_buttons"))
	_list.add_child(_switch("Free revive button", "free_revive_button"))
	_list.add_child(_switch("Hit log on Down! · copy", "hit_log"))
	_list.add_child(_switch("Hidden heroes as locked on the title", "preview_locked_heroes"))
	# pass 69: the heroes to buy, for tests: every one owned at once (no gold, no quest), or back to the free ones
	var on_sale: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return not c.hidden and c.availability == "purchase")
	var owned_n := on_sale.filter(func(c: CharacterDef) -> bool: return Save.owns_hero(c.id)).size()
	var own_row := _row("Heroes · own every one", "%d / %d" % [owned_n, on_sale.size()], func():
		Save.own_every_hero()
		_refresh())
	own_row.name = "OwnEveryHero"
	_list.add_child(own_row)
	var forget_row := _row("Heroes · forget the bought ones", "›", func():
		Save.forget_bought_heroes()
		_refresh())
	forget_row.name = "ForgetBoughtHeroes"
	_list.add_child(forget_row)
	# pass 62: the pierce damage drop-off (also in Settings' Debug panel)
	var pf_row := _switch("Pierce damage drop-off", "pierce_falloff")
	pf_row.name = "PierceFalloffRow"
	_list.add_child(pf_row)
	# pass 88: the hero's knockback from hits, off by default (also in Settings' Debug panel)
	var hk_row := _switch("Full hero knockback", "hero_knockback")
	hk_row.name = "HeroKnockbackRow"
	_list.add_child(hk_row)
	# pass 95 (lane ITEMS): "Fire forward", off by default (also in Settings' Debug panel): the Sabre, Spear, Hammer,
	# Frisbee, Tumbleweed and Basketball fire along the hero's facing while no creature is within 75% of their range
	var ff_row := _switch("Fire forward (Sabre, Spear, Hammer, Frisbee, Tumbleweed, Basketball)", "fire_forward")
	ff_row.name = "FireForwardRow"
	_list.add_child(ff_row)
	# pass 101 (lane FPS): the frame cap (Settings.frame_cap): 60 (a phone's default) or MAX (the screen's own rate)
	var fc_row := _row("Frame rate · 60 or the screen's max (%s Hz)" % _refresh_hz(), Settings.frame_cap_label(), func():
		Settings.set_value("frame_cap", Settings.next_frame_cap(Settings.frame_cap))
		_refresh())
	fc_row.name = "FrameCap"
	_list.add_child(fc_row)
	# the arena's training dummies (pass 48): a tap steps each one on, the arena lays them out from these
	var hp_row := _row("Arena dummies · health", Settings.dummy_hp_label(Settings.dummy_hp), func():
		Settings.set_value("dummy_hp", Settings.next_step(Settings.DUMMY_HP_STEPS, Settings.dummy_hp))
		_refresh())
	hp_row.name = "DummyHealth"
	_list.add_child(hp_row)
	var n_row := _row("Arena dummies · count", str(Settings.dummy_count), func():
		Settings.set_value("dummy_count", Settings.next_step(Settings.DUMMY_COUNT_STEPS, Settings.dummy_count))
		_refresh())
	n_row.name = "DummyCount"
	_list.add_child(n_row)
	# pass 49: the field's patrol, the attackers' health, the Elite's and the Boss's health and behaviour
	var p_row := _row("Arena dummies · patrol", "ON" if Settings.dummy_patrol else "OFF", func():
		Settings.set_value("dummy_patrol", not Settings.dummy_patrol)
		_refresh())
	p_row.name = "DummyPatrol"
	_list.add_child(p_row)
	var a_row := _row("Arena attackers · health", Settings.dummy_hp_label(Settings.attacker_dummy_hp), func():
		Settings.set_value("attacker_dummy_hp", Settings.next_step(Settings.ATTACKER_HP_STEPS, Settings.attacker_dummy_hp))
		_refresh())
	a_row.name = "AttackerHealth"
	_list.add_child(a_row)
	for spec in [["elite", "Elite", Settings.ELITE_DUMMY_HP_STEPS], ["boss", "Boss", Settings.BOSS_DUMMY_HP_STEPS]]:
		var role: String = spec[0]
		var word: String = spec[1]
		var steps: Array = spec[2]
		var h_row := _row("Arena %s dummy · health" % word, Settings.dummy_hp_label(int(Settings.get(role + "_dummy_hp"))), func():
			Settings.set_value(role + "_dummy_hp", Settings.next_step(steps, int(Settings.get(role + "_dummy_hp"))))
			_refresh())
		h_row.name = word + "DummyHealth"
		_list.add_child(h_row)
		var m_row := _row("Arena %s dummy · behaviour" % word, str(Settings.get(role + "_dummy_mode")).to_upper(), func():
			Settings.set_value(role + "_dummy_mode", Settings.next_mode(str(Settings.get(role + "_dummy_mode"))))
			_refresh())
		m_row.name = word + "DummyMode"
		_list.add_child(m_row)
	# the top inset for a camera cutout: what the phone reports, or a fixed value to see the screens with one
	var ins := int(Settings.top_inset)
	_list.add_child(_row("Top inset · camera cutout", "AUTO (%d px)" % int(round(W.safe_top())) if ins < 0 else "%d px" % ins, func():
		var steps := [-1, 0, 80, 130, 180]
		var k := steps.find(int(Settings.top_inset))
		Settings.set_value("top_inset", steps[(k + 1) % steps.size()])
		_refresh()))
	_list.add_child(_file_row("Last run's last second", "user://breadcrumb.txt", "no run has left a breadcrumb yet"))
	_list.add_child(_file_row("Recent system pauses", "user://pauses.txt", "the phone has not paused a run"))
	var hidden := CollectionScreen.hidden_items().size()
	_list.add_child(_row("Hidden items · %d" % hidden, "›", func():
		CollectionScreen.hidden_only = true
		UiFx.go(get_tree(), "res://ui/CollectionScreen.tscn")))
	# pass 109: the first-run Dynamite offer (FtueDynamite): TAKEN once the Dynamite was picked; a tap brings it back
	var ftue_row := _row("First-run Dynamite offer · a tap brings it back", "TAKEN" if FtueDynamite.taken() else "DUE", func():
		FtueDynamite.reset()
		_refresh())
	ftue_row.name = "FtueDynamiteRow"
	_list.add_child(ftue_row)
	# PostHog (pass 57): the key file, whether anything goes and why not, the queue and the last send; never the key
	var an := _box()
	an.name = "Analytics"
	var av: VBoxContainer = an.get_child(0)
	av.add_child(W.text("Analytics · PostHog", W.mono(500), 30, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	for line: String in Analytics.status_lines():
		av.add_child(W.text(line, W.mono(500), 22, Color(W.AGED, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	_list.add_child(an)
	var send := _row("Analytics · send now (a ping goes too)", "›", func():
		Analytics.send_now()
		_refresh_soon())
	send.name = "AnalyticsSendNow"
	_list.add_child(send)
	_surveys_block()
	var save := _box()
	var sv: VBoxContainer = save.get_child(0)
	sv.add_child(W.text("Save file", W.mono(500), 30, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var path := W.text(ProjectSettings.globalize_path(Save.path()), W.mono(500), 22, Color(W.AGED, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	sv.add_child(path)
	# what the boot read, the last write and its error, whether a backup sits beside the file (pass 45)
	var when: String = Time.get_datetime_string_from_unix_time(Save.last_saved_unix, true) + " UTC" if Save.last_saved_unix > 0 else "never"
	for line: String in ["loaded from: %s" % Save.loaded_from,
			"last write: %s%s" % [when, "" if Save.last_error == "" else " · " + Save.last_error],
			"backup: %s" % ("yes" if FileAccess.file_exists(Save.bak_path()) else "none")]:
		sv.add_child(W.text(line, W.mono(500), 22, Color(W.AGED, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	_list.add_child(save)


## The Surveys block (pass 62): the readout, then Reset (asks first), Fetch now, Show one now, Next run asks and the
## counted runs. Every row works in a release build; nothing here needs the debug mode.
func _surveys_block() -> void:
	var box := _box()
	box.name = "Surveys"
	var bv: VBoxContainer = box.get_child(0)
	bv.add_child(W.text("Surveys · PostHog", W.mono(500), 30, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	for line: String in Analytics.survey_lines():
		bv.add_child(W.text(line, W.mono(500), 22, Color(W.AGED, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	if _survey_note != "":
		var note := W.text(_survey_note, W.mono(500), 22, W.BRASS, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
		note.name = "SurveyNote"
		bv.add_child(note)
	_list.add_child(box)
	var reset := _row("Surveys · reset (counted runs, answered, shown)", "›", _ask_reset_surveys)
	reset.name = "SurveyReset"
	_list.add_child(reset)
	var fetch := _row("Surveys · fetch now", "›", func():
		var why := Analytics.fetch_surveys_now()
		_survey_note = "fetching..." if why == "" else "not fetched: " + why
		_refresh_soon())
	fetch.name = "SurveyFetch"
	_list.add_child(fetch)
	var show_row := _row("Surveys · show one now", "›", show_survey_now)
	show_row.name = "SurveyShow"
	_list.add_child(show_row)
	var arm := _row("Surveys · next run asks", "ON" if Analytics.next_run_armed() else "OFF", func():
		Analytics.arm_next_run(not Analytics.next_run_armed())
		_survey_note = "the next run of %d s or more ends with a survey" % int(Analytics.SURVEY_MIN_RUN) if Analytics.next_run_armed() else "the next run asks by the rules"
		_refresh_soon())
	arm.name = "SurveyArm"
	_list.add_child(arm)
	var counted := _row("Surveys · counted runs (a tap: +1)", str(int(Save.survey_state().get("counted", 0))), func():
		Analytics.add_counted(1)
		_survey_note = "counted runs set to %d: the next counted run is run %d" % [int(Save.survey_state().get("counted", 0)), int(Save.survey_state().get("counted", 0)) + 1]
		_refresh_soon())
	counted.name = "SurveyCounted"
	_list.add_child(counted)


func _ask_reset_surveys() -> void:
	var off := "" if Settings.surveys else " Questions after a run are OFF in Settings: turn them on there too."
	WConfirm.open(self, "Reset surveys?", "Counted runs go to 0 and every survey can be asked again, answered or not. The play-data answer stays." + off,
		"Reset", "Keep", func():
			Analytics.reset_surveys()
			_survey_note = "surveys reset" + ("" if Settings.surveys else " · questions after a run are OFF in Settings")
			_refresh_soon())


## "Show a survey now": the next survey not answered yet opens over this menu, as it would after a run (its shown,
## sent or dismissed events go to PostHog like a real one's); the timing record is left alone.
func show_survey_now() -> Control:
	if is_instance_valid(_survey) and not bool(_survey.call("is_done")):
		return _survey
	var sv := Analytics.survey_for_test()
	if sv.is_empty():
		_survey_note = "nothing to show: " + Analytics.no_test_survey_reason()
		_refresh_soon()
		return null
	_survey_note = "showing: " + str(sv.get("name", ""))
	_survey = WSurveyScript.open(self, sv)
	_refresh_soon()
	return _survey


## Pass 101 (lane FPS): the screen's refresh rate in words ("120", or "?" when the system does not say).
func _refresh_hz() -> String:
	var hz := DisplayServer.screen_get_refresh_rate()
	return "?" if hz <= 0.0 else str(int(round(hz)))


## A row's frame: a 3 px aged outline round 26 x 30 px of room, a column inside.
func _box() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var b := W.box(Color(0, 0, 0, 0), 3, 0).pad(33, 29, 33, 29)
	b.border_color = W.AGED
	p.add_theme_stylebox_override("panel", b)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return p


## A tappable row: the words on the left, the value or the arrow in brass on the right.
func _row(t: String, value: String, on_tap: Callable, extra: Control = null) -> WTap:
	var r := WTap.new()
	var b := W.box(Color(0, 0, 0, 0), 3, 0).pad(33, 29, 33, 29)
	b.border_color = W.AGED
	var down := b.duplicate() as HardBox
	down.fill = Color(W.PAPER, 0.08)
	r.box = b
	r.box_down = down
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the words wrap (pass 62): one long name (the debug mode row's) had made the whole list wider than the screen, so
	# every row's value was cut at the right edge
	var l := W.text(t, W.mono(500), 30, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var val := W.text(value, W.mono(500), 30, W.BRASS, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	val.name = "Value"
	h.add_child(val)
	v.add_child(h)
	if extra:
		v.add_child(extra)
	r.pressed.connect(on_tap)
	return r


## A setting that is on or off (Settings.<key>).
func _switch(t: String, key: String) -> WTap:
	var on := bool(Settings.get(key))
	return _row(t, "ON" if on else "OFF", func():
		Settings.set_value(key, not bool(Settings.get(key)))
		_refresh())


## A log file shown in the row when it is opened.
func _file_row(t: String, path: String, empty: String) -> WTap:
	var open := _open == path
	var body: Control = null
	if open:
		var txt := ""
		if FileAccess.file_exists(path):
			txt = FileAccess.get_file_as_string(path).strip_edges()
		body = W.text(txt if txt != "" else empty, W.mono(500), 22, Color(W.AGED, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 30.0, true)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _row(t, "hide" if open else "›", func():
		_open = "" if open else path
		_refresh(), body)


func _back() -> void:
	# a question or a survey card over the menu goes first (pass 62)
	if WConfirm.dismiss(self):
		return
	if is_instance_valid(_survey) and not bool(_survey.call("is_done")):
		_survey.call("dismiss")
		return
	UiFx.go(get_tree(), SETTINGS)


## Whether a card lies over the list (a survey or a question): the list under it keeps still.
func _covered() -> bool:
	return WConfirm.is_open(self) or (is_instance_valid(_survey) and not bool(_survey.call("is_done")))


func _input(event: InputEvent) -> void:
	if _touch and not _covered():
		_touch.input(event)


func _process(_delta: float) -> void:
	if _touch:
		_touch.process()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()
