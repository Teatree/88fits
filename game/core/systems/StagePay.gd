class_name StagePay
extends RefCounted
## Pass 140 (lane ECON; Garry on the progression plan's stage pay, "The Fifty-Run Plan" section 5: "Yes I am accepting all of
## the multipliers"): what a stage pays besides its gems, each a key of the map's `timeline_data.stage_list` entry
## (WaveTimeline.stage_coin_mult, stage_boss_purse, stage_wage; BALANCING 81.ECON):
##   coin_mult   a coin on the sand worth v pays v x this (coin_pay: the fraction carried from coin to coin, so a factor of 2.66
##               pays 2 or 3 a coin and 2.66 on average, the same coins paying the same in a replay); absent = the round of
##               `reward_mult` (at least 1), the pay before pass 140
##   boss_purse  a boss's purse (Game.boss_purse); absent = Game.BOSS_PURSE's line
##   wage        Wages: coins a minute of the stage clock survived (the clock stands still from the boss on, so a run that met
##               its boss is paid the whole stage; Endless adds nothing), paid once at the run's end into the purse with
##               everything else it banks (pay_wages, out of Game.bank_run_end): a death too. Never x greed, never x Coins x25,
##               never counted by a coin poster or Gold Rush (no gold_gained); RunAnalytics source `wages`.

## The coin factor's carried fraction (take): what this game's coins so far earned past their whole coins. A new game's
## PickupManager starts it at 0 (reset), so a run and its replay pay the same coins.
static var carry := 0.0
## Pass 140 (lane FIX): the Wages this game paid into the purse at its end (pay_wages), 0 until then. A replay's checkpoints
## compare the purse the play earned (RunReplay.check_values: Run.run_gold less this), since the run's last check is taken
## after the end has paid them and a replay whose end was not one of the run's own events (a tool's end_run) never pays them.
static var paid := 0


static func reset() -> void:
	carry = 0.0
	paid = 0


## The timeline `tl` (null: this run's map's), or null without one.
static func _tl(tl):
	if tl != null:
		return tl
	return Run.map.timeline if Run.map != null else null


## The coin factor of stage `stage` (-1: this run's) in timeline `tl` (null: this run's map's); 1 without a map.
static func coin_mult(stage: int = -1, tl = null) -> float:
	var t = _tl(tl)
	if t == null or not t.has_method("stage_coin_mult"):
		return 1.0
	return float(t.stage_coin_mult(Run.stage if stage < 0 else stage))


## Pass 140 (lead, 81.ECON): an Elite's purse follows the stage's coin factor against the pay before pass 140 (coin_mult over
## the round of `reward_mult`, at least 1): x1 / x1.33 / x2 / x2.85 on the four stages, as Garry's accepted multipliers say
## for coins. 1 without a map.
static func purse_factor(stage: int = -1, tl = null) -> float:
	var t = _tl(tl)
	if t == null or not t.has_method("stage_coin_mult") or not t.has_method("stage_reward_mult"):
		return 1.0
	var i := Run.stage if stage < 0 else stage
	var old := float(maxi(int(round(float(t.stage_reward_mult(i)))), 1))
	return float(t.stage_coin_mult(i)) / old


## What a coin of `units` (its value as PickupManager pays it) pays at factor `k` before greed and Coins x25: the whole part
## of units x k plus the fraction carried from the coins before; the rest is carried on. A whole factor pays exactly as before.
static func take(units: float, k: float) -> int:
	var exact := maxf(units * k, 0.0) + carry
	var whole := int(floor(exact + 0.000001))
	carry = clampf(exact - float(whole), 0.0, 0.999999)
	return maxi(whole, 0)


## Stage `stage`'s Wages a minute (-1: this run's), 0 without a map or a `wage`.
static func wage_rate(stage: int = -1, tl = null) -> float:
	var t = _tl(tl)
	if t == null or not t.has_method("stage_wage"):
		return 0.0
	return float(t.stage_wage(Run.stage if stage < 0 else stage))


## The seconds of the stage clock Wages pay for: the clock (it stands still from the boss on), never past the stage's length.
static func wage_seconds() -> float:
	return clampf(Run.stage_clock(), 0.0, maxf(Run.stage_length_now(), 0.0))


## The Wages `seconds` of stage `stage`'s clock earn: round(wage x minutes).
static func wages_for(seconds: float, stage: int = -1, tl = null) -> int:
	return maxi(int(round(wage_rate(stage, tl) * maxf(seconds, 0.0) / 60.0)), 0)


## What this run's Wages come to now (0 in the arena or without a map).
static func wages_due() -> int:
	if Run.arena or _tl(null) == null:
		return 0
	return wages_for(wage_seconds())


## The run's end (Game.bank_run_end, once): the Wages into the purse, so they bank with it. Returns what was paid.
static func pay_wages() -> int:
	var w := wages_due()
	if w <= 0:
		return 0
	Run.run_gold += w
	paid += w
	Save.add_total("gold_earned", w)
	if RunAnalytics.I:
		RunAnalytics.I.gold_in("wages", w, 0)
	Run.gold_changed.emit(Run.run_gold)
	return w
