extends RefCounted

## M40 inventory / crafting / gameplay UI contract.
##
## These tests drive the real interface: the same click handlers, the same
## `Inventory`, the same transient `Station` grid and the same `Crafting`
## catalogue the game uses.  They cover the interaction list in the M40 brief:
## moving, merging, splitting, partial transfers, incompatible stacks, a full
## inventory, duplication/loss prevention, stack caps, hotbar synchronisation,
## consumption, valid/invalid/missing/blocked crafting, atomic failure, displayed
## quantities, empty slots, the equipment presentation and navigation state.
##
## No test asserts on a pixel or a mock: every quantity is read from the model
## after a real handler ran.

const StationModel = preload("res://scripts/core/station.gd")


func name() -> String:
	return "M40 inventory UI"


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _panel(inventory: Inventory) -> InventoryPanel:
	var panel := InventoryPanel.new()
	panel.setup(inventory, null)
	_root().add_child(panel)
	panel.open()
	return panel


## Total owned items, including the temporary cursor stack, so a handler that
## copies a stack instead of transferring it is visible immediately.
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


func _check_valid_stacks(h: TestHarness, inventory: Inventory, label: String) -> void:
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
# Moving, merging, splitting, caps
# =========================================================================

func _test_moves(h: TestHarness) -> void:
	h.section("M40 inventory moves")

	var inventory := Inventory.new()
	inventory.put_stack(0, {"item": BlockDB.STONE, "count": 12})
	var panel := _panel(inventory)
	var before := _owned(inventory, panel.carried())
	h.check(panel.pick_up(0), "a whole stack is picked up")
	h.check(inventory.is_empty(0), "picking up clears the source slot")
	h.check(panel.put_down(20), "the carried stack is placed in an empty slot")
	h.eq(inventory.slots[20], BlockDB.STONE, "the stack arrived in the target slot")
	h.eq(inventory.counts[20], 12, "the stack kept its count")
	h.eq(_owned(inventory, panel.carried()), before, "moving an item conserves ownership")

	# Merge into a compatible, partially filled stack.
	inventory.clear_slot(20)
	inventory.put_stack(20, {"item": BlockDB.STONE, "count": 60})
	inventory.put_stack(21, {"item": BlockDB.STONE, "count": 10})
	before = _owned(inventory, panel.carried())
	h.check(panel.pick_up(21), "the merge source is picked up")
	h.check(panel.put_down(20), "a compatible stack accepts the carried items")
	h.eq(inventory.counts[20], 64, "the target stack is topped up to the cap")
	h.eq(int(panel.carried().get("count", 0)), 6, "the overflow stays on the cursor")
	h.eq(_owned(inventory, panel.carried()), before, "merging conserves ownership")
	h.check(panel.put_down(21), "the overflow goes back to its source slot")
	h.eq(inventory.counts[21], 6, "the remainder is preserved")

	# Split a stack in half.
	inventory.clear_slot(20)
	inventory.clear_slot(21)
	inventory.put_stack(20, {"item": BlockDB.STONE, "count": 9})
	before = _owned(inventory, panel.carried())
	h.check(panel.split_half(20), "right-click splits a stack")
	h.eq(int(panel.carried().get("count", 0)), 5, "the split takes ceil(half)")
	h.eq(inventory.count_at(20), 4, "the other half stays in the source slot")
	h.eq(_owned(inventory, panel.carried()), before, "splitting conserves ownership")

	# Partial transfer into a partially filled stack.
	inventory.clear_slot(22)
	inventory.clear_slot(23)
	inventory.put_stack(22, {"item": BlockDB.STONE, "count": 63})
	inventory.put_stack(23, {"item": BlockDB.STONE, "count": 10})
	panel.flush_cursor()
	before = _owned(inventory, panel.carried())
	h.check(panel.pick_up(23), "the partial-transfer source is picked up")
	h.check(panel.put_down(22), "one item fills the remaining room")
	h.eq(inventory.counts[22], 64, "the target stack is exactly full")
	h.eq(int(panel.carried().get("count", 0)), 9, "only the part that fits was placed")
	h.eq(_owned(inventory, panel.carried()), before, "partial transfer conserves ownership")

	# Incompatible stacks are swapped, never merged.
	inventory.clear_slot(24)
	inventory.clear_slot(25)
	inventory.put_stack(24, {"item": BlockDB.STONE, "count": 5})
	inventory.put_stack(25, {"item": BlockDB.DIRT, "count": 7})
	panel.flush_cursor()
	before = _owned(inventory, panel.carried())
	h.check(panel.pick_up(24), "the stone stack is picked up")
	h.check(panel.put_down(25), "placing on a different item swaps instead of merging")
	h.eq(inventory.slots[25], BlockDB.STONE, "the stone moved into the target slot")
	h.eq(int(panel.carried().get("item", BlockDB.AIR)), BlockDB.DIRT,
		"the displaced dirt is on the cursor")
	h.eq(int(panel.carried().get("count", 0)), 7, "the displaced stack kept its count")
	h.eq(_owned(inventory, panel.carried()), before, "an incompatible swap conserves ownership")

	# A full target stack refuses more items without losing them.
	inventory.clear_slot(26)
	inventory.clear_slot(27)
	inventory.put_stack(26, {"item": BlockDB.STONE, "count": 64})
	inventory.put_stack(27, {"item": BlockDB.STONE, "count": 10})
	panel.flush_cursor()
	h.check(panel.pick_up(27), "the overflow stack is picked up")
	h.check(panel.put_down(26), "placing into a full stack is refused")
	h.eq(int(panel.carried().get("count", 0)), 10, "the refused items stay on the cursor")
	h.eq(inventory.count_at(26), 64, "the full stack is untouched")
	panel.flush_cursor()
	_check_valid_stacks(h, inventory, "the move battery")

	# Empty slots and absent items never error or invent state.
	inventory.clear_slot(30)
	h.eq(inventory.item_at(30), BlockDB.AIR, "an empty slot reports no item")
	h.eq(panel.slot_count_text(30), "", "an empty slot shows no count badge")
	h.check(not panel.pick_up(30), "picking up an empty slot is refused")
	h.check(not panel.split_half(30), "splitting an empty slot is refused")
	h.check(panel.carried().is_empty(), "a refused action never invents a carried stack")

	panel.close()
	panel.free()


func _test_full_inventory(h: TestHarness) -> void:
	h.section("M40 full inventory")
	var inventory := Inventory.new()
	for index in Inventory.SIZE:
		inventory.put_stack(index, {"item": BlockDB.STONE, "count": 64})
	inventory.clear_slot(20)
	inventory.put_stack(20, {"item": BlockDB.GRAVEL, "count": 5})
	var panel := _panel(inventory)
	h.check(panel.pick_up(20), "a stack in a full inventory can be picked up")
	inventory.put_stack(20, {"item": BlockDB.DIRT, "count": 64})
	h.check(not panel.flush_cursor(), "a genuinely full inventory refuses to flush")
	h.eq(int(panel.carried().get("count", 0)), 5, "the refused stack is preserved")
	h.eq(inventory.count_of(BlockDB.GRAVEL), 0, "the refused items are not destroyed")
	h.eq(inventory.free_slot_count(), 0, "the inventory really is full")
	panel.free()


# =========================================================================
# Hotbar + displayed quantities
# =========================================================================

func _test_hotbar_and_display(h: TestHarness) -> void:
	h.section("M40 hotbar and displayed quantities")
	var inventory := Inventory.new()
	var panel := _panel(inventory)
	inventory.put_stack(0, {"item": BlockDB.STONE, "count": 7})
	h.eq(panel.slot_count_text(0), "7", "the slot badge shows the real count")
	inventory.take_from_slot(0)
	inventory.take_from_slot(0)
	h.eq(panel.slot_count_text(0), "5", "the badge updates after consumption")
	inventory.clear_slot(0)
	h.eq(panel.slot_count_text(0), "", "the badge clears with the stack")

	inventory.put_stack(2, {"item": ItemDB.WOOD_PICKAXE, "count": 1, "durability": 60})
	h.check(panel.click_slot(2), "clicking a hotbar slot selects it")
	h.eq(inventory.selected, 2, "the click path updates the authoritative selection")
	h.eq(int(panel.carried().get("item", BlockDB.AIR)), ItemDB.WOOD_PICKAXE,
		"the same click takes the stack, exactly like the old interface")
	panel.flush_cursor()
	h.eq(inventory.selected_item(), ItemDB.WOOD_PICKAXE,
		"the selected item is the tool in that slot after the stack returns")

	# The HUD reads the same model, so its badge cannot drift from the screen.
	var hud := GameHUD.new()
	hud.setup(inventory, null)
	_root().add_child(hud)
	inventory.put_stack(3, {"item": ItemDB.COAL, "count": 12})
	hud.refresh()
	h.eq(hud.hotbar_count_text(3), "12", "the HUD hotbar shows the model count")
	inventory.take_from_slot(3)
	hud.refresh()
	h.eq(hud.hotbar_count_text(3), "11", "the HUD hotbar follows a consumption")
	h.eq(panel.slot_count_text(3), "11", "the screen badge follows the same consumption")
	hud.free()
	panel.close()
	panel.free()


# =========================================================================
# Crafting grid
# =========================================================================

## Puts `item_id` in a grid cell by the real click path: pick the stack up from
## the player inventory, then click the grid cell.  Right-click places one item
## per click, so the ingredient counts are exact.
func _place_one(panel: InventoryPanel, player_slot: int, grid_index: int) -> bool:
	if panel.carried().is_empty() and not panel.pick_up(player_slot):
		return false
	return panel.craft_click(grid_index, MOUSE_BUTTON_RIGHT)


func _fill_pickaxe_grid(panel: InventoryPanel, plank_slot: int, stick_slot: int) -> void:
	for grid_index in [0, 1, 2]:
		_place_one(panel, plank_slot, grid_index)
	for grid_index in [4, 7]:
		_place_one(panel, stick_slot, grid_index)
	panel.flush_cursor()


func _test_crafting(h: TestHarness) -> void:
	h.section("M40 crafting")
	var recipe: Dictionary = Crafting.recipe("wood_pickaxe")
	h.eq(Crafting.station_of(recipe), Crafting.STATION_TABLE,
		"the wood pickaxe is a crafting-table recipe")

	var inventory := Inventory.new()
	inventory.put_stack(0, {"item": BlockDB.PLANKS, "count": 3})
	inventory.put_stack(1, {"item": ItemDB.STICK, "count": 2})
	var panel := _panel(inventory)
	panel.set_station(Crafting.STATION_HAND)
	h.eq(panel.craft_grid_slot_count(), 9, "the interface exposes a real 3x3 grid")
	_fill_pickaxe_grid(panel, 0, 1)
	h.eq(panel.craft_grid_item(0), BlockDB.PLANKS, "the grid holds the placed planks")
	h.eq(panel.craft_grid_item(4), ItemDB.STICK, "the grid holds the placed sticks")

	# The shape matches, but the hand cannot use a table recipe.
	var preview: Dictionary = panel.craft_output()
	h.eq(int(preview.get("item", BlockDB.AIR)), ItemDB.WOOD_PICKAXE,
		"the output slot previews the matching recipe")
	h.check(not panel.craft_click(9), "a table recipe cannot be crafted by hand")
	h.eq(inventory.count_of(BlockDB.PLANKS), 0, "the refused craft consumed no planks")
	h.eq(panel.craft_grid_count(0), 1, "the refused craft left the grid intact")
	h.check(panel.craft_status_text().to_lower().contains("crafting table"),
		"the status names the missing station")

	# With a table the same grid crafts atomically.
	panel.set_station(Crafting.STATION_TABLE)
	h.check(panel.craft_click(9), "the same grid crafts at a crafting table")
	h.eq(int(panel.carried().get("item", BlockDB.AIR)), ItemDB.WOOD_PICKAXE,
		"the crafted pickaxe is taken from the output")
	h.eq(panel.craft_grid_item(0), BlockDB.AIR, "crafting consumed the grid contents")
	h.eq(inventory.count_of(ItemDB.STICK), 0, "crafting consumed exactly the sticks")
	h.check(panel.put_down(20), "the crafted item can be stored")
	h.eq(inventory.count_at(20), 1, "the crafted pickaxe is in the inventory")

	# An invalid arrangement produces nothing and consumes nothing.
	inventory.clear_slot(20)
	inventory.put_stack(2, {"item": BlockDB.PLANKS, "count": 1})
	panel.flush_cursor()
	panel.pick_up(2)
	panel.craft_click(0)
	panel.flush_cursor()
	h.check(panel.craft_output().is_empty(), "one plank matches no recipe")
	h.check(not panel.craft_click(9), "an invalid grid cannot be crafted")
	h.eq(panel.craft_grid_count(0), 1, "an invalid grid is left untouched")

	# A missing ingredient is reported, not silently crafted.  Three cobblestone
	# and one stick are one stick short of a stone pickaxe.
	panel.debug_clear_crafting_grid()
	inventory.clear_slot(2)
	inventory.clear_slot(3)
	inventory.put_stack(2, {"item": BlockDB.COBBLESTONE, "count": 3})
	inventory.put_stack(3, {"item": ItemDB.STICK, "count": 1})
	_fill_pickaxe_grid(panel, 2, 3)
	h.check(panel.craft_output().is_empty(), "a missing stick produces no output")
	h.check(panel.craft_status_text().to_lower().contains("missing"),
		"the status names the missing ingredient")
	h.eq(panel.craft_grid_count(0), 1, "the incomplete grid is untouched")

	# A hand recipe still works without a table.
	panel.debug_clear_crafting_grid()
	inventory.clear_slot(4)
	inventory.put_stack(4, {"item": BlockDB.PLANKS, "count": 2})
	panel.set_station(Crafting.STATION_HAND)
	panel.pick_up(4)
	panel.craft_click(0)
	panel.flush_cursor()
	h.eq(panel.craft_grid_count(0), 2, "the two planks are in the grid")
	h.check(not panel.craft_output().is_empty(), "the stick recipe matches by hand")
	h.check(panel.craft_click(9), "the hand recipe crafts")
	h.eq(int(panel.carried().get("item", BlockDB.AIR)), ItemDB.STICK,
		"the hand recipe produced sticks")
	h.eq(int(panel.carried().get("count", 0)), 4, "the hand recipe produced four sticks")
	panel.flush_cursor()

	# A full output slot refuses the craft before consuming anything.  Sticks
	# stack to 64, so 60 already in the result slot leave no room for another 4.
	panel.debug_clear_crafting_grid()
	panel.debug_clear_output()
	panel.set_station(Crafting.STATION_HAND)
	inventory.clear_slot(5)
	inventory.clear_slot(6)
	inventory.put_stack(5, {"item": BlockDB.PLANKS, "count": 2})
	panel.pick_up(5)
	panel.craft_click(0)
	panel.flush_cursor()
	panel.debug_seed_output(ItemDB.STICK, 61)
	h.check(panel.craft_output().get("ghost", false) == false,
		"the full output slot is real state, not a preview")
	h.check(not panel.craft_press(), "a full output slot refuses the craft")
	h.eq(panel.craft_grid_count(0), 2, "the refused craft did not consume the grid")
	h.eq(panel.craft_grid_count(1), 0, "nothing else appeared in the grid")
	h.eq(int(panel.craft_output().get("count", 0)), 61, "the result slot is unchanged")
	panel.debug_clear_output()
	h.check(panel.craft_press(), "with room in the result slot the craft succeeds")
	h.eq(panel.craft_grid_count(0), 0, "the successful craft consumed the planks")
	h.eq(int(panel.craft_output().get("item", BlockDB.AIR)), ItemDB.STICK,
		"the successful craft put sticks in the result slot")
	h.check(panel.craft_click(9), "the result is taken")
	h.eq(int(panel.carried().get("count", 0)), 4, "the whole output stack is carried")
	panel.flush_cursor()

	# Closing returns every grid item to the player.
	panel.debug_clear_output()
	panel.debug_clear_crafting_grid()
	inventory.clear_slot(7)
	inventory.put_stack(7, {"item": BlockDB.PLANKS, "count": 4})
	panel.pick_up(7)
	panel.craft_click(0)
	panel.flush_cursor()
	var planks_before := inventory.count_of(BlockDB.PLANKS)
	h.eq(panel.craft_grid_count(0), 4, "the grid holds the planks before closing")
	h.check(panel.close(), "closing succeeds with room in the inventory")
	h.eq(inventory.count_of(BlockDB.PLANKS), planks_before + 4,
		"closing returned the grid planks")
	h.eq(panel.craft_grid_item(0), BlockDB.AIR, "the grid is empty after closing")

	# And refuses to close (destroying nothing) when the inventory is full.
	var full := Inventory.new()
	for index in Inventory.SIZE:
		full.put_stack(index, {"item": BlockDB.STONE, "count": 64})
	full.clear_slot(20)
	full.put_stack(20, {"item": BlockDB.PLANKS, "count": 4})
	var full_panel := _panel(full)
	full_panel.pick_up(20)
	full_panel.craft_click(0)
	full_panel.flush_cursor()
	full.put_stack(20, {"item": BlockDB.DIRT, "count": 64})
	h.check(not full_panel.close(), "a full inventory refuses to close over grid items")
	h.eq(full_panel.craft_grid_count(0), 4, "the grid items are preserved")
	h.check(full_panel.is_open(), "the panel stays open so nothing is lost")
	full.clear_slot(10)
	h.check(full_panel.close(), "once a slot is free the panel closes and returns the grid")
	h.eq(full.count_of(BlockDB.PLANKS), 4, "the preserved grid planks were returned")
	full_panel.free()

	panel.free()


# =========================================================================
# Character, equipment, navigation, vitals
# =========================================================================

func _test_panels(h: TestHarness) -> void:
	h.section("M40 character, equipment, navigation and vitals")
	var inventory := Inventory.new()
	inventory.give_starter_kit()
	var panel := _panel(inventory)
	panel.set_vitals(14.0, 20.0, 8.0, 20.0)
	h.check(panel.vitals_text().contains("14"),
		"the character page reports the real health value")
	h.check(panel.vitals_text().contains("8"),
		"the character page reports the real hunger value")
	h.check(not panel.vitals_text().to_lower().contains("xp"),
		"no experience value is invented")
	h.check(not panel.vitals_text().to_lower().contains("level"),
		"no level value is invented")
	h.eq(panel.equipment_slot_count(), 6, "four armour and two off-hand slots are presented")
	h.check(not panel.equipment_enabled(),
		"equipment slots are disabled because the game has no equipment system")

	h.check(panel.nav_enabled("inventory"), "the Inventory tab is available")
	h.check(panel.nav_enabled("crafting"), "the Crafting tab is available")
	h.check(panel.nav_enabled("character"), "the Character tab is available")
	h.check(panel.nav_enabled("settings"), "the Settings tab is available")
	h.check(not panel.nav_enabled("map"), "the Map tab is explicitly unavailable")

	var visited: Array = []
	panel.navigate.connect(func(target: String) -> void: visited.append(target))
	h.check(not panel.press_nav("map"), "pressing the unavailable Map tab does nothing")
	h.eq(visited.size(), 0, "an unavailable tab emits no navigation")
	h.check(panel.press_nav("crafting"), "pressing Crafting navigates")
	h.eq(visited, ["crafting"], "the navigation names the crafting screen")
	panel.set_page("character")
	h.eq(panel.page(), "character", "the Character tab switches the screen page")
	h.check(panel.press_nav("inventory"), "pressing Inventory returns to the inventory page")
	h.eq(panel.page(), "inventory", "the Inventory tab restores the inventory page")

	h.check(panel.press_nav("settings"), "pressing Settings navigates")
	h.eq(visited, ["crafting", "settings"],
		"the navigation names the settings screen")
	h.eq(panel.slot_count(), Inventory.SIZE,
		"the screen still exposes exactly the 27+9 player slots")
	h.check(panel.find_children("*Carry*", "", true, false).is_empty(),
		"the screen has no permanent carrying slot")
	panel.close()
	panel.free()


func run(h: TestHarness) -> void:
	_test_moves(h)
	_test_full_inventory(h)
	_test_hotbar_and_display(h)
	_test_crafting(h)
	_test_panels(h)
	h.finish()
