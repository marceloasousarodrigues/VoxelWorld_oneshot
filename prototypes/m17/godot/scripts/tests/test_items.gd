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
	h.eq(ItemDB.BLOCK_COUNT, BlockDB.COUNT, "every block id is an item id")
	h.eq(ItemDB.COUNT, 61, "the item namespace has the expected size")
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
	h.greater(hand_stone, wood_pick_stone, "a pickaxe breaks stone faster than a bare hand")
	h.greater(wood_pick_stone, diamond_pick_stone, "a diamond pickaxe breaks stone faster than a wooden one")
	h.greater(float(ItemDB.break_seconds(BlockDB.DIRT, BlockDB.AIR)),
		float(ItemDB.break_seconds(BlockDB.DIRT, ItemDB.STONE_SHOVEL)), "a shovel digs dirt faster")

	# The wrong tool is not a slowdown (a sword is slightly faster than a hand).
	h.check(ItemDB.break_seconds(BlockDB.STONE, ItemDB.WOOD_AXE) <= hand_stone,
		"using the wrong tool never takes longer than the bare hand")
	h.check(ItemDB.break_seconds(BlockDB.STONE, ItemDB.WOOD_SWORD) < hand_stone,
		"a sword is faster than a bare hand even on stone")
	h.approx(ItemDB.break_seconds(BlockDB.AIR, BlockDB.AIR), float(ItemDB.MIN_BREAK_SECONDS), 0.0001,
		"a block with no hardness still takes the minimum time")
	h.check(ItemDB.break_seconds(BlockDB.DIAMOND_ORE, ItemDB.DIAMOND_PICKAXE) > 0.0,
		"a hard ore has a positive break time with the best tool")


func _test_drop_requirements(h: TestHarness) -> void:
	h.check(not ItemDB.harvestable(BlockDB.STONE, BlockDB.AIR), "stone does not drop to a bare hand")
	h.check(ItemDB.harvestable(BlockDB.STONE, ItemDB.WOOD_PICKAXE), "stone drops to a wooden pickaxe")
	h.check(ItemDB.harvestable(BlockDB.DIRT, BlockDB.AIR), "dirt drops to a bare hand")
	h.check(ItemDB.harvestable(BlockDB.OAK_LOG, BlockDB.AIR), "a log drops to a bare hand")
	h.check(ItemDB.harvestable(BlockDB.CLAY, BlockDB.AIR), "clay drops to a bare hand")
	h.check(not ItemDB.harvestable(BlockDB.IRON_ORE, ItemDB.WOOD_PICKAXE), "iron ore needs better than wood")
	h.check(ItemDB.harvestable(BlockDB.IRON_ORE, ItemDB.STONE_PICKAXE), "iron ore drops to a stone pickaxe")
	h.check(not ItemDB.harvestable(BlockDB.DIAMOND_ORE, ItemDB.STONE_PICKAXE), "diamond needs better than stone")
	h.check(ItemDB.harvestable(BlockDB.DIAMOND_ORE, ItemDB.IRON_PICKAXE), "diamond ore drops to an iron pickaxe")
	h.check(not ItemDB.harvestable(BlockDB.OBSIDIAN, ItemDB.IRON_PICKAXE), "obsidian needs a diamond pickaxe")
	h.check(ItemDB.harvestable(BlockDB.OBSIDIAN, ItemDB.DIAMOND_PICKAXE), "obsidian drops to a diamond pickaxe")
	h.check(not ItemDB.harvestable(BlockDB.STONE, ItemDB.WOOD_AXE), "an axe is not a pickaxe")


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
	var wheat := 0
	for x in range(0, 400, 3):
		for z in range(0, 400, 7):
			if ItemDB.bonus_drop(BlockDB.OAK_LEAVES, x, 70, z) == ItemDB.APPLE:
				apples += 1
			if ItemDB.bonus_drop(BlockDB.TALL_GRASS, x, 70, z) == ItemDB.WHEAT:
				wheat += 1
	h.check(apples > 0, "oak leaves do drop apples sometimes (%d)" % apples)
	h.check(wheat > 0, "tall grass does drop wheat sometimes (%d)" % wheat)
	h.check(wheat > apples, "wheat is the more common of the two bonus drops")
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
	var distinct := [BlockDB.GRASS, BlockDB.DIRT, BlockDB.STONE, BlockDB.SAND,
		BlockDB.COBBLESTONE, BlockDB.GLASS, BlockDB.BRICK, BlockDB.CLAY, BlockDB.PLANKS]
	for block_id: int in distinct:
		inventory.add(block_id, 64)
	h.eq(inventory.used_slots(), Inventory.HOTBAR_SIZE, "the inventory is full")
	h.eq(inventory.free_slot_count(), 0, "no free slot remains")
	h.eq(inventory.add(ItemDB.STICK, 1), 1, "an item with nowhere to go is returned as leftover")
	h.eq(inventory.count_of(ItemDB.STICK), 0, "nothing was added")
	h.eq(inventory.add(BlockDB.STONE, 1), 1, "a full stack rejects the overflow")

	inventory.remove(BlockDB.STONE, 1)
	h.eq(inventory.add(BlockDB.STONE, 1), 0, "the freed room accepts the item again")


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
	_test_durability(h)
	_test_serialisation(h)
	h.finish()
