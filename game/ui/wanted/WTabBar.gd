## The docked bottom tab bar (pass 123, lane KIT2; the handoff's README "Docked tabs" and the mock 5_Main_menu; Garry:
## "Keep the tab bar on all four hub screens (Heroes, Battle, Upgrade, Collections), the open one gold", "Show STORE as a
## locked tab, as the mock"). Royale only: ScreenBase adds it to a screen whose tab_bar() names its tab, the main menu
## adds its own. A band R.DOCK_BAR_H tall at the foot, above the phone's gesture bar (W.safe_bottom; the band runs on
## under it to the screen's edge), a 4 px navy top edge and a 10 % white lip; five tabs STORE, HEROES, BATTLE, UPGRADE,
## COLLECTIONS, R.DOCK_SIDE in from either side and R.DOCK_GAP apart, slate faces with their top corners rounded 8 px and
## no bottom edge; the open one gold, R.DOCK_TAB_H_ACTIVE tall against R.DOCK_TAB_H and R.DOCK_ACTIVE_FLEX times as wide,
## its word navy Ultra 28; the others' words cream Ultra 22 with a navy drop (pass 126; Garry: "It's weird that the font changes
## when I tap that button. Make it so it's the same westerny style font": one face open or not, over his Ultra minimum, and a word
## too long for its tab shrinks to fit: _fit_word). Each wears the
## game's own icon: STORE the Hush Money sack (greyed), HEROES the hero the title opens on in the look he is played in
## (his round badge in a navy ring), BATTLE the Revolver, UPGRADE the crown of Stakes' Boss form, COLLECTIONS the Field
## Notes card in its played look.
## STORE is locked (there is no store; no new rule): the locked grey with a lock badge; a finger on it plays ui_locked and
## shakes the tab (the Stages' closed card's shake), nothing else. HEROES is locked the same way while
## res://ui/HeroesScreen.tscn does not exist. A finger on another tab goes to its screen with today's cross-fade (UiFx.go;
## `navigate` replaces that for a test or a tool); the open tab's tap does nothing. The UPGRADE tab carries the title's
## mark (pass 123: a red "!" crumb, core/systems/Crumbs.gd) while a rank of the Upgrade board is newly affordable (upgrade_mark(), the rule of the title's
## _rank_affordable), except on the Upgrade board itself.
## No class_name: load it by path,
##     var bar: Control = load("res://ui/wanted/WTabBar.gd").make("upgrade")
## and add it last to a full-rect screen (it anchors itself to the foot). Nodes for tools: the bar "TabBar", its band
## "Band" (takes the touches between the tabs), the tabs "Tab_store" .. "Tab_collections" (WTap; metas "tab" and
## "locked"), "LockBadge", "UpgradeMark". Nothing is done a frame: it draws when it changes.
extends Control

## Every tap on a tab, the open one and the locked ones too (before anything happens).
signal tab_pressed(id: String)

const SELF_PATH := "res://ui/wanted/WTabBar.gd"
const TABS := ["store", "heroes", "battle", "upgrade", "collections"]
const WORDS := {"store": "STORE", "heroes": "OUTLAWS", "battle": "BATTLE", "upgrade": "UPGRADE", "collections": "COLLECTIONS"}
## Where each tab goes ("" nowhere: there is no store).
const SCENES := {"store": "", "heroes": "res://ui/HeroesScreen.tscn", "battle": "res://ui/TitleScreen.tscn",
	"upgrade": "res://ui/HomesteadScreen.tscn", "collections": "res://ui/CollectionScreen.tscn"}
## Pass 129 (lane TRAIL-UI): once the Trail has nodes (Trail.has_nodes) the fourth tab reads TRAIL, opens the Trail screen,
## wears the boots and carries the same red crumb by the same rule (pass 123: red, gone once the player has been shown)
## on the Trail's nodes: a node the purse can buy now that the player has not been shown (Crumbs.upgrade_due reads the
## Trail then); the tab's id stays "upgrade" (node Tab_upgrade, UpgradeMark). While the Trail is empty it is the Upgrade
## board's tab as before.
const TRAIL_SCENE := "res://ui/TrailScreen.tscn"
const TRAIL_WORD := "TRAIL"
const TRAIL_ICON := "boots"
## The locked tab's icon: desaturated and darker (the mock's saturate(.15) brightness(.8)).
const GREY_SHADER := "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = COLOR;\n\tfloat l = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(vec3(l), c.rgb, 0.15) * 0.8, c.a);\n}\n"

## Pass 126: what a word keeps clear of its tab's sides, and the smallest it shrinks to.
const WORD_PAD := 16.0
const WORD_MIN_PX := 14

## The tab of the screen the bar sits on.
var active := "battle"
## Where a tap goes: unset = UiFx.go(get_tree(), path); a test or a tool sets a Callable(path: String).
var navigate: Callable
var _tabs: Dictionary = {}
var _band: Control
var _lock_badge: Control
var _mark: Control
var _mark_heroes: Control
var _heroes_due := false
var _affordable := false

static var _grey: ShaderMaterial


## The bar with `p_active` open ("store", "heroes", "battle", "upgrade" or "collections"; anything else reads battle).
static func make(p_active: String = "battle") -> Control:
	var s: GDScript = load(SELF_PATH)
	var b: Control = s.new()
	b.set("active", p_active if TABS.has(p_active) else "battle")
	b.call("_build")
	return b


## The band's height over the screen's foot, the gesture bar's inset under it: where a board above the bar ends.
static func height() -> float:
	return float(R.DOCK_BAR_H) + W.safe_bottom()


## How far up the bar reaches (the open tab rises R.DOCK_TAB_H_ACTIVE over the gesture bar's inset).
static func reach() -> float:
	return float(R.DOCK_TAB_H_ACTIVE) + W.safe_bottom()


## The scene a tab opens ("" for STORE).
static func scene_of(id: String) -> String:
	if id == "upgrade" and trail_on():
		return TRAIL_SCENE
	return str(SCENES.get(id, ""))


## Pass 129: whether the fourth tab is the Trail's (the Trail has nodes and its screen exists).
static func trail_on() -> bool:
	return Trail.has_nodes() and ResourceLoader.exists(TRAIL_SCENE)


## A tab's word (pass 129: TRAIL on the fourth tab once the Trail has nodes).
static func word_of(id: String) -> String:
	return TRAIL_WORD if id == "upgrade" and trail_on() else str(WORDS.get(id, ""))


## Whether a tab goes anywhere: STORE never, HEROES once its screen exists, the rest always.
static func opens(id: String) -> bool:
	var p := scene_of(id)
	return p != "" and ResourceLoader.exists(p)


## Whether the purse buys the next rank of any open talent: the title's Upgrade mark (TitleScreen._rank_affordable, the
## same rule; the title can call this one instead).
static func upgrade_mark() -> bool:
	var reg := W.node("Registry")
	var save := W.node("Save")
	if reg == null or save == null:
		return false
	for def in reg.talents_list():
		if not reg.is_unlocked("talent", def.id):
			continue
		var cost: int = def.cost_of_rank(save.talent_rank(def.id))
		if cost >= 0 and Currency.can_afford(def.currency_type, cost):
			return true
	return false


## The hero the HEROES tab shows: the one the title opens on (the save's last hero), the Drifter when he is gone.
static func hero_def():
	var reg := W.node("Registry")
	var save := W.node("Save")
	if reg == null:
		return null
	var last := "drifter"
	if save != null:
		last = str(save.data.get("last_character", "drifter"))
	var c = reg.playable_character(last)
	if c == null:
		c = reg.playable_character("drifter")
	return reg.played_look(c) if c != null else null


## A tab's icon from the game's own art (null when it is missing: the tab shows its word alone).
static func icon_of(id: String) -> Texture2D:
	var reg := W.node("Registry")
	if reg == null:
		return null
	var def = null
	match id:
		"store":
			def = reg.passive("hush_money")
		"heroes":
			def = hero_def()
		"battle":
			def = reg.weapon("revolver")
		"upgrade":
			if trail_on() and Trail.icon(TRAIL_ICON) != null:
				return Trail.icon(TRAIL_ICON)
			var t = reg.talent("spite")
			return t.form_icon(1) if t != null else null
		"collections":
			def = reg.passive("field_notes")
	return def.icon if def != null else null


func _build() -> void:
	name = "TabBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -reach()
	offset_bottom = 0.0
	_band = Control.new()
	_band.name = "Band"
	# the touches between and under the tabs stop here (nothing beneath the bar takes them)
	_band.mouse_filter = Control.MOUSE_FILTER_STOP
	_band.draw.connect(_draw_band)
	add_child(_band)
	for id: String in TABS:
		var t := _make_tab(id)
		_tabs[id] = t
		add_child(t)
	_lock_badge = _badge("LockBadge", false)
	add_child(_lock_badge)
	_mark = make_crumb("UpgradeMark", float(R.DOCK_BADGE))
	add_child(_mark)
	_mark_heroes = make_crumb("HeroesMark", float(R.DOCK_BADGE))
	add_child(_mark_heroes)
	_read_crumbs()
	resized.connect(_layout)
	_layout()


## The tab `id` (a WTap named Tab_<id>).
func tab(id: String) -> WTap:
	return _tabs.get(id) as WTap


## Whether a finger on `id` is refused (STORE, and HEROES while its screen does not exist).
func is_locked(id: String) -> bool:
	return id != active and not opens(id)


## The mark and the locks again (the purse changed: a rank bought on the Upgrade board).
func refresh() -> void:
	_read_crumbs()
	for id: String in TABS:
		var t: WTap = _tabs[id]
		var lk := is_locked(id)
		t.set_meta("locked", lk)
		t.locked = lk
	_layout()


## What a finger on tab `id` does: the open tab nothing, a locked one its shake, the rest their screen.
func press(id: String) -> void:
	tab_pressed.emit(id)
	if id == active:
		return
	if is_locked(id):
		W.sfx("ui_locked")
		_shake(_tabs[id])
		return
	var path := scene_of(id)
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		UiFx.go(get_tree(), path)


func _make_tab(id: String) -> WTap:
	var on := id == active
	var lk := is_locked(id)
	var t := WTap.new()
	t.name = "Tab_%s" % id
	t.set_meta("tab", id)
	t.set_meta("locked", lk)
	var hb := W.box(W.PAPER, R.BUTTON_EDGE, 0).pad(6, 4, 6, 8)
	# pass 127: the closed tabs' own tint (R.DOCK_ROLE), apart from every tile and button above the bar
	hb.role = WButton.GOLD if on else R.DOCK_ROLE
	hb.sides = [true, true, true, false]
	hb.radius = R.RADIUS_TAB
	hb.corners = [true, true, false, false]
	t.box = hb
	t.box_down = hb.pressed()
	t.locked = lk
	var v := VBoxContainer.new()
	v.name = "Face"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	v.add_child(_icon(id, on, lk))
	var px := R.DOCK_WORD_ACTIVE_PX if on else R.DOCK_WORD_PX
	var word := W.text(word_of(id), R.display(), px, R.NAVY if on else R.CREAM, HORIZONTAL_ALIGNMENT_CENTER, float(px))
	word.name = "Word"
	# pass 126: W.text sets a display size under R.ULTRA_MIN in Rubik; the bar keeps its one face in every state
	word.font = R.display()
	if on:
		R.no_edge(word)
	else:
		# the mock's 2 px navy drop keeps it off the slate
		word.stroke = 0
		word.shadow = 2
		word.shadow_color = R.NAVY
		word.shadow_straight = true
	_fit_word(word, on)
	v.add_child(word)
	t.pressed.connect(press.bind(id))
	return t


## Pass 126: Ultra is wide: a word longer than its tab (COLLECTIONS) drops a px at a time until it fits, its line box kept so
## every word in the bar sits on the same line.
func _fit_word(word: WText, on: bool) -> void:
	var room := tab_width(on) - WORD_PAD
	while word.font_size > WORD_MIN_PX and word.text_width() > room:
		word.font_size -= 1


## A tab's width on the design's 1080 canvas (a wider screen only gives it more).
static func tab_width(on: bool) -> float:
	var n := float(TABS.size())
	var unit := (1080.0 - 2.0 * R.DOCK_SIDE - R.DOCK_GAP * (n - 1.0)) / (n - 1.0 + R.DOCK_ACTIVE_FLEX)
	return unit * (R.DOCK_ACTIVE_FLEX if on else 1.0)


func _icon(id: String, on: bool, lk: bool) -> Control:
	var side := float(R.DOCK_ICON_ACTIVE if on else R.DOCK_ICON)
	var holder := Control.new()
	holder.name = "Icon"
	holder.custom_minimum_size = Vector2(side, side)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := icon_of(id)
	if tex == null:
		holder.custom_minimum_size.y = 0.0
		return holder
	if id == "heroes":
		# the round badge in a navy ring (the mock's 80 px portrait)
		holder.draw.connect(func() -> void:
			var d := float(R.DOCK_PORTRAIT)
			var r := Rect2((holder.size - Vector2(d, d)) * 0.5, Vector2(d, d))
			holder.draw_texture_rect(tex, r, false, Color(0.62, 0.62, 0.66) if lk else Color.WHITE)
			holder.draw_arc(r.get_center(), d * 0.5, 0.0, TAU, 48, R.NAVY, float(R.DOCK_PORTRAIT_RING), true))
		return holder
	var tr := TextureRect.new()
	tr.name = "Art"
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if lk:
		tr.material = _grey_material()
	holder.add_child(tr)
	return holder


static func _grey_material() -> ShaderMaterial:
	if _grey == null:
		var sh := Shader.new()
		sh.code = GREY_SHADER
		_grey = ShaderMaterial.new()
		_grey.shader = sh
	return _grey


## The crumbs (pass 123, core/systems/Crumbs.gd; Garry: red, and gone once tapped until there is something new): the
## Upgrade board's while a rank the player has not been shown is affordable, the Heroes screen's while a look is newly
## unlocked. Never on the open tab.
func _read_crumbs() -> void:
	_affordable = Crumbs.upgrade_due()
	_heroes_due = Crumbs.any_look_due()


## The lock's round badge on a tab's top-right corner (slate, a gold padlock).
func _badge(n: String, _mark_unused: bool) -> Control:
	var b := Control.new()
	b.name = n
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size = Vector2(R.DOCK_BADGE, R.DOCK_BADGE)
	b.draw.connect(func() -> void:
		var d := float(R.DOCK_BADGE)
		var c := Vector2(d, d) * 0.5
		b.draw_circle(c, d * 0.5, R.NAVY, true, -1.0, true)
		var inner := d * 0.5 - float(R.DOCK_BADGE_RING)
		b.draw_circle(c, inner, R.DOCK_BADGE_FILL, true, -1.0, true)
		var g := Vector2(18.0, 22.0)
		W.draw_glyph(b, "lock", Rect2(c - g * 0.5, g), R.GOLD_TEXT, R.DOCK_BADGE_FILL))
	return b


## A red crumb (pass 123): a round red badge with a white "!", `d` px across. The Heroes screen's LOOKS button and hero
## tiles wear the same one.
static func make_crumb(n: String, d: float) -> Control:
	var b := Control.new()
	b.name = n
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size = Vector2(d, d)
	b.custom_minimum_size = b.size
	b.draw.connect(func() -> void:
		var k := d / 46.0
		var c := Vector2(d, d) * 0.5
		b.draw_circle(c, d * 0.5, R.NAVY, true, -1.0, true)
		b.draw_circle(c, d * 0.5 - float(R.DOCK_BADGE_RING) * k, R.ROLES["red"]["bottom"], true, -1.0, true)
		b.draw_rect(Rect2(c + Vector2(-3.0, -11.0) * k, Vector2(6.0, 13.0) * k), Color.WHITE)
		b.draw_circle(c + Vector2(0.0, 7.5) * k, 3.2 * k, Color.WHITE, true, -1.0, true))
	return b


func _layout() -> void:
	var w := size.x if size.x > 1.0 else 1080.0
	var full_h := size.y if size.y > 1.0 else reach()
	var sb := W.safe_bottom()
	var foot := full_h - sb
	var n := TABS.size()
	var unit := (w - 2.0 * R.DOCK_SIDE - R.DOCK_GAP * float(n - 1)) / (float(n - 1) + R.DOCK_ACTIVE_FLEX)
	var x := float(R.DOCK_SIDE)
	for id: String in TABS:
		var on := id == active
		var tw := unit * (R.DOCK_ACTIVE_FLEX if on else 1.0)
		var th := float(R.DOCK_TAB_H_ACTIVE if on else R.DOCK_TAB_H)
		var t: WTap = _tabs[id]
		t.position = Vector2(roundf(x), foot - th)
		t.size = Vector2(roundf(tw), th)
		x += tw + R.DOCK_GAP
	_band.position = Vector2(0.0, foot - R.DOCK_BAR_H)
	_band.size = Vector2(w, R.DOCK_BAR_H + sb)
	_band.queue_redraw()
	var store: WTap = _tabs["store"]
	_lock_badge.visible = is_locked("store")
	_lock_badge.position = Vector2(store.position.x + store.size.x + R.DOCK_BADGE_OUT.x - R.DOCK_BADGE, store.position.y - R.DOCK_BADGE_OUT.y)
	var up: WTap = _tabs["upgrade"]
	_mark.visible = _affordable and active != "upgrade"
	_mark.position = Vector2(up.position.x + up.size.x + R.DOCK_BADGE_OUT.x - R.DOCK_BADGE, up.position.y - R.DOCK_BADGE_OUT.y)
	var he: WTap = _tabs["heroes"]
	_mark_heroes.visible = _heroes_due and active != "heroes"
	_mark_heroes.position = Vector2(he.position.x + he.size.x + R.DOCK_BADGE_OUT.x - R.DOCK_BADGE, he.position.y - R.DOCK_BADGE_OUT.y)


func _draw_band() -> void:
	var s := _band.size
	_band.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([R.DOCK_BAR_TOP, R.DOCK_BAR_TOP, R.DOCK_BAR_BOTTOM, R.DOCK_BAR_BOTTOM]))
	var e := float(R.DOCK_BAR_EDGE)
	_band.draw_rect(Rect2(0.0, 0.0, s.x, e), R.NAVY)
	_band.draw_rect(Rect2(0.0, e, s.x, e), Color(1, 1, 1, R.DOCK_BAR_LIP))


## A refused tap: the tab shakes sideways and settles (the Stages' closed card's numbers).
func _shake(c: Control) -> void:
	# a second tap mid-shake starts again from the tab's place, never from where the last shake had it
	if c.has_meta("shake"):
		var old = c.get_meta("shake")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	_layout()
	var x := c.position.x
	var tw := c.create_tween()
	c.set_meta("shake", tw)
	var n := 4
	for k in n:
		var s := 1.0 - float(k) / float(n)
		tw.tween_property(c, "position:x", x + (R.DOCK_SHAKE_PX * s if k % 2 == 0 else -R.DOCK_SHAKE_PX * s), R.DOCK_SHAKE_S / float(n + 1))
	tw.tween_property(c, "position:x", x, R.DOCK_SHAKE_S / float(n + 1))
