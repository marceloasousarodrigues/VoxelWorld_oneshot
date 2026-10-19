extends RefCounted

## M24 build economy: prove that the construction materials are actually
## obtainable.
##
## Two independent checks:
##   1. Every core raw material has a *world source* in normal deterministic
##      generation (wood, soil, stone, sand, clay, gravel, coal, iron).  This is
##      what caught gravel, which the recipe list wanted but the generator never
##      produced.
##   2. A fresh player can follow the real progression from an empty inventory:
##      hand-harvest wood, make planks/sticks/table, craft a wooden pickaxe,
##      mine stone, build a furnace, mine coal, upgrade to a stone pickaxe, mine
##      iron, smelt ingots, then craft the whole build kit.  Every mining action
##      goes through `ItemDB.harvestable` (the same gate the player uses) and
##      every craft goes through `Crafting.craft` at a station found in the real
##      voxel world with `Crafting.best_station`.
##
## The route uses a prepared field of source blocks (the blocks themselves, not
## crafted items) so it is fast and deterministic; the presence check below
## proves those source blocks also occur in generated terrain.


func name() -> String:
	return "building economy"


func run(h: TestHarness) -> void:
	_test_generated_sources(h)
	_test_starter_kit_is_not_a_shortcut(h)
	_test_empty_inventory_route(h)
	h.finish()


# --- 1) real generation contains every raw material -----------------------

func _test_generated_sources(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var generator: WorldGen = world.generator

	# Wood: a natural tree trunk near spawn.
	var log_cell := _find_tree_log(world, generator)
	h.check(log_cell.x != -999, "a natural tree trunk generates near spawn")
	if log_cell.x != -999:
		var log_block := world.get_block(log_cell)
		h.check(log_block == BlockDB.OAK_LOG or log_block == BlockDB.PINE_LOG
			or log_block == BlockDB.BIRCH_LOG, "the tree column generates a real log block")

	# Soil and stone under a normal surface column.
	var column := Vector2i(8, 8)
	var surface := generator.height_at(column.x, column.y)
	var below := Vector3i(column.x, surface - 2, column.y)
	world.ensure_chunk(VoxelWorld.world_to_chunk(below))
	var below_block := world.get_block(below)
	h.check(below_block == BlockDB.DIRT or below_block == BlockDB.STONE,
		"dirt/stone generates under the surface")

	# Sand: a beach, desert or ocean surface column.
	var sand_cell := _find_surface(world, generator,
		[WorldGen.Biome.BEACH, WorldGen.Biome.DESERT, WorldGen.Biome.OCEAN], BlockDB.SAND)
	h.check(sand_cell.x != -999, "a sand surface generates in an appropriate biome")

	# Clay and gravel: the subsurface band of a submerged column.
	var band := _find_underwater_band(world, generator)
	h.check(band.has(BlockDB.CLAY), "clay generates in a submerged subsurface band")
	h.check(band.has(BlockDB.GRAVEL), "gravel generates in a submerged subsurface band")

	# Coal and iron: ore blobs underground.
	var ores := _scan_underground(world, [BlockDB.COAL_ORE, BlockDB.IRON_ORE])
	h.check(ores.has(BlockDB.COAL_ORE), "coal ore generates underground")
	h.check(ores.has(BlockDB.IRON_ORE), "iron ore generates underground")


func _find_tree_log(world: VoxelWorld, generator: WorldGen) -> Vector3i:
	for radius in range(0, 49):
		for step in range(-radius, radius + 1):
			for candidate: Vector2i in [
				Vector2i(8 + step, 8 - radius), Vector2i(8 + step, 8 + radius),
				Vector2i(8 - radius, 8 + step), Vector2i(8 + radius, 8 + step),
			]:
				var tree: Dictionary = generator.tree_at(candidate.x, candidate.y)
				if int(tree.get("type", WorldGen.TreeType.NONE)) == WorldGen.TreeType.NONE:
					continue
				var cell := Vector3i(candidate.x, generator.height_at(candidate.x, candidate.y) + 1, candidate.y)
				world.ensure_chunk(VoxelWorld.world_to_chunk(cell))
				var block_id := world.get_block(cell)
				if block_id == BlockDB.OAK_LOG or block_id == BlockDB.PINE_LOG or block_id == BlockDB.BIRCH_LOG:
					return cell
	return Vector3i(-999, -999, -999)


func _find_surface(world: VoxelWorld, generator: WorldGen, biomes: Array, wanted: int) -> Vector3i:
	for radius in range(0, 81):
		for step in range(-radius, radius + 1):
			for candidate: Vector2i in [
				Vector2i(8 + step, 8 - radius), Vector2i(8 + step, 8 + radius),
				Vector2i(8 - radius, 8 + step), Vector2i(8 + radius, 8 + step),
			]:
				if not biomes.has(generator.biome_at(candidate.x, candidate.y)):
					continue
				var height := generator.height_at(candidate.x, candidate.y)
				var cell := Vector3i(candidate.x, height, candidate.y)
				world.ensure_chunk(VoxelWorld.world_to_chunk(cell))
				if world.get_block(cell) == wanted:
					return cell
	return Vector3i(-999, -999, -999)


func _find_underwater_band(world: VoxelWorld, generator: WorldGen) -> Dictionary:
	var found := {}
	for radius in range(0, 81):
		for step in range(-radius, radius + 1):
			for candidate: Vector2i in [
				Vector2i(8 + step, 8 - radius), Vector2i(8 + step, 8 + radius),
				Vector2i(8 - radius, 8 + step), Vector2i(8 + radius, 8 + step),
			]:
				var height := generator.height_at(candidate.x, candidate.y)
				if height >= WorldGen.SEA_LEVEL:
					continue
				for depth in [1, 2]:
					var cell := Vector3i(candidate.x, height - depth, candidate.y)
					world.ensure_chunk(VoxelWorld.world_to_chunk(cell))
					var block_id := world.get_block(cell)
					if block_id == BlockDB.CLAY or block_id == BlockDB.GRAVEL:
						found[block_id] = true
				if found.has(BlockDB.CLAY) and found.has(BlockDB.GRAVEL):
					return found
	return found


func _scan_underground(world: VoxelWorld, wanted: Array) -> Dictionary:
	var found := {}
	for coord: Vector3i in [Vector3i(0, 2, 0), Vector3i(1, 2, 0), Vector3i(-1, 2, 0),
			Vector3i(0, 2, 1), Vector3i(0, 1, 0)]:
		var chunk := world.ensure_chunk(coord)
		for index in chunk.blocks.size():
			var block_id := int(chunk.blocks[index])
			if wanted.has(block_id):
				found[block_id] = true
		if found.size() == wanted.size():
			break
	return found


# --- 2) the starter kit is a head start, not a progression bypass ---------

func _test_starter_kit_is_not_a_shortcut(h: TestHarness) -> void:
	var inventory := Inventory.new()
	inventory.give_starter_kit()
	h.eq(inventory.used_slots(), Inventory.HOTBAR_SIZE + 1,
		"the starter kit fills the hotbar and one seed slot")
	for tool: int in [ItemDB.WOOD_PICKAXE, ItemDB.STONE_PICKAXE, ItemDB.IRON_PICKAXE]:
		h.eq(inventory.count_of(tool), 0, "the starter kit grants no %s" % ItemDB.name_of(tool))
	h.eq(inventory.count_of(ItemDB.IRON_INGOT), 0, "the starter kit grants no refined ingot")
	h.eq(inventory.count_of(ItemDB.IRON_LUMP), 0, "the starter kit grants no iron ore")
	h.eq(inventory.count_of(BlockDB.FURNACE), 0, "the starter kit grants no furnace")


# --- 3) the empty-inventory construction route ----------------------------

func _test_empty_inventory_route(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var field := _make_source_field(world)
	var inventory := Inventory.new()
	h.eq(inventory.used_slots(), 0, "the route starts from an empty inventory")

	# --- the first minutes: wood by hand ---------------------------------
	h.eq(_mine(world, inventory, field, BlockDB.STONE, 1), 0,
		"a bare hand cannot harvest stone (the tool gate holds from the start)")
	var logs := _mine(world, inventory, field, BlockDB.OAK_LOG, 20)
	h.eq(logs, 20, "the player harvests logs by hand")
	_craft(h, inventory, "planks_oak", Crafting.STATION_HAND, 5, "planks by hand")
	h.check(inventory.count_of(BlockDB.PLANKS) >= 20, "hand crafting yields the first planks")
	_craft(h, inventory, "sticks", Crafting.STATION_HAND, 3, "sticks by hand")
	h.check(inventory.count_of(ItemDB.STICK) >= 12, "hand crafting yields the first sticks")

	# --- the first station ------------------------------------------------
	_craft(h, inventory, "crafting_table", Crafting.STATION_HAND, 1,
		"the first crafting table is hand-made")
	var table_cell := _place_station(world, inventory, BlockDB.CRAFTING_TABLE, Vector3i(12, 8, 2))
	var table_station := Crafting.best_station(world, table_cell, 3)
	h.eq(table_station, Crafting.STATION_TABLE, "the placed table is found by the real station scan")

	# --- tools and the stone/furnace loop ---------------------------------
	_craft(h, inventory, "wood_pickaxe", table_station, 1, "the wooden pickaxe crafts at the table")
	h.check(_select_item(inventory, ItemDB.WOOD_PICKAXE), "the wooden pickaxe can be selected")
	var stone := _mine(world, inventory, field, BlockDB.STONE, 24)
	h.eq(stone, 24, "the wooden pickaxe harvests stone")
	h.eq(inventory.count_of(BlockDB.COBBLESTONE), 24, "stone yields cobblestone")
	_craft(h, inventory, "furnace", table_station, 1, "the furnace crafts at the table")
	var furnace_cell := _place_station(world, inventory, BlockDB.FURNACE, Vector3i(13, 8, 2))
	var furnace_station := Crafting.best_station(world, furnace_cell, 3)
	h.eq(furnace_station, Crafting.STATION_FURNACE, "the placed furnace becomes the best station")

	h.check(_select_item(inventory, ItemDB.WOOD_PICKAXE), "the wooden pickaxe is still selected")
	h.eq(_mine(world, inventory, field, BlockDB.COAL_ORE, 14), 14, "the wooden pickaxe harvests coal")
	h.check(inventory.count_of(ItemDB.COAL) >= 14, "coal ore drops coal")
	h.eq(_mine(world, inventory, field, BlockDB.IRON_ORE, 1), 0,
		"a wooden pickaxe cannot harvest iron ore")
	_craft(h, inventory, "stone_pickaxe", furnace_station, 1, "the stone pickaxe crafts at the furnace/table")
	h.check(_select_item(inventory, ItemDB.STONE_PICKAXE), "the stone pickaxe can be selected")
	h.eq(_mine(world, inventory, field, BlockDB.IRON_ORE, 6), 6, "the stone pickaxe harvests iron ore")
	h.check(inventory.count_of(ItemDB.IRON_LUMP) >= 6, "iron ore drops iron lumps")

	# --- smelting and refinement ------------------------------------------
	_smelt(h, inventory, "iron_ingot", furnace_station, 6, "six iron lumps smelt into ingots")
	h.eq(inventory.count_of(ItemDB.IRON_INGOT), 6, "the furnace produces iron ingots")
	h.eq(inventory.count_of(ItemDB.IRON_LUMP), 0, "the iron lumps were consumed")

	# --- the rest of the raw palette --------------------------------------
	h.eq(_mine(world, inventory, field, BlockDB.SAND, 10), 10, "the player gathers sand")
	h.eq(_mine(world, inventory, field, BlockDB.CLAY, 6), 6, "the player gathers clay")
	h.eq(_mine(world, inventory, field, BlockDB.GRAVEL, 4), 4, "the player gathers gravel")
	h.eq(_mine(world, inventory, field, BlockDB.DIRT, 4), 4, "the player gathers dirt")

	# --- the build kit -----------------------------------------------------
	var kit := [
		["planks_oak", 8, furnace_station, "planks"],
		["timber_frame", 2, furnace_station, "timber framing"],
		["stair", 2, furnace_station, "roof stairs"],
		["fence", 1, furnace_station, "fence"],
		["door", 1, furnace_station, "door"],
		["stone_brick", 2, furnace_station, "stone brick"],
		["packed_path", 2, furnace_station, "packed path"],
		["barrel", 1, furnace_station, "barrel"],
		["lantern", 1, furnace_station, "lantern"],
	]
	for entry: Array in kit:
		_craft(h, inventory, str(entry[0]), str(entry[2]), int(entry[1]),
			"%s crafts from gathered materials" % str(entry[3]))
	# Glass has both a hand recipe and a furnace smelt; prove both.
	_craft(h, inventory, "glass", furnace_station, 2, "glass crafts from sand")
	_smelt(h, inventory, "glass_from_sand", furnace_station, 2, "sand also smelts into glass")
	# Fired roof tiles are the smelting-only masonry piece.
	_smelt(h, inventory, "roof_tile", furnace_station, 2, "clay fires into roof tiles")

	var expected_outputs := [
		BlockDB.PLANKS, BlockDB.TIMBER_FRAME, BlockDB.STAIR, BlockDB.FENCE,
		BlockDB.DOOR, BlockDB.STONE_BRICK, BlockDB.PATH, BlockDB.BARREL,
		BlockDB.LANTERN, BlockDB.GLASS, BlockDB.ROOF_TILE,
	]
	var missing: Array[String] = []
	for item_id: int in expected_outputs:
		if inventory.count_of(item_id) <= 0:
			missing.append(ItemDB.name_of(item_id))
	h.eq(missing, [], "the route produces every core build material (%s)" % ", ".join(missing))
	h.check(inventory.count_of(BlockDB.ROOF_TILE) >= 6, "the roof tile batch is enough for a roof")
	h.check(inventory.count_of(BlockDB.PLANKS) > 0 and inventory.count_of(ItemDB.STICK) > 0,
		"the route still has wood and sticks for the next building step")


# --- route helpers --------------------------------------------------------

## Places one field of real source blocks in an empty loaded chunk.  Only raw
## blocks are granted; every tool, station and processed item in the route has
## to be earned below.
func _make_source_field(world: VoxelWorld) -> Dictionary:
	var chunk := ChunkData.new(Vector3i.ZERO)
	chunk.generated = true
	world.adopt_chunk(chunk)
	var field := {}
	var sources := [
		[BlockDB.OAK_LOG, 20], [BlockDB.STONE, 32], [BlockDB.COAL_ORE, 16],
		[BlockDB.IRON_ORE, 8], [BlockDB.SAND, 12], [BlockDB.CLAY, 8],
		[BlockDB.GRAVEL, 6], [BlockDB.DIRT, 8],
	]
	for row in sources.size():
		var block_id: int = int(sources[row][0])
		var count: int = int(sources[row][1])
		var cells: Array[Vector3i] = []
		for index in count:
			var cell := Vector3i(1 + index % 10, 4 + int(index / 10), 2 + row)
			world.set_block(cell, block_id)
			cells.append(cell)
		field[block_id] = cells
	return field


## Harvests up to `wanted` blocks with the real tool gate and drop rules.  A
## refused block is not removed and yields nothing, exactly like the player's
## `break_target`.
func _mine(world: VoxelWorld, inventory: Inventory, field: Dictionary, block_id: int,
		wanted: int) -> int:
	var cells: Array = field.get(block_id, [])
	var gained := 0
	while gained < wanted and not cells.is_empty():
		var held := inventory.selected_item()
		if not ItemDB.harvestable(block_id, held):
			break
		var cell: Vector3i = cells.pop_back()
		if world.get_block(cell) != block_id:
			continue
		world.set_block(cell, BlockDB.AIR)
		var drop := ItemDB.drop_for_block(block_id)
		if drop == BlockDB.NO_DROP:
			drop = ItemDB.bonus_drop(block_id, cell.x, cell.y, cell.z)
		if drop == BlockDB.NO_DROP:
			continue
		inventory.add(drop, 1)
		if ItemDB.is_tool_item(held):
			inventory.wear(inventory.selected, 1)
		gained += 1
	return gained


func _select_item(inventory: Inventory, item_id: int) -> bool:
	for index in Inventory.HOTBAR_SIZE:
		if inventory.slots[index] == item_id and inventory.counts[index] > 0:
			if index == inventory.selected:
				return true
			return inventory.select(index)
	return false


func _craft(h: TestHarness, inventory: Inventory, recipe_id: String, station: String,
		count: int, description: String) -> bool:
	var result: Dictionary = Crafting.craft_many(inventory, Crafting.recipe(recipe_id), count, station)
	if not bool(result["ok"]):
		h.check(false, "%s (%s)" % [description, str(result["reason"])])
		return false
	h.check(true, description)
	return true


func _smelt(h: TestHarness, inventory: Inventory, recipe_id: String, station: String,
		count: int, description: String) -> bool:
	return _craft(h, inventory, recipe_id, station, count, description)


func _place_station(world: VoxelWorld, inventory: Inventory, block_id: int, cell: Vector3i) -> Vector3i:
	inventory.remove(block_id, 1)
	world.set_block(cell, BlockDB.AIR)
	world.set_block(cell, block_id)
	return cell
