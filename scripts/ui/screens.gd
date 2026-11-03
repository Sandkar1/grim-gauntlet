class_name Screens
extends RefCounted
## Full-screen menus: title, class selection, and the end-of-run screen.


## Dark backdrop with drifting embers, shared by all screens.
class Backdrop extends Control:
	var embers: Array = []
	var t := 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 70:
			embers.append(_new_ember(true))

	func _new_ember(anywhere: bool) -> Array:
		var vp := Vector2(640, 360)
		return [Vector2(randf() * vp.x, (randf() * vp.y) if anywhere else vp.y + 4.0),
			randf_range(8.0, 26.0), randf_range(0.6, 2.0), randf() * TAU, randf_range(0.4, 1.0)]

	func _process(delta: float) -> void:
		t += delta
		for e: Array in embers:
			e[0].y -= e[1] * delta
			e[0].x += sin(t * e[2] + e[3]) * 8.0 * delta
			if e[0].y < -4.0:
				e.assign(_new_ember(false))
		queue_redraw()

	func _draw() -> void:
		var vp := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.025, 0.015, 0.02))
		var g := Fx.glow_texture()
		var flick := 0.85 + 0.1 * sin(t * 7.0) + 0.05 * sin(t * 17.0)
		draw_texture_rect(g, Rect2(vp * 0.5 - Vector2(320, 140) + Vector2(0, 60), Vector2(640, 280)), false, Color(0.55, 0.12, 0.05, 0.35 * flick))
		draw_texture_rect(g, Rect2(Vector2(vp.x * 0.5 - 140, vp.y - 120), Vector2(280, 160)), false, Color(0.9, 0.35, 0.1, 0.25 * flick))
		for e: Array in embers:
			var c := Color(1.0, 0.5 + e[4] * 0.3, 0.2, e[4] * clampf(e[0].y / vp.y, 0.0, 1.0))
			draw_rect(Rect2(e[0], Vector2(1, 1)), c)


class TitleScreen extends Control:
	var main: Node
	var help: PanelContainer

	func _init(m: Node) -> void:
		main = m

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		theme = UI.theme()
		add_child(Backdrop.new())
		var cc := UI.center()
		add_child(cc)
		var v := UI.vbox(6)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		cc.add_child(v)
		var t := UI.title("Grim Gauntlet", 54, Color("b8261f"))
		v.add_child(t)
		v.add_child(UI.label("Three floors.  One soul.  No light but what you carry.", 10, Color("9a8a78"), HORIZONTAL_ALIGNMENT_CENTER))
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 18)
		v.add_child(spacer)
		for b in [UI.button("Begin the Descent", main.show_class_select, 170), UI.button("How to Play", _toggle_help, 170),
				UI.button("Quit", func() -> void: get_tree().quit(), 170)]:
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(b)
		var ver := UI.label("prototype build", 8, Color(0.4, 0.35, 0.33), HORIZONTAL_ALIGNMENT_RIGHT)
		add_child(ver)
		ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		ver.position -= Vector2(6, 4)
		help = _help_panel()
		help.visible = false
		add_child(help)
		Audio.music("ambient")

	func _toggle_help() -> void:
		help.visible = not help.visible

	func _help_panel() -> PanelContainer:
		var p := UI.panel()
		p.set_anchors_preset(Control.PRESET_CENTER)
		p.custom_minimum_size = Vector2(420, 0)
		p.position = Vector2(-210, -150)
		var v := UI.vbox(4)
		p.add_child(v)
		v.add_child(UI.title("How to Play", 27, UI.GOLD))
		var txt := """[color=#f2d65a]WASD[/color] move    [color=#f2d65a]Mouse[/color] aim    [color=#f2d65a]Left click[/color] attack    [color=#f2d65a]Right click / R[/color] skill
[color=#f2d65a]Space[/color] dodge roll (invulnerable)    [color=#f2d65a]Q[/color] drink a blood flask
[color=#f2d65a]E[/color] equip / use    [color=#f2d65a]F[/color] salvage an item for gold    [color=#f2d65a]Tab[/color] character    [color=#f2d65a]Esc[/color] pause

Clear a chamber and its gates rise. The sigil above each gate shows what lies beyond - choose your path. After seven chambers, the floor's master awaits.

[color=#7ee0ff]Soulbound gear[/color]: walk over loot and press E to wear it - no inventory to manage. Every magic or better item hides a [color=#7ee0ff]dormant Rite[/color]. Each foe you slay feeds souls to everything you wear; when an item has drunk its fill it [color=#7ee0ff]awakens[/color] and its Rite comes alive.

[color=#e0403a]Cursed[/color] items are stronger but carry a burden - until they awaken, which breaks the curse for good. Swapping an item resets its hunger, so choose what you keep."""
		v.add_child(UI.rich(txt, 400))
		var b := UI.button("Close", _toggle_help, 100)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(b)
		return p


class ClassSelect extends Control:
	var main: Node

	func _init(m: Node) -> void:
		main = m

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		theme = UI.theme()
		add_child(Backdrop.new())
		var cc := UI.center()
		add_child(cc)
		var v := UI.vbox(8)
		cc.add_child(v)
		v.add_child(UI.title("Who Descends?", 36, Color("c8b898")))
		var row := UI.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(row)
		for id: String in Game.CLASSES:
			row.add_child(_card(id))
		var back := UI.button("Back", main.show_title, 100)
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(back)

	func _card(id: String) -> Control:
		var c: Dictionary = Game.CLASSES[id]
		var p := UI.panel()
		p.custom_minimum_size = Vector2(170, 0)
		var v := UI.vbox(4)
		p.add_child(v)
		var at := AtlasTexture.new()
		at.atlas = load("res://assets/sprites/chars/%s.png" % c["sprite"])
		at.region = Rect2(0, 0, 20, 28)
		var portrait := CharPortrait.new()
		portrait.tex = at
		portrait.weapon = load("res://assets/sprites/items/w_%s.png" % c["weapon"])
		portrait.custom_minimum_size = Vector2(150, 92)
		v.add_child(portrait)
		v.add_child(UI.title(c["name"], 18, UI.GOLD))
		var d := UI.label(c["desc"], 8, UI.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(150, 34)
		v.add_child(d)
		var s: Dictionary = c["stats"]
		var info := "[center][color=#8a8078]Life[/color] %d   [color=#8a8078]Speed[/color] %d\n[color=#8a8078]Weapon[/color] %s\n[color=#f2d65a]%s[/color]: %s[/center]" % [
			int(s["max_hp"]), int(s["move_speed"]), ItemDB.WEAPON_NAMES[c["weapon"]][0], c["skill_name"], c["skill_desc"]]
		v.add_child(UI.rich(info, 150))
		var b := UI.button("Descend", main.start_run.bind(id), 120)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(b)
		return p


class CharPortrait extends Control:
	var tex: Texture2D
	var weapon: Texture2D
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, 6)
		var g := Fx.glow_texture()
		var fl := 0.9 + 0.1 * sin(t * 6.0)
		draw_texture_rect(g, Rect2(c - Vector2(60, 50), Vector2(120, 100)), false, Color(0.9, 0.45, 0.15, 0.3 * fl))
		draw_set_transform(c + Vector2(0, 40), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var sc := 3.0
		draw_texture_rect(tex, Rect2(c - Vector2(10, 28) * sc + Vector2(0, 40), Vector2(20, 28) * sc), false)
		draw_set_transform(c + Vector2(4, -30 + 40) + Vector2(0, -sc * 0.0), -0.3, Vector2(sc * 0.8, sc * 0.8))
		draw_texture(weapon, Vector2(0, -weapon.get_height() * 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class EndScreen extends Control:
	var main: Node
	var victory := false

	func _init(m: Node, won: bool) -> void:
		main = m
		victory = won

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		theme = UI.theme()
		add_child(Backdrop.new())
		var cc := UI.center()
		add_child(cc)
		var v := UI.vbox(6)
		cc.add_child(v)
		if victory:
			v.add_child(UI.title("Victory", 54, UI.GOLD))
			v.add_child(UI.label("The Hollow Bishop is silent. The halls are yours.", 10, UI.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER))
		else:
			v.add_child(UI.title("You Have Died", 54, Color("b8261f")))
			v.add_child(UI.label("Your soul joins the rest, deep in the halls.", 10, Color("9a8a78"), HORIZONTAL_ALIGNMENT_CENTER))
		var p := UI.panel()
		p.custom_minimum_size = Vector2(260, 0)
		p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(p)
		var t := int(Game.run_time)
		var lines := [
			["Class", Game.class_data()["name"]],
			["Deepest floor", "%d  -  %s" % [Game.floor_idx + 1, Game.floor_data()["name"]]],
			["Level", str(Game.level)],
			["Foes slain", str(Game.kills)],
			["Souls harvested", str(Game.souls_total)],
			["Items awakened", str(Game.awakened_count)],
			["Gold", str(Game.gold)],
			["Time", "%d:%02d" % [t / 60, t % 60]],
		]
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 16)
		p.add_child(g)
		for l: Array in lines:
			g.add_child(UI.label(l[0], 9, UI.DIM))
			g.add_child(UI.label(l[1], 9, UI.PARCHMENT))
		var row := UI.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(UI.button("Descend Again", main.start_run.bind(Game.class_id), 130))
		row.add_child(UI.button("Choose Class", main.show_class_select, 110))
		row.add_child(UI.button("Title", main.show_title, 80))
		v.add_child(row)
		Audio.music("ambient")
