## Base class for every content item. A content item is a folder under res://content/<type>/<id>/
## holding <id>.json (authoring source), <id>.tres (this resource, editor-editable),
## optionally <id>_visual.tscn and <id>_icon.png.
class_name ContentDef
extends Resource

## The rarity tiers, lowest first (pass 47: uncommon and legendary joined common, rare and epic).
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]

@export var id: String = ""
@export var display_name: String = ""
## Optional flavour line shown under the generated description.
@export var flavour: String = ""
## common | uncommon | rare | epic | legendary (pass 47: five tiers, RARITIES). Weighs the card and chest offers
## (CardPool.RARITY_W, with luck lifting the higher tiers); a passive item shows it as its plate's colour.
@export var rarity: String = "common"
## "poison" | "fire" | "": the element the item carries (weapons derive it from their base stats); since pass 36 a run may
## hold both
@export var element: String = ""
## Relative weight in card pools.
@export var weight: float = 10.0
## Kept in the content but out of play (pass 34, any kind; heroes since pass 33.4): never offered, and the collection
## lists it apart. Registry.is_hidden also hides what only a hidden thing brings (its evolution, its paths, its perks).
@export var hidden: bool = false
## The first stage (1-based) whose offers may hold it; 0 = any (pass 43: the hell items appear on stage 3 only).
@export var from_stage: int = 0
## Icon texture. Required by the rule; Registry substitutes a letter tile when missing.
@export var icon: Texture2D
## File name of the icon inside the content folder, kept so re-import can resolve it.
@export var icon_file: String = ""
## Hints for tools/gen_placeholders.gd: colour, shape, ears, size. Free-form.
@export var placeholder: Dictionary = {}
## Folder this item was loaded from, e.g. res://content/weapons/boomstick/. Set by Registry.
var source_dir: String = ""


func kind() -> String:
	return "content"


func has_icon() -> bool:
	return icon != null
