## The kit's one box (the mock's "nine-slice"): a flat fill, an ink border on the chosen sides, and a hard ink shadow
## offset down-right with no blur. `press` draws the box sitting on its shadow (a pressed button), and `inner` draws a
## band just inside the border (the brass outline of a held card, the ember outline of an evolution). Corners are
## square unless `radius` is set (the icon plates), then the box is drawn through a StyleBoxFlat.
## Pass 122 (lane UIKIT_A): while the Royale theme is on the same box draws itself the Royale way
## (_draw_royale), by what it is (royale_kind): a paper box is the slate panel (the gradient, a navy edge, a navy base
## straight down, the white lip, 6 px corners), an aged box the dimmer slate, a box with a button `role` ("gold", "green",
## "blue", "slate", "red", "locked") the two-tone button face on its coloured and navy base, "plate" the black info plate,
## and any other fill is kept as it is with navy where the ink was. The Wanted drawing is untouched while the switch is off.
## copy() is the faithful copy (Resource.duplicate() keeps no HardBox field); the Royale locked face and pressed copy are
## made with it, the Wanted ones keep duplicate() as they always were.
class_name HardBox
extends StyleBox

var fill := W.PAPER
var border := 5
var border_color := W.INK
## Which sides carry the border: left, top, right, bottom (a tab has no bottom, an edge pointer no right).
var sides := [true, true, true, true]
var shadow := 0
var shadow_color := W.INK
var radius := 0
var inner := 0
var inner_color := W.BRASS
var press := 0
## Pass 122: the Royale role ("" = by the fill; a button role, "plate", "panel" or "plain"), which corners round under
## Royale (top-left, top-right, bottom-right, bottom-left: a docked tab rounds its top two), and the held look of a box
## without a base (pressed() sets it: the face shows its inset shadow even when it cannot move).
var role := ""
var corners := [true, true, true, true]
var held := false
## Pass 122 (the review of lane UIHUD): false keeps the Wanted drawing under Royale too, as WBar.themed does (the
## banner's boxes: Garry keeps the banners as they are).
var themed := true
var _flat: StyleBoxFlat
var _flat_shadow: StyleBoxFlat


func _init() -> void:
	set_content_margin_all(0)


## What this box is under Royale (pass 122): "button" (a role of R.ROLES), "plate", "panel" (the slate panel: a paper
## fill, or asked for), "panel_dim" (an aged fill) or "plain" (any other fill, kept).
func royale_kind() -> String:
	if role != "":
		return "button" if R.ROLES.has(role) else role
	if fill.is_equal_approx(W.PAPER):
		return "panel"
	if fill.is_equal_approx(W.AGED):
		return "panel_dim"
	return "plain"


## The Royale drawing (pass 122): the base straight down (a button's in its role's base colour with a navy base under
## it, a panel's navy), the navy edge (the box's own width, at most R.PANEL_EDGE), the inside by kind, the inner band
## (brass reads gold), the whole thing pressed down by `press` with no base.
func _draw_royale(ci: RID, rect: Rect2) -> void:
	var kind := royale_kind()
	var r := rect
	var rad := radius if radius > 0 else R.RADIUS
	if kind == "plate":
		R.plate(ci, r, rad)
		return
	var edge := mini(border, R.PANEL_EDGE) if border > 0 else 0
	var edge_col := R.NAVY if (border_color.is_equal_approx(W.INK) or kind != "plain") else border_color
	var base_col := R.NAVY if (shadow_color.is_equal_approx(W.INK) or kind != "plain") else shadow_color
	if kind == "plain":
		_draw_royale_plain(ci, r, edge, edge_col, base_col)
		return
	if press > 0:
		r.position.y += press
	elif shadow > 0:
		if kind == "button":
			R.flat(base_col, rad, corners).draw(ci, Rect2(r.position + Vector2(0, shadow + R.BUTTON_NAVY_BASE), r.size))
			R.flat(R.role(role)["base"], rad, corners).draw(ci, Rect2(r.position + Vector2(0, shadow), r.size))
		else:
			R.flat(base_col, rad, corners).draw(ci, Rect2(r.position + Vector2(0, shadow), r.size))
	# the edge: the whole rounded box in navy, the opaque inside drawn over it (a side without a border lets the inside
	# reach the rect's edge there, as the Wanted box does: a tab's open bottom, a choice's shared middle line)
	if edge > 0:
		R.flat(edge_col, rad, corners).draw(ci, r)
	var inner_r := Rect2(r.position + Vector2(edge if sides[0] else 0, edge if sides[1] else 0),
		r.size - Vector2((edge if sides[0] else 0) + (edge if sides[2] else 0), (edge if sides[1] else 0) + (edge if sides[3] else 0)))
	if inner_r.size.x <= 0.0 or inner_r.size.y <= 0.0:
		return
	match kind:
		"button":
			R.button_fill(ci, inner_r, role, press > 0 or held)
		"panel_dim":
			if edge > 0:
				RenderingServer.canvas_item_add_rect(ci, inner_r, R.SLATE_DIM)
			else:
				R.flat(R.SLATE_DIM, rad, corners).draw(ci, inner_r)
		_:
			if edge > 0:
				R.panel_fill(ci, inner_r)
			else:
				R.flat(R.SLATE_MID, rad, corners).draw(ci, inner_r)
				R.lip(ci, inner_r, R.PANEL_LIP, R.PANEL_LIP_PX)
	_draw_royale_inner(ci, inner_r)


## A plain box under Royale (pass 122): the Wanted construction (the fill, the border strips on `sides`, the inner band)
## with navy where the ink was and the base straight down; a see-through fill stays see-through; an opaque box with a
## `radius` (an icon plate) keeps its rounded corners.
func _draw_royale_plain(ci: RID, rect: Rect2, edge: int, edge_col: Color, base_col: Color) -> void:
	var r := rect
	if radius > 0 and fill.a >= 1.0:
		if press > 0:
			r.position.y += press
		elif shadow > 0:
			R.flat(base_col, radius, corners).draw(ci, Rect2(r.position + Vector2(0, shadow), r.size))
		if edge > 0:
			R.flat(edge_col, radius, corners).draw(ci, r)
		var inner_r := Rect2(r.position + Vector2(edge if sides[0] else 0, edge if sides[1] else 0),
			r.size - Vector2((edge if sides[0] else 0) + (edge if sides[2] else 0), (edge if sides[1] else 0) + (edge if sides[3] else 0)))
		if inner_r.size.x > 0.0 and inner_r.size.y > 0.0:
			R.flat(fill, maxi(radius - edge, 0), corners).draw(ci, inner_r)
			_draw_royale_inner(ci, inner_r)
		return
	if press > 0:
		r.position.y += press
	elif shadow > 0:
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(0, shadow), r.size), base_col)
	if fill.a > 0.0:
		RenderingServer.canvas_item_add_rect(ci, r, fill)
	if edge > 0:
		var b := float(edge)
		if sides[0]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(b, r.size.y)), edge_col)
		if sides[1]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, b)), edge_col)
		if sides[2]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - b, r.position.y), Vector2(b, r.size.y)), edge_col)
		if sides[3]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - b), Vector2(r.size.x, b)), edge_col)
	_draw_royale_inner(ci, r.grow(-float(edge)))


## The inner band under Royale (pass 122): the Wanted `inner` px inside the edge, brass reading as the kit's gold.
func _draw_royale_inner(ci: RID, inner_r: Rect2) -> void:
	if inner <= 0 or inner_r.size.x <= 0.0 or inner_r.size.y <= 0.0:
		return
	var i := float(inner)
	var ic: Color = R.role("gold")["bottom"] if inner_color.is_equal_approx(W.BRASS) else inner_color
	RenderingServer.canvas_item_add_rect(ci, Rect2(inner_r.position, Vector2(i, inner_r.size.y)), ic)
	RenderingServer.canvas_item_add_rect(ci, Rect2(inner_r.position, Vector2(inner_r.size.x, i)), ic)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(inner_r.end.x - i, inner_r.position.y), Vector2(i, inner_r.size.y)), ic)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(inner_r.position.x, inner_r.end.y - i), Vector2(inner_r.size.x, i)), ic)


func _draw(ci: RID, rect: Rect2) -> void:
	if themed:
		_draw_royale(ci, rect)
		return
	var r := rect
	if press > 0:
		r.position += Vector2(press, press)
	elif shadow > 0:
		if radius > 0:
			_flat_box(true).draw(ci, Rect2(r.position + Vector2(shadow, shadow), r.size))
		else:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(shadow, shadow), r.size), shadow_color)
	if radius > 0:
		_flat_box(false).draw(ci, r)
		return
	if fill.a > 0.0:
		RenderingServer.canvas_item_add_rect(ci, r, fill)
	if border > 0:
		var b := float(border)
		if sides[0]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(b, r.size.y)), border_color)
		if sides[1]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, b)), border_color)
		if sides[2]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - b, r.position.y), Vector2(b, r.size.y)), border_color)
		if sides[3]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - b), Vector2(r.size.x, b)), border_color)
	if inner > 0:
		var o := float(border)
		var i := float(inner)
		var ir := r.grow(-o)
		RenderingServer.canvas_item_add_rect(ci, Rect2(ir.position, Vector2(i, ir.size.y)), inner_color)
		RenderingServer.canvas_item_add_rect(ci, Rect2(ir.position, Vector2(ir.size.x, i)), inner_color)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(ir.end.x - i, ir.position.y), Vector2(i, ir.size.y)), inner_color)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(ir.position.x, ir.end.y - i), Vector2(ir.size.x, i)), inner_color)


func _flat_box(for_shadow: bool) -> StyleBoxFlat:
	var f := _flat_shadow if for_shadow else _flat
	if f == null:
		f = StyleBoxFlat.new()
		f.anti_aliasing = true
		if for_shadow:
			_flat_shadow = f
		else:
			_flat = f
	f.set_corner_radius_all(radius)
	if for_shadow:
		f.bg_color = shadow_color
		f.set_border_width_all(0)
	else:
		f.bg_color = fill
		f.border_color = border_color
		f.border_width_left = border if sides[0] else 0
		f.border_width_top = border if sides[1] else 0
		f.border_width_right = border if sides[2] else 0
		f.border_width_bottom = border if sides[3] else 0
	return f


## A copy with every field carried (pass 122, the review of lane UIKIT_A): Resource.duplicate() copies only exported
## properties, so a duplicated HardBox comes back at the defaults (paper, a 5 px border, no shadow, square, no role:
## game/tools/_p122_UIKIT_dupprobe.gd). The content margins come with duplicate(); the rest is assigned by hand, the arrays
## as their own copies. The Royale paths use it (WTap's locked face, pressed()); the Wanted ones keep duplicate(), so the
## Wanted drawing stays pixel-identical.
func copy() -> HardBox:
	var c: HardBox = duplicate()
	c.fill = fill
	c.border = border
	c.border_color = border_color
	c.sides = sides.duplicate()
	c.shadow = shadow
	c.shadow_color = shadow_color
	c.radius = radius
	c.inner = inner
	c.inner_color = inner_color
	c.press = press
	c.role = role
	c.corners = corners.duplicate()
	c.held = held
	c.themed = themed
	return c


## A copy that sits on its own shadow: pressed. Pass 122, under Royale: the box goes straight down by its base (at most
## R.PRESS_DOWN), the content with it, and the face shows its inset shadow (`held`) even with no base to lose; the copy is
## copy(), so a tab-shaped, rounded or thin-bordered box keeps its shape while held. Wanted keeps duplicate() as before.
func pressed(fill_override: Color = Color(0, 0, 0, 0)) -> HardBox:
	var p: HardBox = copy()
	p.role = role   # pass 122 (lane UIKIT_B): Wanted's duplicate() copies no script variable; the role is carried by hand (Wanted ignores it)
	p.press = maxi(shadow, 0)
	if fill_override.a > 0.0:
		p.fill = fill_override
	p.press = mini(p.press, R.PRESS_DOWN)
	p.held = true
	p.content_margin_top = content_margin_top + p.press
	p.content_margin_bottom = content_margin_bottom - p.press
	return p


func pad(l: float, t: float, r: float, b: float) -> HardBox:
	content_margin_left = l
	content_margin_top = t
	content_margin_right = r
	content_margin_bottom = b
	return self
