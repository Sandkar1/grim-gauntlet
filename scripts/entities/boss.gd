class_name Boss
extends Enemy
## Floor bosses. Each boss cycles through a list of attack patterns; below
## 50% life it enters phase two and its patterns intensify.
##
## A pattern is a small function called every frame with `pt` (time since the
## pattern started). `every(interval)` fires once per interval.

var boss_id := ""
var pattern := ""
var pt := 0.0
var pattern_len := 0.0
var phase := 1
var cycle: Array = []
var cycle_i := 0
var spiral_a := 0.0
var intro := true
var _dt := 0.0
var _move_target := Vector2.ZERO


func setup_boss(run_: Node, id: String) -> void:
	boss_id = id
	var d: Dictionary = EnemyDB.BOSSES[id].duplicate()
	d["ai"] = "boss"
	d["xp"] = 40
	d["gold"] = [30, 50]
	setup(run_, d)
	is_boss = true
	contact_damage = d["dmg"]
	match id:
		"bone_warden":
			cycle = ["stalk", "slam", "spiral", "stalk", "summon", "slam", "sweep"]
		"mother_of_rot":
			cycle = ["spew", "rain", "pulse", "birth", "spew", "rain", "flower"]
		"hollow_bishop":
			cycle = ["judgement", "cross", "teleport", "halo", "judgement", "summon", "teleport", "cross"]


func _ready() -> void:
	super._ready()
	bar.visible = false
	state = "intro"
	state_t = 1.6
	var lt := PointLight2D.new()
	lt.texture = Fx.light_texture()
	lt.color = {"bone_warden": Color(1.0, 0.4, 0.3), "mother_of_rot": Color(0.6, 1.0, 0.4), "hollow_bishop": Color(1.0, 0.9, 0.6)}[boss_id]
	lt.energy = 0.8
	lt.texture_scale = 0.9
	lt.position = Vector2(0, -20)
	add_child(lt)


func _think(delta: float, spd: float, dir: Vector2, dist: float, pl: Node) -> Vector2:
	_dt = delta
	if state == "intro":
		if state_t <= 0.0:
			state = "fight"
			_next_pattern()
		return Vector2.ZERO
	if phase == 1 and hp < max_hp * 0.5:
		phase = 2
		run.fx.ring(global_position, 10.0, 120.0, Color(1.0, 0.3, 0.2), 0.8, 4.0)
		run.add_shake(0.8)
		Audio.play("boss_roar", 0.0)
		Game.notify.emit("%s is enraged!" % data["name"], Color("ff5040"))
		speed *= 1.25
	pt += delta
	var v := Vector2.ZERO
	match pattern:
		"stalk":
			v = _chase(spd, pl)
			if dist < 55.0 and pt > 0.8:
				_set_pattern("slam", 1.3)
		"slam":
			v = _p_slam(pl)
		"spiral":
			_p_spiral()
		"summon":
			_p_summon(["skeleton", "skeleton", "skel_archer"] if phase == 1 else ["skeleton", "skeleton", "skel_archer", "ghoul"])
		"sweep":
			_p_sweep(pl)
		"spew":
			v = _chase(spd * 0.6, pl)
			_p_spew(pl)
		"rain":
			_p_rain(pl)
		"pulse":
			_p_pulse()
		"birth":
			_p_summon(["bloater", "bat", "bat", "bat"] if phase == 1 else ["bloater", "bloater", "bat", "bat", "bat"])
		"flower":
			_p_flower()
		"judgement":
			v = dir.orthogonal() * spd * 0.8 * signf(sin(pt))
			_p_judgement(pl)
		"cross":
			_p_cross()
		"teleport":
			_p_teleport(pl)
		"halo":
			_p_halo(pl)
	if pt >= pattern_len:
		_next_pattern()
	return v


func every(interval: float) -> bool:
	return int(pt / interval) != int((pt - _dt) / interval)


func _set_pattern(p: String, length: float) -> void:
	pattern = p
	pt = 0.0
	pattern_len = length


func _next_pattern() -> void:
	var p: String = cycle[cycle_i % cycle.size()]
	cycle_i += 1
	var lengths := {"stalk": 2.4, "slam": 1.3, "spiral": 3.6, "summon": 1.2, "sweep": 2.2, "spew": 2.6, "rain": 2.8,
		"pulse": 2.4, "birth": 1.2, "flower": 4.0, "judgement": 2.6, "cross": 4.0, "teleport": 1.0, "halo": 3.0}
	_set_pattern(p, lengths.get(p, 2.0) * (0.85 if phase == 2 else 1.0))
	state = "fight"


# ---------------------------------------------------------------------------
# Bone Warden
# ---------------------------------------------------------------------------

func _p_slam(pl: Node) -> Vector2:
	if pt - _dt <= 0.0:
		run.ground_fx.circle(global_position, 70.0, 0.75)
		flash = 0.6
		state = "windup"
	if pt >= 0.75 and pt - _dt < 0.75:
		state = "fight"
		run.explode(global_position, 70.0, dmg, 1, Color(0.9, 0.85, 0.7))
		run.bullets.ring(global_position, 20 if phase == 1 else 28, 105.0, dmg * 0.6, randf() * TAU, Color(0.95, 0.9, 0.75), "shard", {"r": 3.0})
		if phase == 2:
			run.bullets.ring(global_position, 20, 70.0, dmg * 0.6, 0.15, Color(0.95, 0.9, 0.75), "shard", {"r": 3.0})
		Audio.play("slam", 2.0)
		run.add_shake(0.7)
	return Vector2.ZERO


func _p_spiral() -> void:
	if every(0.11 if phase == 1 else 0.08):
		var arms := 3 if phase == 1 else 4
		spiral_a += deg_to_rad(13.0)
		for i in arms:
			run.bullets.enemy_shot(global_position, Vector2.from_angle(spiral_a + TAU * i / arms), 92.0, dmg * 0.55, Color(0.95, 0.9, 0.75), "shard", {"r": 3.0})
			if phase == 2:
				run.bullets.enemy_shot(global_position, Vector2.from_angle(-spiral_a * 1.3 + TAU * i / arms), 70.0, dmg * 0.55, Color(1.0, 0.45, 0.3), "orb")
		if every(0.33):
			Audio.play("enemy_shoot", -12.0, 0.1, 0.6)
	state = "windup" if pt < 0.3 else "fight"


func _p_summon(ids: Array) -> void:
	if pt - _dt <= 0.0:
		state = "windup"
		Audio.play("boss_roar", -6.0, 0.05, 1.2)
		var alive_count := 0
		for e in run.enemies:
			if e.alive and not e.is_boss:
				alive_count += 1
		if alive_count < 6:
			for id: String in ids:
				run.queue_spawn(id, run.room.random_floor_pos(run.player.global_position, 80.0), "")
	if pt > 0.6:
		state = "fight"


func _p_sweep(pl: Node) -> void:
	if every(0.55) and pt < 2.0:
		var aim: Vector2 = (pl.global_position - global_position).normalized()
		run.bullets.fan(global_position, aim, 7 if phase == 1 else 9, 70.0, 140.0, dmg * 0.6, Color(0.95, 0.9, 0.75), "shard", {"r": 3.0})
		Audio.play("enemy_shoot", -8.0)
		flash = 0.4


# ---------------------------------------------------------------------------
# Mother of Rot
# ---------------------------------------------------------------------------

func _p_spew(pl: Node) -> void:
	if every(0.7 if phase == 1 else 0.5):
		state = "windup"
		var aim: Vector2 = (pl.global_position - global_position).normalized()
		for i in (9 if phase == 1 else 13):
			var a := aim.angle() + deg_to_rad(randf_range(-38, 38))
			run.bullets.enemy_shot(global_position + Vector2(0, -6), Vector2.from_angle(a), randf_range(80, 150), dmg * 0.55, Color(0.55, 0.95, 0.25), "orb", {"decel": 0.35})
		Audio.play("enemy_shoot", -6.0, 0.1, 0.5)
	elif pt > 0.3:
		state = "fight"


func _p_rain(pl: Node) -> void:
	if every(0.3) and pt < 2.4:
		var p: Vector2 = pl.global_position + Vector2(randf_range(-60, 60), randf_range(-30, 30))
		p = run.room.clamp_to_floor(p)
		run.ground_fx.circle(p, 24.0, 0.9, Color(0.5, 0.9, 0.2))
		run.delayed(0.9, _rain_hit.bind(p))


func _rain_hit(p: Vector2) -> void:
	if not alive or run.room == null:
		return
	run.explode(p, 24.0, dmg * 0.8, 1, Color(0.5, 0.9, 0.2))
	run.bullets.ring(p, 5 if phase == 1 else 7, 60.0, dmg * 0.4, randf() * TAU, Color(0.55, 0.95, 0.25))


func _p_pulse() -> void:
	if every(0.6) and pt < 2.0:
		state = "windup"
		run.bullets.ring(global_position, 24 if phase == 1 else 32, 72.0, dmg * 0.55, pt * 0.4, Color(0.6, 0.95, 0.3))
		run.fx.ring(global_position, 10.0, 40.0, Color(0.5, 0.9, 0.2), 0.3)
		Audio.play("enemy_shoot", -8.0, 0.05, 0.4)


func _p_flower() -> void:
	if every(0.09):
		spiral_a += deg_to_rad(9.0)
		var arms := 5 if phase == 1 else 7
		for i in arms:
			run.bullets.enemy_shot(global_position, Vector2.from_angle(spiral_a + TAU * i / arms), 75.0, dmg * 0.5, Color(0.8, 0.95, 0.3), "orb", {"curve": 0.5})


# ---------------------------------------------------------------------------
# Hollow Bishop
# ---------------------------------------------------------------------------

func _p_judgement(pl: Node) -> void:
	if every(0.5 if phase == 1 else 0.38) and pt < 2.3:
		flash = 0.4
		var aim: Vector2 = (pl.global_position - global_position).normalized()
		run.bullets.fan(global_position, aim, 5, 26.0, 185.0, dmg * 0.6, Color(1.0, 0.85, 0.4))
		Audio.play("shoot_magic", -8.0, 0.1, 1.4)


func _p_cross() -> void:
	if every(0.07):
		var arms := 4 if phase == 1 else 6
		spiral_a += deg_to_rad(2.6)
		for i in arms:
			run.bullets.enemy_shot(global_position, Vector2.from_angle(spiral_a + TAU * i / arms), 120.0, dmg * 0.5, Color(1.0, 0.9, 0.5))
			if phase == 2 and i % 2 == 0:
				run.bullets.enemy_shot(global_position, Vector2.from_angle(-spiral_a + TAU * i / arms), 90.0, dmg * 0.5, Color(1.0, 0.4, 0.3))
	state = "windup"
	if pt >= pattern_len - 0.1:
		state = "fight"


func _p_teleport(pl: Node) -> void:
	if pt - _dt <= 0.0:
		phased = true
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.3)
		run.fx.burst(global_position, Color(1.0, 0.9, 0.6), 20, 50.0, 30.0, 2.0, -30.0, 0.8)
	if pt >= 0.45 and pt - _dt < 0.45:
		global_position = run.room.random_floor_pos(pl.global_position, 130.0, 3)
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 1.0, 0.3)
		run.fx.burst(global_position, Color(1.0, 0.9, 0.6), 20, 50.0, 30.0, 2.0, -30.0, 0.8)
		Audio.play("spawn", -4.0, 0.05, 1.4)
	if pt >= 0.75:
		phased = false
		if pt - _dt < 0.75:
			run.bullets.ring(global_position, 18, 95.0, dmg * 0.5, randf() * TAU, Color(1.0, 0.85, 0.45))


func _p_halo(pl: Node) -> void:
	if pt - _dt <= 0.0:
		state = "windup"
		var n := 30 if phase == 1 else 40
		for i in n:
			run.bullets.enemy_shot(global_position, Vector2.from_angle(TAU * i / n), 25.0, dmg * 0.55, Color(1.0, 0.95, 0.6), "orb", {"accel": 1.1, "max_speed": 210.0})
		Audio.play("awaken", -10.0, 0.05, 0.8)
	if phase == 2 and every(0.8) and pt > 0.5:
		var aim: Vector2 = (pl.global_position - global_position).normalized()
		run.bullets.fan(global_position, aim, 3, 14.0, 160.0, dmg * 0.6, Color(1.0, 0.4, 0.3))
	if pt > 0.5:
		state = "fight"


func _process(delta: float) -> void:
	super._process(delta)
	if alive and state in ["fight", "intro"] and velocity.length() < 8.0:
		sprite.frame = int(anim_t * 3.0) % 2 if boss_id != "hollow_bishop" else 2 + int(anim_t * 6.0) % 4


func take_damage(amount: float, crit := false, push := Vector2.ZERO, show_number := true) -> bool:
	if state == "intro":
		return false
	return super.take_damage(amount, crit, push, show_number)


func die(by_player := true) -> void:
	if not alive:
		return
	run.add_shake(1.0)
	for i in 6:
		run.fx.ring(global_position, 4.0 + i * 6.0, 90.0 + i * 20.0, Color(1.0, 0.5, 0.3), 0.6 + i * 0.1, 3.0)
	Audio.play("boss_roar", 0.0, 0.0, 0.7)
	Audio.play("explosion", 0.0)
	super.die(by_player)
