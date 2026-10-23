class_name InventoryPanel
extends Control

## M40 v2 — the inventory, character and crafting experience.
##
## One full-screen screen with three pages:
##   * Inventory  — Player panel, the 27+9 inventory, item actions panel, hotbar.
##   * Character  — the same stable Player panel and inventory, plus real stats.
##   * Crafting   — categories, searchable recipe browser and recipe details.
##
## Presentation and intent only.  Item mutations go through `Inventory`; recipe
## facts and transactions go through `Crafting`, so the UI never invents a stack
## or a recipe.  Hotbar selection is a gameplay action (1-9/wheel), not a side
## effect of clicking a slot: a click always means "move this stack".
##
## Equipment is display-only because VoxelWorld has no equipment system, and
## experience/defence/armour are labelled unavailable rather than fabricated.

signal changed_stack(item_id: int)
signal message(text: String)
signal crafted(result: Dictionary)
## External navigation (Settings); the three main pages are internal.
signal navigate(target: String)
signal opened()
signal closed()

const PAGE_INVENTORY := "inventory"
const PAGE_CHARACTER := "character"
const PAGE_CRAFTING := "crafting"
const NAV_TARGETS := ["inventory", "crafting", "character", "map", "settings"]
const NAV_LABELS := {
	"inventory": "Inventory", "crafting": "Crafting", "character": "Character",
	"map": "Map", "settings": "Settings",
}
const NAV_GLYPHS := {
	"inventory": "inventory", "crafting": "crafting", "character": "character",
	"map": "map", "settings": "settings",
}

const GRID_COLUMNS := 6
const GRID_SLOT := 66
const GRID_GAP := 5
const HOTBAR_SLOT := UiStyle.SLOT_SIZE
const BODY_WIDTH := 1104.0
const PLAYER_WIDTH := 320.0
const INVENTORY_WIDTH := 460.0
const SIDE_WIDTH := 300.0
const CRAFT_GRID_SLOT := 42
const RECIPE_TILE := 70

const ACTION_ALL := "all"
const ACTION_HALF := "half"
const ACTION_ONE := "one"
const ACTION_AMOUNT := "amount"
const ACTION_QUICK := "quick"
const ACTION_MOVE := "move"
const ACTION_CANCEL := "cancel"

var inventory: Inventory
var library: TextureLibrary

var _station := Crafting.STATION_HAND
var _page := PAGE_INVENTORY
var _active_tab := "inventory"

var _slots: Array[InventorySlot] = []
var _equipment_slots: Array[Control] = []
var _tabs: Dictionary = {}
var _carried: Dictionary = {}
var _carry_origin := -1
var _focus_index := 0
var _context_index := -1
var _context_open := false

var _player_panel: Control
var _preview_cell: Control
var _preview: CharacterPreview
var _rotation_row: Control
var _inventory_page: Control
var _inventory_grid: GridContainer
var _grid_slots: Array[InventorySlot] = []
var _detail_label: Label
var _storage_label: Label
var _context_panel: Control
var _context_icon: ItemIcon
var _context_title: Label
var _context_count: Label
var _context_buttons: Dictionary = {}
var _context_move_button: Button
var _stats_panel: Control
var _stats_vitals: Label
var _stats_health_bar: ProgressBar
var _stats_hunger_bar: ProgressBar
var _stats_attack: Label
var _stats_speed: Label
var _stats_held: Label
var _crafting_page: Control
var _crafting_category_buttons: Dictionary = {}
var _crafting_category := ""
var _crafting_search := ""
var _crafting_grid: GridContainer
var _recipe_tiles: Array = []
var _recipe_grid_scroll: ScrollContainer
var _recipe_count_label: Label
var _craft_title: Label
var _craft_desc: Label
var _craft_preview: Array[ItemIcon] = []
var _craft_output_icon: ItemIcon
var _craft_output_count: Label
var _craft_ingredients: VBoxContainer
var _craft_station_icon: ItemIcon
var _craft_station_title: Label
var _craft_station_text: Label
var _craft_quantity_label: Label
var _craft_max_label: Label
var _craft_status: Label
var _craft_button: Button
var _selected_recipe_id := ""
var _craft_quantity := 1

var _amount_dialog: Control
var _amount_slot := -1
var _amount_take := true
var _amount_value := 1
var _amount_max := 1
var _amount_icon: ItemIcon
var _amount_title: Label
var _amount_available: Label
var _amount_value_label: Label
var _amount_slider: HSlider
var _amount_edit: LineEdit
var _amount_max_label: Label
var _amount_confirm: Button
var _amount_updating := false

var _cursor: ItemCursor
var _vitals: VitalsBar
var _hints_panel: Control


func setup(player_inventory: Inventory, texture_library: TextureLibrary = null) -> void:
	inventory = player_inventory
	library = texture_library
	_build()
	if inventory != null and not inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.connect(_on_inventory_changed)
	visible = false
	_refresh_all()


# =========================================================================
# Construction
# =========================================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = UiStyle.SCREEN_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
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

	# A fixed-width body, horizontally centred by spacers.  The body itself fills
	# the available height, so content changes in one panel (details, stats,
	# rotations) can never move the Player panel or the character preview.
	var body_row := HBoxContainer.new()
	body_row.name = "BodyRow"
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_theme_constant_override("separation", 0)
	column.add_child(body_row)
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_row.add_child(left_spacer)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.custom_minimum_size = Vector2(BODY_WIDTH, 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	body.alignment = BoxContainer.ALIGNMENT_BEGIN
	body_row.add_child(body)
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_row.add_child(right_spacer)

	_player_panel = _build_player_panel()
	body.add_child(_player_panel)
	_inventory_page = _build_inventory_page()
	body.add_child(_inventory_page)
	_context_panel = _build_context_panel()
	body.add_child(_context_panel)
	_stats_panel = _build_stats_panel()
	body.add_child(_stats_panel)
	_crafting_page = _build_crafting_page()
	body.add_child(_crafting_page)

	column.add_child(_build_bottom())

	_cursor = ItemCursor.new()
	_cursor.name = "CursorStack"
	add_child(_cursor)
	_cursor.setup(library)

	_amount_dialog = _build_amount_dialog()
	add_child(_amount_dialog)

	_refresh_nav()
	_refresh_page_visibility()


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


# --- Player panel ---------------------------------------------------------

func _build_player_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "PlayerPanel"
	panel.custom_minimum_size = Vector2(PLAYER_WIDTH, 0)
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
	survivor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(survivor)
	column.add_child(title_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_child(row)
	var armour := VBoxContainer.new()
	armour.name = "Equipment"
	armour.add_theme_constant_override("separation", 6)
	armour.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for entry: Array in [["helmet", "Helmet"], ["chestplate", "Chestplate"],
			["leggings", "Leggings"], ["boots", "Boots"]]:
		armour.add_child(_equipment_slot(str(entry[0]), str(entry[1])))
	row.add_child(armour)

	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 3)
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview_cell = Control.new()
	_preview_cell.name = "PreviewCell"
	_preview_cell.custom_minimum_size = Vector2(200, 290)
	_preview_cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview_cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_column.add_child(_preview_cell)
	_preview = CharacterPreview.new()
	_preview.name = "CharacterPreview"
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.custom_minimum_size = Vector2(200, 290)
	_preview.setup()
	_preview_cell.add_child(_preview)
	_rotation_row = HBoxContainer.new()
	_rotation_row.name = "RotationRow"
	_rotation_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_rotation_row.add_theme_constant_override("separation", 6)
	preview_column.add_child(_rotation_row)
	_rotation_row.add_child(_rotation_button("‹", -45.0))
	_rotation_row.add_child(_rotation_button("•", 0.0))
	_rotation_row.add_child(_rotation_button("›", 45.0))
	row.add_child(preview_column)

	var offhand := VBoxContainer.new()
	offhand.add_theme_constant_override("separation", 6)
	offhand.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	offhand.add_child(_equipment_slot("shield", "Off Hand"))
	offhand.add_child(_equipment_slot("shield", "Second Off Hand"))
	row.add_child(offhand)

	var held_row := HBoxContainer.new()
	held_row.add_theme_constant_override("separation", 7)
	var held_icon := ItemIcon.new()
	held_icon.name = "HeldIcon"
	held_icon.custom_minimum_size = Vector2(26, 26)
	held_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	held_row.add_child(held_icon)
	var held_label := _label("", 12, UiStyle.TEXT_SECONDARY)
	held_label.name = "HeldLabel"
	held_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	held_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	held_row.add_child(held_label)
	column.add_child(held_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var note := _label("Equipment slots are display-only: VoxelWorld has no equipment system yet.",
		10, UiStyle.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	return panel


func _equipment_slot(glyph: String, label_text: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Equipment_%s" % glyph
	slot.custom_minimum_size = Vector2(38, 38)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.add_theme_stylebox_override("panel", UiStyle.slot_style(false, false, true))
	slot.tooltip_text = "%s — equipment is not implemented in VoxelWorld yet" % label_text
	var icon := NavIcon.new()
	icon.setup(glyph, Color(0.58, 0.68, 0.82, 0.58), 1.6)
	slot.add_child(icon)
	_equipment_slots.append(slot)
	return slot


func _rotation_button(text: String, degrees: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(34, 24)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", UiStyle.TEXT_SECONDARY)
	button.add_theme_stylebox_override("normal", UiStyle.button_style(false))
	button.add_theme_stylebox_override("hover", UiStyle.button_style(false, true))
	button.add_theme_stylebox_override("pressed", UiStyle.button_style(true, true))
	if is_zero_approx(degrees):
		button.tooltip_text = "Reset the character preview rotation"
		button.pressed.connect(func() -> void: _preview.reset_rotation())
	else:
		button.tooltip_text = "Rotate the character preview"
		button.pressed.connect(func() -> void: _preview.rotate_by(degrees))
	return button


# --- Inventory page -------------------------------------------------------

func _build_inventory_page() -> Control:
	var panel := PanelContainer.new()
	panel.name = "InventoryCenter"
	panel.custom_minimum_size = Vector2(INVENTORY_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_storage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_storage_label)
	column.add_child(header)

	_inventory_grid = GridContainer.new()
	_inventory_grid.name = "InventoryGrid"
	_inventory_grid.columns = GRID_COLUMNS
	_inventory_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_inventory_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_inventory_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_inventory_grid)
	for index in range(Inventory.MAIN_FIRST, Inventory.SIZE):
		var slot := _make_slot(index, _inventory_grid, GRID_SLOT)
		slot.show_number = false
		_grid_slots.append(slot)

	# The full item facts live in the actions card so long tool/recipe text can
	# never inflate this panel and resize the character preview.
	var hint := _label("Hover a slot to inspect it. Middle-click for item actions.", 10, UiStyle.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	return panel


# --- Item actions / context panel ----------------------------------------

func _build_context_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "ContextPanel"
	panel.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", UiStyle.screen_panel_style())
	panel.visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_label("Item Actions", 14, UiStyle.TEXT_PRIMARY))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_context_icon = ItemIcon.new()
	_context_icon.custom_minimum_size = Vector2(42, 42)
	head.add_child(_context_icon)
	var head_text := VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_text.add_theme_constant_override("separation", 1)
	_context_title = _label("", 14, UiStyle.TEXT_PRIMARY)
	head_text.add_child(_context_title)
	_context_count = _label("", 11, UiStyle.TEXT_SECONDARY)
	head_text.add_child(_context_count)
	head.add_child(head_text)
	column.add_child(head)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "DetailScroll"
	detail_scroll.custom_minimum_size = Vector2(0, 88)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(detail_scroll)
	_detail_label = _label("", 11, Color(0.84, 0.90, 0.97))
	_detail_label.name = "DetailLabel"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_label)

	for entry: Array in [
		[ACTION_ALL, "Select All"], [ACTION_HALF, "Select Half"],
		[ACTION_ONE, "Select One"], [ACTION_AMOUNT, "Select Amount…"],
		[ACTION_QUICK, "Quick Move"], [ACTION_MOVE, "Move to Hotbar"],
		[ACTION_CANCEL, "Cancel"],
	]:
		var button := _action_button(str(entry[1]))
		var action := str(entry[0])
		button.name = "Action_%s" % action.capitalize()
		button.pressed.connect(func() -> void: activate_context(action))
		column.add_child(button)
		_context_buttons[action] = button
	_context_move_button = _context_buttons[ACTION_MOVE] as Button

	var note := _label("Middle-click a slot to reopen these actions. R opens the amount dialog.",
		10, UiStyle.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	return panel


func _action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 30)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", UiStyle.button_style(false))
	button.add_theme_stylebox_override("hover", UiStyle.button_style(false, true))
	button.add_theme_stylebox_override("pressed", UiStyle.button_style(true, true))
	button.add_theme_stylebox_override("disabled", UiStyle.button_disabled_style())
	return button


# --- Character stats ------------------------------------------------------

func _build_stats_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "StatsPanel"
	panel.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.screen_panel_style())
	panel.visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(_label("Stats", 21, UiStyle.TEXT_PRIMARY))
	_stats_vitals = _label("", 13, UiStyle.TEXT_SECONDARY)
	column.add_child(_stats_vitals)

	column.add_child(_label("HEALTH", 10, UiStyle.TEXT_MUTED))
	_stats_health_bar = _stat_bar(UiStyle.HEART_RED)
	column.add_child(_stats_health_bar)
	column.add_child(_label("HUNGER", 10, UiStyle.TEXT_MUTED))
	_stats_hunger_bar = _stat_bar(UiStyle.HUNGER_AMBER)
	column.add_child(_stats_hunger_bar)

	var attack_row := HBoxContainer.new()
	var attack_label := _label("Attack", 13, UiStyle.TEXT_SECONDARY)
	attack_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attack_row.add_child(attack_label)
	_stats_attack = _label("", 13, UiStyle.TEXT_PRIMARY)
	attack_row.add_child(_stats_attack)
	column.add_child(attack_row)

	var speed_row := HBoxContainer.new()
	var speed_label := _label("Movement Speed", 13, UiStyle.TEXT_SECONDARY)
	speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(speed_label)
	_stats_speed = _label("", 13, UiStyle.TEXT_PRIMARY)
	speed_row.add_child(_stats_speed)
	column.add_child(speed_row)

	var held_row := HBoxContainer.new()
	var held_label := _label("Held", 13, UiStyle.TEXT_SECONDARY)
	held_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	held_row.add_child(held_label)
	_stats_held = _label("", 13, UiStyle.TEXT_PRIMARY)
	held_row.add_child(_stats_held)
	column.add_child(held_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var note := _label("Experience, defence and armour are not implemented in VoxelWorld, so no value is shown.",
		10, UiStyle.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	return panel


func _stat_bar(colour: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.02, 0.03, 0.045, 0.85)
	background.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


# --- Crafting page --------------------------------------------------------

func _build_crafting_page() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CraftingPage"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.screen_panel_style())
	panel.visible = false

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	panel.add_child(columns)

	# Categories.
	var categories := PanelContainer.new()
	categories.custom_minimum_size = Vector2(200, 0)
	categories.add_theme_stylebox_override("panel", UiStyle.screen_panel_style(true))
	columns.add_child(categories)
	var category_column := VBoxContainer.new()
	category_column.add_theme_constant_override("separation", 4)
	categories.add_child(category_column)
	category_column.add_child(_label("Categories", 18, UiStyle.TEXT_PRIMARY))
	var all_button := _category_button("All", "")
	category_column.add_child(all_button)
	_crafting_category_buttons[""] = all_button
	for category: String in Crafting.categories():
		var button := _category_button(category, category)
		category_column.add_child(button)
		_crafting_category_buttons[category] = button

	# Recipe browser.
	var browser := VBoxContainer.new()
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser.add_theme_constant_override("separation", 8)
	columns.add_child(browser)
	var browser_header := HBoxContainer.new()
	var browser_title := _label("Recipes", 18, UiStyle.TEXT_PRIMARY)
	browser_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser_header.add_child(browser_title)
	_recipe_count_label = _label("", 11, UiStyle.TEXT_MUTED)
	_recipe_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	browser_header.add_child(_recipe_count_label)
	browser.add_child(browser_header)
	var search := LineEdit.new()
	search.name = "RecipeSearch"
	search.placeholder_text = "Search recipes…"
	search.custom_minimum_size = Vector2(0, 32)
	search.add_theme_font_size_override("font_size", 12)
	search.text_changed.connect(func(text: String) -> void: set_craft_search(text))
	browser.add_child(search)
	_recipe_grid_scroll = ScrollContainer.new()
	_recipe_grid_scroll.name = "RecipeScroll"
	_recipe_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipe_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.add_child(_recipe_grid_scroll)
	_crafting_grid = GridContainer.new()
	_crafting_grid.name = "RecipeGrid"
	_crafting_grid.columns = 5
	_crafting_grid.add_theme_constant_override("h_separation", 6)
	_crafting_grid.add_theme_constant_override("v_separation", 6)
	_crafting_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_grid_scroll.add_child(grid_center)
	grid_center.add_child(_crafting_grid)
	for recipe: Dictionary in Crafting.recipes():
		_crafting_grid.add_child(_recipe_tile(recipe))

	# Recipe details.
	var details := PanelContainer.new()
	details.name = "RecipeDetails"
	details.custom_minimum_size = Vector2(330, 0)
	details.add_theme_stylebox_override("panel", UiStyle.screen_panel_style(true))
	columns.add_child(details)
	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 7)
	details.add_child(detail_column)
	detail_column.add_child(_label("Crafting", 18, UiStyle.TEXT_PRIMARY))
	_craft_title = _label("Select a recipe", 15, UiStyle.TEXT_PRIMARY)
	detail_column.add_child(_craft_title)
	_craft_desc = _label("", 11, UiStyle.TEXT_MUTED)
	_craft_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_column.add_child(_craft_desc)

	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 8)
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	detail_column.add_child(preview_row)
	var preview_grid := GridContainer.new()
	preview_grid.columns = 3
	preview_grid.add_theme_constant_override("h_separation", 4)
	preview_grid.add_theme_constant_override("v_separation", 4)
	preview_row.add_child(preview_grid)
	for index in 9:
		var cell := ItemIcon.new()
		cell.custom_minimum_size = Vector2(CRAFT_GRID_SLOT, CRAFT_GRID_SLOT)
		preview_grid.add_child(cell)
		_craft_preview.append(cell)
	var arrow := _label("→", 20, UiStyle.TEXT_SECONDARY)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_row.add_child(arrow)
	var output_column := VBoxContainer.new()
	output_column.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_child(output_column)
	_craft_output_icon = ItemIcon.new()
	_craft_output_icon.custom_minimum_size = Vector2(46, 46)
	output_column.add_child(_craft_output_icon)
	_craft_output_count = _label("", 11, UiStyle.TEXT_SECONDARY)
	_craft_output_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	output_column.add_child(_craft_output_count)

	_craft_station_title = _label("", 12, UiStyle.TEXT_PRIMARY)
	detail_column.add_child(_craft_station_title)
	_craft_station_text = _label("", 10, UiStyle.TEXT_MUTED)
	_craft_station_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_column.add_child(_craft_station_text)

	detail_column.add_child(_label("INGREDIENTS", 10, UiStyle.TEXT_MUTED))
	_craft_ingredients = VBoxContainer.new()
	_craft_ingredients.add_theme_constant_override("separation", 3)
	detail_column.add_child(_craft_ingredients)

	var quantity_row := HBoxContainer.new()
	quantity_row.add_theme_constant_override("separation", 6)
	quantity_row.add_child(_label("Quantity", 12, UiStyle.TEXT_SECONDARY))
	var minus := _small_button("−")
	minus.pressed.connect(func() -> void: set_craft_quantity(_craft_quantity - 1))
	quantity_row.add_child(minus)
	_craft_quantity_label = _label("1", 14, UiStyle.TEXT_PRIMARY)
	_craft_quantity_label.custom_minimum_size = Vector2(34, 0)
	_craft_quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_row.add_child(_craft_quantity_label)
	var plus := _small_button("+")
	plus.pressed.connect(func() -> void: set_craft_quantity(_craft_quantity + 1))
	quantity_row.add_child(plus)
	_craft_max_label = _label("", 10, UiStyle.TEXT_MUTED)
	_craft_max_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quantity_row.add_child(_craft_max_label)
	detail_column.add_child(quantity_row)

	_craft_status = _label("", 11, UiStyle.TEXT_MUTED)
	_craft_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_column.add_child(_craft_status)
	_craft_button = Button.new()
	_craft_button.name = "CraftButton"
	_craft_button.text = "Craft"
	_craft_button.focus_mode = Control.FOCUS_NONE
	_craft_button.custom_minimum_size = Vector2(0, 36)
	_craft_button.add_theme_stylebox_override("normal", UiStyle.button_style(true))
	_craft_button.add_theme_stylebox_override("hover", UiStyle.button_style(true, true))
	_craft_button.add_theme_stylebox_override("pressed", UiStyle.button_style(true, true))
	_craft_button.add_theme_stylebox_override("disabled", UiStyle.button_disabled_style())
	_craft_button.pressed.connect(func() -> void: craft_selected())
	detail_column.add_child(_craft_button)
	return panel


func _category_button(text: String, category: String) -> Button:
	var button := Button.new()
	button.name = "Category_%s" % (text if not text.is_empty() else "All")
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 32)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", UiStyle.category_style(false))
	button.add_theme_stylebox_override("hover", UiStyle.category_style(false, true))
	button.add_theme_stylebox_override("pressed", UiStyle.category_style(true))
	button.pressed.connect(func() -> void: set_craft_category(category))
	return button


func _recipe_tile(recipe: Dictionary) -> Button:
	var button := Button.new()
	button.name = "RecipeTile_%s" % str(recipe["id"])
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(RECIPE_TILE, RECIPE_TILE)
	button.tooltip_text = "%s — %s" % [ItemDB.name_of(int(recipe["output"])), str(recipe["category"])]
	button.add_theme_stylebox_override("normal", UiStyle.recipe_tile_style(false))
	button.add_theme_stylebox_override("hover", UiStyle.recipe_tile_style(false, true))
	button.add_theme_stylebox_override("pressed", UiStyle.recipe_tile_style(true))
	var icon := ItemIcon.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 8
	icon.offset_top = 8
	icon.offset_right = -8
	icon.offset_bottom = -8
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_item(int(recipe["output"]), library, ItemDB.icon_tint(int(recipe["output"])))
	button.add_child(icon)
	var count := Label.new()
	count.text = "" if int(recipe["output_count"]) <= 1 else str(int(recipe["output_count"]))
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -26
	count.offset_top = -22
	count.offset_right = -4
	count.offset_bottom = -2
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(count)
	var id := str(recipe["id"])
	button.pressed.connect(func() -> void: select_recipe(id))
	_recipe_tiles.append({"recipe": recipe, "button": button, "icon": icon, "count": count})
	return button


func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(28, 26)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", UiStyle.button_style(false))
	button.add_theme_stylebox_override("hover", UiStyle.button_style(false, true))
	button.add_theme_stylebox_override("pressed", UiStyle.button_style(true, true))
	return button


# --- Bottom strip ---------------------------------------------------------

func _build_bottom() -> Control:
	var bottom := Control.new()
	bottom.name = "Bottom"
	bottom.custom_minimum_size = Vector2(0, 132)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
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
		var slot := _make_slot(index, cell, HOTBAR_SLOT)
		slot.custom_minimum_size = Vector2(HOTBAR_SLOT, HOTBAR_SLOT)
		slot.show_number = false
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

	_hints_panel = PanelContainer.new()
	_hints_panel.name = "Hints"
	_hints_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hints_panel.offset_left = -270
	_hints_panel.offset_top = -132
	_hints_panel.offset_right = 0
	_hints_panel.offset_bottom = 0
	_hints_panel.custom_minimum_size = Vector2(270, 0)
	var hint_style := UiStyle.screen_subpanel_style()
	hint_style.set_content_margin_all(6)
	_hints_panel.add_theme_stylebox_override("panel", hint_style)
	bottom.add_child(_hints_panel)
	var hint_column := VBoxContainer.new()
	hint_column.add_theme_constant_override("separation", 2)
	_hints_panel.add_child(hint_column)
	hint_column.add_child(_hint_row("LMB", "Move full stack"))
	hint_column.add_child(_hint_row("RMB", "Half / one item"))
	hint_column.add_child(_hint_row("Shift", "Quick move"))
	hint_column.add_child(_hint_row("Ctrl", "Select all"))
	hint_column.add_child(_hint_row("MMB / R", "Actions / amount"))
	return bottom


func _hint_row(key: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(54, 16)
	var cap_style := UiStyle.keycap_style()
	cap_style.set_content_margin_all(2)
	cap.add_theme_stylebox_override("panel", cap_style)
	var key_label := _label(key, 9, UiStyle.TEXT_SECONDARY)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(key_label)
	row.add_child(cap)
	var label := _label(text, 9, UiStyle.TEXT_SECONDARY)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


# --- Amount dialog --------------------------------------------------------

func _build_amount_dialog() -> Control:
	var root := Control.new()
	root.name = "AmountDialog"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 110
	root.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.025, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.dialog_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(_label("Select Amount", 18, UiStyle.TEXT_PRIMARY))

	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 10)
	_amount_icon = ItemIcon.new()
	_amount_icon.custom_minimum_size = Vector2(48, 48)
	item_row.add_child(_amount_icon)
	var item_text := VBoxContainer.new()
	item_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_title = _label("", 14, UiStyle.TEXT_PRIMARY)
	item_text.add_child(_amount_title)
	_amount_available = _label("", 11, UiStyle.TEXT_MUTED)
	item_text.add_child(_amount_available)
	item_row.add_child(item_text)
	column.add_child(item_row)

	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 6)
	for entry: Array in [["All", 0], ["Half", 1], ["One", 2]]:
		var button := _small_button(str(entry[0]))
		button.custom_minimum_size = Vector2(0, 28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mode := int(entry[1])
		button.pressed.connect(func() -> void: _amount_quick(mode))
		quick.add_child(button)
	column.add_child(quick)

	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 8)
	amount_row.add_child(_label("Enter Amount", 11, UiStyle.TEXT_SECONDARY))
	_amount_edit = LineEdit.new()
	_amount_edit.name = "AmountEdit"
	_amount_edit.custom_minimum_size = Vector2(76, 28)
	_amount_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_edit.add_theme_font_size_override("font_size", 13)
	_amount_edit.text_changed.connect(_on_amount_text_changed)
	_amount_edit.text_submitted.connect(func(_text: String) -> void: _commit_amount_edit())
	amount_row.add_child(_amount_edit)
	_amount_value_label = _label("", 12, UiStyle.TEXT_PRIMARY)
	_amount_value_label.custom_minimum_size = Vector2(80, 0)
	amount_row.add_child(_amount_value_label)
	column.add_child(amount_row)

	_amount_slider = HSlider.new()
	_amount_slider.name = "AmountSlider"
	_amount_slider.min_value = 1
	_amount_slider.max_value = 1
	_amount_slider.step = 1
	_amount_slider.custom_minimum_size = Vector2(0, 20)
	_amount_slider.value_changed.connect(_on_amount_slider_changed)
	column.add_child(_amount_slider)
	_amount_max_label = _label("", 10, UiStyle.TEXT_MUTED)
	column.add_child(_amount_max_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 34)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.add_theme_stylebox_override("normal", UiStyle.button_style(false))
	cancel.add_theme_stylebox_override("hover", UiStyle.button_style(false, true))
	cancel.pressed.connect(cancel_amount)
	buttons.add_child(cancel)
	_amount_confirm = Button.new()
	_amount_confirm.name = "AmountConfirm"
	_amount_confirm.text = "Confirm"
	_amount_confirm.focus_mode = Control.FOCUS_NONE
	_amount_confirm.custom_minimum_size = Vector2(0, 34)
	_amount_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_confirm.add_theme_stylebox_override("normal", UiStyle.button_style(true))
	_amount_confirm.add_theme_stylebox_override("hover", UiStyle.button_style(true, true))
	_amount_confirm.add_theme_stylebox_override("disabled", UiStyle.button_disabled_style())
	_amount_confirm.pressed.connect(confirm_amount)
	buttons.add_child(_amount_confirm)
	column.add_child(buttons)
	return root


# =========================================================================
# Navigation / pages
# =========================================================================

func nav_enabled(target: String) -> bool:
	return target != "map" and NAV_TARGETS.has(target)


func press_nav(target: String) -> bool:
	if not nav_enabled(target):
		return false
	match target:
		"inventory", "character", "crafting":
			set_page(target)
		"settings":
			navigate.emit(target)
	return true


func set_page(value: String) -> void:
	if value != PAGE_INVENTORY and value != PAGE_CHARACTER and value != PAGE_CRAFTING:
		return
	_page = value
	_active_tab = value
	_refresh_page_visibility()
	_refresh_nav()
	_refresh_all()


func page() -> String:
	return _page


func _refresh_page_visibility() -> void:
	var inventory_page := _page != PAGE_CRAFTING
	if _player_panel != null:
		_player_panel.visible = inventory_page
	if _inventory_page != null:
		_inventory_page.visible = inventory_page
	if _context_panel != null:
		_context_panel.visible = inventory_page and _page == PAGE_INVENTORY and _context_open
	if _stats_panel != null:
		_stats_panel.visible = inventory_page and _page == PAGE_CHARACTER
	if _crafting_page != null:
		_crafting_page.visible = _page == PAGE_CRAFTING
	if _rotation_row != null:
		_rotation_row.visible = _page == PAGE_CHARACTER


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
# Configuration
# =========================================================================

func set_station(station: String) -> void:
	if _station == station:
		return
	_station = station
	_refresh_crafting()


func station() -> String:
	return _station


func set_vitals(health: float, max_health: float, hunger: float, max_hunger: float,
		breath: float = Survival.MAX_BREATH, max_breath: float = Survival.MAX_BREATH,
		breath_visible: bool = false) -> void:
	if _vitals == null:
		return
	_vitals.set_vitals(health, max_health, hunger, max_hunger)
	_vitals.set_breath(breath, max_breath, breath_visible)
	if _stats_vitals != null:
		_stats_vitals.text = _vitals.summary_text()
	if _stats_health_bar != null:
		_stats_health_bar.value = 0.0 if max_health <= 0.0 else clampf(health / max_health * 100.0, 0.0, 100.0)
	if _stats_hunger_bar != null:
		_stats_hunger_bar.value = 0.0 if max_hunger <= 0.0 else clampf(hunger / max_hunger * 100.0, 0.0, 100.0)


## Real gameplay stats for the Character page.  Experience/defence/armour have
## no model and are deliberately absent.
func set_player_stats(move_speed: float) -> void:
	if _stats_speed != null:
		_stats_speed.text = "%.1f" % move_speed


func vitals_text() -> String:
	return "" if _vitals == null else _vitals.summary_text()


func equipment_slot_count() -> int:
	return _equipment_slots.size()


func equipment_enabled() -> bool:
	return false


func stats_text() -> String:
	if _stats_vitals == null:
		return ""
	return "%s · Attack %s · Speed %s" % [
		_stats_vitals.text, _stats_attack.text, _stats_speed.text,
	]


## Experience/defence/armour are not implemented; the UI says so instead of
## presenting a fabricated value.
func stats_experience_available() -> bool:
	return false


func stats_defence_available() -> bool:
	return false


## Diagnostic/test accessors for preview stability.
func character_preview_rect() -> Rect2:
	return _preview.preview_rect() if _preview != null else Rect2()


func character_preview_viewport_size() -> Vector2i:
	return _preview.viewport_size() if _preview != null else Vector2i.ZERO


func character_preview_visible() -> bool:
	return _preview != null and _preview.is_visible_in_tree()


func rotate_preview(degrees: float) -> void:
	if _preview != null:
		_preview.rotate_by(degrees)


func reset_preview_rotation() -> void:
	if _preview != null:
		_preview.reset_rotation()


# =========================================================================
# Player slots
# =========================================================================

func _make_slot(index: int, parent: Control, size: int) -> InventorySlot:
	var slot := InventorySlot.new()
	slot.name = "Slot%d" % index
	slot.configure(index, inventory, library, size)
	slot.clicked.connect(_on_slot_clicked)
	slot.stack_moved.connect(_on_stack_moved)
	slot.hovered.connect(_on_slot_hovered)
	parent.add_child(slot)
	_slots.append(slot)
	return slot


func _on_slot_hovered(index: int) -> void:
	_focus_index = index
	_update_detail()
	if _context_open and _page == PAGE_INVENTORY:
		_context_index = index
		_refresh_context()


func _on_slot_clicked(index: int, button: int, shift: bool, ctrl: bool) -> bool:
	_focus_index = index
	if button == MOUSE_BUTTON_MIDDLE:
		open_context_menu(index)
		return true
	if shift:
		var moved := quick_move(index)
		_refresh_all()
		return moved
	var select_all := ctrl
	if button == MOUSE_BUTTON_RIGHT and not select_all:
		if _carried.is_empty():
			split_half(index)
		else:
			put_one(index)
	else:
		# Left click (and Ctrl+left) moves the full stack.  It deliberately does
		# not change the hotbar selection: that is a gameplay action (1-9/wheel).
		if _carried.is_empty():
			pick_up(index)
		else:
			put_down(index)
	if _context_open and _page == PAGE_INVENTORY:
		_context_index = index
		_refresh_context()
	_refresh_all()
	return true


func click_slot(index: int, button: int = MOUSE_BUTTON_LEFT, shift: bool = false,
		ctrl: bool = false) -> bool:
	return _on_slot_clicked(index, button, shift, ctrl)


func _on_stack_moved(from_index: int, to_index: int) -> void:
	if inventory == null or not _carried.is_empty():
		return
	if inventory.move_slot(from_index, to_index):
		_focus_index = to_index
		changed_stack.emit(inventory.item_at(to_index))
	_refresh_all()


func _on_inventory_changed() -> void:
	# A hidden screen must not rebuild the recipe browser and icons on every
	# pickup while the player is in the world; opening the screen refreshes it.
	if visible:
		_refresh_all()


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
	_refresh_all()
	return true


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
		_carry_origin = index
	if not _carried.is_empty():
		changed_stack.emit(int(_carried["item"]))
	_refresh_all()
	return true


## Right-click with nothing carried: take ceil(half) of the stack.
func split_half(index: int) -> bool:
	if inventory == null or not _carried.is_empty() or inventory.is_empty(index):
		return false
	var count := inventory.count_at(index)
	return _take_amount(index, maxi(1, int(ceil(float(count) * 0.5))))


## Right-click while carrying: place exactly one item.
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
	_refresh_all()
	return true


## Shift-click: move a whole stack between the hotbar and the storage rows.
func quick_move(index: int) -> bool:
	if inventory == null or not _carried.is_empty():
		return false
	if not inventory.quick_move(index):
		return false
	_focus_index = index
	changed_stack.emit(inventory.item_at(index))
	_refresh_all()
	return true


func swap(a: int, b: int) -> bool:
	if inventory == null or not _carried.is_empty() or not inventory.swap_slots(a, b):
		return false
	_refresh_all()
	return true


func carried() -> Dictionary:
	return _carried.duplicate()


func slot_count() -> int:
	return _slots.size()


func slot_count_text(index: int) -> String:
	for slot: InventorySlot in _slots:
		if slot.index == index:
			return (slot._count as Label).text
	return ""


func detail_text() -> String:
	return _detail_label.text if _detail_label != null else ""


func focus_slot(index: int) -> void:
	_focus_index = clampi(index, 0, Inventory.SIZE - 1)
	_update_detail()
	if _context_open and _page == PAGE_INVENTORY:
		_context_index = _focus_index
		_refresh_context()


func focused_index() -> int:
	return _focus_index


# =========================================================================
# Context actions
# =========================================================================

func open_context_menu(index: int) -> bool:
	if index < 0 or index >= Inventory.SIZE:
		return false
	_context_index = index
	_context_open = true
	_focus_index = index
	_context_panel.visible = _page == PAGE_INVENTORY
	_update_detail()
	_refresh_context()
	return true


func close_context_menu() -> void:
	_context_open = false
	if _context_panel != null:
		_context_panel.visible = false


func context_menu_open() -> bool:
	return _context_open


func context_actions() -> Array:
	var actions: Array = []
	if _context_index < 0 or _context_index >= Inventory.SIZE:
		return actions
	if not _carried.is_empty():
		actions.append(ACTION_CANCEL)
		return actions
	if inventory.is_empty(_context_index):
		return actions
	actions.append(ACTION_ALL)
	if inventory.count_at(_context_index) > 1:
		actions.append(ACTION_HALF)
	actions.append(ACTION_ONE)
	actions.append(ACTION_AMOUNT)
	actions.append(ACTION_QUICK)
	if _context_index >= Inventory.HOTBAR_SIZE:
		actions.append(ACTION_MOVE)
	actions.append(ACTION_CANCEL)
	return actions


func activate_context(action: String) -> bool:
	if _context_index < 0 or _context_index >= Inventory.SIZE:
		return false
	match action:
		ACTION_ALL:
			return _take_amount(_context_index, inventory.count_at(_context_index))
		ACTION_HALF:
			var half := maxi(1, int(ceil(float(inventory.count_at(_context_index)) * 0.5)))
			return _take_amount(_context_index, half)
		ACTION_ONE:
			return _take_amount(_context_index, 1)
		ACTION_AMOUNT:
			return open_amount_dialog(_context_index) > 0
		ACTION_QUICK:
			return quick_move(_context_index)
		ACTION_MOVE:
			if _context_index < Inventory.HOTBAR_SIZE:
				return _move_to_storage(_context_index)
			return _move_to_hotbar(_context_index)
		ACTION_CANCEL:
			if not _carried.is_empty():
				flush_cursor()
			close_context_menu()
			return true
	return false


## Takes `amount` from a slot into the cursor, leaving the rest in the slot.
func _take_amount(index: int, amount: int) -> bool:
	if inventory == null or not _carried.is_empty() or inventory.is_empty(index):
		return false
	var wanted := clampi(amount, 1, inventory.count_at(index))
	var whole := inventory.take_stack(index)
	if whole.is_empty():
		return false
	var take := mini(wanted, int(whole["count"]))
	var remainder := {
		"item": int(whole["item"]),
		"count": int(whole["count"]) - take,
		"durability": int(whole.get("durability", 0)),
	}
	if int(remainder["count"]) > 0:
		inventory.put_stack(index, remainder)
	_carried = {"item": int(whole["item"]), "count": take,
		"durability": int(whole.get("durability", 0))}
	_carry_origin = index
	_focus_index = index
	changed_stack.emit(int(_carried["item"]))
	_refresh_all()
	return true


## Moves a storage stack into the first suitable hotbar slot (or merges).
func _move_to_hotbar(index: int) -> bool:
	if index < Inventory.HOTBAR_SIZE or inventory.is_empty(index):
		return false
	if inventory.quick_move(index):
		_focus_index = index
		_refresh_all()
		return true
	return false


## Moves a hotbar stack into the first suitable storage slot (or merges).
func _move_to_storage(index: int) -> bool:
	if index >= Inventory.HOTBAR_SIZE or inventory.is_empty(index):
		return false
	if inventory.quick_move(index):
		_focus_index = index
		_refresh_all()
		return true
	return false


func _refresh_context() -> void:
	if _context_panel == null:
		return
	if not _context_open or _page != PAGE_INVENTORY or _context_index < 0:
		_context_panel.visible = false
		return
	var item_id := inventory.item_at(_context_index)
	var count := inventory.count_at(_context_index)
	var empty := item_id == BlockDB.AIR or count <= 0
	_context_panel.visible = true
	_context_icon.set_item(item_id, library, ItemDB.icon_tint(item_id))
	_context_title.text = ItemDB.name_of(item_id) if not empty else "Empty slot"
	_context_count.text = "" if empty else ("×%d" % count)
	var available := context_actions()
	for action: String in _context_buttons:
		var button := _context_buttons[action] as Button
		var valid := available.has(action)
		button.visible = valid or action == ACTION_CANCEL
		button.disabled = not valid
	if _context_move_button != null:
		_context_move_button.text = "Move to Storage" if _context_index < Inventory.HOTBAR_SIZE else "Move to Hotbar"


# =========================================================================
# Amount dialog
# =========================================================================

## Opens the quantity dialog for a slot.  With an empty cursor this selects an
## amount to pick up; with a carried stack it selects an amount to place into
## the slot.  Returns the maximum selectable amount (0 when the action is invalid).
func open_amount_dialog(index: int) -> int:
	if inventory == null or index < 0 or index >= Inventory.SIZE:
		return 0
	if _amount_dialog == null:
		return 0
	var item_id := BlockDB.AIR
	var maximum := 0
	var take_mode := _carried.is_empty()
	if take_mode:
		if inventory.is_empty(index):
			return 0
		item_id = inventory.item_at(index)
		maximum = inventory.count_at(index)
	else:
		item_id = int(_carried["item"])
		if inventory.is_empty(index):
			maximum = mini(int(_carried["count"]), ItemDB.max_stack(item_id))
		elif inventory.item_at(index) == item_id:
			maximum = mini(int(_carried["count"]),
				maxi(0, ItemDB.max_stack(item_id) - inventory.count_at(index)))
		else:
			return 0
	if maximum <= 0:
		return 0
	_amount_slot = index
	_amount_take = take_mode
	_amount_max = maximum
	_focus_index = index
	_update_detail()
	if _context_open and _page == PAGE_INVENTORY:
		_context_index = index
		_refresh_context()
	var initial := maxi(1, int(ceil(float(maximum) * 0.5)))
	_amount_slider.min_value = 1
	_amount_slider.max_value = maximum
	_amount_icon.set_item(item_id, library, ItemDB.icon_tint(item_id))
	_amount_title.text = ItemDB.name_of(item_id)
	_amount_available.text = ("Available: %d" % maximum) if take_mode \
		else ("Carrying: %d · Room: %d" % [int(_carried["count"]), maximum])
	_amount_max_label.text = "1 – %d" % maximum
	_amount_confirm.disabled = false
	_amount_dialog.visible = true
	set_amount_value(initial)
	return maximum


func amount_dialog_open() -> bool:
	return _amount_dialog != null and _amount_dialog.visible


func amount_value() -> int:
	return _amount_value


func amount_max() -> int:
	return _amount_max


func amount_slot() -> int:
	return _amount_slot


func set_amount_value(value: int) -> void:
	if not amount_dialog_open():
		return
	_amount_value = clampi(value, 1, _amount_max)
	_amount_updating = true
	_amount_slider.value = _amount_value
	_amount_edit.text = str(_amount_value)
	_amount_value_label.text = "%d / %d" % [_amount_value, _amount_max]
	_amount_updating = false


func _on_amount_slider_changed(value: float) -> void:
	if _amount_updating:
		return
	set_amount_value(int(round(value)))


func _on_amount_text_changed(text: String) -> void:
	if _amount_updating:
		return
	if text.strip_edges().is_empty():
		return
	if text.is_valid_int():
		set_amount_value(text.to_int())


func _commit_amount_edit() -> void:
	set_amount_value(_amount_edit.text.to_int() if _amount_edit.text.is_valid_int() else _amount_value)


func _amount_quick(mode: int) -> void:
	match mode:
		0:
			set_amount_value(_amount_max)
		1:
			set_amount_value(maxi(1, int(ceil(float(_amount_max) * 0.5))))
		_:
			set_amount_value(1)


func confirm_amount() -> bool:
	if not amount_dialog_open():
		return false
	var chosen := clampi(_amount_value, 1, _amount_max)
	var ok := false
	if _amount_take:
		ok = _take_amount(_amount_slot, chosen)
	else:
		ok = _place_amount(_amount_slot, chosen)
	_amount_dialog.visible = false
	_refresh_all()
	return ok


func cancel_amount() -> void:
	if _amount_dialog != null:
		_amount_dialog.visible = false


func _place_amount(index: int, amount: int) -> bool:
	if _carried.is_empty() or index < 0 or index >= Inventory.SIZE:
		return false
	var item_id := int(_carried["item"])
	var one := {"item": item_id, "count": amount,
		"durability": int(_carried.get("durability", 0))}
	var leftover: Dictionary = inventory.put_stack(index, one)
	var placed := amount - int(leftover.get("count", 0))
	if placed <= 0:
		return false
	_carried["count"] = int(_carried["count"]) - placed
	if int(_carried["count"]) <= 0:
		_carried = {}
		_carry_origin = -1
	_focus_index = index
	_refresh_all()
	return true


func handle_cancel() -> bool:
	if amount_dialog_open():
		cancel_amount()
		return true
	if _context_open:
		close_context_menu()
		return true
	if not _carried.is_empty():
		return flush_cursor()
	return false


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			if amount_dialog_open():
				cancel_amount()
			elif not _carried.is_empty():
				flush_cursor()
			else:
				close_context_menu()
			_refresh_all()


# =========================================================================
# Crafting page
# =========================================================================

func set_craft_category(category: String) -> void:
	_crafting_category = category
	_refresh_recipe_tiles()
	_ensure_visible_selection()
	_refresh_crafting()


func craft_category() -> String:
	return _crafting_category


func set_craft_search(text: String) -> void:
	_crafting_search = text.strip_edges().to_lower()
	_refresh_recipe_tiles()
	_ensure_visible_selection()
	_refresh_crafting()


func craft_search_text() -> String:
	return _crafting_search


func visible_recipe_count() -> int:
	var count := 0
	for entry: Dictionary in _recipe_tiles:
		if (entry["button"] as Control).visible:
			count += 1
	return count


func visible_recipe_ids() -> Array:
	var ids: Array = []
	for entry: Dictionary in _recipe_tiles:
		if (entry["button"] as Control).visible:
			ids.append(str((entry["recipe"] as Dictionary)["id"]))
	return ids


func recipe_count() -> int:
	return _recipe_tiles.size()


func recipe_is_craftable(id: String) -> bool:
	var recipe := Crafting.recipe(id)
	if recipe.is_empty() or inventory == null:
		return false
	return Crafting.can_craft(inventory, recipe, _station)


func select_recipe(id: String) -> bool:
	var recipe := Crafting.recipe(id)
	if recipe.is_empty():
		return false
	_selected_recipe_id = id
	_craft_quantity = 1
	_refresh_recipe_tiles()
	_refresh_crafting()
	call_deferred("_scroll_selected_recipe")
	return true


## Keeps the selected recipe visible in the scrollable browser, so the blue
## selection highlight is never hidden below the fold.
func _scroll_selected_recipe() -> void:
	if _recipe_grid_scroll == null or _selected_recipe_id.is_empty():
		return
	for entry: Dictionary in _recipe_tiles:
		if str((entry["recipe"] as Dictionary)["id"]) == _selected_recipe_id:
			var button := entry["button"] as Control
			if button.visible:
				_recipe_grid_scroll.ensure_control_visible(button)
			return


func selected_recipe_id() -> String:
	return _selected_recipe_id


func selected_recipe() -> Dictionary:
	return Crafting.recipe(_selected_recipe_id) if not _selected_recipe_id.is_empty() else {}


func set_craft_quantity(value: int) -> void:
	var maximum := max_craft_quantity()
	if maximum <= 0:
		_craft_quantity = 1
	else:
		_craft_quantity = clampi(value, 1, maximum)
	_refresh_quantity()


func craft_quantity() -> int:
	return _craft_quantity


func max_craft_quantity() -> int:
	var recipe := selected_recipe()
	if recipe.is_empty() or inventory == null:
		return 0
	if not Crafting.station_satisfied(recipe, _station):
		return 0
	var ingredient_limit := Crafting.craftable_count(inventory, recipe, _station)
	if ingredient_limit <= 0:
		return 0
	ingredient_limit = mini(ingredient_limit, 999)
	for count in range(ingredient_limit, 0, -1):
		if Crafting.can_craft_times(inventory, recipe, count, _station):
			return count
	return 0


## Crafts the selected recipe at the selected quantity.  `Crafting.craft_many`
## is atomic, so a failed transaction consumes nothing.
func craft_selected() -> bool:
	var recipe := selected_recipe()
	if recipe.is_empty() or inventory == null:
		return false
	var maximum := max_craft_quantity()
	if maximum <= 0:
		_refresh_crafting()
		return false
	var quantity := clampi(_craft_quantity, 1, maximum)
	var result: Dictionary = Crafting.craft_many(inventory, recipe, quantity, _station)
	crafted.emit(result)
	_refresh_all()
	return bool(result.get("ok", false))


func craft_status_text() -> String:
	return "" if _craft_status == null else _craft_status.text


## Compatibility-ish diagnostics used by the runtime test and captures.
func row_count() -> int:
	return _recipe_tiles.size()


func row_enabled(id: String) -> bool:
	return recipe_is_craftable(id)


func row_status(id: String) -> String:
	var recipe := Crafting.recipe(id)
	if recipe.is_empty():
		return ""
	if not Crafting.station_satisfied(recipe, _station):
		return "needs %s" % _station_name(Crafting.station_of(recipe))
	var missing := Crafting.missing(inventory, recipe, _station)
	if not missing.is_empty():
		return "missing %s" % _shortfall(missing)
	if not Crafting.can_craft(inventory, recipe, _station):
		return "inventory full"
	return "ready"


func press_craft(id: String, batch: bool = false) -> bool:
	if not select_recipe(id):
		return false
	if batch:
		set_craft_quantity(5)
	return craft_selected()


func debug_open_amount(index: int, quantity: int = -1) -> bool:
	var maximum := open_amount_dialog(index)
	if maximum <= 0:
		return false
	if quantity > 0:
		set_amount_value(quantity)
	return true


func debug_open_context(index: int) -> bool:
	return open_context_menu(index)


func _refresh_recipe_tiles() -> void:
	var selected := _selected_recipe_id
	for entry: Dictionary in _recipe_tiles:
		var recipe: Dictionary = entry["recipe"]
		var button := entry["button"] as Button
		var search_ok := _crafting_search.is_empty() or _recipe_matches_search(recipe)
		var category_ok := _crafting_category.is_empty() or str(recipe["category"]) == _crafting_category
		button.visible = search_ok and category_ok
		var is_selected := str(recipe["id"]) == selected
		button.add_theme_stylebox_override("normal",
			UiStyle.recipe_tile_style(is_selected))
		button.add_theme_stylebox_override("hover",
			UiStyle.recipe_tile_style(is_selected, true))
		button.add_theme_stylebox_override("pressed", UiStyle.recipe_tile_style(true))
		if not recipe_is_craftable(str(recipe["id"])):
			button.modulate = Color(1, 1, 1, 0.55)
		else:
			button.modulate = Color.WHITE
	if _recipe_count_label != null:
		_recipe_count_label.text = "%d shown" % visible_recipe_count()
	if _crafting_category_buttons.has(_crafting_category):
		for key: String in _crafting_category_buttons:
			var button := _crafting_category_buttons[key] as Button
			button.add_theme_stylebox_override("normal",
				UiStyle.category_style(key == _crafting_category))
			button.add_theme_stylebox_override("hover", UiStyle.category_style(key == _crafting_category, true))
			button.add_theme_stylebox_override("pressed", UiStyle.category_style(true))


## If the selected recipe no longer matches the visible category/search, move the
## selection to the first visible recipe (or clear it), so the details panel can
## never describe a recipe the browser has hidden.
func _ensure_visible_selection() -> void:
	if _selected_recipe_id.is_empty():
		return
	for entry: Dictionary in _recipe_tiles:
		if str((entry["recipe"] as Dictionary)["id"]) == _selected_recipe_id:
			if (entry["button"] as Control).visible:
				return
			break
	for entry: Dictionary in _recipe_tiles:
		if (entry["button"] as Control).visible:
			select_recipe(str((entry["recipe"] as Dictionary)["id"]))
			return
	_selected_recipe_id = ""
	_refresh_crafting()


func _recipe_matches_search(recipe: Dictionary) -> bool:
	var haystack := "%s %s %s %s" % [
		ItemDB.name_of(int(recipe["output"])), str(recipe["id"]),
		str(recipe["category"]), Crafting.label(recipe),
	]
	for item_id in Crafting.ingredients(recipe):
		haystack += " " + ItemDB.name_of(int(item_id))
	return haystack.to_lower().contains(_crafting_search)


func _refresh_crafting() -> void:
	if _craft_status == null:
		return
	_refresh_recipe_tiles()
	var recipe := selected_recipe()
	var maximum := max_craft_quantity()
	if recipe.is_empty():
		_craft_title.text = "Select a recipe"
		_craft_desc.text = "Choose a recipe from the browser."
		for cell: ItemIcon in _craft_preview:
			cell.set_item(BlockDB.AIR, library)
		_craft_output_icon.set_item(BlockDB.AIR, library)
		_craft_output_count.text = ""
		for child: Node in _craft_ingredients.get_children():
			child.queue_free()
		_craft_station_title.text = "Crafting Table"
		_craft_station_text.text = _station_note()
		_craft_quantity_label.text = "1"
		_craft_max_label.text = "Max 0"
		_craft_status.text = "Select a recipe to see its ingredients."
		_craft_status.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
		_craft_button.disabled = true
		return
	var output := int(recipe["output"])
	_craft_title.text = ItemDB.name_of(output)
	_craft_desc.text = "%s · %s" % [str(recipe["category"]), _station_name(Crafting.station_of(recipe))]
	_craft_output_icon.set_item(output, library, ItemDB.icon_tint(output))
	_craft_output_count.text = "×%d" % int(recipe["output_count"])
	_refresh_recipe_pattern(recipe)
	_craft_station_title.text = _station_name(Crafting.station_of(recipe))
	_craft_station_text.text = _station_note()
	if maximum <= 0:
		_craft_quantity = 1
		_craft_quantity_label.text = "1"
		_craft_max_label.text = "Max 0"
	else:
		_craft_quantity = clampi(_craft_quantity, 1, maximum)
		_craft_quantity_label.text = str(_craft_quantity)
		_craft_max_label.text = "Max %d" % maximum
	_craft_button.disabled = maximum <= 0
	_refresh_quantity()
	var status := ""
	var colour := UiStyle.TEXT_MUTED
	if not Crafting.station_satisfied(recipe, _station):
		status = "Requires a %s" % _station_name(Crafting.station_of(recipe))
		colour = UiStyle.BLOCKED
	elif not Crafting.missing(inventory, recipe, _station).is_empty():
		status = "Missing: %s" % _shortfall(Crafting.missing(inventory, recipe, _station))
		colour = UiStyle.MISSING
	elif maximum <= 0:
		status = "Not enough room for the output"
		colour = UiStyle.BLOCKED
	else:
		status = "Ready to craft" if _craft_quantity == 1 else "Ready to craft ×%d" % _craft_quantity
		colour = UiStyle.READY
	_craft_status.text = status
	_craft_status.add_theme_color_override("font_color", colour)


func _refresh_quantity() -> void:
	if _craft_quantity_label == null:
		return
	_craft_quantity_label.text = str(_craft_quantity)
	# Re-render ingredient requirements for the selected quantity.
	var recipe := selected_recipe()
	if not recipe.is_empty():
		_refresh_ingredient_rows(recipe, max_craft_quantity())


func _refresh_recipe_pattern(recipe: Dictionary) -> void:
	for cell: ItemIcon in _craft_preview:
		cell.set_item(BlockDB.AIR, library)
		cell.set_ghost(false)
	if recipe.has("pattern") and recipe.has("key"):
		var pattern: Array = recipe["pattern"]
		var key: Dictionary = recipe["key"]
		for row in mini(3, pattern.size()):
			var line := str(pattern[row])
			for column in mini(3, line.length()):
				var symbol := line[column]
				if symbol == " ":
					continue
				var item_id := int(key.get(symbol, BlockDB.AIR))
				if item_id != BlockDB.AIR:
					_craft_preview[row * 3 + column].set_item(item_id, library,
						ItemDB.icon_tint(item_id))
	else:
		var item_ids: Array = []
		for item_id in Crafting.ingredients(recipe):
			item_ids.append(int(item_id))
		item_ids.sort()
		for index in mini(9, item_ids.size()):
			_craft_preview[index].set_item(int(item_ids[index]), library,
				ItemDB.icon_tint(int(item_ids[index])))
	for cell: ItemIcon in _craft_preview:
		cell.set_ghost(true)


func _refresh_ingredient_rows(recipe: Dictionary, maximum: int) -> void:
	for child: Node in _craft_ingredients.get_children():
		child.queue_free()
	var rows: Array = []
	var ingredients := Crafting.ingredients(recipe)
	for item_id in ingredients:
		rows.append({"item": int(item_id), "need": int(ingredients[item_id]), "fuel": false})
	var fuel := Crafting.fuel(recipe)
	for item_id in fuel:
		rows.append({"item": int(item_id), "need": int(fuel[item_id]), "fuel": true})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["item"]) < str(b["item"]))
	var quantity := maxi(1, _craft_quantity)
	for row: Dictionary in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var icon := ItemIcon.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.set_item(int(row["item"]), library, ItemDB.icon_tint(int(row["item"])))
		line.add_child(icon)
		var name_label := _label(ItemDB.name_of(int(row["item"])) + (" (fuel)" if bool(row["fuel"]) else ""),
			11, UiStyle.TEXT_SECONDARY)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var need := int(row["need"]) * quantity
		var have := inventory.count_of(int(row["item"]))
		var amount_label := _label("%d / %d" % [mini(have, need), need], 11,
			UiStyle.READY if have >= need else UiStyle.MISSING)
		line.add_child(amount_label)
		_craft_ingredients.add_child(line)


func _station_name(station: String) -> String:
	match station:
		Crafting.STATION_TABLE:
			return "Crafting Table"
		Crafting.STATION_FURNACE:
			return "Furnace"
	return "Hand"


func _station_note() -> String:
	var table_rank := int(Crafting.STATION_RANK.get(Crafting.STATION_TABLE, 1))
	var have := int(Crafting.STATION_RANK.get(_station, 0))
	if have >= table_rank:
		return "A crafting station is nearby."
	return "Craft more advanced items using a crafting table."


# =========================================================================
# Refresh
# =========================================================================

func _refresh_all() -> void:
	if inventory == null or _detail_label == null:
		return
	for slot: InventorySlot in _slots:
		slot.selected = slot.index == inventory.selected
		slot.override_stack = {}
		slot.refresh()
	_cursor.set_stack(_carried)
	if _storage_label != null:
		_storage_label.text = "%d slots · %d free" % [Inventory.MAIN_SIZE, inventory.free_slot_count()]
	_update_detail()
	_update_held()
	_refresh_context()
	_refresh_crafting()
	_refresh_vitals()


func _refresh_vitals() -> void:
	if _stats_vitals != null and _vitals != null:
		_stats_vitals.text = _vitals.summary_text()
	if _stats_attack != null and inventory != null:
		var item_id := inventory.selected_item()
		var attack := 1.0 if item_id == BlockDB.AIR else ItemDB.attack_damage(item_id)
		_stats_attack.text = "%.1f" % attack
	if _stats_held != null and inventory != null:
		var item_id := inventory.selected_item()
		_stats_held.text = "Empty" if item_id == BlockDB.AIR else ItemDB.name_of(item_id)


func _update_held() -> void:
	if inventory == null:
		return
	var held_icon := find_child("HeldIcon", true, false) as ItemIcon
	var held_label := find_child("HeldLabel", true, false) as Label
	var item_id := inventory.selected_item()
	if held_icon != null:
		held_icon.set_item(item_id, library, ItemDB.icon_tint(item_id))
	if held_label != null:
		if item_id == BlockDB.AIR:
			held_label.text = "Hand: empty"
		else:
			held_label.text = "Hand: %s" % ItemDB.name_of(item_id)
			var maximum := ItemDB.max_durability(item_id)
			if maximum > 0:
				held_label.text += "  %d / %d" % [inventory.durability_of(inventory.selected), maximum]


func _update_detail() -> void:
	if _detail_label == null or inventory == null:
		return
	var item_id := inventory.item_at(_focus_index)
	if item_id == BlockDB.AIR and not _carried.is_empty():
		item_id = int(_carried["item"])
	if item_id == BlockDB.AIR:
		_detail_label.text = "No item selected. Hover a slot, pick one up, or press 1-9 in game."
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
	_detail_label.text = "\n".join(lines)


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


func _shortfall(missing: Dictionary) -> String:
	var parts: Array = []
	var keys: Array = missing.keys()
	keys.sort()
	for item_id in keys:
		parts.append("%d more %s" % [int(missing[item_id]), ItemDB.name_of(int(item_id))])
	return " + ".join(parts)


# =========================================================================
# Ownership / visibility
# =========================================================================

func open() -> void:
	_refresh_all()
	visible = true
	_refresh_page_visibility()
	_refresh_nav()
	# The reference's main inventory opens with the item-actions card beside the
	# selected stack.  It is a real context menu, not decoration: its buttons use
	# the same transfer rules as the slots.
	if _page == PAGE_INVENTORY and inventory != null and not inventory.is_empty(inventory.selected):
		open_context_menu(inventory.selected)
	opened.emit()


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


## No transient crafting grid exists on the screen any more, so flushing is the
## cursor plus dialog/menu state.  Kept as the save/close choke point.
func flush_all() -> bool:
	if not flush_cursor():
		return false
	cancel_amount()
	close_context_menu()
	return true


func _recover_cursor() -> Dictionary:
	var leftover := _carried
	if _carry_origin >= 0 and _carry_origin < Inventory.SIZE:
		if inventory.is_empty(_carry_origin) \
				or inventory.item_at(_carry_origin) == int(_carried["item"]):
			leftover = inventory.put_stack(_carry_origin, leftover)
	if not leftover.is_empty():
		leftover = inventory.add_stack(leftover)
	return leftover


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


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label
