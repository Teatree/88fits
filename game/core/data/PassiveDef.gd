## A passive: a level table of Effects that target the player (or all weapons). Pass 47 splits content/passives in two:
## the line items (`line`: four levels, an evolution once maxed, six slots beside the weapons) and the passive items (the
## rest: no cap, not on the HUD, their rarity shown as the plate's colour).
class_name PassiveDef
extends ContentDef

## A line item (pass 47, Garry: "Line Items"): a levelled stat item that evolves when maxed and takes one of the six line
## slots next to the weapons on the HUD. Its evolution carries `line` too. False = a passive item: as many as the run
## finds, listed only on the pause screen's Build tab and in the Collection. Pass 73 (lane CARDS): the player meets them as
## fortune cards ("The Sun", its evolution "The Sun Risen"; every text says Card); the code and the JSON keep `line`.
@export var line: bool = false

## levels[i] is an Array of Effect gained when reaching level i+1.
@export var levels: Array = []
## When true and levels has fewer entries than max_level, the last entry repeats for the remaining levels.
@export var repeat_last_level: bool = true
@export var max_level: int = 8
## Weapon id this passive pairs with for an evolution (informational; the weapon carries the recipe).
@export var pairs_with: String = ""
## The price in words ("−6% max HP a level"), empty for none (a line's trade; on the passive since pass 46).
@export var trade: String = ""
## What it evolves into once maxed (pass 33.2 on the lines, every passive since pass 46): a level-up card offers it at
## the top level.
@export var evolves_into: String = ""
## On an evolved one: what it replaces. An evolved item has one level and is never offered on its own.
@export var evolves_from: String = ""
## Its own sentence for the card (the Energy Shield's rules), shown above the generated effect text.
@export var text: String = ""
## Item looks (pass 73, lane CARDS: the line items became fortune cards, Garry: "Each a new 'Look' so I can come back to
## the old one"): code -> {"icon": Texture2D, "icon_file", "note", "shelved"}, every icon the item can be drawn with
## (the cards: "A" the icon it had before, "B".."E" the four card framings). `variant` is the look the JSON plays and
## `variant_base` the look whose icon is the top-level `icon` file. The icon of the look worn is the def's own `icon`
## (JsonContent.build puts the JSON's look on; wear_look changes it, Registry.apply_card_looks for a phone's kept look), so
## every screen that draws def.icon shows it. A look whose picture is not on disk is left out.
@export var variants: Dictionary = {}
@export var variant: String = ""
@export var variant_base: String = ""
## The look whose icon `icon` holds now ("" = the JSON's `variant`): wear_look.
var worn := ""
## Pass 95 (lane PASSIVES): the icon a passive item wears on its Evolved rung (`<id>_icon_evolved.png`, the same
## picture with a white outline round its subject, tools/evolved_icons.py); null = the base icon there too.
@export var evolved_icon: Texture2D

## Pass 95 (lane PASSIVES, Garry: "the number of Upgrades is reduced to the number of upgrades they have left to reach
## Legendary + Evolved Rarity"): a passive item climbs the rarity ladder one rung an upgrade. An item of rarity r has
## steps(r) = the rungs from r to legendary (common 4, uncommon 3, rare 2, epic 1, legendary 0) + 1 (Evolved) upgrades,
## so levels = steps + 1: common 6, uncommon 5, rare 4, epic 3, legendary 2. Level k stands on rung LADDER[idx(r) + k - 1]
## and the top level is EVOLVED_RUNG ("Evolved" is a rarity for passive items, never for weapons or cards: the dark plate
## ringed in brass, the Evolved icon, "Evolved" in the words). `max_level` is derived from the rule for every item
## (apply_ladder, JsonContent.build); the lines (`line`) and the evolved cards keep their own. The JSON holds every rung's
## effects explicitly (tools/passive_ladder.py wrote them), so Garry tunes each rung; a shorter list repeats its last
## level as before (repeat_last_level), a longer one is unreachable (the Level Editor warns of both).
const LADDER := ["common", "uncommon", "rare", "epic", "legendary"]
const EVOLVED_RUNG := "evolved"

## Pass 100 (lane SMALL, Garry: Phoenix "can only be used once and doesn't feature any upgrades"): a one-shot passive
## item (`single` in the JSON): one level, off the rarity ladder (no rungs, no Evolved rung, no Evolved icon), never
## offered again once held (its max_level is 1). Any future one-shot item sets the same key.
@export var single: bool = false


func kind() -> String:
	return "passive"


## The levels an item of `rarity` climbs: the rungs left to legendary + Evolved + its own first level (common 6 ..
## legendary 2). An unknown rarity reads as common (as W.rarity_of reads it).
static func ladder_levels(p_rarity: String) -> int:
	var i := LADDER.find(p_rarity)
	return LADDER.size() - 1 - maxi(i, 0) + 2


## Whether this is a passive item on the ladder: not a line (a card), not an evolved form.
func is_item() -> bool:
	return not line and evolves_from == ""


## Whether this item climbs the rarity ladder (pass 100: a passive item that is not `single`).
func on_ladder() -> bool:
	return is_item() and not single


## The top level of this passive (the ladder's for an item, 1 for a one-shot, else `max_level`).
func ladder_top() -> int:
	if single and is_item():
		return 1
	return ladder_levels(rarity) if on_ladder() else maxi(max_level, 1)


## The rung an item stands on at `level`: its rarity at level 1 (and at 0, the item in general), one rung up a level,
## EVOLVED_RUNG at the top and past it; the rarity itself for a line or an evolved form.
func rung_at(level: int) -> String:
	if not on_ladder() or level <= 1:
		return rarity if LADDER.has(rarity) else LADDER[0]
	if level >= ladder_top():
		return EVOLVED_RUNG
	var i := maxi(LADDER.find(rarity), 0) + level - 1
	return LADDER[mini(i, LADDER.size() - 1)]


## Whether `level` is an item's Evolved rung (its top level or past it; never a line's, which evolves into a card).
func is_evolved_rung(level: int) -> bool:
	return on_ladder() and level >= ladder_top()


## The icon to draw at `level`: the Evolved icon on the Evolved rung when it has one, else the icon worn.
func icon_at(level: int) -> Texture2D:
	return evolved_icon if is_evolved_rung(level) and evolved_icon != null else icon


## Derives `max_level` from the ladder for an item (JsonContent.build, once the rarity is read).
func apply_ladder() -> void:
	if single and is_item():
		max_level = 1
	elif on_ladder():
		max_level = ladder_levels(rarity)


## The look codes in order (empty when it has one icon); a shelved look (`variants[CODE].shelved`) is left out unless
## asked for.
func variant_codes(include_shelved := false) -> Array:
	var out: Array = []
	for code in variants.keys():
		if include_shelved or not variant_shelved(str(code)):
			out.append(str(code))
	out.sort()
	return out if out.size() > 1 else []


## Whether a look is shelved; false for a code it does not have.
func variant_shelved(code: String) -> bool:
	var e = variants.get(code)
	return e is Dictionary and bool((e as Dictionary).get("shelved", false))


## A look's note ("" when it has none).
func variant_note(code: String) -> String:
	var e = variants.get(code)
	return str((e as Dictionary).get("note", "")) if e is Dictionary else ""


## The icon of look `code`: its own picture, else the base look's, else the icon worn now.
func look_icon(code: String) -> Texture2D:
	var e = variants.get(code)
	if e is Dictionary and (e as Dictionary).get("icon") is Texture2D:
		return (e as Dictionary)["icon"]
	var b = variants.get(variant_base)
	if b is Dictionary and (b as Dictionary).get("icon") is Texture2D:
		return (b as Dictionary)["icon"]
	return icon


## The look the item is drawn in now: the one worn, else the JSON's.
func look_code() -> String:
	return worn if worn != "" else variant


## Draws the item in look `code` from now on (its icon becomes that look's): "", a code it lacks or a shelved one wears
## the JSON's own look again. Returns the look worn.
func wear_look(code: String) -> String:
	if variants.is_empty():
		worn = ""
		return ""
	var use := code if (code != "" and variants.has(code) and not variant_shelved(code)) else ""
	worn = use
	var show := use if use != "" else variant
	if variants.has(show):
		icon = look_icon(show)
	return look_code()


## The display name of the passive `id` (pass 73: a text that names a card reads its name, never a hard-coded one: the
## cards were renamed), `fallback` when the Registry has none. The Registry by path: naming the autoload here would break
## the compile of every tool script.
static func display_name_of(pid: String, fallback: String = "") -> String:
	var ml := Engine.get_main_loop()
	var reg: Node = (ml as SceneTree).root.get_node_or_null("Registry") if ml is SceneTree else null
	var d = reg.call("passive", pid) if reg else null
	return (d as PassiveDef).display_name if d is PassiveDef else (fallback if fallback != "" else pid.capitalize())


## Whether this is a line item (pass 47): `line` in its JSON. A line and a passive item are both kind() "passive" (the
## Registry, the save's met-it lists and the unlock quests know them by that); this tells them apart.
func is_line() -> bool:
	return line


## Whether this is the evolution of another (it replaces `evolves_from`).
func is_evolved() -> bool:
	return evolves_from != ""


func effects_at_level(level: int) -> Array:
	if levels.is_empty() or level < 1:
		return []
	# pass 100 (lane SMALL): a one-shot item gives its one level once (a level past it, from an old run, adds nothing)
	if single and level > 1:
		return []
	var idx := level - 1
	if idx >= levels.size():
		if not repeat_last_level:
			return []
		idx = levels.size() - 1
	var lv = levels[idx]
	return lv if lv is Array else []


func effects_for_level(level: int) -> Array:
	var out: Array = []
	for l in range(1, level + 1):
		out.append_array(effects_at_level(l))
	return out
