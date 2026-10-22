extends RefCounted

## Shared M17 fixture contract.
##
## The new engine must keep honouring the shared scenario and fixture: same seed,
## same palette, same 16-cubed chunk order and the same per-chunk SHA-256.  This
## module loads the real files from `prototypes/m17/shared`.


func name() -> String:
	return "shared M17 fixture contract"


func _shared_path(relative: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(relative).simplify_path()


func run(h: TestHarness) -> void:
	var scenario_file := FileAccess.open(_shared_path("../prototypes/m17/shared/scenario.json"), FileAccess.READ)
	if not h.check(scenario_file != null, "the shared scenario is readable"):
		return
	var scenario: Dictionary = JSON.parse_string(scenario_file.get_as_text())
	h.eq(int(scenario["schema_version"]), 1, "scenario schema version")
	h.eq(int(scenario["seed"]), 17017, "scenario seed is 17017")
	h.eq(int((scenario["chunk_size"] as Array)[0]), 16, "scenario chunk size is 16")

	var palette: Dictionary = scenario["block_palette"]
	h.eq(int(palette["AIR"]), BlockDB.AIR, "palette AIR matches the block database")
	h.eq(int(palette["GRASS"]), BlockDB.GRASS, "palette GRASS matches the block database")
	h.eq(int(palette["DIRT"]), BlockDB.DIRT, "palette DIRT matches the block database")
	h.eq(int(palette["STONE"]), BlockDB.STONE, "palette STONE matches the block database")
	h.eq(int(palette["WATER"]), BlockDB.WATER, "palette WATER matches the block database")

	var fixture_file := FileAccess.open(_shared_path("../prototypes/m17/shared/fixture/world.json"), FileAccess.READ)
	if not h.check(fixture_file != null, "the shared fixture is readable (run python prototypes/m17/shared/generate_fixture.py)"):
		return
	var fixture: Dictionary = JSON.parse_string(fixture_file.get_as_text())
	h.eq(int(fixture["seed"]), int(scenario["seed"]), "fixture seed matches the scenario")
	h.eq(int(fixture["chunk_size"]), 16, "fixture chunk size is 16")

	var world := VoxelWorld.new(int(scenario["seed"]))
	var palette_seen := {}
	var expected_coords: Array[Vector3i] = []
	for entry: Array in scenario["chunk_coords"]:
		expected_coords.append(Vector3i(int(entry[0]), 0, int(entry[2])))
	h.eq((fixture["chunks"] as Array).size(), expected_coords.size(), "fixture has one chunk per scenario coordinate")

	for chunk_entry: Dictionary in fixture["chunks"]:
		var coordinate: Array = chunk_entry["coord"]
		var coord := Vector3i(int(coordinate[0]), int(coordinate[1]), int(coordinate[2]))
		var cells: String = chunk_entry["cells"]
		h.eq(cells.length(), 4096, "fixture chunk %s stores 4096 cells" % coord)
		var ascii := cells.to_ascii_buffer()
		h.eq(ascii.size(), 4096, "fixture chunk %s uses ASCII palette ids" % coord)
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(ascii)
		h.eq(context.finish().hex_encode(), str(chunk_entry["sha256"]), "fixture chunk %s matches its SHA-256" % coord)

		var chunk := ChunkData.new(coord)
		for index in ascii.size():
			var block_id: int = ascii[index] - 48
			chunk.blocks[index] = block_id
			palette_seen[block_id] = true
		world.adopt_chunk(chunk)

	h.eq(world.chunks.size(), expected_coords.size(), "the world adopts every fixture chunk")
	for block_id in [BlockDB.AIR, BlockDB.GRASS, BlockDB.DIRT, BlockDB.STONE, BlockDB.WATER]:
		h.check(palette_seen.has(block_id), "fixture uses palette id %d" % block_id)

	# Negative-coordinate reads come from the fixture, not from the generator.
	h.check(world.get_block(Vector3i(-1, 7, 0)) != BlockDB.AIR, "reads fixture data at x=-1")
	h.check(world.get_block(Vector3i(-16, 7, 0)) != BlockDB.AIR, "reads fixture data at x=-16 (chunk -1)")
	h.eq(world.get_block(Vector3i(-97, 7, 0)), BlockDB.AIR, "x=-97 is outside the fixture")

	# Fixture loading must not consult the procedural generator at all.
	h.eq(world.stats["generated_chunks"], 0, "loading the fixture generates no procedural chunks")

	# The generated world of the same seed must differ (it is a different design),
	# but it must still be deterministic and valid to mesh alongside.
	var generated := VoxelWorld.new(int(scenario["seed"]))
	generated.ensure_chunk(Vector3i(0, 3, 0))
	h.eq(generated.stats["generated_chunks"], 1, "the procedural generator produces a chunk for the same seed")

	var library := TextureLibrary.new()
	library.load_all()
	var mesher := ChunkMesher.new(library)
	var meshed := 0
	for coord: Vector3i in world.chunks:
		if mesher.build(world.get_chunk(coord), world)["mesh"] != null:
			meshed += 1
	h.eq(meshed, expected_coords.size(), "every fixture chunk produces a rendered mesh")

	h.finish()
