class_name InventoryPanel
extends Control

## Full player inventory interface (M20).
##
## Minecraft-like layout: a 9x3 main grid above the nine-slot hotbar, with the
## selected hotbar slot highlighted.  Moving a stack with the mouse uses a
## temporary cursor stack (drawn under the pointer), never a permanent "carrying
## slot"; the item in the player's hand is always the selected hotbar slot.
##
## Presentation and intent only: every mutation goes through `Inventory`, and the
## recipe facts come from `Crafting`, so the interface can never invent state.

signal changed_stack(item_id: int)
signal message(text: String)

const PANEL_WIDTH := 900
const DETAIL_WIDTH := 274
const GRID_GAP := 5
const ROW_GAP := 14

var inventory: Inventory
var library: TextureLibrary

var _slots: Array[InventorySlot] = []
var _detail: Label
var _hint: Label
var _cursor: ItemCursor
var _carried: Dictionary = {}
var _carry_origin := -1
var _focus_index := 0


func setup(player_inventory: Inventory, texture_library: TextureLibrary = null) -> void:
	inventory = player_inventory
	library = texture_library
	_build()
	if inventory != null and not inventory.changed.is_connected(_refresh):
		inventory.changed.connect(_refresh)
	visible = false
	_refresh()


# --- construction --------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.60)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	box.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	box.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)

	var title_row := HBoxContainer.new()
	left.add_child(title_row)
	var title := _label("INVENTORY", 21, UiStyle.TEXT_PRIMARY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var selected_label := _label("", 13, UiStyle.TEXT_SECONDARY)
	selected_label.name = "SelectedLabel"
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(selected_label)

	var main_label := _label("STORAGE", 11, UiStyle.TEXT_MUTED)
	left.add_child(main_label)
	var main_grid := GridContainer.new()
	main_grid.name = "MainSlots"
	main_grid.columns = Inventory.HOTBAR_SIZE
	main_grid.add_theme_constant_override("h_separation", GRID_GAP)
	main_grid.add_theme_constant_override("v_separation", GRID_GAP)
	left.add_child(main_grid)
	for index in range(Inventory.MAIN_FIRST, Inventory.SIZE):
		var slot := _make_slot(index, main_grid)
		slot.show_number = false

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ROW_GAP)
	left.add_child(spacer)

	var hotbar_label := _label("HOTBAR  ·  the selected slot is the item in your hand", 11, UiStyle.TEXT_MUTED)
	left.add_child(hotbar_label)
	var hotbar := HBoxContainer.new()
	hotbar.name = "HotbarSlots"
	hotbar.add_theme_constant_override("separation", GRID_GAP)
	left.add_child(hotbar)
	for index in Inventory.HOTBAR_SIZE:
		_make_slot(index, hotbar)

	_hint = _label("Left click: pick up / place · Right click: split / place one · "
		+ "Shift-click: move hotbar ↔ storage · Drag: reorder · I or Esc closes",
		12, UiStyle.TEXT_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(590, 0)
	left.add_child(_hint)

	var detail_box := PanelContainer.new()
	detail_box.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail_box.add_theme_stylebox_override("panel", UiStyle.detail_style())
	columns.add_child(detail_box)
	_detail = _label("", 13, Color(0.88, 0.93, 0.99))
	_detail.custom_minimum_size = Vector2(DETAIL_WIDTH - 24, 0)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(_detail)

	# The cursor stack is an overlay, not a slot in any grid.
	_cursor = ItemCursor.new()
	_cursor.name = "CursorStack"
	add_child(_cursor)
	_cursor.setup(library)


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


func _make_slot(index: int, parent: Control) -> InventorySlot:
	var slot := InventorySlot.new()
	slot.name = "Slot%d" % index
	slot.configure(index, inventory, library)
	slot.clicked.connect(_on_slot_clicked)
	slot.stack_moved.connect(_on_stack_moved)
	slot.hovered.connect(func(hovered_index: int) -> void: _focus_index = hovered_index)
	parent.add_child(slot)
	_slots.append(slot)
	return slot


# --- interaction ---------------------------------------------------------

func _on_slot_clicked(index: int, button: int, shift: bool) -> void:
	_focus_index = index
	if index < Inventory.HOTBAR_SIZE and inventory != null:
		# An explicit click on a hotbar slot is a selection action, exactly like
		# pressing 1-9 in the world. Merely opening the panel never changes it.
		inventory.select(index)
	if shift:
		quick_move(index)
		_refresh()
		return
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


## Diagnostic/test entry: runs the same handler a real slot click uses.
func click_slot(index: int, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	_on_slot_clicked(index, button, shift)


func slot_count() -> int:
	return _slots.size()


## Text of a slot's count badge (empty when the count is 1 or the slot is empty).
## Diagnostic accessor for the runtime test.
func slot_count_text(index: int) -> String:
	for slot: InventorySlot in _slots:
		if slot.index == index:
			return (slot._count as Label).text
	return ""


## Text of the item facts pane, for diagnostics.
func detail_text() -> String:
	return _detail.text


## Focuses a slot for the item facts pane.  A hotbar slot also becomes the item
## held in the world, because that is what clicking it means.
func focus_slot(index: int) -> void:
	_focus_index = clampi(index, 0, Inventory.SIZE - 1)
	if inventory != null and _focus_index < Inventory.HOTBAR_SIZE:
		inventory.select(_focus_index)
	_refresh()


# --- state ---------------------------------------------------------------

func _refresh() -> void:
	if inventory == null or _detail == null:
		return
	var selected := inventory.selected
	for slot: InventorySlot in _slots:
		slot.selected = slot.index == selected
		slot.override_stack = {}
		slot.refresh()
	_cursor.set_stack(_carried)
	var selected_label := find_child("SelectedLabel", true, false) as Label
	if selected_label != null:
		var selected_item := inventory.selected_item()
		selected_label.text = "Hand: %s" % ("empty" if selected_item == BlockDB.AIR
			else ItemDB.name_of(selected_item))
	_hint.text = "Left click: take/place · Right click: split/one · " \
		+ "Shift-click: move hotbar ↔ storage · Drag: reorder · I/Esc closes"
	_update_detail()


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


# --- visibility ----------------------------------------------------------

func open() -> void:
	_refresh()
	visible = true


## Puts the cursor stack back into the inventory model, preferring its origin
## slot.  Returns whatever could not be stored.  `_carried` still owns it.
func _recover_cursor() -> Dictionary:
	var leftover := _carried
	if _carry_origin >= 0 and _carry_origin < Inventory.SIZE:
		if inventory.is_empty(_carry_origin) \
				or inventory.item_at(_carry_origin) == int(_carried["item"]):
			leftover = inventory.put_stack(_carry_origin, leftover)
	if not leftover.is_empty():
		leftover = inventory.add_stack(leftover)
	return leftover


## Returns the temporary cursor stack to the model *without* closing the panel,
## so a save always contains every owned item.  Returns false when there is
## genuinely no room; the stack stays on the cursor (nothing is destroyed), and
## the caller must not treat the model as complete.
func flush_cursor() -> bool:
	if _carried.is_empty() or inventory == null:
		return true
	_carried = _recover_cursor()
	if _carried.is_empty():
		_carry_origin = -1
	_cursor.set_stack(_carried)
	return _carried.is_empty()


## Closes the interface, recovering a cursor stack:
##   1. back into its original slot when that slot is still available,
##   2. otherwise into any matching/empty slot,
##   3. otherwise the panel stays open and explains why, so nothing is deleted.
## Returns true when the panel actually closed.
func close() -> bool:
	if not _carried.is_empty() and inventory != null:
		if not flush_cursor():
			message.emit("No room for %d %s — make space before closing" % [
				int(_carried["count"]), ItemDB.name_of(int(_carried["item"]))])
			return false
	_cursor.set_stack({})
	visible = false
	return true


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible
