## The camera cutout's band on every screen (pass 47d painted it in ink under the in-run HUD only; pass 49, Garry: "add the
## same black fill in the area where we did that in the Gameplay HUD in every other screen"). An autoload on its own canvas
## layer above every screen, menu, modal and the scene fade: an ink strip from the top of the screen down to W.safe_top()
## (the display's safe area under a camera cutout, or Settings.top_inset from the developer menu), refitted when that
## changes. Touches go through it; with no cutout it is not drawn at all.
extends CanvasLayer

## Above the game's UI and UiFx's fade (100).
const LAYER := 110

var _band: ColorRect
var _h := -1.0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_band = ColorRect.new()
	_band.name = "Band"
	_band.color = W.INK
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(_band)
	_fit()


func _process(_delta: float) -> void:
	_fit()


## The band as tall as the cutout is now (the developer menu's inset and the window can change it).
func _fit() -> void:
	var h := W.safe_top()
	if absf(h - _h) < 0.5:
		return
	_h = h
	_band.offset_top = 0.0
	_band.offset_bottom = h
	_band.visible = h > 0.0


## How tall the band is drawn now, in canvas px (tests).
func height() -> float:
	return maxf(_h, 0.0) if _band and _band.visible else 0.0
