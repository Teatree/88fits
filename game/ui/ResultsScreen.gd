## Results (Wanted screen 16): the hero and the gold first, the tables last. "★ EXTRACTED ★" (or RUN OVER) over the
## time survived and one line of the run; a panel with the hero's portrait and what was banked, the purse before and
## after, and a NEW BEST seal hanging off it when the run beat the map's best; the kills chart with its Kills and Damage
## counters; the damage dealt, one row a source (pass 47, Garry: "Each row must have both the icon and the text, with the
## absolute value of damage dealt": the plate, the name and the number over a bar of its share, the percent beside it,
## for every weapon, perk, power-up, fire, poison, the revive's blast and explosions, and a "?" plate for anything
## unknown); what the run unlocked and the unlocks it brought closer; PLAY AGAIN, then Upgrade (turquoise, pass 46: brass
## is for buying) and Main Menu. Since pass 70 a death banks the purse like an extraction (the Strongbox is retired).
## The hero's last hits are on the Down! screen since pass 46, not here.
## Pass 72 (Garry: "The Result Screen sequence in general should be more animated"), told as two sequences out of the
## run's own story (Run.timeline, RunTimeline):
## 1. "Run performance", the board held at the top (no finger or wheel moves it; it only eases down by itself when a
##    source row would land under the buttons): the banked gold counts up along the run's own purse curve in
##    GOLD_TIME while the rest of the board waits unseen in its place (pass 74, Garry: "The empty chart shouldn't just
##    be sitting there"); then the chart block pops in (POP_TIME) with the starting weapon's row; then the chart part
##    (pass 74, Garry: "the chart, the kill count, the damage dealt and the individual damage sources sequence to play
##    together at the same time"): one clock, JOINT_TIME for the whole run, draws the kills line left to right, its
##    badges popping in as the line reaches them (a grave for each time the hero went down, a skull a boss, a crown an
##    Elite, a gear a special), the Kills and Damage counters counting up in short numbers (999, 1.2k, 20k, 1.2m), and
##    the damage sources coming in as the line reaches the moment each joined the run (first owned, else first hit: a
##    revive's blast only when he got up again; ROW_BEAT between two that joined together), each bar, number and
##    percent showing its damage so far at the line's moment against the run's final total.
## 2. After PAUSE seconds the board scrolls down to the unlocks: each one this run completed lands in turn (its plate
##    from a silhouette to its art, a flash, an UNLOCKED stamp, a burst), then every unlock the run brought closer fills
##    its bar from where it stood to where it stands (this run's part in sage).
## A tap anywhere but on a button hurries the sequence playing (SPEED_UP), a second tap ends it; the buttons work at any
## time; the board scrolls freely once both are done. A normal run's whole show lasts about 10-14 s.
extends ScreenBase

## The damage sources' own pictures (pass 47, painted by the lead; until one is there its plate shows a "?").
const SOURCE_ART := "res://art/ui/sources/%s.png"
## Damage ids that are not an item: [picture, name]. A picture is a file in SOURCE_ART, or "passive:<id>" for a
## passive's icon (poison is Venom's, thorns Bristle's, pass 48 the Powder Keg's blast the Powder Keg's; the explosions'
## picture while a passive has no icon or is not in the game). Several ids can be one source ("burn" and "fire").
const SOURCES := {
	"": ["unknown", "ui.results.source.unknown"],
	"revive": ["revive", "ui.results.source.revive"],
	"fire": ["fire", "ui.results.source.fire"], "burn": ["fire", "ui.results.source.fire"], "burning": ["fire", "ui.results.source.fire"], "flames": ["fire", "ui.results.source.fire"],
	"poison": ["passive:venom", "ui.results.source.poison"], "toxic": ["passive:venom", "ui.results.source.poison"],
	"blast": ["blast", "ui.results.source.explosions"], "explosion": ["blast", "ui.results.source.explosions"], "loose_rocket": ["blast", "ui.results.source.explosions"],
	"thorns": ["passive:bristle", "ui.results.source.thorns"],
	"powder_keg": ["passive:powder_keg", "ui.results.source.powder_keg"],
	# pass 69: Hot Springs' heal pulses
	"hot_springs": ["passive:hot_springs", "ui.results.source.hot_springs"],
}

## The Stages menu's helpers (pass 87): a stage's entry, its colour.
const StagesScreenScript := preload("res://ui/StagesScreen.gd")
## Pass 137 (lane RESULTS, Garry: "the number going up looks jerky ... Make it ramp up linearly with higher intensity the
## higher the amount of Coins is; very animated, the number font increasing in size as it gets bigger and then snapping
## to the original size"): the banked gold counts up in a straight line from 0 to what was banked (equal time, equal
## coins: gold_at; the run's purse curve is the charts' only now). How hard it plays grows with the amount on one scale,
## gold_intensity: 0 up to GOLD_FEW coins, 1 from GOLD_MANY, by the logarithm between (100 coins 0.37, 1,000 0.74). Its
## length gold_time runs GOLD_MIN_TIME .. GOLD_MAX_TIME on it (10 coins 0.8 s, 100 1.4 s, 1,000 2.0 s, 5,000 and more
## 2.4 s); the number swells as it climbs (gold_swell: to GOLD_SWELL_LOW .. GOLD_SWELL_HIGH of its size at the top, the
## climb easing in by GOLD_SWELL_EASE), warms from its gold to GOLD_HOT, trembles by up to GOLD_RUMBLE px near the top of
## a big count (x Settings.screen_shake), and each coin's tick nudges it by GOLD_TICK_BUMP for GOLD_TICK_BUMP_TIME; the
## ticks come every GOLD_TICK_SLOW at the start down to GOLD_TICK_FAST at the top (a big purse starts faster). At the top
## it snaps back to its size (SNAP_DOWN to SNAP_UNDER of it, then SNAP_BACK with a small overshoot), a flash, a spray of
## coins (GOLD_SPRAY_MIN .. GOLD_SPRAY_MAX on the scale) and the last clink. Nothing of it for an empty purse.
const GOLD_FEW := 10.0
const GOLD_MANY := 5000.0
const GOLD_MIN_TIME := 0.8
const GOLD_MAX_TIME := 2.4
const GOLD_SWELL_LOW := 1.3
const GOLD_SWELL_HIGH := 1.45
const GOLD_SWELL_EASE := 1.4
const GOLD_HOT := Color("ffa22e")
const GOLD_RUMBLE := 3.0
const GOLD_TICK_BUMP := 0.05
const GOLD_TICK_BUMP_TIME := 0.07
const GOLD_TICK_SLOW := 0.11
const GOLD_TICK_FAST := 0.04
const SNAP_DOWN := 0.07
const SNAP_UNDER := 0.9
const SNAP_BACK := 0.26
const GOLD_SPRAY_MIN := 8
const GOLD_SPRAY_MAX := 22
## The chart block's pop once the gold is counted: from POP_FROM of its size, an ease-out-back of POP_BACK (a small
## overshoot, about 3 % past its size halfway through) and a fade over the first POP_FADE of it (as one picture:
## _pop_holder's CanvasGroup).
const POP_TIME := 0.3
const POP_FROM := 0.85
const POP_BACK := 2.6
const POP_FADE := 0.5
## The chart part: the line crosses the whole run in JOINT_TIME, the counters and the source rows on the same clock; a
## row comes in at its source's moment on the line, at least ROW_BEAT after the row before (two that joined together),
## and fades in over ROW_FADE; the part runs on past JOINT_TIME only as long as the last row needs.
const JOINT_TIME := 3.2
const ROW_BEAT := 0.12
const ROW_FADE := 0.2
## Pass 116 (lane RESULTS, Garry: "the progress for the task counts up like for other things on that screen ... the
## reward ... very clearly indicated as coins and it being added to the total Coins after the count is done"): after the
## gold, the bounty's panel fades in and its bar fills from 0 to how far the run came in BOUNTY_STAMP_AT of BOUNTY_TIME,
## then the stamp lands (PAID in sage, FAILED in rock, NOT DONE in soft ink) and the reward's row shows; a paid one then
## sends BOUNTY_FLY coins up to the Banked count in BOUNTY_PAY_TIME, the count ticking up with the coin's chink, the
## purse line after it. The reward was paid once already, at the run's end (WantedRun.settle): this only shows it.
## Pass 137 (lane RESULTS, Garry: "The addition of the coins from the Wanted poster should be very visual as well"): the
## pay is a show of its own in BOUNTY_PAY_TIME: BOUNTY_FLY coins pour from the reward's coin (it flashes as each leaves)
## one after another over BOUNTY_POUR of the part, each flying BOUNTY_FLIGHT of it on an arc with a streak behind it;
## each arrival adds its share to the Banked count (the shares sum to the reward exactly) with a chink, a nudge and a
## splash of three coins, the count swelling again to BOUNTY_SWELL of its size by the last; the last one snaps it back as
## the gold count's end does (a flash, a spray of coins, the clink) and the purse line takes the new total with a
## flourish (BOUNTY_LINE_POP, a gold flash).
const BOUNTY_TIME := 1.6
const BOUNTY_STAMP_AT := 0.7
const BOUNTY_PAY_TIME := 1.7
const BOUNTY_FLY := 10
const BOUNTY_POUR := 0.5
const BOUNTY_FLIGHT := 0.32
const BOUNTY_SWELL := 1.35
const BOUNTY_LINE_POP := 1.18
## Before the first part (the board's own slide-in).
const LEAD_IN := 0.35
const PAUSE := 2.0
const SCROLL_TIME := 0.7
const UNLOCK_TIME := 1.2
## A run that lands many unlocks gives each less time (all of them in UNLOCKS_MAX at most), never under UNLOCK_MIN.
const UNLOCKS_MAX := 4.0
const UNLOCK_MIN := 0.7
## When in an unlock's time its stamp lands (a share of its time).
const STAMP_AT := 0.35
const PROGRESS_STEP := 0.35
const PROGRESS_FILL := 0.55
const PROGRESS_MAX := 3.0
## A tap's hurry: the sequence playing runs this many times faster.
const SPEED_UP := 4.0
## The first sequence's lock ends with the second; once the show is over the board scrolls under a finger again.
const DONE := 3

var _count: WText
var _banked := 0
## The end-of-run survey (pass 59): PostHog's questions, when Analytics has one due, SURVEY_DELAY after the show ends.
const WSurveyScript := preload("res://ui/wanted/WSurvey.gd")
const SURVEY_DELAY := 1.4
var _survey: Control

var _tl: RunTimeline
var _run_time := 0.0
var _chart: WKillChart
var _kills_num: WText
var _dmg_num: WText
## The chart block (pass 74): unseen until the gold is counted, then popped in; the panel sits in a plain holder so its
## scale is not reset by the board's column (a Container resets its children's scale whenever it sorts).
var _chart_box: Control
var _chart_panel: PanelContainer
## The pop's own picture of the panel (a CanvasGroup: the panel fades as one picture, not layer by layer); gone once
## the block has landed (the panel back in its holder, so nothing is drawn twice for the rest of the show).
var _pop_group: CanvasGroup
var _perf_label: Control
var _dmg_label: Control
var _dmg_panel: PanelContainer
var _popped := false
## How long the chart part lasts: JOINT_TIME, or a little more when the last source row comes in later (ROW_BEAT).
var _joint_time := JOINT_TIME
var _kill_curve := PackedFloat32Array()
var _kills_total := 0
var _dmg_total := 0.0
## The source rows: {"row", "bar", "amount", "share", "frac", "value", "on", "ids": [[id, its damage]], "at": when it
## comes in on the chart part's clock, "from": that moment as a share of the run}.
var _rows: Array = []
## The unlocks completed: {"panel", "plate", "stamp", "landed"}.
var _unlocks: Array = []
## The unlocks brought closer: {"row", "bar", "count", "before", "after", "need", "on"}.
var _progress: Array = []
var _unlock_box: VBoxContainer
var _unlock_label: Control
var _progress_label: Control
## The show: {"seq": 1|2, "name", "dur", "fn": Callable(f: float, live: bool)}; the part playing, its clock, the speed.
var _parts: Array = []
var _part := 0
var _pt := 0.0
var _speed := 1.0
var _taps := 0
var _seq := 0
## Where the board is easing to while the show moves it (-1: nowhere).
var _follow := -1.0
var _scroll_from := -1.0
var _touch_id := -1
var _touch_on_button := false
var _gold_shown := -1
var _coin_ms := 0
## Pass 137 (lane RESULTS): the Banked count's own holder (a plain Control, so the row's sorting never resets the count's
## swell), its colour at rest, its last tick, its snap (one tween at a time) and whether this part has snapped yet.
var _count_hold: Control
var _count_base := Color.WHITE
var _tick_ms := -100000
var _snap_tw: Tween
var _snapped := false
## The bounty's pour (CoinPour: the coins in flight, drawn in one Control) and how many have come in.
var _pour: Control
var _pour_landed := 0
var _line_tw: Tween
## The purse line's own colour (its flourish flashes gold and comes back to it).
var _line_base := Color(0, 0, 0, 0)
## Pass 116 (lane RESULTS): the bounty's panel in the show: {"panel", "bar", "count", "stamp", "coins" (the reward's row),
## "coin", "coin_num", "have", "need", "paid", "landed", "fly": the flying coins}; {} without a bounty.
var _bounty: Dictionary = {}
var _gold_before := 0
var _after_line: WText
var _mark_ms := 0

## Pass 123 (lane RUN_A), the Royale look (the mock 7_Results; Garry: "Results as the mock, same order and content; PLAY
## AGAIN gold, UPGRADE blue, MAIN MENU slate", "Same white header"): the head's gaps and the run pills' size, the banked
## card's portrait and count, the gaps between the blocks, the damage rows' frame and type, the unlock's frame, the
## stamp's tag; the show and its timings are today's.
const ROYALE_HEAD_GAP := 40.0
const ROYALE_PILL_PX := 24
const ROYALE_PILL_H := 44.0
const ROYALE_PORTRAIT := 124.0
const ROYALE_BANKED_PX := 76
const ROYALE_BLOCK_GAP := 34.0
const ROYALE_LABEL_GAP := 12.0
const ROYALE_ROW_PLATE := 72.0
const ROYALE_ROW_PX := 28
const ROYALE_ROW_BAR := 16.0
const ROYALE_UNLOCK_PLATE := 80.0
const ROYALE_UNLOCK_PX := 40
const ROYALE_STAMP_PX := 28
## The dark overlay over the menu backdrop (ScreenBase.ROYALE_DIM is 0.25), the kills pill's skull.
const ROYALE_BACKDROP_DIM := 0.35
const ROYALE_SKULL := "res://art/ui/badges/skull.png"
const ROYALE_SKULL_PX := 30.0


## Pass 123 (lane RUN_A): the kills chart under Royale (the mock's RUN PERFORMANCE): no paper plot, the run's kills as a
## gold area under a lighter gold line straight on the slate, two faint guides, the stages' starts as dashed light lines
## with their names under them, the head's tip a navy dot ringed in cream, the badges as today with their counts on navy
## chips. The marks, their pops and their layout are WKillChart's own.
class RoyaleChart extends WKillChart:
	const AREA := Color(0.961, 0.722, 0.165, 0.86)
	const LINE := Color("ffdc73")
	const GUIDE := Color(1, 1, 1, 0.08)
	const BASE_LINE := Color(1, 1, 1, 0.22)
	const DASH := Color(1, 1, 1, 0.5)

	func _draw() -> void:
		var r := plot_rect()
		var inner := r.grow(-BORDER)
		for g in [0.33, 0.66]:
			var y: float = inner.end.y - inner.size.y * 0.86 * g
			draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), GUIDE, 2.0)
		draw_line(Vector2(inner.position.x, inner.end.y), Vector2(inner.end.x, inner.end.y), BASE_LINE, 2.0)
		if head > 0.0 and slices.size() > 0:
			var pts := PackedVector2Array()
			var steps := maxi(int(ceil(head * 120.0)), 2)
			for k in steps + 1:
				pts.append(_point(r, inner, head * float(k) / float(steps)))
			var poly := PackedVector2Array(pts)
			poly.append(Vector2(pts[pts.size() - 1].x, inner.end.y))
			poly.append(Vector2(inner.position.x, inner.end.y))
			draw_colored_polygon(poly, AREA)
			draw_polyline(pts, LINE, 4.0, true)
		for s in stage_x:
			if float(s[0]) > head:
				continue
			var sx: float = inner.position.x + float(s[0]) * inner.size.x
			_dashed(Vector2(sx, inner.position.y), Vector2(sx, inner.end.y), DASH, 3.0)
			_stage_name(Vector2(sx, r.end.y), Loc.t("ui.results.stage", {"stage": "%d" % (int(s[1]) + 1)}))
		if head > 0.0 and head < 1.0 and slices.size() > 0:
			var tip := _point(r, inner, head)
			draw_line(Vector2(tip.x, inner.position.y), Vector2(tip.x, inner.end.y), GUIDE, 2.0)
			draw_circle(tip, 8.0, R.NAVY, true, -1.0, true)
			draw_circle(tip, 4.0, R.CREAM, true, -1.0, true)
		if _laid != size:
			_layout()
		for pass_graves in [true, false]:
			for mk: Dictionary in marks:
				var grave := int(mk["kind"]) == RunTimeline.KIND_DOWN
				if grave != pass_graves or bool(mk["hidden"]) or float(mk["at"]) == -1.0:
					continue
				var sc := _pop_scale(float(mk["at"]))
				if sc <= 0.0:
					continue
				var c: Vector2 = mk["c"]
				var px := badge_px(int(mk["kind"]))
				var tex := _badge(int(mk["kind"]))
				var side := px * sc
				if tex:
					draw_texture_rect(tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
				else:
					draw_circle(c, side * 0.4, R.NAVY, true, -1.0, true)
				if int(mk["n"]) > 1 and sc >= 0.99:
					_chip(c + Vector2(px * 0.22, px * 0.18), "×%d" % int(mk["n"]))

	## A count on a navy chip (the mock's "×3"), white Rubik 700.
	func _chip(at: Vector2, t: String) -> void:
		var f := R.body(R.LABEL_WEIGHT)
		var px := 16
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 12.0
		var rc := Rect2(at - Vector2(0, 12), Vector2(w, 24))
		draw_style_box(R.flat(R.NAVY, R.RADIUS_TAG), rc)
		draw_string(f, Vector2(rc.position.x + 6.0, rc.position.y + 17.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, R.WHITE)

	## A stage's name under the plot in the kit's tracked label face, a light tick up to it.
	func _stage_name(at: Vector2, t: String) -> void:
		var px := 16
		var f := R.body(R.LABEL_WEIGHT, false, W.em(px, R.LABEL_TRACK))
		var w := f.get_string_size(t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var x := clampf(at.x - w * 0.5, 0.0, size.x - w)
		draw_line(at, at + Vector2(0, 7), DASH, 3.0)
		draw_string(f, Vector2(x, at.y + 7.0 + f.get_ascent(px)), t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px, R.SECONDARY)


## Pass 123 (lane RUN_A): the Results' stamp under Royale: the kit's tag (the mock's UNLOCKED): the word in Ultra, navy
## on the stamp's colour read the kit's way (sage -> the green tag, rock -> red, soft ink -> the muted grey), 4 px corners,
## a 3 px navy edge, on a navy foot. It lands as WStamp does (slam).
class RoyaleStamp extends WStamp:
	func stamp_size() -> Vector2:
		var f := R.display()
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px).x
		return Vector2(ceilf(w) + 36.0, float(text_px) + 26.0)

	func tag_fill() -> Color:
		if color.is_equal_approx(W.SAGE):
			return R.TAG_GREEN
		if color.is_equal_approx(W.ROCK):
			return R.TAG_RED
		if color.is_equal_approx(W.INK_SOFT):
			return R.MUTED
		return R.text_colour(color)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(R.flat(R.NAVY, R.RADIUS_TAG), Rect2(r.position + Vector2(0, 5), r.size))
		draw_style_box(R.flat(R.NAVY, R.RADIUS_TAG), r)
		draw_style_box(R.flat(tag_fill(), R.RADIUS_TAG - 1), r.grow(-float(R.TAG_EDGE)))
		var f := R.display()
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px).x
		var base := (size.y - f.get_height(text_px)) * 0.5 + f.get_ascent(text_px)
		draw_string(f, Vector2((size.x - w) * 0.5, base), word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px, R.NAVY)


## Pass 137 (lane RESULTS): coins drawn over the board in one Control (top level, in the screen's own coordinates): a
## `spray` (the snap at the top of a count: `bits` [pos, velocity, spin phase, spin speed, side] flung up and out, falling
## and fading over LIFE, then it frees itself) or a bounty's pour (`flying` [pos, streak points newest first, spin phase,
## side], set by the part each frame). The painted coin (WCoin.art(), else a drawn disc), spinning on its edge. Looks only.
class CoinFx extends Control:
	const LIFE := 0.8
	const FALL := 2400.0
	const STREAK := Color(1.0, 0.8, 0.28)
	var spray := false
	var bits: Array = []
	var flying: Array = []
	var _t := 0.0
	var _tex: Texture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_level = true
		_tex = WCoin.art()

	func _process(delta: float) -> void:
		if not spray:
			return
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		for b: Array in bits:
			b[1] = (b[1] as Vector2) + Vector2(0.0, FALL * delta)
			b[0] = (b[0] as Vector2) + (b[1] as Vector2) * delta
			b[2] = float(b[2]) + float(b[3]) * delta
		queue_redraw()

	func _draw() -> void:
		var fade := clampf((LIFE - _t) / (LIFE * 0.45), 0.0, 1.0) if spray else 1.0
		for b: Array in bits:
			_coin(b[0], float(b[4]), absf(cos(float(b[2]))), fade)
		for c: Array in flying:
			var streak: PackedVector2Array = c[1]
			var side := float(c[3])
			for k in streak.size():
				var q := 1.0 - float(k + 1) / float(streak.size() + 1)
				draw_circle(streak[k], side * 0.34 * (0.4 + 0.6 * q), Color(STREAK, 0.9 * q), true, -1.0, true)
			_coin(c[0], side, absf(cos(float(c[2]))), 1.0)

	func _coin(at: Vector2, side: float, squash: float, a: float) -> void:
		draw_set_transform(at, 0.0, Vector2(maxf(squash, 0.18), 1.0))
		if _tex:
			draw_texture_rect(_tex, Rect2(Vector2.ONE * -side * 0.5, Vector2(side, side)), false, Color(1, 1, 1, a))
		else:
			draw_circle(Vector2.ZERO, side * 0.5, Color(R.NAVY, a), true, -1.0, true)
			draw_circle(Vector2.ZERO, side * 0.5 - 3.0, Color(R.GOLD_TEXT, a), true, -1.0, true)
		draw_set_transform(Vector2.ZERO)


## A stamp in the theme (pass 123): WStamp, or under Royale the kit's tag (RoyaleStamp) built the way WStamp.make builds.
static func make_stamp(t: String, col: Color, px: int) -> WStamp:
	var s := RoyaleStamp.new()
	s.word = t
	s.color = col
	s.text_px = px
	s.size = s.stamp_size()
	s.custom_minimum_size = s.size
	s.pivot_offset = s.size * 0.5
	return s


## A run's number as a black pill (pass 123: the mock's run pills).
static func _pill(t: String) -> PanelContainer:
	return W.pill([[t, null, "bold"]], ROYALE_PILL_PX, ROYALE_PILL_H)


func use_header() -> bool:
	return false


## Pass 123 (lane RUN_A): under Royale the menu backdrop a little darker behind the Results' labels and panels.
func backdrop_dim() -> float:
	return ROYALE_BACKDROP_DIM


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
	_tl = Run.timeline if Run.timeline else RunTimeline.new()
	_run_time = float(s["time"])
	Audio.play_music(["mu_results"], 1)
	content.add_theme_constant_override("separation", 0)
	# the head: the star line, the time, one line of the run
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pass 87 (lane SUI): how the stage ended, the stage by its number and name, its own time, Endless's line when it ran
	var story := stage_story()
	head.add_child(WStarLine.make(str(story["star"]), 30, W.INK))
	var stage_line := W.text(str(story["stage"]).to_upper(), W.slab(W.em(26, 0.06)), 26, story["tone"], HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	# pass 123: the mock's stage line, the kit's tracked label in the secondary blue
	stage_line = W.text(str(story["stage"]).to_upper(), R.body(R.LABEL_WEIGHT, false, W.em(24, 0.12)), 24, R.SECONDARY,
		HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	stage_line.name = "StageLine"
	head.add_child(stage_line)
	head.add_child(W.slab_text(W.mmss(float(story["time"])), 120, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 120.0))
	if str(story["endless"]) != "":
		var el := W.serif_text(str(story["endless"]), 30, W.ROCK, 600, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
		el.name = "EndlessLine"
		el.custom_minimum_size.y = 42
		head.add_child(el)
	var bits: Array = [W.lv(int(s["level"])), Loc.t("ui.results.kills", {"kills": W.num(int(s["kills"]))}),
		Loc.t("ui.results.chests", {"count": "%d" % int(s["chests"])}), Loc.t("ui.results.evolutions", {"count": "%d" % int(s["evolutions"])})]
	# pass 123: the run's numbers as black pills (the mock's LV 47 · 934 kills · 3 chests · 0 evolutions)
	var pills := HBoxContainer.new()
	pills.name = "RunPills"
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 10)
	pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in bits.size():
		var pl := _pill(str(bits[k]))
		if k == 1 and ResourceLoader.exists(ROYALE_SKULL):
			# the mock's skull before the kills (the game's own badge)
			var sk := TextureRect.new()
			sk.name = "Skull"
			sk.texture = load(ROYALE_SKULL) as Texture2D
			sk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sk.custom_minimum_size = Vector2(ROYALE_SKULL_PX, ROYALE_SKULL_PX)
			sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sk.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var prow := pl.get_node_or_null("Row")
			if prow:
				prow.add_child(sk)
				prow.move_child(sk, 0)
		pills.add_child(pl)
	head.add_child(_gap(10))
	head.add_child(pills)
	content.add_child(head)
	content.add_child(_gap(ROYALE_HEAD_GAP))
	# the hero and the gold: banked, whatever the end (pass 70, Garry: "Make Coins stay if Player dies": a death and an
	# abandon bank the purse as an extraction does, Game.end_run); the Strongbox's line went with the Strongbox
	var before := int(res.get("gold_before", Save.gold()))
	_banked = int(res.get("banked", s["gold"]))
	var hero := PanelContainer.new()
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(38, 28, 38, 28))
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 30)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(hr)
	if Run.character:
		# his badge in the look he was played in (pass 68, Registry.played_look)
		var p := WPlate.new().for_def(Registry.played_look(Run.character), ROYALE_PORTRAIT)
		p.border = 6
		p.fill = W.AGED
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hr.add_child(p)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 6)
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gv.add_child(W.label(Loc.t("ui.results.banked"), 20, W.INK_SOFT))
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 14)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gr.add_child(WCoin.make(52.0, W.BRASS, 4.0))
	var banked_px := ROYALE_BANKED_PX
	_count = W.slab_text("+0", banked_px, W.BRASS_DARK, HORIZONTAL_ALIGNMENT_LEFT, float(banked_px))
	_count.name = "Banked"
	# pass 137 (lane RESULTS): in a plain holder that takes its size (the swell scales the count about its left middle;
	# its glyphs stay inside the line box up to about 1.5x)
	_count_base = _count.color
	_count_hold = Control.new()
	_count_hold.name = "BankedHold"
	_count_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_hold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_hold.add_child(_count)
	_count.minimum_size_changed.connect(_fit_count)
	_fit_count()
	gr.add_child(_count_hold)
	gv.add_child(gr)
	# pass 111 (lane WANTED): a bounty done came home beside the purse (WantedRun.settle)
	var bounty: Dictionary = res.get("bounty", {}) if res.get("bounty") is Dictionary else {}
	# pass 116 (lane RESULTS): the purse line takes the bounty's coins only once they have flown in (_part_bounty_pay)
	_gold_before = before
	_after_line = W.serif_text("%s → %s" % [W.num(before), W.num(before + _banked)], 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	# pass 123: the purse before and after in white Rubik 700, as the mock
	_after_line = W.text(_after_line.text, R.body(R.LABEL_WEIGHT), 24, R.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_after_line.name = "PurseLine"
	gv.add_child(_after_line)
	if not Save.hint_seen("results"):
		Save.mark_hint("results")
		gv.add_child(W.serif_text(Loc.t("ui.results.gold_note"),
			24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	hr.add_child(gv)
	var prev: Dictionary = res.get("prev_best", {})
	var new_best := not prev.is_empty() and float(s["time"]) > float(prev.get("time", 0.0)) + 0.5
	content.add_child(hero)
	if new_best:
		var seal := WSeal.new()
		seal.side = 150.0
		seal.fill = W.ROCK
		seal.border = 6
		seal.ring = 8
		seal.word = Loc.t("ui.results.new_best")
		seal.text_size = 19
		seal.rotation = deg_to_rad(12.0)
		seal.pivot_offset = Vector2(75, 75)
		hero.add_child(seal)
		# a free child: the panel lays out the rest (and resets its turn), the seal hangs off its top-right corner
		hero.sort_children.connect(func():
			seal.size = Vector2(150, 150)
			seal.pivot_offset = Vector2(75, 75)
			seal.rotation = deg_to_rad(12.0)
			seal.position = Vector2(hero.size.x - 150.0 + 30.0, -44.0))
	# pass 111 (lane WANTED): the run's bounty: what it paid, or how far it came (WantedRun.results_panel)
	# pass 116 (lane RESULTS): the Results' own panel, played in the show (_bounty_panel, _part_bounty, _part_bounty_pay)
	var bounty_panel := _bounty_panel(bounty)
	if bounty_panel:
		content.add_child(_gap(28))
		content.add_child(bounty_panel)
	# the kills chart and its counters (pass 72)
	_kills_total = int(s["kills"])
	var dmg: Dictionary = s["damage_by_weapon"]
	for id in dmg:
		_dmg_total += float(dmg[id])
	content.add_child(_gap(ROYALE_BLOCK_GAP))
	# pass 74: the block waits unseen in its place (nothing under it moves) until the gold is counted, then pops in
	_perf_label = W.label(Loc.t("ui.results.performance"), 22, W.INK_SOFT)
	_perf_label.modulate.a = 0.0
	content.add_child(_perf_label)
	content.add_child(_gap(ROYALE_LABEL_GAP))
	_chart_panel = _kills_panel()
	_chart_box = _pop_holder(_chart_panel)
	_pop_group.self_modulate.a = 0.0
	content.add_child(_chart_box)
	# the damage dealt, by source, in the order each joined the run (pass 47: every row its plate, its name and its number)
	if not dmg.is_empty():
		content.add_child(_gap(ROYALE_BLOCK_GAP))
		_dmg_label = W.label(Loc.t("ui.results.damage_dealt"), 22, W.INK_SOFT)
		_dmg_label.modulate.a = 0.0
		content.add_child(_dmg_label)
		content.add_child(_gap(ROYALE_LABEL_GAP))
		var src_rows := _source_rows(dmg)
		# pass 123: the mock's "DAMAGE DEALT · 12 SOURCES" and every row on one slate panel
		_dmg_label.text = Loc.t("ui.results.damage_dealt_count", {"count": "%d" % _rows.size()}).to_upper()
		var dp := PanelContainer.new()
		dp.name = "DamagePanel"
		dp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dp.add_theme_stylebox_override("panel", W.sheet_box(Vector2(22, 18)))
		dp.add_child(src_rows)
		# pass 124 (Garry: "Shows up from the start, empty and with nothing on it. It should only appear at the end"): the
		# panel waits unseen with its label and rows, keeping its place, and pops in with the chart (_part_pop)
		dp.modulate.a = 0.0
		_dmg_panel = dp
		content.add_child(dp)
	# what the run unlocked, and what it brought closer
	_build_unlocks()
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
	var again := WButton.make([Loc.t("ui.results.play_again")], 72, WButton.PRIMARY, 6, 10, 24.0, 0.0, 72.0)
	# pass 87 (lane SUI): the same stage again (Game plays stage 1 unless a stage was chosen)
	var again_stage := Run.stage
	# pass 120 (lane STARTGO): through the revolver wipe and the loading screen (UiFx.go_run, ui/RunCurtain.gd)
	again.pressed.connect(func(): Run.choose_stage(again_stage); UiFx.go_run(get_tree()))
	col.add_child(again)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pass 129: the Trail's button (the Upgrade board's until the board went); pass 137 (lane TUTOR; Garry: "The Results
	# screen's Trail button reads 'Upgrade'"): UPGRADE here only, still the Trail's way in (_on_upgrade)
	for spec in [[Loc.t("ui.results.upgrade"), Nav.TRAIL, WButton.UPGRADE], [Loc.t("ui.results.main_menu"), TITLE, WButton.SECONDARY]]:
		# pass 123: the words in capitals under Royale (UPGRADE blue, MAIN MENU slate: the variants' roles)
		var b := WButton.make([str(spec[0]).to_upper()], 30, spec[2], 5, 6, 20.0, 0.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var path: String = spec[1]
		if path == Nav.TRAIL:
			_upgrade_button(b)
		else:
			b.pressed.connect(func(): go(path))
		row.add_child(b)
	col.add_child(row)
	_plan()


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A plain holder for a panel the show pops in (pass 74, the chart block): as tall as the panel wants to be, the panel
## filling it. Until it has landed the panel sits in a CanvasGroup (`_pop_group`) centred in the holder, which the pop
## scales and fades as one picture (a see-through panel showed its ink shadow and its plot's ink through the paper);
## the board's column lays out only the holder, so nothing resets the pop's scale.
func _pop_holder(panel: Control) -> Control:
	var holder := Control.new()
	holder.name = "ChartBlock"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pop_group = CanvasGroup.new()
	_pop_group.name = "Pop"
	holder.add_child(_pop_group)
	_pop_group.add_child(panel)
	var fit := func():
		holder.custom_minimum_size.y = panel.get_combined_minimum_size().y
	panel.minimum_size_changed.connect(fit)
	holder.tree_entered.connect(fit)
	holder.resized.connect(func():
		panel.size = holder.size
		if is_instance_valid(_pop_group) and panel.get_parent() == _pop_group:
			_pop_group.position = holder.size * 0.5
			panel.position = -holder.size * 0.5
		else:
			panel.position = Vector2.ZERO)
	fit.call()
	return holder


## The block has landed: the panel back in its holder at its place, the pop's picture gone.
func _land_pop() -> void:
	if not is_instance_valid(_pop_group):
		return
	_pop_group.remove_child(_chart_panel)
	_chart_box.add_child(_chart_panel)
	_chart_panel.position = Vector2.ZERO
	_chart_panel.size = _chart_box.size
	_pop_group.queue_free()
	_pop_group = null


# ---------------------------------------------------------------- the parts the show fills

## The kills chart on paper, its Kills and Damage counters on the right (pass 72).
func _kills_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "KillsPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 5, 8).pad(30, 22, 30, 18))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 28)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var side := 236.0
	var chart_w := 1080.0 - 2.0 * board_side() - 70.0 - 28.0 - side
	_chart = (RoyaleChart.new()).setup(_tl, chart_w)
	_chart.name = "KillChart"
	_chart.custom_minimum_size = Vector2(0, 306)
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.popped.connect(_on_mark_popped)
	h.add_child(_chart)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size.x = side
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(W.label(Loc.t("ui.results.kills_label"), 20, W.INK_SOFT))
	# pass 123: both counters in gold under Royale (the mock's KILLS 934, DAMAGE 19k)
	_kills_num = W.slab_text("0", 66, W.BRASS, HORIZONTAL_ALIGNMENT_LEFT, 70.0)
	_kills_num.name = "Kills"
	v.add_child(_kills_num)
	v.add_child(_gap(26))
	v.add_child(W.label(Loc.t("ui.results.damage_label"), 20, W.INK_SOFT))
	_dmg_num = W.slab_text("0", 66, W.BRASS, HORIZONTAL_ALIGNMENT_LEFT, 70.0)
	_dmg_num.name = "Damage"
	v.add_child(_dmg_num)
	h.add_child(v)
	_kill_curve = _tl.kills_so_far()
	return p


## The damage rows in the order their sources joined the run, each unseen until its moment in the chart part (pass 74:
## `at`, row_times), the starting weapon's with the chart block's pop.
func _source_rows(dmg: Dictionary) -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.name = "DamageRows"
	rows.add_theme_constant_override("separation", 14)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var total := maxf(_dmg_total, 1.0)
	var story := not _tl.sources.is_empty()
	var joins: Array = []
	for src: Dictionary in ordered_sources(dmg, _tl):
		var frac := float(src["amount"]) / total
		var row := damage_row(src, frac)
		rows.add_child(row)
		var e := {"row": row, "bar": row.find_child("Bar", true, false), "amount": row.find_child("Amount", true, false),
			"share": row.find_child("Share", true, false), "frac": frac, "value": float(src["amount"]), "on": false,
			"ids": src.get("ids", []), "at": 0.0, "from": 0.0}
		_rows.append(e)
		_fill_row(e, 0.0)
		row.modulate.a = 0.0
		var at := float(src.get("at", INF))
		joins.append(INF if is_inf(at) else maxf(at, 0.0) / _tl.length())
	# pass 74: when each row comes in on the chart part's clock
	var times := row_times(joins, story, JOINT_TIME, ROW_BEAT)
	for k in _rows.size():
		_rows[k]["at"] = times[k]
		_rows[k]["from"] = clampf(times[k] / JOINT_TIME, 0.0, 1.0)
	if not _rows.is_empty():
		_joint_time = maxf(JOINT_TIME, float(times[times.size() - 1]) + ROW_FADE)
	return rows


## What the run unlocked (each lands in the second sequence) and every unlock it brought closer.
func _build_unlocks() -> void:
	var done: Array = []
	for id in QuestTracker.just_completed:
		# pass 76 (Garry: "Result Screen unlocks are showing heroes that I already unlocked"): a hero owned already is
		# never announced
		if not done.has(id) and not QuestTracker.owned_reward(Registry.quests.get(id)):
			done.append(id)
	QuestTracker.just_completed.clear()
	var closer := progress_list(_tl.quests_before)
	if done.is_empty() and closer.is_empty():
		return
	_unlock_box = VBoxContainer.new()
	_unlock_box.name = "Unlocks"
	_unlock_box.add_theme_constant_override("separation", 0)
	_unlock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_gap(ROYALE_BLOCK_GAP + 8.0))
	content.add_child(_unlock_box)
	if not done.is_empty():
		_unlock_label = W.label(Loc.t("ui.results.unlocked_label"), 22, W.INK_SOFT)
		_unlock_label.modulate.a = 0.0
		_unlock_box.add_child(_unlock_label)
		_unlock_box.add_child(_gap(ROYALE_LABEL_GAP))
		for id in done:
			var q: QuestDef = Registry.quests.get(id)
			if q == null:
				continue
			var panel := _unlocked(q)
			panel.modulate.a = 0.0
			var plate: WPlate = panel.find_child("Plate", true, false)
			if plate:
				plate.locked = true
				plate.queue_redraw()
			var stamp: WStamp = make_stamp(Loc.t("ui.results.stamp.for_sale") if bool(panel.get_meta("on_sale", false)) else Loc.t("ui.results.stamp.unlocked"), W.SAGE,
				ROYALE_STAMP_PX)
			stamp.visible = false
			panel.add_child(stamp)
			# pass 123: the mock's UNLOCKED tag inside the card at its right (the card keeps room for it), tilted 6 degrees
			var ps := panel.get_theme_stylebox("panel")
			if ps:
				ps.content_margin_right += stamp.stamp_size().x + 18.0
			panel.sort_children.connect(func():
				stamp.size = stamp.stamp_size()
				stamp.pivot_offset = stamp.size * 0.5
				stamp.rotation = deg_to_rad(-6.0)
				stamp.position = Vector2(panel.size.x - stamp.size.x - 26.0, (panel.size.y - stamp.size.y) * 0.5))
			_unlock_box.add_child(panel)
			_unlock_box.add_child(_gap(44))
			_unlocks.append({"panel": panel, "plate": plate, "stamp": stamp, "landed": false})
	if not closer.is_empty():
		if not done.is_empty():
			_unlock_box.add_child(_gap(30))
		_progress_label = W.label(Loc.t("ui.results.progress_label"), 22, W.INK_SOFT)
		_progress_label.modulate.a = 0.0
		_unlock_box.add_child(_progress_label)
		_unlock_box.add_child(_gap(18))
		var list := VBoxContainer.new()
		list.name = "Progress"
		list.add_theme_constant_override("separation", 22)
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_unlock_box.add_child(list)
		for c: Dictionary in closer:
			var e := _progress_row(c)
			list.add_child(e["row"])
			_progress.append(e)
			_fill_progress(e, 0.0)
			(e["row"] as Control).modulate.a = 0.0


## The unlocks the run brought closer: every counted quest not done whose progress grew since the run began
## (`before`: RunTimeline.quests_before), nearest to done first: {q, before, after, need}.
static func progress_list(before: Dictionary) -> Array:
	var out: Array = []
	for id in before:
		var q: QuestDef = Registry.quests.get(id)
		# pass 76: nor a hero owned already (bought before his quest was done)
		if q == null or Save.quest_done(q.id) or QuestTracker.owned_reward(q):
			continue
		var p := QuestTracker.progress(q)
		if p.y <= 0 or p.x <= int(before[id]):
			continue
		out.append({"q": q, "before": int(before[id]), "after": mini(p.x, p.y), "need": p.y})
	out.sort_custom(func(a, b): return float(a["after"]) / float(a["need"]) > float(b["after"]) / float(b["need"]))
	return out


## One unlock brought closer: its reward's plate (a silhouette: it is not his yet), what it asks, and a bar from where
## it stood to where it stands, this run's part in sage, the count beside it.
func _progress_row(c: Dictionary) -> Dictionary:
	var q: QuestDef = c["q"]
	var h := HBoxContainer.new()
	h.name = "Closer"
	h.add_theme_constant_override("separation", 22)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var def := _reward(q)
	var plate := WPlate.new()
	if def:
		plate.for_def(def, 84.0, true)
	else:
		plate.side = 84.0
		plate.fill = W.AGED
		plate.glyph = "?"
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pass 128: a weapon that waits for its outlaw says so in place of the quest's words (a tap opens his page)
	var giver := CollectionScreen.comes_with(_reward(q))
	if giver:
		v.add_child(CollectionScreen.comes_with_line(giver, 26, self))
	else:
		v.add_child(W.serif_text(TextGen.quest_text(q), 26, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 16)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := WBar.make(0.0, W.BRASS, 26.0, 4, 0)
	bar.name = "Bar"
	bar.gain_fill = W.SAGE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(bar)
	var count := W.slab_text("", 26, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	count.name = "Count"
	count.custom_minimum_size.x = 190
	bh.add_child(count)
	v.add_child(bh)
	h.add_child(v)
	return {"row": h, "bar": bar, "count": count, "before": int(c["before"]), "after": int(c["after"]),
		"need": maxi(int(c["need"]), 1), "on": false, "q": q}


# ---------------------------------------------------------------- the show

## The parts in their order: the first sequence (the gold, the chart block's pop, the chart part: the line, the counters
## and the sources together), then the second (a pause, the scroll, each unlock, the bars) when the run unlocked or
## brought anything closer.
func _plan() -> void:
	_parts.clear()
	_add(1, "gold", gold_time(_banked), _part_gold)
	if not _bounty.is_empty():
		_add(1, "bounty", BOUNTY_TIME, _part_bounty)
		if int(_bounty["paid"]) > 0:
			_add(1, "bounty_pay", BOUNTY_PAY_TIME, _part_bounty_pay)
	_add(1, "pop", POP_TIME, _part_pop)
	_add(1, "chart", _joint_time, _part_chart)
	if _unlock_box:
		_add(2, "pause", PAUSE, _noop)
		_add(2, "scroll", SCROLL_TIME, _part_scroll)
		for k in _unlocks.size():
			_add(2, "unlock", unlock_time(_unlocks.size()), _part_unlock.bind(k))
		if not _progress.is_empty():
			_add(2, "progress", _progress_time(), _part_progress)
	_part = 0
	_pt = -LEAD_IN
	_speed = 1.0
	_taps = 0
	_seq = 1


func _add(seq: int, part: String, dur: float, fn: Callable) -> void:
	_parts.append({"seq": seq, "name": part, "dur": dur, "fn": fn})


func _noop(_f: float, _live: bool) -> void:
	pass


## The start-to-start step of `n` rows filling over `fill`, at most `step`, so the lot fits in `most`.
static func row_step(n: int, step: float, fill: float, most: float) -> float:
	if n <= 1:
		return 0.0
	return minf(step, maxf(most - fill, 0.0) / float(n - 1))


## One unlock's time when the run lands `n`.
static func unlock_time(n: int) -> float:
	return clampf(UNLOCKS_MAX / float(maxi(n, 1)), UNLOCK_MIN, UNLOCK_TIME)


## When each source row comes in on the chart part's clock (seconds from its start; pass 74), from `joins`, each source's
## moment as a share of the run (INF for one the record never saw): a run with a story brings each in as the line
## reaches its moment (the starting weapon at 0, one never seen at the line's end), a run without one (a tool's, a
## test's) spreads them evenly, row k at k / n of `part`; never closer than `beat` to the row before.
static func row_times(joins: Array, story: bool, part: float, beat: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := joins.size()
	for k in n:
		var at := part * float(k) / float(maxi(n, 1))
		if story:
			var j := float(joins[k])
			at = part if is_inf(j) else clampf(j, 0.0, 1.0) * part
		if k > 0:
			at = maxf(at, out[k - 1] + beat)
		out.append(at)
	return out


func _progress_time() -> float:
	return row_step(_progress.size(), PROGRESS_STEP, PROGRESS_FILL, PROGRESS_MAX) * float(maxi(_progress.size() - 1, 0)) + PROGRESS_FILL


## Pass 137 (lane RESULTS): how hard the gold count plays for `n` coins: 0 up to GOLD_FEW, 1 from GOLD_MANY, by the
## logarithm between.
static func gold_intensity(n: int) -> float:
	if float(n) <= GOLD_FEW:
		return 0.0
	return clampf(log(float(n) / GOLD_FEW) / log(GOLD_MANY / GOLD_FEW), 0.0, 1.0)


## The gold count's length for `n` coins: GOLD_MIN_TIME .. GOLD_MAX_TIME on gold_intensity.
static func gold_time(n: int) -> float:
	return lerpf(GOLD_MIN_TIME, GOLD_MAX_TIME, gold_intensity(n))


## The count at share `f` of its time: a straight line from 0 to `n`, rounded down (never ahead of the line), `n` at the
## end.
static func gold_at(n: int, f: float) -> int:
	if f >= 1.0:
		return n
	return clampi(int(floor(float(n) * clampf(f, 0.0, 1.0) + 0.000001)), 0, n)


## The count's size at share `f` of its climb: 1 at the start, GOLD_SWELL_LOW .. GOLD_SWELL_HIGH (on gold_intensity) at
## the top, easing in; 1 for an empty purse.
static func gold_swell(n: int, f: float) -> float:
	if n <= 0:
		return 1.0
	var top := lerpf(GOLD_SWELL_LOW, GOLD_SWELL_HIGH, gold_intensity(n))
	return 1.0 + (top - 1.0) * pow(clampf(f, 0.0, 1.0), GOLD_SWELL_EASE)


## The gap between two coin ticks at share `f` of the climb (real seconds): GOLD_TICK_SLOW at the start of a small count
## down to GOLD_TICK_FAST at the top (a big purse starts faster).
static func gold_tick_gap(n: int, f: float) -> float:
	return lerpf(GOLD_TICK_SLOW, GOLD_TICK_FAST, clampf(0.35 * gold_intensity(n) + 0.65 * clampf(f, 0.0, 1.0), 0.0, 1.0))


## The banked gold (pass 137: in a straight line, gold_at; the run's purse curve before): the number swells, warms and
## ticks faster as it climbs, a big count trembles near the top, and at the top it snaps back (_snap_count). Skipped
## (`live` false) it lands at once, at its size and colour.
func _part_gold(f: float, live: bool) -> void:
	var iv := gold_at(_banked, f)
	_count.text = "+" + W.num(iv)
	var now := Time.get_ticks_msec()
	if live and f < 1.0 and _banked > 0 and iv > _gold_shown and float(now - _tick_ms) >= gold_tick_gap(_banked, f) * 1000.0:
		_tick_ms = now
		W.sfx("pk_coin")
	_gold_shown = iv
	if f >= 1.0:
		if not live or _banked <= 0:
			_rest_count()
		elif not _snapped:
			_snapped = true
			_snap_count(gold_intensity(_banked))
		return
	var k := gold_intensity(_banked)
	var warm := clampf(f * 1.15, 0.0, 1.0) if _banked > 0 else 0.0
	_swell_count(gold_swell(_banked, f) + _tick_bump(now), _count_base.lerp(GOLD_HOT, warm), f * f * k)


## The count at `s` of its size (about its left middle), in `col`, trembling by up to `rumble` x GOLD_RUMBLE px
## (x Settings.screen_shake; a look, randf).
func _swell_count(s: float, col: Color, rumble: float) -> void:
	if _snap_tw and _snap_tw.is_valid():
		_snap_tw.kill()
	_count.scale = Vector2.ONE * s
	_count.color = col
	_count.modulate = Color.WHITE
	var r := GOLD_RUMBLE * rumble * clampf(Settings.screen_shake, 0.0, 1.0)
	_count.position = Vector2(randf_range(-r, r), randf_range(-r, r)) if r > 0.05 else Vector2.ZERO


## A tick's nudge, fading over GOLD_TICK_BUMP_TIME after it.
func _tick_bump(now: int) -> float:
	return GOLD_TICK_BUMP * clampf(1.0 - float(now - _tick_ms) / (GOLD_TICK_BUMP_TIME * 1000.0), 0.0, 1.0)


## The top of a count: the number snaps from its swell down past its size (SNAP_DOWN to SNAP_UNDER) and back with a small
## overshoot (SNAP_BACK), flashing from cream to its gold, a spray of coins from it (more and further for a bigger
## purse, `k` its intensity) and the last clink.
func _snap_count(k: float) -> void:
	if _snap_tw and _snap_tw.is_valid():
		_snap_tw.kill()
	var sp := maxf(_speed, 1.0)
	_count.position = Vector2.ZERO
	_count.color = R.CREAM
	_count.modulate = Color(1.6, 1.6, 1.4, 1.0)
	_snap_tw = create_tween()
	_snap_tw.tween_property(_count, "scale", Vector2.ONE * SNAP_UNDER, SNAP_DOWN / sp).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_snap_tw.tween_property(_count, "scale", Vector2.ONE, SNAP_BACK / sp).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_snap_tw.parallel().tween_property(_count, "modulate", Color.WHITE, SNAP_BACK / sp)
	_snap_tw.parallel().tween_property(_count, "color", _count_base, SNAP_BACK / sp)
	W.sfx("it_coin_drop")
	if _count.is_inside_tree():
		_spray_coins(_count_centre(), int(round(lerpf(GOLD_SPRAY_MIN, GOLD_SPRAY_MAX, k))), lerpf(0.8, 1.2, k))


## The count at rest: its size, its place, its gold (a skip; the snap's tween stopped).
func _rest_count() -> void:
	if _snap_tw and _snap_tw.is_valid():
		_snap_tw.kill()
	_snap_tw = null
	_count.scale = Vector2.ONE
	_count.position = Vector2.ZERO
	_count.color = _count_base
	_count.modulate = Color.WHITE


## The holder takes the count's size; the count scales about its left middle.
func _fit_count() -> void:
	if _count == null or _count_hold == null:
		return
	var m := _count.get_combined_minimum_size()
	_count_hold.custom_minimum_size = m
	_count.size = m
	_count.pivot_offset = Vector2(0.0, m.y * 0.5)


## Where the Banked number stands on screen (the middle of its digits as drawn): the bounty's coins fly there, the
## spray starts there.
func _count_centre() -> Vector2:
	if _count == null or _count_hold == null or not _count_hold.is_inside_tree():
		return Vector2.ZERO
	var w := _count.text_width()
	return _count_hold.get_global_rect().position + Vector2(w * 0.5 * _count.scale.x, _count.size.y * 0.5)


## A spray of `n` coins from `at` (CoinFx), flung up and out at `power` of their speed. Looks only (randf).
func _spray_coins(at: Vector2, n: int, power: float) -> void:
	if n <= 0:
		return
	var fx := CoinFx.new()
	fx.name = "CoinSpray"
	fx.spray = true
	for i in n:
		var ang := randf_range(-PI * 0.92, -PI * 0.08)
		var v := Vector2(cos(ang), sin(ang)) * randf_range(420.0, 950.0) * power
		var spin := randf_range(9.0, 20.0) * (1.0 if randf() < 0.5 else -1.0)
		fx.bits.append([at, v, randf() * TAU, spin, randf_range(26.0, 42.0)])
	add_child(fx)


## Pass 116 (lane RESULTS): the bounty's panel in the show (one poster a run: the one taken, WantedRun). Built hidden;
## its bar, its count ("0 / 60" counting up), its stamp and the reward as coins: the coin and "+240" in gold.
func _bounty_panel(rec: Dictionary) -> Control:
	if rec.is_empty():
		return null
	var have := int(rec.get("have", 0))
	var need := maxi(int(rec.get("need", 0)), 1)
	var paid_n := int(rec.get("paid", 0))
	var p := PanelContainer.new()
	p.name = "BountyPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(34, 22, 34, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(W.label(Loc.t("ui.results.bounty_label"), 22, W.INK_SOFT))
	# the poster's row without its right-hand word (the stamp and the coins say it)
	v.add_child(WantedRun.row_for(rec, ""))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 16)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := WBar.make(0.0, W.SAGE if paid_n > 0 else W.BRASS, 26.0, 4, 0)
	bar.name = "BountyBar"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(bar)
	var count := W.slab_text("", 26, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	count.name = "BountyCount"
	count.custom_minimum_size.x = 190
	bh.add_child(count)
	v.add_child(bh)
	# the reward: the coin and its number in gold (Garry: "right now it's just brownish text, could mean anything");
	# a bounty not done shows what it would have paid, faded
	var coins := HBoxContainer.new()
	coins.name = "BountyReward"
	coins.add_theme_constant_override("separation", 12)
	coins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reward_n := paid_n if paid_n > 0 else int(rec.get("reward", 0))
	var say := W.serif_text(Loc.t("ui.results.bounty_paid") if paid_n > 0 else Loc.t("ui.results.bounty_would_pay"), 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	say.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coins.add_child(say)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coins.add_child(sp)
	var coin := WCoin.make(56.0, W.BRASS if paid_n > 0 else W.AGED, 4.0)
	coin.name = "BountyCoin"
	coins.add_child(coin)
	var cn := W.slab_text("+%s" % W.num(reward_n), 52, W.BRASS if paid_n > 0 else W.INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT, 56.0)
	cn.name = "BountyCoins"
	cn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if paid_n > 0:
		cn.stroke = 6
		cn.stroke_color = W.INK
		cn.shadow = 3
	coins.add_child(cn)
	coins.modulate.a = 0.0
	v.add_child(coins)
	var word := Loc.t("ui.results.stamp.paid") if paid_n > 0 else (Loc.t("ui.results.stamp.failed") if bool(rec.get("failed", false)) else Loc.t("ui.results.stamp.not_done"))
	var stamp := make_stamp(word, W.SAGE if paid_n > 0 else (W.ROCK if bool(rec.get("failed", false)) else W.INK_SOFT), 34)
	stamp.name = "BountyStamp"
	stamp.visible = false
	p.add_child(stamp)
	p.sort_children.connect(func():
		stamp.size = stamp.stamp_size()
		stamp.pivot_offset = stamp.size * 0.5
		stamp.rotation = deg_to_rad(-8.0)
		stamp.position = Vector2(p.size.x - stamp.size.x - 10.0, -stamp.size.y * 0.35))
	p.modulate.a = 0.0
	_bounty = {"panel": p, "bar": bar, "count": count, "stamp": stamp, "coins": coins, "coin": coin, "coin_num": cn,
		"have": mini(have, need), "need": need, "paid": paid_n, "landed": false}
	_fill_bounty(0.0)
	return p


func _fill_bounty(k: float) -> void:
	var need := float(_bounty["need"])
	var now := lerpf(0.0, float(_bounty["have"]), clampf(k, 0.0, 1.0))
	(_bounty["bar"] as WBar).value = now / need
	(_bounty["count"] as WText).text = "%s / %s" % [W.num(int(round(now))), W.num(int(need))]


## The bounty's record shown (tests, captures): {} without one.
func bounty_view() -> Dictionary:
	return _bounty


## The bounty part: the panel fades in, the bar and its count fill from nothing to how far the run came (a tick as it
## climbs), then the stamp slams down and the reward's row shows.
func _part_bounty(f: float, live: bool) -> void:
	var p: Control = _bounty["panel"]
	if p.modulate.a <= 0.0 and live:
		_follow_into(p)
	p.modulate.a = 1.0 if f >= 1.0 else maxf(p.modulate.a, clampf(f / 0.15, 0.0, 1.0))
	var k := _ease_out(clampf(f / BOUNTY_STAMP_AT, 0.0, 1.0))
	var was := (_bounty["count"] as WText).text
	_fill_bounty(k)
	if live and was != (_bounty["count"] as WText).text and Time.get_ticks_msec() - _coin_ms > 70:
		_coin_ms = Time.get_ticks_msec()
		W.sfx("ui_reel_tick")
	if f >= BOUNTY_STAMP_AT and not bool(_bounty["landed"]):
		_bounty["landed"] = true
		var stamp: WStamp = _bounty["stamp"]
		stamp.visible = true
		stamp.slam(0.16 / _speed if live else 0.0)
		if live:
			W.sfx("ui_stamp")
			if int(_bounty["paid"]) > 0:
				p.modulate = Color(1.6, 1.6, 1.5, 1.0)
				create_tween().tween_property(p, "modulate", Color.WHITE, 0.4 / _speed)
	if f >= BOUNTY_STAMP_AT:
		(_bounty["coins"] as Control).modulate.a = 1.0 if f >= 1.0 else clampf((f - BOUNTY_STAMP_AT) / 0.15, 0.0, 1.0)
	if f >= 1.0:
		p.modulate = Color.WHITE


## When coin `i` of a bounty's `n` leaves the reward (a share of the pay part: one after another over BOUNTY_POUR) and how
## far it has come at `f`: below 0 not yet gone, 1 and more in.
static func bounty_coin_t(n: int, i: int, f: float) -> float:
	var s := BOUNTY_POUR * float(i) / float(maxi(n - 1, 1))
	return (f - s) / BOUNTY_FLIGHT


## How many of a bounty's `n` coins have come in at `f` (all of them at the part's end).
static func bounty_landed(n: int, f: float) -> int:
	if f >= 1.0:
		return n
	var k := 0
	for i in n:
		if bounty_coin_t(n, i, f) >= 1.0:
			k += 1
	return k


## What `landed` of `n` coins have brought of the reward `paid`: each its share rounded down, the last the rest (the
## shares sum to the reward exactly).
static func bounty_got(paid: int, n: int, landed: int) -> int:
	if landed >= n:
		return paid
	return clampi(int(floor(float(paid) * float(landed) / float(maxi(n, 1)))), 0, paid)


## Pass 137 (lane RESULTS): a paid bounty's coins pour from its reward into the Banked count: BOUNTY_FLY coins leave the
## reward's coin one after another (it flashes as each goes), each on its own arc with a streak behind it; each arrival
## adds its share (bounty_got) with a chink and a nudge, the count swelling and warming to BOUNTY_SWELL by the last, which
## snaps it back (_snap_count) and gives the purse line its new total with a flourish. The reward's number stays as what
## it paid. Skipped (`live` false) it lands at once.
func _part_bounty_pay(f: float, live: bool) -> void:
	var paid_n := int(_bounty["paid"])
	var n := BOUNTY_FLY
	var from_c: Control = _bounty["coin"]
	var landed := bounty_landed(n, f)
	var now := Time.get_ticks_msec()
	if live and f < 1.0 and _pour == null and landed < n and from_c.is_inside_tree() and _count.is_inside_tree():
		var fx := CoinFx.new()
		fx.name = "BountyPour"
		add_child(fx)
		_pour = fx
	if _pour and is_instance_valid(_pour):
		var a: Vector2 = from_c.get_global_rect().get_center()
		var b: Vector2 = _count_centre()
		var flying: Array = []
		var gone := 0
		for i in n:
			var t := bounty_coin_t(n, i, f)
			if t >= 0.0:
				gone += 1
			if t <= 0.0 or t >= 1.0 or f >= 1.0:
				continue
			var lean := lerpf(-170.0, 170.0, float(i) / float(maxi(n - 1, 1)))
			var mid := (a + b) * 0.5 + Vector2(lean, -190.0 - 50.0 * sin(float(i) * 1.7))
			var streak := PackedVector2Array()
			for k in 5:
				var tk := t - 0.05 * float(k + 1)
				if tk <= 0.0:
					break
				streak.append(_arc(a, mid, b, tk))
			flying.append([_arc(a, mid, b, t), streak, t * TAU * 1.6 + float(i), lerpf(58.0, 42.0, t)])
		(_pour as CoinFx).flying = flying
		_pour.queue_redraw()
		if gone > int(_bounty.get("gone", 0)):
			_bounty["gone"] = gone
			_bounty["gone_ms"] = now
		var flash := clampf(1.0 - float(now - int(_bounty.get("gone_ms", -100000))) / 110.0, 0.0, 1.0)
		from_c.modulate = Color.WHITE.lerp(Color(1.7, 1.6, 1.2, 1.0), flash)
	var got := bounty_got(paid_n, n, landed)
	var iv := _banked + got
	_count.text = "+" + W.num(iv)
	if _after_line:
		_after_line.text = "%s → %s" % [W.num(_gold_before), W.num(_gold_before + iv)]
	if not live:
		if f >= 1.0:
			_end_pour()
			_rest_count()
			_rest_line()
		_gold_shown = iv
		return
	if landed > _pour_landed:
		_pour_landed = landed
		_tick_ms = now
		if landed < n:
			W.sfx("pk_coin")
			# a little splash where it lands
			_spray_coins(_count_centre(), 3, 0.45)
	_gold_shown = iv
	if landed >= n:
		if not bool(_bounty.get("snapped", false)):
			_bounty["snapped"] = true
			_end_pour()
			_snap_count(gold_intensity(paid_n))
			_flourish_line()
		return
	var share := float(landed) / float(n)
	_swell_count(1.0 + (BOUNTY_SWELL - 1.0) * share + _tick_bump(now), _count_base.lerp(GOLD_HOT, share), 0.0)


## A point of a coin's arc (a quadratic curve from `a` over `mid` to `b`) at `t`, eased in and out.
static func _arc(a: Vector2, mid: Vector2, b: Vector2, t: float) -> Vector2:
	var e := clampf(t, 0.0, 1.0)
	e = e * e * (3.0 - 2.0 * e)
	return a.lerp(mid, e).lerp(mid.lerp(b, e), e)


## The pour's coins gone, the reward's coin at rest.
func _end_pour() -> void:
	if _pour and is_instance_valid(_pour):
		_pour.queue_free()
	_pour = null
	if not _bounty.is_empty() and is_instance_valid(_bounty["coin"]):
		(_bounty["coin"] as Control).modulate = Color.WHITE


## The purse line's flourish as the bounty lands: it swells to BOUNTY_LINE_POP about its left middle and back, flashing
## gold and coming back to its own colour.
func _flourish_line() -> void:
	if _after_line == null:
		return
	if _line_tw and _line_tw.is_valid():
		_line_tw.kill()
	var sp := maxf(_speed, 1.0)
	_after_line.pivot_offset = Vector2(0.0, _after_line.size.y * 0.5)
	if _line_base.a <= 0.0:
		_line_base = _after_line.color
	_after_line.color = R.GOLD_TEXT
	_after_line.modulate = Color(1.4, 1.3, 1.1, 1.0)
	_line_tw = create_tween()
	_line_tw.tween_property(_after_line, "scale", Vector2.ONE * BOUNTY_LINE_POP, 0.1 / sp).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_line_tw.tween_property(_after_line, "scale", Vector2.ONE, 0.32 / sp).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_line_tw.parallel().tween_property(_after_line, "modulate", Color.WHITE, 0.5 / sp)
	_line_tw.parallel().tween_property(_after_line, "color", _line_base, 0.4 / sp).set_delay(0.15 / sp)


## The purse line at rest (a skip).
func _rest_line() -> void:
	if _line_tw and _line_tw.is_valid():
		_line_tw.kill()
	_line_tw = null
	if _after_line:
		_after_line.scale = Vector2.ONE
		_after_line.modulate = Color.WHITE
		if _line_base.a > 0.0:
			_after_line.color = _line_base


## The chart block pops in once the gold is counted (pass 74): the panel from POP_FROM of its size past its size and
## back, fading in; the section labels and the rows that come in at the chart part's very start (the starting weapon's)
## fade in with it.
func _part_pop(f: float, live: bool) -> void:
	if live and not _popped:
		_popped = true
		W.sfx("ui_card")
	var a := 1.0 if f >= 1.0 else clampf(f / POP_FADE, 0.0, 1.0)
	if f >= 1.0:
		_land_pop()
	elif is_instance_valid(_pop_group):
		_pop_group.scale = Vector2.ONE * lerpf(POP_FROM, 1.0, back_out(f, POP_BACK))
		_pop_group.self_modulate.a = a
	_perf_label.modulate.a = a
	if _dmg_label:
		_dmg_label.modulate.a = a
	if _dmg_panel:
		_dmg_panel.modulate.a = a
	for e: Dictionary in _rows:
		if float(e["at"]) <= 0.0:
			e["on"] = true
			(e["row"] as Control).modulate.a = a


## An ease-out-back: 0 to 1 past 1 and back (`c1` the overshoot's strength; 1.70158 the usual 10 %).
static func back_out(f: float, c1: float) -> float:
	var t := clampf(f, 0.0, 1.0)
	return 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


## The chart part (pass 74: everything on one clock): the line drawn across `x` of the run in JOINT_TIME, its marks as
## it reaches them, the counters at what the run had reached by then, and each source row once the clock passes its
## moment (`at`), fading in, its bar, number and percent at its damage so far at `x` (_row_damage).
func _part_chart(f: float, live: bool) -> void:
	var clock := f * _joint_time
	var x := 1.0 if f >= 1.0 else clampf(clock / JOINT_TIME, 0.0, 1.0)
	if not live and f >= 1.0:
		_chart.finish()
	else:
		_chart.head = x
	var k: float = _tl.value_at(_kill_curve, float(_kills_total), x) if not _tl.is_empty() else float(_kills_total) * x
	var d: float = _tl.value_at(_tl.damage, _dmg_total, x) if not _tl.is_empty() else _dmg_total * x
	_kills_num.text = short_num(k)
	_dmg_num.text = short_num(d)
	for e: Dictionary in _rows:
		var at := float(e["at"])
		if f < 1.0 and clock < at:
			continue
		if not bool(e["on"]):
			e["on"] = true
			if live:
				W.sfx("ui_card")
				_follow_into(e["row"])
		var row: Control = e["row"]
		row.modulate.a = 1.0 if f >= 1.0 else maxf(row.modulate.a, clampf((clock - at) / ROW_FADE, 0.0, 1.0))
		_fill_row(e, _row_damage(e, x))


## A source row's damage so far when the line stands at `x` of the run: each of its ids' own samples
## (RunTimeline.source_damage_at), else (a run with no story, an id the record never sampled) the id's damage spread
## evenly from the row's own moment (`from`) to the end. At the end every row stands at its whole damage.
func _row_damage(e: Dictionary, x: float) -> float:
	var at := x * _tl.length()
	var from := float(e["from"])
	var sum := 0.0
	for pair in e["ids"]:
		var fin := float(pair[1])
		var v := _tl.source_damage_at(str(pair[0]), at, fin)
		if v < 0.0:
			v = fin if x >= 1.0 or from >= 1.0 else fin * clampf((x - from) / (1.0 - from), 0.0, 1.0)
		sum += v
	return sum


func _on_mark_popped(kind: int) -> void:
	if _seq != 1 or Time.get_ticks_msec() - _mark_ms < 60:
		return
	_mark_ms = Time.get_ticks_msec()
	W.sfx("ui_locked" if kind == RunTimeline.KIND_DOWN else ("ui_card_pick" if kind == RunTimeline.KIND_BOSS else "ui_reel_tick"))


## A source row at `dmg` dealt so far: its bar and its percent against the run's final total (so a bar only grows, and
## ends on its share), its number.
func _fill_row(e: Dictionary, dmg: float) -> void:
	var frac := clampf(dmg / maxf(_dmg_total, 1.0), 0.0, 1.0)
	var bar: WBar = e["bar"]
	if bar:
		bar.value = frac
	var amt: WText = e["amount"]
	if amt:
		amt.text = W.num(dmg)
	var sh: WText = e["share"]
	if sh:
		var pct := roundf(frac * 100.0)
		sh.text = "<1%" if frac > 0.0 and pct < 1.0 else "%d%%" % int(pct)


## The board down to the unlocks (eased); a skip puts it there at once.
func _part_scroll(f: float, _live: bool) -> void:
	if _scroll_from < 0.0:
		_scroll_from = float(scroll.scroll_vertical)
		_follow = -1.0
	var to := _unlock_target()
	scroll.scroll_vertical = int(round(lerpf(_scroll_from, to, smoothstep(0.0, 1.0, f))))


## Where the board stands to show the unlocks: their label near the top of the view, as far as the board goes.
func _unlock_target() -> float:
	if _unlock_box == null:
		return 0.0
	var y := _content_y(_unlock_box) - 40.0
	return clampf(y, 0.0, _max_scroll())


## Unlock k lands: its panel fades in (its plate a silhouette), at STAMP_AT its art shows, the panel flashes, the
## UNLOCKED stamp slams down and a burst goes off over its plate.
func _part_unlock(f: float, live: bool, k: int) -> void:
	var e: Dictionary = _unlocks[k]
	var panel: Control = e["panel"]
	if _unlock_label:
		_unlock_label.modulate.a = 1.0
	if panel.modulate.a <= 0.0 and live:
		_follow_into(panel)
	panel.modulate.a = maxf(panel.modulate.a, clampf(f / 0.2, 0.0, 1.0))
	if f >= STAMP_AT and not bool(e["landed"]):
		e["landed"] = true
		var plate: WPlate = e["plate"]
		if plate:
			plate.locked = false
			plate.queue_redraw()
		var stamp: WStamp = e["stamp"]
		stamp.visible = true
		stamp.slam(0.16 / _speed if live else 0.0)
		if live:
			panel.modulate = Color(1.7, 1.7, 1.6, 1.0)
			create_tween().tween_property(panel, "modulate", Color.WHITE, 0.45 / _speed)
			if plate and plate.is_inside_tree():
				WCelebrate.burst(self, plate.get_global_rect().get_center(), get_child_count())
			W.sfx("ui_stamp")
			W.sfx("ui_unlock")
	if f >= 1.0:
		panel.modulate = Color.WHITE


## The bars of the unlocks brought closer, one after another from where each stood to where it stands.
func _part_progress(f: float, live: bool) -> void:
	if _progress_label:
		_progress_label.modulate.a = 1.0
	var step := row_step(_progress.size(), PROGRESS_STEP, PROGRESS_FILL, PROGRESS_MAX)
	var at := f * _progress_time()
	for k in _progress.size():
		var e: Dictionary = _progress[k]
		var local := clampf((at - float(k) * step) / PROGRESS_FILL, 0.0, 1.0) if f < 1.0 else 1.0
		if local <= 0.0 and not bool(e["on"]):
			continue
		if not bool(e["on"]):
			e["on"] = true
			if live:
				W.sfx("ui_reel_tick")
				_follow_into(e["row"])
		(e["row"] as Control).modulate.a = maxf((e["row"] as Control).modulate.a, clampf(local * 4.0, 0.0, 1.0))
		_fill_progress(e, _ease_out(local))


func _fill_progress(e: Dictionary, k: float) -> void:
	var need := float(e["need"])
	var b := float(e["before"]) / need
	var now := lerpf(float(e["before"]), float(e["after"]), k)
	var bar: WBar = e["bar"]
	bar.value = now / need
	bar.gain = maxf(now / need - b, 0.0)
	(e["count"] as WText).text = "%s / %s" % [W.num(now), W.num(need)]


# ---------------------------------------------------------------- the clock, the taps, the board

func _process(delta: float) -> void:
	super._process(delta)
	_tick_follow(delta)
	if _seq <= 0 or _seq >= DONE:
		return
	_pt += delta * _speed
	while _part < _parts.size():
		var p: Dictionary = _parts[_part]
		var dur := float(p["dur"])
		if _pt < 0.0:
			return
		var f := 1.0 if dur <= 0.0 else minf(_pt / dur, 1.0)
		(p["fn"] as Callable).call(f, true)
		if f < 1.0:
			return
		_pt -= dur
		_part += 1
		if _part >= _parts.size():
			_finish()
			return
		if int(_parts[_part]["seq"]) != _seq:
			# a new sequence starts at its own pace, its taps from nothing
			_seq = int(_parts[_part]["seq"])
			_speed = 1.0
			_taps = 0
			_pt = 0.0
			return


## A tap: the first hurries the sequence playing, the second ends it.
func tap() -> void:
	if _seq <= 0 or _seq >= DONE:
		return
	_taps += 1
	if _taps == 1:
		_speed = SPEED_UP
	else:
		skip_sequence()


## The sequence playing jumps to its end (no sounds, no bursts); the next one starts from its beginning.
func skip_sequence() -> void:
	var seq := _seq
	while _part < _parts.size() and int(_parts[_part]["seq"]) == seq:
		(_parts[_part]["fn"] as Callable).call(1.0, false)
		_part += 1
	_pt = 0.0
	_speed = 1.0
	_taps = 0
	if seq == 1:
		# the first sequence's own easing of the board stops where it stands
		_follow = -1.0
	if _part >= _parts.size():
		_finish()
	else:
		_seq = int(_parts[_part]["seq"])


## Everything shown as it ends: both sequences skipped (tests, tools).
func skip_all() -> void:
	while _seq > 0 and _seq < DONE:
		skip_sequence()


## Which sequence plays (1, 2), 3 when the show is over; 0 before it starts.
func sequence() -> int:
	return _seq


func speed() -> float:
	return _speed


## The part playing ("gold", "pop", "chart" (pass 74: the line, its marks, both counters and the sources together),
## "pause", "scroll", "unlock", "progress"; "" when none) and how far it has come (0..1): the captures wait on it.
func part_name() -> String:
	return str(_parts[_part]["name"]) if _seq > 0 and _seq < DONE and _part < _parts.size() else ""


func part_frac() -> float:
	if _seq <= 0 or _seq >= DONE or _part >= _parts.size():
		return 1.0
	var dur := float(_parts[_part]["dur"])
	return 1.0 if dur <= 0.0 else clampf(_pt / dur, 0.0, 1.0)


## How long the whole show lasts at normal speed (both sequences, the lead-in counted).
func show_time() -> float:
	var t := LEAD_IN
	for p: Dictionary in _parts:
		t += float(p["dur"])
	return t


func _finish() -> void:
	_seq = DONE
	_speed = 1.0
	_follow = -1.0
	# pass 137 (lane TUTOR): the show is over: UPGRADE wakes and, while the tutorial asks, is highlighted
	_upgrade_after_show()
	_offer_survey(_run_time)


## The finger while the show plays: a lift anywhere but on a button is a tap (a drag too: the board does not move, so a
## finger that tries to scroll is in a hurry); the board's own scrolling waits for the end. Once the show is over the
## board scrolls under a finger as every menu does (ScreenBase).
func _input(event: InputEvent) -> void:
	if _seq >= DONE or _seq <= 0:
		super._input(event)
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_id < 0:
			_touch_id = t.index
			_touch_on_button = _on_button(t.position)
		elif not t.pressed and t.index == _touch_id:
			_touch_id = -1
			if not _touch_on_button:
				tap()
	elif event is InputEventScreenDrag:
		# no list under the finger moves the board either (a ScrollContainer can drag by itself on a touch screen)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			get_viewport().set_input_as_handled()


func _on_button(at: Vector2) -> bool:
	for n in find_children("*", "Control", true, false):
		if n is WTap and (n as Control).is_visible_in_tree() and (n as Control).get_global_rect().has_point(at):
			return true
	return false


## The board eases down so `c` stands whole above the buttons (the show's own scrolling; never up).
func _follow_into(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	var bottom := _content_y(c) + c.size.y + 24.0
	var need := clampf(bottom - scroll.size.y, 0.0, _max_scroll())
	if need > maxf(float(scroll.scroll_vertical), _follow):
		_follow = need


func _tick_follow(delta: float) -> void:
	if _follow < 0.0:
		return
	var now := float(scroll.scroll_vertical)
	var to := minf(_follow, _max_scroll())
	if absf(to - now) < 1.5:
		scroll.scroll_vertical = int(round(to))
		return
	scroll.scroll_vertical = int(round(lerpf(now, to, clampf(delta * 9.0 * maxf(_speed, 1.0), 0.0, 1.0))))


## A control's top in the board's own coordinates (0 = the board's top, whatever the scroll).
func _content_y(c: Control) -> float:
	return c.get_global_rect().position.y - margin.get_global_rect().position.y


func _max_scroll() -> float:
	return maxf(margin.size.y - scroll.size.y, 0.0)


static func _ease_out(f: float) -> float:
	var t := clampf(f, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)


## A count kept short (pass 72, Garry: "We shorten the big numbers here into 1.2m for 1.2 million, and 20k for 20000"):
## under 1,000 as it is, then thousands (k), millions (m) and billions (b), one decimal under 10 (dropped when it is
## .0), none from 10 up; always rounded down, so a counter never shows more than it has reached.
static func short_num(n: float) -> String:
	var v := absf(n)
	var neg := "-" if n < 0.0 else ""
	if v < 1000.0:
		return neg + str(int(floor(v)))
	for unit in [[1e9, "b"], [1e6, "m"], [1e3, "k"]]:
		var u := float(unit[0])
		if v >= u:
			var x := v / u
			var s := ""
			if x < 10.0:
				var tenth := floorf(x * 10.0 + 0.0001) / 10.0
				s = str(int(tenth)) if is_equal_approx(tenth, floorf(tenth)) else "%.1f" % tenth
			else:
				s = str(int(floor(x)))
			return neg + s + str(unit[1])
	return neg + str(int(floor(v)))


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
		return {"key": "source:" + str(spec[1]), "name": Loc.t(str(spec[1])), "def": null, "icon": icon}
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


## The damage sources, one a source (the ids that are one source summed), in the order they joined the run (pass 72):
## the starting weapon first, then each at the moment it was first owned, else first hit (RunTimeline.joined); a run
## with no story (a tool's, a test's) biggest first. Each source dict gains "amount", "at" (its moment in the run's
## seconds; -1 the starting weapon, INF never seen) and "ids" ([[id, its damage]], pass 74: the row's bar follows them).
static func ordered_sources(dmg: Dictionary, tl: RunTimeline) -> Array:
	var by_key: Dictionary = {}
	for id in dmg.keys():
		var amount := float(dmg[id])
		var src := damage_source(str(id))
		var k := str(src["key"])
		var at := INF
		if tl:
			at = -1.0 if tl.start_weapon != "" and str(id) == tl.start_weapon else tl.joined(str(id))
		if by_key.has(k):
			by_key[k]["amount"] = float(by_key[k]["amount"]) + amount
			by_key[k]["at"] = minf(float(by_key[k]["at"]), at)
			(by_key[k]["ids"] as Array).append([str(id), amount])
		else:
			src["amount"] = amount
			src["at"] = at
			src["ids"] = [[str(id), amount]]
			by_key[k] = src
	var out: Array = by_key.values()
	out.sort_custom(func(a, b):
		if float(a["at"]) != float(b["at"]):
			return float(a["at"]) < float(b["at"])
		return float(a["amount"]) > float(b["amount"]))
	return out


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
	return _damage_row_royale(src, frac)


## Pass 123 (lane RUN_A): one source under Royale (the mock's DAMAGE DEALT row): a 72 px frame, the name in white Rubik
## 700 and the damage in gold Ultra over a gold bar of its share, the percent in cream Ultra beside it. The same names
## ("Source", "Name", "Amount", "Bar", "Share") and the plate first.
static func _damage_row_royale(src: Dictionary, frac: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Source"
	h.set_meta("source", src)
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(source_plate(src, ROYALE_ROW_PLATE))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := W.text(str(src["name"]), R.body(R.LABEL_WEIGHT), ROYALE_ROW_PX, R.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	nm.name = "Name"
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var num := W.slab_text(W.num(float(src["amount"])), ROYALE_ROW_PX, W.BRASS, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	num.name = "Amount"
	top.add_child(num)
	mid.add_child(top)
	var bar := WBar.make(frac, W.BRASS, ROYALE_ROW_BAR, 3, 0)
	bar.name = "Bar"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(bar)
	h.add_child(mid)
	var pct := roundf(frac * 100.0)
	var pc := W.slab_text("<1%" if frac > 0.0 and pct < 1.0 else "%d%%" % int(pct), ROYALE_ROW_PX, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	pc.name = "Share"
	pc.custom_minimum_size.x = 92
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


## One unlock: the item's plate (named "Plate"), its name, and what earned it on the right; the stamp over its corner
## says UNLOCKED (FOR SALE on a hero to buy).
func _unlocked(q: QuestDef) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Unlock"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 5, 6).pad(31, 25, 31, 25))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var def := _reward(q)
	# pass 69: a hero to buy is not his yet: on sale, still unknown (his badge black with a "?"); pass 76: only while
	# Registry.hero_state says so (a hero owned already never reads FOR SALE)
	var on_sale := def is CharacterDef and Registry.hero_state(def as CharacterDef) == "buyable"
	# pass 111 (lane SKINS): a look's goal: the look itself, FOR SALE until it is bought (or UNLOCKED when it is free)
	var skin := str(q.unlocks.get("type", "")) == "skin" and def is CharacterDef
	if skin:
		on_sale = Registry.skin_state(def as CharacterDef, (def as CharacterDef).look_code()) == "buyable"
	if def:
		var pl := WPlate.new().for_def(def, ROYALE_UNLOCK_PLATE)
		pl.name = "Plate"
		pl.icon_frac = 0.7
		pl.mystery = on_sale and not skin
		h.add_child(pl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pass 72: the word is the stamp's (UNLOCKED, or FOR SALE on a hero to buy: _build_unlocks)
	p.set_meta("on_sale", on_sale)
	var title := Loc.t("ui.results.new_outlaw") if on_sale else (def.display_name if def else q.display_name)
	if skin:
		title = "%s · %s" % [def.display_name, (def as CharacterDef).skin_name((def as CharacterDef).look_code())]
	var tpx := ROYALE_UNLOCK_PX
	v.add_child(W.slab_text(title, tpx, W.INK, HORIZONTAL_ALIGNMENT_LEFT, float(tpx)))
	h.add_child(v)
	# pass 128: an unlocked weapon that still waits for its outlaw reads "Comes with <name>" (a tap opens his page)
	var giver := CollectionScreen.comes_with(def)
	var why: Control = CollectionScreen.comes_with_line(giver, 24, self, true) if giver 		else W.serif_text(TextGen.quest_text(q), 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, true)
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
		"skin":
			# pass 111 (lane SKINS): the hero in that look
			return Registry.unlocked_by(q)
	return null


func on_back() -> void:
	# the back gesture closes the survey card first ("Not now")
	if is_instance_valid(_survey) and not bool(_survey.call("is_done")):
		_survey.call("dismiss")
		return
	go(TITLE)


## Asks Analytics whether this run brings a survey (pass 59: at most one every few runs of a minute or more, never in a
## run's first minute, never twice a session, never after "Don't ask me again") and opens it after a beat (pass 72: once
## the show is over).
func _offer_survey(run_seconds: float) -> void:
	var sv: Dictionary = Analytics.survey_after_run(run_seconds)
	if sv.is_empty():
		return
	await get_tree().create_timer(SURVEY_DELAY).timeout
	if not is_inside_tree():
		return
	_survey = WSurveyScript.open(self, sv)


## The head's stage story (pass 87, lane SUI; Garry: a stage run ends at its boss, then the portal's minute, then
## Endless): `star` how it ended (Extracted, Fell in Endless, Run over: Run.outcome), `stage` the stage by number and name
## with "Beaten" once its boss died (Run.stage_beaten), `tone` the stage's colour (StagesScreen.tone), `time` the run's
## time (Run.summary's, every second played, as the best runs count it), `endless` the time survived in Endless and its
## waves ("" when it never started).
static func stage_story() -> Dictionary:
	var i := maxi(Run.stage, 0)
	var list: Array = StagesScreenScript.entries(Run.map) if Run.map else []
	var e: Dictionary = list[i] if i < list.size() else {}
	var out := Run.outcome()
	var beaten := Run.stage_beaten or Run.extracted or Run.endless
	var star := Loc.t("ui.results.star.run_over")
	if out == "extracted":
		star = Loc.t("ui.results.star.extracted")
	elif out == "died_endless" and Run.died:
		star = Loc.t("ui.results.star.fell_in_endless")
	var parts: Array = [Loc.t("ui.results.stage", {"stage": "%d" % (i + 1)})]
	var nm := str(e.get("name", ""))
	if nm != "" and nm != Loc.t("ui.results.stage", {"stage": "%d" % (i + 1)}):
		parts.append(nm)
	if beaten:
		parts.append(Loc.t("ui.results.beaten"))
	var endless := ""
	if Run.endless:
		endless = Loc.t("ui.results.endless_time", {"time": W.mmss(Run.endless_time)})
		var wave := Run.endless_wave()
		if wave > 0:
			endless += " " + Loc.t("ui.results.endless_wave", {"wave": "%d" % wave})
	return {"star": star, "stage": " · ".join(parts), "tone": StagesScreenScript.tone(list, i) if not list.is_empty() else W.INK_SOFT,
		"time": Run.run_time(), "endless": endless, "beaten": beaten}


# ---------------------------------------------------------------- UPGRADE and the Trail's first steps (pass 137, lane TUTOR)

const WHighlightScript := preload("res://ui/wanted/WHighlight.gd")
## The UPGRADE button (named "Upgrade") and its highlight while the tutorial asks for it.
var upgrade_btn: WButton
var upgrade_highlight: Control


## Garry: "After the first run the Results screen, only once its whole sequence (data, unlock progress) is done, shows a
## big fat highlight of the Upgrade button; during the sequence the button is greyed out or not there; this plays every
## Results until the Player first taps Upgrade." While Save's step upgrade_tapped is open, UPGRADE is grey and does
## nothing through the show (_finish wakes it, a skip too); with the Trail closed (no run counted: a tool's Results) it
## stays grey and says ui_locked. Otherwise it is the Trail's way in from the start, as before.
func _upgrade_button(b: WButton) -> void:
	b.name = "Upgrade"
	upgrade_btn = b
	b.locked = not Save.trail_open() or not Save.tutorial_done("upgrade_tapped")
	b.pressed.connect(_on_upgrade)


func _on_upgrade() -> void:
	if upgrade_btn == null or upgrade_btn.locked:
		if not Save.trail_open():
			W.sfx("ui_locked")
		return
	if not Save.tutorial_done("upgrade_tapped"):
		Save.mark_tutorial("upgrade_tapped")
	if upgrade_highlight and is_instance_valid(upgrade_highlight):
		upgrade_highlight.call("stop")
	upgrade_highlight = null
	go(Nav.TRAIL)


## The show's end (_finish): UPGRADE wakes, highlighted while the tutorial still waits for its first tap.
func _upgrade_after_show() -> void:
	if upgrade_btn == null or not Save.trail_open():
		return
	upgrade_btn.locked = false
	if Save.tutorial_done("upgrade_tapped") or (upgrade_highlight and is_instance_valid(upgrade_highlight)):
		return
	upgrade_highlight = WHighlightScript.attach(upgrade_btn, self)


## Whether UPGRADE is highlighted now (tests, tools).
func upgrade_highlighted() -> bool:
	return upgrade_highlight != null and is_instance_valid(upgrade_highlight) and bool(upgrade_highlight.call("is_on"))
