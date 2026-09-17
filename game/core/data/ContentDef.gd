## Base class for every content item. A content item is a folder under res://content/<type>/<id>/
## holding <id>.json (authoring source), <id>.tres (this resource, editor-editable),
## optionally <id>_visual.tscn and <id>_icon.png.
class_name ContentDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
## Optional flavour line shown under the generated description.
@export var flavour: String = ""
## common | rare | epic. Affects card weight and backplate.
@export var rarity: String = "common"
## "poison" | "fire" | "": items of one element never share a run with the other (weapons derive it from their base stats)
@export var element: String = ""
## Relative weight in card pools.
@export var weight: float = 10.0
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
