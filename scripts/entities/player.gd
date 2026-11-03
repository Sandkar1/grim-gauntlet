class_name Player
extends CharacterBody2D
## The player: WASD to move, mouse to aim, LMB to shoot, RMB skill,
## Space to dodge-roll, Q to drink a flask.

const SHOT_HEIGHT := 10.0
const DODGE_TIME := 0.22
const DODGE_SPEED_MULT := 3.1
const DODGE_COOLDOWN := 0.85
const IFRAMES_ON_HIT := 0.75

var run: Node
var sprite: Sprite2D
var weapon_pivot: Node2D
var weapon_sprite: Sprite2D
var light: PointLight2D
var shadow: Shadow
var mat: ShaderMaterial

var dead := false
var aim_dir := Vector2.RIGHT
var fire_cd := 0.0
var skill_cd := 0.0
var shot_count := 0
var dodge_t := 0.0
var dodge_cd := 0.0
var dodge_dir := Vector2.ZERO
var iframes := 0.0
var flash := 0.0
var anim_t := 0.0
var cast_t := 0.0
var haste_t := 0.0
var recoil := 0.0
var kills_for_spirit := 0
var _after_t := 0.0
var _contact_t := 0.0
var _bot_t := 0.0
var _bot_dir := Vector2.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	cs.shape = circle
	add_child(cs)

	shadow = Shadow.new()
	shadow.radius = 6.0
	add_child(shadow)

	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/flash.gdshader")
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/sprites/chars/%s.png" % Game.class_data()["sprite"])
	sprite.hframes = 7
	sprite.offset = Vector2(0, -13)
	sprite.material = mat
	# A touch brighter than the world so the hero reads against the floor.
	mat.set_shader_parameter("tint", Color(1.3, 1.25, 1.2))
	add_child(sprite)

	weapon_pivot = Node2D.new()
	weapon_pivot.position = Vector2(0, -SHOT_HEIGHT)
	add_child(weapon_pivot)
	weapon_sprite = Sprite2D.new()
	weapon_pivot.add_child(weapon_sprite)
	refresh_weapon()

	light = PointLight2D.new()
	light.texture = Fx.light_texture()
	light.color = Color(1.0, 0.84, 0.66)
	light.energy = 1.05
	light.texture_scale = 1.55
	light.position = Vector2(0, -8)
	add_child(light)

	Game.equipment_changed.connect(refresh_weapon)


func refresh_weapon() -> void:
	var it = Game.equipment.get("weapon")
	if it == null:
		return
	weapon_sprite.texture = load("res://assets/sprites/items/w_%s.png" % it["weapon"])
	weapon_sprite.offset = Vector2(weapon_sprite.texture.get_width() * 0.5 + 1, 0)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var s := Game.stats
	fire_cd -= delta
	skill_cd -= delta
	dodge_cd -= delta
	iframes -= delta
	haste_t -= delta
	cast_t -= delta
	_contact_t -= delta
	flash = maxf(0.0, flash - delta * 6.0)
	recoil = maxf(0.0, recoil - delta * 40.0)

	# --- movement -------------------------------------------------------
	var input := _input_vector()
	var speed: float = s["move_speed"] * (1.35 if haste_t > 0.0 else 1.0)
	if dodge_t > 0.0:
		dodge_t -= delta
		velocity = dodge_dir * speed * DODGE_SPEED_MULT
		_after_t -= delta
		if _after_t <= 0.0:
			_after_t = 0.035
			run.spawn_afterimage(self)
			if Game.rite_count("embers") > 0:
				run.ground_fx.zone(global_position, 16.0, 2.5, "fire", 6.0 * (1.0 + Game.stat("damage_pct")) * Game.rite_count("embers"))
	else:
		var target := Vector2(input.x, input.y * 0.85) * speed
		velocity = velocity.move_toward(target, speed * 12.0 * delta)
	move_and_slide()

	# --- aiming ---------------------------------------------------------
	var target_pos := _aim_target()
	var to := target_pos + Vector2(0, SHOT_HEIGHT) - global_position
	if to.length() > 2.0:
		aim_dir = to.normalized()
	weapon_pivot.rotation = aim_dir.angle()
	weapon_sprite.flip_v = aim_dir.x < 0.0
	weapon_sprite.position = Vector2(-recoil, 0)
	weapon_pivot.show_behind_parent = aim_dir.y < -0.35
	sprite.flip_h = aim_dir.x < 0.0

	# --- actions --------------------------------------------------------
	if run.ui_blocked():
		return
	var want_shoot: bool = Input.is_action_pressed("shoot") or (Game.autoplay and run.enemies.size() > 0)
	if want_shoot and fire_cd <= 0.0 and dodge_t <= 0.0:
		fire()
	var want_skill := Input.is_action_just_pressed("skill") or Input.is_action_just_pressed("skill_key")
	if Game.autoplay and Game.mana >= Game.stat("max_mana") * 0.95 and run.enemies.size() > 2:
		want_skill = true
	if want_skill:
		use_skill()
	var want_dodge := Input.is_action_just_pressed("dodge")
	if want_dodge and dodge_cd <= 0.0 and dodge_t <= 0.0:
		dodge(input)
	if Input.is_action_just_pressed("flask") or (Game.autoplay and Game.hp < Game.stat("max_hp") * 0.35):
		drink_flask()

	# --- regen ----------------------------------------------------------
	Game.mana = minf(s["max_mana"], Game.mana + s["mana_regen"] * delta)
	if s["life_regen"] != 0.0:
		Game.hp = clampf(Game.hp + s["life_regen"] * delta, 1.0, s["max_hp"])

	# --- contact damage from touching enemies ---------------------------
	if _contact_t <= 0.0:
		for e in run.enemies:
			if e.alive and e.contact_damage > 0.0 and global_position.distance_to(e.global_position) < e.radius + 4.0:
				if take_hit(e.contact_damage, (global_position - e.global_position).normalized()):
					_contact_t = 0.3
					var th := Game.rite_count("thorns")
					if th > 0:
						e.take_damage(30.0 * th, false, (e.global_position - global_position).normalized() * 80.0)
				break


func _process(delta: float) -> void:
	if dead:
		return
	anim_t += delta
	var moving := velocity.length() > 12.0
	if cast_t > 0.0:
		sprite.frame = 6
	elif dodge_t > 0.0:
		sprite.frame = 3
	elif moving:
		sprite.frame = 2 + int(anim_t * 10.0) % 4
	else:
		sprite.frame = int(anim_t * 2.0) % 2
	var blink := iframes > 0.0 and dodge_t <= 0.0 and int(iframes * 20.0) % 2 == 0
	sprite.modulate.a = 0.45 if blink else 1.0
	mat.set_shader_parameter("flash", flash)
	if dodge_t > 0.0:
		sprite.scale = Vector2(1.15, 0.85)
	else:
		sprite.scale = sprite.scale.lerp(Vector2.ONE, delta * 14.0)
	light.energy = 1.05 + 0.04 * sin(anim_t * 7.0)


func _input_vector() -> Vector2:
	if Game.autoplay:
		return _bot_input()
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _aim_target() -> Vector2:
	if Game.autoplay:
		var e = run.nearest_enemy(global_position, 400.0)
		if e != null:
			return e.global_position + Vector2(0, -SHOT_HEIGHT)
		return global_position + Vector2(40, -SHOT_HEIGHT)
	return get_global_mouse_position()


## Very small debug bot used by `--autoplay` smoke tests.
func _bot_input() -> Vector2:
	_bot_t -= get_physics_process_delta_time()
	if run.room != null and run.room.unlocked and run.enemies.is_empty():
		var door = run.bot_target_door()
		if door != null:
			return (door - global_position).normalized()
		var it = run.bot_target_item()
		if it != null:
			return (it - global_position).normalized()
	if _bot_t <= 0.0:
		_bot_t = randf_range(0.4, 1.0)
		var e = run.nearest_enemy(global_position, 500.0)
		var away := Vector2.ZERO
		if e != null:
			var d: Vector2 = global_position - e.global_position
			away = d.normalized() if d.length() < 90.0 else -d.normalized() * 0.4
		_bot_dir = (away + Vector2.from_angle(randf() * TAU) * 0.8).normalized()
		var c: Vector2 = run.room.center() - global_position
		if c.length() > 120.0:
			_bot_dir = (_bot_dir + c.normalized()).normalized()
	return _bot_dir


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

func fire() -> void:
	var s := Game.stats
	var w := Game.weapon_data()
	var rate: float = w["rate"] * (1.0 + s["attack_speed_pct"])
	fire_cd = 1.0 / maxf(0.2, rate)
	shot_count += 1
	var volleys := 2 if (Game.rite_count("echo") > 0 and shot_count % 4 == 0) else 1
	for v in volleys:
		_fire_volley(w, v * 0.06)
	Audio.play(w["sfx"], -6.0 if w["type"] == "repeater" else -3.0, 0.1)
	recoil = 4.0 if w["type"] == "blunderbuss" else 2.0
	if w["type"] == "blunderbuss":
		run.add_shake(0.25)
	run.fx.glow(global_position + aim_dir * 14.0, 10.0, Color(1.0, 0.7, 0.3, 0.6), 0.08)


func _fire_volley(w: Dictionary, delay: float) -> void:
	var s := Game.stats
	var count: int = w["count"] + int(s["extra_proj"])
	var spread: float = deg_to_rad(w["spread"])
	var extra_fan := deg_to_rad(10.0) if int(s["extra_proj"]) > 0 and w["count"] == 1 else 0.0
	var origin := global_position + aim_dir * 10.0
	for i in count:
		var ang := aim_dir.angle()
		if w["count"] > 1:
			ang += randf_range(-spread, spread) * 0.5
		else:
			ang += randf_range(-spread, spread) * 0.5
			if count > 1:
				ang += extra_fan * (float(i) - (count - 1) * 0.5)
		var speed: float = w["speed"] * (1.0 + s["proj_speed_pct"]) * (1.0 + randf_range(-1, 1) * w.get("speed_var", 0.0))
		var crit: bool = randf() < s["crit_chance"]
		var dmg: float = w["damage"] * (1.0 + s["damage_pct"]) * ((1.0 + s["crit_mult"] + 0.0) if crit else 1.0)
		var opts := {
			"r": w["size"] * 0.5 + 1.0, "life": w["life"], "pierce": int(w["pierce"] + s["pierce"]),
			"knock": w["knock"], "crit": crit, "delay": delay, "homing": w.get("homing", 0.0),
			"explode": w.get("explode", 0.0), "decel": w.get("decel", 0.0), "height": SHOT_HEIGHT,
		}
		match w["proj"]:
			"fireball":
				opts["color"] = Color(1.0, 0.55, 0.2)
			"pellet":
				opts["color"] = Color(1.0, 0.85, 0.5)
				opts["r"] = 2.0
			"skull":
				opts["color"] = Color(0.5, 1.0, 0.45)
			_:
				opts["color"] = Color(1.0, 0.9, 0.7)
		run.bullets.spawn(origin, Vector2.from_angle(ang) * speed, dmg, 0, w["proj"] if w["proj"] != "pellet" else "orb", opts)


func use_skill() -> void:
	var cls := Game.class_data()
	var cost: float = cls["skill_cost"]
	if skill_cd > 0.0 or Game.mana < cost or dodge_t > 0.0:
		if Game.mana < cost and Input.is_action_just_pressed("skill"):
			run.hud.flash_mana()
		return
	Game.mana -= cost
	skill_cd = 0.5
	cast_t = 0.25
	var w := Game.weapon_data()
	var power: float = w["damage"] * w["count"] * (1.0 + Game.stat("damage_pct")) * (1.0 + Game.stat("skill_pct"))
	Audio.play("skill", -2.0)
	match cls["skill"]:
		"volley":
			for i in 9:
				var ang := aim_dir.angle() + deg_to_rad(-28.0 + i * 7.0)
				run.bullets.spawn(global_position + aim_dir * 8.0, Vector2.from_angle(ang) * 430.0, power * 0.85, 0, "bolt",
					{"r": 3.0, "life": 0.8, "pierce": 1 + int(Game.stat("pierce")), "knock": 50.0, "color": Color(1, 0.9, 0.7), "height": SHOT_HEIGHT})
			run.add_shake(0.2)
		"nova":
			for i in 18:
				var ang := TAU * i / 18.0
				run.bullets.spawn(global_position, Vector2.from_angle(ang) * 210.0, power * 0.6, 0, "fireball",
					{"r": 4.0, "life": 0.7, "explode": 16.0, "knock": 60.0, "color": Color(1.0, 0.35, 0.15), "height": 8.0})
			run.explode(global_position, 44.0 * (1.0 + Game.stat("area_pct")), power * 0.8, 0, Color(1.0, 0.3, 0.1))
			run.add_shake(0.4)
		"consecrate":
			run.ground_fx.zone(global_position, 56.0 * (1.0 + Game.stat("area_pct")), 4.5, "holy", power * 0.42)
			run.fx.ring(global_position, 10.0, 60.0, Color(1.0, 0.9, 0.5), 0.5, 2.0)
			run.fx.glow(global_position, 70.0, Color(1.0, 0.85, 0.4, 0.6), 0.5)
			run.add_shake(0.25)


func dodge(input: Vector2) -> void:
	dodge_dir = input.normalized() if input.length() > 0.1 else aim_dir
	dodge_t = DODGE_TIME
	dodge_cd = DODGE_COOLDOWN / (1.0 + Game.stat("dodge_cd_pct"))
	iframes = maxf(iframes, DODGE_TIME + 0.05)
	_after_t = 0.0
	Audio.play("dodge", -4.0)
	run.fx.burst(global_position, Color(0.5, 0.45, 0.4), 6, 30.0, 1.0, 1.5, 100.0, 0.4)


func drink_flask() -> void:
	if Game.flask_charges <= 0 or Game.hp >= Game.stat("max_hp"):
		return
	Game.flask_charges -= 1
	var amount: float = Game.stat("max_hp") * maxf(0.1, Game.stat("flask_heal"))
	Game.heal(amount)
	if Game.rite_count("phylactery") > 0:
		Game.mana = Game.stat("max_mana")
	Audio.play("flask", -2.0)
	run.fx.number(global_position, amount, Color("ff5a5a"), true)
	run.fx.burst(global_position, Color("d82020"), 14, 40.0, 14.0, 2.0, -40.0, 0.7)
	run.fx.glow(global_position, 30.0, Color(1.0, 0.2, 0.2, 0.6), 0.4)


## Returns true if the hit landed.
func take_hit(raw: float, dir: Vector2) -> bool:
	if dead or iframes > 0.0 or dodge_t > 0.0 or run.transitioning:
		return false
	var dmg := raw * 100.0 / (100.0 + maxf(0.0, Game.stat("armor"))) * (1.0 + Game.stat("dmg_taken_pct"))
	Game.hp -= dmg
	iframes = IFRAMES_ON_HIT
	flash = 1.0
	velocity += dir * 120.0
	Audio.play("player_hurt", -1.0)
	run.add_shake(0.45)
	run.hitstop(0.06)
	run.fx.number(global_position, dmg, Color("ff3030"), true)
	run.fx.gore(global_position, "blood", 10)
	run.hud.damage_flash()
	var mt := Game.rite_count("martyr")
	if mt > 0:
		var w := Game.weapon_data()
		for i in 12:
			run.bullets.spawn(global_position, Vector2.from_angle(TAU * i / 12.0) * 260.0, w["damage"] * 0.8 * mt, 0, "bolt",
				{"r": 3.0, "life": 0.7, "pierce": 1, "knock": 50.0, "color": Color(1, 0.95, 0.7)})
	if Game.hp <= 0.0:
		if Game.rite_count("revenant") > 0 and not Game.revenant_used:
			Game.revenant_used = true
			Game.hp = 1.0
			iframes = 2.0
			Game.notify.emit("Revenant: death refuses you", Color("7ee0ff"))
			run.fx.ring(global_position, 4.0, 70.0, Color(0.5, 0.9, 1.0), 0.6, 3.0)
			Audio.play("awaken", -4.0)
		else:
			Game.hp = 0.0
			die()
	Game.stats_changed.emit()
	return true


func die() -> void:
	dead = true
	velocity = Vector2.ZERO
	weapon_pivot.visible = false
	sprite.frame = 0
	var tw := create_tween()
	tw.tween_property(sprite, "rotation", PI * 0.5 * (-1.0 if sprite.flip_h else 1.0), 0.5).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(sprite, "offset", Vector2(0, -6), 0.5)
	tw.parallel().tween_property(light, "energy", 0.35, 1.5)
	run.fx.gore(global_position, "blood", 30)
	run.on_player_died()


func on_kill() -> void:
	if Game.rite_count("haste") > 0:
		haste_t = 2.0
	var sp := Game.rite_count("spectral")
	if sp > 0:
		kills_for_spirit += 1
		if kills_for_spirit >= 3:
			kills_for_spirit = 0
			var w := Game.weapon_data()
			for i in sp:
				run.bullets.spawn(global_position + Vector2(0, -6), Vector2.from_angle(randf() * TAU) * 160.0,
					w["damage"] * w["count"] * 1.6 * (1.0 + Game.stat("damage_pct")), 0, "orb",
					{"r": 4.0, "life": 2.5, "homing": 7.0, "color": Color(0.55, 0.9, 1.0), "pierce": 1, "knock": 30.0})


## Soft elliptical shadow under a character.
class Shadow extends Node2D:
	var radius := 6.0

	func _ready() -> void:
		z_index = -8
		z_as_relative = false

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.42))
		draw_circle(Vector2.ZERO, radius * 0.65, Color(0, 0, 0, 0.2))
