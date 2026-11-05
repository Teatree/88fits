## Title (Wanted 01/02), with play setup merged in: the gold plate, "★ WANTED ★ / OUTLAW / SURVIVORS" (pass 115; it was
## "88fits / DRAG · DODGE · SURVIVE"), the
## hero full-body (art/ui/wanted/hero_<id>.png, since pass 68 the played look's own `title` when it has one; a striped
## slot until painted) between two arrow squares, swipe or tap
## to change, a dot per hero under it, the hero plaque (name, italic line, the trait's numbers and the favourite's plate:
## his weapon, or the line or passive he favours, Ironwood's Brawn since pass 47, each plate in its colour), PLAY, the
## map and its best run in one line (a tap changes the map when there are several). Heroes still to unlock ride the
## same carousel after the open ones: a dark silhouette with a padlock, a half-aged dot, what unlocks them and how far
## along that is, and PLAY reading LOCKED. (The developer menu can add the hidden heroes, locked, to preview the look.) Then Upgrade · Collection ·
## Settings, Upgrade in turquoise (pass 46: brass is kept for buying) with a breathing glow and a mark when a rank is
## affordable (pass 44: the Mirror's name said nothing about what it was for). No version label; the developer menu
## lives in Settings (hold the version label for 2 s), and the player's own debug mode (ten taps on the hints switch)
## puts an ARENA button top right. The top block hangs from the top edge, the plaque and the buttons from the bottom;
## the hero keeps the middle.
## Pass 69 (Garry: heroes to unlock and to buy): the carousel holds every hero not hidden, owned first, then those on
## sale, then the locked ones (Registry.heroes_for_drawer). A hero not owned runs in under a full black mask; his plaque
## reads Unknown, "?" for his stats, his start weapon and favourite as black silhouettes with a "?" (WPlate.mystery), and
## PLAY is LOCKED. Locked (his quest not done): what unlocks him written over the plaque (the Requirement card, with how
## far along it is) and the padlock on his chest. On sale: a BUY button over him with his price; a tap asks (WConfirm),
## spends the gold (Save.buy_hero), lifts the mask with a burst (WCelebrate) and he is playable.
## Pass 123 (lane MAINMENU), under the Royale theme (Garry: "Main menu in the new layout: wordmark, hero with
## ‹ ›, name, trait pill, DETAILS (opens Hero details), gold START to Select Stage, docked bottom bar, Settings behind ≡,
## wallet top right."; the mock 5_Main_menu): lane BACKDROP's painted sunset with its hero disc (RoyaleBackdrop "title",
## no 3D stage is built), ≡ top left (Settings), the wallet top right, OUTLAW over
## "★ SURVIVORS ★", the hero small on the disc as a run draws him (his played look's idle frames, HeroFigure) between ‹ ›
## slate squares, his name, one black pill with his trait ("+1% CRIT per Level"), DETAILS (blue: his sheet), START (gold,
## today's PLAY flow) and the docked tab bar (WTabBar, BATTLE open). Gone under Royale: the plaque, the Hero Collections
## button and its drawer, the dots, the Upgrade · Collection · Settings row (the tabs and ≡ replace them) and the map's
## run line (Garry: "Move the run-history line ... to the Stages screen's header"). A hero not owned keeps today's rules:
## a black silhouette and UNKNOWN, START LOCKED; on sale a green price · BUY over him (the shared confirm, kind "buy");
## locked, the requirement and its progress on a slate card over his feet, the padlock on his chest. The sides stay empty
## (Garry: "Leave the main menu's sides empty"). The ARENA button (debug mode), the play-data card and the back gesture
## are as before. Wanted is built and drawn exactly as before.
extends Control

const NAME_PX := 52
const VALUE_PX := 30
const LABEL_PX := 18
const PLATE_PX := 84.0
## A finger that travels this far sideways over the hero changes it.
const SWIPE := 90.0
## The game's big word in the slab (pass 115: OUTLAW, 953 px wide at 190, inside the 1080 px canvas with its 10 px
## shadow; "88fits" was 210).
const LOGO_PX := 190
## The trait's numbers under short names (the rest fall back to TextGen's stat names: ATTACK DAMAGE, AREA OF EFFECT,
## COIN GAIN since pass 45, so the words live in one place).
const SHORT := {"max_hp": "HP", "damage_reduction": "DEFENCE", "move_speed": "SPEED", "magnet": "REACH",
	"cooldown": "COOLDOWN", "luck": "LUCK", "regen": "REGEN", "regen_delay": "REGEN DELAY", "revives": "REVIVES",
	"projectile_speed": "SHOT SPEED", "xp_gain": "XP", "crit_chance": "CRIT", "amount": "PROJECTILES"}
## A unit after a number whose stat has none of its own (regen is health a second: "+1.2/s" over REGEN).
const UNIT := {"regen": "/s"}
## The breathing halo behind Upgrade: the button's own turquoise (pass 46; it was brass with the button).
const GLOW := W.TURQUOISE
## Stats a hero is better off with less of: a negative on these is a buff, and stays sage.
const LOWER_BETTER := ["cooldown", "regen_delay", "shield_delay"]

var _heroes: Array = []
var _index := 0
var _maps: Array = []
var _map_id := ""
var _hero_row: Control
var _art_host: Control
var _art: WPlaceholder
var _dots: Control
var _plaque: PanelContainer
var _name: WText
var _line: WText
## The item plates (START, FAVOURITE) on the plaque's right; the trait's numbers flow under the flavour (pass 73).
var _stats: HBoxContainer
var _trait: HFlowContainer
var _play: WButton
var _map_tap: WTap
var _map_line: WText
var _lower: Array = []
## The hero's sheet (pass 61): the CV a tap on the plaque opens (ui/wanted/WHeroSheet.gd, no class_name).
const WHeroSheetScript := preload("res://ui/wanted/WHeroSheet.gd")
var _sheet: Control
var _swipe_id := -2   # -2 none, -1 the mouse, else a finger index
var _swipe_from := Vector2.ZERO
var _glow: Control
var _mark: Control
var _halo := StyleBoxFlat.new()
var _affordable := false
var _glow_t := 0.0
var _arena_btn: WButton
## The live look (pass 52): the 3D stage behind everything, the padlock over a locked hero there, and the wash, whose
## clear middle reaches down to the hero's feet (it is under the hero in this look, over the still in the other). The
## stage's script by its path: a new class_name is unknown to a headless run until the editor rescans the project.
const TitleStageScript := preload("res://ui/TitleStage.gd")
## The play-data card (pass 59) and how long after the title comes in it asks.
const WConsentScript := preload("res://ui/wanted/WConsent.gd")
## The Stages menu (pass 87, lane SUI): PLAY opens it once the map's first stage is beaten.
const StagesScreenScript := preload("res://ui/StagesScreen.gd")
const CONSENT_DELAY := 0.8
var _wash_rect: TextureRect
var _gold_plate: PanelContainer
var _req: PanelContainer
var _req_text: WText
var _buy_col: VBoxContainer
var _buy: WButton
## The title's top block (the name stack).
var _top_stack: Control
## A hero not owned on the painted title: his cut-out's fill, a full black (pass 69).
const MASK := Color(0.03, 0.024, 0.02, 1.0)

# ---------------------------------------------------------------- the Royale main menu (pass 123, lane MAINMENU)
## The mock 5_Main_menu's numbers on the 1080 x 1920 canvas (README "Main menu"): ≡ a 96 px slate square at (40, 52), the
## wallet 40 in from the right at 64, ARENA (debug mode) beside ≡, OUTLAW Ultra 170 at 150 over "★ SURVIVORS ★" (gold 40,
## tracked .32em) at 330, all under the camera cutout.
const RY_MENU_POS := Vector2(40, 52)
const RY_MENU := 96.0
const RY_WALLET := Vector2(40, 64)
const RY_ARENA_POS := Vector2(160, 64)
const RY_ARENA := Vector2(180, 72)
const RY_LOGO_TOP := 150.0
const RY_LOGO_PX := 170
const RY_LOGO_DROP := 10
const RY_TAG_TOP := 330.0
const RY_TAG_PX := 40
const RY_TAG_EM := 0.32
const RY_TAG_DROP := 3
## The hero on the backdrop's disc (lane BACKDROP: "his figure ~300 px tall", the scale its paintings were projected at;
## the mock's figure is ~310): his figure (head to soles) RY_FIGURE_H tall, times the plate's scale on a wide screen, his
## soles RY_FEET_UP over the disc's centre (on the disc's dark patch, where the mock's stand). Pass 126 (lane UI; Garry: "make the
## MM Hero bigger than the Heroes Screen one. Around x1.15 bigger"): 1.15 x HeroesScreen.FIGURE_PX 320.
const RY_FIGURE_H := 368.0
## Pass 124, the swap: how far up the sand and to the side a hero starts (and leaves), how far away he looks there and how near as he
## leaves, the seconds in and out, and the beat he holds his three-quarter idle before he turns to face us.
const RY_RUN_DX := 780.0
const RY_RUN_DY := 165.0
const RY_RUN_FAR := 0.8
const RY_RUN_NEAR := 1.18
const RY_RUN_IN := 0.62
## Pass 126 (lane UI; Garry: "On MM make the hero fade away more quickly when he is running away while switching"): out in 0.32 s
## (was 0.44), gone to nothing by RY_RUN_FADE of that (he had no fade at all: he ran the whole way off the screen).
const RY_RUN_OUT := 0.32
const RY_RUN_FADE := 0.7
const RY_TURN_BEAT := 0.14
const RY_FEET_UP := 10.0
## ‹ › 96 px slate squares, their outer edges RY_ARROW_X either side of the disc's centre, their tops RY_ARROW_UP above it
## (the mock's 200 and 784 at 930).
const RY_ARROW := 96.0
const RY_ARROW_X := 340.0
const RY_ARROW_UP := 230.0
const RY_ARROW_PX := 60
## The name (Ultra 60, cream) RY_NAME_DOWN under the disc's centre, the trait pill and DETAILS (170 x 50, blue) RY_PILL_GAP
## apart RY_PILL_DOWN under it (the mock's 1222 and 1300).
const RY_NAME_DOWN := 62.0
const RY_NAME_PX := 60
const RY_PILL_DOWN := 140.0
const RY_PILL_GAP := 16
const RY_DETAILS := Vector2(220, 60)
const RY_DETAILS_GAP := 10.0
const RY_DETAILS_PX := 22
## START: gold, 990 x 150, its top RY_START_UP over the screen's foot less the gesture bar (1500 on 1920), Ultra 84.
const RY_START := Vector2(990, 150)
const RY_START_UP := 420.0
const RY_START_PX := 84
## A locked hero's requirement card over his feet (its foot RY_REQ_GAP over the name) and the BUY of one on sale.
const RY_REQ_W := 760.0
const RY_REQ_GAP := 14.0
const RY_BUY_PX := 34
const RY_BUY_H := 84.0
## The padlock on a not-owned figure's chest: this much of the painted cut-out's (the figure is smaller), its chest this
## far down the figure.
const RY_LOCK_SCALE := 0.6
const RY_LOCK_CHEST := 0.32
## The hero's idle when his look names no speed for it (BillboardSprite.SPEEDS["idle"]).
const RY_IDLE_FPS := 4.0
const WTabBarScript := preload("res://ui/wanted/WTabBar.gd")
var _backdrop: Control
var _menu_btn: WButton
var _details_btn: WButton
var _trait_row: HBoxContainer
var _trait_pill: Control
var _tab_bar: Control
var _tab_hero := ""
var _figure: HeroFigure
## The run-history pill under the trait until the Stages menu opens (pass 123).
var _run_pill: Control
## The disc's centre and the hero's scale as last laid out (_place_royale).
var _disc := Vector2.ZERO
var _fig_k := 1.0


## Back on the title leaves the game, as it always did (quit_on_go_back is off so a run can ignore the gesture).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# the hero's sheet up (pass 61): back closes it, the game stays
		if sheet_open():
			# pass 111 (lane SKINS): a look's question on the sheet goes first
			if not WConfirm.dismiss(_sheet):
				_sheet.call("close")
			return
		# pass 69: the buy question before the game goes
		if WConfirm.dismiss(self):
			return
		Save.flush()
		get_tree().quit()


func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the look (pass 52): the painted cut-out over the still of the desert, or the level itself with the hero standing in it
	# pass 119 (lane LOADUI): the production build is always painted (it offers no choice)
	# pass 123 (lane MAINMENU): under Royale the painted sunset with the hero's disc replaces both looks (no TitleStage)
	_backdrop = ScreenBase.add_backdrop(self, "title")
	TitleStageScript.forget()
	# quests a save's totals already satisfy (pass 44 added many) complete here, quietly, instead of all at once five
	# seconds into the next run; since pass 76 they are not listed again as "Unlocked this run" (only a run's own checks
	# fill QuestTracker.just_completed)
	QuestTracker.check_all(false)
	# gold cannot change on the title: the Upgrade mark is decided once
	_affordable = _rank_affordable()
	_heroes = _roster()
	var last := Registry.playable_character(str(Save.data.get("last_character", Save.DEFAULT_HERO)))
	# pass 69: a hero to be bought is not the one the title opens on (the first owned one is: the carousel lists them first)
	if last and _is_locked(last):
		last = null
	_index = maxi(_heroes.find(last), 0)
	# pass 101 (lane LOOKS): no run is going, so the last run's pinned strips are let go (LookArt keeps the most recent
	# few); the live title keeps the strip of the hero it opens on (the painted title draws his cut-out, no strip)
	var keep: Array = []
	# (pass 123: the Royale title draws his strip too)
	if not _heroes.is_empty():
		keep.append(Registry.played_look(_heroes[_index]).strip_path())
	LookArt.pin_only(keep)
	_maps = Registry.sorted_maps().filter(func(m: MapDef) -> bool: return Registry.is_unlocked("map", m.id))
	_map_id = str(Save.data.get("last_map", ""))
	if _maps.filter(func(m: MapDef) -> bool: return m.id == _map_id).is_empty():
		_map_id = _maps[0].id if not _maps.is_empty() else "red_canyon"
	_build_royale()
	_show_hero(0)
	get_viewport().size_changed.connect(_place)
	_place()
	_enter()
	Audio.play_music(["mu_title"], 1)
	# the play-data card (pass 59): once, the first time a build that can send starts, after the title has come in
	if Analytics.consent_needed():
		get_tree().create_timer(CONSENT_DELAY).timeout.connect(func():
			if is_inside_tree() and Analytics.consent_needed() and get_node_or_null("Consent") == null:
				WConsentScript.open(self))


## The debug arena (pass 44: the player's debug mode, ten taps on the hints switch).
func _go_arena() -> void:
	Run.arena_next = true
	_leave_for_a_run()
	# pass 120 (lane STARTGO): the revolver wipe and the loading screen into the run (ui/RunCurtain.gd)
	UiFx.go_run(get_tree())


## Everything that depends on the screen's height: the lower block hangs from the bottom edge, the hero row takes the
## middle and shrinks when a short screen has no room for it.
func _place() -> void:
	_place_royale()
	return


## Every hero the carousel shows (pass 69: Registry.heroes_for_drawer, the drawer's list too): the owned ones first,
## then those on sale, then the locked ones. With the developer's preview on, the hidden heroes join the locked ones.
func _roster() -> Array:
	var out: Array = Registry.heroes_for_drawer()
	if bool(Settings.get("preview_locked_heroes")):
		var hidden: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return c.hidden)
		hidden.sort_custom(func(a, b): return a.id < b.id)
		out.append_array(hidden)
	return out


## Where the player stands with `c` (pass 69, Registry.hero_state): owned, buyable or locked; a hidden hero the
## developer previews reads as locked.
func _state(c: CharacterDef) -> String:
	var st := Registry.hero_state(c)
	return "locked" if st == "hidden" else st


## Not owned (pass 69: locked, on sale, or a previewed hidden one): the black mask, Unknown, PLAY locked.
func _is_locked(c: CharacterDef) -> bool:
	return _state(c) != "owned"


## The hero at `_index`: the cut-out (sliding in from the side the finger went), the dots, the plaque and PLAY.
func _show_hero(from_side: int) -> void:
	if _heroes.is_empty():
		return
	var c: CharacterDef = _heroes[_index]
	var locked := _is_locked(c)
	_show_figure(c, from_side)
	_show_plaque(c)


## The dots, the plaque, PLAY, the Requirement card and the BUY for `c`. Pass 69 (Garry: "the name is simply 'unknown',
## stats are unknown, weapon is a black silhouette of the one with a question mark and so is the fav item"): a hero not
## owned reads Unknown, a "?" for each of his numbers, his start weapon and favourite as mystery plates.
func _show_plaque(c: CharacterDef) -> void:
	_show_royale(c)
	return


## The level a hero has an item at when he finds it or lands with it (pass 48: the plaque's plates take its colour): a
## favourite at its bonus level (the Drifter's Peashooter and Calavera's Skull Rain 2, Ironwood's Brawn 2), else 1.
static func start_level(c: CharacterDef, def: ContentDef) -> int:
	if c == null or def == null:
		return 1
	if def is WeaponDef and def.id == c.favourite_weapon:
		if str(c.favourite_bonus.get("type", "")) == "level":
			return clampi(int(c.favourite_bonus.get("value", 1)), 1, maxi((def as WeaponDef).max_level, 1))
		return 1
	if def is PassiveDef and def.id == c.favourite_passive:
		var mx := maxi((def as PassiveDef).max_level, 1)
		match str(c.favourite_passive_bonus.get("type", "")):
			"max":
				return mx
			"level":
				return clampi(int(c.favourite_passive_bonus.get("value", 1)), 1, mx)
	return 1


## Up to three of the trait's numbers: its effects on the player, then the heal on every level. Each is [value, label,
## good]: a debuff (a negative, or a positive on a lower-is-better stat) is not good and reads in dark red (pass 45).
## Pass 61: a hero whose trait grows with his level shows what one level gives ("+1%" over "CRIT / LV").
func _stats_of(c: CharacterDef) -> Array:
	var out: Array = []
	if not c.level_trait.is_empty():
		for e in c.level_trait:
			if e is Effect:
				var x: Effect = e
				var up: bool = (x.value >= 0.0) != (x.stat in LOWER_BETTER)
				out.append([TextGen.hero_step(x) + str(UNIT.get(x.stat, "")), str(SHORT.get(x.stat, TextGen.stat_name(x.stat).to_upper())) + " / LV", up])
		if c.level_heal > 0.0:
			out.append(["%d%%" % int(round(c.level_heal * 100.0)), "HEAL / LV", true])
		return out.slice(0, 3)
	for e in c.trait_effects:
		if e is Effect and (e.target == "player" or e.target == ""):
			var good: bool = e.op == "set" or ((e.value >= 0.0) != (e.stat in LOWER_BETTER))
			out.append([TextGen.describe_effect(e, false) + str(UNIT.get(e.stat, "")), SHORT.get(e.stat, TextGen.stat_name(e.stat).to_upper()), good])
	if c.level_heal > 0.0:
		out.append(["%d%%" % int(round(c.level_heal * 100.0)), "HEAL / LV", true])
	return out.slice(0, 3)


## One of the trait's numbers on the plaque: sage slab (dark red for a debuff) and its tracked label beside it, on one
## baseline (pass 73: the numbers flow along the plaque's foot; they stood over their labels in a row that pushed the
## plaque wider and taller).
func _stat(value: String, what: String, good: bool = true, unknown: bool = false) -> HBoxContainer:
	var v := HBoxContainer.new()
	v.name = "Stat"
	v.add_theme_constant_override("separation", 7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := W.slab_text(value, VALUE_PX, W.INK_SOFT if unknown else (W.SAGE if good else W.BAD_DARK), HORIZONTAL_ALIGNMENT_LEFT, float(VALUE_PX))
	n.name = "Value"
	v.add_child(n)
	var l := W.label(what, LABEL_PX, W.INK_SOFT, 0.1)
	l.name = "Label"
	# the label's line box at the foot of the number's: their baselines meet (Alfa Slab's at 25.5 of 30, Bitter's at
	# 17 of 22)
	l.custom_minimum_size.y = float(VALUE_PX)
	l.valign = VERTICAL_ALIGNMENT_BOTTOM
	v.add_child(l)
	return v


func _step(dir: int) -> void:
	if _heroes.size() < 2:
		return
	_index = posmod(_index + dir, _heroes.size())
	Audio.play("ui_tap")
	_show_hero(dir)
	_place()


## The map's best run under PLAY: nothing until a run has been played (pass 44: the "no runs yet" line read like a
## placeholder), then the true best: time, level, stage and kills.
func _refresh_map() -> void:
	var m := Registry.map(_map_id)
	var bits: Array = [m.display_name if m else _map_id]
	var best := Save.best_run(_map_id)
	var played := not best.is_empty() and float(best.get("time", 0.0)) > 0.0
	_map_tap.visible = played or _maps.size() > 1
	if played:
		bits.append("best " + W.mmss(float(best.get("time", 0.0))))
		bits.append(W.lv(int(best.get("level", 0))))
		bits.append("stage %d" % int(best.get("stage", 1)))
		if int(best.get("kills", 0)) > 0:
			bits.append("%s kills" % W.num(int(best.get("kills", 0))))
	_map_line.text = " · ".join(bits)


## Whether the purse buys the next rank of any open talent (pass 111, lane SKINS: in the talent's own currency). Pass 123
## (lane MAINMENU): the rule lives once, in the tab bar's Upgrade mark (WTabBar.upgrade_mark, the same loop word for word).
func _rank_affordable() -> bool:
	return WTabBarScript.upgrade_mark()


func _process(delta: float) -> void:
	if _glow == null:
		return
	_glow_t += delta
	_glow.queue_redraw()
	# the row slides in (_enter): the mark follows the button
	if _mark:
		_mark.queue_redraw()


func _on_play() -> void:
	if _play.locked:
		Audio.play("ui_locked")
		return
	var c: CharacterDef = _heroes[_index] if not _heroes.is_empty() else null
	# pass 69: a hero not owned never starts a run, whatever the button shows
	if c and _is_locked(c):
		Audio.play("ui_locked")
		return
	if c:
		Save.data["last_character"] = c.id
	Save.data["last_map"] = _map_id
	Save.request_save()
	# pass 87 (lane SUI): once the map's first stage is beaten, PLAY opens the Stages menu (every time); the live look
	# keeps its world for the way back, as for the other menus. Before that PLAY starts stage 1 as it always did.
	if StagesScreenScript.opens_for(_map_id):
		UiFx.go(get_tree(), "res://ui/StagesScreen.tscn")
		return
	Run.choose_stage(0)
	_leave_for_a_run()
	# pass 120 (lane STARTGO): the revolver wipe and the loading screen into the run (ui/RunCurtain.gd)
	UiFx.go_run(get_tree())


## A run starting lets the live look's world go (pass 52): the run builds its own map, and never carries two.
func _leave_for_a_run() -> void:
	TitleStageScript.forget()


## The hero's sheet over the title (pass 61): open while it is up and not on its way out.
func sheet_open() -> bool:
	return _sheet != null and is_instance_valid(_sheet) and not bool(_sheet.call("is_done"))


# ---------------------------------------------------------------- heroes to buy (pass 69)


## What the card and the BUY say for `c`, and which of them shows.
func _show_unknown(c: CharacterDef) -> void:
	if _req == null or _buy_col == null:
		return
	var st := _state(c)
	_req.visible = st == "locked"
	_buy_col.visible = st == "buyable"
	if st == "locked":
		var q := Registry.quest_for("character", c.id)
		_req_text.text = Registry.hero_requirement_text(c) if q else "Not in the game yet."
		var line: Control = _req.get_node("Rows/Line")
		var old := line.get_node_or_null("Bar")
		if old:
			line.remove_child(old)
			old.queue_free()
		var p := QuestTracker.progress(q) if q else Vector2i.ZERO
		if p.y > 0:
			var bar := WBar.make(clampf(float(p.x) / float(p.y), 0.0, 1.0), W.BRASS, 34.0, 4, 0)
			bar.name = "Bar"
			bar.custom_minimum_size.x = 280
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.text = "%s / %s" % [W.num(mini(p.x, p.y)), W.num(p.y)]
			bar.text_px = 20
			line.add_child(bar)


## The rect the shown hero's figure takes on the screen: the live hero's (TitleStage.figure_rect), else the cut-out's box.
func hero_figure_rect() -> Rect2:
	# pass 123: the figure inside the frame the Royale title draws (TitleStage's fractions of a strip's frame)
	var box := Rect2(_hero_row.position + _art_host.position, _art_host.size)
	var w := box.size.x * TitleStageScript.FIGURE_W
	return Rect2(Vector2(box.get_center().x - w * 0.5, box.position.y + box.size.y * TitleStageScript.FIGURE_TOP),
		Vector2(w, box.size.y * (TitleStageScript.FIGURE_FEET - TitleStageScript.FIGURE_TOP)))


## The BUY button: a hero on sale and a purse that holds his price asks first (WConfirm); short of it, it only says so.
func ask_buy() -> void:
	if _heroes.is_empty():
		return
	var c: CharacterDef = _heroes[_index]
	if _state(c) != "buyable":
		return
	if not Currency.can_afford(c.currency_type, maxi(c.price, 0)):
		Audio.play("ui_locked")
		return
	# pass 123 (lane MAINMENU): under Royale the shared confirm's buy (green; Wanted keeps its card as it was)
	WConfirm.open(self, "Buy this hero?", "%s from your purse. Yours to play from then on." % Currency.price_words(c.currency_type, maxi(c.price, 0)),
		"Buy · %s" % W.num(maxi(c.price, 0)), "Not now", func(): _buy_now(c), Callable(), "buy",
		WButton.price_parts(maxi(c.price, 0), "BUY", R.MODAL_BUTTON_PX, Currency.of(c.currency_type)))


## The purchase: the gold spent (Save.buy_hero, the sink "hero"), the mask lifted with a burst, the plaque and PLAY his.
func _buy_now(c: CharacterDef) -> void:
	if not Save.buy_hero(c):
		Audio.play("ui_locked")
		_show_plaque(c)
		_place()
		return
	Audio.play("ui_buy")
	Analytics.track("hero_bought", {"hero": c.id, "price": maxi(c.price, 0), "currency": Currency.of(c.currency_type), "gold_after": Save.gold()})
	_refresh_gold()
	# the carousel's order follows what is owned: he moves up among the owned heroes and stays the one shown
	_heroes = _roster()
	_index = maxi(_heroes.find(c), 0)
	_reveal_figure()
	_show_plaque(c)
	_place()
	var fig := hero_figure_rect()
	WCelebrate.burst(self, fig.get_center(), get_child_count(), 1.6)


## The gold plate's number after a purchase, and the Upgrade mark (a rank may no longer be affordable).
func _refresh_gold() -> void:
	if _gold_plate:
		for n in _gold_plate.find_children("Amount", "", true, false):
			(n as WText).text = W.num(Save.gold())
		# fewer digits: the plate shrinks to them
		_gold_plate.reset_size()
	_affordable = _rank_affordable()
	# pass 123: the Royale tab bar's Upgrade mark follows the purse too
	if _tab_bar and is_instance_valid(_tab_bar):
		_tab_bar.call("refresh")


## A tap on the plaque (pass 61): the shown hero's sheet, a locked one's with its quest.
func open_sheet() -> void:
	if _heroes.is_empty() or sheet_open():
		return
	var c: CharacterDef = _heroes[_index]
	_swipe_id = -2
	_sheet = WHeroSheetScript.open(self, c, _is_locked(c))
	# pass 111 (lane SKINS): a look worn or bought on the sheet: the purse and the hero behind it at once
	_sheet.connect("look_changed", func(_code: String): _on_sheet_look(c))


## The sheet's look changed (pass 111, lane SKINS): the gold plate, and the hero drawn again in the look he wears now.
func _on_sheet_look(c: CharacterDef) -> void:
	_refresh_gold()
	if _heroes.is_empty() or _heroes[_index] != c:
		return
	_show_hero(0)
	_place()


## A sideways swipe over the hero changes it; the finger is read here so it works wherever it lands in the row, and
## (pass 61) across the plaque, whose tap opens the hero's sheet: a swipe travels past the tap's slop, so it never opens it.
func _input(event: InputEvent) -> void:
	if sheet_open():
		return
	# pass 123: nothing moves under an open question (the buy's): the carousel stays on the hero it asks about
	if WConfirm.is_open(self):
		return
	var pos := Vector2.ZERO
	var id := -2
	var down := false
	var up := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		pos = t.position
		id = t.index
		down = t.pressed
		up = not t.pressed
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var m := event as InputEventMouseButton
		pos = m.position
		id = -1
		down = m.pressed
		up = not m.pressed
	else:
		return
	pos = get_viewport().get_canvas_transform().affine_inverse() * pos
	if down and _swipe_id == -2:
		var band := Rect2(Vector2(0, _hero_row.position.y), Vector2(get_viewport_rect().size.x, _hero_row.size.y))
		# (pass 123: the Royale title has no plaque; its band runs from over the hero's hat to the trait pill's foot)
		if band.has_point(pos) or (_plaque != null and _plaque.get_global_rect().has_point(pos)):
			_swipe_id = id
			_swipe_from = pos
	elif up and id == _swipe_id:
		_swipe_id = -2
		var d := pos - _swipe_from
		if absf(d.x) > SWIPE and absf(d.x) > absf(d.y) * 1.5:
			_step(-1 if d.x > 0 else 1)


## The lower block slides up 40 px and the rest fades in.
func _enter() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	for n in _lower:
		var c := n as Control
		var y := c.position.y
		c.position.y = y + 40.0
		create_tween().tween_property(c, "position:y", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- the Royale main menu (pass 123, lane MAINMENU)

## The Royale title's pieces (the mock 5_Main_menu; see the header): ≡, the wallet, ARENA, the wordmark, the hero band
## (the figure between ‹ ›), the requirement card and the BUY column, the name, the trait pill and DETAILS, START and the
## tab bar. Names for tools and tests: "MenuButton", "Wallet" (with "Amount"), "ArenaButton", "Wordmark" ("Logo",
## "Tagline"), "HeroRow" ("HeroBox" > "HeroFigure", "Prev", "Next"), "Requirement", "BuyColumn" ("Buy", "BuyNote"),
## "Name", "TraitRow" ("Pill", "Details"), "Start", "TabBar".
func _build_royale() -> void:
	set_process(false)
	# ≡: Settings (Garry: "Settings behind ≡")
	_menu_btn = WButton.make([{"glyph": "menu", "px": 40}], 40, WButton.SECONDARY, 4, 8, 24.0, 22.0, 40.0)
	_menu_btn.name = "MenuButton"
	_menu_btn.custom_minimum_size = Vector2(RY_MENU, RY_MENU)
	_menu_btn.pressed.connect(func(): UiFx.go(get_tree(), "res://ui/SettingsScreen.tscn"))
	add_child(_menu_btn)
	# the wallet, top right (WMenuHeader's Royale plate: the coin and the purse in white)
	_gold_plate = WMenuHeader.gold_plate(Save.gold(), 44, 40.0, 5, 4)
	_gold_plate.name = "Wallet"
	add_child(_gold_plate)
	# the debug arena beside ≡ (the wallet holds the top right)
	_arena_btn = WButton.make(["ARENA"], 28, WButton.SECONDARY, 4, 8, 18.0, 18.0, 28.0)
	_arena_btn.custom_minimum_size = RY_ARENA
	_arena_btn.visible = Settings.debug_mode and not Settings.is_prod()
	_arena_btn.name = "ArenaButton"
	_arena_btn.pressed.connect(_go_arena)
	add_child(_arena_btn)
	# the wordmark: OUTLAW over ★ SURVIVORS ★ (the words as today, W.GAME_NAME's)
	var mark := Control.new()
	mark.name = "Wordmark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_stack = mark
	add_child(mark)
	var logo := W.slab_text(W.GAME_WORD.to_upper(), RY_LOGO_PX, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, float(RY_LOGO_PX))
	logo.name = "Logo"
	logo.shadow = RY_LOGO_DROP
	mark.add_child(logo)
	var tag := WStarLine.make(W.GAME_LINE, RY_TAG_PX, W.BRASS, RY_TAG_EM)
	tag.name = "Tagline"
	# the mock's SURVIVORS: gold with the navy edge and a hard navy drop, no bevel (that is the big gold titles')
	var words := tag.get("_text") as WText
	if words:
		words.bevel = 0
		words.shadow = RY_TAG_DROP
	mark.add_child(tag)
	# the hero band: the figure on the disc between ‹ › (a swipe over it changes the hero, _input)
	_hero_row = Control.new()
	_hero_row.name = "HeroRow"
	_hero_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero_row)
	_art_host = Control.new()
	_art_host.name = "HeroBox"
	_art_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_row.add_child(_art_host)
	for side in [-1, 1]:
		var pad_v := (RY_ARROW - 8.0 - float(RY_ARROW_PX)) * 0.5
		var a := WButton.make(["‹" if side < 0 else "›"], RY_ARROW_PX, WButton.SECONDARY, 4, 8, pad_v, 18.0, float(RY_ARROW_PX))
		a.custom_minimum_size = Vector2(RY_ARROW, RY_ARROW)
		a.set_meta("side", side)
		a.pressed.connect(func(): _step(side))
		a.name = "Prev" if side < 0 else "Next"
		_hero_row.add_child(a)
	_build_unknown_royale()
	# the name, the trait pill and DETAILS
	_name = W.slab_text("", RY_NAME_PX, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, float(RY_NAME_PX))
	_name.name = "Name"
	add_child(_name)
	_trait_row = HBoxContainer.new()
	_trait_row.name = "TraitRow"
	_trait_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_trait_row.add_theme_constant_override("separation", RY_PILL_GAP)
	_trait_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_trait_row)
	var dv := (RY_DETAILS.y - 8.0 - float(RY_DETAILS_PX)) * 0.5
	_details_btn = WButton.make(["DETAILS"], RY_DETAILS_PX, WButton.UPGRADE, 4, 5, dv, 18.0, float(RY_DETAILS_PX), WButton.BLUE)
	_details_btn.name = "Details"
	_details_btn.custom_minimum_size = RY_DETAILS
	_details_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_details_btn.pressed.connect(open_sheet)
	# pass 124 (Garry: "Bring the Details button ... down from the stat summary. Because currently it flops around"): its own
	# row under the trait, the same spot for every hero
	add_child(_details_btn)
	# START: gold, today's PLAY flow (_on_play); LOCKED for a hero not owned
	var sv := (RY_START.y - 8.0 - float(RY_START_PX)) * 0.5
	_play = WButton.make(["START"], RY_START_PX, WButton.PRIMARY, 4, 8, sv, 22.0, float(RY_START_PX))
	_play.name = "Start"
	_play.pressed.connect(_on_play)
	add_child(_play)
	# the run-history line: on the Stages screen's header once that menu opens; until then here, under the trait (nothing
	# informational is removed, the map's best run has no other place before stage 1 is beaten)
	if not StagesScreenScript.opens_for(_map_id):
		var best := Save.best_run(_map_id)
		if not best.is_empty() and float(best.get("time", 0.0)) > 0.0:
			_run_pill = W.pill(StagesScreenScript.run_line(_map_id), R.PILL_PX, R.PILL_H)
			_run_pill.name = "RunLine"
			add_child(_run_pill)
	# the docked tab bar, BATTLE open (lane KIT2's WTabBar), over everything above
	_add_tab_bar()
	_lower = [_name, _trait_row, _details_btn, _play]


## The tab bar (WTabBar, BATTLE open), added last; the HEROES tab wears the hero the title shows (the save's last hero).
func _add_tab_bar() -> void:
	var at := -1
	if _tab_bar and is_instance_valid(_tab_bar):
		at = _tab_bar.get_index()
		remove_child(_tab_bar)
		_tab_bar.queue_free()
	_tab_bar = WTabBarScript.make("battle")
	add_child(_tab_bar)
	if at >= 0:
		move_child(_tab_bar, at)
	_tab_hero = _tab_key()


## Which hero (and look) the HEROES tab shows: the save's last hero in his played look.
func _tab_key() -> String:
	var d = WTabBarScript.hero_def()
	return "%s:%s" % [d.id, d.look_code()] if d != null else ""


## The requirement card (a locked hero: what unlocks him and how far along it is, over his feet) and the BUY column (one
## on sale: green price · BUY over his figure, "n short" under it when the purse is short), built once like Wanted's.
func _build_unknown_royale() -> void:
	_req = PanelContainer.new()
	_req.name = "Requirement"
	_req.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_req.add_theme_stylebox_override("panel", W.sheet_box(Vector2(26, 14)))
	var v := VBoxContainer.new()
	v.name = "Rows"
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_req.add_child(v)
	v.add_child(W.label("To unlock", 18, W.ROCK))
	var line := HBoxContainer.new()
	line.name = "Line"
	line.add_theme_constant_override("separation", 20)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	_req_text = W.serif_text("", 26, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	_req_text.name = "Text"
	_req_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_req_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_req_text)
	_req.visible = false
	add_child(_req)
	_buy_col = VBoxContainer.new()
	_buy_col.name = "BuyColumn"
	_buy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_buy_col.add_theme_constant_override("separation", 10)
	_buy_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy_col.visible = false
	add_child(_buy_col)


## The name, the trait pill, START, the requirement or the BUY, and the HEROES tab for `c` (the Royale _show_plaque).
## A hero not owned reads UNKNOWN with a "?" for each of his numbers (today's rule), START LOCKED.
func _show_royale(c: CharacterDef) -> void:
	var locked := _is_locked(c)
	var shown := ("The " + c.display_name) if c.id == "drifter" else c.display_name
	_name.text = ("Unknown" if locked else shown).to_upper()
	if _trait_pill:
		_trait_row.remove_child(_trait_pill)
		_trait_pill.queue_free()
		_trait_pill = null
	var parts := trait_parts(c, locked)
	if not parts.is_empty():
		_trait_pill = W.pill(parts)
		_trait_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_trait_row.add_child(_trait_pill)
		_trait_row.move_child(_trait_pill, 0)
	_play.locked = locked
	_play.set_parts(["LOCKED" if locked else "START"])
	if not locked:
		Save.data["last_character"] = c.id
		# the HEROES tab wears the hero shown (its portrait is made once: a new bar when he changes)
		if _tab_bar and _tab_key() != _tab_hero:
			_add_tab_bar()
	_show_unknown(c)
	if _buy_col and _state(c) == "buyable":
		_fill_buy_royale(c)


## The trait's numbers as the pill's parts (README: "one pill with the trait '+1% CRIT per Level'"): each number bold in
## green (red for a debuff), its stat's short name and "per Level" for what grows with his level (today's "/ LV"), a
## " · " between two; a hero not owned "?" and "???" (today's plaque).
func trait_parts(c: CharacterDef, locked: bool) -> Array:
	var out: Array = []
	var stats := _stats_of(c)
	for i in stats.size():
		var st: Array = stats[i]
		if i > 0:
			out.append("  ·  ")
		if locked:
			out.append(["?", R.SECONDARY, "bold"])
			out.append(" ???")
			continue
		out.append([str(st[0]), R.ROLES["green"]["top"] if bool(st[2]) else R.ROLES["red"]["top"], "bold"])
		out.append(" " + per_level(str(st[1])))
	return out


## "CRIT / LV" -> "CRIT per Level" (Garry: "per Level", never "/ LV").
static func per_level(label: String) -> String:
	return label.replace(" / LV", " per Level")


## The BUY over a hero on sale: the green price button (WButton.price; short of it, the locked grey with the price alone
## and "n short" in red under it), his currency's icon.
func _fill_buy_royale(c: CharacterDef) -> void:
	for n in _buy_col.get_children():
		_buy_col.remove_child(n)
		n.queue_free()
	var cur := Currency.of(c.currency_type)
	var price := maxi(c.price, 0)
	var short := maxi(price - Currency.balance(cur), 0)
	_buy = WButton.price(price, "BUY", WButton.GREEN, RY_BUY_PX, short, cur, true, RY_BUY_H)
	_buy.name = "Buy"
	_buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_buy.pressed.connect(ask_buy)
	_buy_col.add_child(_buy)
	# "n short" in red on a black pill (it reads over the black figure), as the shops' shortfall
	var note := W.pill([["%s short" % W.num(short), R.ROLES["red"]["top"], "bold"]], 24, 40.0)
	note.name = "BuyNote"
	note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	note.visible = short > 0
	_buy_col.add_child(note)


## The hero on the disc, as a run draws him (his played look's strip, idling at its speed), sliding in from the side the
## finger went (the painted cut-out's 0.2 s); a hero not owned a black silhouette with the padlock while locked.
func _show_figure(c: CharacterDef, from_side: int) -> void:
	var old := _figure
	_figure = HeroFigure.new()
	_figure.name = "HeroFigure"
	_figure.setup(Registry.played_look(c), c)
	_figure.backdrop = _backdrop
	_figure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _is_locked(c):
		_figure.tint = MASK
		if _state(c) == "locked":
			var lock := _padlock_royale()
			lock.name = "Padlock"
			_figure.add_child(lock)
	_art_host.add_child(_figure)
	_figure.size = _art_host.size
	_figure.pivot_offset = _figure.feet()
	_place_lock_royale()
	if from_side == 0:
		if old:
			old.queue_free()
		_figure.refresh_shadow()
		return
	if old:
		_run_off(old, -from_side)
	_run_in(_figure, from_side)


## Pass 124 (Garry: "Let's make the hero run in and out like we had before. But let's make it so they run in diagonally because it
## always looked weird how fast they turn from side to facing us. Make the sequence smooth"): the next hero comes from up the sand on
## `side` down a straight diagonal in his three-quarter run (run_fd), growing as he nears, slowing as he arrives; he then stops in the
## three-quarter idle for a beat and only then turns to face us. The one standing leaves down the same diagonal the other way,
## starting slowly. A press in the middle of it just starts the next one from where things stand.
func _run_in(f: HeroFigure, side: int) -> void:
	f.flip = side > 0
	f.play(["run_fd", "run_s", "run_f", "run"])
	var from := Vector2(side * RY_RUN_DX, -RY_RUN_DY) * _fig_k
	f.position = from
	f.scale = Vector2.ONE * RY_RUN_FAR
	f.refresh_shadow()
	var tw := f.create_tween()
	f.tween = tw
	tw.tween_method(func(u: float) -> void:
		var k := 1.0 - pow(1.0 - u, 2.4)
		f.position = from.lerp(Vector2.ZERO, k)
		f.scale = Vector2.ONE * lerpf(RY_RUN_FAR, 1.0, k)
		f.anim_rate = lerpf(1.15, 0.55, u * u)
		f.refresh_shadow(), 0.0, 1.0, RY_RUN_IN)
	tw.tween_callback(func() -> void:
		f.anim_rate = 1.0
		f.play(["idle_fd", "idle_s", "idle_f", "idle"]))
	tw.tween_interval(RY_TURN_BEAT)
	tw.tween_callback(func() -> void:
		f.flip = false
		f.play(["idle_f", "idle_fd", "idle"])
		f.tween = null)


## The other half: `side` is where he is heading (-1 the left).
func _run_off(f: HeroFigure, side: int) -> void:
	if f.tween and f.tween.is_valid():
		f.tween.kill()
	f.flip = side < 0
	f.anim_rate = 1.0
	f.play(["run_fd", "run_s", "run_f", "run"])
	var from := f.position
	var from_s := f.scale.x
	var to := Vector2(side * RY_RUN_DX, RY_RUN_DY) * _fig_k
	var tw := f.create_tween()
	f.tween = tw
	tw.tween_method(func(u: float) -> void:
		var k := pow(u, 1.8)
		f.position = from.lerp(to, k)
		f.scale = Vector2.ONE * lerpf(from_s, RY_RUN_NEAR, k)
		f.modulate.a = clampf(1.0 - u / RY_RUN_FADE, 0.0, 1.0)
		f.refresh_shadow(), 0.0, 1.0, RY_RUN_OUT)
	tw.tween_callback(f.queue_free)


## A hero just bought: the black mask lifts off his figure (TitleStage.REVEAL_TIME, the live look's reveal), the padlock
## goes.
func _reveal_figure() -> void:
	if _figure == null:
		return
	var lock := _figure.get_node_or_null("Padlock")
	if lock:
		lock.queue_free()
	var f := _figure
	create_tween().tween_method(func(k: float): f.set_tint(MASK.lerp(Color.WHITE, k)), 0.0, 1.0, TitleStageScript.REVEAL_TIME)


## The padlock on the figure's chest, in the figure's own units.
func _place_lock_royale() -> void:
	if _figure == null:
		return
	var lock := _figure.get_node_or_null("Padlock") as Control
	if lock == null:
		return
	var h := _art_host.size.y
	var chest := h * (TitleStageScript.FIGURE_TOP + RY_LOCK_CHEST * (TitleStageScript.FIGURE_FEET - TitleStageScript.FIGURE_TOP))
	var s := RY_LOCK_SCALE * _fig_k
	lock.scale = Vector2(s, s)
	lock.position = Vector2(_art_host.size.x * 0.5 - 60.0 * s, chest - 80.0 * s)


## The padlock in the kit's colours: a navy shackle round a pale bar, a gold body in a navy edge, a navy keyhole.
func _padlock_royale() -> Control:
	var l := Control.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(120, 140)
	l.draw.connect(func():
		var c := Vector2(60, 0)
		l.draw_arc(c + Vector2(0, 58), 34.0, PI, TAU, 32, R.NAVY, 26.0, true)
		l.draw_arc(c + Vector2(0, 58), 34.0, PI, TAU, 32, R.MUTED, 12.0, true)
		var sb := R.flat(R.GOLD_TEXT, 14)
		sb.border_color = R.NAVY
		sb.set_border_width_all(6)
		l.draw_style_box(sb, Rect2(Vector2(4, 56), Vector2(112, 84)))
		l.draw_circle(c + Vector2(0, 88), 11.0, R.NAVY, true, -1.0, true)
		l.draw_rect(Rect2(c + Vector2(-5, 92), Vector2(10, 26)), R.NAVY))
	return l


## The Royale layout (the mock's numbers, see the constants): the top row and the wordmark under the camera cutout, START
## over the tab bar and the gesture bar, the hero group round the backdrop's disc (half the extra height lower on a taller
## screen, as the backdrop keeps its spot; the hero times the plate's scale on a wide one).
func _place_royale() -> void:
	var vp := get_viewport_rect().size
	var top := W.safe_top()
	_menu_btn.position = Vector2(RY_MENU_POS.x, RY_MENU_POS.y + top)
	_menu_btn.size = Vector2(RY_MENU, RY_MENU)
	_gold_plate.reset_size()
	var ws := _gold_plate.get_combined_minimum_size()
	_gold_plate.position = Vector2(vp.x - RY_WALLET.x - ws.x, RY_WALLET.y + top)
	_gold_plate.size = ws
	_arena_btn.position = Vector2(RY_ARENA_POS.x, RY_ARENA_POS.y + top)
	_arena_btn.size = RY_ARENA
	_top_stack.position = Vector2(0, top)
	_top_stack.size = Vector2(vp.x, RY_TAG_TOP + RY_TAG_PX * 1.25)
	var logo := _top_stack.get_node("Logo") as Control
	logo.position = Vector2(0, RY_LOGO_TOP)
	logo.size = Vector2(vp.x, RY_LOGO_PX)
	var tag := _top_stack.get_node("Tagline") as Control
	var ts := tag.get_combined_minimum_size()
	tag.size = ts
	# the star line's box is 1.25 of its size, the words in its middle: their top on the mock's 330
	tag.position = Vector2((vp.x - ts.x) * 0.5, RY_TAG_TOP - (ts.y - RY_TAG_PX) * 0.5)
	var start_top := vp.y - W.safe_bottom() - RY_START_UP
	var sw := minf(RY_START.x, vp.x - 90.0)
	_play.position = Vector2((vp.x - sw) * 0.5, start_top)
	_play.size = Vector2(sw, RY_START.y)
	# the disc: the backdrop's own spot (lower by half the extra height on a taller screen), told back to it
	_disc = Vector2(vp.x * 0.5, 1160.0 + (vp.y - 1920.0) * 0.5)
	_fig_k = 1.0
	if _backdrop and _backdrop.has_method("disc_center"):
		_backdrop.call("set_disc", _disc, float(_backdrop.call("disc_radius")))
		_fig_k = maxf(float(_backdrop.call("plate_scale")), 1.0)
	# the figure's frame: the strip's frame drawn so the figure inside it (TitleStage's fractions) is RY_FIGURE_H tall
	var fig_h := RY_FIGURE_H * _fig_k
	var span := TitleStageScript.FIGURE_FEET - TitleStageScript.FIGURE_TOP
	var frame_h := fig_h / span
	var frame_w := frame_h * (_figure.aspect() if _figure else 1.0)
	var feet_y := _disc.y - RY_FEET_UP
	var band_top := feet_y - fig_h - 40.0
	var band_bottom := _disc.y + RY_PILL_DOWN + R.PILL_H + 10.0
	_hero_row.position = Vector2(0, band_top)
	_hero_row.size = Vector2(vp.x, band_bottom - band_top)
	_art_host.position = Vector2(_disc.x - frame_w * 0.5, feet_y - frame_h * TitleStageScript.FIGURE_FEET - band_top)
	_art_host.size = Vector2(frame_w, frame_h)
	if _figure:
		_figure.size = _art_host.size
		_figure.pivot_offset = _figure.feet()
		_figure.refresh_shadow()
	for a in _hero_row.get_children():
		if a is WButton:
			var side: int = a.get_meta("side")
			var x := _disc.x - RY_ARROW_X if side < 0 else _disc.x + RY_ARROW_X - RY_ARROW
			a.position = Vector2(x, _disc.y - RY_ARROW_UP - band_top)
			a.size = Vector2(RY_ARROW, RY_ARROW)
	_place_lock_royale()
	var name_y := _disc.y + RY_NAME_DOWN
	_name.position = Vector2(0, name_y)
	_name.size = Vector2(vp.x, RY_NAME_PX)
	_trait_row.reset_size()
	var rs := _trait_row.get_combined_minimum_size()
	_trait_row.size = rs
	_trait_row.position = Vector2((vp.x - rs.x) * 0.5, _disc.y + RY_PILL_DOWN + (R.PILL_H - rs.y) * 0.5)
	var details_y := _disc.y + RY_PILL_DOWN + R.PILL_H + RY_DETAILS_GAP
	_details_btn.size = RY_DETAILS
	_details_btn.position = Vector2((vp.x - RY_DETAILS.x) * 0.5, details_y)
	if _run_pill:
		var ps := _run_pill.get_combined_minimum_size()
		_run_pill.size = ps
		_run_pill.position = Vector2((vp.x - ps.x) * 0.5, details_y + RY_DETAILS.y + RY_DETAILS_GAP + 8.0)
	# a locked hero's requirement over his feet, its foot just over the name; the BUY over the middle of his figure
	if _req:
		# its words wrap only once it has its width: it grows upwards from its foot when they take a second line
		var rw := minf(RY_REQ_W, vp.x - 80.0)
		_req.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_req.size = Vector2(rw, 0)
		_req.reset_size()
		_req.size = Vector2(rw, 0)
		var h := _req.get_combined_minimum_size().y
		_req.position = Vector2((vp.x - rw) * 0.5, name_y - RY_REQ_GAP - R.PANEL_BASE - h)
	if _buy_col:
		var fig := hero_figure_rect()
		_buy_col.reset_size()
		var cs := _buy_col.get_combined_minimum_size()
		_buy_col.size = cs
		_buy_col.position = Vector2(fig.get_center().x - cs.x * 0.5, fig.position.y + fig.size.y * 0.5 - RY_BUY_H * 0.5)


## The hero as a run draws him, flat on the title (pass 123, lane MAINMENU): one frame of his played look's strip at a
## time (the grid the strip is: strip_cols a row, else one row), his front idle (idle_f, else idle_fd, else idle; the
## order Player and TitleStage lay a strip out in) stepped at the look's own speed (its `fps` for "idle", else
## BillboardSprite's 4 a second). A frame is drawn only when it changes; nothing is made a frame. `tint` multiplies it:
## MASK is the black silhouette of a hero not owned.
class HeroFigure extends Control:
	var tex: Texture2D
	var tint := Color.WHITE
	var cols := 1
	var first := 0
	var count := 1
	var fps := 4.0
	var frame := 0
	var cell := Vector2(256, 256)
	var flip := false
	var anim_rate := 1.0
	var tween: Tween
	var backdrop: Control
	var offsets := {}
	var speeds := {}
	var _t := 0.0
	var _shadow: FigureShadow
	var _contact: TextureRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## The strip, its grid and the idle's frames from `look` (the def's played look; `def` for a drawn stand-in).
	func setup(look: CharacterDef, def: CharacterDef) -> void:
		tex = look.sprite if look else null
		var anims: Dictionary = look.anims if look else {}
		var grid := look.strip_cols if look and tex else 0
		speeds = look.fps if look and tex else {}
		if tex == null:
			tex = PlaceholderArt.character_strip(def)
			anims = {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
		offsets = {}
		var k := 0
		for a in TitleStageScript.ORDER:
			var n := int(anims.get(a, 0))
			if n > 0:
				offsets[a] = [k, n]
				k += n
		var total := maxi(k, 1)
		cols = grid if grid > 0 else total
		var rows := int(ceil(float(total) / float(maxi(cols, 1))))
		if tex:
			cell = Vector2(float(tex.get_width()) / float(maxi(cols, 1)), float(tex.get_height()) / float(maxi(rows, 1)))
		play(["idle_f", "idle_fd", "idle"])

	## The first of `names` his strip has, from its first frame.
	func play(names: Array) -> void:
		var anim := "idle"
		for want in names:
			if offsets.has(want):
				anim = want
				break
		var slot: Array = offsets.get(anim, [0, 1])
		first = int(slot[0])
		count = maxi(int(slot[1]), 1)
		fps = speed_of(speeds, anim)
		frame = 0
		_t = 0.0
		set_process(count > 1)
		queue_redraw()
		if _shadow:
			_shadow.queue_redraw()

	## The look's speed for `anim` (the first `fps` key it begins with, as BillboardSprite reads it), else BillboardSprite's own
	## for a run and RY_IDLE_FPS for the rest.
	static func speed_of(speed_map: Dictionary, anim: String) -> float:
		for key in speed_map.keys():
			if anim.begins_with(str(key)):
				return float(speed_map[key])
		if anim.begins_with("run"):
			return float(BillboardSprite.SPEEDS.get("run", 10.0))
		return RY_IDLE_FPS

	## The frame's width over its height (the title sizes the box by it).
	func aspect() -> float:
		return cell.x / cell.y if cell.y > 0.0 else 1.0

	## Where his soles stand, in this control's own px (the figure's box: what he is placed and scaled by).
	func feet() -> Vector2:
		return Vector2(size.x * 0.5, size.y * TitleStageScript.FIGURE_FEET)

	## Pass 126: where the paint of his soles really ends: his shadow and the pool under him start here, touching his feet.
	func soles() -> Vector2:
		return Vector2(size.x * 0.5, size.y * TitleStageScript.FIGURE_SOLE)

	func set_tint(c: Color) -> void:
		tint = c
		queue_redraw()

	## The part of the strip his frame takes.
	func frame_rect() -> Rect2:
		var i := first + frame
		return Rect2(Vector2(float(i % cols), float(i / cols)) * cell, cell)

	## His shadow again, for where he stands now (the backdrop says which way the sun throws it).
	func refresh_shadow() -> void:
		if backdrop == null or not is_inside_tree() or not backdrop.has_method("figure_axis"):
			return
		if _shadow == null:
			_shadow = FigureShadow.new()
			_shadow.figure = self
			_shadow.setup(backdrop)
			add_child(_shadow)
			_contact = TextureRect.new()
			_contact.name = "Contact"
			_contact.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_contact.show_behind_parent = true
			_contact.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_contact.stretch_mode = TextureRect.STRETCH_SCALE
			_contact.texture = _contact_texture()
			_contact.modulate = Color(1, 1, 1, 0.75)
			add_child(_contact)
		_shadow.size = size
		var cw := Vector2(size.x * 0.4, size.x * 0.11)
		_contact.size = cw
		_contact.position = soles() - cw * 0.5
		var parent_xf := get_parent_control().get_global_transform() if get_parent_control() else Transform2D()
		var foot_global: Vector2 = parent_xf * (position + pivot_offset)
		_shadow.axis = backdrop.call("figure_axis", backdrop.get_global_transform().affine_inverse() * foot_global)
		_shadow.queue_redraw()

	## The soft pool under his soles.
	static func _contact_texture() -> Texture2D:
		var g := Gradient.new()
		g.set_color(0, Color(0.08, 0.04, 0.11, 0.95))
		g.set_color(1, Color(0.08, 0.04, 0.11, 0.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		return t

	func _process(delta: float) -> void:
		_t = fmod(_t + delta * fps * anim_rate, float(count))
		var f := int(_t)
		if f != frame:
			frame = f
			queue_redraw()
			if _shadow:
				_shadow.queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		var dst := Rect2(Vector2.ZERO, Vector2(-size.x, size.y)) if flip else Rect2(Vector2.ZERO, size)
		draw_texture_rect_region(tex, dst, frame_rect(), tint)


## Pass 124: a hero's shadow is his own frame on the sand: the picture flipped at his soles and thrown away from the sun, blurred along
## its length (the shader the props' shadows use), redrawn when his frame changes.
class FigureShadow extends Control:
	var figure: HeroFigure
	var axis := Vector2(0.15, 0.3)
	var _mat: ShaderMaterial

	func _init() -> void:
		name = "FigureShadow"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		show_behind_parent = true

	func setup(bd: Control) -> void:
		var sh: Dictionary = bd.call("shadow_style")
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://core/shaders/ui_backdrop_shadow.gdshader")
		_mat.set_shader_parameter("shadow_color", Color(str(sh.get("color", "#1a0c24"))))
		_mat.set_shader_parameter("strength", float(sh.get("alpha", 0.6)))
		_mat.set_shader_parameter("foot_v", TitleStageScript.FIGURE_SOLE)
		_mat.set_shader_parameter("blur_near", float(sh.get("blur_near", 0.006)))
		_mat.set_shader_parameter("blur_far", float(sh.get("blur_far", 0.05)))
		material = _mat

	func _draw() -> void:
		if figure == null or figure.tex == null:
			return
		var src := figure.frame_rect()
		var ts := figure.tex.get_size()
		_mat.set_shader_parameter("region", Vector4(src.position.x / ts.x, src.position.y / ts.y, src.size.x / ts.x, src.size.y / ts.y))
		var foot := figure.soles()
		# a point `h` px above his soles lands `h` x axis from them, across the sand
		var ax := Vector2.RIGHT
		var ay := -axis
		draw_set_transform_matrix(Transform2D(ax, ay, foot - ax * foot.x - ay * foot.y))
		var dst := Rect2(Vector2.ZERO, Vector2(-size.x, size.y)) if figure.flip else Rect2(Vector2.ZERO, size)
		draw_texture_rect_region(figure.tex, dst, src)
