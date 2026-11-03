## A stand-in for art still to be painted (hero cut-outs, the Stranger, the strongbox, the portal): diagonal stripes, a
## dashed border and a mono label saying what goes here. When `res://art/ui/wanted/<slot>.png` exists it is drawn
## instead, fitted to the same box, so the artists fill the slot by dropping the file in. A slot that is a res:// path
## names its file outright (pass 68: a hero look's own title cut-out).
## Pass 122 (lane UIKIT_B), under Royale (W.royale()): the mock's placeholder tile, slate with a dashed inner border in
## pale white and the label in Rubik, 6 px corners (a painting, when the file exists, is drawn as before).
class_name WPlaceholder
extends Control

## The Royale tile's dashed line and its inset from the edge.
const ROYALE_DASH := Color(1, 1, 1, 0.28)
const ROYALE_INSET := 8.0

const ART_DIR := "res://art/ui/wanted/"
const SILHOUETTE := preload("res://ui/wanted/silhouette.gdshader")

var slot := ""
var label := ""
# the mock's repeating-linear-gradient(135deg, stripe 0 period/2, transparent period/2 period)
var stripe := Color(W.INK, 0.14)
var period := 28.0
var dash := Color(W.INK, 0.5)
var ink := W.INK
var tex: Texture2D
var label_px := 22
## The label in the middle (the small strongbox and portal boxes) rather than at the foot.
var centered := false
## The painting as a flat dark silhouette (a hero still to unlock).
var silhouette := false:
	set(v):
		silhouette = v
		if v:
			var m := ShaderMaterial.new()
			m.shader = SILHOUETTE
			material = m
		else:
			material = null
		queue_redraw()


static func make(p_slot: String, p_label: String, px: Vector2, dark: bool = false) -> WPlaceholder:
	var p := WPlaceholder.new()
	p.slot = p_slot
	p.label = p_label
	p.custom_minimum_size = px
	p.size = px
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dark:
		p.stripe = Color(W.PAPER, 0.08)
		p.dash = Color(W.PAPER, 0.4)
		p.ink = W.AGED
	if px.x < 300.0:
		# the small boxes: finer stripes, the label in the middle in ink-soft
		p.label_px = 18
		p.centered = true
		p.stripe = Color(W.INK, 0.12)
		p.period = 24.0
		p.dash = Color(W.INK, 0.5)
		p.ink = W.INK_SOFT
	# a slot may name its file outright (pass 68: a hero look's own cut-out, CharacterDef.title_path)
	var path := p_slot if p_slot.begins_with("res://") else ART_DIR + p_slot + ".png"
	if ResourceLoader.exists(path):
		p.tex = load(path)
	return p


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if tex:
		var ts := tex.get_size()
		var k := minf(r.size.x / ts.x, r.size.y / ts.y)
		var sz := ts * k
		draw_texture_rect(tex, Rect2((r.size - sz) * 0.5, sz), false)
		return
	var royale := W.royale()
	var dash_col := dash
	var dash_rect := r
	if royale:
		# the slate tile with its dashed line inside (no stripes)
		draw_style_box(R.flat(R.SLATE_DIM, R.RADIUS), r)
		dash_col = ROYALE_DASH
		dash_rect = r.grow(-ROYALE_INSET)
	else:
		# stripes at 45 degrees: bands period/2 wide, period apart across the stripe, the first band from the top-left corner
		var step := period * sqrt(2.0)
		var x := period * 0.25 * sqrt(2.0) - r.size.y - step * ceilf(r.size.x / step)
		while x < r.size.x + step:
			var a := Vector2(x, r.size.y)
			var b := Vector2(x + r.size.y, 0)
			var pts := W.clip_segment(a, b, r)
			if pts.size() == 2:
				draw_line(pts[0], pts[1], stripe, period * 0.5)
			x += step
	# dashed border
	var d := 10.0
	var g := 6.0
	var dr := dash_rect
	for e in [[dr.position, Vector2(dr.end.x, dr.position.y)], [Vector2(dr.end.x, dr.position.y), dr.end],
			[dr.end, Vector2(dr.position.x, dr.end.y)], [Vector2(dr.position.x, dr.end.y), dr.position]]:
		var p0: Vector2 = e[0]
		var p1: Vector2 = e[1]
		var len := p0.distance_to(p1)
		var dir := (p1 - p0) / len
		var t := 0.0
		while t < len:
			draw_line(p0 + dir * t, p0 + dir * minf(t + d, len), dash_col, 4.0)
			t += d + g
	if label != "":
		var f := W.serif(400) if royale else W.mono(500)
		var px := label_px
		var lines := label.split("\n")
		var lh := px * 1.4
		var y := r.size.y - 28.0 - lh * lines.size()
		if centered:
			y = (r.size.y - lh * lines.size()) * 0.5
		var col := R.SECONDARY if royale else ink
		for i in lines.size():
			var w := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			draw_string(f, Vector2((r.size.x - w) * 0.5, y + i * lh + f.get_ascent(px)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
