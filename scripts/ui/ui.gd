class_name UI
extends RefCounted
## Shared UI theme and small widget builders.

const PARCHMENT := Color("d8c8a8")
const GOLD := Color("f2d65a")
const BLOOD := Color("c8302a")
const DIM := Color("8a8078")
const SOUL := Color("7ee0ff")

static var _theme: Theme


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = Fx.font()
	t.default_font_size = 10
	var panel := _tex_box("res://assets/sprites/ui/panel.png", 6, 10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var b := _tex_box("res://assets/sprites/ui/button_%s.png" % st, 4, 0)
		b.content_margin_left = 10
		b.content_margin_right = 10
		b.content_margin_top = 4
		b.content_margin_bottom = 4
		t.set_stylebox(st, "Button", b)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD.darkened(0.2))
	t.set_color("font_focus_color", "Button", PARCHMENT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_font_size("font_size", "Button", 10)
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	for f in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
		t.set_font(f, "RichTextLabel", Fx.font())
	for f in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		t.set_font_size(f, "RichTextLabel", 9)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color("1a1216")
	slider_bg.content_margin_top = 2
	slider_bg.content_margin_bottom = 2
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = BLOOD
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	_theme = t
	return t


static func _tex_box(path: String, margin: int, content: int) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = load(path)
	b.texture_margin_left = margin
	b.texture_margin_right = margin
	b.texture_margin_top = margin
	b.texture_margin_bottom = margin
	b.content_margin_left = content
	b.content_margin_right = content
	b.content_margin_top = content
	b.content_margin_bottom = content
	return b


static func label(text: String, size := 10, color := PARCHMENT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size := 36, color := BLOOD) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", Fx.title_font())
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.01))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(text: String, cb: Callable, min_w := 120) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 18)
	b.pressed.connect(func() -> void:
		Audio.play("ui_click", -4.0)
		cb.call())
	b.mouse_entered.connect(func() -> void: Audio.play("ui_hover", -10.0))
	return b


static func rich(bbcode: String, width := 170.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(width, 0)
	r.text = bbcode
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func vbox(sep := 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## Full-screen centring container.
static func center() -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func texture_rect(tex: Texture2D, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func item_slot(it: Variant, size := 22.0) -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/sprites/ui/slot.png")
	sb.texture_margin_left = 3
	sb.texture_margin_right = 3
	sb.texture_margin_top = 3
	sb.texture_margin_bottom = 3
	slot.add_theme_stylebox_override("panel", sb)
	if it != null:
		var tr := texture_rect(WorldObjects.item_icon(it), Vector2(size - 6, size - 6))
		tr.position = Vector2(3, 3)
		tr.size = Vector2(size - 6, size - 6)
		slot.add_child(tr)
		var border := ColorRect.new()
		border.color = ItemDB.color_of(it)
		border.color.a = 0.5
		border.position = Vector2(2, size - 3)
		border.size = Vector2(size - 4, 1)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(border)
		if it["awakened"]:
			var aw := ColorRect.new()
			aw.color = SOUL
			aw.position = Vector2(size - 5, 2)
			aw.size = Vector2(3, 3)
			aw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(aw)
	return slot
