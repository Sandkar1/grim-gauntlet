class_name GroundFx
extends Node2D
## Things painted flat on the floor, under the characters: attack telegraphs,
## summoning sigils, and lingering zones (holy ground, burning embers).
## Zones also deal their damage from here.

var telegraphs: Array = [] # {pos, radius, t, dur, color, kind, dir, length, width}
var sigils: Array = [] # {pos, t, dur, color}
var zones: Array = [] # {pos, radius, t, dur, kind, tick, dmg}
var run: Node


func _ready() -> void:
	material = Fx.unshaded_material()
	z_index = -7
	z_as_relative = false


func clear() -> void:
	telegraphs.clear()
	sigils.clear()
	zones.clear()


func circle(pos: Vector2, radius: float, dur: float, color := Color(0.9, 0.15, 0.1)) -> void:
	telegraphs.append({"pos": pos, "radius": radius, "t": 0.0, "dur": dur, "color": color, "kind": "circle"})


func line(pos: Vector2, dir: Vector2, length: float, width: float, dur: float, color := Color(0.9, 0.15, 0.1)) -> void:
	telegraphs.append({"pos": pos, "dir": dir, "length": length, "width": width, "t": 0.0, "dur": dur, "color": color, "kind": "line"})


func sigil(pos: Vector2, dur: float, color := Color(0.75, 0.2, 0.9)) -> void:
	sigils.append({"pos": pos, "t": 0.0, "dur": dur, "color": color})


func zone(pos: Vector2, radius: float, dur: float, kind: String, dmg: float) -> void:
	zones.append({"pos": pos, "radius": radius, "t": 0.0, "dur": dur, "kind": kind, "tick": 0.0, "dmg": dmg})


func _process(delta: float) -> void:
	for arr: Array in [telegraphs, sigils]:
		var i := 0
		while i < arr.size():
			arr[i]["t"] += delta
			if arr[i]["t"] >= arr[i]["dur"]:
				arr.remove_at(i)
			else:
				i += 1
	var j := 0
	while j < zones.size():
		var z: Dictionary = zones[j]
		z["t"] += delta
		z["tick"] -= delta
		if z["tick"] <= 0.0:
			z["tick"] = 0.4
			_zone_tick(z)
		if z["t"] >= z["dur"]:
			zones.remove_at(j)
		else:
			j += 1
	queue_redraw()


func _zone_tick(z: Dictionary) -> void:
	if run == null:
		return
	for e in run.enemies:
		if is_instance_valid(e) and e.alive and Iso.ground_dist(e.global_position, z["pos"]) < z["radius"]:
			e.take_damage(z["dmg"], false, Vector2.ZERO, false)
	if z["kind"] == "holy" and run.player != null and Iso.ground_dist(run.player.global_position, z["pos"]) < z["radius"]:
		Game.heal(2.0)
	if z["kind"] == "holy":
		run.fx.embers(z["pos"], Color("ffe08a"), 3)
	else:
		run.fx.embers(z["pos"], Color("ff8a2a"), 2)


func _draw() -> void:
	for tg: Dictionary in telegraphs:
		var t: float = tg["t"] / tg["dur"]
		var c: Color = tg["color"]
		if tg["kind"] == "circle":
			draw_set_transform(tg["pos"], 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, tg["radius"], Color(c.r, c.g, c.b, 0.12 + 0.1 * t))
			draw_circle(Vector2.ZERO, tg["radius"] * t, Color(c.r, c.g, c.b, 0.25))
			draw_arc(Vector2.ZERO, tg["radius"], 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.8), 2.0)
		else:
			var d: Vector2 = tg["dir"]
			var n: Vector2 = d.orthogonal() * tg["width"] * 0.5
			var a: Vector2 = tg["pos"]
			var b: Vector2 = a + d * tg["length"]
			draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), Color(c.r, c.g, c.b, 0.12 + 0.18 * t))
			draw_line(a, a + d * tg["length"] * t, Color(c.r, c.g, c.b, 0.6), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for s: Dictionary in sigils:
		var t: float = s["t"] / s["dur"]
		var c: Color = s["color"]
		var r := 12.0 * minf(1.0, t * 3.0)
		draw_set_transform(s["pos"], 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, r, Color(c.r, c.g, c.b, 0.18))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.9), 1.5)
		var rot: float = s["t"] * 2.0
		var pts := PackedVector2Array()
		for k in 6:
			pts.append(Vector2.from_angle(rot + k * TAU * 2.0 / 5.0) * r * 0.9)
		draw_polyline(pts, Color(c.r, c.g, c.b, 0.7), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for z: Dictionary in zones:
		var fade := clampf((z["dur"] - z["t"]) / 0.5, 0.0, 1.0) * clampf(z["t"] / 0.2, 0.0, 1.0)
		var c := Color(1.0, 0.85, 0.4) if z["kind"] == "holy" else Color(1.0, 0.4, 0.1)
		draw_set_transform(z["pos"], 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, z["radius"], Color(c.r, c.g, c.b, 0.16 * fade))
		draw_arc(Vector2.ZERO, z["radius"] * (0.92 + 0.05 * sin(z["t"] * 6.0)), 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.6 * fade), 1.5)
		if z["kind"] == "holy":
			draw_line(Vector2(-z["radius"] * 0.5, 0), Vector2(z["radius"] * 0.5, 0), Color(c.r, c.g, c.b, 0.4 * fade), 2.0)
			draw_line(Vector2(0, -z["radius"] * 0.5), Vector2(0, z["radius"] * 0.5), Color(c.r, c.g, c.b, 0.4 * fade), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
