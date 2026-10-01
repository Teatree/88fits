## The old meta shop. The Mirror replaced it (ui/HomesteadScreen.gd): this screen only forwards, so any old route or
## saved deep link still lands somewhere sensible.
extends ScreenBase


func build() -> void:
	set_title("Upgrade")
	content.add_child(UiKit.label("The shop is the Upgrade board now.", 30, UiKit.INK))
	var go := UiKit.button("Open Upgrade", 30, true, 84)
	go.pressed.connect(func(): UiFx.go(get_tree(), "res://ui/HomesteadScreen.tscn"))
	content.add_child(go)
