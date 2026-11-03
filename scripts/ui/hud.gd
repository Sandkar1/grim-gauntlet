class_name HUD
extends CanvasLayer
## In-game HUD: life & mana orbs, flask belt, skill, XP, floor progress,
## boss bar, interaction prompt with item tooltip, and message feed.

var run: Node
var root: Control
var life_orb: Orb
var mana_orb: Orb
var belt: HBoxContainer
var skill_icon: SkillIcon
var xp_bar: Bar
var gold_label: Label
var floor_label: Label
var room_label: Label
var path_box: HBoxContainer
var boss_box: Control
var boss_bar: Bar
var boss_name: Label
var prompt_label: RichTextLabel
var tooltip: PanelContainer
var tooltip_text: RichTextLabel
var messages: VBoxContainer
var levelup_label: Label
var banner: Label
var banner_sub: Label
var post: ColorRect
var _boss: Node = null
var _t := 0.0
var _tooltip_id := -1
var _mana_flash := 0.0
var _belt_key := Vector3(-1, -1, -1)


func _ready() -> void:
	layer = 10
	# Vignette / grain / hurt overlay, below the HUD itself.
	var post_layer := CanvasLayer.new()
	post_layer.layer = 5
	add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/post.gdshader")
	post.material = sm
	post_layer.add_child(post)

	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)

	life_orb = Orb.new()
	life_orb.liquid = Color(0.62, 0.06, 0.07)
	life_orb.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	life_orb.position = Vector2(6, -62)
	life_orb.size = Vector2(56, 56)
	root.add_child(life_orb)
	mana_orb = Orb.new()
	mana_orb.liquid = Color(0.12, 0.2, 0.62)
	mana_orb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mana_orb.position = Vector2(-62, -62)
	mana_orb.size = Vector2(56, 56)
	root.add_child(mana_orb)

	# Belt: flasks + skill, bottom centre.
	var belt_panel := PanelContainer.new()
	belt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	belt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	belt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	belt_panel.position.y = -8
	belt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(belt_panel)
	belt = UI.hbox(3)
	belt_panel.add_child(belt)
	skill_icon = SkillIcon.new()
	skill_icon.custom_minimum_size = Vector2(20, 20)
	skill_icon.tex = load("res://assets/sprites/ui/skill_%s.png" % Game.class_data()["skill"])

	xp_bar = Bar.new()
	xp_bar.fill = Color(0.75, 0.62, 0.25)
	xp_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	xp_bar.position = Vector2(-110, -6)
	xp_bar.size = Vector2(220, 3)
	root.add_child(xp_bar)
	levelup_label = UI.label("", 9, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	levelup_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	levelup_label.position = Vector2(-110, -50)
	levelup_label.size = Vector2(220, 12)
	root.add_child(levelup_label)

	# Top-left: floor name, chamber, gold.
	var tl := UI.vbox(0)
	tl.position = Vector2(8, 4)
	root.add_child(tl)
	floor_label = UI.title("", 18, Color("c8b898"))
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tl.add_child(floor_label)
	room_label = UI.label("", 8, UI.DIM)
	tl.add_child(room_label)
	var gold_row := UI.hbox(3)
	gold_row.add_child(UI.texture_rect(load("res://assets/sprites/items/coin.png"), Vector2(10, 10)))
	gold_label = UI.label("0", 10, UI.GOLD)
	gold_row.add_child(gold_label)
	tl.add_child(gold_row)

	# Top-right: rooms walked this floor.
	path_box = UI.hbox(2)
	path_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	path_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	path_box.position = Vector2(-8, 8)
	root.add_child(path_box)

	# Boss bar.
	boss_box = Control.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.position = Vector2(-150, 24)
	boss_box.size = Vector2(300, 30)
	boss_box.visible = false
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boss_box)
	boss_name = UI.title("", 18, Color("e8d8b8"))
	boss_name.size = Vector2(300, 18)
	boss_name.position = Vector2(0, -6)
	boss_box.add_child(boss_name)
	boss_bar = Bar.new()
	boss_bar.fill = Color(0.65, 0.08, 0.08)
	boss_bar.position = Vector2(0, 18)
	boss_bar.size = Vector2(300, 6)
	boss_bar.frame = true
	boss_box.add_child(boss_bar)

	# Interaction prompt + tooltip.
	prompt_label = UI.rich("", 400)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-200, -64)
	prompt_label.size = Vector2(400, 14)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)
	tooltip = PanelContainer.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	root.add_child(tooltip)
	tooltip_text = UI.rich("", 172)
	tooltip.add_child(tooltip_text)

	messages = UI.vbox(1)
	messages.set_anchors_preset(Control.PRESET_CENTER_TOP)
	messages.position = Vector2(-160, 62)
	messages.size = Vector2(320, 100)
	messages.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(messages)

	banner = UI.title("", 36, UI.BLOOD)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.position = Vector2(-300, -60)
	banner.size = Vector2(600, 40)
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_sub = UI.label("", 10, Color("b8a888"), HORIZONTAL_ALIGNMENT_CENTER)
	banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	banner_sub.position = Vector2(-300, -16)
	banner_sub.size = Vector2(600, 14)
	banner_sub.modulate.a = 0.0
	root.add_child(banner_sub)

	Game.notify.connect(message)
	Game.equipment_changed.connect(_refresh_tooltip_force)
	_rebuild_belt()


func _process(delta: float) -> void:
	_t += delta
	var s := Game.stats
	life_orb.value = clampf(Game.hp / s["max_hp"], 0.0, 1.0)
	life_orb.text = "%d" % ceili(Game.hp)
	mana_orb.value = clampf(Game.mana / s["max_mana"], 0.0, 1.0)
	mana_orb.text = "%d" % int(Game.mana)
	_mana_flash = maxf(0.0, _mana_flash - delta * 3.0)
	mana_orb.flash = _mana_flash
	life_orb.low = Game.hp < s["max_hp"] * 0.3
	xp_bar.value = float(Game.xp) / Game.xp_to_next()
	gold_label.text = str(Game.gold)
	if Game.pending_levels > 0:
		levelup_label.text = "Level up!  (blessing after the fight)" if Game.pending_levels == 1 else "Level up x%d!  (blessings after the fight)" % Game.pending_levels
		levelup_label.modulate.a = 0.6 + 0.4 * sin(_t * 5.0)
	else:
		levelup_label.text = ""
	if run != null and run.player != null:
		var cls := Game.class_data()
		skill_icon.ready_pct = clampf(Game.mana / cls["skill_cost"], 0.0, 1.0)
	if _boss != null and is_instance_valid(_boss):
		boss_bar.value = clampf(_boss.hp / _boss.max_hp, 0.0, 1.0)
	var key := Vector3(Game.stat("flask_max"), Game.flask_charges, snappedf(Game.flask_progress, 0.05))
	if key != _belt_key:
		_belt_key = key
		_rebuild_belt()
	_update_interact()
	var i := 0
	while i < messages.get_child_count():
		var m: Label = messages.get_child(i)
		var age: float = m.get_meta("age") + delta
		m.set_meta("age", age)
		m.modulate.a = clampf(3.5 - age, 0.0, 1.0)
		if age > 3.5:
			m.queue_free()
		i += 1


func _rebuild_belt() -> void:
	if belt == null:
		return
	for c in belt.get_children():
		belt.remove_child(c)
		if c != skill_icon:
			c.queue_free()
	var flask_tex: Texture2D = load("res://assets/sprites/items/flask.png")
	var maxf_ := int(Game.stat("flask_max"))
	for i in maxf_:
		var f := FlaskIcon.new()
		f.tex = flask_tex
		f.full = i < Game.flask_charges
		f.partial = Game.flask_progress if i == Game.flask_charges else 0.0
		f.custom_minimum_size = Vector2(14, 20)
		belt.add_child(f)
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(4, 18)
	belt.add_child(sep)
	belt.add_child(skill_icon)


func update_room_info() -> void:
	var fd := Game.floor_data()
	floor_label.text = fd["name"]
	var total := Game.ROOMS_PER_FLOOR
	if run.room_type == "boss":
		room_label.text = "Floor %d  -  The Lair" % (Game.floor_idx + 1)
	elif Game.room_idx == 0:
		room_label.text = "Floor %d  -  Threshold" % (Game.floor_idx + 1)
	else:
		room_label.text = "Floor %d  -  Chamber %d of %d" % [Game.floor_idx + 1, mini(Game.room_idx, total), total]
	for c in path_box.get_children():
		c.queue_free()
	var icons: Texture2D = load("res://assets/sprites/ui/room_icons.png")
	var order := ["combat", "elite", "treasure", "shop", "shrine", "rest", "boss", "start"]
	var steps: Array = Game.room_history.duplicate()
	for i in range(steps.size(), total + 2):
		steps.append("?" if i < total + 1 else "boss")
	for i in steps.size():
		var st: String = steps[i]
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(10, 10)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if st == "?":
			var dot := ColorRect.new()
			dot.color = Color(0.35, 0.3, 0.3, 0.7)
			dot.custom_minimum_size = Vector2(3, 3)
			var cc := CenterContainer.new()
			cc.custom_minimum_size = Vector2(6, 10)
			cc.add_child(dot)
			path_box.add_child(cc)
			continue
		var at := AtlasTexture.new()
		at.atlas = icons
		at.region = Rect2(order.find(st) * 14, 0, 14, 14)
		tr.texture = at
		var current := i == Game.room_history.size() - 1
		tr.modulate = Color.WHITE if current else (Color(0.6, 0.55, 0.55) if i < Game.room_history.size() else Color(0.35, 0.3, 0.3))
		if current:
			tr.custom_minimum_size = Vector2(13, 13)
		path_box.add_child(tr)


func _update_interact() -> void:
	var it = run.current_interact if run != null else null
	if it == null or not is_instance_valid(it) or it.is_queued_for_deletion():
		prompt_label.text = ""
		tooltip.visible = false
		_tooltip_id = -1
		return
	var txt: String = "[color=#f2d65a][E][/color] " + it.prompt()
	var alt: String = it.alt_prompt()
	if alt != "":
		txt += "     [color=#f2d65a][F][/color] " + alt
	prompt_label.text = "[center]%s[/center]" % txt
	var item = it.tooltip_item()
	if item == null:
		tooltip.visible = false
		_tooltip_id = -1
		return
	if item["id"] != _tooltip_id:
		_tooltip_id = item["id"]
		var cur = Game.equipment.get(item["slot"])
		var t := ItemDB.describe(item, cur)
		if cur != null:
			t += "\n\n[color=#6a6058]Replaces:[/color] [color=#%s]%s[/color]" % [ItemDB.hex(ItemDB.color_of(cur)), cur["name"]]
		else:
			t += "\n\n[color=#7ad46a]Empty slot[/color]"
		tooltip_text.text = t
		tooltip.reset_size()
	tooltip.visible = true
	var vp := root.get_viewport_rect().size
	tooltip.position = Vector2(vp.x - tooltip.size.x - 10, clampf(vp.y * 0.5 - tooltip.size.y * 0.5, 40.0, vp.y - tooltip.size.y - 70.0))


func _refresh_tooltip_force() -> void:
	_tooltip_id = -1


func message(text: String, color := UI.PARCHMENT) -> void:
	var l := UI.label(text, 10, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.02))
	l.add_theme_constant_override("outline_size", 4)
	l.set_meta("age", 0.0)
	messages.add_child(l)
	if messages.get_child_count() > 5:
		messages.get_child(0).queue_free()


func show_banner(text: String, sub := "", color := UI.BLOOD, dur := 2.6) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner_sub.text = sub
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.6)
	tw.parallel().tween_property(banner_sub, "modulate:a", 1.0, 0.9)
	tw.tween_interval(dur)
	tw.tween_property(banner, "modulate:a", 0.0, 1.0)
	tw.parallel().tween_property(banner_sub, "modulate:a", 0.0, 1.0)


func show_boss(b: Node) -> void:
	_boss = b
	boss_name.text = b.data["name"]
	boss_box.visible = true
	boss_box.modulate.a = 0.0
	create_tween().tween_property(boss_box, "modulate:a", 1.0, 1.0)


func hide_boss() -> void:
	_boss = null
	create_tween().tween_property(boss_box, "modulate:a", 0.0, 1.0)


func damage_flash() -> void:
	var sm: ShaderMaterial = post.material
	sm.set_shader_parameter("hurt", 0.9)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: sm.set_shader_parameter("hurt", v), 0.9, 0.0, 0.5)


func flash_mana() -> void:
	_mana_flash = 1.0
	Audio.play("ui_click", -6.0, 0.0, 0.6)


# ---------------------------------------------------------------------------
# Widgets
# ---------------------------------------------------------------------------

## Diablo-style liquid orb.
class Orb extends Control:
	var value := 1.0
	var shown := 1.0
	var liquid := Color.RED
	var text := ""
	var low := false
	var flash := 0.0
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta
		shown = move_toward(shown, value, delta * 1.5)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, r + 4.0, Color("1a1214"))
		draw_arc(c, r + 3.0, 0.0, TAU, 48, Color("6a5432"), 2.0)
		draw_arc(c, r + 4.0, 0.0, TAU, 48, Color("0c0808"), 1.0)
		draw_circle(c, r, Color(0.03, 0.02, 0.03))
		var level := c.y + r - 2.0 * r * shown
		var y0 := int(floor(level))
		for y in range(y0, int(c.y + r) + 1):
			var dy := float(y) + 0.5 - c.y
			if absf(dy) > r:
				continue
			var hw := sqrt(r * r - dy * dy)
			var depth := (float(y) - level) / (2.0 * r)
			var col := liquid.lightened(0.15).lerp(liquid.darkened(0.45), clampf(depth * 1.6, 0.0, 1.0))
			if low:
				col = col.lightened(0.15 * (0.5 + 0.5 * sin(t * 8.0)))
			col = col.lerp(Color.WHITE, flash * 0.5)
			var wave := sin(t * 3.0 + float(y) * 0.3) * 0.6
			draw_line(Vector2(c.x - hw + wave, y), Vector2(c.x + hw + wave, y), col, 1.0)
		if shown > 0.02 and shown < 0.99:
			var dy := level - c.y
			var hw := sqrt(maxf(0.0, r * r - dy * dy))
			draw_line(Vector2(c.x - hw, level), Vector2(c.x + hw, level), liquid.lightened(0.45), 1.0)
		draw_arc(c + Vector2(-r * 0.25, -r * 0.25), r * 0.55, PI * 1.05, PI * 1.45, 12, Color(1, 1, 1, 0.22), 2.0)
		var f := Fx.bold_font()
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tp := (c + Vector2(-tw * 0.5, 5)).round()
		draw_string_outline(f, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 5, Color(0, 0, 0, 0.95))
		draw_string(f, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.97, 0.9))


class Bar extends Control:
	var value := 0.0
	var shown := 0.0
	var fill := Color.WHITE
	var frame := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		shown = move_toward(shown, value, delta * 2.0) if shown > value else value
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2(-1, -1), size + Vector2(2, 2)), Color(0.02, 0.01, 0.02, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.08, 0.08, 0.9))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * shown, size.y)), Color(0.9, 0.85, 0.75, 0.6))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, size.y)), fill)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, 1)), fill.lightened(0.3))
		if frame:
			draw_rect(Rect2(Vector2(-2, -2), size + Vector2(4, 4)), Color("6a5432"), false, 1.0)


class FlaskIcon extends Control:
	var tex: Texture2D
	var full := true
	var partial := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(-1, 2), Vector2(16, 16))
		if full:
			draw_texture_rect(tex, r, false)
		else:
			draw_texture_rect(tex, r, false, Color(0.25, 0.2, 0.2, 0.8))
			if partial > 0.0:
				var h := 12.0 * partial
				draw_rect(Rect2(Vector2(4, 16 - h), Vector2(6, h)), Color(0.6, 0.08, 0.08, 0.8))


class SkillIcon extends Control:
	var tex: Texture2D
	var ready_pct := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2(-1, -1), size + Vector2(2, 2)), Color("6a5432"))
		draw_texture_rect(tex, Rect2(Vector2(1, 1), size - Vector2(2, 2)), false)
		if ready_pct < 1.0:
			draw_rect(Rect2(Vector2(1, 1), Vector2(size.x - 2, (size.y - 2) * (1.0 - ready_pct))), Color(0, 0, 0.1, 0.7))
		var f := Fx.font()
		draw_string_outline(f, Vector2(size.x - 6, size.y), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color.BLACK)
		draw_string(f, Vector2(size.x - 6, size.y), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UI.PARCHMENT)
