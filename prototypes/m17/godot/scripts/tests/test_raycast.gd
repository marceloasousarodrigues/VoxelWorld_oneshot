extends RefCounted

## DDA voxel raycast: hits, normals, negative coordinates, liquids, diagonals.


func name() -> String:
	return "voxel raycast"


func _world_with_blocks() -> VoxelWorld:
	var world := VoxelWorld.new(17017)
	for coord in [Vector3i(0, 0, 0), Vector3i(-1, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]:
		var chunk := ChunkData.new(coord)
		chunk.generated = true
		world.adopt_chunk(chunk)
	return world


func run(h: TestHarness) -> void:
	var world := _world_with_blocks()
	world.set_block(Vector3i(4, 4, 4), BlockDB.STONE)

	var hit := VoxelRay.cast(world, Vector3(4.5, 4.5, -2.0), Vector3(0, 0, 1), 10.0)
	h.check(hit["hit"], "a ray along +Z hits the block")
	h.eq(hit["block"], Vector3i(4, 4, 4), "the reported block is the target")
	h.eq(hit["normal"], Vector3i(0, 0, -1), "the reported normal is the entered face")
	# The block's -Z face is at z = 4.0 and the ray starts at z = -2.0.
	h.approx(float(hit["distance"]), 6.0, 0.001, "the reported distance is exact")

	var downward := VoxelRay.cast(world, Vector3(4.5, 20.0, 4.5), Vector3(0, -1, 0), 40.0)
	h.check(downward["hit"], "a downward ray hits the block")
	h.eq(downward["normal"], Vector3i(0, 1, 0), "entering from above reports the +Y face")

	var upward := VoxelRay.cast(world, Vector3(4.5, -6.0, 4.5), Vector3(0, 1, 0), 40.0)
	h.check(upward["hit"], "an upward ray hits the block")
	h.eq(upward["normal"], Vector3i(0, -1, 0), "entering from below reports the -Y face")

	# Out of range and empty space.
	var too_far := VoxelRay.cast(world, Vector3(4.5, 4.5, -40.0), Vector3(0, 0, 1), 10.0)
	h.check(not too_far["hit"], "a ray shorter than the distance misses")
	var empty := VoxelRay.cast(world, Vector3(4.5, 40.0, 4.5), Vector3(1, 0, 0), 30.0)
	h.check(not empty["hit"], "a ray through empty space misses")

	# Negative world coordinates.  The ray must start inside cell x = -3, which is
	# the cell the block occupies (floor(-2.5) == -3).
	world.set_block(Vector3i(-3, 6, -3), BlockDB.PLANKS)
	var negative := VoxelRay.cast(world, Vector3(-2.5, 6.5, 4.0), Vector3(0, 0, -1), 12.0)
	h.check(negative["hit"], "a ray into negative Z hits")
	h.eq(negative["block"], Vector3i(-3, 6, -3), "negative coordinates resolve to the right cell")
	h.eq(negative["normal"], Vector3i(0, 0, 1), "the negative-coordinate normal is correct")

	# Diagonal ray (all three axes stepping).  The origin is chosen so the ray
	# travels through the (8, 8, 8) -> (9, 9, 9) diagonal without crossing the
	# stone block placed at (4, 4, 4) earlier.
	world.set_block(Vector3i(9, 9, 9), BlockDB.OBSIDIAN)
	var diagonal := VoxelRay.cast(world, Vector3(7.5, 7.5, 7.5), Vector3(1, 1, 1), 20.0)
	h.check(diagonal["hit"], "a diagonal ray hits a diagonal block")
	h.eq(diagonal["block"], Vector3i(9, 9, 9), "diagonal traversal reaches the exact cell")

	# Liquids are skipped by default and reported when requested.
	var water := VoxelWorld.new(17017)
	for coord in [Vector3i(0, 4, 0), Vector3i(0, 3, 0)]:
		var chunk := ChunkData.new(coord)
		chunk.generated = true
		water.adopt_chunk(chunk)
	var water_position := Vector3i(2, 70, 2)
	water.set_block(water_position, BlockDB.WATER)
	water.set_block(Vector3i(2, 68, 2), BlockDB.STONE)
	var through_water := VoxelRay.cast(water, Vector3(2.5, 73.0, 2.5), Vector3(0, -1, 0), 20.0)
	h.check(through_water["hit"], "a ray through water still hits the solid block")
	h.eq(through_water["block"], Vector3i(2, 68, 2), "water is skipped unless requested")
	var into_water := VoxelRay.cast(water, Vector3(2.5, 73.0, 2.5), Vector3(0, -1, 0), 20.0, true)
	h.eq(into_water["block"], water_position, "liquids are reported when requested")

	# Unloaded chunks read as air, so rays never hit phantom blocks.
	var unloaded := VoxelRay.cast(world, Vector3(5000.5, 70.0, 5000.5), Vector3(0, -1, 0), 20.0)
	h.check(not unloaded["hit"], "a ray through unloaded chunks misses")

	h.finish()
