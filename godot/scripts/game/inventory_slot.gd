class_name InventorySlot
extends Panel

## One slot of the player inventory interface.
##
## It draws its own item (icon, count, durability), reports a click as intent, and
## implements Godot's drag & drop source and target.  Every mutation is delegated
## to `Inventory`; the slot itself never changes a stack.
##
## The slot is deliberately generic enough for both the hotbar row and the main
## grid: `index` addresses the model, `compact` only changes the number badge, and
## `slot_size` lets the M40 screen use a denser grid than the default panel.

signal clicked(index: int, button: int, shift: bool)
## Emitted when a stack was dragged from one slot onto another.
signal stack_moved(from: int, to: int)
signal hovered(index: int)

const SIZE := UiStyle.SLOT_SIZE
const ICON_MARGIN := UiStyle.SLOT_ICON_MARGIN

var index := -1
var inventory: Inventory
var library: TextureLibrary
var selected := false
## When set, the slot draws this stack instead of reading the model.  Used only
## by tests/diagnostics now; the real cursor stack is drawn by `ItemCursor`.
var override_stack: Dictionary = {}
## Hide the little slot-number badge (the main 3x3 grid does not need it).
var show_number := true
## Slot edge length; the M40 screen uses `UiStyle.SCREEN_SLOT` for its grid.
var slot_size := SIZE

var _icon: ItemIcon
var _count: Label
var _wear: ColorRect
var _number: Label
var _hovered := false


func configure(slot_index: int, player_inventory: Inventory, texture_library: TextureLibrary,
		size_override: int = 0) -> void:
	index = slot_index
	inventory = player_inventory
	library = texture_library
	if size_override > 0:
		slot_size = size_override
	_build()


func _build() -> void:
	custom_minimum_size = Vector2(slot_size, slot_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icon = ItemIcon.new()
	_icon.name = "Icon"
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = ICON_MARGIN
	_icon.offset_top = ICON_MARGIN
	_icon.offset_right = -ICON_MARGIN
	_icon.offset_bottom = -ICON_MARGIN
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
	_number.add_theme_font_size_override("font_size", 10)
	_number.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_number)
	_wear = ColorRect.new()
	_wear.color = Color(0.42, 0.88, 0.45, 0.95)
	_wear.position = Vector2(ICON_MARGIN, slot_size - 10)
	_wear.size = Vector2(slot_size - ICON_MARGIN * 2, 4)
	_wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wear.visible = false
	add_child(_wear)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	refresh()


func refresh() -> void:
	if inventory == null:
		return
	var carrying := not override_stack.is_empty()
	var item_id := int(override_stack["item"]) if carrying else inventory.item_at(index)
	var count := int(override_stack["count"]) if carrying else inventory.count_at(index)
	var wear_value := int(override_stack.get("durability", 0)) if carrying else inventory.durability_of(index)
	var empty := item_id == BlockDB.AIR or count <= 0
	add_theme_stylebox_override("panel", UiStyle.slot_style(not empty, selected, false, _hovered))
	_icon.set_item(BlockDB.AIR if empty else item_id, library, ItemDB.icon_tint(item_id))
	_count.text = "" if count <= 1 else str(count)
	tooltip_text = _tooltip(item_id, count, wear_value) if not empty else ""
	var maximum := ItemDB.max_durability(item_id)
	if maximum <= 0 or empty:
		_wear.visible = false
	else:
		var ratio := clampf(float(wear_value) / float(maximum), 0.0, 1.0)
		_wear.visible = true
		_wear.size.x = maxf(0.0, (slot_size - ICON_MARGIN * 2) * ratio)
		_wear.color = Color(0.42, 0.88, 0.45, 0.95) if ratio > 0.35 \
			else (Color(0.95, 0.78, 0.25, 0.95) if ratio > 0.15 else Color(0.92, 0.30, 0.26, 0.95))
	_number.visible = show_number
	if show_number:
		_number.text = str(index + 1)
		_number.add_theme_color_override("font_color",
			Color(1, 1, 1, 0.9) if selected else Color(1, 1, 1, 0.42))


func _tooltip(item_id: int, count: int, wear_value: int) -> String:
	var lines: Array = ["%s ×%d" % [ItemDB.name_of(item_id), count]]
	if ItemDB.is_tool_item(item_id):
		lines.append("%s tool · %d / %d durability" % [
			ItemDB.tier_name(ItemDB.tier(item_id)),
			wear_value, ItemDB.max_durability(item_id)])
	elif ItemDB.is_food(item_id):
		lines.append("Food · +%d hunger" % int(ItemDB.food_value(item_id)))
	elif ItemDB.is_block(item_id):
		lines.append("Block · %s" % ("placeable" if ItemDB.is_block(item_id) else "material"))
	else:
		lines.append("Material")
	lines.append("Stack cap %d" % ItemDB.max_stack(item_id))
	return "\n".join(lines)


# --- input ---------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and (button.button_index == MOUSE_BUTTON_LEFT \
				or button.button_index == MOUSE_BUTTON_RIGHT):
			clicked.emit(index, button.button_index, button.shift_pressed)


func _on_mouse_entered() -> void:
	_hovered = true
	hovered.emit(index)
	if inventory != null:
		refresh()


func _on_mouse_exited() -> void:
	_hovered = false
	if inventory != null:
		refresh()


func _get_drag_data(_position: Vector2) -> Variant:
	if inventory == null or inventory.is_empty(index):
		return null
	var item_id := inventory.item_at(index)
	var preview := Panel.new()
	preview.custom_minimum_size = Vector2(slot_size, slot_size)
	preview.add_theme_stylebox_override("panel", UiStyle.slot_style(true))
	var icon := ItemIcon.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = ICON_MARGIN
	icon.offset_top = ICON_MARGIN
	icon.offset_right = -ICON_MARGIN
	icon.offset_bottom = -ICON_MARGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(icon)
	icon.set_item(item_id, library, ItemDB.icon_tint(item_id))
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
