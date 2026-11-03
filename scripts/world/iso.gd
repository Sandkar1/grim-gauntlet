class_name Iso
extends RefCounted
## Isometric helpers. Tiles are 32x16 diamonds (2:1).
## Grid +x runs down-right on screen, grid +y runs down-left.

const TW := 32.0
const TH := 16.0


static func to_world(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * TW * 0.5, (cell.x + cell.y) * TH * 0.5)


static func to_cellf(p: Vector2) -> Vector2:
	var a := p.x / (TW * 0.5)
	var b := p.y / (TH * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


static func to_cell(p: Vector2) -> Vector2i:
	var c := to_cellf(p)
	return Vector2i(roundi(c.x), roundi(c.y))


## Diamond outline of one cell in world space (optionally shrunk).
static func diamond(cell: Vector2i, scale := 1.0) -> PackedVector2Array:
	var c := to_world(Vector2(cell))
	var hw := TW * 0.5 * scale
	var hh := TH * 0.5 * scale
	return PackedVector2Array([c + Vector2(0, -hh), c + Vector2(hw, 0), c + Vector2(0, hh), c + Vector2(-hw, 0)])


## Distance on the ground plane, correcting for the squashed iso y-axis.
static func ground_dist(a: Vector2, b: Vector2) -> float:
	var d := b - a
	return Vector2(d.x, d.y * 2.0).length()
