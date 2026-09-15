## Permanent upgrades. Every row is a ShopUpgradeDef: effect per tier, costs, tier pips, big buy button, refund all.
extends ScreenBase

var _gold: Label


func build() -> void:
	set_title("Shop")
	_gold = UiKit.label("", 34, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	header.add_child(_gold)
	_refresh()


func _refresh() -> void:
	_gold.text = "%d gold" % Save.gold()
	clear_content()
	for def in Registry.sorted_shop():
		content.add_child(_row(def))
	content.add_child(UiKit.spacer(10))
	var refund := UiKit.button("Refund everything", 28, false, 90)
	refund.pressed.connect(func():
		var r := Save.refund_all()
		Audio.play("ui_buy")
		_refresh())
	content.add_child(refund)
	content.add_child(UiKit.label("Refunds return all gold spent so experimenting is free.", 22, UiKit.INK3, HORIZONTAL_ALIGNMENT_CENTER))


func _row(def: ShopUpgradeDef) -> Control:
	var tier := Save.tier(def.id)
	var maxed := tier >= def.tiers()
	var cost := def.cost_of_tier(tier)
	var p := UiKit.panel(UiKit.BG2, 24, UiKit.LINE, 2)
	var h := UiKit.hbox(20)
	p.add_child(h)
	var ic := UiKit.icon_view(def, 100, "shop")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UiKit.vbox(4)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(UiKit.label(def.display_name, 36, UiKit.INK))
	var per := def.effect_text if def.effect_text != "" else (TextGen.describe_effect(def.effect_per_tier) if def.effect_per_tier else "")
	v.add_child(UiKit.label("%s per tier · %d / %d" % [per, tier, def.tiers()], 24, UiKit.INK2))
	if tier > 0 and def.effect_per_tier:
		v.add_child(UiKit.label("Now: " + TextGen.describe_effects(TextGen._sum_effects(def.effects_for_tiers(tier))), 22, UiKit.ACCENT))
	v.add_child(UiKit.pip_row(tier, def.tiers(), 240))
	h.add_child(v)
	var b := UiKit.button("MAX" if maxed else str(cost), 30, not maxed and Save.gold() >= cost, 96)
	b.custom_minimum_size = Vector2(200, 96)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = maxed
	b.pressed.connect(func():
		if Save.buy_tier(def):
			Audio.play("ui_buy")
		else:
			Audio.play("ui_locked")
		_refresh())
	h.add_child(b)
	return p
