## The Watch's build strip (pass 80, lane WATCH): when each item arrived over the run so far, one lane a kind (weapons;
## mutations and evolutions; cards; items and perks), a tick and a short name at its second of play. Drawn from the
## arrivals WatchData reads off the recorder's events; the panel hands it the list and a name lookup. Tools only.
extends Control

const BG := Color(0.105, 0.115, 0.14)
const EDGE := Color(0.22, 0.24, 0.29)
const TEXT := Color(0.62, 0.66, 0.74)
const LANES := ["Weapons", "Mutations", "Cards", "Items"]
const LANE_COL := [Color(0.98, 0.62, 0.3), Color(0.82, 0.52, 0.98), Color(0.45, 0.78, 0.98), Color(0.55, 0.88, 0.55)]
const FONT_SIZE := 11
const PAD_L := 70.0

var arrivals: Array = []
var now := 60.0
## {id: name}
var names: Dictionary = {}
## the microseconds _draw took since the panel last asked
var draw_us := 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The lane of an arrival: 0 a weapon, 1 a mutation or an evolution, 2 a card (a line), 3 an item or a perk.
static func lane_of(a: Dictionary) -> int:
	match str(a.get("kind", "")):
		"weapon":
			return 0
		"mutation", "evolution":
			return 1
		"passive_evolution":
			return 2
		"passive":
			return 2 if bool(a.get("line", false)) else 3
	return 3


func _draw() -> void:
	var us := Time.get_ticks_usec()
	_draw_all()
	draw_us += Time.get_ticks_usec() - us


func _draw_all() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2.ZERO, size), EDGE, false, 1.0)
	var lh := (size.y - 14.0) / float(LANES.size())
	var w := size.x - PAD_L - 8.0
	var span := maxf(now, 60.0)
	for i in range(LANES.size()):
		var y := 2.0 + lh * float(i)
		draw_string(font, Vector2(6, y + lh * 0.5 + 4.0), str(LANES[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LANE_COL[i])
		draw_line(Vector2(PAD_L, y + lh), Vector2(PAD_L + w, y + lh), Color(1, 1, 1, 0.05), 1.0)
	# the minutes along the bottom
	var step := 60.0 if span <= 600.0 else 300.0
	var m := 0.0
	while m <= span + 0.1:
		var x := PAD_L + w * m / span
		draw_line(Vector2(x, 2.0), Vector2(x, size.y - 12.0), Color(1, 1, 1, 0.04), 1.0)
		draw_string(font, Vector2(x + 2.0, size.y - 2.0), "%d:00" % int(m / 60.0), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
		m += step
	# the arrivals: a tick each, the name when it fits before the next one in its lane
	var last_end := [-1000.0, -1000.0, -1000.0, -1000.0]
	for a in arrivals:
		var lane := lane_of(a)
		var x := PAD_L + w * clampf(float(a["t"]) / span, 0.0, 1.0)
		var y := 2.0 + lh * float(lane)
		draw_line(Vector2(x, y + 3.0), Vector2(x, y + lh - 2.0), LANE_COL[lane], 2.0)
		if x > float(last_end[lane]) + 3.0:
			var nm := str(names.get(str(a["id"]), str(a["id"])))
			if int(a.get("level", 0)) > 1:
				nm += " %d" % int(a["level"])
			if nm.length() > 14:
				nm = nm.substr(0, 13) + "."
			var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x
			if x + 3.0 + tw < size.x - 2.0:
				draw_string(font, Vector2(x + 3.0, y + lh * 0.5 + 4.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
				last_end[lane] = x + 3.0 + tw
