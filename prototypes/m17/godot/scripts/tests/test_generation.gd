extends RefCounted

## Deterministic terrain generation: repeatability, layering, biomes, features.


func name() -> String:
	return "world generation"


func _generate_column_block(world_seed: int, chunk_x: int, chunk_z: int, chunk_y: int = 3) -> PackedByteArray:
	var world := VoxelWorld.new(world_seed)
	var chunk := world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	return chunk.blocks.duplicate()


func run(h: TestHarness) -> void:
	var first := _generate_column_block(17017, 0, 0)
	var second := _generate_column_block(17017, 0, 0)
	h.eq(first, second, "the same seed regenerates an identical chunk")

	var other := _generate_column_block(4242, 0, 0)
	var differences := 0
	for index in first.size():
		if first[index] != other[index]:
			differences += 1
	h.greater(float(differences), 200.0, "a different seed produces different terrain")

	# Determinism must not depend on generation order.
	var world_a := VoxelWorld.new(17017)
	world_a.ensure_chunk(Vector3i(0, 3, 0))
	world_a.ensure_chunk(Vector3i(1, 3, 0))
	var ordered := (world_a.get_chunk(Vector3i(1, 3, 0)) as ChunkData).blocks.duplicate()
	var world_b := VoxelWorld.new(17017)
	world_b.ensure_chunk(Vector3i(5, 3, -2))
	world_b.ensure_chunk(Vector3i(1, 3, 0))
	var reordered := (world_b.get_chunk(Vector3i(1, 3, 0)) as ChunkData).blocks.duplicate()
	h.eq(ordered, reordered, "generation is independent of chunk load order")

	# Vertical layering at a column in the middle of the world.
	var world := VoxelWorld.new(17017)
	var surface := world.surface_height(8, 8)
	var ground_chunk := world.ensure_chunk(VoxelWorld.world_to_chunk(Vector3i(8, surface, 8)))
	var surface_block := ground_chunk.get_block(8, posmod(surface, 16), 8)
	h.check(surface_block != BlockDB.AIR, "the surface column is not empty")
	h.check(surface_block == BlockDB.GRASS or surface_block == BlockDB.SAND or surface_block == BlockDB.DRY_GRASS \
		or surface_block == BlockDB.SNOW or surface_block == BlockDB.STONE, "surface uses a real surface material")
	var bedrock_chunk := world.ensure_chunk(Vector3i(0, 0, 0))
	h.eq(bedrock_chunk.get_block(8, 0, 8), BlockDB.BEDROCK, "the bottom layer is bedrock")

	# Deep underground must be stone or ore, never air everywhere.
	var stone_like := 0
	var deep := world.ensure_chunk(Vector3i(0, 2, 0))
	for index in deep.blocks.size():
		var block_id := int(deep.blocks[index])
		if block_id == BlockDB.STONE or block_id == BlockDB.DIRT or block_id == BlockDB.COAL_ORE \
			or block_id == BlockDB.IRON_ORE or block_id == BlockDB.GOLD_ORE or block_id == BlockDB.DIAMOND_ORE \
			or block_id == BlockDB.GRAVEL or block_id == BlockDB.WATER:
			stone_like += 1
	h.greater(float(stone_like), 2000.0, "y 32..47 is mostly solid rock")

	# Caves: a deep vertical scan must contain some carved air.
	var carved := 0
	for y in range(6, 40):
		if world.get_block(Vector3i(8, y, 8)) == BlockDB.AIR:
			carved += 1
	h.greater(float(carved), 0.0, "underground carving produces caves")

	# Ocean or lake water exists somewhere in a wide scan.  `get_block` only sees
	# loaded chunks, so every column the generator reports as below sea level gets
	# its chunk loaded before the cell is queried.
	var water_cells := 0
	var underwater_columns := 0
	for x in range(-96, 97, 16):
		for z in range(-96, 97, 16):
			if world.surface_height(x, z) >= WorldGen.SEA_LEVEL:
				continue
			underwater_columns += 1
			world.ensure_chunk(VoxelWorld.world_to_chunk(Vector3i(x, WorldGen.SEA_LEVEL, z)))
			if world.get_block(Vector3i(x, WorldGen.SEA_LEVEL, z)) == BlockDB.WATER:
				water_cells += 1
	h.greater(float(water_cells), 5.0, "the world contains standing water")
	h.eq(water_cells, underwater_columns, "every submerged column is filled with water")
	h.eq(world.get_fluid(Vector3i(0, 0, 0)), 0, "solid rock carries no fluid")
	h.eq(world.surface_height(0, 0), world.surface_height(0, 0), "surface height is stable")

	# Trees and decoration near the surface.  A bounded 3x3 chunk block around the
	# origin is loaded explicitly so the scan never reads unloaded chunks as air.
	for chunk_x in range(-1, 2):
		for chunk_z in range(-1, 2):
			for chunk_y in range(3, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	var logs := 0
	var leaves := 0
	var decos := 0
	for chunk_x in range(-1, 2):
		for chunk_z in range(-1, 2):
			for local_z in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var world_x := chunk_x * ChunkData.SIZE + local_x
					var world_z := chunk_z * ChunkData.SIZE + local_z
					var column_top := world.surface_height(world_x, world_z)
					for y in range(maxi(1, column_top - 2), mini(WorldGen.WORLD_HEIGHT - 1, column_top + 18)):
						var block_id := world.get_block(Vector3i(world_x, y, world_z))
						if block_id == BlockDB.OAK_LOG or block_id == BlockDB.PINE_LOG:
							logs += 1
						elif block_id == BlockDB.OAK_LEAVES or block_id == BlockDB.PINE_LEAVES:
							leaves += 1
						elif BlockDB.is_deco(block_id):
							decos += 1
	h.greater(float(logs), 0.0, "trees grow in the world")
	h.greater(float(leaves), float(logs), "trees have canopies")
	h.greater(float(decos), 0.0, "vegetation decorations are placed")

	# Biome variety.
	var seen := {}
	for x in range(-400, 401, 40):
		for z in range(-400, 401, 40):
			seen[world.biome_at(x, z)] = true
	h.greater(float(seen.size()), 3.0, "several biomes exist within a short walk")

	# Sea level contract used by the fixture loader.
	h.eq(WorldGen.SEA_LEVEL, 62, "sea level is 62")
	h.eq(WorldGen.WORLD_HEIGHT, 128, "world height is 128")

	h.finish()
