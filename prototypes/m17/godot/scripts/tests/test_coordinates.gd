extends RefCounted

## Coordinate conversion, chunk indexing and boundary semantics.


func name() -> String:
	return "coordinates"


func run(h: TestHarness) -> void:
	h.eq(VoxelWorld.world_to_chunk(Vector3i(0, 0, 0)), Vector3i(0, 0, 0), "origin maps to chunk 0,0,0")
	h.eq(VoxelWorld.world_to_chunk(Vector3i(15, 15, 15)), Vector3i(0, 0, 0), "15 stays in chunk 0")
	h.eq(VoxelWorld.world_to_chunk(Vector3i(16, 0, 0)), Vector3i(1, 0, 0), "16 starts chunk 1")
	h.eq(VoxelWorld.world_to_chunk(Vector3i(-1, 0, 0)), Vector3i(-1, 0, 0), "-1 belongs to chunk -1 (floor semantics)")
	h.eq(VoxelWorld.world_to_chunk(Vector3i(-16, 0, 0)), Vector3i(-1, 0, 0), "-16 belongs to chunk -1")
	h.eq(VoxelWorld.world_to_chunk(Vector3i(-17, 0, 0)), Vector3i(-2, 0, 0), "-17 belongs to chunk -2")

	h.eq(VoxelWorld.world_to_local(Vector3i(-1, 0, 0)), Vector3i(15, 0, 0), "-1 is local x 15")
	h.eq(VoxelWorld.world_to_local(Vector3i(-16, 5, -17)), Vector3i(0, 5, 15), "negative locals use positive modulo")
	h.eq(VoxelWorld.world_to_local(Vector3i(31, 0, 0)), Vector3i(15, 0, 0), "31 is local x 15")

	h.eq(VoxelWorld.chunk_origin(Vector3i(-2, 1, 3)), Vector3i(-32, 16, 48), "chunk origin multiplies by 16")

	h.eq(ChunkData.cell_index(0, 0, 0), 0, "cell index origin is 0")
	h.eq(ChunkData.cell_index(1, 0, 0), 1, "cell index x advances by 1")
	h.eq(ChunkData.cell_index(0, 0, 1), 16, "cell index z advances by 16")
	h.eq(ChunkData.cell_index(0, 1, 0), 256, "cell index y advances by 256")
	h.eq(ChunkData.cell_index(15, 15, 15), 4095, "highest cell index is 4095")
	h.eq(ChunkData.index_to_local(4095), Vector3i(15, 15, 15), "index to local round-trips")
	h.eq(ChunkData.index_to_local(ChunkData.cell_index(3, 7, 11)), Vector3i(3, 7, 11), "index to local matches cell index")
	h.eq(ChunkData.column_index(15, 15), 255, "column index spans 256 columns")

	h.check(VoxelWorld.in_world_vertical(0), "y=0 is inside the world")
	h.check(VoxelWorld.in_world_vertical(WorldGen.WORLD_HEIGHT - 1), "top voxel is inside the world")
	h.check(not VoxelWorld.in_world_vertical(-1), "y=-1 is outside the world")
	h.check(not VoxelWorld.in_world_vertical(WorldGen.WORLD_HEIGHT), "y=128 is outside the world")
	h.eq(WorldGen.WORLD_HEIGHT / ChunkData.SIZE, WorldGen.CHUNKS_Y, "vertical chunk count matches world height")

	h.finish()
