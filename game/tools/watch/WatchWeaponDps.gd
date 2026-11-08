## The Watch's "Weapon DPS" tab (pass 117, lane WATCHDPS; Garry: "Add Individual Weapon Real DPS to the local Dashboard,
## and make a version of that for the Watch tool. For this hero, what items he had and their real DPS. For each item that
## was affected by other items we list those as icons as well (with a highlight hint to show what they did). I expect
## this real DPS to be a graph over time just like everything else, where new items that affect the DPS, power-ups, War
## Drums and upgrades are all displayed."). The dashboard's card "Each weapon's real DPS" (analytics/dashboard.html
## renderWeaponDps) live, as the run plays, in three parts:
## - a chart (a WatchChart child): one line a weapon family (a mutation and an evolution count as their weapon) of the
##   damage it really dealt, a rolling mean over WINDOWS[i] seconds (5, 10 or 30; the panel's chips), each weapon in the
##   colour the damage share chart gives it; the other damage sources (Powder Keg, blasts...) dashed, the small ones
##   folded into one grey dashed "other sources";
## - under it a strip of icons at their seconds, a row a kind (dps_marks): weapons (taken, levelled, a mutation, an
##   evolution), items (the cards, passive items and perks that changed a weapon's numbers, Totem gifts of a weapon stat,
##   the Stranger's deals), boosts (power-ups, the War Drum); a row's icons in up to LANES lanes so they do not cover
##   each other;
## - each line's row: its colour, the weapon's icon, name (an evolved one "Revolver → Golden Revolver"), level and
##   mutations, the damage it dealt and its share, its DPS since its first hit and its peak, and "shaped by": the icons of
##   every item, Trail upgrade, perk, gift and hero trait that changes its numbers now (RunAnalytics.weapon_sources_of).
## The pointer on an icon gives a hint (what it was, when, what it did) and lights its time(s) on the chart; a click on a
## row's name hides or shows its line; the wheel over the rows scrolls them. The panel hands the model (WatchPanel
## _refresh_wdps); the folding and the marks are pure (tested: tests/pass117_WATCHDPS_test.gd). Tools only.
extends Control

const DATA := preload("res://tools/watch/WatchData.gd")
const CHART := preload("res://tools/watch/WatchChart.gd")

const BG := Color(0.105, 0.115, 0.14)
const EDGE := Color(0.22, 0.24, 0.29)
const GRID := Color(1, 1, 1, 0.06)
const TEXT := Color(0.62, 0.66, 0.74)
const TITLE := Color(0.86, 0.89, 0.94)
const ACCENT := Color(0.93, 0.66, 0.26)
const PURPLE := Color(0.72, 0.55, 0.96)
const BLUE := Color(0.43, 0.71, 1.0)
const GOOD := Color(0.47, 0.83, 0.5)
const PINK := Color(0.95, 0.55, 0.8)
const GOLD := Color(0.98, 0.85, 0.35)
const BAD := Color(0.95, 0.42, 0.36)
const GREYLINE := Color(0.5, 0.52, 0.58)
const HILITE := Color(1, 1, 1, 0.07)
const HOVER_BOX := Color(0.06, 0.065, 0.08, 0.95)
const HOVER_EDGE := Color(0.35, 0.38, 0.45)
## the time an icon lights on the chart
const LIGHT := Color(1, 1, 1, 0.8)
const FONT_SIZE := 12
## the rolling mean's choices (the dashboard's DPS_WINDOWS), seconds
const WINDOWS := [5, 10, 30]
## a source that is no weapon gets its own (dashed) line from this share of all the damage; below, "other sources"
const OTHER_MIN := 0.02
## the strip: an icon's size, the lanes a row may use, the gap between lanes; the rows in order [key, word]
const ICON := 16.0
const LANES := 2
const STRIP_ROWS := [["weapons", "weapons"], ["items", "items"], ["boosts", "boosts"]]
## a weapon's row and its icons
const ROW_H := 28.0
const ROW_ICON := 20.0
const SRC_ICON := 18.0
## the hero's stats every weapon folds in or its hits read (RunAnalytics.WEAPON_FEED): a Totem gift of one shaped them
const FEED := ["might", "cooldown", "haste", "area", "projectile_speed", "duration", "amount", "crit_chance",
	"crit_damage", "elite_damage", "ricochet", "overkill", "execute_frac", "debuff_duration"]
## how an item came (the recorder's `via`; the dashboard's VIA_WORDS)
const VIA_WORDS := {"starter": "the starting weapon", "card": "a level-up card", "path": "a mutation level-up", "chest": "a chest",
	"boss_chest": "the boss chest", "stranger": "the Stranger", "shop": "bought at the shop", "debug": "the debug hand"}
## a source's kind in words (the dashboard's SRC_KIND_WORDS; "buff" live: a boost running now)
const SRC_KIND_WORDS := {"passive": "passive item or card", "favourite": "the outlaw's favourite", "perk": "perk", "mutation": "mutation",
	"trail": "the Trail", "trait": "the outlaw's trait", "hero": "the outlaw", "momentum": "the outlaw's momentum", "totem": "Totem gift",
	"stranger": "the Stranger", "buff": "a boost running now", "weapon": "a weapon", "bonus": "the outlaw's favourite"}

## the model the panel hands over (set_model): {t: PackedFloat32Array, keys: [line key], raw: {key: PackedFloat32Array},
## total: float, info: {key: {name, sub, color, weapon, icon, sources: [{icon, name, lines, times}], note}}, marks:
## dps_marks' list each with its `icon`, x0, x1, base_marks (the falls, the takeovers: the other charts' marks)}
var model: Dictionary = {}
var window_s := 10
## the lines hidden by a click on their row
var hidden_lines: Dictionary = {}
var scroll := 0
var hover := Vector2(-1, -1)
var draw_us := 0
var chart
var _overlay: Control
## each line's rolling mean (the window's) and its peak
var _rolled: Dictionary = {}
## the places drawn: [[Rect2, what ("mark" | "src" | "row"), payload]]
var _spots: Array = []
## the hovered spot's payload's key (the chart's light follows it)
var _lit_key := ""


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	chart = CHART.new()
	chart.title = "Each weapon's real DPS"
	add_child(chart)
	# the hints over everything (the chart included): drawn on a child above it
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	resized.connect(_place)
	_place()


## The chart's height for the view's height now: about 38% of it, at least 110 px, at most 230 (the rows want the rest).
func chart_h() -> float:
	return clampf(size.y * 0.38, 110.0, 230.0)


func _place() -> void:
	if chart == null:
		return
	chart.position = Vector2.ZERO
	chart.size = Vector2(size.x, chart_h())
	_overlay.position = Vector2.ZERO
	_overlay.size = size


## The panel's model (see `model`), then the chart drawn again from it.
func set_model(m: Dictionary) -> void:
	model = m
	_rebuild()


## A window chip: the rolling mean over `secs` seconds.
func set_window(secs: int) -> void:
	window_s = secs
	_rebuild()


## The rolling means, the chart's lines, axes and legend from the model.
func _rebuild() -> void:
	_rolled = {}
	if chart == null:
		return
	var ts: PackedFloat32Array = model.get("t", PackedFloat32Array())
	var x0 := float(model.get("x0", 0.0))
	var x1 := float(model.get("x1", 180.0))
	chart.x0 = x0
	chart.x1 = x1
	chart.series = []
	chart.legend = []
	var top := 0.0
	var info: Dictionary = model.get("info", {})
	for k in model.get("keys", []):
		var raw: PackedFloat32Array = (model["raw"] as Dictionary)[k]
		var r := roll(raw, window_s)
		var peak := 0.0
		for v in r:
			peak = maxf(peak, v)
		_rolled[k] = {"roll": r, "peak": peak}
		if hidden_lines.has(k):
			continue
		var inf: Dictionary = info.get(k, {})
		var pts: PackedVector2Array = DATA.bucket(ts, r, x0, x1, 360)
		var weapon := bool(inf.get("weapon", false))
		var col: Color = inf.get("color", GREYLINE)
		chart.series.append({"pts": pts, "name": str(inf.get("name", k)), "color": col, "width": 2.0 if weapon else 1.4,
			"axis": 0, "dashed": not weapon})
		for p in pts:
			top = maxf(top, p.y)
		if weapon:
			chart.legend.append([str(inf.get("name", k)), col])
	# (the weapons' lines on top: the other sources first)
	chart.series.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a["dashed"]) and not bool(b["dashed"]))
	chart.axes = [{"max": DATA.nice_max(top), "fmt": "k", "unit": ""}, {"max": 0.0}, {"max": 0.0}]
	chart.title = "Each weapon's real DPS (%d s mean)" % window_s
	chart.note = "" if not ts.is_empty() else "no rows yet"
	_light(_lit_key, true)
	queue_redraw()


# ---------------------------------------------------------------- pure helpers (tested)

## An id's family: its base weapon, following `fam` ({id: the weapon it evolved from}) up to five steps.
static func family_of(id: String, fam: Dictionary) -> String:
	var f := id
	var k := 0
	while fam.has(f) and str(fam[f]) != f and str(fam[f]) != "" and k < 5:
		f = str(fam[f])
		k += 1
	return f


## The rolling mean of `a` over `w` values (fewer at the start; the dashboard's roll).
static func roll(a: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	var acc := 0.0
	var ww := maxi(w, 1)
	for i in range(a.size()):
		acc += a[i]
		if i >= ww:
			acc -= a[i - ww]
		if absf(acc) < 0.000001:
			acc = 0.0
		out[i] = acc / float(mini(ww, i + 1))
	return out


## The lines of the chart from the rows' damage by source (`dmg_rows`: one {source: damage} a row): every weapon family
## of `weapon_ids` (in that order; an id's family by `fam`) with every source of that family summed into it, then the
## other sources: each at least `other_min` of all the damage its own line, the rest summed as "__other".
## {fams, members {family: [ids]}, own, folded, keys (fams, own, then "__other" when any), raw {key:
## PackedFloat32Array a row}, totals {key: damage}, total}.
static func fold(dmg_rows: Array, weapon_ids: Array, fam: Dictionary, other_min: float = OTHER_MIN) -> Dictionary:
	var fams: Array = []
	var members := {}
	for id in weapon_ids:
		var f := family_of(str(id), fam)
		if not members.has(f):
			members[f] = []
			fams.append(f)
		if not (members[f] as Array).has(str(id)):
			(members[f] as Array).append(str(id))
	var by_id := {}
	var total := 0.0
	for r in dmg_rows:
		if not (r is Dictionary):
			continue
		for k in r:
			by_id[str(k)] = float(by_id.get(str(k), 0.0)) + float(r[k])
			total += float(r[k])
	var others: Array = []
	for k in by_id:
		var f := family_of(str(k), fam)
		if members.has(f):
			if not (members[f] as Array).has(str(k)):
				(members[f] as Array).append(str(k))
		else:
			others.append(str(k))
	others.sort_custom(func(a: String, b: String) -> bool:
		return float(by_id[a]) > float(by_id[b]) if float(by_id[a]) != float(by_id[b]) else a < b)
	var own: Array = []
	var folded: Array = []
	for o in others:
		if total > 0.0 and float(by_id[o]) >= other_min * total:
			own.append(o)
		else:
			folded.append(o)
	var keys: Array = fams + own
	if not folded.is_empty():
		keys.append("__other")
	# which line each source's damage goes to
	var line_of := {}
	for f in fams:
		for id in members[f]:
			line_of[str(id)] = f
	for o in own:
		line_of[o] = o
	for o in folded:
		line_of[o] = "__other"
	var raw := {}
	var totals := {}
	for k in keys:
		# (a line's array filled whole, then kept: a packed array put back in a dictionary each row would be copied)
		var a := PackedFloat32Array()
		a.resize(dmg_rows.size())
		var sum := 0.0
		for i in range(dmg_rows.size()):
			var r = dmg_rows[i]
			if not (r is Dictionary):
				continue
			var v := 0.0
			for id in r:
				if str(line_of.get(str(id), "")) == str(k):
					v += float(r[id])
			a[i] = v
			sum += v
		raw[k] = a
		totals[k] = sum
	return {"fams": fams, "members": members, "own": own, "folded": folded, "keys": keys, "raw": raw, "totals": totals, "total": total}


## {source id: [{weapon, w, n, k, i}]}: which weapon each source shapes and how, from {weapon id: weapon_sources_of}.
static func sources_by_sid(ws: Dictionary) -> Dictionary:
	var out := {}
	for wid in ws:
		for x in ws[wid]:
			if not (x is Dictionary) or str(x.get("s", "")) == "":
				continue
			var sid := str(x["s"])
			if not out.has(sid):
				out[sid] = []
			(out[sid] as Array).append({"weapon": str(wid), "w": str(x.get("w", "")), "n": str(x.get("n", "")), "k": str(x.get("k", "")),
				"i": str(x.get("i", ""))})
	return out


## The moments a source joined or grew (its pick events, play seconds): a passive's or a card's levels, a perk, a
## mutation, a Totem gift, the Stranger's deals; [] for what was there from the start (the board, the hero, his trait).
static func source_times(events: Array, sid: String) -> Array:
	var i := sid.find(":")
	var kind := sid.substr(0, i) if i > 0 else sid
	var id := sid.substr(i + 1).split(":")[0] if i > 0 else ""
	var kinds: Array = {"passive": ["passive", "passive_evolution", "line", "line_evolution"], "favourite": ["passive"], "perk": ["perk"],
		"mutation": ["mutation"], "totem": ["totem"], "weapon": ["weapon", "evolution"]}.get(kind, [])
	var out: Array = []
	for e in events:
		if not (e is Dictionary):
			continue
		var ek := str(e.get("kind", ""))
		if kind == "stranger":
			if ek == "stranger":
				out.append(float(e.get("t", 0.0)))
		elif kinds.has(ek) and str(e.get("id", "")) == id:
			out.append(float(e.get("t", 0.0)))
	return out


## The marks under the chart, by row (the dashboard's dpsMarks): weapons (taken, a level, a mutation, an evolution),
## items (the cards, passive items and perks that change a weapon's numbers now, Totem gifts of a weapon stat, the
## Stranger's deals), boosts (every power-up but the small ones, the War Drum and any boost structure). `by_sid`:
## sources_by_sid's; `names` {id: name} (and "stat:<stat>": a stat's words). [{t, row, key, kind, label, lines}]
static func dps_marks(events: Array, by_sid: Dictionary, names: Dictionary) -> Array:
	var out: Array = []
	for e in events:
		if not (e is Dictionary):
			continue
		var kind := str(e.get("kind", ""))
		var id := str(e.get("id", ""))
		var t := float(e.get("t", 0.0))
		var at := DATA.mmss(t) + " · "
		var via := str(e.get("via", ""))
		var how := (" (%s)" % str(VIA_WORDS.get(via, via))) if via != "" else ""
		var est := ""
		if e.get("est_before") != null and e.get("est_after") != null:
			est = "the build's estimate %s → %s DPS" % [_n(float(e["est_before"])), _n(float(e["est_after"]))]
		var nm := _name(names, id)
		match kind:
			"weapon":
				var words := (" joined at level %d" % int(e.get("level", 1))) if bool(e.get("new", false)) else (" to level %s" % str(e.get("level", "?")))
				out.append(_mark(t, "weapons", id, "weapon", nm, [at + nm + words + how, est]))
			"evolution":
				out.append(_mark(t, "weapons", id, "evolution", nm, [at + "★ " + _name(names, str(e.get("from", ""))) + " evolved into " + nm + how, est]))
			"mutation":
				var on := str(e.get("weapon", ""))
				var l: Array = [at + nm + (" (outlaw mutation)" if bool(e.get("hero", false)) else " (mutation)") + ((" on " + _name(names, on)) if on != "" else "") + how, est]
				out.append(_mark(t, "weapons", id, "mutation", nm, l + _shaped(by_sid, "mutation:" + id, names)))
			"passive", "passive_evolution", "line", "line_evolution", "perk":
				var is_perk := kind == "perk"
				var sh: Array = _shaped(by_sid, ("perk:" if is_perk else "passive:") + id, names)
				if not is_perk:
					sh += _shaped(by_sid, "favourite:" + id, names)
				if sh.is_empty():
					continue
				var what := "perk" if is_perk else ("card" if bool(e.get("line", false)) or kind.begins_with("line") else "passive item")
				var lv := int(e.get("level", 0))
				out.append(_mark(t, "items", id, "perk" if is_perk else ("card" if what == "card" else "passive"), nm,
					[at + nm + ((" to level %d" % lv) if lv > 1 else "") + " (" + what + ")" + how, est] + sh))
			"totem":
				var stat := str(e.get("stat", ""))
				if not FEED.has(stat):
					continue
				var v := float(e.get("value", 0.0))
				var sname := str(names.get("stat:" + stat, stat.replace("_", " ")))
				out.append(_mark(t, "items", id, "totem", nm, [at + "Totem gift: " + nm, "%s %s%s" % [sname, "+" if v >= 0.0 else "", str(snappedf(v, 0.001))]] + _shaped(by_sid, "totem:" + id, names)))
			"stranger":
				var ty := str(e.get("type", ""))
				var lv2 := int(e.get("level", 0))
				out.append(_mark(t, "items", id, "weapon" if ty == "weapon" else ("mutation" if ty == "mutation" else "passive"), nm,
					[at + "the Stranger's deal: " + nm + ((" at level %d" % lv2) if lv2 > 0 else ""), "for %d%% of max HP" % int(roundf(100.0 * float(e.get("cost", 0.0))))]))
			"pickup":
				var s = e.get("small", false)
				var small: bool = (s is bool and s) or ((s is int or s is float) and float(s) != 0.0)
				if small:
					continue
				var eff := str(e.get("effect", ""))
				out.append(_mark(t, "boosts", id, "pickup", nm, [at + nm + " (power-up" + ((": " + eff) if eff != "" else "") + ")"]))
			"structure":
				if id == "war_drum" or str(e.get("effect", "")) == "buff":
					out.append(_mark(t, "boosts", id, "structure", nm, [at + nm + (" (the drum moment, then its boost)" if id == "war_drum" else " (a boost)")]))
	return out


static func _mark(t: float, row: String, key: String, kind: String, label: String, lines: Array) -> Dictionary:
	var l: Array = []
	for x in lines:
		if str(x) != "":
			l.append(str(x))
	return {"t": t, "row": row, "key": key, "kind": kind, "label": label, "lines": l}


## What a source does to the weapons, in lines: one when it does the same to every weapon it shapes.
static func _shaped(by_sid: Dictionary, sid: String, names: Dictionary) -> Array:
	var l: Array = by_sid.get(sid, [])
	if l.is_empty():
		return []
	var same := l.size() > 1
	for x in l:
		if str(x["w"]) != str(l[0]["w"]):
			same = false
	if same:
		return ["every weapon held now: " + str(l[0]["w"])]
	var out: Array = []
	for x in l:
		out.append(_name(names, str(x["weapon"])) + ": " + str(x["w"]))
	return out


static func _name(names: Dictionary, id: String) -> String:
	return str(names.get(id, id)) if id != "" else ""


## Lanes for icons at sorted x positions `xs` (px), `sz` wide, at most `max_lanes`: each icon takes the first lane its
## left edge clears, else a new one, else the lane that ends first (the dashboard's iconStrip). [lane a position]
static func lanes(xs: Array, sz: float, max_lanes: int) -> Array:
	var right: Array = []
	var out: Array = []
	for x in xs:
		var px := float(x)
		var lane := -1
		for j in range(right.size()):
			if px - sz * 0.5 >= float(right[j]) + 1.0:
				lane = j
				break
		if lane < 0 and right.size() < max_lanes:
			lane = right.size()
			right.append(-1.0e9)
		if lane < 0:
			lane = 0
			for j in range(right.size()):
				if float(right[j]) < float(right[lane]):
					lane = j
		right[lane] = px + sz * 0.5
		out.append(lane)
	return out


## A damage figure: 12k, 3.4k, 812.
## Pass 136 (lane BOT): the run's dry shots by weapon id (Aim.dry_counts(), loaded at run time: the class names an autoload
## and tools compile before autoloads); {} where the game keeps none.
static func dry_counts() -> Dictionary:
	if not ResourceLoader.exists("res://core/systems/Aim.gd"):
		return {}
	var aim = load("res://core/systems/Aim.gd")
	if not (aim is Script):
		return {}
	for m in (aim as Script).get_script_method_list():
		if str(m.get("name", "")) == "dry_counts":
			var d = aim.dry_counts()
			return d if d is Dictionary else {}
	return {}


static func _n(v: float) -> String:
	if v >= 100000.0:
		return "%dk" % int(roundf(v / 1000.0))
	if v >= 1000.0:
		return ("%.1fk" % (v / 1000.0)).replace(".0k", "k")
	if v >= 10.0:
		return "%d" % int(roundf(v))
	return str(snappedf(v, 0.1))


static func _pct(v: float) -> String:
	if v <= 0.0:
		return "-"
	if v < 0.01:
		return "<1%"
	return "%d%%" % int(roundf(100.0 * v))


## A mark kind's colour (the icon's rim and the hint's first line).
static func kind_colour(kind: String) -> Color:
	match kind:
		"weapon":
			return ACCENT
		"evolution":
			return GOLD
		"mutation":
			return PURPLE
		"card":
			return BLUE
		"passive":
			return Color(0.55, 0.88, 0.55)
		"perk":
			return Color(0.4, 0.85, 0.85)
		"totem":
			return PINK
		"pickup":
			return GOOD
		"structure":
			return BAD
	return TEXT


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		set_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.position.y > _rows_top():
			scroll = mini(scroll + 1, maxi((model.get("keys", []) as Array).size() - _fit_rows(), 0))
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.position.y > _rows_top():
			scroll = maxi(scroll - 1, 0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var s: Array = _spot_at(mb.position)
			if not s.is_empty() and str(s[1]) == "row":
				toggle_line(str(s[2]))
				accept_event()


## The pointer at local `p` (x < 0: gone): the hint follows, the chart lights the hovered icon's time(s).
func set_hover(p: Vector2) -> void:
	hover = p
	var s: Array = _spot_at(p) if p.x >= 0.0 else []
	var key := ""
	if not s.is_empty() and str(s[1]) != "row":
		key = "%s#%d" % [str(s[1]), _spots.find(s)]
	if key != _lit_key:
		_light(_lit_key, false)
		_lit_key = key
		_light(key, true)
	queue_redraw()
	_overlay.queue_redraw()


## Hides or shows line `k` (a click on its row's name).
func toggle_line(k: String) -> void:
	if hidden_lines.has(k):
		hidden_lines.erase(k)
	else:
		hidden_lines[k] = true
	_rebuild()


## A check's pointer: "m<k>" the k-th mark drawn, "s<k>" the k-th "shaped by" icon drawn, "r<k>" the k-th row, else
## shares of the view's size "<x>/<y>". The local point, or (-1, -1).
func point_for(spec: String) -> Vector2:
	var want: String = {"m": "mark", "s": "src", "r": "row"}.get(spec.substr(0, 1), "")
	if want != "" and spec.substr(1).is_valid_int():
		var n := int(spec.substr(1))
		for s in _spots:
			if str(s[1]) == want:
				if n == 0:
					return (s[0] as Rect2).get_center()
				n -= 1
		return Vector2(-1, -1)
	var bits := spec.split("/")
	if bits.size() == 2:
		return Vector2(float(bits[0]) * size.x, float(bits[1]) * size.y)
	return Vector2(-1, -1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover.x >= 0.0:
		set_hover(Vector2(-1, -1))


## The spot drawn under local `p` ([Rect2, what, payload]), or [] for none.
func _spot_at(p: Vector2) -> Array:
	for s in _spots:
		if (s[0] as Rect2).grow(1.0).has_point(p):
			return s
	return []


## Lights (or puts out) the time(s) of hovered spot `key` ("<what>#<index in _spots>") on the chart.
func _light(key: String, on: bool) -> void:
	if chart == null:
		return
	var base: Array = model.get("base_marks", [])
	var ms: Array = base.duplicate()
	if on and key != "":
		var i := int(key.get_slice("#", 1))
		# (a row's spot carries its line key, no times)
		if i >= 0 and i < _spots.size() and _spots[i][2] is Dictionary:
			for tt in (_spots[i][2] as Dictionary).get("times", []):
				ms.append({"x": float(tt), "color": LIGHT})
	chart.marks = ms
	chart.queue_redraw()


# ---------------------------------------------------------------- drawing

func _strip_top() -> float:
	return chart_h() + 2.0


## The strip's rows that have marks, each [key, word, lanes used]: laid as drawn (the lanes need the x scale).
func _strip_layout() -> Array:
	var out: Array = []
	var marks: Array = model.get("marks", [])
	for r in STRIP_ROWS:
		var xs: Array = []
		for m in marks:
			if str(m["row"]) == str(r[0]):
				xs.append(m)
		if xs.is_empty():
			continue
		xs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
		var px: Array = []
		for m in xs:
			px.append(chart.to_px(Vector2(float(m["t"]), 0.0), 0).x)
		var ln := lanes(px, ICON, LANES)
		var used := 1
		for l in ln:
			used = maxi(used, int(l) + 1)
		out.append([r[0], r[1], used, xs, px, ln])
	return out


func _strip_h(lay: Array) -> float:
	var h := 0.0
	for r in lay:
		h += 4.0 + float(r[2]) * (ICON + 2.0)
	return h


func _rows_top() -> float:
	return _strip_top() + _strip_h(_strip_layout()) + 4.0


func _fit_rows() -> int:
	return maxi(int(floor((size.y - _rows_top() - 16.0) / ROW_H)), 1)


func _draw() -> void:
	var us := Time.get_ticks_usec()
	_draw_all()
	draw_us += Time.get_ticks_usec() - us
	_overlay.queue_redraw()


func _draw_all() -> void:
	var font := get_theme_default_font()
	_spots = []
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2.ZERO, size), EDGE, false, 1.0)
	if model.is_empty() or (model.get("keys", []) as Array).is_empty():
		draw_string(font, Vector2(12, chart_h() + 20.0), "No damage dealt yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		return
	var plot: Rect2 = chart.plot_rect()
	# the strip: a row a kind, its icons at their seconds
	var y := _strip_top()
	for r in _strip_layout():
		var h := 4.0 + float(r[2]) * (ICON + 2.0)
		draw_rect(Rect2(plot.position.x, y, plot.size.x, h - 1.0), Color(1, 1, 1, 0.025))
		# (the row's word in the chart's left margin, small enough to fit it whole: "weapons" was cut to "weapo")
		draw_string(font, Vector2(4.0, y + 12.0), str(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 3, TEXT)
		var xs: Array = r[3]
		for k in range(xs.size()):
			var m: Dictionary = xs[k]
			var px := float(r[4][k])
			if px < plot.position.x - 1.0 or px > plot.end.x + 1.0:
				continue
			var rect := Rect2(px - ICON * 0.5, y + 2.0 + float(r[5][k]) * (ICON + 2.0), ICON, ICON)
			_icon(font, rect, m.get("icon"), str(m["label"]), kind_colour(str(m["kind"])))
			_spots.append([rect, "mark", {"lines": m["lines"], "times": [float(m["t"])], "colour": kind_colour(str(m["kind"]))}])
		y += h
	# the rows: a line each
	y = _rows_top()
	var w := size.x
	var name_x := 10.0
	var name_w := clampf(w * 0.3, 150.0, 260.0)
	var num_x := name_x + name_w + 8.0
	var num_w := clampf(w * 0.25, 140.0, 220.0)
	var src_x := num_x + num_w + 8.0
	draw_string(font, Vector2(name_x + 14.0, y + 10.0), "line · level · mutations", HORIZONTAL_ALIGNMENT_LEFT, name_w, FONT_SIZE - 2, TEXT)
	draw_string(font, Vector2(num_x, y + 10.0), "dealt · share · DPS", HORIZONTAL_ALIGNMENT_LEFT, num_w, FONT_SIZE - 2, TEXT)
	draw_string(font, Vector2(src_x, y + 10.0), "shaped by (its numbers now)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, TEXT)
	y += 13.0
	var keys: Array = model["keys"]
	var info: Dictionary = model.get("info", {})
	var total := float(model.get("total", 0.0))
	var ts: PackedFloat32Array = model.get("t", PackedFloat32Array())
	var fit := _fit_rows()
	var dry := dry_counts()
	scroll = clampi(scroll, 0, maxi(keys.size() - fit, 0))
	for idx in range(scroll, mini(scroll + fit, keys.size())):
		var k := str(keys[idx])
		var inf: Dictionary = info.get(k, {})
		var row := Rect2(4.0, y, w - 8.0, ROW_H - 2.0)
		if hover.x >= 0.0 and row.has_point(hover):
			draw_rect(row, HILITE)
		var off := hidden_lines.has(k)
		var col: Color = inf.get("color", GREYLINE)
		var dim := 0.35 if off else 1.0
		# the line's colour (dashed for a source that is no weapon), its icon, its name and words
		var sy := y + ROW_H * 0.5 - 1.0
		if bool(inf.get("weapon", false)):
			draw_line(Vector2(name_x, sy), Vector2(name_x + 10.0, sy), Color(col, dim), 3.0)
		else:
			draw_line(Vector2(name_x, sy), Vector2(name_x + 4.0, sy), Color(col, dim), 2.0)
			draw_line(Vector2(name_x + 6.0, sy), Vector2(name_x + 10.0, sy), Color(col, dim), 2.0)
		var ix := name_x + 14.0
		var irect := Rect2(ix, y + (ROW_H - ROW_ICON) * 0.5 - 1.0, ROW_ICON, ROW_ICON)
		_icon(font, irect, inf.get("icon"), str(inf.get("name", k)), Color(col, 0.6 * dim))
		var tx := ix + ROW_ICON + 6.0
		var tw := name_x + name_w - tx
		draw_string(font, Vector2(tx, y + 12.0), str(inf.get("name", k)), HORIZONTAL_ALIGNMENT_LEFT, tw, FONT_SIZE, Color(TITLE, dim))
		draw_string(font, Vector2(tx, y + 24.0), str(inf.get("sub", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, FONT_SIZE - 2, Color(TEXT, dim))
		_spots.append([Rect2(name_x, y, name_w, ROW_H - 2.0), "row", k])
		# its numbers: dealt and share, DPS from its first hit and the window's peak
		var raw: PackedFloat32Array = (model["raw"] as Dictionary)[k]
		var tot := 0.0
		var first := -1
		for i in range(raw.size()):
			tot += raw[i]
			if first < 0 and raw[i] > 0.0:
				first = i
		var held_s := (ts[ts.size() - 1] - ts[first] + 1.0) if first >= 0 and ts.size() > first else 0.0
		var peak := float((_rolled.get(k, {}) as Dictionary).get("peak", 0.0))
		draw_string(font, Vector2(num_x, y + 12.0), "%s dealt · %s" % [_n(tot), _pct(tot / total if total > 0.0 else 0.0)], HORIZONTAL_ALIGNMENT_LEFT, num_w, FONT_SIZE, Color(ACCENT if bool(inf.get("weapon", false)) else TITLE, dim))
		# pass 136 (lane BOT): the dry shots (fired by the aim rule with nothing to hit; Aim.dry_counts, lane GUNS)
		var dry_n := int(dry.get(k, 0))
		draw_string(font, Vector2(num_x, y + 24.0), "%s DPS since first hit · peak %s%s" % [_n(tot / held_s if held_s > 0.0 else 0.0), _n(peak),
			(" · %d dry shots" % dry_n) if dry_n > 0 else ""], HORIZONTAL_ALIGNMENT_LEFT, num_w, FONT_SIZE - 2, Color(TEXT, dim))
		# what shaped it: an icon each (the hint says what it did and when it was taken)
		var srcs: Array = inf.get("sources", [])
		if srcs.is_empty():
			draw_string(font, Vector2(src_x, y + 17.0), str(inf.get("note", "")), HORIZONTAL_ALIGNMENT_LEFT, maxf(w - src_x - 8.0, 10.0), FONT_SIZE - 1, Color(TEXT, dim))
		else:
			var sx := src_x
			for x in srcs:
				if sx + SRC_ICON > w - 8.0:
					draw_string(font, Vector2(sx, y + 17.0), "+%d" % (srcs.size() - srcs.find(x)), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
					break
				var r2 := Rect2(sx, y + (ROW_H - SRC_ICON) * 0.5 - 1.0, SRC_ICON, SRC_ICON)
				_icon(font, r2, x.get("icon"), str(x.get("name", "?")), kind_colour(str(x.get("kind_col", ""))))
				_spots.append([r2, "src", {"lines": x.get("lines", []), "times": x.get("times", []), "colour": TITLE}])
				sx += SRC_ICON + 3.0
		y += ROW_H
	if keys.size() > fit:
		draw_string(font, Vector2(name_x, size.y - 4.0), "%d-%d of %d lines (wheel)" % [scroll + 1, mini(scroll + fit, keys.size()), keys.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, TEXT)


## An icon in `rect` on a dark square with a rim in `rim`; without a texture, the name's first letter.
func _icon(font: Font, rect: Rect2, tex, label: String, rim: Color) -> void:
	draw_rect(rect.grow(1.0), Color(0.06, 0.065, 0.08))
	if tex is Texture2D:
		draw_texture_rect(tex, rect, false)
	else:
		var ch := label.substr(0, 1).to_upper()
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x
		draw_string(font, Vector2(rect.get_center().x - cw * 0.5, rect.end.y - 4.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TITLE)
	draw_rect(rect.grow(1.0), rim, false, 1.0)


## The hovered icon's hint, over everything (the overlay's draw).
func _draw_overlay() -> void:
	if hover.x < 0.0:
		return
	var s: Array = _spot_at(hover)
	if s.is_empty() or str(s[1]) == "row":
		return
	var pay: Dictionary = s[2]
	var lines: Array = pay.get("lines", [])
	if lines.is_empty():
		return
	var font := get_theme_default_font()
	var r: Rect2 = s[0]
	_overlay.draw_rect(r.grow(2.0), LIGHT, false, 1.5)
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var box := Vector2(w + 14.0, float(lines.size()) * 15.0 + 8.0)
	var x := r.get_center().x + 12.0
	if x + box.x > size.x - 2.0:
		x = r.get_center().x - 12.0 - box.x
	x = clampf(x, 2.0, maxf(size.x - box.x - 2.0, 2.0))
	# above the icon (over the chart), below it when there is no room
	var y := r.position.y - 6.0 - box.y
	if y < 2.0:
		y = r.end.y + 6.0
	y = clampf(y, 2.0, maxf(size.y - box.y - 2.0, 2.0))
	var rect := Rect2(Vector2(x, y), box)
	_overlay.draw_rect(rect, HOVER_BOX)
	_overlay.draw_rect(rect, HOVER_EDGE, false, 1.0)
	var ly := y + 15.0
	for k in range(lines.size()):
		_overlay.draw_string(font, Vector2(x + 7.0, ly), str(lines[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, pay.get("colour", TITLE) if k == 0 else TITLE)
		ly += 15.0
