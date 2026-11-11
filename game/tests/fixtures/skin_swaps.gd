## Pass 141 (lane TRAIL): the two skins lane ART replaces (tools/dl/p141/COMMON.md): Astro's AST-B makes way for AST-D
## Splashdown (the Trail's skin node), Solenne's SOL-H for SOL-I Oasis (her task chain, 4,500 gold). The lead switches them
## with tools/dl/p141/TRAIL/retarget_skins.py once the looks are installed; a test that names one of these skins asks
## here which code stands now, so it passes before and after.
##   const SWAPS := preload("res://tests/fixtures/skin_swaps.gd")
##   SWAPS.now("astro", "AST-B")      "AST-D" once the switch is made, else "AST-B"
##   SWAPS.table()                     the table (the script's own when tools/dl is there: it is git-ignored)
extends RefCounted

const SCRIPT := "../tools/dl/p141/TRAIL/retarget_skins.py"
## A copy of the script's TABLE (pass141_trail_test pins that the two agree wherever the script is on disk).
const TABLE := [
	{"hero": "astro", "old": "AST-B", "new": "AST-D", "name": "Splashdown", "price": 3000, "via": "trail"},
	{"hero": "solenne", "old": "SOL-H", "new": "SOL-I", "name": "Oasis", "price": 4500, "via": "task",
		"quest_old": "skin_solenne_sol_h", "quest_new": "skin_solenne_sol_i", "quest_name": "Solenne · Oasis"},
]


## The script's TABLE (the JSON between its TABLE-BEGIN and TABLE-END markers), else the copy above.
static func table() -> Array:
	var got := script_table()
	return got if not got.is_empty() else TABLE


## The script's own TABLE; [] when the script is not on disk (a checkout without tools/dl).
static func script_table() -> Array:
	var path := ProjectSettings.globalize_path("res://").path_join(SCRIPT).simplify_path()
	if not FileAccess.file_exists(path):
		return []
	var text := FileAccess.get_file_as_string(path)
	var a := text.find("json.loads(r'''")
	var b := text.find("''')", a)
	if a < 0 or b < 0:
		return []
	var data: Variant = JSON.parse_string(text.substr(a + 15, b - a - 15))
	return data if data is Array else []


## Whether the switch of entry `e` is made: its new look is in its outlaw's file and sold as a skin.
static func done(e: Dictionary) -> bool:
	var c: CharacterDef = Registry.character(str(e["hero"]))
	return c != null and c.variants.has(str(e["new"])) and not c.skin_of(str(e["new"])).is_empty()


## The code that stands for look `code` of outlaw `hero` now: the new one once its switch is made.
static func now(hero: String, code: String) -> String:
	for e: Dictionary in table():
		if str(e["hero"]) == hero and str(e["old"]) == code and done(e):
			return str(e["new"])
	return code
