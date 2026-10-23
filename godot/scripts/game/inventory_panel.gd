class_name InventoryPanel
extends Control

## The M40 inventory experience: navigation, player/equipment panel, the real
## 27+9 inventory, a 3x3 crafting grid with station gating, a hotbar and the
## health/hunger readout, in one full-screen interface.
##
## Presentation and intent only: every mutation goes through `Inventory`, and the
## grid uses the real `Station` crafting transaction, so the interface can never
## invent state and no recipe logic is duplicated here.  A temporary cursor stack
## is owned by this panel and is recovered into a model before closing/saving.
##
## The equipment slots are deliberately presentational: VoxelWorld has no
## equipment system, so they are disabled rather than filled with invented armour.
## Nothing here displays experience or level values for the same reason.

signal changed_stack(item_id: int)
signal message(text: String)
signal crafted(result: Dictionary)
## Navigation to another existing screen ("crafting", "settings").
signal navigate(target: String)
## The panel really opened / really closed (used by the game to hide the HUD).
signal opened()
signal closed()

const PAGE_INVENTORY := "inventory"
const PAGE_CHARACTER := "character"
const NAV_TARGETS := ["inventory", "crafting", "character", "map", "settings"]
const NAV_LABELS := {
	"inventory": "Inventory", "crafting": "Crafting", "character": "Character",
	"map": "Map", "settings": "Settings",
}
const NAV_GLYPHS := {
	"inventory": "inventory", "crafting": "crafting", "character": "character",
	"map": "map", "settings": "settings",
}
const CRAFT_GRID := Station.TABLE_GRID_SLOTS
const CRAFT_OUTPUT := Station.TABLE_OUTPUT_SLOT
const SLOT := UiStyle.SCREEN_SLOT
const GRID_GAP := 5
const DETAIL_MIN_HEIGHT := 240

var inventory: Inventory
var library: TextureLibrary

var _craft: Station
var _station := Crafting.STATION_HAND
var _page := PAGE_INVENTORY
var _active_tab := "inventory"

var _slots: Array[InventorySlot] = []
var _craft_slots: Array[StationSlot] = []
var _equipment_slots: Array[Control] = []
var _tabs: Dictionary = {}
var _detail: Label
var _hint: Label
var _cursor: ItemCursor
var _carried: Dictionary = {}
var _carry_origin := -1
var _focus_index := 0

var _inventory_page: Control
var _character_page: Control
var _player_panel: Control
var _craft_panel: Control
var _held_icon: ItemIcon
var _held_label: Label
var _character_icon: ItemIcon
var _character_held: Label
var _character_vitals: Label
var _vitals: VitalsBar
var _craft_status: Label
var _craft_table_label: Label
var _craft_button: Button
var _output_slot: StationSlot
var _storage_label: Label


func setup(player_inventory: Inventory, texture_library: TextureLibrary = null) -> void:
	inventory = player_inventory
	library = texture_library
	_craft = Station.new(Station.TABLE)
	_build()
	if inventory != null and not inventory.changed.is_connected(_refresh):
		inventory.changed.connect(_refresh)
	if not _craft.inventory.changed.is_connected(_refresh_craft):
		_craft.inventory.changed.connect(_refresh_craft)
	visible = false
	_refresh()


# =========================================================================
# Construction
# =========================================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = UiStyle.SCREEN_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var margin := MarginContainer.new()
	margin.name = "ScreenMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "ScreenColumn"
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	column.add_child(_build_nav())

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 12)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_player_panel = _build_player_panel()
	body.add_child(_player_panel)
	_inventory_page = _build_inventory_page()
	body.add_child(_inventory_page)
	_character_page = _build_character_page()
	body.add_child(_character_page)
	_craft_panel = _build_craft_panel()
	body.add_child(_craft_panel)

	column.add_child(_build_bottom())

	_cursor = ItemCursor.new()
	_cursor.name = "CursorStack"
	add_child(_cursor)
	_cursor.setup(library)
	_refresh_nav()


func _build_nav() -> Control:
	var wrap := CenterContainer.new()
	wrap.name = "NavWrap"
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := PanelContainer.new()
	bar.name = "Nav"
	bar.add_theme_stylebox_override("panel", UiStyle.nav_style())
	bar.custom_minimum_size = Vector2(760, 0)
	wrap.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(row)
	row.add_child(_keycap("I"))
	for target: String in NAV_TARGETS:
		row.add_child(_tab(target))
	row.add_child(_keycap("Esc"))
	return wrap


func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(30, 30)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_theme_stylebox_override("panel", UiStyle.keycap_style())
	var label := _label(text, 12, UiStyle.TEXT_SECONDARY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(label)
	return cap


func _tab(target: String) -> Button:
	var button := Button.new()
	button.name = "Tab_%s" % target
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(124, 38)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not nav_enabled(target):
		button.tooltip_text = "Map is not available yet"
		button.disabled = true
	button.pressed.connect(func() -> void: press_nav(target))
	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 7)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var icon := NavIcon.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.setup(str(NAV_GLYPHS[target]), UiStyle.TEXT_MUTED)
	content.add_child(icon)
	var label := _label(str(NAV_LABELS[target]), 14, UiStyle.TEXT_MUTED)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(label)
	_tabs[target] = {"button": button, "icon": icon, "label": label}
	return button


func _build_player_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "PlayerPanel"
	panel.custom_minimum_size = Vector2(272, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.screen_panel_style())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	var title := _label("Player", 21, UiStyle.TEXT_PRIMARY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var survivor := _label("Survivor", 11, UiStyle.TEXT_MUTED)
	survivor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	survivor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(survivor)
	column.add_child(title_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	var armour := VBoxContainer.new()
	armour.name = "Equipment"
	armour.add_theme_constant_override("separation", 6)
	armour.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for entry: Array in [["helmet", "Helmet"], ["chestplate", "Chestplate"],
			["leggings", "Leggings"], ["boots", "Boots"]]:
		armour.add_child(_equipment_slot(str(entry[0]), str(entry[1])))
	row.add_child(armour)

	var preview := CharacterPreview.new()
	preview.name = "CharacterPreview"
	preview.setup()
	preview.custom_minimum_size = Vector2(140, 236)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(preview)

	var offhand := VBoxContainer.new()
	offhand.add_theme_constant_override("separation", 6)
	offhand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	offhand.add_child(_equipment_slot("shield", "Off Hand"))
	offhand.add_child(_equipment_slot("shield", "Second Off Hand"))
	row.add_child(offhand)

	var held_row := HBoxContainer.new()
	held_row.add_theme_constant_override("separation", 7)
	_held_icon = ItemIcon.new()
	_held_icon.custom_minimum_size = Vector2(26, 26)
	_held_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	held_row.add_child(_held_icon)
	_held_label = _label("", 12, UiStyle.TEXT_SECONDARY)
	_held_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_held_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	held_row.add_child(_held_label)
	column.add_child(held_row)

	var note := _label("Equipment slots are display-only: VoxelWorld has no equipment system yet.",
		10, UiStyle.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(230, 0)
	column.add_child(note)
	return panel


func _equipment_slot(glyph: String, label_text: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Equipment_%s" % glyph
	slot.custom_minimum_size = Vector2(42, 42)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.add_theme_stylebox_override("panel", UiStyle.slot_style(false, false, true))
	slot.tooltip_text = "%s — equipment is not implemented in VoxelWorld yet" % label_text
	var icon := NavIcon.new()
	icon.setup(glyph, Color(0.56, 0.66, 0.80, 0.42), 1.5)
	slot.add_child(icon)
	_equipment_slots.append(slot)
	return slot


func _build_inventory_page() -> Control:
	var panel := PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.custom_minimum_size = Vector2(500, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.screen_panel_style(true))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var header := HBoxContainer.new()
	var title := _label("Inventory", 21, UiStyle.TEXT_PRIMARY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_storage_label = _label("", 11, UiStyle.TEXT_MUTED)
	_storage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_storage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_storage_label)
	column.add_child(header)

	var grid := GridContainer.new()
	grid.name = "MainSlots"
	grid.columns = Inventory.HOTBAR_SIZE
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	column.add_child(grid)
	for index in range(Inventory.MAIN_FIRST, Inventory.SIZE):
		var slot := _make_slot(index, grid, SLOT, false)
		slot.show_number = false

	var rule := ColorRect.new()
	rule.color = Color(0.62, 0.74, 0.90, 0.14)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	var detail_box := PanelContainer.new()
	detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.custom_minimum_size = Vector2(0, DETAIL_MIN_HEIGHT)
	detail_box.add_theme_stylebox_override("panel", UiStyle.screen_subpanel_style())
	column.add_child(detail_box)
	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 4)
	detail_box.add_child(detail_column)
	var detail_title := _label("ITEM", 10, UiStyle.TEXT_MUTED)
	detail_column.add_child(detail_title)
	_detail = _label("", 12, Color(0.88, 0.93, 0.99))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(_detail)
	return panel


func _build_character_page() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CharacterPage"
	panel.custom_minimum_size = Vector2(620, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.screen_panel_style(true))
	panel.visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var title := _label("Character", 21, UiStyle.TEXT_PRIMARY)
	column.add_child(title)
	var subtitle := _label("Survivor", 14, UiStyle.TEXT_SECONDARY)
	column.add_child(subtitle)

	var vitals_box := PanelContainer.new()
	vitals_box.add_theme_stylebox_override("panel", UiStyle.screen_subpanel_style())
	column.add_child(vitals_box)
	var vitals_column := VBoxContainer.new()
	vitals_column.add_theme_constant_override("separation", 6)
	vitals_box.add_child(vitals_column)
	vitals_column.add_child(_label("VITALS", 10, UiStyle.TEXT_MUTED))
	_character_vitals = _label("", 14, UiStyle.TEXT_PRIMARY)
	vitals_column.add_child(_character_vitals)
	var vitals_note := _label(
		"Health and hunger are the game's own survival values. VoxelWorld does not "
		+ "implement experience or levels, so none are shown.",
		11, UiStyle.TEXT_MUTED)
	vitals_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vitals_note.custom_minimum_size = Vector2(440, 0)
	vitals_column.add_child(vitals_note)

	var held_box := PanelContainer.new()
	held_box.add_theme_stylebox_override("panel", UiStyle.screen_subpanel_style())
	column.add_child(held_box)
	var held_row := HBoxContainer.new()
	held_row.add_theme_constant_override("separation", 10)
	held_box.add_child(held_row)
	_character_icon = ItemIcon.new()
	_character_icon.custom_minimum_size = Vector2(40, 40)
	held_row.add_child(_character_icon)
	var held_column := VBoxContainer.new()
	held_column.add_theme_constant_override("separation", 2)
	held_row.add_child(held_column)
	held_column.add_child(_label("HELD ITEM", 10, UiStyle.TEXT_MUTED))
	_character_held = _label("", 14, UiStyle.TEXT_PRIMARY)
	held_column.add_child(_character_held)

	var equipment_box := PanelContainer.new()
	equipment_box.add_theme_stylebox_override("panel", UiStyle.screen_subpanel_style())
	column.add_child(equipment_box)
	var equipment_column := VBoxContainer.new()
	equipment_column.add_theme_constant_override("separation", 6)
	equipment_box.add_child(equipment_column)
	equipment_column.add_child(_label("EQUIPMENT", 10, UiStyle.TEXT_MUTED))
	var equipment_note := _label(
		"VoxelWorld does not define armour or off-hand gameplay yet. The player "
		+ "panel presents the six slots as unavailable rather than inventing items.",
		11, UiStyle.TEXT_MUTED)
	equipment_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_note.custom_minimum_size = Vector2(440, 0)
	equipment_column.add_child(equipment_note)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var note := _label("Held item, health and hunger update from the live game.", 11, UiStyle.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	return panel


func _build_craft_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CraftingPanel"
	panel.custom_minimum_size = Vector2(306, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.screen_panel_style())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(_label("Crafting", 21, UiStyle.TEXT_PRIMARY))

	var grid_row := HBoxContainer.new()
	grid_row.add_theme_constant_override("separation", 10)
	grid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(grid_row)
	var grid := GridContainer.new()
	grid.name = "CraftGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	grid_row.add_child(grid)
	for index in CRAFT_GRID:
		var slot := StationSlot.new()
		slot.name = "CraftSlot%d" % index
		slot.configure("craft", index, _craft.inventory, library, SLOT)
		slot.clicked.connect(_on_craft_slot_clicked)
		slot.stack_moved.connect(_on_craft_stack_moved)
		grid.add_child(slot)
		_craft_slots.append(slot)

	_craft_button = Button.new()
	_craft_button.name = "CraftArrow"
	_craft_button.text = "→"
	_craft_button.tooltip_text = "Craft the matching recipe"
	_craft_button.focus_mode = Control.FOCUS_NONE
	_craft_button.custom_minimum_size = Vector2(34, SLOT)
	_craft_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_craft_button.add_theme_font_size_override("font_size", 22)
	_craft_button.add_theme_color_override("font_color", UiStyle.ACCENT_BLUE)
	_craft_button.add_theme_stylebox_override("normal", _arrow_style(false))
	_craft_button.add_theme_stylebox_override("hover", _arrow_style(true))
	_craft_button.add_theme_stylebox_override("pressed", _arrow_style(true))
	_craft_button.add_theme_stylebox_override("disabled", _arrow_style(false))
	_craft_button.pressed.connect(craft_press)
	grid_row.add_child(_craft_button)

	_output_slot = StationSlot.new()
	_output_slot.name = "CraftOutput"
	_output_slot.configure("craft", CRAFT_OUTPUT, _craft.inventory, library, SLOT)
	_output_slot.draggable = false
	_output_slot.tooltip_text = "Crafted result — click to take, Shift-click to send to the inventory"
	_output_slot.clicked.connect(_on_craft_slot_clicked)
	grid_row.add_child(_output_slot)
	_craft_slots.append(_output_slot)

	_craft_status = _label("", 12, UiStyle.TEXT_SECONDARY)
	_craft_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_status.custom_minimum_size = Vector2(0, 34)
	column.add_child(_craft_status)

	var table_box := PanelContainer.new()
	table_box.add_theme_stylebox_override("panel", UiStyle.screen_subpanel_style())
	column.add_child(table_box)
	var table_row := HBoxContainer.new()
	table_row.add_theme_constant_override("separation", 10)
	table_box.add_child(table_row)
	var table_icon := ItemIcon.new()
	table_icon.custom_minimum_size = Vector2(38, 38)
	table_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	table_icon.set_item(BlockDB.CRAFTING_TABLE, library)
	table_row.add_child(table_icon)
	var table_column := VBoxContainer.new()
	table_column.add_theme_constant_override("separation", 3)
	table_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_row.add_child(table_column)
	table_column.add_child(_label("Crafting Table", 13, UiStyle.TEXT_PRIMARY))
	_craft_table_label = _label("", 11, UiStyle.TEXT_SECONDARY)
	_craft_table_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	table_column.add_child(_craft_table_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var tip := _label("The grid uses the game's real recipes. Table recipes need a crafting table nearby.",
		10, UiStyle.TEXT_MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tip)
	return panel


func _arrow_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.20, 0.32, 0.85) if hovered else Color(0.06, 0.10, 0.15, 0.0)
	style.border_color = Color(0.40, 0.68, 1.0, 0.9) if hovered else Color(0, 0, 0, 0)
	style.set_border_width_all(1 if hovered else 0)
	style.set_corner_radius_all(6)
	return style


func _build_bottom() -> Control:
	var bottom := Control.new()
	bottom.name = "Bottom"
	bottom.custom_minimum_size = Vector2(0, 132)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.name = "HotbarCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	center.offset_top = -126
	center.offset_bottom = -45
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(center)
	var strip := PanelContainer.new()
	strip.name = "HotbarStrip"
	strip.add_theme_stylebox_override("panel", UiStyle.hotbar_style())
	center.add_child(strip)
	var hotbar := HBoxContainer.new()
	hotbar.name = "HotbarSlots"
	hotbar.add_theme_constant_override("separation", 6)
	hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_child(hotbar)
	for index in Inventory.HOTBAR_SIZE:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		hotbar.add_child(cell)
		var slot := _make_slot(index, cell, UiStyle.SLOT_SIZE, false)
		slot.custom_minimum_size = Vector2(UiStyle.SLOT_SIZE, UiStyle.SLOT_SIZE)
		var number := _label(str(index + 1), 11, UiStyle.TEXT_MUTED)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(number)

	_vitals = VitalsBar.new()
	_vitals.name = "Vitals"
	_vitals.setup(library)
	_vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_vitals.offset_left = 4
	_vitals.offset_top = -42
	_vitals.offset_right = 4 + 360
	_vitals.offset_bottom = -16
	bottom.add_child(_vitals)

	var hints := PanelContainer.new()
	hints.name = "Hints"
	hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hints.offset_left = -260
	hints.offset_top = -132
	hints.offset_right = 0
	hints.offset_bottom = 0
	hints.add_theme_stylebox_override("panel", UiStyle.screen_subpanel_style())
	bottom.add_child(hints)
	var hint_column := VBoxContainer.new()
	hint_column.add_theme_constant_override("separation", 3)
	hints.add_child(hint_column)
	_hint = _label("", 10, UiStyle.TEXT_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.visible = false
	hint_column.add_child(_hint)
	hint_column.add_child(_hint_row("LMB", "Move item"))
	hint_column.add_child(_hint_row("RMB", "Split stack"))
	hint_column.add_child(_hint_row("Shift", "Quick move"))
	hint_column.add_child(_hint_row("I / Esc", "Close"))
	return bottom


func _hint_row(key: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(52, 21)
	cap.add_theme_stylebox_override("panel", UiStyle.keycap_style())
	var key_label := _label(key, 10, UiStyle.TEXT_SECONDARY)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(key_label)
	row.add_child(cap)
	var label := _label(text, 11, UiStyle.TEXT_SECONDARY)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


func _make_slot(index: int, parent: Control, size: int, show_number: bool) -> InventorySlot:
	var slot := InventorySlot.new()
	slot.name = "Slot%d" % index
	slot.configure(index, inventory, library, size)
	slot.show_number = show_number
	slot.clicked.connect(_on_slot_clicked)
	slot.stack_moved.connect(_on_stack_moved)
	slot.hovered.connect(func(hovered_index: int) -> void: _focus_index = hovered_index)
	parent.add_child(slot)
	_slots.append(slot)
	return slot


# =========================================================================
# Navigation
# =========================================================================

func nav_enabled(target: String) -> bool:
	return target != "map" and NAV_TARGETS.has(target)


## Activates a navigation target.  Inventory/Character switch the page; Crafting
## and Settings are existing overlays the game opens; Map is explicitly not
## available.  Returns false when nothing happened.
func press_nav(target: String) -> bool:
	if not nav_enabled(target):
		return false
	match target:
		"inventory", "character":
			set_page(target)
		_:
			navigate.emit(target)
	return true


func set_page(value: String) -> void:
	if value != PAGE_INVENTORY and value != PAGE_CHARACTER:
		return
	_page = value
	_active_tab = value
	if _inventory_page != null:
		_inventory_page.visible = value == PAGE_INVENTORY
	if _character_page != null:
		_character_page.visible = value == PAGE_CHARACTER
	if _craft_panel != null:
		_craft_panel.visible = value == PAGE_INVENTORY
	_refresh_nav()
	_refresh()


func page() -> String:
	return _page


func _refresh_nav() -> void:
	for target: String in _tabs:
		var entry: Dictionary = _tabs[target]
		var button := entry["button"] as Button
		var enabled := nav_enabled(target)
		var active := target == _active_tab
		button.add_theme_stylebox_override("normal", UiStyle.tab_style(active, false, not enabled))
		button.add_theme_stylebox_override("hover", UiStyle.tab_style(active, enabled, not enabled))
		button.add_theme_stylebox_override("pressed", UiStyle.tab_style(active, false, not enabled))
		button.add_theme_stylebox_override("disabled", UiStyle.tab_style(false, false, true))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.disabled = not enabled
		var colour := UiStyle.TEXT_PRIMARY if active else (UiStyle.TEXT_MUTED if enabled else UiStyle.TAB_DISABLED)
		(entry["label"] as Label).add_theme_color_override("font_color", colour)
		(entry["icon"] as NavIcon).setup(str(NAV_GLYPHS[target]), colour)


# =========================================================================
# Configuration (game -> screen)
# =========================================================================

## The best station the player currently has.  Table recipes stay gated by it.
func set_station(station: String) -> void:
	if _station == station:
		return
	_station = station
	_refresh_craft()


func station() -> String:
	return _station


func set_vitals(health: float, max_health: float, hunger: float, max_hunger: float,
		breath: float = Survival.MAX_BREATH, max_breath: float = Survival.MAX_BREATH,
		breath_visible: bool = false) -> void:
	if _vitals == null:
		return
	_vitals.set_vitals(health, max_health, hunger, max_hunger)
	_vitals.set_breath(breath, max_breath, breath_visible)
	if _character_vitals != null:
		_character_vitals.text = _vitals.summary_text()


func vitals_text() -> String:
	return "" if _vitals == null else _vitals.summary_text()


func equipment_slot_count() -> int:
	return _equipment_slots.size()


func equipment_enabled() -> bool:
	return false


# =========================================================================
# Player slot interaction
# =========================================================================

func _on_slot_clicked(index: int, button: int, shift: bool) -> bool:
	_focus_index = index
	if index < Inventory.HOTBAR_SIZE and inventory != null:
		# An explicit click on a hotbar slot is a selection action, exactly like
		# pressing 1-9 in the world.  Merely opening the panel never changes it.
		inventory.select(index)
	if shift:
		var moved := quick_move(index)
		_refresh()
		return moved
	if button == MOUSE_BUTTON_RIGHT:
		if _carried.is_empty():
			split_half(index)
		else:
			put_one(index)
	else:
		if _carried.is_empty():
			pick_up(index)
		else:
			put_down(index)
	_refresh()
	return true


func click_slot(index: int, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> bool:
	return _on_slot_clicked(index, button, shift)


func _on_stack_moved(from: int, to: int) -> void:
	if inventory == null or not _carried.is_empty():
		# Dragging is a whole-stack model move; it cannot run while the temporary
		# cursor already owns a stack, or the two operations could double up.
		return
	if inventory.move_slot(from, to):
		_focus_index = to
		changed_stack.emit(inventory.item_at(to))
	_refresh()


## Picks the whole stack out of a slot (and makes it the cursor stack).
func pick_up(index: int) -> bool:
	if inventory == null or not _carried.is_empty():
		return false
	var stack := inventory.take_stack(index)
	if stack.is_empty():
		return false
	_carried = stack
	_carry_origin = index
	_focus_index = index
	changed_stack.emit(int(stack["item"]))
	_refresh()
	return true


## Puts the cursor stack into a slot.  Whatever does not fit stays carried.
func put_down(index: int) -> bool:
	if inventory == null or _carried.is_empty():
		return false
	var before_item := int(_carried["item"])
	var leftover: Dictionary = inventory.put_stack(index, _carried)
	_carried = leftover
	_focus_index = index
	if _carried.is_empty():
		_carry_origin = -1
	elif int(_carried["item"]) != before_item:
		# A swap displaced the target stack; that stack is now the cursor stack
		# and its original home is this slot.
		_carry_origin = index
	if not _carried.is_empty():
		changed_stack.emit(int(_carried["item"]))
	_refresh()
	return true


## Right-click with nothing carried: take ceil(half) of the stack.
func split_half(index: int) -> bool:
	if inventory == null or not _carried.is_empty() or inventory.is_empty(index):
		return false
	var count := inventory.count_at(index)
	var half := maxi(1, int(ceil(float(count) * 0.5)))
	var whole := inventory.take_stack(index)
	if whole.is_empty():
		return false
	var take := mini(int(whole["count"]), half)
	var remainder := {"item": int(whole["item"]),
		"count": int(whole["count"]) - take,
		"durability": int(whole.get("durability", 0))}
	if not remainder.is_empty() and int(remainder["count"]) > 0:
		inventory.put_stack(index, remainder)
	_carried = {"item": int(whole["item"]), "count": take,
		"durability": int(whole.get("durability", 0))}
	_carry_origin = index
	_focus_index = index
	changed_stack.emit(int(_carried["item"]))
	_refresh()
	return true


## Right-click while carrying: place exactly one item into a compatible slot.
func put_one(index: int) -> bool:
	if inventory == null or _carried.is_empty():
		return false
	if not inventory.is_empty(index) and inventory.item_at(index) != int(_carried["item"]):
		return false
	var one := {"item": int(_carried["item"]), "count": 1,
		"durability": int(_carried.get("durability", 0))}
	var leftover := inventory.put_stack(index, one)
	if not leftover.is_empty():
		return false
	_carried["count"] = int(_carried["count"]) - 1
	if int(_carried["count"]) <= 0:
		_carried = {}
		_carry_origin = -1
	_focus_index = index
	_refresh()
	return true


## Shift-click: move a whole stack between the hotbar and the main rows.
func quick_move(index: int) -> bool:
	if inventory == null or not _carried.is_empty():
		return false
	if not inventory.quick_move(index):
		return false
	_focus_index = index
	changed_stack.emit(inventory.item_at(index))
	_refresh()
	return true


## Swaps two slots (also the model path used by the drag & drop drop handler).
func swap(a: int, b: int) -> bool:
	if inventory == null or not _carried.is_empty() or not inventory.swap_slots(a, b):
		return false
	_refresh()
	return true


func carried() -> Dictionary:
	return _carried.duplicate()


func slot_count() -> int:
	return _slots.size()


## Text of a slot's count badge (empty when the count is 1 or the slot is empty).
func slot_count_text(index: int) -> String:
	for slot: InventorySlot in _slots:
		if slot.index == index:
			return (slot._count as Label).text
	return ""


## Text of the item facts pane, for diagnostics.
func detail_text() -> String:
	return _detail.text


func focus_slot(index: int) -> void:
	_focus_index = clampi(index, 0, Inventory.SIZE - 1)
	if inventory != null and _focus_index < Inventory.HOTBAR_SIZE:
		inventory.select(_focus_index)
	_refresh()


# =========================================================================
# Crafting grid
# =========================================================================

func craft_grid_slot_count() -> int:
	return CRAFT_GRID


func craft_grid_item(index: int) -> int:
	if _craft == null:
		return BlockDB.AIR
	return _craft.inventory.item_at(index)


func craft_grid_count(index: int) -> int:
	if _craft == null:
		return 0
	return _craft.inventory.count_at(index)


## The current output: a real stack in the result slot, or the ghost preview of
## the recipe the grid matches.  Empty when nothing matches.
func craft_output() -> Dictionary:
	if _craft == null:
		return {}
	if not _craft.inventory.is_empty(CRAFT_OUTPUT):
		return {
			"item": _craft.inventory.item_at(CRAFT_OUTPUT),
			"count": _craft.inventory.count_at(CRAFT_OUTPUT),
			"ghost": false,
		}
	var preview := _craft.result_preview()
	if preview.is_empty():
		return {}
	var recipe: Dictionary = preview["recipe"]
	return {
		"recipe": recipe,
		"item": int(preview["output"]),
		"count": int(preview["count"]),
		"ghost": true,
		"station_ok": Crafting.station_satisfied(recipe, _station),
	}


func craft_status_text() -> String:
	return "" if _craft_status == null else _craft_status.text


## Crafts the matching recipe into the result slot.  Atomic: `Station.craft_grid`
## validates the result slot before consuming anything, and the station check runs
## first.  Returns true when the output slot received the craft.
func craft_press() -> bool:
	if inventory == null or _craft == null:
		return false
	var preview := _craft.result_preview()
	if preview.is_empty():
		message.emit("Nothing matches this grid")
		return false
	var recipe: Dictionary = preview["recipe"]
	if not Crafting.station_satisfied(recipe, _station):
		message.emit("%s needs a crafting table" % ItemDB.name_of(int(recipe["output"])))
		_refresh()
		return false
	var result: Dictionary = _craft.craft_grid()
	if not bool(result.get("ok", false)):
		message.emit(str(result.get("reason", "Cannot craft")))
		_refresh()
		return false
	crafted.emit(result)
	_refresh()
	return true


## The result slot: crafts (if empty) and takes the output.  Shift-click sends it
## straight to the inventory.
func craft_click(index: int, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> bool:
	if index != CRAFT_OUTPUT:
		return _click_craft_grid(index, button, shift)
	if inventory == null or _craft == null:
		return false
	if not _carried.is_empty():
		message.emit("Place the held stack first")
		return false
	if _craft.inventory.is_empty(CRAFT_OUTPUT):
		if not craft_press():
			return false
	var stack := _craft.inventory.take(CRAFT_OUTPUT, -1)
	if stack.is_empty():
		return false
	if shift:
		var leftover: Dictionary = inventory.add_stack(stack)
		if not leftover.is_empty():
			_craft.inventory.insert(CRAFT_OUTPUT, leftover, true)
			message.emit("No room for %d %s" % [
				int(leftover["count"]), ItemDB.name_of(int(leftover["item"]))])
			_refresh()
			return false
		_refresh()
		return true
	_carried = stack
	_carry_origin = -1
	changed_stack.emit(int(stack["item"]))
	_focus_index = -1
	_refresh()
	return true


func _on_craft_slot_clicked(_side: String, index: int, button: int, shift: bool) -> void:
	craft_click(index, button, shift)


func _click_craft_grid(index: int, button: int, shift: bool) -> bool:
	if _craft == null or index < 0 or index >= CRAFT_GRID:
		return false
	if shift:
		if not _carried.is_empty():
			return false
		var stack := _craft.inventory.take(index, -1)
		if stack.is_empty():
			return false
		var leftover: Dictionary = inventory.add_stack(stack)
		if not leftover.is_empty():
			_craft.inventory.insert(index, leftover)
			message.emit("No room for %d %s" % [
				int(leftover["count"]), ItemDB.name_of(int(leftover["item"]))])
		_refresh()
		return true
	if button == MOUSE_BUTTON_RIGHT:
		if _carried.is_empty():
			if _craft.inventory.is_empty(index):
				return false
			var count := _craft.inventory.count_at(index)
			var take := maxi(1, int(ceil(float(count) * 0.5)))
			_carried = _craft.inventory.take(index, take)
			_carry_origin = -1
			_refresh()
			return true
		var one := {"item": int(_carried["item"]), "count": 1,
			"durability": int(_carried.get("durability", 0))}
		var leftover_one: Dictionary = _craft.inventory.insert(index, one)
		if not leftover_one.is_empty():
			return false
		_carried["count"] = int(_carried["count"]) - 1
		if int(_carried["count"]) <= 0:
			_carried = {}
			_carry_origin = -1
		_refresh()
		return true
	if _carried.is_empty():
		if _craft.inventory.is_empty(index):
			return false
		_carried = _craft.inventory.take(index, -1)
		_carry_origin = -1
		_refresh()
		return true
	var before := int(_carried["count"])
	var leftover: Dictionary = _craft.inventory.insert(index, _carried)
	if leftover.is_empty():
		_carried = {}
		_carry_origin = -1
		_refresh()
		return true
	_carried = leftover
	if int(_carried["count"]) == before:
		message.emit("That slot already holds a different item")
		return false
	_refresh()
	return true


func _on_craft_stack_moved(from_side: String, from_index: int, to_side: String,
		to_index: int) -> void:
	if _craft == null or inventory == null or not _carried.is_empty():
		return
	if to_side == "craft" and to_index == CRAFT_OUTPUT:
		return
	if from_side == to_side:
		if from_side == "player":
			inventory.move_slot(from_index, to_index)
		else:
			_craft.inventory.move(from_index, to_index)
	elif from_side == "player" and to_side == "craft":
		var stack := inventory.take_stack(from_index)
		if stack.is_empty():
			return
		var leftover: Dictionary = _craft.inventory.insert(to_index, stack)
		if not leftover.is_empty():
			inventory.put_stack(from_index, leftover)
	elif from_side == "craft" and to_side == "player":
		var stack: Dictionary = _craft.inventory.take(from_index, -1)
		if stack.is_empty():
			return
		var leftover: Dictionary = inventory.add_stack(stack)
		if not leftover.is_empty():
			_craft.inventory.insert(from_index, leftover)
	_refresh()


func _refresh_craft() -> void:
	if _craft == null or _craft_status == null or _output_slot == null:
		return
	var output_empty := _craft.inventory.is_empty(CRAFT_OUTPUT)
	var preview := _craft.result_preview()
	if output_empty and not preview.is_empty():
		_output_slot.override_stack = {
			"item": int(preview["output"]), "count": int(preview["count"]),
		}
		_output_slot.ghost = true
		_output_slot.selected = true
	else:
		_output_slot.override_stack = {}
		_output_slot.ghost = false
		_output_slot.selected = false
	_output_slot.refresh()
	for slot: StationSlot in _craft_slots:
		if slot != _output_slot:
			slot.refresh()

	var status := ""
	var can := false
	var status_colour := UiStyle.TEXT_MUTED
	if not output_empty:
		status = "Take the crafted %s" % ItemDB.name_of(_craft.inventory.item_at(CRAFT_OUTPUT))
		can = _carried.is_empty()
		status_colour = UiStyle.READY
	elif preview.is_empty():
		var hint := _closest_recipe()
		if hint.is_empty():
			status = "Place ingredients in the 3x3 grid" if _grid_empty() else "No matching recipe"
			status_colour = UiStyle.TEXT_MUTED
		else:
			status = "Missing: %s · %s" % [
				_shortfall_text(hint),
				ItemDB.name_of(int((hint["recipe"] as Dictionary)["output"])),
			]
			if not Crafting.station_satisfied(hint["recipe"], _station):
				status += " (needs a table)"
			status_colour = UiStyle.MISSING
	else:
		var recipe: Dictionary = preview["recipe"]
		if not Crafting.station_satisfied(recipe, _station):
			status = "%s needs a crafting table" % ItemDB.name_of(int(recipe["output"]))
			status_colour = UiStyle.BLOCKED
		elif not _output_fits(preview):
			status = "Result slot is full"
			status_colour = UiStyle.BLOCKED
		else:
			status = "Ready: %d %s" % [int(preview["count"]), ItemDB.name_of(int(preview["output"]))]
			can = true
			status_colour = UiStyle.READY
	_craft_status.text = status
	_craft_status.add_theme_color_override("font_color", status_colour)
	_craft_button.disabled = not can
	_craft_button.modulate.a = 1.0 if can else 0.4
	_refresh_table_note()


func _refresh_table_note() -> void:
	if _craft_table_label == null:
		return
	var table_rank := int(Crafting.STATION_RANK.get(Crafting.STATION_TABLE, 1))
	var have := int(Crafting.STATION_RANK.get(_station, 0))
	if have >= table_rank:
		_craft_table_label.text = "A crafting table is nearby: table recipes are unlocked."
	else:
		_craft_table_label.text = "Craft more advanced items using a crafting table. None nearby."


func _output_fits(preview: Dictionary) -> bool:
	var output := int(preview.get("output", preview.get("item", BlockDB.AIR)))
	var amount := int(preview.get("count", 0))
	if _craft.inventory.is_empty(CRAFT_OUTPUT):
		return amount <= maxi(1, ItemDB.max_stack(output))
	if _craft.inventory.item_at(CRAFT_OUTPUT) != output:
		return false
	return _craft.inventory.count_at(CRAFT_OUTPUT) + amount <= maxi(1, ItemDB.max_stack(output))


func _grid_empty() -> bool:
	for index in CRAFT_GRID:
		if not _craft.inventory.is_empty(index):
			return false
	return true


## The closest recipe by multiset when the grid does not match one exactly, so
## the interface can say what is missing instead of only "no recipe".
func _closest_recipe() -> Dictionary:
	var counts := _craft.grid_counts()
	if counts.is_empty():
		return {}
	var best: Dictionary = {}
	var best_missing := 1 << 30
	var best_parts: Array = []
	for recipe: Dictionary in Crafting.recipes():
		if Crafting.station_of(recipe) == Crafting.STATION_FURNACE:
			continue
		var ingredients := Crafting.ingredients(recipe)
		var compatible := true
		for item_id in counts:
			if not ingredients.has(int(item_id)) or int(counts[item_id]) > int(ingredients[int(item_id)]):
				compatible = false
				break
		if not compatible:
			continue
		var missing := 0
		var parts: Array = []
		for item_id in ingredients:
			var short := int(ingredients[item_id]) - int(counts.get(int(item_id), 0))
			if short > 0:
				missing += short
				parts.append("%d %s" % [short, ItemDB.name_of(int(item_id))])
		if missing > 0 and missing < best_missing:
			best_missing = missing
			best = recipe
			best_parts = parts
	if best.is_empty():
		return {}
	return {"recipe": best, "missing": best_parts}


func _shortfall_text(hint: Dictionary) -> String:
	return " + ".join(hint.get("missing", []))


# =========================================================================
# State
# =========================================================================

func _refresh() -> void:
	if inventory == null or _detail == null:
		return
	var selected := inventory.selected
	for slot: InventorySlot in _slots:
		slot.selected = slot.index == selected
		slot.override_stack = {}
		slot.refresh()
	_cursor.set_stack(_carried)
	if _storage_label != null:
		_storage_label.text = "%d slots · %d free" % [Inventory.MAIN_SIZE, inventory.free_slot_count()]
	_update_held()
	_update_detail()
	if _hint != null:
		if _carried.is_empty():
			_hint.text = ""
			_hint.visible = false
		else:
			_hint.text = "Carrying %d %s" % [int(_carried["count"]), ItemDB.name_of(int(_carried["item"]))]
			_hint.visible = true
	_refresh_craft()


func _update_held() -> void:
	var item_id := inventory.selected_item()
	var text := "Hand: empty"
	var icon_item := BlockDB.AIR
	if item_id != BlockDB.AIR:
		icon_item = item_id
		text = "Hand: %s" % ItemDB.name_of(item_id)
		var maximum := ItemDB.max_durability(item_id)
		if maximum > 0:
			text += "  %d / %d" % [inventory.durability_of(inventory.selected), maximum]
	if _held_icon != null:
		_held_icon.set_item(icon_item, library, ItemDB.icon_tint(icon_item))
	if _held_label != null:
		_held_label.text = text
	if _character_icon != null:
		_character_icon.set_item(icon_item, library, ItemDB.icon_tint(icon_item))
	if _character_held != null:
		_character_held.text = "Nothing" if item_id == BlockDB.AIR else (
			"%s (slot %d)" % [ItemDB.name_of(item_id), inventory.selected + 1])


func _update_detail() -> void:
	var item_id := inventory.item_at(_focus_index)
	if item_id == BlockDB.AIR and not _carried.is_empty():
		item_id = int(_carried["item"])
	if item_id == BlockDB.AIR:
		_detail.text = "No item selected.\n\nClick or hover a stack, pick one up, or press 1-9."
		return
	var lines: Array = []
	lines.append(ItemDB.name_of(item_id))
	lines.append(_kind_text(item_id))
	lines.append("")
	if ItemDB.is_block(item_id):
		var block_id := item_id
		lines.append("Block: %s" % BlockDB.name_of(block_id))
		lines.append("Hardness: %.2f  ·  %s" % [float(BlockDB.hardness[block_id]),
			"solid" if BlockDB.is_solid(block_id) else "passable"])
		var drop := ItemDB.drop_for_block(block_id)
		if drop != BlockDB.NO_DROP:
			lines.append("Drops: %s" % ItemDB.name_of(drop))
		var required := ItemDB.required_tool(block_id)
		if required != ItemDB.Tool.NONE:
			lines.append("Needs a %s (tier %s)" % [ItemDB.tool_name(required),
				ItemDB.tier_name(ItemDB.required_tier(block_id))])
	lines.append("Stack: %d" % ItemDB.max_stack(item_id))
	lines.append("Held: %d" % inventory.count_of(item_id))
	if ItemDB.is_tool_item(item_id):
		lines.append("")
		lines.append("Tool tier: %s" % ItemDB.tier_name(ItemDB.tier(item_id)))
		lines.append("Mining speed: %.1fx" % ItemDB.mining_speed(item_id))
		lines.append("Attack: %d" % int(round(ItemDB.attack_damage(item_id))))
		var wear := inventory.durability_of(_focus_index)
		var maximum_wear := ItemDB.max_durability(item_id)
		lines.append("Durability: %d / %d" % [wear, maximum_wear])
		if maximum_wear > 0:
			lines.append("Blocks left: about %d" % wear)
	if ItemDB.is_food(item_id):
		lines.append("")
		lines.append("Food: +%d hunger" % int(ItemDB.food_value(item_id)))
		if ItemDB.heal_value(item_id) > 0.0:
			lines.append("Also heals %d" % int(ItemDB.heal_value(item_id)))
	var made_by := _recipe_making(item_id)
	if not made_by.is_empty():
		lines.append("")
		lines.append("Made by: %s" % Crafting.label(made_by))
	var used_in := _recipes_using(item_id)
	if not used_in.is_empty():
		lines.append("")
		lines.append("Used in %d recipe%s:" % [used_in.size(), "" if used_in.size() == 1 else "s"])
		for recipe: Dictionary in used_in:
			lines.append("  · %s" % Crafting.label(recipe))
	_detail.text = "\n".join(lines)


func _kind_text(item_id: int) -> String:
	if ItemDB.is_tool_item(item_id):
		return "%s tool (%s)" % [ItemDB.tier_name(ItemDB.tier(item_id)), ItemDB.tool_name(ItemDB.tool_class(item_id))]
	if ItemDB.is_food(item_id):
		return "Food"
	if ItemDB.is_block(item_id):
		return "Block"
	if item_id == BlockDB.WATER:
		return "Liquid"
	return "Material"


func _recipe_making(item_id: int) -> Dictionary:
	for recipe: Dictionary in Crafting.recipes():
		if int(recipe["output"]) == item_id:
			return recipe
	return {}


func _recipes_using(item_id: int) -> Array:
	var found: Array = []
	for recipe: Dictionary in Crafting.recipes():
		if Crafting.ingredients(recipe).has(item_id) or Crafting.fuel(recipe).has(item_id):
			found.append(recipe)
	return found


# =========================================================================
# Visibility / ownership
# =========================================================================

func open() -> void:
	_refresh()
	visible = true
	_refresh_nav()
	opened.emit()


## Puts the cursor stack back into the inventory model, preferring its origin
## slot, and returns every crafting-grid item to the player.  Returns whatever
## could not be stored.  `_carried` still owns it.
func _recover_cursor() -> Dictionary:
	var leftover := _carried
	if _carry_origin >= 0 and _carry_origin < Inventory.SIZE:
		if inventory.is_empty(_carry_origin) \
				or inventory.item_at(_carry_origin) == int(_carried["item"]):
			leftover = inventory.put_stack(_carry_origin, leftover)
	if not leftover.is_empty():
		leftover = inventory.add_stack(leftover)
	return leftover


## Returns the temporary cursor stack to the inventory *without* closing the
## panel.  Returns false when there is genuinely no room; the stack stays on the
## cursor (nothing is destroyed).
func flush_cursor() -> bool:
	if inventory == null:
		return true
	if not _carried.is_empty():
		_carried = _recover_cursor()
		if not _carried.is_empty():
			_cursor.set_stack(_carried)
			return false
		_carry_origin = -1
		_cursor.set_stack({})
	return true


## Returns the cursor stack *and* the crafting grid to the models, so a save or a
## close always contains every owned item.  False when something has nowhere to
## go; the items stay where they are.
func flush_all() -> bool:
	if not flush_cursor():
		return false
	return _flush_grid()


## Returns the 3x3 grid and the result slot to the player.  False when an item
## could not fit, so the caller must not treat the model as complete.
func _flush_grid() -> bool:
	if _craft == null:
		return true
	_craft.return_crafting_items(inventory)
	for index in CRAFT_GRID + 1:
		if not _craft.inventory.is_empty(index):
			return false
	_refresh_craft()
	return true


## Closes the interface, recovering the cursor and the crafting grid:
##   1. the cursor returns to its origin/any matching slot;
##   2. the grid returns to the player;
##   3. if anything has nowhere to go, the panel stays open and explains why.
## Returns true when the panel actually closed.
func close() -> bool:
	if not flush_all():
		message.emit("No room for every held item — make space before closing")
		return false
	_cursor.set_stack({})
	visible = false
	closed.emit()
	return true


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


# =========================================================================
# Diagnostics (captures and tests)
# =========================================================================

## Fills grid cells from `[index, item_id, count]` entries.  Diagnostic only.
func debug_seed_crafting_grid(entries: Array) -> void:
	debug_clear_crafting_grid()
	for entry: Array in entries:
		if entry.size() < 2:
			continue
		var index := int(entry[0])
		var item_id := int(entry[1])
		var count := int(entry[2]) if entry.size() > 2 else 1
		_craft.inventory.insert(index, {"item": item_id, "count": count})
	_refresh()


func debug_seed_output(item_id: int, count: int) -> void:
	_craft.inventory.clear_slot(CRAFT_OUTPUT)
	_craft.inventory.insert(CRAFT_OUTPUT, {"item": item_id, "count": count}, true)
	_refresh()


## Diagnostic only: empties the grid losslessly, returning each stack to the
## player.  Anything that does not fit stays in the grid.
func debug_clear_crafting_grid() -> void:
	for index in CRAFT_GRID:
		var stack := _craft.inventory.take(index, -1)
		if stack.is_empty():
			continue
		var leftover: Dictionary = inventory.add_stack(stack)
		if not leftover.is_empty():
			_craft.inventory.insert(index, leftover)
	_refresh()


func debug_clear_output() -> void:
	_craft.inventory.clear_slot(CRAFT_OUTPUT)
	_refresh()
