class_name InventorySlot
extends Panel

## One slot of the inventory interface.
##
## It draws its own item (icon, count, durability), reports a click as intent, and
## implements Godot's drag & drop source and target.  Every mutation is delegated
## to `Inventory`; the slot itself never changes a stack.

signal clicked(index: int)
## Emitted when a stack was dragged from one slot onto another.
signal stack_moved(from: int, to: int)

const SIZE := 64
const ICON_MARGIN := 7

var index := -1
var inventory: Inventory
var library: TextureLibrary
var selected := false
## When set, the slot draws this stack instead of reading the model.  The
## inventory panel's "carrying" slot uses it: a carried stack has left the
## inventory, so there is no slot to read it from.
var override_stack: Dictionary = {}

var _icon: TextureRect
var _count: Label
var _wear: ColorRect
var _number: Label
var _style_selected := false


func configure(slot_index: int, player_inventory: Inventory, texture_library: TextureLibrary) -> void:
	index = slot_index
	inventory = player_inventory
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
	_count.add_theme_font_size_override("font_size", 16)
	_count.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_count.add_theme_constant_override("shadow_offset_x", 1)
	_count.add_theme_constant_override("shadow_offset_y", 1)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	_number = Label.new()
	_number.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_number.offset_left = 5
	_number.offset_top = 2
	_number.add_theme_font_size_override("font_size", 11)
	_number.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_number.text = str(index + 1)
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_number)
	_wear = ColorRect.new()
	_wear.color = Color(0.42, 0.88, 0.45, 0.95)
	_wear.position = Vector2(ICON_MARGIN, SIZE - 10)
	_wear.size = Vector2(SIZE - ICON_MARGIN * 2, 4)
	_wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wear.visible = false
	add_child(_wear)
	refresh()


func refresh() -> void:
	if inventory == null:
		return
	var carrying := not override_stack.is_empty()
	if index < 0 and not carrying:
		visible = false
		return
	var item_id := inventory.slots[index] if not carrying else int(override_stack["item"])
	var count := inventory.counts[index] if not carrying else int(override_stack["count"])
	var wear_value := inventory.durability_of(index) if not carrying else int(override_stack.get("durability", 0))
	var empty := inventory.is_empty(index) if not carrying else false
	add_theme_stylebox_override("panel", _slot_style(selected, not empty))
	_icon.texture = null if empty or library == null else library.icon(ItemDB.icon_key(item_id))
	var tint := ItemDB.icon_tint(item_id)
	_icon.modulate = Color(tint.r, tint.g, tint.b, 0.2 if empty else 1.0)
	_count.text = "" if count <= 1 else str(count)
	var maximum := ItemDB.max_durability(item_id)
	if maximum <= 0 or empty:
		_wear.visible = false
	else:
		var ratio := clampf(float(wear_value) / float(maximum), 0.0, 1.0)
		_wear.visible = true
		_wear.size.x = maxf(0.0, (SIZE - ICON_MARGIN * 2) * ratio)
		_wear.color = Color(0.42, 0.88, 0.45, 0.95) if ratio > 0.35 \
			else (Color(0.95, 0.78, 0.25, 0.95) if ratio > 0.15 else Color(0.92, 0.30, 0.26, 0.95))
	_number.add_theme_color_override("font_color",
		Color(1, 1, 1, 0.85) if selected else Color(1, 1, 1, 0.45))
	_number.visible = index >= 0


func _slot_style(is_selected: bool, occupied: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.78 if occupied else 0.45)
	style.border_color = Color(1, 0.92, 0.6, 0.95) if is_selected else Color(1, 1, 1, 0.22)
	style.set_border_width_all(3 if is_selected else 1)
	style.set_corner_radius_all(5)
	return style


# --- input ---------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			clicked.emit(index)


func _get_drag_data(_position: Vector2) -> Variant:
	if inventory == null or inventory.is_empty(index):
		return null
	var item_id := inventory.slots[index]
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
	# The stack stays in the inventory while it is dragged; the drop performs the
	# move, so cancelling a drag can never lose an item.
	return {"from": index}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload := data as Dictionary
	return payload.has("from") and int(payload["from"]) != index


func _drop_data(_position: Vector2, data: Variant) -> void:
	var payload := data as Dictionary
	stack_moved.emit(int(payload["from"]), index)
