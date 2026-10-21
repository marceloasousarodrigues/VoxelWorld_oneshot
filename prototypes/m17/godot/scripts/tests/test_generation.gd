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
	world_a.ensure_chunk(Vector3i(-1, 3, -1))
	var negative_ordered := (world_a.get_chunk(Vector3i(-1, 3, -1)) as ChunkData).blocks.duplicate()
	world_b.ensure_chunk(Vector3i(-1, 3, -1))
	var negative_reordered := (world_b.get_chunk(Vector3i(-1, 3, -1)) as ChunkData).blocks.duplicate()
	h.eq(negative_ordered, negative_reordered,
		"negative-coordinate chunks crossing two borders are independent of load order")

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

	# Clay: a thin subsurface band in submerged columns must actually generate.
	# A branch-ordering bug previously shadowed the clay clause, so the band was
	# never reached and clay was unobtainable.
	var clay_cells := 0
	for x in range(-96, 97, 16):
		for z in range(-96, 97, 16):
			var column_height := world.surface_height(x, z)
			if column_height >= WorldGen.SEA_LEVEL:
				continue
			for y in [column_height - 1, column_height - 2]:
				if y <= 0:
					continue
				world.ensure_chunk(VoxelWorld.world_to_chunk(Vector3i(x, y, z)))
				if world.get_block(Vector3i(x, y, z)) == BlockDB.CLAY:
					clay_cells += 1
	h.greater(float(clay_cells), 0.0, "clay generates in underwater columns (%d cells found)" % clay_cells)

	# Trees and decoration near the surface.  A bounded 3x3 chunk block around the
	# origin is loaded explicitly so the scan never reads unloaded chunks as air.
	for chunk_x in range(-1, 2):
		for chunk_z in range(-1, 2):
			for chunk_y in range(3, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	var logs := 0
	var leaves := 0
	var decos := 0
	var flowers := 0
	for chunk_x in range(-1, 2):
		for chunk_z in range(-1, 2):
			for local_z in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var world_x := chunk_x * ChunkData.SIZE + local_x
					var world_z := chunk_z * ChunkData.SIZE + local_z
					var column_top := world.surface_height(world_x, world_z)
					for y in range(maxi(1, column_top - 2), mini(WorldGen.WORLD_HEIGHT - 1, column_top + 18)):
						var block_id := world.get_block(Vector3i(world_x, y, world_z))
						if block_id == BlockDB.OAK_LOG or block_id == BlockDB.PINE_LOG or block_id == BlockDB.BIRCH_LOG:
							logs += 1
						elif block_id == BlockDB.OAK_LEAVES or block_id == BlockDB.PINE_LEAVES \
								or block_id == BlockDB.BIRCH_LEAVES or block_id == BlockDB.BLOSSOM_LEAVES:
							leaves += 1
						elif BlockDB.is_deco(block_id):
							decos += 1
							if BlockDB.is_flower(block_id):
								flowers += 1
	h.greater(float(logs), 0.0, "trees grow in the world")
	h.greater(float(leaves), float(logs), "trees have canopies")
	h.greater(float(decos), 0.0, "vegetation decorations are placed")
	h.greater(float(flowers), 0.0, "wildflowers are placed in grass biomes")

	# A known deterministic fallen trunk crosses the negative-coordinate chunk
	# border at x=-481/-480. Both generation orders must write every segment.
	var fallen_order_a := VoxelWorld.new(17017)
	var fallen_order_b := VoxelWorld.new(17017)
	var fallen_left := Vector3i(-31, 4, -32)
	var fallen_right := Vector3i(-30, 4, -32)
	fallen_order_a.ensure_chunk(fallen_left)
	fallen_order_a.ensure_chunk(fallen_right)
	fallen_order_b.ensure_chunk(fallen_right)
	fallen_order_b.ensure_chunk(fallen_left)
	var fallen_segments := 0
	for offset in 4:
		var world_x := -483 + offset
		var world_z := -500
		var log_position := Vector3i(world_x, fallen_order_a.surface_height(world_x, world_z) + 1, world_z)
		var log_id := fallen_order_a.get_block(log_position)
		if log_id == BlockDB.OAK_LOG or log_id == BlockDB.PINE_LOG or log_id == BlockDB.BIRCH_LOG:
			fallen_segments += 1
	h.eq(fallen_segments, 4, "a fallen trunk is complete across a negative-coordinate chunk seam")
	h.eq((fallen_order_a.get_chunk(fallen_left) as ChunkData).blocks,
		(fallen_order_b.get_chunk(fallen_left) as ChunkData).blocks,
		"fallen-log geometry in the first chunk is independent of load order")
	h.eq((fallen_order_a.get_chunk(fallen_right) as ChunkData).blocks,
		(fallen_order_b.get_chunk(fallen_right) as ChunkData).blocks,
		"fallen-log geometry in the second chunk is independent of load order")

	# Biome variety.
	var seen := {}
	for x in range(-400, 401, 40):
		for z in range(-400, 401, 40):
			seen[world.biome_at(x, z)] = true
	h.greater(float(seen.size()), 3.0, "several biomes exist within a short walk")

	# M30 terrain profile: high ground resolves into deliberate terraces, with
	# isolated ridges above broad hills and gentle surfaces left for building.
	var m30_world := VoxelWorld.new(17017)
	var highland_columns := 0
	var terraced_columns := 0
	var peak_columns := 0
	var scenic_relief_columns := 0
	var level_build_sites := 0
	var river_columns := 0
	var river_probe := Vector2i(1 << 30, 1 << 30)
	var generator: WorldGen = m30_world.generator
	var m32 := generator.terrain_version >= WorldGen.M32_VERSION
	var terrace_size := WorldGen.M32_MOUNTAIN_TERRACE_SIZE if m32 else WorldGen.HIGHLAND_TERRACE_SIZE
	var terrace_floor := WorldGen.M32_MOUNTAIN_FLOOR if m32 else WorldGen.SEA_LEVEL + 8
	for x in range(-320, 321, 4):
		for z in range(-320, 321, 4):
			var height := m30_world.surface_height(x, z)
			if height >= terrace_floor:
				# The tapered river floodplain deliberately keeps one-block
				# steps, so terrace consistency is measured outside that band.
				if generator._river_distance(x, z) >= WorldGen.RIVER_BANK_LIMIT * 1.6:
					highland_columns += 1
					if posmod(height, terrace_size) == 0:
						terraced_columns += 1
			if height >= WorldGen.SEA_LEVEL + 40:
				peak_columns += 1
			if posmod(x, 32) == 0 and posmod(z, 32) == 0 and height >= WorldGen.SEA_LEVEL + 8:
				var local_low := height
				var local_high := height
				for offset_x in [-16, 0, 16]:
					for offset_z in [-16, 0, 16]:
						var neighbor_height := m30_world.surface_height(x + offset_x, z + offset_z)
						local_low = mini(local_low, neighbor_height)
						local_high = maxi(local_high, neighbor_height)
				if local_high - local_low >= 24:
					scenic_relief_columns += 1
			if height > WorldGen.SEA_LEVEL + 4 and generator._column_slope(x, z, height) <= 1:
				level_build_sites += 1
			# Continental values above 0.35 are naturally dry land in the legacy
			# profile, so below-sea columns in that band demonstrate carved rivers.
			if generator._continent.get_noise_2d(x, z) > 0.35 and height < WorldGen.SEA_LEVEL - 1:
				river_columns += 1
				if river_probe.x == 1 << 30:
					river_probe = Vector2i(x, z)
	h.greater(float(highland_columns), 100.0, "the region has substantial elevated terrain")
	h.greater(float(terraced_columns), float(highland_columns) * 0.93,
		"the mountain belt uses consistent %d-block terraces outside tapered river and valley transitions" % terrace_size)
	h.greater(float(peak_columns), 10.0, "the region includes distinct mountain peaks")
	h.greater(float(scenic_relief_columns), 20.0,
		"nearby ridge and valley profiles have strong visible relief")
	h.greater(float(level_build_sites), 10.0, "the world retains naturally level building sites")
	h.greater(float(river_columns), 10.0, "winding river channels cut into otherwise dry land")
	var river_source := Vector3i(river_probe.x, WorldGen.SEA_LEVEL, river_probe.y)
	m30_world.ensure_chunk(VoxelWorld.world_to_chunk(river_source))
	h.eq(m30_world.get_block(river_source), BlockDB.WATER,
		"the river channel at %s fills to the sea-level water surface" % river_probe)
	h.eq(m30_world.get_fluid(river_source), ChunkData.SOURCE_LEVEL,
		"the river at %s remains a deterministic source block" % river_probe)

	# M30 forest patches deliberately alternate open clearings and denser groves.
	var forest_clearings := 0
	var open_forest_columns_with_trees := 0
	var dense_grove_columns := 0
	var dense_grove_trees := 0
	var dense_grove_species := {}
	var clearing_threshold := -0.32 if generator.terrain_version >= WorldGen.M32_VERSION else -0.24
	for x in range(-320, 321, 2):
		for z in range(-320, 321, 2):
			if m30_world.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var patch: float = generator._forest_patches.get_noise_2d(x, z)
			var tree := generator.tree_at(x, z)
			if patch < clearing_threshold:
				forest_clearings += 1
				if int(tree["type"]) != WorldGen.TreeType.NONE:
					open_forest_columns_with_trees += 1
			elif patch > 0.34:
				dense_grove_columns += 1
				if int(tree["type"]) != WorldGen.TreeType.NONE:
					dense_grove_trees += 1
					dense_grove_species[int(tree["type"])] = true
	h.greater(float(forest_clearings), 100.0, "forest regions contain broad clearing patches")
	h.eq(open_forest_columns_with_trees, 0, "clearings remain open and useful for building")
	h.greater(float(dense_grove_columns), 100.0, "forest regions retain dense woodland patches")
	h.greater(float(dense_grove_trees), 10.0, "dense patches still provide harvestable trees")
	h.greater(float(dense_grove_species.size()), 2.0, "dense groves mix broadleaf, blossom, and conifer species")

	# Sea level contract used by the fixture loader.
	h.eq(WorldGen.SEA_LEVEL, 62, "sea level is 62")
	h.eq(WorldGen.WORLD_HEIGHT, 128, "world height is 128")

	h.finish()
