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


func kind() -> String:
	return "passive"


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
