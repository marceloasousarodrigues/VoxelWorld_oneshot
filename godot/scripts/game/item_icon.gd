class_name ItemIcon
extends Control

## One item icon, drawn consistently everywhere (M40).
##
## Presentation only: the caller supplies an item id and the texture library, and
## this control decides *how* to draw it.  Item identity and gameplay mapping stay
## in `ItemDB` / `BlockDB`; nothing here reads or mutates a model.
##
## Blocks are drawn as the reference's small isometric cubes: the real top face
## and one real side texture, with restrained per-face lighting (top bright, left
## mid, right dark) and no extra effects.  Items that are not placeable blocks
## (tools, food, lumps, seeds, open-model plants) keep their existing transparent
## art with a soft shadow, so they stay recognisable at slot size.  The result is
## one lighting/perspective/padding rule for the whole inventory.

## Draw-time choices, exposed for tests/tools.
const CUBE_TOP_LIGHT := Color(1.0, 1.0, 1.0, 1.0)
const CUBE_LEFT_LIGHT := Color(0.72, 0.72, 0.72, 1.0)
const CUBE_RIGHT_LIGHT := Color(0.52, 0.52, 0.52, 1.0)
const FLAT_MARGIN := 2.0

var item_id := BlockDB.AIR
var library: TextureLibrary
var tint := Color.WHITE
var ghost := false
var error_outline := false

var _cube: Array[Polygon2D] = []
var _flat_root: Control
var _flat_shadow: TextureRect
var _flat_icon: TextureRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)


## Replaces the shown item.  `AIR` clears the icon.
func set_item(value: int, texture_library: TextureLibrary, item_tint: Color = Color.WHITE) -> void:
	item_id = value
	library = texture_library
	tint = item_tint
	_layout()


## Draws the icon dimmed/translucent (the crafting-result preview).
func set_ghost(value: bool) -> void:
	ghost = value
	_layout()


func is_cube() -> bool:
	return _cube.size() > 0 and _cube[0].visible


func _layout() -> void:
	var empty := item_id == BlockDB.AIR or item_id <= BlockDB.AIR
	if empty or library == null:
		_clear()
		return
	var key := ItemDB.icon_key(item_id)
	if key.is_empty():
		_clear()
		return
	if _is_cube_item(item_id):
		_build_cube(key)
	else:
		_build_flat(key)


## A block is drawn as a cube unless it is a non-solid decoration (a flower, a
## grass tuft) where the flat art is the recognisable silhouette.  Stations are
## solid blocks with real top/side textures, so they get the isometric treatment.
func _is_cube_item(value: int) -> bool:
	if not ItemDB.is_block(value):
		return false
	if value >= BlockDB.face_keys.size():
		return false
	if BlockDB.is_deco(value) or BlockDB.is_flower(value):
		return false
	return true


func _clear() -> void:
	for face: Polygon2D in _cube:
		face.visible = false
	if _flat_root != null:
		_flat_root.visible = false


# --- isometric block cube -------------------------------------------------

func _build_cube(_key: String) -> void:
	_hide_flat()
	var face_keys: PackedStringArray = BlockDB.face_keys[item_id]
	var top_texture := library.icon(str(face_keys[BlockDB.FACE_PY]))
	var side_key := str(face_keys[BlockDB.FACE_PZ])
	if side_key.is_empty():
		side_key = str(face_keys[BlockDB.FACE_PX])
	var side_texture := library.icon(side_key) if not side_key.is_empty() else top_texture
	if top_texture == null and side_texture == null:
		_clear()
		return
	if top_texture == null:
		top_texture = side_texture
	if side_texture == null:
		side_texture = top_texture
	_ensure_cube_faces()
	var scale := minf(size.x, size.y)
	if scale <= 0.0:
		return
	var left := (size.x - scale) * 0.5
	var top := (size.y - scale) * 0.5
	# The three visible faces of a cube seen from just above a corner.
	var peak := Vector2(left + scale * 0.50, top + scale * 0.06)
	var right := Vector2(left + scale * 0.96, top + scale * 0.30)
	var bottom_peak := Vector2(left + scale * 0.50, top + scale * 0.54)
	var left_corner := Vector2(left + scale * 0.04, top + scale * 0.30)
	var bottom_right := Vector2(left + scale * 0.96, top + scale * 0.76)
	var bottom_left := Vector2(left + scale * 0.04, top + scale * 0.76)
	var bottom_mid := Vector2(left + scale * 0.50, top + scale * 0.98)
	_set_face(0, PackedVector2Array([peak, right, bottom_peak, left_corner]), top_texture, CUBE_TOP_LIGHT)
	_set_face(1, PackedVector2Array([left_corner, bottom_peak, bottom_mid, bottom_left]), side_texture, CUBE_LEFT_LIGHT)
	_set_face(2, PackedVector2Array([bottom_peak, right, bottom_right, bottom_mid]), side_texture, CUBE_RIGHT_LIGHT)


func _ensure_cube_faces() -> void:
	if not _cube.is_empty():
		return
	for index in 3:
		var face := Polygon2D.new()
		face.name = "CubeFace%d" % index
		face.antialiased = true
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(face)
		_cube.append(face)


func _set_face(index: int, points: PackedVector2Array, texture: Texture2D,
		light: Color) -> void:
	if index < 0 or index >= _cube.size():
		return
	var face := _cube[index]
	face.visible = true
	face.polygon = points
	face.texture = texture
	face.uv = _face_uv(texture)
	var alpha := 0.95 if ghost else 1.0
	face.modulate = Color(light.r * tint.r, light.g * tint.g, light.b * tint.b, alpha)


func _face_uv(texture: Texture2D) -> PackedVector2Array:
	var extent := texture.get_size()
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(extent.x, 0.0),
		Vector2(extent.x, extent.y), Vector2(0.0, extent.y),
	])


# --- flat item art --------------------------------------------------------

func _build_flat(key: String) -> void:
	_hide_cube()
	if _flat_root == null:
		_build_flat_nodes()
	_flat_root.visible = true
	var texture := library.icon(key)
	_flat_icon.texture = texture
	_flat_shadow.texture = texture
	var alpha := 0.95 if ghost else 1.0
	_flat_icon.modulate = Color(tint.r, tint.g, tint.b, alpha)
	_flat_shadow.modulate = Color(0.0, 0.0, 0.0, 0.30 if not ghost else 0.12)


func _build_flat_nodes() -> void:
	_flat_root = Control.new()
	_flat_root.name = "FlatIcon"
	_flat_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flat_root)
	_flat_shadow = TextureRect.new()
	_flat_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flat_shadow.offset_left = FLAT_MARGIN + 1.0
	_flat_shadow.offset_top = FLAT_MARGIN + 2.0
	_flat_shadow.offset_right = -FLAT_MARGIN + 1.0
	_flat_shadow.offset_bottom = -FLAT_MARGIN + 2.0
	_flat_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flat_shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flat_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flat_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flat_root.add_child(_flat_shadow)
	_flat_icon = TextureRect.new()
	_flat_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flat_icon.offset_left = FLAT_MARGIN
	_flat_icon.offset_top = FLAT_MARGIN
	_flat_icon.offset_right = -FLAT_MARGIN
	_flat_icon.offset_bottom = -FLAT_MARGIN
	_flat_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flat_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flat_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flat_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flat_root.add_child(_flat_icon)


func _hide_cube() -> void:
	for face: Polygon2D in _cube:
		face.visible = false


func _hide_flat() -> void:
	if _flat_root != null:
		_flat_root.visible = false
