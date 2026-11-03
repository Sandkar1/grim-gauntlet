class_name Bullets
extends Node2D
## Manages every projectile in the room (player and enemy) in one place.
##
## Projectiles live on the ground plane (`pos`) and are drawn `height` pixels
## above it, so their shadow shows where they really are. Collision against
## walls uses the room grid; against creatures, simple circle checks.

class B:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var r := 3.0
	var dmg := 5.0
	var team := 0 # 0 = player, 1 = enemy
	var life := 1.0
	var pierce := 0
	var hit := {}
	var kind := "orb"
	var color := Color.WHITE
	var homing := 0.0
	var explode := 0.0
	var decel := 0.0
	var accel := 0.0
	var curve := 0.0
	var height := 10.0
	var knock := 0.0
	var crit := false
	var delay := 0.0
	var shard := false
	var dead := false
	var t := 0.0
	var max_speed := 420.0

var list: Array = []
var run: Node
var tex := {}
var _glow: GlowLayer
var _shadow: ShadowLayer


class GlowLayer extends Node2D:
	var owner_b: Bullets

	func _draw() -> void:
		var g := Fx.glow_texture()
		for b: Bullets.B in owner_b.list:
			if b.dead or b.delay > 0.0:
				continue
			if b.kind in ["bolt", "arrow", "axe", "shard"] and b.team == 0:
				continue
			var p := b.pos - Vector2(0, b.height)
			var s := b.r * 3.2
			var c := b.color
			c.a = 0.55
			draw_texture_rect(g, Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), false, c)


class ShadowLayer extends Node2D:
	var owner_b: Bullets

	func _draw() -> void:
		for b: Bullets.B in owner_b.list:
			if b.dead or b.delay > 0.0:
				continue
			draw_set_transform(b.pos, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, maxf(1.5, b.r * 0.7), Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ready() -> void:
	z_index = 10
	z_as_relative = false
	material = Fx.unshaded_material()
	for k in ["bolt", "axe", "skull", "shard", "orb"]:
		tex[k] = load("res://assets/sprites/fx/%s.png" % k)
	_glow = GlowLayer.new()
	_glow.owner_b = self
	_glow.material = Fx.additive_material()
	_glow.z_index = 9
	_glow.z_as_relative = false
	add_child(_glow)
	_shadow = ShadowLayer.new()
	_shadow.owner_b = self
	_shadow.z_index = -6
	_shadow.z_as_relative = false
	add_child(_shadow)


func clear() -> void:
	list.clear()


func spawn(pos: Vector2, vel: Vector2, dmg: float, team: int, kind: String, opts := {}) -> B:
	var b := B.new()
	b.pos = pos
	b.vel = vel
	b.dmg = dmg
	b.team = team
	b.kind = kind
	for k: String in opts:
		b.set(k, opts[k])
	list.append(b)
	return b


## Convenience for enemy attacks.
func enemy_shot(pos: Vector2, dir: Vector2, speed: float, dmg: float, color := Color(1.0, 0.3, 0.2), kind := "orb", opts := {}) -> B:
	var o := {"r": 3.5, "life": 6.0, "color": color, "height": 9.0}
	o.merge(opts, true)
	return spawn(pos, dir.normalized() * speed, dmg, 1, kind, o)


func ring(pos: Vector2, count: int, speed: float, dmg: float, offset := 0.0, color := Color(1.0, 0.3, 0.2), kind := "orb", opts := {}) -> void:
	for i in count:
		enemy_shot(pos, Vector2.from_angle(offset + TAU * i / count), speed, dmg, color, kind, opts)


func fan(pos: Vector2, dir: Vector2, count: int, spread_deg: float, speed: float, dmg: float, color := Color(1.0, 0.3, 0.2), kind := "orb", opts := {}) -> void:
	var base := dir.angle()
	for i in count:
		var t := 0.0 if count == 1 else (float(i) / (count - 1) - 0.5)
		enemy_shot(pos, Vector2.from_angle(base + deg_to_rad(spread_deg) * t), speed, dmg, color, kind, opts)


func _physics_process(delta: float) -> void:
	if run == null or run.room == null:
		return
	var player = run.player
	var enemies: Array = run.enemies
	for b: B in list:
		if b.dead:
			continue
		if b.delay > 0.0:
			b.delay -= delta
			continue
		b.t += delta
		b.life -= delta
		if b.life <= 0.0:
			_expire(b)
			continue
		if b.homing > 0.0:
			var target = null
			if b.team == 0:
				var best := 190.0
				for e in enemies:
					if e.alive and not b.hit.has(e.get_instance_id()):
						var d: float = b.pos.distance_to(e.global_position)
						if d < best:
							best = d
							target = e.global_position
			elif player != null and not player.dead:
				target = player.global_position
			if target != null:
				var want: float = (target - b.pos).angle()
				var cur := b.vel.angle()
				var diff := wrapf(want - cur, -PI, PI)
				b.vel = b.vel.rotated(clampf(diff, -b.homing * delta, b.homing * delta))
		if b.curve != 0.0:
			b.vel = b.vel.rotated(b.curve * delta)
		if b.accel != 0.0:
			b.vel *= 1.0 + b.accel * delta
			if b.vel.length() > b.max_speed:
				b.vel = b.vel.normalized() * b.max_speed
		if b.decel > 0.0:
			b.vel *= maxf(0.0, 1.0 - b.decel * delta)
		b.pos += b.vel * delta
		if run.room.blocks_projectile(b.pos):
			_impact_wall(b)
			continue
		if b.team == 0:
			for e in enemies:
				if not e.alive or b.hit.has(e.get_instance_id()):
					continue
				if b.pos.distance_to(e.global_position) < e.radius + b.r + 2.0:
					_hit_enemy(b, e)
					if b.dead:
						break
		elif player != null and not player.dead:
			if b.pos.distance_to(player.global_position) < 3.5 + b.r * 0.8:
				if player.take_hit(b.dmg, b.vel.normalized()):
					b.dead = true
					run.fx.sparks(b.pos, b.color, 5)
	list = list.filter(func(x: B) -> bool: return not x.dead)
	queue_redraw()
	_glow.queue_redraw()
	_shadow.queue_redraw()


func _hit_enemy(b: B, e: Node) -> void:
	b.hit[e.get_instance_id()] = true
	var dmg := b.dmg
	var exe := Game.rite_count("executioner")
	if exe > 0 and e.hp < e.max_hp * 0.35:
		dmg *= 1.0 + 0.8 * exe
	e.take_damage(dmg, b.crit, b.vel.normalized() * b.knock)
	if Game.rite_count("frost") > 0:
		e.apply_slow(2.0)
	var storm := Game.rite_count("storm")
	if storm > 0 and randf() < 0.15 * storm:
		run.chain_lightning(e, dmg * 0.7, 3)
	if b.crit and Game.rite_count("volatile") > 0:
		run.explode(b.pos, 26.0, dmg * 0.6, 0, Color(1.0, 0.6, 0.2))
	if not b.shard and Game.rite_count("splinter") > 0:
		for s in [-1.0, 1.0]:
			var nb := spawn(b.pos, b.vel.rotated(deg_to_rad(35.0 * s)) * 0.8, dmg * 0.45, 0, "shard",
				{"r": 2.0, "life": 0.4, "shard": true, "knock": 10.0})
			nb.hit[e.get_instance_id()] = true
	if b.explode > 0.0:
		run.explode(b.pos, b.explode * (1.0 + Game.stat("area_pct")), dmg * 0.55, 0, Color(1.0, 0.5, 0.15), e)
		b.dead = true
		return
	run.fx.sparks(b.pos - Vector2(0, b.height - 4), Color(1.0, 0.9, 0.6), 3, 60.0)
	if b.pierce > 0:
		b.pierce -= 1
		b.dmg *= 0.85
	else:
		b.dead = true


func _impact_wall(b: B) -> void:
	b.dead = true
	if b.explode > 0.0 and b.team == 0:
		run.explode(b.pos, b.explode * (1.0 + Game.stat("area_pct")), b.dmg * 0.55, 0, Color(1.0, 0.5, 0.15))
	else:
		run.fx.sparks(b.pos - Vector2(0, b.height), b.color if b.team == 1 else Color(1, 0.85, 0.5), 4, 50.0)


func _expire(b: B) -> void:
	b.dead = true
	if b.explode > 0.0 and b.team == 0:
		run.explode(b.pos, b.explode * (1.0 + Game.stat("area_pct")), b.dmg * 0.55, 0, Color(1.0, 0.5, 0.15))


func _draw() -> void:
	for b: B in list:
		if b.dead or b.delay > 0.0:
			continue
		var p := b.pos - Vector2(0, b.height)
		var fade := clampf(b.life / 0.12, 0.0, 1.0)
		match b.kind:
			"bolt", "arrow", "shard":
				var t: Texture2D = tex["shard" if b.kind == "shard" else "bolt"]
				draw_set_transform(p, b.vel.angle(), Vector2.ONE)
				var mod := Color(1, 1, 1, fade) if b.kind != "arrow" else Color(1.0, 0.55, 0.45, fade)
				draw_texture(t, -t.get_size() * 0.5, mod)
			"axe":
				var t: Texture2D = tex["axe"]
				draw_set_transform(p, b.t * 16.0 * signf(b.vel.x + 0.01), Vector2.ONE)
				draw_texture(t, -t.get_size() * 0.5, Color(1, 1, 1, fade))
			"skull":
				var t: Texture2D = tex["skull"]
				draw_set_transform(p, 0.0, Vector2(-1.0 if b.vel.x < 0 else 1.0, 1.0))
				draw_texture(t, -t.get_size() * 0.5, Color(1, 1, 1, fade))
			_:
				var t: Texture2D = tex["orb"]
				var s := b.r * 2.4
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var c := b.color
				c.a = fade
				draw_texture_rect(t, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, c)
				var core := s * 0.45
				draw_texture_rect(t, Rect2(p - Vector2(core, core) * 0.5, Vector2(core, core)), false, Color(1, 1, 0.95, fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
