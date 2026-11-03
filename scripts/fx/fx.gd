class_name Fx
extends Node2D
## Lightweight effects layer: particles, floating damage numbers, shock rings
## and lightning. Everything is drawn unshaded so it glows in the dark.
## Also holds a few shared, cached resources (light texture, materials, font).

static var _light_tex: Texture2D
static var _glow_tex: Texture2D
static var _unshaded: CanvasItemMaterial
static var _additive: CanvasItemMaterial
static var _font: Font
static var _bold: Font
static var _font_title: Font

var particles: Array = [] # [pos, z, vel, vz, life, max_life, color, size, gravity, ground_fade]
var numbers: Array = [] # [pos, text, color, life, size]
const NUMBER_LIFE := 0.95
var rings: Array = [] # [pos, r0, r1, life, max_life, color, width]
var bolts: Array = [] # [points, life, color]
var glows: Array = [] # [pos, radius, color, life, max_life]
var _glow_layer: GlowLayer


class GlowLayer extends Node2D:
	var fx: Fx

	func _draw() -> void:
		var tex := Fx.glow_texture()
		for g: Array in fx.glows:
			var t: float = g[3] / g[4]
			var r: float = g[1]
			var c: Color = g[2]
			c.a *= t
			draw_texture_rect(tex, Rect2(g[0] - Vector2(r, r * 0.6), Vector2(r * 2, r * 1.2)), false, c)


static func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.45))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 256
		t.height = 256
		_light_tex = t
	return _light_tex


static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		_glow_tex = load("res://assets/sprites/fx/glow.png")
	return _glow_tex


static func unshaded_material() -> CanvasItemMaterial:
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unshaded


static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/PixelifySans.ttf")
	return _font


## Heavy weight of the pixel font, used for numbers so they read at a glance.
static func bold_font() -> Font:
	if _bold == null:
		var v := FontVariation.new()
		v.base_font = font()
		var ts := TextServerManager.get_primary_interface()
		v.variation_opentype = {ts.name_to_tag("wght"): 700}
		_bold = v
	return _bold


static func title_font() -> Font:
	if _font_title == null:
		_font_title = load("res://assets/fonts/JacquardaBastarda9-Regular.ttf")
	return _font_title


func _ready() -> void:
	material = unshaded_material()
	z_index = 20
	z_as_relative = false
	_glow_layer = GlowLayer.new()
	_glow_layer.fx = self
	_glow_layer.material = additive_material()
	_glow_layer.z_index = 19
	_glow_layer.z_as_relative = false
	add_child(_glow_layer)


func clear() -> void:
	particles.clear()
	numbers.clear()
	rings.clear()
	bolts.clear()
	glows.clear()


# ---------------------------------------------------------------------------
# Spawning helpers
# ---------------------------------------------------------------------------

func burst(pos: Vector2, color: Color, count: int, speed := 60.0, height := 8.0, size := 2.0, gravity := 220.0, life := 0.7) -> void:
	for i in count:
		var a := randf() * TAU
		var sp := randf_range(0.3, 1.0) * speed
		particles.append([pos + Vector2(randf_range(-2, 2), randf_range(-1, 1)), height + randf_range(-2, 4),
			Vector2(cos(a), sin(a) * 0.5) * sp, randf_range(20, 90), 0.0, life * randf_range(0.6, 1.2),
			color.lightened(randf_range(-0.15, 0.15)), size * randf_range(0.6, 1.3), gravity, true])
	if particles.size() > 900:
		particles = particles.slice(particles.size() - 900)


func gore(pos: Vector2, kind: String, count := 10) -> void:
	match kind:
		"bone":
			burst(pos, Color("d8cfb0"), count, 70.0, 10.0, 2.0)
			burst(pos, Color("8a7e62"), count / 2, 50.0, 8.0, 1.5)
		"rot":
			burst(pos, Color("7a9a3a"), count, 70.0, 10.0, 2.0)
			burst(pos, Color("4a1a1a"), count / 2, 50.0, 8.0, 2.0)
		"ghost":
			burst(pos, Color("a8d8ff"), count, 50.0, 12.0, 1.5, -30.0, 0.9)
		_:
			burst(pos, Color("8a1414"), count, 70.0, 10.0, 2.0)
			burst(pos, Color("4a0808"), count / 2, 50.0, 8.0, 2.0)


func sparks(pos: Vector2, color: Color, count := 6, speed := 90.0) -> void:
	for i in count:
		var a := randf() * TAU
		particles.append([pos, 10.0, Vector2(cos(a), sin(a)) * randf_range(0.4, 1.0) * speed, randf_range(-10, 30),
			0.0, randf_range(0.15, 0.35), color, randf_range(1.0, 2.0), 0.0, false])


func embers(pos: Vector2, color: Color, count := 6) -> void:
	for i in count:
		particles.append([pos + Vector2(randf_range(-8, 8), randf_range(-4, 4)), randf_range(0, 10),
			Vector2(randf_range(-10, 10), randf_range(-6, 6)), randf_range(25, 60), 0.0, randf_range(0.6, 1.4),
			color, randf_range(1.0, 2.0), -10.0, false])


func number(pos: Vector2, value: float, color: Color, big := false) -> void:
	var txt := str(int(round(value)))
	if value < 1.0 and value > 0.0:
		txt = "1"
	numbers.append([pos + Vector2(randf_range(-7, 7), -20 + randf_range(-3, 3)), txt, color, 0.0, 14 if big else 11])
	if numbers.size() > 80:
		numbers.remove_at(0)


func text(pos: Vector2, txt: String, color: Color, size := 8) -> void:
	numbers.append([pos + Vector2(0, -24), txt, color, 0.0, size + 2])


func ring(pos: Vector2, r0: float, r1: float, color: Color, life := 0.35, width := 2.0) -> void:
	rings.append([pos, r0, r1, 0.0, life, color, width])


func glow(pos: Vector2, radius: float, color: Color, life := 0.3) -> void:
	glows.append([pos, radius, color, life, life])


func lightning(a: Vector2, b: Vector2, color := Color("bfe8ff")) -> void:
	var pts := PackedVector2Array()
	var n := maxi(3, int(a.distance_to(b) / 10.0))
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t)
		if i > 0 and i < n:
			p += Vector2(randf_range(-5, 5), randf_range(-5, 5))
		pts.append(p + Vector2(0, -10))
	bolts.append([pts, 0.22, color])
	glow(b, 20.0, Color(0.6, 0.8, 1.0, 0.6), 0.25)


# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var i := 0
	while i < particles.size():
		var p: Array = particles[i]
		p[4] += delta
		if p[4] >= p[5]:
			particles.remove_at(i)
			continue
		p[0] += p[2] * delta
		p[3] -= p[8] * delta
		p[1] += p[3] * delta
		if p[1] <= 0.0 and p[8] > 0.0:
			p[1] = 0.0
			p[3] = 0.0
			p[2] *= 0.6
		i += 1
	i = 0
	while i < numbers.size():
		numbers[i][3] += delta
		if numbers[i][3] > NUMBER_LIFE:
			numbers.remove_at(i)
		else:
			i += 1
	i = 0
	while i < rings.size():
		rings[i][3] += delta
		if rings[i][3] > rings[i][4]:
			rings.remove_at(i)
		else:
			i += 1
	i = 0
	while i < bolts.size():
		bolts[i][1] -= delta
		if bolts[i][1] <= 0:
			bolts.remove_at(i)
		else:
			i += 1
	i = 0
	while i < glows.size():
		glows[i][3] -= delta
		if glows[i][3] <= 0:
			glows.remove_at(i)
		else:
			i += 1
	queue_redraw()
	_glow_layer.queue_redraw()


func _draw() -> void:
	for p: Array in particles:
		var t: float = p[4] / p[5]
		var c: Color = p[6]
		c.a = 1.0 - t * t if p[9] else 1.0 - t
		var s: float = p[7]
		draw_rect(Rect2(p[0] - Vector2(s * 0.5, p[1] + s * 0.5), Vector2(s, s)), c)
	for r: Array in rings:
		var t: float = r[3] / r[4]
		var rad: float = lerpf(r[1], r[2], ease(t, 0.4))
		var c: Color = r[5]
		c.a *= 1.0 - t
		draw_set_transform(r[0], 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 40, c, r[6] * 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b: Array in bolts:
		var c: Color = b[2]
		c.a = clampf(b[1] / 0.22, 0.0, 1.0)
		draw_polyline(b[0], Color(1, 1, 1, c.a), 1.0)
		draw_polyline(b[0], Color(c.r, c.g, c.b, c.a * 0.5), 3.0)
	var f := bold_font()
	for n: Array in numbers:
		var t: float = n[3] / NUMBER_LIFE
		# Rise quickly, then hang in place so the value can be read.
		var pos: Vector2 = n[0] + Vector2(0, -16.0 * ease(minf(t * 2.0, 1.0), 0.4))
		var c: Color = n[2]
		var a := 1.0 - clampf((t - 0.65) / 0.35, 0.0, 1.0)
		var sz: int = n[4]
		if t < 0.1:
			sz += 3
		elif t < 0.18:
			sz += 1
		var w := f.get_string_size(n[1], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var p := (pos - Vector2(w * 0.5, 0)).round()
		var dark := Color(0.04, 0.01, 0.02, a)
		draw_string_outline(f, p + Vector2(1, 1), n[1], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, a * 0.6))
		draw_string_outline(f, p, n[1], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, dark)
		draw_string(f, p, n[1], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(c.r, c.g, c.b, a))
