class_name ItemCursor
extends Control

## The temporary stack held by the mouse while an interface is open.
##
## This is an interaction cursor, not a fourteenth inventory slot: it exists only
## while a panel is visible and its contents are owned by that panel.  The item
## actually held in the world is always `Inventory.selected_item()` in the hotbar.
## The control draws the stack under the pointer and never mutates a model.

var library: TextureLibrary
var stack: Dictionary = {}

var _slot: Panel
var _icon: TextureRect
var _count: Label


func setup(texture_library: TextureLibrary) -> void:
	library = texture_library
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100

	_slot = Panel.new()
	_slot.custom_minimum_size = Vector2(UiStyle.SLOT_SIZE, UiStyle.SLOT_SIZE)
	_slot.size = Vector2(UiStyle.SLOT_SIZE, UiStyle.SLOT_SIZE)
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_theme_stylebox_override("panel",
		UiStyle.slot_style(true, false, false))
	_slot.modulate = Color(1, 1, 1, 0.92)
	add_child(_slot)

	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = UiStyle.SLOT_ICON_MARGIN
	_icon.offset_top = UiStyle.SLOT_ICON_MARGIN
	_icon.offset_right = -UiStyle.SLOT_ICON_MARGIN
	_icon.offset_bottom = -UiStyle.SLOT_ICON_MARGIN
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(_icon)

	_count = Label.new()
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.offset_left = -26
	_count.offset_top = -24
	_count.offset_right = -4
	_count.offset_bottom = -2
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_size_override("font_size", 16)
	_count.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	_count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_count.add_theme_constant_override("shadow_offset_x", 1)
	_count.add_theme_constant_override("shadow_offset_y", 1)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(_count)
	_refresh()
	visible = false


func set_stack(value: Dictionary) -> void:
	stack = value.duplicate()
	_refresh()


func carried() -> Dictionary:
	return stack.duplicate()


func _refresh() -> void:
	if _slot == null:
		return
	var item_id := int(stack.get("item", BlockDB.AIR))
	var count := int(stack.get("count", 0))
	var empty := item_id == BlockDB.AIR or count <= 0
	visible = not empty
	if empty:
		return
	var key := ItemDB.icon_key(item_id)
	_icon.texture = library.icon(key) if library != null and not key.is_empty() else null
	_icon.modulate = ItemDB.icon_tint(item_id)
	_count.text = "" if count <= 1 else str(count)


func _process(_delta: float) -> void:
	if not visible or _slot == null:
		return
	# Draw slightly down-right of the pointer so the arrow never covers the
	# stack, and clamp to the viewport so it cannot disappear off-screen.
	var pointer := get_viewport().get_mouse_position()
	var limit := get_viewport_rect().size - _slot.size - Vector2(4, 4)
	_slot.global_position = Vector2(
		clampf(pointer.x + 14.0, 2.0, maxf(2.0, limit.x)),
		clampf(pointer.y + 10.0, 2.0, maxf(2.0, limit.y)))
