class_name Enemy
extends CharacterBody2D
## A monster. Behaviour is chosen by `data.ai`:
##   melee    - walks up and lunges            (Skeleton)
##   archer   - keeps distance, aimed arrows    (Skeleton Archer)
##   bat      - erratic swooping flyer          (Crypt Bat)
##   charger  - telegraphs, then dashes         (Ghoul)
##   caster   - radial bursts, blinks away      (Cultist)
##   bomber   - waddles close and explodes      (Bloater)
##   wraith   - phases out, fires spreads       (Wraith)
##   imp      - hops around, throws fire        (Imp)
##   brute    - slow, ground-slam shockwaves    (Flayed Brute)
## Every attack is telegraphed (red flash / ground marker) so it's fair.

var run: Node
var data: Dictionary
var alive := true
var hp := 10.0
var max_hp := 10.0
var radius := 6.0
var speed := 50.0
var contact_damage := 10.0
var dmg := 10.0
var champion := ""
var champion_name := ""
var is_boss := false

var sprite: Sprite2D
var mat: ShaderMaterial
var shadow: Player.Shadow
var bar: HealthBar

var state := "spawn"
var state_t := 0.0
var attack_cd := 1.0
var anim_t := 0.0
var flash := 0.0
var slow_t := 0.0
var knock := Vector2.ZERO
var path := PackedVector2Array()
var path_t := 0.0
var lock_dir := Vector2.ZERO
var wobble := 0.0
var fly_h := 0.0
var phased := false
var hexed_done := false
var _sep := Vector2.ZERO


func setup(run_: Node, d: Dictionary, champ := "") -> void:
	run = run_
	data = d
	max_hp = d["hp"]
	radius = d["radius"]
	speed = d["speed"]
	dmg = d["dmg"]
	contact_damage = dmg if d["ai"] not in ["archer", "caster"] else dmg * 0.5
	fly_h = d.get("fly", 0.0)
	champion = champ
	if champion != "":
		champion_name = EnemyDB.champion_name()
		max_hp *= 2.6 if champion == "Stoneskin" else 2.0
		if champion == "Fanatic":
			speed *= 1.45
	hp = max_hp
	wobble = randf() * TAU
	attack_cd = randf_range(0.8, 1.8)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = minf(radius, 7.0)
	cs.shape = c
	add_child(cs)
	shadow = Player.Shadow.new()
	shadow.radius = radius + 1.0
	add_child(shadow)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/flash.gdshader")
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/sprites/chars/%s.png" % data["sprite"])
	sprite.hframes = 7
	sprite.offset = Vector2(0, -data["fh"] * 0.5 + 2 - fly_h)
	sprite.material = mat
	add_child(sprite)
	if champion != "":
		sprite.scale = Vector2(1.2, 1.2)
		mat.set_shader_parameter("tint", EnemyDB.CHAMPION_MODS[champion]["color"].lerp(Color.WHITE, 0.45))
		var lt := PointLight2D.new()
		lt.texture = Fx.light_texture()
		lt.color = EnemyDB.CHAMPION_MODS[champion]["color"]
		lt.energy = 0.6
		lt.texture_scale = 0.4
		lt.position = Vector2(0, -10)
		add_child(lt)
	bar = HealthBar.new()
	bar.enemy = self
	bar.position = Vector2(0, -data["fh"] * (1.2 if champion != "" else 1.0) - fly_h - 2)
	add_child(bar)
	# Rise from the ground.
	sprite.modulate = Color(1, 1, 1, 0)
	sprite.position.y = 8
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate:a", 1.0, 0.35)
	tw.tween_property(sprite, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	state = "spawn"
	state_t = 0.4


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var pl = run.player
	if pl == null or pl.dead:
		velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
		move_and_slide()
		return
	slow_t -= delta
	flash = maxf(0.0, flash - delta * 7.0)
	attack_cd -= delta
	state_t -= delta
	path_t -= delta
	var spd := speed * (1.0 + Game.stat("enemy_speed_pct")) * (0.65 if slow_t > 0.0 else 1.0)
	var to_player: Vector2 = pl.global_position - global_position
	var dist := to_player.length()
	var dir := to_player / maxf(dist, 0.001)
	var want := Vector2.ZERO

	if state == "spawn":
		if state_t <= 0.0:
			state = "move"
	else:
		want = _think(delta, spd, dir, dist, pl)

	_sep = _separation()
	velocity = velocity.move_toward(want + _sep * 40.0, 600.0 * delta) + knock
	knock = knock.move_toward(Vector2.ZERO, 500.0 * delta)
	move_and_slide()
	if is_on_wall() and state == "dash" and data["ai"] == "charger":
		state = "stunned"
		state_t = 0.7
		run.add_shake(0.2)
		Audio.play("slam", -8.0)


## Returns the desired velocity for this frame.
func _think(delta: float, spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match data["ai"]:
		"melee":
			return _ai_melee(spd, dir, dist, pl)
		"archer":
			return _ai_archer(spd, dir, dist, pl)
		"bat":
			wobble += delta * 5.0
			var side := dir.orthogonal() * sin(wobble) * 0.9
			if state == "move" and dist < 70.0 and attack_cd <= 0.0:
				state = "dash"
				state_t = 0.45
				lock_dir = dir
				attack_cd = 1.6
			if state == "dash":
				if state_t <= 0.0:
					state = "move"
				return lock_dir * spd * 1.8
			return (dir + side).normalized() * spd
		"charger":
			return _ai_charger(spd, dir, dist, pl)
		"caster":
			return _ai_caster(spd, dir, dist, pl)
		"bomber":
			return _ai_bomber(spd, dir, dist, pl)
		"wraith":
			return _ai_wraith(spd, dir, dist, pl)
		"imp":
			return _ai_imp(spd, dir, dist, pl)
		"brute":
			return _ai_brute(spd, dir, dist, pl)
	return Vector2.ZERO


func _chase(spd: float, pl: Node) -> Vector2:
	var target: Vector2 = pl.global_position
	if fly_h > 0.0 or run.room.line_of_sight(global_position, target):
		path = PackedVector2Array()
		return (target - global_position).normalized() * spd
	if path_t <= 0.0 or path.is_empty():
		path = run.room.find_path(global_position, target)
		path_t = 0.5
		if path.size() > 0:
			path.remove_at(0)
	while path.size() > 0 and global_position.distance_to(path[0]) < 6.0:
		path.remove_at(0)
	if path.size() > 0:
		return (path[0] - global_position).normalized() * spd
	return (target - global_position).normalized() * spd


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for e in run.enemies:
		if e == self or not e.alive:
			continue
		var d: Vector2 = global_position - e.global_position
		var l := d.length()
		var min_d: float = radius + e.radius
		if l < min_d and l > 0.01:
			push += d / l * (1.0 - l / min_d)
	return push


func _ai_melee(spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match state:
		"move":
			if dist < 34.0 and attack_cd <= 0.0:
				state = "windup"
				state_t = 0.42
				lock_dir = dir
				flash = 0.6
				return Vector2.ZERO
			return _chase(spd, pl)
		"windup":
			if state_t <= 0.0:
				state = "dash"
				state_t = 0.2
				Audio.play("shoot_axe", -10.0, 0.2, 0.7)
			return Vector2.ZERO
		"dash":
			if state_t <= 0.0:
				state = "recover"
				state_t = 0.45
				attack_cd = randf_range(0.9, 1.4)
			return lock_dir * 175.0
		"recover":
			if state_t <= 0.0:
				state = "move"
			return Vector2.ZERO
	return _chase(spd, pl)


func _ai_archer(spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match state:
		"move":
			var los: bool = run.room.line_of_sight(global_position, pl.global_position)
			if attack_cd <= 0.0 and los and dist < 230.0:
				state = "windup"
				state_t = 0.55
				flash = 0.5
				return Vector2.ZERO
			if not los or dist > 170.0:
				return _chase(spd, pl)
			if dist < 100.0:
				return -dir * spd
			return dir.orthogonal() * spd * 0.5 * sin(anim_t + wobble)
		"windup":
			if state_t <= 0.0:
				var aim: Vector2 = (pl.global_position - global_position).normalized()
				var n := 1 if Game.floor_idx == 0 else 3
				run.bullets.fan(global_position, aim, n, 22.0, 165.0 + Game.floor_idx * 15.0, dmg, Color(1.0, 0.5, 0.35), "arrow", {"r": 3.0})
				Audio.play("shoot_bolt", -9.0, 0.1, 0.8)
				state = "move"
				attack_cd = randf_range(1.8, 2.6) / (1.45 if champion == "Fanatic" else 1.0)
			return Vector2.ZERO
	return Vector2.ZERO


func _ai_charger(spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match state:
		"move":
			if dist < 150.0 and attack_cd <= 0.0 and run.room.line_of_sight(global_position, pl.global_position):
				state = "windup"
				state_t = 0.6
				lock_dir = dir
				run.ground_fx.line(global_position, lock_dir, 150.0, 14.0, 0.6)
				flash = 0.5
				return Vector2.ZERO
			return _chase(spd, pl)
		"windup":
			if state_t <= 0.0:
				state = "dash"
				state_t = 0.5
				Audio.play("dodge", -6.0, 0.1, 0.6)
			return Vector2.ZERO
		"dash":
			if state_t <= 0.0:
				state = "recover"
				state_t = 0.5
				attack_cd = randf_range(1.5, 2.2)
			run.fx.burst(global_position, Color(0.4, 0.38, 0.35), 1, 20.0, 1.0, 1.5, 80.0, 0.4)
			return lock_dir * 290.0
		"recover", "stunned":
			if state_t <= 0.0:
				state = "move"
			return Vector2.ZERO
	return Vector2.ZERO


func _ai_caster(spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match state:
		"move":
			if dist < 60.0 and randf() < 0.01:
				_blink(pl)
			if attack_cd <= 0.0 and dist < 260.0:
				state = "windup"
				state_t = 0.65
				run.fx.glow(global_position + Vector2(0, -26), 14.0, Color(0.6, 0.3, 1.0, 0.8), 0.65)
				return Vector2.ZERO
			if dist > 150.0:
				return _chase(spd, pl)
			if dist < 100.0:
				return -dir * spd
			return dir.orthogonal() * spd * 0.6
		"windup":
			if state_t <= 0.0:
				var n := 10 if Game.floor_idx < 2 else 14
				run.bullets.ring(global_position, n, 70.0, dmg, randf() * TAU, Color(0.7, 0.3, 1.0))
				Audio.play("enemy_shoot", -6.0)
				state = "move"
				attack_cd = randf_range(2.6, 3.4)
			return Vector2.ZERO
	return Vector2.ZERO


func _blink(pl: Node) -> void:
	run.fx.burst(global_position, Color(0.6, 0.3, 1.0), 12, 40.0, 14.0, 1.5, -20.0, 0.6)
	global_position = run.room.random_floor_pos(pl.global_position, 110.0)
	run.fx.burst(global_position, Color(0.6, 0.3, 1.0), 12, 40.0, 14.0, 1.5, -20.0, 0.6)
	Audio.play("spawn", -10.0, 0.1, 1.5)


func _ai_bomber(spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match state:
		"move":
			if dist < 34.0:
				_start_fuse()
				return Vector2.ZERO
			return _chase(spd, pl)
		"fuse":
			flash = 0.5 + 0.5 * sin(state_t * 40.0)
			sprite.scale = Vector2.ONE * (1.0 + (0.7 - state_t) * 0.35)
			if state_t <= 0.0:
				_bloater_explode()
			return Vector2.ZERO
	return Vector2.ZERO


func _start_fuse() -> void:
	state = "fuse"
	state_t = 0.7
	run.ground_fx.circle(global_position, 42.0, 0.7, Color(0.5, 0.9, 0.2))
	Audio.play("enemy_shoot", -6.0, 0.05, 0.5)


func _bloater_explode() -> void:
	if not alive:
		return
	var pos := global_position
	run.bullets.ring(pos, 12, 85.0, dmg * 0.6, randf() * TAU, Color(0.55, 0.95, 0.25))
	run.explode(pos, 42.0, dmg, 1, Color(0.5, 0.9, 0.2))
	die(false)


func _ai_wraith(spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match state:
		"move":
			if attack_cd <= 0.0 and dist < 220.0:
				state = "windup"
				state_t = 0.5
				flash = 0.6
				return Vector2.ZERO
			if randf() < 0.004:
				state = "phase"
				state_t = 1.1
				phased = true
				sprite.modulate.a = 0.25
			if dist > 110.0:
				return dir * spd
			return dir.orthogonal() * spd * signf(sin(wobble))
		"phase":
			if state_t <= 0.0:
				state = "move"
				phased = false
				sprite.modulate.a = 1.0
			return dir * spd * 1.6
		"windup":
			if state_t <= 0.0:
				run.bullets.fan(global_position, dir, 3, 30.0, 105.0, dmg, Color(0.5, 0.85, 1.0), "orb", {"homing": 0.4})
				Audio.play("shoot_wand", -8.0, 0.1, 0.7)
				state = "move"
				attack_cd = randf_range(2.0, 2.8)
			return Vector2.ZERO
	return Vector2.ZERO


func _ai_imp(spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match state:
		"move":
			if state_t <= 0.0:
				state = "hop"
				state_t = 0.35
				var side := 1.0 if randf() < 0.5 else -1.0
				lock_dir = (dir * (1.0 if dist > 120.0 else -0.4) + dir.orthogonal() * side).normalized()
			if attack_cd <= 0.0 and dist < 220.0:
				state = "windup"
				state_t = 0.4
				flash = 0.5
			return Vector2.ZERO
		"hop":
			if state_t <= 0.0:
				state = "move"
				state_t = randf_range(0.3, 0.8)
			return lock_dir * spd * 2.0
		"windup":
			if state_t <= 0.0:
				run.bullets.fan(global_position, dir, 3, 24.0, 150.0, dmg, Color(1.0, 0.55, 0.15))
				Audio.play("shoot_magic", -9.0, 0.1, 1.3)
				state = "move"
				state_t = 0.3
				attack_cd = randf_range(1.6, 2.3)
			return Vector2.ZERO
	return Vector2.ZERO


func _ai_brute(spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	match state:
		"move":
			if dist < 60.0 and attack_cd <= 0.0:
				state = "windup"
				state_t = 0.85
				run.ground_fx.circle(global_position, 58.0, 0.85)
				return Vector2.ZERO
			return _chase(spd, pl)
		"windup":
			if state_t <= 0.0:
				run.explode(global_position, 58.0, dmg, 1, Color(0.9, 0.3, 0.2))
				run.bullets.ring(global_position, 14, 95.0, dmg * 0.6, randf() * TAU, Color(1.0, 0.35, 0.2))
				Audio.play("slam", 0.0)
				run.add_shake(0.5)
				state = "recover"
				state_t = 0.6
				attack_cd = randf_range(2.0, 2.8)
			return Vector2.ZERO
		"recover":
			if state_t <= 0.0:
				state = "move"
			return Vector2.ZERO
	return Vector2.ZERO


func _process(delta: float) -> void:
	if not alive:
		return
	anim_t += delta
	var moving := velocity.length() > 8.0
	if state in ["windup", "fuse"]:
		sprite.frame = 6
	elif state == "dash" and data["ai"] in ["melee", "charger"]:
		sprite.frame = 6
	elif moving or data["ai"] == "bat":
		sprite.frame = 2 + int(anim_t * (14.0 if data["ai"] == "bat" else 9.0)) % 4
	else:
		sprite.frame = int(anim_t * 2.0) % 2
	if run.player != null and state not in ["dash", "hop"]:
		sprite.flip_h = run.player.global_position.x < global_position.x
	elif state in ["dash", "hop"]:
		sprite.flip_h = velocity.x < 0.0
	mat.set_shader_parameter("flash", flash)
	if slow_t > 0.0:
		mat.set_shader_parameter("flash_color", Color(0.6, 0.85, 1.0))
	else:
		mat.set_shader_parameter("flash_color", Color(1.0, 0.25, 0.15) if (state == "windup" and not is_boss) else Color(1.0, 0.95, 0.9))


# ---------------------------------------------------------------------------

## Returns true if this hit killed the enemy.
func take_damage(amount: float, crit := false, push := Vector2.ZERO, show_number := true) -> bool:
	if not alive or state == "spawn" or phased:
		return false
	hp -= amount
	flash = 1.0
	if not is_boss:
		knock += push * (0.4 if champion == "Stoneskin" else 1.0)
	if show_number:
		run.fx.number(global_position, amount, Color("ffc21a") if crit else Color("ffffff"), crit)
	Audio.play(data.get("hit_sfx", "hit_bone" if data["gore"] == "bone" else "hit"), -10.0, 0.15)
	bar.show_t = 2.5
	if champion == "Hexed" and not hexed_done and hp < max_hp * 0.5:
		hexed_done = true
		run.bullets.ring(global_position, 16, 80.0, dmg * 0.6, 0.0, Color(0.7, 0.3, 1.0))
	if hp <= 0.0:
		die(true)
		return true
	return false


func apply_slow(t: float) -> void:
	slow_t = maxf(slow_t, t)


func die(by_player := true) -> void:
	if not alive:
		return
	alive = false
	if data["ai"] == "bomber" and state != "fuse" and by_player:
		# Bloaters still pop when killed, just weaker.
		run.bullets.ring(global_position, 8, 75.0, dmg * 0.5, randf() * TAU, Color(0.55, 0.95, 0.25))
		run.fx.ring(global_position, 4.0, 30.0, Color(0.5, 0.9, 0.2), 0.3)
	if champion == "Fire-Touched":
		run.bullets.ring(global_position, 12, 90.0, dmg * 0.6, 0.0, Color(1.0, 0.5, 0.1))
	run.on_enemy_killed(self, by_player)
	run.fx.gore(global_position, data["gore"], 14 if not is_boss else 60)
	Audio.play("enemy_die", -6.0, 0.15)
	collision_layer = 0
	bar.visible = false
	var tw := create_tween().set_parallel(true)
	mat.set_shader_parameter("flash", 1.0)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tw.tween_property(sprite, "scale", Vector2(1.3, 0.4), 0.3)
	tw.tween_property(shadow, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)


## Small health bar (and champion name) above an enemy.
class HealthBar extends Node2D:
	var enemy: Enemy
	var show_t := 0.0

	func _ready() -> void:
		material = Fx.unshaded_material()
		z_index = 15
		z_as_relative = false

	func _process(delta: float) -> void:
		show_t -= delta
		queue_redraw()

	func _draw() -> void:
		if enemy.is_boss:
			return
		var champ := enemy.champion != ""
		if show_t <= 0.0 and not champ:
			return
		var w := 18.0 if not champ else 26.0
		var pct := clampf(enemy.hp / enemy.max_hp, 0.0, 1.0)
		draw_rect(Rect2(-w * 0.5 - 1, -1, w + 2, 4), Color(0.05, 0.02, 0.03, 0.9))
		draw_rect(Rect2(-w * 0.5, 0, w * pct, 2), Color(0.85, 0.15, 0.12) if not champ else EnemyDB.CHAMPION_MODS[enemy.champion]["color"])
		if champ:
			var f := Fx.font()
			var txt := enemy.champion_name
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string_outline(f, Vector2(-tw * 0.5, -3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color(0.03, 0.02, 0.03))
			draw_string(f, Vector2(-tw * 0.5, -3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, EnemyDB.CHAMPION_MODS[enemy.champion]["color"])
