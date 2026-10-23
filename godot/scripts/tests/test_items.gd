extends RefCounted

## Item definitions (`ItemDB`) and the item-aware `Inventory` model.
##
## These are the rules the crafting system, the mining system and the HUD all
## depend on: the block/item id namespace, stack sizes, tool tiers, what a block
## needs before it drops, and how durability is spent and persisted.

var _library: TextureLibrary


func name() -> String:
	return "items and inventory"


func _setup() -> void:
	if _library != null:
		return
	_library = TextureLibrary.new()
	_library.load_all()


### ItemDB ------------------------------------------------------------------

func _test_item_namespace(h: TestHarness) -> void:
	h.eq(ItemDB.BLOCK_COUNT, BlockDB.COUNT, "the item namespace covers the block id space")
	h.eq(ItemDB.COUNT, 103, "the item namespace has the expected size")
	h.check(not ItemDB.is_block(ItemDB.STICK), "a material below the M21 blocks is not a block")
	h.check(not ItemDB.is_block(ItemDB.DIAMOND_PICKAXE), "a tool below the M21 blocks is not a block")
	h.check(ItemDB.is_block(BlockDB.FARMLAND), "farmland is a placeable block")
	h.check(ItemDB.is_block(BlockDB.CHEST), "the storage chest is a placeable block")
	h.check(not ItemDB.is_block(ItemDB.RAW_MEAT), "raw meat is not a block")
	h.check(not ItemDB.is_block(ItemDB.WHEAT_SEEDS), "wheat seeds are not a block")
	var valid := true
	var seen := {}
	for item_id in ItemDB.COUNT:
		if not ItemDB.is_valid(item_id):
			valid = false
		if seen.has(item_id):
			valid = false
		seen[item_id] = true
		if ItemDB.name_of(item_id).is_empty():
			valid = false
		# Air is a valid id (an empty slot) but has no icon and is not an item.
		if item_id != BlockDB.AIR and ItemDB.icon_key(item_id).is_empty():
			valid = false
	h.check(valid, "every item id resolves to a unique name and icon")
	h.check(not ItemDB.is_valid(ItemDB.COUNT), "an id past the namespace is invalid")
	h.check(not ItemDB.is_valid(-1), "a negative id is invalid")

	# Block items delegate to BlockDB, so nothing about block behaviour moved.
	h.eq(ItemDB.name_of(BlockDB.OAK_LOG), BlockDB.name_of(BlockDB.OAK_LOG),
		"a block item keeps its BlockDB name")
	h.eq(ItemDB.icon_key(BlockDB.PLANKS), (BlockDB.face_keys[BlockDB.PLANKS] as PackedStringArray)[BlockDB.FACE_PY],
		"a block item keeps its BlockDB top-face icon")
	h.check(ItemDB.is_block(BlockDB.GRASS), "grass is a placeable block item")
	h.check(ItemDB.placeable_block(BlockDB.GRASS) == BlockDB.GRASS, "grass places itself")
	h.check(not ItemDB.is_block(BlockDB.AIR), "air is not placeable")
	h.check(not ItemDB.is_block(BlockDB.WATER), "water is not a placeable item")
	h.check(not ItemDB.is_block(ItemDB.STICK), "a material is not placeable")
	h.eq(ItemDB.placeable_block(ItemDB.WOOD_PICKAXE), BlockDB.NO_DROP, "a tool is not placeable")


func _test_item_icons_resolve(h: TestHarness) -> void:
	_setup()
	h.check(_library != null and _library.array != null, "loads the texture library for icon checks")
	var missing: Array[String] = []
	for item_id in range(1, ItemDB.COUNT):
		var key := ItemDB.icon_key(item_id)
		if not _library.layer_of.has(key):
			missing.append("%d:%s" % [item_id, key])
	h.eq(missing, [], "every item icon key resolves to a texture layer (%s)" % ", ".join(missing))


func _test_tools(h: TestHarness) -> void:
	var tiers := [ItemDB.WOOD_PICKAXE, ItemDB.STONE_PICKAXE, ItemDB.IRON_PICKAXE, ItemDB.DIAMOND_PICKAXE]
	var durable := true
	var faster := true
	for index in tiers.size():
		var item_id: int = tiers[index]
		if not ItemDB.is_tool_item(item_id):
			durable = false
		if ItemDB.tool_class(item_id) != ItemDB.Tool.PICKAXE:
			durable = false
		if ItemDB.max_stack(item_id) != 1:
			durable = false
		if ItemDB.max_durability(item_id) != int(ItemDB.TIER_DURABILITY[index + 1]):
			durable = false
		if index > 0 and ItemDB.mining_speed(item_id) <= ItemDB.mining_speed(tiers[index - 1]):
			faster = false
	h.check(durable, "each pickaxe tier has the right class, single-item stack and durability")
	h.check(faster, "a higher tool tier mines faster")
	h.check(ItemDB.max_durability(ItemDB.DIAMOND_PICKAXE) > ItemDB.max_durability(ItemDB.WOOD_PICKAXE) * 10,
		"a diamond tool lasts far longer than a wooden one")
	h.eq(ItemDB.tool_class(ItemDB.STONE_AXE), ItemDB.Tool.AXE, "the axe has its own class")
	h.eq(ItemDB.tool_class(ItemDB.STONE_SHOVEL), ItemDB.Tool.SHOVEL, "the shovel has its own class")
	h.eq(ItemDB.tool_class(ItemDB.STONE_SWORD), ItemDB.Tool.SWORD, "the sword has its own class")
	h.check(ItemDB.attack_damage(ItemDB.DIAMOND_SWORD) > ItemDB.attack_damage(ItemDB.WOOD_SWORD),
		"a better sword hits harder")
	h.check(not ItemDB.is_tool_item(ItemDB.STICK), "a material is not a tool")
	h.eq(ItemDB.describe(ItemDB.STONE_PICKAXE), "Stone Pickaxe", "a tool describes tier and class")


func _test_break_times(h: TestHarness) -> void:
	var hand_stone := ItemDB.break_seconds(BlockDB.STONE, BlockDB.AIR)
	var wood_pick_stone := ItemDB.break_seconds(BlockDB.STONE, ItemDB.WOOD_PICKAXE)
	var diamond_pick_stone := ItemDB.break_seconds(BlockDB.STONE, ItemDB.DIAMOND_PICKAXE)
	h.greater(hand_stone, wood_pick_stone,
		"the timing curve gives a pickaxe a speed advantage on stone")
	h.greater(wood_pick_stone, diamond_pick_stone, "a diamond pickaxe breaks stone faster than a wooden one")
	h.greater(float(ItemDB.break_seconds(BlockDB.DIRT, BlockDB.AIR)),
		float(ItemDB.break_seconds(BlockDB.DIRT, ItemDB.STONE_SHOVEL)), "a shovel digs dirt faster")

	# The wrong tool is not a slowdown on a hand-mineable block (a sword is
	# slightly faster than a hand).  Gated blocks never reach this timing call
	# because the break is refused first.
	var hand_dirt := ItemDB.break_seconds(BlockDB.DIRT, BlockDB.AIR)
	h.check(ItemDB.break_seconds(BlockDB.DIRT, ItemDB.WOOD_AXE) <= hand_dirt,
		"using the wrong tool never takes longer than the bare hand")
	h.check(ItemDB.break_seconds(BlockDB.DIRT, ItemDB.WOOD_SWORD) < hand_dirt,
		"a sword is faster than a bare hand on a hand-mineable block")
	h.approx(ItemDB.break_seconds(BlockDB.AIR, BlockDB.AIR), float(ItemDB.MIN_BREAK_SECONDS), 0.0001,
		"a block with no hardness still takes the minimum time")
	h.check(ItemDB.break_seconds(BlockDB.DIAMOND_ORE, ItemDB.DIAMOND_PICKAXE) > 0.0,
		"a hard ore has a positive break time with the best tool")


func _test_drop_requirements(h: TestHarness) -> void:
	h.check(not ItemDB.harvestable(BlockDB.STONE, BlockDB.AIR), "stone cannot be mined by a bare hand")
	h.check(ItemDB.harvestable(BlockDB.STONE, ItemDB.WOOD_PICKAXE), "stone can be mined by a wooden pickaxe")
	h.check(ItemDB.harvestable(BlockDB.DIRT, BlockDB.AIR), "dirt drops to a bare hand")
	h.check(ItemDB.harvestable(BlockDB.OAK_LOG, BlockDB.AIR), "a log drops to a bare hand")
	h.check(ItemDB.harvestable(BlockDB.CLAY, BlockDB.AIR), "clay drops to a bare hand")
	h.check(not ItemDB.harvestable(BlockDB.IRON_ORE, ItemDB.WOOD_PICKAXE), "iron ore needs better than wood")
	h.check(ItemDB.harvestable(BlockDB.IRON_ORE, ItemDB.STONE_PICKAXE), "iron ore drops to a stone pickaxe")
	h.check(not ItemDB.harvestable(BlockDB.DIAMOND_ORE, ItemDB.STONE_PICKAXE), "diamond needs better than stone")
	h.check(ItemDB.harvestable(BlockDB.DIAMOND_ORE, ItemDB.IRON_PICKAXE), "diamond ore drops to an iron pickaxe")
	h.check(not ItemDB.harvestable(BlockDB.OBSIDIAN, ItemDB.IRON_PICKAXE), "obsidian needs a diamond pickaxe")
	h.check(ItemDB.harvestable(BlockDB.OBSIDIAN, ItemDB.DIAMOND_PICKAXE), "obsidian drops to a diamond pickaxe")
	h.check(not ItemDB.harvestable(BlockDB.STONE, ItemDB.WOOD_AXE), "an axe cannot mine stone")
	h.eq(ItemDB.requirement_label(BlockDB.STONE), "Pickaxe",
		"stone asks for a pickaxe in the HUD")
	h.eq(ItemDB.requirement_label(BlockDB.IRON_ORE), "Stone Pickaxe",
		"iron ore names both its tool class and minimum tier")
	h.eq(ItemDB.requirement_label(BlockDB.DIRT), "",
		"a hand-mineable block has no tool requirement")


func _test_item_drops(h: TestHarness) -> void:
	h.eq(ItemDB.drop_for_block(BlockDB.COAL_ORE), ItemDB.COAL, "coal ore drops a coal item")
	h.eq(ItemDB.drop_for_block(BlockDB.IRON_ORE), ItemDB.IRON_LUMP, "iron ore drops an iron lump")
	h.eq(ItemDB.drop_for_block(BlockDB.GOLD_ORE), ItemDB.GOLD_LUMP, "gold ore drops a gold lump")
	h.eq(ItemDB.drop_for_block(BlockDB.DIAMOND_ORE), ItemDB.DIAMOND, "diamond ore drops a diamond")
	h.eq(ItemDB.drop_for_block(BlockDB.STONE), BlockDB.COBBLESTONE, "stone keeps its block drop")
	h.eq(ItemDB.drop_for_block(BlockDB.GRASS), BlockDB.DIRT, "grass keeps its block drop")
	h.eq(ItemDB.drop_for_block(BlockDB.BEDROCK), BlockDB.NO_DROP, "bedrock drops nothing")
	h.check(ItemDB.is_valid(ItemDB.drop_for_block(BlockDB.DIAMOND_ORE)),
		"an ore drop is a valid item id")


## The bonus (chance) drops must be a pure function of the position so a replayed
## world mines identically, and they must actually occur.
func _test_bonus_drops(h: TestHarness) -> void:
	h.eq(ItemDB.bonus_drop(BlockDB.OAK_LEAVES, 4, 70, 9), ItemDB.bonus_drop(BlockDB.OAK_LEAVES, 4, 70, 9),
		"a bonus drop is deterministic for one position")
	var apples := 0
	var seeds := 0
	for x in range(0, 400, 3):
		for z in range(0, 400, 7):
			if ItemDB.bonus_drop(BlockDB.OAK_LEAVES, x, 70, z) == ItemDB.APPLE:
				apples += 1
			if ItemDB.bonus_drop(BlockDB.TALL_GRASS, x, 70, z) == ItemDB.WHEAT_SEEDS:
				seeds += 1
	h.check(apples > 0, "oak leaves do drop apples sometimes (%d)" % apples)
	h.check(seeds > 0, "tall grass does drop wheat seeds sometimes (%d)" % seeds)
	h.check(seeds > apples, "wheat seeds are the more common of the two bonus drops")
	h.eq(ItemDB.bonus_drop(BlockDB.STONE, 1, 2, 3), BlockDB.NO_DROP, "stone has no bonus drop")
	h.eq(ItemDB.bonus_drop(BlockDB.OAK_LEAVES, 1, 2, 3) == ItemDB.APPLE or
		ItemDB.bonus_drop(BlockDB.OAK_LEAVES, 1, 2, 3) == BlockDB.NO_DROP, true,
		"a leaf bonus drop is either an apple or nothing")


func _test_food(h: TestHarness) -> void:
	h.check(ItemDB.is_food(ItemDB.APPLE), "the apple is food")
	h.check(ItemDB.is_food(ItemDB.BREAD), "the bread is food")
	h.check(ItemDB.is_food(ItemDB.GOLDEN_APPLE), "the golden apple is food")
	h.check(not ItemDB.is_food(ItemDB.STICK), "a stick is not food")
	h.check(ItemDB.food_value(ItemDB.BREAD) > ItemDB.food_value(ItemDB.APPLE),
		"bread is more filling than an apple")
	h.check(ItemDB.food_value(ItemDB.GOLDEN_APPLE) > ItemDB.food_value(ItemDB.BREAD),
		"the golden apple is the best food")
	h.greater(ItemDB.heal_value(ItemDB.GOLDEN_APPLE), 0.0, "the golden apple also heals")
	h.check(ItemDB.is_food(ItemDB.RAW_MEAT), "raw meat is edible")
	h.check(ItemDB.is_food(ItemDB.COOKED_MEAT), "cooked meat is edible")
	h.check(ItemDB.food_value(ItemDB.COOKED_MEAT) > ItemDB.food_value(ItemDB.RAW_MEAT),
		"cooking meat makes it more filling")
	h.check(not ItemDB.is_food(ItemDB.HIDE), "hide is not food")
	h.check(not ItemDB.is_food(ItemDB.BONE), "bone is not food")


### Inventory ---------------------------------------------------------------

func _test_stack_cap(h: TestHarness) -> void:
	var inventory := Inventory.new()
	h.eq(inventory.add(BlockDB.GRASS, 64), 0, "a full stack fits into one slot")
	h.eq(inventory.used_slots(), 1, "one slot is used")
	h.eq(inventory.add(BlockDB.GRASS, 1), 0, "one more item still fits (in a second slot)")
	h.eq(inventory.count_of(BlockDB.GRASS), 65, "the count spans both slots")
	h.eq(inventory.used_slots(), 2, "the overflow opened a second slot")
	h.eq(inventory.stack_room(BlockDB.GRASS), 63, "the second slot reports its remaining room")

	var tools := Inventory.new()
	h.eq(tools.add(ItemDB.WOOD_PICKAXE, 3), 0, "three tools fit")
	h.eq(tools.used_slots(), 3, "each tool takes its own slot")
	var merged := false
	for index in Inventory.HOTBAR_SIZE:
		if tools.slots[index] == ItemDB.WOOD_PICKAXE and tools.counts[index] > 1:
			merged = true
	h.check(not merged, "tools never merge into one stack")
	h.eq(tools.durability_of(0), ItemDB.max_durability(ItemDB.WOOD_PICKAXE), "a new tool starts at full durability")


func _test_full_inventory(h: TestHarness) -> void:
	var inventory := Inventory.new()
	# 36 distinct items fill the 27 main slots and the nine-slot hotbar.
	for item_id in range(1, Inventory.SIZE + 1):
		inventory.add(item_id, 64)
	h.eq(inventory.used_slots(), Inventory.SIZE, "the inventory is full")
	h.eq(inventory.free_slot_count(), 0, "no free slot remains")
	h.eq(inventory.add(ItemDB.DIAMOND_SWORD, 1), 1, "an item with nowhere to go is returned as leftover")
	h.eq(inventory.count_of(ItemDB.DIAMOND_SWORD), 0, "nothing was added")
	h.eq(inventory.add(BlockDB.STONE, 1), 1, "a full stack rejects the overflow")

	inventory.remove(BlockDB.STONE, 1)
	h.eq(inventory.add(BlockDB.STONE, 1), 0, "the freed room accepts the item again")


## The reported M20 defect: a fresh starter kit filled every slot, so a mined
## iron/coal drop was refused even though nothing was "wrong" with the drop rule.
func _test_starter_kit_leaves_storage(h: TestHarness) -> void:
	var inventory := Inventory.new()
	inventory.give_starter_kit()
	h.eq(inventory.used_slots(), Inventory.HOTBAR_SIZE + 2,
		"the starter kit fills the hotbar plus the table and seed storage slots")
	h.eq(inventory.free_slot_count(), Inventory.MAIN_SIZE - 2, "25 of the 27 storage slots are free")
	for index in Inventory.HOTBAR_SIZE:
		h.eq(inventory.count_at(index), ItemDB.max_stack(inventory.item_at(index)),
			"starter material slot %d holds a full stack" % index)
	h.eq(inventory.count_of(BlockDB.CLAY), 64, "the starter kit includes a full stack of clay")
	h.eq(inventory.count_of(BlockDB.CRAFTING_TABLE), 2,
		"the utility crafting table keeps its small starter count")
	h.eq(inventory.count_of(ItemDB.WHEAT_SEEDS), 8, "the starter kit provides wheat seeds for a first plot")
	h.eq(inventory.add(ItemDB.IRON_LUMP, 1), 0, "a mined iron lump fits after spawn")
	h.eq(inventory.count_of(ItemDB.IRON_LUMP), 1, "the iron lump is in the inventory")
	h.eq(inventory.add(ItemDB.COAL, 1), 0, "coal also fits after spawn")
	h.eq(inventory.add(ItemDB.APPLE, 1), 0, "a bonus drop also fits after spawn")
	h.eq(inventory.used_slots(), Inventory.HOTBAR_SIZE + 5, "each new item opened a storage slot")
	var iron_slot := inventory.slots.find(ItemDB.IRON_LUMP)
	h.check(iron_slot >= Inventory.MAIN_FIRST, "new material drops go to the storage rows")
	h.check(inventory.select(iron_slot) == false, "a storage slot cannot become the held item")
	h.eq(inventory.selected_item(), BlockDB.GRASS, "selecting a storage slot left the hand unchanged")


func _test_durability(h: TestHarness) -> void:
	var inventory := Inventory.new()
	inventory.add(ItemDB.STONE_PICKAXE, 1, 2)
	h.eq(inventory.durability_of(0), 2, "the tool starts with the requested durability")
	h.check(not inventory.wear(0, 1), "the first use does not break the tool")
	h.eq(inventory.durability_of(0), 1, "the durability went down by one")
	h.check(inventory.wear(0, 1), "the tool breaks when its durability reaches zero")
	h.eq(inventory.durability_of(0), 0, "a broken tool leaves no durability")
	h.check(inventory.is_empty(0), "a broken tool frees its slot")

	inventory.add(ItemDB.WOOD_SWORD, 1)
	h.check(not inventory.wear(0, 5), "a tool with plenty of durability survives a big wear step")
	h.eq(inventory.durability_of(0), ItemDB.max_durability(ItemDB.WOOD_SWORD) - 5,
		"the wear step is applied exactly")

	var blocks := Inventory.new()
	blocks.add(BlockDB.STONE, 5)
	h.check(not blocks.wear(0, 1), "a block never wears")
	h.eq(blocks.count_of(BlockDB.STONE), 5, "wearing a block consumes nothing")
	h.eq(blocks.durability_of(0), 0, "a block has no durability")

	# Explicit durability is clamped into the tool's legal range.
	var clamped := Inventory.new()
	clamped.add(ItemDB.WOOD_PICKAXE, 1, 99999)
	h.eq(clamped.durability_of(0), ItemDB.max_durability(ItemDB.WOOD_PICKAXE), "an oversized durability clamps to full")


func _test_serialisation(h: TestHarness) -> void:
	var inventory := Inventory.new()
	inventory.add(BlockDB.STONE, 7)
	inventory.add(ItemDB.DIAMOND_PICKAXE, 1)
	inventory.add(ItemDB.APPLE, 3)
	inventory.select(2)
	var payload: Dictionary = inventory.to_dictionary()

	var restored := Inventory.new()
	h.check(restored.from_dictionary(payload), "the payload round-trips")
	h.eq(restored.count_of(BlockDB.STONE), 7, "the stone survived")
	h.eq(restored.count_of(ItemDB.APPLE), 3, "the food survived")
	h.eq(restored.count_of(ItemDB.DIAMOND_PICKAXE), 1, "the tool survived")
	h.eq(restored.selected, 2, "the selection survived")
	h.eq(restored.to_dictionary(), payload, "the full payload is identical after a round trip")

	# A save written before tools existed has no "durability" field at all.
	var legacy: Dictionary = payload.duplicate(true)
	(legacy as Dictionary).erase("durability")
	var legacy_inventory := Inventory.new()
	h.check(legacy_inventory.from_dictionary(legacy), "a payload without durability still loads")
	h.eq(legacy_inventory.count_of(ItemDB.DIAMOND_PICKAXE), 1, "the legacy tool survived")
	h.eq(legacy_inventory.durability_of(1), ItemDB.max_durability(ItemDB.DIAMOND_PICKAXE),
		"a tool without a saved durability starts at full")

	# A save written before M20 has only the nine-row hotbar.  It must load into
	# the hotbar with the 27 storage slots empty.
	var legacy_rows := Inventory.new()
	legacy_rows.add(BlockDB.GRASS, 3)
	legacy_rows.add(ItemDB.IRON_LUMP, 2)
	var legacy_payload := legacy_rows.to_dictionary()
	(legacy_payload["hotbar"] as Array).resize(Inventory.HOTBAR_SIZE)
	(legacy_payload["durability"] as Array).resize(Inventory.HOTBAR_SIZE)
	legacy_payload.erase("size")
	var legacy_loaded := Inventory.new()
	h.check(legacy_loaded.from_dictionary(legacy_payload), "a nine-row pre-M20 inventory still loads")
	h.eq(legacy_loaded.count_of(BlockDB.GRASS), 3, "the legacy hotbar contents survived")
	h.eq(legacy_loaded.count_of(ItemDB.IRON_LUMP), 2, "the legacy iron survived")
	h.eq(legacy_loaded.used_slots(), 2, "no phantom items appeared in the storage rows")
	h.eq(legacy_loaded.free_slot_count(), Inventory.SIZE - 2, "the storage rows start empty")

	# A payload with more rows than this build has is rejected rather than
	# silently truncated (which could lose items).
	var oversized := legacy_rows.to_dictionary()
	for index in Inventory.SIZE + 2:
		(oversized["hotbar"] as Array).append([BlockDB.DIRT, 1])
	h.check(not Inventory.new().from_dictionary(oversized), "an oversized inventory payload is rejected")

	# Malformed payloads are rejected without touching the live inventory.
	var live := Inventory.new()
	live.add(BlockDB.GRASS, 4)
	var before: Dictionary = live.to_dictionary()
	var bad_cases := [
		{"hotbar": "not an array", "selected": 0},
		{"hotbar": [[BlockDB.GRASS, 1], "garbage"], "selected": 0},
		{"hotbar": [[ItemDB.COUNT + 5, 1]], "selected": 0},
		{"hotbar": [[BlockDB.GRASS, -3]], "selected": 0},
		{"hotbar": [[BlockDB.GRASS, 1]], "durability": "nope"},
	]
	for bad: Dictionary in bad_cases:
		h.check(not live.from_dictionary(bad), "a malformed payload is rejected: %s" % str(bad))
		h.eq(live.to_dictionary(), before, "a rejected payload leaves the inventory untouched")

	# A tool with an impossible saved durability is repaired into range.
	var repaired := Inventory.new()
	h.check(repaired.from_dictionary({
		"hotbar": [[ItemDB.WOOD_PICKAXE, 1]], "durability": [9999], "selected": 0,
	}), "a payload with an out-of-range durability loads")
	h.eq(repaired.durability_of(0), ItemDB.max_durability(ItemDB.WOOD_PICKAXE),
		"an impossible durability was clamped to full")
	h.check(repaired.from_dictionary({
		"hotbar": [[ItemDB.WOOD_PICKAXE, 1]], "durability": [0], "selected": 0,
	}), "a zero-durability payload loads")
	h.eq(repaired.durability_of(0), 1, "a zero durability is repaired to a usable one")


func run(h: TestHarness) -> void:
	_test_item_namespace(h)
	_test_item_icons_resolve(h)
	_test_tools(h)
	_test_break_times(h)
	_test_drop_requirements(h)
	_test_item_drops(h)
	_test_bonus_drops(h)
	_test_food(h)
	_test_stack_cap(h)
	_test_full_inventory(h)
	_test_starter_kit_leaves_storage(h)
	_test_durability(h)
	_test_serialisation(h)
	_test_slot_moves(h)
	h.finish()


### Slot moves (the inventory interface's drag & drop model) -----------------

func _test_slot_moves(h: TestHarness) -> void:
	# Swapping two occupied slots exchanges item, count and durability.
	var inventory := Inventory.new()
	inventory.add(BlockDB.STONE, 5)
	inventory.add(ItemDB.WOOD_PICKAXE, 1, 17)
	h.check(inventory.swap_slots(0, 1), "swapping two occupied slots reports a change")
	h.eq(inventory.slots[0], ItemDB.WOOD_PICKAXE, "the tool moved to the first slot")
	h.eq(inventory.counts[0], 1, "the tool kept its count")
	h.eq(inventory.durability_of(0), 17, "the tool kept its durability")
	h.eq(inventory.slots[1], BlockDB.STONE, "the block moved to the second slot")
	h.eq(inventory.counts[1], 5, "the block kept its count")
	h.check(not inventory.swap_slots(0, 0), "swapping a slot with itself does nothing")
	h.check(not inventory.swap_slots(-1, 0), "an out-of-range swap does nothing")

	# Moving onto an empty slot is a plain move.
	var moved := inventory.move_slot(0, 5)
	h.check(moved, "moving a stack into an empty slot reports a change")
	h.eq(inventory.slots[5], ItemDB.WOOD_PICKAXE, "the tool arrived in the empty slot")
	h.check(inventory.is_empty(0), "the source slot is now empty")
	h.eq(inventory.durability_of(5), 17, "the moved tool kept its durability")

	# Moving onto a matching stack merges what fits and leaves the rest behind.
	var merge := Inventory.new()
	merge.add(BlockDB.STONE, 60)
	merge.add(BlockDB.STONE, 10)
	h.check(merge.move_slot(0, 1), "moving onto a matching stack reports a change")
	h.eq(merge.slots[0], BlockDB.STONE, "the partial stack stays in its slot")
	h.eq(merge.counts[0], 6, "only the overflow beyond the stack cap stayed behind")
	h.eq(merge.counts[1], 64, "the target stack was topped up to the cap")
	h.eq(merge.count_of(BlockDB.STONE), 70, "the merge conserved the items")

	# Moving a different item onto an occupied slot swaps instead.
	var swap := Inventory.new()
	swap.add(BlockDB.DIRT, 3)
	swap.add(BlockDB.SAND, 7)
	h.check(swap.move_slot(0, 1), "moving onto a different item reports a change")
	h.eq(swap.slots[0], BlockDB.SAND, "the two stacks swapped")
	h.eq(swap.slots[1], BlockDB.DIRT, "both stacks survived the swap")

	# Tools never merge with each other.
	var tools := Inventory.new()
	tools.add(ItemDB.STONE_AXE, 1, 30)
	tools.add(ItemDB.STONE_AXE, 1, 90)
	h.check(tools.move_slot(0, 1), "moving a tool onto another tool reports a change")
	h.eq(tools.durability_of(0), 90, "the tools swapped instead of merging")
	h.eq(tools.durability_of(1), 30, "both tools kept their own durability")

	# take_stack / put_stack round-trip, with the leftover reported.
	var carried := tools.take_stack(0)
	h.eq(int(carried.get("item", -1)), ItemDB.STONE_AXE, "take_stack returns the item")
	h.eq(int(carried.get("count", 0)), 1, "take_stack returns the count")
	h.eq(int(carried.get("durability", -1)), 90, "take_stack returns the durability")
	h.check(tools.is_empty(0), "take_stack empties the slot")
	h.check(tools.take_stack(0).is_empty(), "taking from an empty slot returns nothing")
	h.check(tools.take_stack(99).is_empty(), "taking from a bad index returns nothing")

	var leftover: Dictionary = tools.put_stack(4, {"item": BlockDB.COBBLESTONE, "count": 8, "durability": 0})
	h.check(leftover.is_empty(), "putting a stack into an empty slot leaves no leftover")
	h.eq(tools.counts[4], 8, "the stack landed in the slot")
	h.eq(tools.slots[4], BlockDB.COBBLESTONE, "the right item landed in the slot")

	var big: Dictionary = tools.put_stack(5, {"item": BlockDB.COBBLESTONE, "count": 70, "durability": 0})
	h.eq(int(big.get("count", -1)), 6, "putting more than the cap returns the overflow")
	h.eq(tools.counts[5], 64, "the slot filled to the cap")

	# A different item displaces the target stack, which comes back to the caller.
	var displaced: Dictionary = tools.put_stack(5, {"item": BlockDB.GRAVEL, "count": 3, "durability": 0})
	h.eq(int(displaced.get("item", -1)), BlockDB.COBBLESTONE, "the displaced stack is handed back")
	h.eq(int(displaced.get("count", -1)), 64, "the displaced stack kept its count")
	h.eq(tools.slots[5], BlockDB.GRAVEL, "the new stack took the slot")
	h.eq(tools.counts[5], 3, "the new stack kept its count")

	# A full matching stack returns the whole carried stack (nowhere to put it).
	h.eq(tools.put_stack(5, {"item": BlockDB.GRAVEL, "count": 64, "durability": 0}).get("count", -1), 3,
		"topping the gravel stack up to its cap returns the surplus of the second put")
	h.eq(tools.counts[5], 64, "the gravel stack is now full")
	var onto_full := tools.put_stack(5, {"item": BlockDB.GRAVEL, "count": 2, "durability": 0})
	h.eq(int(onto_full.get("count", -1)), 2, "a full matching stack returns the whole stack")
	h.eq(int(onto_full.get("item", -1)), BlockDB.GRAVEL, "the returned stack is the same item")
	h.eq(tools.counts[5], 64, "the target stack was not touched")

	h.eq(int(tools.put_stack(99, {"item": BlockDB.SAND, "count": 1, "durability": 0}).get("count", -1)), 1,
		"putting into a bad index returns the whole stack")
	h.eq(tools.take_stack(4).size(), 3, "take_stack returns a complete stack dictionary")
