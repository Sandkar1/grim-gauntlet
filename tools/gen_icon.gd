extends SceneTree
## Run: godot --headless --path . --script res://tools/gen_icon.gd
# Builds a 64x64 window icon from the boss room sigil.
func _init():
	var strip := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/ui/room_icons.png"))
	var skull := strip.get_region(Rect2i(6 * 14, 0, 14, 14))
	skull.resize(56, 56, Image.INTERPOLATE_NEAREST)
	var icon := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	icon.fill(Color("120a0d"))
	icon.blend_rect(skull, Rect2i(0, 0, 56, 56), Vector2i(4, 4))
	icon.save_png(ProjectSettings.globalize_path("res://assets/icon.png"))
	quit()
