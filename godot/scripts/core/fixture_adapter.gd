extends RefCounted

## Converts the shared renderer-evaluation fixture to the native game's logical
## block storage while preserving the common AIR/GRASS/DIRT/STONE/WATER IDs.

const PALETTE := {0: true, 1: true, 2: true, 3: true, 4: true}


static func load_into_world(world: VoxelWorld, scenario: Dictionary, fixture_path: String) -> Dictionary:
	var file := FileAccess.open(fixture_path, FileAccess.READ)
	if file == null:
		push_error("Missing shared M17 fixture: %s" % fixture_path)
		return {}
	var fixture: Variant = JSON.parse_string(file.get_as_text())
	if typeof(fixture) != TYPE_DICTIONARY:
		push_error("Shared M17 fixture is invalid JSON: %s" % fixture_path)
		return {}
	if int(fixture.get("seed", -1)) != int(scenario.get("seed", -2)) or int(fixture.get("chunk_size", -1)) != ChunkData.SIZE:
		push_error("Shared M17 fixture does not match the requested scenario")
		return {}

	var expected_chunks: Dictionary = {}
	for coordinate: Array in scenario.get("chunk_coords", []):
		expected_chunks[Vector3i(int(coordinate[0]), 0, int(coordinate[2]))] = true
	var fixture_chunks: Dictionary = {}
	var fixture_hashes: Dictionary = {}
	var palette_presence := {0: false, 1: false, 2: false, 3: false, 4: false}
	var hash_checks: int = 0
	for data: Dictionary in fixture.get("chunks", []):
		var coordinates: Array = data.get("coord", [])
		if coordinates.size() != 3:
			push_error("Fixture chunk has an invalid logical coordinate")
			return {}
		var coord := Vector3i(int(coordinates[0]), int(coordinates[1]), int(coordinates[2]))
		if not expected_chunks.has(coord) or fixture_chunks.has(coord):
			push_error("Fixture chunk is unexpected or duplicated: %s" % coord)
			return {}
		var cells: String = str(data.get("cells", ""))
		var ascii := cells.to_ascii_buffer()
		if ascii.size() != ChunkData.CELLS:
			push_error("Fixture chunk %s must have 4096 palette IDs" % coord)
			return {}
		var hash_context := HashingContext.new()
		if hash_context.start(HashingContext.HASH_SHA256) != OK or hash_context.update(ascii) != OK:
			push_error("Could not validate fixture hash at %s" % coord)
			return {}
		var checksum := hash_context.finish().hex_encode()
		if checksum != str(data.get("sha256", "")):
			push_error("Fixture checksum mismatch at %s" % coord)
			return {}
		hash_checks += 1
		var block_ids := PackedByteArray()
		var fluid_levels := PackedByteArray()
		var fluid_sources := PackedByteArray()
		block_ids.resize(ascii.size())
		fluid_levels.resize(ascii.size())
		fluid_sources.resize(ascii.size())
		for index: int in range(ascii.size()):
			var block_id: int = ascii[index] - 48
			if not PALETTE.has(block_id):
				push_error("Fixture includes a block outside the shared palette at %s" % coord)
				return {}
			block_ids[index] = block_id
			if block_id == BlockDB.WATER:
				fluid_levels[index] = ChunkData.SOURCE_LEVEL
				fluid_sources[index] = 1
			palette_presence[block_id] = true
		fixture_chunks[coord] = {"blocks": block_ids, "fluid": fluid_levels, "sources": fluid_sources}
		fixture_hashes[coord] = checksum

	if fixture_chunks.size() != expected_chunks.size():
		push_error("Fixture is missing one or more scenario chunks")
		return {}
	for palette_id: int in PALETTE:
		if not palette_presence[palette_id]:
			push_error("Fixture omits shared palette ID %d" % palette_id)
			return {}
	for coord: Vector3i in expected_chunks:
		var chunk := ChunkData.new(coord)
		var chunk_data: Dictionary = fixture_chunks[coord]
		chunk.blocks = chunk_data["blocks"]
		chunk.fluid = chunk_data["fluid"]
		chunk.sources = chunk_data["sources"]
		chunk.generated = true
		world.adopt_chunk(chunk)
	return {"hashes": fixture_hashes, "count": fixture_chunks.size(), "hash_checks": hash_checks}
