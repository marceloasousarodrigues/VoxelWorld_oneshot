class_name GameHUD
extends CanvasLayer

## In-game interface: crosshair, hotbar with real block icons, a status readout
## and a transient message line.
##
## The HUD is presentation only.  It reads the inventory and is told what to
## display; it never mutates game state.

const SLOT_SIZE := 54
const SLOT_GAP := 6
const ICON_MARGIN := 5

var inventory: Inventory
var library: TextureLibrary

var _hotbar: HBoxContainer
var _slots: Array[Panel] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _status: Label
var _selected_label: Label
var _message: Label
var _hint: Label
var _debug: Label
var _crosshair: Control
var _message_timer := 0.0
var _debug_visible := true


func setup(player_inventory: Inventory, texture_library: TextureLibrary) -> void:
	inventory = player_inventory
	library = texture_library
	_build()
	inventory.changed.connect(refresh)
	refresh()


func _ready() -> void:
	if inventory != null and not inventory.changed.is_connected(refresh):
		inventory.changed.connect(refresh)
	if _slots.is_empty() and inventory != null:
		_build()
		refresh()


# --- construction --------------------------------------------------------

func _build() -> void:
	layer = 10
	_crosshair = _build_crosshair()
	_status = _build_label(Vector2(18, 14), 15, Color(1, 1, 1, 0.92))
	_hint = _build_label(Vector2.ZERO, 13, Color(1, 1, 1, 0.62))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 18
	_hint.offset_top = -52
	_hint.offset_right = 780
	_hint.offset_bottom = -14
	_message = _build_label(Vector2.ZERO, 18, Color(1, 1, 1, 0.95))
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_left = -420
	_message.offset_right = 420
	_message.offset_top = 92
	_message.offset_bottom = 122
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.visible = false
	_debug = _build_label(Vector2(18, 128), 13, Color(0.85, 0.95, 1.0, 0.78))
	_build_hotbar()


func _build_crosshair() -> Control:
	var root := Control.new()
	root.name = "Crosshair"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colour := Color(1, 1, 1, 0.85)
	var shadow := Color(0, 0, 0, 0.5)
	for entry: Array in [
		[Vector2(-11, -1), Vector2(22, 2), shadow],
		[Vector2(-1, -11), Vector2(2, 22), shadow],
		[Vector2(-10, -1), Vector2(20, 2), colour],
		[Vector2(-1, -10), Vector2(2, 20), colour],
	]:
		var line := ColorRect.new()
		line.color = entry[2]
		line.size = entry[1]
		line.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		line.offset_left = (entry[0] as Vector2).x
		line.offset_top = (entry[0] as Vector2).y
		line.offset_right = (entry[0] as Vector2).x + (entry[1] as Vector2).x
		line.offset_bottom = (entry[0] as Vector2).y + (entry[1] as Vector2).y
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(line)
	add_child(root)
	return root


func _build_label(at: Vector2, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _build_hotbar() -> void:
	var root := Control.new()
	root.name = "HotbarRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	root.offset_top = -(SLOT_SIZE + 34)
	root.offset_bottom = -18
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hotbar = HBoxContainer.new()
	_hotbar.name = "Hotbar"
	_hotbar.add_theme_constant_override("separation", SLOT_GAP)
	_hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hotbar.offset_left = -(Inventory.HOTBAR_SIZE * (SLOT_SIZE + SLOT_GAP)) * 0.5
	_hotbar.offset_right = (Inventory.HOTBAR_SIZE * (SLOT_SIZE + SLOT_GAP)) * 0.5
	_hotbar.offset_top = -SLOT_SIZE * 0.5
	_hotbar.offset_bottom = SLOT_SIZE * 0.5
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hotbar)
	_selected_label = _build_label(Vector2.ZERO, 15, Color(1, 1, 1, 0.95))
	_selected_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_selected_label.offset_left = -300
	_selected_label.offset_right = 300
	_selected_label.offset_top = -(SLOT_SIZE + 30)
	_selected_label.offset_bottom = -(SLOT_SIZE + 4)
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in Inventory.HOTBAR_SIZE:
		_build_slot(index)


func _build_slot(index: int) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.add_child(panel)
	_slots.append(panel)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = ICON_MARGIN
	icon.offset_top = ICON_MARGIN
	icon.offset_right = -ICON_MARGIN
	icon.offset_bottom = -ICON_MARGIN
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	_icons.append(icon)
	var count := Label.new()
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -20
	count.offset_top = -19
	count.offset_right = -3
	count.offset_bottom = -1
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", 13)
	count.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	count.add_theme_constant_override("shadow_offset_x", 1)
	count.add_theme_constant_override("shadow_offset_y", 1)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(count)
	_counts.append(count)


# --- state ---------------------------------------------------------------

func refresh() -> void:
	if inventory == null:
		return
	for index in Inventory.HOTBAR_SIZE:
		var panel := _slots[index]
		var block_id := inventory.slots[index]
		var count := inventory.counts[index]
		panel.add_theme_stylebox_override("panel", _slot_style(index == inventory.selected, block_id != BlockDB.AIR))
		_icons[index].texture = _icon_for(block_id)
		_icons[index].modulate = Color(1, 1, 1, 1.0 if block_id != BlockDB.AIR else 0.15)
		_counts[index].text = "" if count <= 1 else str(count)
	var selected_block := inventory.selected_block()
	_selected_label.text = "" if selected_block == BlockDB.AIR \
		else "%s   (slot %d)" % [BlockDB.name_of(selected_block), inventory.selected + 1]
	_hint.text = "WASD move  ·  Space jump  ·  Shift sprint  ·  LMB mine  ·  RMB build\n" \
		+ "1-9 select  ·  F fly  ·  F5 save  ·  F9 load  ·  F3 debug  ·  Esc pause"


func _icon_for(block_id: int) -> Texture2D:
	if block_id == BlockDB.AIR or library == null or block_id >= BlockDB.COUNT:
		return null
	var keys: PackedStringArray = BlockDB.face_keys[block_id]
	return library.icon(keys[BlockDB.FACE_PY])


func _slot_style(selected: bool, occupied: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.55 if occupied else 0.3)
	style.border_color = Color(1, 1, 1, 0.92) if selected else Color(1, 1, 1, 0.2)
	var width := 3 if selected else 1
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	return style


func set_status(text: String) -> void:
	_status.text = text


func set_debug(text: String) -> void:
	_debug.text = text


func toggle_debug() -> void:
	_debug_visible = not _debug_visible
	_debug.visible = _debug_visible
	_status.visible = _debug_visible


func debug_visible() -> bool:
	return _debug_visible


func flash(text: String, seconds: float = 2.4) -> void:
	_message.text = text
	_message.visible = true
	_message_timer = seconds


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		_message.modulate.a = clampf(_message_timer, 0.0, 1.0)
		if _message_timer <= 0.0:
			_message.visible = false
