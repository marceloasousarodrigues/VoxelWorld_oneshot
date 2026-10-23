class_name NavIcon
extends Control

## Small vector glyphs for the inventory navigation and the equipment slots.
##
## Drawn shapes rather than font characters or emoji: the same glyph renders at
## any scale, never depends on a font, and stays visually consistent with the
## reference's restrained line art.  Presentation only.

var kind := "inventory"
var colour := UiStyle.ACCENT_BLUE
var line_width := 2.0


func setup(glyph: String, tint: Color = UiStyle.ACCENT_BLUE, width: float = 2.0) -> void:
	kind = glyph
	colour = tint
	line_width = width
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var extent := minf(size.x, size.y)
	if extent <= 4.0:
		return
	var origin := (size - Vector2(extent, extent)) * 0.5
	_draw_glyph(origin, extent)


func _draw_glyph(origin: Vector2, extent: float) -> void:
	match kind:
		"inventory":
			_backpack(origin, extent)
		"crafting":
			_grid(origin, extent)
		"character":
			_person(origin, extent)
		"map":
			_map(origin, extent)
		"settings":
			_gear(origin, extent)
		"helmet":
			_helmet(origin, extent)
		"chestplate":
			_chestplate(origin, extent)
		"leggings":
			_leggings(origin, extent)
		"boots":
			_boots(origin, extent)
		"shield":
			_shield(origin, extent)
		_:
			_frame(origin, extent)


func _p(origin: Vector2, extent: float, x: float, y: float) -> Vector2:
	return origin + Vector2(x, y) * extent


func _line(origin: Vector2, extent: float, points: Array, closed: bool = false) -> void:
	var packed := PackedVector2Array()
	for point: Array in points:
		packed.append(_p(origin, extent, float(point[0]), float(point[1])))
	if closed and packed.size() > 2:
		packed.append(packed[0])
	draw_polyline(packed, colour, line_width, true)


func _outline_rect(origin: Vector2, extent: float, x0: float, y0: float, x1: float, y1: float) -> void:
	draw_rect(Rect2(_p(origin, extent, x0, y0), Vector2(x1 - x0, y1 - y0) * extent),
		colour, false, line_width)


func _backpack(origin: Vector2, extent: float) -> void:
	_outline_rect(origin, extent, 0.24, 0.36, 0.76, 0.88)
	_outline_rect(origin, extent, 0.32, 0.22, 0.68, 0.42)
	draw_line(_p(origin, extent, 0.36, 0.36), _p(origin, extent, 0.36, 0.24), colour, line_width, true)
	draw_line(_p(origin, extent, 0.64, 0.36), _p(origin, extent, 0.64, 0.24), colour, line_width, true)
	draw_line(_p(origin, extent, 0.42, 0.56), _p(origin, extent, 0.58, 0.56), colour, line_width, true)
	draw_line(_p(origin, extent, 0.42, 0.56), _p(origin, extent, 0.42, 0.64), colour, line_width, true)
	draw_line(_p(origin, extent, 0.58, 0.56), _p(origin, extent, 0.58, 0.64), colour, line_width, true)


func _grid(origin: Vector2, extent: float) -> void:
	for row in 3:
		for column in 3:
			var x := 0.22 + float(column) * 0.20
			var y := 0.22 + float(row) * 0.20
			_outline_rect(origin, extent, x, y, x + 0.15, y + 0.15)


func _person(origin: Vector2, extent: float) -> void:
	draw_circle(_p(origin, extent, 0.5, 0.32), extent * 0.15, colour, false, line_width, true)
	_line(origin, extent, [
		[0.30, 0.84], [0.30, 0.62], [0.38, 0.52], [0.62, 0.52], [0.70, 0.62], [0.70, 0.84],
	])


func _map(origin: Vector2, extent: float) -> void:
	_line(origin, extent, [
		[0.14, 0.28], [0.38, 0.20], [0.62, 0.28], [0.86, 0.20],
		[0.86, 0.74], [0.62, 0.82], [0.38, 0.74], [0.14, 0.82],
	], true)
	draw_line(_p(origin, extent, 0.38, 0.20), _p(origin, extent, 0.38, 0.74), colour, line_width, true)
	draw_line(_p(origin, extent, 0.62, 0.28), _p(origin, extent, 0.62, 0.82), colour, line_width, true)


func _gear(origin: Vector2, extent: float) -> void:
	var center := _p(origin, extent, 0.5, 0.5)
	draw_arc(center, extent * 0.20, 0.0, TAU, 20, colour, line_width, true)
	for tooth in 8:
		var angle := TAU * float(tooth) / 8.0
		var inner := center + Vector2(cos(angle), sin(angle)) * extent * 0.21
		var outer := center + Vector2(cos(angle), sin(angle)) * extent * 0.33
		draw_line(inner, outer, colour, line_width + 0.6, true)


func _helmet(origin: Vector2, extent: float) -> void:
	draw_arc(_p(origin, extent, 0.5, 0.52), extent * 0.24, PI, TAU, 18, colour, line_width, true)
	draw_line(_p(origin, extent, 0.26, 0.52), _p(origin, extent, 0.74, 0.52), colour, line_width, true)
	draw_line(_p(origin, extent, 0.26, 0.52), _p(origin, extent, 0.26, 0.64), colour, line_width, true)
	draw_line(_p(origin, extent, 0.74, 0.52), _p(origin, extent, 0.74, 0.64), colour, line_width, true)


func _chestplate(origin: Vector2, extent: float) -> void:
	_line(origin, extent, [
		[0.30, 0.26], [0.42, 0.22], [0.50, 0.30], [0.58, 0.22], [0.70, 0.26],
		[0.74, 0.48], [0.66, 0.52], [0.66, 0.80], [0.34, 0.80], [0.34, 0.52], [0.26, 0.48],
	], true)


func _leggings(origin: Vector2, extent: float) -> void:
	_line(origin, extent, [
		[0.30, 0.22], [0.70, 0.22], [0.66, 0.48], [0.58, 0.82], [0.47, 0.82], [0.50, 0.52],
		[0.42, 0.82], [0.34, 0.82], [0.34, 0.48],
	], true)


func _boots(origin: Vector2, extent: float) -> void:
	_line(origin, extent, [[0.24, 0.30], [0.46, 0.30], [0.46, 0.68], [0.60, 0.68], [0.60, 0.80], [0.24, 0.80]], true)
	_line(origin, extent, [[0.54, 0.30], [0.76, 0.30], [0.76, 0.68], [0.90, 0.68], [0.90, 0.80], [0.54, 0.80]], true)


func _shield(origin: Vector2, extent: float) -> void:
	_line(origin, extent, [
		[0.50, 0.16], [0.80, 0.26], [0.76, 0.58], [0.50, 0.84], [0.24, 0.58], [0.20, 0.26],
	], true)
	draw_line(_p(origin, extent, 0.50, 0.26), _p(origin, extent, 0.50, 0.74), colour, line_width, true)


func _frame(origin: Vector2, extent: float) -> void:
	_outline_rect(origin, extent, 0.20, 0.20, 0.80, 0.80)
