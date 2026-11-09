## The Trail (pass 129, lane TRAIL-UI; docs/trail_schema.md; Garry: "For the UI try to do something similar to
## survivor.io", _REFERENCES/2d/survivorio1.jpg, survivorio2.jpg). The game's permanent progression as one long track of
## nodes bought with gold, level 1 at the bottom, read from core/systems/Trail.gd (the rules live there, never here).
## The tab bar's fourth tab opens it once the Trail has nodes (WTabBar.scene_of).
##
## What is on screen, top to bottom: a dark header band (the back square, TRAIL, "LEVEL n" = the Trail Level, the
## purse); the track, which a finger scrolls; the dock (the node chosen: its picture, name, what it gives, where the
## player stands with it, and BUY with its price); the tab bar.
## The track (the schema's Layout: rows ROW apart, the required nodes of a level placed by their count, optional ones
## beside them, the right quarter kept free): the backdrop is the sections' two colours blending up the track with the
## section's sign tiled faintly over it; every level's number stands in a diamond at the left; rails run from each node
## to the nodes it comes from; a choice group is joined by a bar with an OR between its members (a padlock once one is
## taken); a section's name hangs on a small plate at the right where it begins; the end plate stands over the last
## level. Above level Trail Level + 1 everything lies in a dark band with a crisp edge (THE LINE), and still shows.
## A tile reads by its state on any section colour: bought = green rim, warm face, its picture in full colour, a green
## tick, lit rails; open = slate face under a pulsing gold rim with its price beneath (grey with the amount in red when
## the purse is short); locked = dark slate, the picture grey; closed (the road not taken) = dimmer still, struck
## through in red. An optional node is a smaller tile on a thinner rail; a node with a `name` wears a second frame and
## its name on a plaque.
## It opens centred on the node bought last (a new save: level 1) with the next node to buy chosen; opened by
## TrailScreen.open_on(type, id) (a "Reach Trail Level N" line, through Nav.to_trail) it centres on that thing's node,
## chosen and ringed in gold, and Back returns to the screen the player came from (Nav.back). A tap on a tile chooses
## it. BUY buys it (Trail.buy); a choice and a node whose upgrade warns ask once more (WConfirm). A purchase pops the
## tile, lights its rails and names the gift in a toast; a level done slides the line up and shows "TRAIL LEVEL n".
## Only what is near the view exists: tiles are pooled (about thirty), the canvas draws the visible rows, so a track of
## 500 levels costs what one of 40 does. Nodes for tools: "Track", "Canvas", "Dock" ("Buy", "DockName", "DockGives",
## "DockState"), the tiles "Node_<id>" (metas "node", "state").
class_name TrailScreen
extends ScreenBase

const SELF_SCENE := "res://ui/TrailScreen.tscn"
const MOTIF_ART := "res://art/ui/trail/motifs/%s.png"
const STAGE_ART := "res://art/ui/stages/%s_%s.jpg"
const FEATURE_ART := {"wanted": "res://art/ui/wanted/barrel.png"}

## The schema's layout numbers (design width 1080).
const ROW := 236.0
const TILE := 148.0
const TILE_FOUR := 132.0
const TILE_OPTIONAL := 116.0
const X_BY_COUNT := {1: [0.50], 2: [0.33, 0.60], 3: [0.20, 0.42, 0.64], 4: [0.12, 0.30, 0.48, 0.66]}
const OPTIONAL_STEP := 0.20
const OPTIONAL_RIGHT_MAX := 0.68
const DIAMOND_X := 0.06
const RAIL := 22.0
const RAIL_THIN := 12.0
## The screen's own: the header band and the dock (px), the room over the last level (the end plate) and under the
## first, the motif grid, the diamond's half diagonal.
const HEAD_H := 176.0
const DOCK_H := 252.0
const DOCK_FOOT := 30.0
const PAD_TOP := 300.0
const PAD_BOTTOM := 80.0
const MOTIF_STEP := 216.0
const MOTIF_PX := 112.0
const MOTIF_INK := Color(0, 0, 0, 0.075)
const DIAMOND := 44.0
## A row whose leftmost tile reaches the diamond wears a smaller one, lifted into the gap over the row.
const DIAMOND_SMALL := 32.0
const BAND := Color(0.05, 0.065, 0.14, 0.82)
const RAIL_LIT := Color("6fd63f")
const RAIL_LIT_HI := Color("b9f58e")
const RAIL_DARK := Color("3a4661")
const RAIL_CLOSED := Color("272f45")
const TICK := Color("4fc43a")
const STRIKE := Color("e2402f")
## A tile's colours by state: the rim, the face's top and bottom.
const LOOK := {
	"bought": [Color("7ddc45"), Color("ffa53d"), Color("ee7620")],
	"open": [Color("f5b82a"), Color("5a6c98"), Color("38476c")],
	"locked": [Color("55627f"), Color("2c3552"), Color("1d2439")],
	"closed": [Color("3b4359"), Color("242b3f"), Color("191e2e")],
}
const GREY_SHADER := "shader_type canvas_item;\nuniform float bright = 0.55;\nuniform float alpha = 1.0;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat l = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(vec3(l) * bright, c.a * alpha);\n}\n"

## Opened on a thing's node (open_on), read once by build().
static var _want_type := ""
static var _want_id := ""
static var _boxes: Dictionary = {}
static var _mats: Dictionary = {}
## A tool's stopwatch: the microseconds spent laying tiles and drawing the canvas, and how many times.
static var bench_usec := 0
static var bench_calls := 0

## The node chosen (the dock shows it), and the one a requirement line asked for (ringed in gold).
var selected := ""
var ringed := ""
var _track: Control
var _canvas: Control
var _head: Control
var _dock: Control
var _wallet: PanelContainer
var _level_pill: Control
var _toasts: WToasts
var _banner: WBanner
var _tiles: Dictionary = {}
var _spare: Array = []
var _lay: Dictionary = {}
var _where: Dictionary = {}
var _links_of: Dictionary = {}
var _motifs: Dictionary = {}
var _track_h := 0.0
var _vis_lo := 0
var _vis_hi := -1
var _last_sv := -1
var _from_nav := false
var _line_shift := 0.0
var _clock := 0.0
var _placed := false
var _scroll_tw: Tween
var _line_tw: Tween


## The Trail opens on the node that gives `type` `id` (centred, chosen, ringed), once: the next build() reads it.
static func open_on(type: String, id: String) -> void:
	_want_type = type
	_want_id = id


# ---------------------------------------------------------------- the frame

func tab_bar() -> String:
	return "upgrade"


func board_sheet() -> bool:
	return false


func board_top() -> float:
	return HEAD_H


func board_room() -> float:
	return 0.0


func board_side() -> float:
	return 0.0


func board_bottom() -> float:
	return DOCK_H


func header_right() -> Control:
	_wallet = WMenuHeader.gold_plate(Currency.balance(Trail.currency()), 44, 40.0, 5, 4)
	return _wallet


func build() -> void:
	set_title(Loc.t("ui.trail.title"))
	_from_nav = Nav.arrived()
	# the Trail has its own backdrop: the menu's painting and its dim are not shown
	if backdrop:
		backdrop.visible = false
	wash.visible = false
	margin.add_theme_constant_override("margin_bottom", 0)
	content.add_theme_constant_override("separation", 0)
	_touch.only_inside = true
	_track_h = PAD_TOP + ROW * float(Trail.levels()) + PAD_BOTTOM
	_track = Control.new()
	_track.name = "Track"
	_track.mouse_filter = Control.MOUSE_FILTER_PASS
	_track.custom_minimum_size = Vector2(0.0, _track_h)
	_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_track)
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.clip_contents = true
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.offset_top = scroll.offset_top
	_canvas.offset_bottom = scroll.offset_bottom
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)
	move_child(_canvas, scroll.get_index())
	_head = Control.new()
	_head.name = "HeadBand"
	_head.mouse_filter = Control.MOUSE_FILTER_STOP
	_head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_head.offset_bottom = HEAD_H + W.safe_top()
	_head.draw.connect(_draw_head)
	add_child(_head)
	_dock = Control.new()
	_dock.name = "Dock"
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dock.offset_top = -(tab_bar_height() + DOCK_H)
	_dock.offset_bottom = -tab_bar_height()
	_dock.draw.connect(_draw_dock)
	add_child(_dock)
	_toasts = WToasts.new()
	_toasts.name = "Toasts"
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toasts.offset_top = HEAD_H + W.safe_top() + 36.0
	_toasts.offset_bottom = _toasts.offset_top + 200.0
	add_child(_toasts)
	_banner = WBanner.new()
	add_child(_banner)
	# what the screen opens on: the thing asked for, else the node bought last, else level 1
	var want := ""
	if _want_type != "":
		var g := Trail.gate(_want_type, _want_id)
		want = str(g.get("id", ""))
	_want_type = ""
	_want_id = ""
	ringed = want
	var centre := want if want != "" else _last_bought()
	selected = want if want != "" else _next_open()
	if selected == "":
		selected = centre
	if centre == "" and Trail.levels() > 0:
		var first := Trail.nodes_on(1)
		centre = str(first[0]["id"]) if not first.is_empty() else ""
	if selected == "":
		selected = centre
	_fill_head()
	_fill_dock()
	_show_note()
	# the tab's red crumb: everything the purse can buy now has been shown (pass 123's rule, on the Trail's nodes)
	Crumbs.upgrade_mark_seen()
	_place.call_deferred(centre)


## The migration's note (Save.board_note, kind "trail_refund"), said once in toasts, a sentence each, then forgotten.
func _show_note() -> void:
	var words := Trail.note_text(Save.board_note())
	if words == "":
		return
	Save.clear_board_note()
	for s: String in words.split(". ", false):
		_toasts.push(s.trim_suffix(".") + ".")


func _enter() -> void:
	for c: Control in [scroll, _canvas]:
		c.modulate.a = 0.0


## The first frame with the track laid: the scroll goes to `centre`'s row and the track fades in.
func _place(centre: String) -> void:
	var lv := int(Trail.node(centre).get("level", 1)) if centre != "" else 1
	# the list takes the scroll only once it has laid the track out (a frame, sometimes a few on a cold start)
	for k in 30:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var want := int(_scroll_for(_row_y(lv)))
		scroll.scroll_vertical = want
		if absi(scroll.scroll_vertical - want) <= 1 and _track.size.y >= _track_h - 1.0:
			break
	_last_sv = scroll.scroll_vertical
	_placed = true
	_sync(true)
	for c: Control in [scroll, _canvas]:
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.2)


func on_back() -> void:
	if _from_nav and Nav.back():
		return
	go(TITLE)


func _process(delta: float) -> void:
	super._process(delta)
	_clock += delta
	if _toasts:
		_toasts.tick(delta)
	if not _placed:
		return
	if scroll.scroll_vertical != _last_sv:
		_last_sv = scroll.scroll_vertical
		_sync(false)
	var p := 0.5 + 0.5 * sin(_clock * 4.2)
	for t: Tile in _tiles.values():
		if t.state == "open" or t.ring:
			t.set_pulse(p)


# ---------------------------------------------------------------- where things stand

## The track's y of level `l`'s row (its middle).
func _row_y(l: int) -> float:
	return _track_h - PAD_BOTTOM - (float(l) - 0.5) * ROW


## The level whose row holds track y `y` (1 .. the last).
func _level_at(y: float) -> int:
	return clampi(int(floor((_track_h - PAD_BOTTOM - y) / ROW)) + 1, 1, maxi(Trail.levels(), 1))


func _view_h() -> float:
	return scroll.size.y if scroll.size.y > 1.0 else 1200.0


## The scroll that puts track y `y` in the middle of the view.
func _scroll_for(y: float) -> float:
	return clampf(y - _view_h() * 0.5, 0.0, maxf(_track_h - _view_h(), 0.0))


func _width() -> float:
	return _track.size.x if _track and _track.size.x > 1.0 else 1080.0


## Level `l`'s nodes placed: [{id, x (0..1), side}] in file order (the schema's Layout).
func _lay_level(l: int) -> Array:
	if _lay.has(l):
		return _lay[l]
	var out: Array = []
	var req: Array = []
	var opt: Array = []
	for n: Dictionary in Trail.nodes_on(l):
		if str(n["kind"]) == "optional":
			opt.append(n)
		else:
			req.append(n)
	var xs := _spread(req.size())
	var side := TILE_FOUR if req.size() >= 4 else TILE
	var left := 1.0
	var right := 0.0
	for i in req.size():
		var n: Dictionary = req[i]
		var x := float(n["x"]) if n.has("x") else float(xs[i])
		left = minf(left, x)
		right = maxf(right, x)
		out.append({"id": str(n["id"]), "x": x, "side": side})
	if req.is_empty():
		var oxs := _spread(opt.size())
		for i in opt.size():
			var n: Dictionary = opt[i]
			out.append({"id": str(n["id"]), "x": float(n["x"]) if n.has("x") else float(oxs[i]), "side": TILE_OPTIONAL})
	else:
		# the first to the right of the rightmost required node while that is no further right than 0.68, else left of
		# the leftmost; the second takes the other side; any more keep stepping outward on the left
		var first_right := right <= OPTIONAL_RIGHT_MAX
		var lefts := 0
		for i in opt.size():
			var n: Dictionary = opt[i]
			var x := 0.0
			if (i == 0 and first_right) or (i == 1 and not first_right):
				x = right + OPTIONAL_STEP
			else:
				lefts += 1
				x = left - OPTIONAL_STEP * float(lefts)
			if n.has("x"):
				x = float(n["x"])
			out.append({"id": str(n["id"]), "x": clampf(x, 0.05, 0.95), "side": TILE_OPTIONAL})
	_lay[l] = out
	var y := _row_y(l)
	for e: Dictionary in out:
		_where[str(e["id"])] = Vector3(float(e["x"]), y, float(e["side"]))
	return out


static func _spread(n: int) -> Array:
	if X_BY_COUNT.has(n):
		return X_BY_COUNT[n]
	var out: Array = []
	for i in n:
		out.append(lerpf(0.10, 0.68, float(i) / float(maxi(n - 1, 1))))
	return out


## Node `id`'s place: (x in px, y on the track, its tile's side).
func _spot(id: String) -> Vector3:
	if not _where.has(id):
		var n := Trail.node(id)
		if n.is_empty():
			return Vector3(_width() * 0.5, 0.0, TILE)
		_lay_level(int(n["level"]))
	var v: Vector3 = _where.get(id, Vector3(0.5, 0.0, TILE))
	return Vector3(v.x * _width(), v.y, v.z)


## The rails into node `id`: [[from id, thin]]. An optional node that names none hangs on the nearest required node
## of its own level.
func _links(id: String) -> Array:
	if _links_of.has(id):
		return _links_of[id]
	var out: Array = []
	var n := Trail.node(id)
	var optional := str(n["kind"]) == "optional"
	if optional and (n["from"] as Array).is_empty():
		var me := _spot(id)
		var best := ""
		var best_d := INF
		for e: Dictionary in _lay_level(int(n["level"])):
			var other := str(e["id"])
			if other == id or str(Trail.node(other)["kind"]) == "optional":
				continue
			var d := absf(float(e["x"]) * _width() - me.x)
			if d < best_d:
				best_d = d
				best = other
		if best != "":
			out.append([best, true])
	if out.is_empty():
		for p: Variant in Trail.from_of(id):
			out.append([str(p), optional])
	_links_of[id] = out
	return out


func _last_bought() -> String:
	var b := Save.trail_bought()
	for i in range(b.size() - 1, -1, -1):
		if not Trail.node(str(b[i])).is_empty():
			return str(b[i])
	return ""


## The next node to buy: the open required one on the lowest level; with none, the lowest open optional one.
func _next_open() -> String:
	var best := ""
	var best_key := 1 << 30
	for n: Dictionary in Trail.nodes():
		var id := str(n["id"])
		if Trail.state(id) != "open":
			continue
		var key := int(n["level"]) + (1 << 20 if str(n["kind"]) == "optional" else 0)
		if key < best_key:
			best_key = key
			best = id
	return best


## The track's y of THE LINE (the top edge of level Trail Level + 1's row); -INF when every level is done.
func _line_y() -> float:
	var tl := Trail.level()
	if tl >= Trail.levels():
		return -INF
	return _row_y(tl + 1) - ROW * 0.5


# ---------------------------------------------------------------- the tiles (only those near the view)

func _sync(force: bool) -> void:
	var t0 := Time.get_ticks_usec()
	var sv := float(scroll.scroll_vertical)
	var lo := maxi(_level_at(sv + _view_h()) - 1, 1)
	var hi := mini(_level_at(sv) + 1, Trail.levels())
	if force or lo != _vis_lo or hi != _vis_hi:
		_vis_lo = lo
		_vis_hi = hi
		var keep := {}
		for l in range(lo, hi + 1):
			for e: Dictionary in _lay_level(l):
				keep[str(e["id"])] = true
		for id: String in _tiles.keys():
			if not keep.has(id):
				var old: Tile = _tiles[id]
				_tiles.erase(id)
				old.visible = false
				_spare.append(old)
		for id: String in keep.keys():
			var t: Tile = _tiles.get(id)
			if t == null:
				t = _spare.pop_back() if not _spare.is_empty() else _new_tile()
				t.visible = true
				_tiles[id] = t
				_dress(t, id)
			elif force:
				_dress(t, id)
	_canvas.queue_redraw()
	bench_usec += Time.get_ticks_usec() - t0
	bench_calls += 1


func _new_tile() -> Tile:
	var t := Tile.new()
	_track.add_child(t)
	t.pressed.connect(func() -> void: select(t.id))
	return t


## Tile `t` as node `id` stands now.
func _dress(t: Tile, id: String) -> void:
	var n := Trail.node(id)
	var at := _spot(id)
	t.name = "Node_" + id
	t.set_meta("node", id)
	t.position = Vector2(at.x - at.z * 0.5, at.y - at.z * 0.5)
	_set_tile(t, n, at.z)
	t.chosen = id == selected
	t.ring = id == ringed
	t.refresh()


func _set_tile(t: Tile, n: Dictionary, side: float) -> void:
	var id := str(n["id"])
	t.id = id
	t.side = side
	t.size = Vector2(side, side)
	t.state = Trail.state(id)
	t.set_meta("state", t.state)
	t.optional = str(n["kind"]) == "optional"
	t.named = str(n.get("name", ""))
	t.price = Trail.price(id) if t.state == "open" else -1
	t.short = t.state == "open" and not Trail.can_buy(id)
	var g: Dictionary = n["gives"]
	t.picture = str(g.get("type", "")) == "stage" or str(g.get("type", "")) == "map"
	t.set_art(gift_art(n))


## The tile of node `id` while it is near the view (null otherwise).
func tile_of(id: String) -> Control:
	return _tiles.get(id) as Control


## The level whose row lies in the middle of the view.
func centre_level() -> int:
	return _level_at(float(scroll.scroll_vertical) + _view_h() * 0.5)


## What a node's tile shows: an upgrade's icon, else the thing's own picture (an outlaw's badge, a skin's still, an
## item's icon, a stage's picture, a structure's or a power-up's icon); null when there is none.
static func gift_art(n: Dictionary) -> Texture2D:
	var g: Dictionary = n.get("gives", {})
	var id := str(g.get("id", ""))
	var def: Variant = null
	match str(g.get("type", "")):
		"upgrade":
			return Trail.icon(str(g.get("upgrade", "")))
		"outlaw":
			var c := Registry.character(id)
			def = Registry.played_look(c) if c else null
		"skin":
			var hc := Registry.character(id.get_slice(":", 0))
			if hc:
				var still := hc.look_still_path(id.get_slice(":", 1))
				if still != "" and ResourceLoader.exists(still):
					return load(still)
				def = hc
		"weapon":
			def = Registry.weapon(id)
		"passive":
			def = Registry.passive(id)
		"stage", "map":
			var map_id := str(g.get("map", id.get_slice(":", 0)))
			var m := Registry.map(map_id)
			var k := maxi(Trail.stage_index(map_id, str(g.get("stage", id.get_slice(":", 1)))), 0)
			if m and m.timeline and k < m.timeline.stage_list.size():
				var own := str((m.timeline.stage_list[k] as Dictionary).get("shot", ""))
				if own != "" and ResourceLoader.exists(own):
					return load(own)
			var p := STAGE_ART % [map_id, "s%d" % (k + 1)]
			return load(p) if ResourceLoader.exists(p) else null
		"structure":
			def = Registry.structure(id)
		"powerup":
			def = Registry.pickup(id)
		"feature":
			var fp := str(FEATURE_ART.get(id, ""))
			return load(fp) if fp != "" and ResourceLoader.exists(fp) else null
	return def.get("icon") as Texture2D if def is Object else null


## A node's short name: its own, else its upgrade type's, else the thing it gives.
static func name_of(n: Dictionary) -> String:
	var own := str(n.get("name", ""))
	if own != "":
		return own
	var g: Dictionary = n.get("gives", {})
	if str(g.get("type", "")) == "upgrade":
		return str(Trail.upgrade(str(g.get("upgrade", ""))).get("name", str(g.get("upgrade", ""))))
	return thing_of(n)


## The thing an unlock gives, without its kind ("Outlaw: Astro" -> "Astro", "Skin: Astro, Moonwalker" -> "Moonwalker").
static func thing_of(n: Dictionary) -> String:
	var words := Trail.give_text(n)
	var g: Dictionary = n.get("gives", {})
	var at := words.find(": ")
	if at >= 0:
		words = words.substr(at + 2)
	if str(g.get("type", "")) == "skin" and words.contains(", "):
		words = words.get_slice(", ", 1)
	return words


## The toast a purchase shows ("Astro rides with you").
static func gift_words(n: Dictionary) -> String:
	var g: Dictionary = n.get("gives", {})
	var what := thing_of(n)
	match str(g.get("type", "")):
		"outlaw":
			return Loc.t("ui.trail.gift.outlaw", {"what": what})
		"skin":
			return Loc.t("ui.trail.gift.skin", {"what": what})
		"weapon", "passive":
			return Loc.t("ui.trail.gift.item", {"what": what})
		"stage", "map", "feature":
			return Loc.t("ui.trail.gift.open", {"what": what})
		"structure":
			return Loc.t("ui.trail.gift.structure", {"what": what})
		"powerup":
			return Loc.t("ui.trail.gift.powerup", {"what": what})
	return Trail.give_text(n)


## Where the player stands with node `n`, in words (the dock's line).
static func state_words(n: Dictionary) -> String:
	var id := str(n["id"])
	match Trail.state(id):
		"bought":
			return Loc.t("ui.trail.state.yours")
		"closed":
			return Loc.t("ui.trail.state.closed")
		"locked":
			if int(n["level"]) > Trail.level() + 1:
				return Loc.t("ui.trail.state.finish_level", {"level": str(int(n["level"]) - 1)})
			var need: Array = []
			for p: Variant in Trail.from_of(id):
				if Trail.state(str(p)) != "bought":
					need.append(name_of(Trail.node(str(p))))
			return Loc.t("ui.trail.state.take_first", {"nodes": join(need)}) if not need.is_empty() else Loc.t("ui.trail.state.locked")
	var sib := siblings_of(n)
	if not sib.is_empty():
		return Loc.t("ui.trail.closes", {"nodes": join(sib)})
	return ""


## Names in plain words: "A", "A and B", "A, B and C".
static func join(names: Array) -> String:
	if names.size() <= 1:
		return str(names[0]) if names.size() == 1 else ""
	var head: Array = names.slice(0, names.size() - 1)
	return Loc.t("ui.trail.join_and", {"head": ", ".join(head), "last": str(names[names.size() - 1])})


## The other members of an open choice's group, by name ([] for anything else).
static func siblings_of(n: Dictionary) -> Array:
	var out: Array = []
	if str(n["kind"]) != "choice":
		return out
	for other: Variant in Trail.group(str(n["id"])):
		if str(other) != str(n["id"]) and Trail.state(str(other)) != "bought":
			out.append(name_of(Trail.node(str(other))))
	return out


# ---------------------------------------------------------------- choosing and buying

## Chooses node `id` (a tap on its tile): the ring moves, the dock shows it, the track scrolls it clear of the edges.
func select(id: String) -> void:
	if Trail.node(id).is_empty():
		return
	var old := selected
	selected = id
	for k: String in [old, id]:
		var t: Tile = _tiles.get(k)
		if t:
			t.chosen = k == selected
			t.refresh()
	_fill_dock()
	_reveal(id)


func _reveal(id: String) -> void:
	var at := _spot(id)
	var sv := float(scroll.scroll_vertical)
	var top := at.y - at.z * 0.5 - 40.0
	var foot := at.y + at.z * 0.5 + 70.0
	var to := sv
	if top < sv:
		to = top
	elif foot > sv + _view_h():
		to = foot - _view_h()
	to = clampf(to, 0.0, maxf(_track_h - _view_h(), 0.0))
	if absf(to - sv) < 1.0:
		return
	if _scroll_tw:
		_scroll_tw.kill()
	_scroll_tw = create_tween()
	_scroll_tw.tween_property(scroll, "scroll_vertical", int(to), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The dock's BUY: a short purse says no; a choice and a node whose upgrade warns ask once more; else it is bought.
func press_buy() -> void:
	var n := Trail.node(selected)
	if n.is_empty() or not Trail.can_buy(selected):
		W.sfx("ui_locked")
		return
	# pass 137 (lane TUTOR): the first BUY the purse can pay ends its highlight for good
	_buy_tapped()
	var g: Dictionary = n["gives"]
	var warn := str(Trail.upgrade(str(g.get("upgrade", ""))).get("warn", "")) if str(g.get("type", "")) == "upgrade" else ""
	var sib := siblings_of(n)
	if sib.is_empty() and warn == "":
		buy_selected()
		return
	var lines: Array = []
	if not sib.is_empty():
		lines.append(Loc.t("ui.trail.closes", {"nodes": join(sib)}))
	if warn != "":
		lines.append(warn)
	var cur := Trail.currency()
	WConfirm.open(self, Loc.t("ui.trail.confirm_title", {"node": name_of(n)}), " ".join(lines), Loc.t("ui.trail.confirm_buy"), Loc.t("ui.trail.not_now"), func() -> void: buy_selected(),
		Callable(), "buy", WButton.price_parts(Trail.price(selected), Loc.t("ui.trail.buy"), R.MODAL_BUTTON_PX, cur))


## Buys the node chosen (Trail.buy) and shows it: the tile pops, its rails light, the gift in a toast; a level done
## slides the line up under "TRAIL LEVEL n". True when it was bought.
func buy_selected() -> bool:
	var id := selected
	var n := Trail.node(id)
	var level_was := Trail.level()
	var line_was := _line_y()
	if n.is_empty() or not Trail.buy(id):
		W.sfx("ui_locked")
		return false
	var g: Dictionary = n["gives"]
	W.sfx("ui_buy" if str(g.get("type", "")) == "upgrade" else "ui_unlock")
	_links_of.clear()
	Crumbs.upgrade_mark_seen()
	_toasts.push(gift_words(n), W.PAPER, gift_art(n) if str(g.get("type", "")) == "upgrade" else null)
	_fill_head()
	if tab_bar_node and tab_bar_node.has_method("refresh"):
		tab_bar_node.call("refresh")
	if Trail.level() > level_was:
		var line_now := _line_y()
		# the line starts where it stood and slides up to its new place
		_line_shift = (line_was - line_now) if line_now > -INF and line_was > -INF else ROW
		if _line_tw:
			_line_tw.kill()
		_line_tw = create_tween()
		_line_tw.tween_method(func(v: float) -> void:
			_line_shift = v
			_canvas.queue_redraw(), _line_shift, 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_banner.play(Loc.t("ui.trail.level_banner", {"level": str(Trail.level())}), false, null, HEAD_H + W.safe_top() + 150.0)
		W.sfx("ui_levelup")
	_sync(true)
	var t: Tile = _tiles.get(id)
	if t:
		t.pivot_offset = t.size * 0.5
		t.scale = Vector2(1.22, 1.22)
		t.create_tween().tween_property(t, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		WCelebrate.burst(self, t.get_global_rect().get_center(), _dock.get_index(), 1.2)
	# on to the next node to buy on the track, while there is one
	var next := _next_open()
	if next != "":
		select(next)
	else:
		_fill_dock()
	return true


# ---------------------------------------------------------------- the header and the dock

func _fill_head() -> void:
	if _wallet:
		for a in _wallet.find_children("Amount", "", true, false):
			(a as WText).text = W.num(Currency.balance(Trail.currency()))
		_wallet.reset_size()
	if header == null:
		return
	if _level_pill:
		header.remove_child(_level_pill)
		_level_pill.queue_free()
	_level_pill = W.pill([[Loc.t("ui.trail.level") + " ", R.SECONDARY, "bold"], [str(Trail.level()), R.GOLD_TEXT, "bold"]], 30, 56.0)
	_level_pill.name = "TrailLevel"
	header.add_child(_level_pill)
	_level_pill.position = Vector2(header.title.position.x + header.title.text_width() + 26.0, header.title.position.y + 6.0)


func _draw_head() -> void:
	var s := _head.size
	_head.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([R.DOCK_BAR_TOP, R.DOCK_BAR_TOP, R.DOCK_BAR_BOTTOM, R.DOCK_BAR_BOTTOM]))
	_head.draw_rect(Rect2(0.0, s.y - 4.0, s.x, 4.0), R.NAVY)


func _draw_dock() -> void:
	var s := _dock.size
	_dock.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([R.SLATE_MID, R.SLATE_MID, R.SLATE_BOTTOM, R.SLATE_BOTTOM]))
	_dock.draw_rect(Rect2(0.0, 0.0, s.x, 4.0), R.NAVY)
	_dock.draw_rect(Rect2(0.0, 4.0, s.x, 3.0), Color(1, 1, 1, R.PANEL_LIP))


## The dock again for the node chosen.
func _fill_dock() -> void:
	for c in _dock.get_children():
		_dock.remove_child(c)
		c.queue_free()
	# pass 137 (lane TUTOR): the highlight waits for the new BUY (none on a node that is not open)
	_tutor_buy(null)
	var n := Trail.node(selected)
	if n.is_empty():
		var hint := W.serif_text(Loc.t("ui.trail.hint") if Trail.has_nodes() else Loc.t("ui.trail.not_laid"), 28, R.SECONDARY, 400, false,
			HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
		hint.name = "DockState"
		hint.position = Vector2(0.0, 90.0)
		hint.size = Vector2(1080.0, 40.0)
		_dock.add_child(hint)
		return
	var st := Trail.state(selected)
	var usable := DOCK_H - DOCK_FOOT
	var small := Tile.new()
	small.inert = true
	small.name = "DockTile"
	_dock.add_child(small)
	_set_tile(small, n, 124.0)
	small.named = ""
	small.price = -1
	small.position = Vector2(30.0, (usable - 124.0) * 0.5 + 4.0)
	small.refresh()
	var x0 := 184.0
	var right_w := 320.0
	var x1 := 1080.0 - 30.0 - right_w
	var room := x1 - x0 - 22.0
	var nm := W.slab_text(name_of(n).to_upper(), 40, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 44.0)
	nm.name = "DockName"
	_fit(nm, room, 26)
	_dock.add_child(nm)
	nm.position = Vector2(x0, 22.0)
	nm.size = Vector2(room, 44.0)
	var gv := W.serif_text(Trail.give_text(n), 32, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 38.0)
	gv.name = "DockGives"
	_fit(gv, room, 22)
	_dock.add_child(gv)
	gv.position = Vector2(x0, 76.0)
	gv.size = Vector2(room, 38.0)
	var g: Dictionary = n["gives"]
	var warn := str(Trail.upgrade(str(g.get("upgrade", ""))).get("warn", "")) if str(g.get("type", "")) == "upgrade" else ""
	var words := state_words(n)
	var red := false
	if st == "open" and warn != "":
		words = warn if words == "" else words + " " + warn
		red = true
	var line := W.serif_text(words, 25, R.SHORT_INK if red else R.SECONDARY, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 30.0, true, false)
	line.name = "DockState"
	line.max_lines = 3
	_dock.add_child(line)
	line.position = Vector2(x0, 122.0)
	line.size = Vector2(room, 92.0)
	if st == "open":
		var cost := Trail.price(selected)
		var cur := Trail.currency()
		var short := maxi(cost - Currency.balance(cur), 0)
		var b := WButton.price(cost, Loc.t("ui.trail.buy"), WButton.GREEN, 36, short, cur, false, 100.0)
		b.name = "Buy"
		b.position = Vector2(x1, 44.0)
		b.size = Vector2(right_w, b.get_combined_minimum_size().y)
		b.pressed.connect(press_buy)
		_dock.add_child(b)
		_tutor_buy(b)
		if short > 0:
			var sh := W.short_text(short, 24)
			sh.align = HORIZONTAL_ALIGNMENT_CENTER
			sh.position = Vector2(x1, 44.0 + b.size.y + 10.0)
			sh.size = Vector2(right_w, 30.0)
			_dock.add_child(sh)
		return
	var tag: Array = [{"glyph": "lock", "px": 26, "color": R.MUTED}, [Loc.t("ui.trail.tag.locked"), R.MUTED, "bold"]]
	if st == "bought":
		tag = [[Loc.t("ui.trail.tag.yours"), TICK.lightened(0.25), "bold"]]
	elif st == "closed":
		tag = [[Loc.t("ui.trail.tag.closed"), R.SHORT_INK, "bold"]]
	var pill := W.pill(tag, 30, 64.0)
	pill.name = "DockTag"
	_dock.add_child(pill)
	var ps := pill.get_combined_minimum_size()
	pill.position = Vector2(x1 + (right_w - ps.x) * 0.5, (usable - ps.y) * 0.5 + 4.0)
	pill.size = ps


static func _fit(t: WText, max_w: float, min_px: int) -> void:
	while t.font_size > min_px and t.text_width() > max_w:
		t.font_size -= 1


# ---------------------------------------------------------------- the canvas: backdrop, line, rails, marks

## The backdrop's colour at height `u` in levels (0 = the foot of level 1): the section's bottom colour rising to its
## top, blending into the next section's over the three levels before it.
func _colour_at(u: float) -> Color:
	var secs := Trail.sections()
	if secs.is_empty():
		return R.SLATE_MID
	var n := float(maxi(Trail.levels(), 1))
	var k := 0
	for i in secs.size():
		if float(int((secs[i] as Dictionary)["from"]) - 1) <= u:
			k = i
	var s: Dictionary = secs[k]
	var a := float(int(s["from"]) - 1)
	var b := float(int((secs[k + 1] as Dictionary)["from"]) - 1) if k + 1 < secs.size() else maxf(n, a + 1.0)
	var c := _hex(s, "bottom").lerp(_hex(s, "top"), clampf((u - a) / maxf(b - a, 1.0), 0.0, 1.0))
	if k + 1 < secs.size() and u > b - 3.0:
		c = c.lerp(_hex(secs[k + 1], "bottom"), smoothstep(0.0, 1.0, (u - (b - 3.0)) / 3.0))
	return c


static func _hex(s: Dictionary, key: String) -> Color:
	var h := str(s.get(key, ""))
	return Color(h) if h.is_valid_html_color() else R.SLATE_MID


func _motif(name: String) -> Texture2D:
	if not _motifs.has(name):
		var p := MOTIF_ART % name
		_motifs[name] = load(p) if name != "" and name != "none" and ResourceLoader.exists(p) else null
	return _motifs[name]


func _draw_canvas() -> void:
	var t0 := Time.get_ticks_usec()
	var c := _canvas
	var w := c.size.x
	var vh := c.size.y
	var sv := float(scroll.scroll_vertical)
	var n := Trail.levels()
	if n <= 0:
		c.draw_rect(Rect2(0, 0, w, vh), R.SLATE_BOTTOM)
		_plate(Vector2(w * 0.5, vh * 0.4), Trail.end_text() if Trail.end_text() != "" else Loc.t("ui.trail.to_be_continued"), 34, true)
		return
	var lo := _level_at(sv + vh)
	var hi := _level_at(sv)
	# the backdrop: a band a row, its colours the section's at the row's foot and top; the room over and under the track
	var top_y := _row_y(n) - ROW * 0.5 - sv
	if top_y > 0.0:
		c.draw_rect(Rect2(0, 0, w, top_y + 1.0), _colour_at(float(n)))
	var foot_y := _row_y(1) + ROW * 0.5 - sv
	if foot_y < vh:
		c.draw_rect(Rect2(0, foot_y - 1.0, w, vh - foot_y + 1.0), _colour_at(0.0))
	for l in range(lo, hi + 1):
		var y1 := _row_y(l) + ROW * 0.5 - sv
		var ca := _colour_at(float(l))
		var cb := _colour_at(float(l - 1))
		c.draw_polygon(PackedVector2Array([Vector2(0, y1 - ROW), Vector2(w, y1 - ROW), Vector2(w, y1), Vector2(0, y1)]),
			PackedColorArray([ca, ca, cb, cb]))
	# the section's sign, tiled and tilted, every other row moved half a step
	var k0 := int(floor(sv / MOTIF_STEP)) - 1
	var k1 := int(floor((sv + vh) / MOTIF_STEP)) + 1
	for k in range(k0, k1 + 1):
		var ty := float(k) * MOTIF_STEP + MOTIF_STEP * 0.5
		var tex := _motif(str(Trail.section_at(_level_at(ty)).get("motif", "none")))
		if tex == null:
			continue
		var off := MOTIF_STEP * 0.5 if posmod(k, 2) == 1 else 0.0
		for j in range(-1, int(w / MOTIF_STEP) + 2):
			c.draw_set_transform(Vector2(float(j) * MOTIF_STEP + off + 40.0, ty - sv), -0.26, Vector2.ONE)
			c.draw_texture_rect(tex, Rect2(-MOTIF_PX * 0.5, -MOTIF_PX * 0.5, MOTIF_PX, MOTIF_PX), false, MOTIF_INK)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the dark band above the line, and its crisp edge
	var ly := _line_y() - sv + _line_shift
	var dark := _line_y() > -INF and ly > 0.0
	if dark:
		c.draw_rect(Rect2(0, 0, w, minf(ly, vh)), BAND)
		c.draw_rect(Rect2(0, ly - 6.0, w, 6.0), R.NAVY)
		c.draw_rect(Rect2(0, ly, w, 3.0), Color(1, 1, 1, 0.3))
	# section plates (over the band: a signpost for what lies ahead): a hairline where a section begins, its name on a
	# plate at the right
	for s: Dictionary in Trail.sections():
		var from := int(s["from"])
		if from < lo - 1 or from > hi + 1 or str(s.get("name", "")) == "":
			continue
		var by := _row_y(from) + ROW * 0.5 - sv
		c.draw_rect(Rect2(w * 0.12, by - 1.0, w * 0.88, 2.0), Color(1, 1, 1, 0.16))
		_plate(Vector2(w - 150.0, by), str(s["name"]), 22, false)
	# rails: every outline first, then the dark ones, then the lit ones, so a shared run reads as one
	var edge: Array = []
	var dim: Array = []
	var lit: Array = []
	for l in range(maxi(lo - 1, 1), mini(hi + 1, n) + 1):
		for e: Dictionary in _lay_level(l):
			var id := str(e["id"])
			var me := _spot(id)
			var mine := Trail.state(id)
			for link: Array in _links(id):
				var pid := str(link[0])
				var from_at := _spot(pid)
				var rw := RAIL_THIN if bool(link[1]) else RAIL
				var on := mine == "bought" and Trail.state(pid) == "bought"
				var col := RAIL_LIT if on else (RAIL_CLOSED if mine == "closed" else RAIL_DARK)
				var a := Vector2(from_at.x, from_at.y - sv)
				var b := Vector2(me.x, me.y - sv)
				var runs: Array = []
				if absf(a.y - b.y) < 1.0 or absf(a.x - b.x) < 1.0:
					runs.append(_run(a, b, rw))
				else:
					var mid := b.y + ROW * 0.5
					runs.append(_run(a, Vector2(a.x, mid), rw))
					runs.append(_run(Vector2(a.x, mid), Vector2(b.x, mid), rw))
					runs.append(_run(Vector2(b.x, mid), b, rw))
				for r: Rect2 in runs:
					edge.append(r.grow(4.0))
					(lit if on else dim).append([r, col])
	for r: Rect2 in edge:
		c.draw_rect(r, R.NAVY)
	for pair: Array in dim:
		c.draw_rect(pair[0], pair[1])
	for pair: Array in lit:
		var r: Rect2 = pair[0]
		c.draw_rect(r, pair[1])
		if r.size.x < r.size.y:
			c.draw_rect(Rect2(r.position.x + 3.0, r.position.y, maxf(r.size.x * 0.24, 3.0), r.size.y), RAIL_LIT_HI)
		else:
			c.draw_rect(Rect2(r.position.x, r.position.y + 3.0, r.size.x, maxf(r.size.y * 0.24, 3.0)), RAIL_LIT_HI)
	# choice groups: a bar through the members, an OR between each pair (a padlock once one is taken)
	for l in range(lo, hi + 1):
		var groups := {}
		for e: Dictionary in _lay_level(l):
			var nd := Trail.node(str(e["id"]))
			if str(nd["kind"]) == "choice":
				var key := str(nd["group"])
				if not groups.has(key):
					groups[key] = []
				(groups[key] as Array).append(e)
		for key: String in groups.keys():
			var mem: Array = groups[key]
			if mem.size() < 2:
				continue
			mem.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["x"]) < float(q["x"]))
			var taken := false
			for e: Dictionary in mem:
				if Trail.state(str(e["id"])) == "bought":
					taken = true
			var y := _row_y(l) - sv
			var xa := float(mem[0]["x"]) * w
			var xb := float(mem[mem.size() - 1]["x"]) * w
			c.draw_rect(Rect2(xa, y - 8.0, xb - xa, 16.0), R.NAVY)
			c.draw_rect(Rect2(xa, y - 4.0, xb - xa, 8.0), RAIL_DARK if taken else R.CREAM)
			for i in range(mem.size() - 1):
				var gap_a := float(mem[i]["x"]) * w + float(mem[i]["side"]) * 0.5
				var gap_b := float(mem[i + 1]["x"]) * w - float(mem[i + 1]["side"]) * 0.5
				_or_mark(Vector2((gap_a + gap_b) * 0.5, y), taken, minf(gap_b - gap_a - 18.0, 62.0))
	# every level's number in a diamond at the left
	var tl := Trail.level()
	for l in range(lo, hi + 1):
		var left_edge := w
		var left_side := TILE
		for e: Dictionary in _lay_level(l):
			var edge_x := float(e["x"]) * w - float(e["side"]) * 0.5
			if edge_x < left_edge:
				left_edge = edge_x
				left_side = float(e["side"])
		if left_edge < w * DIAMOND_X + DIAMOND + 16.0:
			_diamond(Vector2(w * DIAMOND_X, _row_y(l) - sv - left_side * 0.5 - DIAMOND_SMALL - 8.0), l, tl, DIAMOND_SMALL)
		else:
			_diamond(Vector2(w * DIAMOND_X, _row_y(l) - sv), l, tl, DIAMOND)
	# the padlock on the line, and the end plate over the last level
	if dark and ly < vh + 30.0:
		var lc := Vector2(w * 0.875, ly - 1.0)
		c.draw_circle(lc, 27.0, R.NAVY, true, -1.0, true)
		c.draw_circle(lc, 22.0, R.DOCK_BADGE_FILL, true, -1.0, true)
		W.draw_glyph(c, "lock", Rect2(lc - Vector2(10.0, 13.0), Vector2(20.0, 25.0)), R.GOLD_TEXT, R.DOCK_BADGE_FILL)
	if top_y > -80.0:
		_plate(Vector2(w * 0.5, top_y - 130.0), Trail.end_text() if Trail.end_text() != "" else Loc.t("ui.trail.to_be_continued"), 34, true)
	bench_usec += Time.get_ticks_usec() - t0


## One straight run of a rail between two points on one axis, `rw` wide, its ends squared off half a width past them.
static func _run(a: Vector2, b: Vector2, rw: float) -> Rect2:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(lo - Vector2(rw, rw) * 0.5, hi - lo + Vector2(rw, rw))


func _or_mark(at: Vector2, taken: bool, w: float) -> void:
	var c := _canvas
	var h := 36.0
	var r := Rect2(at - Vector2(w, h) * 0.5, Vector2(w, h))
	c.draw_style_box(box(R.NAVY, 10), r.grow(4.0))
	c.draw_style_box(box(R.DOCK_BADGE_FILL if taken else R.TAG_GOLD, 8), r)
	if taken:
		W.draw_glyph(c, "lock", Rect2(at - Vector2(9.0, 12.0), Vector2(18.0, 23.0)), R.MUTED, R.DOCK_BADGE_FILL)
		return
	var f := R.body(R.BOLD_WEIGHT)
	var px := 22
	c.draw_string(f, Vector2(r.position.x, at.y - px * 0.62 + f.get_ascent(px)), Loc.t("ui.trail.or"), HORIZONTAL_ALIGNMENT_CENTER, w, px, R.NAVY)


func _diamond(at: Vector2, l: int, tl: int, d: float) -> void:
	var c := _canvas
	var fill := Color("5fc43a") if l <= tl else (R.TAG_GOLD if l == tl + 1 else Color("3a4661"))
	for step: Array in [[d + 6.0, R.NAVY], [d, fill]]:
		var k: float = step[0]
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -k), at + Vector2(k, 0), at + Vector2(0, k), at + Vector2(-k, 0)]), step[1])
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(-d, 0)]), Color(1, 1, 1, 0.14))
	var f := R.body(R.BOLD_WEIGHT)
	var px := int(round((30.0 if l < 100 else 24.0) * d / DIAMOND))
	var pos := Vector2(at.x - d, at.y - px * 0.62 + f.get_ascent(px))
	var ink := R.NAVY if l == tl + 1 else R.WHITE
	if l != tl + 1:
		c.draw_string_outline(f, pos, str(l), HORIZONTAL_ALIGNMENT_CENTER, d * 2.0, px, 6, R.NAVY)
	c.draw_string(f, pos, str(l), HORIZONTAL_ALIGNMENT_CENTER, d * 2.0, px, ink)


## A navy plate with words in it, centred on `at` (the end plate in the display face, a section's name in capitals).
func _plate(at: Vector2, words: String, px: int, big: bool) -> void:
	var c := _canvas
	var f: Font = R.display() if big else R.body(R.LABEL_WEIGHT)
	var t := words.to_upper()
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var pad := Vector2(40.0, 22.0) if big else Vector2(18.0, 10.0)
	var r := Rect2(at - Vector2(tw * 0.5 + pad.x, px * 0.5 + pad.y), Vector2(tw + pad.x * 2.0, float(px) + pad.y * 2.0))
	c.draw_style_box(box(R.NAVY, 12 if big else 8), r.grow(4.0))
	c.draw_style_box(box(R.SLATE_MID if big else R.DOCK_BADGE_FILL, 10 if big else 6), r)
	c.draw_string(f, Vector2(r.position.x, at.y - px * 0.62 + f.get_ascent(px)), t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, px,
		R.CREAM if big else R.SECONDARY)


# ---------------------------------------------------------------- shared pieces

## A flat rounded box in `col` (one a colour and radius, kept); `top_only` rounds only its top corners.
static func box(col: Color, radius: int, top_only: bool = false) -> StyleBoxFlat:
	var key := "%s|%d|%d" % [col.to_html(), radius, int(top_only)]
	if _boxes.has(key):
		return _boxes[key]
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.anti_aliasing = true
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = 0 if top_only else radius
	s.corner_radius_bottom_right = 0 if top_only else radius
	_boxes[key] = s
	return s


## A rounded outline `width` thick in `col` (no middle).
static func ring_box(col: Color, radius: int, width: int) -> StyleBoxFlat:
	var key := "ring|%s|%d|%d" % [col.to_html(), radius, width]
	if _boxes.has(key):
		return _boxes[key]
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = col
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	_boxes[key] = s
	return s


## The grey a locked or closed tile's picture is drawn in.
static func grey(bright: float, alpha: float) -> ShaderMaterial:
	var key := "%.2f|%.2f" % [bright, alpha]
	if not _mats.has(key):
		var sh := Shader.new()
		sh.code = GREY_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("bright", bright)
		m.set_shader_parameter("alpha", alpha)
		_mats[key] = m
	return _mats[key]


## A "Reach Trail Level N" line with a gold chevron (docs/trail_schema.md rule 7), for any screen that shows what a
## locked outlaw, skin, item or stage needs: a tap opens the Trail on that thing's node and Back there returns here
## (Nav.to_trail). Null when no node gives `type` `id`. Named "TrailLine", metas "type" and "id"; the look of the
## Collection's "Comes with <name>" line (pass 128).
static func requirement_line(type: String, id: String, px: int, soft: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> WTap:
	var words := Trail.requirement_text(type, id)
	if words == "":
		return null
	var t := WTap.new()
	t.name = "TrailLine"
	t.set_meta("type", type)
	t.set_meta("id", id)
	t.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	t.add_child(row)
	var wt := W.serif_text(words, px, W.INK_SOFT if soft else W.INK, 400, false, align, px * 1.3, align == HORIZONTAL_ALIGNMENT_LEFT)
	wt.name = "Words"
	if not soft:
		wt.color = R.WHITE
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		wt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wt)
	var mark := W.text("›" if R.body().has_char(0x203A) else ">", R.body(R.LABEL_WEIGHT), px + 6, R.GOLD_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	mark.name = "Chevron"
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	# pass 137 (lane TUTOR): refused while the Trail is closed (no run counted yet)
	t.pressed.connect(func() -> void:
		if not Nav.to_trail(type, id):
			W.sfx("ui_locked"))
	return t


# ---------------------------------------------------------------- BUY's highlight (pass 137, lane TUTOR)

const WHighlightScript := preload("res://ui/wanted/WHighlight.gd")
## The highlight on BUY while Save's tutorial step buy_tapped is open (WHighlight; null when off).
var buy_highlight: Control


## Garry: "On the Trail screen the Buy button is highlighted the same way until the first tap." BUY wears the Results'
## highlight whenever the dock shows one (the node chosen is open), also when the purse is short (its price in red and the
## "N short" line under it say what it needs); the first tap the purse can pay (press_buy) ends it for good, a short tap
## (ui_locked) leaves it on. `b` null hides it until the next BUY.
func _tutor_buy(b: Control) -> void:
	var on := buy_highlight != null and is_instance_valid(buy_highlight)
	if Save.tutorial_done("buy_tapped"):
		if on:
			buy_highlight.call("stop")
		buy_highlight = null
		return
	if b == null:
		if on:
			buy_highlight.call("retarget", null)
		return
	if on:
		buy_highlight.call("retarget", b)
	else:
		buy_highlight = WHighlightScript.attach(b, self)


func _buy_tapped() -> void:
	if not Save.tutorial_done("buy_tapped"):
		Save.mark_tutorial("buy_tapped")
	_tutor_buy(null)


## Whether BUY is highlighted now (tests, tools).
func buy_highlighted() -> bool:
	return buy_highlight != null and is_instance_valid(buy_highlight) and bool(buy_highlight.call("is_on"))


# ---------------------------------------------------------------- a node's tile

## One node on the track (and, inert, in the dock): the frame by its state, the picture, the tick, the strike, the
## price under an open one, the name under a named one, the ring while it is chosen.
class Tile extends WTap:
	const BASE := 8.0
	var id := ""
	var side := 148.0
	var state := "locked"
	var optional := false
	var named := ""
	var chosen := false
	var ring := false
	var price := -1
	var short := false
	## A wide picture (a stage's) fills the face; an icon keeps its room.
	var picture := false
	var inert := false
	var _pulse := 0.0
	var _face: Control
	var _pad: MarginContainer
	var _icon: TextureRect
	var _over: Control

	func _init() -> void:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_face = Control.new()
		_face.name = "Face"
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.draw.connect(_draw_face)
		add_child(_face)
		_pad = MarginContainer.new()
		_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_pad)
		_icon = TextureRect.new()
		_icon.name = "Art"
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pad.add_child(_icon)
		_over = Control.new()
		_over.name = "Over"
		_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_over.draw.connect(_draw_over)
		add_child(_over)

	func _ready() -> void:
		super._ready()
		if inert:
			mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_art(tex: Texture2D) -> void:
		_icon.texture = tex

	func set_pulse(p: float) -> void:
		_pulse = p
		_face.queue_redraw()
		if ring:
			_over.queue_redraw()

	## The tile again after its fields changed.
	func refresh() -> void:
		var m := int(round(side * (0.13 if picture else 0.17)))
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			_pad.add_theme_constant_override(k, m)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if picture else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.material = null
		if state == "locked":
			_icon.material = TrailScreen.grey(0.62, 0.9)
		elif state == "closed":
			_icon.material = TrailScreen.grey(0.42, 0.6)
		_face.queue_redraw()
		_over.queue_redraw()

	func _draw_face() -> void:
		var f := _face
		var s := side
		var r := Rect2(Vector2.ZERO, Vector2(s, s))
		var look: Array = TrailScreen.LOOK.get(state, TrailScreen.LOOK["locked"])
		var rim: Color = look[0]
		var rad := int(round(s * 0.16))
		var rim_w := 6.0 if optional else 8.0
		if state == "open":
			# the next to buy: a gold rim that breathes, a soft glow round it
			var q := snappedf(_pulse, 0.125)
			rim = Color("f5b82a").lerp(Color("fff0b0"), q)
			f.draw_style_box(TrailScreen.box(Color(1.0, 0.82, 0.3, 0.16 + 0.2 * q), rad + 12), r.grow(9.0 + 5.0 * q))
		if named != "":
			# a milestone: a second frame outside the first
			f.draw_style_box(TrailScreen.box(R.NAVY, rad + 10), r.grow(13.0))
			f.draw_style_box(TrailScreen.box(rim.darkened(0.25) if state != "open" else Color("c98a14"), rad + 7), r.grow(9.0))
		f.draw_style_box(TrailScreen.box(R.NAVY, rad), Rect2(0.0, BASE, s, s))
		f.draw_style_box(TrailScreen.box(R.NAVY, rad), r)
		f.draw_style_box(TrailScreen.box(rim, rad - 3), r.grow(-4.0))
		f.draw_style_box(TrailScreen.box(R.NAVY, rad - 7), r.grow(-(4.0 + rim_w)))
		var inner := r.grow(-(7.0 + rim_w))
		f.draw_style_box(TrailScreen.box(look[2], rad - 9), inner)
		f.draw_style_box(TrailScreen.box(look[1], rad - 9, true), Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.46)))
		f.draw_rect(Rect2(inner.position + Vector2(rad * 0.5, 2.0), Vector2(inner.size.x - rad, 3.0)), Color(1, 1, 1, 0.2 if state == "bought" else 0.1))

	func _draw_over() -> void:
		var o := _over
		var s := side
		var r := Rect2(Vector2.ZERO, Vector2(s, s))
		var rad := int(round(s * 0.16))
		if state == "closed":
			# the road not taken: struck through
			var a := Vector2(s * 0.14, s * 0.86)
			var b := Vector2(s * 0.86, s * 0.14)
			o.draw_line(a, b, R.NAVY, 16.0, true)
			o.draw_line(a, b, TrailScreen.STRIKE, 8.0, true)
		elif state == "bought":
			var c := Vector2(s - 12.0, 12.0)
			o.draw_circle(c, 21.0, R.NAVY, true, -1.0, true)
			o.draw_circle(c, 17.0, TrailScreen.TICK, true, -1.0, true)
			o.draw_polyline(PackedVector2Array([c + Vector2(-8.0, 0.0), c + Vector2(-2.0, 6.5), c + Vector2(8.5, -6.0)]), Color.WHITE, 4.5, true)
		var y := s + BASE + 8.0
		if named != "":
			y = _label(named.to_upper(), y, 20, R.NAVY, R.CREAM) + 6.0
		if price >= 0:
			_price(y)
		if chosen:
			o.draw_style_box(TrailScreen.ring_box(R.NAVY, rad + 14, 12), r.grow(17.0))
			o.draw_style_box(TrailScreen.ring_box(R.CREAM, rad + 12, 6), r.grow(14.0))
		if ring:
			var k := 0.55 + 0.45 * _pulse
			o.draw_style_box(TrailScreen.ring_box(Color(1.0, 0.86, 0.45, k), rad + 22, 7), r.grow(24.0 + 4.0 * _pulse))

	## A small plate of words under the tile at `y`; returns its foot.
	func _label(words: String, y: float, px: int, ink: Color, fill: Color) -> float:
		var f := R.body(R.LABEL_WEIGHT)
		var tw := f.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var w := tw + 24.0
		var h := float(px) + 12.0
		var r := Rect2((side - w) * 0.5, y, w, h)
		_over.draw_style_box(TrailScreen.box(R.NAVY, 8), r.grow(3.0))
		_over.draw_style_box(TrailScreen.box(fill, 6), r)
		_over.draw_string(f, Vector2(r.position.x, y + 6.0 + f.get_ascent(px) - px * 0.12), words, HORIZONTAL_ALIGNMENT_CENTER, w, px, ink)
		return y + h

	## The price under an open tile: the coin and the amount on a dark plate; the amount red on grey when short.
	func _price(y: float) -> void:
		var f := R.body(R.BOLD_WEIGHT)
		var px := 26
		var words := W.num(price)
		var tw := f.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var coin := 28.0
		var w := tw + coin + 34.0
		var h := 40.0
		var r := Rect2((side - w) * 0.5, y, w, h)
		_over.draw_style_box(TrailScreen.box(R.NAVY, 10), r.grow(3.0))
		_over.draw_style_box(TrailScreen.box(Color("454e66") if short else Color("141a2e"), 8), r)
		var tex := WCoin.art_of(Trail.currency())
		if tex:
			_over.draw_texture_rect(tex, Rect2(r.position + Vector2(10.0, (h - coin) * 0.5), Vector2(coin, coin)), false,
				Color(0.7, 0.7, 0.74) if short else Color.WHITE)
		_over.draw_string(f, Vector2(r.position.x + coin + 18.0, y + (h - px) * 0.5 + f.get_ascent(px) - px * 0.14), words,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, R.SHORT_INK if short else R.WHITE)
