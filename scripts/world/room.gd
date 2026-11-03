class_name Room
extends Node2D
## One dungeon room: an isometric grid with walls, doors, props and torches.
##
## The room node is Y-sorted and lives inside the Run's Y-sorted world, so
## walls, props, enemies, pickups and the player all depth-sort together.

enum { FLOOR, WALL, BLOCK, DOOR }

const WALL_H := 40
const RIM_H := 6

var run: Node
var type := "combat"
var biome := "crypt"
var W := 13
var H := 13
var grid := {}
var doors: Array = []
var spawn_cell := Vector2i.ZERO
var astar := AStarGrid2D.new()
var unlocked := false
var rng := RandomNumberGenerator.new()

var _floor: FloorDrawer
var _body: StaticBody2D
var _torches: Array = []
var _t := 0.0

var tex_floor: Texture2D
var tex_floor_glow: Texture2D
var tex_wall: Texture2D
var tex_rim: Texture2D
var tex_door: Texture2D
var tex_bars: Texture2D
var tex_icons: Texture2D


## Draws all floor tiles and decals in one pass (cheap and static).
class FloorDrawer extends Node2D:
	var room: Room
	var decals: Array = [] # [texture, position, modulate, flip]
	var glow: Node2D

	func _draw() -> void:
		for c: Vector2i in room.grid:
			var t: int = room.grid[c]
			if t == Room.WALL:
				continue
			var v := absi(hash(c * 7 + Vector2i(room.W, room.H))) % 8
			if v > 5 and hash(c) % 3 != 0:
				v = v % 4
			var p := Iso.to_world(Vector2(c)) - Vector2(16, 8)
			draw_texture_rect_region(room.tex_floor, Rect2(p, Vector2(32, 16)), Rect2(v * 32, 0, 32, 16))
		for d: Array in decals:
			var tex: Texture2D = d[0]
			var sz := tex.get_size()
			draw_set_transform(d[1], 0.0, Vector2(-1 if d[3] else 1, 1))
			draw_texture(tex, -sz * 0.5, d[2])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Emissive floor details (inferno lava cracks), drawn unshaded.
class FloorGlow extends Node2D:
	var room: Room

	func _draw() -> void:
		for c: Vector2i in room.grid:
			if room.grid[c] == Room.WALL:
				continue
			var v := absi(hash(c * 7 + Vector2i(room.W, room.H))) % 8
			if v > 5 and hash(c) % 3 != 0:
				v = v % 4
			var p := Iso.to_world(Vector2(c)) - Vector2(16, 8)
			draw_texture_rect_region(room.tex_floor_glow, Rect2(p, Vector2(32, 16)), Rect2(v * 32, 0, 32, 16))


func setup(run_: Node, type_: String, biome_: String, door_types: Array, seed_: int) -> void:
	run = run_
	type = type_
	biome = biome_
	rng.seed = seed_
	y_sort_enabled = true
	_load_textures()
	match type:
		"boss":
			W = 17
			H = 17
		"combat", "elite":
			W = rng.randi_range(12, 15)
			H = rng.randi_range(12, 15)
		_:
			W = 11
			H = 11
	_build_grid(door_types)
	_build_floor()
	_build_walls()
	_build_collision()
	_build_props()
	_build_astar()


func _load_textures() -> void:
	var p := "res://assets/sprites/tiles/"
	tex_floor = load(p + "floor_%s.png" % biome)
	tex_floor_glow = load(p + "floor_glow_%s.png" % biome)
	tex_wall = load(p + "wall_%s.png" % biome)
	tex_rim = load(p + "rim_%s.png" % biome)
	tex_door = load(p + "door_%s.png" % biome)
	tex_bars = load(p + "door_bars.png")
	tex_icons = load("res://assets/sprites/ui/room_icons.png")


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_grid(door_types: Array) -> void:
	grid.clear()
	for y in H:
		for x in W:
			var edge := x == 0 or y == 0 or x == W - 1 or y == H - 1
			grid[Vector2i(x, y)] = WALL if edge else FLOOR
	spawn_cell = Vector2i(W - 3, H - 3)
	# Exit doors live on the two back walls (top-left and top-right edges).
	var spots: Array = []
	match door_types.size():
		1:
			spots = [["ne", Vector2i(W / 2, 0)]] if rng.randf() < 0.5 else [["nw", Vector2i(0, H / 2)]]
		2:
			spots = [["nw", Vector2i(0, H / 2)], ["ne", Vector2i(W / 2, 0)]]
		3:
			spots = [["nw", Vector2i(0, H / 2)], ["ne", Vector2i(int(W * 0.3), 0)], ["ne", Vector2i(int(W * 0.7), 0)]]
	doors.clear()
	for i in spots.size():
		var cell: Vector2i = spots[i][1]
		grid[cell] = DOOR
		var inner := cell + (Vector2i(0, 1) if spots[i][0] == "ne" else Vector2i(1, 0))
		doors.append({"cell": cell, "side": spots[i][0], "type": door_types[i], "inner": inner,
			"open": false, "sprite": null, "bars": null, "icon": null, "body": null})
	_place_obstacles()


func _place_obstacles() -> void:
	if type in ["shop", "rest", "shrine", "treasure", "start"]:
		return
	var patterns := ["pillars4", "pillars_ring", "scatter", "center", "none", "pillars4", "scatter"]
	if type == "boss":
		patterns = ["pillars_boss"]
	var pat: String = patterns[rng.randi_range(0, patterns.size() - 1)]
	var cells: Array = []
	var cx := W / 2
	var cy := H / 2
	match pat:
		"pillars4":
			var ox := maxi(3, W / 3)
			var oy := maxi(3, H / 3)
			cells = [Vector2i(ox, oy), Vector2i(W - 1 - ox, oy), Vector2i(ox, H - 1 - oy), Vector2i(W - 1 - ox, H - 1 - oy)]
		"pillars_boss":
			cells = [Vector2i(3, 3), Vector2i(W - 4, 3), Vector2i(3, H - 4), Vector2i(W - 4, H - 4)]
		"pillars_ring":
			for a in 6:
				var ang := TAU * a / 6.0
				cells.append(Vector2i(cx + roundi(cos(ang) * (W / 2 - 3)), cy + roundi(sin(ang) * (H / 2 - 3))))
		"center":
			cells = [Vector2i(cx, cy), Vector2i(cx + 1, cy), Vector2i(cx, cy + 1), Vector2i(cx + 1, cy + 1)]
		"scatter":
			for _i in rng.randi_range(3, 6):
				cells.append(Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3)))
	for c: Vector2i in cells:
		if grid.get(c) != FLOOR:
			continue
		# Keep the spawn area and door approaches clear.
		if Vector2(c - spawn_cell).length() < 3.0:
			continue
		var near_door := false
		for d: Dictionary in doors:
			if Vector2(c - d["inner"]).length() < 2.5:
				near_door = true
		if near_door:
			continue
		grid[c] = BLOCK
		if not _all_reachable():
			grid[c] = FLOOR


func _all_reachable() -> bool:
	var seen := {spawn_cell: true}
	var stack := [spawn_cell]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and grid.get(n) == FLOOR:
				seen[n] = true
				stack.append(n)
	for c: Vector2i in grid:
		if grid[c] == FLOOR and not seen.has(c):
			return false
	for d: Dictionary in doors:
		if not seen.has(d["inner"]):
			return false
	return true


func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for c: Vector2i in grid:
		if grid[c] != FLOOR:
			astar.set_point_solid(c, true)


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _build_floor() -> void:
	_floor = FloorDrawer.new()
	_floor.room = self
	_floor.z_index = -10
	_floor.z_as_relative = false
	add_child(_floor)
	if biome == "inferno":
		var g := FloorGlow.new()
		g.room = self
		g.z_index = -9
		g.z_as_relative = false
		var mat := CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		g.material = mat
		add_child(g)
	# Scatter some decals: blood, bones, rubble.
	var decal_tex := [load("res://assets/sprites/props/blood_0.png"), load("res://assets/sprites/props/blood_1.png"),
		load("res://assets/sprites/props/blood_2.png"), load("res://assets/sprites/props/bones.png"),
		load("res://assets/sprites/props/rubble.png"), load("res://assets/sprites/props/skulls.png")]
	for _i in rng.randi_range(3, 7):
		var c := Vector2i(rng.randi_range(1, W - 2), rng.randi_range(1, H - 2))
		if grid.get(c) == FLOOR:
			var tex: Texture2D = decal_tex[rng.randi_range(0, decal_tex.size() - 1)]
			_floor.decals.append([tex, Iso.to_world(Vector2(c)) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-3, 3)),
				Color(1, 1, 1, 0.85), rng.randf() < 0.5])


func add_decal(tex: Texture2D, pos: Vector2, col := Color.WHITE) -> void:
	_floor.decals.append([tex, pos, col, randf() < 0.5])
	if _floor.decals.size() > 140:
		_floor.decals.remove_at(0)
	_floor.queue_redraw()


func _wall_sprite(tex: Texture2D, cell: Vector2i, hh: int, region_x: int, flip := false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.region_enabled = true
	s.region_rect = Rect2(region_x, 0, 32, 16 + hh)
	s.offset = Vector2(-16, -(8 + hh))
	s.position = Iso.to_world(Vector2(cell))
	s.flip_h = flip
	add_child(s)
	return s


func _build_walls() -> void:
	for c: Vector2i in grid:
		var t: int = grid[c]
		if t == WALL:
			var back := c.x == 0 or c.y == 0
			if back:
				var v := absi(hash(c)) % 3
				_wall_sprite(tex_wall, c, WALL_H, v * 32)
			else:
				_wall_sprite(tex_rim, c, RIM_H, 0)
	for d: Dictionary in doors:
		var flip: bool = d["side"] == "nw"
		d["sprite"] = _wall_sprite(tex_door, d["cell"], WALL_H, 0, flip)
		var bars := Sprite2D.new()
		bars.texture = tex_bars
		bars.centered = false
		bars.offset = Vector2(-16, -(8 + WALL_H))
		bars.flip_h = flip
		d["sprite"].add_child(bars)
		d["bars"] = bars
		var icon := DoorIcon.new()
		icon.setup(tex_icons, d["type"])
		icon.position = Vector2(8 if flip else -8, -66)
		d["sprite"].add_child(icon)
		d["icon"] = icon
	# Torches along the back walls.
	var flame_tex: Texture2D = load("res://assets/sprites/fx/flame.png")
	var sconce_tex: Texture2D = load("res://assets/sprites/props/sconce.png")
	var glow_tex := Fx.light_texture()
	for c: Vector2i in grid:
		if grid[c] != WALL:
			continue
		var on_ne := c.y == 0 and c.x > 1 and c.x < W - 2
		var on_nw := c.x == 0 and c.y > 1 and c.y < H - 2
		if not (on_ne or on_nw):
			continue
		var idx := c.x if on_ne else c.y
		if idx % 4 != 2:
			continue
		var near_door := false
		for d: Dictionary in doors:
			if (Vector2(c) - Vector2(d["cell"])).length() < 1.5:
				near_door = true
		if near_door:
			continue
		var base := Iso.to_world(Vector2(c)) + Vector2(-8 if on_ne else 8, -22)
		var holder := Node2D.new()
		holder.position = Iso.to_world(Vector2(c))
		holder.z_index = 0
		add_child(holder)
		var sc := Sprite2D.new()
		sc.texture = sconce_tex
		sc.position = base - holder.position
		holder.add_child(sc)
		var fl := Sprite2D.new()
		fl.texture = flame_tex
		fl.hframes = 4
		fl.position = sc.position + Vector2(0, -9)
		fl.material = Fx.unshaded_material()
		holder.add_child(fl)
		var lt := PointLight2D.new()
		lt.texture = glow_tex
		lt.color = Color(1.0, 0.62, 0.3)
		lt.energy = 0.9
		lt.texture_scale = 1.05
		lt.position = fl.position + Vector2(0, 14)
		holder.add_child(lt)
		_torches.append([fl, lt, rng.randf() * 10.0])


func _build_collision() -> void:
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	for c: Vector2i in grid:
		var t: int = grid[c]
		if t == WALL or t == BLOCK:
			var cp := CollisionPolygon2D.new()
			cp.polygon = Iso.diamond(c, 1.0 if t == WALL else 0.62)
			_body.add_child(cp)
	# Each door gets its own body so it can be opened.
	for d: Dictionary in doors:
		var b := StaticBody2D.new()
		b.collision_layer = 1
		var cp := CollisionPolygon2D.new()
		cp.polygon = Iso.diamond(d["cell"])
		b.add_child(cp)
		add_child(b)
		d["body"] = b
		# Seal the void behind the door so nobody can wander out.
		var back: Vector2i = d["cell"] - (d["inner"] - d["cell"])
		var cp2 := CollisionPolygon2D.new()
		cp2.polygon = Iso.diamond(back)
		_body.add_child(cp2)


func _build_props() -> void:
	var p := "res://assets/sprites/props/"
	for c: Vector2i in grid:
		if grid[c] != BLOCK:
			continue
		var choice := rng.randf()
		var tex: Texture2D
		if type == "boss" or choice < 0.55:
			tex = load(p + "pillar_%s.png" % biome)
		elif choice < 0.75:
			tex = load(p + "statue.png")
		elif choice < 0.9:
			tex = load(p + "tombstone.png")
		else:
			tex = load(p + "brazier.png")
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() + 5)
		s.position = Iso.to_world(Vector2(c))
		add_child(s)
		if tex.resource_path.ends_with("brazier.png"):
			_add_fire(s, Vector2(0, -12), 0.9)
	# Non-blocking candles for atmosphere.
	if type != "boss":
		for _i in rng.randi_range(0, 3):
			var c := Vector2i(rng.randi_range(1, W - 2), 1 if rng.randf() < 0.5 else rng.randi_range(1, H - 2))
			if grid.get(c) == FLOOR and Vector2(c - spawn_cell).length() > 3:
				var s := Sprite2D.new()
				s.texture = load(p + "candles.png")
				s.offset = Vector2(0, -5)
				s.position = Iso.to_world(Vector2(c)) + Vector2(rng.randf_range(-6, 6), 0)
				add_child(s)
				var lt := PointLight2D.new()
				lt.texture = Fx.light_texture()
				lt.color = Color(1.0, 0.75, 0.45)
				lt.energy = 0.55
				lt.texture_scale = 0.45
				lt.position = Vector2(0, -6)
				s.add_child(lt)
				_torches.append([null, lt, rng.randf() * 10.0])


func _add_fire(parent: Node2D, offset: Vector2, energy: float) -> void:
	var fl := Sprite2D.new()
	fl.texture = load("res://assets/sprites/fx/flame.png")
	fl.hframes = 4
	fl.position = offset
	fl.material = Fx.unshaded_material()
	parent.add_child(fl)
	var lt := PointLight2D.new()
	lt.texture = Fx.light_texture()
	lt.color = Color(1.0, 0.6, 0.3)
	lt.energy = energy
	lt.texture_scale = 1.0
	lt.position = offset
	parent.add_child(lt)
	_torches.append([fl, lt, rng.randf() * 10.0])


func _process(delta: float) -> void:
	_t += delta
	for t: Array in _torches:
		var ph: float = t[2]
		if t[0] != null:
			t[0].frame = int((_t + ph) * 10.0) % 4
		t[1].energy = (0.85 + 0.12 * sin(_t * 9.0 + ph) + 0.06 * sin(_t * 23.0 + ph * 2.0)) * (1.0 if t[0] != null else 0.6)


# ---------------------------------------------------------------------------
# Queries used by gameplay
# ---------------------------------------------------------------------------

func is_floor(c: Vector2i) -> bool:
	return grid.get(c, WALL) == FLOOR


## True if a projectile at world position p should be stopped.
func blocks_projectile(p: Vector2) -> bool:
	var cf := Iso.to_cellf(p)
	var c := Vector2i(roundi(cf.x), roundi(cf.y))
	var t: int = grid.get(c, WALL)
	if t == FLOOR:
		return false
	if t == BLOCK:
		return absf(cf.x - c.x) + absf(cf.y - c.y) < 0.36
	return true


func line_of_sight(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	var steps := int(dist / 6.0)
	for i in range(1, steps):
		if blocks_projectile(a.lerp(b, float(i) / steps)):
			return false
	return true


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := Iso.to_cell(from)
	var b := Iso.to_cell(to)
	if not astar.is_in_boundsv(a) or not astar.is_in_boundsv(b) or astar.is_point_solid(a) or astar.is_point_solid(b):
		return PackedVector2Array()
	var cells := astar.get_id_path(a, b)
	var out := PackedVector2Array()
	for c in cells:
		out.append(Iso.to_world(Vector2(c)))
	return out


func center() -> Vector2:
	return Iso.to_world(Vector2((W - 1) * 0.5, (H - 1) * 0.5))


func spawn_position() -> Vector2:
	return Iso.to_world(Vector2(spawn_cell))


## A random open floor position, at least `min_dist` from `avoid`.
func random_floor_pos(avoid: Vector2, min_dist: float, margin := 2) -> Vector2:
	for _i in 60:
		var c := Vector2i(rng.randi_range(margin, W - 1 - margin), rng.randi_range(margin, H - 1 - margin))
		if not is_floor(c):
			continue
		var p := Iso.to_world(Vector2(c))
		if p.distance_to(avoid) >= min_dist:
			return p + Vector2(rng.randf_range(-4, 4), rng.randf_range(-2, 2))
	return center()


func clamp_to_floor(p: Vector2) -> Vector2:
	var c := Iso.to_cell(p)
	if is_floor(c):
		return p
	var best := center()
	var bd := INF
	for cell: Vector2i in grid:
		if grid[cell] == FLOOR:
			var w := Iso.to_world(Vector2(cell))
			var d := w.distance_squared_to(p)
			if d < bd:
				bd = d
				best = w
	return best


func bounds() -> Rect2:
	var top := Iso.to_world(Vector2(0, 0))
	var right := Iso.to_world(Vector2(W - 1, 0))
	var left := Iso.to_world(Vector2(0, H - 1))
	var bottom := Iso.to_world(Vector2(W - 1, H - 1))
	return Rect2(left.x - 16, top.y - 8 - WALL_H, right.x - left.x + 32, bottom.y - top.y + 16 + WALL_H)


func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	for d: Dictionary in doors:
		d["open"] = true
		d["body"].queue_free()
		var tw := create_tween().set_parallel(true)
		tw.tween_property(d["bars"], "position:y", -26.0, 0.9).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(d["bars"], "modulate:a", 0.0, 0.9)
		d["icon"].lit = true
	if not doors.is_empty():
		Audio.play("door_open", -4.0)


## Returns the door the player is walking into, or null.
func door_at(p: Vector2) -> Variant:
	if not unlocked:
		return null
	for d: Dictionary in doors:
		var dp := Iso.to_world(Vector2(d["cell"]))
		if p.distance_to(dp) < 9.0:
			return d
	return null


## Floating room-type icon above a door.
class DoorIcon extends Node2D:
	const ORDER := ["combat", "elite", "treasure", "shop", "shrine", "rest", "boss", "start"]
	var tex: Texture2D
	var idx := 0
	var lit := false
	var t := 0.0

	func setup(t_: Texture2D, room_type: String) -> void:
		tex = t_
		idx = maxi(0, ORDER.find(room_type))
		material = Fx.unshaded_material()

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var y := sin(t * 2.5) * 1.5
		var a := 1.0 if lit else 0.35
		draw_texture_rect(Fx.glow_texture(), Rect2(-12, -12 + y, 24, 24), false, Color(1, 0.6, 0.3, 0.35 * a))
		draw_texture_rect_region(tex, Rect2(Vector2(-7, -7 + y), Vector2(14, 14)), Rect2(idx * 14, 0, 14, 14), Color(1, 1, 1, a))
