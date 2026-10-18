## The Watch's "Damage taken" tab (pass 90, lane WATCH; Garry: "add a tab in the HP, and Danger beneath which would show
## a breakdown of where the damage comes from"): the hits the hero took (WatchData.hurt, harvested from his damage log)
## summed by source and attack, one row each: a dot (red a boss, purple an Elite, pink a special, else the colour it
## wore), "Source · attack", a bar (HP lost red, the Energy Shield's part blue, what he evaded a grey outline, against the
## biggest row), the whole run's HP lost and its share, the last WINDOWS[i] seconds' HP lost and share, the shield's
## part, the evades and the hits; a totals row at the foot. Click a column's head to sort by it (again: back to the run's
## HP lost); chips choose the window (10, 30 or 60 s); the wheel scrolls; the pointer on a row lights it
## and a hint gives its whole story (incoming, lost, shield, evaded, blocked, biggest hit, last hit). The window chips
## sit in the panel's tab row over it (WatchPanel._hp_block; click("win:<s>") here too). Drawn in _draw like
## the charts, in their style. Nothing here reads the game (the panel hands it the rows). Tools only.
extends Control

const DATA := preload("res://tools/watch/WatchData.gd")

const BG := Color(0.105, 0.115, 0.14)
const EDGE := Color(0.22, 0.24, 0.29)
const GRID := Color(1, 1, 1, 0.06)
const TEXT := Color(0.62, 0.66, 0.74)
const TITLE := Color(0.86, 0.89, 0.94)
const ACCENT := Color(0.93, 0.66, 0.26)
const BAD := Color(0.95, 0.42, 0.36)
const BLUE := Color(0.43, 0.71, 1.0)
const PURPLE := Color(0.72, 0.55, 0.96)
const PINK := Color(0.95, 0.55, 0.8)
const EVADE := Color(0.75, 0.78, 0.84, 0.75)
const HILITE := Color(1, 1, 1, 0.07)
const HOVER_BOX := Color(0.06, 0.065, 0.08, 0.95)
const HOVER_EDGE := Color(0.35, 0.38, 0.45)
const FONT_SIZE := 12
## (the space over the heads: the tab row above names the table and holds the window chips)
const TITLE_H := 3.0
const HEAD_H := 16.0
const ROW_H := 16.0
const PAD := 8.0
## the last-N-seconds column's choices
const WINDOWS := [10, 30, 60]
## the sortable columns: [key, head, width px, right-aligned]; "name" and "bar" take the room left
const COLS := [["run", "HP lost", 62.0], ["share", "Share", 44.0], ["win", "Last %d s", 92.0], ["shield", "Shield", 52.0],
	["evaded", "Evaded", 50.0], ["hits", "Hits", 40.0]]

## the rows the panel hands over: the whole run's and the window's (WatchData.sum_hurt's shape)
var run_rows: Array = []
var win_rows: Array = []
var window_s := 30
## "run" (the whole run's HP lost, the default), "win", "shield", "evaded", "hits"
var sort_by := "run"
## the play second now (the hint's "x s ago")
var now := 0.0
var scroll := 0
var draw_us := 0
var hover := Vector2(-1, -1)
## the table as drawn: table() of the rows
var _table: Array = []
## clickable places as drawn: [[Rect2, what]] ("sort:<key>", "win:<s>")
var _hits: Array = []
## the window changed by a click (the panel reads it and hands new rows)
signal window_changed(seconds: int)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_rows(p_run: Array, p_win: Array, p_now: float) -> void:
	run_rows = p_run
	win_rows = p_win
	now = p_now
	_table = table(run_rows, win_rows, sort_by)
	scroll = clampi(scroll, 0, maxi(_table.size() - 1, 0))
	queue_redraw()


## The rows of the table: each source + attack of the run with its window's numbers beside it: {key, by, attack, kind,
## role, colour, lost, share, raw, shield, evaded, evaded_raw, blocked, hits, biggest, last, w_lost, w_share, w_hits},
## sorted by `by` (pure; tested).
static func table(p_run: Array, p_win: Array, by: String = "run") -> Array:
	var tot := DATA.hurt_totals(p_run)
	var wtot := DATA.hurt_totals(p_win)
	var win := {}
	for r in p_win:
		win[str(r["key"])] = r
	var out: Array = []
	for r in p_run:
		var e: Dictionary = (r as Dictionary).duplicate()
		var w: Dictionary = win.get(str(r["key"]), {})
		e["share"] = float(r["lost"]) / float(tot["lost"]) if float(tot["lost"]) > 0.0 else 0.0
		e["w_lost"] = float(w.get("lost", 0.0))
		e["w_hits"] = int(w.get("hits", 0))
		e["w_share"] = float(w.get("lost", 0.0)) / float(wtot["lost"]) if float(wtot["lost"]) > 0.0 else 0.0
		out.append(e)
	var key: String = {"run": "lost", "share": "lost", "win": "w_lost", "shield": "shield", "evaded": "evaded", "hits": "hits"}.get(by, "lost")
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a[key]) != float(b[key]):
			return float(a[key]) > float(b[key])
		if float(a["lost"]) != float(b["lost"]):
			return float(a["lost"]) > float(b["lost"])
		if float(a["shield"]) != float(b["shield"]):
			return float(a["shield"]) > float(b["shield"])
		if int(a["hits"]) != int(b["hits"]):
			return int(a["hits"]) > int(b["hits"])
		return str(a["key"]) < str(b["key"]))
	return out


## A row's dot: a boss red, an Elite purple, a special pink, else the colour it wore ("#rrggbb"), else dim.
static func dot_colour(r: Dictionary) -> Color:
	match str(r.get("role", "")):
		"boss":
			return BAD
		"elite":
			return PURPLE
		"special":
			return PINK
	var c := str(r.get("colour", ""))
	if c.begins_with("#") and c.length() >= 7:
		return Color.html(c)
	return TEXT


static func _n(v: float) -> String:
	if v >= 100000.0:
		return "%dk" % int(roundf(v / 1000.0))
	if v >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	return "%d" % int(roundf(v))


static func _pct(v: float) -> String:
	return "%d%%" % int(roundf(100.0 * v)) if v > 0.0 else "-"


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = (event as InputEventMouseMotion).position
		queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll = mini(scroll + 1, maxi(_table.size() - _fit_rows(), 0))
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll = maxi(scroll - 1, 0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			for h in _hits:
				if (h[0] as Rect2).has_point(mb.position):
					click(str(h[1]))
					accept_event()
					break


## A click on a column's head or a window chip ("sort:<key>", "win:<seconds>").
func click(what: String) -> void:
	if what.begins_with("sort:"):
		var k := what.substr(5)
		sort_by = "run" if sort_by == k else k
		_table = table(run_rows, win_rows, sort_by)
	elif what.begins_with("win:"):
		window_s = int(what.substr(4))
		window_changed.emit(window_s)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover.x >= 0.0:
		hover = Vector2(-1, -1)
		queue_redraw()


func _fit_rows() -> int:
	return maxi(int(floor((size.y - TITLE_H - HEAD_H - ROW_H - 4.0) / ROW_H)), 1)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var us := Time.get_ticks_usec()
	_draw_all()
	draw_us += Time.get_ticks_usec() - us


## The columns' x (left edges) for the width now: name, bar, then COLS; [name_x, name_w, bar_x, bar_w, [col_x...]].
func _layout() -> Array:
	var right := size.x - PAD
	var xs: Array = []
	var x := right
	for i in range(COLS.size() - 1, -1, -1):
		x -= float(COLS[i][2])
		xs.push_front(x)
	var name_x := PAD + 12.0
	var room := x - 8.0 - name_x
	var name_w := clampf(room * 0.55, 90.0, 240.0)
	var bar_x := name_x + name_w + 6.0
	var bar_w := maxf(x - 10.0 - bar_x, 0.0)
	return [name_x, name_w, bar_x, bar_w, xs]


func _draw_all() -> void:
	var font := get_theme_default_font()
	_hits = []
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2.ZERO, size), EDGE, false, 1.0)
	# (the tab row over it names it and holds the window's chips: WatchPanel._hp_block)
	var lay := _layout()
	var name_x: float = lay[0]
	var name_w: float = lay[1]
	var bar_x: float = lay[2]
	var bar_w: float = lay[3]
	var xs: Array = lay[4]
	# the heads (click to sort)
	var hy := TITLE_H + 11.0
	draw_string(font, Vector2(name_x, hy), "Source · attack", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
	if bar_w > 30.0:
		draw_string(font, Vector2(bar_x, hy), "lost · shield · evaded", HORIZONTAL_ALIGNMENT_LEFT, bar_w, FONT_SIZE - 1, TEXT)
	for i in range(COLS.size()):
		var key := str(COLS[i][0])
		var head := str(COLS[i][1])
		if key == "win":
			head = head % window_s
		if sort_by == key or (key == "run" and sort_by == "share"):
			head = "▾ " + head
		var cw := float(COLS[i][2])
		var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x
		var hx: float = xs[i] + cw - hw
		draw_string(font, Vector2(hx, hy), head, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, ACCENT if sort_by == key else TEXT)
		_hits.append([Rect2(xs[i], TITLE_H, cw, HEAD_H), "sort:" + key])
	draw_line(Vector2(PAD, TITLE_H + HEAD_H), Vector2(size.x - PAD, TITLE_H + HEAD_H), GRID, 1.0)
	if _table.is_empty():
		draw_string(font, Vector2(name_x, TITLE_H + HEAD_H + 16.0), "Nothing has hurt him yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		return
	var fit := _fit_rows()
	var top := 0.0
	for r in _table:
		top = maxf(top, float(r["lost"]) + float(r["shield"]) + float(r["evaded_raw"]))
	var y := TITLE_H + HEAD_H + 2.0
	var hovered := -1
	for i in range(scroll, mini(scroll + fit, _table.size())):
		var r: Dictionary = _table[i]
		var row := Rect2(PAD, y, size.x - PAD * 2.0, ROW_H)
		if hover.x >= 0.0 and row.has_point(hover):
			hovered = i
			draw_rect(row, HILITE)
		_row(font, r, y, name_x, name_w, bar_x, bar_w, xs, top)
		y += ROW_H
	# the totals at the foot
	draw_line(Vector2(PAD, y + 1.0), Vector2(size.x - PAD, y + 1.0), GRID, 1.0)
	var tot := DATA.hurt_totals(run_rows)
	var wtot := DATA.hurt_totals(win_rows)
	var more := _table.size() - fit
	var label := "All, %d sources" % _table.size()
	if more > 0:
		label += " (%d-%d shown, wheel)" % [scroll + 1, mini(scroll + fit, _table.size())]
	var ty := y + 14.0
	draw_string(font, Vector2(name_x, ty), label, HORIZONTAL_ALIGNMENT_LEFT, name_w + bar_w, FONT_SIZE, TITLE)
	_cell(font, xs, 0, ty, "-" + _n(float(tot["lost"])) if float(tot["lost"]) >= 0.5 else "0", BAD)
	_cell(font, xs, 1, ty, "100%" if float(tot["lost"]) > 0.0 else "-", TEXT)
	_cell(font, xs, 2, ty, ("-%s" % _n(float(wtot["lost"]))) if float(wtot["lost"]) >= 0.5 else "0", BAD)
	_cell(font, xs, 3, ty, _n(float(tot["shield"])) if float(tot["shield"]) >= 0.5 else "-", BLUE)
	_cell(font, xs, 4, ty, str(int(tot["evaded"])) if int(tot["evaded"]) > 0 else "-", TITLE)
	_cell(font, xs, 5, ty, str(int(tot["hits"])), TITLE)
	if hovered >= 0:
		_hint(font, _table[hovered])


func _row(font: Font, r: Dictionary, y: float, name_x: float, name_w: float, bar_x: float, bar_w: float, xs: Array, top: float) -> void:
	var ty := y + 13.0
	draw_circle(Vector2(PAD + 5.0, y + ROW_H * 0.5), 3.5, dot_colour(r))
	var nm := "%s · %s" % [str(r["by"]), str(r["attack"])]
	draw_string(font, Vector2(name_x, ty), nm, HORIZONTAL_ALIGNMENT_LEFT, name_w, FONT_SIZE, TITLE)
	if bar_w > 8.0 and top > 0.0:
		var lost_w := bar_w * float(r["lost"]) / top
		var sh_w := bar_w * float(r["shield"]) / top
		var ev_w := bar_w * float(r["evaded_raw"]) / top
		var by := y + 4.0
		var bh := ROW_H - 8.0
		if lost_w > 0.0:
			draw_rect(Rect2(bar_x, by, maxf(lost_w, 1.0), bh), Color(BAD.r, BAD.g, BAD.b, 0.85))
		if sh_w > 0.0:
			draw_rect(Rect2(bar_x + lost_w, by, maxf(sh_w, 1.0), bh), Color(BLUE.r, BLUE.g, BLUE.b, 0.8))
		if ev_w > 0.5:
			draw_rect(Rect2(bar_x + lost_w + sh_w, by + 0.5, ev_w, bh - 1.0), EVADE, false, 1.0)
	_cell(font, xs, 0, ty, ("-" + _n(float(r["lost"]))) if float(r["lost"]) >= 0.5 else "0", BAD if float(r["lost"]) >= 0.5 else TEXT)
	_cell(font, xs, 1, ty, _pct(float(r["share"])), TEXT)
	var wl := float(r["w_lost"])
	_cell(font, xs, 2, ty, ("-%s  %s" % [_n(wl), _pct(float(r["w_share"]))]) if wl >= 0.5 else ("%d hit%s" % [int(r["w_hits"]), "" if int(r["w_hits"]) == 1 else "s"] if int(r["w_hits"]) > 0 else "-"),
		BAD if wl >= 0.5 else TEXT)
	_cell(font, xs, 3, ty, _n(float(r["shield"])) if float(r["shield"]) >= 0.5 else "-", BLUE if float(r["shield"]) >= 0.5 else TEXT)
	_cell(font, xs, 4, ty, str(int(r["evaded"])) if int(r["evaded"]) > 0 else "-", TITLE if int(r["evaded"]) > 0 else TEXT)
	_cell(font, xs, 5, ty, str(int(r["hits"])), TITLE)


## Column `i`'s text, right-aligned in it.
func _cell(font: Font, xs: Array, i: int, y: float, txt: String, col: Color) -> void:
	var cw := float(COLS[i][2])
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(float(xs[i]) + cw - w, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


## A row's whole story under the pointer (hint_lines), in a box beside it.
func _hint(font: Font, r: Dictionary) -> void:
	var lines := hint_lines(r, window_s, now)
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var box := Vector2(w + 14.0, float(lines.size()) * 15.0 + 8.0)
	var x := hover.x + 14.0
	if x + box.x > size.x - 2.0:
		x = hover.x - 14.0 - box.x
	x = clampf(x, 2.0, maxf(size.x - box.x - 2.0, 2.0))
	var y := hover.y + 12.0
	if y + box.y > size.y - 2.0:
		y = hover.y - 12.0 - box.y
	y = clampf(y, 2.0, maxf(size.y - box.y - 2.0, 2.0))
	var rect := Rect2(Vector2(x, y), box)
	draw_rect(rect, HOVER_BOX)
	draw_rect(rect, HOVER_EDGE, false, 1.0)
	var ly := y + 15.0
	for k in range(lines.size()):
		draw_string(font, Vector2(x + 7.0, ly), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, dot_colour(r) if k == 0 else TITLE)
		ly += 15.0


## The hint's lines for row `r` (pure; tested).
static func hint_lines(r: Dictionary, win_s: int, p_now: float) -> PackedStringArray:
	var out := PackedStringArray()
	var role := str(r.get("role", ""))
	out.append("%s · %s%s" % [str(r["by"]), str(r["attack"]), (" (%s)" % role) if role != "" else ""])
	out.append("Whole run: %d hit%s, %s incoming, %s HP lost (%s of all)" % [int(r["hits"]), "" if int(r["hits"]) == 1 else "s",
		_n(float(r["raw"])), _n(float(r["lost"])), _pct(float(r["share"]))])
	var parts := PackedStringArray()
	if float(r["shield"]) >= 0.5:
		parts.append("the Energy Shield took %s" % _n(float(r["shield"])))
	if int(r["evaded"]) > 0:
		parts.append("%d evaded (%s)" % [int(r["evaded"]), _n(float(r["evaded_raw"]))])
	if int(r["blocked"]) > 0:
		parts.append("%d blocked" % int(r["blocked"]))
	if not parts.is_empty():
		var s := ", ".join(parts)
		out.append(s.substr(0, 1).to_upper() + s.substr(1))
	out.append("Biggest hit %s HP · last hit %s ago" % [_n(float(r["biggest"])), DATA.mmss(maxf(p_now - float(r["last"]), 0.0))])
	out.append("Last %d s: %d hit%s, %s HP lost (%s)" % [win_s, int(r.get("w_hits", 0)), "" if int(r.get("w_hits", 0)) == 1 else "s",
		_n(float(r.get("w_lost", 0.0))), _pct(float(r.get("w_share", 0.0)))])
	return out
