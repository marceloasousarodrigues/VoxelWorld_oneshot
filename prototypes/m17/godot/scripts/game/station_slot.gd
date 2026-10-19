class_name StationSlot
extends Panel

## One slot of a station interface (M19).
##
## The same control draws either a player `Inventory` slot or a `StationInventory`
## slot: both expose `slots`, `counts`, `durability_of()` and `is_empty()`, so the
## presentation never needs to know which model it is looking at.  It reports
## intent (`clicked`, `quick_moved`, drag & drop) and never mutates a model.
##
## A slot may show a `ghost` stack instead: the crafting table's result preview
## uses this to show what the current grid would make before the player commits.

signal clicked(side: String, index: int, button: int, shift: bool)
signal stack_moved(from_side: String, from_index: int, to_side: String, to_index: int)

const SIZE := 58
const ICON_MARGIN := 6

var side := "player"
var index := -1
## `Inventory` (player) or `StationInventory` (station).
var model: Variant
var library: TextureLibrary
var selected := false
## Text drawn in the top-left corner (e.g. "input", "fuel").  Empty hides it.
var caption := ""
## A stack to draw instead of reading the model (the result preview and the
## interface's "carrying" slot).
var override_stack: Dictionary = {}
## Draw the override as a translucent preview rather than a real stack.
var ghost := false

var _icon: TextureRect
var _count: Label
var _wear: ColorRect
var _caption: Label
var _number: Label


func configure(slot_side: String, slot_index: int, slot_model: Variant,
		texture_library: TextureLibrary) -> void:
	side = slot_side
	index = slot_index
	model = slot_model
	library = texture_library
	_build()


func _build() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = ICON_MARGIN
	_icon.offset_top = ICON_MARGIN
	_icon.offset_right = -ICON_MARGIN
	_icon.offset_bottom = -ICON_MARGIN
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_count = Label.new()
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.offset_left = -26
	_count.offset_top = -24
	_count.offset_right = -4
	_count.offset_bottom = -2
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_size_override("font_size", 15)
	_count.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_count.add_theme_constant_override("shadow_offset_x", 1)
	_count.add_theme_constant_override("shadow_offset_y", 1)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)

	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_caption.offset_left = 5
	_caption.offset_top = 2
	_caption.add_theme_font_size_override("font_size", 10)
	_caption.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92, 0.72))
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	_number = Label.new()
	_number.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_number.offset_left = 5
	_number.offset_bottom = -2
	_number.add_theme_font_size_override("font_size", 10)
	_number.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	_number.text = str(index + 1) if side == "player" else ""
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_number)

	_wear = ColorRect.new()
	_wear.color = Color(0.42, 0.88, 0.45, 0.95)
	_wear.position = Vector2(ICON_MARGIN, SIZE - 9)
	_wear.size = Vector2(SIZE - ICON_MARGIN * 2, 4)
	_wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wear.visible = false
	add_child(_wear)
	refresh()


func refresh() -> void:
	if model == null:
		return
	var preview := not override_stack.is_empty()
	var item_id: int = int(override_stack["item"]) if preview else int(model.item_at(index))
	var count: int = int(override_stack["count"]) if preview else int(model.count_at(index))
	var wear_value: int = int(override_stack.get("durability", 0)) if preview \
		else int(model.durability_of(index))
	var empty: bool = item_id == BlockDB.AIR or count <= 0
	add_theme_stylebox_override("panel", _slot_style(selected, not empty and not ghost))
	_icon.texture = null if empty or library == null else library.icon(ItemDB.icon_key(item_id))
	var tint := ItemDB.icon_tint(item_id)
	var alpha := 0.15
	if not empty:
		alpha = 0.42 if ghost else 1.0
	_icon.modulate = Color(tint.r, tint.g, tint.b, alpha)
	_count.text = "" if count <= 1 else str(count)
	_caption.text = caption
	_caption.visible = not caption.is_empty()
	tooltip_text = "" if empty else "%s ×%d" % [ItemDB.name_of(item_id), count]
	var maximum := ItemDB.max_durability(item_id)
	if maximum <= 0 or empty or ghost:
		_wear.visible = false
	else:
		var ratio := clampf(float(wear_value) / float(maximum), 0.0, 1.0)
		_wear.visible = true
		_wear.size.x = maxf(0.0, (SIZE - ICON_MARGIN * 2) * ratio)
		_wear.color = Color(0.42, 0.88, 0.45, 0.95) if ratio > 0.35 \
			else (Color(0.95, 0.78, 0.25, 0.95) if ratio > 0.15 else Color(0.92, 0.30, 0.26, 0.95))


func _slot_style(is_selected: bool, occupied: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.8 if occupied else 0.45)
	if ghost:
		style.bg_color = Color(0.12, 0.14, 0.1, 0.55)
	style.border_color = Color(1, 0.92, 0.6, 0.95) if is_selected else Color(1, 1, 1, 0.22)
	style.set_border_width_all(3 if is_selected else 1)
	style.set_corner_radius_all(5)
	return style


# --- input ---------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and (button.button_index == MOUSE_BUTTON_LEFT \
				or button.button_index == MOUSE_BUTTON_RIGHT):
			clicked.emit(side, index, button.button_index, button.shift_pressed)


func _get_drag_data(_position: Vector2) -> Variant:
	if model == null or model.is_empty(index) or ghost:
		return null
	var item_id: int = model.item_at(index)
	var preview := Panel.new()
	preview.custom_minimum_size = Vector2(SIZE, SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.9)
	style.set_corner_radius_all(5)
	preview.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.texture = library.icon(ItemDB.icon_key(item_id)) if library != null else null
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(icon)
	set_drag_preview(preview)
	# The stack stays in its model while it is dragged; the drop performs the
	# move, so cancelling a drag can never lose an item.
	return {"side": side, "index": index}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload := data as Dictionary
	return payload.has("side") and not (payload["side"] == side and int(payload["index"]) == index)


func _drop_data(_position: Vector2, data: Variant) -> void:
	var payload := data as Dictionary
	stack_moved.emit(str(payload["side"]), int(payload["index"]), side, index)
