class_name WorldObjects
extends RefCounted
## Pickups and interactive props that appear in rooms.

const ICON_DIR := "res://assets/sprites/items/"
const PROP_DIR := "res://assets/sprites/props/"


static func item_icon(it: Dictionary) -> Texture2D:
	return load(ICON_DIR + it["icon"] + ".png")


## An item lying on the floor, Diablo-style: coloured name label and,
## for rare and better, a pillar of light.
class GroundItem extends Interactable:
	var item: Dictionary
	var run: Node
	var icon: Texture2D
	var beam: Texture2D
	var h := 0.0
	var vh := 0.0
	var vel := Vector2.ZERO
	var landed := false
	var t := 0.0
	var label: WorldObjects.Label2D
	var beam_sprite: Sprite2D

	func setup(run_: Node, it: Dictionary, pos: Vector2, pop := true) -> void:
		run = run_
		item = it
		position = pos
		icon = WorldObjects.item_icon(it)
		beam = load("res://assets/sprites/fx/beam.png")
		interact_radius = 20.0
		if pop:
			vh = 110.0
			vel = Vector2.from_angle(randf() * TAU) * randf_range(10.0, 35.0)
			vel.y *= 0.5
		else:
			landed = true

	func _ready() -> void:
		material = Fx.unshaded_material()
		label = WorldObjects.Label2D.new()
		label.text = item["name"]
		label.color = ItemDB.color_of(item)
		label.position = Vector2(0, -22)
		add_child(label)
		if item["rarity"] >= ItemDB.RARE or item["cursed"]:
			beam_sprite = Sprite2D.new()
			beam_sprite.texture = beam
			beam_sprite.offset = Vector2(0, -26)
			beam_sprite.scale = Vector2(1.3, 1.6)
			beam_sprite.material = Fx.additive_material()
			beam_sprite.modulate = ItemDB.color_of(item)
			beam_sprite.show_behind_parent = true
			beam_sprite.visible = false
			add_child(beam_sprite)

	func _process(delta: float) -> void:
		t += delta
		if not landed:
			vh -= 380.0 * delta
			h = maxf(0.0, h + vh * delta)
			var np := position + vel * delta
			if run.room != null and run.room.is_floor(Iso.to_cell(np)):
				position = np
			if h <= 0.0 and vh < 0.0:
				landed = true
				h = 0.0
				Audio.play("item_unique" if item["rarity"] == ItemDB.UNIQUE else "item_drop", -4.0 if item["rarity"] == ItemDB.UNIQUE else -6.0)
				if item["rarity"] >= ItemDB.RARE:
					run.fx.glow(position, 24.0, ItemDB.color_of(item), 0.6)
		label.visible = landed
		if beam_sprite != null:
			beam_sprite.visible = landed
			beam_sprite.modulate.a = 0.75 + 0.25 * sin(t * 3.0)
		label.highlight = run.current_interact == self
		queue_redraw()

	func can_interact() -> bool:
		return landed and enabled

	func prompt() -> String:
		return "Equip " + item["name"]

	func alt_prompt() -> String:
		return "Salvage (%d gold)" % item["value"]

	func tooltip_item() -> Variant:
		return item

	func interact(r: Node) -> void:
		var old = Game.equip(item)
		Audio.play("equip", -2.0)
		r.fx.burst(position, ItemDB.color_of(item), 10, 40.0, 6.0, 1.5, -20.0, 0.5)
		Game.notify.emit("Equipped " + item["name"], ItemDB.color_of(item))
		if old != null:
			r.drop_item(old, position, false)
		enabled = false
		queue_free()

	func alt_interact(r: Node) -> void:
		Game.add_gold(item["value"])
		Audio.play("salvage", -3.0)
		r.fx.text(position, "+%d gold" % item["value"], Color("f2d65a"))
		r.fx.burst(position, Color("f2d65a"), 8, 40.0, 6.0, 1.5)
		enabled = false
		queue_free()

	func _draw() -> void:
		var col := ItemDB.color_of(item)
		# Shadow
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var bob := sin(t * 3.0) * 1.0 if landed else 0.0
		var sz := icon.get_size()
		var scale := minf(1.0, 14.0 / maxf(sz.x, sz.y))
		var ds := sz * scale
		draw_texture_rect(icon, Rect2(Vector2(-ds.x * 0.5, -ds.y - 2 - h + bob), ds), false)


## Diablo-style floating item name.
class Label2D extends Node2D:
	var text := ""
	var color := Color.WHITE
	var highlight := false

	func _ready() -> void:
		material = Fx.unshaded_material()
		z_index = 18
		z_as_relative = false

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var f := Fx.font()
		var sz := 8
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var r := Rect2(-w * 0.5 - 3, -9, w + 6, 11)
		draw_rect(r, Color(0.04, 0.02, 0.03, 0.82 if not highlight else 0.95))
		if highlight:
			draw_rect(r, color.darkened(0.3), false, 1.0)
		draw_string(f, Vector2(-w * 0.5, -1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, color)


## Gold coins and blood orbs: pop out, then fly to the player.
class Pickup extends Node2D:
	var run: Node
	var kind := "gold"
	var amount := 1.0
	var h := 0.0
	var vh := 0.0
	var vel := Vector2.ZERO
	var t := 0.0
	var tex: Texture2D

	func setup(run_: Node, k: String, amt: float, pos: Vector2) -> void:
		run = run_
		kind = k
		amount = amt
		position = pos
		vh = randf_range(60.0, 110.0)
		vel = Vector2.from_angle(randf() * TAU) * randf_range(15.0, 45.0)
		vel.y *= 0.5
		tex = load(WorldObjects.ICON_DIR + ("coin.png" if kind == "gold" else "flask.png"))

	func _ready() -> void:
		material = Fx.unshaded_material()

	func _process(delta: float) -> void:
		t += delta
		var pl = run.player
		if pl == null:
			return
		var to: Vector2 = pl.global_position - global_position
		var magnet := 60.0 if kind == "gold" else 34.0
		var homing: bool = t > 0.45 and (to.length() < magnet or (kind == "gold" and run.room != null and run.room.unlocked))
		if homing and not pl.dead:
			vel = vel.move_toward(to.normalized() * 260.0, 900.0 * delta)
			position += vel * delta
			h = move_toward(h, 6.0, 30.0 * delta)
		else:
			vh -= 350.0 * delta
			h = maxf(0.0, h + vh * delta)
			if h <= 0.0:
				vh = absf(vh) * 0.35 if absf(vh) > 30.0 else 0.0
				vel *= 0.5
			var np := position + vel * delta
			if run.room != null and run.room.is_floor(Iso.to_cell(np)):
				position = np
		if to.length() < 8.0 and t > 0.3 and not pl.dead:
			_collect()
		queue_redraw()

	func _collect() -> void:
		if kind == "gold":
			var g := int(amount)
			Game.add_gold(g)
			Audio.play("gold", -8.0, 0.15)
			run.fx.text(position, "+%d" % g, Color("f2d65a"), 8)
		else:
			var heal: float = Game.stat("max_hp") * amount
			Game.heal(heal)
			Audio.play("flask", -6.0, 0.1, 1.3)
			run.fx.number(position, heal, Color("ff5a5a"))
		queue_free()

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if kind == "gold":
			draw_texture_rect(tex, Rect2(-4, -8 - h, 8, 8), false)
		else:
			var p := Vector2(0, -5 - h)
			draw_texture_rect(Fx.glow_texture(), Rect2(p - Vector2(9, 9), Vector2(18, 18)), false, Color(1, 0.2, 0.2, 0.5))
			draw_circle(p, 3.2, Color(0.75, 0.08, 0.08))
			draw_circle(p + Vector2(-1, -1), 1.2, Color(1, 0.6, 0.6))


class Chest extends Interactable:
	var run: Node
	var sprite: Sprite2D
	var opened := false

	func setup(run_: Node, pos: Vector2) -> void:
		run = run_
		position = pos
		interact_radius = 26.0

	func _ready() -> void:
		sprite = Sprite2D.new()
		sprite.texture = load(WorldObjects.PROP_DIR + "chest.png")
		sprite.hframes = 2
		sprite.offset = Vector2(0, -7)
		add_child(sprite)
		var lt := PointLight2D.new()
		lt.texture = Fx.light_texture()
		lt.color = Color(1.0, 0.8, 0.4)
		lt.energy = 0.6
		lt.texture_scale = 0.6
		lt.position = Vector2(0, -10)
		add_child(lt)

	func prompt() -> String:
		return "Open the Reliquary"

	func can_interact() -> bool:
		return not opened

	func interact(r: Node) -> void:
		opened = true
		sprite.frame = 1
		Audio.play("chest", 0.0)
		r.add_shake(0.25)
		r.fx.burst(position, Color("f2d65a"), 20, 60.0, 10.0, 2.0, 150.0, 0.8)
		r.fx.glow(position, 40.0, Color(1.0, 0.85, 0.4, 0.8), 0.6)
		var items := [ItemDB.generate(Game.floor_idx, -1, "", ItemDB.RARE),
			ItemDB.generate(Game.floor_idx, -1, "", ItemDB.MAGIC), ItemDB.generate(Game.floor_idx)]
		for it: Dictionary in items:
			r.drop_item(it, position + Vector2(0, 8), true)
		r.drop_gold(position + Vector2(0, 6), Game.rng.randi_range(8, 16) * (Game.floor_idx + 1))


class Altar extends Interactable:
	var run: Node
	var used := false
	var lt: PointLight2D

	func setup(run_: Node, pos: Vector2) -> void:
		run = run_
		position = pos
		interact_radius = 28.0

	func _ready() -> void:
		var s := Sprite2D.new()
		s.texture = load(WorldObjects.PROP_DIR + "altar.png")
		s.offset = Vector2(0, -9)
		add_child(s)
		lt = PointLight2D.new()
		lt.texture = Fx.light_texture()
		lt.color = Color(0.75, 0.4, 1.0)
		lt.energy = 1.0
		lt.texture_scale = 1.0
		lt.position = Vector2(0, -12)
		add_child(lt)

	func prompt() -> String:
		return "Kneel at the Altar of Awakening"

	func can_interact() -> bool:
		return not used

	func interact(r: Node) -> void:
		r.open_shrine(self)

	func consume() -> void:
		used = true
		var tw := create_tween()
		tw.tween_property(lt, "energy", 0.15, 1.0)


class Campfire extends Interactable:
	var run: Node
	var used := false
	var flames: Array = []
	var lt: PointLight2D
	var t := 0.0

	func setup(run_: Node, pos: Vector2) -> void:
		run = run_
		position = pos
		interact_radius = 28.0

	func _ready() -> void:
		var s := Sprite2D.new()
		s.texture = load(WorldObjects.PROP_DIR + "campfire.png")
		s.offset = Vector2(0, -3)
		add_child(s)
		for i in 3:
			var f := Sprite2D.new()
			f.texture = load("res://assets/sprites/fx/flame.png")
			f.hframes = 4
			f.position = Vector2(-4 + i * 4, -8 - (i % 2) * 2)
			f.scale = Vector2(1.2, 1.4)
			f.material = Fx.unshaded_material()
			add_child(f)
			flames.append(f)
		lt = PointLight2D.new()
		lt.texture = Fx.light_texture()
		lt.color = Color(1.0, 0.6, 0.3)
		lt.energy = 1.2
		lt.texture_scale = 1.4
		lt.position = Vector2(0, -8)
		add_child(lt)

	func _process(delta: float) -> void:
		t += delta
		for i in flames.size():
			flames[i].frame = int(t * 10.0 + i) % 4
		lt.energy = (1.15 + 0.15 * sin(t * 8.0)) * (0.5 if used else 1.0)
		if randf() < delta * 6.0:
			run.fx.embers(position + Vector2(0, -6), Color(1.0, 0.6, 0.2), 1)

	func prompt() -> String:
		return "Rest by the fire"

	func can_interact() -> bool:
		return not used

	func interact(r: Node) -> void:
		r.open_rest(self)


class ShopPedestal extends Interactable:
	var run: Node
	var item: Variant = null
	var product := "item" # item / vial / blessing
	var price := 10
	var sold := false
	var t := 0.0

	func setup(run_: Node, pos: Vector2, prod: String, it: Variant, p: int) -> void:
		run = run_
		position = pos
		product = prod
		item = it
		price = p
		interact_radius = 20.0

	func _ready() -> void:
		var s := Sprite2D.new()
		s.texture = load(WorldObjects.PROP_DIR + "pedestal.png")
		s.offset = Vector2(0, -6)
		add_child(s)
		var lbl := WorldObjects.Label2D.new()
		lbl.text = "%d gold" % price
		lbl.color = Color("f2d65a")
		lbl.position = Vector2(0, -36)
		add_child(lbl)
		material = Fx.unshaded_material()

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func can_interact() -> bool:
		return not sold

	func prompt() -> String:
		var what := ""
		match product:
			"item":
				what = item["name"]
			"vial":
				what = "Blood Vial (refill flasks)"
			"blessing":
				what = "Unholy Blessing"
		if Game.gold < price:
			return "%s - need %d gold" % [what, price]
		return "Buy %s for %d gold" % [what, price]

	func tooltip_item() -> Variant:
		return item if product == "item" and not sold else null

	func interact(r: Node) -> void:
		if Game.gold < price:
			Audio.play("ui_click", 0.0, 0.0, 0.5)
			r.fx.text(position, "Not enough gold", Color("d0504a"))
			return
		Game.add_gold(-price)
		Audio.play("gold", -2.0, 0.0, 0.8)
		sold = true
		get_child(1).visible = false
		match product:
			"item":
				var old = Game.equip(item)
				Audio.play("equip", -2.0)
				Game.notify.emit("Bought " + item["name"], ItemDB.color_of(item))
				if old != null:
					r.drop_item(old, position + Vector2(0, 14), true)
			"vial":
				Game.flask_charges = int(Game.stat("flask_max"))
				Game.heal(Game.stat("max_hp") * 0.25)
				Game.notify.emit("Your flasks brim with blood", Color("d8352f"))
			"blessing":
				r.open_levelup(true)
		queue_redraw()

	func _draw() -> void:
		if sold:
			return
		var y := -22.0 + sin(t * 2.5) * 1.5
		var tex: Texture2D
		var col := Color.WHITE
		match product:
			"item":
				tex = WorldObjects.item_icon(item)
				col = ItemDB.color_of(item)
			"vial":
				tex = load(WorldObjects.ICON_DIR + "flask.png")
				col = Color(1.0, 0.3, 0.3)
			"blessing":
				tex = load("res://assets/sprites/ui/blessing.png")
				col = Color(1.0, 0.85, 0.4)
		draw_texture_rect(Fx.glow_texture(), Rect2(-12, y - 12, 24, 24), false, Color(col.r, col.g, col.b, 0.35))
		var sz := tex.get_size()
		var sc := minf(1.0, 14.0 / maxf(sz.x, sz.y))
		draw_texture_rect(tex, Rect2(Vector2(-sz.x * sc * 0.5, y - sz.y * sc * 0.5), sz * sc), false)


class Portal extends Interactable:
	var run: Node
	var t := 0.0
	var victory := false

	func setup(run_: Node, pos: Vector2, is_victory: bool) -> void:
		run = run_
		position = pos
		victory = is_victory
		interact_radius = 30.0

	func _ready() -> void:
		material = Fx.unshaded_material()
		var lt := PointLight2D.new()
		lt.texture = Fx.light_texture()
		lt.color = Color(0.7, 0.3, 1.0) if not victory else Color(1.0, 0.9, 0.5)
		lt.energy = 1.4
		lt.texture_scale = 1.3
		lt.position = Vector2(0, -16)
		add_child(lt)
		scale = Vector2(0.05, 0.05)
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func prompt() -> String:
		return "Claim your victory" if victory else "Descend deeper"

	func interact(r: Node) -> void:
		enabled = false
		if victory:
			r.on_victory()
		else:
			r.descend()

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var base := Color(0.55, 0.2, 0.9) if not victory else Color(1.0, 0.8, 0.35)
		var c := Vector2(0, -18)
		draw_set_transform(c, 0.0, Vector2(0.6, 1.0))
		draw_circle(Vector2.ZERO, 16.0, Color(0.03, 0.0, 0.05, 0.9))
		for i in 5:
			var r := 16.0 - i * 3.0
			var a0 := t * (2.0 + i * 0.7) * (1.0 if i % 2 == 0 else -1.0)
			draw_arc(Vector2.ZERO, r, a0, a0 + PI * 1.3, 24, base.lightened(i * 0.1), 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(base.r, base.g, base.b, 0.6), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Merchant extends Node2D:
	var sprite: Sprite2D
	var t := 0.0

	func _ready() -> void:
		sprite = Sprite2D.new()
		sprite.texture = load("res://assets/sprites/chars/merchant.png")
		sprite.hframes = 7
		sprite.offset = Vector2(0, -13)
		add_child(sprite)
		var lt := PointLight2D.new()
		lt.texture = Fx.light_texture()
		lt.color = Color(1.0, 0.75, 0.4)
		lt.energy = 1.0
		lt.texture_scale = 1.2
		lt.position = Vector2(6, -6)
		add_child(lt)

	func _process(delta: float) -> void:
		t += delta
		sprite.frame = int(t * 1.5) % 2
