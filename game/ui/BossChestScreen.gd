## The boss chest's pop-up (pass 118, lane BOSSCHEST; Garry: "Each Boss Chest unlocks with a visual sequence presented
## in a pop-up. This sequence shows the chest opening and gold and exp flying out of it with increasing speed (kind of
## like chests in Vampire Survivors, except here it's both EXP and Coins at the same time). The faster the Boss was killed
## the more Gold and Exp flies out. The coin count is communicated with a counter at the bottom. Same with exp. All the
## while a jackpot like slot machine tune plays ... At the end of the sequence Player has to tap a Claim button. Make this
## whole sequence like a big ol celebration").
## The beats, one clock (`_t`, advance): the world dims, the boss's chest (its three paintings, BossChest.paintings: drawn
## in its light's colour until they exist) drops onto the middle of the screen with a thud, rattles harder with each of
## four knocks, cracks its lid on a line of light (the shine grows in behind it), then bursts open: a white flash, the
## screen shakes, a strong burst of rays and scraps, "BOSS LOOT!" slams in and the jackpot tune starts (TUNE, a loop
## whose pitch climbs with the spew). Coins and XP gems fly out of the open chest in arcs and dive into their counters at
## the bottom (gold with the coin, XP with a gem), slowly at first, faster and faster (RATE_LIN: a cubic rate), each one
## counted as it lands with its ding; the banner climbs BIG WIN!, HUGE WIN!, MEGA WIN! with a burst each, and coins start
## raining down the screen. When the last one lands: JACKPOT!, bursts over both counters, the jackpot sting, and CLAIM
## pops in. The speed bonus sits under the title: its multiplier, the kill's time and a gauge from x1 to the map's top.
## A faster kill pays more (the pack) and spews longer (SPEW_MIN to SPEW_MAX by the bonus).
## The numbers are the hero's real ones: the pack's net gold and XP (BossChest.net: greed and Field Notes in), split into
## the pieces' shares so the counters end exactly on them, and exactly what the pickups pay after CLAIM (Game).
## A tap before the burst goes straight to it; a tap during the spew hurries the rest into HURRY seconds (hurry); CLAIM
## (claim) closes and Game pays out. A tool claims at once (claim finishes the count first). Raw touch and the mouse both
## tap (the button is a WButton); RunReplay records the hurry and the claim.
## Pass 123 (lane RUN_B), under Royale: the mock 8_Boss_chest with Garry's
## note ("Boss chest as the mock: speed bonus panel, the painted chest and loot party kept, GOLD and EXP panels, CLAIM in
## gold"; "Header text white"): "★ BOSS CHEST ★" in the kit's gold over the boss's chest's name in cream Ultra (fitted);
## the SPEED BONUS a slate panel across the screen (ROYALE_SIDE in, ROYALE_METER_Y down, ROYALE_METER_H tall): the label,
## "Killed in" with the time in bold white at its right, the multiplier gold Ultra with the bevel (secondary blue at x1),
## the kit's gold bar from x1 to the map's top with its two ends under it; the chest, its light, the shine and the loot
## party as before; the banner (BOSS LOOT! .. JACKPOT!) gold Ultra with the navy edge, the bevel and the drop; GOLD and
## EXP slate panels (ROYALE_GAP apart, as wide as the meter between them) with the label, the kit's coin or the purple
## gem, and the count big in gold Ultra; CLAIM the kit's gold. The beats, the counts and the timings are as before.
class_name BossChestScreen
extends WModal

signal claimed

const WShineScript := preload("res://ui/wanted/WShine.gd")
## the jackpot tune (a loop) and the knocks' thud
const TUNE := "ui_bosschest_tune"
const KNOCK := "ui_chest_knock"
const KNOCK_FALLBACK := "en_golem_hit"
## The beats (s on the screen's clock): landed, the four knocks, the lid cracks, it bursts, the spew starts.
const DROP := 0.32
const KNOCKS := [0.56, 0.84, 1.08, 1.28]
const CRACK := 1.44
const BURST := 1.9
const SPEW_AT := 2.05
## The spew's length with no bonus and with the whole bonus (between by the bonus).
const SPEW_MIN := 3.4
const SPEW_MAX := 5.4
## After the last piece lands: the finale (JACKPOT!), then CLAIM.
const FINALE := 0.2
const CLAIM_AFTER := 0.75
## A tap during the spew: the rest of it in this many seconds.
const HURRY := 0.9
## The pieces that fly: about one coin per UI_GOLD of gold and one gem per UI_XP of XP, within UI_MIN..UI_MAX of each.
const UI_GOLD := 8.0
const UI_XP := 22.0
const UI_MIN := 18
const UI_MAX := 130
## The spew's rate: by u of its length, RATE_LIN u + (1 - RATE_LIN) u^3 of the pieces are out (a trickle that swells).
const RATE_LIN := 0.12
## A piece's flight at the spew's start and at its end (the late ones fly quicker too).
const FLIGHT := Vector2(1.0, 0.62)
## The chest: its width, its foot as a share of the screen's height, the open chest's mouth over its foot as a share
## of its width.
const CHEST_W := 600.0
const CHEST_FOOT := 0.62
const MOUTH_UP := 0.5
## The counters at the bottom, over the CLAIM row, and the banner between them and the chest.
const COUNTER_H := 178.0
const BUTTON_H := 132.0
const BANNER_PX := 118
## The banner's words by the share of the pieces landed (the last one: JACKPOT at the finale).
const WORDS := [[0.0, "ui.boss_chest.word.loot"], [0.3, "ui.boss_chest.word.big"], [0.6, "ui.boss_chest.word.huge"], [0.88, "ui.boss_chest.word.mega"]]
const JACKPOT_KEY := "ui.boss_chest.word.jackpot"
const WORD_COLOURS := [Color("f3e6c8"), Color("f6d75e"), Color("ffb347"), Color("ff7a4a"), Color("ffe066")]
## The gems' colours (PickupManager's small, medium and large) and the coin's painting.
const GEM_COLOURS := [Color(0.4836, 0.3744, 0.78), Color(0.351, 0.663, 0.78), Color(0.78, 0.429, 0.663)]
const COIN_ART := "res://art/ui/wanted/coin.png"
const COIN_PX := 64.0
## the run's music under the tune (dB)
const MUSIC_DUCK := -14.0
const GEM_PX := 30.0
## Pass 119, the party (Garry: "All Boss Chest sequences need more coins floating and other floating stuff"): loot that only
## celebrates, counted nowhere, drawn under the title, the speed bonus, the banner, the counters and CLAIM (never over them).
## The fountain: loot thrown up out of the mouth from the burst to the last landing, falling past the chest; FOUNTAIN_N
## pieces, FOUNTAIN_BONUS more at the top speed bonus, the first FOUNTAIN_POP of them in the burst itself; after the last
## landing FOUNTAIN_LOOP pieces keep it going until CLAIM, each thrown again every FOUNTAIN_LOOP_S seconds.
const FOUNTAIN_N := 120
const FOUNTAIN_BONUS := 60
const FOUNTAIN_POP := 36
const FOUNTAIN_LOOP := 16
const FOUNTAIN_LOOP_S := 1.6
const FOUNTAIN_G := 2300.0
## The drift: DRIFT_N pieces rising slowly up the screen with a sway from the burst on, round and round until CLAIM.
const DRIFT_N := 40
## The twinkles round the open chest.
const TWINKLE_N := 14
## The loot's kinds: a coin, an XP gem, a poker chip, a banknote, a scrap of a Wanted poster, a brass star.
enum Loot { COIN, GEM, CHIP, NOTE, SCRAP, STAR }
## the fountain's and the drift's mixes, by Loot
const FOUNTAIN_MIX := [0.5, 0.25, 0.1, 0.05, 0.0, 0.1]
const DRIFT_MIX := [0.15, 0.1, 0.2, 0.22, 0.18, 0.15]
const CHIP_COLOURS := [Color("b4472b"), Color("3e6e9e"), Color("241b14"), Color("6e8b5e")]
## Pass 123 (lane RUN_B), the Royale layout (the mock 8_Boss_chest, canvas px): the panels' side margin and the gap between
## GOLD and EXP; the speed bonus panel's top (under the header, + the cutout) and height, its padding, where its bar starts
## and how tall it is; the label, the time, the multiplier's and the bar ends' type; a counter's label, icon and number.
const ROYALE_SIDE := 48.0
const ROYALE_GAP := 30.0
const ROYALE_METER_Y := 300.0
const ROYALE_METER_H := 172.0
const ROYALE_PAD := 32.0
const ROYALE_BAR_X := 144.0
## pass 128: the least room between the multiplier's right edge and the bar's left end (meter_bar_x)
const ROYALE_MULT_GAP := 24.0
const ROYALE_BAR := Vector2(62.0, 26.0)
const ROYALE_LABEL_PX := 22
const ROYALE_TIME_PX := 28
const ROYALE_MULT_PX := 72
const ROYALE_END_PX := 20
const ROYALE_COUNT_PX := 76
const ROYALE_COUNT_SMALL_PX := 60
const ROYALE_COIN_PX := 76.0
## the counter's icon (as the flying pieces aim at it: 74 px in, 58 % down) and its number's left edge
const ROYALE_ICON_X := 74.0
const ROYALE_NUM_X := 136.0
const NOTE_GREEN := Color("b9cf98")
const NOTE_INK := Color("4e6b3a")

var boss_id := ""
var pack: Dictionary = {}
var gold_total := 0
var xp_total := 0.0
var shine := W.BRASS
var look: Dictionary = {}
var _frames: Array = []
var _coin_tex: Texture2D
var _t := 0.0
var _speed := 1.0
var _spew_len := SPEW_MIN
var _bonus_k := 0.0
var _end_t := 0.0
## the pieces: {emit, flight, coin, share, p0, p1, p2, spin, gem, done}
var _pieces: Array = []
var _landed := 0
var _gold_target := 0.0
var _xp_target := 0.0
var _gold_shown := 0.0
var _xp_shown := 0.0
var _gold_bump := 0.0
var _xp_bump := 0.0
var _word := ""
var _word_k := -1
var _word_t := -10.0
## a ding's sparkle at a counter: [t0, pos, colour]
var _sparks: Array = []
## the coins raining at the end: [t0, x, speed, spin, size]
var _rain: Array = []
## pass 119, the party: the fountain [t0, x0, y0, vx, vy, spin, spin_v, size, kind, sub, life, loop (s, 0: once)], the drift [t0, x0, y0,
## speed, sway, freq, phase, size, kind, sub, period, spin_v] and the twinkles [x, y, period, phase, size]
var _fountain: Array = []
var _drift: Array = []
var _twinkles: Array = []
var _party: Control
var _party_rng := RandomNumberGenerator.new()
var _shake := 0.0
var _done := false
var _claiming := false
var _said: Dictionary = {}
var _quiet := false
var _ducked := false
var _seek_to := -1.0
var _rng := RandomNumberGenerator.new()
## the layers: the shine, the rays and the chest shake together (_stage); the rest stays still
var _stage: Control
var _shine: Control
var _rays: Control
var _chest: Control
var _meter: Control
var _banner: Control
var _counters: Control
var _fx: Control
var _flash: ColorRect
var _claim_btn: WButton
## the layout for the open screen (px)
var _vp := Vector2(1080, 1920)
var _foot := Vector2(540, 1190)
var _mouth := Vector2(540, 890)
var _gold_rect := Rect2()
var _xp_rect := Rect2()
var _banner_y := 1330.0
var _meter_rect := Rect2()


func _ready() -> void:
	build_dim(Color(0.07, 0.04, 0.02, 0.9))
	_stage = _layer(self, Callable())
	_shine = WShineScript.make(Vector2(540, 890), 560)
	_shine.name = "Shine"
	(_shine as WShineScript).put(_stage)
	_shine.visible = false
	_rays = _layer(_stage, _draw_rays)
	_chest = _layer(_stage, _draw_chest)
	# pass 119: the party over the chest and under everything that reads (the title, the meter, the banner, the counters)
	_party = _layer(self, _draw_party)
	# pass 123, Royale: the header's words cream (Garry: "Header text white"), set again with the boss's name on open
	build_header(Loc.t("ui.boss_chest.star"), Loc.t("ui.boss_chest.title"), "", 128, W.PAPER)
	_meter = _layer(self, _draw_meter)
	_banner = _layer(self, _draw_banner)
	_counters = _layer(self, _draw_counters)
	build_buttons(BUTTON_H)
	_claim_btn = WButton.make([Loc.t("ui.boss_chest.claim")], 62, WButton.PRIMARY, 6, 10, 30.0, 0.0)
	_claim_btn.name = "Claim"
	_claim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_claim_btn.pressed.connect(_on_claim)
	buttons.add_child(_claim_btn)
	buttons.visible = false
	_fx = _layer(self, _draw_fx)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	if ResourceLoader.exists(COIN_ART):
		_coin_tex = load(COIN_ART) as Texture2D
	set_process(false)


func _layer(host: Control, painter: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if painter.is_valid():
		c.draw.connect(painter)
	host.add_child(c)
	return c


## Opens on boss `id`'s chest holding `p` (BossChest.net: gold_net and xp_net are what it counts up to).
func open(id: String, p: Dictionary) -> void:
	boss_id = id
	pack = p
	gold_total = maxi(int(p.get("gold_net", 0)), 0)
	xp_total = maxf(float(p.get("xp_net", 0.0)), 0.0)
	look = BossChest.look(id)
	shine = look["shine"]
	_frames = BossChest.paintings(id)
	_vp = get_viewport_rect().size
	_layout()
	header.set_title_fit(str(look["name"]).to_upper(), 128, W.PAPER, _vp.x - 96.0)
	# (Royale: the star line the kit's gold, as every star line over a modal)
	header.set_star(Loc.t("ui.boss_chest.star"), W.BRASS)
	header.set_line("")
	(_shine as WShineScript).tint(shine)
	(_shine as WShineScript).color2 = W.LINE_YELLOW
	(_shine as WShineScript).center = _mouth
	(_shine as WShineScript).radius = 560.0
	_shine.visible = false
	_t = 0.0
	_speed = 1.0
	_done = false
	_claiming = false
	_said = {}
	_landed = 0
	_gold_target = 0.0
	_xp_target = 0.0
	_gold_shown = 0.0
	_xp_shown = 0.0
	_gold_bump = 0.0
	_xp_bump = 0.0
	_word = ""
	_word_k = -1
	_word_t = -10.0
	_sparks.clear()
	_shake = 0.0
	_flash.color.a = 0.0
	_stage.position = Vector2.ZERO
	modulate.a = 1.0
	buttons.visible = false
	_build_pieces()
	_build_rain()
	_build_party()
	enter()
	set_process(true)
	_redraw()


## Where everything sits on this screen (a 1080-wide design, centred; the chest and the counters by the height).
func _layout() -> void:
	var cx := _vp.x * 0.5
	_foot = Vector2(cx, roundf(_vp.y * CHEST_FOOT))
	_mouth = _foot - Vector2(0.0, CHEST_W * MOUTH_UP)
	var bottom := _vp.y - 90.0 - BUTTON_H - 34.0
	# pass 123: the mock's panels: the meter across the screen under the header, GOLD and EXP as wide as it between them
	# (pass 128: the Wanted layout's rects that these overwrote are gone; the banner's height is the same sum as before)
	var w2 := (_vp.x - 2.0 * ROYALE_SIDE - ROYALE_GAP) * 0.5
	_gold_rect = Rect2(ROYALE_SIDE, bottom - COUNTER_H, w2, COUNTER_H)
	_xp_rect = Rect2(_vp.x - ROYALE_SIDE - w2, bottom - COUNTER_H, w2, COUNTER_H)
	_banner_y = (_foot.y + _gold_rect.position.y) * 0.5 + 6.0
	_meter_rect = Rect2(ROYALE_SIDE, W.safe_top() + ROYALE_METER_Y, _vp.x - 2.0 * ROYALE_SIDE, ROYALE_METER_H)


## The pieces: the coins and the gems in one shuffled order (the screen's own dice: the run's never move), each sent out at
## its moment of the swelling spew with its share of the totals and its arc from the mouth to its counter.
func _build_pieces() -> void:
	_pieces.clear()
	_rng.seed = hash([boss_id, gold_total, int(xp_total)])
	var tl = Run.map.timeline if Run.map else null
	var top := float(BossChest.config(tl)["max_mult"])
	_bonus_k = clampf((float(pack.get("mult", 1.0)) - 1.0) / maxf(top - 1.0, 0.0001), 0.0, 1.0)
	_spew_len = lerpf(SPEW_MIN, SPEW_MAX, _bonus_k)
	var nc := 0 if gold_total <= 0 else clampi(int(round(float(gold_total) / UI_GOLD)), mini(UI_MIN, gold_total), UI_MAX)
	var ng := 0 if xp_total <= 0.0 else clampi(int(round(xp_total / UI_XP)), UI_MIN, UI_MAX)
	var golds := BossChest.split_int(gold_total, nc)
	var xps := BossChest.split_float(xp_total, ng)
	var order: Array = []
	for k in range(nc):
		order.append(true)
	for k in range(ng):
		order.append(false)
	for k in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var tmp = order[k]
		order[k] = order[j]
		order[j] = tmp
	var n := order.size()
	var ci := 0
	var gi := 0
	_end_t = SPEW_AT
	for idx in range(n):
		var u := _rate_inverse((float(idx) + 0.5) / float(n))
		var coin: bool = order[idx]
		var share: float = float(golds[ci]) if coin else float(xps[gi])
		if coin:
			ci += 1
		else:
			gi += 1
		var target: Rect2 = _gold_rect if coin else _xp_rect
		var p2 := Vector2(target.position.x + 74.0, target.position.y + target.size.y * 0.58) + Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-10.0, 10.0))
		var p0 := _mouth + Vector2(_rng.randf_range(-110.0, 110.0), _rng.randf_range(-10.0, 30.0))
		var side := _rng.randf_range(-1.0, 1.0)
		var p1 := _mouth + Vector2(side * 520.0 + (p2.x - _mouth.x) * 0.35, -_rng.randf_range(560.0, 980.0))
		var fl := lerpf(FLIGHT.x, FLIGHT.y, u) * _rng.randf_range(0.88, 1.12)
		var emit := SPEW_AT + u * _spew_len
		_pieces.append({"emit": emit, "flight": fl, "coin": coin, "share": share, "p0": p0, "p1": p1, "p2": p2,
			"spin": _rng.randf() * TAU, "gem": _rng.randi_range(0, 2), "done": false})
		_end_t = maxf(_end_t, emit + fl)


## The share of the spew `u` at which the share `f` of the pieces is out (F(u) = RATE_LIN u + (1 - RATE_LIN) u^3).
static func _rate_inverse(f: float) -> float:
	var lo := 0.0
	var hi := 1.0
	for k in range(30):
		var mid := (lo + hi) * 0.5
		if RATE_LIN * mid + (1.0 - RATE_LIN) * mid * mid * mid < f:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## The coins raining down the screen from the spew's second half to after CLAIM shows (not counted: the party).
func _build_rain() -> void:
	_rain.clear()
	var t0 := SPEW_AT + _spew_len * 0.55
	var t1 := _end_t + 1.8
	var n := int(round(44.0 + 30.0 * _bonus_k))
	for k in range(n):
		_rain.append([lerpf(t0, t1, float(k) / float(n)) + _rng.randf_range(-0.1, 0.1), _rng.randf_range(30.0, _vp.x - 30.0),
			_rng.randf_range(820.0, 1350.0), _rng.randf() * TAU, _rng.randf_range(0.55, 1.0)])


## Pass 119, the party (its own dice, so the counted pieces and the rain stay as they were): the fountain out of the mouth
## through the spew, the drift rising up the screen until CLAIM, the twinkles round the chest.
func _build_party() -> void:
	_fountain.clear()
	_drift.clear()
	_twinkles.clear()
	_party_rng.seed = hash([boss_id, "party", gold_total])
	var floor_y := _foot.y + 260.0
	var n := FOUNTAIN_N + int(round(float(FOUNTAIN_BONUS) * _bonus_k))
	for k in range(n + FOUNTAIN_LOOP):
		var t0 := BURST + _party_rng.randf_range(0.0, 0.15)
		var loop := 0.0
		if k >= n:
			# the finale's fountain, round and round until CLAIM
			loop = FOUNTAIN_LOOP_S
			t0 = _end_t + FINALE + FOUNTAIN_LOOP_S * float(k - n) / float(FOUNTAIN_LOOP)
		elif k >= FOUNTAIN_POP:
			t0 = SPEW_AT + _rate_inverse((float(k - FOUNTAIN_POP) + 0.5) / float(maxi(n - FOUNTAIN_POP, 1))) * _spew_len
		var ang := -PI * 0.5 + _party_rng.randf_range(-0.95, 0.95)
		var sp := _party_rng.randf_range(900.0, 1550.0) * (1.15 if k < FOUNTAIN_POP else 1.0)
		var v := Vector2.from_angle(ang) * sp
		var x0 := _mouth.x + _party_rng.randf_range(-120.0, 120.0)
		var y0 := _mouth.y + _party_rng.randf_range(-10.0, 40.0)
		# its life: until it has fallen past the chest's foot
		var life := (-v.y + sqrt(v.y * v.y + 2.0 * FOUNTAIN_G * (floor_y - y0))) / FOUNTAIN_G
		var kind := _pick_kind(FOUNTAIN_MIX)
		_fountain.append([t0, x0, y0, v.x, v.y, _party_rng.randf() * TAU, _party_rng.randf_range(-9.0, 9.0),
			_loot_size(kind), kind, _party_rng.randi_range(0, 3), minf(life, loop) if loop > 0.0 else life, loop])
	var top := W.safe_top() + 60.0
	var low := minf(_gold_rect.position.y - 30.0, _foot.y + 220.0)
	for k in range(DRIFT_N):
		# most of them up the sides, past the chest rather than over it
		var x0 := _party_rng.randf_range(40.0, 250.0)
		if k % 2 == 1:
			x0 = _vp.x - x0
		if k % 4 == 3:
			x0 = _party_rng.randf_range(60.0, _vp.x - 60.0)
		var y0 := _party_rng.randf_range(_foot.y - 60.0, low)
		var speed := _party_rng.randf_range(120.0, 230.0)
		var kind := _pick_kind(DRIFT_MIX)
		_drift.append([BURST + 0.15 + float(k) * 0.11, x0, y0, speed, _party_rng.randf_range(24.0, 60.0),
			_party_rng.randf_range(0.35, 0.8), _party_rng.randf() * TAU, _loot_size(kind) * 0.9, kind,
			_party_rng.randi_range(0, 3), (y0 - top) / speed, _party_rng.randf_range(-1.6, 1.6)])
	for k in range(TWINKLE_N):
		var a := _party_rng.randf() * TAU
		var r := sqrt(_party_rng.randf())
		_twinkles.append([_mouth.x + cos(a) * r * 330.0, _mouth.y - 60.0 + sin(a) * r * 230.0, _party_rng.randf_range(0.7, 1.3),
			_party_rng.randf(), _party_rng.randf_range(18.0, 34.0)])


func _pick_kind(mix: Array) -> int:
	var u := _party_rng.randf()
	for i in range(mix.size()):
		u -= float(mix[i])
		if u <= 0.0:
			return i
	return Loot.COIN


func _loot_size(kind: int) -> float:
	match kind:
		Loot.COIN:
			return _party_rng.randf_range(48.0, 72.0)
		Loot.GEM:
			return _party_rng.randf_range(24.0, 36.0)
		Loot.CHIP:
			return _party_rng.randf_range(44.0, 60.0)
		Loot.NOTE:
			return _party_rng.randf_range(84.0, 108.0)
		Loot.SCRAP:
			return _party_rng.randf_range(72.0, 94.0)
	return _party_rng.randf_range(40.0, 58.0)


func _process(delta: float) -> void:
	if not visible or _claiming:
		return
	advance(Lockstep.dt(delta) * _speed)


## The sequence `dt` seconds on: the beats, the landings, the counters rolling, the banner, the finale and CLAIM.
func advance(dt: float) -> void:
	_t += dt
	_beats()
	for p: Dictionary in _pieces:
		if not bool(p["done"]) and _t >= float(p["emit"]) + float(p["flight"]):
			_land(p)
	_gold_shown = _roll(_gold_shown, _gold_target, dt)
	_xp_shown = _roll(_xp_shown, _xp_target, dt)
	_gold_bump = maxf(_gold_bump - dt * 5.0, 0.0)
	_xp_bump = maxf(_xp_bump - dt * 5.0, 0.0)
	_shake = maxf(_shake - dt * 2.6, 0.0)
	var f := float(_landed) / maxf(float(_pieces.size()), 1.0)
	if _t >= BURST and not _done:
		for k in range(WORDS.size() - 1, -1, -1):
			if f >= float(WORDS[k][0]):
				if k > _word_k:
					_say(k, Loc.t(str(WORDS[k][1])))
				break
	if not _done and _t >= _end_t + FINALE:
		_finale()
	if _done and not buttons.visible and _t >= _end_t + CLAIM_AFTER:
		_show_claim()
	if _t >= BURST and not _quiet and not _claiming:
		var a := W.node("Audio")
		if a and a.has_method("set_loop_pitch"):
			a.set_loop_pitch(TUNE, lerpf(1.0, 1.12, clampf((_t - SPEW_AT) / maxf(_spew_len, 0.1), 0.0, 1.0)))
	var sh := _shake * _shake * 26.0
	_stage.position = Vector2(sin(_t * 61.0) * sh, cos(_t * 53.0) * sh * 0.7)
	_flash.color.a = maxf(_flash.color.a - dt * 2.4, 0.0)
	_redraw()


static func _roll(shown: float, target: float, dt: float) -> float:
	if absf(target - shown) < 0.5:
		return target
	return shown + (target - shown) * minf(dt * 14.0, 1.0)


func _redraw() -> void:
	for c: Control in [_rays, _chest, _party, _meter, _banner, _counters, _fx]:
		c.queue_redraw()
	# pass 123: the Royale panels fade in by their layer's alpha (their boxes are the kit's shared ones, drawn opaque)
	_meter.modulate.a = _meter_alpha()
	_counters.modulate.a = _counters_alpha()


## How far the speed bonus and the counters have come in (0..1), on the screen's clock.
func _meter_alpha() -> float:
	return clampf((_t - 0.15) / 0.3, 0.0, 1.0)


func _counters_alpha() -> float:
	return clampf((_t - 0.2) / 0.3, 0.0, 1.0)


## Once only: `key` the first time it is asked (a beat's sound and burst).
func _once(key: String) -> bool:
	if _said.has(key):
		return false
	_said[key] = true
	return true


## The beats as the clock passes them: the landing's thud, the knocks, the crack, the burst.
func _beats() -> void:
	if _t >= DROP and _once("drop"):
		_sfx(_knock())
		_shake = maxf(_shake, 0.45)
	for k in range(KNOCKS.size()):
		if _t >= float(KNOCKS[k]) and _once("knock%d" % k):
			_sfx(_knock())
			_shake = maxf(_shake, 0.3 + 0.12 * k)
	if _t >= CRACK and _once("crack"):
		_sfx(_knock())
		_sfx("ui_slot_start")
		_shake = maxf(_shake, 0.6)
		_shine.visible = true
		var sh := _shine as WShineScript
		sh.strength = 0.6
		sh.grow = 0.55
		sh.fade = 0.6
	if _t >= BURST and _once("burst"):
		_burst()


## The lid flies: the flash, the shake, the shine at full, two strong bursts and the sun badge, the tune.
func _burst() -> void:
	_shake = 1.0
	if not _quiet:
		_flash.color.a = 0.85
	var sh := _shine as WShineScript
	sh.strength = 1.0
	sh.grow = 1.15
	sh.fade = 1.0
	var tw := create_tween()
	tw.tween_property(sh, "grow", 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _celebrate_now():
		WCelebrate.sunburst(self, _mouth, 1, 330.0, shine)
		WCelebrate.burst(self, _mouth, 1, 2.0, shine)
		WCelebrate.burst(self, _mouth + Vector2(0, -40), 1, 2.0, W.BRASS)
	_sfx("pk_chest_open")
	_sfx("ui_fanfare")
	if not _quiet and not Run.sim_mode:
		var a := W.node("Audio")
		if a and a.has_method("play_loop"):
			a.play_loop(TUNE, 1.0)
		# the run's music steps back under the tune while it plays
		if a and a.has_method("duck_music"):
			a.duck_music(MUSIC_DUCK, 0.3)
			_ducked = true


## A celebration burst only when it will be seen: never while a seek runs through beats long past.
func _celebrate_now() -> bool:
	if Run.sim_mode:
		return false
	return not _quiet or _t >= _seek_to - 1.2


func _say(k: int, word: String) -> void:
	_word_k = k
	_word = word
	_word_t = _t
	if k > 0:
		_sfx("ui_slot_stop")
		_shake = maxf(_shake, 0.35)
		if _celebrate_now():
			WCelebrate.burst(self, Vector2(_vp.x * 0.5, _banner_y), get_child_count() - 1, 1.5, WORD_COLOURS[clampi(k, 0, WORD_COLOURS.size() - 1)])


## A piece lands in its counter: the count takes its share, the counter bumps, a sparkle and its ding.
func _land(p: Dictionary) -> void:
	p["done"] = true
	_landed += 1
	var coin := bool(p["coin"])
	if coin:
		_gold_target += float(p["share"])
		_gold_bump = 1.0
	else:
		_xp_target += float(p["share"])
		_xp_bump = 1.0
	_sparks.append([_t, p["p2"], W.BRASS if coin else GEM_COLOURS[int(p["gem"])]])
	if _sparks.size() > 40:
		_sparks.pop_front()
	if coin:
		_sfx("pk_coin")
	else:
		_sfx(["pk_gem_s", "pk_gem_m", "pk_gem_l"][int(p["gem"])])


## Every piece in: JACKPOT!, the counters exact, bursts over both, the sting; CLAIM follows CLAIM_AFTER on.
func _finale() -> void:
	_done = true
	_gold_target = float(gold_total)
	_xp_target = xp_total
	_word = Loc.t(JACKPOT_KEY)
	_word_k = WORDS.size()
	_word_t = _t
	_shake = maxf(_shake, 0.7)
	if not _quiet:
		_flash.color.a = maxf(_flash.color.a, 0.45)
	if _celebrate_now():
		WCelebrate.burst(self, _gold_rect.get_center(), get_child_count() - 1, 2.0, W.BRASS)
		WCelebrate.burst(self, _xp_rect.get_center(), get_child_count() - 1, 2.0, GEM_COLOURS[0])
		WCelebrate.burst(self, Vector2(_vp.x * 0.5, _banner_y), get_child_count() - 1, 2.0, shine)
	_sfx("ui_jackpot")


func _show_claim() -> void:
	buttons.visible = true
	if _quiet:
		return
	_claim_btn.pivot_offset = _claim_btn.size * 0.5
	var tw := create_tween()
	buttons.modulate.a = 0.0
	tw.tween_property(buttons, "modulate:a", 1.0, 0.15)


## Whether the count is over (CLAIM is up or about to be).
func is_done() -> bool:
	return _done


## Whether CLAIM is showing.
func ready_to_claim() -> bool:
	return visible and buttons.visible and not _claiming


## The counters as they show now: [gold, xp] (tests, captures).
func counters() -> Array:
	return [int(round(_gold_shown)), int(round(_xp_shown))]


## How many pieces fly in all, and how many have landed.
func pieces() -> Vector2i:
	return Vector2i(_pieces.size(), _landed)


## A tap: before the burst, straight to it (the knocks left unsaid); during the spew, the rest of it in HURRY seconds.
func hurry() -> void:
	if not visible or _done or _claiming:
		return
	RunReplay.note("bosschest_hurry")
	if _t < BURST - 0.05:
		for k in range(KNOCKS.size()):
			_said["knock%d" % k] = true
		_said["drop"] = true
		_said["crack"] = true
		_shine.visible = true
		_t = BURST - 0.05
		return
	var left := maxf(_end_t + FINALE - _t, 0.05)
	_speed = maxf(_speed, left / HURRY)


## The sequence jumped to `t` seconds (the captures: the frames passed through in steps, quietly, so the pieces and the
## counters are where the clock says).
func seek(t: float) -> void:
	_quiet = true
	_seek_to = t
	while _t < t - 0.0001:
		advance(minf(1.0 / 60.0, t - _t))
	_quiet = false
	_seek_to = -1.0


## Every piece landed now: the counters on their totals, JACKPOT!, CLAIM up.
func finish_now() -> void:
	if _done:
		return
	_quiet = true
	# no bursts for a count finished in one go (a tool's claim): nobody sees it
	_seek_to = INF
	for p: Dictionary in _pieces:
		if not bool(p["done"]):
			_land(p)
	_said["drop"] = true
	_said["crack"] = true
	_said["burst"] = true
	for k in range(KNOCKS.size()):
		_said["knock%d" % k] = true
	_t = maxf(_t, _end_t + FINALE)
	_finale()
	_gold_shown = _gold_target
	_xp_shown = _xp_target
	_quiet = false
	_seek_to = -1.0
	_show_claim()


## CLAIM (the button, the bot, a tool): the count finished if it was not, the tune stops, the screen goes at once and Game
## pays out in the same call (the lead's review: a claim that waited on a tween could leave the turn held when the screen
## was hidden under it; nothing waits now, so the turn is always given back).
func claim() -> void:
	if not visible or _claiming:
		return
	RunReplay.note("bosschest_claim")
	if not _done:
		finish_now()
	_claiming = true
	_stop_tune()
	_sfx("ui_buy")
	visible = false
	set_process(false)
	claimed.emit()


func _on_claim() -> void:
	if _done:
		claim()


func _stop_tune() -> void:
	var a := W.node("Audio")
	if a and a.has_method("stop_loop"):
		a.stop_loop(TUNE)
	if _ducked and a and a.has_method("duck_music"):
		a.duck_music(0.0, 0.6)
	_ducked = false


## A tap anywhere before the end hurries the sequence (the CLAIM button takes its own tap once it is up).
func _input(event: InputEvent) -> void:
	if not visible or _done or _claiming:
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if tap:
		hurry()


## The tune never outlives the screen.
func _notification(what: int) -> void:
	if (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()) or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_stop_tune()


func _sfx(id: String) -> void:
	if _quiet or Run.sim_mode:
		return
	W.sfx(id)


static var _knock_id := ""


func _knock() -> String:
	if _knock_id == "":
		_knock_id = KNOCK_FALLBACK
		var reg := W.node("Registry")
		if reg and reg.get("soundmap") and reg.soundmap.has_method("entry") and not (reg.soundmap.entry(KNOCK) as Dictionary).is_empty():
			_knock_id = KNOCK
	return _knock_id


# ---------------------------------------------------------------- drawing

## The chest's pose now: [lift (px up), lean (rad), squash, frame].
func _pose() -> Array:
	var y := 0.0
	var rot := 0.0
	var sq := Vector2.ONE
	if _t < DROP:
		var k := _t / DROP
		y = 420.0 * (1.0 - k * k)
	else:
		sq *= _bump(_t - DROP, 0.16, Vector2(1.16, 0.82))
	for n in range(KNOCKS.size()):
		var u := (_t - float(KNOCKS[n])) / 0.15
		if u > 0.0 and u < 1.0:
			var s := sin(u * PI)
			var amp := 0.06 + 0.03 * float(n)
			rot += (amp if n % 2 == 0 else -amp) * s
			y += (16.0 + 8.0 * float(n)) * s
			sq *= Vector2(1.0 + 0.05 * s, 1.0 - 0.05 * s)
	if _t >= CRACK and _t < BURST:
		# trembling, harder as the burst nears
		var k2 := (_t - CRACK) / (BURST - CRACK)
		rot += sin(_t * 70.0) * 0.025 * (0.4 + k2)
		y += absf(sin(_t * 41.0)) * 8.0 * k2
	if _t >= BURST:
		sq *= _bump(_t - BURST, 0.22, Vector2(0.86, 1.18))
		if not _done:
			# it bucks while it spews, a little more as the rate swells
			var k3 := clampf((_t - SPEW_AT) / maxf(_spew_len, 0.1), 0.0, 1.0)
			rot += sin(_t * 31.0) * 0.012 * (0.5 + k3)
			y += absf(sin(_t * 23.0)) * 6.0 * k3
	var frame := 0 if _t < CRACK else (1 if _t < BURST else 2)
	return [y, rot, sq, frame]


static func _bump(dt: float, length: float, to: Vector2) -> Vector2:
	if dt < 0.0 or dt >= length:
		return Vector2.ONE
	var k := dt / length
	var w := (1.0 - k) * cos(k * PI * 1.5)
	return Vector2.ONE + (to - Vector2.ONE) * w


func _draw_chest() -> void:
	if not visible:
		return
	var pose := _pose()
	var foot := _foot - Vector2(0.0, float(pose[0]))
	var alpha := clampf(_t / 0.08, 0.0, 1.0)
	_chest.draw_set_transform(foot, float(pose[1]), pose[2])
	# its shadow on the ground (stays on the ground as it hops)
	_chest.draw_set_transform(_foot, 0.0, Vector2(1.0, 0.22))
	_chest.draw_circle(Vector2.ZERO, CHEST_W * 0.42 * (0.6 + 0.4 * clampf(_t / DROP, 0.0, 1.0)), Color(0, 0, 0, 0.35 * alpha))
	_chest.draw_set_transform(foot, float(pose[1]), pose[2])
	var frame: int = pose[3]
	if _frames.size() == 3:
		var tex: Texture2D = _frames[frame]
		var h := CHEST_W * float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
		_chest.draw_texture_rect(tex, Rect2(-CHEST_W * 0.5, -h, CHEST_W, h), false, Color(1, 1, 1, alpha))
	else:
		_draw_drawn_chest(frame, alpha)
	# the light in front of the open mouth: a soft glow that pulses with the spew
	if _t >= BURST:
		var m := Vector2(0.0, -CHEST_W * MOUTH_UP)
		var k := 1.0 - clampf((_t - BURST) / 0.5, 0.0, 1.0) * 0.5
		for i in 6:
			_chest.draw_circle(m, 150.0 - i * 22.0, Color(W.PAPER, 0.06 * k * (1.0 + 0.3 * sin(_t * 9.0))))
	_chest.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The chest in the kit's look until its paintings exist: a box and a lid in its light's colour, ink outlined.
func _draw_drawn_chest(frame: int, alpha: float) -> void:
	var wd := CHEST_W * 0.86
	var hb := CHEST_W * 0.4
	var hl := CHEST_W * 0.2
	var wood := shine.darkened(0.45)
	var lid_y := -hb - (0.0 if frame == 0 else (28.0 if frame == 1 else 0.0))
	if frame == 2:
		_chest.draw_rect(Rect2(-wd * 0.46, -hb - hl * 2.4, wd * 0.92, hl * 2.2), Color(W.INK, alpha))
		_chest.draw_rect(Rect2(-wd * 0.46 + 6.0, -hb - hl * 2.4 + 6.0, wd * 0.92 - 12.0, hl * 2.2 - 12.0), Color(wood.darkened(0.3), alpha))
	_chest.draw_rect(Rect2(-wd * 0.5, -hb, wd, hb), Color(W.INK, alpha))
	_chest.draw_rect(Rect2(-wd * 0.5 + 6.0, -hb + 6.0, wd - 12.0, hb - 12.0), Color(wood, alpha))
	for sx: float in [-0.3, 0.3]:
		_chest.draw_rect(Rect2(sx * wd - 14.0, -hb, 28.0, hb), Color(W.BRASS, alpha))
	if frame != 2:
		_chest.draw_rect(Rect2(-wd * 0.5, lid_y - hl, wd, hl), Color(W.INK, alpha))
		_chest.draw_rect(Rect2(-wd * 0.5 + 6.0, lid_y - hl + 6.0, wd - 12.0, hl - 12.0), Color(wood.lightened(0.1), alpha))
	_chest.draw_rect(Rect2(-30.0, -hb - 10.0, 60.0, 64.0), Color(W.BRASS, alpha))


## The light: through the crack a fan of thin rays; after the burst a wide turning sunburst in the boss's colour and a
## column of light climbing the screen from the mouth.
func _draw_rays() -> void:
	if not visible or _t < CRACK:
		return
	var pose := _pose()
	var mouth := _foot - Vector2(0.0, float(pose[0]) + CHEST_W * MOUTH_UP)
	if _t < BURST:
		var k := (_t - CRACK) / (BURST - CRACK)
		for i in 9:
			var ang := -PI * 0.5 + (float(i) - 4.0) * 0.32 + sin(_t * 3.0 + i) * 0.03
			var reach := (260.0 + 220.0 * k) * (0.8 + 0.3 * sin(i * 2.1))
			var half := 0.025 + 0.01 * k
			_rays.draw_polygon(PackedVector2Array([mouth, mouth + Vector2.from_angle(ang - half) * reach, mouth + Vector2.from_angle(ang + half) * reach]),
				PackedColorArray([Color(W.PAPER, 0.7 * k), Color(shine, 0.0), Color(shine, 0.0)]))
		return
	var since := _t - BURST
	var grow := 1.0 - pow(1.0 - clampf(since / 0.35, 0.0, 1.0), 3.0)
	var fade := 0.55 if not _done else 0.4
	var turn := _t * 0.35
	for i in 16:
		var a := turn + TAU * float(i) / 16.0
		var half := 0.07 + 0.03 * sin(i * 1.7)
		var reach := 1500.0 * grow
		# the boss's colour and the jackpot's gold by turns
		var rc: Color = shine if i % 2 == 0 else W.LINE_YELLOW
		_rays.draw_polygon(PackedVector2Array([mouth, mouth + Vector2.from_angle(a - half) * reach, mouth + Vector2.from_angle(a + half) * reach]),
			PackedColorArray([Color(rc, 0.34 * fade), Color(rc, 0.0), Color(rc, 0.0)]))
	# the column of light out of the mouth, up the screen
	var top := mouth.y - 1400.0 * grow
	var w0 := 150.0
	var w1 := 420.0
	var pul := 0.85 + 0.15 * sin(_t * 6.0)
	_rays.draw_polygon(PackedVector2Array([Vector2(mouth.x - w1, top), Vector2(mouth.x + w1, top), Vector2(mouth.x + w0, mouth.y), Vector2(mouth.x - w0, mouth.y)]),
		PackedColorArray([Color(W.PAPER, 0.0), Color(W.PAPER, 0.0), Color(W.PAPER, 0.42 * pul * fade), Color(W.PAPER, 0.42 * pul * fade)]))


## The speed bonus under the title: SPEED BONUS and its multiplier, the kill's time, and a gauge from x1 to the top.
func _draw_meter() -> void:
	if not visible:
		return
	var a := clampf((_t - 0.15) / 0.3, 0.0, 1.0)
	if a <= 0.0:
		return
	_draw_meter_royale(a)
	return


## Pass 123: the speed bonus as the mock's slate panel (its alpha is the layer's, _redraw): SPEED BONUS and "Killed in
## 0:45" on its top line, the multiplier big in gold (secondary at x1, where it says "faster pays more"), the kit's gold bar
## from x1 to the map's top, filling as the panel comes in, its ends under it.
func _draw_meter_royale(a: float) -> void:
	var r := _meter_rect
	_meter.draw_set_transform(Vector2(0.0, 30.0 * (1.0 - a)), 0.0, Vector2.ONE)
	panel(_meter, r)
	var mult := float(pack.get("mult", 1.0))
	var fight := float(pack.get("fight", -1.0))
	var label_f := _rfont("label")
	_meter.draw_string(label_f, r.position + Vector2(ROYALE_PAD, 46.0), Loc.t("ui.boss_chest.speed_bonus"), HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_LABEL_PX, R.SECONDARY)
	# "Killed in" and the time in bold white, right-aligned on the label's line
	var time_f := _rfont("bold")
	var lead_f := _rfont("body")
	var right := r.end.x - ROYALE_PAD
	# "Killed in" (secondary), the time (bold white), and at x1 " · faster pays more" (secondary), right-aligned
	var time := W.mmss(fight) if fight >= 0.0 else ""
	var lead := Loc.t("ui.boss_chest.killed_in") + " " if fight >= 0.0 else Loc.t("ui.boss_chest.boss_down")
	var extra := " " + Loc.t("ui.boss_chest.faster_pays") if mult <= 1.001 else ""
	var y := r.position.y + 46.0
	var ew := lead_f.get_string_size(extra, HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_TIME_PX).x if extra != "" else 0.0
	var tw := time_f.get_string_size(time, HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_TIME_PX).x if time != "" else 0.0
	var lw := lead_f.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_TIME_PX).x
	_meter.draw_string(lead_f, Vector2(right - ew - tw - lw, y), lead, HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_TIME_PX, R.SECONDARY)
	if time != "":
		_meter.draw_string(time_f, Vector2(right - ew - tw, y), time, HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_TIME_PX, R.WHITE)
	if extra != "":
		_meter.draw_string(lead_f, Vector2(right - ew, y), extra, HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_TIME_PX, R.SECONDARY)
	var bonus := mult > 1.001
	ultra_string(_meter, r.position + Vector2(ROYALE_PAD, 124.0), times() + _mult_text(mult), HORIZONTAL_ALIGNMENT_LEFT, -1,
		ROYALE_MULT_PX, R.GOLD_TEXT if bonus else R.SECONDARY, 1.0, bonus)
	# the bar: x1 at its left, the map's top at its right, filled to this kill's bonus as the panel comes in
	var tl = Run.map.timeline if Run.map else null
	var top := float(BossChest.config(tl)["max_mult"])
	# pass 128: the bar starts past the multiplier as drawn ("x1.6" ran over the bar's left end and its "x1")
	var bx := meter_bar_x(mult)
	var g := Rect2(r.position + Vector2(bx, ROYALE_BAR.x), Vector2(r.size.x - bx - ROYALE_PAD, ROYALE_BAR.y))
	var fill := clampf((mult - 1.0) / maxf(top - 1.0, 0.0001), 0.0, 1.0) * clampf((_t - 0.3) / 0.6, 0.0, 1.0)
	WBar.paint(_meter, g, fill, R.BAR_GOLD, R.BAR_GOLD_LIP, 3.0)
	var end_f := _rfont("end")
	var ey := g.end.y + 30.0
	_meter.draw_string(end_f, Vector2(g.position.x, ey), times() + "1", HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_END_PX, R.WHITE)
	_meter.draw_string(end_f, Vector2(g.position.x, ey), times() + _mult_text(top), HORIZONTAL_ALIGNMENT_RIGHT, g.size.x, ROYALE_END_PX, R.WHITE)
	_meter.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The Royale faces this screen draws with by hand, looked up once (no lookups a frame): "label" (Rubik 700 tracked),
## "bold", "body", "end" (Rubik 700).
static var _rfonts: Dictionary = {}


static func _rfont(k: String) -> Font:
	if not _rfonts.has(k):
		match k:
			"label":
				_rfonts[k] = R.body(R.LABEL_WEIGHT, false, W.em(ROYALE_LABEL_PX, R.LABEL_TRACK))
			"bold":
				_rfonts[k] = R.body(R.BOLD_WEIGHT)
			"body":
				_rfonts[k] = R.body(R.BODY_WEIGHT)
			_:
				_rfonts[k] = R.body(R.LABEL_WEIGHT)
	return _rfonts[k]


## The multiplication sign in the faces that have it ("×"), else an x (looked up once).
static var _times := ""


static func times() -> String:
	if _times == "":
		_times = "×" if R.display().has_char(0xD7) and R.body().has_char(0xD7) else "x"
	return _times


## A slate panel drawn by hand in `ci` (the kit's HardBox "panel" look: the navy base straight down, the navy edge,
## the slate gradient and its lip) over `r` (its face; the base hangs R.PANEL_BASE under it).
static func panel(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_style_box(R.flat(R.NAVY, R.RADIUS), Rect2(r.position + Vector2(0.0, R.PANEL_BASE), r.size))
	ci.draw_style_box(R.flat(R.NAVY, R.RADIUS), r)
	R.panel_fill(ci.get_canvas_item(), r.grow(-R.PANEL_EDGE))


## Display type drawn by hand with the kit's edge (R.edge's numbers, WText's order): the navy drop straight down, the
## gold bevel when `gold`, the navy stroke, the face; `a` its alpha.
static func ultra_string(ci: CanvasItem, at: Vector2, t: String, align: HorizontalAlignment, w: float, px: int, col: Color,
		a: float = 1.0, gold: bool = false) -> void:
	var f := R.display()
	var stroke := maxi(int(round(R.stroke_px(px) / R.STROKE_DIV)), 1) * 2
	var drop := maxi(int(round(R.GOLD_DROP_FRAC * px)), 1) if gold else R.drop_px(px)
	var navy := Color(R.NAVY, a)
	ci.draw_string_outline(f, at + Vector2(0.0, drop), t, align, w, px, stroke, navy)
	ci.draw_string(f, at + Vector2(0.0, drop), t, align, w, px, navy)
	if gold:
		var bev := Color(R.GOLD_BEVEL, a)
		ci.draw_string_outline(f, at + Vector2(0.0, R.bevel_px(px)), t, align, w, px, stroke, bev)
		ci.draw_string(f, at + Vector2(0.0, R.bevel_px(px)), t, align, w, px, bev)
	ci.draw_string_outline(f, at, t, align, w, px, stroke, navy)
	ci.draw_string(f, at, t, align, w, px, Color(col, a))


static func _mult_text(m: float) -> String:
	var s := "%.1f" % m
	return s.trim_suffix(".0") if absf(m - roundf(m)) < 0.05 else s


## Pass 128: how wide the multiplier is drawn in the speed panel (its text at ROYALE_MULT_PX plus the kit's edge round it).
static func meter_mult_width(mult: float) -> float:
	var stroke := maxi(int(round(R.stroke_px(ROYALE_MULT_PX) / R.STROKE_DIV)), 1) * 2
	return R.display().get_string_size(times() + _mult_text(mult), HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_MULT_PX).x + float(stroke)


## Pass 128: where the gold bar starts inside the speed panel: the mock's ROYALE_BAR_X while the multiplier fits before it
## ("x1"), else ROYALE_MULT_GAP past the multiplier's measured right edge, so no value (x1.6, x9.9, a map's own top) can
## touch the bar or the "x1" under its left end.
static func meter_bar_x(mult: float) -> float:
	return maxf(ROYALE_BAR_X, ROYALE_PAD + meter_mult_width(mult) + ROYALE_MULT_GAP)


## The banner between the chest and the counters: the word slams in (big and turning, settling with a bounce) and
## breathes while it stands; JACKPOT! pulses.
func _draw_banner() -> void:
	if not visible or _word == "":
		return
	var since := _t - _word_t
	var k := clampf(since / 0.28, 0.0, 1.0)
	var pop := 1.0 + 0.9 * pow(1.0 - k, 3.0) + (0.05 * sin(_t * 8.0) if _word == Loc.t(JACKPOT_KEY) else 0.02 * sin(_t * 5.0))
	var rot := -0.06 + 0.12 * pow(1.0 - k, 2.0) * (1.0 if _word_k % 2 == 0 else -1.0)
	var col: Color = WORD_COLOURS[clampi(_word_k, 0, WORD_COLOURS.size() - 1)]
	var slab := W.slab()
	var w := _vp.x
	_banner.draw_set_transform(Vector2(_vp.x * 0.5, _banner_y), rot, Vector2.ONE * pop)
	var base := Vector2(-w * 0.5, BANNER_PX * 0.36)
	# pass 123: the headline in the kit's gold with the navy edge, the bevel and the drop (the mock's BIG WIN!)
	ultra_string(_banner, base, _word, HORIZONTAL_ALIGNMENT_CENTER, w, BANNER_PX, R.GOLD_TEXT, k, true)
	_banner.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return


## The two counters at the bottom: GOLD with the coin, EXP with a gem; each bumps as a piece lands and glows at the end.
func _draw_counters() -> void:
	if not visible:
		return
	var a := clampf((_t - 0.2) / 0.3, 0.0, 1.0)
	if a <= 0.0:
		return
	_counter(_gold_rect, Loc.t("ui.boss_chest.gold"), W.num(int(round(_gold_shown))), true, _gold_bump, a)
	_counter(_xp_rect, Loc.t("ui.boss_chest.exp"), W.num(int(round(_xp_shown))), false, _xp_bump, a)


func _counter(r: Rect2, label: String, value: String, coin: bool, bump: float, a: float) -> void:
	var c := r.get_center()
	var s := 1.0 + 0.09 * bump * bump
	_counters.draw_set_transform(c, 0.0, Vector2.ONE * s)
	var rr := Rect2(-r.size * 0.5, r.size)
	_counter_royale(rr, label, value, coin, bump)
	_counters.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return


## Pass 123: a counter as the mock's slate panel (its alpha is the layer's, _redraw): the glow round it at the end, the
## panel, a wash as a piece lands, the label in the kit's tracked Rubik, the kit's coin or the purple gem where the
## pieces aim, the count big in gold Ultra with the bevel.
func _counter_royale(rr: Rect2, label: String, value: String, coin: bool, bump: float) -> void:
	if _done:
		var glow := 0.5 + 0.5 * sin(_t * 7.0)
		for i in 4:
			_counters.draw_rect(rr.grow(6.0 + i * 7.0), Color(R.GOLD_TEXT if coin else GEM_COLOURS[0], 0.12 * glow), false, 8.0)
	panel(_counters, rr)
	if bump > 0.0:
		_counters.draw_rect(rr.grow(-R.PANEL_EDGE), Color(R.GOLD_TEXT if coin else GEM_COLOURS[1], 0.16 * bump))
	var label_f := _rfont("label")
	_counters.draw_string(label_f, rr.position + Vector2(ROYALE_PAD, 48.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, ROYALE_LABEL_PX, R.SECONDARY)
	var icon_c := rr.position + Vector2(ROYALE_ICON_X, rr.size.y * 0.58)
	if coin:
		_draw_coin(_counters, icon_c, ROYALE_COIN_PX, 0.0, 1.0)   # pass 123: the painted coin, as everywhere (Garry)
	else:
		_draw_gem(_counters, icon_c, 40.0, 0, 1.0)
	var px := ROYALE_COUNT_PX if value.length() <= 5 else ROYALE_COUNT_SMALL_PX
	var f := R.display()
	var mid := icon_c.y + (f.get_ascent(px) - f.get_descent(px)) * 0.5 - px * 0.04
	ultra_string(_counters, Vector2(rr.position.x + ROYALE_NUM_X, mid), value, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - ROYALE_NUM_X - 20.0,
		px, R.GOLD_TEXT, 1.0, true)


func _draw_coin(host: Control, at: Vector2, px: float, spin: float, a: float) -> void:
	var w := px * maxf(absf(cos(spin)), 0.15)
	var r := Rect2(at - Vector2(w, px) * 0.5, Vector2(w, px))
	if _coin_tex:
		host.draw_texture_rect(_coin_tex, r, false, Color(1, 1, 1, a))
	else:
		host.draw_circle(at, px * 0.5, Color(W.INK, a))
		host.draw_circle(at, px * 0.5 - 4.0, Color(W.BRASS, a))


## An XP gem as the field draws it from above: a cut diamond in its size's colour, a lit facet, an ink line.
func _draw_gem(host: Control, at: Vector2, px: float, kind: int, a: float, rot: float = 0.0) -> void:
	var col: Color = GEM_COLOURS[clampi(kind, 0, 2)]
	var w := px * 0.62
	var pts := PackedVector2Array([Vector2(0, -px), Vector2(w, -px * 0.12), Vector2(0, px), Vector2(-w, -px * 0.12)])
	var lit := PackedVector2Array([Vector2(0, -px), Vector2(0, -px * 0.12), Vector2(-w, -px * 0.12)])
	var xf := Transform2D(rot, at)
	pts = xf * pts
	lit = xf * lit
	host.draw_colored_polygon(pts, Color(col, a))
	host.draw_colored_polygon(lit, Color(col.lightened(0.45), a))
	var loop := pts.duplicate()
	loop.append(pts[0])
	host.draw_polyline(loop, Color(W.INK, a), maxf(px * 0.09, 2.0), true)


## Pass 119, the party: the fountain's loot in its arcs, the drift rising and swaying (round and round, fading in at the
## bottom and out near the top), the twinkles round the open chest. All a function of the clock, so a seek lands on it.
func _draw_party() -> void:
	if not visible or _t < BURST:
		return
	for f: Array in _fountain:
		var age := _t - float(f[0])
		var life := float(f[10])
		if age >= 0.0 and float(f[11]) > 0.0:
			age = fmod(age, float(f[11]))
		if age < 0.0 or age > life:
			continue
		var pos := Vector2(float(f[1]) + float(f[3]) * age, float(f[2]) + float(f[4]) * age + 0.5 * FOUNTAIN_G * age * age)
		var a := clampf((life - age) / 0.25, 0.0, 1.0) * clampf(age / 0.06, 0.0, 1.0)
		_loot(int(f[8]), int(f[9]), pos, float(f[7]), float(f[5]) + float(f[6]) * age, a)
	for d: Array in _drift:
		var since := _t - float(d[0])
		if since < 0.0:
			continue
		var period := maxf(float(d[10]), 0.5)
		var age := fmod(since, period)
		var u := age / period
		var pos := Vector2(float(d[1]) + float(d[4]) * sin(float(d[5]) * TAU * since + float(d[6])), float(d[2]) - float(d[3]) * age)
		var a := clampf(age / 0.4, 0.0, 1.0) * clampf((1.0 - u) / 0.18, 0.0, 1.0) * 0.92
		_loot(int(d[8]), int(d[9]), pos, float(d[7]), float(d[6]) + float(d[11]) * since, a)
	var fade_in := clampf((_t - BURST) / 0.3, 0.0, 1.0)
	for tw: Array in _twinkles:
		var ph := fmod(_t / float(tw[2]) + float(tw[3]), 1.0)
		var k := sin(ph * PI)
		if k <= 0.05:
			continue
		_twinkle(Vector2(float(tw[0]), float(tw[1])), float(tw[4]) * k, fade_in * k)
	_party.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One piece of the party's loot at `pos`, about `px` across, turned by `spin`, at alpha `a`.
func _loot(kind: int, sub: int, pos: Vector2, px: float, spin: float, a: float) -> void:
	if a <= 0.01:
		return
	match kind:
		Loot.COIN:
			_draw_coin(_party, pos, px, spin, a)
		Loot.GEM:
			_draw_gem(_party, pos, px, sub % 3, a, sin(spin) * 0.6)
		Loot.CHIP:
			# a poker chip flipping: its face squashed by the flip, an ink rim, six white notches, an inner ring
			_party.draw_set_transform(pos, 0.0, Vector2(maxf(absf(cos(spin)), 0.18), 1.0))
			var col: Color = CHIP_COLOURS[sub % CHIP_COLOURS.size()]
			var r := px * 0.5
			_party.draw_circle(Vector2.ZERO, r, Color(W.INK, a))
			_party.draw_circle(Vector2.ZERO, r - 3.0, Color(col, a))
			for i in 6:
				var d := Vector2.from_angle(TAU * float(i) / 6.0)
				_party.draw_line(d * (r - 9.0), d * (r - 3.0), Color(W.PAPER, a), 6.0)
			_party.draw_arc(Vector2.ZERO, r * 0.56, 0.0, TAU, 20, Color(W.PAPER, a * 0.9), 2.5)
			_party.draw_circle(Vector2.ZERO, r * 0.4, Color(col.lightened(0.15), a))
			_party.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		Loot.NOTE:
			# a greenback fluttering: pale green paper, an ink frame, an oval medallion and a dollar sign
			_party.draw_set_transform(pos, sin(spin) * 0.6, Vector2(1.0, maxf(absf(cos(spin * 0.7)), 0.25)))
			var w := px
			var h := px * 0.46
			var rr := Rect2(-w * 0.5, -h * 0.5, w, h)
			_party.draw_rect(rr.grow(2.0), Color(W.INK, a))
			_party.draw_rect(rr, Color(NOTE_GREEN, a))
			_party.draw_rect(rr.grow(-4.0), Color(NOTE_INK, a * 0.8), false, 2.0)
			_party.draw_circle(Vector2.ZERO, h * 0.32, Color(NOTE_INK, a * 0.85))
			_party.draw_string(W.slab(), Vector2(-w * 0.5, h * 0.17), "$", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.5), Color(NOTE_GREEN, a))
			_party.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		Loot.SCRAP:
			# a torn scrap of a Wanted poster: aged paper with a jagged edge, two ink lines and a red stamp
			_party.draw_set_transform(pos, sin(spin) * 0.8, Vector2(maxf(absf(cos(spin * 0.6)), 0.3), 1.0))
			var w2 := px
			var h2 := px * 0.7
			var pts := PackedVector2Array([Vector2(-w2 * 0.5, -h2 * 0.5), Vector2(w2 * 0.1, -h2 * 0.56), Vector2(w2 * 0.5, -h2 * 0.44),
				Vector2(w2 * 0.42, -h2 * 0.05), Vector2(w2 * 0.52, h2 * 0.5), Vector2(-w2 * 0.05, h2 * 0.42),
				Vector2(-w2 * 0.3, h2 * 0.55), Vector2(-w2 * 0.52, h2 * 0.1)])
			var ink := pts.duplicate()
			ink.append(pts[0])
			_party.draw_colored_polygon(pts, Color(W.PAPER, a))
			_party.draw_polyline(ink, Color(W.INK, a), 3.0, true)
			_party.draw_line(Vector2(-w2 * 0.34, -h2 * 0.22), Vector2(w2 * 0.3, -h2 * 0.22), Color(W.INK, a * 0.85), 5.0)
			_party.draw_line(Vector2(-w2 * 0.34, -h2 * 0.02), Vector2(w2 * 0.12, -h2 * 0.02), Color(W.INK_SOFT, a * 0.8), 3.0)
			_party.draw_arc(Vector2(w2 * 0.16, h2 * 0.22), h2 * 0.17, 0.0, TAU, 14, Color(W.ROCK, a * 0.9), 3.0)
			_party.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_:
			# a brass star (the sheriff's), turning
			_party.draw_set_transform(pos, spin * 0.5, Vector2(maxf(absf(cos(spin * 0.8)), 0.3), 1.0))
			var star := PackedVector2Array()
			for i in 10:
				var rad := px * (0.5 if i % 2 == 0 else 0.23)
				star.append(Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 10.0) * rad)
			var loop := star.duplicate()
			loop.append(star[0])
			_party.draw_colored_polygon(star, Color(W.BRASS, a))
			_party.draw_colored_polygon(PackedVector2Array([star[0], Vector2.ZERO, star[8], star[9]]), Color(W.LINE_YELLOW, a))
			_party.draw_polyline(loop, Color(W.INK, a), 3.0, true)
			_party.draw_circle(Vector2.ZERO, px * 0.09, Color(W.INK, a))
			_party.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A four-point twinkle: two crossed slivers, white at the heart.
func _twinkle(at: Vector2, size: float, a: float) -> void:
	var s := size
	var t := size * 0.16
	_party.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(t, 0), at + Vector2(0, s), at + Vector2(-t, 0)]),
		Color(W.LINE_YELLOW, a))
	_party.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.8, 0), at + Vector2(0, -t), at + Vector2(s * 0.8, 0), at + Vector2(0, t)]),
		Color(W.LINE_YELLOW, a))
	_party.draw_circle(at, t * 1.3, Color(1, 1, 1, a))


## Over everything: the pieces in flight, the sparkles where they landed, the coins raining.
func _draw_fx() -> void:
	if not visible:
		return
	for rn: Array in _rain:
		var age := _t - float(rn[0])
		if age < 0.0:
			continue
		var y := -60.0 + float(rn[2]) * age + 300.0 * age * age
		if y > _vp.y + 80.0:
			continue
		_draw_coin(_fx, Vector2(float(rn[1]), y), COIN_PX * float(rn[4]), float(rn[3]) + age * 9.0, 0.95)
	for p: Dictionary in _pieces:
		if bool(p["done"]):
			continue
		var s := (_t - float(p["emit"])) / float(p["flight"])
		if s < 0.0:
			continue
		var e := s * s * (3.0 - 2.0 * s)
		var q := 1.0 - e
		var pos: Vector2 = q * q * (p["p0"] as Vector2) + 2.0 * q * e * (p["p1"] as Vector2) + e * e * (p["p2"] as Vector2)
		var size := 0.55 + 0.75 * sin(minf(s * 1.25, 1.0) * PI * 0.5) - 0.35 * maxf(s - 0.7, 0.0) / 0.3
		if bool(p["coin"]):
			_draw_coin(_fx, pos, COIN_PX * size, float(p["spin"]) + s * 16.0, 1.0)
		else:
			_draw_gem(_fx, pos, GEM_PX * size, int(p["gem"]), 1.0, sin(float(p["spin"]) + s * 6.0) * 0.5)
	for sp: Array in _sparks:
		var age2 := _t - float(sp[0])
		if age2 < 0.0 or age2 > 0.35:
			continue
		var k := age2 / 0.35
		var c: Vector2 = sp[1]
		var r := 16.0 + 30.0 * k
		var col: Color = sp[2]
		col.a = 1.0 - k
		for i in 4:
			var d := Vector2.from_angle(PI * 0.5 * float(i) + 0.4)
			_fx.draw_line(c + d * r * 0.3, c + d * r, col, 4.0 * (1.0 - k) + 1.0, true)
