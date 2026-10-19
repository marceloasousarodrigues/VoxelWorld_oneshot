extends RefCounted

## Block editing: logical writes, mesh invalidation, boundary neighbours,
## fluid interaction and edit persistence across unload/reload.


func name() -> String:
	return "block editing"


func run(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var chunk := world.ensure_chunk(Vector3i(0, 3, 0))
	var target := Vector3i(8, 60, 8)
	h.check(world.set_block(target, BlockDB.PLANKS), "placing a block reports a change")
	h.eq(world.get_block(target), BlockDB.PLANKS, "the placed block is readable")
	h.check(not world.set_block(target, BlockDB.PLANKS), "placing the same block again is a no-op")
	h.check(world.set_block(target, BlockDB.AIR), "breaking a block reports a change")
	h.eq(world.get_block(target), BlockDB.AIR, "the broken block is gone")

	h.check(world.edits.has(target), "edits are recorded for persistence")
	h.check(world.edits_by_chunk.has(Vector3i(0, 3, 0)), "edits are grouped by chunk")

	# Mesh invalidation, including the neighbouring chunk across a border.
	var boundary := Vector3i(0, 60, 8)
	world.set_block(boundary, BlockDB.AIR)
	h.check(chunk.mesh_dirty, "editing marks the chunk mesh dirty")
	var west := world.ensure_chunk(Vector3i(-1, 3, 0))
	west.mesh_dirty = false
	chunk.mesh_dirty = false
	world.set_block(boundary, BlockDB.PLANKS)
	h.check(west.mesh_dirty, "an edit on the -X border dirties the western neighbour")
	h.check(chunk.mesh_dirty, "the edited chunk is dirty too")
	west.mesh_dirty = false
	chunk.mesh_dirty = false
	h.check(world.set_block_state(boundary, BlockDB.STAIR, 5), "a boundary stair orientation is an edit")
	h.eq(world.get_orientation(boundary), 5, "the edited stair orientation is readable")
	h.check(west.mesh_dirty, "rotating a boundary stair dirties the western neighbour")
	h.check(chunk.mesh_dirty, "rotating a stair dirties its own chunk")

	# Editing on a Y border must dirty the chunk above/below.
	var y_border := Vector3i(8, 47, 8)
	var lower := VoxelWorld.world_to_chunk(y_border)
	var lower_chunk := world.ensure_chunk(lower)
	var above: ChunkData = world.ensure_chunk(lower + Vector3i.UP)
	above.mesh_dirty = false
	lower_chunk.mesh_dirty = false
	h.check(world.set_block(y_border, BlockDB.PLANKS), "a block can be placed on the +Y border")
	h.check(lower_chunk.mesh_dirty, "the edited chunk is dirty")
	h.check(above.mesh_dirty, "an edit on the +Y border dirties the chunk above")

	# Editing does not require the neighbours to be loaded.
	var isolated := Vector3i(5000, 60, 5000)
	world.ensure_chunk(VoxelWorld.world_to_chunk(isolated))
	h.check(world.set_block(isolated, BlockDB.OBSIDIAN), "editing far from other chunks works")

	# Boolean (1-bit) storage sanity: the same cell read through chunk data.
	var chunk_coord := VoxelWorld.world_to_chunk(isolated)
	var local := VoxelWorld.world_to_local(isolated)
	h.eq(world.get_chunk(chunk_coord).get_block(local.x, local.y, local.z), BlockDB.OBSIDIAN, "chunk data holds the edited block")

	# Placing water creates a source cell and fluid state.
	var water_target := Vector3i(4, 70, 4)
	world.ensure_chunk(VoxelWorld.world_to_chunk(water_target))
	world.set_block(water_target, BlockDB.WATER)
	h.eq(world.get_block(water_target), BlockDB.WATER, "placing water writes the water block")
	h.eq(world.get_fluid(water_target), ChunkData.SOURCE_LEVEL, "placed water is a full source")
	h.check(world.is_water_source(water_target), "placed water is flagged as a source")

	# Replacing water with a solid block clears its fluid.
	world.set_block(water_target, BlockDB.STONE)
	h.eq(world.get_fluid(water_target), ChunkData.NO_FLUID, "replacing water clears its fluid")
	h.check(not world.is_water_source(water_target), "replacing water clears the source flag")

	# Removing the block under decoration removes the decoration rather than
	# leaving a flower or tuft floating in the air.
	var flower_ground := Vector3i(12, 64, 12)
	world.ensure_chunk(VoxelWorld.world_to_chunk(flower_ground))
	world.set_block(flower_ground, BlockDB.GRASS)
	world.set_block(flower_ground + Vector3i.UP, BlockDB.FLOWER_RED)
	h.eq(world.get_block(flower_ground + Vector3i.UP), BlockDB.FLOWER_RED, "a flower can stand on grass")
	world.set_block(flower_ground, BlockDB.AIR)
	h.eq(world.get_block(flower_ground + Vector3i.UP), BlockDB.AIR,
		"breaking the supporting block clears the flower")

	# Unloading and regenerating a chunk re-applies the saved edits.
	var edited_position := Vector3i(3, 64, 3)
	world.ensure_chunk(VoxelWorld.world_to_chunk(edited_position))
	world.set_block(edited_position, BlockDB.BRICK)
	var edited_stair := edited_position + Vector3i(1, 0, 0)
	world.set_block_state(edited_stair, BlockDB.STAIR, 6)
	var coord := VoxelWorld.world_to_chunk(edited_position)
	world.unload_chunk(coord)
	h.check(not world.has_chunk(coord), "the chunk can be unloaded")
	world.ensure_chunk(coord)
	h.eq(world.get_block(edited_position), BlockDB.BRICK, "the edit survives unload and regeneration")
	h.eq(world.get_block(edited_stair), BlockDB.STAIR, "the stair survives unload and regeneration")
	h.eq(world.get_orientation(edited_stair), 6, "the stair orientation survives unload and regeneration")

	# Fluid overrides survive too.  The cell must live in the edited chunk and be
	# empty in the generated world: trees can occupy any given column, so the
	# topmost air cell of the column is used instead of a fixed height.
	var fluid_position := Vector3i(2, 64, 2)
	var fluid_found := false
	for local_z in range(0, 16):
		for local_x in range(0, 16):
			for y in range(79, 63, -1):
				if world.get_block(Vector3i(local_x, y, local_z)) == BlockDB.AIR:
					fluid_position = Vector3i(local_x, y, local_z)
					fluid_found = true
					break
			if fluid_found:
				break
		if fluid_found:
			break
	h.check(fluid_found, "the edited chunk has an empty cell for a fluid override")
	h.check(world.set_fluid(fluid_position, 5, false), "a fluid override can be written")
	world.unload_chunk(coord)
	world.ensure_chunk(coord)
	h.eq(world.get_fluid(fluid_position), 5, "a fluid override survives unload and regeneration")
	h.eq(world.get_block(fluid_position), BlockDB.WATER, "fluid overrides recreate the water block")

	# Pristine ocean water is not stored as an override (saves stay small).
	var ocean_x := 0
	var ocean_z := 0
	for x in range(-128, 129):
		for z in range(-128, 129, 7):
			if world.get_block(Vector3i(x, WorldGen.SEA_LEVEL, z)) == BlockDB.WATER:
				ocean_x = x
				ocean_z = z
				break
		if ocean_x != 0 or ocean_z != 0:
			break
	if ocean_x != 0 or ocean_z != 0:
		var ocean_position := Vector3i(ocean_x, WorldGen.SEA_LEVEL, ocean_z)
		world.set_fluid(ocean_position, ChunkData.SOURCE_LEVEL, true)
		h.check(not world.fluid_overrides.has(ocean_position), "unchanged generated water is not persisted as an override")

	h.eq(world.stats["edits"], world.edits.size(), "edit statistics track the record count")

	h.finish()
