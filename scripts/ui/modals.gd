class_name Modals
extends RefCounted
## Pop-up menus shown during a run. The game is paused while one is open.


class Modal extends Control:
	signal closed
	var run: Node
	var panel: PanelContainer
	var body: VBoxContainer
	var can_escape := true

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func build(title_text: String, width := 300.0) -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		theme = UI.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.0, 0.62)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var cc := UI.center()
		add_child(cc)
		panel = UI.panel()
		panel.custom_minimum_size = Vector2(width, 0)
		cc.add_child(panel)
		body = UI.vbox(6)
		panel.add_child(body)
		if title_text != "":
			body.add_child(UI.title(title_text, 27, UI.GOLD))
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.15)

	func close() -> void:
		closed.emit()
		queue_free()

	func _unhandled_input(e: InputEvent) -> void:
		if can_escape and (e.is_action_pressed("pause") or e.is_action_pressed("sheet")):
			get_viewport().set_input_as_handled()
			close()


## Pick one of three Blessings on level-up.
class LevelUp extends Modal:
	var from_shop := false
	var choices: Array = []

	func _init(r: Node, shop := false) -> void:
		super._init()
		run = r
		from_shop = shop
		can_escape = false

	func _ready() -> void:
		build("Choose a Blessing", 380.0)
		var sub := "The dark rewards those who persist." if not from_shop else "The merchant's unholy wares."
		if not from_shop:
			sub = "Level %d.  %s" % [Game.level - Game.pending_levels + 1, sub]
		body.add_child(UI.label(sub, 9, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
		var row := UI.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		body.add_child(row)
		choices = Game.roll_blessings(3)
		for b: Dictionary in choices:
			row.add_child(_card(b))
		Audio.play("level_up", -4.0)
		if Game.autoplay:
			_pick.call_deferred(choices[0])

	func _card(b: Dictionary) -> Button:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(112, 74)
		var v := UI.vbox(2)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(v)
		var ic := UI.texture_rect(load("res://assets/sprites/ui/blessing.png"), Vector2(16, 16))
		v.add_child(ic)
		v.add_child(UI.label(b["name"], 11, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		var d := UI.label(b["desc"], 8, UI.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(100, 0)
		v.add_child(d)
		btn.pressed.connect(_pick.bind(b))
		btn.mouse_entered.connect(func() -> void: Audio.play("ui_hover", -10.0))
		return btn

	func _pick(b: Dictionary) -> void:
		if not is_inside_tree() or is_queued_for_deletion():
			return
		Game.apply_blessing(b)
		if not from_shop:
			Game.pending_levels = maxi(0, Game.pending_levels - 1)
		Audio.play("equip", -2.0)
		Game.notify.emit("Blessing of %s" % b["name"], UI.GOLD)
		close()


## The awakening shrine: pay blood to wake an item's dormant rite now.
class Shrine extends Modal:
	var altar: Node

	func _init(r: Node, a: Node) -> void:
		super._init()
		run = r
		altar = a

	func _ready() -> void:
		build("Altar of Awakening", 360.0)
		Audio.play("shrine", -4.0)
		var cost := cost_hp()
		body.add_child(UI.label("Offer your blood (%d Life) and one possession awakens at once.\nAwakening also breaks any curse." % cost,
			9, UI.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER))
		var any := false
		for slot: String in Game.SLOTS:
			var it = Game.equipment.get(slot)
			if it == null or it["awakened"] or it["rite"] == "":
				continue
			any = true
			var row := UI.hbox(6)
			row.add_child(UI.item_slot(it, 22.0))
			var info := UI.vbox(0)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.add_child(UI.label(it["name"], 10, ItemDB.color_of(it)))
			var r: Dictionary = ItemDB.RITES[it["rite"]]
			info.add_child(UI.label("%s  (%d/%d souls)" % [r["name"], int(it["souls"]), int(it["souls_needed"])], 8, UI.SOUL))
			row.add_child(info)
			var b := UI.button("Awaken", _awaken.bind(it), 70)
			b.disabled = Game.hp <= cost + 1.0
			row.add_child(b)
			body.add_child(row)
		if not any:
			body.add_child(UI.label("None of your possessions hold a dormant rite.", 9, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
		var leave := UI.button("Leave", close, 100)
		leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		body.add_child(leave)

	func cost_hp() -> float:
		return round(Game.stat("max_hp") * 0.25)

	func _awaken(it: Dictionary) -> void:
		Game.hp -= cost_hp()
		Game.awaken(it)
		altar.consume()
		run.fx.gore(run.player.global_position, "blood", 20)
		close()


## Campfire: rest, or pray for a blessing.
class Rest extends Modal:
	var fire: Node

	func _init(r: Node, f: Node) -> void:
		super._init()
		run = r
		fire = f

	func _ready() -> void:
		build("The Last Fire", 300.0)
		body.add_child(UI.label("A moment's peace in the dark. Choose one.", 9, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
		var b1 := UI.button("Rest  -  restore 60% Life, refill flasks", _rest, 260)
		var b2 := UI.button("Pray  -  receive a Blessing", _pray, 260)
		for b in [b1, b2]:
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			body.add_child(b)
		var leave := UI.button("Not yet", close, 100)
		leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		body.add_child(leave)

	func _rest() -> void:
		fire.used = true
		Game.heal(Game.stat("max_hp") * 0.6)
		Game.flask_charges = int(Game.stat("flask_max"))
		Game.notify.emit("You rest. Your wounds close.", Color("ff8a6a"))
		Audio.play("flask", 0.0, 0.0, 0.8)
		close()

	func _pray() -> void:
		fire.used = true
		# Replaces this menu with the blessing choice.
		run.open_levelup(true)


class Pause extends Modal:
	func _init(r: Node) -> void:
		super._init()
		run = r

	func _ready() -> void:
		build("Paused", 260.0)
		for b in [UI.button("Resume", close, 160), UI.button("Character  (Tab)", _sheet, 160),
				UI.button("Abandon Run", _abandon, 160)]:
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			body.add_child(b)
		body.add_child(_slider("Music", Game.music_volume, func(v: float) -> void:
			Game.music_volume = v
			Audio.refresh_music_volume()))
		body.add_child(_slider("Effects", Game.sfx_volume, func(v: float) -> void: Game.sfx_volume = v))
		var help := UI.label("WASD move  -  Mouse aim, LMB shoot  -  RMB/R skill\nSpace dodge  -  Q flask  -  E use/equip  -  F salvage", 8, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
		body.add_child(help)

	func _slider(name: String, v: float, cb: Callable) -> HBoxContainer:
		var h := UI.hbox(6)
		var l := UI.label(name, 9)
		l.custom_minimum_size = Vector2(50, 0)
		h.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = v
		s.custom_minimum_size = Vector2(150, 12)
		s.value_changed.connect(cb)
		h.add_child(s)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		return h

	func _sheet() -> void:
		close()
		run.open_sheet.call_deferred()

	func _abandon() -> void:
		close()
		run.abandon.call_deferred()


## Equipment, stats and rites overview.
class CharacterSheet extends Modal:
	var detail: RichTextLabel

	func _init(r: Node) -> void:
		super._init()
		run = r

	func _ready() -> void:
		build("", 560.0)
		var cls := Game.class_data()
		var head := UI.hbox(8)
		head.add_child(UI.title(cls["name"], 27, UI.GOLD))
		var lv := UI.label("Level %d   -   %s, Floor %d" % [Game.level, Game.floor_data()["name"], Game.floor_idx + 1], 9, UI.DIM)
		lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(lv)
		body.add_child(head)
		var cols := UI.hbox(10)
		body.add_child(cols)

		# Equipment column
		var eq := UI.vbox(3)
		eq.custom_minimum_size = Vector2(190, 0)
		cols.add_child(eq)
		eq.add_child(UI.label("Equipment", 10, UI.GOLD))
		for slot: String in Game.SLOTS:
			var it = Game.equipment.get(slot)
			var row := UI.hbox(5)
			var sl := UI.item_slot(it, 20.0)
			row.add_child(sl)
			var info := UI.vbox(0)
			if it != null:
				info.add_child(UI.label(it["name"], 9, ItemDB.color_of(it)))
				var sub := Game.SLOT_NAMES[slot] as String
				if it["rite"] != "":
					var rn: String = ItemDB.RITES[it["rite"]]["name"]
					sub += ("  -  %s (awakened)" % rn) if it["awakened"] else ("  -  %s %d/%d" % [rn, int(it["souls"]), int(it["souls_needed"])])
				info.add_child(UI.label(sub, 7, UI.SOUL if it["awakened"] else UI.DIM))
			else:
				info.add_child(UI.label("- empty %s -" % Game.SLOT_NAMES[slot].to_lower(), 9, UI.DIM))
			row.add_child(info)
			# An invisible button over the row shows the item on hover.
			var wrap := Control.new()
			wrap.custom_minimum_size = Vector2(190, 22)
			wrap.add_child(row)
			var over := Button.new()
			over.flat = true
			over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			for st in ["normal", "hover", "pressed", "focus"]:
				over.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			over.mouse_entered.connect(_show_item.bind(it))
			wrap.add_child(over)
			eq.add_child(wrap)

		# Stats column
		var st := UI.vbox(1)
		st.custom_minimum_size = Vector2(150, 0)
		cols.add_child(st)
		st.add_child(UI.label("Attributes", 10, UI.GOLD))
		var s := Game.stats
		var w := Game.weapon_data()
		var lines := [
			["Life", "%d / %d" % [ceili(Game.hp), int(s["max_hp"])]],
			["Mana", "%d / %d" % [int(Game.mana), int(s["max_mana"])]],
			["Weapon damage", "%.1f%s" % [w["damage"] * (1.0 + s["damage_pct"]), (" x%d" % w["count"]) if w["count"] > 1 else ""]],
			["Attacks / sec", "%.2f" % (w["rate"] * (1.0 + s["attack_speed_pct"]))],
			["Critical chance", "%d%%" % int(s["crit_chance"] * 100)],
			["Critical damage", "%d%%" % int((1.0 + s["crit_mult"]) * 100)],
			["Armor", "%d  (-%d%% dmg)" % [int(s["armor"]), int(100.0 - 10000.0 / (100.0 + maxf(0.0, s["armor"])))]],
			["Move speed", "%d" % int(s["move_speed"])],
			["Projectiles", "+%d" % int(s["extra_proj"])],
			["Pierce", "+%d" % int(s["pierce"])],
			["Life on kill", "%d" % int(s["life_on_kill"])],
			["Flask heals", "%d%%" % int(s["flask_heal"] * 100)],
			["Souls gained", "+%d%%" % int(s["soul_gain"] * 100)],
			["Gold found", "+%d%%" % int(s["gold_find"] * 100)],
		]
		for l: Array in lines:
			var row := UI.hbox(4)
			var a := UI.label(l[0], 8, UI.DIM)
			a.custom_minimum_size = Vector2(80, 0)
			row.add_child(a)
			row.add_child(UI.label(l[1], 8, UI.PARCHMENT))
			st.add_child(row)
		if not Game.blessing_names.is_empty():
			st.add_child(UI.label("Blessings", 10, UI.GOLD))
			var bl := UI.label(", ".join(Game.blessing_names), 8, UI.PARCHMENT)
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bl.custom_minimum_size = Vector2(150, 0)
			st.add_child(bl)

		# Detail column
		var dp := UI.vbox(2)
		cols.add_child(dp)
		dp.add_child(UI.label("Inspect", 10, UI.GOLD))
		detail = UI.rich("[color=#6a6058]Hover an item to inspect it.[/color]", 170)
		dp.add_child(detail)
		var close_b := UI.button("Close", close, 100)
		close_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		body.add_child(close_b)

	func _show_item(it: Variant) -> void:
		if it == null:
			detail.text = "[color=#6a6058]Nothing equipped.[/color]"
		else:
			detail.text = ItemDB.describe(it)
