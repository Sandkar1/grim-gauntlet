class_name Run
extends Node2D
## One descent through the halls. Owns the current room, the player, all
## projectiles/effects, the HUD, and the flow from room to room.

signal ended(victory: bool)

var world: Node2D
var room: Room
var player: Player
var bullets: Bullets
var fx: Fx
var ground_fx: GroundFx
var camera: Camera2D
var canvas_mod: CanvasModulate
var hud: HUD
var modal_layer: CanvasLayer
var fade_rect: ColorRect

var enemies: Array = []
var pending_spawns: Array = []
var waves: Array = []
var wave_timer := 0.0
var in_combat := false
var transitioning := true
var current_interact: Variant = null
var boss: Boss = null
var room_type := "start"
var shake := 0.0

var _timers: Array = []
var _hitstop_until := 0
var _modal: Control = null
var _last_kill_pos := Vector2.ZERO
var _ended := false
var _bot_seen := {}
var _clear_pending := false
var _used_first_override := false
var _base_time_scale := 1.0


func _ready() -> void:
	Game.run = self
	_base_time_scale = maxf(1.0, Engine.time_scale)
	canvas_mod = CanvasModulate.new()
	add_child(canvas_mod)
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	ground_fx = GroundFx.new()
	ground_fx.run = self
	add_child(ground_fx)
	bullets = Bullets.new()
	bullets.run = self
	add_child(bullets)
	fx = Fx.new()
	add_child(fx)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	player = Player.new()
	player.run = self
	world.add_child(player)
	hud = HUD.new()
	hud.run = self
	add_child(hud)
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 30
	modal_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(modal_layer)
	var fl := CanvasLayer.new()
	fl.layer = 40
	add_child(fl)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.01, 0.005, 0.01, 1.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(fade_rect)
	Game.item_awakened.connect(_on_item_awakened)
	start_floor()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--open="):
			delayed(1.6, _debug_open.bind(a.split("=")[1]))


func _debug_open(what: String) -> void:
	match what:
		"levelup":
			Game.pending_levels = 1
			open_levelup()
		"sheet":
			for i in 4:
				Game.equip(ItemDB.generate(Game.floor_idx, randi_range(1, 3)))
			Game.add_souls(12)
			open_sheet()
		"pause":
			open_pause()
		"shrine":
			for i in 3:
				Game.equip(ItemDB.generate(Game.floor_idx, randi_range(1, 3)))
			open_shrine(Node.new())
		"loot":
			for i in 5:
				drop_item(ItemDB.generate(Game.floor_idx, i % 4), player.global_position + Vector2(-40 + i * 20, -20 if i != 2 else 0), i != 2)
		"die":
			Game.hp = 1
			player.take_hit(999, Vector2.RIGHT)


func _exit_tree() -> void:
	Engine.time_scale = _base_time_scale
	if Game.run == self:
		Game.run = null


# ---------------------------------------------------------------------------
# Floors & rooms
# ---------------------------------------------------------------------------

func start_floor() -> void:
	Game.room_idx = 0
	Game.room_history = ["start"]
	canvas_mod.color = Game.floor_data()["ambient"]
	Audio.music("ambient")
	var first := "start"
	if not _used_first_override:
		_used_first_override = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--first-room="):
				first = a.split("=")[1]
	await enter_room(first, true)
	hud.show_banner(Game.floor_data()["name"], "Floor %s" % ["I", "II", "III"][Game.floor_idx], Color("c8b898"), 2.2)


func enter_room(type: String, first := false) -> void:
	transitioning = true
	if not first:
		await _fade(1.0, 0.3)
	_clear_room()
	room_type = type
	room = Room.new()
	room.setup(self, type, Game.floor_data()["biome"], _plan_doors(type), Game.rng.randi())
	world.add_child(room)
	player.global_position = room.spawn_position()
	player.velocity = Vector2.ZERO
	camera.global_position = _camera_target()
	camera.reset_smoothing()
	Game.revenant_used = false
	_populate(type)
	hud.update_room_info()
	await _fade(0.0, 0.45)
	transitioning = false
	if type in ["combat", "elite"]:
		delayed(0.4, _begin_combat)


func _clear_room() -> void:
	if room != null:
		world.remove_child(room)
		room.queue_free()
		room = null
	enemies.clear()
	pending_spawns.clear()
	waves.clear()
	bullets.clear()
	fx.clear()
	ground_fx.clear()
	_timers.clear()
	boss = null
	current_interact = null
	in_combat = false
	_clear_pending = false


func _plan_doors(type: String) -> Array:
	if type == "boss":
		return []
	if Game.room_idx >= Game.ROOMS_PER_FLOOR:
		return ["boss"]
	var rng := Game.rng
	var n := 2 if (rng.randf() < 0.75 or type == "start") else 3
	var i := Game.room_idx
	var weights := {
		"combat": 42,
		"elite": 14 if i >= 2 else 0,
		"treasure": 9 if i >= 1 else 0,
		"shop": 9 if i >= 1 else 0,
		"shrine": 9 if i >= 1 else 0,
		"rest": 8 if i >= 2 else 0,
	}
	# Avoid offering the same calm room twice in a row.
	if type in ["shop", "rest", "shrine", "treasure"]:
		weights[type] = 0
	var picks: Array = []
	if i == Game.ROOMS_PER_FLOOR - 1:
		picks.append("rest" if rng.randf() < 0.5 else "shop")
	while picks.size() < n:
		var total := 0
		for k: String in weights:
			if k not in picks:
				total += weights[k]
		if total <= 0:
			break
		var r := rng.randi_range(1, total)
		for k: String in weights:
			if k in picks:
				continue
			r -= weights[k]
			if r <= 0:
				picks.append(k)
				break
	# At least one door should lead to a fight (xp and souls).
	if not ("combat" in picks or "elite" in picks):
		picks[0] = "combat"
	picks.shuffle()
	return picks


func _populate(type: String) -> void:
	var c := room.center()
	match type:
		"start":
			room.unlock()
			if Game.floor_idx == 0:
				hud.message("WASD move - Mouse aim & shoot - Space dodge - E use", UI.DIM)
		"combat", "elite":
			waves = _make_waves(type)
		"treasure":
			var ch := WorldObjects.Chest.new()
			ch.setup(self, c)
			room.add_child(ch)
			room.unlock()
		"shop":
			var m := WorldObjects.Merchant.new()
			m.position = c + Vector2(0, -36)
			room.add_child(m)
			var spots := [Vector2(-48, 0), Vector2(-16, 14), Vector2(16, 14), Vector2(48, 0), Vector2(0, 34)]
			for k in 3:
				var it := ItemDB.generate(Game.floor_idx, -1, "", ItemDB.MAGIC)
				var price := int(it["value"] * 2.2) + 10
				_add_pedestal(c + spots[k], "item", it, price)
			_add_pedestal(c + spots[3], "vial", null, 25 + 15 * Game.floor_idx)
			_add_pedestal(c + spots[4], "blessing", null, 60 + 40 * Game.floor_idx)
			room.unlock()
			hud.message("\"Coin for steel, wanderer. No refunds in the dark.\"", Color("b8a888"))
		"shrine":
			var a := WorldObjects.Altar.new()
			a.setup(self, c)
			room.add_child(a)
			room.unlock()
		"rest":
			var f := WorldObjects.Campfire.new()
			f.setup(self, c)
			room.add_child(f)
			room.unlock()
		"boss":
			delayed(0.8, _spawn_boss)


func _add_pedestal(pos: Vector2, prod: String, it: Variant, price: int) -> void:
	var p := WorldObjects.ShopPedestal.new()
	p.setup(self, pos, prod, it, price)
	room.add_child(p)


func _make_waves(type: String) -> Array:
	var rng := Game.rng
	var pool: Array = EnemyDB.FLOOR_POOLS[Game.floor_idx]
	var budget := 8.0 + Game.floor_idx * 4.0 + Game.room_idx * 1.4
	if type == "elite":
		budget *= 1.2
	var n_waves := 2 if type == "combat" else 3
	var result: Array = []
	for w in n_waves:
		var b := budget / n_waves * (0.8 + 0.4 * float(w) / maxf(1.0, n_waves - 1))
		var wave: Array = []
		while b > 0.0:
			var id: String = pool[rng.randi_range(0, pool.size() - 1)]
			# Early chambers avoid the nastier enemies.
			if Game.floor_idx == 0 and Game.room_idx <= 1 and id == "ghoul":
				id = "skeleton"
			if id == "bat":
				for _k in 3:
					wave.append([id, ""])
			else:
				wave.append([id, ""])
			b -= EnemyDB.ENEMIES[id]["cost"]
		result.append(wave)
	var mods := EnemyDB.CHAMPION_MODS.keys()
	if type == "elite":
		var last: Array = result[result.size() - 1]
		var champ_id: String = pool[rng.randi_range(0, pool.size() - 1)]
		if champ_id == "bat":
			champ_id = "skeleton"
		last.append([champ_id, mods[rng.randi_range(0, mods.size() - 1)]])
		if Game.floor_idx >= 1:
			var champ2: String = pool[rng.randi_range(0, pool.size() - 1)]
			if champ2 != "bat":
				result[0].append([champ2, mods[rng.randi_range(0, mods.size() - 1)]])
	elif Game.floor_idx >= 1 and rng.randf() < 0.3:
		var last: Array = result[result.size() - 1]
		var idx := rng.randi_range(0, last.size() - 1)
		if last[idx][0] != "bat":
			last[idx][1] = mods[rng.randi_range(0, mods.size() - 1)]
	return result


func _begin_combat() -> void:
	in_combat = true
	_next_wave()


func _next_wave() -> void:
	if waves.is_empty():
		return
	var wave: Array = waves.pop_front()
	wave_timer = 0.0
	Audio.play("spawn", -6.0)
	for entry: Array in wave:
		var pos := room.random_floor_pos(player.global_position, 95.0)
		queue_spawn(entry[0], pos, entry[1], randf_range(0.7, 1.1))


func queue_spawn(id: String, pos: Vector2, champion: String, delay := 0.8) -> void:
	var col: Color = Color(0.75, 0.2, 0.9) if champion == "" else EnemyDB.CHAMPION_MODS[champion]["color"]
	ground_fx.sigil(pos, delay, col)
	pending_spawns.append({"id": id, "pos": pos, "champion": champion, "t": delay})


func spawn_enemy(id: String, pos: Vector2, champion: String) -> Enemy:
	var e := Enemy.new()
	e.setup(self, EnemyDB.scaled(id, Game.floor_idx), champion)
	e.position = pos
	room.add_child(e)
	enemies.append(e)
	fx.burst(pos, Color(0.4, 0.35, 0.3), 8, 30.0, 2.0, 1.5, 120.0, 0.5)
	return e


func _spawn_boss() -> void:
	var b := Boss.new()
	b.setup_boss(self, Game.floor_data()["boss"])
	b.position = room.center() + Vector2(0, -24)
	room.add_child(b)
	enemies.append(b)
	boss = b
	in_combat = true
	hud.show_boss(b)
	hud.show_banner(b.data["name"], b.data["title"], Color("d83a2a"), 1.6)
	Audio.music("boss", 0.5)
	Audio.play("boss_roar", 0.0)
	add_shake(0.6)
	fx.burst(b.position, Color(0.5, 0.45, 0.4), 30, 80.0, 4.0, 2.0)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if room == null:
		return
	if not player.dead:
		Game.run_time += delta
	var i := 0
	while i < _timers.size():
		_timers[i][0] -= delta
		if _timers[i][0] <= 0.0:
			var cb: Callable = _timers[i][1]
			_timers.remove_at(i)
			if cb.is_valid():
				cb.call()
		else:
			i += 1
	i = 0
	while i < pending_spawns.size():
		var p: Dictionary = pending_spawns[i]
		p["t"] -= delta
		if p["t"] <= 0.0:
			pending_spawns.remove_at(i)
			spawn_enemy(p["id"], p["pos"], p["champion"])
		else:
			i += 1
	if in_combat and boss == null and not player.dead:
		wave_timer += delta
		if pending_spawns.is_empty():
			if not waves.is_empty() and (enemies.size() <= 1 or wave_timer > 16.0):
				_next_wave()
			elif waves.is_empty() and enemies.is_empty() and not _clear_pending:
				_clear_pending = true
				delayed(0.5, _on_room_cleared)
	if Game.autoplay:
		_watchdog(delta)
	_update_interact()
	if not transitioning and not player.dead and room.unlocked:
		var d = room.door_at(player.global_position)
		if d != null:
			_go_through(d)


func _process(delta: float) -> void:
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = _base_time_scale
	if room != null:
		var target := _camera_target()
		camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-7.0 * delta))
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * shake * 7.0
	shake = maxf(0.0, shake - delta * 1.8)
	_stack_item_labels()


## Diablo-style: nudge overlapping ground-item labels apart so all are readable.
func _stack_item_labels() -> void:
	if room == null:
		return
	var items: Array = []
	for c in room.get_children():
		if c is WorldObjects.GroundItem and c.landed and c.enabled:
			items.append(c)
	if items.size() < 2:
		for it in items:
			it.label.position.y = -22.0
		return
	items.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.y > b.global_position.y)
	var placed: Array = []
	var f := Fx.font()
	for it in items:
		var w: float = f.get_string_size(it.label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 6.0
		var y: float = -22.0
		var r := Rect2(it.global_position + Vector2(-w * 0.5, y - 9.0), Vector2(w, 11.0))
		var guard := 0
		var moved := true
		while moved and guard < 12:
			moved = false
			guard += 1
			for pr: Rect2 in placed:
				if pr.intersects(r):
					y -= (r.end.y - pr.position.y) + 1.0
					r.position.y = it.global_position.y + y - 9.0
					moved = true
		placed.append(r)
		it.label.position.y = lerpf(it.label.position.y, y, 0.35)


func _unhandled_input(e: InputEvent) -> void:
	if ui_blocked() or player.dead:
		return
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		open_pause()
	elif e.is_action_pressed("sheet"):
		get_viewport().set_input_as_handled()
		open_sheet()


func _camera_target() -> Vector2:
	var t := player.global_position + Vector2(0, -12)
	if not player.dead and not Game.autoplay and not ui_blocked():
		var look := (get_global_mouse_position() - player.global_position) * 0.12
		t += look.limit_length(28.0)
	# Keep the view on the room when it is bigger than the screen.
	var b := room.bounds().grow(24.0)
	var half := get_viewport_rect().size * 0.5
	if b.size.x > half.x * 2.0:
		t.x = clampf(t.x, b.position.x + half.x, b.end.x - half.x)
	else:
		t.x = b.get_center().x
	if b.size.y > half.y * 2.0:
		t.y = clampf(t.y, b.position.y + half.y, b.end.y - half.y + 40.0)
	else:
		t.y = lerpf(b.get_center().y, t.y, 0.3)
	return t


func _update_interact() -> void:
	current_interact = null
	if transitioning or player.dead or ui_blocked():
		return
	var best_d := INF
	for c in room.get_children():
		if c is Interactable and c.can_interact():
			var d: float = c.global_position.distance_to(player.global_position)
			if d < c.interact_radius and d < best_d:
				best_d = d
				current_interact = c
	if current_interact == null:
		return
	if Input.is_action_just_pressed("interact") or (Game.autoplay and _bot_wants(current_interact)):
		current_interact.interact(self)
	elif Input.is_action_just_pressed("salvage") and current_interact.alt_prompt() != "":
		current_interact.alt_interact(self)


func _go_through(d: Dictionary) -> void:
	if transitioning:
		return
	Game.room_idx += 1
	Game.room_history.append(d["type"])
	Audio.play("dodge", -2.0, 0.0, 0.6)
	enter_room(d["type"])


func descend() -> void:
	if transitioning:
		return
	transitioning = true
	Audio.play("spawn", 0.0, 0.0, 0.5)
	await _fade(1.0, 1.0)
	Game.floor_idx = mini(Game.floor_idx + 1, Game.FLOORS.size() - 1)
	start_floor()


func _fade(to: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", to, dur)
	await tw.finished


# ---------------------------------------------------------------------------
# Combat events
# ---------------------------------------------------------------------------

func on_enemy_killed(e: Enemy, by_player: bool) -> void:
	enemies.erase(e)
	_last_kill_pos = e.global_position
	var decal := "blood_%d" % randi_range(0, 2)
	if e.data["gore"] == "bone":
		decal = "bones"
	room.add_decal(load("res://assets/sprites/props/%s.png" % decal), e.global_position,
		Color(0.6, 0.9, 0.4, 0.8) if e.data["gore"] == "rot" else Color(1, 1, 1, 0.85))
	Game.kills += 1
	var champ := e.champion != ""
	var mult := 3 if champ else 1
	if e.is_boss:
		mult = 15
	Game.add_xp(int(e.data["xp"]) * (2 if champ else 1))
	Game.add_souls(1.0 * mult)
	Game.add_flask_progress(1.0 / 18.0 * mult)
	fx.glow(e.global_position, 12.0, Color(0.5, 0.85, 1.0, 0.7), 0.3)
	if Game.stat("life_on_kill") > 0.0:
		Game.heal(Game.stat("life_on_kill"))
	var leech := Game.rite_count("leech")
	if leech > 0:
		Game.heal(3.0 * leech)
	player.on_kill()
	if Game.rite_count("corpse") > 0 and randf() < 0.35:
		explode(e.global_position, 30.0, minf(e.max_hp * 0.5, 80.0), 0, Color(0.8, 0.2, 0.15))
	var g: Array = e.data["gold"]
	var coins := randi_range(g[0], g[1]) * (2 if champ else 1)
	if coins > 0:
		drop_gold(e.global_position, coins * (Game.floor_idx + 1))
	var orb_chance := 0.045 if Game.hp > Game.stat("max_hp") * 0.4 else 0.09
	if not e.is_boss and randf() < orb_chance:
		_drop_orb(e.global_position)
	if champ and randf() < 0.6:
		drop_item(ItemDB.generate(Game.floor_idx, -1, "", ItemDB.MAGIC), e.global_position, true)
	elif not e.is_boss and randf() < 0.035:
		drop_item(ItemDB.generate(Game.floor_idx), e.global_position, true)
	if e.is_boss:
		_on_boss_killed(e)


func _on_room_cleared() -> void:
	if room == null or player.dead:
		return
	in_combat = false
	room.unlock()
	Audio.play("room_clear", -6.0)
	hud.message("The chamber falls silent.", Color("9a8a78"))
	var pos := room.clamp_to_floor(_last_kill_pos)
	if room_type == "elite":
		drop_item(ItemDB.generate(Game.floor_idx, -1, "", ItemDB.MAGIC), pos, true)
		if randf() < 0.5:
			drop_item(ItemDB.generate(Game.floor_idx, -1, "", ItemDB.RARE if Game.floor_idx > 0 else ItemDB.MAGIC), pos, true)
		drop_gold(pos, randi_range(10, 20) * (Game.floor_idx + 1))
	elif randf() < 0.45:
		drop_item(ItemDB.generate(Game.floor_idx), pos, true)
	if Game.pending_levels > 0:
		delayed(1.0, open_levelup)


func _on_boss_killed(b: Enemy) -> void:
	in_combat = false
	waves.clear()
	pending_spawns.clear()
	for e in enemies.duplicate():
		e.die(false)
	bullets.list = bullets.list.filter(func(x: Bullets.B) -> bool: return x.team == 0)
	hud.hide_boss()
	Audio.music("ambient", 3.0)
	hud.show_banner("Vanquished", b.data["name"] + " falls", UI.GOLD, 2.0)
	var pos := room.clamp_to_floor(b.global_position)
	drop_item(ItemDB.make_unique(Game.floor_idx), pos, true)
	drop_item(ItemDB.generate(Game.floor_idx, ItemDB.RARE), pos, true)
	drop_gold(pos, 40 * (Game.floor_idx + 1))
	_drop_orb(pos)
	_drop_orb(pos)
	room.unlock()
	delayed(2.5, _spawn_portal)
	if Game.pending_levels > 0:
		delayed(1.5, open_levelup)


func _spawn_portal() -> void:
	var p := WorldObjects.Portal.new()
	p.setup(self, room.center() + Vector2(0, -30), Game.floor_idx >= Game.FLOORS.size() - 1)
	room.add_child(p)
	Audio.play("awaken", -6.0, 0.0, 0.7)


func on_player_died() -> void:
	in_combat = false
	Audio.music("", 1.0)
	Audio.play("player_death", 0.0)
	Engine.time_scale = 0.35 * _base_time_scale
	_hitstop_until = Time.get_ticks_msec() + 1400
	hud.show_banner("You Have Died", "", Color("b8261f"), 2.0)
	delayed(1.4, _finish.bind(false))


func on_victory() -> void:
	Audio.play("item_unique", 0.0)
	_finish(true)


func abandon() -> void:
	_finish(false)


func _finish(victory: bool) -> void:
	if _ended:
		return
	_ended = true
	transitioning = true
	await _fade(1.0, 1.0)
	Engine.time_scale = _base_time_scale
	ended.emit(victory)


func _on_item_awakened(it: Dictionary) -> void:
	var r: Dictionary = ItemDB.RITES[it["rite"]]
	var txt := "%s AWAKENS - Rite of %s" % [it["name"], r["name"]]
	if it["cursed"]:
		txt += " (curse broken!)"
	hud.message(txt, UI.SOUL)
	Audio.play("awaken", -2.0)
	if player != null:
		fx.ring(player.global_position, 4.0, 60.0, UI.SOUL, 0.7, 3.0)
		fx.glow(player.global_position, 50.0, Color(0.5, 0.9, 1.0, 0.8), 0.6)
		fx.burst(player.global_position, UI.SOUL, 24, 60.0, 14.0, 2.0, -40.0, 1.0)


# ---------------------------------------------------------------------------
# Helpers used by entities
# ---------------------------------------------------------------------------

func explode(pos: Vector2, radius: float, dmg: float, team: int, color: Color, exclude: Variant = null) -> void:
	fx.ring(pos, 4.0, radius, color, 0.35, 2.0)
	fx.glow(pos, radius * 1.4, Color(color.r, color.g, color.b, 0.7), 0.3)
	fx.burst(pos, color, 14, radius * 2.2, 6.0, 2.0, 100.0, 0.5)
	Audio.play("explosion", -10.0 if team == 0 else -6.0, 0.15)
	add_shake(0.12 + radius / 400.0)
	if team == 0:
		for e in enemies.duplicate():
			if e == exclude or not e.alive:
				continue
			if Iso.ground_dist(e.global_position, pos) < radius + e.radius:
				e.take_damage(dmg, false, (e.global_position - pos).normalized() * 70.0)
	elif player != null and not player.dead:
		if Iso.ground_dist(player.global_position, pos) < radius + 3.0:
			player.take_hit(dmg, (player.global_position - pos).normalized())


func chain_lightning(from: Node, dmg: float, jumps: int) -> void:
	var hit := [from]
	var cur: Node = from
	for j in jumps:
		var best: Node = null
		var bd := 120.0
		for e in enemies:
			if e.alive and e not in hit:
				var d: float = e.global_position.distance_to(cur.global_position)
				if d < bd:
					bd = d
					best = e
		if best == null:
			break
		fx.lightning(cur.global_position, best.global_position)
		best.take_damage(dmg, false, Vector2.ZERO)
		hit.append(best)
		cur = best
	Audio.play("hit_bone", -4.0, 0.1, 2.2)


func drop_item(it: Dictionary, pos: Vector2, pop: bool) -> void:
	if room == null:
		return
	var g := WorldObjects.GroundItem.new()
	g.setup(self, it, room.clamp_to_floor(pos), pop)
	room.add_child(g)


func drop_gold(pos: Vector2, total: int) -> void:
	if room == null:
		return
	total = int(total * maxf(0.0, 1.0 + Game.stat("gold_find")))
	if total <= 0:
		return
	var n := clampi(total / 3, 1, 10)
	var per := total / n
	var rest := total - per * n
	for k in n:
		var p := WorldObjects.Pickup.new()
		p.setup(self, "gold", per + (rest if k == 0 else 0), pos)
		room.add_child(p)


func _drop_orb(pos: Vector2) -> void:
	var p := WorldObjects.Pickup.new()
	p.setup(self, "orb", 0.12, pos)
	room.add_child(p)


func nearest_enemy(pos: Vector2, max_d: float) -> Variant:
	var best: Variant = null
	var bd := max_d
	for e in enemies:
		if e.alive and e.state != "spawn":
			var d: float = e.global_position.distance_to(pos)
			if d < bd:
				bd = d
				best = e
	return best


func spawn_afterimage(src: Player) -> void:
	var s := Sprite2D.new()
	s.texture = src.sprite.texture
	s.hframes = src.sprite.hframes
	s.frame = src.sprite.frame
	s.flip_h = src.sprite.flip_h
	s.offset = src.sprite.offset
	s.scale = src.sprite.scale
	s.global_position = src.global_position
	s.modulate = Color(0.5, 0.6, 1.0, 0.45)
	s.material = Fx.unshaded_material()
	room.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.25)
	tw.tween_callback(s.queue_free)


func add_shake(amount: float) -> void:
	shake = minf(1.0, shake + amount)


func hitstop(seconds: float) -> void:
	if _hitstop_until > 0:
		return
	Engine.time_scale = 0.08 * _base_time_scale
	_hitstop_until = Time.get_ticks_msec() + int(seconds * 1000.0)


## Run `cb` after `seconds` of game time (paused with the game, cleared on room change).
func delayed(seconds: float, cb: Callable) -> void:
	_timers.append([seconds, cb])


# ---------------------------------------------------------------------------
# Modals
# ---------------------------------------------------------------------------

func ui_blocked() -> bool:
	return _modal != null or transitioning


func _open_modal(m: Control) -> void:
	if _modal != null:
		_modal.queue_free()
	_modal = m
	modal_layer.add_child(m)
	m.closed.connect(_on_modal_closed.bind(m))
	get_tree().paused = true


func _on_modal_closed(m: Control) -> void:
	if _modal == m:
		_modal = null
		get_tree().paused = false
		if Game.pending_levels > 0 and not in_combat and not player.dead:
			delayed(0.2, open_levelup)


func open_levelup(from_shop := false) -> void:
	if player.dead or (_modal != null and not from_shop):
		return
	if not from_shop and Game.pending_levels <= 0:
		return
	_open_modal(Modals.LevelUp.new(self, from_shop))


func open_shrine(altar: Node) -> void:
	_open_modal(Modals.Shrine.new(self, altar))


func open_rest(fire: Node) -> void:
	_open_modal(Modals.Rest.new(self, fire))


func open_pause() -> void:
	_open_modal(Modals.Pause.new(self))


func open_sheet() -> void:
	_open_modal(Modals.CharacterSheet.new(self))


# ---------------------------------------------------------------------------
# Debug bot (only used with --autoplay)
# ---------------------------------------------------------------------------

func _bot_wants(it: Interactable) -> bool:
	if it is WorldObjects.GroundItem:
		var key: int = it.item["id"]
		if _bot_seen.has(key):
			return false
		_bot_seen[key] = true
		return true
	return it is WorldObjects.Chest or it is WorldObjects.Portal


var _wd_t := 0.0
var _wd_room: Node = null


func _watchdog(delta: float) -> void:
	if _wd_room != room:
		_wd_room = room
		_wd_t = 0.0
	_wd_t += delta
	if _wd_t > 60.0:
		_wd_t = 0.0
		var info := []
		for e in enemies:
			info.append("%s@%s st=%s cell=%s" % [e.data["id"] if e.data.has("id") else "boss", e.global_position.round(), e.state, Iso.to_cell(e.global_position)])
		print("WATCHDOG room=%s type=%s unlocked=%s in_combat=%s waves=%d pending=%d enemies=%s player=%s cell=%s modal=%s" % [
			Game.room_idx, room_type, room.unlocked, in_combat, waves.size(), pending_spawns.size(), info,
			player.global_position.round(), Iso.to_cell(player.global_position), _modal])


func bot_target_item() -> Variant:
	for c in room.get_children():
		if c is WorldObjects.GroundItem and c.can_interact() and not _bot_seen.has(c.item["id"]):
			return c.global_position
		if (c is WorldObjects.Chest and not c.opened) or c is WorldObjects.Portal:
			return c.global_position
	return null


func bot_target_door() -> Variant:
	if bot_target_item() != null or room.doors.is_empty():
		return null
	var d: Dictionary = room.doors[Game.room_idx % room.doors.size()]
	return Iso.to_world(Vector2(d["cell"]))
