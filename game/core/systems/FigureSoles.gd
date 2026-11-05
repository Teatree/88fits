## Pass 127: where a hero look's painted soles end, frame by frame, in its idle cycles: art/ui/figure_soles.json, written by
## tools/figure_soles.py (ship.sh runs it) so the main menu never decodes a strip to measure it. The idle frames squeeze a little
## about the figure's middle, so his soles rise and fall with them; ui/TitleScreen.gd's HeroFigure draws each frame so they stay on
## the shadow's line. A look with no row (a new one, before the next run of the tool) plays on TitleStage.FIGURE_SOLE as before.
class_name FigureSoles
extends RefCounted

const PATH := "res://art/ui/figure_soles.json"

static var _table: Dictionary = {}
static var _read := false


## The strip's rows {anim: [sole of each frame, 0 top .. 1 foot of the frame]}, {} when the table has none.
static func of(tex: Texture2D) -> Dictionary:
	if tex == null or tex.resource_path == "":
		return {}
	if not _read:
		_read = true
		if FileAccess.file_exists(PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if parsed is Dictionary:
				_table = parsed
	var row = _table.get(tex.resource_path)
	return row if row is Dictionary else {}
