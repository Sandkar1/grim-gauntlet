extends SceneTree
## Procedural pixel-art generator for Grim Gauntlet.
##
## Every sprite under assets/sprites/ is drawn by this script, so you own all
## of it. Tweak a colour or a shape here and re-run:
##
##   godot --headless --path . --script res://tools/gen_art.gd
##
## Drawing model: each body part is a shape (ellipse / polygon / rect) filled
## with a 3-tone palette [light, base, dark]. Shapes are shaded so light comes
## from the top-left, then a dark 1px outline is added around the sprite.

const OUT := Color("110a0d")
const OUT_DIR := "res://assets/sprites/"

var img: Image
var W := 0
var H := 0
var rng := RandomNumberGenerator.new()
var PAL := {}

const BIOMES := {
	"crypt": {
		"floor": ["7a7884", "5c5a66", "403e4a"],
		"wall": ["8a8490", "67616f", "433e4a"],
		"top": ["9a94a2", "77717f", "524c5a"],
		"accent": "4f6a3c",
	},
	"catacomb": {
		"floor": ["857561", "66594a", "463d33"],
		"wall": ["8e7e68", "6d5f4e", "4a3f34"],
		"top": ["a08e76", "7e6e5a", "574a3c"],
		"accent": "d8cfb0",
	},
	"inferno": {
		"floor": ["5a4446", "3f2f31", "281c1e"],
		"wall": ["7e4038", "5c2c27", "3a1a17"],
		"top": ["8a5048", "683a33", "452420"],
		"accent": "ff8a2a",
	},
}


func _init() -> void:
	rng.seed = 1337
	_build_palettes()
	for sub in ["chars", "tiles", "props", "items", "fx", "ui"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + sub))
	gen_characters()
	gen_weapons_and_items()
	gen_projectiles()
	gen_tiles()
	gen_props()
	gen_ui()
	print("Art generated.")
	quit()


func _p(a: String, b: String, c: String) -> Array:
	return [Color(a), Color(b), Color(c)]


func _build_palettes() -> void:
	PAL = {
		"bone": _p("ece3c8", "c7ba96", "877b5c"),
		"cloth": _p("5c5664", "3f3a48", "28242e"),
		"hood": _p("5f6a52", "444c3b", "2a3024"),
		"leather": _p("8c6642", "66482a", "42301c"),
		"boot": _p("4a3828", "33261a", "201810"),
		"metal": _p("c8ced6", "8c929c", "54585f"),
		"rust": _p("a0705a", "7a4e3a", "4e3024"),
		"gold": _p("f6d27a", "c9982e", "7f5b17"),
		"crimson": _p("b8342f", "861d1f", "4e0f12"),
		"skin": _p("e2b493", "b98868", "7f5a40"),
		"pale": _p("bfb8a4", "918b7b", "5d5850"),
		"purple": _p("7c5598", "573a70", "352347"),
		"rot": _p("93a24e", "6a783a", "3f4a22"),
		"flesh": _p("d08876", "a35a4f", "6b3433"),
		"ghost": _p("dcf0ff", "92c2e8", "4f7eaa"),
		"black": _p("3c353a", "251f24", "151014"),
		"fire": _p("fff3b0", "ffa53a", "d04a14"),
		"wood": _p("94703e", "6c4c26", "46301a"),
		"white": _p("fffaf0", "e3dccd", "aaa294"),
		"hell": _p("d4523f", "952e25", "5a1913"),
		"stone": _p("9a96a0", "75717d", "4d4a55"),
		"glow_g": _p("e0ffd0", "86f070", "2f9a3a"),
		"glow_p": _p("f0d0ff", "b070f0", "6a2fa8"),
	}


# ---------------------------------------------------------------------------
# Drawing primitives
# ---------------------------------------------------------------------------

func V(x: float, y: float) -> Vector2:
	return Vector2(x, y)


func canvas(w: int, h: int) -> void:
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	W = w
	H = h


func setp(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		img.set_pixel(x, y, c)


func getp(x: int, y: int) -> Color:
	if x >= 0 and y >= 0 and x < W and y < H:
		return img.get_pixel(x, y)
	return Color(0, 0, 0, 0)


func dk(p: Array, amt := 0.25) -> Array:
	return [p[0].darkened(amt), p[1].darkened(amt), p[2].darkened(amt)]


func lt(p: Array, amt := 0.2) -> Array:
	return [p[0].lightened(amt), p[1].lightened(amt), p[2].lightened(amt)]


## Fill a pixel mask, light on top/left edges and dark on bottom/right edges.
func shade_mask(mask: Dictionary, p: Array) -> void:
	for k: Vector2i in mask:
		var c: Color = p[1]
		var rb: bool = not mask.has(k + Vector2i(1, 0)) or not mask.has(k + Vector2i(0, 1))
		var lft: bool = not mask.has(k + Vector2i(-1, 0)) or not mask.has(k + Vector2i(0, -1))
		if rb:
			c = p[2]
		elif lft:
			c = p[0]
		setp(k.x, k.y, c)


func rect(x: float, y: float, w: float, h: float, p: Array) -> void:
	var m := {}
	for yy in range(int(round(y)), int(round(y + h))):
		for xx in range(int(round(x)), int(round(x + w))):
			m[Vector2i(xx, yy)] = true
	shade_mask(m, p)


func flat(x: float, y: float, w: float, h: float, c: Color) -> void:
	for yy in range(int(round(y)), int(round(y + h))):
		for xx in range(int(round(x)), int(round(x + w))):
			setp(xx, yy, c)


func _poly_mask(pts: Array) -> Dictionary:
	var pk := PackedVector2Array(pts)
	var r := Rect2(pk[0], Vector2.ZERO)
	for q in pk:
		r = r.expand(q)
	var m := {}
	for yy in range(int(floor(r.position.y)) - 1, int(ceil(r.end.y)) + 1):
		for xx in range(int(floor(r.position.x)) - 1, int(ceil(r.end.x)) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(xx + 0.5, yy + 0.5), pk):
				m[Vector2i(xx, yy)] = true
	return m


func poly(pts: Array, p: Array) -> void:
	shade_mask(_poly_mask(pts), p)


func poly_flat(pts: Array, c: Color) -> void:
	for k: Vector2i in _poly_mask(pts):
		setp(k.x, k.y, c)


## Sphere-shaded ellipse.
func ell(cx: float, cy: float, rx: float, ry: float, p: Array) -> void:
	for yy in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 1):
		for xx in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 1):
			var dx := (xx + 0.5 - cx) / rx
			var dy := (yy + 0.5 - cy) / ry
			var d := dx * dx + dy * dy
			if d <= 1.0:
				var t := -dx * 0.6 - dy * 0.8
				var c: Color = p[1]
				if t > 0.42:
					c = p[0]
				elif t < -0.3:
					c = p[2]
				setp(xx, yy, c)


func ell_flat(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for yy in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 1):
		for xx in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 1):
			var dx := (xx + 0.5 - cx) / rx
			var dy := (yy + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				setp(xx, yy, c)


func ring(cx: float, cy: float, rx: float, ry: float, inner: float, c: Color) -> void:
	for yy in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 1):
		for xx in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 1):
			var dx := (xx + 0.5 - cx) / rx
			var dy := (yy + 0.5 - cy) / ry
			var d := dx * dx + dy * dy
			if d <= 1.0 and d >= inner:
				setp(xx, yy, c)


func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		setp(x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


func thick_line(x0: float, y0: float, x1: float, y1: float, wd: float, p: Array) -> void:
	var a := V(x0, y0)
	var b := V(x1, y1)
	var n := (b - a).normalized().orthogonal() * (wd * 0.5)
	poly([a + n, b + n, b - n, a - n], p)


func outline(col := OUT) -> void:
	var src := img.duplicate() as Image
	for y in H:
		for x in W:
			if src.get_pixel(x, y).a < 0.1:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx >= 0 and ny >= 0 and nx < W and ny < H and src.get_pixel(nx, ny).a > 0.1:
						img.set_pixel(x, y, col)
						break


func clear_px(x: int, y: int) -> void:
	setp(x, y, Color(0, 0, 0, 0))


func save(path: String) -> void:
	img.save_png(OUT_DIR + path + ".png")


## Builds a horizontal strip of `frames` frames by calling fn(frame_index).
func sheet(path: String, frames: int, fw: int, fh: int, fn: Callable, do_outline := true) -> void:
	var out := Image.create(fw * frames, fh, false, Image.FORMAT_RGBA8)
	for i in frames:
		canvas(fw, fh)
		fn.call(i)
		if do_outline:
			outline()
		out.blit_rect(img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
	out.save_png(OUT_DIR + path + ".png")


# ---------------------------------------------------------------------------
# Characters. Every creature sheet has 7 frames:
#   0-1 idle (breathing), 2-5 walk cycle, 6 attack / cast pose.
# Sprites face right; the game flips them to face left.
# ---------------------------------------------------------------------------

func motion(f: int) -> Dictionary:
	var m := {"bob": 0, "a": 0, "b": 0, "la": 0, "lb": 0, "arm": 0, "atk": false}
	match f:
		1:
			m["bob"] = 1
		2:
			m["a"] = -2
			m["b"] = 2
			m["arm"] = 1
		3:
			m["bob"] = -1
			m["la"] = 1
		4:
			m["a"] = 2
			m["b"] = -2
			m["arm"] = -1
		5:
			m["bob"] = -1
			m["lb"] = 1
		6:
			m["atk"] = true
	return m


func _leg(hx: float, top: float, fx: float, bottom: float, wd: float, pl: Array, pb: Array) -> void:
	poly([V(hx, top), V(hx + wd, top), V(fx + wd, bottom - 2), V(fx, bottom - 2)], pl)
	rect(fx, bottom - 3, wd + 1, 3, pb)


func legs_pants(m: Dictionary, bx: float, fx: float, hip: float, foot: float, pl: Array, pb: Array, wd := 2.0) -> void:
	_leg(bx, hip, bx + m["a"], foot - m["la"], wd, dk(pl, 0.25), dk(pb, 0.2))
	_leg(fx, hip, fx + m["b"], foot - m["lb"], wd, pl, pb)


func _bone_leg(hx: int, top: int, fx: int, bottom: int, p: Array) -> void:
	var kx := int((hx + fx) / 2.0) + 1
	var ky := int((top + bottom) / 2.0)
	line(hx, top, kx, ky, p[1])
	line(kx, ky, fx, bottom - 1, p[1])
	line(hx + 1, top, kx + 1, ky, p[2])
	setp(kx, ky, p[0])
	flat(fx, bottom - 1, 3, 1, p[1])


func robe(m: Dictionary, x0: float, x1: float, top: float, bx0: float, bx1: float, foot: float, p: Array, tatter := true) -> void:
	var sway: float = -float(m["a"]) * 0.5
	poly([V(x0, top), V(x1, top), V(bx1 + sway, foot), V(bx0 + sway, foot)], p)
	if tatter:
		for x in range(int(bx0 + sway), int(bx1 + sway) + 1):
			if (x * 5) % 3 == 0:
				clear_px(x, int(foot) - 1)


func draw_exile(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"]
	var arm: int = m["arm"]
	var hood: Array = PAL["hood"]
	var sway: float = -float(m["a"]) * 0.5
	poly([V(5, 11 + b), V(11, 11 + b), V(10, 23), V(3 + sway, 24)], dk(hood, 0.15))
	legs_pants(m, 7, 10, 19 + b, 27, PAL["cloth"], PAL["boot"])
	rect(5, 12 + b - arm, 2, 6, dk(PAL["leather"], 0.3))
	poly([V(6, 11 + b), V(13, 11 + b), V(12, 20 + b), V(7, 20 + b)], PAL["leather"])
	line(7, 12 + b, 11, 17 + b, PAL["boot"][1])
	flat(7, 18 + b, 6, 1, PAL["boot"][2])
	setp(10, 18 + b, PAL["gold"][0])
	ell(9.5, 12 + b, 4.6, 2.2, hood)
	rect(12, 13 + b + arm, 2, 5, PAL["leather"])
	flat(12, 18 + b + arm, 2, 1, PAL["skin"][1])
	poly([V(6, 5 + b), V(8, 1 + b), V(10, 2 + b)], dk(hood, 0.1))
	ell(9.5, 6.5 + b, 4.2, 4.5, hood)
	ell_flat(11.4, 7.4 + b, 2.2, 2.6, PAL["black"][2])
	setp(12, 8 + b, PAL["skin"][1])
	setp(12, 9 + b, PAL["skin"][2])
	setp(11, 7 + b, Color("e6dcc8"))
	setp(13, 7 + b, Color("e6dcc8"))


func draw_heretic(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"]
	var arm: int = m["arm"]
	var cr: Array = PAL["crimson"]
	rect(6 + m["a"], 25, 3, 2, PAL["boot"])
	rect(10 + m["b"], 25, 3, 2, PAL["boot"])
	rect(4, 12 + b - arm, 2, 6, dk(cr, 0.35))
	robe(m, 5, 14, 11 + b, 4, 15, 26, cr)
	flat(11, 13 + b, 1, 12, PAL["black"][2])
	flat(5, 17 + b, 10, 1, PAL["black"][1])
	setp(8, 18 + b, PAL["bone"][1])
	setp(8, 19 + b, PAL["bone"][2])
	ell(9.5, 11.5 + b, 4.6, 1.8, dk(cr, 0.3))
	for i in 5:
		setp(7 + i, 12 + b + (1 if i % 2 == 0 else 0), PAL["bone"][0])
	if m["atk"]:
		rect(12, 6 + b, 3, 6, cr)
		flat(13, 5 + b, 2, 1, PAL["skin"][1])
		ell(13.5, 3 + b, 2.2, 2.2, PAL["fire"])
	else:
		rect(12, 12 + b + arm, 3, 6, cr)
		flat(13, 18 + b + arm, 2, 1, PAL["skin"][1])
	flat(8, 10 + b, 3, 1, PAL["skin"][2])
	ell(9.5, 6.5 + b, 3.6, 4.0, PAL["skin"])
	setp(11, 6 + b, PAL["black"][2])
	setp(12, 6 + b, PAL["fire"][0])
	flat(10, 5 + b, 3, 1, PAL["skin"][2])
	setp(12, 9 + b, PAL["crimson"][2])
	line(7, 3 + b, 8, 8 + b, PAL["crimson"][1])
	setp(6, 6 + b, PAL["skin"][2])


func draw_penitent(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"]
	var arm: int = m["arm"]
	var mt: Array = PAL["metal"]
	legs_pants(m, 6, 10, 19 + b, 27, dk(mt, 0.15), dk(mt, 0.45), 3)
	rect(4, 12 + b - arm, 3, 6, dk(mt, 0.35))
	poly([V(5, 11 + b), V(14, 11 + b), V(13, 20 + b), V(6, 20 + b)], mt)
	poly([V(7, 12 + b), V(12, 12 + b), V(12, 23 + b), V(7, 23 + b)], PAL["white"])
	flat(9, 13 + b, 1, 7, PAL["crimson"][1])
	flat(8, 15 + b, 3, 1, PAL["crimson"][1])
	flat(6, 19 + b, 8, 1, PAL["leather"][2])
	ell(5.5, 12 + b, 2.6, 2.2, mt)
	ell(13.5, 12 + b, 2.6, 2.2, mt)
	rect(13, 13 + b + arm, 3, 5, mt)
	flat(13, 18 + b + arm, 3, 1, dk(mt, 0.4)[1])
	ell(9.5, 6.0 + b, 3.9, 4.4, mt)
	flat(6, 8 + b, 8, 2, mt[1])
	flat(10, 6 + b, 4, 1, PAL["black"][2])
	flat(11, 8 + b, 1, 2, PAL["black"][1])
	flat(13, 8 + b, 1, 1, PAL["black"][1])
	line(8, 2 + b, 6, -1 + b, PAL["crimson"][1])
	line(9, 2 + b, 7, 0 + b, PAL["crimson"][0])


func draw_merchant(f: int) -> void:
	var m := motion(f % 2)
	var b: int = m["bob"]
	rect(2, 8 + b, 7, 12, PAL["leather"])
	line(2, 8 + b, 2, 21, PAL["wood"][1])
	line(8, 8 + b, 8, 21, PAL["wood"][1])
	ell(5.5, 7.5 + b, 4, 2, PAL["hood"])
	rect(8, 25, 3, 2, PAL["boot"])
	rect(12, 25, 3, 2, PAL["boot"])
	robe(m, 6, 14, 11 + b, 5, 16, 26, PAL["black"])
	flat(6, 18 + b, 9, 1, PAL["leather"][2])
	ell(12.0, 11 + b, 4.2, 4.0, PAL["black"])
	ell_flat(13.6, 11.6 + b, 2.2, 2.4, Color("0a0608"))
	setp(14, 11 + b, PAL["gold"][0])
	setp(15, 12 + b, PAL["pale"][0])
	setp(16, 13 + b, PAL["pale"][1])
	rect(14, 14 + b, 2, 5, PAL["black"])
	line(16, 18 + b, 16, 19 + b, PAL["metal"][2])
	rect(15, 20 + b, 3, 4, PAL["gold"])
	flat(16, 21 + b, 1, 2, PAL["fire"][0])


func skeleton_body(m: Dictionary, cx: int, bonep: Array, eye: Color, weapon: String) -> void:
	var b: int = m["bob"]
	var arm: int = m["arm"]
	var hip := 18 + b
	_bone_leg(cx - 1, hip, cx - 2 + m["a"], 27 - m["la"], dk(bonep, 0.25))
	line(cx - 3, 12 + b, cx - 4, 17 + b - arm, bonep[2])
	if weapon == "bow":
		if m["atk"]:
			line(cx + 3, 13 + b, cx + 6, 13 + b, bonep[1])
		else:
			line(cx + 3, 12 + b, cx + 5, 16 + b, bonep[1])
	_bone_leg(cx + 1, hip, cx + 1 + m["b"], 27 - m["lb"], bonep)
	ell(cx + 0.5, hip + 0.5, 2.6, 1.6, bonep)
	flat(cx, 12 + b, 1, 6, bonep[2])
	ell(cx + 0.5, 13 + b, 3.7, 2.9, bonep)
	flat(cx - 2, 12 + b, 5, 1, PAL["black"][2])
	flat(cx - 2, 14 + b, 5, 1, PAL["black"][2])
	flat(cx, 11 + b, 1, 5, bonep[1])
	if weapon == "sword":
		if m["atk"]:
			line(cx + 3, 11 + b, cx + 5, 7 + b, bonep[1])
			thick_line(cx + 5, 7 + b, cx + 10, 0 + b, 2, PAL["rust"])
			flat(cx + 4, 6 + b, 3, 1, PAL["metal"][2])
		else:
			line(cx + 3, 12 + b, cx + 4, 16 + b + arm, bonep[1])
			thick_line(cx + 5, 16 + b + arm, cx + 10, 8 + b + arm, 2, PAL["rust"])
			flat(cx + 3, 16 + b + arm, 3, 1, PAL["metal"][2])
	elif weapon == "bow":
		var bx := cx + 6
		if m["atk"]:
			bx = cx + 7
		for yy in range(6, 21):
			var off := int(round(2.0 * sin(PI * float(yy - 6) / 14.0)))
			setp(bx + off, yy + b, PAL["wood"][1])
		line(bx, 6 + b, bx - (2 if m["atk"] else 0), 13 + b, PAL["white"][2])
		line(bx - (2 if m["atk"] else 0), 13 + b, bx, 20 + b, PAL["white"][2])
		if m["atk"]:
			line(cx + 3, 13 + b, cx + 11, 13 + b, PAL["wood"][0])
	ell(cx + 0.5, 6.5 + b, 3.5, 3.4, bonep)
	rect(cx - 1, 9 + b, 4, 2, bonep)
	setp(cx, 6 + b, PAL["black"][2])
	setp(cx + 2, 6 + b, eye)
	setp(cx + 2, 7 + b, PAL["black"][2])
	setp(cx + 1, 10 + b, PAL["black"][2])
	setp(cx + 3, 10 + b, PAL["black"][2])


func draw_skeleton(f: int) -> void:
	skeleton_body(motion(f), 8, PAL["bone"], Color("ff5a2a"), "sword")


func draw_skel_archer(f: int) -> void:
	var m := motion(f)
	skeleton_body(m, 8, dk(PAL["bone"], 0.08), Color("ffb03a"), "bow")
	var b: int = m["bob"]
	poly([V(4, 7 + b), V(8, 2 + b), V(12, 4 + b), V(12, 6 + b), V(5, 11 + b)], PAL["cloth"])
	ell(7.0, 10.5 + b, 3.5, 1.6, PAL["cloth"])


func draw_ghoul(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"]
	var arm: int = m["arm"]
	var sk: Array = PAL["pale"]
	poly([V(6, 15 + b), V(9, 15 + b), V(6 + m["a"], 21), V(4 + m["a"], 21)], dk(sk, 0.3))
	rect(3 + m["a"], 20, 4, 3, dk(sk, 0.35))
	line(8, 11 + b, 11 + arm, 20 + b, dk(sk, 0.3)[1])
	line(9, 11 + b, 12 + arm, 20 + b, dk(sk, 0.3)[2])
	poly([V(9, 15 + b), V(12, 15 + b), V(13 + m["b"], 21), V(10 + m["b"], 21)], sk)
	rect(10 + m["b"], 20, 4, 3, dk(sk, 0.1))
	ell(10.0, 12.5 + b, 5.5, 4.2, sk)
	for i in 4:
		setp(7 + i * 2, 9 + b, sk[0])
	flat(7, 15 + b, 6, 2, PAL["leather"][2])
	clear_px(8, 16 + b)
	clear_px(11, 16 + b)
	if m["atk"]:
		thick_line(13, 11 + b, 20, 10 + b, 2, sk)
		for i in 3:
			setp(20 + (i % 2), 9 + b + i, PAL["bone"][0])
	else:
		thick_line(13, 11 + b, 15 - arm, 20 + b, 2, sk)
		for i in 3:
			setp(14 - arm + i, 21 + b, PAL["bone"][0])
	ell(16.0, 11.0 + b, 3.2, 2.8, sk)
	flat(16, 12 + b, 3, 2 if not m["atk"] else 3, PAL["black"][2])
	setp(17, 12 + b, PAL["white"][0])
	setp(18, 13 + b, PAL["white"][0])
	setp(17, 10 + b, Color("ff3020"))


func draw_cultist(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"]
	var arm: int = m["arm"]
	var pu: Array = PAL["purple"]
	rect(6 + m["a"], 25, 3, 2, PAL["boot"])
	rect(10 + m["b"], 25, 3, 2, PAL["boot"])
	rect(4, 12 + b - arm, 2, 6, dk(pu, 0.35))
	robe(m, 5, 14, 11 + b, 4, 15, 26, dk(pu, 0.1))
	flat(10, 12 + b, 2, 14, PAL["crimson"][1])
	flat(5, 18 + b, 10, 1, PAL["crimson"][2])
	if m["atk"]:
		rect(11, 5 + b, 3, 7, pu)
		rect(5, 5 + b, 3, 7, dk(pu, 0.2))
		ell(9.5, 2.5 + b, 3.0, 2.5, PAL["glow_g"])
	else:
		rect(12, 12 + b + arm, 3, 6, pu)
		flat(13, 18 + b + arm, 2, 1, PAL["pale"][1])
	poly([V(6, 6 + b), V(8, 0 + b), V(9, 1 + b), V(13, 6 + b), V(13, 11 + b), V(6, 11 + b)], pu)
	ell(9.5, 7.5 + b, 3.8, 3.6, pu)
	ell_flat(11.0, 8.0 + b, 2.0, 2.4, Color("0a0608"))
	setp(11, 8 + b, PAL["glow_g"][1])
	setp(12, 8 + b, PAL["glow_g"][0])


func draw_wraith(f: int) -> void:
	var m := motion(f)
	var fl := [0, 1, 1, 0, -1, -1, 0][f] as int
	var gp: Array = PAL["ghost"]
	var arm: int = m["arm"]
	poly([V(5, 11 + fl), V(14, 11 + fl), V(17, 25 + fl), V(13, 23 + fl), V(10, 27 + fl), V(7, 23 + fl), V(3, 25 + fl)], gp)
	flat(9, 14 + fl, 2, 9, gp[2])
	if m["atk"]:
		thick_line(12, 13 + fl, 19, 12 + fl, 3, gp)
		for i in 3:
			setp(19, 11 + fl + i, PAL["white"][0])
	else:
		thick_line(12, 13 + fl, 15, 19 + fl + arm, 3, gp)
		for i in 3:
			setp(14 + i, 20 + fl + arm, PAL["white"][1])
	ell(9.5, 7.5 + fl, 4.4, 4.6, gp)
	ell_flat(11.2, 8.4 + fl, 2.4, 2.8, Color("05070c"))
	setp(11, 8 + fl, Color("e8ffff"))
	setp(13, 8 + fl, Color("9ff0ff"))
	for y in H:
		for x in W:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				var fade := clampf(1.0 - float(y - 18 - fl) / 10.0, 0.25, 1.0)
				c.a = 0.88 * fade
				img.set_pixel(x, y, c)


func draw_imp(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"]
	var hp: Array = PAL["hell"]
	var wing := [0, 1, -2, 0, 2, 0, -3][f] as int
	poly([V(6, 9 + b), V(1, 3 + b + wing), V(2, 8 + b + wing), V(0, 11 + b + wing), V(5, 13 + b)], PAL["black"])
	line(5, 14 + b, 2, 17 + b, hp[2])
	line(2, 17 + b, 1, 15 + b, hp[2])
	_leg(6, 14 + b, 5 + m["a"] * 0.5, 19 - m["la"], 2, dk(hp, 0.3), dk(hp, 0.5))
	_leg(9, 14 + b, 9 + m["b"] * 0.5, 19 - m["lb"], 2, hp, dk(hp, 0.3))
	ell(8.0, 11.5 + b, 3.2, 3.6, hp)
	if m["atk"]:
		thick_line(10, 10 + b, 15, 8 + b, 2, hp)
		ell(15.5, 7.5 + b, 1.8, 1.8, PAL["fire"])
	else:
		thick_line(10, 10 + b, 12, 14 + b, 2, hp)
	ell(9.5, 6.0 + b, 3.6, 3.2, hp)
	line(7, 3 + b, 6, 0 + b, PAL["bone"][1])
	line(11, 3 + b, 12, 0 + b, PAL["bone"][1])
	setp(11, 5 + b, PAL["gold"][0])
	setp(12, 5 + b, Color("fff080"))
	flat(10, 8 + b, 3, 1, PAL["black"][2])


func draw_brute(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"]
	var arm: int = m["arm"]
	var fp: Array = PAL["flesh"]
	legs_pants(m, 7, 14, 22 + b, 33, dk(fp, 0.15), PAL["boot"], 4)
	flat(7, 26, 4, 1, PAL["leather"][2])
	thick_line(6, 12 + b, 4, 22 + b - arm, 4, dk(fp, 0.3))
	poly([V(3, 10 + b), V(23, 10 + b), V(20, 23 + b), V(7, 23 + b)], fp)
	ell(13.5, 18.5 + b, 6.0, 4.6, fp)
	line(9, 13 + b, 16, 19 + b, fp[2])
	for i in 4:
		setp(10 + i * 2, 15 + b + i, PAL["black"][1])
	flat(7, 22 + b, 13, 2, PAL["leather"][1])
	if m["atk"]:
		thick_line(20, 12 + b, 24, 4 + b, 4, fp)
		poly([V(21, 4 + b), V(27, -2 + b), V(27, 1 + b), V(24, 6 + b)], PAL["metal"])
	else:
		thick_line(20, 12 + b, 22, 22 + b + arm, 4, fp)
		poly([V(20, 21 + b + arm), V(26, 21 + b + arm), V(26, 30 + b + arm), V(22, 29 + b + arm)], PAL["metal"])
		flat(22, 23 + b + arm, 3, 1, PAL["rust"][1])
	ell(14.0, 7.0 + b, 4.0, 4.2, PAL["leather"])
	setp(15, 6 + b, PAL["black"][2])
	setp(17, 6 + b, Color("ff3a20"))
	line(12, 9 + b, 17, 9 + b, PAL["black"][1])
	line(10, 4 + b, 12, 2 + b, PAL["leather"][2])


func draw_bat(f: int) -> void:
	var wy := [0, 5, 10, 5, 0, 5, 10][f] as int
	var bl: Array = PAL["black"]
	poly([V(8, 6), V(1, wy), V(3, 6 + wy / 3.0), V(0, 7 + wy / 2.0), V(7, 9)], dk(PAL["purple"], 0.5))
	poly([V(10, 6), V(17, wy), V(15, 6 + wy / 3.0), V(18, 7 + wy / 2.0), V(11, 9)], dk(PAL["purple"], 0.4))
	ell(9.0, 7.0, 2.6, 2.8, bl)
	setp(7, 3, bl[1])
	setp(11, 3, bl[1])
	setp(8, 6, Color("ff3a20"))
	setp(10, 6, Color("ff3a20"))
	setp(9, 8, PAL["white"][0])


func draw_bloater(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"]
	var wob := [0.0, 0.6, -0.4, 0.4, 0.4, -0.4, 1.8][f] as float
	rect(7 + m["a"] * 0.5, 22, 3, 3, dk(PAL["pale"], 0.3))
	rect(14 + m["b"] * 0.5, 22, 3, 3, PAL["pale"])
	ell(12.0, 14.5 + b, 9.5 + wob, 8.2 + wob * 0.5, PAL["rot"])
	ell(9.0, 16.0 + b, 4.0, 3.5, PAL["flesh"])
	ell(15.5, 12.0 + b, 1.6, 1.6, PAL["glow_g"])
	ell(8.0, 11.0 + b, 1.2, 1.2, PAL["glow_g"])
	ell(14.0, 19.5 + b, 1.2, 1.2, Array([Color("fff0a0"), Color("d8c050"), Color("907a20")]))
	for i in 5:
		setp(11 + i, 14 + b + (i % 2), PAL["black"][1])
	if m["atk"]:
		line(5, 12 + b, 10, 17 + b, PAL["glow_g"][0])
		line(14, 8 + b, 18, 15 + b, PAL["glow_g"][0])
	ell(13.0, 5.0 + b, 3.0, 2.6, PAL["pale"])
	line(13, 4 + b, 15, 6 + b, PAL["black"][2])
	line(15, 4 + b, 13, 6 + b, PAL["black"][2])
	rect(19, 12 + b, 3, 3, PAL["pale"])


func draw_bone_warden(f: int) -> void:
	var m := motion(f)
	var b: int = m["bob"] * 2
	var bp: Array = PAL["bone"]
	var cx := 20
	poly([V(cx - 7, 18 + b), V(cx + 4, 18 + b), V(cx + 2, 44), V(cx - 4, 47), V(cx - 10 - m["a"], 45)], PAL["crimson"])
	clear_px(cx - 6, 46)
	clear_px(cx - 9, 44)
	var hip := 36 + b
	thick_line(cx - 2, hip, cx - 4 + m["a"] * 1.5, 54 - m["la"] * 2, 3, dk(bp, 0.25))
	rect(cx - 6 + m["a"] * 1.5, 52 - m["la"] * 2, 6, 3, dk(PAL["rust"], 0.2))
	thick_line(cx + 3, hip, cx + 3 + m["b"] * 1.5, 54 - m["lb"] * 2, 3, bp)
	rect(cx + 1 + m["b"] * 1.5, 52 - m["lb"] * 2, 6, 3, PAL["rust"])
	rect(cx + 1 + m["b"] * 1.2, 44 - m["lb"], 5, 4, PAL["rust"])
	ell(cx + 0.5, hip, 5.0, 3.0, bp)
	rect(cx - 5, hip, 11, 4, PAL["rust"])
	flat(cx - 1, 22 + b, 3, 14, bp[2])
	thick_line(cx - 7, 21 + b, cx - 9, 34 + b, 3, dk(bp, 0.3))
	ell(cx + 0.5, 26.0 + b, 7.0, 5.6, bp)
	for ry in [23, 26, 29]:
		flat(cx - 5, ry + b, 11, 1, PAL["black"][2])
	flat(cx - 1, 21 + b, 3, 10, bp[1])
	ell(cx - 7.0, 20.0 + b, 4.5, 3.5, PAL["rust"])
	ell(cx + 8.0, 20.0 + b, 4.5, 3.5, PAL["rust"])
	if m["atk"]:
		thick_line(cx + 8, 21 + b, cx + 12, 12 + b, 3, bp)
		thick_line(cx + 12, 12 + b, cx + 22, -2 + b, 4, PAL["metal"])
		flat(cx + 9, 10 + b, 6, 2, PAL["gold"][1])
	else:
		thick_line(cx + 8, 21 + b, cx + 10, 32 + b, 3, bp)
		thick_line(cx + 11, 34 + b, cx + 13, 55, 4, PAL["metal"])
		flat(cx + 7, 32 + b, 8, 2, PAL["gold"][1])
		rect(cx + 10, 28 + b, 2, 4, PAL["leather"])
	ell(cx + 1.0, 11.0 + b, 6.2, 6.0, bp)
	rect(cx - 2, 15 + b, 7, 4, bp)
	flat(cx - 2, 9 + b, 3, 3, PAL["black"][2])
	flat(cx + 3, 9 + b, 3, 3, PAL["black"][2])
	flat(cx + 4, 10 + b, 2, 1, Color("ff4a20"))
	flat(cx - 1, 10 + b, 1, 1, Color("ff4a20"))
	for i in 4:
		setp(cx - 1 + i * 2, 17 + b, PAL["black"][2])
	rect(cx - 5, 4 + b, 12, 3, PAL["gold"])
	for i in 4:
		poly([V(cx - 5 + i * 3, 5 + b), V(cx - 4 + i * 3, 0 + b), V(cx - 2 + i * 3, 5 + b)], PAL["gold"])


func draw_mother_of_rot(f: int) -> void:
	var br := [0.0, 0.8, 0.3, -0.3, 0.3, 0.6, 2.0][f] as float
	var rp: Array = PAL["rot"]
	var fp: Array = PAL["flesh"]
	for i in 7:
		var tx := 8 + i * 7
		var sw := (i + f) % 3 - 1
		thick_line(tx, 40, tx + sw * 2, 46, 2, dk(fp, 0.3))
	ell(28.0, 30.0, 25.0 + br, 15.0 + br * 0.6, fp)
	ell(17.0, 33.0, 9.0, 7.0, rp)
	ell(42.0, 31.0, 8.0, 7.5, rp)
	ell(30.0, 38.0, 10.0, 4.0, dk(rp, 0.2))
	for p in [V(10, 27), V(46, 25), V(22, 38), V(38, 39)]:
		ell(p.x, p.y, 2.0, 2.0, PAL["glow_g"])
	for p in [V(8, 33), V(48, 33), V(19, 24)]:
		ell_flat(p.x, p.y, 2.4, 1.4, PAL["black"][2])
		setp(int(p.x) - 1, int(p.y) - 1, PAL["white"][0])
		setp(int(p.x) + 1, int(p.y) - 1, PAL["white"][0])
	for i in 5:
		thick_line(18 + i * 5, 18, 16 + i * 6, 6 + (i % 2) * 3, 2, PAL["bone"])
	ell(32.0, 21.0, 8.0, 6.5, PAL["pale"])
	setp(29, 19, PAL["glow_g"][0])
	setp(30, 19, PAL["glow_g"][1])
	setp(35, 19, PAL["glow_g"][0])
	setp(36, 19, PAL["glow_g"][1])
	var mo := 3.0 if f == 6 else 1.6
	ell_flat(32.5, 24.0, 4.5, mo, PAL["black"][2])
	for i in 5:
		setp(29 + i * 2, 23, PAL["white"][1])
	if f == 6:
		ell_flat(32.5, 24.5, 2.5, 1.5, PAL["glow_g"][1])


func draw_hollow_bishop(f: int) -> void:
	var fl := [0, 1, 2, 1, 0, -1, 0][f] as int
	var wp: Array = PAL["white"]
	var gd: Array = PAL["gold"]
	ring(20.5, 13.0 + fl, 10.0, 10.0, 0.72, gd[1])
	ring(20.5, 13.0 + fl, 10.0, 10.0, 0.9, gd[0])
	poly([V(13, 22 + fl), V(28, 22 + fl), V(35, 52 + fl), V(29, 49 + fl), V(24, 54 + fl), V(18, 50 + fl), V(12, 55 + fl), V(6, 51 + fl)], wp)
	poly([V(13, 22 + fl), V(15, 22 + fl), V(8, 52 + fl), V(6, 51 + fl)], gd)
	poly([V(26, 22 + fl), V(28, 22 + fl), V(35, 52 + fl), V(33, 51 + fl)], gd)
	rect(18, 22 + fl, 5, 30, PAL["crimson"])
	flat(20, 26 + fl, 1, 6, gd[0])
	flat(19, 28 + fl, 3, 1, gd[0])
	if f == 6:
		thick_line(14, 25 + fl, 3, 18 + fl, 3, wp)
		thick_line(27, 25 + fl, 38, 18 + fl, 3, wp)
		ell(3.0, 17.0 + fl, 2.5, 2.5, PAL["fire"])
		ell(38.0, 17.0 + fl, 2.5, 2.5, PAL["fire"])
	else:
		thick_line(14, 25 + fl, 11, 36 + fl, 3, dk(wp, 0.2))
		thick_line(27, 25 + fl, 30, 35 + fl, 3, wp)
		line(31, 36 + fl, 32, 42 + fl, gd[2])
		ell(32.0, 44.0 + fl, 2.5, 2.2, gd)
		setp(33, 41 + fl, PAL["glow_g"][1])
	poly([V(14, 15 + fl), V(16, 3 + fl), V(20, 0 + fl), V(25, 3 + fl), V(27, 15 + fl)], wp)
	flat(20, 3 + fl, 1, 10, gd[1])
	flat(18, 6 + fl, 5, 1, gd[1])
	ell(20.5, 17.5 + fl, 5.4, 5.0, wp)
	ell_flat(21.0, 18.0 + fl, 3.6, 4.0, Color("040205"))
	setp(19, 17 + fl, Color("fffbe0"))
	setp(23, 17 + fl, Color("fffbe0"))
	for y in H:
		for x in W:
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and y > 44 + fl:
				c.a = clampf(1.0 - float(y - 44 - fl) / 13.0, 0.25, 1.0)
				img.set_pixel(x, y, c)


func gen_characters() -> void:
	sheet("chars/exile", 7, 20, 28, draw_exile)
	sheet("chars/heretic", 7, 20, 28, draw_heretic)
	sheet("chars/penitent", 7, 20, 28, draw_penitent)
	sheet("chars/merchant", 7, 20, 28, draw_merchant)
	sheet("chars/skeleton", 7, 20, 28, draw_skeleton)
	sheet("chars/skel_archer", 7, 20, 28, draw_skel_archer)
	sheet("chars/ghoul", 7, 24, 24, draw_ghoul)
	sheet("chars/cultist", 7, 20, 28, draw_cultist)
	sheet("chars/wraith", 7, 22, 30, draw_wraith)
	sheet("chars/imp", 7, 18, 20, draw_imp)
	sheet("chars/brute", 7, 30, 34, draw_brute)
	sheet("chars/bat", 7, 19, 14, draw_bat)
	sheet("chars/bloater", 7, 25, 26, draw_bloater)
	sheet("chars/bone_warden", 7, 46, 57, draw_bone_warden)
	sheet("chars/mother_of_rot", 7, 58, 48, draw_mother_of_rot)
	sheet("chars/hollow_bishop", 7, 42, 58, draw_hollow_bishop)


# ---------------------------------------------------------------------------
# Weapons (held, pointing right, grip at left-centre) and item icons
# ---------------------------------------------------------------------------

func gen_weapons_and_items() -> void:
	var weapons := {
		"crossbow": [18, 11], "repeater": [18, 12], "blunderbuss": [18, 9],
		"staff": [22, 9], "wand": [14, 8], "axe": [14, 12],
	}
	for wname: String in weapons:
		var sz: Array = weapons[wname]
		canvas(sz[0], sz[1])
		call("weapon_" + wname)
		outline()
		save("items/w_" + wname)
	for iname in ["helm", "armor", "gloves", "boots", "amulet", "ring", "flask", "coin", "soul", "key"]:
		canvas(16, 16)
		call("icon_" + iname)
		outline()
		save("items/" + iname)


func weapon_crossbow() -> void:
	rect(1, 4, 11, 3, PAL["wood"])
	rect(0, 4, 3, 4, dk(PAL["wood"], 0.2))
	thick_line(12, 0, 12, 10, 2, PAL["metal"])
	line(11, 1, 9, 5, PAL["white"][2])
	line(9, 5, 11, 9, PAL["white"][2])
	flat(5, 3, 9, 1, PAL["wood"][0])
	flat(14, 3, 2, 1, PAL["metal"][0])
	setp(6, 7, PAL["metal"][2])


func weapon_repeater() -> void:
	weapon_crossbow()
	rect(5, 0, 6, 3, PAL["leather"])
	flat(6, 1, 4, 1, PAL["gold"][1])


func weapon_blunderbuss() -> void:
	rect(0, 3, 6, 4, PAL["wood"])
	rect(5, 3, 9, 3, PAL["metal"])
	poly([V(13, 2), V(17, 0), V(17, 8), V(13, 6)], PAL["metal"])
	flat(16, 2, 1, 4, PAL["black"][2])
	flat(7, 3, 6, 1, PAL["gold"][1])


func weapon_staff() -> void:
	rect(0, 4, 17, 2, PAL["wood"])
	ell(18.0, 4.5, 3.0, 3.6, PAL["fire"])
	line(16, 1, 15, 4, PAL["bone"][1])
	line(16, 8, 15, 5, PAL["bone"][1])
	flat(4, 3, 2, 4, PAL["gold"][1])


func weapon_wand() -> void:
	rect(0, 3, 8, 2, PAL["bone"])
	ell(10.5, 3.5, 3.0, 3.0, PAL["bone"])
	setp(11, 3, PAL["glow_g"][1])
	setp(10, 5, PAL["black"][2])
	flat(2, 2, 1, 4, PAL["crimson"][1])


func weapon_axe() -> void:
	rect(0, 5, 11, 2, PAL["wood"])
	poly([V(8, 1), V(13, 0), V(13, 11), V(8, 10), V(10, 6)], PAL["metal"])
	flat(12, 1, 1, 9, PAL["metal"][0])


func icon_helm() -> void:
	ell(8.0, 8.0, 5.5, 5.5, PAL["metal"])
	rect(3, 9, 10, 4, PAL["metal"])
	flat(5, 9, 7, 1, PAL["black"][2])
	flat(8, 10, 1, 2, PAL["black"][2])
	line(8, 2, 8, 0, PAL["crimson"][0])


func icon_armor() -> void:
	poly([V(2, 3), V(14, 3), V(13, 14), V(3, 14)], PAL["metal"])
	ell(3.0, 4.0, 2.5, 2.0, PAL["metal"])
	ell(13.0, 4.0, 2.5, 2.0, PAL["metal"])
	flat(6, 2, 4, 2, Color(0, 0, 0, 0))
	flat(8, 5, 1, 8, PAL["metal"][2])
	flat(4, 11, 9, 1, PAL["leather"][2])


func icon_gloves() -> void:
	poly([V(4, 2), V(11, 2), V(12, 10), V(4, 10)], PAL["leather"])
	for i in 3:
		rect(4 + i * 3, 0, 2, 4, PAL["leather"])
	rect(11, 4, 3, 3, PAL["leather"])
	rect(3, 10, 10, 4, PAL["metal"])


func icon_boots() -> void:
	rect(4, 1, 6, 10, PAL["leather"])
	poly([V(4, 10), V(10, 10), V(15, 12), V(15, 15), V(4, 15)], PAL["leather"])
	flat(4, 14, 11, 1, PAL["boot"][2])
	flat(4, 3, 6, 1, PAL["metal"][1])


func icon_amulet() -> void:
	for i in 12:
		var a := PI * float(i) / 11.0
		setp(int(8 + 6 * cos(a)), int(7 - 6 * sin(a)) - 1, PAL["gold"][1])
	ell(8.0, 11.0, 3.4, 3.8, PAL["gold"])
	ell(8.0, 11.0, 2.0, 2.4, PAL["crimson"])
	setp(7, 10, PAL["white"][0])


func icon_ring() -> void:
	ring(8.0, 9.5, 5.5, 4.5, 0.4, PAL["gold"][1])
	ring(8.0, 9.0, 5.5, 4.5, 0.75, PAL["gold"][0])
	ell(8.0, 4.0, 2.4, 2.4, PAL["glow_p"])
	setp(7, 3, PAL["white"][0])


func icon_flask() -> void:
	rect(6, 1, 4, 2, PAL["wood"])
	rect(6, 3, 4, 3, dk(PAL["white"], 0.3))
	ell(8.0, 10.0, 5.5, 5.0, PAL["crimson"])
	flat(5, 8, 1, 3, PAL["white"][0])


func icon_coin() -> void:
	ell(8.0, 8.0, 4.0, 4.0, PAL["gold"])
	flat(7, 6, 2, 4, PAL["gold"][2])


func icon_soul() -> void:
	ell(8.0, 10.0, 3.6, 3.8, PAL["ghost"])
	poly([V(5, 9), V(8, 1), V(11, 9)], PAL["ghost"])
	setp(7, 10, Color("ffffff"))
	setp(9, 10, Color("ffffff"))


func icon_key() -> void:
	ring(5.0, 8.0, 3.5, 3.5, 0.3, PAL["gold"][1])
	flat(8, 7, 7, 2, PAL["gold"][1])
	flat(12, 9, 1, 3, PAL["gold"][1])
	flat(14, 9, 1, 2, PAL["gold"][1])


# ---------------------------------------------------------------------------
# Projectiles & effects (drawn unshaded in game, so they glow in the dark)
# ---------------------------------------------------------------------------

func gen_projectiles() -> void:
	canvas(11, 3)
	flat(0, 1, 9, 1, PAL["wood"][0])
	flat(8, 0, 2, 3, PAL["metal"][0])
	flat(10, 1, 1, 1, PAL["white"][0])
	flat(0, 0, 2, 1, PAL["crimson"][0])
	flat(0, 2, 2, 1, PAL["crimson"][0])
	save("fx/bolt")
	canvas(10, 10)
	call("weapon_axe_spin")
	outline()
	save("fx/axe")
	canvas(9, 9)
	ell(4.5, 4.5, 4.0, 4.0, PAL["bone"])
	setp(3, 4, PAL["glow_g"][0])
	setp(6, 4, PAL["glow_g"][0])
	flat(3, 7, 4, 1, PAL["black"][2])
	save("fx/skull")
	canvas(7, 3)
	flat(0, 1, 6, 1, PAL["bone"][0])
	flat(5, 0, 2, 3, PAL["bone"][1])
	save("fx/shard")
	# Soft round sprite, tinted at runtime for bullets.
	canvas(16, 16)
	for y in 16:
		for x in 16:
			var d := V(x + 0.5 - 8, y + 0.5 - 8).length() / 8.0
			if d < 1.0:
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = pow(a, 0.6)
				var c := Color(1, 1, 1, a)
				if d < 0.45:
					c = Color(1, 1, 1, 1)
				img.set_pixel(x, y, c)
	save("fx/orb")
	canvas(64, 64)
	for y in 64:
		for x in 64:
			var d := V(x + 0.5 - 32, y + 0.5 - 32).length() / 32.0
			if d < 1.0:
				img.set_pixel(x, y, Color(1, 1, 1, pow(1.0 - d, 2.0)))
	save("fx/glow")
	sheet("fx/flame", 4, 8, 12, draw_flame, false)
	# Item light beam (Diablo-style loot pillar), tinted at runtime.
	canvas(12, 48)
	for y in 48:
		for x in 12:
			var cx := absf(x + 0.5 - 6.0) / 6.0
			var a := (1.0 - cx * cx) * pow(float(y) / 48.0, 1.5) * 0.9
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0, 1)))
	save("fx/beam")


func weapon_axe_spin() -> void:
	rect(4, 1, 2, 8, PAL["wood"])
	poly([V(0, 0), V(5, 2), V(5, 5), V(0, 6)], PAL["metal"])
	poly([V(10, 4), V(5, 5), V(5, 8), V(10, 10)], PAL["metal"])


func draw_flame(f: int) -> void:
	var sway := [0, 1, 0, -1][f] as int
	var hgt := [10, 9, 11, 9][f] as int
	poly([V(1, 11), V(7, 11), V(6, 7), V(4 + sway, 11 - hgt), V(2, 7)], PAL["fire"])
	poly([V(3, 11), V(5, 11), V(5, 8), V(4 + sway, 12 - hgt + 3), V(3, 8)], [Color("ffffe0"), Color("fff3b0"), Color("ffd070")])
	for y in H:
		for x in W:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				c.a = clampf(0.6 + float(y) / 20.0, 0.0, 1.0)
				img.set_pixel(x, y, c)


# ---------------------------------------------------------------------------
# Isometric tiles: 32x16 floor diamonds, walls with brick faces, doors.
# ---------------------------------------------------------------------------

func in_diamond(x: int, y: int) -> bool:
	return absf(x + 0.5 - 16.0) / 16.0 + absf(y + 0.5 - 8.0) / 8.0 <= 1.0


func gen_tiles() -> void:
	for bname: String in BIOMES:
		var bio: Dictionary = BIOMES[bname]
		var fp := _p(bio["floor"][0], bio["floor"][1], bio["floor"][2])
		var strip := Image.create(32 * 8, 16, false, Image.FORMAT_RGBA8)
		var emis := Image.create(32 * 8, 16, false, Image.FORMAT_RGBA8)
		for v in 8:
			canvas(32, 16)
			var lava := floor_tile(fp, v, bname)
			strip.blit_rect(img, Rect2i(0, 0, 32, 16), Vector2i(v * 32, 0))
			emis.blit_rect(lava, Rect2i(0, 0, 32, 16), Vector2i(v * 32, 0))
		strip.save_png(OUT_DIR + "tiles/floor_" + bname + ".png")
		emis.save_png(OUT_DIR + "tiles/floor_glow_" + bname + ".png")
		var wp := _p(bio["wall"][0], bio["wall"][1], bio["wall"][2])
		var tp := _p(bio["top"][0], bio["top"][1], bio["top"][2])
		var tall := Image.create(32 * 3, 56, false, Image.FORMAT_RGBA8)
		for v in 3:
			canvas(32, 56)
			draw_wall(40, wp, tp, v, bname)
			tall.blit_rect(img, Rect2i(0, 0, 32, 56), Vector2i(v * 32, 0))
		tall.save_png(OUT_DIR + "tiles/wall_" + bname + ".png")
		canvas(32, 22)
		draw_wall(6, wp, tp, 0, bname)
		save("tiles/rim_" + bname)
		canvas(32, 56)
		draw_wall(40, wp, tp, 1, bname)
		draw_door_arch(40, wp)
		save("tiles/door_" + bname)
		canvas(32, 56)
		draw_door_bars(40)
		save("tiles/door_bars")


func floor_tile(fp: Array, v: int, bname: String) -> Image:
	var r := RandomNumberGenerator.new()
	r.seed = hash(bname) + v * 977
	var base: Color = fp[1].lightened(r.randf_range(-0.06, 0.06)) if v != 0 else fp[1]
	var glow := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	var split := r.randi_range(0, 2)
	for y in 16:
		for x in 32:
			if not in_diamond(x, y):
				continue
			var c := base
			var n := r.randf()
			if n < 0.18:
				c = c.darkened(0.12)
			elif n > 0.86:
				c = c.lightened(0.08)
			var edge_tl := not in_diamond(x - 1, y) or not in_diamond(x, y - 1)
			var edge_br := not in_diamond(x + 1, y) or not in_diamond(x, y + 1)
			if edge_br:
				c = fp[2].darkened(0.35)
			elif edge_tl:
				c = fp[0]
			# Some tiles are split into two flagstones.
			if split == 1 and absi((x - 16) - (y - 8) * 2) == 0 and not edge_br:
				c = fp[2].darkened(0.2)
			setp(x, y, c)
	# cracks
	for _i in r.randi_range(0, 2):
		var px := r.randi_range(8, 24)
		var py := r.randi_range(4, 11)
		for _s in r.randi_range(3, 7):
			if in_diamond(px, py):
				setp(px, py, fp[2].darkened(0.3))
				if bname == "inferno" and r.randf() < 0.75:
					glow.set_pixel(px, py, Color("ff7a20") if r.randf() < 0.7 else Color("ffd060"))
			px += r.randi_range(-1, 1)
			py += r.randi_range(0, 1) if r.randf() < 0.5 else r.randi_range(-1, 0)
	if bname == "crypt" and r.randf() < 0.4:
		for _i in 6:
			var mx := r.randi_range(6, 26)
			var my := r.randi_range(3, 12)
			if in_diamond(mx, my):
				setp(mx, my, Color("4a5e3a"))
	if bname == "catacomb" and r.randf() < 0.35:
		var bx := r.randi_range(10, 20)
		var by := r.randi_range(5, 9)
		flat(bx, by, 3, 1, PAL["bone"][1])
		setp(bx + 3, by - 1, PAL["bone"][2])
	return glow


func draw_wall(hh: int, wp: Array, tp: Array, variant: int, bname: String) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash(bname) * 31 + variant * 7 + hh
	var left := _poly_mask([V(0, 8), V(16, 16), V(16, 16 + hh), V(0, 8 + hh)])
	var right := _poly_mask([V(16, 16), V(32, 8), V(32, 8 + hh), V(16, 16 + hh)])
	var brick_h := 7
	for k: Vector2i in left:
		var rr := k.y - 8.0 - k.x * 0.5
		var row := int(floor(rr / brick_h))
		var c: Color = wp[1]
		var bh := hash(Vector2i(row, int(floor((k.x + (row % 2) * 4) / 8.0)))) + variant * 13
		c = c.lightened(float(bh % 9) / 100.0) if bh % 2 == 0 else c.darkened(float(bh % 9) / 90.0)
		if int(rr) % brick_h == 0 or (k.x + (row % 2) * 4) % 8 == 0:
			c = wp[2].darkened(0.25)
		if rr < 1.5:
			c = wp[0]
		setp(k.x, k.y, c)
	for k: Vector2i in right:
		var rr := k.y - 16.0 + (k.x - 16) * 0.5
		var row := int(floor(rr / brick_h))
		var bh := hash(Vector2i(row, int(floor((k.x + (row % 2) * 4) / 8.0)))) + variant * 17
		var c: Color = wp[1].darkened(0.22)
		c = c.lightened(float(bh % 9) / 100.0) if bh % 2 == 0 else c.darkened(float(bh % 9) / 90.0)
		if int(rr) % brick_h == 0 or (k.x + (row % 2) * 4) % 8 == 0:
			c = wp[2].darkened(0.4)
		if rr < 1.5:
			c = wp[1]
		setp(k.x, k.y, c)
	for y in 16:
		for x in 32:
			if in_diamond(x, y):
				var c: Color = tp[1]
				if not in_diamond(x + 1, y) or not in_diamond(x, y + 1):
					c = tp[2]
				elif not in_diamond(x - 1, y) or not in_diamond(x, y - 1):
					c = tp[0]
				elif r.randf() < 0.15:
					c = c.darkened(0.1)
				setp(x, y, c)
	# grime gradient towards the base
	for y in range(16, 16 + hh + 8):
		for x in 32:
			var c := getp(x, y)
			if c.a > 0.0:
				var t := clampf(float(y - (8 + hh - 6)) / 14.0, 0.0, 0.5)
				setp(x, y, c.darkened(t))
	# damage & biome decoration
	if hh > 10:
		for _i in r.randi_range(1, 3):
			var cx := r.randi_range(2, 29)
			var cy := r.randi_range(18, 8 + hh)
			var hole := getp(cx, cy)
			if hole.a > 0.0:
				flat(cx, cy, 2, 1, wp[2].darkened(0.5))
		if bname == "catacomb":
			for _i in r.randi_range(1, 3):
				var sx := r.randi_range(2, 12)
				var sy := int(8 + sx * 0.5) + r.randi_range(6, hh - 6)
				ell(sx + 1.5, sy + 1.5, 1.8, 1.6, PAL["bone"])
				setp(sx + 1, sy + 1, PAL["black"][2])
				setp(sx + 2, sy + 1, PAL["black"][2])
		if bname == "crypt" and variant == 2:
			for _i in 12:
				var vx := r.randi_range(0, 31)
				var vy := r.randi_range(10, 16 + hh)
				if getp(vx, vy).a > 0:
					setp(vx, vy, Color("3f5532"))
		if bname == "inferno":
			for _i in r.randi_range(2, 4):
				var ex := r.randi_range(1, 30)
				var ey := r.randi_range(20, 8 + hh)
				if getp(ex, ey).a > 0:
					setp(ex, ey, Color("c84a1a"))


## Arched doorway cut into the left face of a tall wall block.
func face_pt(u: float, v: float, hh: int) -> Vector2:
	return V(u, 8.0 + hh + u * 0.5 - v)


func in_arch(u: float, v: float) -> bool:
	if u < 3.0 or u > 13.0 or v < 0.0:
		return false
	if v <= 22.0:
		return true
	var dx := (u - 8.0) / 5.0
	var dy := (v - 22.0) / 6.0
	return dx * dx + dy * dy <= 1.0


func draw_door_arch(hh: int, wp: Array) -> void:
	for x in range(0, 17):
		for y in range(8, 17 + hh):
			var u := float(x) + 0.5
			var v := 8.0 + hh + u * 0.5 - (float(y) + 0.5)
			if in_arch(u, v):
				var depth := clampf(v / 30.0, 0.0, 1.0)
				setp(x, y, Color("070405").lerp(Color("1a1214"), 1.0 - depth))
			elif in_arch(u - 1.5, v - 1.0) or in_arch(u + 1.5, v - 1.0) or in_arch(u, v - 1.5):
				setp(x, y, wp[0].lightened(0.08))
	# keystone
	var k := face_pt(8, 29, hh)
	flat(k.x - 1, k.y - 1, 3, 3, wp[0].lightened(0.15))


func draw_door_bars(hh: int) -> void:
	var bar: Array = PAL["metal"]
	for u in [4, 6, 8, 10, 12]:
		for v in range(0, 30):
			if in_arch(u + 0.5, v):
				var p := face_pt(u, v, hh)
				setp(int(p.x), int(p.y), bar[1] if u % 4 == 0 else bar[2])
	for vv in [6, 16]:
		for u in range(3, 14):
			var p := face_pt(u, vv, hh)
			setp(int(p.x), int(p.y), PAL["rust"][1])
	for u in [4, 8, 12]:
		var p := face_pt(u, 0, hh)
		setp(int(p.x), int(p.y), bar[0])


# ---------------------------------------------------------------------------
# Props & interactables. Origin convention: the bottom-centre of the image is
# the point that touches the floor.
# ---------------------------------------------------------------------------

func gen_props() -> void:
	for bname: String in BIOMES:
		var bio: Dictionary = BIOMES[bname]
		var wp := _p(bio["wall"][0], bio["wall"][1], bio["wall"][2])
		canvas(18, 46)
		draw_pillar(wp, bname)
		outline()
		save("props/pillar_" + bname)
	canvas(14, 18)
	draw_tombstone()
	outline()
	save("props/tombstone")
	canvas(18, 9)
	draw_bones()
	outline()
	save("props/bones")
	canvas(16, 12)
	draw_skulls()
	outline()
	save("props/skulls")
	canvas(14, 14)
	draw_brazier()
	outline()
	save("props/brazier")
	canvas(16, 34)
	draw_statue()
	outline()
	save("props/statue")
	canvas(12, 10)
	draw_candles()
	outline()
	save("props/candles")
	sheet("props/chest", 2, 20, 17, draw_chest)
	canvas(26, 22)
	draw_altar()
	outline()
	save("props/altar")
	canvas(20, 10)
	draw_campfire()
	outline()
	save("props/campfire")
	canvas(16, 14)
	draw_pedestal()
	outline()
	save("props/pedestal")
	canvas(8, 12)
	draw_sconce()
	outline()
	save("props/sconce")
	for i in 3:
		canvas(24, 12)
		draw_blood(i)
		save("props/blood_%d" % i)
	canvas(32, 16)
	draw_rubble()
	save("props/rubble")


func draw_pillar(wp: Array, bname: String) -> void:
	rect(1, 38, 16, 7, dk(wp, 0.1))
	for y in range(6, 39):
		for x in range(3, 15):
			var t := float(x - 3) / 11.0
			var c: Color = wp[0] if t < 0.3 else (wp[1] if t < 0.75 else wp[2])
			if (x == 6 or x == 10) and y % 2 == 0:
				c = c.darkened(0.15)
			setp(x, y, c)
	rect(1, 2, 16, 5, wp)
	flat(0, 2, 18, 1, wp[0])
	if bname == "catacomb":
		ell(9.0, 22.0, 2.5, 2.2, PAL["bone"])
		setp(8, 22, PAL["black"][2])
		setp(10, 22, PAL["black"][2])
	if bname == "inferno":
		line(6, 12, 9, 30, Color("a03a1a"))


func draw_tombstone() -> void:
	ell(7.0, 6.0, 5.5, 5.0, PAL["stone"])
	rect(1.5, 6, 11, 10, PAL["stone"])
	flat(6, 4, 2, 7, PAL["stone"][2])
	flat(4, 6, 6, 2, PAL["stone"][2])
	rect(0, 15, 14, 3, dk(PAL["stone"], 0.3))
	setp(11, 12, Color("3f5532"))
	setp(2, 13, Color("3f5532"))


func draw_bones() -> void:
	thick_line(1, 6, 9, 3, 2, PAL["bone"])
	thick_line(6, 7, 15, 6, 2, PAL["bone"])
	ell(14.0, 4.0, 3.0, 2.6, PAL["bone"])
	setp(13, 4, PAL["black"][2])
	setp(15, 4, PAL["black"][2])


func draw_skulls() -> void:
	for p in [V(4, 8), V(11, 8), V(8, 4)]:
		ell(p.x, p.y, 3.2, 2.9, PAL["bone"])
		setp(int(p.x) - 1, int(p.y), PAL["black"][2])
		setp(int(p.x) + 1, int(p.y), PAL["black"][2])


func draw_brazier() -> void:
	line(3, 13, 6, 7, PAL["metal"][2])
	line(10, 13, 7, 7, PAL["metal"][2])
	ell(7.0, 5.0, 6.0, 3.0, PAL["metal"])
	flat(2, 3, 10, 2, PAL["fire"][2])
	setp(4, 3, PAL["fire"][1])
	setp(8, 3, PAL["fire"][0])


func draw_statue() -> void:
	rect(2, 27, 12, 7, PAL["stone"])
	poly([V(4, 12), V(11, 12), V(13, 27), V(3, 27)], PAL["stone"])
	poly([V(4, 10), V(0, 4), V(1, 16), V(4, 18)], dk(PAL["stone"], 0.15))
	poly([V(11, 10), V(15, 4), V(14, 16), V(11, 18)], dk(PAL["stone"], 0.2))
	ell(8.0, 8.0, 3.0, 3.4, PAL["stone"])
	flat(7, 9, 3, 1, PAL["stone"][2])
	flat(8, 10, 1, 4, Color("6a2020"))
	rect(5, 14, 5, 3, PAL["stone"])


func draw_candles() -> void:
	for p in [V(2, 4), V(6, 2), V(9, 5)]:
		rect(p.x, p.y, 2, 9 - p.y, PAL["white"])
		setp(int(p.x), int(p.y) - 1, PAL["fire"][0])
	flat(0, 9, 12, 1, PAL["white"][2])


func draw_chest(f: int) -> void:
	rect(1, 7, 18, 9, PAL["wood"])
	flat(1, 9, 18, 1, PAL["metal"][2])
	flat(3, 7, 2, 9, PAL["metal"][1])
	flat(15, 7, 2, 9, PAL["metal"][1])
	if f == 0:
		ell(10.0, 7.0, 9.0, 4.0, PAL["wood"])
		flat(3, 3, 2, 5, PAL["metal"][1])
		flat(15, 3, 2, 5, PAL["metal"][1])
		rect(8, 7, 4, 4, PAL["gold"])
	else:
		poly([V(1, 7), V(19, 7), V(17, 0), V(3, 0)], dk(PAL["wood"], 0.25))
		flat(2, 7, 16, 2, PAL["black"][2])
		flat(5, 6, 10, 1, PAL["gold"][0])


func draw_altar() -> void:
	rect(2, 8, 22, 13, PAL["stone"])
	rect(0, 6, 26, 4, lt(PAL["stone"], 0.05))
	flat(4, 6, 10, 2, PAL["crimson"][1])
	flat(8, 10, 2, 6, PAL["crimson"][2])
	ell(19.0, 4.0, 3.0, 2.8, PAL["bone"])
	setp(18, 4, PAL["black"][2])
	setp(20, 4, PAL["black"][2])
	for x in [3, 6, 23]:
		rect(x, 1, 2, 5, PAL["white"])
	ell(13.0, 14.5, 3.5, 3.5, PAL["glow_p"])
	flat(12, 13, 3, 3, PAL["white"][0])


func draw_campfire() -> void:
	thick_line(2, 8, 17, 5, 3, PAL["wood"])
	thick_line(3, 4, 18, 8, 3, dk(PAL["wood"], 0.2))
	for i in 7:
		ell(2.0 + i * 2.6, 8.5, 1.6, 1.2, PAL["stone"])


func draw_pedestal() -> void:
	rect(1, 0, 14, 3, lt(PAL["stone"], 0.05))
	rect(3, 3, 10, 8, PAL["stone"])
	rect(1, 11, 14, 3, dk(PAL["stone"], 0.2))
	flat(5, 5, 6, 1, PAL["gold"][2])


func draw_sconce() -> void:
	flat(2, 8, 4, 3, PAL["metal"][2])
	rect(3, 3, 2, 6, PAL["wood"])
	flat(2, 2, 4, 1, PAL["metal"][1])


func draw_blood(i: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4242 + i
	for _k in 7:
		var cx := r.randf_range(6, 18)
		var cy := r.randf_range(3, 9)
		ell_flat(cx, cy, r.randf_range(1.5, 4.5), r.randf_range(1.0, 2.2), Color(0.42, 0.04, 0.05, 0.85))
	for _k in 6:
		setp(r.randi_range(1, 22), r.randi_range(1, 10), Color(0.35, 0.03, 0.04, 0.8))


func draw_rubble() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for _k in 9:
		var cx := r.randf_range(6, 26)
		var cy := r.randf_range(4, 12)
		ell(cx, cy, r.randf_range(1.0, 2.5), r.randf_range(0.8, 1.6), PAL["stone"])


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func gen_ui() -> void:
	canvas(32, 32)
	draw_panel(Color("120c10"), PAL["gold"])
	save("ui/panel")
	canvas(32, 32)
	draw_panel(Color("0c0a0e"), dk(PAL["metal"], 0.3))
	save("ui/panel_dark")
	for st in ["normal", "hover", "pressed", "disabled"]:
		canvas(24, 14)
		draw_button(st)
		save("ui/button_" + st)
	canvas(22, 22)
	draw_slot()
	save("ui/slot")
	var icons := ["combat", "elite", "treasure", "shop", "shrine", "rest", "boss", "start"]
	var strip := Image.create(14 * icons.size(), 14, false, Image.FORMAT_RGBA8)
	for i in icons.size():
		canvas(14, 14)
		call("room_icon_" + icons[i])
		outline()
		strip.blit_rect(img, Rect2i(0, 0, 14, 14), Vector2i(i * 14, 0))
	strip.save_png(OUT_DIR + "ui/room_icons.png")
	for sk in ["volley", "nova", "consecrate"]:
		canvas(18, 18)
		call("skill_icon_" + sk)
		save("ui/skill_" + sk)
	canvas(15, 15)
	draw_cursor()
	var cur := img.duplicate() as Image
	cur.resize(30, 30, Image.INTERPOLATE_NEAREST)
	cur.save_png(OUT_DIR + "ui/cursor.png")
	canvas(16, 16)
	draw_blessing_icon()
	outline()
	save("ui/blessing")


func draw_panel(bg: Color, trim: Array) -> void:
	for y in 32:
		for x in 32:
			setp(x, y, bg)
	for i in 32:
		for e in [[i, 0], [i, 31], [0, i], [31, i]]:
			setp(e[0], e[1], OUT)
		for e in [[i, 1], [1, i]]:
			setp(e[0], e[1], trim[1])
		for e in [[i, 30], [30, i]]:
			setp(e[0], e[1], trim[2])
		for e in [[i, 2], [2, i], [i, 29], [29, i]]:
			setp(e[0], e[1], OUT)
	for c in [V(2, 2), V(29, 2), V(2, 29), V(29, 29)]:
		flat(c.x - 1, c.y - 1, 3, 3, trim[0])
		setp(int(c.x), int(c.y), trim[2])


func draw_button(st: String) -> void:
	var base := Color("2a2026")
	var trim: Array = PAL["gold"]
	match st:
		"hover":
			base = Color("3e2a2c")
		"pressed":
			base = Color("1a1216")
		"disabled":
			base = Color("1c1a1c")
			trim = dk(PAL["metal"], 0.5)
	flat(0, 0, 24, 14, OUT)
	flat(1, 1, 22, 12, trim[2])
	flat(2, 2, 20, 10, base)
	flat(2, 2, 20, 1, base.lightened(0.12 if st != "pressed" else 0.0))
	flat(2, 11, 20, 1, base.darkened(0.3))
	if st == "hover":
		flat(1, 1, 22, 1, trim[0])


func draw_slot() -> void:
	flat(0, 0, 22, 22, OUT)
	flat(1, 1, 20, 20, Color("2a2428"))
	flat(2, 2, 18, 18, Color("0e0b0d"))
	flat(2, 2, 18, 1, Color("050405"))
	flat(1, 21, 20, 1, Color("3a3238"))


func room_icon_combat() -> void:
	thick_line(2, 11, 11, 2, 2, PAL["metal"])
	thick_line(2, 2, 11, 11, 2, PAL["metal"])
	flat(2, 9, 3, 3, PAL["leather"][1])
	flat(9, 9, 3, 3, PAL["leather"][1])


func room_icon_elite() -> void:
	ell(7.0, 7.5, 4.6, 4.2, PAL["bone"])
	rect(5, 10, 5, 3, PAL["bone"])
	poly([V(2, 6), V(0, 0), V(5, 4)], PAL["crimson"])
	poly([V(12, 6), V(14, 0), V(9, 4)], PAL["crimson"])
	setp(5, 7, PAL["crimson"][0])
	setp(9, 7, PAL["crimson"][0])


func room_icon_treasure() -> void:
	rect(1, 6, 12, 7, PAL["wood"])
	ell(7.0, 6.0, 6.0, 3.0, PAL["wood"])
	rect(6, 6, 3, 3, PAL["gold"])
	flat(1, 8, 12, 1, PAL["gold"][2])


func room_icon_shop() -> void:
	ell(7.0, 8.5, 5.0, 4.5, PAL["leather"])
	rect(5, 2, 4, 3, PAL["leather"])
	flat(4, 4, 6, 1, PAL["gold"][1])
	ell(7.0, 9.0, 2.0, 2.0, PAL["gold"])


func room_icon_shrine() -> void:
	ell(7.0, 6.0, 4.0, 5.0, PAL["glow_p"])
	rect(2, 9, 10, 4, PAL["stone"])
	flat(7, 2, 1, 7, PAL["white"][0])
	flat(5, 4, 5, 1, PAL["white"][0])


func room_icon_rest() -> void:
	thick_line(1, 12, 12, 10, 2, PAL["wood"])
	thick_line(2, 10, 12, 12, 2, dk(PAL["wood"], 0.2))
	poly([V(3, 10), V(11, 10), V(9, 5), V(7, 0), V(5, 5)], PAL["fire"])


func room_icon_boss() -> void:
	ell(7.0, 6.5, 6.0, 5.5, PAL["crimson"])
	rect(4, 10, 7, 3, PAL["crimson"])
	flat(3, 5, 3, 3, OUT)
	flat(8, 5, 3, 3, OUT)
	setp(4, 6, PAL["fire"][0])
	setp(9, 6, PAL["fire"][0])
	for i in 3:
		setp(5 + i * 2, 12, OUT)


func room_icon_start() -> void:
	poly([V(2, 13), V(2, 5), V(7, 1), V(12, 5), V(12, 13)], PAL["stone"])
	poly_flat([V(4, 13), V(4, 6), V(7, 3), V(10, 6), V(10, 13)], Color("0c0809"))


func skill_icon_volley() -> void:
	flat(0, 0, 18, 18, Color("1a2418"))
	for i in 3:
		var y := 4 + i * 5
		line(2, y + 3, 14, y - 2, PAL["wood"][0])
		flat(13, y - 3, 3, 2, PAL["metal"][0])
		flat(2, y + 2, 2, 2, PAL["crimson"][0])


func skill_icon_nova() -> void:
	flat(0, 0, 18, 18, Color("240c0c"))
	ring(9.0, 9.0, 7.5, 7.5, 0.55, PAL["fire"][1])
	ring(9.0, 9.0, 7.5, 7.5, 0.8, PAL["fire"][0])
	ell(9.0, 9.0, 2.5, 2.5, PAL["crimson"])


func skill_icon_consecrate() -> void:
	flat(0, 0, 18, 18, Color("221c0c"))
	ell_flat(9.0, 13.0, 8.0, 3.5, PAL["gold"][2])
	flat(8, 2, 3, 12, PAL["gold"][0])
	flat(4, 5, 11, 3, PAL["gold"][0])


func draw_cursor() -> void:
	var c := Color("f0e0c0")
	for i in [0, 1, 2, 3, 11, 12, 13, 14]:
		setp(7, i, c)
		setp(i, 7, c)
	setp(7, 7, Color("ff4a2a"))
	for i in [0, 1, 2, 3, 11, 12, 13, 14]:
		for d in [Vector2i(-1, 0), Vector2i(1, 0)]:
			if getp(7 + d.x, i).a == 0:
				setp(7 + d.x, i, OUT)
			if getp(i, 7 + d.x).a == 0:
				setp(i, 7 + d.x, OUT)


func draw_blessing_icon() -> void:
	ell(8.0, 8.0, 6.0, 6.0, PAL["gold"])
	flat(7, 3, 2, 10, PAL["white"][0])
	flat(4, 6, 8, 2, PAL["white"][0])
