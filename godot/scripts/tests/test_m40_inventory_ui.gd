extends RefCounted

## M40 v2 — inventory, character and crafting UI contract.
##
## Every test drives the real interface handlers and reads the real `Inventory` /
## `Crafting` state.  The suite covers the reported defects (preview stability,
## click semantics, navigation, crafting depth), the explicit context/amount
## model, atomic crafting, and ownership conservation.

func name() -> String:
	return "M40 inventory UI"


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _panel(inventory: Inventory, station: String = Crafting.STATION_HAND) -> InventoryPanel:
	var panel := InventoryPanel.new()
	panel.setup(inventory, null)
	_root().add_child(panel)
	panel.set_station(station)
	panel.set_page(InventoryPanel.PAGE_INVENTORY)
	panel.open()
	return panel


func _owned(inventory: Inventory, carried: Dictionary = {}) -> Dictionary:
	var totals := {}
	for index in inventory.size():
		if inventory.is_empty(index):
			continue
		var item_id := inventory.item_at(index)
		totals[item_id] = int(totals.get(item_id, 0)) + inventory.count_at(index)
	if not carried.is_empty():
		var item_id := int(carried.get("item", BlockDB.AIR))
		totals[item_id] = int(totals.get(item_id, 0)) + int(carried.get("count", 0))
	return totals


func _valid_stacks(h: TestHarness, inventory: Inventory, label: String) -> void:
	var valid := true
	for index in inventory.size():
		if inventory.counts[index] < 0:
			valid = false
		if inventory.counts[index] > ItemDB.max_stack(inventory.slots[index]):
			valid = false
		if inventory.counts[index] == 0 and inventory.slots[index] != BlockDB.AIR:
			valid = false
	h.check(valid, "stack counts stay valid after %s" % label)


# =========================================================================
# Stack movement and the explicit click model
# =========================================================================

func _test_moves(h: TestHarness) -> void:
	h.section("M40 inventory movement")
	var inventory := Inventory.new()
	inventory.put_stack(0, {"item": BlockDB.STONE, "count": 12})
	var panel := _panel(inventory)
	var before := _owned(inventory, panel.carried())

	h.check(panel.pick_up(0), "left-click takes the full stack")
	h.check(inventory.is_empty(0), "taking the full stack clears the source")
	h.check(panel.put_down(20), "left-click places the full stack")
	h.eq(inventory.slots[20], BlockDB.STONE, "the stack arrived in the target")
	h.eq(inventory.counts[20], 12, "the full count moved, not one item")
	h.eq(_owned(inventory, panel.carried()), before, "full-stack movement conserves items")

	# Clicking an occupied slot while carrying a compatible stack merges it.
	inventory.clear_slot(20)
	inventory.put_stack(20, {"item": BlockDB.STONE, "count": 60})
	inventory.put_stack(21, {"item": BlockDB.STONE, "count": 10})
	before = _owned(inventory, panel.carried())
	h.check(panel.pick_up(21), "the merge source is picked up")
	h.check(panel.put_down(20), "a compatible target merges the stack")
	h.eq(inventory.counts[20], 64, "the target is capped at the stack size")
	h.eq(int(panel.carried().get("count", 0)), 6, "the overflow stays carried")
	h.eq(_owned(inventory, panel.carried()), before, "merging conserves items")
	h.check(panel.put_down(21), "the overflow returns to its source")

	# Right-click splits with the documented ceil(half) rule.
	inventory.clear_slot(20)
	inventory.clear_slot(21)
	inventory.put_stack(20, {"item": BlockDB.STONE, "count": 9})
	before = _owned(inventory, panel.carried())
	h.check(panel.split_half(20), "right-click splits the stack")
	h.eq(int(panel.carried().get("count", 0)), 5, "the split uses ceil(half)")
	h.eq(inventory.count_at(20), 4, "the remainder stays in the source")
	h.eq(_owned(inventory, panel.carried()), before, "splitting conserves items")

	# Partial transfer into a nearly full stack.
	inventory.clear_slot(22)
	inventory.clear_slot(23)
	inventory.put_stack(22, {"item": BlockDB.STONE, "count": 63})
	inventory.put_stack(23, {"item": BlockDB.STONE, "count": 10})
	panel.flush_cursor()
	before = _owned(inventory, panel.carried())
	h.check(panel.pick_up(23), "the partial-transfer stack is picked up")
	h.check(panel.put_down(22), "the target takes only what fits")
	h.eq(inventory.counts[22], 64, "the target is exactly full")
	h.eq(int(panel.carried().get("count", 0)), 9, "the remainder is still carried")
	h.eq(_owned(inventory, panel.carried()), before, "partial transfer conserves items")

	# Incompatible occupied slots swap; the displaced stack becomes carried.
	inventory.clear_slot(24)
	inventory.clear_slot(25)
	inventory.put_stack(24, {"item": BlockDB.STONE, "count": 5})
	inventory.put_stack(25, {"item": BlockDB.DIRT, "count": 7})
	panel.flush_cursor()
	before = _owned(inventory, panel.carried())
	h.check(panel.pick_up(24), "the stone is picked up")
	h.check(panel.put_down(25), "an incompatible slot swaps")
	h.eq(inventory.slots[25], BlockDB.STONE, "the stone moved in")
	h.eq(int(panel.carried().get("item", BlockDB.AIR)), BlockDB.DIRT,
		"the displaced dirt is carried")
	h.eq(int(panel.carried().get("count", 0)), 7, "the displaced count is preserved")
	h.eq(_owned(inventory, panel.carried()), before, "swapping conserves items")
	panel.flush_cursor()

	# Right-click placement is exactly one item.
	inventory.clear_slot(26)
	inventory.clear_slot(27)
	inventory.put_stack(26, {"item": BlockDB.STONE, "count": 10})
	panel.flush_cursor()
	h.check(panel.pick_up(26), "the one-item source is picked up")
	inventory.put_stack(26, {"item": BlockDB.STONE, "count": 4})
	h.check(panel.put_one(27), "right-click places one item")
	h.eq(inventory.count_at(27), 1, "exactly one item was placed")
	h.eq(int(panel.carried().get("count", 0)), 9, "only one item left the cursor")
	panel.flush_cursor()

	# A full inventory refuses to flush and never destroys the stack.
	var full := Inventory.new()
	for index in Inventory.SIZE:
		full.put_stack(index, {"item": BlockDB.STONE, "count": 64})
	full.clear_slot(20)
	full.put_stack(20, {"item": BlockDB.GRAVEL, "count": 5})
	var full_panel := _panel(full)
	h.check(full_panel.pick_up(20), "a stack can be carried in a full inventory")
	full.put_stack(20, {"item": BlockDB.DIRT, "count": 64})
	h.check(not full_panel.flush_cursor(), "a full inventory refuses the cursor flush")
	h.eq(int(full_panel.carried().get("count", 0)), 5, "the refused stack survives")
	h.eq(full.count_of(BlockDB.GRAVEL), 0, "the refused gravel is not destroyed")
	full_panel.free()

	# Clicking a hotbar slot moves its stack but does not change the held slot.
	inventory.clear_slot(0)
	inventory.put_stack(0, {"item": BlockDB.GRASS, "count": 1})
	inventory.clear_slot(2)
	inventory.put_stack(2, {"item": ItemDB.WOOD_PICKAXE, "count": 1, "durability": 40})
	inventory.select(0)
	h.check(panel.click_slot(2), "clicking a hotbar slot moves the stack")
	h.eq(inventory.selected, 0, "clicking a hotbar slot never changes the held slot")
	h.eq(int(panel.carried().get("item", BlockDB.AIR)), ItemDB.WOOD_PICKAXE,
		"the full tool stack is carried")
	panel.flush_cursor()
	h.eq(inventory.selected_item(), BlockDB.GRASS, "the original held item is unchanged")
	h.check(not panel.pick_up(30), "an empty slot cannot be picked up")
	h.check(panel.carried().is_empty(), "a refused action invents no carried stack")
	h.eq(panel.slot_count_text(30), "", "an empty slot shows no count badge")
	_valid_stacks(h, inventory, "the movement battery")
	panel.close()
	panel.free()


# =========================================================================
# Context menu and amount dialog
# =========================================================================

func _test_context_and_amount(h: TestHarness) -> void:
	h.section("M40 context menu and amount dialog")
	var inventory := Inventory.new()
	inventory.put_stack(0, {"item": ItemDB.WOOD_AXE, "count": 1, "durability": 30})
	inventory.put_stack(9, {"item": BlockDB.GRASS, "count": 64})
	inventory.put_stack(10, {"item": BlockDB.DIRT, "count": 7})
	var panel := _panel(inventory)
	var before := _owned(inventory, panel.carried())

	h.check(panel.click_slot(9, MOUSE_BUTTON_MIDDLE), "middle-click opens item actions")
	h.check(panel.context_menu_open(), "the actions card is open after a middle-click")
	h.eq(panel.context_actions(), ["all", "half", "one", "amount", "quick", "move", "cancel"],
		"an occupied storage slot exposes the full action set")

	# Ctrl+left is the explicit select-all shortcut from the reference.
	h.check(panel.click_slot(9, MOUSE_BUTTON_LEFT, false, true), "Ctrl+click selects all")
	h.eq(int(panel.carried().get("count", 0)), 64, "Ctrl+click carried the whole stack")
	panel.flush_cursor()

	h.check(panel.activate_context(InventoryPanel.ACTION_ONE), "Select One takes one item")
	h.eq(int(panel.carried().get("count", 0)), 1, "Select One carried exactly one")
	panel.flush_cursor()
	h.check(panel.activate_context(InventoryPanel.ACTION_HALF), "Select Half takes half")
	h.eq(int(panel.carried().get("count", 0)), 32, "Select Half uses ceil(half)")
	panel.flush_cursor()
	h.check(panel.activate_context(InventoryPanel.ACTION_ALL), "Select All takes the stack")
	h.eq(int(panel.carried().get("count", 0)), 64, "Select All took the whole stack")
	panel.flush_cursor()
	h.eq(inventory.count_at(9), 64, "the context actions returned every item")
	h.eq(_owned(inventory, panel.carried()), before, "context actions conserve ownership")

	# Amount dialog: take exactly 10 of 64.
	h.check(panel.activate_context(InventoryPanel.ACTION_AMOUNT), "Select Amount opens the dialog")
	h.check(panel.amount_dialog_open(), "the amount dialog is open")
	h.eq(panel.amount_max(), 64, "the dialog range is the available stack")
	h.eq(panel.amount_value(), 32, "the dialog starts at half the stack")
	panel.set_amount_value(10)
	h.eq(panel.amount_value(), 10, "the amount can be typed exactly")
	h.check(panel.confirm_amount(), "Confirm applies the amount")
	h.eq(int(panel.carried().get("count", 0)), 10, "exactly ten items were taken")
	h.eq(inventory.count_at(9), 54, "the remainder stayed in the slot")

	# Cancel is mutation-free.
	var grass_before := inventory.count_of(BlockDB.GRASS)
	h.check(panel.open_amount_dialog(9) > 0, "the amount dialog reopens for placing/taking")
	panel.set_amount_value(5)
	panel.cancel_amount()
	h.eq(inventory.count_of(BlockDB.GRASS), grass_before, "Cancel did not mutate the slot")
	h.eq(int(panel.carried().get("count", 0)), 10, "Cancel kept the carried stack")
	panel.flush_cursor()

	# Boundaries clamp to 1..available.
	h.check(panel.open_amount_dialog(9) > 0, "the dialog opens on a non-empty slot")
	panel.set_amount_value(0)
	h.eq(panel.amount_value(), 1, "a zero amount clamps to one")
	panel.set_amount_value(999)
	h.eq(panel.amount_value(), panel.amount_max(), "an oversized amount clamps to the maximum")
	panel.cancel_amount()

	# Place an exact amount from the cursor into an empty slot.
	inventory.clear_slot(20)
	panel.pick_up(9)
	h.check(panel.open_amount_dialog(20) > 0, "the dialog supports placing into an empty slot")
	panel.set_amount_value(4)
	h.check(panel.confirm_amount(), "placing the selected amount succeeds")
	h.eq(inventory.count_at(20), 4, "exactly four items were placed")
	h.eq(int(panel.carried().get("count", 0)), 60, "the carried remainder is preserved")
	panel.flush_cursor()

	# A nearly full destination limits the range and never overfills.
	inventory.clear_slot(21)
	inventory.put_stack(21, {"item": BlockDB.GRASS, "count": 62})
	panel.pick_up(9)
	h.eq(panel.open_amount_dialog(21), 2, "a nearly full slot limits the amount to its room")
	panel.set_amount_value(50)
	h.eq(panel.amount_value(), 2, "the destination room clamps the amount")
	h.check(panel.confirm_amount(), "the limited amount is placed")
	h.eq(inventory.count_at(21), 64, "the destination is exactly full")
	h.eq(int(panel.carried().get("count", 0)), 58, "only the destination room left the cursor")
	panel.flush_cursor()

	# An incompatible destination is refused with no mutation.
	inventory.clear_slot(22)
	inventory.put_stack(22, {"item": BlockDB.DIRT, "count": 1})
	panel.pick_up(9)
	var carried_before := int(panel.carried().get("count", 0))
	h.eq(panel.open_amount_dialog(22), 0, "an incompatible slot refuses the dialog")
	h.eq(int(panel.carried().get("count", 0)), carried_before,
		"the refused dialog did not change the cursor")
	h.eq(inventory.count_at(22), 1, "the incompatible destination is untouched")
	panel.flush_cursor()

	# Quick Move / Move to Hotbar.
	inventory.clear_slot(9)
	inventory.put_stack(9, {"item": BlockDB.STONE, "count": 8})
	panel.open_context_menu(9)
	h.check(panel.activate_context(InventoryPanel.ACTION_MOVE), "Move to Hotbar moves the stack")
	h.eq(inventory.count_of(BlockDB.STONE), 8, "the moved stack is conserved")
	h.check(inventory.slots.find(BlockDB.STONE) < Inventory.HOTBAR_SIZE,
		"the storage stack reached a hotbar slot")
	h.check(panel.activate_context(InventoryPanel.ACTION_CANCEL), "Cancel closes the actions")
	h.check(not panel.context_menu_open(), "the context menu is closed")
	h.check(panel.open_context_menu(9), "the empty source still opens a context menu")
	h.eq(panel.context_actions(), [], "an empty slot exposes no actions")
	panel.close()
	panel.free()


# =========================================================================
# Crafting page
# =========================================================================

func _test_crafting(h: TestHarness) -> void:
	h.section("M40 crafting page")
	var inventory := Inventory.new()
	inventory.put_stack(0, {"item": BlockDB.PLANKS, "count": 10})
	inventory.put_stack(1, {"item": ItemDB.STICK, "count": 10})
	inventory.put_stack(2, {"item": BlockDB.COBBLESTONE, "count": 16})
	inventory.put_stack(3, {"item": ItemDB.IRON_INGOT, "count": 4})
	inventory.put_stack(4, {"item": ItemDB.COAL, "count": 4})
	inventory.put_stack(5, {"item": ItemDB.IRON_LUMP, "count": 2})
	var panel := _panel(inventory, Crafting.STATION_TABLE)
	panel.set_page(InventoryPanel.PAGE_CRAFTING)

	h.eq(panel.recipe_count(), Crafting.recipes().size(), "the browser lists every recipe")
	h.eq(panel.visible_recipe_count(), Crafting.recipes().size(), "All shows the catalogue")
	panel.set_craft_category("Tools")
	var tools := panel.visible_recipe_ids()
	h.eq(tools.size(), Crafting.recipes_in("Tools").size(), "the Tools category filters exactly")
	var all_tools := true
	for id in tools:
		if str(Crafting.recipe(str(id))["category"]) != "Tools":
			all_tools = false
	h.check(all_tools, "every visible Tools recipe belongs to Tools")
	panel.set_craft_category("")
	panel.set_craft_search("pickaxe")
	h.eq(panel.visible_recipe_count(), 4, "search finds the four pickaxes")
	panel.set_craft_search("zzz")
	h.eq(panel.visible_recipe_count(), 0, "an impossible search shows nothing")
	panel.set_craft_search("")

	# Selecting a recipe updates details and quantity limits.
	h.check(panel.select_recipe("wood_pickaxe"), "the wood pickaxe can be selected")
	h.eq(panel.selected_recipe_id(), "wood_pickaxe", "the selected recipe id is stable")
	h.eq(panel.max_craft_quantity(), 3, "max craftability is computed from the ingredients")
	h.check(panel.craft_status_text().contains("Ready"), "a craftable recipe is reported ready")
	panel.set_craft_quantity(99)
	h.eq(panel.craft_quantity(), 3, "the quantity clamps to the maximum")
	panel.set_craft_quantity(2)
	h.check(panel.craft_selected(), "the selected recipe crafts")
	h.eq(inventory.count_of(BlockDB.PLANKS), 4, "two crafts consumed six planks")
	h.eq(inventory.count_of(ItemDB.STICK), 6, "two crafts consumed four sticks")
	h.eq(inventory.count_of(ItemDB.WOOD_PICKAXE), 2, "two pickaxes were produced")
	h.check(panel.craft_status_text() != "", "the status refreshes after crafting")

	# A hand recipe and repeated quantity crafting.
	h.check(panel.press_craft("sticks"), "a hand recipe crafts through the same page")
	h.eq(inventory.count_of(BlockDB.PLANKS), 2, "the sticks craft consumed two planks")
	h.eq(inventory.count_of(ItemDB.STICK), 10, "the sticks craft produced four sticks")

	# Missing ingredients: no transaction, no consumption.
	inventory.remove(ItemDB.IRON_INGOT, inventory.count_of(ItemDB.IRON_INGOT))
	h.check(panel.select_recipe("iron_pickaxe"), "an unaffordable recipe can still be inspected")
	panel.set_craft_quantity(1)
	h.eq(panel.max_craft_quantity(), 0, "missing ingredients yield a zero maximum")
	h.check(not panel.craft_selected(), "crafting with missing ingredients is refused")
	h.eq(inventory.count_of(ItemDB.IRON_INGOT), 0, "the failed craft consumed no iron")
	h.check(panel.craft_status_text().to_lower().contains("missing"),
		"the details name the missing ingredient")

	# Crafting-table restriction.
	inventory.add(BlockDB.PLANKS, 3)
	inventory.add(ItemDB.STICK, 2)
	panel.set_station(Crafting.STATION_HAND)
	h.check(panel.select_recipe("wood_pickaxe"), "a table recipe can be selected by hand")
	h.eq(panel.max_craft_quantity(), 0, "a table recipe is not craftable by hand")
	var planks_before := inventory.count_of(BlockDB.PLANKS)
	h.check(not panel.craft_selected(), "the hand refuses the table recipe")
	h.eq(inventory.count_of(BlockDB.PLANKS), planks_before, "the refusal consumed no planks")
	h.check(panel.craft_status_text().to_lower().contains("crafting table"),
		"the details name the required station")
	panel.set_station(Crafting.STATION_TABLE)
	h.check(panel.max_craft_quantity() > 0, "the table unlocks the recipe")
	h.check(panel.craft_selected(), "the table recipe crafts")

	# A furnace recipe uses the same page, station gate and fuel transaction.
	var ingots_before := inventory.count_of(ItemDB.IRON_INGOT)
	var lumps_before := inventory.count_of(ItemDB.IRON_LUMP)
	var coal_before := inventory.count_of(ItemDB.COAL)
	panel.set_station(Crafting.STATION_FURNACE)
	h.check(panel.select_recipe("iron_ingot"), "a smelting recipe can be selected")
	h.check(panel.max_craft_quantity() >= 1, "a furnace unlocks smelting on the page")
	h.check(panel.craft_selected(), "the page smelts through the real recipe")
	h.eq(inventory.count_of(ItemDB.IRON_INGOT), ingots_before + 1, "one ingot was produced")
	h.eq(inventory.count_of(ItemDB.IRON_LUMP), lumps_before - 1, "one lump was consumed")
	h.eq(inventory.count_of(ItemDB.COAL), coal_before - 1, "one coal fuel was consumed")
	panel.set_station(Crafting.STATION_TABLE)

	# Full output destination: a full inventory with no free slot cannot deliver.
	var full := Inventory.new()
	for index in Inventory.SIZE:
		full.put_stack(index, {"item": BlockDB.STONE, "count": 64})
	full.clear_slot(20)
	full.put_stack(20, {"item": BlockDB.PLANKS, "count": 64})
	var full_panel := _panel(full, Crafting.STATION_HAND)
	full_panel.set_page(InventoryPanel.PAGE_CRAFTING)
	h.check(full_panel.select_recipe("sticks"), "the sticks recipe is selected in a full inventory")
	h.eq(full_panel.max_craft_quantity(), 0, "no room for the output yields a zero maximum")
	var full_planks := full.count_of(BlockDB.PLANKS)
	h.check(not full_panel.craft_selected(), "a full output destination refuses the craft")
	h.eq(full.count_of(BlockDB.PLANKS), full_planks, "the failed craft consumed nothing")
	full.clear_slot(10)
	var max_after := full_panel.max_craft_quantity()
	h.eq(max_after, 32, "the maximum includes the slot the consumed planks will free")
	full_panel.set_craft_quantity(max_after)
	h.check(full_panel.craft_selected(), "the maximum batch crafts after space is freed")
	h.eq(full.count_of(ItemDB.STICK), 128, "the crafted output fills both free slots")
	h.eq(full.count_of(BlockDB.PLANKS), 0, "the batch consumed the whole plank stack")
	full_panel.free()

	_valid_stacks(h, inventory, "the crafting battery")
	panel.close()
	panel.free()


# =========================================================================
# Character page, navigation and preview stability
# =========================================================================

func _test_character_nav_preview(h: TestHarness) -> void:
	h.section("M40 character, navigation and preview")
	var inventory := Inventory.new()
	inventory.give_starter_kit()
	inventory.put_stack(9, {"item": BlockDB.GRASS, "count": 64})
	var panel := _panel(inventory, Crafting.STATION_TABLE)
	panel.set_vitals(16.0, 20.0, 13.0, 20.0)
	panel.set_player_stats(5.4)
	var rect := panel.character_preview_rect()
	h.greater(rect.size.x, 0.0, "the character preview has a real rect")
	h.greater(rect.size.y, 0.0, "the character preview has a real height")

	# The reported bug: selecting an item must not resize the preview.
	panel.focus_slot(10)
	h.eq(panel.character_preview_rect(), rect, "selecting an item leaves the preview rect intact")
	panel.open_context_menu(10)
	h.eq(panel.character_preview_rect(), rect, "opening the actions card leaves the preview intact")
	panel.rotate_preview(45.0)
	h.eq(panel.character_preview_rect(), rect, "rotating the model leaves the preview intact")

	# Three distinct pages; Character can never route into Crafting.
	panel.press_nav("character")
	h.eq(panel.page(), "character", "the Character tab opens the Character page")
	h.check(panel.character_preview_visible(), "the preview is visible on the Character page")
	h.eq(panel.character_preview_rect(), rect, "the Character page keeps the preview rect")
	h.check(panel.stats_text().contains("16"), "the Character page shows real health")
	h.check(panel.stats_text().contains("13"), "the Character page shows real hunger")
	h.check(panel.stats_text().contains("5.4"), "the Character page shows the real move speed")
	h.check(not panel.stats_experience_available(), "no fabricated experience value is offered")
	h.check(not panel.stats_defence_available(), "no fabricated defence value is offered")

	panel.press_nav("inventory")
	h.eq(panel.page(), "inventory", "the Inventory tab returns to the inventory page")
	panel.press_nav("crafting")
	h.eq(panel.page(), "crafting", "the Crafting tab opens the crafting page")
	h.check(not panel.character_preview_visible(), "the preview is hidden on the Crafting page")
	h.check(panel.select_recipe("wood_pickaxe"), "a recipe can be selected on the Crafting page")
	panel.press_nav("character")
	h.eq(panel.page(), "character", "Crafting -> Character stays on Character")
	panel.press_nav("inventory")
	h.eq(panel.page(), "inventory", "Character -> Inventory stays on Inventory")
	h.eq(panel.character_preview_rect(), rect, "repeated tab switching keeps the preview rect")

	# Repeated switching and the disabled Map tab.
	for step in 6:
		panel.press_nav("character" if step % 2 == 0 else "inventory")
	h.check(not panel.nav_enabled("map"), "Map remains explicitly unavailable")
	h.check(not panel.press_nav("map"), "pressing Map does nothing")
	var visited: Array = []
	panel.navigate.connect(func(target: String) -> void: visited.append(target))
	h.check(panel.press_nav("settings"), "Settings is still a real external screen")
	h.eq(visited, ["settings"], "Settings is the only external navigation")
	h.eq(panel.equipment_slot_count(), 6, "six equipment slots are presented")
	h.check(not panel.equipment_enabled(), "equipment stays disabled without a game system")
	h.eq(panel.slot_count(), Inventory.SIZE, "the screen exposes exactly the 27+9 player slots")
	h.check(panel.find_children("*Carry*", "", true, false).is_empty(),
		"there is no permanent carrying slot node")
	panel.close()
	panel.free()


# =========================================================================
# Hotbar and displayed quantities
# =========================================================================

func _test_hotbar(h: TestHarness) -> void:
	h.section("M40 hotbar synchronisation")
	var inventory := Inventory.new()
	var panel := _panel(inventory)
	inventory.put_stack(0, {"item": BlockDB.STONE, "count": 7})
	h.eq(panel.slot_count_text(0), "7", "the slot badge shows the model count")
	inventory.take_from_slot(0)
	inventory.take_from_slot(0)
	h.eq(panel.slot_count_text(0), "5", "the badge follows consumption")
	inventory.clear_slot(0)
	h.eq(panel.slot_count_text(0), "", "the badge clears with the stack")
	inventory.put_stack(3, {"item": ItemDB.COAL, "count": 12})
	var hud := GameHUD.new()
	hud.setup(inventory, null)
	_root().add_child(hud)
	hud.refresh()
	h.eq(hud.hotbar_count_text(3), "12", "the HUD hotbar reads the same model")
	inventory.take_from_slot(3)
	hud.refresh()
	h.eq(hud.hotbar_count_text(3), "11", "the HUD follows a consumption")
	h.eq(panel.slot_count_text(3), "11", "the screen badge follows the same consumption")
	hud.free()
	panel.close()
	panel.free()


func run(h: TestHarness) -> void:
	_test_moves(h)
	_test_context_and_amount(h)
	_test_crafting(h)
	_test_character_nav_preview(h)
	_test_hotbar(h)
	h.finish()
