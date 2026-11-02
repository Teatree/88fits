## Pass 121 (lane LEGEND; Garry, 2026-11-02: "Make it so that up until 4:30 in every run of any Stage there is 0 chance
## of getting a Legendary and after 4:30 there is some (small) chance of getting it (so whatever it is now)"; asked
## whether a long run should also be sure of one: "No guarantee, just the hold"). BALANCING.md 63.LEGEND.
##
## The hold: no NEW item of rarity "legendary" (a passive item today; a weapon or a perk of that rarity later) is offered
## while the stage's clock (Run.stage_clock: the HUD's, 0:00 at the stage's start) is under `from` seconds. The boss's
## fall (the portal's countdown) and Endless count as past it. Once the clock reaches it the draw is exactly the old one
## (CardPool.weight_of unchanged). It holds in every offer: the level-up cards, the Shop and the Stranger (through
## CardPool.offer_passives / offer_weapons and CardPool.candidates), a chest's roll (Run.chest_candidates) and the chest
## reel's filler plates (ChestScreen._pool_for). An item the hero already holds keeps its levels (only the debug arena's
## ITEMS tab can hand one over that early); an evolution of something held is never held.
##
## The guarantee (a switch, OFF by default: `guarantee_at` 0): when on, a run whose stage clock reaches `guarantee_at`
## (and `from`: the hold wins) without having been shown a legendary card gets one among its next level-up's three cards
## (one the hero can take: CardPool.candidates already leaves out the banished, the shut out and the maxed), drawn by the
## cards' own weights on the cards' dice, in place of the offer's last card. Once a run only.
##
## "Shown": any card of rarity "legendary" put in front of the player by any offer (level-up, a banish's redraw, a
## reroll, the Shop, the first-run Dynamite screen, a chest's roll, the Stranger): Run.legendary_shown.
##
## The numbers: the map's `timeline_data.legendary` {from, guarantee_at} (seconds of the stage clock), a stage entry's own
## `stage_list[k].legendary` key by key over it, WaveTimeline.LEGENDARY_DEFAULTS (270, 0) for what neither names.
class_name LegendaryHold
extends RefCounted

## The rarity the hold is about (ContentDef.rarity; never a list of ids, so a new legendary is held too).
const RARITY := "legendary"


## One of the two numbers for the run's stage: its stage entry's, the map's, else the default.
static func value(key: String) -> float:
	var tl: WaveTimeline = null
	if Run.map != null:
		tl = Run.map.timeline
	if tl == null:
		return float(WaveTimeline.LEGENDARY_DEFAULTS.get(key, 0.0))
	return tl.legendary_value(key, Run.stage)


## The seconds of the stage clock the hold is up to (the map's `from`, never below 0).
static func from_seconds() -> float:
	return maxf(value("from"), 0.0)


## The stage clock the hold reads: Run.stage_clock(), and past every number once the stage's boss has fallen or Endless runs.
static func clock() -> float:
	if Run.endless or Run.stage_beaten:
		return INF
	return Run.stage_clock()


## Whether a legendary may be offered now (the clock has reached `from`).
static func open() -> bool:
	return clock() >= from_seconds()


## Whether `def` is of the held rarity.
static func is_legendary(def: ContentDef) -> bool:
	return def != null and def.rarity == RARITY


## Whether `def`, as a NEW item, is held out of every offer now.
static func held(def: ContentDef) -> bool:
	return is_legendary(def) and not open()


## Whether a card is of the held rarity (any card: a new item, a level of one held).
static func is_legendary_card(c) -> bool:
	return c is Dictionary and (c as Dictionary).get("def") is ContentDef and is_legendary((c as Dictionary)["def"])


## Whether an offer holds a legendary card.
static func has_legendary(offer: Array) -> bool:
	for c in offer:
		if is_legendary_card(c):
			return true
	return false


## Counts an offer as shown: a legendary card among it marks the run (Run.legendary_shown).
static func note_shown(offer: Array) -> void:
	if not Run.legendary_shown and has_legendary(offer):
		Run.legendary_shown = true


## The one-card form of note_shown, handing the card back (the Stranger's returns).
static func noted(card: Dictionary) -> Dictionary:
	note_shown([card])
	return card


## The guarantee's time (seconds of the stage clock; 0 = off).
static func guarantee_seconds() -> float:
	return maxf(value("guarantee_at"), 0.0)


## Whether the next level-up must hold a legendary: the switch on, its time and the hold's both reached, none shown yet.
static func guarantee_due() -> bool:
	var g := guarantee_seconds()
	if g <= 0.0 or Run.legendary_shown:
		return false
	var t := clock()
	return t >= g and t >= from_seconds()


## A level-up's `offer` of `count` cards with the guarantee applied (CardPool.level_up_offer): unchanged unless it is
## due and the offer has no legendary; then one legendary card of `cands` (the draw's candidates, so one the hero can
## take), drawn by weight on the cards' dice, takes the last card's place (or fills an empty place). No such card: as it was.
static func guarantee(offer: Array, cands: Array, count: int) -> Array:
	if count <= 0 or not guarantee_due() or has_legendary(offer):
		return offer
	var legends: Array = cands.filter(func(c) -> bool: return is_legendary_card(c))
	if legends.is_empty():
		return offer
	var drawn: Array = CardPool._pick(legends, 1)
	if drawn.is_empty():
		return offer
	var out := offer.duplicate()
	if out.size() < count:
		out.append(drawn[0])
	else:
		out[out.size() - 1] = drawn[0]
	return out
